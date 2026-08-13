# Spaces

`MeTTa()` binds to `&self`, the same space used by the CLI. `m.space(name)` selects another named space on the same engine. `m.fresh_space()` creates an unused name and can be used as a context manager. Leaving the block drops that space.

Spaces isolate stored atoms and equations. `(context-space)` names the space where the current code runs. `save(path)` writes serializable atoms and equations as loadable MeTTa source. `load(path)` loads a `.metta` file with the CLI's working-directory behavior. `save(path, format="fast")` writes the same atoms as a version-pinned binary cache instead, measured 10.4x faster than text over twenty thousand atoms, and `load` auto-detects it by its header; the header pins the exact SWI-Prolog version, a mismatch refuses with a re-save message before any byte of payload is read, and text stays the durable interchange format.

For facts that should persist as they change rather than at save points, `petta.persistent.PersistentFactSpace(path, {"edge": 2})` is a space whose writes journal to an append-only text file and replay when a new process attaches, `library(persistency)` underneath. It is schema-bound and holds natives only, its limits stated in its own docstring. The default sync mode buffers for speed (169k adds/s measured); `flush()` is the on-demand checkpoint, and `sync="flush"` buys per-write crash survival for about two percent, proven in the suite by replaying a journal whose writer died mid-run from SIGKILL. Registered with `m.register_space`, it matches like any space, and it is the event-store half of an event-sourcing page: the journal is the log, projections are `bridge()` subscriptions into read models.

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
