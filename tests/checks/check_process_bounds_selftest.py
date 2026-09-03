"""Purpose: prove check_process_bounds.py can find, and can spare.

Running the pass over this repository proves the repository is bounded. It says
nothing about whether the pass can find an unbounded spawn at all, which is the
whole of its job. Both halves are planted here in a fixture the test writes and
throws away.

Two negatives are load-bearing. `$(dirname "$(dirname "$PY")")` holds `$PY`
without starting a Python, so a pass matching the line rather than the command
POSITION would report it and be turned off within a day. And `in_py() { ...; }`
is a one-line function whose closing brace is not at column 0, so a parser
tracking only `^}` would treat the remaining 400 lines of check.sh as its body
and report every top-level lane in it: that exact mistake produced 32 false
findings while this check was being written.

Assumes: a writable ai-tmp/ in this repository.
Guarantees:
  - a planted unbounded swipl, sh and "$PY" are each reported with lane and
    line [tested: tests/checks/check_process_bounds_selftest.py; commit=WORKTREE]
  - a `bounded` spawn, an `in_py` spawn, a comment, a dirname substitution and
    a one-line function are NOT reported
    [tested: tests/checks/check_process_bounds_selftest.py; commit=WORKTREE]
  - an `in_py` that stops calling `bounded` is reported even though every lane
    reaching its command through it still LOOKS bounded
    [tested: tests/checks/check_process_bounds_selftest.py; commit=WORKTREE]
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

from check_process_bounds import findings  # noqa: E402  -- the path is installed above

BOUND_IN_PY = 'in_py() { ( cd "$PYDIR" && bounded "$@" ); }\n'
LOOSE_IN_PY = 'in_py() { ( cd "$PYDIR" && "$@" ); }\n'

#: Top-level lines that follow the one-line function, which is the shape
#: check.sh actually has: in_py() { ...; } and then 400 lines of `run` calls
#: before the next function opens. A parser that treats the one-liner as open
#: attributes every one of them to it. Reported here as a NEGATIVE, because
#: `run()` already wraps a lane whose command word is a program.
TOP_LEVEL = """
run GATE   evidence   "$PY" "$HERE/tests/checks/check_evidence_tags.py"
swipl -g halt -s "$HERE/engine/main.pl" -- extensions >/dev/null 2>&1 || true
run GATE   petta      sh -c "cd '$HERE' && '$PY' tests/conformance/petta.py"
"""

LANES = """
check_bad_swipl() {
    swipl -q --on-error=status thing.pl
}

check_bad_sh() {
    sh "$HERE/engine/test.sh"
}

check_bad_python() {
    ( cd "$HERE" && "$PY" -m ruff check $found )
}

# The case that hung a real gate run: `make` drives a sanitizer build whose
# llvm-symbolizer went to 0% CPU and never returned, and `make` was missing
# from the spawner list, so this check called that lane clean.
check_bad_make() {
    make --quiet -C "$binding" sanitize
}

check_good_swipl() {
    bounded swipl -q --on-error=status thing.pl
}

check_good_via_in_py() {
    in_py "$PY" bench.py --json out.json
}

check_only_a_comment() {
    # ( swipl -q thing.pl ) would run here if this were not a comment, and the
    # paren puts it at a command position, so only the comment skip spares it
    return 0
}

check_dirname_only() {
    py_prefix=$(dirname "$(dirname "$PY")")
    printf '%s\\n' "$py_prefix"
}

check_prose_only() {
    echo "note: node_modules is absent, the built-package \\
check will not run; npm ci fetches swipl-wasm and a gate does not reach the \\
network" >&2
    return 0
}
"""


def report(text: str) -> tuple[list[str], int]:
    """The pass's findings over a planted check.sh, and its spawn count.

    The count is asserted too, because a pass that stops RECOGNISING a spawn
    reports the same findings over fewer of them, and only the count tells
    those two apart.
    """
    with tempfile.TemporaryDirectory(dir=ROOT / "ai-tmp") as work:
        root = Path(work)
        (root / "check.sh").write_text(text, encoding="utf-8")
        return findings([root / "check.sh"], root)


def main() -> int:
    """Every planted case, positive and negative."""
    problems: list[str] = []

    found, total = report(BOUND_IN_PY + TOP_LEVEL + LANES)
    lanes = {line.split(": ")[1].split(" starts")[0]
             for line in found if " starts a process" in line}
    problems.extend(
        f"{expected}: an unbounded spawn was NOT reported"
        for expected in ("check_bad_swipl", "check_bad_sh", "check_bad_python",
                         "check_bad_make")
        if expected not in lanes
    )
    problems.extend(
        f"{spared}: reported, and it must not be"
        for spared in ("check_good_swipl", "check_good_via_in_py",
                       "check_only_a_comment", "check_dirname_only",
                       "check_prose_only")
        if spared in lanes
    )
    if len(found) != 4:
        problems.append(f"expected exactly 4 findings, got {len(found)}: {found}")
    #: Four unbounded, one `bounded swipl`, one `in_py`. A pass that forgot
    #: how to see a bounded spawn would still report exactly the four above.
    if total != 6:
        problems.append(
            f"expected 6 spawns to be looked at, got {total}. A pass that "
            f"stops recognising `bounded` as a spawn line reports the same "
            f"findings while covering less."
        )

    # The one-line function must not swallow what follows it. With BOUND_IN_PY
    # first, the three bad lanes below it are still found; a parser that treated
    # in_py as open would attribute them to in_py instead.
    if "in_py" in lanes:
        problems.append(
            "the one-line in_py was treated as an open function body, so the "
            "top-level lines after it were reported as spawns inside it. That "
            "is the mistake that produced 32 false findings."
        )

    # in_py losing its bound is a finding even when every caller looks bounded.
    loose, _ = report(LOOSE_IN_PY + TOP_LEVEL + LANES)
    if not any("in_py no longer calls" in line for line in loose):
        problems.append("in_py without `bounded` was NOT reported")

    for problem in problems:
        print(f"  {problem}")
    print(f"{len(problems)} finding(s) over 16 planted cases")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
