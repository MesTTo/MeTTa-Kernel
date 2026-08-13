# `pettorch.reflect`

Source: `python/pettorch/reflect.py`.

> Purpose: nn.Module architecture as MeTTa knowledge, registered as a
> reflector on the general reflection registry: wrap() and reflect() dispatch
> through petta.integrate, and this module only teaches it what a torch module
> looks like inside.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: fact vocabularies for more layer families (Conv,
>     attention) as programs need them; Linear covers the demos today.

The entries below reproduce the source signatures and docstrings.

## `register`

```python
def register() -> None:
```

> Teach the general reflection registry about nn.Module, once.

## `reflect`

```python
def reflect(m, root_name: str, module) -> int:
```

> Write the module's architecture into the space; returns the fact count.
>
> Dispatches through the general registry, so pettorch.reflect and
> petta.integrate.reflect are the same call once register() has run.
