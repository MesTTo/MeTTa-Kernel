# `petta.aio`

Source: `python/petta/aio.py`.

> Purpose: the same engine without blocking an event loop. AsyncMeTTa
> proxies a MeTTa space onto one dedicated worker thread that holds an
> attached Prolog engine, the aiosqlite architecture (one thread per
> connection, a request queue, results delivered back through the loop), so
> awaiting a long query lets every other coroutine keep running. One engine
> per process stays the rule: calls are serialized, and the win is a live
> event loop, never parallel evaluation.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `AsyncMeTTa`

```python
class AsyncMeTTa:
```

> A space whose calls are awaited instead of blocking.
>
>     async with petta.aio.connect() as am:
>         await am.add(S.edge(1, 2))
>         rows = await am.query(S.edge(V.a, V.b))
>
> Every method mirrors MeTTa's method of the same name, bounds and
> capture included; call(fn) reaches anything not mirrored by running
> fn(m) on the engine's thread. The worker thread attaches a Prolog
> engine once, so the fast calling convention holds there, the same
> pattern remote.serve() runs.

### `AsyncMeTTa.space_name`

```python
def space_name(self) -> str:
```

No docstring is defined.

### `AsyncMeTTa.metta`

```python
def metta(self) -> MeTTa:
```

> The wrapped synchronous space, for engine-thread work via call().

### `AsyncMeTTa.start`

```python
async def start(self) -> "AsyncMeTTa":
```

> Start the engine thread; connect() and `async with` call this.

### `AsyncMeTTa.call`

```python
async def call(self, fn: Callable[[MeTTa], Any]) -> Any:
```

> Run fn(m) on the engine's thread and await its result: the
> escape hatch to the entire synchronous surface, subscriptions,
> derivations, stats blocks and all.

### `AsyncMeTTa.run`

```python
async def run(self, source: str, using: dict | None = None, **bounds) -> Any:
```

No docstring is defined.

### `AsyncMeTTa.load`

```python
async def load(self, path: str) -> list:
```

No docstring is defined.

### `AsyncMeTTa.save`

```python
async def save(self, path: str) -> int:
```

No docstring is defined.

### `AsyncMeTTa.add`

```python
async def add(self, *atoms: Any) -> None:
```

No docstring is defined.

### `AsyncMeTTa.add_table`

```python
async def add_table(self, head: Any, data: Any) -> int:
```

No docstring is defined.

### `AsyncMeTTa.remove`

```python
async def remove(self, atom: Any) -> bool:
```

No docstring is defined.

### `AsyncMeTTa.clear`

```python
async def clear(self) -> None:
```

No docstring is defined.

### `AsyncMeTTa.count`

```python
async def count(self) -> int:
```

No docstring is defined.

### `AsyncMeTTa.atoms`

```python
async def atoms(self) -> list:
```

No docstring is defined.

### `AsyncMeTTa.query`

```python
async def query(self, *patterns: Any, **options) -> Rows:
```

No docstring is defined.

### `AsyncMeTTa.eval`

```python
async def eval(self, target: Any, **bounds) -> Any:
```

No docstring is defined.

### `AsyncMeTTa.value`

```python
async def value(self, target: Any, **bounds) -> Any:
```

No docstring is defined.

### `AsyncMeTTa.space`

```python
async def space(self, name: str) -> "AsyncMeTTa":
```

> Another space through the same engine thread. The connection
> owns the thread; spaces borrow it, so closing a borrowed space is
> a no-op and closing the owner ends them all.

### `AsyncMeTTa.aclose`

```python
async def aclose(self) -> None:
```

> Stop accepting, let queued work finish, and end the thread.

## `connect`

```python
async def connect(space: str = "&self", *, metta: MeTTa | None = None) -> AsyncMeTTa:
```

> An AsyncMeTTa with its engine thread already running, aiosqlite's
> own naming for the entry point.
