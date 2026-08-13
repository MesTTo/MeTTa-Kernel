# `petta.foreign`

Source: `python/petta/foreign.py`.

> Purpose: spaces implemented in Python. A SpaceProvider answers match, add,
> remove and enumeration for a named space whose atoms live wherever the
> provider keeps them: a SQL table, a dataframe, a dict, a service. The engine
> unifies patterns against what the provider yields, so a provider may
> over-approximate its filtering and stay sound; pushing bound parts of the
> pattern down into the backend is the performance lever, never a correctness
> requirement.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `SpaceProvider`

```python
class SpaceProvider:
```

> One space backed by Python. Subclass and override what the backend has.
>
> match(pattern) yields candidate atoms; the pattern's variables arrive as
> Var atoms, and bound positions as ground atoms, which is what a backend
> turns into its own filter (a WHERE clause, a mask). Yielding every atom
> is always correct; yielding fewer than match is never allowed to be.
> A provider without add/remove is read-only, and the engine's write
> answers a clear error instead of pretending.

### `SpaceProvider.match`

```python
def match(self, pattern: Atom) -> Iterator[Any]:
```

> Candidates for a pattern; the default enumerates everything.

### `SpaceProvider.atoms`

```python
def atoms(self) -> Iterator[Any]:
```

No docstring is defined.

### `SpaceProvider.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

### `SpaceProvider.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.

### `SpaceProvider.clear`

```python
def clear(self) -> None:
```

No docstring is defined.

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
