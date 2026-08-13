# `petta.lint`

Source: `python/petta/lint.py`.

> Purpose: diagnostics for the silently-wrong class. MeTTa fails open:
> a call to a misspelled function stays an unreduced expression, a call
> with the wrong argument count never matches an equation, and a type
> declaration for a name nothing defines promises a function that cannot
> answer. lint(space) walks the space's declarations and equations against
> the engine's own registries (every builtin and defined function is a
> fun/1 fact, every compiled arity an arity/2 fact) and answers findings,
> each naming its kind, its subject, and the atom it stands on. Checks
> that rest on a heuristic say so in their kind: an expression head that
> is no known function may be data on purpose.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Finding`

```python
class Finding:
```

> One diagnostic: kind names the check, subject the offending name,
> detail says what holds, atom is the evidence.

## `lint`

```python
def lint(space) -> list[Finding]:
```

> Diagnose a space. Answers findings, empty when nothing looks
> wrong; print them or branch on .kind.
