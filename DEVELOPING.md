# Developing MeTTa

Run commands in this guide from the repository root unless a command starts
with `cd extensions/python`.

## Python environment

MeTTa requires Python 3.12 or newer, SWI-Prolog 9.3 or newer, and a
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
"$PY" -m pytest extensions/python/tests/ -q --rootdir=extensions/python -c extensions/python/pyproject.toml
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
npm ci --prefix extensions/node
```

That enables the `node-binding` lane and the conformance corpus in
`extensions/python/tests/ch21_another_language_at_the_seam/test_node_binding.py`,
which answers the same cases in the Node binding and in this library and
compares the two.

The binding is TypeScript, and `npm ci` builds it through the package's own
`prepare` script. Both lanes run the BUILD rather than the sources, because a
distro Node is often compiled without type stripping
(`node -p process.config.variables.node_use_amaro` answers false on Debian and
Ubuntu) and a lane that only ran on the official build would not run at all on
the machine that most needs it. `npm run test:source` runs the sources
directly, on a Node that has type stripping and, for `using`, Node 24.

## Performance measurements

### Which counter decides

Pick the counter from where the work happens, not from what is convenient.

| the work | what decides it | why |
|---|---|---|
| inside the engine | `MeTTa.stats().inferences`, min of three | deterministic: five runs of one workload gave the same count while wall clock swung 6.9% |
| no engine involved | retired instructions, min of three | there is no inference to count |
| across a host boundary | instructions AND CPU seconds, paired | foreign code retires NO inferences, so the inference counter is blind |
| anything | not wall clock | it moves with scheduler load and CPU frequency |

The third row is the one people get wrong. A C wire encoder in this tree
measured **526x faster on inferences while CPU time said it was 1.8x slower**,
because the work had moved to where the counter cannot see it. `measure_counters`
runs a command under `perf stat` for several events at once and hands back each
run's counters and its standard output, and
`BenchmarkBaseline.observe_measurement` pins any of them against a declared
two-sided band. The two declarations that exist are `INSTRUCTIONS` and
`CPU_SECONDS`; pair them, and never let inferences decide alone.
`extensions/cmetta/benchmarks/bench.py` is the worked example, and a seat whose
counters are not the default ones passes its own `policies` to
`BenchmarkBaseline` so the committed file states its own rule rather than the
default seat's.

Before trusting any timing at all, check the box is quiet: `cat /proc/loadavg`
and `ps -eo pcpu,pid,comm --sort=-pcpu | head`. Two false results in this
repository, `pln_roman "+97%"` and `permutations "+16%"`, were both a busy
machine rather than a code change.

### Running the benchmarks

`extensions/python/bench.py` is the entry point. It runs each selected case in a
fresh process, with untimed setup and teardown per round, warmup rounds, and
committed counters compared before any wall result.

```sh
cd extensions/python
"$PY" bench.py --list
"$PY" bench.py --counter-only query-2k-rows wire-codec
"$PY" -m benchmarks.check_instructions          # the engine-free cases
```

The instruction check runs `perf stat -e instructions:u` around only the
workload, and hard-errors if `perf`, event permission, control pipes, or output
parsing fail. Wall results are advisory and recorded separately:

```sh
cd extensions/python
"$PY" bench.py query-2k-rows --json benchmarks/local.json
"$PY" bench.py query-2k-rows --compare-wall
```

Update committed baselines only after reviewing the workload and recording at
least three before and after counter samples:

```sh
cd extensions/python
"$PY" bench.py query-2k-rows --update-baseline
"$PY" -m benchmarks.check_instructions wire-codec --update
```

Two benchmarks answer questions about the extension surface specifically.
`benchmarks/extension_cost.py` prices every extension point per call and is a
GATE against `extension-baseline.json`, so its numbers are the ones
`EXTENDING.md` publishes and they cannot drift. `benchmarks/axes.py` prices the
two crossing axes that table does not: which side DRIVES the crossing, and
whether a value crosses transparent or opaque.

```sh
cd extensions/python
"$PY" -m benchmarks.extension_cost            # --update to re-pin
"$PY" -m benchmarks.axes                      # --list for the case names
```

The axes harness drives ONE case per process and refuses a second, because
every `MeTTa()` context shares one engine and registrations are process-wide:
a second case installs its driver's head again, the recursion then leaves a
choice point per level, and a deep drive runs out of stack instead of
measuring anything. That failure looks from outside like a run that never
finishes, so the refusal is loud.

Its published instruction figures are a recorded run and its inference figures
are held by `tests/ch18_performance/test_axes.py`, which asserts an axis's
class AND its published rate: an opaque crossing flat in the value's size, a
transparent one linear and at four inferences an element, and the engine-out
row still agreeing with the gated extension-cost table. Assert both, because a
class alone admits any constant and a rate alone does not notice a change of
class. That split is the general shape to copy. Pin what is deterministic,
record what is not, and say in the document which is which.

Sibling packages should import `BenchmarkBaseline`, `benchmark_case`,
`count_atoms`, `measure_instructions`, and `measure_counters` from
`metta.testing`. Do not copy the harness into another repository.

### Profiling one workload

```python
groups, profile = metta.profile("!(query-expression)")
print(profile.samples, profile.ticks, profile.top(10))
```

`MeTTa.profile()` samples ticks, so profile something that runs. For a
Python-driven block, read the inference counter directly:

```python
with metta.stats() as stats:
    rows = metta.match(pattern)
print(stats.inferences)
```

`m.profile_extension(...)` asks the narrower question: of the functions one
extension registered, which is costing, and whether anything went in wrong.
Its calls and redos are counted exactly, its ticks sampled.
`EXTENDING.md` documents its columns.

### What a performance change must carry

A fixed workload, its unit and operation count, a minimum of three before and
after samples of the DECIDING counter for that workload, and a regression test
or committed baseline. Wall time may accompany those results and cannot decide
the claim. Optimisation targets a complexity class rather than a percentage, so
name the current and target complexity before changing anything and measure at
input sizes large enough to separate them; the axes benchmark is shaped that
way deliberately, sweeping four value sizes because one size would report a
linear cost as a constant factor.

## Engine contributor tests

The engine-side build, PlUnit, shell regression, and measurement
instructions live in `tests/prolog/README.md`, which is in this tree.
`engine/check.sh` is the authoritative list of engine-side gate commands, and
the root `check.sh` sources it, so `sh check.sh <lane>` still names any of them.

## Change requirements

Every behavior change carries a regression test in the matching tier and
updates its public documentation in the same commit. Reproduce a defect before
changing it. Keep commits independently buildable. A change is ready only when
the direct relevant tests and `GATE_ONLY=1 sh check.sh` both pass with the
intended interpreter.

## Evidence tags and their commit pins

A claim in a file's header carries the evidence behind it, and the evidence
names the repository state that produced it: `[tested: <test name>;
commit=<object ID>]`. While you are working, write `commit=WORKTREE`. A commit
cannot contain its own object ID, so the pin is resolved afterwards: commit the
functional, tested state as A, then resolve every placeholder to A's ID in a
provenance-only commit B.

Resolve them with the pass, never by hand:

```sh
python tests/checks/pin_provenance.py --check          # what is still open
python tests/checks/pin_provenance.py --commit <A>     # resolve them to A
```

It rewrites a placeholder only where the file's own grammar says the text is a
comment, and prints every occurrence it declined with the reason. A hand sweep
does not know that difference: one on 2026-08-31 rewrote twelve string
literals, which made the twin re-pin tool start writing a stale object ID into
every twin it priced and silently disabled the release check that refuses
unresolved pins.

`RELEASE=1 python tests/checks/check_evidence_tags.py` is the cut-time check
that no placeholder survived.
