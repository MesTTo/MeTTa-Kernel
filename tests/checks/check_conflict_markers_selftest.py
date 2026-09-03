"""Purpose: prove check_conflict_markers.py finds a marker and spares a heading.

Running the pass on THIS repository proves the repository is clean. It says
nothing about whether the pass can find a marker at all, which is the whole of
its job, and nothing about the one shape it must NOT flag. Both are planted here
in a fixture checkout the test builds and throws away.

The separator case is the load-bearing one. `=======` on its own line is a
markdown setext heading underline as well as a conflict separator, so a pass
that matched it would report every such heading as a leftover conflict and be
turned off within a day. It is planted here as a NEGATIVE so the decision to
match only the opener and closer cannot be quietly reversed.

Assumes: git on PATH, and a writable ai-tmp/ in this repository.
Guarantees:
  - a planted opener and a planted closer are each reported with their path and
    line [tested: tests/checks/check_conflict_markers_selftest.py; commit=WORKTREE]
  - a setext heading underline and a table rule are NOT reported
    [tested: tests/checks/check_conflict_markers_selftest.py; commit=WORKTREE]
  - an untracked file carrying a marker is NOT reported, because a commit
    cannot carry it [tested: tests/checks/check_conflict_markers_selftest.py;
    commit=WORKTREE]
Fails when: run against a tree it did not write. It asserts on its own fixture.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_conflict_markers import findings  # noqa: E402  -- the path is installed above

CONFLICTED = "before\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> other\nafter\n"
HEADING = "A Title\n=======\n\nbody, and a table rule below\n\n=====\n"


def git(directory: Path, *args: str) -> None:
    """Run one git command in the fixture, failing loudly."""
    subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)


def main() -> int:
    """Plant each shape and hold the pass to what it reports."""
    problems: list[str] = []
    scratch = ROOT / "ai-tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="conflict-markers-selftest-", dir=scratch
    ) as name:
        fixture = Path(name)
        git(fixture, "init", "-q")
        (fixture / "conflicted.md").write_text(CONFLICTED, encoding="utf-8")
        (fixture / "heading.md").write_text(HEADING, encoding="utf-8")
        git(fixture, "add", "conflicted.md", "heading.md")
        # tracked by nothing, so a commit cannot carry it
        (fixture / "untracked.md").write_text(CONFLICTED, encoding="utf-8")

        reported = findings(fixture)
        paths = {line.split(":", 1)[0] for line in reported}

        if "conflicted.md:2: leftover conflict marker" not in reported:
            problems.append(f"the planted opener was not reported: {reported}")
        if "conflicted.md:6: leftover conflict marker" not in reported:
            problems.append(f"the planted closer was not reported: {reported}")
        if "heading.md" in paths:
            problems.append(
                "a setext heading underline was reported as a conflict marker, "
                "which is the false positive that matching only the pair avoids"
            )
        if "untracked.md" in paths:
            problems.append("an untracked file was reported; a commit cannot carry it")

    for problem in problems:
        print(f"  {problem}")
    print(f"conflict-markers-selftest: {len(problems)} finding(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
