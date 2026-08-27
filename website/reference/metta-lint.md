# `metta.lint`

Source: `extensions/python/metta/lint.py`.

> Purpose: expose diagnostics for declarations, equations, and calls.
> Guarantees:
>   - public Finding records retain the metta.lint pickle identity [tested:
>     test_finding_retains_public_pickle_identity; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - a lint invocation records and applies exact ``# metta: ok(kind)`` source
>     intents without changing the space or executing findings [tested:
>     test_a_named_metta_ok_intent_suppresses_only_its_bound_rule; commit=acb40f1912f131ae088083d1af29b4b283019bea]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `lint`

```python
def lint(space) -> list[Finding]:
```

> Diagnose a space and return an empty list when no check fires.
>
> One of nine observability doors, the one for the silently-wrong
> class; rows.why() explains one empty answer, and the guide's
> observability page maps the family.

## `lint_file`

```python
def lint_file(path: str | os.PathLike[str], *, m=None) -> list[Finding]:
```

> Diagnose one source file, each finding anchored to its line.
>
> The file loads into a scratch space and lint() runs there; every
> finding whose atom alpha-matches a top-level form then carries
> {"file", "line", "column"} in its payload, recovered exactly from
> the reader's own verbatim form texts, so a tool prints path:line
> without the engine ever tracking positions on its hot path. A
> finding about an atom no single form wrote, or one a form computed,
> stays unanchored rather than guessed.
