# `petta.Space`

Source: `bindings/python/petta/_space.py`.

> Purpose: provide the narrow MeTTa context and context-relative Space handles.
>
> Assumes:
>   - the six extracted ``_space_*`` modules own query, definition, execution,
>     persistence, eager decoding, and diagnostic implementation [source:
>     bindings/python/petta/_space_query.py, _space_definitions.py,
>     _space_execution.py, _space_persistence.py, _space_objects.py, and
>     _space_diagnostics.py; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
> Guarantees:
>   - solve, Linda verbs, class define, get-type, bang resolution, and both
>     transaction laws are observable through one Space handle [tested:
>     test_solve_retires_the_five_relational_let_workarounds,
>     test_solve_refuses_an_anonymous_only_subject,
>     test_take_peek_and_watch_retire_the_thread_linda_fn_strings,
>     test_watch_close_before_first_event_cancels_its_eager_subscription,
>     test_define_absorbs_class_declaration_and_frees_space_type,
>     test_fn_strips_one_bang_only_when_the_exact_name_is_absent, and
>     test_transaction_term_uses_empty_answer_rollback_law; commit=c34c9bf3e55a8425d3f251c3ad06c33bc9755a22]
>   - relational solve exposes variables from its pattern before variables from
>     its subject [tested: test_solve_projects_variables_from_the_winning_pattern;
>     commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - ``MeTTa`` carries only context primitives while ``Space`` owns storage,
>     query, declaration, and lifecycle verbs [tested:
>     test_m7_narrow_core_surface; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - ``MeTTa.space()`` creates named or anonymous handles through one door
>     [tested: test_module_tier_is_sugar_over_one_default_engine;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - named space construction accepts a space-name Symbol as well as its text
>     spelling [tested: test_space_factory_accepts_a_name_symbol; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - a Symbol or ground Expression names a source-visible atomic or parametric
>     space, while a free variable refuses before engine state changes [tested:
>     test_python_space_factory_accepts_atom_valued_names; commit=WORKTREE]
>   - a tuple headed by an atom is one subscript pattern, a tuple of complete
>     patterns is a join, list writes stream their atoms, and del drains every
>     match or raises KeyError [tested:
>     test_subscript_one_pattern_and_bulk_delete_laws; commit=WORKTREE]
>   - ``Space.query`` returns a lazy Answers view; truth and single unpack pull
>     only their demanded prefix, while len counts inside the engine [tested:
>     test_query_answers_complete_the_lazy_projection_protocol,
>     test_query_single_unpack_pulls_at_most_two_answers; commit=WORKTREE]
>   - ``Space.pre_add`` declares one compiled unary judge through the engine's
>     existing pre-add hook [tested: test_pre_add_compiles_the_four_verdict_judge;
>     commit=WORKTREE]
>   - handle-level Linda waits load their support into the default caller space,
>     never into a distinct waited-on space [tested:
>     test_peek_does_not_import_linda_into_the_waited_space; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - ``Space.query``, every head-named declaration verb, and the write door
>     retain their established semantics after moving off ``MeTTa`` [tested:
>     test_query_surfaces_share_column_order,
>     test_no_decorator_flag_changes_the_return_shape_and_declarations_are_atoms,
>     test_the_python_remove_door_subtracts_one_copy; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - all fifteen declaration verbs use the atom head as the method name,
>     inject the receiver where it is the subject, and expose no ``declare_*``
>     aliases [tested: test_declarations_use_their_atom_heads_on_the_receiver,
>     test_m7_narrow_core_surface; commit=WORKTREE]
>   - ``Space.op`` and ``Space.unregister_op`` are the sole public operation
>     lifecycle pair [tested: test_operation_registration_names_are_symmetric;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - ``Space.answers`` and bound ``Space.fn`` expose lazy, replayable
>     evaluation, with unknown function attributes rejected at access [tested:
>     test_bound_function_namespace_validates_at_access,
>     test_function_calls_pull_engine_answers_only_as_demanded;
>     commit=2d4d4583c2d82e90bb21a7e8671842f126edd4f4]
>   - builtin discovery is cached per logical space and invalidated by every
>     catalogue mutation [tested: test_builtin_discovery_is_cached,
>     test_builtin_cache_invalidates_after_a_miss; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - ``Space`` is a grounded ``Handle`` that crosses as a term operand, and
>     ``peek`` and ``take`` expose the engine's event-driven Linda operations
>     [tested: test_space_handles_are_term_operands_and_round_trip,
>     test_space_handle_peek_and_take_are_linda_verbs; commit=4e2398075da67bb2cbcc123a9fc1e078ecac6fbf]
> Owns resources:
>   - ``Space.save`` owns its sibling temporary file and removes it after every
>     failed operation [tested: test_save_failure_preserves_existing_file;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

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
> PeTTa keeps one engine per process; every context shares it. The
> default space is &self, the space the CLI itself uses, so source pasted
> from a .metta file behaves identically here. Two ``MeTTa().self`` handles
> therefore see the same &self state. Use ``MeTTa().space()`` when
> independent stored state is required.
>
> A named space isolates both its atoms and its EQUATIONS, and the rule for
> equations has a third part this docstring used to get wrong by calling
> them process-wide. They are per-space, with a dynamic fallback to &self
> and local shadowing [measured 2026-08-17]:
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
>     from petta import MeTTa, S, V
>
>     m = MeTTa().self
>     m.run("(= (foo) boo) !(foo)")     # [[Symbol('boo')]]
>     m.add(S.Parent(S.Tom, S.Bob))
>     m.query(S.Parent(V.x, S.Bob))

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
> '&petta' from boot, every native space that has been written to,
> and every foreign space currently bound. Naming a space never
> registers it, only writing or binding does, so a bind! token's
> target appears here once something is stored under it.

### `Space.drop`

```python
def drop(self) -> None:
```

> Clear this space and release its name for reuse. Dropping a
> foreign space releases the binding and leaves the provider's own
> data alone; &self, the engine's own space, is cleared but its name
> never released. Subscriptions on the space cancel with it: a
> pooled name reused later must not deliver to the old life's
> watchers. The handle itself dies here: every later call through it
> refuses, because its name may already belong to another space.
> Dropping twice is a no-op, as closing twice is.

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
> `using` names Python values the source refers to by bare symbol,
> the way DuckDB reads a local dataframe by its variable name:
>
>     m.run("!(py-len graph)", using={"graph": my_graph})
>
> Each named symbol substitutes to its value (objects by identity),
> after reading, before anything runs.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the call
> with the engine's own guards; passing either raises TimeLimitError
> or InferenceLimitError when the bound is hit, and whatever the
> source completed before the stop, writes included, stands.
>
> `with m.capture() as output` collects printed text in `output.text`
> without changing this method's return shape. `with m.atomic()`,
> `with m.speculative()`, and `with m.strict()` scope execution policy
> without boolean combinations on each call. Atomic commits or rolls
> back each complete source; speculative answers and discards its
> writes. Both cover engine state; Python side effects and subscription
> callbacks already fired stay where they happened.
>
> A strict scope requires every directive to reduce, raising
> StrictError on one the engine hands back unevaluated. It is opt-in,
> because an unreduced term is an ordinary MeTTa value: a bare data
> constructor is refused under strict for the same reason a bare
> typo is, since neither reduces. An empty answer is allowed, being
> the pruned branch that (empty) and an unmatched match produce.
> eval_status() reports the same paths without refusing anything.

### `Space.profile`

```python
def profile(
    self,
    source: str,
    using: dict[str, Any] | None = None,
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
    using: dict[str, Any] | None = None,
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
def save(self, path: str | os.PathLike[str], format: str = 'metta') -> int:
```

> Write every stored atom of this space, equations included, as
> MeTTa source by default, or as a version-pinned trusted cache with
> format="fast"; answers how many. A path ending .gz writes gzip
> compressed in either format, and load and import! read it back
> under the same name. The completed sibling file is synced and then
> atomically replaces the target, so a failed save leaves the old file
> intact. Atoms carrying live host objects cannot survive either file
> and are refused.

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
> `!(import! &self path)` is the other door and loads a file that is
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
def register_token(self, pattern: str, constructor: Callable[[str], Any]) -> None:
```

> Register a full-token regex and its Atom constructor.
>
> The constructor receives the complete matched lexeme. It may return an
> Atom or any value accepted by :func:`petta.ground`. A later registration
> of the same pattern replaces the constructor. Only future parses read
> the new mapping; atoms already returned are immutable values.

### `Space.unregister_token`

```python
def unregister_token(self, pattern: str) -> None:
```

> Remove a reader-token class; an absent pattern is already removed.

### `Space.add`

```python
def add(self, *atoms: Any) -> None:
```

> Add atoms to this space, one engine round-trip for the lot.
> An (= ...) atom compiles as an equation. A stored atom is an
> expression, the engine's own storage shape, so anything else is
> refused here rather than failing silently inside.
>
> A variable's NAME is not stored. `(rule $x $y)` reads back as
> `(rule $_17902 $_17904)`, because a variable is an identity and not a
> spelling. That is the right property for a logic engine and it is the
> one thing about storage that surprises everybody once.

### `Space.remove`

```python
def remove(self, atom: Any) -> bool:
```

> Remove an atom, engine semantics: multiset subtraction, so ONE
> unifying occurrence leaves and the answer says whether one did.
> This is the same law `remove-atom` obeys, so both doors say the
> same thing about the same operation; `del m[pattern]` is the
> bulk spelling that drains every occurrence. A bare variable is
> the remove-everything reading a multiset space gives it, each
> atom leaving through its own proper path, equations and their
> compiled clauses included.

### `Space.atoms`

```python
def atoms(self) -> list[Atom]:
```

> Every stored atom in this space.

### `Space.peek`

```python
def peek(self, pattern: Any, *, deadline: float | None = None) -> Atom:
```

> Wait for one matching atom and leave it in this space.
>
> A finite deadline raises ``TimeoutError`` when no match arrives.

### `Space.take`

```python
def take(self, pattern: Any, *, deadline: float | None = None) -> Atom:
```

> Wait for and remove exactly one matching atom from this space.
>
> Competing takers cannot receive the same occurrence. A finite
> deadline raises ``TimeoutError`` when no match arrives.

### `Space.cast`

```python
def cast(self, value: Any, type_: Any, /) -> Any:
```

> Answer value, narrowed to its Python-most spelling, when this
> space's type discipline admits it as type_: the same acceptance
> a typed call compiles, ':' declarations in this space and &self
> in scope, protocol types included. A refused cast raises
> petta.CastError naming the value's actual types, the loud
> spelling of what a typed call does silently.

### `Space.trace`

```python
def trace(self, source: str, max_events: int = 1000000):
```

> Run source under the engine's reduction trace and answer
> TraceEvent records: what entered reduction at which depth, what
> it answered, and which reductions failed (a call with no exit).
> The source executes for real, writes included, like run(); the
> wrap exists only while tracing, so untraced calls pay nothing.
> max_events bounds the recording, raising past it rather than
> accumulating a long run's trace without limit.

### `Space.lint`

```python
def lint(self):
```

> Diagnose this space for the silently-wrong class: declared
> types nothing defines, arity mismatches, unbound body variables,
> duplicate equations, and references no function or fact carries.
> Answers petta.lint.Finding records, empty when nothing looks
> wrong.

### `Space.copy`

```python
def copy(self) -> Space:
```

> This space's contents in a new anonymous space, cloned through
> the bulk door, so equations copy as equations and keep running:
> "a scratch space set up like production" is one line. The handle
> is ``space()``'s kind, so drop it, or use it as a context
> manager, to return the name. copy.copy(m) answers the same
> through the copy protocol. There is deliberately no __deepcopy__:
> stored Python objects keep their identity across the clone, the
> shallow reading, and a deep clone of a live engine handle has no
> meaning to promise.

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

### `Space.query`

```python
def query(
    self,
    *patterns: Any,
    where: Any | None = None,
    limit: int | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
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
>     m.query(S.person(V.name, V.age), where=V.age >= 18)
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
> `into=Rows` explicitly chooses the eager Rows face. Other `into=`
> values shape each row into a dataclass, NamedTuple, or
> TypedDict matched by field name, sqlite3's row_factory reading:
> `m.query(S.edge(V.a, V.b), into=Edge)` answers `list[Edge]`,
> and Rows stays the default so nothing is lost. A one-variable query
> whose column holds complete constructor expressions rebuilds those
> expressions instead: `m.query(V.edge, into=Edge)`.
>
>     m.query(S.Edge(V.x, V.y), S.Edge(V.y, V.z))

### `Space.assuming`

```python
def assuming(self, *facts: Any) -> _Assuming:
```

> Facts held only inside a with-block: the assumptions reading of
> a what-if query, added on entry, removed on exit, exceptions
> included.
>
>     with m.assuming(S.closed(S.bridge)):
>         detour = m.query(S.route(V.r), where=...)

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
def watch(self, pattern: Any, *, on: str = 'add'):
```

> Yield matching change events until the iterator closes.

### `Space.limits`

```python
def limits(self, *, timeout: float | None = None, inferences: int | None = None) -> ScopedLimits:
```

> Scoped default bounds for every call in the with-block:
>
>     with m.limits(inferences=1_000_000, timeout=2.0):
>         m.query(...)      # bounded without saying so again
>
> decimal.localcontext's shape, contextvars underneath, so the
> scope is async-correct and per-task. A per-call timeout= or
> inferences= still overrides, which is the whole ladder: one
> block replaces the parameter forest, and the forest remains
> for whoever wants per-call control.

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

### `Space.strict`

```python
def strict(self) -> ScopedExecution:
```

> Refuse any run directive the engine returns unreduced.

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
> The write ladder reads: add one; add(*atoms) several; batch a
> region; transaction all-or-nothing; a provider's own bulk door
> underneath. A batch is a transport economy and must not invent
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
    *,
    using: dict[str, Any] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[Atom | Undefined]:
```

> Evaluate a term, returning every answer.
>
> This is what !(...) runs, minus the printing: the engine's
> translate_expr over the term, then its goals. Nondeterminism means
> the list can hold any number of answers, including none.
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
> `using` binds named host values into the term before it evaluates,
> exactly as it does for run(): `m.eval("(decide $x)", using={"x":
> tensor})` hands the tensor itself to the rule, by identity, rather
> than a printed form of it. The evaluation doors take the same
> vocabulary the source door takes, so reaching for a term instead
> of source text costs no change of spelling.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the call,
> raising TimeLimitError or InferenceLimitError when hit. A surrounding
> `capture()` scope collects printed text without changing the list.

### `Space.answers`

```python
def answers(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Answers[Any]:
```

> Evaluate lazily as an immutable, cached and replayable view.
>
> Creating the view performs no engine work. Existence pulls at most
> one answer, ``one()`` at most two, and ordinary iteration resumes the
> same held evaluation [tested:
> test_function_calls_pull_engine_answers_only_as_demanded;
> commit=2d4d4583c2d82e90bb21a7e8671842f126edd4f4].

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
> million [measured 2026-08-15]. An unenforceable bound is worse than
> an absent one, so eval() over a `superpose` is the way to bound this
> work by inferences, at the cost of running it on one core.

### `Space.hyperpose`

```python
def hyperpose(self, *targets: Any, timeout: float | None = None) -> list[Atom | Undefined]:
```

> parallel(), under the language's own name.
>
> (hyperpose ...) is the engine form this runs, so the Python
> surface reads MeTTa-natively; a thread pool is a space whose
> atoms are spaces, and this is how one is exercised from Python.

### `Space.pool`

```python
def pool(self, workers: int | None = None) -> Any:
```

> A pool of worker threads that each hold their own Prolog engine.
>
> The Python-side twin of `parallel()`. Each worker attaches its own
> engine, so the process lock that serialises the home engine does not
> apply to it and the calls genuinely run at once [measured 2026-08-15:
> 1.94x, 3.90x and 7.26x at 2, 4 and 8 workers].
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

### `Space.eval_status`

```python
def eval_status(
    self,
    target: Any,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
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
> itself, which is what PeTTa does with any head it cannot call.
> `empty` means the goal produced no answer at all, and its atom is
> None. Reading the last two as the same thing is the mistake this
> exists to prevent: an unevaluated term and a pruned branch look
> alike from the answers alone. An error is not a status here,
> because it arrives as an exception.

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
>         m.query(S.edge(V.x, V.y), S.edge(V.y, V.z))
>     s.inferences        # engine steps the block spent
>     s.cputime           # engine CPU seconds
>     s.walltime          # wall seconds, Python's clock
>     s.gc_count, s.gc_freed, s.gc_time
>     s.table_bytes       # answer-table bytes grown, tabling's memory
>
> The counters are the engine's statistics/2, and the engine is one
> per process, so a block that runs other threads' engine work counts
> that work too; the honest reading is "what the engine did while
> this block ran". The z3py Solver.statistics() reading, on the
> engine this library actually has.

### `Space.op`

```python
def op(
    self,
    fn: Callable | None = None,
    *,
    name: str | None = None,
    transport: Literal['encoded', 'raw'] = 'encoded',
    declarations: Iterable[Atom] = (),
    arities: list[int] | None = None,
    inverse: Callable | None = None,
) -> Any:
```

> Register a Python callable as a MeTTa function, decorator-style.
>
>     @m.op
>     def double(x: int) -> int:
>         return 2 * x                    # !(double 21) -> 42
>
>     @m.op
>     def neighbours(n: int):
>         yield n - 1                     # a generator is nondeterministic
>         yield n + 1
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
>     @m.op
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
> When evaluation order stays ordinary but the callable needs the
> resulting Atom wrappers, declare that policy as data:
>
>     m.op(
>         inspect_atom,
>         name="inspect-atom",
>         declarations=[parse("(arguments inspect-atom atoms)")],
>     )
>
> The declaration is matchable in &petta and is retired with the
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
> inverse gives the operation a BACKWARDS direction, so it can stand in
> a pattern position the way a MeTTa equation does:
>
>     m.op(cons, name="cons", inverse=uncons)
>     # !(let (cons $h $t) (1 2 3) ($h $t))  ->  (1 (2 3))
>
> It takes the result and returns the arguments, as a tuple, or the
> bare value at arity one; a generator enumerates every preimage, and
> None or NotReducible means there is none. It runs only when the arguments
> are not ground and the result is, so a forward call never reaches it,
> and an operation without one compiles exactly what it did before.
>
> A parameter annotated `petta.MeTTa` is the framework's to fill,
> FastAPI's Depends read with the house convention that the
> annotation is the request. The engine injects itself bound to the
> CALLING context's space, so an operation invoked from a program
> running in &kb queries &kb; the slot never counts toward MeTTa
> arities or the declared arrow, and only operations that ask pay
> the weaving:
>
>     @m.op
>     def related(term, engine: petta.MeTTa):
>         for row in engine.query(Expression(S.link, term, V.x)):
>             yield row[0]
>
> Purity is a seam declaration rather than a Python boolean. Supply the
> ordinary effect atom to let the operation appear in a `(tabled ...)`
> or memoized body:
>
>     m.op(
>         len,
>         name="size",
>         declarations=[parse("(effect size immutable)")],
>     )
>     # (= (count-of $x) (size $x))  is cacheable
>
> It is an allow-list on purpose. An operation that does not say so is
> refused by name in a cached body, loudly, rather than cached and
> quietly wrong.

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
> written in Prolog [measured 2026-08-15, 3000 calls in one harness].
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
> With a callback, delivery is synchronous, inside the write that
> caused it (the callback may write back; the engine re-enters
> cleanly; an infinite add-triggers-add loop is the author's own).
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
> `petta.structures.LiveView` is the worked instance.

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

### `Space.why`

```python
def why(self, pattern: Any) -> str:
```

> Why a pattern matches nothing here, in words.
>
> Checks the cheap explanations in order: unknown function, wrong
> arity, no stored atoms with that head. Honest when it cannot tell.

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
> are declared together and `petta.testing.check_twin` proves they
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
> This is rung 4 of the naming ladder applied to the definition door
> itself: ``def not_provable`` lands as ``not-provable``. An authored
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

> Compile or accept one unary judge and claim this space's write door.
>
> The common decorator stack places ``@pre_add`` above ``@define``, so
> an existing Defined keeps the module that owns its equations. A raw
> function is compiled into this space before claiming the hook.

### `Space.cache`

```python
def cache(
    self,
    fn: Callable[..., Any] | None = None,
    *,
    name: str | None = None,
    unchecked: bool = False,
) -> Any:
```

> Define a function and TABLE it, in functools.lru_cache's shape.
>
> The decorator is notation. What it lowers to is the engine's own
> tabling declaration, `(tabled (<name> $a ...))`, so the answers come
> from SWI's answer trie and stay correct across writes to the spaces
> the body reads: a declared table is incremental, and a write that
> invalidates it is re-evaluated rather than answered stale
> [source: lib/lib_tabling.pl, metta_tabled_decl/2].
>
>     @m.cache
>     def fib(n):
>         return n if n < 2 else fib(n - 1) + fib(n - 2)
>
>     fib(25)               # [75025], linear rather than exponential
>     fib.cache_info()      # {'tables': 26, 'answers': 26, ...}
>     fib.cache_clear()
>
> `unchecked=True` is the declaration that ACCEPTS STALENESS: the
> purity walk is skipped and the table is plain, which is the only way
> to table a body whose reads the engine cannot resolve. It is the
> engine's `(cache <name> unchecked)`, not a size, and there is no
> maxsize here because a table is not a fixed-size cache: it holds the
> answers for the calls that were made.
>
> The counters are the table's, so `cache_info()` answers `tables`,
> `answers`, `complete-call`, `invalidated` and `reevaluated` rather
> than lru_cache's hits and misses
> [tested: test_a_cached_definition_tables_and_answers_from_its_trie].
>
> WHAT THIS CHANGES, and lru_cache does not: a table normalises answer
> ORDER and DUPLICATES away. `(= (f) a) (= (f) a) (= (f) b)` answers the
> bag `a a b` and answers `a b` once tabled. The arbiter leaves order
> unspecified and SPECIFIES multiplicity, so dropping the repeat is a
> real change to what the function means and this decorator is the place
> that asks for it. Cache a function whose equations are exclusive, or
> one whose callers only ever ask whether an answer is there. lib_memo's
> `(memoized ...)` keeps the bag and is the door for everything else
> [tested: test_a_cached_definition_normalises_duplicate_answers_away].

### `Space.type`

```python
def type(self, atom: Any) -> Atom:
```

> Return this space's first ``get-type`` answer, including undefined.

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

> Install a library integration; see petta.integrate.

### `Space.handles`

```python
def handles(self, pattern: str | Atom, fidelity: str, *, det: str | None = None) -> Atom:
```

> Declare how faithfully a space answers queries of one shape.
>
> The declaration is one (handles ...) atom in &petta, and queries
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
> from &petta withdraws the declaration.

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
> ``contractive`` and ``staged`` [tested:
> test_amplitudes_interfere_inside_the_fragment_and_are_refused_outside;
> commit=f88aa8be03cb64cb59d3307515ded8701f418321]. Declaring replaces any earlier row for the
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
) -> Atom:
```

> Declare operations and checked laws for an arbitrary atom carrier.
>
> Public laws are certificates, not wishes. When an equational law is
> named, ``carrier`` must be finite and the operation tables are checked
> exhaustively before the catalog atom lands. ``contraction`` is the
> explicit resource-reuse capability and has no equation to sample.

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
def image(self, type_name: str, setting: Literal['opaque', 'transparent', 'auto']) -> Atom:
```

> Choose how one Python type crosses one context boundary.
>
> opaque carries the live object by identity; transparent projects its
> structural MeTTa image; auto makes that choice from the value's size
> and replayability. A later declaration for the same context and type
> replaces the earlier one, so an attached provider reads one policy.
> Use ``_`` as the type name for a context-wide fallback.

### `Space.evaluate_algebra`

```python
def evaluate_algebra(self, query: str | Atom, *, algebra: str, max_rounds: int = 64) -> Any:
```

> Evaluate stored tagged facts and rules through one declared algebra.

### `Space.sample_rates`

```python
def sample_rates(
    self,
    query: str | Atom,
    *,
    algebra: str,
    draws: int,
    seed: int,
) -> tuple[Atom, ...]:
```

> Select tagged alternatives by their nonnegative ``(rate n)`` tags.

### `Space.source`

```python
def source(self, kind: str) -> Atom:
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
    mode: str | None = None,
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
def merge(self, pattern: str | Atom, policy: str) -> Atom:
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
def context(self, world: str) -> Atom:
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
def agenda(self, policy: str, function: str | None = None) -> Atom:
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
>     alarms.reaction("(alert $w)", "(insert &log (all $w))")
>     alarms.reaction("(alert fire)", "(insert &log (fire))", priority=9)
>     alarms.agenda("priority")

### `Space.reaction`

```python
def reaction(self, pattern: str | Atom, operation: str | Atom, priority: int | None = None) -> Atom:
```

> Declare a reaction, stored as an (on ...) atom: when an atom
> matching PATTERN lands in the space, OPERATION runs under the
> match's bindings.
>
> The managed heads are (insert &lt;ctx> &lt;atom>), (retract &lt;ctx>
> &lt;atom>) and (revise &lt;ctx> &lt;old> &lt;new>), engine-routed rules
> going through the same write paths as direct writes. Declaring
> installs the engine's write hook, which is why reactions go
> through here or petta_install_bridges rather than a bare
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
> door: (admits &pool Space) plus per-atom (: &lt;space> Space)
> declarations make membership a type judgement the ontology
> already knows how to make.

### `Space.capacity`

```python
def capacity(self, limit: int) -> Atom:
```

> Bound a pool: an add beyond LIMIT atoms is refused loudly.

### `Space.writes`

```python
def writes(self, atomicity: str) -> Atom:
```

> Declare what a space's writes promise inside a transaction.
>
> transactional providers implement petta.foreign.Transactional and
> are committed or rolled back WITH the engine's transaction;
> best-effort is the author's declared acceptance of a write that
> survives a rollback; atomic-single refuses transactional writes.
> Undeclared spaces refuse them loudly too, because a foreign write
> silently surviving a rolled-back transaction is the wrong answer
> the declaration exists to replace.

### `Space.emits`

```python
def emits(self, policy: str) -> Atom:
```

> Declare the order a context emits its own answers in.
>
> best-first is the promise (top k ...) needs before its bound may
> reach the provider: the first k of a best-first emission ARE the
> k best. Distinct from the (merge &lt;pattern> &lt;policy>) strategy,
> which is how the ENGINE merges answers across several contexts.

### `Space.events`

```python
def events(self, delivery: str | None = None, order: str = 'unordered') -> Atom | Any:
```

> Return the event stream, or declare what this context promises.
>
> Subscribability is a promise about the context, not something the
> seam reads off its methods. A native space needs no declaration:
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

## `MeTTa`

```python
class MeTTa:
```

> One PeTTa evaluation context; context-relative operations use Space.

### `MeTTa.self`

```python
def self(self) -> Space:
```

> The context's ``&self`` space handle.

### `MeTTa.runtime`

```python
def runtime(self) -> Runtime:
```

> The engine bridge itself, for callers going under the surface.

### `MeTTa.info`

```python
def info(self) -> dict[str, str | None]:
```

> Return backend versions and the consulted PeTTa runtime tree.

### `MeTTa.space`

```python
def space(
    self,
    name: str | None = None,
    backing: Any = None,
    *,
    journal: str | os.PathLike[str] | None = None,
    **options: Any,
) -> Space:
```

> Create one native, provider-backed, remote, or journaled space.
>
> With no name, the engine mints an anonymous handle. A ``SpaceProvider``
> backing is attached directly, an HTTP(S) URL becomes a remote provider,
> and ``journal=`` constructs ``PersistentFactSpace`` from ``schema=`` or
> a schema mapping supplied as ``backing``.

### `MeTTa.define`

```python
def define(self, *args: Any, **kwargs: Any) -> Any:
```

> Define in ``&self``; derived as ``self.define(...)``.

### `MeTTa.op`

```python
def op(self, *args: Any, **kwargs: Any) -> Any:
```

> Ground a callable in ``&self``; derived as ``self.op(...)``.

### `MeTTa.unregister_op`

```python
def unregister_op(self, name: str) -> None:
```

> Release an operation installed through :meth:`op`.

### `MeTTa.limits`

```python
def limits(self, **kwargs: Any) -> ScopedLimits:
```

> Scope resource bounds across this context.

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

### `MeTTa.speculative`

```python
def speculative(self) -> ScopedExecution:
```

> Scope source execution to discarded snapshots.

### `MeTTa.strict`

```python
def strict(self) -> ScopedExecution:
```

> Scope source execution to reject unreduced directives.

### `MeTTa.transaction`

```python
def transaction(self, target: Any, /) -> Any:
```

> Run one callable or term in an engine transaction.

### `MeTTa.stats`

```python
def stats(self) -> _StatsBlock:
```

> Measure engine counters across a block.

### `MeTTa.trace`

```python
def trace(self, source: str, *, max_events: int = 10000):
```

> Trace source in ``&self``.

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
