# Holding llms.txt to what the doors answer
Goal: make the cheat sheets' return-type claims fail the build when they stop
being true, rather than drifting behind the library.
Constraint: the sheets are compact signature tables mixed with call examples in
the same fenced blocks, so a check has to tell one from the other without a
declared format to lean on.

## 2026-09-04

Tried: comparing documented `kw=value` against the live signature default, the
`DOC105`-shaped half of the problem -> abandoned. A survey over all five sheets
found 28 documented keyword arguments, 23 of them call-example values rather
than declarations (`m.limits(inferences=10_000)` passes 10,000; it is not the
default). Worse, the one stale line is textually indistinguishable from the
correct ones: `m.trace`'s live default is `None`, with the real 10,000 bound
resolved in the body, so no rule separates it from five correct examples.
Rejected: the default check, because the signature does not carry the value it
would need to be compared against. Revisit if defaults stop being resolved in
function bodies.

Confirmed the split against prior art after reaching it: pydoclint checks
return types (`DOC203`) and documents that it deliberately does not read
argument defaults
(https://jsh9.github.io/pydoclint/violation_codes.html).

Tried: comparing the documented `-> Type` against the live annotation as whole
strings -> four false disagreements out of 19, all decoration rather than
drift: a prose tail (`int   (atomic, fsynced)`), a module qualifier
(`_ops_module.EffectPlan`), an omitted parameter (`Answers` for `Answers[Any]`)
and a positional tuple (`(groups, EngineProfile)` for `tuple[...]`).
Decided: compare HEAD names. All four survive it, and the head is the part
carrying the promise. `list` where the live type is `Trace` tells a reader the
result is an ordinary list, which is exactly the claim that hid
`Trace.truncated`.

Found while measuring: `m.trace` had no live return annotation at all, so no
comparison was possible in either direction. `Space.trace` and `Space.lint` are
wrappers that dropped the annotation their implementations carry
(`_trace.trace -> Trace`, `lint.lint -> list[Finding]`). Decided: annotate the
wrappers, which is the root cause of the doc being uncheckable, rather than
teach the checker to infer a return type from an implementation.

Both names reach the mirrors through `aiogen`, which copies annotations
verbatim into `aio.py` and through `MODULE_ALIASES` into `__init__.py`. mypy
named all three unresolved references immediately, so no generator-side import
check was added: the lane that already catches this is the one to rely on.

Decided: `Trace` stays unexported. Every result type is
(`TraceEvent`, `Derivation`, `EffectPlan`, `Answers`, `EngineProfile`), so
exporting one would be the inconsistent move, and the annotation is text under
`from __future__ import annotations` and never needs the name at runtime.

Open: `tests/checks/*.py` and `extensions/python/tools/*.py` are linted by
nothing. `ruff-drivers` covers `engine/`, `extensions/*/` and `examples/ch19-*/`
and excludes both. Measured 2026-09-04: 97 findings in the first, 38 in the
second. The gate's own checkers and generators are the code least well placed
to be ungated.

## 2026-09-04, the context/space door split

A downstream integration reported `metta.arrays.install(m)` failing with
`AttributeError: 'MeTTa' object has no attribute 'is_function'`, and cited the
Python sheet's "most doors exist on both" as the reason it wrote `install(m)`.

Measured: `Space` has 113 public doors, `MeTTa` has 34, and 28 are shared. So
25% exist on both, not most. The 28 are the evaluation and session family
(`run`, `eval`, `match`, `add`, `define`, `op`, `transaction`, `limits`,
`stats`, `trace`) plus the collection protocols; the 85 that are not are
storage and introspection (`atoms`, `type`, `digest`, `is_function`, `arities`,
`builtins`, `space_names`). The split is coherent, only described wrongly.

Rejected: forwarding the 85 doors from the context. `MeTTa` owns runtime
context and `Space` owns storage is a tested guarantee in the package header,
and forwarding would erase the distinction the two classes exist to draw.
Revisit if the context/space split is itself reconsidered.

Decided: refuse loudly with the remedy, from `dir(Space)` rather than a list,
so a door Space grows is covered without an edit. `hasattr` still answers False
and `getattr(m, name, default)` still returns the default, because the refusal
stays an ordinary AttributeError.

Tried: writing it as a plain `def __getattr__(self, name) -> Never` -> mypy
stopped reporting unknown attributes. `reveal_type(m.totally_made_up)` became
`Never` and `x: int = m.atoms` type-checked clean, trading a static error for a
runtime one. Decided: define it under `if not TYPE_CHECKING:`, after which
mypy reports `attr-defined` for both, including the exact `m.atoms` the report
hit.

The repository's ruff gate caught two conventions on the first pass, EM102 and
TRY003 on the raises and B018 on the test's bare attribute read. The local
convention is `msg = ...` then `raise AttributeError(msg)`, which clears both.

## 2026-09-04, the trace run bound

A downstream renderer reported `limits(inferences=)` not bounding `trace`,
evidenced as 0.11s against 0.10s at a hundredfold tighter limit. Wall clock at
that scale is noise on this box, so it was re-measured on the engine's own
counter, where the answer is not marginal: on `!(loop 2000)` under
`inferences=100`, `run` stopped at 1,685 inferences with an
InferenceLimitError and `trace` retired 209,322 and completed.

Cause: `_trace.trace` passed a literal `None` as `_controlled_run`'s limits
argument, so it took the unlimited `rt.apply_must` path and never consulted the
`_SCOPED_LIMITS` ContextVar that `m.limits()` sets.

Surveyed all 18 `_controlled_run` call sites by AST before fixing the one.
Four pass `None`: `metta_py_function_shape` is a metadata read, and the two
cursor opens are inert by construction with their pulls carrying limits at
`_space_execution.py:716` and `_space_objects.py:759`. Only the trace runs the
program, so the fix is one call site rather than a policy change.

Decided: give `trace` the `*, timeout=None, inferences=None` pair every other
evaluating door takes, rather than only reading the ambient scope. `derivation`
is the nearest sibling and already has exactly that shape, and the per-call
kwarg is what `_limits` overrides the scope with.

Control: reverting the limits argument to `None` and clearing `__pycache__`
turns the new test red with `DID NOT RAISE InferenceLimitError`.

## 2026-09-04, the scoped get-doc miss

Reported as "scoped Space.doc misses documentation stored in its receiver",
with one stored row, one unary answer, and an EngineError from `space.doc`.

Four reproduction attempts missed: a plain symbol, a named space, a dotted
name, and each of the four storage paths (`run`, `add`, `+=`, `add(parse)`) all
answered correctly. The trigger is the TYPE. With `(: name (-> Number Number))`
present, `get-doc-single-atom` commits the name to `get-doc-function`, which
matches only `['@doc', Name, Desc, ['@params', _], _]`; a three-part portable
document fails it and the whole branch fails with no fallback, while
`get-doc-atom` has a fallback in the other direction. The reporter's 47
subjects are all arrow-typed callables, which is why it looked space-scoped.

Arbiter: LeaTTa's `stdlib.md` says `get-doc-function` "returns documentation on
a function if it exists or default documentation with no description
otherwise", and its `stdlib_docs_help.metta` conformance test covers the full
shape, the no-type route and a plain typed atom, but not a function-typed name
with a short document. So the arbiter requires only that the helper not fail.

Rejected: making `get-doc-function` answer a default for every input. Two
things forbid it. `get_doc_function_on_a_non_space_answers_nothing` requires it
to fail for a non-space, and `Space.doc` documents and tests that a subject
with NO documentation raises. Revisit if the Python door's raise-on-absent
contract is reconsidered.

Rejected: delegating the short shape to `get-doc-atom`. It answers
`(@kind atom)`, and for an arrow-typed name `function` is what the name IS.

Decided: the arrow branch chooses by the SHAPE of the stored document. The
four-field shape keeps going to `get-doc-function` exactly as the arbiter pins
it; the short shape answers `(@kind function)` with the arrow type and the
description the author wrote, which upstream's default would have dropped.
`formal_doc_atom` stays the only reader, so a non-space still acquires nothing
and multiplicity is preserved.

Control: reverting the branch turns the new plunit test red with
`prelude_docs:get_doc_answers_an_arrow_typed_name_documented_without_parameters:
failed` while the undocumented-name test stays green.

The Python test first used `undocumented` as its never-documented subject and
did not raise: that is engine vocabulary and resolves from the prelude doc
register, which is `get-doc`'s documented fallback rather than a miss.

## 2026-09-04, declarations moving between spaces

Reported as "re-registering a typed operation moves declarations between
spaces", three rows in A before and zero after. Reproduced on the first
attempt with the reporter's exact numbers.

Cause: `REGISTRY` is keyed by name alone because an implementation is
process-global, so registering the same name in space B replaces A's entry, and
`_retire_previous` released `previous.declarations` from `previous.space`. The
`_DECLARATION_REFS` refcount is already keyed by `(space, declaration)`, so the
two spaces' rows were never shared; A's were simply released.

Rejected: releasing only when `previous.space == space`. It fixes the reported
case but leaks on register-A, register-B, register-A: `previous` is then B's
entry, nothing of A's is released, and a changed signature leaves A holding both
signatures' rows.

Decided: the Operation records `holdings`, one `(space, declarations)` entry per
space it has declared into. A registration releases only the entry for the space
it is registering into; `unregister` releases every entry. No special case, and
the four properties hold together: A keeps its rows when B registers, B gets its
own, re-registering in A with a changed signature replaces only A's, and
unregistering clears both.

Control: restoring the whole-set release turns the new test red with
`assert [] == ['(: two-space-op ...']`, which is the reported three-to-zero.

The repository's D205 burn-down caught the first version of the new helper's
docstring: a `# noqa: D205` took the suppression count from 2201 to 2202 and the
ceiling is there to fall, so the docstring was written to comply instead.

## 2026-09-04, an error report that destroyed its own error

Reported as "host exceptions with opaque arguments fail during rendering": an
operation taking `G(object())` and raising `MettaError("clean")` surfaced a
`PrologError` carrying a `swrite/2` complaint and no `clean`.

A four-cell matrix located it exactly. Opaque argument with a succeeding
operation answers normally, plain argument with a raising operation gives
`EngineError: Python MettaError in (probe plain)` with `clean` intact, and only
opaque-plus-raising fails. So the defect is in rendering the CALL, not in
passing the value or in raising.

Cause: `extensions/python/bridge.pl`'s `prolog:message//1` calls
`swrite(Call, CallText)`. `swrite/2` is the round-trip writer and refuses any
value whose printed form would read back as something else, which
`metta_unwritable_symbol/2` documents as covering opaque host values. The throw
escapes the message renderer, so the refusal replaces the error being rendered.
This is the error-handler-that-errors shape, and the general answer is the one
`logging.Handler.handleError` takes: formatting a report has to be total.

Surveyed every `prolog:message//1` and `prolog:error_message//1` clause in the
shipped tree: thirteen call sites across eight files had the same hazard, each
rendering a user-supplied term. Fixing only the reported one would have left
twelve.

Measured before substituting, because these renderings are pinned by tests:
`sdisplay/2` and `swrite/2` produce byte-identical strings for every term
`swrite` can write (`(a b)`, `"text"`, `3.5`, `-0.0`, `Foo`, `()`, `prime?`)
and differ only where `swrite` refuses, where `sdisplay` renders (`(foo 1)`,
`a b`, `inf`). So the substitution changes no existing message.

Control: restoring `swrite` in the bridge clause turns the new test red as
`janus_swi.janus.PrologError: <exception str() failed>`, which is the renderer
failing while rendering the renderer's own failure.

The first scan of message clauses missed two sites in
`engine/spaces/segment_matching.pl` because a COMMENT line ending in a full
stop looked like the end of a clause. A comment-aware rescan found them.

## 2026-09-04, a rollback the library's own mirror did not follow

Reported as "integration installation is not transactional", narrowed by the
reporter to "fact rolls back, operation does not".

First reproduction attempts used `atomic()` and showed neither rolling back.
`atomic()` makes each RUN a committing transaction; `transaction()` is the
all-or-nothing door. With the right door the reporter's numbers reproduce
exactly: fact absent, operation still registered.

It is worse than "still registered". Measured: `registered()` answered True
while `&metta`'s reflection rows were gone, the space's type declarations were
gone, and `!(installed-op 4)` no longer reduced. The mirror claimed an
operation the engine had forgotten, so an installer's own idempotence check
skips reinstalling a name that is dead for the rest of the process.

`transaction()` documents that Python-side state is the caller's to undo, and
that is right for a list appended or a file written. REGISTRY is not that: it
is the library's own mirror of engine state, and no caller can be asked to
repair the library's bookkeeping.

Decided: a nested undo log, the shape a savepoint keeps. A frame records what
REGISTRY held for each name BEFORE the frame changed it, first record wins so a
re-registration inside one transaction cannot overwrite the pre-frame value,
and a completing inner frame hands its records to its parent so an outer
rollback discards inner work. `transaction()` opens a frame; `transactional()`
delegates to it and needs no change.

Control: replacing the frame with a null context turns both new tests red on
`assert "rolled-back-op" not in ops.registered()` and the nested one.

Checked and left alone: `speculative()` does NOT discard a registration, but it
leaves the engine clauses too, so the two agree and there is no split reading.
Whether speculation should cover registration is a separate design question.

A first patch attempt corrupted `registry_undo` itself: the replacement pattern
`    REGISTRY.pop(name, None)` matched inside the new function's own except
block before reaching `unregister`. Anchoring on the neighbouring
`_withdraw_purity` line fixed it, and `ast.parse` caught the damage.

## 2026-09-04, a wait that could never end

Reported as "a spawning call blocks inside a transaction", with
`01-thread_lib.metta` not finishing in 150s where it draws in 10.1.

Reproduced exactly: `(let $f (spawn (inc 41)) (await $f))` answers
`[Grounded(42)]` in 0.00s and blocks past 90s inside `transaction()`.

Isolated in two steps. `spawn` alone inside a transaction returns
`Space('&future-1')` immediately, so the launch is fine and the WAIT is the
problem. Then the visibility A/B: polling the future space every 50ms, the
worker's answer is visible in 0.00s outside a transaction and NEVER inside one
in a full second. A transaction reads the database as of its open, so a write
another thread makes afterwards is invisible for as long as it lasts, which
makes the awaited condition unreachable rather than slow.

Surveyed the other blocking families rather than fixing only `await`.
`space_await` is worse than a hang: with a two-second timeout it answers `(job
1)` outside a transaction and `[]` after the full two seconds inside, reporting
absence for an atom that was written. Channels are NOT affected and are NOT
guarded, measured: `(let $c (channel) (let $_ (send $c hello) (recv $c)))`
answers hello in both places, because a message queue is not database state.

Decided: refuse at the two database-backed funnels, `future_settle_` through
`thread_await` and `space_wait_` for both the await and take modes, using
`current_transaction/1` which is a builtin that fails outside a transaction.
Refusing is the honest answer because the condition cannot be reached, and a
caller waiting on it has no way to learn that.

Control: removing the guard from `thread_await` turns the new test into a
45-second timeout, which is the defect itself.

One full-suite run showed
`test_a_landing_observer_can_await_another_async_future` failing. It passes
alone, passes with its whole chapter, and passes in a repeat full run at load
18.3; the box was carrying another workload at 344% CPU throughout.

## 2026-09-04, naming what the engine wrote

Requested as "nothing published names a generated function", with the reporter
reaching past the published service list into `specializer:ho_specialization/3`
because there was nothing on the list to reach instead.

Reproduced: after `!(twice inc 1)` the space holds
`(= (twice_Spec_[inc] $_ $_) (inc (inc $_)))`, and `(origin-of ...)` answers
`(equation $metta_exec:&pyspace_1)` for that name and for `inc` alike.

Rejected: a separate `(generated? $name)` predicate. `origin-of` already exists
to say where a name came from and its tiers are ordered by AUTHOR, so a
specialization is a tier rather than a second question. One door, one more
face.

Decided: a `specialization` tier above `equation`, carrying the name being
specialized as its detail, so `(origin-of twice_Spec_[inc])` answers
`(specialization twice)`. The reader learns both facts at once, and
`ho_specialization/3` is already exported from the specializer module for
engine/spaces.pl, so nothing new is published to read it.

Control: removing the tier turns the new plunit test red on its assertion.

Two generated artifacts had to follow the library's own doc comment:
`libdoc.py --write` for the libraries page, and the ruff gate caught a
duplicate `EngineError` import in the new concurrency test, which was already
imported further down the same block. That last one had shipped in the
preceding commit because the chapter suite was run before committing and the
gate-completeness lane was not; it is folded back into that commit.

## 2026-09-04, what this pass did not close

Two reported items did not reproduce here, and one is a gap rather than a
defect. Recording the measurements so the next attempt starts from them.

ROLLBACK POISONING. Reported as a rolled-back transaction leaving a later
evaluation far worse than cold, at 1.44s cold against a rolled-back run that
did not finish in 120s. On this tree, with the same workload run three ways and
measured on inferences: no prior run 19,851, a kept run 17,677, a ROLLED BACK
run 17,689. The rolled-back and kept runs are within 0.07% of each other and
both below the cold baseline, which is the first-compile cost. The reporter's
own harness (`ai-tmp/probe_perturb.py`) answers 0.00s for every channel on
every input available here, including the one their finding names, so the work
it timed is not being reached. A reproducing input would settle it.

DERIVATION IN A COPY. Reported as a derivation inside a `Space.copy` slowing
later derivations. Measured, three derivations after each prelude: no prior
derivation-in-copy 14,870 inferences, after a derivation inside a copy 15,214,
after a derivation in the space itself 15,212. In-copy and in-place are within
0.02%. The related channel asymmetry their notes describe, a derivation writing
to the root `&self` while other channels write to the scratch, does not
reproduce either: `eval`, `run` and `derivation` each wrote to the selected
space and none to the root.

MODE-DIRECTED TABLING. A downstream note records that a mode-directed table
over an incremental predicate must itself be declared incremental or it is
never invalidated. That is true of hand-written Prolog and is not a defect
here: `metta_tabling_install_table/3` marks every read `dynamic(... as
incremental)` and declares the table `as (incremental, shared)`, so the MeTTa
door cannot make that mistake. The gap is that the door has no mode-directed
form at all, so a caller wanting `min` answer subsumption drops to raw Prolog
and inherits the obligation. Worth closing by extending `(tabled ...)`, not by
warning about it.

RUFF OVER THE GATE'S OWN CODE. `tests/checks/*.py` and
`extensions/python/tools/*.py` are linted by nothing: `ruff-drivers` covers
`engine/`, `extensions/*/` and `examples/ch19-*/` and excludes both. Measured
2026-09-04 with each file under its own resolved configuration: 97 findings in
the first and 38 in the second, dominated by 50 D205, 24 D103, and 28
TRY003/EM102 sites that the `msg = ...` convention already used elsewhere in
this tree would close. The structural remedy is one line, adding the two globs
to `check_component_python`, and it can only land once the findings are clean.
Deliberately not bundled with this release: it is a large diff in the gate's
own checkers, and a broken checker breaks every lane.

## 2026-09-04, the gate's own code, gated

Supersedes this thread's earlier "RUFF OVER THE GATE'S OWN CODE" note, which
recorded the measurement and deliberately left the work out of the release.
The user asked for all of it, so all 135 findings are closed and the two
directories are gated.

None of the 135 was suppressed to make a lane green. The split, by what the
finding actually was:

- 50 D205, a summary wrapping to a second line. Twelve were a clean first
  sentence and were restructured mechanically; the other 38 needed a summary
  written. The house style decided the approach rather than preference:
  measured, `metta/` carries 347 D205 suppressions across about 1,325
  docstrings, so 74% have a one-line summary and the rest carry one canonical
  reason. Every one of the 38 got the summary.
- 24 D103, a missing docstring, each written from what the function does.
- 28 TRY003/EM102, closed with the `msg = ...` convention this tree already
  uses everywhere else.
- 10 PERF401, converted to `extend`, because `metta/` has zero PERF401
  suppressions: the house answer is to convert.
- 3 D301, r-prefixed AND unescaped in the same edit, so the rendered text is
  unchanged: under an r-string a source `\\|` prints two backslashes.
- 5 FBT003 and 1 FBT001 on `ItemStatus`, closed by naming the fields at every
  construction rather than suppressing.
- The rest one at a time, with the house reason where the house has one.

Tried: a script that rewrote each flagged docstring wholesale -> it flattened
`check_evidence_tags.py`'s module docstring, lists and sub-blocks into one
paragraph. Reverted immediately. The second version touches only the FIRST
paragraph and leaves everything after the docstring's first blank line
byte-identical.

Tried: adding `../../tests/checks` to the burn-down's existing flat path list
-> `metta/__init__.py` reported eight PTH findings that are configured away.
Ruff picks ONE project root per invocation, so naming a path outside
extensions/python moved every file onto the repository config and the package's
own per-file ignore stopped matching. Decided: one invocation per (working
directory, paths) pair, which is what the lanes already do.

Found by extending the audit: `tools/` was already carrying 30 D suppressions,
1 TRY and 2 FBT that no lane linted and no ledger counted, and tests/checks a
further 1 FBT and 2 ARG. The D ceiling moves 2201 -> 2231 and TRY 24 -> 25 to
record them, which is the point of scanning a directory rather than the cost of
this change: nothing was added, 36 pre-existing suppressions simply became
visible.

Also found: a bare `# noqa: ARG005` with no reason, which the canonical-form
half of the audit rejects. It has one now.

## 2026-09-04, the two benchmark rows the gate stopped on

The full gate ran 98 lanes with two failures, both benchmarks. They turned out
to be different things, which is why each needed its own measurement.

BOOT, the C seat. Real. Three identical inference samples at 1,485,362 against
a 1,484,575 pin, and inferences are deterministic, so load is not a reading
here. That pin sees the CONSULT, and engine/ grew by the get-doc arrow branch
in engine/metta/runtime.pl and the message-rendering change across
engine/metta/registration.pl and the four engine/spaces units.

Attributed with one arm per side: engine/ at c5a11c00 reads 1,484,569 and HEAD
reads 1,485,363, three identical samples each way, which puts the whole +794 in
engine/ and leaves the pre-change tree six inferences under the old pin.
Re-pinned inferences only; the instruction minimum sits inside its 0.1% band
and replacing a pin that did not move would lose the better measurement.

Tried first, and wrong: reverting engine/ and measuring straight away. Both
arms read 3.28M, more than double. `git checkout -- engine/` resets source
mtimes, the loaders purge the whole .qlf set, and every boot then recompiles
from source. The arms above rebuild the set with one
`swipl -g true -t halt engine/main.pl` before measuring. Worth recording that
the contaminated arms still differed by +794, the same number, because both sat
in the same regime.

MORK-WINDOW-FLOOR. Not real. 29,404 against a 28,952 pin plus 1%, measured
inside the gate at loadavg 9.52 with every other lane running. Re-measured on a
quieter box: 29,030, 29,020, 29,020 across three consecutive runs, all inside
the band, and the whole mork lane exits 0. The row is the perf window handshake
that bench.py's own docstring says "moves for its own reasons", not a workload,
so 452 instructions on 29,000 is the environment. Nothing re-pinned.
