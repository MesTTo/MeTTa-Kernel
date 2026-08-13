# `petta.subscribe`

Source: `python/petta/subscribe.py`.

> Purpose: standing queries. A subscription watches one space for atoms
> unifying with a pattern and reacts to every add or removal: with a callback,
> synchronously, inside the write that caused it; without one, by queuing
> events for drain(). This is the actors-and-pub-sub reading of a space: the
> mailbox is the space, the subscription is the standing query that maintains
> itself, and the engine's own write hooks deliver.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Event`

```python
class Event:
```

> One delivery: what happened, where, to which atom, with which
> bindings the pattern took.

## `Subscription`

```python
class Subscription:
```

> One standing query; cancel() ends it. With no callback, events
> queue and drain() empties the queue.

### `Subscription.drain`

```python
def drain(self) -> list[Event]:
```

> Every queued event, oldest first; the queue empties.

### `Subscription.cancel`

```python
def cancel(self) -> None:
```

No docstring is defined.

## `subscribe`

```python
def subscribe(
    runtime,
    space: str,
    pattern: Atom,
    callback: Callable[[Event], None] | None = None,
    on: str = "add",
) -> Subscription:
```

No docstring is defined.

## `atom_added`

```python
def atom_added(space: str, wire: list) -> bool:
```

No docstring is defined.

## `atom_removed`

```python
def atom_removed(space: str, wire: list) -> bool:
```

No docstring is defined.
