# `petta.space`

Source: `python/petta/space.py`.

> Purpose: the MeTTa runtime surface. One class binds a space name to the
> process's engine and offers running source, loading files, structured space
> edits, conjunctive queries with guards, bounds, scoped assumptions and
> preparation, evaluation, Python-backed operations, proof-tree derivations
> and a why-not diagnostic, all in PeTTa's own semantics.
> Guarantees:
>   - MeTTa.save preserves an existing target when validation, writing, or
>     replacement fails [tested test_save_validation_preserves_existing_file,
>     test_text_save_write_failure_preserves_existing_file,
>     test_save_failure_preserves_existing_file]
>   - MeTTa.save fsyncs a completed sibling file before replacing the target
>     [tested test_save_syncs_before_replacing]
>   - MeTTa.derivation distinguishes a finite-depth cutoff from no proof and
>     accepts time and inference guards [tested
>     test_depth_exhaustion_returns_a_partial_proof,
>     test_unbounded_derivation_obeys_resource_guards]
>   - an exhausted Cursor keeps raising StopIteration, while an explicitly
>     closed Cursor refuses use [tested
>     test_stream_agrees_with_query_and_closes_on_exhaustion,
>     test_stream_pulls_rows_lazily_and_interleaves]
>   - register_op and unregister_op are the paired operation lifecycle names
>     [tested test_operation_registration_names_are_symmetric]
>   - define accepts source-bearing Python functions and refuses callable
>     objects before reading compiler metadata [tested
>     test_define_refuses_callable_objects]
>   - query, prepare, and stream preserve distinct variable columns in first
>     appearance order [tested test_query_surfaces_share_column_order]
>   - public name and save-format annotations distinguish their string
>     contexts [tested test_public_context_types_are_distinct]
>   - cast preserves a concrete target class as its static return type and keeps
>     the target positional-only [tested
>     test_target_type_overloads_preserve_the_requested_class,
>     test_cast_target_is_positional_only]
>   - dropping a space releases its integration installation records [tested
>     test_dropped_space_name_reinstalls_integrations]
>   - eval_status and run_status separate a pruned branch from an unevaluated
>     term, and strict= refuses only the latter [tested
>     test_eval_status_reports_the_four_outcomes,
>     test_strict_accepts_a_pruned_branch_and_every_reduction]
>   - profile_extension reports every declared member of an extension, including
>     one the workload never reached, with the tier that installed it and its
>     clause index [tested 2026-08-16:
>     test_profile_extension_reports_every_declared_member,
>     test_profile_extension_separates_an_indexed_table_from_a_single_clause]
>   - register_prolog reads a metta_export declaration from inline source as it
>     does from a file [tested 2026-08-16:
>     test_inline_source_declares_its_own_exports_too]
>   - remove() is multiset subtraction, one unifying occurrence per call,
>     the same law remove-atom obeys [tested
>     test_the_python_remove_door_subtracts_one_copy]
>   - del m[pattern] drains every unifying occurrence and raises KeyError
>     when none unified, remove() reporting the same absence as False
>     [tested test_delitem_drains_every_unifying_occurrence]
>   - |= merges a space, a registered space name, or an iterable, and refuses
>     an operand add() would lift into one atom [tested
>     test_ior_merges_a_space_equations_included,
>     test_ior_refuses_the_operands_add_would_lift]
> Owns:
>   - MeTTa.save owns its sibling temporary file and removes it after every
>     failed operation [tested test_save_failure_preserves_existing_file]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `current_space`

```python
def current_space(default: str = _DEFAULT_SPACE) -> SpaceName:
```

> The space whose module the ENGINE is evaluating in right now.
>
> Callable from inside a registered operation, where it answers the space
> of the program that called it: janus re-enters the engine cleanly, so
> an operation can behave per-space without the space being an argument.
> Outside any evaluation it answers the default.

## `MeTTa`

```python
class MeTTa:
```

> A space bound to the engine: the way in from Python.
>
> PeTTa keeps one engine per process; every MeTTa instance shares it. The
> default space is &self, the space the CLI itself uses, so source pasted
> from a .metta file behaves identically here. Two MeTTa() calls therefore
> see the same &self state. Use new_space() when independent stored state
> is required.
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
> process-wide, which new_space() says.
>
>     from petta import MeTTa, S, V
>
>     m = MeTTa()
>     m.run("(= (foo) boo) !(foo)")     # [[Sym('boo')]]
>     m.add(S.Parent(S.Tom, S.Bob))
>     m.query(S.Parent(V.x, S.Bob))     # Rows[x](Row(x=Sym('Tom')))

### `MeTTa.space_name`

```python
def space_name(self) -> SpaceName:
```

No docstring is defined.

### `MeTTa.space`

```python
def space(self, name: str) -> MeTTa:
```

> Another space on the same engine.

### `MeTTa.space_names`

```python
def space_names(self) -> list[str]:
```

> Every space name this engine registers, sorted: '&self' and
> '&petta' from boot, every native space that has been written to,
> and every foreign space currently bound. Naming a space never
> registers it, only writing or binding does, so a bind! token's
> target appears here once something is stored under it.

### `MeTTa.new_space`

```python
def new_space(self) -> MeTTa:
```

> An anonymous space with a name nothing else is using.
>
> Works as a context manager: leaving the block drops the space, so a
> churn of short-lived spaces reuses names instead of growing the
> engine's module table.
>
>     with m.new_space() as scratch:
>         scratch.add(...)
>
> What it isolates is STORED STATE: atoms and equations. Registrations
> are process-wide, so a register_prolog, a register_op or a define made
> on a new space is visible from every other one. Reach for this to
> isolate the data a test writes, not the names it registers; to isolate
> a name, unregister it.

### `MeTTa.drop`

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

### `MeTTa.run`

```python
def run(
    self,
    source: str,
    using: dict[str, Any] | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
    capture: bool = False,
    atomic: bool = False,
    speculative: bool = False,
    strict: bool = False,
) -> list[list[Atom]] | tuple[list[list[Atom]], str]:
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
> source completed before the stop, writes included, stands. With
> `capture=True` the return value is (groups, text), text being
> everything the source printed, println! included.
>
> `atomic=True` runs the whole source inside the engine's own
> transaction/1: every write, facts and equations alike, commits
> whole, or rolls back whole when a directive throws; the inline
> (transaction ...) form does the same for a scope inside a
> program. `speculative=True` is the what-if twin through
> snapshot/1: the answers return and every write is discarded.
> Both cover engine state; a Python operation's side effects, and
> subscription callbacks already fired, stay where they happened.
>
> `strict=True` requires every directive to reduce, raising
> StrictError on one the engine hands back unevaluated. It is opt-in,
> because an unreduced term is an ordinary MeTTa value: a bare data
> constructor is refused under strict for the same reason a bare
> typo is, since neither reduces. An empty answer is allowed, being
> the pruned branch that (empty) and an unmatched match produce.
> eval_status() reports the same paths without refusing anything.

### `MeTTa.profile`

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

### `MeTTa.profile_extension`

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

### `MeTTa.save`

```python
def save(self, path: str | os.PathLike[str], format: SaveFormat = 'metta') -> int:
```

> Write every stored atom of this space, equations included, as
> MeTTa source by default, or as a version-pinned trusted cache with
> format="fast"; answers how many. A path ending .gz writes gzip
> compressed in either format, and load and import! read it back
> under the same name. The completed sibling file is synced and then
> atomically replaces the target, so a failed save leaves the old file
> intact. Atoms carrying live host objects cannot survive either file
> and are refused.

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
> Existing atoms remain, so loading the same file twice adds two copies.
> Use clear() first or load into new_space() when replacement is wanted.
> A .gz path is detected and read through the decompressed bytes.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the load
> with the engine's own guards, raising TimeLimitError or
> InferenceLimitError, and whatever the file completed before the stop
> stands. This is the entry point most likely to be handed code the
> caller did not write, since a file can carry `!` directives and an
> import graph, so it takes the same pair its siblings take.

### `MeTTa.parse`

```python
def parse(self, source: str) -> Atom:
```

> Read one form into an atom without evaluating it.

### `MeTTa.add`

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

### `MeTTa.add_table`

```python
def add_table(self, head: Any, data: Any) -> int:
```

> Any tabular source as facts (head v1 .. vn); answers how many.
>
>     m.add_table("edge", polars_frame)         # or a pandas frame
>     m.add_table("edge", {"src": [...], "dst": [...]})
>     m.add_table("edge", [("a", "b"), ("b", "c")])
>
> The source is read by the interface it offers, never by library:
> iter_rows() (polars), itertuples() (pandas), a mapping of columns,
> or any iterable of rows. A row may be a sequence or a mapping, so
> a list of records from rows.to_dicts() reads correctly; every
> record must carry the same keys in the same order, because their
> order is what fixes the fact positions. A mapping of columns takes
> its own key order, and columns of unequal length are a hard error
> rather than a silent truncation.
>
> rows.table() is the reverse in shape, the dict every DataFrame
> constructor takes, but not in identity: it decodes atoms to Python
> values, so a symbol comes back as a str and re-enters as a MeTTa
> String. For a lossless round trip keep the atoms:
>
>     m.add_table(head, {c: rows[c] for c in rows.columns})

### `MeTTa.remove`

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

### `MeTTa.atoms`

```python
def atoms(self) -> list[Atom]:
```

> Every stored atom in this space.

### `MeTTa.count`

```python
def count(self) -> int:
```

> Return the number of atoms stored in this space.

### `MeTTa.cast`

```python
def cast(self, value: Any, type_: Any, /) -> Any:
```

> Answer value, narrowed to its Python-most spelling, when this
> space's type discipline admits it as type_: the same acceptance
> a typed call compiles, ':' declarations in this space and &self
> in scope, protocol types included. A refused cast raises
> petta.CastError naming the value's actual types, the loud
> spelling of what a typed call does silently.

### `MeTTa.trace`

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

### `MeTTa.lint`

```python
def lint(self):
```

> Diagnose this space for the silently-wrong class: declared
> types nothing defines, arity mismatches, unbound body variables,
> duplicate equations, and references no function or fact carries.
> Answers petta.lint.Finding records, empty when nothing looks
> wrong.

### `MeTTa.copy`

```python
def copy(self) -> MeTTa:
```

> This space's contents in a new anonymous space, cloned through
> the bulk door, so equations copy as equations and keep running:
> "a scratch space set up like production" is one line. The handle
> is new_space()'s kind, so drop it, or use it as a context
> manager, to return the name. copy.copy(m) answers the same
> through the copy protocol. There is deliberately no __deepcopy__:
> stored Python objects keep their identity across the clone, the
> shallow reading, and a deep clone of a live engine handle has no
> meaning to promise.

### `MeTTa.digest`

```python
def digest(self) -> str:
```

> A sha256 hex digest of this space's content: every stored atom,
> equations included, canonicalized (variables numbered, multiset
> sorted) so the same atoms answer the same digest in any insertion
> order and in any process. Two spaces agree on digest() exactly
> when save() would write the same content. Live host objects have
> no cross-process identity and are refused, like save().

### `MeTTa.clear`

```python
def clear(self) -> None:
```

> Remove everything stored here, compiled equations included.

### `MeTTa.query`

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

> Match patterns against this space as one conjunction.
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
> **Slicing the result is not the same thing.** query() is EAGER, so
> `query(pat)[:3]` computes every row and throws all but three away.
> Over 2,000 stored atoms that measured 26,055 inferences against 20
> for `stream(pat)[:3]`, which pulls three and stops. Reach for `limit`
> when you want a bounded answer set, and for stream() when you want to
> take rows until you have seen enough.
>
> `into=` shapes each row into a dataclass, NamedTuple, or
> TypedDict matched by field name, sqlite3's row_factory reading:
> `m.query(S.edge(V.a, V.b), into=Edge)` answers `list[Edge]`,
> and Rows stays the default so nothing is lost.
>
>     m.query(S.Edge(V.x, V.y), S.Edge(V.y, V.z))

### `MeTTa.stream`

```python
def stream(
    self,
    *patterns: Any,
    where: Any | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Cursor:
```

> query(), pulled: the same conjunction and guard, answered one
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
> query() computes and decodes every answer up front. `timeout`
> bounds each pull's wall time; `inferences` is one budget for the
> cursor's whole engine work, spent across pulls, because an
> engine's inferences are its own. The cursor enumerates under the
> engine's logical update view: writes made after the first pull
> are not seen by this cursor.

### `MeTTa.assuming`

```python
def assuming(self, *facts: Any) -> _Assuming:
```

> Facts held only inside a with-block: the assumptions reading of
> a what-if query, added on entry, removed on exit, exceptions
> included.
>
>     with m.assuming(S.closed(S.bridge)):
>         detour = m.query(S.route(V.r), where=...)

### `MeTTa.transaction`

```python
def transaction(self, callable_: Callable[[], _R], /) -> _R:
```

> Run a zero-argument callable inside one engine transaction,
> now, answering its return value: the Python door of the MeTTa
> (transaction ...) form, riding the same petta_transaction/1, so
> foreign-space enlistment and nesting behave identically in both
> languages.
>
>     m.transaction(lambda: migrate(m))
>
> Every engine write the callable makes, stored atoms, equations
> and their compiled clauses included, commits or rolls back
> together. An exception is the one rollback trigger, because a
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

### `MeTTa.limits`

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

### `MeTTa.batch`

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

### `MeTTa.transactional`

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

### `MeTTa.prepare`

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

### `MeTTa.eval`

```python
def eval(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
    capture: bool = False,
    residuals: bool = False,
) -> list[Atom | Undefined] | tuple[list[Atom | Undefined], str]:
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
> undefined, never as an ordinary-looking value. `residuals=True`
> additionally fills each Undefined's .residual with the residual
> program, the clauses of the loop itself. run() does not carry the
> third truth value; evaluate through eval() when it matters.
>
> `using` binds named host values into the term before it evaluates,
> exactly as it does for run(): `m.eval("(decide $x)", using={"x":
> tensor})` hands the tensor itself to the rule, by identity, rather
> than a printed form of it. The evaluation doors take the same
> vocabulary the source door takes, so reaching for a term instead
> of source text costs no change of spelling.
>
> `timeout` (seconds) and `inferences` (engine steps) bound the call,
> raising TimeLimitError or InferenceLimitError when hit. With
> `capture=True` the return value is (answers, text), text being
> everything the evaluation printed.

### `MeTTa.parallel`

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

### `MeTTa.hyperpose`

```python
def hyperpose(self, *targets: Any, timeout: float | None = None) -> list[Atom | Undefined]:
```

> parallel(), under the language's own name.
>
> (hyperpose ...) is the engine form this runs, so the Python
> surface reads MeTTa-natively; a thread pool is a space whose
> atoms are spaces, and this is how one is exercised from Python.

### `MeTTa.pool`

```python
def pool(self, workers: int | None = None) -> _EnginePool:
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
>         p.map(lambda n: m.one(f"(sq {n})"), range(64))
>
> Use it as a context manager so every engine is released. `workers`
> defaults to os.cpu_count(). This handle stays usable from the workers:
> a MeTTa is a space name over the process runtime, not thread-owned.
>
> Reach for `parallel()` instead when the fan-out is a MeTTa expression
> rather than a Python loop; the two compose.

### `MeTTa.eval_status`

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
>     m.eval_status(S.double(4))       # [("value", Gnd(8))]
>     m.eval_status(S.Point(1, 2))     # [("not-reducible", Expr(...))]
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

### `MeTTa.run_status`

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

### `MeTTa.one`

```python
def one(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Any:
```

> THE answer of evaluating target, as a plain Python value.
>
>     m.one("(+ 1 2)")            # 3
>     m.one(S.fact(5))            # 120
>
> Exactly one answer is the contract: none or several raise naming
> the count, because a caller asking for the value has asserted
> there is one. Grounded answers unwrap to their Python values;
> symbols and structure stay atoms.
>
> This is one point on the answer-cardinality axis, spelled the
> same everywhere it appears: eval() takes every answer (MeTTa's
> collapse), first() takes the first and tolerates absence, one()
> demands exactly one. fn() and Rows carry the same triple, and
> the same timeout/inferences bounds apply throughout.
>
> An `(Error ...)` answer raises MettaResultError carrying the
> atom: an error among the answers is the evaluation reporting
> failure, and failure outranks the count. eval() is the door
> that keeps errors as data.

### `MeTTa.first`

```python
def first(
    self,
    target: Any,
    *,
    using: dict[str, Any] | None = None,
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

### `MeTTa.stats`

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

### `MeTTa.register_op`

```python
def register_op(
    self,
    fn: Callable | None = None,
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
    pure: bool = False,
) -> Any:
```

> Register a Python callable as a MeTTa function, decorator-style.
>
>     @m.register_op
>     def double(x: int) -> int:
>         return 2 * x                    # !(double 21) -> 42
>
>     @m.register_op
>     def neighbours(n: int):
>         yield n - 1                     # a generator is nondeterministic
>         yield n + 1
>
> Annotations become a (: ...) declaration unless typed=False, and the
> three combinations answer differently, which is worth knowing because
> the middle one reads like nothing happened:
>
>     def op(x: int) -> int    typed=True   (: op (-> Number Number))
>     def op(x)                typed=True   (: op (-> %Undefined% %Undefined%))
>     def op(x)                typed=False  no declaration at all
>
> The unannotated typed=True case is not a no-op. It declares the ARROW
> SHAPE, so get-type answers that op is a one-argument function while
> constraining neither slot, and typed=False leaves get-type answering
> %Undefined%. It also costs nothing per call: a %Undefined% slot emits
> no check.
>
> A raw operation skips the wire encoding both ways, which suits tensor
> and number work; symbols reach it as plain strings, so keep raw off
> when the symbol-string distinction matters. pass_atoms hands the
> callable Atom objects instead of decoded Python values.
> unregister_op(name) removes every registered arity.
>
> The cost ladder, measured on the maintained box in inferences per
> call, is why the flags exist and which one to reach for:
>
>     native MeTTa function            9.11   the floor
>     raw=True                        10.11   opaque handles, near-native
>     typed=False                     17.11   encoded values
>     typed=True, literal argument    17.11   the check hoists to compile
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
>     m.register_op(cons, name="cons", inverse=uncons)
>     # !(let (cons $h $t) (1 2 3) ($h $t))  ->  (1 (2 3))
>
> It takes the result and returns the arguments, as a tuple, or the
> bare value at arity one; a generator enumerates every preimage, and
> None or Decline means there is none. It runs only when the arguments
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
>     @m.register_op
>     def related(term, engine: petta.MeTTa):
>         for row in engine.query(expr(S.link, term, V.x)):
>             yield row[0]
>
> pure=True says the operation has no effect a cache could hide, which
> is what lets it appear in a `(tabled ...)` or memoized body:
>
>     m.register_op(len, name="size", pure=True)
>     # (= (count-of $x) (size $x))  is cacheable
>
> It is an allow-list on purpose. An operation that does not say so is
> refused by name in a cached body, loudly, rather than cached and
> quietly wrong.

### `MeTTa.unregister_op`

```python
def unregister_op(self, name: str) -> None:
```

> Remove a registered operation, every arity of it.
>
> An absent name raises KeyError, as convert.unregister_type does:
> removing something that was never there is a mistake worth hearing
> about, not a no-op to absorb.

### `MeTTa.builtins`

```python
def builtins(self) -> list[str]:
```

> Every function name the engine has registered.

### `MeTTa.is_function`

```python
def is_function(self, name: str) -> bool:
```

> Report whether a function is visible from this space.

### `MeTTa.is_function_here`

```python
def is_function_here(self, name: str) -> bool:
```

> Whether a function would answer from THIS space: it has clauses
> this space's module sees, its own or the shared ones in user.
> Another space's equations are invisible here and do not count.

### `MeTTa.arities`

```python
def arities(self, name: str) -> list[int]:
```

> Compiled predicate arities for a name: MeTTa arity plus one each.

### `MeTTa.disassemble`

```python
def disassemble(self, name: str) -> str:
```

> The Prolog clauses a function name compiled to, dis for the
> translator: one listing per registered arity, resolved in this
> space's module. What the engine RUNS for a call, which is the
> debuggability bytecode has and homoiconicity alone does not
> give, since (= ...) atoms are the source, not the compilation.
> Also reachable as m.fn(name).compiled.

### `MeTTa.register_prolog`

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
> register_op() is the one most people find first, and every call it
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
>     m.one("(vec-dot (1 2) (3 4))")
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
> register_op and define. Only equations are space-scoped, so a
> new_space() isolates one of the three things you can register and
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
>     m.one("(shape-of (+ 1 2))")     # (shape (+ 1 2)), not (shape 3)
>
> Declare it BEFORE anything calls the function. A call site compiled
> while the declaration is absent keeps evaluating the argument even
> after it lands.

### `MeTTa.register_foreign_library`

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

### `MeTTa.register_library_path`

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

### `MeTTa.unregister_prolog`

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

### `MeTTa.subscribe`

```python
def subscribe(
    self,
    pattern: Any,
    callback: Callable | None = None,
    *,
    on: str = 'add',
    queue_max: int = SUBSCRIPTION_QUEUE_MAX,
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

### `MeTTa.prolog`

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

### `MeTTa.derivation`

```python
def derivation(
    self,
    target: Any,
    depth: int | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> list[Derivation]:
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

### `MeTTa.why`

```python
def why(self, pattern: Any) -> str:
```

> Why a pattern matches nothing here, in words.
>
> Checks the cheap explanations in order: unknown function, wrong
> arity, no stored atoms with that head. Honest when it cannot tell.

### `MeTTa.define`

```python
def define(
    self,
    fn: Callable[..., Any] | None = None,
    *,
    prolog: str | os.PathLike[str] | None = None,
    name: str | None = None,
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
>     m.one("(vec-dot (1 2) (3 4))")    # the Prolog answers
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
>     m.run("!(add-one 5)")       # [[6]]
>     add_one.py(5)               # 6, ordinary Python
>
> The equation's name is the Python name, verbatim, or `name=`
> when given. Hyphens are the MeTTa convention and Python cannot
> spell one, so a hyphenated name is asked for rather than inferred:
>
>     @m.define(name="add-one")
>     def add_one(n):
>         return n + 1
>
> Nothing is rewritten behind the author's back, which is the whole
> of the rule: the name in the source is the name in the space.
>
> A generator compiles to nondeterminism (each yield one answer), a
> lambda to the engine's own |->, a comprehension to map-atom and
> filter-atom, and match(Pattern(x, y), template) to a match against
> the running space, lowercase free names in the pattern binding as
> variables.

### `MeTTa.type`

```python
def type(self, cls: _builtins.type | None = None, *, accessors: bool = True, methods: bool = True):
```

> Declare a Python class INTO this space, decorator-style: the
> (: ...) declarations land as atoms, an expression-image class
> (a dataclass, a NamedTuple) gains one accessor equation per
> field, and its own METHODS register as MeTTa functions, so the
> class crosses with its behavior, not only its structure.
>
>     @m.type
>     @dataclass
>     class Point:
>         x: float
>         y: float
>         def norm(self) -> float:
>             return (self.x ** 2 + self.y ** 2) ** 0.5
>
>     m.run("!(Point-x (Point 3.0 4.0))")        # [[3.0]]
>     m.run("!(Point-norm (Point 3.0 4.0))")     # [[5.0]]
>
> A method receives the instance whether it arrives as a
> constructor TERM (rebuilt through the translator) or as a live
> handle, and a result the translator knows projects back as a
> term, so a method answering the class answers something MeTTa
> keeps matching and Python builds back. An equation over the
> constructor is then a method written in MeTTa itself, on equal
> footing. An Enum declares its members; get-type sees them all.
> Returns the class, so it stacks under @dataclass.

### `MeTTa.fn`

```python
def fn(self, name: str) -> _EngineFunction:
```

> Any engine function as an ordinary Python callable.
>
>     car = m.fn("car-atom")
>     car(m.parse("(1 2 3)"))     # 1
>     m.fn("superpose").all(expr(1, 2, 3))   # [1, 2, 3]
>
> Calling expects exactly one answer and raises otherwise, the loud
> reading; .all returns every answer, nondeterminism included.

### `MeTTa.integrate`

```python
def integrate(self, target: Any) -> str:
```

> Install a library integration; see petta.integrate.

### `MeTTa.register_space`

```python
def register_space(self, provider: Any, name: str) -> Any:
```

> A space answered by Python: matches, adds and removals route to
> the provider, so a table, a dataframe or a service is matchable the
> way stored atoms are. See petta.foreign.SpaceProvider.
>
> Subject first, as every register_* call: the thing being
> registered, then where it lives. The two calls that named the
> name first were the surface's own inconsistency, and learning
> the order from register_op raised TypeError here.

### `MeTTa.unregister_space`

```python
def unregister_space(self, name: str) -> None:
```

> Remove a registered Python-backed space.

### `MeTTa.declare_handles`

```python
def declare_handles(
    self,
    name: str,
    pattern: str | Atom,
    fidelity: Literal['Exact', 'Partial', 'Sound', 'Refuse'],
    *,
    det: str | None = None,
) -> Atom:
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
>     m.declare_handles("&rows", "(edge (in $a) $b)", "Refuse")
>
> Coherence is checked eagerly in the same transaction as the
> write: a new entry that can disagree with an existing one on some
> query fails here, naming both, rather than on the first query
> that falls into their overlap. The atom is returned; removing it
> from &petta withdraws the declaration.

### `MeTTa.declare_annotations`

```python
def declare_annotations(
    self,
    name: str,
    semiring: Literal['bool', 'bag', 'set', 'ranked', 'prob', 'prov'],
) -> Atom:
```

> Declare the semiring a context's answer annotations live in.
>
> A context is a space name or an operation name. bool is the
> default at which everything vanishes; ranked admits ordered
> annotations, which is what (top k ...) consumes. Declaring
> replaces any earlier declaration for the context, so the reader
> never meets two disagreeing atoms.

### `MeTTa.declare_source`

```python
def declare_source(self, name: str, kind: Literal['linear', 'repeated', 'peek']) -> Atom:
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

### `MeTTa.declare_on_error`

```python
def declare_on_error(
    self,
    name: str,
    pattern: str | Atom,
    mode: Literal['keep', 'empty', 'abort'],
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

### `MeTTa.declare_merge`

```python
def declare_merge(
    self,
    pattern: str | Atom,
    policy: Literal['depth', 'fair', 'best-first'],
) -> Atom:
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

### `MeTTa.declare_context`

```python
def declare_context(self, name: str, world: Literal['closed-world', 'open-world']) -> Atom:
```

> Record what a space's absence means.
>
> Negation as failure reads absence as falsity, which is only
> sound over a world the answerer holds whole, so a negated goal
> may consult a foreign space only when it declares closed-world;
> an undeclared one refuses under negation loudly. Native spaces
> are the engine's own database and closed by construction.

### `MeTTa.declare_reaction`

```python
def declare_reaction(self, name: str, pattern: str | Atom, operation: str | Atom) -> Atom:
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
> petta.bridge() is the NEIGHBOUR, not a special case of this: a
> reaction's operation runs engine-side, so it reaches registered
> spaces, while a bridge rule delivers Python-side to anything
> with add and remove, an unregistered or remote target included.
> Same multi-context-systems idea, two delivery tiers.

### `MeTTa.declare_admits`

```python
def declare_admits(self, name: str, type_name: str) -> Atom:
```

> Type a pool's membership: only TYPE-carrying atoms enter.
>
> A thread pool is a space whose atoms are spaces, and this is its
> door: (admits &pool Space) plus per-atom (: &lt;space> Space)
> declarations make membership a type judgement the ontology
> already knows how to make.

### `MeTTa.declare_capacity`

```python
def declare_capacity(self, name: str, limit: int) -> Atom:
```

> Bound a pool: an add beyond LIMIT atoms is refused loudly.

### `MeTTa.declare_writes`

```python
def declare_writes(
    self,
    name: str,
    atomicity: Literal['transactional', 'atomic-single', 'best-effort'],
) -> Atom:
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

### `MeTTa.declare_emits`

```python
def declare_emits(self, name: str, policy: Literal['depth', 'fair', 'best-first']) -> Atom:
```

> Declare the order a context emits its own answers in.
>
> best-first is the promise (top k ...) needs before its bound may
> reach the provider: the first k of a best-first emission ARE the
> k best. Distinct from the (merge &lt;pattern> &lt;policy>) strategy,
> which is how the ENGINE merges answers across several contexts.

### `MeTTa.runtime`

```python
def runtime(self) -> Runtime:
```

> The engine bridge itself, for callers going under the surface.
