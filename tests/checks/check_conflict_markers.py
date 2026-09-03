"""Purpose: refuse a tracked file that carries a leftover merge-conflict marker.

`git diff --check` already reports these, and this repository runs it. It reads
a DIFF, so it sees a marker only while the change carrying it is uncommitted.
A merge is where that gap opens: resolve, `git add`, `git commit`, and if the
staged result was never checked the markers land, after which they appear in no
later diff and every subsequent `git diff --check` is blind to them. 134 lines
of unresolved conflict sat in CHANGELOG.md from 2026-08-28 to 2026-09-03,
through every gate run in between, for exactly that reason.

So this asks the question the diff cannot: does the COMMITTED tree contain one.

Only the opener and the closer are matched, never a bare `=======`. Seven
identical angle brackets followed by a space and a label are unambiguous, while
`=======` on its own is also a markdown setext heading underline, and a real
conflict always carries an opener and a closer anyway. Matching the pair rather
than the separator removes that false-positive class by construction rather than
by an exception list.

Assumes: git on PATH, and a checkout of this repository.
Guarantees:
  - a tracked file carrying an opener or a closer fails the run and is named
    with its path and line [tested: tests/checks/check_conflict_markers_selftest.py;
    commit=74e3f12824aee43fb5dd5c7f0f21b859d72e5c78]
  - a markdown setext heading underline is NOT a finding, because the separator
    alone is never matched [tested:
    tests/checks/check_conflict_markers_selftest.py; commit=74e3f12824aee43fb5dd5c7f0f21b859d72e5c78]
Fails when: run outside a git checkout, where it reports that rather than
  passing on an empty file list.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

#: git's own opener and closer. The separator is deliberately absent; see the
#: module docstring for why matching the pair is what makes this safe.
MARKER = re.compile(r"^(<<<<<<<|>>>>>>>) ", re.MULTILINE)


def tracked_files(root: Path) -> list[str]:
    """Every path git tracks, which is the set a commit can carry a marker in."""
    done = subprocess.run(
        ["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True, check=False
    )
    if done.returncode != 0:
        message = f"not a git checkout: {root}"
        raise SystemExit(message)
    return [name for name in done.stdout.split("\0") if name]


def findings(root: Path) -> list[str]:
    """Each tracked file's marker lines, named by path and line."""
    out: list[str] = []
    for name in tracked_files(root):
        path = root / name
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue  # a binary or unreadable file cannot carry a text marker
        for match in MARKER.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            out.append(f"{name}:{line}: leftover conflict marker")
    return out


def main() -> int:
    """Report every leftover marker in the committed tree."""
    problems = findings(ROOT)
    for problem in problems:
        print(f"  {problem}")
    print(f"conflict-markers: {len(problems)} finding(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
