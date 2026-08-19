# Developing PeTTa

Run commands in this guide from the repository root unless a command starts
with `cd python`.

## Python environment

PeTTa requires Python 3.11 or newer, SWI-Prolog 9.3 or newer, and a
`janus_swi` build linked against the installed SWI-Prolog library. Install the
locked development environment with:

```sh
uv sync --locked --extra checks
```

On the maintained development workstation, use this interpreter:

```sh
PY=/path/to/your/venv/bin/python
```

It is the only local interpreter with `janus_swi` linked against the installed
SWI-Prolog 10 library. The published wheel currently links `libswipl.so.9`, so
a fresh local virtual environment cannot load it. Build or copy `janus_swi`
against the installed SWI-Prolog before treating another local interpreter as
test evidence. On other systems, set `PY` to the interpreter whose
`import janus_swi` succeeds.

Install the working tree for editable imports when required:

```sh
"$PY" -m pip install -e ".[checks]"
```

## Gates and tests

The blocking gate is:

```sh
CHECK_PY="$PY" GATE_ONLY=1 sh check.sh
```

Run the full gate and analysis report with `CHECK_PY="$PY" sh check.sh`.
Pass check names to run a subset, for example:

```sh
CHECK_PY="$PY" sh check.sh ruff mypy ty
```

`GATE` failures make `check.sh` fail. `REPORT` findings are printed and remain
non-blocking only while their recorded backlog is being removed. A clean
REPORT check belongs in the GATE tier.

Run the Python suite directly with the repository root and configuration made
explicit:

```sh
"$PY" -m pytest python/tests/ -q --rootdir=python -c python/pyproject.toml
```

The gate runs test files in separate worker processes because each process
owns one engine. Keep all tests from one file in the same worker when adding
parallel test configuration. Optional integrations must use
`pytest.importorskip()` so the minimum dependency environment skips them at
module collection.

## Python performance measurements

`python/bench.py` is the benchmark entry point. It runs each selected case in
a fresh process. The harness uses untimed setup and teardown for every round,
performs warmup rounds, and compares committed counters before wall results.

```sh
cd python
"$PY" bench.py --list
"$PY" bench.py --counter-only query-2k-rows wire-codec
```

Engine-backed cases are decided by the minimum of three
`MeTTa.stats().inferences` samples. Engine-free cases are decided by the
minimum of three retired instruction samples:

```sh
cd python
"$PY" -m benchmarks.check_instructions
```

The instruction check runs `perf stat -e instructions:u` around only the
workload. It hard-errors if `perf`, event permission, control pipes, or output
parsing fail. Do not substitute elapsed time for either deciding counter.
Short wall measurements move with scheduler load and CPU frequency. They are
advisory and can be recorded separately:

```sh
cd python
"$PY" bench.py query-2k-rows --json benchmarks/local.json
"$PY" bench.py query-2k-rows --compare-wall
```

Update committed baselines only after reviewing the workload and recording at
least three before and after counter samples:

```sh
cd python
"$PY" bench.py query-2k-rows --update-baseline
"$PY" -m benchmarks.check_instructions wire-codec --update
```

Sibling packages should import `BenchmarkBaseline`, `benchmark_case`,
`count_atoms`, and `measure_instructions` from `petta.testing`. Do not copy the
harness into another repository.

For a focused engine profile, use `MeTTa.profile()`:

```python
groups, profile = metta.profile("!(query-expression)")
print(profile.samples, profile.ticks, profile.top(10))
```

For a Python-driven block, use the same inference counter directly:

```python
with metta.stats() as stats:
    rows = metta.query(pattern)
print(stats.inferences)
```

A performance change must include a fixed workload, its unit and operation
count, a minimum of three before and after deciding-counter samples, and a
regression test or committed baseline. Wall time may accompany those results
but cannot decide the claim.

## Engine contributor tests

The engine-side build, PlUnit, shell regression, and measurement
instructions live in `tests/prolog/README.md`, which is in this tree.
`check.sh` remains the authoritative list of engine-side gate commands.

## Change requirements

Every behavior change carries a regression test in the matching tier and
updates its public documentation in the same commit. Reproduce a defect before
changing it. Keep commits independently buildable. A change is ready only when
the direct relevant tests and `GATE_ONLY=1 sh check.sh` both pass with the
intended interpreter.
