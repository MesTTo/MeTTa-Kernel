<!--
Purpose: show weighted relations built on the general surface: an
operation answering its classes with weights as annotations.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
-->

# Weighted relations and neural predicates

A weighted relation is an ordinary operation whose answers carry their
weights as annotations. There is no dedicated machinery: `register_op`
registers the callable, each answer names its class as the value and its
weight as `k`, and `declare_annotations` states the semiring. `top`
orders the answers, `(annotation)` reads each weight beside its class,
and the in-language measure library consumes `(weight value)` pairs you
build with that bridge.

```python
from petta import Answer, MeTTa, S

m = MeTTa().new_space()

def mood(day, chosen=None):
    yield Answer(value=S.calm, k=0.25)
    yield Answer(value=S.tense, k=0.75)

m.register_op(mood, name="mood", typed=False)
m.declare_annotations("mood", "prob")

m.run("!(collapse (mood today))")                 # (calm tense)
m.run("!(collapse (top 1 (mood today)))")         # (tense)
m.run("!(collapse (let $c (mood today) (pair (annotation) $c)))")
# ((pair 0.25 calm) (pair 0.75 tense))
```

The callable can be a lookup table, a heuristic, or a model. The torch
instance is `pettorch.neural_predicate`, which lives in the pettorch
repository beside this one: it softmaxes a network's forward pass and
answers each class with its probability as the annotation, DeepProbLog's
nn predicate reading, built entirely on the surface above. Its docs
travel with that repository.
