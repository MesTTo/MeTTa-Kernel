<!--
Purpose: teach canonical atom construction, operators, methods, pattern matching, ordering, and wire conversion.
Guarantees: examples contain no superseded atom class or helper names, and
plain atom sorting agrees with the explicit specialist key.
[tested: npm run docs:build and test_plain_sorted_uses_the_engines_elementwise_order;
commit=5fe3175632a6b60b3b54ca9125b75607ac82401a]
[tested: test_atom_comparisons_are_only_ordering; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
-->

# Atoms, operators, and term building

Atoms are immutable Python values. `Symbol` is a MeTTa symbol, `Variable` is a variable, `Grounded` carries a host value, and `Expression` is an ordered expression. `S.likes` creates the symbol `likes`. `V.x` creates `$x`. Applying a symbol builds an expression without calling the engine.

## S and V are name factories

`S.edge(S.Ada, V.friend)` builds `(edge Ada $friend)`. `S.edge` mints the
`edge` symbol, `S.Ada` mints the `Ada` symbol, and `V.friend` mints the
`$friend` variable. Calling the head symbol then builds one `Expression`.

Attribute names use Python spelling. An underscore maps to a MeTTa hyphen, so
`S.parent_of` is `parent-of` and `V.next_value` is `$next-value`. Brackets
preserve exact spelling: `S["parent_of"]` is `parent_of`, and
`V["next_value"]` is `$next_value`. Use brackets for punctuation, keywords,
and names whose underscores must remain underscores.

`S` and `V` only construct atoms. They do not consult a space, resolve a
function, or evaluate a term. The variable `V._` is anonymous: it can match a
value but never creates a result column. A raw Python string is a grounded
string, not a symbol, so use `S[name]` when the value must be a symbol.

The first example builds a small family relation, joins over it, and evaluates a nondeterministic term:

```python
# Atoms are Python values: S mints symbols, V variables, application builds
# expressions, and none of it costs an engine call.
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann), S.Parent(S.Ann, S.Zoe))
rows = m.match(S.Parent(V.gp, V.p), S.Parent(V.p, V.gc))
check("join count", len(rows), 2)
check("first grandparent", (rows[0].gp, rows[0].gc), (S.Tom, S.Ann))

# Evaluation is what ! runs, nondeterminism included.
check("eval", m.eval(S.superpose(Expression(1, 2, 3))), [1, 2, 3])
```

## Build terms, not source text

`term = S.Order(7, 5)` builds `(Order 7 5)` on every supported Python
version, including the 3.12 floor. Pass that atom to `m.eval(term)` or another
atom-taking door. Do not assemble MeTTa source when the API accepts an atom.

When a text-only door is unavoidable, build each atom first and render the
finished term: `source = f"!{term}"` produces `!(Order 7 5)`, which
`m.run(source)` can read. Python t-string syntax is available only on 3.14 and
newer. It creates a `string.templatelib.Template`; `Space.run` accepts a
`str`, not a `Template`. Treat a t-string as optional sugar for an integration
that explicitly renders templates, not as the 3.12 term-construction path.

See [where code runs](./where-code-runs.md) for the boundary between building
an atom and evaluating it.

Arithmetic and boolean operators on atoms build terms. Comparison operators
compare atoms; comparison terms name their head explicitly. The full set:

| you write | it builds | | you write | it builds |
|---|---|---|---|---|
| `x + y` | `(+ x y)` | | `x & y` | `(and x y)` |
| `x - y` | `(- x y)` | | `x \| y` | `(or x y)` |
| `x * y` | `(* x y)` | | `x ^ y` | `(xor x y)` |
| `x / y` | `(/ x y)` | | `~x` | `(not x)` |
| `x % y` | `(% x y)` | | `x.lt(y)` | `(< x y)` |
| `x ** y` | `(pow-math x y)` | | `x.le(y)` | `(<= x y)` |
| `x // y` | `(floor-math (/ x y))` | | `x.gt(y)` | `(> x y)` |
| `x @ y` | `(matmul x y)` | | `x.ge(y)` | `(>= x y)` |
| `-x` | `(- 0 x)` | | `abs(x)` | `(abs-math x)` |
| `x.eq(y)` | `(== x y)` | | `x.ne(y)` | `(not (== x y))` |

Reflected forms work too: `1 + V.x` builds `(+ 1 $x)`.

The specialist immutable `metta.atoms.OPERATOR_LOWERINGS` table records these
lowerings. A row is a builtin symbol, a composite template, a provided name, a
reserved Python spelling, a sorting spelling, or an explicit absence. `matmul` is provided: `@`
always builds that stable name, and a library supplies its MeTTa definition.
Left and right shift are absent because MeTTa has no integer-shift operation;
`x << y` and `x >> y` raise a message naming that fact instead of Python's
generic unsupported-operands error. Grounded values keep Python semantics, so
`Grounded(3) << 2` answers `12` rather than building a term.

All comparisons answer Python booleans. **`x.eq(y)` builds the equality term `(== x y)`, while `==` itself compares atoms structurally.** The same split holds for ordering: `x.lt(y)`, `x.le(y)`, `x.gt(y)` and `x.ge(y)` build relations, while the four rich comparison operators compare the engine's standard atom order. The bracket door `S["<"](x, y)` spells the same term for a head outside identifier grammar. Atoms are dict keys, test comparands, and sortable values, so Python comparison operators never become terms.

`Grounded` arithmetic and comparisons against raw Python values keep Python value semantics. Comparing one atom with another uses atom identity for equality and the engine order for all four ordering operations.

A symbol and a grounded string are different atoms. Use `S[name]` when a symbol name is not a Python identifier, `V[name]` for a variable, `ground(value)` or `G(value)` to carry a host object, and `Expression(...)` to build an expression from parts. `parse(source)` reads one form without evaluating it.

Atoms expose `.vars`, `.map(transform)`, and `.alpha_eq(other)`. `unify(a, b)` is symmetric: variables in either atom bind, and it answers one normalized bindings mapping or `None`. The four-argument overload, `unify(a, b, then, els)`, evaluates MeTTa's conditional in the ambient space; a compiled body lowers the same spelling directly. A ground atom has no variables, so `not atom.vars` is the groundness test. See [`metta.atoms`](../reference/metta-atoms) for the specialist surface.

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

The correspondence is direct: `Expression([Symbol("edge"), a, b])` is `(edge $a $b)` with `a` and `b` as the captures, `*rest` is the tail a MeTTa `$xs` would take, and a literal like `Symbol("edge")` plays the ground-symbol role. What `case` does not do is unification: a repeated capture name is a Python error rather than an equality constraint, and nothing binds inside the atom. When you want real unification, ask for it, `unify(left, right)` answers the bindings or `None`; `case` is for shape dispatch in Python code, `query` on a space is for knowledge.

## Sorting atoms

`sorted(atoms)` uses the engine's standard atom order directly. The specialist key remains available when an API asks for a key function:

```python
from metta.atoms import order_key

sorted(atoms)
sorted(atoms, key=order_key)  # the same order
```

The order places variables first, then numbers, symbols, strings, opaque objects, and expressions. Expressions compare child by child; length decides only after one is a prefix. `True` sorts with the symbols it reads as rather than with the numbers Python inherits it from.

## Atoms as JSON

An atom's wire form is a JSON document, and it round-trips, keeping the variable's name:

```python
import json
from metta import wire

text = json.dumps(S.edge(S.a, 1, V.x).to_wire())
# '["e", [["s", "edge"], ["s", "a"], ["n", 1], ["v", "x"]]]'
wire.from_wire(json.loads(text))       # (edge a 1 $x)
```

That is the interchange for anything web-facing, and it preserves what storage does not: a variable that goes through a space comes back with a machine name, and one that goes through JSON comes back as `$x`. Both spell one identity, which is all a `v` payload ever means; `CODEC.md` is the grammar, for anyone writing the other end in another language.
