# Translator-rule module ownership fix

Purpose: record and verify the implementation that makes translator-rule
registry scope agree with the module that owns each rule body.

Evidence snapshot: [tested: GATE_ONLY=1 sh check.sh; commit=d1318d20b5d89d33079c49d0e94aa29e12685664].

## Outcome

Translator rules remain global, matching upstream PeTTa. The canonical registry
row is now `translator_rule(Name, Declarations, HomeModule)`. Registration reads
`current_metta_module/1` once and stores that module. Translation reads the
three fields in one indexed registry lookup and calls the hook as
`HomeModule:HookCall`.

The release path now retires registrations owned by a dying module before that
module is cleared. Support repair skips recompilation only for functions in the
exact module being released. A dependent in any live module is still repaired.
This closes the executed-call-site teardown failure without disabling
translator rules during teardown and without hiding a missing body.

The same registry/body split also caused a named-space definition of a prelude
translator-rule name to retain the global prelude registration. Function
registration now withdraws that prelude registration from every execution
module, so CLI, Python, and Node all give the ordinary function reading.

No exception is caught in `apply_translator_rule_dl/7`. If a canonical registry
row points to a body that does not exist, the engine still raises. The change
removes stale or module-blind registry claims instead of degrading a failed
translator rewrite into ordinary dispatch.

## Design

### Global name, explicit body home

Upstream commit `43705f5d9ff8958ffe7f0aa6777fb8477f2401f2` has one global
`translator_rule/1` registry in `../PeTTa-base/src/metta.pl:318-322` and invokes
the hook unqualified in `../PeTTa-base/src/translator.pl:117-132`. Upstream has
one execution module, so a global registry necessarily denotes a globally
resolvable body. This fork keeps that meaning: register a translator rule in
any space, then compile it from any space.

The local template is the function catalogue in
`engine/metta/registration.pl`. `fun/1` is the global compile-time fact and
`fun_in/2` records where clauses live. `translator_rule/2` previously supplied
only the first half. `translator_rule/3` now carries both meanings atomically.

This is recognisably the same shape as the function solution, with one useful
simplification. Functions may be locally shadowed, inherited, shared through
`&self`, or built in, so `fun_here_in/2` must walk that resolution order. A
translator-rule name has one global semantic identity: registration already
rejects a second declaration that differs from the first. One canonical home
per name is therefore well defined and no parent walk is needed.

`translator_rule/2`, `translator_rule/1`, and the new
`translator_rule_home/2` are read-only projections. Engine application paths
read `/3` directly. There is no compatibility write path for `/2`, as backward
compatibility for internal registry rows was not required.

The requested same-module fallback is represented directly rather than by a
runtime branch. Every accepted registration records a home. When a rule is
registered where it is used, that home is exactly the value
`current_metta_module/1` would have returned at application time. Avoiding a
second lookup is both stricter and cheaper.

### Release lifetime

The non-perturbing trace below confirmed the drop-time path that the audit had
previously marked as a source-reading hypothesis:

```text
JOB8ED apply_rule '$metta_exec:&pyspace_1' pick
1
JOB8ED clear_start '&pyspace_1' '$metta_exec:&pyspace_1'
JOB8ED remove_equation_start '&pyspace_1' pick
JOB8ED before_announce_changed '$metta_exec:&pyspace_1' pick
JOB8ED invalidation_action '$metta_exec:&pyspace_1' 'uses-b'
JOB8ED repair_context immediate
JOB8ED repair_function '$metta_exec:&pyspace_1' 'uses-b'
JOB8ED apply_rule '$metta_exec:&pyspace_1' pick
EngineError: translator:apply_translator_rule_dl/6: Unknown procedure:
  '$metta_exec:&pyspace_1':pick/6
```

The trace instrumented calls with temporary clauses in a detached copy at
`12771f41ae1d566989323ce9220ea05d33172b1b`. It did not ask
`predicate_property/2`, create a local predicate, or otherwise query the hook
through the child module. It confirms the earlier lead: removing `pick` queues
and immediately repairs the compiled `uses-b`, which retranslates while the
global rule row survives but its body has gone.

Recording the home fixes manifestation 1a, but cannot by itself fix 1b. The
home in 1b was already the compiling module and the body was already absent.
The implementation therefore makes a rule registration share its body's
lifetime:

- `with_metta_space_releasing/2` records the exact dying module and retires all
  of its translator registrations before clearing equations.
- `unregister_fun_in/2` retires a live rule after its home loses its last local
  function claim and before dependent repair runs.
- `support_invalidation_action/1` does not enqueue a compiled function in the
  exact dying module. It continues to enqueue live modules, including a
  cross-space user of the disappearing rule.

The boolean `$metta_space_releasing` remains available to the existing
`seam:function_changed/1` guard. The module-valued companion is restored across
nested child release, so a child cleanup cannot cause the parent cleanup to be
mistaken for a live module.

Two broader alternatives were rejected:

- Catching `existence_error` and falling through to ordinary dispatch was
  explicitly refused. It preserves the false global claim and hides the
  resulting inconsistency. The implementation contains no such catch.
- Muting all support repair while any release is active would also suppress a
  live dependent that must be recompiled after its rule disappears. The chosen
  guard is keyed by the exact dying module. The live-dependent regression first
  observes the rewrite, drops the home, then verifies that the surviving call
  site is repaired to ordinary unresolved data.

### Prelude shadowing

The prelude registers each derived form globally. An equation in `&self`
already evicted the associated equation, declarations, ownership marker, and
translator registration. A named-space equation did not, because ordinary
function shadowing needs no global eviction but translator registration does.

`register_fun_in/2` now folds the special case into its existing global
`fun/1` test. A fresh function name pays no translator-registry lookup. A
prelude translator-rule name is already a function, reaches the extra
`prelude_translator_rule/1` check, and invokes the existing complete eviction
door. This preserves the documented user-wins behavior in every execution
module.

## Changed sites

- `engine/translator_rules.pl`: changed the canonical registry from `/2` to
  `/3`; added read projections; recorded the registration module; made
  `forget_translator_rule/1` retract the complete row; added live and bulk
  retirement by home; converted declaration and cost readers to direct `/3`
  reads.
- `engine/translator/lowering.pl`: changed the application helper to
  `apply_translator_rule_dl/7`; its caller reads declarations and home from one
  `/3` row; the helper calls the recorded module and has no error fallback.
- `engine/metta/registration.pl`: retires a translator registration when its
  final owning function is unregistered, before support repair; extends
  prelude translator-rule eviction to named-space definitions.
- `engine/spaces/lifecycle.pl`: gives release an exact module context, retires
  all registrations for that module before clearing it, and restores nested
  release state.
- `engine/filereader.pl`: suppresses support recompilation only for a compiled
  function in the exact dying module.
- `engine/metta.pl`: routes prelude translator-rule removal through
  `forget_translator_rule/1` so every part of the row and the rule gates are
  updated together.
- `engine/metta/effects.pl`, `engine/metta/types.pl`,
  `engine/translator/analysis.pl`, and
  `engine/translator/special_forms.pl`: changed registry reads to canonical
  `/3` rows. These are policy, type, analysis, and special-form readers, not
  hook application sites.
- `tests/prolog/suites/translator/translator.plt`: added the cross-space,
  executed-release, and live-dependent regressions and migrated planted
  registry fixtures to `/3`.
- `tests/prolog/suites/evaluation/prelude.plt`: added named-space prelude-rule
  shadowing coverage.
- `tests/prolog/suites/evaluation/metta.plt`,
  `tests/prolog/suites/host/prolog_interface.plt`,
  `tests/prolog/translator_confluence.pl`, and
  `tests/shell/test_loader_concurrency.sh`: migrated direct test fixtures and
  assertions to `/3` while preserving their prior semantics.
- `tests/prolog/layering.pl`: records the lifecycle to translator-registry
  release dependency.
- `CHANGELOG.md`: documents the user-visible behavior.
- Benchmark baselines and the Python identity example's measured comments were
  repinned to the measured final tree so the repository's executable cost and
  provenance gates describe the implementation they run.

## Deliberately unchanged sites

- `compile_time_rules/5` in `tests/prolog/translator_confluence.pl` still asks
  `translator_rule/1` for the global name set and asks `space_equation/3` for
  equations in the space under analysis. It does not execute a hook and needs
  no home resolution. Only its planted fixture changed arity.
- `install_conjunctive_rule/2` reads `current_metta_module/1` while registering
  the generated equation into the same space. This is a registration-side read
  and is correct.
- `derive_translator_rule_inverse/2` reads `current_metta_module/1` while adding
  and recording the inverse equation in the registering space. This is also a
  registration-side read and is correct.
- The remaining application-side module reads in translator analysis and type
  resolution select equations or declarations visible to the compiling space.
  They do not locate a globally registered hook body and do not share this
  defect.
- Registry scoping was not changed. Making translator rules local would be a
  coherent language change, but it would diverge from upstream rather than fix
  the fork's incomplete global implementation.

A repository-wide search of `translator_rule(` covered all engine, test,
confluence, and shell-fixture readers. No second hook invocation path or other
registry/body split remains. `call(RuleModule:HookCall)` in
`apply_translator_rule_dl/7` is the only execution site.

## Reproductions

The exact Python seat was selected as follows. `REPO` was the current repository
root, and `CHECK_PY` expanded to the project interpreter requested in the audit:

```sh
REPO="$(git rev-parse --show-toplevel)"
CHECK_PY="$(cd "$REPO/../.." && pwd)/.venv-pypetta/bin/python"
export PYTHONPATH="$REPO/extensions/python"
cd "$REPO/ai-tmp/nodeaudit/repro"
```

The engine build was warmed first through `engine/qlf_boot.pl`. Each case then
ran in a separate process using the drivers from `ai-engine-defects.md`.

### 1a: cross-space application

Pre-change tree `12771f41ae1d566989323ce9220ea05d33172b1b`:

```text
metta.errors.EngineError: translator:apply_translator_rule_dl/6:
Unknown procedure: '$metta_exec:&other':pick/6
```

Final worktree:

```text
1
exit 0
```

`flat3.metta` registered `pick` in `&pyspace_1`; `callsite.metta` compiled and
ran it in `&other`.

### 1b: executed call site during release

Pre-change tree:

```text
1
metta.errors.EngineError: translator:apply_translator_rule_dl/6:
Unknown procedure: '$metta_exec:&pyspace_1':pick/6
```

Final worktree:

```text
1
exit 0
```

The first line proves that the rule rewrite executed before `m.close()`. The
clean exit proves release no longer retranslates a dying user through a stale
registry row.

### Controls

`flat2.metta`, whose call site is stored but not executed:

```text
closed
exit 0
```

`flat3.metta`, whose rule has no call site:

```text
closed
exit 0
```

The stronger executed-rewrite control is in the new release regression. It
asserts the printed `1` before release. The live-dependent control produced:

```text
1
home dropped
exit 0
```

and a subsequent call in the surviving space returned the unresolved rule
form rather than calling a missing body:

```text
1
[['(pick (1 2 3) $_1 $_2 $_1 empty)']]
exit 0
```

## Regression tests

The new tests live beside the translator's existing PlUnit coverage in
`tests/prolog/suites/translator/translator.plt`. Following the actual current
suite convention, that file loads `../../../../engine/qlf_boot.pl` and
`../../../../engine/metta.pl`. Focused runs used the repository convention:

```sh
cd tests/prolog
VIRTUAL_ENV=<project-venv> PATH="$VIRTUAL_ENV/bin:$PATH" \
  swipl -g "set_test_options([format(log)]), run_tests" \
        -t halt suites/translator/translator.plt -- extensions
```

The new test file was copied without the implementation into a detached copy
of pre-change tree `12771f41ae1d566989323ce9220ea05d33172b1b`.

Manifestation 1a failed there:

```text
% [1/1] translator_rule_m..r_space_compiles_it .... **FAILED (0.001 sec)
test translator_rule_module_home:
  a_rule_registered_in_one_space_runs_when_another_space_compiles_it:
received error: translator:apply_translator_rule_dl/6: Unknown procedure:
  '$metta_exec:&plunit-tr-cross-other':'plunit-tr-cross-pick'/6
ERROR: 1 test failed
exit 1
```

Manifestation 1b failed there:

```text
% [1/1] translator_rule_m..te_releases_cleanly .... **FAILED (0.002 sec)
test translator_rule_module_home:
  a_space_with_an_executed_translator_callsite_releases_cleanly:
received error: translator:apply_translator_rule_dl/6: Unknown procedure:
  '$metta_exec:&plunit-tr-release':'plunit-tr-release-pick'/6
ERROR: 1 test failed
exit 1
```

The third test verifies the part a blanket release mute would break. It loads
and executes a cross-space user, releases the rule home, asserts that the
global registration is gone, and verifies the live user was recompiled.

All three passed on the changed worktree:

```text
% [1/3] translator_rule_m..r_space_compiles_it ...... passed (0.002 sec)
% [2/3] translator_rule_m..ve_cross_space_user ...... passed (0.001 sec)
% [3/3] translator_rule_m..te_releases_cleanly ...... passed (0.002 sec)
exit 0
```

The full translator suite also passed:

```text
% [193/193] rule_gate_swap:th..fresh_is_idempotent .. passed (0.000 sec)
exit 0
```

The named-space prelude test also failed on the pre-change tree, with the
translator registration still present and the macro reading observable:

```text
Assertion: [+]==[[]]
Assertion: \+translator_rule(union)
Assertion: \+prelude_translator_rule(union)
ERROR: 1 test failed
exit 1
```

It passed with the other four prelude tests on the changed tree. Direct seat
checks then agreed:

```text
CLI:    ()
        ()
Python: [[()], [()]]
Node:   [()]
        [()]
```

Every focused command exited 0.

## Translation-path cost

Both trees were warmed before measurement by loading `engine/qlf_boot.pl`.
Inference counts are deterministic. Wall clock was treated as advisory because
the machine was under load.

The `engine/bench.sh` inference comparison was:

| case | pre-change | changed tree | delta |
|---|---:|---:|---:|
| boot | 534,160 | 534,184 | +24 |
| evaluate | 559,368 | 559,335 | -33 |
| match | 338,002 | 338,002 | 0 |
| match-skew | 210,482 | 210,482 | 0 |
| parse | 152 | 152 | 0 |
| parse-prolog | 3,076,184 | 3,076,184 | 0 |
| translate | 381,697 | 380,972 | **-725** |

The direct registry microbenchmark ran each form 100,000 times:

```text
N=100000 registry2=400002 registry2_plus_current=700002
registry2_plus_home=500002 registry3=400002
exit 0
```

An indexed `translator_rule/3` head costs the same four inferences per
iteration as the old `/2` head. Looking up a companion home costs one more, and
reading `current_metta_module/1` costs three more. Passing the home out of the
same `/3` row therefore adds zero registry cost per rule application and removes
the application-time current-module read. It is the least-cost complete
representation among the measured choices. The file-load translation benchmark
improved by 725 inferences rather than regressing.

Function registration pays one indexed prelude-rule miss for an already-known
non-prelude function. A 1,000-definition source-load probe moved from 233,410
to 234,410 inferences. This is one inference per function registration, not a
cost on `apply_translator_rule_dl/7` or on ordinary expression compilation.

The engine, Python, C, Node, MORK, parity-performance, and twin-identity cost
checks all passed their final baselines. `jscpd` found zero clones across the
15 mapped Prolog files touched by the implementation.

## Full gate

The final worktree command was captured without a pipeline:

```sh
GATE_ONLY=1 sh check.sh > ai-tmp/engine-defect1-job8ed/gate-final-worktree-2.log 2>&1
status=$?
echo "exit $status" >> ai-tmp/engine-defect1-job8ed/gate-final-worktree-2.log
```

Its opening lines identify this job and tree. Its exact summary was:

```text
================ summary ================
GATE   worktree     ok
GATE   build        ok
GATE   shell        ok
GATE   shell-failure ok
GATE   shell-oracle ok
GATE   encoding     ok
GATE   examples     ok
GATE   spec-differential ok
GATE   git-dependency ok
GATE   git-import   ok
GATE   loader-threads ok
GATE   engine-bench ok
GATE   prolog       ok
GATE   ciao-grade   ok
GATE   prolog-static ok
GATE   prolog-reach-selftest ok
GATE   prolog-metatheory ok
GATE   translator-confluence-gate ok
GATE   translator-confluence-selftest ok
GATE   dev-typed-selftest ok
GATE   dev-typed    ok
GATE   engine-integrity ok
GATE   engine-integrity-selftest ok
GATE   cumulative-syntax ok
GATE   cumulative-syntax-selftest ok
GATE   no-autoload  ok
GATE   lib-surface  ok
GATE   layering     ok
GATE   prolog-determinism ok
GATE   plunit       ok
GATE   c-binding    ok
GATE   c-sanitize   ok
GATE   c-bench      ok
GATE   c-install    ok
GATE   mork-seat    ok
GATE   mork-bench   ok
GATE   mork-lint    ok
GATE   node-binding ok
GATE   node-dist    ok
GATE   node-bench   ok
GATE   pytest       ok
GATE   gallery      ok
GATE   benchmarks   ok
GATE   instructions ok
GATE   scaling      ok
GATE   memory-scale-gate ok
GATE   packaged     ok
GATE   parity       ok
GATE   phrasebook   ok
GATE   slotscheck   ok
GATE   vulture      ok
GATE   imports      ok
GATE   imports-selftest ok
GATE   extcost      ok
GATE   ruff         ok
GATE   mypy         ok
GATE   ty           ok
GATE   pylint       ok
GATE   refurb       ok
GATE   bandit       ok
GATE   deptry       ok
GATE   audit        ok
GATE   interrogate  ok
GATE   spec-status-selftest ok
GATE   policy-inventory ok
GATE   policy-inventory-selftest ok
GATE   refusal-grounds ok
GATE   refusal-grounds-selftest ok
GATE   qlf-freshness ok
GATE   qlf-freshness-selftest ok
GATE   petta        ok
GATE   parity-perf  ok
GATE   cetta        ok
GATE   llms         ok
GATE   llms-selftest ok
GATE   evidence     ok
GATE   evidence-selftest ok
GATE   provenance-pin-selftest ok
GATE   reference    ok
GATE   ledger       ok
GATE   aio-mirror   ok
GATE   libdoc       ok
GATE   codec-doc    ok
GATE   vocab-sync   ok
GATE   ruff-drivers ok
GATE   docs         ok
GATE   codespell    ok

all gate checks passed
exit 0
```

The first full attempt found a missing declared layering edge and four newly
written absolute workspace paths; both were corrected and their focused checks
passed. Its two Python serve/boot tests also reported
`Failed: Timeout (>30.0s)` on one xdist worker under load. The unchanged tests
passed together in the gate's xdist shape in 2.57 seconds, and both passed in
the subsequent full gate above. No timeout or test logic was changed.

## Scope left open

Findings 3 through 8 in `ai-engine-defects.md` concern different prelude arity,
parity harness, platform library, Node engine-lifetime, and Node identifier
issues. They were inspected only as needed to keep this change from claiming
their scope. They remain separate work.

An additional provenance audit command found a pre-existing documentation-site
pin outside that checker's source globs:

```text
website/.vitepress/config.ts: 1 pin(s) OUTSIDE the evidence gate's globs, so
nothing reads this file's claims and nothing would ever resolve them; add its
glob to check_evidence_tags.SOURCES
```

The row was already present at the clean base in commit `34c48b5b` and is
unrelated to translator ownership. This change leaves the documentation-site
file and its evidence policy untouched. The required repository gate does not
invoke that optional release audit and passed with its existing policy.

Nothing required by defect 1 was left unverified. The exact Python
reproductions, fail-before regressions, stronger release controls, complete
translator suite, seat checks, cost lanes, and full repository gate all ran.
