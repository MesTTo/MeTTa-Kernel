<!--
Purpose: explain MeTTa declarations, annotation-derived arrows, and checked casts.
Guarantees: operation examples use the canonical Space.op decorator.
[tested: npm run docs:build; commit=WORKTREE]
-->

# 06. Types and casting

Types are optional atoms. A declaration such as `(: Ann Person)` gives a value a type. A function declaration such as `(: age (-> Person Number))` says that `age` accepts a `Person` and answers a `Number`.

![Value and function type declarations beside a get-type query](/visuals/06-types-and-casting.svg)

Python annotations can create function declarations at registration time:

```python
def test_annotations_declare_types(metta):
    name = unique("typed")

    @metta.op(name=name)
    def typed_op(x: int) -> int:
        return x

    assert metta.run(f"!(get-type ({name} 1))") == [[S.Number]]
```

`get-type` asks what type the current space can derive. The arrow's final atom is the result type; preceding atoms are input types. A typed call that refuses an argument can disappear as an empty branch during nondeterministic evaluation.

A function's type has to be an arrow, and a source that gets this wrong is refused rather than accepted quietly. `(: inc Number)` beside `(= (inc $x) (+ $x 1))` reads like a type but is one: it types the symbol `inc`, not a call to it, so every `(inc ...)` compiles with no check and a wrong argument surfaces wherever it finally breaks, deep inside `+` rather than at `inc`'s own door. Writing `(: inc (-> Number Number))` is what puts the check on the call. The engine refuses the first form when it loads the source:

```
(: inc Number) is not an arrow, so it types the symbol inc and not a call to
it: every (inc ...) compiles with no check at all, and a wrong argument
surfaces wherever it finally breaks instead of here. Write (: inc (-> ...)),
or (: inc %Undefined%) to say inc is deliberately untyped.
```

Three things pass. A name may carry several declarations, MeTTa's ad-hoc polymorphism, and one arrow among them is enough. `%Undefined%` says the function is deliberately untyped. And a declaration for a name nothing defines is data, not a defect, which is what lets `(: nars-belief (--> Cat Animal))` mean inheritance rather than a mistyped arrow.

At a Python boundary, use `m.cast` when refusal must raise instead:

```python
def test_declared_symbols_cast_by_their_declarations(m):
    m.run("(: Ann Person)")
    assert m.cast(S.Ann, "Person") is S.Ann
    with pytest.raises(CastError) as caught:
        m.cast(S.Ann, "Robot")
    assert "Person" in str(caught.value)
```

The successful cast returns the same symbol. The failed cast names the type the space knows. Declarations are space-relative, so another space can carry a different type environment.

See [`petta.casting`](../reference/petta-casting) for structural targets, protocol types, and Python type spellings. Next, inspect execution and support in [07. Seeing your program](./07-seeing-your-program).
