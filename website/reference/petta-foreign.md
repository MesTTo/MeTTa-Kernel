# `petta.foreign`

Source: `python/petta/foreign.py`.

> Purpose: spaces implemented in Python. A SpaceProvider answers match, add,
> remove and enumeration for a named space whose atoms live wherever the
> provider keeps them: a SQL table, a dataframe, a dict, a service. The engine
> unifies patterns against what the provider yields, so a provider may
> over-approximate its filtering and stay sound; pushing bound parts of the
> pattern down into the backend is the performance lever, never a correctness
> requirement.
> Guarantees:
>   - capabilities derive from implemented narrow protocols and unknown
>     operations are refused [tested test_capabilities_follow_implemented_methods]
>   - providers may decline one concrete request through should_run before its
>     operation executes [tested test_provider_can_decline_one_request]
>   - provider registration changes Python state only after the engine accepts
>     the same change [tested test_provider_registration_is_transactional]
> Guarded by:
>   - _PROVIDER_LOCK serializes library registration and provider lookups
>     [tested test_provider_registration_is_transactional]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Matcher`

```python
class Matcher(Protocol):
```

No docstring is defined.

### `Matcher.match`

```python
def match(self, pattern: Atom) -> Iterator[Any]:
```

No docstring is defined.

## `Enumerable`

```python
class Enumerable(Protocol):
```

No docstring is defined.

### `Enumerable.atoms`

```python
def atoms(self) -> Iterator[Any]:
```

No docstring is defined.

## `Adder`

```python
class Adder(Protocol):
```

No docstring is defined.

### `Adder.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

## `Remover`

```python
class Remover(Protocol):
```

No docstring is defined.

### `Remover.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.

## `Clearer`

```python
class Clearer(Protocol):
```

No docstring is defined.

### `Clearer.clear`

```python
def clear(self) -> None:
```

No docstring is defined.

## `SpaceProvider`

```python
class SpaceProvider:
```

> One space backed by Python. Implement only what the backend has.
>
> match(pattern) yields candidate atoms; the pattern's variables arrive as
> Var atoms, and bound positions as ground atoms, which is what a backend
> turns into its own filter (a WHERE clause, a mask). Yielding every atom
> is always correct; yielding fewer than match is never allowed to be.
> An Enumerable provider need not implement Matcher: enumeration is the
> correct default candidate set. Missing methods are unsupported, never
> assumed present.

### `SpaceProvider.can_run`

```python
def can_run(self, capability: str, /, **request: Any) -> bool:
```

> Whether this provider implements the operation for this request.

### `SpaceProvider.should_run`

```python
def should_run(self, _capability: str, /, **_request: Any) -> bool:
```

> Policy hook: decline a supported concrete request before execution.

### `SpaceProvider.supports`

```python
def supports(self, capability: str, /, **request: Any) -> bool:
```

> Compatibility spelling for can_run().

## `has_provider`

```python
def has_provider(space: str) -> bool:
```

> Whether a Python provider currently owns the space.

## `require_capability`

```python
def require_capability(
    space: str,
    capability: str,
    operation: str,
    **request: Any,
) -> None:
```

> Refuse an operation before it creates partial state or enters Prolog.

## `register_provider`

```python
def register_provider(runtime, name: str, provider: SpaceProvider) -> None:
```

No docstring is defined.

## `unregister_provider`

```python
def unregister_provider(runtime, name: str) -> None:
```

No docstring is defined.

## `foreign_match`

```python
def foreign_match(space: str, pattern_wire: list):
```

> Generator the shim's py_iter enumerates: candidate atoms, encoded.

## `foreign_atoms`

```python
def foreign_atoms(space: str):
```

No docstring is defined.

## `foreign_add`

```python
def foreign_add(space: str, atom_wire: list) -> bool:
```

No docstring is defined.

## `foreign_remove`

```python
def foreign_remove(space: str, atom_wire: list) -> bool:
```

No docstring is defined.

## `foreign_clear`

```python
def foreign_clear(space: str) -> bool:
```

No docstring is defined.
