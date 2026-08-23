<!--
Purpose: explain Space handles, journal-backed stores, composition, and external backing providers.
Guarantees: examples use the public metta.space() and metta.attach() creation doors.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Spaces

`metta.engine().self` binds to `&self`, the same space used by the CLI. `metta.space(name)` selects another named space on that engine. `metta.space()` creates an unused name and can be used as a context manager. Inside any space, source that says `&self` means that hosting space itself: the reader substitutes the token for the space's name, so the same program text runs unchanged wherever it is loaded. Leaving the block drops that space, and a drop clears the whole life: atoms, equations, subscriptions, import markers, and tabling state all go, so a pooled name's next life starts from nothing.

Spaces isolate stored atoms and equations. `(context-space)` names the space where the current code runs. `save(path)` writes serializable atoms and equations as loadable MeTTa source. `load(path)` loads a `.metta` file with the CLI's working-directory behavior. `save(path, format="fast")` writes the same atoms as a version-pinned binary cache instead, measured 10.4x faster than text over twenty thousand atoms, and `load` auto-detects it by its header; the header pins the exact SWI-Prolog version and carries a sha256 of the payload, so a version mismatch refuses with a re-save message and a corrupt payload, even one flipped byte, refuses on integrity before the binary reader sees any of it. The proof costs about six milliseconds on the twenty-thousand-atom corpus, and text stays the durable interchange format. A path ending `.gz` compresses either format through zlib on the engine side and gzip on the Python side, interchangeably: over the same twenty thousand atoms, text shrank 4.7x and the fast cache 5.1x, with load time within two milliseconds of the uncompressed file either way. `import!` and the CLI read `.metta.gz` programs under their ordinary names too, and a corrupt archive refuses loudly, naming the file.

`digest()` names a space's content: one sha256 over every stored atom, equations included, canonicalized so insertion order and stored-variable names cannot change it. Two spaces agree on `digest()` exactly when `save()` would write the same content, in this process or another one, which makes it the cheap answer to "did anything change" and "are these two the same" without shipping the atoms:

```python
        a.add(S.dg(1), S.dg(2))
        a.run("(= (dg-f $x) (+ $x 1))")
        b.run("(= (dg-f $renamed) (+ $renamed 1))")
        b.add(S.dg(2), S.dg(1))
        assert a.digest() == b.digest()
```

Live host objects have no cross-process identity, so a space holding one refuses to digest, the same contract as `save()`.

When two digests disagree, `metta.spaces.diff(a, b)` says HOW: it answers `(only_in_a, only_in_b)` as the multiset difference over enumeration, so a space holding an atom twice against one holding it once differs by the one copy, and alpha-equivalent atoms count as the same atom, digest's own equivalence. Either side is anything the combinators accept, a `Space` handle or a provider.

`m.copy()` goes the other way: this space's contents in a new anonymous space, cloned through the bulk door, so equations copy as equations and keep running, "a scratch space set up like production" in one line. `copy.copy(m)` answers the same through the copy protocol, and the clone is `space()`'s kind of handle, so dropping it returns the name.

For facts that should persist as they change rather than at save points, `metta.space(backing={"edge": 2}, journal=path)` creates a schema-bound journal-backed store whose writes append to text and replay when a new process opens the same journal, `library(persistency)` underneath. `sync="flush"` asks for per-write crash survival; the default buffered mode is faster and closes cleanly when the handle is dropped. The resulting object is the same `Space` handle as every other backing, so query and write code does not depend on the persistence implementation. It is the event-store half of an event-sourcing page: the journal is the log, and subscriptions project changes into read models.

## A space is a Python container

The protocols Python containers speak all answer on a space, each mapped to the engine operation it already names. `len(m)` is `count()`, `atom in m` asks whether anything stored unifies, and `for atom in m` iterates `atoms()`. An empty space is still `True`: a space is a handle to a store, not a value that dwindles, so `if space:` never skips one that happens to be empty.

Subscription is query. `m[pattern]` answers `match(pattern)`, and because Python delivers `m[p1, p2]` as a tuple, the comma spells the join:

```python
    m.add(S.edge(S.a, S.b), S.edge(S.b, S.c))
    rows = m[S.edge(V.x, V.y), S.edge(V.y, V.z)]
    assert [(row.x, row.z) for row in rows] == [(S.a, S.c)]
```

A str key parses first, so `m["(edge $x $y)"]` works, and a slice is refused: `match(limit=n)` bounds an answer set. Deletion pairs with subscription the way `d[k]` and `del d[k]` pair. The two removal doors differ in how much they take: `remove()` is multiset subtraction, one unifying occurrence per call, reporting absence as `False`; `del m[pattern]` is the bulk spelling that drains every unifying occurrence, since `m[pattern]` is a query answering many rows, and it raises `KeyError` when nothing unified.

The in-place operators split by what their operand means. `m += x` is `add(x)` exactly, one atom per use, so a list lifts into one expression atom the same way `add` reads it; `m -= x` is `remove(x)`. The bulk door is `|=`, whose operand has no lifted reading: another space (equations included, compiled on arrival), a registered space name, or an iterable adding each element. A dict is refused there, because `add` reads the same dict as one grounded atom and its values would silently vanish.

```python
    m |= other_space
    m |= "&kb"
    m |= [S.note(1), "(note 2)"]
```

`m.space_names()` lists every space the engine registers, sorted: `&self` and `&petta` from boot, every native space that has been written to, and every foreign space currently bound. Naming a space never registers it; writing does.

## Combinators: spaces composed from spaces

`metta.spaces` composes existing spaces into new ones with zero engine changes, each combinator an ordinary provider attached under a name. `union(*spaces)` reads every member as one space, the way rdflib aggregates graphs: overlapping shapes answer as a nondeterministic union exactly as overlapping equations do, duplicates across members answer twice (a union of multisets), and no write operation exists, so `add-atom` on it meets the engine's capability refusal with `.capability` filled in. `readonly(inner)` is the one-line spelling for handing a space to code that must not mutate it.

```python
all_space = metta.attach("&all", metta.spaces.union(kb, rules))
all_space.run("!(match &all (edge $a $b) $b)")
```

`mapped(inner, declaration)` is a shape view over any space, the tables bridge with unification where tables emits WHERE: one `(bridge <outer> <inner>)` pair derives both directions, so renames, projections, and legacy-shape adapters stop being custom providers.

```python
view = metta.spaces.mapped(kb, "(bridge (edge $a $b) (triple $a linked-to $b))")
```

The view presents the inner space's `(triple ...)` atoms as `(edge ...)` atoms, adds map right-to-left, removal maps the pattern through, and atoms the declaration does not map are invisible here and untouched there. `overlay(front, back)` reads both layers and writes, removes, and clears the front only, `ChainMap`'s own rule, stated loudly because for multisets silent routing would invent placement decisions; `union` refuses writes precisely so nobody widens it into this. Combinators take combinators, `readonly(union(a, b))` included, because everything is the one seam, and `overlay` and `mapped` pass the same conformance kit any provider does.

`object_view(obj)` presents one live Python object as `(py-field obj name value)` atoms. It holds the object rather than a projected copy, so later Python mutations answer immediately. Compose it with stored facts to make fields participate in an ordinary join:

```python
manager = Manager(age=31)
kb.add(S.manager(S.ada, ground(manager)))
view = metta.spaces.object_view(manager)
live = metta.attach("&live", metta.spaces.union(kb, view))

rows = live.match(
    S.manager(V.who, V.manager),
    S["py-field"](V.manager, S.age, V.age),
)
assert rows["age"] == [31]
```

Register the view itself when MeTTa should mutate the object. Adding `(py-field obj age 32)` to that space performs `setattr(obj, "age", 32)`. An unbound field name enumerates dataclass fields, named-tuple fields, public instance attributes, or public slots. A bound name uses `getattr` directly, so a dynamic object may support named reads without claiming it can enumerate.

## MORK at scale

[MORK](https://github.com/trueagi-io/MORK) is a PathMap-backed store built for atom counts far past the predicate store's reach. The integration's own measurements set the honest expectations: below roughly ten million atoms the predicate store is faster, and from one hundred to four hundred million atoms MORK kept answering where the predicate store ran out of memory.

To enable it, run `sh build.sh` at the repository root: `mork_ffi` ships in the tree, and the script builds it on nightly Rust against `MORK` and `PathMap` checkouts beside the repository, cloned at the validated revisions when absent. Once `backends/mork/mork_ffi/target/release/libmork_ffi.so` exists, the CLI and the python runtime both detect it and boot the engine with the `&mork` space wired in; nothing else changes.

`metta.space("&mork")` then behaves like any space: adds, removes, queries, `len()`, `atoms()`, subscriptions, and `digest()` all run the ordinary surface with MORK as the store, and `digest()` agrees with a native space holding the same atoms because the digest names content, not storage. A conjunction is handed to MORK whole, so its own worst-case-optimal join answers it rather than the engine splitting it one pattern at a time:

```python
    mork.add(S.friend(S.sam, S.tim), S.friend(S.sam, S.joe), S.age(S.tim, 30))
    join = mork.match(S.friend(S.sam, V.x), S.age(V.x, V.n))
    assert [(row.x, row.n) for row in join] == [(S.tim, 30)]
```

Writes queue inside MORK for throughput and every read flushes the queue first, so a program always reads its own writes. `metta.space("&mork:name")` addresses a named MORK space, its own store created on first use and fully isolated from the default and from every other name. `(mork-add-atoms space atoms)` lands a whole list in one FFI call, with MORK parsing the batch itself; measured at twenty thousand atoms it answered 76.7k against the per-atom path's 69.8k atoms per second, the write queue already amortizing most of the difference. `lib_mm2` layers the minimal-MeTTa surface on top: `＋` and `－` add and remove, `＋*` bulk-adds a list, `?` queries, and `~>` compiles a transform into an exec rule that MORK's own calculus runs, entirely inside the store.

## Shared spaces over Redis

`lib_redis` binds a space name to a Redis set through the same foreign-space seam, SWI's own `library(redis)` underneath. Load it with `!(import! &self (library lib_redis))`, then `!(redis-attach &shared "localhost:6379")` claims the name: from then on every process attached to the same address and name reads and writes the same facts, and the whole surface just works on it:

```python
    shared.add(S.stock(S.widget, 5), S.stock(S.gadget, 7))
    rows = shared.match(S.stock(V.item, V.n))
    assert sorted(str(row.item) for row in rows) == ["gadget", "widget"]
    assert len(shared) == 2
    assert shared.remove(S.stock(S.widget, 5)) is True
    assert [str(atom) for atom in shared.atoms()] == ["(stock gadget 7)"]
```

Candidates enumerate from Redis and unify in the engine, and the engine splits conjunctions per conjunct, so a query can join shared facts with native ones in one `match`. Subscriptions reach across processes: every write publishes on a per-space channel carrying the writer's process nonce, so a remote write fires your callbacks asynchronously while your own writes fire them synchronously through the engine, each write heard exactly once per process. Here a second Python process attached to the same address writes, and this process's callback sees it (`_other_process` is the suite's helper that runs one):

```python
    seen = []
    subscription = shared.subscribe(
        S.alert(V.level), lambda event: seen.append(event)
    )
    try:
        _other_process(
            redis_address,
            "context.space('&shared-test').add(S.alert(S.red), S.other(S.noise))\n",
        )
        deadline = time.monotonic() + 10.0
        while not seen and time.monotonic() < deadline:
            time.sleep(0.05)
        assert len(seen) == 1
        assert seen[0].bindings["level"] == S.red
    finally:
        subscription.cancel()
```

`clear()` deletes the shared set itself, a deliberate cross-process act, and refuses loudly on a foreign space that defines no clear. `!(redis-detach &shared)` releases the binding, stops this process's subscriber and waits for it, and leaves the stored facts in Redis for the next attach; attaching a name twice, detaching a name that is not attached, and a subscription that fails to stop all raise instead of degrading.

## Python-backed spaces

A `SpaceProvider` keeps atoms in Python or in another storage system. The engine still unifies the candidates returned by the provider. A provider may return an over-approximation, while bound positions can be pushed down for speed.

The DuckDB integration maps each table to a relation. The example below registers an in-memory database as `&crm`, queries it, writes through the space, and joins SQL rows with native facts:

```python
m = metta.space()
conn = duckdb.connect(":memory:")
conn.execute("create table users (id integer, name text)")
conn.execute("insert into users values (1, 'Ada'), (2, 'Bob'), (3, 'Cy')")
conn.execute("create table vips (id integer)")
conn.execute("insert into vips values (1), (3)")
provider = attach(m, "&crm", conn)

check("enumerate", m.run("!(collapse (match &crm (users $id $n) $n))"),
      [[Expression("Ada", "Bob", "Cy")]])
check("pushdown filter", m.run("!(match &crm (users 2 $n) $n)"), [["Bob"]])
```

One match joins SQL tables with each other and with native facts:

```python
# One match joins SQL tables with each other and with native facts.
m.run("(nickname 1 the-countess)")
(group,) = m.run(
    "!(collapse (match &crm (, (vips $id) (users $id $n)) "
    "(match (context-space) (nickname $id $nick) ($n $nick))))"
)
check(
    "SQL joined with native facts",
    group,
    [Expression(Expression("Ada", S["the-countess"]))],
)
```


Implement another backend by subclassing [`SpaceProvider`](../reference/metta-foreign#spaceprovider), then attach it with `metta.attach(name, provider)`.
