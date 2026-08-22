# `petta.atoms`

Source: `bindings/python/petta/atoms.py`.

> Purpose: expose PeTTa atoms, the S/V/G factories, parsing, and matching.
> Guarantees:
>   - public atom classes retain the petta.atoms pickle path after internal
>     module cuts [tested test_atoms_pickle_by_value,
>     test_atoms_cross_a_spawned_process_boundary]
>   - Atom.map transforms trees iteratively and validates replacements [tested
>     test_map_atoms_handles_depth_as_data_and_validates_transform_results]
>   - parse uses the engine reader and preserves source variable names [tested
>     test_parse_keeps_variable_names]
>   - engine results restore registered ampersand names as Space operands while
>     the public wire decoder keeps explicit s and p tags distinct [tested:
>     test_space_handles_are_term_operands_and_round_trip; commit=WORKTREE]
>   - exact-type formatter registrations have exact removal counterparts [tested
>     test_object_repr_registrations_can_be_removed_exactly]
>   - the immutable operator lowering table is public data [tested:
>     test_the_operator_table_is_generated_from_one_source_with_no_holes;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `ground`

```python
def ground(value: Any) -> Grounded:
```

> Carry a Python value whole, whatever it is.
>
> This is the FFI boxing door. Structural wire conversion lives in
> :mod:`petta.wire`; ``ground([1, 2, 3])`` therefore carries one list by
> identity instead of turning it into an expression.

## `parse`

```python
def parse(source: str) -> Atom:
```

> Read one form of MeTTa source into an atom, evaluating nothing.
>
> Backed by the engine's own reader, with one improvement over sread/2: the
> variable names the DCG collects are kept, so parse("(Parent $x Bob)")
> contains Variable('x') rather than a machine name, and the same pattern built
> with V.x compares equal.
>
> Crossed through apply() rather than once(). petta_py_parse/2 already has
> the functional shape, one ground input and one output, and every call that
> passes source text to eval(), run() or match() parses first, so this is a
> second crossing on top of the evaluation's own [measured 2026-08-16:
> eval("(structured (pair a b))") 517.02 inferences and 34.70us, against
> 241.01 and 10.60us for the same term prebuilt].

## `order_key`

```python
def order_key(atom: Atom) -> tuple:
```

> A sort key for atoms, in Prolog's standard order of terms.
>
>     sorted(atoms, key=order_key)
>
> A KEY rather than `__lt__`, because `<` already means something here:
> `S.a < S.b` builds the term `(< a b)`, which is what the operators are
> for, so `sorted()` over atoms raised "(&lt; a c) is a comparison TERM, not a
> truth value". That message is right and the order it refuses to invent
> exists anyway, in the language underneath: variables before numbers before
> symbols before strings before compounds, and compounds by arity, then by
> functor, then argument by argument
> [source: SWI-Prolog 10.1 Reference Manual, Standard Order of Terms].
>
> Two atoms that compare equal here are not necessarily the same atom: a key
> orders, `same_atom` decides identity.

## `substitute`

```python
def substitute(atom: Any, bindings: Mapping[str, Atom]) -> Atom:
```

> The atom with every bound variable replaced, unify's companion:
> substitute(pattern, unify(pattern, atom)) is the matched instance.
> An unbound variable stays itself, so a partial substitution is a
> narrower pattern rather than an error.

## `unify`

```python
def unify(pattern: Any, atom: Any) -> Mapping[str, Atom] | None:
```

> Match a pattern against an atom, returning bindings or None.
>
> One-way: variables on the pattern side bind; a variable on the atom side
> matches only the same variable. No occurs check, matching SWI's default
> and therefore the engine's.
