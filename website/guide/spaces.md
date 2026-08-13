# Spaces

`MeTTa()` binds to `&self`, the same space used by the CLI. `m.space(name)` selects another named space on the same engine. `m.fresh_space()` creates an unused name and can be used as a context manager. Leaving the block drops that space, and a drop clears the whole life: atoms, equations, subscriptions, import markers, and tabling state all go, so a pooled name's next life starts from nothing.

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

For facts that should persist as they change rather than at save points, `petta.persistent.PersistentFactSpace(path, {"edge": 2})` is a space whose writes journal to an append-only text file and replay when a new process attaches, `library(persistency)` underneath. It is schema-bound and holds natives only, its limits stated in its own docstring. The default sync mode buffers for speed (169k adds/s measured); `flush()` is the on-demand checkpoint, and `sync="flush"` buys per-write crash survival for about two percent, proven in the suite by replaying a journal whose writer died mid-run from SIGKILL. Registered with `m.register_space`, it matches like any space, and it is the event-store half of an event-sourcing page: the journal is the log, projections are `bridge()` subscriptions into read models.

## MORK at scale

[MORK](https://github.com/trueagi-io/MORK) is a PathMap-backed store built for atom counts far past the predicate store's reach. The integration's own measurements set the honest expectations: below roughly ten million atoms the predicate store is faster, and from one hundred to four hundred million atoms MORK kept answering where the predicate store ran out of memory.

To enable it, run `sh build.sh` at the repository root: `mork_ffi` ships in the tree, and the script builds it on nightly Rust against `MORK` and `PathMap` checkouts beside the repository, cloned at the validated revisions when absent. Once `mork_ffi/target/release/libmork_ffi.so` exists, the CLI and the python runtime both detect it and boot the engine with the `&mork` space wired in; nothing else changes.

`m.space("&mork")` then behaves like any space: adds, removes, queries, `count()`, `atoms()`, subscriptions, and `digest()` all run the ordinary surface with MORK as the store, and `digest()` agrees with a native space holding the same atoms because the digest names content, not storage. A conjunction joins in the engine with MORK answering each conjunct:

```python
    mork.add(S.friend(S.sam, S.tim), S.friend(S.sam, S.joe), S.age(S.tim, 30))
    join = mork.query(S.friend(S.sam, V.x), S.age(V.x, V.n))
    assert [(row.x, row.n) for row in join] == [(S.tim, 30)]
```

Writes queue inside MORK for throughput and every read flushes the queue first, so a program always reads its own writes. `m.space("&mork:name")` addresses a named MORK space, its own store created on first use and fully isolated from the default and from every other name. `(mork-add-atoms space atoms)` lands a whole list in one FFI call, with MORK parsing the batch itself; measured at twenty thousand atoms it answered 76.7k against the per-atom path's 69.8k atoms per second, the write queue already amortizing most of the difference. `lib_mm2` layers the minimal-MeTTa surface on top: `＋` and `－` add and remove, `＋*` bulk-adds a list, `?` queries, and `~>` compiles a transform into an exec rule that MORK's own calculus runs, entirely inside the store.

## Shared spaces over Redis

`lib_redis` binds a space name to a Redis set through the same foreign-space seam, SWI's own `library(redis)` underneath. Load it with `!(import! &self (library lib_redis))`, then `!(redis-attach &shared "localhost:6379")` claims the name: from then on every process attached to the same address and name reads and writes the same facts, and the whole surface just works on it:

```python
    shared.add(S.stock(S.widget, 5), S.stock(S.gadget, 7))
    rows = shared.query(S.stock(V.item, V.n))
    assert sorted(str(row.item) for row in rows) == ["gadget", "widget"]
    assert shared.count() == 2
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
            "m.space('&shared-test').add(S.alert(S.red), S.other(S.noise))\n",
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
m = MeTTa().fresh_space()
conn = duckdb.connect(":memory:")
conn.execute("create table users (id integer, name text)")
conn.execute("insert into users values (1, 'Ada'), (2, 'Bob'), (3, 'Cy')")
conn.execute("create table vips (id integer)")
conn.execute("insert into vips values (1), (3)")
provider = attach(m, "&crm", conn)

check("enumerate", m.run("!(collapse (match &crm (users $id $n) $n))"),
      [[expr("Ada", "Bob", "Cy")]])
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
check("SQL joined with native facts", group, [expr(expr("Ada", S["the-countess"]))])
```


Implement another backend by subclassing [`SpaceProvider`](../reference/petta-foreign#spaceprovider), then register it with `m.register_space(name, provider)`.
