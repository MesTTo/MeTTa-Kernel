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
