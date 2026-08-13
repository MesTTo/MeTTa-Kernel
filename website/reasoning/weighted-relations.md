# Weighted relations and neural predicates

`petta.measure.weighted_relation` turns a weights-producing Python callable into a dual-mode MeTTa relation. The unbound mode returns one `(weight class)` pair for every class. The bound mode scores one chosen class. Both modes use the shape consumed by `ws-best`, `ws-sample!`, and the other measure operations.

The callable can be a lookup table, a heuristic, or a model. It must return one weight per declared class.

The torch instance is `pettorch.neural_predicate`, which lives in the pettorch repository beside this one: it softmaxes a network's forward pass, aligns each output with a class term, and registers the result through this very interface, DeepProbLog's nn predicate reading. Its docs travel with that repository.

A weighted relation from a plain callable, registered and consumed through the measure algebra:

```python
def test_weighted_relation_takes_any_callable(m):
    from petta import measure

    measure.install(m)

    def mood_weights(day):
        return [0.25, 0.75]

    measure.weighted_relation(m, "mood", mood_weights, [S.calm, S.tense])
    (pairs,) = m.run("!(collapse (mood today))")[0]
    assert [(float(p[0]), str(p[1])) for p in pairs] == [
        (0.25, "calm"),
        (0.75, "tense"),
    ]
    (best,) = m.run("!(ws-best (collapse (mood today)))")[0]
    assert best == S.tense
    (scored,) = m.run("!(mood today calm)")[0]
    assert float(scored[0]) == 0.25 and scored[1] == S.calm
```

See [`petta.measure.weighted_relation`](../reference/petta-measure#weighted-relation).
