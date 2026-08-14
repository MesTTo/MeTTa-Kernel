# `petta.ops`

Source: `python/petta/ops.py`.

> Purpose: registration of Python callables as MeTTa functions. Reads the
> signature for arities (defaults yield several), auto-detects nondeterminism
> (a generator function is one), derives a MeTTa type declaration from the
> annotations, and registers the whole thing with the engine through shim.pl.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: keyword-argument call forms once PeTTa itself grows a
>     spelling for them; today MeTTa call sites are positional.

The entries below reproduce the source signatures and docstrings.

## `class_declarations`

```python
def class_declarations(cls: type) -> list[Expr]:
```

> The (: ...) atoms that make a class a MeTTa type: the translator's
> own declarations for an Enum, dataclass or NamedTuple, constructor
> arrows and member typings, derived from the class itself. A plain
> class needs NO declaration: its instances already answer the class
> name to get-type through the engine's MRO typing bridge, so emitting
> one would only restate what the engine figures out on its own.

## `register`

```python
def register(
    runtime,
    fn: Callable,
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    space: str = "&self",
    arities: list[int] | None = None,
) -> Callable:
```

> Make fn callable from MeTTa. Returns fn unchanged.
>
> A generator function registers as nondeterministic: each yield is one
> answer, and MeTTa's collapse, superpose and let compose over them. A
> plain function is deterministic; returning None or raising Decline
> answers nothing. Defaults yield one registration per reachable arity;
> a variadic callable names its call forms with arities=[...].

## `unregister`

```python
def unregister(runtime, name: str) -> None:
```

> Remove every arity of a registered operation, and every declaration
> registration added, so nothing keeps describing a function that no
> longer exists.

## `registered`

```python
def registered() -> dict[str, Operation]:
```

> The live registry, name to operation.
