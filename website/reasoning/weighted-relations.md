# Weighted relations and neural predicates

`petta.measure.weighted_relation` turns a weights-producing Python callable into a dual-mode MeTTa relation. The unbound mode returns one `(weight class)` pair for every class. The bound mode scores one chosen class. Both modes use the shape consumed by `ws-best`, `ws-sample!`, and the other measure operations.

The callable can be a lookup table, a heuristic, or a model. It must return one weight per declared class.

`pettorch.neural_predicate` applies that interface to a PyTorch network. It softmaxes the forward pass, aligns each output with a class term, and registers the resulting weighted relation. The following source registers three classes and selects the maximum-weight answer:

```python
network = torch.nn.Linear(2, 3, bias=False)
with torch.no_grad():
    network.weight.copy_(torch.tensor([[0.1, 0.9], [2.0, 0.1], [0.2, 0.2]]))
pettorch.neural_predicate(m, "guess", network, [S.zero, S.one, S.two])

m.run("!(import! (context-space) (library lib_measure))")
m.run("!(ws-best (collapse (guess (tensor (1.0 0.0)))))")   # [[Sym('one')]]
```

By default, probabilities cross as Python floats for reasoning. With `with_grad=True`, each probability remains a zero-dimensional tensor on the autograd graph. Downstream work on those values must then use tensor operations.

See [`petta.measure.weighted_relation`](../reference/petta-measure#weighted-relation) and [`pettorch.neural.neural_predicate`](../reference/pettorch-neural#neural-predicate).
