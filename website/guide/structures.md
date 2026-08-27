<!--
Purpose: explain the pure, engine-backed, and MeTTa-native data-structure tiers.
Guarantees: Python examples use canonical atom construction and Space.name.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Data structures

`metta.structures` ships containers whose semantics are MeTTa's, unification, multisets, alpha equivalence, with each structure implemented where it is fastest. The pure tier runs on the atom kernel (`unify`, `Atom.alpha_eq`, `substitute`) and never touches the engine, so it imports and works without janus in the process; the engine-backed tier crosses deliberately, because its win IS the engine: tabling that invalidates on writes, subscriptions that maintain a view. MeTTa-side structures live in `lib_datastructures` for programs written in MeTTa itself.

## The pure tier: MeTTa semantics at Python speed

`PatternMap` is a `MutableMapping` whose keys are atoms and whose point is the dispatch question, "which entries apply to this atom?". Ground keys hash exactly like dict keys, so the plain job pays no tax; keys carrying variables land in head/arity buckets, and `matching(atom)` probes only the buckets the atom could touch:

```python
from metta.structures import PatternMap

routes = PatternMap()
routes[S.route(S.home)] = home_handler          # ground: dict speed
routes[S.route(V.anything)] = fallback_handler  # pattern: bucketed
[handler for _, handler in routes.matching(S.route(S.home))]
```

`MatchIndex` is the inverse: many registered patterns, one incoming atom, "which patterns match it?" answered sublinearly through an imperfect discrimination tree, the term-indexing structure theorem provers run at millions of terms. Candidates verify with `unify`, which is what makes a nonlinear pattern like `(pair $x $x)` exact. The everyday jobs are pub/sub topic matching, rule dispatch, and webhook routing:

```python
from metta.structures import MatchIndex

inbox = MatchIndex()
inbox.add(S.order(V.id, S.express), rush_handler)
[handler for _, handler in inbox.matches(S.order(ground(7), S.express))]
```

`AlphaSet` holds atoms modulo variable renaming, the store a rule base wants: `(= (inc $x) (+ $x 1))` and its `$n` twin are one element. Membership is `Atom.alpha_eq` membership, reached through canonical renaming so it costs a hash, and the suite proves it against the pairwise oracle with property tests.

None of the three parses source text, because parsing needs the engine and their contract is engine-freedom: `metta.parse()` first, or build atoms with `S`, `V`, and `Expression`.

## The engine-backed tier

`TabledMap` is the memoization that is safe next to a mutating knowledge base. It views a TABLED function: `tm[args]` evaluates once, repeats answer from the engine's table, and a write to a space the function reads by its literal name invalidates exactly the affected tables, SWI's incremental tabling underneath, which `functools.cache` cannot do at all:

```python
kb.run(f"(= (cheapest) (min-atom (collapse (match {kb.name} (price $i $p) $p))))")
prices = TabledMap(kb, "cheapest", arity=0)
prices[()]                  # evaluated once, tabled
kb.add(S.price(S.plum, 1))  # invalidates
prices[()]                  # fresh
prices.stats()              # {'tables': ..., 'invalidated': ..., 'reevaluated': ...}
```

The engine refuses to table a function whose space reads it cannot resolve to one literal space, `(match (context-space) ...)` included, because a cached answer would hide whatever the dynamic read does; name the space.

`LiveView` materialises one pattern and keeps it current from the space's own subscription events, so dashboards and "the current set of X" read locally. The seed query and the subscription install run inside one engine transaction, so no write falls between them, and the view mirrors the engine's multiset exactly: one removal operation takes one occurrence, and so does the view. A removal event carries the pattern that was asked for rather than the occurrence that left, so where the two differ, `m.remove(S.alert(V.q))` over two alerts, the view re-reads the space instead of guessing. A ground removal needs no read and costs the same whether the view holds ten atoms or a thousand.

```python
with LiveView(m, S.alert(V.level)) as alerts:
    S.alert(S.red) in alerts      # no engine call
    alerts.count(S.alert(S.red))  # multiplicity
```

`ClosureView` answers reachability over a stored relation, `("app", "libc") in deps`, through a pair of MeTTa equations tabled from birth: tabling is what makes a cyclic or symmetric closure terminate at all, and the literal space name is what keeps it fresh when the relation changes. It defines `<relation>-closure` in the space, so a MeTTa program calls the same closure.

## The MeTTa tier

`lib_datastructures` carries the term-shaped structures for programs written in MeTTa: the amortized O(1) functional queue, and a Hinze-Paterson 2-3 finger tree, push and pop at both ends in amortized O(1) with O(log n) concatenation, so one structure serves as sequence, deque, and staging buffer:

```metta
!(import! &self (library lib_datastructures))
!(ft-to-list (ft-concat (ft-from-list (1 2 3)) (ft-from-list (4 5))))  ; (1 2 3 4 5)
```

Every form carries `@doc` atoms, so `(help! ft-concat)` answers, and `examples/ch08-data/08-03-the-shipped-libraries/02-datastructures_fingertree.metta` runs the whole surface under the gate.
