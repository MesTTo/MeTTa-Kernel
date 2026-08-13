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

## Memoize a function

Tabling is the engine's own memoization: declare a function tabled, and every distinct call computes once, with later calls of the same shape answering from the table. After `!(import! &self (library lib_tabling))`, the declaration is `!(tabled (spin-down $n))`, made after the function is defined, because instrumenting a name that does not exist yet is refused by name and arity instead of silently tabling nothing.

```python
    with m.stats() as first:
        assert m.run("!(spin-down 200000)") == [[S.done]]
    with m.stats() as second:
        assert m.run("!(spin-down 200000)") == [[S.done]]
    # The second call answers from the table: orders of magnitude fewer
    # engine steps than the first recursion.
    assert second.inferences < first.inferences / 10
```

Tabling changes what a function means, so the admission burden is yours: it is sound for a pure function whose equations and read spaces stay put while its tables live, whose callers never observe answer order or duplicates, and whose call modes stay bounded. Hyphenated and uppercase names work, repeated declarations are cumulative and idempotent, and a named space's functions instrument their own module. `(untabled ...)` removes the instrumentation, `(table-clear ...)` abolishes one function's cached answers and keeps the declaration, `(table-clear-all)` abolishes every table, and `s.table_bytes` from `m.stats()` watches the memory.

Every live declaration is also a fact: `(tabled space name arity)` in the `&petta` reflection space, input arity, added on declare and removed on undeclare, so a program can ask what is memoized right now:

```python
    reflection = MeTTa(REFLECTION_SPACE)
    m.run("(= (reflected-fn $n) (+ $n 1))")
    assert m.run("!(tabled (reflected-fn $n))") == [[True]]
    pattern = S.tabled(S[m.space_name], S["reflected-fn"], V.a)
    assert [row.a for row in reflection.query(pattern)] == [1]
```

Tabling state dies with the space life. A dropped or cleared space takes its declarations, its tables, and its `&petta` records with it, so a pooled name's next life cannot be answered by a dead life's cache; the suite pins this by redefining a function in a reused space and requiring the new answer.

## The third truth value

Tabled negation gives this engine Well Founded Semantics: an answer can be true, false, or genuinely undefined, a loop through `tnot`. Before this surface, an undefined answer reached Python as an ordinary-looking unbound variable, which is silently wrong. Now every `eval` answer carries its truth: definite answers stay plain atoms, and an undefined one arrives as an `Undefined` holding the answer, the delay condition that makes it undefined, and, with `residuals=True`, the residual program, the clauses of the loop itself.

```python
def test_undefined_answers_cross_as_undefined(m, wfs_program):
    answers = m.eval("(translatePredicate (wfs_loop))")
    assert len(answers) == 1
    answer = answers[0]
    assert isinstance(answer, Undefined)
    assert "wfs_loop" in answer.why
```

`Undefined` refuses truthiness on purpose, so code cannot branch on it by accident, and `value()` refuses it outright: a caller asking for THE value has asserted a definite one exists. The carrier is the engine's own `call_delays`, applied per answer inside the enumeration, which is the only place the condition exists. It is unconditional because any "only when tabling" gate would answer silently wrong exactly once, on the first tabled call; the measured cost on the trivial-eval crossing is five to ten percent, amortized below that on real evaluations. `run()` mirrors the CLI and stays two-valued; evaluate through `eval()` when undefined truth matters.

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

## Strings and regular expressions

Structural match reads terms; strings stay opaque to it. `lib_regex` opens them with the engine's own PCRE2: `(re-match pat text)` answers a boolean and therefore guards queries, `(re-find pat text)` answers every match nondeterministically, `(re-captures pat text)` answers the first match's groups as `((key value) ...)` pairs with a `_I` name suffix answering an integer, and `(re-split ...)`, `(re-replace ...)`, `(re-replace-all ...)` do what they say. Flags ride the pattern inline, PCRE2's `(?i)` style, and a MeTTa string reads a doubled backslash as one, so `"\\d"` spells the digit class, Python's own non-raw convention.

```python
def test_regex_guards_queries(rx, metta):
    with metta.fresh_space() as m:
        m.add(S.person(S.Ada), S.person(S.alan), S.person(S.Alice))
        rows = m.query(S.person(V.name), where='(re-match "^A" $name)')
        assert [row.name for row in rows] == [S.Ada, S.Alice]
```

The guard is also an optimization: patterns compile once into the engine's cache and every candidate row is tested in C, never crossing to Python. Against an equivalent Python-operation guard on a 2000-row scan, the regex guard measured 2.3x (317 against 138 queries per second, identical rows answered).

## Content hashes

`lib_crypto` opens the engine's own OpenSSL to MeTTa programs: `(crypto-hash sha256 "text")` answers the lowercase hex digest under any `library(crypto)` algorithm name, an unknown name refuses loudly, and `(crypto-random-hex 16)` answers thirty-two hex characters of cryptographically secure randomness for nonces and fresh ids. Hashes make content keys, so a fact can carry the identity of its own payload, and the digests agree with every other tool's:

```python
    (digest,) = cr.eval('(crypto-hash sha256 "hello")')
    assert digest == hashlib.sha256(b"hello").hexdigest()
```

The whole-space version of the same idea is [`digest()`](./spaces), one hash naming everything a space stores.

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

## Trace a reduction

Where the profiler says where time went, `m.trace(source)` says what happened: it runs source with every compiled MeTTa function wrapped by the engine's own predicate wrapping, and answers one call event per reduction entered, depth-nested through the call tree, and one exit event per answer. A reduction that fails is a call with no exit, which is precisely what failing looks like:

```python
    m.run("(= (tr-fact $n) (if (== $n 0) 1 (* $n (tr-fact (- $n 1)))))")
    events = m.trace("!(tr-fact 3)")
    calls = [e for e in events if e.kind == "call"]
    exits = [e for e in events if e.kind == "exit"]
    assert [str(c.term) for c in calls] == [
        "(tr-fact 3)", "(tr-fact 2)", "(tr-fact 1)", "(tr-fact 0)",
    ]
    assert [c.depth for c in calls] == [0, 1, 2, 3]
```

Builtins inline and stay invisible, so the trace is about your program, not the engine. The source executes for real, writes included, exactly like a `run`; the wrap exists only while tracing, so untraced calls pay nothing. Printing an event indents it by depth, which makes `for e in m.trace(...): print(e)` a readable story of the evaluation.

## Lint a space

MeTTa fails open: a call to a misspelled function stays an unreduced expression, a call with the wrong argument count matches no equation, and a declared type nothing defines promises a function that cannot answer. `m.lint()` walks a space's declarations and equations against the engine's own registries and answers findings, each naming its kind, its subject, and the atom it stands on:

```python
    m.run("(: ghost-fn (-> Number Number))")
    findings = m.lint()
    assert _kinds(findings) == ["declared-but-undefined"]
    assert findings[0].subject == "ghost-fn"
```

The kinds: `declared-but-undefined`, `arrow-arity-mismatch` (the arrow's input count against the equations'), `arity-mismatch` (a call with an argument count no equation takes), `unbound-variable` (a body variable the head never bound, exempting equations with their own binding forms), `duplicate-equation` (the same equation stored twice, answering every call twice), and `possibly-undefined-reference`, which says in its own text that it is a heuristic, because an expression head that is no known function may be data on purpose. A healthy space answers an empty list.

`add_table(head, source)` reads a Polars frame, a pandas frame, a mapping of columns, or any iterable of rows into facts shaped as `(head v1 .. vn)`. In the other direction, `rows.table()` returns a dict of plain columns accepted by DataFrame constructors, and `rows.to_df()` / `rows.to_pl()` build the pandas or polars frame directly, DuckDB's conversion naming. `rows.build(column, Class)` rebuilds translated objects from a result column. In a notebook, rows render as a table on their own.

Use `derivation(atom)` to obtain proof trees for an answer. Use `why(pattern)` to explain an empty match. The complete runtime surface is in [`petta.space`](../reference/petta-space), and result containers are in [`petta.results`](../reference/petta-results).
