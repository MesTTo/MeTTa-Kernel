# `metta.ops`

Source: `bindings/python/metta/ops.py`.

> Purpose: registration of Python callables as MeTTa functions. Reads the
> signature for arities (defaults yield several), auto-detects nondeterminism
> (a generator function is one), derives a MeTTa type declaration from the
> annotations, and registers the whole thing with the engine through shim.pl.
> Guarantees:
>   - class declaration has no process-global ``record`` registry or second
>     decorator spelling [tested:
>     test_define_absorbs_class_declaration_and_frees_space_type;
>     commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
>   - registration distinguishes a MeTTa function name from its declaration
>     space [tested: test_canonical_context_types_replace_public_newtypes;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - registration asks the engine grammar whether the requested name reads as
>     one symbol and refuses before reflecting or registering anything [tested:
>     test_register_op_refuses_a_name_metta_cannot_read;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - implicit operation names apply the total underscore-to-hyphen map while
>     explicit name= remains exact [tested: test_op_uses_the_define_name_ladder;
>     commit=b1de70215dd3f0c9d5437558c57c5911c13948b5]
>   - full annotations become ordinary claims in the declaration space
>     [tested: test_the_four_containers_share_one_parameterised_treatment;
>      commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - overload stubs each contribute their declared arrow and annotation claims
>     [tested: test_every_advanced_annotation_reaches_metta_as_a_target_symbol;
>      commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - unreachable **kwargs refuses and a typed zero-parameter operation still
>     emits its return arrow
>     [tested: test_each_remaining_annotation_shape_refuses_or_carries;
>      commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - callable code flags, through partials, wrappers, bound methods, and
>     callable objects, classify generators and route coroutine functions to
>     future-space dispatch
>     before registration changes any engine or registry state [tested:
>     test_register_op_reads_co_flags_and_refuses_or_awaits;
>     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
>   - generator signatures supply positional and sparse-dict relation row names
>     after injected engine parameters are removed [tested:
>     test_sparse_relational_dict_candidates_bind_parameter_names;
>     commit=6917bef7ca902671999eafcae3a7a86db8f69723]
>   - every documented operation owns its portable @doc atom in the
>     declaration space, independent of type annotations, under the same transactional
>     lifecycle and reference count as type declarations [tested:
>     test_every_register_op_writes_its_declaration_and_get_doc_answers;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - each registered arity owns the arrow for exactly the arguments that call
>     form accepts, including repeated variadic annotations [tested:
>     test_every_array_operation_is_typed_and_a_shape_is_a_constraint;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - Annotated MeTTa parameters retain metadata without losing engine
>     injection [tested:
>     test_two_values_of_one_base_type_are_distinguishable_by_their_metadata;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - transport, evaluation order, typing, and purity are expressed by op,
>     type, and effect atoms rather than boolean decorator flags [tested:
>     test_no_decorator_flag_changes_the_return_shape_and_declarations_are_atoms;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - every registration publishes exactly one canonical five-rank effect and
>     missing metadata refuses before engine mutation [tested:
>     test_unclassified_operation_refuses_with_all_five_effect_remedies,
>     test_every_effect_rank_registers_and_reflects; commit=acb40f1912f131ae088083d1af29b4b283019bea]
>   - the first Python owner refuses to adopt a source-owned declaration, while
>     later Python owners share the declaration reference count
>     [tested: test_a_duplicate_declaration_names_the_first_one;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - the returned staging wrapper carries its registration identity through
>     functools.wraps chains so mutually exclusive definition doors can refuse
>     before mutation [tested:
>     test_cache_over_an_operation_refuses_before_definition_registration;
>     commit=8d6131a9d9902c67ce8cac71e96e8362a8713561]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `class_declarations`

```python
def class_declarations(cls: type) -> list[Expression]:
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
    fn: Callable[P, R],
    *,
    name: str | None = None,
    transport: Literal['encoded', 'raw'] = 'encoded',
    effect: EffectClass | str | None = None,
    declarations: Iterable[Atom] = (),
    space: str = _DEFAULT_SPACE,
    arities: list[int] | None = None,
    inverse: Callable | None = None,
) -> Callable[P, R]:
```

> Make fn callable from MeTTa. Returns fn unchanged.
>
> A generator function registers as nondeterministic: each yield is one
> answer, and MeTTa's collapse, superpose and let compose over them. An exact
> tuple yield is a positional relational candidate and an exact dict yield
> is its sparse parameter-name spelling: the engine unifies each row against
> the call, so ground arguments filter and variables bind through the same
> implementation. Use ``Answer(value=...)`` when a generator intentionally
> answers an exact tuple or dict value. Relational rows require encoded
> transport.
> A plain function is deterministic; returning None or raising NotReducible
> answers nothing. Defaults yield one registration per reachable arity; a
> variadic callable names its call forms with arities=[...].
>
> inverse supplies a distinct result-to-arguments implementation for an
> ordinary result-producing operation. It takes the result and returns the
> arguments, as a tuple, or the bare value at arity one; a generator
> enumerates every preimage, and None or NotReducible means there is none. It
> only ever runs when the arguments are not ground and the result is, so a
> forward call never reaches it. A relational tuple/dict generator needs no
> inverse because its one implementation already binds every direction.
>
> Python annotations derive type atoms and Atom parameters receive syntax
> before evaluation. `transport="raw"` derives raw_det/raw_many in the
> operation's `(op ...)` fact. Effect metadata is required; ``effect=`` is
> the canonical input and names the strongest observable capability of the
> operation. Existing effect declaration atoms remain a compatibility input.
> Additional declaration atoms are owned for
> the operation's complete lifecycle: type atoms live in its declaration
> space, while its canonical effect row and other policy atoms live in
> &petta and can be matched there. Only ``pureStructural`` enters the
> compatibility allow-list for tabled or memoized bodies.

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
