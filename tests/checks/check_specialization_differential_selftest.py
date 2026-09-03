"""Purpose: prove the specialization-differential gate detects a live defect.

Guarantees:
  - reverting only the specialization arity policy in an isolated loaded copy
    makes the exact four-line wrap-one/sleep fixture raise
    ``metta_specialization_disagrees`` through the production detector, while
    the plain-call control stays clean under the same plant
    [tested: tests/checks/check_specialization_differential_selftest.py;
    commit=de2a69fbea43d7bbc641fd93240cf7572285bb5c]
Fails when:
  - the production detector, specializer verification, or fixture stops
    exercising the same disagreement; this imports the detector rather than
    reimplementing its output scan.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from check_specialization_differential import MARKER, ROOT, specialization_finding

PLANTED = """(: wrap-one (-> %Undefined% %Undefined%))
(= (wrap-one $x) ($x))
!(println! (plain  (wrap-one plain)))
!(println! (native (wrap-one sleep)))
"""

CONTROL = """(: wrap-one (-> %Undefined% %Undefined%))
(= (wrap-one $x) ($x))
!(println! (plain  (wrap-one plain)))
"""

FIXED_CALL = "translate_specialized_clause(CompiledInput, Clause, false),"
PLANTED_CALL = "translate_tracked_clause(CompiledInput, Clause, false),"


def _quoted(path: Path) -> str:
    """Quote one absolute path as a Prolog atom."""
    return "'" + path.resolve().as_posix().replace("'", "''") + "'"


def _planted_entrypoint(directory: Path) -> Path:
    """Reload the specializer with only the fixed arity policy removed."""
    source = (ROOT / "engine" / "specializer.pl").read_text(encoding="utf-8")
    if source.count(FIXED_CALL) != 1:
        msg = "the specialization compile seam changed; the selftest plant is stale"
        raise RuntimeError(msg)
    planted_specializer = directory / "specializer_with_old_arity_bug.pl"
    planted_specializer.write_text(
        source.replace(FIXED_CALL, PLANTED_CALL), encoding="utf-8"
    )
    bootstrap = directory / "planted_main.pl"
    bootstrap.write_text(
        ":- ensure_loaded(" + _quoted(ROOT / "engine" / "qlf_boot.pl") + ").\n"
        ":- ensure_loaded(" + _quoted(ROOT / "engine" / "metta.pl") + ").\n"
        ":- unload_file(" + _quoted(ROOT / "engine" / "specializer.pl") + ").\n"
        ":- load_files(" + _quoted(planted_specializer) + ", [if(true)]).\n"
        ":- ensure_loaded(" + _quoted(ROOT / "engine" / "main.pl") + ").\n"
        ":- initialization(main, main).\n",
        encoding="utf-8",
    )
    return bootstrap


def main() -> int:
    """Run the isolated old-arity plant and its no-specialization control."""
    problems: list[str] = []
    scratch = ROOT / "ai-tmp"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="spec-differential-selftest-", dir=scratch
    ) as name:
        directory = Path(name)
        planted = directory / "wrap_one_sleep.metta"
        control = directory / "wrap_one_plain.metta"
        planted.write_text(PLANTED, encoding="utf-8")
        control.write_text(CONTROL, encoding="utf-8")
        entrypoint = _planted_entrypoint(directory)

        planted_finding = specialization_finding(planted, entrypoint=entrypoint)
        control_finding = specialization_finding(control, entrypoint=entrypoint)

        if planted_finding is None:
            problems.append("the production detector stayed quiet on wrap-one/sleep")
        elif MARKER not in planted_finding:
            problems.append(
                "the planted file failed without exposing "
                f"{MARKER}: {planted_finding}"
            )
        if control_finding is not None:
            problems.append(
                f"the plain-call control was reported: {control_finding}"
            )

    for problem in problems:
        print(problem, file=sys.stderr)
    print(
        "spec-differential selftest: "
        f"{len(problems)} problem(s), 1 planted disagreement and 1 clean control"
    )
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
