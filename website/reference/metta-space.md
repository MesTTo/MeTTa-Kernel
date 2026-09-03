# `metta.Space`

Source: `extensions/python/metta/_space.py`.

> Provide the narrow MeTTa context and context-relative Space handles.

The entries below reproduce the source signatures and docstrings.

## `current_space`

```python
def current_space(default: str = _DEFAULT_SPACE) -> _SpaceId:
```

> The space whose module the ENGINE is evaluating in right now.
>
> Callable from inside a registered operation, where it answers the space
> of the program that called it: janus re-enters the engine cleanly, so
> an operation can behave per-space without the space being an argument.
> Outside any evaluation it answers the default.

## `Space`

```python
class Space(Handle):
```

> A space bound to the engine: the way in from Python.
>
> MeTTa keeps one engine per process; every context shares it. The
> process-default home is &self, the space the CLI itself uses, so source
> pasted from a .metta file behaves identically through ``metta.engine()``.
> ``MeTTa()`` itself is a fresh context over its own anonymous home, so two
> contexts never share stored state; ``Space()`` is still the process
> home, and ``metta.engine()`` the context that borrows it.
>
> A named space isolates both its atoms and its EQUATIONS, and the rule for
> equations has a third part this docstring used to get wrong by calling
> them process-wide. They are per-space, with a dynamic fallback to &self
> and local shadowing:
>
>     equation defined in     &self       s1          s2
>     ------------------      ---------   ---------   ---------
>     s1                      unreduced   answers     unreduced
>     &self                   answers     answers     answers
>     both                    &self's     s1's        &self's
>
> So a helper put in &self is reachable from every space, one put in a named
> space is private to it, and a name defined in both resolves to the local
> one where it exists. Registrations are the thing that really is
> process-wide, which the anonymous ``space()`` factory says.
>
>     from metta import MeTTa, S, V
>
>     m = MeTTa().self
>     m.run("(= (foo) boo) !(foo)")     # [[Symbol('boo')]]
>     m.add(S.Parent(S.Tom, S.Bob))
>     m.match(S.Parent(V.x, S.Bob))

### `Space.name`

```python
def name(self) -> _SpaceId:
```

> The live engine name represented by this handle.

### `Space.space_names`

```python
def space_names(self) -> list[str]:
```

> Every space name this engine registers, sorted: '&self' and
> '&metta' from boot, every native space something created or wrote to,
> and every foreign space currently bound. (new-space) and (spawn ...)
> create, so their answers are here at once; naming a space never
> registers it, so Space('&kb') is not here until a write, and a bind!
> token's target appears once something is stored under it.

### `Space.drop`

```python
def drop(self) -> None:
```

> Clear this space and release an anonymous name for reuse.
>
> Dropping unregisters a Python provider and closes only backing state
> owned by this handle. A foreign provider with a clear/drop lifecycle,
> such as MORK, releases its provider state.
> A named space's public name is not an anonymous allocation and never
> enters the anonymous pool. The engine-owned &self and &metta roots
> refuse before any Python-side state changes; drop the caller's own
> context or a named space instead.
> Subscriptions on the space cancel with it: a pooled name reused later
> must not deliver to the old life's watchers. The handle itself dies
> here, and dropping twice is a no-op, as closing twice is.

### `Space.dropped`

```python
def dropped(self) -> bool:
```

> Whether :meth:`drop` has released this handle's space.

### `Space.to_wire`

```python
def to_wire(self) -> list:
```

> Encode the live engine reference as a portable space operand.

### `Space.metatype`

```python
def metatype(self) -> str:
```

No docstring is defined.

### `Space.bind`

```python
def bind(self, values: _abc.Mapping[str, Any] | None = None, /, **named: Any) -> _BoundValues:
```

> Scope named host values for :meth:`run` without a call flag.

### `Space.run`

```python
def run(
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

### `Space.profile`

```python
def profile(
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

### `Space.profile_extension`

```python
def profile_extension(
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

### `Space.save`

```python
def save(
    self,
    path: str | os.PathLike[str],
    *,
    format: SaveFormat = SaveFormat.metta,
    timeout: float | None = None,
    inferences: int | None = None,
) -> int:
```

> Write every stored atom of this space, equations included, as
> MeTTa source by default. ``format="fast"`` writes a version-pinned
> image of the receiver's equation world: its own atoms, owned child
> spaces, aliases bound to those spaces, and translator rules. Loading
> the image mints fresh runtime space identities and preserves their
> graph relationships. The returned count remains the receiver's own
> atom count. A path ending .gz writes gzip compressed in either format,
> and load and import! read it back under the same name. The completed
> sibling file is synced and then atomically replaces the target, so a
> failed save leaves the old file intact. Atoms carrying live host
> objects cannot survive either file and are refused.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the save with
> the engine's own guards, exactly as they bound load(). A text save
> examines the receiver; a fast save also traverses its reachable
> equation-world graph and registries. Those guards therefore bound all
> state the chosen format writes, and the atomic replace above makes a
> stopped save safe: the sibling is never moved into place.
>
> There is no `format` on load(), and that is not an omission. When you
> save, the file does not exist and something has to say which of the two
> to write; when you load, load() reads which it is, `.gz` included.

### `Space.load`

```python
def load(
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

### `Space.parse`

```python
def parse(self, source: str) -> Atom:
```

> Read one form into an atom without evaluating it.

### `Space.register_token`

```python
def register_token(
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

### `Space.unregister_token`

```python
def unregister_token(self, pattern: str | _re.Pattern[str]) -> None:
```

> Remove a reader-token class; an absent pattern is already removed.

### `Space.add`

```python
def add(self, *atoms: Any) -> None:
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

### `Space.remove`

```python
def remove(self, atom: Any, *more: Any) -> bool | int:
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

### `Space.transfer`

```python
def transfer(self, *atoms: Any, to: Space) -> int:
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

### `Space.atoms`

```python
def atoms(self) -> list[Atom]:
```

> Every stored atom in this space.

### `Space.peek`

```python
def peek(self, pattern: Any, *, where: Any | None = None, deadline: float | None = None) -> Atom:
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

### `Space.take`

```python
def take(self, pattern: Any, *, where: Any | None = None, deadline: float | None = None) -> Atom:
```

> Wait for and remove exactly one matching atom from this space.
>
> Competing takers cannot receive the same occurrence. A finite
> deadline raises ``TimeoutError`` when no match arrives. `where` is
> peek()'s guard, and it is checked BEFORE the removal, so an atom the
> guard rejects stays where it is for whoever does want it.

### `Space.cast`

```python
def cast(self, value: Any, type_: Any = ..., /) -> Any:
```

> Cast this space atom ambiently with one argument, or answer value
> narrowed by this space's type discipline with two arguments. The
> explicit form has the same acceptance a typed call compiles, ':'
> declarations here and &self in scope, protocol types included. A
> refusal raises metta.CastError naming the value's actual types.

### `Space.trace`

```python
def trace(self, source: Atom | str, max_events: int | None = None):
```

> Run a TERM, or source, under the engine's reduction trace and
> answer TraceEvent records: what entered reduction at which depth,
> what it answered, and which reductions failed (a call with no
> exit). `m.trace(S.fib(10))` is the ordinary spelling, the same
> argument `answers` and `eval` take; a string is still a string.
> What is traced executes for real, writes included, like run();
> the wrap exists only while tracing, so untraced calls pay
> nothing. max_events bounds the recording; past it the recording
> stops and the result's `truncated` is True, rather
> than accumulating a long run's trace without limit.

### `Space.lint`

```python
def lint(self):
```

> Diagnose this space for the silently-wrong class: declared
> types nothing defines, arity mismatches, unbound body variables,
> duplicate equations, and references no function or fact carries.
> Answers metta.lint.Finding records, empty when nothing looks
> wrong.

### `Space.effect_plan`

```python
def effect_plan(self, target: Any) -> _ops_module.EffectPlan:
```

> Return operations the target may execute and their joined effect.
>
> The engine translates the same atom or source form ``eval`` accepts,
> follows nested compiled calls, and reads current operation metadata.
> It does not execute the target. A later registration change is visible
> on the next call. This is the analysis reified-world admission uses.

### `Space.copy`

```python
def copy(self) -> Space:
```

> This space's contents in a new anonymous space, cloned through
> one bulk write, so equations copy as equations and keep running:
> "a scratch space set up like production" is one line. The handle
> is ``space()``'s kind, so drop it, or use it as a context
> manager, to return the name. copy.copy(m) answers the same
> through the copy protocol. There is deliberately no __deepcopy__:
> stored Python objects keep their identity across the clone, the
> shallow reading, and a deep clone of a live engine handle has no
> meaning to promise.

### `Space.reify`

```python
def reify(self):
```

> Capture this space as an immutable, independently evaluable world.

### `Space.commit`

```python
def commit(self, world: Any) -> None:
```

> Apply one reified world's diff through this originating space.

### `Space.digest`

```python
def digest(self) -> str:
```

> A sha256 hex digest of this space's content: every stored atom,
> equations included, canonicalized (variables numbered, multiset
> sorted) so the same atoms answer the same digest in any insertion
> order and in any process. Two spaces agree on digest() exactly
> when save() would write the same content. Live host objects have
> no cross-process identity and are refused, like save().

### `Space.clear`

```python
def clear(self) -> None:
```

> Remove everything stored here, compiled equations included.

### `Space.match`

```python
def match(
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

### `Space.stream`

```python
def stream(
    self,
    *patterns: Any,
    where: Any | None = None,
    limit: int | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
) -> Cursor:
```

> match(), pulled: the same conjunction and guard, answered one
> row at a time through a cursor the engine holds open.
>
>     with m.stream(S.edge(V.a, V.b), S.edge(V.b, V.c)) as rows:
>         for row in rows:
>             if wanted(row):
>                 break            # nothing further is even joined
>
> The join's state lives inside an SWI engine between pulls, each
> pull is one ordinary call, and unrelated calls interleave freely,
> so a huge join costs one row of work per row actually taken where
> match() computes and decodes every answer up front. `timeout`
> bounds each pull's wall time; `inferences` is one budget for the
> cursor's whole engine work, spent across pulls, and the cursor
> stops on the answer that passes it. Because the budget counts the
> cursor's own engine, it is not the number ``stats()`` reports for
> the same work: ``stats()`` reads the calling thread's counters,
> which see the pull loop rather than the engine. The cursor
> enumerates under the engine's logical update view: writes made
> after the first pull are not seen by this cursor.
>
> `limit` and `under` mean what they mean on match(), because this is
> match() and the cursor underneath already carried both: a tagging
> algebra (ranked, tropical, prov) answers one TaggedAnswer per pull,
> the same value match() answers. `under='counting'` is refused by
> name, because a counting fold is ONE number over the whole answer
> set and a cursor exists not to have one.
>
> What this method does NOT take is match()'s `into=`, the same kind of
> difference: `into` builds a container out of every row.

### `Space.assuming`

```python
def assuming(self, *facts: Any) -> _Assuming:
```

> Facts held only inside a with-block: the assumptions reading of
> a what-if query, added on entry, removed on exit, exceptions
> included.
>
>     with m.assuming(S.closed(S.bridge)):
>         detour = m.match(S.route(V.r), where=...)

### `Space.transaction`

```python
def transaction(self, target: Callable[[], _R] | Any, /) -> Any:
```

> Run one callable or term inside a closed engine transaction.
>
> The two inputs preserve their native failure laws. A zero-argument
> Python callable commits its return value and rolls back on a Python
> exception. A term returns its engine answers and rolls back when that
> answer set is empty, exactly like ``(transaction ...)``.
>
>     m.transaction(lambda: migrate(m))
>     m.transaction(S.progn(write, verify))
>
> Every engine write the callable makes, stored atoms, equations
> and their compiled clauses included, commits or rolls back
> together. An exception is the callable's rollback trigger, because a
> Python callable cannot fail the Prolog way, and it re-raises AS
> ITSELF: your ValueError arrives as ValueError with the engine
> boundary in its chain. Only the engine's dynamic state rolls
> back; what the callable did on the Python side (a list appended,
> a file written) is yours to undo, SWI transactions being
> database-scoped.
>
> Transactions nest, SWI's own semantics: an inner commit is
> relative to its outer transaction, so an outer rollback discards
> inner work too.
>
> There is deliberately no `with m.transaction():` form. SWI's
> transaction/1 takes a closed goal; there is no open begin/commit
> to hold across a block, and pretending otherwise would lie about
> the isolation actually provided. transactional() is the
> decorator twin.

### `Space.saga`

```python
def saga(self, receipts: Space):
```

> Open a committed-receipt saga over this execution space.
>
> ``receipts`` is an ordinary space that stores ``(did op args result)``
> atoms. Run each forward term with the returned context manager's
> ``run`` method. A normal exit keeps its work and receipts; an
> exceptional exit invokes declared compensations in reverse commit
> order and removes each successfully recovered receipt.
>
>     with orders.saga(receipts) as saga:
>         saga.run(S.charge(S.order_7))
>
> Operations ranked writesState or oracleIO leave receipts. Declare a
> handler with ``compensates`` before recovery. Handlers receive the
> complete receipt, written at the call site as ``(quote <receipt>)`` so
> it is not evaluated on the way in, and must be idempotent, because a
> failed compensation remains queryable and is retried by
> ``rollback()``.

### `Space.solve`

```python
def solve(self, pattern: Any, subject: Any) -> Any:
```

> Run relational ``let`` and return bindings keyed by its variables.
>
> ``solve(4, V.x - 1).x`` places the known value on let's pattern side,
> lets the arithmetic relation solve backwards, and projects ``x``.
> The answer template is derived from the pattern's variables followed
> by any new subject variables, so either relational direction can
> introduce the bindings and the third hand-written ``let`` argument
> disappears.

### `Space.watch`

```python
def watch(
    self,
    pattern: Any,
    *,
    on: str = 'add',
    where: Any | None = None,
    deadline: float | None = None,
    queue_max: int | None = None,
):
```

> Yield matching changes, raising Timeout after each quiet deadline.
>
> `queue_max` bounds the subscription underneath, the same bound
> subscribe() takes; a watch could not name it before, though the
> subscription it builds always had one.

### `Space.limits`

```python
def limits(
    self,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    stack: int | None = None,
) -> ScopedLimits:
```

> Scoped default bounds for every call in the with-block:
>
>     with m.limits(inferences=1_000_000, timeout=2.0):
>         m.match(...)      # bounded without saying so again
>
> decimal.localcontext's shape, contextvars underneath, so the
> scope is async-correct and per-task. A per-call timeout= or
> inferences= still overrides, which is the whole ladder: one
> block replaces the parameter forest, and the forest remains
> for whoever wants per-call control.
>
> stack= is SWI's combined stack ceiling in BYTES, the bound a
> runaway recursion hits as a StackOverflow error atom. It is NOT
> MeTTa's reduction depth: that is the max-stack-depth pragma,
> `(with-pragma! ((max-stack-depth N)) expr)`, which counts
> reduction steps and is scoped in the program text.

### `Space.capture`

```python
def capture(self) -> CapturedOutput:
```

> Collect printed engine text without changing answer shapes.
>
> with m.capture() as output:
>     groups = m.run("!(println! hello) !(+ 1 2)")
> assert groups == [[3]]
> assert output.text == "hello\n"

### `Space.atomic`

```python
def atomic(self) -> ScopedExecution:
```

> Make each run in the block one committing engine transaction.

### `Space.speculative`

```python
def speculative(self) -> ScopedExecution:
```

> Run each source against a snapshot and discard its writes.

### `Space.batch`

```python
def batch(self) -> _Batch:
```

> Collect this space's add() calls and cross once at exit:
>
>     with m.batch():
>         for edge in edges:
>             m.add(edge)          # collected, no crossing yet
>     # one add_many crossing happened here
>
> The write forms are add for one or several atoms, batch for a region,
> transaction for all-or-nothing work, and a provider's bulk method
> underneath them. A batch is a transport economy and must not invent
> semantics, so the sharp edges are stated and enforced: reads
> inside the block see the space WITHOUT the pending adds; a
> remove() or clear() on this space inside the block refuses,
> because it would otherwise silently order around writes the
> program already made; and an exception discards the pending
> batch rather than landing writes the code after the raise never
> saw. Compose with transaction() for atomicity: batch for
> economy, transaction for all-or-nothing, or both.

### `Space.transactional`

```python
def transactional(self, fn: Callable[_P, _R], /) -> Callable[_P, _R]:
```

> transaction()'s decorator twin, the atomic shape Django made
> familiar: each CALL of the wrapped function runs inside its own
> engine transaction. Decorating runs nothing, exactly as a
> decorator should not; reach for transaction() to run one
> callable now.
>
>     @m.transactional
>     def migrate():
>         m.add(...)
>         m.remove(...)
>
>     migrate()     # one transaction; a raise rolls it all back

### `Space.prepare`

```python
def prepare(self, *patterns: Any, where: Any | None = None) -> Prepared:
```

> A query whose shape is fixed and whose facts are not: the wire
> form and columns build once, and each solve() may bring per-call
> facts (given=) that leave nothing behind.
>
>     route = m.prepare(S.path(V.a, V.b), where=V.a != ...)
>     route.solve()
>     route.solve(given=[S.edge(S.x, S.y)])

### `Space.eval`

```python
def eval(
    self,
    target: Any,
    *more: Any,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
    theory: Any | None = None,
    interpreter: Any | None = None,
) -> list[Atom | Undefined] | list[list[Atom | Undefined]]:
```

> Evaluate a term, returning every answer.
>
> This is what !(...) runs, minus the printing: the engine's
> translate_expr over the term, then its goals. Nondeterminism means
> the list can hold any number of answers, including none.
>
> Variadic, and that is how evaluation BATCHES: several terms ride
> one engine crossing and the answer is one group per term in call
> order, run()'s own grouping carried to the term form. One term
> keeps its flat list, so the scalar reading never changes shape.
>
> Every answer carries its truth: an answer that is undefined under
> Well Founded Semantics (a tabled loop through tnot, reachable via
> translatePredicate or injected Prolog) arrives as an Undefined
> holding the answer and the delay condition that makes it
> undefined, never as an ordinary-looking value. A term to which no
> rule applies is the ordinary answer itself; `eval_status()` names
> that path `not-reducible`. run() does not carry the third truth
> value; evaluate through eval() when it matters.
>
> `bind()` binds named host values into the term before it evaluates,
> exactly as it does for run(): inside `with m.bind({"x": tensor})`,
> `m.eval("(decide x)")` hands the tensor itself to the rule, by
> identity, rather than a printed form of it. The name is the SYMBOL x
> and not the variable $x, in this call and the source form alike. The
> evaluation calls take the same vocabulary as the source form, so using
> a term instead of source text costs no change of spelling.
>
> A key may be a NAME or an ATOM. A name means the symbol of that name,
> which is what the engine's own substitution matches and what run()
> takes. An atom means exactly that atom, so `bind({V.x: 5})` fills a
> VARIABLE hole -- the one substitution `unify` reports and the one no
> evaluation call could apply, because a variable crosses the wire as ['v', 'x']
> where a symbol crosses as ['s', 'x'] and the engine matches names.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the call,
> raising TimeLimitError or InferenceLimitError when hit. A surrounding
> `capture()` scope collects printed text without changing the list.
>
> `under`, `theory` and `interpreter` are answers()' three, and mean
> exactly what they mean there; `eval()` materialises that query as a list. A
> surrounding `with metta.under(carrier)` reaches here too, which it did
> not before: match() and answers() both honoured such a scope while
> eval() ignored it in silence.

### `Space.answers`

```python
def answers(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
    theory: Any | None = None,
    interpreter: Any | None = None,
) -> Answers[Any]:
```

> Evaluate lazily as an immutable, cached and replayable view.
>
> Creating the view performs no engine work. Existence pulls at most
> one answer, ``one()`` at most two, and ordinary iteration resumes the
> same held evaluation.
>
> ``under=`` has the same carrier semantics as ``match``. In
> particular, ``space.answers(call, under=counting).one()`` counts the
> call's answer derivations inside the engine, and ordered carriers
> order their annotated ``TaggedAnswer`` values before a slice pulls
> its prefix. A surrounding ``metta.under(carrier)`` is used only when
> this call does not pass an explicit carrier.
>
> ``theory=`` treats an atom or iterable of atoms as the theory value for
> this ask. That value replaces the receiver's own equational program.
> Engine builtins and the shared ``&self`` session space remain in scope
> exactly as they are for every space, and names the theory defines
> shadow inherited ones. It installs the theory in an isolated scratch
> space on the first pull, evaluates there, and drops the space when the
> view is exhausted or abandoned. The receiver is unchanged. This
> mirrors reflective descent functions whose inputs are a reified module
> and term.
>
> ``interpreter=`` instead evaluates the explicit full-interpreter
> application ``(interpreter target %Undefined% space)`` for this ask,
> which is the shape MeTTa's own evaluation function has: it says
> "reduce with YOURS rather than the engine's".
>
> The two COMPOSE, and are the head and the third argument of one
> application rather than rival answers to one question: with both, the
> interpreter is handed the theory's space, so it interprets the theory
> . They used to refuse together.
>
> The INTERPRETER must declare its first parameter `Atom`, MeTTa's own
> way to receive an argument unevaluated, or the engine reduces the
> target before the interpreter ever sees it; and its RETURN metatype
> `%Undefined%`, or the interpreter's own answer is not reduced either.
> `(: e (-> Atom Atom Atom %Undefined%))` is the declaration.

### `Space.parallel`

```python
def parallel(self, *targets: Any, timeout: float | None = None) -> list[Atom | Undefined]:
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

### `Space.pool`

```python
def pool(self, workers: int | None = None) -> Any:
```

> A pool of worker threads that each hold their own Prolog engine.
>
> The Python-side twin of `parallel()`. Each worker attaches its own
> engine, so the process lock that serialises the home engine does not
> apply to it and the calls genuinely run at once.
>
>     m.run("(= (sq $x) (* $x $x))")
>     with m.pool(workers=4) as p:
>         p.map(lambda n: m.eval(S.sq(n))[0], range(64))
>
> Use it as a context manager so every engine is released. `workers`
> defaults to os.cpu_count(). This handle stays usable from the workers:
> a MeTTa is a space name over the process runtime, not thread-owned.
>
> Reach for `parallel()` instead when the fan-out is a MeTTa expression
> rather than a Python loop; the two compose.

### `Space.reducible`

```python
def reducible(self, target: Any) -> bool:
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

### `Space.eval_status`

```python
def eval_status(
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

### `Space.run_status`

```python
def run_status(
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

### `Space.stats`

```python
def stats(self) -> _StatsBlock:
```

> The engine's own counters over a with-block, as deltas.
>
>     with m.stats() as s:
>         m.match(S.edge(V.x, V.y), S.edge(V.y, V.z))
>     s.inferences        # engine steps the block spent
>     s.cputime           # engine CPU seconds
>     s.walltime          # wall seconds, Python's clock
>     s.gc_count, s.gc_freed, s.gc_time
>     s.table_bytes       # answer-table bytes grown, tabling's memory
>
> The counters are SWI's statistics/2 read on the CALLING thread, so
> a block that runs other threads' engine work counts that work too;
> the honest reading is "what this thread saw the engine do while the
> block ran". A lazy cursor is the exception, and a large one: its
> goal runs in an SWI engine, an engine counts its own inferences,
> and this thread cannot see them. Draining 20,000 rows through the
> match cursor reports 40,049 inferences against about 381,000 the
> cursor's engine really spent, 10.5% of the work; the real cost is
> readable off the `inferences` budget, which does count the engine
> . The evaluation cursor behind `answers()`
> does report its engine's spend, so that one is whole. The z3py
> Solver.statistics() reading, on the engine this library actually
> has.

### `Space.op`

```python
def op(
    self,
    fn: Callable | None = None,
    *,
    name: str | None = None,
    transport: Literal['encoded', 'raw'] = 'encoded',
    effect: EffectClass | str | None = None,
    declarations: Iterable[Atom] = (),
    arities: list[int] | None = None,
    inverse: Callable | None = None,
) -> Any:
```

> Register a Python callable as a MeTTa function, decorator-style.
>
>     @m.op(effect=EffectClass.pureStructural)
>     def double(x: int) -> int:
>         return 2 * x                    # !(double 21) -> 42
>
>     @m.op(effect=EffectClass.nondeterministicReadOnly)
>     def neighbours(n: int):
>         yield n - 1                     # a generator is nondeterministic
>         yield n + 1
>
> An implicit Python name maps underscores to MeTTa hyphens. ``name=``
> is exact, for source vocabularies that deliberately use underscores.
>
> A name must read back as one MeTTa symbol. A space, parenthesis,
> quote, comment opener, variable spelling, number, boolean, or another
> registered reader token is refused before any registry changes, with
> the name and the conflicting character in the error.
>
> Annotations become ordinary `(: ...)` declarations. An unannotated
> callable makes no type claim. `transport="raw"` skips wire encoding
> both ways and is reflected as raw_det or raw_many in `(op ...)`;
> symbols then reach Python as strings, so encoded transport is the
> fidelity-preserving default. unregister_op(name) removes every
> registered arity and every declaration the registration owns.
>
> An `Atom` parameter changes evaluation order. The declaration tells
> the compiler to pass the argument as written, before it reduces:
>
>     @m.op(effect=EffectClass.pureStructural)
>     def anyatom(term: Atom) -> Atom:
>         return term
>
>     # with (= (side) 42), !(anyatom (side)) answers (side)
>
> An unconstrained parameter receives the evaluated value instead, so
> the otherwise identical `def anyval(term): return term` answers 42.
> Use `Atom` only when the operation deliberately implements syntax or
> a control form; it is not just a static hint.
>
> An encoded generator may instead yield exact tuples as positional
> relation rows, or exact dicts keyed by parameter name as sparse rows.
> The engine unifies each candidate against the written call, so one
> implementation serves free, partially bound, and ground arguments:
>
>     @m.op
>     def route(origin, destination):
>         yield (S.paris, S.lyon)
>         yield {"destination": S.nice}  # origin is unconstrained
>
>     # route(V.origin, S.lyon).rows[0].origin == S.paris
>
> Each matching occurrence answers unit and duplicate yields remain
> duplicate answers. Use `Answer(value=...)` when an exact tuple or dict
> is the result value rather than a parameter row. Relational rows
> require encoded transport; raw calls cannot carry unbound argument
> positions.
>
> When evaluation order stays ordinary but the callable needs the
> resulting Atom wrappers, declare that policy as data:
>
>     m.op(
>         inspect_atom,
>         name="inspect-atom",
>         effect=EffectClass.pureStructural,
>         declarations=[parse("(arguments inspect-atom atoms)")],
>     )
>
> The declaration is matchable in &metta and is retired with the
> operation. Raw transport refuses this declaration because it bypasses
> the atom codec entirely.
>
> The cost ladder, measured on the maintained box in inferences per
> call, explains the transport choice:
>
>     native MeTTa function            9.11   the floor
>     transport="raw"                10.11   opaque handles, near-native
>     encoded                        17.11   encoded values
>     encoded, typed literal         17.11   the check hoists to compile
>     py-call, dotted                 22.11   the ad-hoc escape hatch
>
> The ergonomic default (encoded, typed) costs about 1.7x raw on the
> counter and more on wall clock, since encoding walks the value both
> ways; a registered raw operation measured 0.85us against 2.26us
> encoded. Bulk data should stay opaque: one transparent 64-float
> crossing costs 330 inferences where the handle costs 10.
>
> `inverse=` remains the distinct-output form. Use it when the forward
> operation returns a result and a separate callable must recover the
> arguments from that result:
>
>     m.op(
>         cons,
>         name="cons",
>         inverse=uncons,
>         effect=EffectClass.pureStructural,
>     )
>     # !(let (cons $h $t) (1 2 3) ($h $t))  ->  (1 (2 3))
>
> It takes the result and returns the arguments, as a tuple, or the
> bare value at arity one; a generator enumerates every preimage, and
> None or NotReducible means there is none. It runs only when the arguments
> are not ground and the result is, so a forward call never reaches it,
> and an operation without one compiles exactly what it did before.
>
> A parameter annotated `metta.MeTTa` is the framework's to fill,
> FastAPI's Depends read with the house convention that the
> annotation is the request. The engine injects itself bound to the
> CALLING context's space, so an operation invoked from a program
> running in &kb queries &kb; the slot never counts toward MeTTa
> arities or the declared arrow, and only operations that ask pay
> the weaving:
>
>     @m.op(effect=EffectClass.nondeterministicReadOnly)
>     def related(term, engine: metta.MeTTa):
>         for row in engine.match(Expression(S.link, term, V.x)):
>             yield row[0]
>
> Every operation declares its strongest observable effect. The five
> ordered choices are ``pureStructural``, ``readOnlyLookup``,
> ``nondeterministicReadOnly``, ``writesState``, and ``oracleIO``:
>
>     m.op(
>         len,
>         name="size",
>         effect=EffectClass.pureStructural,
>     )
>     # (= (count-of $x) (size $x))  is cacheable
>
> It is an allow-list on purpose. An operation that does not say so is
> refused by name in a cached body, loudly, rather than cached and
> quietly wrong.

### `Space.pure`

```python
def pure(self, fn: Callable | None = None, /, **options: Any) -> Any:
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

### `Space.reads`

```python
def reads(self, fn: Callable | None = None, /, **options: Any) -> Any:
```

> An operation that reads stable state without changing it.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.

### `Space.writes`

```python
def writes(self, fn: Callable | None = None, /, **options: Any) -> Any:
```

> An operation that changes engine or host state.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.

### `Space.io`

```python
def io(self, fn: Callable | None = None, /, **options: Any) -> Any:
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

### `Space.unregister_op`

```python
def unregister_op(self, name: str) -> None:
```

> Remove a registered operation, every arity of it.
>
> An absent name raises KeyError, as convert.unregister_type does:
> removing something that was never there is a mistake worth hearing
> about, not a no-op to absorb.

### `Space.builtins`

```python
def builtins(self) -> list[str]:
```

> Every registered function and translator special-form name.

### `Space.is_function`

```python
def is_function(self, name: str) -> bool:
```

> Report whether a function is visible from this space.

### `Space.is_function_here`

```python
def is_function_here(self, name: str) -> bool:
```

> Whether a function would answer from THIS space: it has clauses
> this space's module sees, its own or the shared ones in user.
> Another space's equations are invisible here and do not count.

### `Space.arities`

```python
def arities(self, name: str) -> list[int]:
```

> Compiled predicate arities for a name: MeTTa arity plus one each.

### `Space.register_prolog`

```python
def register_prolog(
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

### `Space.register_foreign_library`

```python
def register_foreign_library(
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

### `Space.register_library_path`

```python
def register_library_path(self, directory: Any, name: str) -> None:
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

### `Space.unregister_prolog`

```python
def unregister_prolog(self, extension: str) -> tuple[str, ...]:
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

### `Space.subscribe`

```python
def subscribe(
    self,
    pattern: Any,
    callback: Callable | None = None,
    *,
    on: str = 'add',
    where: Any | None = None,
    queue_max: int | None = None,
):
```

> A standing query on this space: every added (or removed, or
> both) atom unifying with the pattern becomes an Event.
>
>     seen = []
>     sub = m.subscribe(S.order(V.id), lambda e: seen.append(e))
>     m.add(S.order(1))          # seen[0].bindings["id"] == 1
>     sub.cancel()
>
> With a callback, delivery is synchronous. An unscoped write delivers
> before it returns; a transaction delivers its ordered segment only
> after the complete commit, while rollback and speculation deliver
> nothing. The callback may write back; the engine re-enters cleanly,
> and an infinite add-triggers-add loop is the author's own.
> Without one, events queue on the subscription and drain() empties
> them: the mailbox reading. That queue is bounded by `queue_max`,
> and a write arriving at a full queue raises SubscriberError rather
> than discarding the oldest event: nobody draining is a bug in the
> consumer, and a silently shortened history is how it stays hidden.
> A removal event fires only when something was removed, and carries
> the pattern that was asked for rather than the occurrence that
> left. The two are the same atom for a ground removal and differ
> for a pattern one: removal is multiset subtraction, so
> `remove(S.alert(V.q))` takes one of the alerts and the event
> cannot say which. Re-read the space when you need to know;
> `metta.structures.LiveView` is the worked instance.

### `Space.prolog`

```python
def prolog(self) -> None:
```

> Drop into the engine's own interactive Prolog toplevel, the
> deepest debugging lever there is: listing/1 shows compiled
> equations, trace/0 steps through them, and quitting the toplevel
> returns here with the session intact. janus's own janus.prolog(),
> surfaced where the debugging happens.
>
> This is the only Prolog-facing surface here besides register_prolog,
> and that is a decision rather than a gap. There is no public
> "call any Prolog goal" method: the supported way to reach your own
> Prolog from Python is to register it and call it as a MeTTa function,
> which keeps one set of conversion rules, one error taxonomy and one
> lock. A raw goal is janus's job and janus is importable directly.

### `Space.derivation`

```python
def derivation(
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
> Building a proof executes every premise it records, including
> effectful operations. Engine writes persist and repeated derivations
> accumulate them, just as repeated evaluations do. Use
> ``with space.speculative():`` when the proof should return while its
> engine writes are discarded. That scope cannot undo Python side
> effects, I/O, or subscription callbacks that already fired, so do not
> derive an effectful target when those effects must not happen.
>
> A `bind()` scope binds host values into the term, for the reason
> eval_status needs it: the substitution lands BEFORE the search, so the
> proof of an evaluation that binds anything was unaskable. Name keys
> mean symbols and atom keys mean themselves, so `bind({V.x: 5})` fills
> a variable hole. It takes no `theory` or
> `interpreter`, because a meta-interpreted diagnostic does not select an
> evaluation relation.

### `Space.why`

```python
def why(self, pattern: Any, *, where: Any | None = None) -> str:
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

### `Space.define`

```python
def define(
    self,
    fn: Callable[..., Any] | None = None,
    *,
    prolog: str | os.PathLike[str] | None = None,
    name: str | None = None,
    accessors: bool = True,
    methods: bool = True,
) -> Any:
```

> Compile a Python function into MeTTa equations, decorator-style.
>
> With `prolog=`, the Prolog file is registered and becomes the
> function, and the Python stays as the reference twin rather than
> being compiled:
>
>     @m.define(prolog=Path(__file__).parent / "fast.pl")
>     def vec_dot(a, b):
>         return sum(x * y for x, y in zip(a, b))
>
>     m.eval("(vec-dot (1 2) (3 4))")[0] # the Prolog answer
>     vec_dot.py((1, 2), (3, 4))          # the reference answers
>
> Rewriting a defined function in Prolog for speed used to mean
> deleting the Python and the differential oracle with it. Here both
> are declared together and `metta.testing.check_twin` proves they
> agree on ground inputs. The file must register the function's own
> MeTTa name and at the twin's arity, inputs then one output, and
> says so if it does not; its `metta_export` declaration owns the
> types, so annotations on the Python are documentation only.
>
> Written for whoever is fluent in Python rather than s-expressions:
> the body is read as syntax and lowered deterministically, refusals
> name the construct, the line and what to write instead, and the
> original stays reachable as .py, a twin the equations can be checked
> against on any ground input.
>
>     @m.define
>     def add_one(n):
>         return n + 1
>
>     add_one(5)                  # [6], evaluated by the engine
>     S.add_one(5)                # (add_one 5), staged as data
>     add_one.py(5)               # 6, ordinary Python
>
> The equation's implicit name applies the factories' total mechanical
> map, replacing each underscore with a hyphen. ``name=`` is the exact
> quoted-name escape for punctuation that map cannot preserve:
>
>     @m.define(name="add-one")
>     def add_one(n):
>         return n + 1
>
> The same attribute mapping applies to the definition name itself:
> ``def not_provable`` lands as ``not-provable``. An authored
> MeTTa underscore therefore uses explicit ``name="not_provable"``.
>
> A generator compiles to nondeterminism (each yield one answer), a
> lambda to the engine's own |->, a comprehension to map-atom and
> filter-atom, and match(Pattern(x, y), template) to a match against
> the running space, lowercase free names in the pattern binding as
> variables.

### `Space.rules`

```python
def rules(self, fn: Callable[..., Any]) -> _Rules:
```

> Collect and land a non-exclusive equation bundle in this space.

### `Space.pre_add`

```python
def pre_add(self, fn: Defined[..., Any] | Callable[..., Any]) -> Defined[..., Any]:
```

> Compile or accept one unary judge and claim this space's write hook.
>
> The common decorator stack places ``@pre_add`` above ``@define``, so
> an existing Defined keeps the module that owns its equations. A raw
> function is compiled into this space before claiming the hook.

### `Space.type`

```python
def type(self, atom: Any) -> Atom:
```

> Return this space's first ``get-type`` answer, including undefined.

### `Space.doc`

```python
def doc(self, atom: Any) -> Atom:
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

### `Space.fn`

```python
def fn(self) -> _FunctionNamespace:
```

> Functions visible here, as bound attribute or exact-name handles.
>
>     car = m.fn.car_atom
>     car(m.parse("(1 2 3)"))     # [1]
>     m.fn["=="](1, 1).one()      # True
>
> Underscores transliterate to hyphens. Brackets preserve exact
> punctuation, and an unknown name raises at access rather than
> becoming a later empty evaluation.

### `Space.integrate`

```python
def integrate(self, target: Any) -> str:
```

> Install a library integration; see metta.integrate.

### `Space.handles`

```python
def handles(
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

### `Space.annotations`

```python
def annotations(
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

### `Space.algebra`

```python
def algebra(
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

### `Space.covers`

```python
def covers(self, effect: EffectClass | str) -> Atom:
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

### `Space.compensates`

```python
def compensates(self, operation: str, compensation: str) -> Atom:
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

### `Space.add_tagged_fact`

```python
def add_tagged_fact(self, tag: Any, proposition: Any) -> Atom:
```

> Store ``(fact tag proposition)``, the normative annotation form.

### `Space.add_tagged_rule`

```python
def add_tagged_rule(self, tag: Any, head: Any, *premises: Any) -> Atom:
```

> Store one rule generated by the algebra-agnostic tag threader.

### `Space.image`

```python
def image(self, type_name: str, setting: ImageMode) -> Atom:
```

> Choose how one Python type crosses one context boundary.
>
> opaque carries the live object by identity; transparent projects its
> structural MeTTa image; auto makes that choice from the value's size
> and replayability. A later declaration for the same context and type
> replaces the earlier one, so an attached provider reads one policy.
> Use ``_`` as the type name for a context-wide fallback.

### `Space.sample`

```python
def sample(self, query: str | Atom, *, k: int = 10, seed: int = 7) -> list[Atom]:
```

> Choose ``k`` tagged alternatives with replacement by ``(rate n)``.
>
> The argument names and list result follow ``random.choices``. A local
> seeded generator makes repeated calls reproducible without changing
> Python's process-global random state.

### `Space.source`

```python
def source(self, kind: SourceKind) -> Atom:
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

### `Space.on_error`

```python
def on_error(
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

### `Space.merge`

```python
def merge(self, pattern: str | Atom, policy: AnswerPolicy) -> Atom:
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

### `Space.context`

```python
def context(self, world: World) -> Atom:
```

> Record what a space's absence means.
>
> Negation as failure reads absence as falsity, which is only
> sound over a world the answerer holds whole, so a negated goal
> may consult a foreign space only when it declares closed-world;
> an undeclared one refuses under negation loudly. Native spaces
> are the engine's own database and closed by construction.

### `Space.agenda`

```python
def agenda(self, policy: AgendaPolicy, function: str | None = None) -> Atom:
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

### `Space.reacts`

```python
def reacts(self, pattern: str | Atom, operation: str | Atom, priority: int | None = None) -> Atom:
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

### `Space.admits`

```python
def admits(self, type_name: str) -> Atom:
```

> Type a pool's membership: only TYPE-carrying atoms enter.
>
> A thread pool is a space whose atoms are spaces, and this is its
> declaration: (admits &pool Space) plus per-atom (: &lt;space> Space)
> declarations make membership a type judgement the ontology
> already knows how to make.

### `Space.capacity`

```python
def capacity(self, limit: int) -> Atom:
```

> Bound a pool: an add beyond LIMIT atoms is refused loudly.

### `Space.atomicity`

```python
def atomicity(self, atomicity: Atomicity) -> Atom:
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

### `Space.emits`

```python
def emits(self, policy: AnswerPolicy) -> Atom:
```

> Declare the order a context emits its own answers in.
>
> best-first is the promise (top k ...) needs before its bound may
> reach the provider: the first k of a best-first emission ARE the
> k best. Distinct from the (merge &lt;pattern> &lt;policy>) strategy,
> which is how the ENGINE merges answers across several contexts.

### `Space.events`

```python
def events(
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

### `Space.runtime`

```python
def runtime(self) -> Runtime:
```

> The engine bridge itself, for callers going under the surface.

### `Space.metta`

```python
def metta(self) -> MeTTa:
```

> The owning evaluation context, so a handle can reach every
> context-level method: ``m.metta.space(S.kb)`` creates a sibling space
> in THIS handle's own context rather than the process default, which
> is the creation method the twins' known-issue asked for. The context
> BORROWS this handle's space as its home, so answering it mints
> nothing, and two answers compare equal because they share the
> runtime and the home.

## `MeTTa`

```python
class MeTTa:
```

> One MeTTa evaluation context; context-relative operations use Space.
>
> ``MeTTa()`` is a fresh context, the way ``dict()`` is a fresh dict: it
> mints an anonymous space of its own as its home, so two contexts never
> see each other's atoms or equations, and it owns that space, releasing
> it on :meth:`close` or when a ``with`` block leaves. Passing a space
> (a ``Space``, an ``&name`` string, a ``Symbol``, or a parametric ground
> ``Expression``) makes the context a BORROWER of that space instead:
> ``MeTTa(Space())`` is the process-default context ``metta.engine()``
> answers, and closing a borrower never drops what the caller supplied,
> the way a file object built on someone else's descriptor leaves it open.
> ``&self`` is just the default home's name; within any context its own
> home plays that role.

### `MeTTa.close`

```python
def close(self) -> None:
```

> Release the context's own home space; closing twice is a no-op.
>
> A borrowed home, the process default included, is the caller's
> and survives; only a home this context minted is dropped, and the
> drop takes the whole world with it: every space minted inside the
> context, by this object or by the program's own new-space, is
> released first, since it read the home's equations and cannot
> outlive it. A space the program declared with (inherits ...) still
> refuses, naming the heir, because that relationship is the
> program's own.

### `MeTTa.closed`

```python
def closed(self) -> bool:
```

> Whether :meth:`close` has released this context's own home.

### `MeTTa.self`

```python
def self(self) -> Space:
```

> The context's home space handle, its own ``&self``.

### `MeTTa.runtime`

```python
def runtime(self) -> Runtime:
```

> The engine bridge itself, for callers going under the surface.

### `MeTTa.info`

```python
def info(self) -> dict[str, str | None]:
```

> Return backend versions and the consulted MeTTa runtime tree.

### `MeTTa.space`

```python
def space(
    self,
    name: str | Symbol | Expression | Space | None = None,
    backing: Any = None,
    *,
    inherits: Space | None = None,
    restricted: bool = False,
    grants: _abc.Iterable[str] = (),
    journal: str | os.PathLike[str] | None = None,
    schema: _abc.Mapping[str, Any] | None = None,
    sync: str = 'none',
) -> Space:
```

> Create one native, provider-backed, remote, or journaled space.
>
> The BACKING value derives the implementation, so the common calls
> carry no options at all: with no name the engine mints an anonymous
> handle; a ``Space`` reopens that same space, which is what an engine
> answer naming one arrives as; a ``SpaceProvider`` backing is
> attached directly; an HTTP(S) URL becomes a remote provider (build
> the transport with ``metta.remote.connect`` when it needs a token,
> headers, or its own timeout, and hand THAT in as the backing); and
> ``journal=`` constructs ``PersistentFactSpace`` from ``schema=`` or
> a schema mapping supplied as the backing. ``sync`` paces the
> journal and means nothing without one, so it refuses alone.
>
> ``inherits``, ``restricted`` and ``grants`` choose the space MODEL and
> are independent of whether the space is named. MeTTa's own
> ``!(new-space &locked (restricted))`` names a restricted space, and
> ``metta.space(S.locked, restricted=True)`` is that call. Declaring a
> model on a name that already carries the same one is a no-op; a
> different one raises, because a space cannot have two models.

### `MeTTa.fn`

```python
def fn(self) -> _FunctionNamespace:
```

> The bound function namespace of this context's self space.

### `MeTTa.unregister_op`

```python
def unregister_op(self, name: str) -> None:
```

> Release an operation installed through :meth:`op`.

### `MeTTa.capture`

```python
def capture(self) -> CapturedOutput:
```

> Capture printed engine text across this context.

### `MeTTa.atomic`

```python
def atomic(self) -> ScopedExecution:
```

> Scope source execution to committing transactions.

### `MeTTa.transaction`

```python
def transaction(self, target: Any, /) -> Any:
```

> Run one callable or term in an engine transaction.

### `MeTTa.run`

```python
def run(
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
> Runs against this context's self space.

### `MeTTa.load`

```python
def load(
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
> Runs against this context's self space.

### `MeTTa.match`

```python
def match(
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
> Runs against this context's self space.

### `MeTTa.add`

```python
def add(self, *atoms: Any) -> None:
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
> Runs against this context's self space.

### `MeTTa.remove`

```python
def remove(self, atom: Any, *more: Any) -> bool | int:
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
> Runs against this context's self space.

### `MeTTa.eval`

```python
def eval(
    self,
    target: Any,
    *more: Any,
    timeout: float | None = None,
    inferences: int | None = None,
    under: Any = _UNSET,
    theory: Any | None = None,
    interpreter: Any | None = None,
) -> list[Atom | Undefined] | list[list[Atom | Undefined]]:
```

> Evaluate a term, returning every answer.
>
> This is what !(...) runs, minus the printing: the engine's
> translate_expr over the term, then its goals. Nondeterminism means
> the list can hold any number of answers, including none.
>
> Variadic, and that is how evaluation BATCHES: several terms ride
> one engine crossing and the answer is one group per term in call
> order, run()'s own grouping carried to the term form. One term
> keeps its flat list, so the scalar reading never changes shape.
>
> Every answer carries its truth: an answer that is undefined under
> Well Founded Semantics (a tabled loop through tnot, reachable via
> translatePredicate or injected Prolog) arrives as an Undefined
> holding the answer and the delay condition that makes it
> undefined, never as an ordinary-looking value. A term to which no
> rule applies is the ordinary answer itself; `eval_status()` names
> that path `not-reducible`. run() does not carry the third truth
> value; evaluate through eval() when it matters.
>
> `bind()` binds named host values into the term before it evaluates,
> exactly as it does for run(): inside `with m.bind({"x": tensor})`,
> `m.eval("(decide x)")` hands the tensor itself to the rule, by
> identity, rather than a printed form of it. The name is the SYMBOL x
> and not the variable $x, in this call and the source form alike. The
> evaluation calls take the same vocabulary as the source form, so using
> a term instead of source text costs no change of spelling.
>
> A key may be a NAME or an ATOM. A name means the symbol of that name,
> which is what the engine's own substitution matches and what run()
> takes. An atom means exactly that atom, so `bind({V.x: 5})` fills a
> VARIABLE hole -- the one substitution `unify` reports and the one no
> evaluation call could apply, because a variable crosses the wire as ['v', 'x']
> where a symbol crosses as ['s', 'x'] and the engine matches names.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the call,
> raising TimeLimitError or InferenceLimitError when hit. A surrounding
> `capture()` scope collects printed text without changing the list.
>
> `under`, `theory` and `interpreter` are answers()' three, and mean
> exactly what they mean there; `eval()` materialises that query as a list. A
> surrounding `with metta.under(carrier)` reaches here too, which it did
> not before: match() and answers() both honoured such a scope while
> eval() ignored it in silence.
> Runs against this context's self space.

### `MeTTa.solve`

```python
def solve(self, pattern: Any, subject: Any) -> Any:
```

> Run relational ``let`` and return bindings keyed by its variables.
>
> ``solve(4, V.x - 1).x`` places the known value on let's pattern side,
> lets the arithmetic relation solve backwards, and projects ``x``.
> The answer template is derived from the pattern's variables followed
> by any new subject variables, so either relational direction can
> introduce the bindings and the third hand-written ``let`` argument
> disappears.
> Runs against this context's self space.

### `MeTTa.doc`

```python
def doc(self, atom: Any) -> Atom:
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
> Runs against this context's self space.

### `MeTTa.define`

```python
def define(
    self,
    fn: Callable[..., Any] | None = None,
    *,
    prolog: str | os.PathLike[str] | None = None,
    name: str | None = None,
    accessors: bool = True,
    methods: bool = True,
) -> Any:
```

> Compile a Python function into MeTTa equations, decorator-style.
>
> With `prolog=`, the Prolog file is registered and becomes the
> function, and the Python stays as the reference twin rather than
> being compiled:
>
>     @m.define(prolog=Path(__file__).parent / "fast.pl")
>     def vec_dot(a, b):
>         return sum(x * y for x, y in zip(a, b))
>
>     m.eval("(vec-dot (1 2) (3 4))")[0] # the Prolog answer
>     vec_dot.py((1, 2), (3, 4))          # the reference answers
>
> Rewriting a defined function in Prolog for speed used to mean
> deleting the Python and the differential oracle with it. Here both
> are declared together and `metta.testing.check_twin` proves they
> agree on ground inputs. The file must register the function's own
> MeTTa name and at the twin's arity, inputs then one output, and
> says so if it does not; its `metta_export` declaration owns the
> types, so annotations on the Python are documentation only.
>
> Written for whoever is fluent in Python rather than s-expressions:
> the body is read as syntax and lowered deterministically, refusals
> name the construct, the line and what to write instead, and the
> original stays reachable as .py, a twin the equations can be checked
> against on any ground input.
>
>     @m.define
>     def add_one(n):
>         return n + 1
>
>     add_one(5)                  # [6], evaluated by the engine
>     S.add_one(5)                # (add_one 5), staged as data
>     add_one.py(5)               # 6, ordinary Python
>
> The equation's implicit name applies the factories' total mechanical
> map, replacing each underscore with a hyphen. ``name=`` is the exact
> quoted-name escape for punctuation that map cannot preserve:
>
>     @m.define(name="add-one")
>     def add_one(n):
>         return n + 1
>
> The same attribute mapping applies to the definition name itself:
> ``def not_provable`` lands as ``not-provable``. An authored
> MeTTa underscore therefore uses explicit ``name="not_provable"``.
>
> A generator compiles to nondeterminism (each yield one answer), a
> lambda to the engine's own |->, a comprehension to map-atom and
> filter-atom, and match(Pattern(x, y), template) to a match against
> the running space, lowercase free names in the pattern binding as
> variables.
> Runs against this context's self space.

### `MeTTa.op`

```python
def op(
    self,
    fn: Callable | None = None,
    *,
    name: str | None = None,
    transport: Literal['encoded', 'raw'] = 'encoded',
    effect: EffectClass | str | None = None,
    declarations: Iterable[Atom] = (),
    arities: list[int] | None = None,
    inverse: Callable | None = None,
) -> Any:
```

> Register a Python callable as a MeTTa function, decorator-style.
>
>     @m.op(effect=EffectClass.pureStructural)
>     def double(x: int) -> int:
>         return 2 * x                    # !(double 21) -> 42
>
>     @m.op(effect=EffectClass.nondeterministicReadOnly)
>     def neighbours(n: int):
>         yield n - 1                     # a generator is nondeterministic
>         yield n + 1
>
> An implicit Python name maps underscores to MeTTa hyphens. ``name=``
> is exact, for source vocabularies that deliberately use underscores.
>
> A name must read back as one MeTTa symbol. A space, parenthesis,
> quote, comment opener, variable spelling, number, boolean, or another
> registered reader token is refused before any registry changes, with
> the name and the conflicting character in the error.
>
> Annotations become ordinary `(: ...)` declarations. An unannotated
> callable makes no type claim. `transport="raw"` skips wire encoding
> both ways and is reflected as raw_det or raw_many in `(op ...)`;
> symbols then reach Python as strings, so encoded transport is the
> fidelity-preserving default. unregister_op(name) removes every
> registered arity and every declaration the registration owns.
>
> An `Atom` parameter changes evaluation order. The declaration tells
> the compiler to pass the argument as written, before it reduces:
>
>     @m.op(effect=EffectClass.pureStructural)
>     def anyatom(term: Atom) -> Atom:
>         return term
>
>     # with (= (side) 42), !(anyatom (side)) answers (side)
>
> An unconstrained parameter receives the evaluated value instead, so
> the otherwise identical `def anyval(term): return term` answers 42.
> Use `Atom` only when the operation deliberately implements syntax or
> a control form; it is not just a static hint.
>
> An encoded generator may instead yield exact tuples as positional
> relation rows, or exact dicts keyed by parameter name as sparse rows.
> The engine unifies each candidate against the written call, so one
> implementation serves free, partially bound, and ground arguments:
>
>     @m.op
>     def route(origin, destination):
>         yield (S.paris, S.lyon)
>         yield {"destination": S.nice}  # origin is unconstrained
>
>     # route(V.origin, S.lyon).rows[0].origin == S.paris
>
> Each matching occurrence answers unit and duplicate yields remain
> duplicate answers. Use `Answer(value=...)` when an exact tuple or dict
> is the result value rather than a parameter row. Relational rows
> require encoded transport; raw calls cannot carry unbound argument
> positions.
>
> When evaluation order stays ordinary but the callable needs the
> resulting Atom wrappers, declare that policy as data:
>
>     m.op(
>         inspect_atom,
>         name="inspect-atom",
>         effect=EffectClass.pureStructural,
>         declarations=[parse("(arguments inspect-atom atoms)")],
>     )
>
> The declaration is matchable in &metta and is retired with the
> operation. Raw transport refuses this declaration because it bypasses
> the atom codec entirely.
>
> The cost ladder, measured on the maintained box in inferences per
> call, explains the transport choice:
>
>     native MeTTa function            9.11   the floor
>     transport="raw"                10.11   opaque handles, near-native
>     encoded                        17.11   encoded values
>     encoded, typed literal         17.11   the check hoists to compile
>     py-call, dotted                 22.11   the ad-hoc escape hatch
>
> The ergonomic default (encoded, typed) costs about 1.7x raw on the
> counter and more on wall clock, since encoding walks the value both
> ways; a registered raw operation measured 0.85us against 2.26us
> encoded. Bulk data should stay opaque: one transparent 64-float
> crossing costs 330 inferences where the handle costs 10.
>
> `inverse=` remains the distinct-output form. Use it when the forward
> operation returns a result and a separate callable must recover the
> arguments from that result:
>
>     m.op(
>         cons,
>         name="cons",
>         inverse=uncons,
>         effect=EffectClass.pureStructural,
>     )
>     # !(let (cons $h $t) (1 2 3) ($h $t))  ->  (1 (2 3))
>
> It takes the result and returns the arguments, as a tuple, or the
> bare value at arity one; a generator enumerates every preimage, and
> None or NotReducible means there is none. It runs only when the arguments
> are not ground and the result is, so a forward call never reaches it,
> and an operation without one compiles exactly what it did before.
>
> A parameter annotated `metta.MeTTa` is the framework's to fill,
> FastAPI's Depends read with the house convention that the
> annotation is the request. The engine injects itself bound to the
> CALLING context's space, so an operation invoked from a program
> running in &kb queries &kb; the slot never counts toward MeTTa
> arities or the declared arrow, and only operations that ask pay
> the weaving:
>
>     @m.op(effect=EffectClass.nondeterministicReadOnly)
>     def related(term, engine: metta.MeTTa):
>         for row in engine.match(Expression(S.link, term, V.x)):
>             yield row[0]
>
> Every operation declares its strongest observable effect. The five
> ordered choices are ``pureStructural``, ``readOnlyLookup``,
> ``nondeterministicReadOnly``, ``writesState``, and ``oracleIO``:
>
>     m.op(
>         len,
>         name="size",
>         effect=EffectClass.pureStructural,
>     )
>     # (= (count-of $x) (size $x))  is cacheable
>
> It is an allow-list on purpose. An operation that does not say so is
> refused by name in a cached body, loudly, rather than cached and
> quietly wrong.
> Runs against this context's self space.

### `MeTTa.pure`

```python
def pure(self, fn: Callable | None = None, /, **options: Any) -> Any:
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
> Runs against this context's self space.

### `MeTTa.reads`

```python
def reads(self, fn: Callable | None = None, /, **options: Any) -> Any:
```

> An operation that reads stable state without changing it.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.
> Runs against this context's self space.

### `MeTTa.writes`

```python
def writes(self, fn: Callable | None = None, /, **options: Any) -> Any:
```

> An operation that changes engine or host state.
>
> Every ``op`` keyword applies: ``name``, ``arities``,
> ``declarations``, ``inverse`` and ``transport``. They arrive as
> ``**options`` and forward unchanged, so the signature above shows
> the mechanism and this line shows the surface.
> Runs against this context's self space.

### `MeTTa.io`

```python
def io(self, fn: Callable | None = None, /, **options: Any) -> Any:
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
> Runs against this context's self space.

### `MeTTa.stats`

```python
def stats(self) -> _StatsBlock:
```

> The engine's own counters over a with-block, as deltas.
>
>     with m.stats() as s:
>         m.match(S.edge(V.x, V.y), S.edge(V.y, V.z))
>     s.inferences        # engine steps the block spent
>     s.cputime           # engine CPU seconds
>     s.walltime          # wall seconds, Python's clock
>     s.gc_count, s.gc_freed, s.gc_time
>     s.table_bytes       # answer-table bytes grown, tabling's memory
>
> The counters are SWI's statistics/2 read on the CALLING thread, so
> a block that runs other threads' engine work counts that work too;
> the honest reading is "what this thread saw the engine do while the
> block ran". A lazy cursor is the exception, and a large one: its
> goal runs in an SWI engine, an engine counts its own inferences,
> and this thread cannot see them. Draining 20,000 rows through the
> match cursor reports 40,049 inferences against about 381,000 the
> cursor's engine really spent, 10.5% of the work; the real cost is
> readable off the `inferences` budget, which does count the engine
> . The evaluation cursor behind `answers()`
> does report its engine's spend, so that one is whole. The z3py
> Solver.statistics() reading, on the engine this library actually
> has.
> Runs against this context's self space.

### `MeTTa.limits`

```python
def limits(
    self,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    stack: int | None = None,
) -> ScopedLimits:
```

> Scoped default bounds for every call in the with-block:
>
>     with m.limits(inferences=1_000_000, timeout=2.0):
>         m.match(...)      # bounded without saying so again
>
> decimal.localcontext's shape, contextvars underneath, so the
> scope is async-correct and per-task. A per-call timeout= or
> inferences= still overrides, which is the whole ladder: one
> block replaces the parameter forest, and the forest remains
> for whoever wants per-call control.
>
> stack= is SWI's combined stack ceiling in BYTES, the bound a
> runaway recursion hits as a StackOverflow error atom. It is NOT
> MeTTa's reduction depth: that is the max-stack-depth pragma,
> `(with-pragma! ((max-stack-depth N)) expr)`, which counts
> reduction steps and is scoped in the program text.
> Runs against this context's self space.

### `MeTTa.speculate`

```python
def speculate(self) -> ScopedExecution:
```

> Run each source against a snapshot and discard its writes.
>
> Runs against this context's self space.

### `MeTTa.trace`

```python
def trace(self, source: Atom | str, max_events: int | None = None):
```

> Run a TERM, or source, under the engine's reduction trace and
> answer TraceEvent records: what entered reduction at which depth,
> what it answered, and which reductions failed (a call with no
> exit). `m.trace(S.fib(10))` is the ordinary spelling, the same
> argument `answers` and `eval` take; a string is still a string.
> What is traced executes for real, writes included, like run();
> the wrap exists only while tracing, so untraced calls pay
> nothing. max_events bounds the recording; past it the recording
> stops and the result's `truncated` is True, rather
> than accumulating a long run's trace without limit.
> Runs against this context's self space.

### `MeTTa.register_prolog`

```python
def register_prolog(self, *args: Any, **kwargs: Any) -> tuple[str, ...]:
```

> Install a declared Prolog extension.

### `MeTTa.register_foreign_library`

```python
def register_foreign_library(self, *args: Any, **kwargs: Any) -> tuple[str, ...]:
```

> Install a compiled SWI foreign library.

### `MeTTa.register_library_path`

```python
def register_library_path(self, directory: Any, name: str) -> None:
```

> Register one named Prolog library directory.

### `MeTTa.unregister_prolog`

```python
def unregister_prolog(self, extension: str) -> tuple[str, ...]:
```

> Release one declared Prolog extension.

### `MeTTa.prolog`

```python
def prolog(self) -> None:
```

> Enter SWI-Prolog's interactive toplevel.
