# `pettorch.train`

Source: `python/pettorch/train.py`.

> Purpose: training as MeTTa, assembled from the general integration
> toolkit: losses arrive through module_ops over torch.nn.functional, an
> optimizer's step and zero_grad through wrap_object, and train_step runs one
> whole update with the forward pass in MeTTa. Nothing here is machinery of
> its own; that is the point.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `install_loss_ops`

```python
def install_loss_ops(m) -> list[str]:
```

> mse-loss, cross-entropy and l1-loss, straight off torch.nn.functional.

## `attach_optimizer`

```python
def attach_optimizer(m, optimizer, name: str = "optim"):
```

> (name-step!) and (name-zero!): the optimizer's own methods as
> operations, effect convention included (a Python None answers True, the
> engine's own spelling for an effectful builtin).

## `train_step`

```python
def train_step(m, loss_function: str, optimizer, *batch) -> float:
```

> One update where the forward pass is MeTTa: returns the loss value.
>
> What to compute stays equations the engine can match, derive and
> explain; how to differentiate it is torch's.
