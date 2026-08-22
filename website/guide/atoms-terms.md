<!--
Purpose: teach canonical atom construction, operators, methods, pattern matching, ordering, and wire conversion.
Guarantees: examples contain no superseded atom class or helper names, and
plain atom sorting agrees with the explicit specialist key.
[tested: npm run docs:build and test_plain_sorted_uses_the_engines_elementwise_order;
commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
-->

# Atoms, operators, and term building

Atoms are immutable Python values. `Symbol` is a MeTTa symbol, `Variable` is a variable, `Grounded` carries a host value, and `Expression` is an ordered expression. `S.likes` creates the symbol `likes`. `V.x` creates `$x`. Applying a symbol builds an expression without calling the engine.

The first example builds a small family relation, joins over it, and evaluates a nondeterministic term:

```python
# Atoms are Python values: S mints symbols, V variables, application builds
# expressions, and none of it costs an engine call.
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann), S.Parent(S.Ann, S.Zoe))
rows = m.query(S.Parent(V.gp, V.p), S.Parent(V.p, V.gc))
check("join count", len(rows), 2)
check("first grandparent", (rows[0].gp, rows[0].gc), (S.Tom, S.Ann))

# Evaluation is what ! runs, nondeterminism included.
check("eval", m.eval(S.superpose(Expression(1, 2, 3))), [1, 2, 3])
```

Operators on atoms build terms. `V.age >= 18` builds `(>= $age 18)`, so guards and bodies read as the Python they look like. The full set:

| you write | it builds | | you write | it builds |
|---|---|---|---|---|
| `x + y` | `(+ x y)` | | `x & y` | `(and x y)` |
| `x - y` | `(- x y)` | | `x \| y` | `(or x y)` |
| `x * y` | `(* x y)` | | `x ^ y` | `(xor x y)` |
| `x / y` | `(/ x y)` | | `~x` | `(not x)` |
| `x % y` | `(% x y)` | | `S["<"](x, y)` | `(< x y)` |
| `x ** y` | `(pow-math x y)` | | `x <= y` | `(<= x y)` |
| `x // y` | `(floor-math (/ x y))` | | `x > y` | `(> x y)` |
| `x @ y` | `(matmul x y)` | | `x >= y` | `(>= x y)` |
| `-x` | `(- 0 x)` | | `abs(x)` | `(abs-math x)` |
| `x.eq(y)` | `(== x y)` | | `x.ne(y)` | `(not (== x y))` |

Reflected forms work too: `1 + V.x` builds `(+ 1 $x)`.

The specialist immutable `petta.atoms.OPERATOR_LOWERINGS` table records these
lowerings. A row is a builtin symbol, a composite template, a provided name, a
reserved Python spelling, a sorting spelling, or an explicit absence. `matmul` is provided: `@`
always builds that stable name, and a library supplies its MeTTa definition.
Left and right shift are absent because MeTTa has no integer-shift operation;
`x << y` and `x >> y` raise a message naming that fact instead of Python's
generic unsupported-operands error. Grounded values keep Python semantics, so
`Grounded(3) << 2` answers `12` rather than building a term.

Two comparisons answer Python booleans. **`x.eq(y)` builds the equality term `(== x y)`, while `==` itself compares atoms structurally.** Likewise, `S["<"](x, y)` builds the relation while `x < y` compares the engine's standard atom order. Atoms are dict keys, test comparands, and sortable values, so neither Python operator can become a term.

`Grounded` arithmetic and comparisons against raw Python values keep Python value semantics. Comparing one atom with another uses atom identity for equality and the engine order for `<`.

A symbol and a grounded string are different atoms. Use `S[name]` when a symbol name is not a Python identifier, `V[name]` for a variable, `ground(value)` or `G(value)` to carry a host object, and `Expression(...)` to build an expression from parts. `parse(source)` reads one form without evaluating it.

Atoms expose `.vars`, `.map(transform)`, and `.alpha_eq(other)`; `unify(pattern, atom)` remains the relation between two atoms. A ground atom has no variables, so `not atom.vars` is the groundness test. See [`petta.atoms`](../reference/petta-atoms) for the specialist surface.

## Destructuring with match/case

Every atom class declares `__match_args__`, so Python's structural pattern matching destructures atoms the way a MeTTa pattern does, two pattern languages over the same data:

```python
match atom:
    case Expression([Symbol("edge"), a, b]):  # the MeTTa pattern (edge $a $b)
        connect(a, b)
    case Expression([Symbol("edge"), *nodes]):  # any arity
        hyperconnect(nodes)
    case Symbol(name):                     # any bare symbol, name bound
        note(name)
    case Grounded(int() | float() as number):  # a grounded number
        accumulate(number)
    case Variable(_):
        pass                               # an unbound hole
```

The correspondence is direct: `Expression([Symbol("edge"), a, b])` is `(edge $a $b)` with `a` and `b` as the captures, `*rest` is the tail a MeTTa `$xs` would take, and a literal like `Symbol("edge")` plays the ground-symbol role. What `case` does not do is unification: a repeated capture name is a Python error rather than an equality constraint, and nothing binds inside the atom. When you want real unification, ask for it, `unify(pattern, atom)` answers the bindings or `None`; `case` is for shape dispatch in Python code, `query` on a space is for knowledge.

## Sorting atoms

`sorted(atoms)` uses the engine's standard atom order directly. The specialist key remains available when an API asks for a key function:

```python
from petta.atoms import order_key

sorted(atoms)
sorted(atoms, key=order_key)  # the same order
```

The order places variables first, then numbers, symbols, strings, opaque objects, and expressions. Expressions compare child by child; length decides only after one is a prefix. `True` sorts with the symbols it reads as rather than with the numbers Python inherits it from.

## Atoms as JSON

An atom's wire form is a JSON document, and it round-trips, keeping the variable's name:

```python
import json
from petta import wire

text = json.dumps(S.edge(S.a, 1, V.x).to_wire())
# '["e", [["s", "edge"], ["s", "a"], ["n", 1], ["v", "x"]]]'
wire.from_wire(json.loads(text))       # (edge a 1 $x)
```

That is the interchange for anything web-facing, and it preserves what storage does not: a variable that goes through a space comes back with a machine name, and one that goes through JSON comes back as `$x`. Both spell one identity, which is all a `v` payload ever means; `CODEC.md` is the grammar, for anyone writing the other end in another language.
