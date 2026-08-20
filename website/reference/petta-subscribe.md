# `petta.subscribe`

Source: `bindings/python/petta/subscribe.py`.

> Purpose: standing queries. A subscription watches one space for atoms
> unifying with a pattern and reacts to every add or removal: with a callback,
> synchronously, inside the write that caused it; without one, by queuing
> events for drain(). This is the actors-and-pub-sub reading of a space: the
> mailbox is the space, the subscription is the standing query that maintains
> itself, and the engine's own write hooks deliver.
>
> Every write consults the subscriptions on its space, so the dispatch is on
> the write path and its cost is the write's. It goes through the
> discrimination tree in petta.structures rather than one unify per
> subscription [measured 2026-08-19, 1000 standing queries on one space and
> 200 writes, controlled instructions:u min of 3: 4012009981 scanning against
> 48243634 indexed, 83.2x, both delivering 200 of 200].
> Guarantees:
>   - registry snapshots and queued event mutation are locked for
>     free-threaded Python [tested test_subscription_queue_is_thread_safe,
>     test_subscription_cancel_is_thread_safe]
>   - subscription publication and cancellation update registry state, engine
>     write guards, and reflection facts together or restore the prior state
>     [tested test_subscription_lifecycle_rolls_back_failed_boundaries]
>   - cancel waits for callbacks already in flight and stale dispatch snapshots
>     cannot deliver after cancellation [tested
>     test_subscription_cancel_waits_for_inflight_delivery,
>     test_stale_subscription_snapshot_cannot_deliver_after_cancel]
>   - identical subscriptions share one reflection descriptor until the last
>     subscription cancels [tested
>     test_identical_subscriptions_share_one_reflection_fact]
>   - a watcher that raises reaches the writer as SubscriberError, naming the
>     subscription and saying the write stands, where a refused write does
>     not [measured 2026-08-19: both arrived as EngineError with the same
>     "Python '<Type>': <text>" message template, so a caller could only tell
>     them apart by reading the sentence] [tested
>     test_a_watcher_failure_is_distinguishable_from_a_failed_write]
>   - dispatch answers the same subscriptions in the same order the linear
>     scan did, cancels and re-subscriptions included [measured 2026-08-19:
>     routed through the tree before its entry ids were made monotonic, every
>     subscriber still fired and two swapped places] [tested
>     test_dispatch_through_the_index_delivers_the_same_subscribers_in_the_same_order]
> Guarded by:
>   - _SubscriptionRegistry._lock protects subscription state, the active
>     runtime, delivery counts, and engine subscription snapshots [tested
>     test_subscription_cancel_is_thread_safe]
>   - _TRANSACTION_LOCK serializes cross-boundary subscription lifecycle
>     changes [tested test_subscription_lifecycle_rolls_back_failed_boundaries]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Event`

```python
class Event:
```

> One delivery: what happened, where, to which atom, with which
> bindings the pattern took.

## `Subscription`

```python
class Subscription:
```

> One standing query; cancel() ends it. With no callback, events
> queue and drain() empties the queue.

### `Subscription.drain`

```python
def drain(self) -> list[Event]:
```

> Every queued event, oldest first; the queue empties.

### `Subscription.events`

```python
def events(self, timeout: float | None = None):
```

> Incoming events as a blocking stream: the no-callback queue
> mode consumed without polling, so a consumer thread writes
> `for event in sub.events(): ...` and sleeps on a condition
> variable between arrivals. The stream ends when the subscription
> cancels, queued leftovers delivered first, or when `timeout`
> seconds pass with nothing arriving. A callback subscription
> delivers through its callback and has no queue, so it refuses.
> Bare `iter(sub)` is deliberately absent: iteration that blocks
> should say so by name.

### `Subscription.cancel`

```python
def cancel(self) -> None:
```

No docstring is defined.

## `subscribe`

```python
def subscribe(
    runtime,
    space: str,
    pattern: Atom,
    callback: Callable[[Event], None] | None = None,
    on: str = 'add',
    *,
    queue_max: int = SUBSCRIPTION_QUEUE_MAX,
) -> Subscription:
```

No docstring is defined.

## `atom_added`

```python
def atom_added(space: str, wire: list) -> bool:
```

No docstring is defined.

## `atom_removed`

```python
def atom_removed(space: str, wire: list) -> bool:
```

No docstring is defined.

## `bridge`

```python
def bridge(source, pattern, target, template=None, on: str = 'add') -> Subscription:
```

> A bridge rule between spaces, the multi-context-systems reading:
> when an atom unifying with pattern arrives in source, the template's
> instantiation under the match's bindings lands in target, and with
> on="both" a removal in source removes the instantiation from target,
> the mirrored rule.
>
>     rule = petta.bridge(src, S.alarm(V.zone), dst, S.notify(V.zone))
>     src.add(S.alarm(S.kitchen))        # dst now holds (notify kitchen)
>     rule.cancel()
>
> template defaults to the pattern itself. The rule is a standing
> query, delivered inside the write that triggered it; target needs
> only add and remove, so a remote.attach()ed space bridges across
> engines identically.
