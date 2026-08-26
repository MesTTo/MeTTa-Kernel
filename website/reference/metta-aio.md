# `metta.aio`

Source: `bindings/python/metta/aio.py`.

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
>   - async solve, Linda verbs, watch, class/type dispatch, and the two
>     transaction laws execute on the owning worker [tested:
>     test_aio_structural_surface_behaves; commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
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
>     types [tested: test_canonical_context_types_replace_public_newtypes;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - async head-named declaration methods reuse the catalog-generated policy aliases and
>     own no duplicate Literal lists [tested: tests/check_policy_inventory.py;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - all fifteen synchronous declaration heads have asynchronous mirrors,
>     including ``reacts`` for ``(on ...)`` while ``reaction`` remains, and no
>     ``declare_*`` aliases [tested:
>     test_aio_covers_the_whole_synchronous_surface,
>     test_m7_narrow_core_surface; commit=0cfc68a483d8d64fb499e53bbe9a3cc63f68990f]
>   - async cast preserves a concrete target class as its static return type and
>     keeps the target positional-only [tested
>     test_target_type_overloads_preserve_the_requested_class,
>     test_cast_target_is_positional_only]
>   - async space forwards anonymous-space inheritance, restriction, and grants
>     on the owning worker [tested:
>     test_async_space_forwards_restriction_and_grants; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - async scoped limits forward stack byte bounds through the synchronous
>     task-local scope [tested: test_stack_limit_is_carried_to_the_limited_six_seam;
>     commit=b1de70215dd3f0c9d5437558c57c5911c13948b5]
>   - reader-token registration and removal run on the owning engine worker and
>     mirror the synchronous surface [tested:
>     test_aio_plain_methods_forward_on_the_worker and
>     test_async_anonymous_space_repr_keeps_the_submitting_site;
>     commit=50d1de4d0ead4a0c3997f9b2ef58631bbafaede3]
>   - async eval mirrors the synchronous single answer shape without a
>     residuals flag [tested:
>     test_a_not_reducible_answer_is_the_unreduced_term_with_no_flag;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - async function handles consume the synchronous Answers surface on their
>     owning worker, including the composite ``neg`` operator word [tested:
>     test_aio_structural_surface_behaves; commit=8ec44dec3cafba5981e7cf712749cca0e1bdcc45]
>   - async operation registration requires and forwards the canonical effect
>     argument [tested: test_aio_declare_and_register_delegations_land;
>     commit=3cfbe0d7417b1c453c2dc12d47e2e47e7de461f7]
>   - execution-policy scopes cross the worker hop and never change awaited
>     return shapes [tested:
>     test_no_decorator_flag_changes_the_return_shape_and_declarations_are_atoms;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - image reaches the synchronous declaration owner on the engine
>     worker [tested: test_aio_covers_the_whole_synchronous_surface;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - async peek and take keep event-loop threads unblocked while the engine
>     worker performs the synchronous Linda wait [tested:
>     test_async_peek_and_take_mirror_the_space_handle; commit=4e2398075da67bb2cbcc123a9fc1e078ecac6fbf]
>   - async match forwards the submitting task's scoped or explicit algebra,
>     and sample mirrors the synchronous random.choices-shaped door [tested:
>     test_aio_covers_the_whole_synchronous_surface; commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
>   - async reification, world evaluation, and commit keep every engine crossing
>     on the owning worker while immutable atom snapshots remain directly
>     readable [tested: test_async_worlds_stay_on_the_owning_worker;
>     commit=3ded7552797b66d78e666141eb51f3bc14686bd2]
>   - async coverage, compensation declarations, and saga recovery keep their
>     complete synchronous scope on one owning worker [tested:
>     test_async_saga_and_world_coverage_stay_on_the_owning_worker;
>     commit=WORKTREE]
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
>     async with metta.aio.connect() as am:
>         await am.add(S.edge(1, 2))
>         rows = await am.match(S.edge(V.a, V.b))
>
> The exact rule should be: every finite request-response method forwards through the worker. Context managers, cursors, decorators, callback registrations, returned synchronous helper objects, and interactive entry points remain call() or synchronous-surface operations.
>
> call(fn) reaches anything not mirrored by running fn(m) on the engine's
> thread. interrupt() stops the evaluation the
> worker is running right now, and cancelling a waiting task (an
> asyncio timeout included) interrupts its own call, so the engine
> stops working for a listener that is gone.

### `AsyncMeTTa.name`

```python
def name(self) -> _SpaceId:
```

No docstring is defined.

### `AsyncMeTTa.bind`

```python
def bind(self, values: Mapping[str, Any] | None = None, /, **named: Any) -> Any:
```

> Scope host values copied into subsequent worker requests.

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
> reading). The stopped call raises metta.Interrupted; whatever it
> completed before the stop, writes included, stands. Callable from
> any thread or task.

### `AsyncMeTTa.run`

```python
async def run(
    self,
    source: str,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[list[Atom]]:
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
async def save(self, path: str, format: SaveFormat = SaveFormat.metta) -> int:
```

> Save this space and return the number of stored atoms.

### `AsyncMeTTa.add`

```python
async def add(self, *atoms: Any) -> None:
```

> Add atoms to this space on the worker.

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

### `AsyncMeTTa.peek`

```python
async def peek(self, pattern: Any, *, deadline: float | None = None) -> Atom:
```

> Wait for one matching atom without blocking the event loop.

### `AsyncMeTTa.take`

```python
async def take(self, pattern: Any, *, deadline: float | None = None) -> Atom:
```

> Wait for and remove one matching atom without blocking the loop.

### `AsyncMeTTa.match`

```python
async def match(
    self,
    *patterns: Any,
    where: Any | None = None,
    limit: int | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
    into: _builtins.type | None = None,
) -> Any:
```

> Match patterns with synchronous bounds, carrier, guard, and shape.
>
> ``under=`` is resolved in the caller's copied ContextVar context and
> executed on the owning worker, so a surrounding ``metta.under``
> scope behaves the same across the async hop.

### `AsyncMeTTa.solve`

```python
async def solve(self, pattern: Any, subject: Any) -> Any:
```

> Solve a relation backwards and return caller-named bindings.

### `AsyncMeTTa.eval`

```python
async def eval(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[Atom]:
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

### `AsyncMeTTa.copy`

```python
async def copy(self) -> AsyncMeTTa:
```

> This space's contents in a new anonymous space; MeTTa.copy,
> the clone borrowing this connection's worker.

### `AsyncMeTTa.reify`

```python
async def reify(self) -> AsyncWorld:
```

> Capture one immutable world on the owning engine worker.

### `AsyncMeTTa.commit`

```python
async def commit(self, world: AsyncWorld) -> None:
```

> Commit an async world through the worker that produced it.

### `AsyncMeTTa.covers`

```python
async def covers(self, effect: EffectClass | str) -> Atom:
```

> Declare reified-world effect coverage on the owning worker.

### `AsyncMeTTa.compensates`

```python
async def compensates(self, operation: str, compensation: str) -> Atom:
```

> Declare one saga compensation on the owning worker.

### `AsyncMeTTa.saga`

```python
def saga(self, receipts: AsyncMeTTa) -> AsyncSaga:
```

> Open an async saga whose complete scopes run on this worker.

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
async def register_token(
    self,
    pattern: str | _re.Pattern[str],
    constructor: Callable[[str], Any],
) -> None:
```

> Register a full-lexeme reader class on the engine worker.

### `AsyncMeTTa.unregister_token`

```python
async def unregister_token(self, pattern: str | _re.Pattern[str]) -> None:
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
async def space(
    self,
    name: str | None = None,
    backing: Any = None,
    *,
    inherits: AsyncMeTTa | None = None,
    restricted: bool = False,
    grants: Sequence[str] = (),
) -> AsyncMeTTa:
```

> Create or open one space through this connection's worker.
>
> An omitted name creates an anonymous space. A provider supplied as
> ``backing`` is attached to the resulting handle. The connection owns
> the worker; returned spaces borrow it, so closing one does not stop
> the connection.

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

> Install a library integration; see metta.integrate.

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

### `AsyncMeTTa.admits`

```python
async def admits(self, type_name: str) -> Atom:
```

> Declare an admitted type on the owning engine worker.

### `AsyncMeTTa.annotations`

```python
async def annotations(
    self,
    subject_or_algebra: str,
    algebra: str | None = None,
    *,
    capabilities: Sequence[str] = (),
) -> Atom:
```

> Declare annotation algebra or subject capabilities on the worker.

### `AsyncMeTTa.algebra`

```python
async def algebra(
    self,
    name: str,
    *,
    combine: str,
    extend: str,
    zero: Any,
    one: Any,
    laws: Sequence[str] = (),
    carrier: Sequence[Any] = (),
    requires: Sequence[str] = (),
    order: SemiringOrder | None = None,
) -> Atom:
```

> Declare one checked value algebra on the owning engine thread.

### `AsyncMeTTa.add_tagged_fact`

```python
async def add_tagged_fact(self, tag: Any, proposition: Any) -> Atom:
```

> Store one ordinary tagged fact on the owning engine thread.

### `AsyncMeTTa.add_tagged_rule`

```python
async def add_tagged_rule(self, tag: Any, head: Any, *premises: Any) -> Atom:
```

> Store one algebra-threaded ordinary rule on the owning engine thread.

### `AsyncMeTTa.sample`

```python
async def sample(self, query: str | Atom, *, k: int = 10, seed: int = 7) -> list[Atom]:
```

> Draw ``k`` rate-weighted choices on the owning engine thread.

### `AsyncMeTTa.capacity`

```python
async def capacity(self, limit: int) -> Atom:
```

> Declare the maximum concurrent work for this context.

### `AsyncMeTTa.context`

```python
async def context(self, world: World) -> Atom:
```

> Declare whether this context uses an open or closed world.

### `AsyncMeTTa.emits`

```python
async def emits(self, policy: AnswerPolicy) -> Atom:
```

> Declare this context's answer emission policy.

### `AsyncMeTTa.events`

```python
async def events(
    self,
    delivery: Delivery | None = None,
    order: EventOrder = EventOrder.unordered,
) -> Any:
```

> Return the event stream or declare this context's event promise.
>
> A fold registered through it runs on the engine thread, inside the
> write that caused the event, exactly as a synchronous one does.
> `AsyncMeTTa.subscribe` is the async-native door for the delivering
> fold and hands events to an async iterator instead.

### `AsyncMeTTa.handles`

```python
async def handles(
    self,
    pattern: str | Atom,
    fidelity: Fidelity,
    *,
    det: Determinism | None = None,
) -> Atom:
```

> Declare a handler's pattern, fidelity, and determinism.

### `AsyncMeTTa.image`

```python
async def image(self, type_name: str, setting: ImageMode) -> Atom:
```

> Declare whether one type crosses by value or identity.

### `AsyncMeTTa.merge`

```python
async def merge(self, pattern: str | Atom, policy: AnswerPolicy) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.on_error`

```python
async def on_error(
    self,
    subject_or_pattern: str | Atom,
    pattern_or_mode: str | Atom,
    mode: OnError | None = None,
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.reacts`

```python
async def reacts(
    self,
    pattern: str | Atom,
    operation: str | Atom,
    priority: int | None = None,
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.reaction`

```python
async def reaction(
    self,
    pattern: str | Atom,
    operation: str | Atom,
    priority: int | None = None,
) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.agenda`

```python
async def agenda(self, policy: AgendaPolicy, function: str | None = None) -> Atom:
```

> Declare which reaction fires first; see Space.agenda.

### `AsyncMeTTa.source`

```python
async def source(self, kind: SourceKind) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.writes`

```python
async def writes(self, atomicity: Atomicity) -> Atom:
```

No docstring is defined.

### `AsyncMeTTa.op`

```python
async def op(
    self,
    fn: Callable,
    /,
    *,
    effect: EffectClass | str,
    name: str | None = None,
    transport: Literal['encoded', 'raw'] = 'encoded',
    declarations: Iterable[Atom] = (),
    arities: list[int] | None = None,
    inverse: Callable | None = None,
) -> Callable:
```

> Register a callable through the single short operation door.

### `AsyncMeTTa.define`

```python
async def define(
    self,
    fn: Callable | None = None,
    /,
    *,
    prolog: str | os.PathLike[str] | None = None,
    accessors: bool = True,
    methods: bool = True,
) -> Any:
```

> Compile a Python function into equations on the worker. The
> returned handle's own calls are synchronous doors; evaluate
> through fn(name) or run() from async code.

### `AsyncMeTTa.cache`

```python
async def cache(
    self,
    fn: Callable | None = None,
    /,
    *,
    name: str | None = None,
    unchecked: bool = False,
) -> Any:
```

> Define and memoize on the worker, the sync door's cache decorator.
>
> The memo stores every answer occurrence, and the returned handle
> carries cache_clear() and cache_info() as synchronous doors the way
> define's handle carries its own.

### `AsyncMeTTa.type`

```python
async def type(self, atom: Any, /) -> Atom:
```

> Return this space's first get-type answer on the worker.

### `AsyncMeTTa.doc`

```python
async def doc(self, atom: Any, /) -> Atom:
```

> Return this space's structured get-doc answer on the worker.

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

### `AsyncMeTTa.limits`

```python
def limits(
    self,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    stack: int | None = None,
):
```

> Scoped default bounds, the synchronous surface's own block:
> enter and exit only touch a contextvar, so this is an ordinary
> `with` inside async code, and every awaited call in the scope
> carries it to the worker.

### `AsyncMeTTa.capture`

```python
def capture(self):
```

> Collect awaited run/eval output in an ordinary task-local scope.

### `AsyncMeTTa.atomic`

```python
def atomic(self):
```

> Make each awaited run in the block one engine transaction.

### `AsyncMeTTa.speculative`

```python
def speculative(self):
```

> Answer awaited runs while discarding their engine writes.

### `AsyncMeTTa.strict`

```python
def strict(self):
```

> Refuse unreduced directives in awaited runs within the block.

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
async def transaction(self, target: Callable[[MeTTa], Any] | Atom | str, /) -> Any:
```

> Run a callable or term inside one engine transaction on the worker.
>
> A callable receives the worker's own
> synchronous MeTTa, because a transaction body is a closed
> synchronous goal (SWI's transaction/1 takes one), which is also
> why there is no async body and no transactional decorator here.
> A raise rolls every engine write back and re-raises as itself. A term
> instead follows the engine law: empty answers roll its writes back.
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
>     await am.match(...)
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

> match(), pulled asynchronously: one row per worker round trip.
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

### `AsyncMeTTa.watch`

```python
def watch(
    self,
    pattern: Any,
    *,
    on: str = 'add',
    queue_max: int = SUBSCRIPTION_QUEUE_MAX,
) -> _AsyncSubscription:
```

> Observe matching writes as the async-native event iterator.

### `AsyncMeTTa.fn`

```python
def fn(self) -> _AsyncFunctionNamespace:
```

> Engine functions as async callables, by attribute or exact name.
>
> ``m.fn.car_atom`` transliterates underscores to hyphens and
> ``m.fn["=="]`` preserves exact punctuation, the same two doors the
> sync namespace has. Resolution is lazy: the worker is asked when the
> function is awaited, so an unknown name raises there rather than at
> access.

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

## `AsyncSaga`

```python
class AsyncSaga:
```

> The awaitable context-manager twin of :class:`metta._saga.Saga`.

### `AsyncSaga.run`

```python
async def run(self, target: Any) -> list[Atom]:
```

> Commit one forward step and its receipt on the owning worker.

### `AsyncSaga.rollback`

```python
async def rollback(self) -> None:
```

> Run the pending reverse recovery plan on the owning worker.

### `AsyncSaga.aclose`

```python
async def aclose(self) -> None:
```

> Cancel the synchronous receipt observer on the owning worker.

## `AsyncWorld`

```python
class AsyncWorld:
```

> An immutable world whose evaluation crosses its originating worker.

### `AsyncWorld.atoms`

```python
def atoms(self) -> tuple[Atom, ...]:
```

> Return the frozen atom multiset without an engine crossing.

### `AsyncWorld.eval`

```python
async def eval(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> tuple[list[Atom], AsyncWorld]:
```

> Evaluate on the worker and return answers plus a successor value.

### `AsyncWorld.diff`

```python
def diff(self, other: AsyncWorld) -> tuple[list[Atom], list[Atom]]:
```

> Return ordered multiset extras between worlds from one worker.

### `AsyncWorld.aclose`

```python
async def aclose(self) -> None:
```

> Release this world's retained program image on its worker.

## `connect`

```python
async def connect(space: str = _DEFAULT_SPACE, *, metta: MeTTa | None = None) -> AsyncMeTTa:
```

> An AsyncMeTTa with its engine thread already running, aiosqlite's
> own naming for the entry point.
