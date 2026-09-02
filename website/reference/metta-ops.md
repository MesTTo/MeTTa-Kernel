# `metta.ops`

Source: `extensions/python/metta/ops.py`.

> Registration of Python callables as MeTTa functions. Reads the
> signature for arities (defaults yield several), auto-detects nondeterminism
> (a generator function is one), derives a MeTTa type declaration from the
> annotations, and registers the whole thing with the engine through shim.pl.

The entries below reproduce the source signatures and docstrings.

## `EffectPlan`

```python
class EffectPlan:
```

> Named operations reachable from one target and their lattice join.

## `class_declarations`

```python
def class_declarations(cls: type) -> list[Expression]:
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
    fn: Callable[P, R],
    *,
    name: str | None = None,
    transport: Literal['encoded', 'raw'] = 'encoded',
    effect: EffectClass | str | None = None,
    declarations: Iterable[Atom] = (),
    space: str = _DEFAULT_SPACE,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
) -> Callable[P, R]:
```

> Make fn callable from MeTTa. Returns fn unchanged.
>
> A generator function registers as nondeterministic: each yield is one
> answer, and MeTTa's collapse, superpose and let compose over them. An exact
> tuple yield is a positional relational candidate and an exact dict yield
> is its sparse parameter-name spelling: the engine unifies each row against
> the call, so ground arguments filter and variables bind through the same
> implementation. Use ``Answer(value=...)`` when a generator intentionally
> answers an exact tuple or dict value. Relational rows require encoded
> transport.
> A plain function is deterministic; returning None or raising NotReducible
> answers nothing. Defaults yield one registration per reachable arity; a
> variadic callable names its call forms with arities=[...].
>
> inverse supplies a distinct result-to-arguments implementation for an
> ordinary result-producing operation. It takes the result and returns the
> arguments, as a tuple, or the bare value at arity one; a generator
> enumerates every preimage, and None or NotReducible means there is none. It
> only ever runs when the arguments are not ground and the result is, so a
> forward call never reaches it. A relational tuple/dict generator needs no
> inverse because its one implementation already binds every direction.
>
> Python annotations derive type atoms and Atom parameters receive syntax
> before evaluation. `transport="raw"` derives raw_det/raw_many in the
> operation's `(op ...)` fact. Effect metadata is required; ``effect=`` is
> the canonical input and names the strongest observable capability of the
> operation. Existing effect declaration atoms remain a compatibility input.
> Additional declaration atoms are owned for
> the operation's complete lifecycle: type atoms live in its declaration
> space, while its canonical effect row and other policy atoms live in
> &metta and can be matched there. Only ``pureStructural`` enters the
> compatibility allow-list for tabled or memoized bodies.

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
