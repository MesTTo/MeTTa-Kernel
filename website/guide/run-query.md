# Run and query

Use `run` for MeTTa source, `eval` for a term already built in Python, and `query` for structural matches against a space. Variables shared by several query patterns form joins. Rows expose the query variable names as attributes.

Queries also accept guards, answer bounds, temporary assumptions, and prepared shapes:

```python
m.add(S.Age(S.Tom, 62), S.Age(S.Bob, 40))
m.query(S.Age(V.p, V.n), where=(V.n >= 60) & (V.n <= 70))
# Rows[p, n]([Row(p=Sym('Tom'), n=Gnd(62))])

with m.assuming(S.Parent(S.Ann, S.Zoe)):
    m.query(S.Parent(S.Ann, V.c))    # Rows[c]([Row(c=Sym('Zoe'))])

grand = m.prepare(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
grand.solve()
# Rows[x, y, z]([Row(x=Sym('Tom'), y=Sym('Bob'), z=Sym('Ann'))])
```

`where=` is evaluated by the engine for each match. `limit=` stops the engine at the requested count. `assuming(...)` adds facts only for the `with` block. `prepare(...)` fixes the query shape once, and `solve(given=...)` can add facts for one solve without leaving them behind.

`add_table(head, source)` reads a Polars frame, a pandas frame, a mapping of columns, or any iterable of rows into facts shaped as `(head v1 .. vn)`. In the other direction, `rows.table()` returns a dict of plain columns accepted by DataFrame constructors. `rows.build(column, Class)` rebuilds translated objects from a result column.

Use `derivation(atom)` to obtain proof trees for an answer. Use `why(pattern)` to explain an empty match. The complete runtime surface is in [`petta.space`](../reference/petta-space), and result containers are in [`petta.results`](../reference/petta-results).
