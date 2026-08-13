# `pettorch.modules`

Source: `python/pettorch/modules.py`.

> Purpose: the two directions a model crosses the boundary, built on the
> general interface. wrap() is petta.integrate.wrap_callable plus the nn.Module
> reflector; MettaModule packages a MeTTa forward pass as an nn.Module so it
> slots into optimizers and training loops, its parameters reached from MeTTa
> through an ordinary registered operation. The autograd graph survives
> because tensors cross by identity, a property of the boundary, not of torch.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `wrap`

```python
def wrap(m, name: str, module, *, arities: list[int] | None = None):
```

> Register a model (or any callable over tensors) as a MeTTa function.
>
>     pettorch.wrap(m, "classify", model)
>     m.run("!(t-argmax (classify (tensor (1.0 2.0))))")
>
> An nn.Module also reflects its architecture into facts and lands as
> (nn-wrapped name &lt;module&gt;), so rules route between models symbolically.

## `MettaModule`

```python
def MettaModule(metta, function: str, params: dict[str, Any] | None = None,
                param_op: str = "param"):
```

> An nn.Module whose forward pass is a MeTTa program.
>
>     m.run("(= (predict $x) (t-sum (t* (param w) $x)))")
>     model = pettorch.MettaModule(m, "predict", params={"w": torch.zeros(2)})
>     optimizer = torch.optim.SGD(model.parameters(), lr=0.05)
>     loss = loss_fn(model(x), target)   # forward runs the equations
>     loss.backward()                    # gradients reach model.w
>
> Parameters are ordinary nn.Parameters registered on the module, reached
> from MeTTa through (param name) as the very same objects, which is what
> keeps the graph connected. torch.compile cannot trace through the
> engine; forward runs eager. A factory rather than a class, so importing
> pettorch never imports torch.
