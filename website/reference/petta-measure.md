# `petta.measure`

Source: `python/petta/measure.py`.

> Purpose: the Python face of lib_measure, the weighted-superposition
> algebra: install() imports the library into a space, ws() spells a weighted
> superposition from Python pairs, pairs() reads one back as (weight, value)
> tuples, and weighted_relation() registers any weights-producing callable as
> a nondeterministic MeTTa relation answering (weight class) pairs, the shape
> every ws- operation composes over. The algebra itself is pure MeTTa
> (lib/lib_measure.metta), annotated-disjunction shaped, so the CLI and
> Python run the same equations.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `install`

```python
def install(m) -> None:
```

> The measure algebra into this space: ws-total, ws-normalize,
> ws-softmax, ws-best, ws-top, ws-sample!, ws-collapse, ws-expect,
> ws-choose, ws-filter, ws-flip.

## `ws`

```python
def ws(*weighted: tuple[float, Any]) -> Expr:
```

> A weighted superposition from (weight, value) pairs.
>
> measure.ws((0.7, S.high), (0.3, S.low))    # ((0.7 high) (0.3 low))

## `pairs`

```python
def pairs(atom: Atom) -> list[tuple[float, Any]]:
```

> A weighted superposition read back: [(weight, value), ...], grounded
> values unwrapped.

## `weighted_relation`

```python
def weighted_relation(
    m,
    name: str,
    weights: Callable[[Any], Iterable[Any]],
    classes: Iterable[Any],
    *,
    raw_atoms: bool = False,
) -> str:
```

> Register a weights-producing callable as a weighted MeTTa relation.
>
>     measure.weighted_relation(m, "mood", score_moods, [S.calm, S.tense])
>     m.run("!(ws-best (collapse (mood today)))")     # argmax class
>     m.run("!(mood today calm)")                     # (w calm)
>
> classes are the relation's answer terms, in order; weights(value) must
> answer one weight per class, each already in its final form (a float,
> or any atom the caller wants carried, a val() tensor included).
> weights(value) receives a decoded grounded value; symbols and expressions
> stay atoms. Set raw_atoms=True only when the
> callable explicitly needs every input atom, including grounded values.
> The relation is dual-mode: (name $x) superposes every (weight class) pair,
> and (name $x class) scores the one class, both lib_measure's own shape,
> so ws-best is argmax, ws-sample! the stochastic reading, and rules
> compose over the answers as over any weighted alternatives. This is the
> general mechanism behind pettorch.neural_predicate, DeepProbLog's
> nn-predicate reading, with the network generalised to any callable.
