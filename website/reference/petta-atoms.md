# `petta.atoms`

Source: `python/petta/atoms.py`.

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
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

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

## `expr`

```python
def expr(*children: Any) -> Expr:
```

> An expression from parts, each encoded.

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

## `unify`

```python
def unify(pattern: Any, atom: Any) -> Mapping[str, Atom] | None:
```

> Match a pattern against an atom, returning bindings or None.
>
> One-way: variables on the pattern side bind; a variable on the atom side
> matches only the same variable. No occurs check, matching SWI's default
> and therefore the engine's.
