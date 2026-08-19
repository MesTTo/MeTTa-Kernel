# Atoms, operators, and term building

Atoms are immutable Python values. `Sym` is a MeTTa symbol, `Var` is a variable, `Gnd` carries a host value, and `Expr` is an ordered expression. `S.likes` creates the symbol `likes`. `V.x` creates `$x`. Applying a symbol builds an expression without calling the engine.

The first example builds a small family relation, joins over it, and evaluates a nondeterministic term:

```python
# Atoms are Python values: S mints symbols, V variables, application builds
# expressions, and none of it costs an engine call.
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann), S.Parent(S.Ann, S.Zoe))
rows = m.query(S.Parent(V.gp, V.p), S.Parent(V.p, V.gc))
check("join count", len(rows), 2)
check("first grandparent", (rows[0].gp, rows[0].gc), (S.Tom, S.Ann))

# Evaluation is what ! runs, nondeterminism included.
check("eval", m.eval(S.superpose(expr(1, 2, 3))), [1, 2, 3])
```

Operators on atoms build terms. `V.age >= 18` builds `(>= $age 18)`, so guards and bodies read as the Python they look like. The full set:

| you write | it builds | | you write | it builds |
|---|---|---|---|---|
| `x + y` | `(+ x y)` | | `x & y` | `(and x y)` |
| `x - y` | `(- x y)` | | `x \| y` | `(or x y)` |
| `x * y` | `(* x y)` | | `x ^ y` | `(xor x y)` |
| `x / y` | `(/ x y)` | | `~x` | `(not x)` |
| `x % y` | `(% x y)` | | `x < y` | `(< x y)` |
| `x ** y` | `(pow-math x y)` | | `x <= y` | `(<= x y)` |
| `x @ y` | `(matmul x y)` | | `x > y` | `(> x y)` |
| `x.ne(y)` | `(not (== x y))` | | `x >= y` | `(>= x y)` |

Reflected forms work too: `1 + V.x` builds `(+ 1 $x)`.

One operator is deliberately not symbolic. **`x.eq(y)` builds the equality term `(== x y)`, while `==` itself compares atoms structurally** and answers a Python `bool`. Atoms are dict keys and test comparands, so `S.a == S.a` must stay `True` rather than becoming a term; equality is the one place where building the term costs a method call, and it is the only operator that behaves unlike its neighbours.

`Gnd` overrides both families with value semantics: comparisons on grounded values answer booleans, engine-exactly, so a grounded number never quietly becomes a program. Arithmetic on grounded Python values keeps Python's value semantics.

A symbol and a grounded string are different atoms. Use `sym(name)` when a symbol name is not a Python identifier, `var(name)` for a variable, `val(value)` to carry a host object, and `expr(...)` to build an expression from parts. `parse(source)` reads one form without evaluating it.

The atom helpers also expose `variables`, `is_ground`, `alpha_eq`, and `unify`. See [`petta.atoms`](../reference/petta-atoms) for their source docstrings.

## Destructuring with match/case

Every atom class declares `__match_args__`, so Python's structural pattern matching destructures atoms the way a MeTTa pattern does, two pattern languages over the same data:

```python
match atom:
    case Expr([Sym("edge"), a, b]):        # the MeTTa pattern (edge $a $b)
        connect(a, b)
    case Expr([Sym("edge"), *nodes]):      # (edge $a $b $c ...), any arity
        hyperconnect(nodes)
    case Sym(name):                        # any bare symbol, name bound
        note(name)
    case Gnd(int() | float() as number):   # a grounded number
        accumulate(number)
    case Var(_):
        pass                               # an unbound hole
```

The correspondence is direct: `Expr([Sym("edge"), a, b])` is `(edge $a $b)` with `a` and `b` as the captures, `*rest` is the tail a MeTTa `$xs` would take, and a literal like `Sym("edge")` plays the ground-symbol role. What `case` does not do is unification: a repeated capture name is a Python error rather than an equality constraint, and nothing binds inside the atom. When you want real unification, ask for it, `unify(pattern, atom)` answers the bindings or `None`; `case` is for shape dispatch in Python code, `match` in a space is for knowledge.

## Sorting atoms

`sorted(atoms)` raises, and the message says why: `S.a < S.b` builds the term `(< a b)`, because building terms is what the operators are for. Pass the key instead:

```python
from petta import order_key

sorted(atoms, key=order_key)
```

The order is Prolog's standard order of terms: variables, then numbers, then symbols, then strings, then compounds by arity, then functor, then argument by argument. `True` sorts with the symbols it reads as rather than with the numbers Python inherits it from.

## Atoms as JSON

An atom's wire form is a JSON document, and it round-trips, keeping the variable's name:

```python
import json
from petta import atom_from_wire

text = json.dumps(S.edge(S.a, 1, V.x).to_wire())
# '["e", [["s", "edge"], ["s", "a"], ["n", 1], ["v", "x"]]]'
atom_from_wire(json.loads(text))       # (edge a 1 $x)
```

That is the interchange for anything web-facing, and it preserves what storage does not: a variable that goes through a space comes back with a machine name, and one that goes through JSON comes back as `$x`.
