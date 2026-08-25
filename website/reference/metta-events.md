# `metta.events`

Source: `bindings/python/metta/events.py`.

> Purpose: the public event stream.
>
> Every committed space write is an event, the stream of `(action, space, atom)`
> is a first-class object, and a FOLD over it is the one way to consume it: a step
> function `(state, event) -> state` registered for a space and a pattern,
> with the accumulated state readable and takeable.
>
> The three models this library ships are that fold with three steps.
> `subscribe` folds by delivering, to a callback or to a queue; `bridge`
> folds by writing the instantiated template into another space; a declared
> `(on ...)` reaction folds by evaluating its operation, engine-side. Before
> this the tap was `subscribe._dispatch`, private and "called from the
> shim", so a third party could not have written `subscribe()` from the
> public surface, and the three siblings were one unnamed family.
>
> Naming the stream and making the tap public is the shape two production
> systems already ship. Datomic publishes exactly this: "any peer process in
> the system can request a transaction report queue of every transaction
> against a particular database", and its stated value is that this "makes
> it possible for any peer to observe and respond to transactions ... without
> any coordination with database writes", with reactive query notification
> left as something you "implement in user space" over it [source: Datomic
> blog, The Transaction Report Queue, 11 September 2013; Datomic
> Developers forum, "you could use the tx-report-queue or poll the
> transaction log to implement one in user space"]. And a fold is the right
> consumer because a stream and the state it accumulates are two views of one
> thing: Kafka's stream-table duality states that "a stream can be considered
> a changelog of a table, where each data record in the stream captures a
> state change of the table", and that "aggregating data records in a stream
> ... will return a table" [source: Apache Kafka, Streams Core Concepts].
> Guarantees:
>   - unscoped writes publish immediately; transaction and atomic scopes publish
>     their ordered diff after commit, while rollback, speculation, and world
>     evaluation publish nothing [tested:
>     test_events_publish_only_after_transaction_commit,
>     test_atomic_scope_commits_or_discards_one_event_segment,
>     test_rollback_and_outer_rollback_discard_every_buffered_event,
>     test_speculative_execution_discards_its_event_segment; commit=WORKTREE]
>   - event attributes project named pattern bindings and unknown names fail as
>     attributes [tested: test_take_peek_and_watch_retire_the_thread_linda_fn_strings;
>     commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
>   - registry snapshots, fold state and delivery accounting are locked for
>     free-threaded Python [tested test_subscription_queue_is_thread_safe,
>     test_subscription_cancel_is_thread_safe]
>   - dispatch answers the folds on a space in registration order, cancels
>     and re-registrations included, through the discrimination tree in
>     metta.structures rather than one unify per fold [measured 2026-08-19,
>     1000 standing queries on one space and 200 writes, controlled
>     instructions:u min of 3: 4012009981 scanning against 48243634 indexed,
>     83.2x, both delivering 200 of 200] [tested
>     test_dispatch_through_the_index_delivers_the_same_subscribers_in_the_same_order]
>   - cancel waits for steps already in flight and a stale dispatch snapshot
>     cannot deliver after cancellation [tested
>     test_subscription_cancel_waits_for_inflight_delivery,
>     test_stale_subscription_snapshot_cannot_deliver_after_cancel]
>   - subscribe, bridge and reaction are each expressible as a fold over this
>     surface alone, with the same answers as the shipped models [tested
>     test_subscribe_bridge_and_reaction_are_expressible_over_the_public_event_stream]
> Guarded by:
>   - _FoldRegistry._lock protects fold state, the active runtime, delivery
>     counts, and engine subscription snapshots [tested
>     test_subscription_cancel_is_thread_safe]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Event`

```python
class Event:
```

> One change on the stream.
>
> What happened, where, to which atom, and with which bindings the watching
> pattern took.

## `Fold`

```python
class Fold:
```

> One consumer of the stream: a step run for every matching event.
>
> `cancel()` ends it. `state` is what the steps have accumulated so far,
> `take()` reads it out and starts again from the initial state, which is
> how a queueing consumer is written, and `wait(timeout)` is the same read
> blocked on a condition variable until a step has run.

### `Fold.cancel`

```python
def cancel(self) -> None:
```

> End the fold and wait for steps other threads are still running.

### `Fold.take`

```python
def take(self) -> Any:
```

> The accumulated state, at once, reset to the initial one.

### `Fold.wait`

```python
def wait(self, timeout: float | None = None) -> Any:
```

> The accumulated state, blocked until a step has run.
>
> Sleeps on a condition variable rather than polling, and returns early
> when the fold cancels or, with a timeout, when the deadline passes.
> Something that arrived before the call is not waited for.

## `EventStream`

```python
class EventStream:
```

> The engine's `(action, space, atom)` stream, as an object.
>
>     events = m.events()
>     seen = events.fold(
>         lambda held, event: [*held, event.atom],
>         space=m.name, pattern=S.order(V.id), state=[],
>     )
>     m.add(S.order(1))
>     seen.take()            # [(order 1)], and the fold starts again
>
> One operation, `fold`, plus `publish` for a provider whose own channel
> carries changes this process did not make. Everything else this library
> offers over events is a fold with a different step, so a third party's
> consumer and a shipped one are the same kind of thing.

### `EventStream.fold`

```python
def fold(
    self,
    step: Step,
    *,
    space: str,
    pattern: Any,
    on: str = 'add',
    state: Any = STATELESS,
) -> Fold:
```

> Run `step(state, event)` for every matching change to `space`.
>
> `pattern` selects the events by unification, and its bindings ride on
> each event. `on` is "add", "remove" or "both". `state` is where the
> fold starts and what `take()` resets it to; the step's answer is the
> next state. Leave `state` alone and the fold accumulates nothing,
> which is what a consumer that only reacts wants and what costs it no
> serialisation. An unscoped write runs steps synchronously before it
> returns. A transactional write runs them synchronously after the
> complete commit, so every step reads committed state; rollback,
> speculation, and world evaluation run none. A step may write back and
> an infinite add-triggers-add loop is the author's own.

### `EventStream.folds`

```python
def folds(self, space: str) -> tuple[Fold, ...]:
```

> Every live fold on one space, in registration order.

### `EventStream.publish`

```python
def publish(self, action: str, space: str, atom: Any) -> None:
```

> Announce a change this process did not write.
>
> The engine's own write hooks publish every write it makes. A provider
> whose store also changes elsewhere and that has a channel saying so,
> Redis pub/sub or PostgreSQL LISTEN/NOTIFY, announces those changes
> here, which is what its `(events ...)` declaration promised.

## `stream`

```python
def stream(runtime: Any) -> EventStream:
```

> The event stream of one engine; `MeTTa.events()` is the usual door.

## `publish`

```python
def publish(action: str, space: str, wire: list) -> bool:
```

> The engine's write hooks, arriving as events.
>
> Public because the stream is: a host binding for another language taps in
> here exactly as the Python shim does.

## `atom_added`

```python
def atom_added(space: str, wire: list) -> bool:
```

> The shim's added-atom hook.

## `atom_removed`

```python
def atom_removed(space: str, wire: list) -> bool:
```

> The shim's removed-atom hook.
