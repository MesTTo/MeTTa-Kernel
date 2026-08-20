# `petta.spaces`

Source: `bindings/python/petta/spaces.py`.

> Purpose: space views and combinators on the public seam. Object views,
> union, readonly, mapped, and overlay are ordinary SpaceProvider instances;
> the same engine route therefore matches a live object or composes existing
> spaces without hardcoded integration paths.
> Guarantees:
>   - union and readonly implement no write operation, so the engine's own
>     capability refusal answers add-atom on them [tested
>     test_union_refuses_writes_through_the_engine]
>   - mapped presents only atoms unifying its inner shape, both directions
>     derived from the one declaration [tested
>     test_mapped_presents_and_writes_through_the_declaration]
>   - overlay reads both layers and writes, removes, and clears the front
>     only, ChainMap's own rule [tested test_overlay_routes_writes_to_front]
>   - object_view reads live fields, joins with stored atoms through union, and
>     turns an added py-field atom into setattr [tested:
>     test_a_query_joins_stored_atoms_with_live_object_fields;
>     commit=WORKTREE]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `ObjectView`

```python
class ObjectView(SpaceProvider):
```

> One live Python object presented as ``(py-field obj name value)``.
>
> Enumeration names the object's public fields. A bound field may also be
> served through ``getattr``, which lets an object with ``__getattr__``
> answer the mode it actually supports without pretending it can enumerate.
> Adding the same atom shape writes the value with ``setattr``.

### `ObjectView.atoms`

```python
def atoms(self) -> Iterator[Atom]:
```

No docstring is defined.

### `ObjectView.match`

```python
def match(self, pattern: Atom) -> Iterator[Atom]:
```

No docstring is defined.

### `ObjectView.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

## `object_view`

```python
def object_view(obj: Any, *, relation: str | Sym = 'py-field') -> ObjectView:
```

> Present one object as a live, writable provider.
>
> Compose it with stored facts through ``spaces.union(stored, view)`` and
> register the result like any other provider. Register the view itself
> when MeTTa should write its fields through ``add-atom``.

## `union`

```python
def union(*spaces: Any) -> _Union:
```

> A set of spaces read as one, writes refused by capability.
>
>     m.register_space(petta.spaces.union(kb, rules), "&all")
>     m.run("!(match &all (edge $a $b) $b)")
>
> Every member's candidates answer; duplicates across members are
> answers twice, the multiset reading a union of multisets has.

## `readonly`

```python
def readonly(inner: Any) -> _ReadOnly:
```

> The inner space, reads only; writes meet the capability refusal.

## `mapped`

```python
def mapped(inner: Any, declaration: Any) -> _Mapped:
```

> A shape view over ANY space, from one declaration:
>
>     view = petta.spaces.mapped(kb, "(bridge (edge $a $b) (triple $a linked-to $b))")
>
> presents the inner space's (triple ...) atoms as (edge ...) atoms,
> both directions derived from the pattern pair by unification, the
> tables bridge with WHERE replaced by unify. Renames, projections,
> and legacy-shape adapters stop being custom providers and become
> this one line. Adds map right-to-left; removal maps the pattern
> through; atoms the declaration does not map are invisible here and
> untouched there.

## `overlay`

```python
def overlay(front: Any, back: Any) -> _Overlay:
```

> Both layers read as one; every write lands on front. The
> explicitly chosen form union() refuses to be: ChainMap semantics
> for spaces, deletes not forwarded to back.

## `diff`

```python
def diff(a: Any, b: Any) -> tuple[list[Atom], list[Atom]]:
```

> What digest() cannot say: HOW two spaces differ.
>
> Answers (only_in_a, only_in_b), the multiset difference over
> enumeration, so a space holding an atom twice against one holding it
> once differs by the one copy. Alpha-equivalent atoms count as the
> same atom, digest()'s own equivalence, and each side's extras come
> back in that side's enumeration order. Both arguments are anything
> the combinators accept: a MeTTa handle or a provider. Each side is
> enumerated exactly once, so a live space is compared at one moment.
