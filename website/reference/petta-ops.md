# `petta.ops`

Source: `bindings/python/petta/ops.py`.

> Purpose: registration of Python callables as MeTTa functions. Reads the
> signature for arities (defaults yield several), auto-detects nondeterminism
> (a generator function is one), derives a MeTTa type declaration from the
> annotations, and registers the whole thing with the engine through shim.pl.
> Guarantees:
>   - registration distinguishes a MeTTa function name from its declaration
>     space [tested test_public_context_types_are_distinct]
>   - full annotations become ordinary claims in the declaration space
>     [tested: test_the_four_containers_share_one_parameterised_treatment;
>      commit=4224c26819d90b9e03efdaef78cb573b91729295]
>   - overload stubs each contribute their declared arrow and annotation claims
>     [tested: test_every_advanced_annotation_reaches_metta_as_a_target_symbol;
>      commit=4224c26819d90b9e03efdaef78cb573b91729295]
>   - unreachable **kwargs refuses and a typed zero-parameter operation still
>     emits its return arrow
>     [tested: test_each_remaining_annotation_shape_refuses_or_carries;
>      commit=ff4ac16f07a6e373e79ed0eae0a4c2d64cb92550]
>   - callable code flags, through partials, wrappers, bound methods, and
>     callable objects, classify generators and refuse coroutine functions
>     before registration changes any engine or registry state [tested:
>     test_register_op_reads_co_flags_and_refuses_or_awaits;
>     commit=9b1b808f6b8d8aa6a8080c13092fa73ce7893aaa]
>   - every documented operation owns its portable @doc atom in the
>     declaration space, independent of typed=, under the same transactional
>     lifecycle and reference count as type declarations [tested:
>     test_every_register_op_writes_its_declaration_and_get_doc_answers;
>     commit=eda90565cfb66417c62e654b0f3e7b55351366c5]
>   - each registered arity owns the arrow for exactly the arguments that call
>     form accepts, including repeated variadic annotations [tested:
>     test_every_array_operation_is_typed_and_a_shape_is_a_constraint;
>     commit=e5246578ba61fb5efc9d2282bade50479946e34a]
>   - Annotated MeTTa parameters retain metadata without losing engine
>     injection [tested:
>     test_two_values_of_one_base_type_are_distinguishable_by_their_metadata;
>     commit=WORKTREE]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: keyword-argument call forms once PeTTa itself grows a
>     spelling for them; today MeTTa call sites are positional.

The entries below reproduce the source signatures and docstrings.

## `record`

```python
def record(cls: type) -> type:
```

> The declarative-record wiring, attrs' and pydantic's shape: one
> decorator over a dataclass, NamedTuple, or Enum and the class
> converts both ways, its `(: ...)` declarations land in &self, and it
> serves as a cast and query(into=) target.
>
>     @petta.record
>     @dataclass
>     class Edge:
>         a: str
>         b: str
>
> Conversion registers immediately (an unregistrable class fails at
> the decorator, not at first use). The declarations are engine-side
> atoms, so they land the moment an engine exists: immediately when
> one is already booted, or on the first MeTTa construction otherwise,
> which is what lets the decorator run at import time without booting
> anything. Every underlying registration call stays public for the
> classes that need custom shapes.

## `declare_recorded`

```python
def declare_recorded() -> None:
```

> Land every pending recorded class's declarations in &self; a
> no-op when nothing is pending, called by MeTTa construction so a
> decorator that ran before any engine existed still declares.

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

## `register`

```python
def register(
    runtime,
    fn: Callable[_P, _R],
    *,
    name: str | None = None,
    typed: bool = True,
    raw: bool = False,
    pass_atoms: bool = False,
    space: str = _DEFAULT_SPACE,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
    pure: bool = False,
) -> Callable[_P, _R]:
```

> Make fn callable from MeTTa. Returns fn unchanged.
>
> A generator function registers as nondeterministic: each yield is one
> answer, and MeTTa's collapse, superpose and let compose over them. A
> plain function is deterministic; returning None or raising Decline
> answers nothing. Defaults yield one registration per reachable arity;
> a variadic callable names its call forms with arities=[...].
>
> inverse supplies the BACKWARDS direction, so the operation can stand in a
> pattern position the way a MeTTa equation does. It takes the result and
> returns the arguments, as a tuple, or the bare value at arity one; a
> generator enumerates every preimage, and None or Decline means there is
> none. It only ever runs when the arguments are not ground and the result
> is, so a forward call never reaches it and an operation without one
> compiles exactly what it compiled before.
>
> pure declares that the operation has no effect a cache could hide, which
> is what lets it appear in a `(tabled ...)` or memoized body. It is an
> allow-list on purpose: an operation that does not say so is refused there
> by name, loudly, rather than cached and quietly wrong.

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
