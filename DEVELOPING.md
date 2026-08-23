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

The `ciao-grade` gate applies external `pred` assertions to the live engine's
removal and translation funnels, runs them with the packaged runtime checker,
and requires a valid smoke to produce zero `assrchk/1` findings. Install its
three SWI-Prolog development packs with `pack_install/2`: `assertions@0.0.1`,
`rtchecks@0.0.1`, and `xlibrary@0.0.2`. Each reviewed pack carries the
Simplified BSD license. The reviewed immutable revisions are
`4e4244c77a92bb84d1f75fd636b95625d04923bf`,
`be9f11ce1c3d85fae6dbb3653ccfeb2b37b27f6d`, and
`ce589b56dbfa9f7aa39384156d441962b8bb3910`, respectively. The
`ciao@0.0.1` dialect pack is neither copied nor used because its immutable
`865e19fda2a732d841645e497135a12cd9c7ccab` tree contains no license file.

Run the grade alone with:

```sh
CHECK_PY="$PY" sh check.sh ciao-grade
```

`GATE` failures make `check.sh` fail. `REPORT` findings are printed and remain
non-blocking only while their recorded backlog is being removed. A clean
REPORT check belongs in the GATE tier.

Run the Python suite directly with the repository root and configuration made
explicit:

```sh
"$PY" -m pytest bindings/python/tests/ -q --rootdir=python -c bindings/python/pyproject.toml
```

The gate runs test files in separate worker processes because each process
owns one engine. Keep all tests from one file in the same worker when adding
parallel test configuration. Optional integrations must use
`pytest.importorskip()` so the minimum dependency environment skips them at
module collection.

Two lanes need Node and do not fetch anything themselves, because a gate that
reaches the network fails for reasons that are not the tree. Both say which
step is missing and pass without it, so run this once to have them run for
real:

```sh
npm ci --prefix bindings/node
```

That enables the `node-binding` lane, which is `node --test` over the Node
binding's own suite, and the conformance corpus in
`bindings/python/tests/test_node_binding.py`, which answers the same cases in the Node
binding and in this library and compares the two.

## Python performance measurements

`bindings/python/bench.py` is the benchmark entry point. It runs each selected case in
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
`count_atoms`, and `measure_instructions` from `metta.testing`. Do not copy the
harness into another repository.

For a focused engine profile, use `MeTTa.profile()`:

```python
groups, profile = metta.profile("!(query-expression)")
print(profile.samples, profile.ticks, profile.top(10))
```

For a Python-driven block, use the same inference counter directly:

```python
with metta.stats() as stats:
    rows = metta.match(pattern)
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
