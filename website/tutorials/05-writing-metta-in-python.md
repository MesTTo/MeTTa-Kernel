# 05. Writing MeTTa in Python

`@m.define` reads a Python function and adds its MeTTa equation to a space. Calling the decorated name evaluates through that space, `S.name(...)` builds a term explicitly, and `.py` keeps the ordinary Python function.

![A factorial equation and a selected call that answers 120](/visuals/05-writing-metta-in-python.svg)

The runnable definitions example starts with factorial:

```python
@m.define
def fact(n):                      # -> (= (fact $n)
    if n == 0:                    # ->      (if (py-eq $n 0)
        return 1                  # ->          1
    return n * fact(n - 1)        # ->          (* $n (fact (- $n 1)))))


check("equations run", m.run("!(fact 6)"), [[720]])
check("the Python twin agrees", fact.py(6), 720)
check("calling the name evaluates", fact(6), [720])
check("S builds the term", str(S.fact(6)), "(fact 6)")
```

The comment is the equation this body becomes, and you can read it back out
of the space with `m.self.atoms()` rather than take it on trust. Python's `==`
lowers to `py-eq` because Python's equality is not MeTTa's: `1 == 1.0` is True
in Python and False in MeTTa, where the numeric kinds stay apart.

Calling `fact(6)` runs the compiled equation and returns all engine answers. `S.fact(6)` builds `(fact 6)` as data, and `fact.py(6)` runs the Python reference directly. Inside an `@rules` generator, calls to defined objects stage scope-locally so `equation(lhs).to(fact(x))` still produces an ordinary equation atom.

Use direct MeTTa source when matching, free variables, or several clauses state the problem most clearly. Use `@m.define` when Python control flow is the clearest source but the behavior should run as equations, including `try`/`except`/`finally`, `raise`, dicts and sets, type aliases and `global`. Use `@m.op` when a Python library call or effect must stay in Python.

What the vocabulary lowers natively becomes equations; what it does not becomes a visible host island inside the equation, run per application, never at decoration time. The refusals that remain cite their ground in one of the two languages. An unresolvable name is Python's own NameError; a `nonlocal` targets a frame no stored equation outlives.

The [Write MeTTa in Python guide](../guide/define) covers repeated clauses, generators, comprehensions, matching, exceptions, and dicts as spaces. Next, add checked boundaries in [06. Types and casting](./06-types-and-casting).
