"""Purpose: copy the PeTTa runtime into wheels built from pyproject.toml, and
  offer the wire codec as a compiled extension when a builder asks for one.
Assumes:
  - PYMETTA_USE_MYPYC is unset for the wheel that ships, so the default build
    stays pure Python and platform-independent [tested
    test_the_codec_builds_under_mypyc_as_an_option]
Guarantees:
  - the default build is byte-identical to the one before compilation was
    offered: mypycify is not imported, mypy is not required, and ext_modules
    is empty [tested test_the_codec_builds_under_mypyc_as_an_option]
  - PYMETTA_USE_MYPYC=1 without mypy installed stops the build naming the fix,
    rather than quietly producing the pure-Python wheel the builder did not
    ask for [tested test_the_codec_builds_under_mypyc_as_an_option]
Owns:
  - build_py_with_runtime writes only beneath setuptools' build directory;
    the wheel gate builds and boots that copy outside the checkout
    [source .github/workflows/checks.yml:116]
Decides:
  - which modules compile, and which are excluded with their reason.
    Compiling a module turns its classes native, which is a behaviour
    change, so the list is a contract rather than a convenience
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

import os
import shutil
from pathlib import Path

from setuptools import setup
from setuptools.command.build_py import build_py

HERE = Path(__file__).resolve().parent

# The wire codec, and nothing else: _atom_wire decodes and atoms is the
# public surface over it. Every atom crossing the boundary passes through
# both. Measured 2026-08-19, minimum of three instructions:u runs of the
# wire-codec lane, 3457054691 interpreted against 2984812403 compiled, 1.16x.
MYPYC_MODULES = ("bindings/python/metta/_atom_wire.py", "bindings/python/metta/atoms.py")

# _atoms_core.py is NOT in that list, and the reason is behaviour rather than
# taste. An exclusion list with its reasons is mypy's own shape for this
# [source: MYPYC_BLACKLIST in https://github.com/python/mypy/blob/master/setup.py].
#
# The prize for adding it is real: measured 2026-08-19 with the whole codec
# compiled, the wire-codec lane runs 1547302231 against 3377380576, 2.18x,
# and term-operators 2.01x. What that build gets wrong, each observed by
# running the suite against it rather than predicted:
#
#   - Gnd stops answering __index__, so range(Gnd(3)) raises TypeError.
#     mypyc native classes do not fill that slot and there is no annotation
#     that makes them; this alone disqualifies the build, because the
#     casting protocol is documented and tested and would fail silently.
#   - dict-form __slots__ documentation is dropped, so help() no longer
#     describes an attribute [tested test_slot_docstrings_reach_help].
#   - Box cannot hold __weakref__, so the box intern table cannot be built.
#     The workaround is @mypyc_attr(native_class=False), which needs
#     mypy_extensions imported at RUN time, and a runtime dependency added
#     for an opt-in build is exactly what this item forbids. A try/except
#     import does not help: mypy knows the module is installed, marks the
#     handler unreachable, and mypyc compiles it to a raise.
#   - functools.singledispatch compiles to an object with register and
#     registry but no dispatch, which encode's fast table is built from.
#     Spelling it singledispatch(fn) rather than @singledispatch keeps the
#     real functools object, so this one is fixable.
#   - a compiled function has no __dict__, so encode.register cannot be
#     attached to it and the extension point disappears.
#   - getattr(self, "_wire", None) on an unset slot raises rather than
#     answering the default, so Sym and Var lose their lazy wire cell.
#     try/except AttributeError is the spelling that works in both, and it
#     is 2.30% FASTER interpreted as well (wire-codec 3457054691 to
#     3377380576), so it is worth taking on its own terms.
#
# __match_args__ is fixable and worth recording: bare assignment becomes a
# getset descriptor and breaks `case [head, *args]`, while annotating it
# ClassVar or Final keeps the tuple.

# --explicit-package-bases with MYPYPATH=bindings/python, the seat that
# holds metta, so mypy names each module metta.* and the compiled
# extension never shadows the real one.
# --no-warn-unused-configs, because the shared [tool.mypy] overrides here
# describe the whole package and mypy exits nonzero over the ones a
# three-file build does not reach.
MYPYC_FLAGS = ("--explicit-package-bases", "--no-warn-unused-configs")


def compiled_modules():
    """The codec as C extensions when asked for, and nothing otherwise.

    Opt-in rather than default. A compiled wheel is platform-specific where
    the shipped one is py3-none-any, and compiling turns these classes into
    native ones, which is a real behaviour change for anything that reaches
    them reflectively. The variable, the explicit module list and the
    all-or-nothing failure follow mypy's own setup.py
    [source: https://github.com/python/mypy/blob/master/setup.py].
    """
    if os.environ.get("PYMETTA_USE_MYPYC") != "1":
        return []
    try:
        from mypyc.build import mypycify
    except ImportError:
        raise SystemExit(
            "PYMETTA_USE_MYPYC=1 asks for a compiled codec and mypy is not "
            "installed. Install it (pip install mypy) and build again, or "
            "unset PYMETTA_USE_MYPYC to build the pure-Python wheel."
        ) from None
    os.environ["MYPYPATH"] = str(HERE / "bindings" / "python")
    return mypycify([*MYPYC_FLAGS, *MYPYC_MODULES])

# Runtime resources living outside the package that must ship inside the wheel,
# mapped to their destination under metta/_runtime/ (preserving the engine/ and
# lib/ sibling layout that metta.pl relies on for library_path).
#
# backends/ ships even though every backend in it needs a compiled artefact no
# py3-none-any wheel can carry, because the engine GLOBS that directory on
# every boot and EXTENDING.md tells an extension author "a backend is a file in
# backends/". Without it the glob matches nothing, so the seam is simply absent
# from an installed PeTTa and says so to nobody: expand_file_name/2 on a
# missing directory answers [] exactly as it does for a directory holding no
# built backend. The files themselves are a dozen lines of Prolog that test for
# their own artefact and load nothing when it is missing, which is the
# behaviour a wheel wants anyway.
#
# tests/codec/ ships for a different reason: it is the codec's golden corpus,
# the data metta.testing.check_codec reads, and a third party certifying their
# own codec installs this package rather than cloning the repository. It is
# language-neutral JSON, so a binding in another language reads the same file
# out of an installed tree.
RUNTIME_RESOURCES = {
    "engine": "engine",
    "lib": "lib",
    "backends/mork/decider.pl": "backends/mork/decider.pl",
    "tests/codec": "tests/codec",
    "bindings/python/decider.pl": "bindings/python/decider.pl",
    "bindings/python/bridge.pl": "bindings/python/bridge.pl",
    "bindings/python/metta_py.py": "bindings/python/metta_py.py",
    "bindings/python/helper.pl": "bindings/python/helper.pl",
    "bindings/python/metta/shim.pl": "bindings/python/metta/shim.pl",
}


class build_py_with_runtime(build_py):
    """Build Python modules, then copy the runtime tree beside them."""

    def run(self):
        # A build_lib directory that is not a package of THIS build is debris
        # from a retired configuration, and build_py only ever adds, so it
        # ships. Measured 2026-08-24: after the petta -> metta rename a stale
        # build/lib/petta rode into the wheel beside metta and the packaged
        # gate's own "retired petta module still imports" assertion caught the
        # contaminated wheel. Same failure class the _runtime clearing below
        # already documents; this is the package-level half.
        build_root = Path(self.build_lib)
        if build_root.exists():
            expected = {name.split(".")[0] for name in (self.packages or [])}
            for entry in build_root.iterdir():
                if entry.is_dir() and entry.name not in expected:
                    shutil.rmtree(entry)
        super().run()
        runtime_root = Path(self.build_lib) / "metta" / "_runtime"
        # Emptied first, because copytree(dirs_exist_ok=True) only ever adds.
        # A resource dropped from RUNTIME_RESOURCES kept shipping out of a
        # stale build/ directory, and so did a source file deleted from engine/,
        # which made tests/test_packaged_cli.sh green against a wheel the
        # current tree does not describe. Measured 2026-08-17: removing
        # backends/ from the map above and rebuilding produced a wheel that
        # still contained it, and the packaged gate passed; with this, the same
        # edit fails the gate naming the missing directory. The whole tree is
        # generated, so there is nothing here to preserve.
        if runtime_root.exists():
            shutil.rmtree(runtime_root)
        for src_rel, dst_rel in RUNTIME_RESOURCES.items():
            src = HERE / src_rel
            dst = runtime_root / dst_rel
            if src.is_dir():
                # Whatever sits in the working tree is copied verbatim, so an
                # ignored __pycache__ would ship interpreter-specific bytecode
                # inside a py3-none-any wheel, including orphans whose source
                # was deleted. The same class covers a dev tree's build
                # artifacts: a shipped .qlf whose mtime beats the shipped
                # source loads INSTEAD of it and ties the install to the
                # builder's SWI version (engine/qlf_boot.pl regenerates them
                # per install), and engine/reader.so is one machine's binary
                # inside a py3-none-any wheel (the engine falls back to the
                # Prolog grammar when it is absent).
                shutil.copytree(
                    src,
                    dst,
                    dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(
                        "__pycache__", "*.py[co]", "*.qlf", ".qlf-stamp",
                        "*.so", "*.o",
                    ),
                )
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)


setup(
    cmdclass={"build_py": build_py_with_runtime},
    ext_modules=compiled_modules(),
)
