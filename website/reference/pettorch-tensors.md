# `pettorch.tensors`

Source: `python/pettorch/tensors.py`.

> Purpose: the tensor operations pettorch installs. The whole array set is
> petta.arrays, the library-agnostic layer over the array API standard, with
> torch as the constructor default; what remains here is only what genuinely
> is torch and not arrays: autograd controls and gelu. That split is the
> proof the general system carries the integration whole.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `install_tensor_ops`

```python
def install_tensor_ops(m) -> list[str]:
```

> The generic array set with torch constructing, plus torch's autograd.
