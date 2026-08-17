# `petta.lint`

Source: `python/petta/lint.py`.

> Purpose: expose diagnostics for declarations, equations, and calls.
> Guarantees:
>   - lint() refuses spaces that cannot enumerate their contents [tested
>     test_das_space_refuses_unsupported_composed_operations_at_entry]
>   - public Finding records retain the petta.lint pickle identity [tested
>     test_finding_retains_public_pickle_identity]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

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
