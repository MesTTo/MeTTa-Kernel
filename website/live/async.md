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
