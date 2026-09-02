# `metta.aio`

Source: `extensions/python/metta/aio.py`.

> The same engine without blocking an event loop. AsyncMeTTa
> proxies a MeTTa space onto one dedicated worker thread that holds an
> attached Prolog engine, the aiosqlite architecture (one thread per
> connection, a request queue, results delivered back through the loop), so
> awaiting a long query lets every other coroutine keep running. One engine
> per process stays the rule: calls are serialized, and the win is a live
> event loop, never parallel evaluation. interrupt() stops the running
> evaluation through the engine's own thread_signal, the sqlite3 reading,
> and a cancelled task fires it on its own call, so asyncio timeouts stop
> the engine instead of abandoning it.
> Owns:
>   - each owning AsyncMeTTa owns one daemon worker and its attached Prolog
>     engine until aclose(), stop(), or the atexit handler releases it

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
> The rule: every finite request-response method forwards through the
> worker; context managers, cursors, decorators, callback registrations,
> returned synchronous helper objects and interactive entry points remain
> call() or synchronous-surface operations.
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

### `AsyncMeTTa.dropped`

```python
def dropped(self) -> bool:
```

> Whether drop() has released the wrapped space's handle.

### `AsyncMeTTa.bind`

```python
def bind(self, values: Mapping[str, Any] | None = None, /, **named: Any) -> Any:
```

> Scope host values copied into subsequent worker requests.

### `AsyncMeTTa.metta`

```python
def metta(self) -> Space:
```

> The wrapped synchronous space, for engine-thread work via call().

### `AsyncMeTTa.start`

```python
async def start(self) -> Self:
```

> Start the engine thread; connect() and `async with` call this.

### `AsyncMeTTa.call`

```python
async def call(self, fn: Callable[[Space], Any]) -> Any:
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

### `AsyncMeTTa.count`

```python
async def count(self) -> int:
```

> Return the number of atoms in this space.

### `AsyncMeTTa.eval`

```python
async def eval(
    self,
    target: Any,
    *more: Any,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
    theory: Any | None = None,
    interpreter: Any | None = None,
) -> list[Atom] | list[list[Atom]]:
```

> Evaluate a term and return every answer.
>
> `under`, `theory` and `interpreter` are the synchronous eval()'s, and
> they matter more here: answers() is excluded from this surface because
> a replayable cross-thread iterator is not what an await gives you, so
> without them there was no way to annotate an EVALUATION asynchronously
> at all -- match(under=) covered patterns and nothing covered calls
> .

### `AsyncMeTTa.copy`

```python
async def copy(self) -> AsyncMeTTa:
```

> This space's contents in a new anonymous space; Space.copy,
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

### `AsyncMeTTa.saga`

```python
def saga(self, receipts: AsyncMeTTa) -> AsyncSaga:
```

> Open an async saga whose complete scopes run on this worker.

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
> An omitted name creates an anonymous space. ``inherits``, ``restricted``
> and ``grants`` choose the space MODEL and apply to a named space as
> well as an anonymous one. A provider supplied as ``backing`` is
> attached to the resulting handle. The connection owns the worker;
> returned spaces borrow it, so closing one does not stop the connection.

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

> Register a callable through the short operation form.

### `AsyncMeTTa.rules`

```python
async def rules(self, fn: Callable) -> Any:
```

> Collect and land a non-exclusive equation bundle on the worker.
>
> An awaitable CALL rather than a decorator, which is the same answer
> define() gives to the same problem: decoration cannot await, so this
> method accepts only the applied form. It was
> excluded from the async surface for the first reading of that, which
> left an async caller unable to land a bundle at all
> .

### `AsyncMeTTa.pre_add`

```python
async def pre_add(self, fn: Callable) -> Any:
```

> Compile or accept one unary judge and claim this space's write hook.
>
> Excluded for the same reading as rules(), and restored the same way.

### `AsyncMeTTa.define`

```python
async def define(
    self,
    fn: Callable | None = None,
    /,
    *,
    prolog: str | os.PathLike[str] | None = None,
    name: str | None = None,
    accessors: bool = True,
    methods: bool = True,
) -> Any:
```

> Compile a Python function into equations on the worker. The
> returned handle's own calls are synchronous methods; evaluate
> through fn(name) or run() from async code.
>
> `name=` preserves an exact spelling on the async surface. Without it,
> an async caller installing `prime?` or an authored underscore had no
> equivalent of the synchronous define method.

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
async def transaction(self, target: Callable[[Space], Any] | Atom | str, /) -> Any:
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
    limit: int | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
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
    where: Any | None = None,
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
    where: Any | None = None,
    deadline: float | None = None,
    queue_max: int = SUBSCRIPTION_QUEUE_MAX,
) -> _AsyncSubscription:
```

> Observe matching writes, raising Timeout after each quiet deadline.
>
> This method once shared subscribe()'s signature and body despite being
> named watch(), so an async caller had no way to set the quiet deadline
> that peek() and take() both provide
> .

### `AsyncMeTTa.fn`

```python
def fn(self) -> _AsyncFunctionNamespace:
```

> Engine functions as async callables, by attribute or exact name.
>
> ``m.fn.car_atom`` transliterates underscores to hyphens and
> ``m.fn["=="]`` preserves exact punctuation, the same two forms the
> sync namespace has. Resolution is lazy: the worker is asked when the
> function is awaited, so an unknown name raises there rather than at
> access.

### `AsyncMeTTa.space_names`

```python
async def space_names(self) -> list[str]:
```

> Every space name this engine registers, sorted: '&self' and
> '&metta' from boot, every native space something created or wrote to,
> and every foreign space currently bound. (new-space) and (spawn ...)
> create, so their answers are here at once; naming a space never
> registers it, so Space('&kb') is not here until a write, and a bind!
> token's target appears once something is stored under it.

### `AsyncMeTTa.drop`

```python
async def drop(self) -> None:
```

> Clear this space and release an anonymous name for reuse.
>
> Dropping unregisters a Python provider and closes only backing state
> owned by this handle. A foreign provider with a clear/drop lifecycle,
> such as MORK, releases its provider state.
> A named space's public name is not an anonymous allocation and never
> enters the anonymous pool. &self is cleared but never released.
> Subscriptions on the space cancel with it: a pooled name reused later
> must not deliver to the old life's watchers. The handle itself dies
> here, and dropping twice is a no-op, as closing twice is.

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

> Run MeTTa source: one list of answers per ! directive.
>
> The pipeline is the engine's own reader, compiler and evaluator, so
> the answers are exactly what the CLI would print, kept grouped per
> directive instead of flattened. Equations and facts in the source
> land in this space.
>
> `bind()` names Python values the source refers to by bare symbol,
> the way DuckDB reads a local dataframe by its variable name:
>
>     with m.bind({"graph": my_graph}):
>         m.run("!(py-len graph)")
>
> Each named symbol substitutes to its value (objects by identity),
> after reading, before anything runs. It is a BLOCK rather than a
> keyword because a binding mapping is the kind of value that grows,
> and a block grows down the page where a keyword has to fit beside
> everything else on the call. Every call that accepts a target reads the
> same scope, so one block covers run(), eval(), and answers() together.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the call
> with the engine's own guards; passing either raises TimeLimitError
> or InferenceLimitError when the bound is hit, and whatever the
> source completed before the stop, writes included, stands.
>
> `with m.capture() as output` collects printed text in `output.text`
> without changing this method's return shape. `with m.atomic()`
> and `with m.speculative()` scope execution policy without boolean
> combinations on each call. Atomic commits or rolls
> back each complete source; speculative answers and discards its
> writes. Both cover engine state; Python side effects and subscription
> callbacks already fired stay where they happened.
>
> A term the engine hands back unevaluated is an ordinary MeTTa value,
> not a failure: `!(hello world)` answers `(hello world)` and that is
> the whole of hello world in this language. eval_status() reports
> which answers reduced and which did not, as data, for a caller who
> wants to decide about it.

### `AsyncMeTTa.profile`

```python
async def profile(
    self,
    source: str,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> tuple[list[list[Atom]], EngineProfile]:
```

> Run source under the engine's statistical profiler, answering
> (groups, profile): the groups exactly as run() answers them, and
> the profile carrying sample counters plus one row per predicate,
> self-ticks first.
>
>     groups, prof = m.profile("!(big-computation)")
>     prof.top(5)     # the five predicates the samples landed in
>
> The sampler is statistical: a program that finishes in
> milliseconds carries few samples, so profile something that runs.
> Profiling changes execution; it is a debugging surface, not a
> mode to leave on.

### `AsyncMeTTa.profile_extension`

```python
async def profile_extension(
    self,
    source: str,
    *,
    extension: str | None = None,
    names: _abc.Sequence[str] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> tuple[list[list[Atom]], list[FunctionCost]]:
```

> Run source under the profiler, reporting only YOUR functions.
>
> `profile()` answers "which predicate did the samples land in", over
> every predicate in the process. The question a library author has is
> narrower: of the functions my library registered, which one is
> costing me, and is anything wrong with how it was installed.
>
>     groups, costs = m.profile_extension("!(my-workload)",
>                                         extension="mylib")
>     for cost in costs:
>         print(cost)
>     # <mylib-join/3 prolog: 40100 calls, 39900 redos, 812 ticks, index 1x>
>
> Name the `extension` and its registered members are looked up, or
> pass `names` for an explicit list. Each row carries the tier that
> installed the function and where from, its exact call and redo
> counts, the sampler's ticks, and its clause index.
>
> The two columns worth reading first are `redos` and `speedup`. Redos
> on a function meant to be deterministic are a leftover choice point,
> which costs the caller about twice and is invisible to the inference
> counter. A `speedup` of 1 means no argument discriminates, so every
> call walks the clause list; `indexed` False on a function nothing has
> called much only means SWI has not built one yet.
>
> The sampler is statistical, so profile something that runs, and
> profiling changes execution: this is a debugging surface.

### `AsyncMeTTa.save`

```python
async def save(
    self,
    path: str | os.PathLike[str],
    *,
    format: SaveFormat = SaveFormat.metta,
    timeout: float | None = None,
    inferences: int | None = None,
) -> int:
```

> Write every stored atom of this space, equations included, as
> MeTTa source by default, or as a version-pinned trusted cache with
> format="fast"; answers how many. A path ending .gz writes gzip
> compressed in either format, and load and import! read it back
> under the same name. The completed sibling file is synced and then
> atomically replaces the target, so a failed save leaves the old file
> intact. Atoms carrying live host objects cannot survive either file
> and are refused.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the save with
> the engine's own guards, exactly as they bound load(). Every part of a
> save is linear in the space -- the enumeration, the unwritable-atom
> scan and the fast writer -- so this is the unbounded engine work those
> guards exist to bound, and the atomic replace above already makes a
> stopped save safe: the sibling is never moved into place.
>
> There is no `format` on load(), and that is not an omission. When you
> save, the file does not exist and something has to say which of the two
> to write; when you load, load() reads which it is, `.gz` included.

### `AsyncMeTTa.load`

```python
async def load(
    self,
    path: str | os.PathLike[str],
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[list[Atom]]:
```

> Add a text program or trusted fast cache to this space.
>
> This is a consult, so it always loads and what it loads REPLACES
> what the same file put in this space before. Edit the file, load it
> again, and the space holds the new definitions and not both; the
> engine says on stderr which file it replaced and how many atoms
> went. Atoms from other sources, and ones you added yourself, stay.
> A load that raises leaves the previous definitions standing, so a
> broken edit costs nothing but the error.
>
> `!(import! &self path)` is the other form and loads a file that is
> new or edited, skipping one that is neither. The two agree on what
> a reload means and differ only in whether an unchanged file runs
> again, which is SWI's consult/1 against its if(changed).
>
> A .gz path is detected and read through the decompressed bytes.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the load
> with the engine's own guards, raising TimeLimitError or
> InferenceLimitError. A load is all or nothing: a stop takes back
> everything the file had put in a space, the same way a load that
> fails on a bad form does, because a file the space holds half of is
> not a file it can replace later. run() is the entry point that
> keeps finished work when a bound stops it. This is the one most
> likely to be handed code the caller did not write, since a file can
> carry `!` directives and an import graph, so it takes the same pair
> its siblings take.

### `AsyncMeTTa.parse`

```python
async def parse(self, source: str) -> Atom:
```

> Read one form into an atom without evaluating it.

### `AsyncMeTTa.register_token`

```python
async def register_token(
    self,
    pattern: str | _re.Pattern[str],
    constructor: Callable[[str], Any],
) -> None:
```

> Register a full-token regex and its Atom constructor.
>
> The constructor receives the complete matched lexeme. It may return an
> Atom or any value accepted by :func:`metta.ground`. A later registration
> of the same pattern replaces the constructor. Only future parses read
> the new mapping; atoms already returned are immutable values.

### `AsyncMeTTa.unregister_token`

```python
async def unregister_token(self, pattern: str | _re.Pattern[str]) -> None:
```

> Remove a reader-token class; an absent pattern is already removed.

### `AsyncMeTTa.add`

```python
async def add(self, *atoms: Any) -> None:
```

> Add atoms to this space, one engine round-trip for the lot.
> An (= ...) atom compiles as an equation. Every Atom shape the engine's
> add-atom accepts crosses unchanged, including a bare Symbol, Grounded
> value, and empty Expression; a free Variable receives the engine's own
> insufficient-instantiation refusal.
>
> A variable's NAME is not stored. `(rule $x $y)` reads back as
> `(rule $_17902 $_17904)`, because a variable is an identity and not a
> spelling. That is the right property for a logic engine and it is the
> one thing about storage that surprises everybody once.
>
> A library IS knowledge, so the same operator imports it: ``m += lib.he``
> performs ``!(import! <m> (library lib_he))`` with this space as the
> target. An import is an effect, so it refuses to hide inside an atom
> batch or share a call with stored atoms.

### `AsyncMeTTa.remove`

```python
async def remove(self, atom: Any, *more: Any) -> bool | int:
```

> Remove ONE unifying occurrence and say whether one was there,
> which is Python's own `list.remove` grain.
>
> Variadic like `add` and `transfer`: several atoms ride one engine
> crossing inside one transaction, and the answer counts the found,
> so the one-atom call still reads as the truth value it always
> was.
>
> `space -= atom` is this same grain without the report, the way
> `+=` is `add` without one: Python's in-place difference over a
> MULTISET, whose own Python spelling is `collections.Counter`,
> subtracts the multiplicity given rather than clearing the key.
> That is the only reading under which the operators are inverses,
> so `s += a; s -= a` leaves the space it found. `-=` classifies its
> operand exactly as `+=` does, so `-=` subtracts the same fact stream
> `+=` stores, one occurrence per element, in one
> transactional crossing.
>
> `del m[pattern]` is the draining form: it takes every
> unifying occurrence in one crossing and raises when nothing
> matched, as Python's `del` does, and MeTTa spells it `remove-atom`
> .
> MeTTa spells this method's grain `subtract-atom`. This is the one
> method that reports absence.
>
> A bare variable is the remove-everything reading a multiset space
> gives it, each atom leaving through its own proper path, equations
> and their compiled clauses included.

### `AsyncMeTTa.transfer`

```python
async def transfer(self, *atoms: Any, to: Space) -> int:
```

> Move ONE unifying occurrence of each atom into another space.
>
> Variadic and atomic: however many atoms ride the call, one engine
> transaction moves them in one crossing, so a mid-move failure
> rolls every side back and nothing is lost between the spaces. The
> answer counts the moved; an absent atom moves nothing and counts
> nothing, which is ``remove``'s own found-reporting grain, so the
> one-atom call still reads as a truth value. The longhand stays
> reachable: a :meth:`transaction` around ``remove`` and ``add``
> says the same thing one atom at a time. :meth:`take` is the
> WAITING kin for a pattern.

### `AsyncMeTTa.atoms`

```python
async def atoms(self) -> list[Atom]:
```

> Every stored atom in this space.

### `AsyncMeTTa.peek`

```python
async def peek(
    self,
    pattern: Any,
    *,
    where: Any | None = None,
    deadline: float | None = None,
) -> Atom:
```

> Wait for one matching atom and leave it in this space.
>
> A finite deadline raises ``Timeout`` when no match arrives.
>
> `where` is match()'s guard on a blocking wait: a term over the
> pattern's variables, evaluated once a candidate binds them and
> required true, so "wait for a job whose priority is above five" is one
> call. Without it the guard had to live in the caller, as a wait and a
> re-wait around every candidate the guard rejected, and the deadline
> restarted each time round.

### `AsyncMeTTa.take`

```python
async def take(
    self,
    pattern: Any,
    *,
    where: Any | None = None,
    deadline: float | None = None,
) -> Atom:
```

> Wait for and remove exactly one matching atom from this space.
>
> Competing takers cannot receive the same occurrence. A finite
> deadline raises ``TimeoutError`` when no match arrives. `where` is
> peek()'s guard, and it is checked BEFORE the removal, so an atom the
> guard rejects stays where it is for whoever does want it.

### `AsyncMeTTa.cast`

```python
async def cast(self, value: Any, type_: Any = ..., /) -> Any:
```

> Cast this space atom ambiently with one argument, or answer value
> narrowed by this space's type discipline with two arguments. The
> explicit form has the same acceptance a typed call compiles, ':'
> declarations here and &self in scope, protocol types included. A
> refusal raises metta.CastError naming the value's actual types.

### `AsyncMeTTa.trace`

```python
async def trace(self, source: Atom | str, max_events: int = 1000000):
```

> Run a TERM, or source, under the engine's reduction trace and
> answer TraceEvent records: what entered reduction at which depth,
> what it answered, and which reductions failed (a call with no
> exit). `m.trace(S.fib(10))` is the ordinary spelling, the same
> argument `answers` and `eval` take; a string is still a string.
> What is traced executes for real, writes included, like run();
> the wrap exists only while tracing, so untraced calls pay
> nothing. max_events bounds the recording, raising past it rather
> than accumulating a long run's trace without limit.

### `AsyncMeTTa.lint`

```python
async def lint(self):
```

> Diagnose this space for the silently-wrong class: declared
> types nothing defines, arity mismatches, unbound body variables,
> duplicate equations, and references no function or fact carries.
> Answers metta.lint.Finding records, empty when nothing looks
> wrong.

### `AsyncMeTTa.effect_plan`

```python
async def effect_plan(self, target: Any) -> _ops_module.EffectPlan:
```

> Return operations the target may execute and their joined effect.
>
> The engine translates the same atom or source form ``eval`` accepts,
> follows nested compiled calls, and reads current operation metadata.
> It does not execute the target. A later registration change is visible
> on the next call. This is the analysis reified-world admission uses.

### `AsyncMeTTa.digest`

```python
async def digest(self) -> str:
```

> A sha256 hex digest of this space's content: every stored atom,
> equations included, canonicalized (variables numbered, multiset
> sorted) so the same atoms answer the same digest in any insertion
> order and in any process. Two spaces agree on digest() exactly
> when save() would write the same content. Live host objects have
> no cross-process identity and are refused, like save().

### `AsyncMeTTa.clear`

```python
async def clear(self) -> None:
```

> Remove everything stored here, compiled equations included.

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

> Lazily match patterns against this space as one conjunction.
>
> Variables shared between patterns join, the engine's own match/4
> doing the joining. Columns are the variable names in first
> appearance order. `where` is a guard term over the same variables,
> evaluated per join and required true, so restrictions a pattern
> cannot spell (an inequality) compose onto the match:
>
>     m.match(S.person(V.name, V.age), where=V.age.ge(18))
>
> `limit` bounds the answers, the engine stopping at the count
> rather than trimming afterwards. `timeout` (seconds) and
> `inferences` (engine steps) bound the whole call, raising
> TimeLimitError or InferenceLimitError when hit, for joins whose
> size is not known in advance.
>
> The returned Answers view pulls only what Python observes. ``bool``
> pulls one row, exact-one operations pull at most two, and slicing
> retains an Answers view. ``len`` uses an engine-side aggregate when
> no row has yet been pulled.
>
> ``under=`` interprets the same ask through an annotation algebra.
> ``under=counting`` answers one integer computed by an engine
> aggregate, including duplicate derivations without crossing their
> rows into Python. Ordered carriers sort in their declared direction
> before slicing, so ``m.match(q, under=ranked)[:3]`` is top-k and
> ``under=tropical`` puts the cheapest annotation first. Other carriers
> answer ``TaggedAnswer`` values with ``annotation``, ``why()`` and
> ``under(other)``; the latter two reuse the retained derivation rather
> than querying the space again. ``with metta.under(carrier)`` supplies
> the carrier when this call has no explicit ``under=``.
>
> `into=Rows` explicitly chooses the eager Rows face. Other `into=`
> values shape each row into a dataclass, NamedTuple, or
> TypedDict matched by field name, sqlite3's row_factory reading:
> `m.match(S.edge(V.a, V.b), into=Edge)` answers `list[Edge]`,
> and Rows stays the default so nothing is lost. A one-variable query
> whose column holds complete constructor expressions rebuilds those
> expressions instead: `m.match(V.edge, into=Edge)`.
>
>     m.match(S.Edge(V.x, V.y), S.Edge(V.y, V.z))

### `AsyncMeTTa.solve`

```python
async def solve(self, pattern: Any, subject: Any) -> Any:
```

> Run relational ``let`` and return bindings keyed by its variables.
>
> ``solve(4, V.x - 1).x`` places the known value on let's pattern side,
> lets the arithmetic relation solve backwards, and projects ``x``.
> The answer template is derived from the pattern's variables followed
> by any new subject variables, so either relational direction can
> introduce the bindings and the third hand-written ``let`` argument
> disappears.

### `AsyncMeTTa.parallel`

```python
async def parallel(self, *targets: Any, timeout: float | None = None) -> list[Atom | Undefined]:
```

> Evaluate every target concurrently, answering every branch's answers.
>
> This is the engine's `hyperpose`, the parallel twin of `superpose`:
> one SWI thread per branch through concurrent_and/2, so independent
> branches cost about one branch's wall clock rather than their sum.
>
>     m.run("(= (sq $x) (* $x $x))")
>     m.parallel(S.sq(1), S.sq(2), S.sq(3))    # 1, 4 and 9, in any order
>
> This is the **in-engine** fan-out: one janus call, the branches split
> below it. The other route is `pool()`, the **Python-side** fan-out
> across several engines. Reach for this one when the fan-out is a MeTTa
> expression, and for `pool()` when it is a Python loop. They compose,
> so a pool worker may itself evaluate a `parallel()`.
>
> (Before 2026-08-15 this docstring said in-engine fan-out was the only
> route to a second core, because every janus call took one process-wide
> lock. That lock is now per-engine, and Python threads holding their own
> engine measured 1.94x, 3.90x and 7.26x at 2, 4 and 8 threads.)
>
> **Answers arrive in completion order, not argument order**, because
> the branches race. Compare sets rather than sequences, and evaluate a
> `superpose` instead when order carries meaning.
>
> Each target is a term or its source text, as everywhere else. No
> targets answers nothing without calling the engine.
>
> `timeout` bounds the call and is the bound to use here. There is
> deliberately no `inferences=`: the engine's inference limit counts
> the calling thread, and `concurrent_and/2` runs every branch in a
> worker, so a limit of 50,000 does not stop two branches spending six
> million. An unenforceable bound is worse than
> an absent one, so eval() over a `superpose` is the way to bound this
> work by inferences, at the cost of running it on one core.

### `AsyncMeTTa.reducible`

```python
async def reducible(self, target: Any) -> bool:
```

> Whether a head reduces here, asked without evaluating anything.
>
>     m.reducible(S.double(4))     # True
>     m.reducible(S.Point(1, 2))   # False, nothing applies to that head
>
> The same head test eval_status() uses, published on its own because a
> caller who wants to DECIDE about an unreduced term should not have to
> run the term to find out. That decision is the caller's: a term
> nothing applies to is its own answer, which is ordinary MeTTa and how
> `!(hello world)` works, so there is no scope here that refuses one.
>
> The Node extension has had m.reducible() since it existed; Python had
> only eval_status(), which evaluates to tell you.

### `AsyncMeTTa.eval_status`

```python
async def eval_status(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    theory: Any | None = None,
    interpreter: Any | None = None,
) -> list[tuple[str, Atom | Undefined | None]]:
```

> Evaluate a term, pairing each answer with how it was produced.
>
>     m.eval_status(S.double(4))       # [("value", Grounded(8))]
>     m.eval_status(S.Point(1, 2))     # [("not-reducible", Expression(...))]
>     m.eval_status(S.empty())         # [("empty", None)]
>
> `value` means an equation, builtin or special form applied.
> `not-reducible` means no rule applied, so the answer is the term
> itself, which is what MeTTa does with any head it cannot call.
> `empty` means the goal produced no answer at all, and its atom is
> None. Reading the last two as the same thing is the mistake this
> exists to prevent: an unevaluated term and a pruned branch look
> alike from the answers alone. An error is not a status here,
> because it arrives as an exception.
>
> A `bind()` scope binds host values into the term exactly as it
> does for eval(), and it has to: the substitution lands BEFORE the
> reducibility question, so the status of an evaluation that binds
> anything was unaskable without it. Name keys mean symbols and atom
> keys mean themselves, so `bind({V.x: 5})` fills a variable hole.
>
> `theory` and `interpreter` are eval()'s own, and mean the same here.
> This is the method that says which evaluation path produced an answer, so
> being unable to point it at an alternative evaluation relation was the
> sharpest form of the gap: `m.eval_status(target, interpreter=my_eval)`
> is how you see whether an explicit interpreter reduced a term or handed
> it back. `under=` is deliberately NOT here: a carrier annotates every
> answer with an algebra value, so it would make a status row a triple
> rather than the pair it is, which is a question about what a status IS.

### `AsyncMeTTa.run_status`

```python
async def run_status(
    self,
    source: str,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[list[tuple[str, Atom | Undefined | None]]]:
```

> run(), with each directive's answers paired with how they arose.
>
> The grouping and the answers are run()'s own; see eval_status() for
> what the three paths mean.

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

> Return the sole answer as a plain Python value for internal callers.
>
>     m.eval(S.fact(5))[0]         # Grounded(120)
>
> Exactly one answer is the contract: none or several raise naming
> the count, because a caller asking for the value has asserted
> there is one. Grounded answers unwrap to their Python values;
> symbols and structure stay atoms.
>
> This is one point on the answer-cardinality axis, spelled the
> same everywhere it appears: eval() takes every answer (MeTTa's
> collapse), while this private helper demands exactly one. The same
> timeout/inferences bounds apply throughout.
>
> An `(Error ...)` answer raises MettaResultError carrying the
> atom: an error among the answers is the evaluation reporting
> failure, and failure outranks the count. eval() is the method
> that keeps errors as data.

### `AsyncMeTTa.first`

```python
async def first(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Any:
```

> The first answer as a plain Python value, or None for no answers.
>
> The tolerant member of one()'s family: one() asserts exactly
> one, eval() answers all, first() answers the first or nothing,
> decoded by the same rule as one(). An Undefined first answer
> still raises, since None here MEANS no answers. Tolerance is
> about cardinality, not content: a first answer that is an
> `(Error ...)` atom raises MettaResultError exactly as one()
> does, because None must keep meaning "no answers" and an error
> used as a value is the silent kind of wrong.

### `AsyncMeTTa.pure`

```python
async def pure(self, fn: Callable, /, **options: Any) -> Any:
```

> An operation whose answer depends only on its arguments.
>
>     @m.pure
>     def double(x: int) -> int:
>         return 2 * x
>
> The cache-safe class, and the only one memoization and tabling admit
> without an explicit policy.
>
> A GENERATOR written this way is lifted to `nondeterministicReadOnly`,
> because a generator is nondeterministic whatever it declares, and the
> registration reads that off the function rather than asking. The lift
> only ever raises the rank, so it widens the answer-count claim and
> never weakens the effect claim -- but it does mean a generator is not
> cache-safe, which is the whole reason it is lifted out of this class
> .
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.

### `AsyncMeTTa.reads`

```python
async def reads(self, fn: Callable, /, **options: Any) -> Any:
```

> An operation that reads stable state without changing it.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.

### `AsyncMeTTa.writes`

```python
async def writes(self, fn: Callable, /, **options: Any) -> Any:
```

> An operation that changes engine or host state.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.

### `AsyncMeTTa.io`

```python
async def io(self, fn: Callable, /, **options: Any) -> Any:
```

> An operation that observes an external oracle.
>
> A clock, randomness, a network, a file, another runtime.
>
>     @m.io
>     def now() -> float:
>         return time.time()
>
> The fail-closed top of the lattice. Declare it when what the operation
> reaches is decided at run time or by a library the engine cannot bound.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.

### `AsyncMeTTa.unregister_op`

```python
async def unregister_op(self, name: str) -> None:
```

> Remove a registered operation, every arity of it.
>
> An absent name raises KeyError, as convert.unregister_type does:
> removing something that was never there is a mistake worth hearing
> about, not a no-op to absorb.

### `AsyncMeTTa.builtins`

```python
async def builtins(self) -> list[str]:
```

> Every registered function and translator special-form name.

### `AsyncMeTTa.is_function`

```python
async def is_function(self, name: str) -> bool:
```

> Report whether a function is visible from this space.

### `AsyncMeTTa.is_function_here`

```python
async def is_function_here(self, name: str) -> bool:
```

> Whether a function would answer from THIS space: it has clauses
> this space's module sees, its own or the shared ones in user.
> Another space's equations are invisible here and do not count.

### `AsyncMeTTa.arities`

```python
async def arities(self, name: str) -> list[int]:
```

> Compiled predicate arities for a name: MeTTa arity plus one each.

### `AsyncMeTTa.register_prolog`

```python
async def register_prolog(
    self,
    source: str | None = None,
    *,
    path: str | os.PathLike[str] | None = None,
    names: _abc.Sequence[str] | _abc.Mapping[str, str] = (),
) -> tuple[str, ...]:
```

> Register Prolog predicates as MeTTa functions, at native speed.
>
> This is the extension point for a library that wants to run fast.
> op() is the one most people find first, and every call it
> serves crosses the janus boundary: 25.16 inferences and 2.34us per
> call, against 7.16 inferences and 0.13us for the same operation
> written in Prolog.
>
> Read the microseconds, not the inferences. The crossing counts as ONE
> inference and costs real time, so inferences say a Python operation is
> 3.1x a Prolog one while wall clock says 18x. That is a fine price for
> reaching NumPy or an LLM and a bad one for arithmetic in a loop.
>
> A registered predicate keeps its nondeterminism: one that offers three
> solutions gives the MeTTa function three answers.
>
> A predicate follows the compiled calling convention, inputs first and
> one output last:
>
>     m.register_prolog(
>         "'vec-dot'(A, B, Out) :- ... .",
>         names=["vec-dot"],
>     )
>     m.eval("(vec-dot (1 2) (3 4))")[0]
>
> or, for a library shipping a file beside its Python:
>
>     m.register_prolog(path=Path(__file__).parent / "fast.pl",
>                       names=["vec-dot", "vec-norm"])
>
> Every name is registered explicitly rather than discovered, because
> registering a name whose predicate is absent records no arity and then
> compiles every call to it into a partial application instead of
> failing, which is a silent wrong answer rather than an error. This
> raises instead: a name with no predicate behind it is refused before
> it can do that.
>
> The refusals are the engine's, through check_prolog_function_names/3
> and import_prolog_functions/2, so this and the MeTTa spelling enforce
> one rule rather than two copies of it. Three names are refused: one
> with no predicate behind it, a builtin, and a special form.
>
> Nothing is registered unless every name can be, so a typo in the list
> changes nothing. The consulted SOURCE does stay loaded on failure,
> which is deliberate rather than overlooked: loading it again is the
> retry, and it is idempotent, since the source is identified by a hash
> of its own content.
>
> **This is a method on a space and it registers PROCESS-WIDE.** So do
> op and define. Only equations are space-scoped, so an anonymous
> space() isolates one of the three things you can register and
> shares the other two. That is deliberate rather than overlooked: a
> Prolog predicate lives in `user`, every space has to be able to call
> it, and a library loaded inside a named space would define itself
> where the registration could not see it. The method sits on the space
> because that is where the rest of the surface is, not because the
> registration is scoped to it.
>
> The name is owned by one tier. A second registration of the same name
> from another tier is refused, in both directions, naming the owner, so
> two libraries cannot silently take the same name from each other.
>
> A parameter a MeTTa caller should reach unevaluated needs a type
> declaration, which this call does not take yet:
>
>     m.register_prolog("'shape-of'(A, Out) :- Out = [shape, A].",
>                       names=["shape-of"])
>     m.run("(: shape-of (-> Atom Atom))")
>     m.eval("(shape-of (+ 1 2))")[0] # (shape (+ 1 2)), not (shape 3)
>
> Declare it BEFORE anything calls the function. A call site compiled
> while the declaration is absent keeps evaluating the argument even
> after it lands.

### `AsyncMeTTa.register_foreign_library`

```python
async def register_foreign_library(
    self,
    path: str | os.PathLike[str],
    *,
    entry: str | None = None,
    names: _abc.Sequence[str] = (),
) -> tuple[str, ...]:
```

> Load a compiled `.so` and register its predicates as MeTTa functions.
>
> The C tier is the cheapest one on this page's cost table, one
> inference per call, and reaching it used to mean hand-writing two
> Prolog directives into `register_prolog`:
>
>     m.register_foreign_library(Path(__file__).parent / "cbump.so",
>                                entry="install_cbump", names=["c-bump"])
>
> `entry` is the C initialiser, `install_cbump` in
> `install_t install_cbump(void)`; leave it out for a library whose
> entry is plain `install`.
>
> The path is resolved to an ABSOLUTE one here, which is the trap this
> exists to close: `use_foreign_library/2` accepts a path relative to
> the working directory, resolves it, and SWI deprecates that and warns
> on every load, so a library that shipped one worked from the repo root
> and warned or failed anywhere else. A file that is not there is
> refused here rather than inside the engine's loader.
>
> Everything after the load is `register_prolog`, so the same refusals
> apply: a name with no predicate behind it, a builtin, a special form,
> and a name another tier owns.

### `AsyncMeTTa.register_library_path`

```python
async def register_library_path(self, directory: Any, name: str) -> None:
```

> Point MeTTa at a directory of files your package ships.
>
>     # in your package's __init__
>     m.register_library_path(Path(__file__).parent / "prolog", "pettorch")
>
> Subject first, as every register_* call: the directory being
> registered, then the library name it serves.
>
> `(library pettorch fast.pl)` then resolves, from MeTTa and from
> `register_prolog(path=...)`. Without it a pip-installed library is
> under neither `<engine>/../lib` nor a git checkout, so it has to pass
> absolute paths and compute them from `__file__` by hand.
>
> This is SWI's own `file_search_path/2`, so an alias registered here is
> one every SWI tool already understands, and aliases compose: the
> second argument of one may be another alias. Registering the same
> directory twice is a no-op; a directory that is not there is refused
> here rather than at the first import that needs it.

### `AsyncMeTTa.unregister_prolog`

```python
async def unregister_prolog(self, extension: str) -> tuple[str, ...]:
```

> Release everything one extension registered, and its clauses.
>
> The unit is the extension, not the name. `register_prolog` used to
> load a bunch of loose predicates: the engine recorded that each name
> was a function and nothing at all about the library it came from, so
> there was no uninstall to write and a partly-failed registration left
> debris nobody could enumerate.
>
>     :- metta_extension(pettorch, [version('0.3.1')]).
>     :- metta_export("(: vec-dot (-> Number Number Number))").
>
>     m.register_prolog(path="fast.pl")     # names come from the file
>     m.unregister_prolog("pettorch")       # everything it installed
>
> PostgreSQL's rule, and its reason: an individual member cannot be
> dropped on its own, only the whole extension, which is what stops one
> registry keeping a claim on a name another route already replaced.
> The clauses go too, through SWI's own `unload_file/1`, so a name is
> not left callable through a predicate nothing records.
>
> Answers the names it released. Raises when no extension of that name
> is loaded, rather than reporting success for a no-op.

### `AsyncMeTTa.derivation`

```python
async def derivation(
    self,
    target: Any,
    depth: int | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[Any]:
```

> Every proof of an answer, as trees in MeTTa terms.
>
> Each tree names the equations that fired and the stored atoms at the
> leaves, read from the translated_from links the engine keeps for
> every compiled clause. Meta-interpreted, so slower than evaluation;
> a diagnostic, not an evaluation path. The default walks each proof
> without a depth cutoff. A positive depth returns a partial tree with
> Truncated nodes when its budget ends, so an empty list means no proof.
> `timeout` and `inferences` guard the whole search. An evaluation error
> inside a proof surfaces as itself rather than as an empty proof list.
>
> A `bind()` scope binds host values into the term, for the reason
> eval_status needs it: the substitution lands BEFORE the search, so the
> proof of an evaluation that binds anything was unaskable. Name keys
> mean symbols and atom keys mean themselves, so `bind({V.x: 5})` fills
> a variable hole. It takes no `theory` or
> `interpreter`, because a meta-interpreted diagnostic does not select an
> evaluation relation.

### `AsyncMeTTa.why`

```python
async def why(self, pattern: Any, *, where: Any | None = None) -> str:
```

> Why a pattern matches nothing here, in words.
>
> Checks the cheap explanations in order: unknown function, wrong
> arity, no stored atoms with that head. Honest when it cannot tell,
> and honest about the PREMISE too: a pattern that does match is a
> question with a false premise, and this refuses it the way
> Answers.why() always did rather than answering it. Asking why
> `(job $id $pri)` matched nothing, when it matches two atoms, used to
> answer "2 job atom(s) exist here but none unifies with it"
> .
>
> `where` is match()'s guard, and asking with one is where the answer
> gets interesting: a query can be empty because the pattern found
> nothing OR because the guard rejected everything it found, and only
> the guarded question can tell you which.
>
> One implementation, because there were two and they agreed word for
> word on every genuine miss while disagreeing about the premise.

### `AsyncMeTTa.type`

```python
async def type(self, atom: Any) -> Atom:
```

> Return this space's first ``get-type`` answer, including undefined.

### `AsyncMeTTa.doc`

```python
async def doc(self, atom: Any) -> Atom:
```

> Return this space's structured ``get-doc`` answer for one subject.
>
> The answer is the ``(@doc ...)`` atom the engine holds for the
> subject, whether it was documented in MeTTa source or built from a
> Python docstring:
>
>     m.doc(S.area)
>     # (@doc-formal (@item area) (@kind function) (@desc "Circle area.") ...)
>
> A subject with no documentation raises, exactly as ``type`` raises
> for a subject ``get-type`` cannot answer.

### `AsyncMeTTa.integrate`

```python
async def integrate(self, target: Any) -> str:
```

> Install a library integration; see metta.integrate.

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

> Declare how faithfully a space answers queries of one shape.
>
> The declaration is one (handles ...) atom in &metta, and queries
> are routed by the most specific declared shape that matches:
> Exact licenses pushing the caller's bound to the provider, Partial
> and Sound stay candidates the engine re-unifies, and Refuse makes
> the query a loud error instead of a silent partial answer. Write
> (in $x) at a position to match only queries arriving with it
> bound, so a scan-only source is three words:
>
>     rows.handles("(edge (in $a) $b)", "Refuse")
>
> Coherence is checked eagerly in the same transaction as the
> write: a new entry that can disagree with an existing one on some
> query fails here, naming both, rather than on the first query
> that falls into their overlap. The atom is returned; removing it
> from &metta withdraws the declaration.

### `AsyncMeTTa.annotations`

```python
async def annotations(
    self,
    subject_or_algebra: str,
    algebra: str | None = None,
    *,
    capabilities: _abc.Iterable[str] = (),
) -> Atom:
```

> Declare the algebra a context's answer annotations live in.
>
> A context is a space name or an operation name. bool is the
> default at which everything vanishes; ranked admits ordered
> annotations, which is what (top k ...) consumes. A custom name must
> first be introduced with :meth:`algebra`. A one-argument call uses
> this space as the context; the two-argument form keeps an operation
> context as the explicit first subject. Capabilities are
> checked against the algebra's requirements before the catalog write;
> amplitude programs, for example, must explicitly declare ``finite``,
> ``contractive`` and ``staged``. Declaring replaces any earlier row for the
> context, so the reader never meets two disagreeing atoms.

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
    laws: _abc.Iterable[str] = (),
    carrier: _abc.Iterable[Any] = (),
    requires: _abc.Iterable[str] = (),
    order: SemiringOrder | None = None,
) -> Atom:
```

> Declare operations and checked laws for an arbitrary atom carrier.
>
> Public laws are certificates, not wishes. When an equational law is
> named, ``carrier`` must be finite and the operation tables are checked
> exhaustively before the catalog atom lands. ``contraction`` is the
> explicit resource-reuse capability and has no equation to sample.

### `AsyncMeTTa.covers`

```python
async def covers(self, effect: EffectClass | str) -> Atom:
```

> Declare the strongest effect this reified world can handle.
>
> Coverage is a catalog fact ``(covers <space> <effect>)``. World
> evaluation always admits pureStructural plans. A stronger joined plan
> runs only when this declaration is at least as strong; redeclaring
> replaces the previous row atomically.
>
>     orders.covers("writesState")
>     world = orders.reify()

### `AsyncMeTTa.compensates`

```python
async def compensates(self, operation: str, compensation: str) -> Atom:
```

> Declare one recovery operation for an effectful operation.
>
> The catalog row is ``(compensates operation compensation)``. The
> source operation must already be registered at writesState or
> oracleIO, because weaker operations leave no saga receipt. The
> recovery name must already be a host operation or compiled MeTTa
> function. It receives the complete ``(did ...)`` receipt. The runner writes
> the call as ``(quote <receipt>)`` so the receipt is not evaluated
> on the way in; the quote is a barrier and does not survive, so the
> handler is handed the receipt itself.
> Redeclaring replaces the old row atomically.

### `AsyncMeTTa.add_tagged_fact`

```python
async def add_tagged_fact(self, tag: Any, proposition: Any) -> Atom:
```

> Store ``(fact tag proposition)``, the normative annotation form.

### `AsyncMeTTa.add_tagged_rule`

```python
async def add_tagged_rule(self, tag: Any, head: Any, *premises: Any) -> Atom:
```

> Store one rule generated by the algebra-agnostic tag threader.

### `AsyncMeTTa.image`

```python
async def image(self, type_name: str, setting: ImageMode) -> Atom:
```

> Choose how one Python type crosses one context boundary.
>
> opaque carries the live object by identity; transparent projects its
> structural MeTTa image; auto makes that choice from the value's size
> and replayability. A later declaration for the same context and type
> replaces the earlier one, so an attached provider reads one policy.
> Use ``_`` as the type name for a context-wide fallback.

### `AsyncMeTTa.sample`

```python
async def sample(self, query: str | Atom, *, k: int = 10, seed: int = 7) -> list[Atom]:
```

> Choose ``k`` tagged alternatives with replacement by ``(rate n)``.
>
> The argument names and list result follow ``random.choices``. A local
> seeded generator makes repeated calls reproducible without changing
> Python's process-global random state.

### `AsyncMeTTa.source`

```python
async def source(self, kind: SourceKind) -> Atom:
```

> Declare a space's consumption discipline.
>
> repeated is the default: the source re-enumerates. linear is a
> one-shot source, a cursor or a feed: its SECOND consumption is a
> loud error naming the space, where the undeclared floor answers a
> silently empty set from the drained object; re-registering the
> provider resets the mark, because a fresh provider is a fresh
> source. peek promises reads do not consume, which the conformance
> kit checks by enumerating twice.

### `AsyncMeTTa.on_error`

```python
async def on_error(
    self,
    subject_or_pattern: str | Atom,
    pattern_or_mode: str | Atom,
    mode: OnError | None = None,
) -> Atom:
```

> Declare what a context's failure becomes, per query shape.
>
> abort is the undeclared floor: the provider's error propagates.
> keep delivers the failure as one (Error &lt;query> &lt;reason>) answer
> beside the answers that already streamed, the language's own
> error-as-alternative reading. empty ends the stream silently, BY
> declaration, which is what separates it from a swallowed error.
> Shapes route most-specific-first exactly as (handles ...) entries
> do. Control signals and transport failures are never kept or
> emptied: an interrupt is the caller's, and an absent backend has
> said nothing about the data.

### `AsyncMeTTa.merge`

```python
async def merge(self, pattern: str | Atom, policy: AnswerPolicy) -> Atom:
```

> Declare how the engine merges one query shape's answers
> ACROSS contexts, for the multi-context idiom
> (match (superpose (&a &b)) ...).
>
> depth is today's space-after-space order and the undeclared
> floor. fair interleaves the streams round-robin. best-first is a
> k-way ordered merge by annotation, sound only when every merged
> context declares (emits &lt;ctx> best-first), and loudly refused
> without. Shapes route most-specific-first as everywhere.

### `AsyncMeTTa.context`

```python
async def context(self, world: World) -> Atom:
```

> Record what a space's absence means.
>
> Negation as failure reads absence as falsity, which is only
> sound over a world the answerer holds whole, so a negated goal
> may consult a foreign space only when it declares closed-world;
> an undeclared one refuses under negation loudly. Native spaces
> are the engine's own database and closed by construction.

### `AsyncMeTTa.agenda`

```python
async def agenda(self, policy: AgendaPolicy, function: str | None = None) -> Atom:
```

> Declare which reaction fires first when several match one write.
>
> declaration is the default and the order they were declared, which is
> what the engine produced by accident before this was a policy;
> recency is the most recently declared first; specificity is the most
> tests in the pattern first; priority reads each reaction's own
> declared number, highest first; and user names a MeTTa function that
> SCORES a reaction, highest first. Every policy breaks ties on
> declaration order.
>
>     alarms.reacts("(alert $w)", "(insert &log (all $w))")
>     alarms.reacts("(alert fire)", "(insert &log (fire))", priority=9)
>     alarms.agenda("priority")

### `AsyncMeTTa.reacts`

```python
async def reacts(
    self,
    pattern: str | Atom,
    operation: str | Atom,
    priority: int | None = None,
) -> Atom:
```

> Declare a reaction, stored as an (on ...) atom: when an atom
> matching PATTERN lands in the space, OPERATION runs under the
> match's bindings.
>
> The managed heads are (insert &lt;ctx> &lt;atom>), (retract &lt;ctx>
> &lt;atom>) and (revise &lt;ctx> &lt;old> &lt;new>), engine-routed rules
> going through the same write paths as direct writes. Declaring
> installs the engine's write hook, which is why reactions go
> through here or metta_install_bridges rather than a bare
> add-atom.
>
> A subscription bridge is the NEIGHBOUR, not a special case of this:
> a reaction's operation runs engine-side, so it reaches registered
> spaces, while the bridge rule delivers Python-side to anything
> with add and remove, an unregistered or remote target included.
> Same multi-context-systems idea, two delivery tiers.

### `AsyncMeTTa.admits`

```python
async def admits(self, type_name: str) -> Atom:
```

> Type a pool's membership: only TYPE-carrying atoms enter.
>
> A thread pool is a space whose atoms are spaces, and this is its
> declaration: (admits &pool Space) plus per-atom (: &lt;space> Space)
> declarations make membership a type judgement the ontology
> already knows how to make.

### `AsyncMeTTa.capacity`

```python
async def capacity(self, limit: int) -> Atom:
```

> Bound a pool: an add beyond LIMIT atoms is refused loudly.

### `AsyncMeTTa.atomicity`

```python
async def atomicity(self, atomicity: Atomicity) -> Atom:
```

> Declare what a space's writes promise inside a transaction.
>
> Named for what it declares rather than for the atom it stores, which
> stays `(writes <ctx> ...)`: `writes` on a Space is the effect
> decorator for an OPERATION, and one object cannot spell two concepts
> one way.
>
> transactional providers implement metta.foreign.Transactional and
> are committed or rolled back WITH the engine's transaction;
> best-effort is the author's declared acceptance of a write that
> survives a rollback; atomic-single refuses transactional writes.
> Undeclared spaces refuse them loudly too, because a foreign write
> silently surviving a rolled-back transaction is the wrong answer
> the declaration exists to replace.

### `AsyncMeTTa.emits`

```python
async def emits(self, policy: AnswerPolicy) -> Atom:
```

> Declare the order a context emits its own answers in.
>
> best-first is the promise (top k ...) needs before its bound may
> reach the provider: the first k of a best-first emission ARE the
> k best. Distinct from the (merge &lt;pattern> &lt;policy>) strategy,
> which is how the ENGINE merges answers across several contexts.

### `AsyncMeTTa.events`

```python
async def events(
    self,
    delivery: Delivery | None = None,
    order: EventOrder = EventOrder.unordered,
) -> Atom | Any:
```

> Return the event stream, or declare what this context promises.
>
> Subscribability is a promise about the context, not something its
> methods alone establish. A native space needs no declaration:
> every write into it runs the engine's own hooks, so it delivers
> per-write-exactly and ordered by construction. A FOREIGN context
> declares, and one that declares nothing refuses a subscription
> instead of serving one that silently misses writes.
>
>     shared.events("at-most-once")   # redis pub/sub
>     mirror.events("per-write-exactly", "ordered")
>
> delivery is at-most-once, at-least-once or per-write-exactly, and
> order is ordered or unordered, defaulting to unordered because an
> omitted promise is the weaker one. A Python provider says the same
> thing by overriding delivers(), which registration writes here.

### `AsyncMeTTa.aclose`

```python
async def aclose(self, timeout: float = DEFAULT_CLOSE_TIMEOUT) -> None:
```

> Cancel acquired streams, then stop and detach the worker.

### `AsyncMeTTa.stop`

```python
def stop(self, timeout: float = DEFAULT_CLOSE_TIMEOUT) -> None:
```

> Synchronously cancel streams and stop without an event loop.

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
async def connect(
    space: str | Symbol | Expression | Space = _DEFAULT_SPACE,
    *,
    metta: Space | None = None,
) -> AsyncMeTTa:
```

> An AsyncMeTTa with its engine thread already running, aiosqlite's
> own naming for the entry point.
