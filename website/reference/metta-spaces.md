# `metta.spaces`

Source: `bindings/python/metta/spaces.py`.

> Purpose: space views and combinators on the public seam. Object views,
> union, readonly, mapped, and overlay are ordinary SpaceProvider instances;
> the same engine route therefore matches a live object or composes existing
> spaces without hardcoded integration paths.
> Guarantees:
>   - view presents mappings and zero-based sequences through one kv relation
>     and sets as members, reading the Python object afresh for every query
>     [tested: test_view_is_a_live_queryable_space; commit=b1de70215dd3f0c9d5437558c57c5911c13948b5]
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
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - provider queries and bridge declarations retain directional pattern
>     matching after public ``unify`` becomes symmetric [tested:
>     test_mapped_repeated_variable_pattern_stays_sound;
>     commit=6917bef7ca902671999eafcae3a7a86db8f69723]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `view`

```python
def view(obj: Any):
```

> Return an attached live space over a dict, set, or sequence.
>
> Dictionaries image as ``(kv key value)``. Sequences use that same relation
> with zero-based integer keys, matching Python's indices; a value-bound
> query therefore answers every matching index. Sets image as raw members.
> External mutations are visible on the next query.

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

> Yield one field atom per readable public field of the object.

### `ObjectView.match`

```python
def match(self, pattern: Atom) -> Iterator[Atom]:
```

> Yield candidate field atoms for *pattern*, narrowed by root and field name.

### `ObjectView.add`

```python
def add(self, atom: Atom) -> None:
```

> Write one ``(relation <object> <field> <value>)`` atom via ``setattr``.

## `object_view`

```python
def object_view(obj: Any, *, relation: str | Symbol = 'py-field') -> ObjectView:
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
>     m._register_space(metta.spaces.union(kb, rules), "&all")
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
>     view = metta.spaces.mapped(kb, "(bridge (edge $a $b) (triple $a linked-to $b))")
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
