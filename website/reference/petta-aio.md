# `petta.aio`

Source: `python/petta/aio.py`.

> Purpose: the same engine without blocking an event loop. AsyncMeTTa
> proxies a MeTTa space onto one dedicated worker thread that holds an
> attached Prolog engine, the aiosqlite architecture (one thread per
> connection, a request queue, results delivered back through the loop), so
> awaiting a long query lets every other coroutine keep running. One engine
> per process stays the rule: calls are serialized, and the win is a live
> event loop, never parallel evaluation. interrupt() stops the running
> evaluation through the engine's own thread_signal, the sqlite3 reading,
> and a cancelled task fires it on its own call, so asyncio timeouts stop
> the engine instead of abandoning it.
> Guarantees:
>   - interrupt_if_running throws the same reserved structured exception as
>     shim resource guards [tested test_aio_interrupt_stops_the_running_evaluation]
>   - close refuses new work, interrupts a running request, rejects queued
>     requests, and bounds the worker join [tested test_aio_close_interrupts_work]
>   - the transition drain discards only a structured interrupt and fails
>     closed on every other error [tested
>     test_aio_drain_only_discards_structured_interrupt]
>   - an abandoned live owner emits ResourceWarning and registered workers
>     detach during interpreter shutdown [tested test_aio_leak_warns_and_stop_joins,
>     test_aio_shutdown_handler_stops_forgotten_workers]
>   - interpreter shutdown attempts every worker and reports all expected
>     stop failures together [tested test_aio_shutdown_handler_attempts_every_worker]
>   - interpreter shutdown without live workers does not initialize the
>     optional engine bridge [tested test_aio_empty_shutdown_does_not_import_janus]
>   - async names and save formats retain the synchronous surface's contextual
>     types [tested test_public_context_types_are_distinct]
>   - async cast preserves a concrete target class as its static return type and
>     keeps the target positional-only [tested
>     test_target_type_overloads_preserve_the_requested_class,
>     test_cast_target_is_positional_only]
> Owns:
>   - each owning AsyncMeTTa owns one daemon worker and its attached Prolog
>     engine until aclose(), stop(), or the atexit handler releases it [tested
>     test_aio_leak_warns_and_stop_joins]
> Guarded by:
>   - _state_lock publishes worker state and engine identity; _transition
>     serializes request completion with interruption [tested
>     test_aio_interrupt_stops_the_running_evaluation]
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
> The exact rule should be: every finite request-response method forwards through the worker. Context managers, cursors, decorators, callback registrations, returned synchronous helper objects, and interactive entry points remain call() or synchronous-surface operations.
>
> call(fn) reaches anything not mirrored by running fn(m) on the engine's
> thread. interrupt() stops the evaluation the
> worker is running right now, and cancelling a waiting task (an
> asyncio timeout included) interrupts its own call, so the engine
> stops working for a listener that is gone.

### `AsyncMeTTa.space_name`

```python
def space_name(self) -> SpaceName:
```

No docstring is defined.

### `AsyncMeTTa.metta`

```python
def metta(self) -> MeTTa:
```

> The wrapped synchronous space, for engine-thread work via call().

### `AsyncMeTTa.start`

```python
async def start(self) -> Self:
```

> Start the engine thread; connect() and `async with` call this.

### `AsyncMeTTa.call`

```python
async def call(self, fn: Callable[[MeTTa], Any]) -> Any:
```

> Run fn(m) on the engine's thread and await its result: the
> escape hatch to the entire synchronous surface, subscriptions,
> derivations, stats blocks and all.

### `AsyncMeTTa.interrupt`

```python
def interrupt(self) -> bool:
```

> Stop the evaluation the worker is running right now; answers
> whether anything was running (idle is a no-op, sqlite3's own
> reading). The stopped call raises petta.Interrupted; whatever it
> completed before the stop, writes included, stands. Callable from
> any thread or task.

### `AsyncMeTTa.run`

```python
async def run(
    self,
    source: str,
    using: dict[str, Any] | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    capture: bool = False,
    atomic: bool = False,
    speculative: bool = False,
) -> Any:
```

> Run MeTTa source on the worker and return its result groups.

### `AsyncMeTTa.load`

```python
async def load(self, path: str) -> list:
```

> Load source or a fast cache into this space on the worker.

### `AsyncMeTTa.save`

```python
async def save(self, path: str, format: SaveFormat = 'metta') -> int:
```

> Save this space and return the number of stored atoms.

### `AsyncMeTTa.add`

```python
async def add(self, *atoms: Any) -> None:
```

> Add atoms to this space on the worker.

### `AsyncMeTTa.add_table`

```python
async def add_table(self, head: Any, data: Any) -> int:
```

> Add rows from a tabular value and return the number added.

### `AsyncMeTTa.remove`

```python
async def remove(self, atom: Any) -> bool:
```

> Remove one matching atom and report whether one existed.

### `AsyncMeTTa.clear`

```python
async def clear(self) -> None:
```

> Remove every atom from this space.

### `AsyncMeTTa.count`

```python
async def count(self) -> int:
```

> Return the number of atoms in this space.

### `AsyncMeTTa.atoms`

```python
async def atoms(self) -> list:
```

> Return a snapshot of every atom in this space.

### `AsyncMeTTa.query`

```python
async def query(
    self,
    *patterns: Any,
    where: Any | None = None,
    limit: int | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Rows:
```

> Query patterns with the synchronous surface's bounds and guard.

### `AsyncMeTTa.eval`

```python
async def eval(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    capture: bool = False,
    residuals: bool = False,
) -> Any:
```

> Evaluate a term and return every answer.

### `AsyncMeTTa.one`

```python
async def one(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Any:
```

> Evaluate a term that must produce exactly one value.

### `AsyncMeTTa.new_space`

```python
async def new_space(self) -> AsyncMeTTa:
```

> Return an isolated space that borrows this connection's worker.

### `AsyncMeTTa.drop`

```python
async def drop(self) -> None:
```

> Drop this named space from the engine.

### `AsyncMeTTa.profile`

```python
async def profile(
    self,
    source: str,
    using: dict[str, Any] | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Any:
```

> Profile source execution and return its groups and counters.

### `AsyncMeTTa.parse`

```python
async def parse(self, source: str) -> Any:
```

> Parse one MeTTa term without evaluating it.

### `AsyncMeTTa.cast`

```python
async def cast(self, value: Any, type_: Any, /) -> Any:
```

> Check and narrow a value through the engine type system.

### `AsyncMeTTa.trace`

```python
async def trace(self, source: str, max_events: int = 1000000) -> Any:
```

> Trace source execution up to the requested event bound.

### `AsyncMeTTa.lint`

```python
async def lint(self) -> Any:
```

> Return static findings for this space.

### `AsyncMeTTa.digest`

```python
async def digest(self) -> str:
```

> Return the stable content digest for this space.

### `AsyncMeTTa.unregister_op`

```python
async def unregister_op(self, name: str) -> None:
```

> Remove every registered operation overload under a name.

### `AsyncMeTTa.builtins`

```python
async def builtins(self) -> list[str]:
```

> Return the names of engine builtins.

### `AsyncMeTTa.is_function`

```python
async def is_function(self, name: str) -> bool:
```

> Report whether a function is visible from this space.

### `AsyncMeTTa.is_function_here`

```python
async def is_function_here(self, name: str) -> bool:
```

> Report whether this space defines a function itself.

### `AsyncMeTTa.arities`

```python
async def arities(self, name: str) -> list[int]:
```

> Return the registered arities for a function name.

### `AsyncMeTTa.derivation`

```python
async def derivation(
    self,
    target: Any,
    depth: int | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Any:
```

> Build a bounded derivation tree for one target.

### `AsyncMeTTa.why`

```python
async def why(self, pattern: Any) -> str:
```

> Explain why a pattern is not currently reducible.

### `AsyncMeTTa.space`

```python
async def space(self, name: str) -> AsyncMeTTa:
```

> Another space through the same engine thread. The connection
> owns the thread; spaces borrow it, so closing a borrowed space is
> a no-op and closing the owner ends them all.

### `AsyncMeTTa.aclose`

```python
async def aclose(self, timeout: float = DEFAULT_CLOSE_TIMEOUT) -> None:
```

> Interrupt work, reject queued calls, and detach within timeout.

### `AsyncMeTTa.stop`

```python
def stop(self, timeout: float = DEFAULT_CLOSE_TIMEOUT) -> None:
```

> Synchronous cleanup for code without a running event loop.

## `connect`

```python
async def connect(space: str = _DEFAULT_SPACE, *, metta: MeTTa | None = None) -> AsyncMeTTa:
```

> An AsyncMeTTa with its engine thread already running, aiosqlite's
> own naming for the entry point.
