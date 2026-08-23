# `petta.atoms`

Source: `bindings/python/petta/atoms.py`.

> Purpose: expose PeTTa atoms, the S/V/G factories, parsing, and matching.
> Guarantees:
>   - type and keyword builders produce stored terms while ``order_key`` and
>     Atom.__lt__ agree on elementwise expression order [tested:
>     test_typed_and_arrow_retire_49_raw_type_symbols,
>     test_keyword_builders_retire_53_raw_if_mentions, and
>     test_plain_sorted_uses_the_engines_elementwise_order; commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
>   - public atom classes retain the petta.atoms pickle path after internal
>     module cuts [tested test_atoms_pickle_by_value,
>     test_atoms_cross_a_spawned_process_boundary]
>   - Atom.map transforms trees iteratively and validates replacements [tested
>     test_map_atoms_handles_depth_as_data_and_validates_transform_results]
>   - parse uses the engine reader and preserves source variable names [tested
>     test_parse_keeps_variable_names]
>   - engine results restore registered ampersand names as Space operands while
>     the public wire decoder keeps explicit s and p tags distinct [tested:
>     test_space_handles_are_term_operands_and_round_trip; commit=4e2398075da67bb2cbcc123a9fc1e078ecac6fbf]
>   - exact-type formatter registrations have exact removal counterparts [tested
>     test_object_repr_registrations_can_be_removed_exactly]
>   - the immutable operator lowering table is public data [tested:
>     test_the_operator_table_is_generated_from_one_source_with_no_holes;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - grounded atoms lift Python arithmetic to staged MeTTa terms [tested:
>     test_grounded_atoms_lift_python_operators_to_terms; commit=WORKTREE]
>   - if_ preserves both the engine's one-armed and three-armed forms [tested:
>     test_if_builder_accepts_the_one_armed_form; commit=WORKTREE]
>   - the canonical truth, unit, and context atoms are public values [tested:
>     test_the_canonical_atoms_are_public_values;
>     commit=b1599bdc8201a04a3689c1a88707b6f4b53b4d22]
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

## `arrow`

```python
def arrow(*positions: Any) -> Expression:
```

> Build an arrow type as data, mapping Python types through annotations.

## `typed`

```python
def typed(subject: Any, type_: Any) -> Expression:
```

> Build ``(: subject type)`` as data; annotations are accepted as types.

## `if_`

```python
def if_(condition: Any, consequent: Any, alternative: Any = _OMITTED) -> Expression:
```

> Build either engine ``if`` arity; Python ``if`` lowers inside define.

## `not_`

```python
def not_(value: Any) -> Expression:
```

> Build a quoted or stored ``not`` term.

## `and_`

```python
def and_(*values: Any) -> Expression:
```

> Build a quoted or stored ``and`` term.

## `or_`

```python
def or_(*values: Any) -> Expression:
```

> Build a quoted or stored ``or`` term.

## `in_`

```python
def in_(member: Any, container: Any) -> Expression:
```

> Build a quoted or stored ``in`` term.

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
> Atom.__lt__ delegates to this key, so explicit and plain sorting agree.
> The language's list-shaped expressions compare child by child; length is
> reached only when one expression is a prefix of the other. Variables come
> before numbers, symbols, strings, objects, and expressions
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
