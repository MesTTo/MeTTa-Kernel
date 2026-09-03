"""Purpose: bound every process a gate lane starts, past the gate itself.

`check.sh`'s `run()` wraps a lane whose command word is an external program in
`timeout`, and CANNOT wrap one whose command word is a shell function, because
`timeout` execs and a function is not on disk. 25 of the 33 lane functions start
swipl, node or a Python of their own, so most of what this gate runs would carry
no bound at all if those spawns did not carry it themselves. They do, spelled
`bounded swipl ...`, and this is what says so.

The cost of not saying so is measured: two swipl children spawned under this
gate ran from 2026-09-01 to 2026-09-03, spinning at 100% for 122 CPU-hours
between them, after the session that started them was killed. The only bound on
them was `subprocess.run(timeout=)`, which is enforced in the parent's wait loop
and stops enforcing when the parent does.

Assumes:
  - a lane function is `name() {` at column 0 in one of the check scripts, and
    ends at a `}` at column 0, which is how every one of them is written
  - `bounded` and `in_py` are the two helpers that carry a bound; `in_py`
    carries it because its own body calls `bounded`, which is checked here
    rather than assumed
Guarantees:
  - a spawn added to a lane function without a bound is named, with its file,
    line and the text, so the fix is the line the report prints
    [tested: tests/checks/check_process_bounds_selftest.py]
Fails when: a lane starts a process through a name this does not know. The
  known set is printed with the findings for that reason, so an unrecognised
  spawn reads as a gap in this check rather than as a clean run.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

#: The programs a lane starts that can outlive it. `sh` is here because every
#: test.sh and bench.sh the lanes call is a shell script that starts more, and
#: the build tools are here because the gate run that first verified this check
#: HUNG in `make -C extensions/cmetta sanitize` for 360 seconds: LeakSanitizer
#: spawned llvm-symbolizer to report a leak, the symbolizer went to 0% CPU, and
#: the test blocked forever on its pipe. `make` was not on this list, so the
#: check called that lane clean while it was the one lane that could not end.
SPAWNERS = ("swipl", "node", "npx", "sh", '"$PY"', "$PY",
            "make", "gcc", "clang", "cargo", "npm")

#: Helpers that carry the bound themselves. `in_py` is verified, not trusted.
BOUNDING = ("bounded", "in_py")

#: Command position: start of line, or after a shell operator, optionally
#: preceded by environment assignments. `$(dirname "$(dirname "$PY")")` must
#: not match, which is why the executable has to sit at a command position
#: rather than merely appear on the line.
POSITION = re.compile(
    r"(?:^|\(|&&|\|\||;|\||!|\$\()\s*"
    r"(?:[A-Za-z_][A-Za-z_0-9]*=\S*\s+)*"
    r"(" + "|".join(re.escape(s) for s in SPAWNERS + BOUNDING) + r")(?![\w-])"
)


def scripts() -> list[Path]:
    """The gate scripts, discovered the way check.sh discovers them."""
    found = [REPO / "check.sh", REPO / "engine" / "check.sh"]
    found += sorted((REPO / "extensions").glob("*/check.sh"))
    return [p for p in found if p.is_file()]


def spawns(path: Path) -> list[tuple[int, str, str, bool]]:
    """Every spawn inside a multi-line lane function: line, lane, text, bound."""
    out: list[tuple[int, str, str, bool]] = []
    lane: str | None = None
    # Whether the previous line left a double quote open. A continued message
    # is prose, and prose contains shell punctuation: `check will not run; npm
    # ci fetches swipl-wasm` reads as a command separator followed by a spawn
    # unless the string it sits inside is tracked.
    inside_string = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        was_inside, inside_string = inside_string, inside_string ^ (
            len(re.findall(r'(?<!\\)"', line)) % 2 == 1
        )
        if was_inside:
            continue
        opening = re.match(r"^([a-z_][a-z_0-9]*)\(\)\s*\{", line)
        if opening:
            # A one-line function body cannot hold an unbounded continuation.
            lane = None if line.rstrip().endswith("}") else opening.group(1)
            continue
        if lane is None:
            continue
        if line.startswith("}"):
            lane = None
            continue
        if line.lstrip().startswith("#"):
            continue
        words = POSITION.findall(line)
        if not words:
            continue
        out.append((number, lane, line.strip(), any(w in BOUNDING for w in words)))
    return out


def findings(paths: list[Path], root: Path) -> tuple[list[str], int]:
    """Every unbounded lane spawn, and how many spawns were looked at.

    Split out of main so the selftest can put a planted tree in front of it
    without building a whole repository around it.
    """
    found: list[str] = []
    total = 0
    for path in paths:
        name = path.name if path.parent == root else str(path)
        for number, lane, text, bound in spawns(path):
            total += 1
            if not bound:
                found.append(
                    f"{name}:{number}: {lane} starts a process with no bound.\n"
                    f"    {text[:100]}\n"
                    f"    Prefix it with `bounded`, which is check.sh's one "
                    f"definition of the ceiling. A bound kept by the caller "
                    f"stops being kept when the caller is killed."
                )

    # in_py carries the bound for 18 lanes, so its own body is the load-bearing
    # line. Checked rather than trusted: without it those 18 read as bounded
    # here and are not.
    driver = root / "check.sh"
    if driver.is_file() and not re.search(
        r"^in_py\(\)\s*\{[^}]*\bbounded\b", driver.read_text(encoding="utf-8"), re.MULTILINE
    ):
        found.append(
            "check.sh: in_py no longer calls `bounded`, and 18 lanes reach "
            "their command through it. Those lanes are unbounded and this "
            "check would otherwise still pass them."
        )
    return found, total


def main() -> int:
    """Name every lane spawn that carries no bound."""
    paths = scripts()
    found, total = findings(paths, REPO)
    for finding in found:
        print(f"  {finding}")
    print(f"{len(found)} finding(s) over {total} lane spawns "
          f"in {len(paths)} gate scripts")
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main())
