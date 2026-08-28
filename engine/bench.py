"""Purpose: drive engine/bench.pl and hand its counters to the shared
benchmark harness, so the engine's own pins use the one baseline format and
the one regression protocol every component here uses.

This is NOT engine code and no measured process loads it. Each measurement is
a fresh `swipl` running engine/bench.pl and nothing else; this file starts
those processes, reads the line each prints, and calls BenchmarkBaseline.
Assumes:
  - extensions/python is importable from ROOT, which is where
    metta.benchmarking lives. DEVELOPING.md's rule is that a sibling imports
    BenchmarkBaseline, benchmark_case, count_atoms and measure_instructions
    from metta.testing rather than copying the harness, and that is the whole
    reason this file exists instead of a second comparison protocol
    [source: DEVELOPING.md:149-151].
  - engine/bench.pl prints one `metta-bench ...` line per run and answers
    `bench_describe` with its case table and its workload list, so no case
    name, unit, operation count or corpus path is written twice.
Guarantees:
  - the deciding counter is inferences, taken from three fresh processes that
    perf is NOT watching, so a machine with no perf still gates
    [tested: engine/bench.sh; commit=WORKTREE].
  - retired instructions are measured over the same region and not over the
    process, through perf's control descriptors, so a case's instruction pin
    excludes the engine boot that every case would otherwise carry
    [measured 2026-08-28: the parse case reads 109,337,650 instructions in
    its controlled window against 1,119,242,969 for the whole process, so
    without the window nine tenths of its pin would be the boot].
  - the configuration stamp carries the four artifact keys
    benchmarks/configuration.py decides comparability by, PLUS a digest of
    every corpus file the cases read, so editing a workload REFUSES the
    comparison instead of reporting a move the engine did not make
    [tested: engine/bench.sh; commit=WORKTREE].
  - every selected case is measured and every failure is reported before the
    nonzero exit, so one regression cannot hide another
    [source: extensions/python/benchmarks/check_instructions.py, whose
    stop-at-first-failure form masked four stale pins for days].
  - the .qlf artifact set is warmed before any sample, because the boot that
    GENERATES it is a different workload from the boot that loads it and a
    cold first run has inverted a measured win before
    [measured 2026-08-28: 3,129,543 inferences on a generating boot against
    612,598 warm, same tree, same command].
Owns resources:
  - each swipl process is run to completion with an explicit timeout and its
    output captured; a timeout is reported as a failed case rather than
    raised past the loop.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""  # noqa: D205  -- the API contract is one continuous invariant, not summary-and-body prose

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "extensions" / "python"))

from benchmarks.configuration import counter_configuration  # noqa: E402  -- the harness lives in the sibling component and the path above is what makes it importable
from metta.testing import BenchmarkBaseline, measure_instructions  # noqa: E402  -- same

BASELINE = HERE / "bench-baseline.json"
BENCH = HERE / "bench.pl"
#: The shared harness decides on the minimum of three samples; taking fewer
#: here would hand it a shorter list than it accepts.
SAMPLES = 3
#: Every case is well under a second warm. The limit exists so a hung engine
#: fails the case instead of the run.
TIMEOUT = 120.0


def _command(goal: str) -> list[str]:
    """The one swipl invocation shape: no host, one goal, then halt.

    --stack_limit matches run.sh, so the engine is measured in the stack
    configuration it ships with rather than SWI's default.
    """
    return [
        "swipl",
        "-q",
        "--stack_limit=8g",
        "-g",
        goal,
        "-t",
        "halt",
        str(BENCH),
    ]


def _goal(name: str) -> str:
    """bench_run for one case: module-qualified, and quoted because a bare
    parse-prolog reads as a term rather than an atom.
    """
    return f"metta_bench:bench_run('{name}')"


class CaseFailure(Exception):
    """One case could not be measured; the run continues and reports it."""


def _run(goal: str) -> str:
    """Run one swipl process and return its standard output."""
    try:
        finished = subprocess.run(  # noqa: S603  -- the argument vector is built here from a fixed executable name and a case name from bench.pl's own table
            _command(goal),
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        msg = f"{goal} exceeded its {TIMEOUT:g} second limit"
        raise CaseFailure(msg) from expired
    if finished.returncode != 0:
        detail = (finished.stderr or finished.stdout).strip()
        msg = f"{goal} exited with status {finished.returncode}: {detail}"
        raise CaseFailure(msg)
    return finished.stdout


def _fields(line: str, prefix: str) -> dict[str, str] | None:
    """key=value fields from one of bench.pl's tagged lines."""
    head, _, rest = line.partition(" ")
    if head != prefix:
        return None
    return dict(field.split("=", 1) for field in rest.split() if "=" in field)


def describe() -> tuple[dict[str, tuple[str, int]], tuple[str, ...]]:
    """The case table and the workload list, read from bench.pl itself."""
    output = _run("metta_bench:bench_describe")
    cases: dict[str, tuple[str, int]] = {}
    sources: list[str] = []
    for line in output.splitlines():
        case = _fields(line, "metta-bench-case")
        if case is not None:
            cases[case["name"]] = (case["unit"], int(case["operations"]))
            continue
        source = _fields(line, "metta-bench-source")
        if source is not None:
            sources.append(source["path"])
    if not cases or not sources:
        msg = f"bench_describe answered no cases or no sources:\n{output}"
        raise CaseFailure(msg)
    return cases, tuple(sources)


def stamp(sources: Sequence[str]) -> dict[str, Any]:
    """The configuration a pin is only comparable within.

    The four artifact keys are benchmarks/configuration.py's, unchanged: the
    C reader alone moved one Python case from 8,704,891 inferences to 722,264
    with no code change, and it moves this suite's parse case by four orders
    of magnitude the same way. The workload digests are the same idea applied
    to the other input a pin depends on. These cases read the tree's own
    corpus, so an edit to one changes the measured work; digesting them makes
    that a refusal naming the file rather than a regression naming the engine.
    """
    return counter_configuration() | {
        "workloads": {
            relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()[:16]
            for relative in sources
        }
    }


def counter_samples(name: str) -> tuple[list[int], float, float]:
    """Inferences from three fresh processes, plus advisory cpu and wall.

    A fresh process per sample is the strongest form of the harness's own
    fresh-setup rule: nothing an earlier case did to the engine's global state
    can reach this one. It is also what makes the numbers reproducible by
    hand, since each sample is one command anybody can run.
    """
    inferences: list[int] = []
    cpu: list[float] = []
    wall: list[float] = []
    for _ in range(SAMPLES):
        output = _run(_goal(name))
        reading = None
        for line in output.splitlines():
            reading = _fields(line, "metta-bench") or reading
        if reading is None or reading.get("case") != name:
            msg = f"{name} printed no metta-bench line:\n{output}"
            raise CaseFailure(msg)
        inferences.append(int(reading["inferences"]))
        cpu.append(float(reading["cputime"]))
        wall.append(float(reading["walltime"]))
    return inferences, min(cpu), min(wall)


def instruction_samples(name: str) -> tuple[int, ...]:
    """Retired instructions over the same region, through perf's control fds."""
    return measure_instructions(
        _command(_goal(name)),
        rounds=SAMPLES,
        controlled=True,
        timeout=TIMEOUT,
    )


def _movement(previous: Mapping[str, Any] | None, key: str, observed: int) -> str:
    """What an update changed for one pinned number."""
    before = None if previous is None else previous.get(key)
    if not isinstance(before, int) or isinstance(before, bool):
        return f"{key} {observed} (new)"
    delta = observed - before
    percent = 100.0 * delta / before if before else 0.0
    return f"{key} {before} -> {observed} ({delta:+d}, {percent:+.3f}%)"


def observe(
    baseline: BenchmarkBaseline,
    name: str,
    unit: str,
    operations: int,
    *,
    instructions: bool,
) -> str:
    """Measure one case and either compare it or re-pin it."""
    previous = dict(baseline.cases[name]) if name in baseline.cases else None
    samples, cpu, wall = counter_samples(name)
    moved = [_movement(previous, "inferences", min(samples))]
    reported = [f"inference samples={samples}"]
    baseline.observe_counter(name, unit=unit, operations=operations, samples=samples)
    baseline.observe_wall(name, wall / operations)
    if instructions:
        retired = instruction_samples(name)
        moved.append(_movement(previous, "instructions", min(retired)))
        spread = 100.0 * (max(retired) - min(retired)) / min(retired)
        reported.append(f"instruction samples={list(retired)} spread={spread:.3f}%")
        baseline.observe_instructions(name, retired)
    return (
        f"{name}: {'; '.join(moved)}; {'; '.join(reported)}; "
        f"cpu={cpu:.6f}s wall={wall:.6f}s (advisory)"
    )


def main(argv: Sequence[str] | None = None) -> int:  # noqa: C901  -- the loop keeps measurement, reporting and the keep-going contract together, and splitting them would hide which failures were collected
    """Measure the selected cases against engine/bench-baseline.json."""
    try:
        cases, sources = describe()
    except (CaseFailure, OSError) as unreadable:
        print(f"engine/bench.sh: cannot read the case table: {unreadable}", file=sys.stderr)
        return 2
    known = tuple(sorted(cases))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", choices=known, default=known)
    parser.add_argument("--list", action="store_true", dest="list_cases")
    parser.add_argument(
        "--counter-only",
        action="store_true",
        help="skip perf; inferences alone decide",
    )
    parser.add_argument("--update-baseline", action="store_true")
    arguments = parser.parse_args(argv)
    if arguments.list_cases:
        print("\n".join(known))
        return 0
    selected = list(arguments.names)

    instructions = not arguments.counter_only
    if instructions and shutil.which("perf") is None:
        print("note: perf not found, instruction pins will not be checked")
        instructions = False

    baseline = BenchmarkBaseline(BASELINE, update=arguments.update_baseline)
    # A refusal is not a regression and does not get a regression's exit code.
    # Reaching the cases at all after the stamp differs would report the
    # configuration's cost as the engine's, which is the whole reason the stamp
    # exists: the C reader alone moves the parse case from 152 inferences to
    # 5,065,952.
    try:
        # The generating boot is a different workload from the loading one, and
        # every case here starts by loading the engine.
        _run(_goal("boot"))
        baseline.observe_configuration(stamp(sources))
    except AssertionError as refusal:
        print(f"engine/bench.sh: {refusal}", file=sys.stderr)
        print(
            "engine/bench.sh: REFUSING to compare across configurations rather "
            "than reporting a move the engine did not make",
            file=sys.stderr,
        )
        return 2
    except (CaseFailure, OSError) as unusable:
        print(f"engine/bench.sh: cannot measure this tree: {unusable}", file=sys.stderr)
        return 2

    failures: list[str] = []
    for name in selected:
        unit, operations = cases[name]
        try:
            print(observe(baseline, name, unit, operations, instructions=instructions))
        # AssertionError is how the harness reports a band; the rest are how the
        # INSTRUMENT reports that it could not take a reading. Both have to land
        # here rather than unwind: a failure in one case that ends the run hides
        # every case after it, which is the exact shape check_instructions.py
        # records as having masked four stale pins for days.
        except (
            AssertionError,
            CaseFailure,
            FileNotFoundError,
            KeyError,
            RuntimeError,
            TimeoutError,
            ValueError,
        ) as failure:
            failures.append(f"{name}: {failure}")
            print(f"{name}: FAILED")
    baseline.finish()
    if arguments.update_baseline:
        print(f"re-pinned {len(selected)} case(s) in {BASELINE}")
    if failures:
        for message in failures:
            print(message, file=sys.stderr)
        print(f"{len(failures)} of {len(selected)} case(s) failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
