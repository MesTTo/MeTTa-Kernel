# `petta.ops`

Source: `bindings/python/petta/ops.py`.

> Purpose: registration of Python callables as MeTTa functions. Reads the
> signature for arities (defaults yield several), auto-detects nondeterminism
> (a generator function is one), derives a MeTTa type declaration from the
> annotations, and registers the whole thing with the engine through shim.pl.
> Guarantees:
>   - registration distinguishes a MeTTa function name from its declaration
>     space [tested test_public_context_types_are_distinct]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: keyword-argument call forms once PeTTa itself grows a
>     spelling for them; today MeTTa call sites are positional.

The entries below reproduce the source signatures and docstrings.

## `record`

```python
def record(cls: type) -> type:
```

> The declarative-record wiring, attrs' and pydantic's shape: one
> decorator over a dataclass, NamedTuple, or Enum and the class
> converts both ways, its `(: ...)` declarations land in &self, and it
> serves as a cast and query(into=) target.
>
>     @petta.record
>     @dataclass
>     class Edge:
>         a: str
>         b: str
>
> Conversion registers immediately (an unregistrable class fails at
> the decorator, not at first use). The declarations are engine-side
> atoms, so they land the moment an engine exists: immediately when
> one is already booted, or on the first MeTTa construction otherwise,
> which is what lets the decorator run at import time without booting
> anything. Every underlying registration call stays public for the
> classes that need custom shapes.

## `declare_recorded`

```python
def declare_recorded() -> None:
```

> Land every pending recorded class's declarations in &self; a
> no-op when nothing is pending, called by MeTTa construction so a
> decorator that ran before any engine existed still declares.

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
    fn: Callable[_P, _R],
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    space: str = _DEFAULT_SPACE,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
    pure: bool = False,
) -> Callable[_P, _R]:
```

> Make fn callable from MeTTa. Returns fn unchanged.
>
> A generator function registers as nondeterministic: each yield is one
> answer, and MeTTa's collapse, superpose and let compose over them. A
> plain function is deterministic; returning None or raising Decline
> answers nothing. Defaults yield one registration per reachable arity;
> a variadic callable names its call forms with arities=[...].
>
> inverse supplies the BACKWARDS direction, so the operation can stand in a
> pattern position the way a MeTTa equation does. It takes the result and
> returns the arguments, as a tuple, or the bare value at arity one; a
> generator enumerates every preimage, and None or Decline means there is
> none. It only ever runs when the arguments are not ground and the result
> is, so a forward call never reaches it and an operation without one
> compiles exactly what it compiled before.
>
> pure declares that the operation has no effect a cache could hide, which
> is what lets it appear in a `(tabled ...)` or memoized body. It is an
> allow-list on purpose: an operation that does not say so is refused there
> by name, loudly, rather than cached and quietly wrong.

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
