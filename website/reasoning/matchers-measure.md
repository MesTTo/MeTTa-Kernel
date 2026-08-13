# Custom matchers and the measure algebra

A matcher is a MeTTa function with two modes. With a bound candidate it scores that candidate. With an unbound candidate it generates candidates best first. Both modes answer `(score value)` pairs, so structural matching and a custom notion of closeness compose through ordinary evaluation.

`install_fuzzy` uses `difflib` for lexical closeness. `EmbeddingStore.matcher()` supplies semantic closeness from vectors. `matching.matcher(...)` accepts your own scoring and generation functions.

The self-verifying example uses all three readings:

```python
from petta import MeTTa, S, V, matching, measure  # noqa: E402
from petta.arrays import EmbeddingStore  # noqa: E402

m = MeTTa().fresh_space()
measure.install(m)

# Lexical closeness, the standard library's own: a matcher in one call.
matching.install_fuzzy(m, name="fuzmatch")
(scored,) = m.run('!(fuzmatch "recieve" "receive")')[0]
check("fuzzy scores typos", float(scored[0]) > 0.85)

# Semantic closeness: an embedding store IS a matcher.
store = EmbeddingStore(m, name="vec", mirror=False)
store.add(S.espresso, numpy.array([0.9, 0.1, 0.0]))
store.add(S.latte, numpy.array([0.8, 0.3, 0.0]))
store.add(S.granite, numpy.array([0.0, 0.1, 0.9]))
store.matcher(name="semmatch", threshold=0.0)

(best,) = m.run("!(ws-best (collapse (semmatch espresso $k)))")[0]
check("nearest neighbour", best, S.espresso)

# Attention through a matcher: softmax the matches, a distribution over
# candidates by THIS matcher's closeness.
(dist,) = m.run("!(ws-softmax (collapse (semmatch latte $k)) 0.5)")[0]
weights = {str(pair[1]): float(pair[0]) for pair in dist}
check("a distribution", abs(sum(weights.values()) - 1.0) < 1e-9)
check("coffee outweighs rock", weights["latte"] > weights["granite"])

# Your own closeness: any scoring function, same shape, same algebra.
def initials(query, candidate):
    a, b = str(query), matching.text_of(candidate)
    return 1.0 if a[:1] == b[:1] else 0.0

matching.matcher(m, "same-initial", score=initials, threshold=0.5)
m.add(S.person(S.ada), S.person(S.alan), S.person(S.grace))
(hits,) = m.run(
    "!(collapse (match (context-space) (person $p) (same-initial a $p)))"
)[0]
check("composes with structural match", len(hits), 2)
```

## Weighted superpositions

`measure.install(m)` imports `lib_measure` into the current space. The library treats a weighted superposition as a tuple of `(weight value)` pairs. Its operations include total mass, normalization, temperature softmax, maximum, ranking, top-k selection, sampling, duplicate collapse, expectation, filtering, and nondeterministic choice.

The first equations define total mass, normalization, and softmax:

```metta
(= (ws-total $ps)
   (foldl-atom (map-atom $ps (|-> ($p) (index-atom $p 0))) 0.0 +))

;Scale every weight so the mass is one; a distribution:
(= (ws-normalize $ps)
   (let $t (ws-total $ps)
        (map-atom $ps (|-> ($p) ((/ (index-atom $p 0) $t) (index-atom $p 1))))))

;Softmax with a temperature: scores become a distribution. Low temperature
;sharpens toward the best pair, high temperature flattens toward uniform.
(= (ws-softmax $ps $temp)
   (ws-normalize
     (map-atom $ps (|-> ($p) ((exp-math (/ (index-atom $p 0) $temp))
                              (index-atom $p 1))))))
```

See [`petta.matching`](../reference/petta-matching) and [`petta.measure`](../reference/petta-measure) for the Python APIs.
