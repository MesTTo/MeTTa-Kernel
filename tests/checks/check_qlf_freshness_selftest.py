"""Purpose: prove the qlf-freshness gate turns each planted omission red.

Guarantees:
  - a loader with no purge, one that purges too late, and one whose purge
    resolves from a different directory each fail on their own, while a
    correct loader, a declared exemption and the two exempt-by-name entry
    points pass [tested: tests/checks/check_qlf_freshness_selftest.py;
    commit=62b310ed73dfe13f24cc1bd149af3c68ba2dff0e]
Fails when:
  - run from a directory the check's own ROOT cannot be derived from; it
    imports the gate rather than re-implementing its patterns, so the two
    cannot drift apart.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from check_qlf_freshness import complaints_for

ENGINE = ":- ensure_loaded('../../engine/metta.pl').\n"
PURGE = ":- ensure_loaded('../../engine/qlf_boot.pl').\n"


def _loader(root: Path, relative: str, body: str) -> Path:
    """One Prolog file, written where the gate expects to find it."""
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    return path


def _complaints(root: Path, body: str, relative: str = "tests/prolog/planted.pl"):
    """What the gate says about a planted file, with ROOT pointed at the fixture."""
    import check_qlf_freshness

    original = check_qlf_freshness.ROOT
    check_qlf_freshness.ROOT = root
    try:
        return complaints_for(_loader(root, relative, body))
    finally:
        check_qlf_freshness.ROOT = original


def main() -> int:
    """Each planted defect on its own, then the shapes that must stay quiet."""
    defects: list[str] = []
    with tempfile.TemporaryDirectory() as name:
        root = Path(name)

        prolog = "tests/prolog/planted.pl"
        #: A host seat builds its consult as a C string, which is where the rule
        #: matters most and where a Prolog-only walk would see nothing.
        c = "extensions/seat/host.c"
        c_engine = "snprintf(b, n, \"consult('%s/engine/metta.pl')\", path);\n"
        c_purge = "snprintf(b, n, \"consult('%s/engine/qlf_boot.pl')\", path);\n"

        cases = [
            # (label, path, body, must_complain)
            ("no purge at all", prolog, ENGINE, True),
            ("purge after the engine", prolog, ENGINE + PURGE, True),
            ("purge from another directory", prolog,
             ":- ensure_loaded('../../../engine/qlf_boot.pl').\n" + ENGINE, True),
            ("purge first, same prefix", prolog, PURGE + ENGINE, False),
            ("declared exemption", prolog,
             "% qlf-freshness-exempt: measures the artifact set itself\n" + ENGINE,
             False),
            # A file that never loads the engine is not this gate's business.
            ("no engine load", prolog, ":- use_module(library(lists)).\n", False),
            # The engine's own prose names both files constantly; a comment is
            # not a load, and reading it as one would fail every unit.
            ("engine named only in a comment", prolog,
             "% consult('../../engine/metta.pl') is what main.pl does.\n", False),
            ("C loader without the purge", c, c_engine, True),
            ("C loader with the purge first", c, c_purge + c_engine, False),
            ("C comment naming the engine", c,
             "// consult('%s/engine/metta.pl') is what mt_open does.\n", False),
        ]
        for label, path, body, must_complain in cases:
            got = _complaints(root, body, path)
            if must_complain and not got:
                defects.append(f"the gate stayed quiet on a planted defect: {label}")
            if not must_complain and got:
                defects.append(f"the gate complained about a correct file ({label}): {got[0]}")
            #: The remedy is the door, so it has to arrive in the file's own
            #: language; a Prolog directive printed into a C file is a gate that
            #: does not know what it is looking at.
            if must_complain and got and path.endswith(".c") and "ensure_loaded" in got[0]:
                defects.append(f"the C remedy is spelled as a Prolog directive: {label}")

        # The entry points are exempt by NAME, and each exemption has to be
        # real: two load the purge as a module, which the path pattern cannot
        # see, and one mounts engine sources with the .qlf files excluded.
        exempt = ("engine/main.pl", "engine/bench.pl", "extensions/node/src/engine.ts")
        defects.extend(
            f"{entry} should be exempt by name and was not"
            for entry in exempt
            if _complaints(root, ENGINE, entry)
        )
        if not _complaints(root, ENGINE, "engine/other.pl"):
            defects.append("the by-name exemption is too wide: engine/other.pl passed")

    if defects:
        for line in defects:
            print(line, file=sys.stderr)
        return 1
    print(f"qlf-selftest: 0 defect(s), over {len(cases)} planted loaders "
          f"and {len(exempt) + 1} exemption cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
