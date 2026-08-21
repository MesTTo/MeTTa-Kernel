# Prolog engine development

The engine under `engine/` runs directly in SWI-Prolog. A pure Prolog run needs no
build step:

    swipl --stack_limit=8g -q -s engine/main.pl -- examples/basics/fib.metta silent

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

    /path/to/your/venv/bin/python

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

`sh check.sh ciao-grade` loads the unchanged engine and the external
`tests/prolog/ciao_grade.pl` side file, applies packaged runtime checks to the
four removal and translation funnels, and requires its valid smoke to collect
zero `assrchk/1` findings. It uses three external development packs:
`assertions@0.0.1`, `rtchecks@0.0.1`, and `xlibrary@0.0.2`. Each pack carries
the Simplified BSD license. Their reviewed immutable revisions are
`4e4244c77a92bb84d1f75fd636b95625d04923bf`,
`be9f11ce1c3d85fae6dbb3653ccfeb2b37b27f6d`, and
`ce589b56dbfa9f7aa39384156d441962b8bb3910`, respectively. The
`ciao@0.0.1` dialect pack is neither copied nor used because its immutable
`865e19fda2a732d841645e497135a12cd9c7ccab` tree contains no license file.
The named planted test proves the collector reports a bad call as data:

    cd tests/prolog
    swipl -q -g "run_tests(ciao_grade:test_the_ciao_grade_collects_a_planted_assertion_violation_as_data),halt" ciao_grade.plt

None of those five SWI checks reports UNREACHABILITY, so a predicate defined
and never called was invisible to all of them, the way it was to `vulture` and
`jscpd`, which read only Python. `tests/prolog/reachability.pl` answers that
question: it walks every clause under `engine/`, `lib/`, `backends/`, `backends/mork/mork_ffi/`
and `bindings/python/petta/` with SWI's own `prolog_walk_code/1`, adds one probe clause
per directive, adds an edge for every goal the engine BUILDS as a term rather
than calls, and reports what no root reaches.

    cd tests/prolog
    swipl -q -g reachability_report -t 'halt(0)' reachability.pl
    swipl -q --on-error=status -g reachability_selftest -t 'halt(0)' reachability.pl

The roots are read as data and each one is written down in the file's header:
`arity/2` for a name MeTTa can call, a `multifile` declaration for a seam,
the goals of a load-time directive, and a name appearing in a string literal
in `bindings/python/petta/*.py` for an entry point Python reaches across janus. Tests
are deliberately neither definitions nor callers, so a predicate only a test
names is reported and marked `[tests]`.

The report is a REPORT lane and its findings are a burn-down list. The gate is
the second entry point: `reachability_selftest` writes a fixture of nine
planted predicates to a temporary directory, one per door, three of which must
be REPORTED, and fails naming the door that stopped firing. Run it after
changing anything the analysis reads.

`tests/prolog/translator_confluence.pl` answers a different question again:
whether the COMPILE-TIME rule set terminates, and whether it is confluent.
`add-translator-rule!` registers a NAME; the rules are the space's own
`(= Lhs Rhs)` atoms rooted at one of those names, plus every equation their
right-hand sides reach, because a translator rule's body runs while the program
is being compiled. Two libraries registering overlapping rules is unchecked
today: with `(= (m2 a) (quote one))` written before `(= (m2 $x) (quote two))`
the program answers `one`, and with the two lines swapped it answers `two`.

    cd tests/prolog
    swipl -q --on-error=status -g translator_confluence_report -t 'halt(0)' translator_confluence.pl
    swipl -q --on-error=status -g translator_confluence_selftest -t 'halt(0)' translator_confluence.pl
    swipl -q --on-error=status -g translator_confluence_main -t 'halt(0)' translator_confluence.pl -- FILE.metta

The report names each overlapping pair, the position they overlap at and what
each rule gives, and it states the fragment its verdict is worth in: confluence
is decidable for TERMINATING rewrite systems, and today's translator rules are
unconditional, so the rule set sits inside that fragment. A guarded rule would
be a conditional rule and would take it back out.

Termination is reported first because it is that fragment's precondition, and
it comes back ESTABLISHED with the route that decided it, or as a NAMED
failure. There is no third answer. The route is Nishida and Vidal's: declare
which arguments of the entry are ground, infer the rest through the call graph,
filter every possibly-variable argument away, and hand the result to a
termination method for rewriting. `engine/narrowing.pl` implements it,
`engine/trs.pl` is the rewriting library underneath (an adaptation of Markus
Triska's public-domain trs.pl), `tests/prolog/trs.plt` and
`tests/prolog/narrowing.plt` cover both, and
`bindings/python/tests/test_critical_pair_oracle.py` runs the critical-pair enumerator
against the kernel-checked one in LeaTTa's `MeTTaILProofs/CPExecutable.lean`.

WHAT EACH HALF COVERS: the confluence half covers REWRITING and the termination
half covers NARROWING. A critical pair is an overlap between two rules of a
rewrite relation, and it reaches this rule set because a rule's head is MATCHED
against its call, on a copy and with a `subsumes_term/2` re-check. Termination
is asked of a wider set, one closed over the equations the rule bodies reach,
and a body is EVALUATED while the program compiles, which instantiates.
Termination of narrowing does not follow from termination of rewriting, which
is why the route above exists and why the two halves are not interchangeable.

Run all PlUnit files directly with:

    cd tests/prolog
    for suite in *.plt; do
        swipl -g "set_test_options([format(log)]), run_tests" -t halt "$suite" || exit
    done

Run one suite while working on it:

    cd tests/prolog
    swipl -g "set_test_options([format(log)]), run_tests" -t halt translator.plt

Suites consult `../../engine/metta.pl`, not `engine/main.pl`. `main.pl` owns the CLI
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

    /path/to/python -m pytest bindings/python/tests/ -q --rootdir=python -c bindings/python/pyproject.toml

`sh test.sh` runs the self-checking MeTTa examples (the corpus size is pinned in `examples/README.md`). It uses each process
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

## Every clause says when it applies

A clause of an engine predicate that a compiled MeTTa body can call must be
true only when it is meant to fire, on its own, without leaning on a cut in the
clause above it. The derivation walker is why: `m.derivation(...)` proves a
goal by enumerating `clause/3` and calling each body through `call/1`, where a
cut inside one body prunes nothing outside it, so a clause guarded only by an
earlier cut fires on every walk.

The failure does not look like a wrong answer. A refusal clause added to
`match/4` without its own guard answered BESIDE the rows a real space gave, an
ancestor rule recursed on the refusal, and the process hung
[reproduced 2026-08-20, `bindings/python/tests/test_derivation.py` and
`bindings/python/tests/test_space_operation_errors.py::test_a_proof_over_a_match_does_not_carry_the_refusal`].

Cuts still belong where they pay: keep the cut for ordinary execution and
repeat its condition in the clauses below it. `match/4` reads
`atom(Space), native_storage_module_cache(Space, Module), !` and its refusal
clause reads `\+ petta_space_name(Space)`, so evaluation commits on the cut and
a proof walk still reaches one answer.

## Change requirements

A correctness fix carries a reproducer in the matching PlUnit, shell, or
differential tier. A performance fix also carries the counter workload and its
before-and-after result. Run the focused test during development, then run
`GATE_ONLY=1 sh check.sh` before committing. Keep failures loud. Do not catch an
error only to return partial state or an empty answer.
