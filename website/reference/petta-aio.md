# `petta.aio`

Source: `bindings/python/petta/aio.py`.

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
>   - reader-token registration and removal run on the owning engine worker and
>     mirror the synchronous surface [tested:
>     test_aio_plain_methods_forward_on_the_worker; commit=2c741dda928a30d0ce1c7e1fcf0b263b4d1bb97b]
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
>   Future Enhancements: None.

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
async def load(
    self,
    path: str,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list:
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
    into: _builtins.type | None = None,
) -> Any:
```

> Query patterns with the synchronous surface's bounds, guard,
> and into= row shaping.

### `AsyncMeTTa.eval`

```python
async def eval(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
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
    using: dict[str, Any] | None = None,
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

### `AsyncMeTTa.copy`

```python
async def copy(self) -> AsyncMeTTa:
```

> This space's contents in a new anonymous space; MeTTa.copy,
> the clone borrowing this connection's worker.

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

### `AsyncMeTTa.register_token`

```python
async def register_token(self, pattern: str, constructor: Callable[[str], Any]) -> None:
```

> Register a full-lexeme reader class on the engine worker.

### `AsyncMeTTa.unregister_token`

```python
async def unregister_token(self, pattern: str) -> None:
```

> Remove a reader class from the engine worker.

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

### `AsyncMeTTa.first`

```python
async def first(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Any:
```

> The first answer decoded, or None for no answers.

### `AsyncMeTTa.parallel`

```python
async def parallel(self, *targets: Any, timeout: float | None = None) -> list:
```

> Evaluate every target concurrently inside the engine.

### `AsyncMeTTa.hyperpose`

```python
async def hyperpose(self, *targets: Any, timeout: float | None = None) -> list:
```

> parallel() under its MeTTa name.

### `AsyncMeTTa.integrate`

```python
async def integrate(self, target: Any) -> str:
```

> Install a library integration; see petta.integrate.

### `AsyncMeTTa.profile_extension`

```python
async def profile_extension(
    self,
    source: str,
    using: dict[str, Any] | None = None,
    *,
    extension: str | None = None,
    names: Sequence[str] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> tuple:
```

> Run source and report per-function engine cost.

### `AsyncMeTTa.eval_status`

```python
async def eval_status(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list:
```

> Evaluate and report each answer's outcome kind.

### `AsyncMeTTa.run_status`

```python
async def run_status(
    self,
    source: str,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list:
```

> Run source and report each directive's outcome kinds.

### `AsyncMeTTa.space_names`

```python
async def space_names(self) -> list[str]:
```

> Every space name this engine registers, sorted.

### `AsyncMeTTa.disassemble`

```python
async def disassemble(self, name: str) -> str:
```

> The Prolog clauses a function name compiled to.

### `AsyncMeTTa.declare_admits`

```python
async def declare_admits(self, name: str, type_name: str) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_annotations`

```python
async def declare_annotations(
    self,
    name: str,
    semiring: Literal['bool', 'bag', 'set', 'ranked', 'prob', 'prov'],
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_capacity`

```python
async def declare_capacity(self, name: str, limit: int) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_context`

```python
async def declare_context(self, name: str, world: Literal['closed-world', 'open-world']) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_emits`

```python
async def declare_emits(self, name: str, policy: Literal['depth', 'fair', 'best-first']) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_handles`

```python
async def declare_handles(
    self,
    name: str,
    pattern: str | Atom,
    fidelity: Literal['Exact', 'Partial', 'Sound', 'Refuse'],
    *,
    det: str | None = None,
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_merge`

```python
async def declare_merge(
    self,
    pattern: str | Atom,
    policy: Literal['depth', 'fair', 'best-first'],
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_on_error`

```python
async def declare_on_error(
    self,
    name: str,
    pattern: str | Atom,
    mode: Literal['keep', 'empty', 'abort'],
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_reaction`

```python
async def declare_reaction(self, name: str, pattern: str | Atom, operation: str | Atom) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_source`

```python
async def declare_source(self, name: str, kind: Literal['linear', 'repeated', 'peek']) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.declare_writes`

```python
async def declare_writes(
    self,
    name: str,
    atomicity: Literal['transactional', 'atomic-single', 'best-effort'],
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.register_op`

```python
async def register_op(
    self,
    fn: Callable,
    /,
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
    pure: bool = False,
) -> Callable:
```

> Register a Python callable as a MeTTa function. The engine
> calls it synchronously on the worker thread, exactly as the
> synchronous surface does; the decorator spelling stays with the
> synchronous surface, since decoration cannot await.

### `AsyncMeTTa.op`

```python
async def op(
    self,
    fn: Callable,
    /,
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
    pure: bool = False,
) -> Callable:
```

> register_op under its short name.

### `AsyncMeTTa.define`

```python
async def define(
    self,
    fn: Callable | None = None,
    /,
    *,
    prolog: str | os.PathLike[str] | None = None,
) -> Any:
```

> Compile a Python function into equations on the worker. The
> returned handle's own calls are synchronous doors; evaluate
> through fn(name) or run() from async code.

### `AsyncMeTTa.type`

```python
async def type(
    self,
    cls: _builtins.type,
    /,
    *,
    accessors: bool = True,
    methods: bool = True,
) -> _builtins.type:
```

> Declare a Python class into this space. A call, not a
> decorator: decoration cannot await.

### `AsyncMeTTa.register_prolog`

```python
async def register_prolog(
    self,
    source: str | None = None,
    *,
    path: str | os.PathLike[str] | None = None,
    names: Sequence[str] | Mapping[str, str] = (),
) -> tuple[str, ...]:
```

> Register Prolog predicates as MeTTa functions.

### `AsyncMeTTa.register_space`

```python
async def register_space(self, provider: Any, name: str) -> Any:
```

> Register a Python-backed space. Its methods run on whichever
> thread the engine is answering from, exactly as in sync use.

### `AsyncMeTTa.register_foreign_library`

```python
async def register_foreign_library(
    self,
    path: str | os.PathLike[str],
    *,
    entry: str | None = None,
    names: Sequence[str] = (),
) -> tuple[str, ...]:
```

> Load a foreign library of Prolog predicates.

### `AsyncMeTTa.register_library_path`

```python
async def register_library_path(self, directory: Any, name: str) -> None:
```

> Register a directory for (library ...) imports.

### `AsyncMeTTa.unregister_prolog`

```python
async def unregister_prolog(self, extension: str) -> tuple[str, ...]:
```

No docstring is defined.

### `AsyncMeTTa.unregister_space`

```python
async def unregister_space(self, name: str) -> None:
```

No docstring is defined.

### `AsyncMeTTa.limits`

```python
def limits(self, *, timeout: float | None = None, inferences: int | None = None):
```

> Scoped default bounds, the synchronous surface's own block:
> enter and exit only touch a contextvar, so this is an ordinary
> `with` inside async code, and every awaited call in the scope
> carries it to the worker.

### `AsyncMeTTa.batch`

```python
def batch(self) -> _AsyncBatch:
```

> Collect this space's add() calls and cross once at exit,
> the synchronous batch's async twin: `async with am.batch():`.
> The same stated edges apply: reads see the pre-batch space,
> remove and clear refuse, an exception discards.

### `AsyncMeTTa.transaction`

```python
async def transaction(self, fn: Callable[[MeTTa], Any], /) -> Any:
```

> Run fn inside one engine transaction on the worker thread,
> answering its return value. fn receives the worker's own
> synchronous MeTTa, because a transaction body is a closed
> synchronous goal (SWI's transaction/1 takes one), which is also
> why there is no async body and no transactional decorator here.
> A raise rolls every engine write back and re-raises as itself.
>
>     await am.transaction(lambda m: m.add(S.fact(1)))

### `AsyncMeTTa.runtime`

```python
def runtime(self) -> Runtime:
```

> The engine bridge itself, for callers going under the surface.
> Every call on it blocks the calling thread; from async code, wrap
> such work in call().

### `AsyncMeTTa.stats`

```python
def stats(self) -> _AsyncStats:
```

> The engine's counters over an async with-block, as deltas.
>
> async with am.stats() as s:
>     await am.query(...)
> s.inferences

### `AsyncMeTTa.assuming`

```python
def assuming(self, *facts: Any) -> _AsyncAssuming:
```

> Facts held only inside an async with-block: added on entry,
> removed on exit, exceptions included.

### `AsyncMeTTa.prepare`

```python
async def prepare(self, *patterns: Any, where: Any | None = None) -> _AsyncPrepared:
```

> A prepared query whose solve() is awaitable; the shape builds
> once on the worker, columns readable without a round trip.

### `AsyncMeTTa.stream`

```python
def stream(
    self,
    *patterns: Any,
    where: Any | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> _AsyncCursor:
```

> query(), pulled asynchronously: one row per worker round trip.
>
>     async with am.stream(S.edge(V.a, V.b)) as rows:
>         async for row in rows:
>             ...
>
> Iterating without the async-with also works; aclose() is then the
> caller's duty, the finalization reading the data model gives
> asynchronous iterators.

### `AsyncMeTTa.subscribe`

```python
def subscribe(
    self,
    pattern: Any,
    *,
    on: str = 'add',
    queue_max: int = SUBSCRIPTION_QUEUE_MAX,
) -> _AsyncSubscription:
```

> A standing query as an async event stream: every matching
> write becomes an Event on an asyncio queue, consumed with
> async-for. The synchronous surface's callback form stays there;
> here the stream IS the delivery.
>
>     async with am.subscribe(S.order(V.id), on="add") as events:
>         async for event in events:
>             ...

### `AsyncMeTTa.fn`

```python
def fn(self, name: str) -> _AsyncEngineFunction:
```

> An engine function as an async callable: await f(3), with
> .one, .first and .all carrying the same cardinality triple.

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
