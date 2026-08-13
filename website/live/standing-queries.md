# Standing queries

`m.subscribe(pattern, callback)` watches one space for matching writes. With a callback, delivery runs synchronously inside the add or removal that caused it. Without a callback, events wait in a queue until `drain()` reads them.

The space is the mailbox and the subscription is the standing query. Writes from Python and writes performed by MeTTa programs pass through the same delivery path.

The actors example starts a ping-pong exchange with one added atom, then demonstrates queued delivery and cancellation:

```python
from _common import check, done

from petta import MeTTa, S, V

m = MeTTa().fresh_space()

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
done("12_standing_queries")
```

An `Event` records the action, space, matched atom, and bindings. A subscription can watch adds, removals, or both. See [`petta.subscribe`](../reference/petta-subscribe).
