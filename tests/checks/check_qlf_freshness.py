"""Purpose: refuse a file that loads the engine without first loading the purge
that makes the engine's compiled artifacts honest.

Assumes:
  - ``engine/qlf_boot.pl`` is the purge, and loading it runs
    ``purge_stale_qlf`` as a directive
  - a loader names the engine as ``<prefix>engine/metta.pl`` and must name the
    purge with the SAME prefix, so the pair resolves from one directory
Guarantees:
  - every file loading ``engine/metta.pl`` loads ``engine/qlf_boot.pl`` first,
    or declares an exemption in place
    [tested: tests/checks/check_qlf_freshness_selftest.py; commit=WORKTREE]
Fails when:
  - a loader is added without the purge, which is silent otherwise: the suite
    passes, against the previous compile of whatever unit was edited
Decides:
  - ``engine/main.pl`` and ``engine/bench.pl`` are exempt by name because they
    load the purge as a module rather than by path, and they are the two
    entry points the purge was written for
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

#: The engine load, and the purge that has to precede it. Both are captured
#: with their relative prefix, because a suite four levels down and a script
#: two levels down name the same two files differently and each pair has to
#: agree with itself.
ENGINE = re.compile(r"(?:ensure_loaded|consult)\('([^']*)engine/metta\.pl'\)")
PURGE = re.compile(r"(?:ensure_loaded|consult)\('([^']*)engine/qlf_boot(?:\.pl)?'\)")

#: These two load the purge as a module (``:- ensure_loaded(qlf_boot).``) from
#: inside engine/, which the path pattern above cannot see and does not need to.
EXEMPT_BY_NAME = {"engine/main.pl", "engine/bench.pl"}

#: The door. A file that means to load the engine WITHOUT the purge says so on
#: its own line, with the reason beside it, rather than in a list here.
EXEMPTION = re.compile(r"%\s*qlf-freshness-exempt:\s*(\S.*)")


def tracked_prolog_files() -> list[Path]:
    """Every tracked .pl and .plt, so an untracked scratch file is not a gate."""
    listed = subprocess.run(
        ["git", "ls-files", "-z", "*.pl", "*.plt"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    return [ROOT / name for name in listed.split("\0") if name]


def first_match_line(text: str, pattern: re.Pattern[str]) -> tuple[int, str] | None:
    """The line number and captured prefix of a pattern's first occurrence.

    Comment lines are skipped: this gate is about what a file LOADS, and the
    engine's own prose names both files constantly.
    """
    for number, line in enumerate(text.splitlines(), start=1):
        if line.lstrip().startswith("%"):
            continue
        found = pattern.search(line)
        if found:
            return number, found.group(1)
    return None


def complaints_for(path: Path) -> list[str]:
    """What is wrong with one file's engine load, if anything."""
    relative = path.relative_to(ROOT).as_posix()
    if relative in EXEMPT_BY_NAME:
        return []
    text = path.read_text(encoding="utf-8")
    engine = first_match_line(text, ENGINE)
    if engine is None:
        return []
    exemption = EXEMPTION.search(text)
    if exemption:
        return []
    engine_line, engine_prefix = engine
    purge = first_match_line(text, PURGE)
    if purge is None:
        return [
            f"{relative}:{engine_line} loads the engine without the purge; add "
            f"`:- ensure_loaded('{engine_prefix}engine/qlf_boot.pl').` above it, "
            f"or write `% qlf-freshness-exempt: <why>` in this file"
        ]
    purge_line, purge_prefix = purge
    if purge_line > engine_line:
        return [
            f"{relative}:{purge_line} loads the purge AFTER the engine at line "
            f"{engine_line}; the purge decides which artifacts the engine load "
            f"reads, so it has to come first"
        ]
    if purge_prefix != engine_prefix:
        return [
            f"{relative}:{purge_line} names the purge as '{purge_prefix}...' "
            f"while the engine is '{engine_prefix}...'; the two prefixes must "
            f"match or one of them resolves from the wrong directory"
        ]
    return []


def main() -> int:
    """Report every loader that could read a stale compile."""
    complaints: list[str] = []
    loaders = 0
    for path in tracked_prolog_files():
        text_has_engine = ENGINE.search(path.read_text(encoding="utf-8"))
        if text_has_engine:
            loaders += 1
        complaints.extend(complaints_for(path))
    if complaints:
        for line in complaints:
            print(line, file=sys.stderr)
        return 1
    print(f"qlf: all {loaders} engine loaders purge stale artifacts first")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
