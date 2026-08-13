# Python functions as MeTTa functions

`@m.op` registers a Python callable as a MeTTa function. The signature sets its arities. A generator function is nondeterministic, with one MeTTa answer per yield.

```python
@m.op
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.op
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

Annotations become declarations in the running space. A `TypeVar` produces a parametric type variable. A `Union` produces one arrow for each member, which the engine reads as superposed declarations. `Callable[[int], int]` maps to a function arrow, and a typed tuple maps element by element.

A dataclass, enum, or plain class in a signature becomes a declared type. Its field annotations determine the constructor declaration. Translation is two-way: enums project to symbols, structured objects can project to constructor expressions, and answers can rebuild Python instances.

Defaults register every accepted positional arity. A Python `None` produces no answer unless the integration wrapper uses the engine's effect convention. Registration can be removed with `m.unregister(name)`.

See [`petta.ops`](../reference/petta-ops) for annotation mapping and registration, and [`petta.convert`](../reference/petta-convert) for object projection and rebuilding.
