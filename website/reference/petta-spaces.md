# `petta.spaces`

Source: `python/petta/spaces.py`.

> Purpose: space combinators on the public seam: union, readonly, mapped,
> and overlay compose existing spaces into new ones with zero engine changes,
> each an ordinary SpaceProvider, which is the point: the seam proves its
> composability by having the combinators be users of it.
> Guarantees:
>   - union and readonly implement no write operation, so the engine's own
>     capability refusal answers add-atom on them [tested
>     test_union_refuses_writes_through_the_engine]
>   - mapped presents only atoms unifying its inner shape, both directions
>     derived from the one declaration [tested
>     test_mapped_presents_and_writes_through_the_declaration]
>   - overlay reads both layers and writes, removes, and clears the front
>     only, ChainMap's own rule [tested test_overlay_routes_writes_to_front]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

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
