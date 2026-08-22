# `petta.paths`

Source: `bindings/python/petta/paths.py`.

> Purpose: build cycle-safe lazy structural paths for query patterns.
> Guarantees:
>   - a path keeps its root opaque and reads only the named attributes or keys
>     after the engine has matched that root [tested:
>     test_a_path_reaches_into_a_handle_without_converting_it;
>     commit=WORKTREE]
>   - repeated object identities terminate the path as a non-match [tested:
>     test_a_path_reaches_into_a_handle_without_converting_it;
>     commit=WORKTREE]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

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
>     m.query(S.manager(S.ada, path("profile", "age", to=V.age)))
