# DuckDB as a space

A `SpaceProvider` lets an external store answer PeTTa matches. The DuckDB example maps each SQL table to a relation whose head is the table name and whose arguments follow the table's column order.

`DuckDBSpace` belongs to `python/examples/integration/duckdb_space.py`. It is not exported by `petta`, and installing PeTTa does not install a packaged DuckDB adapter. Copy or adapt the example when you want this integration.

## Push ground positions into SQL

The provider inspects the pattern before it asks DuckDB for rows. Grounded values and the `NULL` symbol become SQL predicates. Variables stay open. PeTTa still unifies every returned atom:

```python
    def match(self, pattern: Atom) -> Iterator[Atom]:
        if not (isinstance(pattern, Expr) and pattern.children and isinstance(pattern.head, Sym)):
            # A shapeless pattern falls back to full enumeration; the engine
            # unifies, so this stays correct.
            yield from self.atoms()
            return
        table = pattern.head.name
        if table not in self.table_names():
            return
        columns = self.columns(table)
        if len(pattern.args) != len(columns):
            return
        where, parameters = [], []
        for column, arg in zip(columns, pattern.args):
            if isinstance(arg, Gnd) or (isinstance(arg, Sym) and arg == NULL):
                # A ground position states its value; IS NOT DISTINCT FROM
                # is SQL equality that also finds NULL when NULL is asked.
                where.append(f"{_identifier(column)} IS NOT DISTINCT FROM ?")
                parameters.append(_to_sql_value(arg))
            # A non-NULL symbol stays out of the pushdown: rows carry text
            # as grounded strings, so a symbol never matches one and the
            # engine's unification is the answer, consistently.
        sql = f"select * from {_identifier(table)}"
        if where:
            sql += " where " + " and ".join(where)
        for row in self._conn.execute(sql, parameters).fetchall():
            yield Expr([Sym(table), *(_to_atom_value(v) for v in row)])
```

Equality pushdown reduces the SQL work while preserving PeTTa's final structural check. A non-NULL symbol does not become a SQL text comparison because SQL text returns as a grounded string, not a symbol.

## Register the provider

The example's `attach` helper accepts a connection, path, or in-memory database and registers the provider under a space name:

```python
def attach(m, name: str, database: Any = ":memory:", tables: list[str] | None = None) -> DuckDBSpace:
    """Register a DuckDB database as a space on this engine. database is a
    connection, a path, or :memory:. A path or :memory: opens a connection
    the space owns and close() closes; a passed connection stays the
    caller's."""
    if hasattr(database, "execute"):
        provider = DuckDBSpace(database, tables)
    else:
        provider = DuckDBSpace(duckdb.connect(database), tables)
        provider._owns_connection = True
    m.register_space(name, provider)
    return provider
```

The normal use path creates tables, registers `&crm`, enumerates rows, and binds a ground position:

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

## Join and write

Provider matching is available directly, and the registered space composes with native facts inside one MeTTa expression:

```python
# Provider-level match answers atoms directly.
check("provider-level match", list(provider.match(S.users(2, V.n))),
      [expr(S.users, 2, "Bob")])

# One match joins SQL tables with each other and with native facts.
m.run("(nickname 1 the-countess)")
(group,) = m.run(
    "!(collapse (match &crm (, (vips $id) (users $id $n)) "
    "(match (context-space) (nickname $id $nick) ($n $nick))))"
)
check("SQL joined with native facts", group, [expr(expr("Ada", S["the-countess"]))])

# Writes: add-atom inserts, remove-atom deletes, from running MeTTa.
m.run('!(add-atom &crm (users 4 "Dee"))')
check("insert landed in SQL",
      conn.execute("select name from users where id = 4").fetchone()[0], "Dee")
m.run('!(remove-atom &crm (users 4 "Dee"))')
check("delete landed in SQL",
      conn.execute("select count(*) from users where id = 4").fetchone()[0], 0)
```

Dates cross as ISO text and SQL `NULL` crosses as the `NULL` symbol. Clearing removes rows while preserving the schema, and unregistering removes the space binding:

```python
# NULL and dates: the NULL symbol both ways, ISO text for scalar types,
# a NULL binding finding exactly the NULL row, clear() keeping the schema.
conn.execute("create table logs (day DATE, note TEXT)")
conn.execute("insert into logs values (DATE '2026-08-13', 'shipped'), (NULL, 'undated')")
rows = m.run("!(collapse (match &crm (logs $d $n) ($d $n)))")
listed = {str(pair) for pair in rows[0][0]}
check("a date crosses as its ISO text", '("2026-08-13" "shipped")' in listed, True)
check("NULL crosses as the NULL symbol", '(NULL "undated")' in listed, True)
check("a NULL binding finds the NULL row",
      m.run("!(match &crm (logs NULL $n) $n)"), [["undated"]])
check("a date binding finds the dated row",
      m.run('!(match &crm (logs "2026-08-13" $n) $n)'), [["shipped"]])
provider.clear()
check("clear empties, schema stays",
      m.run("!(collapse (match &crm (logs $d $n) x))"), [[expr()]])

m.unregister_space("&crm")
done("duckdb_space")
```

Continue with [Python-backed spaces](../guide/spaces#python-backed-spaces) for normal provider use and joins, and [`SpaceProvider`](../reference/petta-foreign#spaceprovider) for the interface another backend implements.
