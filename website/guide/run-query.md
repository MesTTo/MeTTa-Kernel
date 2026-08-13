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

## Bounds, stats, and captured output

A query whose join size is unknown, or a program whose recursion depth is someone else's data, should not be able to hold your process. `timeout=` (seconds) and `inferences=` (engine steps) bound any `run`, `eval`, `value`, `query`, or `solve` call with the engine's own guards:

```python
try:
    m.run("!(spin 100000000)", timeout=0.05)
    raise AssertionError("the time bound did not fire")
except petta.TimeLimitError:
    check("a 50ms bound stops a spin that would run for minutes", True)
```

Each bound raises its own error, `TimeLimitError` or `InferenceLimitError`, both under `ResourceLimitError`. An inference bound is the deterministic twin of a timeout: the same call stops at the same step on every machine. Whatever the call completed before the stop, writes included, stands, which is what stopping a computation mid-way means everywhere. Ctrl-C reaches a running evaluation too: the runtime installs janus's heartbeat at startup, so a `KeyboardInterrupt` lands within milliseconds instead of queueing until the goal ends, at an interval measured to cost nothing.

`m.stats()` reads the engine's own counters around a with-block, and `capture=True` on `run` and `eval` returns the printed text beside the answers:

```python
m.add_table("edge", [(i, i + 1) for i in range(200)])
rows = m.query(S.edge(V.a, V.b), S.edge(V.b, V.c), timeout=30.0)
check("a generous bound changes nothing", len(rows), 199)

with m.stats() as s:
    m.query(S.edge(V.a, V.b), S.edge(V.b, V.c))
check("the stats block counts the engine steps spent", s.inferences > 100)

groups, text = m.run("!(println! (hello world)) !(+ 1 2)", capture=True)
check("captured print output", "(hello world)" in text)
check("the answers still arrive beside it", groups[1], [3])
```

After the block, `s.inferences`, `s.cputime`, `s.walltime`, `s.gc_count`, `s.gc_freed`, and `s.gc_time` carry what the block spent. The whole page is [example 17](https://github.com/trueagi-io/PeTTa/blob/main/python/examples/17_bounds_stats_capture.py).

`add_table(head, source)` reads a Polars frame, a pandas frame, a mapping of columns, or any iterable of rows into facts shaped as `(head v1 .. vn)`. In the other direction, `rows.table()` returns a dict of plain columns accepted by DataFrame constructors, and `rows.to_df()` / `rows.to_pl()` build the pandas or polars frame directly, DuckDB's conversion naming. `rows.build(column, Class)` rebuilds translated objects from a result column. In a notebook, rows render as a table on their own.

Use `derivation(atom)` to obtain proof trees for an answer. Use `why(pattern)` to explain an empty match. The complete runtime surface is in [`petta.space`](../reference/petta-space), and result containers are in [`petta.results`](../reference/petta-results).
