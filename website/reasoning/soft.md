# Soft unification and proving

Soft unification keeps expression structure crisp while allowing symbols to be close by a degree. Variables still bind. Degrees combine by minimum. `soft.similar(...)` writes ordinary `(similar a b degree)` facts, `soft.link_store(...)` materializes them from an embedding store, and `soft.similar_pattern(...)` materializes them from a regex over the space's own symbols, so a pattern names a family the way an embedding store names a neighborhood.

`soft-match` scores every matching candidate in a space. Its `(score candidate)` answers feed the same measure algebra used by custom matchers. `soft-best` selects the closest fact.

`soft.prove` adds goal-directed backward chaining. It follows stored facts, Horn-shaped equations, conjunctions, and ground guards. A `Proof` carries substitutions, the aggregate similarity, and each named step.

The complete self-verifying example moves from term scoring to a proof across a predicate similarity:

```python
import petta_soft as soft
from petta import MeTTa, S, V, expr

m = MeTTa().fresh_space()
soft.install(m)

# Declared closeness; identity is 1.0, unrelated is 0.0, min aggregates.
soft.similar(m, "cat", "feline", 0.8)
(degree,) = m.run("!(soft-score (likes feline fish) (likes cat fish))")[0]
check("symbols soft, structure crisp", degree, 0.8)
check("arity mismatch is zero", m.run("!(soft-score (a b) (a b c))")[0][0], 0.0)

# The pattern's variables BIND while scoring: soft matching is unification.
(pair,) = m.run(
    "!(let $probe (soft-score (likes $who fish) (likes cat fish)) ($probe $who))"
)[0]
check("variables bind through the soft match", pair, expr(1.0, S.cat))

# A space of facts, softly matched, measured, decided.
m.add(S.likes(S.cat, S.fish), S.likes(S.dog, S.bones), S.likes(S.bird, S.seeds))
(best,) = m.run("!(soft-best (context-space) (likes feline $food))")[0]
check("the closest fact wins", best, expr(S.likes, S.cat, S.fish))

# The Python scorer mirrors the equations exactly (a differential fuzz in
# the test suite holds them equal); use it where a million scores would be
# a million engine calls.
table = {("cat", "feline"): 0.8}
check(
    "python mirror agrees",
    soft.score(m.parse("(likes feline fish)"), m.parse("(likes cat fish)"), table),
    0.8,
)

# Goal-directed proving over the same closeness: backward chaining with
# soft unification at every step, the tensor-theorem-prover reading. The
# goal predicate grandfather-of never appears in the knowledge, only
# grandpa-of does; the declared similarity carries the proof across, and
# a ground guard like (> 12 10) is decided by the engine itself.
m.add(S["parent-of"](S.homer, S.bart), S["father-of"](S.abe, S.homer))
m.run("(= (grandpa-of $x $y) (and (father-of $x $z) (parent-of $z $y)))")
soft.similar(m, "grandpa-of", "grandfather-of", 0.9)
proof = soft.prove(m, S["grandfather-of"](V.who, S.bart))
check("the similarity bridge carries the proof", proof.substitutions["who"], S.abe)
check("degrees aggregate by minimum", proof.similarity, 0.9)
check(
    "every step is named",
    [s.kind for s in proof.steps],
    ["rule", "fact", "fact"],
)
```

See [`petta_soft`](../reference/petta-soft) for thresholds, proof limits, and all result fields.
