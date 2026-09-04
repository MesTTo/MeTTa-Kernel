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
