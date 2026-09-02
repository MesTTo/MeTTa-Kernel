# `metta.paths`

Source: `extensions/python/metta/paths.py`.

> Build cycle-safe lazy structural paths for query patterns.

The entries below reproduce the source signatures and docstrings.

## `Attr`

```python
class Attr:
```

> One attribute step in a lazy path.

## `Key`

```python
class Key:
```

> One subscription step in a lazy path.

## `Path`

```python
class Path:
```

> An immutable sequence of lazy attribute and subscription steps.

### `Path.to`

```python
def to(self, target: Any) -> Expression:
```

> Build the query marker that binds the reached value to *target*.

## `path`

```python
def path(*segments: str | int | Attr | Key, to: Any) -> Expression:
```

> Reach through an opaque query value and bind only the final field.
>
> Strings name attributes. Integers name subscription keys. Use ``Key``
> for a string or other explicit subscription key.
>
>     m.match(S.manager(S.ada, path("profile", "age", to=V.age)))
