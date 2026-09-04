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
