# 03. Equations and evaluation

An equation gives a matching expression a rewrite. The call `(double 21)` matches the left side `(double $x)`, binds `$x` to `21`, and rewrites through `(* 21 2)` to `42`.

![A double equation, its selected call, and the answer 42](/visuals/03-equations-and-evaluation.svg)

The repository's first example runs that exact rewrite:

```python
# Source runs through the engine's own reader and compiler; one answer list
# per ! directive, grounded values arriving as Python values.
check("run", m.run("(= (double $x) (* $x 2))\n!(double 21)"), [[42]])
```

Read `=` as a rewrite definition. It is not Python assignment and it is not an equality test. The engine uses `==` for a value comparison inside a computation.

The `!` directive starts evaluation. Source without `!` adds an atom or equation to the current space. Source with `!` evaluates its target and returns an answer group. One source string can contain several directives, so `run` returns an outer list of groups:

```python
def test_run_groups_answers_per_directive(metta):
    r = metta.run("!(+ 1 2)\n!(superpose (a b))")
    assert r == [[3], [S.a, S.b]]
```

The second directive has two answers. MeTTa nondeterminism enumerates the answers licensed by the program. Two equations for `(coin)` can therefore answer both `Heads` and `Tails`; it does not choose one at random.

The [Run and query guide](../guide/run-query) covers evaluation bounds, streaming, transactions, profiling, and other runtime controls. Next, cross the language boundary in [04. The Python bridge](./04-python-bridge).
