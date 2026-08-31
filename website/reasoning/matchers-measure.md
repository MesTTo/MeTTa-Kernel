<!--
Purpose: explain custom matching as a property of grounded atoms, with the
measure library as the in-language companion, through executable examples.
Guarantees: the example uses canonical atom names and the public space factory.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
-->

# Custom matching

In MeTTa, a grounded value can define its own matching logic. A space is
the standard instance: in Hyperon a space is a grounded atom whose custom
matching is query, which is why `unify` accepts a space as an operand. The
same door is open to your own values. Any Python object whose class
defines `match_` participates in `(unify ...)` the moment it appears
there, with no registration.

`match_(other)` receives the atom your value met and yields one item per
binding set: a `Bindings` or `Answer` binding the variables of `other`, a
plain atom the operand must equal, or nothing at all for no match. An
interval that matches the numbers inside it is three lines:

```python
from metta import Expression, Grounded, S, space

class Interval:
    def __init__(self, lo, hi):
        self.lo, self.hi = lo, hi

    def match_(self, other):
        value = other.value if isinstance(other, Grounded) else other
        if isinstance(value, (int, float)) and self.lo <= value <= self.hi:
            yield other

m = space()
inside = Grounded(Interval(1, 5))
m.eval(Expression(S.unify, inside, 3, S.inside, S.outside))   # [inside]
m.eval(Expression(S.unify, inside, 9, S.inside, S.outside))   # [outside]
```

Variables are never sent to your logic: `$x` against a matchable value
binds `$x` to the value whole, because the variable case is decided before
any value's matching logic is consulted. A value with no matching logic
compares by identity. And because a space is an operand like any other,
`(unify &self (friend $who Alice) $who no-friends)` answers each friend, or
the else branch when there are none.

A matchable can bind the variables it is handed, which is how a value
becomes a solver rather than a filter:

```python
class Nearest:
    def match_(self, other):
        query, out = other.children[0], other.children[1]
        key, _score = next(iter(store.ranked(query, 1)))
        yield Bindings({out: key})
```

Matching that carries a score is an ordinary operation instead: answer
each candidate as the value with the degree as the answer's annotation,
declare the semiring, and `top` orders while `(annotation)` reads the
degree beside its answer. Nothing about scores is built into the library;
the whole of it is `Space.op`, `Answer(value=..., k=...)` and
`annotations`, so fuzzy, regex and semantic closeness are each a
few lines in your own code. The executable version of everything on this
page is `extensions/python/examples/reasoning/custom_matchers.py`.

The measure library, `lib/lib_measure/lib_measure.metta`, stays what it always was:
pure MeTTa over explicit `(weight value)` pair data, with `ws-total`,
`ws-normalize`, `ws-softmax`, `ws-best`, `ws-sample!` and friends.
`lib/lib_soft/lib_soft.metta` extends it over terms. Both import with
`!(import! (context-space) (library lib_measure))` and operate on pairs
you build in the language; when you want an annotated operation's answers
as pairs, `(pair (annotation) $answer)` is the bridge.
