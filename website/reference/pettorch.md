# `pettorch`

Source: `python/pettorch/__init__.py`.

> Purpose: pettorch, PyTorch integrated with PeTTa as one instantiation of
> the general interface: petta.arrays carries the whole tensor operation set
> with torch as the constructor default, petta.integrate carries losses,
> optimizers, wrapping and reflection, and what remains genuinely torch is
> autograd, gelu and the nn.Module packaging of a MeTTa forward pass. The
> package is the existence proof that the general system loses nothing.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None
>
>     import petta, pettorch
>
>     m = petta.MeTTa()
>     pettorch.install(m)
>     m.run("!(t-tolist (matmul (tensor ((1.0 2.0))) (tensor ((3.0) (4.0)))))")
>     # [[Expr('((11.0))')]]
>
> Importing pettorch is free; torch loads on first use.

The entries below reproduce the source signatures and docstrings.

## `install`

```python
def install(m) -> list[str]:
```

> Register the whole torch integration on the shared engine.
>
> Idempotent per process, because operations are process-wide the way
> every MeTTa function is. Returns the registered names.

## `installed`

```python
def installed() -> bool:
```

No docstring is defined.
