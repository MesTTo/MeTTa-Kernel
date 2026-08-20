# `petta.casting`

Source: `bindings/python/petta/casting.py`.

> Purpose: runtime typecasting against the engine's own type discipline.
> cast(space, value, type) answers value, narrowed to its Python-most
> spelling, when the engine admits it as that type: the exact
> ('get-type' then 'get-metatype') acceptance the translator compiles
> for a typed argument position, run in the space's scope so its ':'
> declarations and &self's both answer. Protocol types registered
> through petta.integrate.register_object_type participate, which makes
> this duck typing through the type system: an object satisfying the
> predicate casts to the protocol's name. A refused cast raises
> CastError naming the value's actual type candidates, the loud spelling
> of what a typed call does silently (a mismatched argument reduces to
> nothing). Targets the translator never checks (Atom, %Undefined%, _)
> pass unchecked here too, and a Python type spells its MeTTa reading:
> bool is Bool before int is Number, str is String, any other class its
> own name, the names get-type itself answers.
> Guarantees:
>   - a concrete Python target type remains the cast's static return type [tested
>     test_target_type_overloads_preserve_the_requested_class]
>   - the target is positional-only, so its implementation name is not API
>     [tested test_cast_target_is_positional_only]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `CastError`

```python
class CastError(PettaError, TypeError):
```

> A cast the engine's type discipline refuses.

## `cast`

```python
def cast(space: Any, value: Any, type_: Any, /) -> Any:
```

> Answer value, narrowed, when space's type discipline admits it as
> type_; raise CastError naming its actual types otherwise.
>
>     m.run("(: Ann Person)")
>     assert m.cast(S.Ann, "Person") is S.Ann
>     assert m.cast(3, int) == 3
