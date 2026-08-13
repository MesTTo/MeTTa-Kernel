# 01. Atoms and expressions

Start with one atom: `(likes Ada Music)`.

The whole form is an expression. Its three children are symbols, in order: `likes`, `Ada`, and `Music`. Parentheses give the atom structure. They do not make it run. You can store the expression as data, place it inside another expression, or later evaluate it as a call.

![The expression likes Ada Music as nested atom blocks](/visuals/01-atoms-and-expressions.svg)

PeTTa exposes the same structure as Python values. `S.Ada` makes the symbol `Ada`, `V.x` makes the variable `$x`, and applying `S.Parent` builds an expression. This source-backed test shows that parsed MeTTa and a Python-built atom are equal:

```python
def test_parse_keeps_variable_names():
    p = parse("(Parent $x Bob)")
    assert p == S.Parent(V.x, S.Bob)
```

MeTTa has four atom forms:

- A symbol is a name such as `Ada` or `likes`.
- A variable is a named position such as `$who` that matching can bind.
- A grounded atom carries a host value such as a Python number or string.
- An expression is an ordered group of atoms.

Write `S.likes(V.who, S.Music)` in Python and you get `(likes $who Music)`. The variable changes one child, but the whole value is still an expression. Building it does not contact the engine.

The [atoms and terms guide](../guide/atoms-terms) covers constructors, parsing, operators, unification, and grounded values. Next, put atoms in a space and match them in [02. Spaces and matching](./02-spaces-and-matching).
