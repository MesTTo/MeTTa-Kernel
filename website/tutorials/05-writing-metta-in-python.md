# 05. Writing MeTTa in Python

`@m.define` reads supported Python syntax and adds its MeTTa equation to a space. Calling the decorated name evaluates through that space, `S.name(...)` builds a term explicitly, and `.py` keeps the ordinary Python function.

![A factorial equation and a selected call that answers 120](/visuals/05-writing-metta-in-python.svg)

The runnable definitions example starts with factorial:

```python
@m.define
def fact(n):
    if n == 0:
        return 1
    return n * fact(n - 1)


check("equations run", m.run("!(fact 6)"), [[720]])
check("the Python twin agrees", fact.py(6), 720)
check("calling the name evaluates", fact(6), [720])
check("the S door builds the term", str(S.fact(6)), "(fact 6)")
```

Calling `fact(6)` runs the compiled equation and returns all engine answers. `S.fact(6)` builds `(fact 6)` as data, and `fact.py(6)` runs the Python reference directly. Inside an `@rules` generator, calls to defined objects stage scope-locally so `equation(lhs).to(fact(x))` still produces an ordinary equation atom.

Use direct MeTTa source when matching, free variables, or several clauses state the problem most clearly. Use `@m.define` when supported Python control flow is the clearest source but the behavior should run as equations. Use `@m.op` when a Python library call or effect must stay in Python.

Compilation failures name the unsupported construct. The compiler does not hide an uncompiled fallback inside the equation.

The [Write MeTTa in Python guide](../guide/define) covers repeated clauses, generators, comprehensions, matching, and the supported subset. Next, add checked boundaries in [06. Types and casting](./06-types-and-casting).
