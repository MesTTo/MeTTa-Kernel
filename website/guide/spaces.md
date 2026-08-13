# Spaces

`MeTTa()` binds to `&self`, the same space used by the CLI. `m.space(name)` selects another named space on the same engine. `m.fresh_space()` creates an unused name and can be used as a context manager. Leaving the block drops that space.

Spaces isolate stored atoms and equations. `(context-space)` names the space where the current code runs. `save(path)` writes serializable atoms and equations as loadable MeTTa source. `load(path)` loads a `.metta` file with the CLI's working-directory behavior.

## Python-backed spaces

A `SpaceProvider` keeps atoms in Python or in another storage system. The engine still unifies the candidates returned by the provider. A provider may return an over-approximation, while bound positions can be pushed down for speed.

The DuckDB integration maps each table to a relation. The example below registers an in-memory database as `&crm`, queries it, writes through the space, and joins SQL rows with native facts:

```python
from _common import check, done, skip

try:
    import duckdb
except ImportError:
    skip("duckdb is not installed")

from petta import MeTTa, expr, S

from petta.integrations.duckdb_space import attach

m = MeTTa().fresh_space()
conn = duckdb.connect(":memory:")
conn.execute("create table users (id integer, name text)")
conn.execute("insert into users values (1, 'Ada'), (2, 'Bob'), (3, 'Cy')")
attach(m, "&crm", conn)

check("enumerate", m.run("!(collapse (match &crm (users $id $n) $n))"),
      [[expr("Ada", "Bob", "Cy")]])
check("pushdown filter", m.run("!(match &crm (users 2 $n) $n)"), [["Bob"]])

m.run('!(add-atom &crm (users 4 "Dee"))')
check("insert landed in SQL",
      conn.execute("select name from users where id = 4").fetchone()[0], "Dee")

m.run("(vip 1)\n(vip 4)")
(group,) = m.run(
    "!(collapse (match (context-space) (vip $id)"
    " (match &crm (users $id $n) $n)))"
)
check("SQL joined with native facts", group, [expr("Ada", "Dee")])
done("04_sql_is_a_space")
```

Implement another backend by subclassing [`SpaceProvider`](../reference/petta-foreign#spaceprovider), then register it with `m.register_space(name, provider)`.
