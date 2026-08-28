"""Purpose: prove the qlf-freshness gate turns each planted omission red.

Guarantees:
  - a loader with no purge, one that purges too late, and one whose purge
    resolves from a different directory each fail on their own, while a
    correct loader, a declared exemption and the two exempt-by-name entry
    points pass [tested: tests/checks/check_qlf_freshness_selftest.py;
    commit=WORKTREE]
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

        cases = [
            # (label, body, must_complain)
            ("no purge at all", ENGINE, True),
            ("purge after the engine", ENGINE + PURGE, True),
            ("purge from another directory",
             ":- ensure_loaded('../../../engine/qlf_boot.pl').\n" + ENGINE, True),
            ("purge first, same prefix", PURGE + ENGINE, False),
            ("declared exemption",
             "% qlf-freshness-exempt: measures the artifact set itself\n" + ENGINE,
             False),
            # A file that never loads the engine is not this gate's business.
            ("no engine load", ":- use_module(library(lists)).\n", False),
            # The engine's own prose names both files constantly; a comment is
            # not a load, and reading it as one would fail every unit.
            ("engine named only in a comment",
             "% consult('../../engine/metta.pl') is what main.pl does.\n", False),
        ]
        for label, body, must_complain in cases:
            got = _complaints(root, body)
            if must_complain and not got:
                defects.append(f"the gate stayed quiet on a planted defect: {label}")
            if not must_complain and got:
                defects.append(f"the gate complained about a correct file ({label}): {got[0]}")

        # The two entry points are exempt by NAME, and the exemption has to be
        # real: they load the purge as a module, which the path pattern cannot
        # see. A wrong name here would silence a file that should be checked.
        for entry in ("engine/main.pl", "engine/bench.pl"):
            if _complaints(root, ENGINE, entry):
                defects.append(f"{entry} should be exempt by name and was not")
        if not _complaints(root, ENGINE, "engine/other.pl"):
            defects.append("the by-name exemption is too wide: engine/other.pl passed")

    if defects:
        for line in defects:
            print(line, file=sys.stderr)
        return 1
    print("qlf-selftest: 0 defect(s), over 7 planted loaders and 3 exemption cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
