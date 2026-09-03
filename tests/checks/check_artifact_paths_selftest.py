"""Purpose: prove check_artifact_paths.py finds a stale path and spares three
things that are not one.

Running the pass on THIS repository proves the repository resolves. It says
nothing about whether the pass can find a stale path at all, and nothing about
the three shapes it must NOT report, each of which would get the lane switched
off the first week if it were wrong.

Assumes: a writable ai-tmp/ in this repository.
Guarantees:
  - a path expression naming a missing file is reported with its line and the
    folded path [tested: tests/checks/check_artifact_paths_selftest.py;
    commit=1b689c7f4ce1be7fd151c0bd5b7ef017c4c12e9f]
  - a resolving path, a `artifact-path-created` opt-out, and a path whose
    segments are not literals are each NOT reported
    [tested: tests/checks/check_artifact_paths_selftest.py; commit=1b689c7f4ce1be7fd151c0bd5b7ef017c4c12e9f]
Fails when: run against a tree it did not write. It asserts on its own fixture.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_artifact_paths import findings  # noqa: E402  -- the path is installed above

FIXTURE = '''\
from pathlib import Path

STALE = Path(__file__).resolve().parents[0] / "gone" / "missing.so"
LIVE = Path(__file__).resolve().parents[0] / "present.txt"
MADE = Path(__file__).resolve().parents[0] / "out" / "built.so"  # artifact-path-created
name = "computed"
DYNAMIC = Path(__file__).resolve().parents[0] / name / "x.so"
'''


def main() -> int:
    """Plant each shape and hold the pass to what it reports."""
    problems: list[str] = []
    scratch = ROOT / "ai-tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="artifact-paths-selftest-", dir=scratch
    ) as name:
        fixture = Path(name)
        (fixture / "probe.py").write_text(FIXTURE, encoding="utf-8")
        (fixture / "present.txt").write_text("here\n", encoding="utf-8")

        reported = findings(fixture)
        lines = {int(entry.split(":")[1]) for entry in reported}

        if 3 not in lines:
            problems.append(f"the stale path on line 3 was not reported: {reported}")
        if 4 in lines:
            problems.append("a path that RESOLVES was reported")
        if 5 in lines:
            problems.append(
                "an `artifact-path-created` opt-out was reported, so a runtime "
                "output path would force the lane off"
            )
        if 7 in lines:
            problems.append(
                "a path with a non-literal segment was reported; the pass has to "
                "skip what it cannot fold rather than guess"
            )
        if len(reported) != 1:
            problems.append(f"expected exactly one finding, got {reported}")

    for problem in problems:
        print(f"  {problem}")
    print(f"artifact-paths-selftest: {len(problems)} finding(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
