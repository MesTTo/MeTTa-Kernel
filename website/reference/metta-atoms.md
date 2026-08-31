# `metta.atoms`

Source: `extensions/python/metta/atoms.py`.

> Purpose: expose MeTTa atoms, the S/V/G factories, parsing, and matching.
>
> Guarantees:
>   - order_key matches the engine's msort across every public atom kind,
>     including float/integer ties, strings, opaque values, and the empty-list
>     atom [tested: test_order_key_matches_msort_across_kinds;
>     commit=b1de70215dd3f0c9d5437558c57c5911c13948b5]
>   - type and keyword builders produce stored terms while ``order_key`` and
>     Atom.__lt__ agree on elementwise expression order [tested:
>     test_typed_and_arrow_retire_49_raw_type_symbols,
>     test_keyword_builders_retire_53_raw_if_mentions, and
>     test_plain_sorted_uses_the_engines_elementwise_order; commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
>   - public atom classes retain the metta.atoms pickle path after internal
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
>     test_grounded_atoms_lift_python_operators_to_terms; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - if_ preserves both the engine's one-armed and three-armed forms [tested:
>     test_if_builder_accepts_the_one_armed_form; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - the canonical truth and unit atoms are public values [tested:
>     test_the_canonical_atoms_are_public_values;
>     commit=b1599bdc8201a04a3689c1a88707b6f4b53b4d22]
>   - seg() builds the named segment and refuses anything but a Variable, since
>     a non-variable second position is ordinary data to the engine [tested:
>     test_seg_builds_a_named_segment; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb]
>   - fresh() mints process-independent variable names for library-authored
>     patterns, so helper-local holes never capture caller names [tested:
>     test_fresh_variables_keep_library_patterns_hygienic; commit=46ae646e5efe14320c01e1e110d9cfd6cd0fc7e1]
>   - two-argument unify is symmetric and returns one normalized substitution
>     over variables from either operand [tested:
>     test_unify_binds_a_ground_term_and_pattern_in_both_orders,
>     test_unify_binds_variables_from_both_operands,
>     test_unify_path_compresses_long_alias_chains; commit=6917bef7ca902671999eafcae3a7a86db8f69723]
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
> :mod:`metta.wire`; ``ground([1, 2, 3])`` therefore carries one list by
> identity instead of turning it into an expression.

## `fresh`

```python
def fresh() -> Variable:
```

> Mint a variable for a library-authored pattern without name capture.

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

## `seg`

```python
def seg(variable: Any) -> Expression:
```

> Build the named segment ``(:seg $x)``, the variable's fifth face.
>
> A segment variable stands for a RUN of expression children rather than for
> one term, so ``space[(S.Order, seg(V.rest))]`` matches an Order of any
> length and each answer's ``rest`` column is the run it took. Bare ``...``
> is the anonymous spelling and every occurrence of it is its own variable; a
> named segment can repeat, and the second occurrence then has to take the
> same run.
>
> The fence is the law's own theorem, not caution: general sequence
> unification is infinitary (Kutsia, Journal of Symbolic Computation 42(3),
> 2007), so a pattern outside the three proved-finite fragments refuses and
> names the rule.

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
> Crossed through apply() rather than once(). metta_py_parse/2 already has
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
> before numbers, strings, opaque objects, the empty expression, symbols,
> and nonempty expressions
> [source: SWI-Prolog 10.1 Reference Manual, Standard Order of Terms].
>
> Two atoms that compare equal here are not necessarily the same atom: a key
> orders, `same_atom` decides identity.

## `substitute`

```python
def substitute(atom: Any, bindings: Mapping[str, Atom]) -> Atom:
```

> The atom with every bound VARIABLE replaced, keyed by variable name.
>
> The internal primitive, for callers that hold names rather than atoms: a
> result row's columns, and ``_match``'s directional bindings. An unbound
> variable stays itself, so a partial substitution is a narrower pattern
> rather than an error.
>
> ``Atom.subs`` is the public door and the one implementation. It is keyed by
> ATOM because a bare name cannot say which kind it means on a surface that
> has both: this function reads ``{"x": ...}`` as the VARIABLE $x while
> ``using=`` at the evaluation doors reads the same mapping as the SYMBOL x
> [measured 2026-08-31, on the source door and the term door alike]. Two
> meanings for one spelling is fine inside the library, where each caller
> knows which it holds, and is not something to publish.

## `unify`

```python
def unify(left: Any, right: Any) -> Mapping[Atom, Atom] | None:
```

> Unify two atoms symmetrically, returning bindings or ``None``.
>
> Variables in either operand bind. The returned substitution is normalized,
> so a chain such as ``x = y, y = a`` reports both names bound to ``a``.
> Anonymous ``_`` occurrences remain fresh and bind nothing. This host
> matcher retains its historical no-occurs-check behavior; four-argument
> conditional unification is the engine form exposed by ``metta.unify``.
>
> Keyed by the VARIABLES themselves, which is what ``Atom.subs`` accepts, so
> a substitution this produces is one the library can apply. A bare name
> cannot say whether it means a variable or a symbol, and this language has
> both: ``using={"x": 5}`` at the evaluation doors means the SYMBOL x.
