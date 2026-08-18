# Prolog engine development

The engine under `src/` runs directly in SWI-Prolog. A pure Prolog run needs no
build step:

    swipl --stack_limit=8g -q -s src/main.pl -- examples/basics/fib.metta silent

`sh run.sh` adds `backends`, which asks the engine to load every native backend
that is built. There is no mode and no backend is named: the engine globs
`backends/*.pl`, and each of those files decides for itself whether its own
artefact is there. A backend that is not built loads nothing and says nothing,
so a successful run is not evidence that any particular one loaded. Check the
one you care about by using it, which for MORK means adding an atom to
`m.space("&mork")` and querying it back.

Run `sh build.sh` to build the optional MORK and FAISS native backends. That
script clones the pinned MORK and PathMap sources beside this repository, so it
needs network access, Git, Rust, and a C toolchain.

The Python library and differential tests need a Python interpreter with
`janus_swi` linked to the installed SWI version. Select it explicitly when the
default environment does not provide that module:

    CHECK_PY=/path/to/python GATE_ONLY=1 sh check.sh

On the project workstation, the matching interpreter is:

    /home/user/Dev/.venv-pypetta/bin/python

## Test tiers

Run every blocking check from the repository root:

    GATE_ONLY=1 sh check.sh

Run selected Prolog checks by name:

    sh check.sh prolog prolog-static prolog-determinism prolog-reach plunit

The Prolog checks have separate jobs for undefined predicates, SWI source
checks, translation determinism, reachability, and PlUnit.
`tests/prolog/static_checks.pl` compiles representative MeTTa code before
running `list_trivial_fails/0`, `list_redefined/0`, `list_void_declarations/0`,
`list_autoload/0`, and `check/0`. The determinism driver parses every MeTTa
example in a fresh process and rejects a form with two translations.

None of those five SWI checks reports UNREACHABILITY, so a predicate defined
and never called was invisible to all of them, the way it was to `vulture` and
`jscpd`, which read only Python. `tests/prolog/reachability.pl` answers that
question: it walks every clause under `src/`, `lib/`, `backends/`, `mork_ffi/`
and `python/petta/` with SWI's own `prolog_walk_code/1`, adds one probe clause
per directive, adds an edge for every goal the engine BUILDS as a term rather
than calls, and reports what no root reaches.

    cd tests/prolog
    swipl -q -g reachability_report -t 'halt(0)' reachability.pl
    swipl -q --on-error=status -g reachability_selftest -t 'halt(0)' reachability.pl

The roots are read as data and each one is written down in the file's header:
`arity/2` for a name MeTTa can call, a `multifile` declaration for a seam,
the goals of a load-time directive, and a name appearing in a string literal
in `python/petta/*.py` for an entry point Python reaches across janus. Tests
are deliberately neither definitions nor callers, so a predicate only a test
names is reported and marked `[tests]`.

The report is a REPORT lane and its findings are a burn-down list. The gate is
the second entry point: `reachability_selftest` writes a fixture of nine
planted predicates to a temporary directory, one per door, three of which must
be REPORTED, and fails naming the door that stopped firing. Run it after
changing anything the analysis reads.

Run all PlUnit files directly with:

    cd tests/prolog
    for suite in *.plt; do
        swipl -g "set_test_options([format(log)]), run_tests" -t halt "$suite" || exit
    done

Run one suite while working on it:

    cd tests/prolog
    swipl -g "set_test_options([format(log)]), run_tests" -t halt translator.plt

Suites consult `../../src/metta.pl`, not `src/main.pl`. `main.pl` owns the CLI
initialization and would run it during a test. Keep stateful tests isolated with
PlUnit `setup` and `cleanup`. Use `forall` for a contract over a family of
cases, `throws` for an error term, and `blocked` only when the named external
dependency is unavailable. A test that changes global engine predicates must
restore them even when its body fails.

The shell regressions exercise process behavior and multi-process state that a
single PlUnit engine cannot represent:

    sh tests/regression/test_specializer_regressions.sh
    sh tests/regression/test_loader_concurrency.sh
    sh tests/regression/test_git_dependency.sh
    sh tests/test_git_import.sh
    sh tests/test_packaged_cli.sh

The full Python oracle runs from the repository root, not from `python/`:

    /path/to/python -m pytest python/tests/ -q --rootdir=python -c python/pyproject.toml

`sh test.sh` runs the 169 self-checking MeTTa examples. It uses each process
exit status as the verdict and prints the existing assertion lines unchanged.

## Measure engine changes

A performance change needs an unchanged correctness oracle and before-and-after
engine counters. State the exact workload, warm it up, run each side at least
three times in the same process, and report the minimum inference count and CPU
time. Read the counters around only the operation under test:

    statistics(inferences, I0),
    statistics(cputime, C0),
    call(Workload),
    statistics(inferences, I1),
    statistics(cputime, C1),
    Inferences is I1-I0,
    CpuTime is C1-C0.

Inference counts are the primary comparison. CPU time confirms a material
change. Wall clock is advisory because scheduler load makes short samples
unstable. Record `/proc/loadavg` when a wall-clock result matters. Do not claim
a speedup from wall time alone, and do not compare runs that produce different
answers or errors.

The Python API exposes the same engine deltas through `m.stats()` and exposes
SWI profiler samples through `m.profile(source)`. Use the profiler to locate
work, then use `statistics/2` or `m.stats()` for the A/B claim.

`sh bench.sh [BASE_REF]` compares stdout and exit codes against a Git base and
reports min-of-N wall time plus `instructions:u` when `perf` is available. It
is not a blocking gate. Check its printed corpus count and every base-only
warning before treating it as whole-corpus evidence. The topical examples tree
keeps selected root compatibility aliases, so the current root-glob benchmark
does not cover every canonical example.

## Change requirements

A correctness fix carries a reproducer in the matching PlUnit, shell, or
differential tier. A performance fix also carries the counter workload and its
before-and-after result. Run the focused test during development, then run
`GATE_ONLY=1 sh check.sh` before committing. Keep failures loud. Do not catch an
error only to return partial state or an empty answer.
