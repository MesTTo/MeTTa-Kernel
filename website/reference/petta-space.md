# `petta.space`

Source: `python/petta/space.py`.

> Purpose: the MeTTa runtime surface. One class binds a space name to the
> process's engine and offers running source, loading files, structured space
> edits, conjunctive queries with guards, bounds, scoped assumptions and
> preparation, evaluation, Python-backed operations, proof-tree derivations
> and a why-not diagnostic, all in PeTTa's own semantics.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `current_space`

```python
def current_space(default: str = "&self") -> str:
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
> default space is &amp;self, the space the CLI itself uses, so source pasted
> from a .metta file behaves identically here. Named spaces isolate stored
> atoms; equations are process-wide, which is the engine's own rule.
>
>     from petta import MeTTa, S, V
>
>     m = MeTTa()
>     m.run("(= (foo) boo) !(foo)")     # [[Sym('boo')]]
>     m.add(S.Parent(S.Tom, S.Bob))
>     m.query(S.Parent(V.x, S.Bob))     # Rows[x](Row(x=Sym('Tom')))

### `MeTTa.space_name`

```python
def space_name(self) -> str:
```

No docstring is defined.

### `MeTTa.space`

```python
def space(self, name: str) -> "MeTTa":
```

> Another space on the same engine.

### `MeTTa.fresh_space`

```python
def fresh_space(self) -> "MeTTa":
```

> An anonymous space with a name nothing else is using.
>
> Works as a context manager: leaving the block drops the space, so a
> churn of short-lived spaces reuses names instead of growing the
> engine's module table.
>
>     with m.fresh_space() as scratch:
>         scratch.add(...)

### `MeTTa.drop`

```python
def drop(self) -> None:
```

> Clear this space and release its name for reuse. Dropping a
> foreign space releases the binding and leaves the provider's own
> data alone; &amp;self, the engine's own space, is cleared but its name
> never released. Subscriptions on the space cancel with it: a
> pooled name reused later must not deliver to the old life's
> watchers.

### `MeTTa.run`

```python
def run(self, source: str, using: dict[str, Any] | None = None) -> list[list[Atom]]:
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

### `MeTTa.save`

```python
def save(self, path: str) -> int:
```

> Write every stored atom of this space, equations included, as
> MeTTa source load() reads back; answers how many. Atoms carrying
> live host objects cannot survive a file and are refused.

### `MeTTa.load`

```python
def load(self, path: str) -> list[list[Atom]]:
```

> Load a .metta file the way the CLI does, working directory included.

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
> or any iterable of row sequences. A mapping's fact positions are
> its own key order, and columns of unequal length are a hard error
> rather than a silent truncation. The reverse direction is
> rows.table(), the dict every DataFrame constructor takes.

### `MeTTa.remove`

```python
def remove(self, atom: Any) -> bool:
```

> Remove an atom, engine semantics: an equation removal reports
> whether it existed; a plain atom removal removes every copy.

### `MeTTa.atoms`

```python
def atoms(self) -> list[Atom]:
```

> Every stored atom in this space.

### `MeTTa.count`

```python
def count(self) -> int:
```

No docstring is defined.

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
) -> Rows:
```

> Match patterns against this space as one conjunction.
>
> Variables shared between patterns join, the engine's own match/4
> doing the joining. Columns are the variable names in first
> appearance order. `where` is a guard term over the same variables,
> evaluated per join and required true, so restrictions a pattern
> cannot spell (an inequality) compose onto the match:
>
>     m.query(S.person(V.name, V.age), where=V.age &gt;= 18)
>
> `limit` bounds the answers, the engine stopping at the count
> rather than trimming afterwards.
>
>     m.query(S.Edge(V.x, V.y), S.Edge(V.y, V.z))

### `MeTTa.assuming`

```python
def assuming(self, *facts: Any) -> "_Assuming":
```

> Facts held only inside a with-block: the assumptions reading of
> a what-if query, added on entry, removed on exit, exceptions
> included.
>
>     with m.assuming(S.closed(S.bridge)):
>         detour = m.query(S.route(V.r), where=...)

### `MeTTa.prepare`

```python
def prepare(self, *patterns: Any, where: Any | None = None) -> "Prepared":
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
def eval(self, target: Any) -> list[Atom]:
```

> Evaluate a term, returning every answer.
>
> This is what !(...) runs, minus the printing: the engine's
> translate_expr over the term, then its goals. Nondeterminism means
> the list can hold any number of answers, including none.

### `MeTTa.value`

```python
def value(self, target: Any) -> Any:
```

> THE answer of evaluating target, as a plain Python value.
>
>     m.value("(+ 1 2)")            # 3
>     m.value(S.fact(5))            # 120
>
> Exactly one answer is the contract: none or several raise naming
> the count, because a caller asking for the value has asserted
> there is one. Grounded answers unwrap to their Python values;
> symbols and structure stay atoms. eval() is the spelling for any
> number of answers.

### `MeTTa.op`

```python
def op(
    self,
    fn: Callable | None = None,
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    arities: list[int] | None = None,
):
```

> Register a Python callable as a MeTTa function, decorator-style.
>
>     @m.op
>     def double(x: int) -&gt; int:
>         return 2 * x                    # !(double 21) -&gt; 42
>
>     @m.op
>     def neighbours(n: int):
>         yield n - 1                     # a generator is nondeterministic
>         yield n + 1
>
> Annotations become a (: ...) declaration unless typed=False. A raw
> operation skips the wire encoding both ways, which suits tensor and
> number work; symbols reach it as plain strings, so keep raw off when
> the symbol-string distinction matters. pass_atoms hands the callable
> Atom objects instead of decoded Python values.

### `MeTTa.unregister`

```python
def unregister(self, name: str) -> None:
```

> Remove a registered operation, every arity of it.

### `MeTTa.builtins`

```python
def builtins(self) -> list[str]:
```

> Every function name the engine has registered.

### `MeTTa.is_function`

```python
def is_function(self, name: str) -> bool:
```

No docstring is defined.

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

### `MeTTa.subscribe`

```python
def subscribe(
    self,
    pattern: Any,
    callback: Callable | None = None,
    *,
    on: str = "add",
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
> them: the mailbox reading. Removal events for plain atoms may fire
> for atoms that were never stored, since the engine's removal is
> retractall; re-check the space rather than trust the event.

### `MeTTa.prolog`

```python
def prolog(self) -> None:
```

> Drop into the engine's own interactive Prolog toplevel, the
> deepest debugging lever there is: listing/1 shows compiled
> equations, trace/0 steps through them, and quitting the toplevel
> returns here with the session intact. janus's own janus.prolog(),
> surfaced where the debugging happens.

### `MeTTa.derivation`

```python
def derivation(self, target: Any, depth: int = 30) -> list[Derivation]:
```

> Every proof of an answer, as trees in MeTTa terms.
>
> Each tree names the equations that fired and the stored atoms at the
> leaves, read from the translated_from links the engine keeps for
> every compiled clause. Meta-interpreted, so slower than evaluation;
> a diagnostic, not an evaluation path. Depth bounds the SEARCH, and
> an evaluation error inside a proof surfaces as itself rather than
> as an empty proof list.

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
def define(self, fn: Callable):
```

> Compile a Python function into MeTTa equations, decorator-style.
>
> Written for whoever is fluent in Python rather than s-expressions:
> the body is read as syntax and lowered deterministically, refusals
> name the construct, the line and what to write instead, and the
> original stays reachable as .py, a twin the equations can be checked
> against on any ground input.
>
>     @m.define
>     def fact(n):
>         if n == 0:
>             return 1
>         return n * fact(n - 1)
>
>     m.run("!(fact 5)")          # [[120]]
>     fact.py(5)                  # 120, ordinary Python
>
> A generator compiles to nondeterminism (each yield one answer), a
> lambda to the engine's own |-&gt;, a comprehension to map-atom and
> filter-atom, and match(Pattern(x, y), template) to a match against
> the running space, lowercase free names in the pattern binding as
> variables.

### `MeTTa.type`

```python
def type(self, cls: type | None = None, *, accessors: bool = True, methods: bool = True):
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
>         def norm(self) -&gt; float:
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
def fn(self, name: str) -> "_EngineFunction":
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
def register_space(self, name: str, provider: Any) -> Any:
```

> A space answered by Python: matches, adds and removals route to
> the provider, so a table, a dataframe or a service is matchable the
> way stored atoms are. See petta.foreign.SpaceProvider.

### `MeTTa.unregister_space`

```python
def unregister_space(self, name: str) -> None:
```

No docstring is defined.

### `MeTTa.runtime`

```python
def runtime(self) -> Runtime:
```

> The engine bridge itself, for callers going under the surface.

## `Prepared`

```python
class Prepared:
```

> A prepared query: pattern wires and columns built once, solved many
> times, optionally with per-call facts. The ladder the clingo API walks
> (assumptions per solve, inputs per session, rules added), with the rung
> clingo lacks: rules REMOVED, since this engine erases clauses whole.
>
>     route = m.prepare(S.path(V.a, V.b))
>     route.solve()
>     route.solve(given=[S.edge(S.a, S.b)])   # facts for this call only

### `Prepared.solve`

```python
def solve(self, given: list | None = None, limit: int | None = None) -> Rows:
```

> Answers now, with `given` facts present for this call alone.
