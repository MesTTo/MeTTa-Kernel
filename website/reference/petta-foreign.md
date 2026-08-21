# `petta.foreign`

Source: `bindings/python/petta/foreign.py`.

> Purpose: spaces implemented in Python. A SpaceProvider answers match, add,
> remove and enumeration for a named space whose atoms live wherever the
> provider keeps them: a SQL table, a dataframe, a dict, a service. The engine
> unifies patterns against what the provider yields, so a provider may
> over-approximate its filtering and stay sound; pushing bound parts of the
> pattern down into the backend is the performance lever, never a correctness
> requirement.
> Guarantees:
>   - capabilities derive from implemented narrow protocols and unknown
>     operations are refused [tested test_capabilities_follow_implemented_methods]
>   - subscribability is not derived: a provider declares what its change
>     events promise through delivers(), registration publishes that as the
>     space's (events ...) row, and one that declares nothing refuses a
>     subscription naming the missing capability [tested
>     test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses]
>   - providers may decline one concrete request through should_run before its
>     operation executes [tested test_provider_can_decline_one_request]
>   - provider registration changes Python state only after the engine accepts
>     the same change [tested test_provider_registration_is_transactional]
>   - a provider's own refusal sentence reaches the caller, and "implements it
>     and declines it" reads differently from "does not have it" [tested
>     test_a_provider_states_its_own_refusal,
>     test_declining_and_not_implementing_read_differently]
>   - a declined capability is checked where it is USED, so match's fall-through
>     to enumeration consults enumerate [tested
>     test_a_declined_enumerate_is_not_reached_through_match]
>   - a single-pattern bounded query tells a provider whose match takes a limit
>     keyword how many answers the caller keeps, never sends it across a join,
>     and bounds the answers itself whatever the provider does [tested
>     2026-08-16: test_a_bound_reaches_a_provider_that_takes_one,
>     test_a_bound_is_not_pushed_past_a_join,
>     test_a_provider_ignoring_the_bound_is_still_bounded_by_the_engine]
>   - the caller's bound reaches a provider that claimed its filtering exact
>     for that pattern and is withheld from one that claimed nothing, so a
>     provider cannot truncate to a number it never promised it could use, and
>     a false claim is caught by check_space_provider rather than by an answer
>     going missing [tested test_a_bound_is_withheld_from_a_provider_that_claimed_nothing,
>     test_a_bound_reaches_a_provider_that_takes_one,
>     test_a_false_exact_claim_is_caught]
> Guarded by:
>   - _PROVIDER_LOCK serializes library registration and provider lookups
>     [tested test_provider_registration_is_transactional]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `Matcher`

```python
class Matcher(Protocol):
```

No docstring is defined.

### `Matcher.match`

```python
def match(self, pattern: Atom) -> Iterator[Any]:
```

No docstring is defined.

## `BoundedMatcher`

```python
class BoundedMatcher(Protocol):
```

> A Matcher whose match also takes the caller's bound.
>
> `limit` is how many answers the caller will keep. It is advisory, and
> that is what makes it sound: a provider may over-approximate, so N
> candidates are not N answers, and truncating at N without knowing which
> candidates unify would yield fewer answers than exist. Honour it only
> where an exact match is distinguishable from a candidate; ignoring it is
> always correct, because the engine bounds the answers itself.
>
> Deliberately not runtime_checkable. A Protocol's isinstance looks at
> method NAMES only, so it would answer True for every Matcher; the
> signature is what separates the two, and _match_takes_a_bound reads it.

### `BoundedMatcher.match`

```python
def match(self, pattern: Atom, *, limit: int | None = None) -> Iterator[Any]:
```

No docstring is defined.

## `CustomMatch`

```python
class CustomMatch(Protocol):
```

> A grounded value that owns its matching logic, Hyperon's CustomMatch.
>
> Any object whose class defines `match_` participates in `(unify ...)`
> the moment it appears as an operand or inside one, with no
> registration, exactly as any grounded atom. `match_(other)` receives
> the atom the value met and yields one item per binding set: a
> `Bindings` or `Answer` binding `other`'s variables, a plain atom or
> value the operand must equal, or nothing at all for no match. This is
> the same answer stream a provider's match yields, so residues and
> explicit values work; an annotation is refused, because a bare value
> has no context to declare a semiring on, and weighted matching
> belongs to a registered context. In Hyperon a space is exactly such a
> value whose match_ is query, which is why `unify` accepts spaces.

### `CustomMatch.match_`

```python
def match_(self, other: Atom) -> Iterable[Any]:
```

No docstring is defined.

## `MatchClassifier`

```python
class MatchClassifier(Protocol):
```

> A Matcher that says how good its own filtering is, for one pattern.
>
> Answer `"exact"` when every candidate you yield for this pattern unifies
> with it, so N candidates are N answers and you may truncate to a limit.
> Answer `"inexact"` otherwise, which is what a provider without this method
> is taken to mean and is always safe.
>
> Per PATTERN, not per provider, which is the part worth having: a backend
> is usually exact on equality against an indexed column and inexact on
> everything else, and one flag for the whole provider would force it to
> claim the weaker answer everywhere.
>
> This is Apache DataFusion's TableProviderFilterPushDown, whose Exact rung
> reads "Your source guarantees that no output rows will have a false value
> for this predicate", against Inexact, "Your source has the ability to
> reduce the data produced, but the output may still include rows that do
> not satisfy the predicate" [source: Apache DataFusion, Custom Table
> Providers]. Spark's DataSourceV2 draws the same line as "filters that need
> to be evaluated after scanning" against those that do not
> [source: Apache Spark 4.2.0 Java API, SupportsPushDownFilters.pushFilters,
> "Pushes down filters, and returns filters that need to be evaluated after
> scanning"].
>
> DataFusion's third rung, Unsupported, is absent here. It exists there
> because the planner decides whether to SEND a filter at all; the pattern
> is the only thing a provider is given, so there is nothing to withhold,
> and a provider that ignores it is inexact in the only sense that acts on
> anything.
>
> A wrong "exact" costs answers, so check_space_provider tests the claim
> against the provider's own output.

### `MatchClassifier.pushdown`

```python
def pushdown(self, pattern: Atom) -> str:
```

No docstring is defined.

## `Transactional`

```python
class Transactional(Protocol):
```

> A provider that participates in the engine's transactions.
>
> Declared with (writes &lt;ctx> transactional) or declare_writes: the
> engine calls begin() at the provider's first write inside the
> outermost transaction, then exactly one of commit() or rollback()
> when it finishes, alongside the engine's own database rollback, so a
> MeTTa (transaction ...) is atomic across both stores.

### `Transactional.begin`

```python
def begin(self) -> None:
```

No docstring is defined.

### `Transactional.commit`

```python
def commit(self) -> None:
```

No docstring is defined.

### `Transactional.rollback`

```python
def rollback(self) -> None:
```

No docstring is defined.

## `Enumerable`

```python
class Enumerable(Protocol):
```

No docstring is defined.

### `Enumerable.atoms`

```python
def atoms(self) -> Iterator[Any]:
```

No docstring is defined.

## `Adder`

```python
class Adder(Protocol):
```

No docstring is defined.

### `Adder.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

## `Planner`

```python
class Planner(Protocol):
```

> A whole conjunction, offered before the engine splits it.
>
> Return None to decline, which is what a provider without a join should do
> and what every provider written before this does by not implementing it.
> Otherwise return (claimed, rest, rows): the patterns you took, the ones you
> left for the engine, and the rows. `claimed` and `rest` must partition the
> conjunction, because the engine plans only what you leave and a dropped
> pattern stops constraining the query. Each row is a list of instantiated
> atoms, one per claimed pattern, in the order you claimed them.
>
> A claim is EXACT, which is the one place this seam differs from the rest of
> it. Elsewhere you may over-approximate because the engine re-unifies each
> candidate cheaply; there is no cheap re-check for a join, so a provider that
> cannot answer exactly must decline.

### `Planner.plan`

```python
def plan(self, patterns: list[Atom]) -> tuple[list[Atom], list[Atom], Iterator[Any]] | None:
```

No docstring is defined.

## `BulkAdder`

```python
class BulkAdder(Protocol):
```

> A whole batch in one crossing, for a backend that can take one.
>
> Optional. Without it a batch is one `add(atom)` per atom, which is what
> every provider written before this gets. A batch is a transport
> optimisation and never a semantic one, so the engine sends only atoms
> whose add is a store and nothing more: an equation or a type declaration
> anywhere in the list drops the whole batch to the per-atom path and never
> reaches here.

### `BulkAdder.add_many`

```python
def add_many(self, atoms: list[Atom]) -> None:
```

No docstring is defined.

## `Remover`

```python
class Remover(Protocol):
```

No docstring is defined.

### `Remover.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.

## `Clearer`

```python
class Clearer(Protocol):
```

No docstring is defined.

### `Clearer.clear`

```python
def clear(self) -> None:
```

No docstring is defined.

## `SpaceProvider`

```python
class SpaceProvider:
```

> One space backed by Python. Implement only what the backend has.
>
> match(pattern) yields candidate atoms; the pattern's variables arrive as
> Var atoms, and bound positions as ground atoms, which is what a backend
> turns into its own filter (a WHERE clause, a mask). Yielding every atom
> is always correct; yielding fewer than match is never allowed to be.
> An Enumerable provider need not implement Matcher: enumeration is the
> correct default candidate set. Missing methods are unsupported, never
> assumed present.
>
> A variable's NAME does not survive the crossing, and this is the place
> that will surprise you. `$x` arrives as `$_17902`, because a variable is
> an identity rather than a spelling and the engine renames on the way in.
> Fuzzing the round trip with 500 examples found the rename in 174 of them
> and nothing else: ground atoms are exact in both directions, and what a
> provider stores comes back to it unchanged. It is not a seam defect, the
> native path does the same, but a provider that PERSISTS atoms persists the
> renamed form, and a rule editor, a serializer or a diff built on this will
> meet it. If you need the source spelling, keep it yourself.

### `SpaceProvider.delivers`

```python
def delivers(self) -> tuple[str, str] | None:
```

> What this space's change events promise, or None for no events.
>
> `(delivery, order)` from the catalog's own words: delivery is
> "at-most-once", "at-least-once" or "per-write-exactly", and order is
> "ordered" or "unordered". Registration writes the answer into &petta
> as `(events <space> <delivery> <order>)`, so a MeTTa program reads
> the same promise the engine acts on.
>
> None is the default and it is the safe one. Whether a space can emit
> change events is a promise about the SPACE, not something the seam
> can read off the methods: a store whose every write comes through
> this engine gets per-write-exactly for free from the engine's own
> write hooks, and one whose contents also change elsewhere gets
> nothing unless it has a channel of its own. Deriving it from add and
> remove made a remote space claim events it could not deliver, and a
> watcher heard this process's own writes and missed every other one.
> Say what your channel promises, or say nothing and subscriptions are
> refused with your own words.

### `SpaceProvider.can_run`

```python
def can_run(self, capability: str, /, **request: Any) -> bool:
```

> Whether this provider implements the operation for this request.

### `SpaceProvider.should_run`

```python
def should_run(self, _capability: str, /, **_request: Any) -> bool:
```

> Policy hook: decline a supported concrete request before execution.

### `SpaceProvider.refusal`

```python
def refusal(self, _capability: str, /, **_request: Any) -> str | None:
```

> Why this provider says no, in its own words.
>
> can_run() and should_run() carry a boolean and no reason, so the
> refusal had to be built from the capability name and got it wrong:
> a provider that IMPLEMENTS add and declines it was told it "does not
> implement add", and the message saying what to do instead, which the
> provider had already written, was unreachable. Return a sentence and
> it is used verbatim; return None and the generic wording applies.

### `SpaceProvider.supports`

```python
def supports(self, capability: str, /, **request: Any) -> bool:
```

> Compatibility spelling for can_run().

## `has_provider`

```python
def has_provider(space: str) -> bool:
```

> Whether a Python provider currently owns the space.

## `require_capability`

```python
def require_capability(space: str, capability: str, operation: str, **request: Any) -> None:
```

> Refuse an operation before it creates partial state or enters Prolog.

## `register_provider`

```python
def register_provider(runtime, name: str, provider: SpaceProvider) -> None:
```

No docstring is defined.

## `unregister_provider`

```python
def unregister_provider(runtime, name: str) -> None:
```

> Release a registered provider; an absent name is a KeyError.
>
> convert.unregister_type answers the same way. Removing something that
> was never there is a mistake worth hearing about.

## `delivery_promise`

```python
def delivery_promise(provider: Any) -> tuple[str, str] | None:
```

> A provider's declared event capability, checked against the catalog.
>
> Silence is None and means no events, which is the safe answer and what
> every provider that says nothing gets. A claim outside the catalog's own
> `delivery` and `event-order` vocabularies is a mistake worth hearing
> about rather than a value to fall back from: falling back would either
> invent a promise the author did not make or discard one they did.

## `pushdown_class`

```python
def pushdown_class(provider: Any, pattern: Atom) -> str:
```

> What a provider claims about its filtering for this pattern.
>
> Silence is "inexact", which is Prolog's closed-world reading of the same
> question and the cautious answer: an inexact provider's candidates are
> re-unified and its bound stays advice. A claim that is neither word is a
> mistake worth hearing about rather than a value to fall back from,
> because the fallback would silently discard a real "exact".

## `foreign_refuse`

```python
def foreign_refuse(space: str, capability: str) -> None:
```

> Raise this provider's own refusal for a capability it does not provide.
>
> The engine now knows what a Python provider provides, so its own
> refuse_absent_capability/2 fires FIRST for an absent capability, and the
> provider's sentence would be lost behind a generic permission_error. This
> hands the refusal back to the side that has the words: "does not implement
> add" and "declines this add request" read differently, and a provider that
> wrote its own reason gets to say it.
>
> It never returns. Returning would mean the engine and this side disagree
> about what the provider provides, which is exactly the split the
> capability projection closed.

## `foreign_pushdown`

```python
def foreign_pushdown(space: str, pattern_wire: list) -> str:
```

> The shim asks this before pulling a bounded match's candidates.

## `foreign_match`

```python
def foreign_match(space: str, pattern_wire: list, limit: int | None = None, mode: str = 'abort'):
```

> The shim's py_iter enumerates this: candidate atoms, encoded.
>
> Everything that can fail happens before the generator exists. A
> generator body does not run until the first pull, and an exception
> raised there escapes through py_iter as
> `SystemError: apply_once returned a result with an exception set`,
> which names nothing the caller did. Raising it from an ordinary call
> instead lets janus carry it as the error it is.

## `foreign_atoms`

```python
def foreign_atoms(space: str):
```

> The shim's py_iter enumerates this; see foreign_match on ordering.

## `is_matchable`

```python
def is_matchable(obj: Any) -> bool:
```

> Whether a grounded value owns its matching logic; the shim's probe.

## `match_object`

```python
def match_object(obj: Any, other_wire: list):
```

> One grounded value's match_ against the operand it met in unify.
>
> The value is local, so nothing crosses per candidate: match_ runs
> here and only the answers are encoded. Errors abort by design; see
> CustomMatch.

## `foreign_transaction`

```python
def foreign_transaction(space: str, step: str) -> bool:
```

> One transactional step on a declared-transactional provider.

## `foreign_add`

```python
def foreign_add(space: str, atom_wire: list) -> bool:
```

No docstring is defined.

## `foreign_plan`

```python
def foreign_plan(space: str, pattern_wires: list):
```

> The claim, as the shim asks for it: a decline is `None`, a claim is
> [claimed, rest, rows] on the wire. The rows are materialised here rather
> than streamed, because a claim is answered as a whole and the engine has no
> use for a half-planned join.

## `foreign_add_many`

```python
def foreign_add_many(space: str, atom_wires: list) -> bool:
```

No docstring is defined.

## `foreign_remove`

```python
def foreign_remove(space: str, atom_wire: list) -> bool:
```

No docstring is defined.

## `foreign_clear`

```python
def foreign_clear(space: str) -> bool:
```

No docstring is defined.
