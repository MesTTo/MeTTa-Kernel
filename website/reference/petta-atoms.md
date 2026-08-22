# `petta.atoms`

Source: `bindings/python/petta/atoms.py`.

> Purpose: public atom construction, parsing, traversal, equivalence, and matching.
> Guarantees:
>   - public atom classes retain the petta.atoms pickle path after internal
>     module cuts [tested test_atoms_pickle_by_value,
>     test_atoms_cross_a_spawned_process_boundary]
>   - map_atoms transforms trees iteratively and validates replacements [tested
>     test_map_atoms_handles_depth_as_data_and_validates_transform_results]
>   - parse uses the engine reader and preserves source variable names [tested
>     test_parse_keeps_variable_names]
>   - formatter registrations have exact removal counterparts [tested
>     test_object_repr_registrations_can_be_removed_exactly]
>   - the immutable operator lowering table is public data [tested:
>     test_the_operator_table_is_generated_from_one_source_with_no_holes;
>     commit=613f35974fa98746552dba584ad66082fdd1f3c7]
>   - the canonical truth, unit, and context atoms are public values [tested:
>     test_the_canonical_atoms_are_public_values; commit=WORKTREE]
>   - Expression preserves one iterable's order while assembling it into one
>     atom [tested: test_expression_assembles_one_ordered_atom_from_an_iterable;
>     commit=WORKTREE]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `sym`

```python
def sym(name: str) -> Sym:
```

> A symbol by name, for names that are not Python identifiers.

## `var`

```python
def var(name: str) -> Var:
```

> A variable by name.

## `val`

```python
def val(value: Any) -> Gnd:
```

> Carry a Python value whole, whatever it is.
>
> MeTTa has no list type: encode([1, 2, 3]) is the expression (1 2 3), so
> petta.val([1, 2, 3]) is how to say this particular list is one grounded
> value. It crosses by reference, comes back as the same object, and
> unifies by identity.

## `Expression`

```python
def Expression(children: Iterable[Any]) -> Expr:
```

> Assemble one ordered expression from an iterable of atoms or values.
>
> Answers are a multiset whose execution order carries no meaning. This
> constructor crosses into an object-level expression, where position and
> multiplicity are data and therefore preserved exactly. It consumes the
> iterable once [source: ai-python-conventions.md section 3.15;
> commit=WORKTREE].

## `pretty`

```python
def pretty(atom: Any, width: int = 78) -> str:
```

> The atom laid out for reading: a subterm prints inline when it fits
> the remaining width, and otherwise breaks after its head with each
> child on its own line two deeper, the classic s-expression
> convention. The engine's (pretty-atom $x) is the same layout on the
> MeTTa side, so a dump reads identically from either tier.

## `parse`

```python
def parse(source: str) -> Atom:
```

> Read one form of MeTTa source into an atom, evaluating nothing.
>
> Backed by the engine's own reader, with one improvement over sread/2: the
> variable names the DCG collects are kept, so parse("(Parent $x Bob)")
> contains Var('x') rather than a machine name, and the same pattern built
> with V.x compares equal.
>
> Crossed through apply() rather than once(). petta_py_parse/2 already has
> the functional shape, one ground input and one output, and every call that
> passes source text to eval(), run() or match() parses first, so this is a
> second crossing on top of the evaluation's own [measured 2026-08-16:
> eval("(structured (pair a b))") 517.02 inferences and 34.70us, against
> 241.01 and 10.60us for the same term prebuilt].

## `variables`

```python
def variables(atom: Atom) -> list[str]:
```

> Variable names in an atom, in first-appearance order. Iterative:
> depth is data.

## `is_ground`

```python
def is_ground(atom: Atom) -> bool:
```

> True when the atom carries no variables.

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

## `map_atoms`

```python
def map_atoms(atom: Atom, transform: Callable[[Atom], Atom]) -> Atom:
```

> Transform every node in an atom tree, children before parents.
>
> The walk is iterative, so nesting depth remains data rather than a Python
> recursion limit. A no-op transform preserves each unchanged Expr object.
> Nodes returned by transform are final for this pass and are not walked
> again.

## `alpha_eq`

```python
def alpha_eq(a: Atom, b: Atom) -> bool:
```

> Equality up to consistent renaming of variables, PeTTa's =alpha.
>
> A named function rather than ==, because two atoms must not compare
> differently depending on which variable names they happen to carry.

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
