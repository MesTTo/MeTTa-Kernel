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

Operators on atoms build terms. `V.age >= 18` builds `(>= $age 18)`. `&`, `|`, and `~` build boolean terms. Arithmetic on grounded Python values keeps Python's value semantics.

A symbol and a grounded string are different atoms. Use `sym(name)` when a symbol name is not a Python identifier, `var(name)` for a variable, `val(value)` to carry a host object, and `expr(...)` to build an expression from parts. `parse(source)` reads one form without evaluating it.

The atom helpers also expose `variables`, `is_ground`, `alpha_eq`, and `unify`. See [`petta.atoms`](../reference/petta-atoms) for their source docstrings.
