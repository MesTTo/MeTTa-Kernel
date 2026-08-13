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

Control signals hold everywhere, by engine design: a bound, a Ctrl-C, or an `interrupt()` cannot be eaten by the evaluation it is stopping, not even by a program's own `(catch ...)`. That is the same reasoning that puts `KeyboardInterrupt` outside `Exception` in Python.

## Streaming answers

`query()` computes and decodes every answer before you see the first one. `stream()` is the same conjunction and guard, pulled: the join's state stays alive inside an SWI engine between pulls, each pull is one ordinary call, and unrelated engine work interleaves freely.

```python
    m.add_table("edge", [(i, i + 1) for i in range(500)])
    with m.stream(S.edge(V.a, V.b), S.edge(V.b, V.c)) as rows:
        first = next(rows)
        assert (first.a, first.b, first.c) == (0, 1, 2)
        # Unrelated engine work interleaves while the cursor stays open,
        # which a raw janus cursor forbids.
        assert m.value("(+ 1 2)") == 3
        second = next(rows)
        assert (second.a, second.b, second.c) == (1, 2, 3)
```

Break out of the loop and nothing further is even joined. Exhaustion closes the cursor on its own, leaving the with-block closes it early, and a dropped cursor is reaped by its finalizer. On a stream, `timeout` bounds each pull's wall time while `inferences` is one budget for the cursor's whole engine work, because an engine's inferences are its own. The cursor enumerates under the engine's logical update view, so writes made after the first pull are not seen by it.

## Atomic and what-if runs

The engine has transactions, and a program can already use the inline `(transaction ...)` form for a scope inside itself. `atomic=True` lifts that over a whole `run`: every write, facts and equations alike, commits whole or rolls back whole when a directive throws.

```python
    with pytest.raises(EngineError):
        m.run("(kept fact) !(/ 1 0)", atomic=True)
    assert expr(S.kept, S.fact) not in m  # the fact rolled back with the throw
    m.run("(kept fact) !(+ 1 1)", atomic=True)
    assert expr(S.kept, S.fact) in m  # and commits whole on success
```

`speculative=True` is the what-if twin: the run executes against a frozen view, the answers return, and every write is discarded.

```python
    groups = m.run("(ghost fact) !(+ 2 2)", speculative=True)
    assert groups[-1] == [4]
    assert expr(S.ghost, S.fact) not in m
```

Both cover engine state. A Python operation's side effects, and subscription callbacks that already fired, stay where they happened; that is what rolling back a database can honestly mean.

## Profile a run

`m.profile(source)` runs source under the engine's statistical profiler and answers the groups beside a profile: sample counters, and one row per predicate with its calls, redos, and ticks, self-ticks first.

```python
    m.run("(= (prof-spin $n) (if (== $n 0) done (prof-spin (- $n 1))))")
    groups, prof = m.profile("!(prof-spin 10000000)")
    assert groups == [[S.done]]
    assert prof.samples > 0 and prof.ticks > 0
```

`prof.top(5)` is where the time went. The sampler is statistical, so profile something that runs; and profiling changes execution, so it is a debugging surface, not a mode to leave on.

`add_table(head, source)` reads a Polars frame, a pandas frame, a mapping of columns, or any iterable of rows into facts shaped as `(head v1 .. vn)`. In the other direction, `rows.table()` returns a dict of plain columns accepted by DataFrame constructors, and `rows.to_df()` / `rows.to_pl()` build the pandas or polars frame directly, DuckDB's conversion naming. `rows.build(column, Class)` rebuilds translated objects from a result column. In a notebook, rows render as a table on their own.

Use `derivation(atom)` to obtain proof trees for an answer. Use `why(pattern)` to explain an empty match. The complete runtime surface is in [`petta.space`](../reference/petta-space), and result containers are in [`petta.results`](../reference/petta-results).
