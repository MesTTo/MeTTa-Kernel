<!--
Purpose: document 04. The Python bridge against the current Python surface.
Guarantees:
  - Python expression construction uses Expression(children), the one-iterable
    ordered assembly door [tested: test_expression_assembles_one_ordered_atom_from_an_iterable; commit=WORKTREE]
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None.
-->

# 04. The Python bridge

Choose the bridge method from the value you already have. Use `run` for MeTTa source text, `eval` for an atom already built in Python, and `query` for bindings from stored facts.

![Age facts and a selected Rows query](/visuals/04-python-bridge.svg)

The core tests put the three value shapes side by side:

```python
def test_eval(metta):
    assert metta.eval(S["car-atom"](Expression((1, 2, 3)))) == [1]
    assert metta.eval(S.superpose(Expression((S.x, S.y)))) == [S.x, S.y]
    assert metta.eval(Expression((S["+"], 20, 22))) == [42]


def test_source_strings_are_parsed_where_atoms_are_expected(m):
    m.add("(likes Ada Coffee)")
    assert m.query("(likes $who Coffee)")[0].who == S.Ada
```

`eval` returns the answers for one target atom. `query` returns bindings as named rows. `run` keeps one answer list per `!` directive because a source string can contain several directives.

The boundary also goes from MeTTa into Python. Register a Python callable with `@m.op`, then evaluate its registered name like any other MeTTa function:

```python
def test_det_op_composes_with_equations(metta):
    name = unique("dbl")

    @metta.register_op(name=name)
    def double(x: int) -> int:
        return 2 * x

    assert metta.run(f"!({name} 21)") == [[42]]
    quad = unique("quad")
    assert metta.run(f"(= ({quad} $x) ({name} ({name} $x)))\n!({quad} 5)") == [[20]]
```

Annotations tell the bridge which grounded Python values to pass and which type declaration to register. The Python callable runs only when evaluation reaches its term. Until then, the expression is data.

Use [Python functions as MeTTa functions](../guide/python-functions) for annotations, generators, defaults, objects, and unregistration. Next, compile supported Python syntax into equations in [05. Writing MeTTa in Python](./05-writing-metta-in-python).
