<!--
Purpose: explain callback and queued subscriptions over a Space handle.
Guarantees: the executable example creates its handle through space().
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Standing queries

`m.subscribe(pattern, callback)` watches one space for matching writes. With a callback, delivery runs synchronously inside the add or removal that caused it. Without a callback, events wait in a queue until `drain()` reads them.

The space is the mailbox and the subscription is the standing query. Writes from Python and writes performed by MeTTa programs pass through the same delivery path.

The actors example starts a ping-pong exchange with one added atom, then demonstrates queued delivery and cancellation:

```python
from petta import S, V, space

m = space()

# The ping actor: every (ping $n) mails back (pong $n), until three.
transcript = []


def ping_actor(event):
    n = event.bindings["n"].value
    transcript.append(("ping", n))
    if n < 3:
        m.add(S.pong(n))


def pong_actor(event):
    n = event.bindings["n"].value
    transcript.append(("pong", n))
    m.add(S.ping(n + 1))


ping = m.subscribe(S.ping(V.n), ping_actor)
pong = m.subscribe(S.pong(V.n), pong_actor)

# One message starts the exchange; delivery cascades inside the writes.
m.add(S.ping(1))
check("the exchange ran itself", transcript,
      [("ping", 1), ("pong", 1), ("ping", 2), ("pong", 2), ("ping", 3)])

# A MeTTa program's own add-atom delivers too: the funnel is the engine's.
seen = []
audit = m.subscribe(S.audit(V.what), lambda e: seen.append(str(e.bindings["what"])))
m.run("!(add-atom (context-space) (audit from-metta))")
check("engine-side writes deliver", seen, ["from-metta"])

# Queue mode is the mailbox reading: events wait until drained.
inbox = m.subscribe(S.letter(V.body), on="add")
m.add(S.letter(S.first), S.letter(S.second))
check("the mailbox drains in order",
      [str(e.bindings["body"]) for e in inbox.drain()], ["first", "second"])
check("and empties", inbox.drain(), [])

for subscription in (ping, pong, audit, inbox):
    subscription.cancel()
m.add(S.ping(99))
check("no delivery after cancel", len(transcript), 5)
```

An `Event` records the action, space, matched atom, and bindings. A subscription can watch adds, removals, or both.

A subscription is a context manager, so `with m.subscribe(pattern) as sub:` cancels on exit, exceptions included. And the queue mode has a blocking reading: `sub.events()` streams incoming events to a consumer thread that sleeps on a condition variable between arrivals instead of polling `drain()`:

```python
with m.subscribe(S.order(V.id)) as sub:
    for event in sub.events(timeout=5.0):   # ends after 5 quiet seconds
        handle(event)
# leaving the block cancels, which also ends an events() stream
```

The stream ends when the subscription cancels, queued leftovers delivered first, or when `timeout` seconds pass with nothing arriving; with no timeout it blocks until cancellation. A callback subscription refuses `events()`, because it delivers through its callback and has no queue. Bare `iter(sub)` is deliberately absent: iteration that blocks should say so by name. On the async surface the stream IS the delivery, `async for event in am.subscribe(...)`.

See [`petta.subscribe`](../reference/petta-subscribe).
