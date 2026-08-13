# `petta.ops`

Source: `python/petta/ops.py`.

> Purpose: registration of Python callables as MeTTa functions. Reads the
> signature for arities (defaults yield several), auto-detects nondeterminism
> (a generator function is one), derives a MeTTa type declaration from the
> annotations, and registers the whole thing with the engine through shim.pl.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: keyword-argument call forms once PeTTa itself grows a
>     spelling for them; today MeTTa call sites are positional.

The entries below reproduce the source signatures and docstrings.

## `metta_type_for`

```python
def metta_type_for(annotation: Any) -> str:
```

> The MeTTa type a Python annotation names.

## `type_atom_for`

```python
def type_atom_for(annotation: Any) -> Atom:
```

> The annotation as one atom; the first alternative when several
> superpose. type_atoms_for is the full mapping.

## `type_atoms_for`

```python
def type_atoms_for(annotation: Any) -> list[Atom]:
```

> Every MeTTa type an annotation names, mapped by the representation
> its values take when they cross. Alternatives superpose the way the
> checker already treats multiple declarations, so a Union contributes
> one atom per member and the checker collects. The cases:
>
> - a TypeVar becomes the engine's own type VARIABLE, so
>   head(items: Sequence[A]) -&gt; A is (-&gt; Expression $a) and the checker
>   propagates the binding per call;
> - Union[A, B] and A | B answer both members' atoms;
> - Optional[T] is Union[T, None], and None crosses as a NoneType handle,
>   so it answers T's atoms plus NoneType (the declaration builder drops
>   NoneType from return position, where returning None answers nothing);
> - Callable[[A, B], R] is the arrow (-&gt; A B R), the type a declared
>   function symbol itself answers to get-type;
> - tuple[A, B] is the elementwise (A B), which is get-type's own answer
>   for a raw pair; tuple[A, ...] and other Sequences are Expression;
> - a class names its declared type, the name get-type answers for its
>   instances, whether they cross as constructor terms or as handles;
> - an abstract origin whose values have no one representation stays
>   %Undefined%, the engine's own spelling for uncommitted.

## `declaration_exprs`

```python
def declaration_exprs(name: str, arg_annotations: list, ret_annotation: Any) -> list[Expr]:
```

> Every (: name (-&gt; ...)) atom a signature declares: the cross product
> of each argument's alternatives with the return's, one declaration per
> combination, superposing for the checker exactly as a Union reads,
> refused past DECLARATION_LIMIT. NoneType leaves the return
> alternatives, because returning None answers nothing rather than a
> value; a return that was only None declares %Undefined%.

## `referenced_classes`

```python
def referenced_classes(annotations: Iterable[Any]) -> list[type]:
```

> Every user class an annotation tree mentions, so registration can
> declare the types it references: a type in MeTTa is a declaration, and
> a signature naming Point should make (: Point ...) exist rather than
> leave the name dangling.

## `class_declarations`

```python
def class_declarations(cls: type) -> list[Expr]:
```

> The (: ...) atoms that make a class a MeTTa type: the translator's
> own declarations for an Enum, dataclass or NamedTuple, constructor
> arrows and member typings, derived from the class itself. A plain
> class needs NO declaration: its instances already answer the class
> name to get-type through the engine's MRO typing bridge, so emitting
> one would only restate what the engine figures out on its own.

## `resolved_annotations`

```python
def resolved_annotations(fn: Callable) -> dict[str, Any]:
```

> The function's annotations as real types, never text: under
> `from __future__ import annotations` the raw __annotations__ are
> strings, which would all read as %Undefined% and silently drop the
> declared types. Unresolvable annotations are a hard error naming the
> function.

## `register`

```python
def register(
    runtime,
    fn: Callable,
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    space: str = "&self",
    arities: list[int] | None = None,
) -> Callable:
```

> Make fn callable from MeTTa. Returns fn unchanged.
>
> A generator function registers as nondeterministic: each yield is one
> answer, and MeTTa's collapse, superpose and let compose over them. A
> plain function is deterministic; returning None or raising Decline
> answers nothing. Defaults yield one registration per reachable arity;
> a variadic callable names its call forms with arities=[...].

## `unregister`

```python
def unregister(runtime, name: str) -> None:
```

> Remove every arity of a registered operation, and every declaration
> registration added, so nothing keeps describing a function that no
> longer exists.

## `registered`

```python
def registered() -> dict[str, Operation]:
```

> The live registry, name to operation.
