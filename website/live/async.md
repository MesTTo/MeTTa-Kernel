# The loop stays live

An event loop and a reasoning engine want the same thread, and the engine usually wins: one long `m.eval` inside a web handler and every other request waits. `petta.aio` resolves this the way aiosqlite resolves it for SQLite: one dedicated worker thread owns the engine calls, requests cross through a queue, and results come back through the loop, so awaiting the engine blocks one coroutine instead of the whole process.

```python
    async def go():
        async with aio.AsyncMeTTa(metta=m) as am:
            await am.add(S.edge(1, 2), S.edge(2, 3))
            rows = await am.query(S.edge(V.a, V.b), S.edge(V.b, V.c))
            groups = await am.run("!(+ 1 2)")
            value = await am.value("(+ 2 3)")
            count = await am.count()
            return rows, groups, value, count
```

`petta.aio.connect()` answers a started connection, aiosqlite's naming; `async with` closes it on the way out. Every mirrored method takes what its synchronous twin takes, bounds and capture included, and errors cross with their types intact:

```python
            with pytest.raises(TimeLimitError):
                # The guard fires on the attached worker thread, so the
                # alarm mechanism is proven off the main thread too.
                await am.run("!(aio-spin-b 100000000)", timeout=0.05)
            with pytest.raises(MettaSyntaxError):
                await am.run("!(unclosed")
            groups, text = await am.run("!(println! crossed)", capture=True)
```

Anything not mirrored is one `call` away: `await am.call(lambda m: m.derivation(atom))` runs on the engine's thread and answers here. `await am.space(name)` opens another space through the same thread; the connection owns the thread, spaces borrow it.

Be clear about what this buys. The engine is one per process and calls are serialized, so `petta.aio` does not evaluate two things at once; it keeps every other coroutine running while one evaluation works. The suite pins exactly that: a heartbeat task keeps ticking while the engine spins through a three-million-step recursion. The worker holds an attached Prolog engine (`janus.attach_engine()`), the same pattern `petta.remote.serve()` runs, so the fast calling convention holds off the main thread. When the work should happen in another process entirely, that is what [contexts and remotes](./contexts) are for; the two compose, an `AsyncMeTTa` in front of an engine that `attach`es a remote one behind.

The complete surface is in [`petta.aio`](../reference/petta-aio).


## A live loop is not a second core

`petta.aio` keeps the loop responsive; it does not make the engine faster. Every call from Python takes one process-wide lock around the engine, so two `AsyncMeTTa` connections, each with its own worker thread and its own attached Prolog engine, still evaluate one at a time. Measured on a four-branch workload, a second connection buys **1.01x**.

That is the design and the module says so: "calls are serialized, and the win is a live event loop, never parallel evaluation."

## `parallel` is the second core

The engine has its own concurrency, and it runs below that lock. `hyperpose` is the parallel twin of `superpose`: same branches, one SWI thread each. `MeTTa.parallel` is its Python spelling.

```python
    m.run("(= (sq $x) (* $x $x))")
    m.parallel(S.sq(1), S.sq(2), S.sq(3))     # 1, 4 and 9, in any order
```

Independent branches cost about one branch rather than their sum:

| branches | `superpose`, sequential | `parallel` |
|---|---|---|
| 2 | 0.586s | 0.303s |
| 4 | 1.172s | 0.305s |

Four cost the same wall clock as one. Reach for this when the work is genuinely independent: scoring a list of candidates, running several analyses over the same space, fanning a query out across unrelated heads.

Three things to know before using it.

**Answers arrive in completion order, not argument order.** The branches race, so `(collapse (superpose ((f 1) (f 2) (f 3))))` answers `(10 20 30)` while the `hyperpose` twin answers `(30 20 10)`. Compare sets, and evaluate a `superpose` instead when order carries meaning.

**There is no `inferences=` bound.** The engine's inference limit counts the calling thread, and every branch runs in a worker, so a limit of 50,000 will not stop two branches spending six million. `timeout=` does bound the call and is the one to use. An unenforceable bound is worse than an absent one, so the parameter is not offered.

**Give each engine its own space.** Two connections share `&self`, and defining an equation is not idempotent: the same recursive equation defined twice answers 2^n times, which reads as a hang rather than an error. Use `fresh_space()` per worker.

The other two engine-level forms are available from MeTTa source: `(with_mutex <name> <body>)` for a named lock, and `(transaction <body>)` for an all-or-nothing write, which `m.run(source, atomic=True)` also wraps a whole source string in.
