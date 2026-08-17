"""Purpose: copy the PeTTa runtime into wheels built from pyproject.toml.
Owns:
  - build_py_with_runtime writes only beneath setuptools' build directory;
    the wheel gate builds and boots that copy outside the checkout
    [source .github/workflows/checks.yml:116]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

import shutil
from pathlib import Path

from setuptools import setup
from setuptools.command.build_py import build_py

HERE = Path(__file__).resolve().parent

# Runtime resources living outside the package that must ship inside the wheel,
# mapped to their destination under petta/_runtime/ (preserving the src/ and
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
RUNTIME_RESOURCES = {
    "src": "src",
    "lib": "lib",
    "backends": "backends",
    "python/helper.pl": "python/helper.pl",
    "python/petta/shim.pl": "python/petta/shim.pl",
}


class build_py_with_runtime(build_py):
    """Build Python modules, then copy the runtime tree beside them."""

    def run(self):
        super().run()
        runtime_root = Path(self.build_lib) / "petta" / "_runtime"
        # Emptied first, because copytree(dirs_exist_ok=True) only ever adds.
        # A resource dropped from RUNTIME_RESOURCES kept shipping out of a
        # stale build/ directory, and so did a source file deleted from src/,
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
                # was deleted.
                shutil.copytree(
                    src,
                    dst,
                    dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("__pycache__", "*.py[co]"),
                )
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)


setup(
    cmdclass={"build_py": build_py_with_runtime},
)
