# `metta.structures`

Source: `extensions/python/metta/structures.py`.

> Purpose: data structures with MeTTa's semantics at Python speed, built on
> the boundary-free atom kernel (unify, alpha_eq, variables, order_key) and
> never touching the engine: importable and usable without janus. PatternMap
> answers "which entries apply to this atom", MatchIndex answers "which of
> many registered patterns match it" sublinearly, and AlphaSet holds atoms
> modulo variable renaming.
> Assumes:
>   - metta.atoms._match is the private directional primitive every lookup
>     here wants: stored patterns are the pattern side and probes are the atom
>     side [source: extensions/python/metta/atoms.py:_match; commit=6917bef7ca902671999eafcae3a7a86db8f69723]
> Guarantees:
>   - PatternMap's ground keys behave exactly like dict keys, the no-tax
>     rule [tested test_patternmap_ground_keys_are_dict_keys]
>   - MatchIndex.matches agrees with brute-force unification over every
>     registered pattern, keeping integer and float atoms apart and NaN atoms
>     together the way the engine's matcher does
>     [tested test_matchindex_agrees_with_brute_force,
>     test_matchindex_matches_grounded_numbers_by_unification]
>   - MatchIndex.matches answers in REGISTRATION order whatever order the
>     tree walk reached the entries in, and a remove does not disturb it
>     [measured 2026-08-19: register a, b; remove a; register c; the answer
>     was c before b] [tested
>     test_dispatch_through_the_index_delivers_the_same_subscribers_in_the_same_order]
>   - MatchIndex treats identity-only Grounded handles as opaque values instead
>     of reading the deliberately absent Grounded.value slot [tested:
>     test_a_transaction_commits_async_launch_before_its_landing,
>     test_matchindex_indexes_handles_without_unwrapping_them;
>     commit=173eeed021beb360b5e5f9f8461889e27190affc]
>   - AlphaSet membership is alpha_eq membership [tested
>     test_alphaset_is_alpha_membership]
>   - LiveView holds exactly what the space holds for its pattern, through
>     adds and through removals whose event cannot say which occurrence left
>     [tested test_liveview_mirrors_the_space]
> Decides:
>   - source text is NOT parsed here, because parsing needs the engine and
>     this module's contract is engine-freedom; parse() first, or build
>     atoms with S/V/Expression
>   - every ordered atom assembled in this file passes one iterable to
>     Expression [tested: test_expression_assembles_one_ordered_atom_from_an_iterable; commit=b1599bdc8201a04a3689c1a88707b6f4b53b4d22]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `PatternMap`

```python
class PatternMap(MutableMapping):
```

> A MutableMapping whose keys are atoms and whose point is the
> question "which entries apply to this atom?".
>
> Ground keys hash exactly like dict keys, the no-tax rule: getting,
> setting, and deleting a ground key is one dict operation. Pattern
> keys (keys carrying variables) land in head/arity buckets, and
> matching(atom) probes only the buckets the atom could touch,
> answering every (key, value) whose key unifies with it. The mapping
> protocol itself stays exact: pm[k] answers the entry stored under
> that very key (alpha-equal for pattern keys), never a unification.
>
>     routes = PatternMap()
>     routes[S.route(S.home)] = home_handler          # ground: dict speed
>     routes[S.route(V.anything)] = fallback_handler  # pattern: bucketed
>     [v for _, v in routes.matching(S.route(S.home))]

### `PatternMap.matching`

```python
def matching(self, atom: Any) -> Iterator[tuple[Atom, Any]]:
```

> Every (key, value) whose KEY unifies with the atom: the
> dispatch question. A ground probe costs one dict hit plus the
> buckets its head and arity could touch; a probe carrying
> variables consults every pattern entry, since a variable probe
> can reach any bucket, and ground entries it unifies with.

## `MatchIndex`

```python
class MatchIndex:
```

> Many registered patterns, one incoming atom, "which patterns match
> it?" answered sublinearly: pub/sub topic matching, rule dispatch,
> feature targeting, webhook routing.
>
> An imperfect discrimination tree, the term-indexing structure theorem
> provers use at millions-of-terms scale, over the atom kernel: each
> pattern flattens to a preorder token path with variables as skip
> edges, retrieval walks the ground atom's own tokens following exact
> and skip edges at once, and the candidates verify with unify, which
> is also what makes nonlinear patterns ((f $x $x)) exact.
>
>     inbox = MatchIndex()
>     inbox.add(S.order(V.id, S.express), rush_handler)
>     [value for _, value in inbox.matches(S.order(ground(7), S.express))]

### `MatchIndex.add`

```python
def add(self, pattern: Any, value: Any = None) -> None:
```

> Register a pattern with a value (a handler, a topic, an id).

### `MatchIndex.remove`

```python
def remove(self, pattern: Any, value: Any = None) -> bool:
```

> Remove one registration matching (pattern, value) exactly;
> answers whether one existed.

### `MatchIndex.matches`

```python
def matches(self, atom: Any) -> Iterator[tuple[Atom, Any]]:
```

> Every registered (pattern, value) whose pattern matches the
> ground atom, in REGISTRATION order, whatever order the tree walk
> reached them in. The tree answers candidates; unify confirms, so
> nonlinearity is exact.

## `AlphaSet`

```python
class AlphaSet(MutableSet):
```

> A set of atoms modulo variable renaming: a rule or pattern store
> that must not hold the same rule twice under renamed variables.
> Membership, addition, and discard all read through the canonical
> form, so (f $x $x) and (f $y $y) are one element and (f $x $y) is
> another.
>
>     rules = AlphaSet([parse("(= (inc $x) (+ $x 1))")])
>     parse("(= (inc $n) (+ $n 1))") in rules     # True

### `AlphaSet.add`

```python
def add(self, value: Any) -> None:
```

No docstring is defined.

### `AlphaSet.discard`

```python
def discard(self, value: Any) -> None:
```

No docstring is defined.

## `TabledMap`

```python
class TabledMap:
```

> A computed cache that stays correct: a read-only view of a TABLED
> function, so tm[args] evaluates once, repeats answer from the
> engine's table, and a write to a space the function reads (by its
> literal name) invalidates exactly the affected tables, SWI's
> incremental tabling underneath. functools.cache has no dependency
> tracking at all; this is the memoization that is safe next to a
> mutating knowledge base.
>
>     m.run("(= (cheapest) (min-atom (collapse (match &kb (price $i $p) $p))))")
>     prices = TabledMap(m, "cheapest", arity=0)
>     prices[()]                  # evaluated once, tabled
>     kb.add(S.price(S.plum, 1))  # invalidates
>     prices[()]                  # re-evaluated, fresh
>
> Not a Mapping ABC on purpose: the key domain is the function's, not
> enumerable, so iteration would lie. `key in tm` COMPUTES (and
> tables) the entry, which is what membership means for a computed
> map. A nondeterministic function does not fit a map; a key whose
> call answers several values raises, and one answering none is a
> KeyError.

### `TabledMap.stats`

```python
def stats(self) -> dict[str, int]:
```

> The engine's own counters for this function's tables: tables,
> answers, complete-call, invalidated, reevaluated. invalidated
> above reevaluated is SWI deciding a table was not worth
> rebuilding yet; both moving is the freshness machinery working.

### `TabledMap.clear`

```python
def clear(self) -> None:
```

> Drop this function's tables; the next read re-evaluates.

## `LiveView`

```python
class LiveView:
```

> A materialised view of one pattern, kept current by the space's
> own subscription events: dashboards, counters, "the current set of
> X" a program keeps consulting. Reads are local, the maintenance
> already happened.
>
>     alerts = LiveView(m, S.alert(V.level))
>     S.alert(S.red) in alerts       # no engine call
>     len(alerts)                    # multiset size, like len(space)
>
> The seed query and the subscription install run inside ONE engine
> transaction, so no write can fall between them: the view starts
> exactly consistent and every later matching write arrives as an
> event. A space is a multiset and so is the view: len counts copies,
> iteration yields them, count(atom) answers multiplicity. close()
> cancels the subscription; a closed view keeps its last state.

### `LiveView.count`

```python
def count(self, atom: Any) -> int:
```

> How many copies of this atom the view holds.

### `LiveView.close`

```python
def close(self) -> None:
```

> Cancel the subscription; the view stops updating.

## `ClosureView`

```python
class ClosureView:
```

> Reachability over a stored relation: dependencies, hierarchies,
> (a, b) in view. The closure is a pair of MeTTa equations over the
> relation's own atoms, TABLED from birth, because tabling is what
> makes a cyclic or symmetric closure terminate at all (SLG
> resolution's whole point) and what keeps the answers fresh when the
> relation's atoms change (the space is read by its literal name, so
> SWI's incremental tabling invalidates on writes).
>
>     deps = ClosureView(m, "imports")
>     (S.app, S.libc) in deps
>     deps.reachable(S.app)
>
> Nodes are ATOMS, not names: the relation holds whatever atoms were
> stored in it, and a Python str is a MeTTa String rather than the
> symbol of the same spelling, so reachable("app") answers nothing
> where reachable(S.app) answers the closure. The relation NAME is a
> str because it names a function rather than an atom.
>
> symmetric=True adds the reversed base case, the undirected reading;
> without tabling that spelling never terminates, which is why the
> class always tables. Defines `<relation>-closure` (and its `-step`)
> in the space, named so a MeTTa program can call the same closure.

### `ClosureView.reachable`

```python
def reachable(self, start: Any) -> set[Atom]:
```

> Every node reachable from start, as a set: the closure is a
> relation, so duplicates are answer multiplicity, not data.
