# `metta.subscribe`

Source: `bindings/python/metta/subscribe.py`.

> Purpose: the two delivery models the library ships over the public event
> stream. A subscription is the fold that DELIVERS, to a callback
> synchronously inside the write or to a queue drain() empties; a bridge is
> the fold that WRITES, landing a template's instantiation in another space.
> Both are `metta.events.EventStream.fold` with a different step and nothing
> else, which is what makes "a third party could have written these" a fact
> rather than a claim.
>
> This is the actors-and-pub-sub reading of a space: the mailbox is the
> space, the subscription is the standing query that maintains itself, and
> the engine's own write hooks deliver. Every write consults the folds on its
> space, so the dispatch is on the write path and its cost is the write's;
> metta.events owns that dispatch and its discrimination tree.
> Guarantees:
>   - subscription publication and cancellation update registry state, engine
>     write guards, and reflection facts together or restore the prior state
>     [tested test_subscription_lifecycle_rolls_back_failed_boundaries]
>   - identical subscriptions share one reflection descriptor until the last
>     subscription cancels [tested
>     test_identical_subscriptions_share_one_reflection_fact]
>   - a watcher that raises reaches the writer as SubscriberError, naming the
>     subscription and saying the write stands, where a refused write does
>     not [measured 2026-08-19: both arrived as EngineError with the same
>     "Python '&lt;Type>': &lt;text>" message template, so a caller could only tell
>     them apart by reading the sentence] [tested
>     test_a_watcher_failure_is_distinguishable_from_a_failed_write]
>   - a queue nobody drains refuses rather than dropping the oldest event
>     [tested test_the_subscription_queue_is_bounded_and_load_takes_a_budget]
> Guarded by:
>   - metta.events' fold registry lock protects queue state and the engine
>     subscription snapshot [tested test_subscription_cancel_is_thread_safe]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Subscription`

```python
class Subscription(Fold):
```

> One standing query; cancel() ends it.
>
> The delivering fold: its step calls the callback, or appends to the
> fold's own state, which is the queue drain() empties.

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

> End the standing query and withdraw its reflection atom.

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
>     rule = bridge(src, S.alarm(V.zone), dst, S.notify(V.zone))
>     src.add(S.alarm(S.kitchen))        # dst now holds (notify kitchen)
>     rule.cancel()
>
> template defaults to the pattern itself. This is the WRITING fold over
> the same event stream the delivering one folds: subscribe's step calls
> your callback, this one's writes, and composing the two is all a bridge
> is. Delivery is inside the write that triggered it; target needs only
> add and remove, so a remote.attach()ed space bridges across engines
> identically.
