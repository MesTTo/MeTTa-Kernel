# `petta.convert`

Source: `python/petta/convert.py`.

> Purpose: the two-way translator between Python objects and MeTTa. There is
> no single conversion: an Enum wants to become symbols the matcher sees
> through, a model wants to stay one opaque handle, a dataclass wants to be a
> constructor expression whose parts match. So this is four images, a rule for
> choosing, defaults so common types need no registration, and a registry in
> the shape JAX proved with pytrees: a type, a flatten, an unflatten. project()
> turns an object into atoms plus the declarations that type them; build() is
> the missing reverse, rebuilding the object an answer describes.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Projected`

```python
class Projected(NamedTuple):
```

> What a projection produced: the atom, and the declarations typing it.
>
> The declarations are (: ...) atoms; adding them to a space once makes
> every later projection of the same type participate in get-type.

## `register_type`

```python
def register_type(
    cls: type,
    *,
    image: str = "expression",
    to_atom: Callable[[Any], Any] | None = None,
    from_atom: Callable[..., Any] | None = None,
    name: str | None = None,
    fields: tuple[str, ...] = (),
) -> type:
```

> Teach the translator one type, pytree-style.
>
>     petta.convert.register_type(
>         Person,
>         image="expression",
>         to_atom=lambda p: (p.name, p.age),
>         from_atom=lambda name, age: Person(name, age),
>     )
>
> to_atom returns the children (projected recursively); from_atom rebuilds
> from them. A class you own may carry __metta__ and __from_metta__ instead
> and skip registration. image chooses among symbol, expression, handle and
> operations; the docstring of project() states the rule for choosing.
> Returns cls, so it composes as a decorator.

## `ensure_registered`

```python
def ensure_registered(cls: type) -> _Registration:
```

> The registration this class projects through, defaults memoized: an
> Enum, dataclass or NamedTuple gets its default image recorded exactly
> as a first projection would record it; anything else must have been
> registered and says so.

## `project`

```python
def project(value: Any) -> Projected:
```

> One Python value into MeTTa, by the image its type chose.
>
> The rule, from what the object is rather than from taste: match on its
> parts wants a symbol or an expression, since those are what the matcher
> sees through; identity mattering wants a handle, since a copy would lie.
> Defaults: an Enum member becomes its symbol, a dataclass or NamedTuple a
> constructor expression with parts projected recursively, and everything
> unregistered a grounded handle carried whole, unified by identity.
>
> project is the explicit spelling; encode() stays value-preserving
> (a dataclass through encode is a handle). The two intents are different:
> encode carries, project translates.

## `declarations`

```python
def declarations(cls: type) -> tuple[Expr, ...]:
```

> The (: ...) atoms a type contributes, without projecting an instance.
> Constructor arrows carry the field annotations' own types, mapped the
> way registration maps signatures, so a dataclass field typed float
> declares Number rather than %Undefined%; a Union field superposes one
> arrow per member, the checker's own reading of alternatives.

## `build`

```python
def build(atom: Atom, cls: type | None = None) -> Any:
```

> The reverse: rebuild the Python value an atom describes.
>
> A constructor expression rebuilds through its registered from_atom,
> children rebuilt recursively; an Enum symbol rebuilds to the member when
> cls names the Enum; a grounded atom unwraps to its value. Anything else
> is returned as the atom it is, which is the honest answer for structure
> with no registered reverse.
