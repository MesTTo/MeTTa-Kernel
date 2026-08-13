# Training

A `MettaModule` participates in ordinary PyTorch training. Parameters reached through `(param name)` are the same live tensors registered on the module, so gradients produced by the MeTTa forward pass reach the optimizer.

```python
import torch

m.run("(= (predict $x) (t-sum (t* (param w) $x)))")
model = pettorch.MettaModule(m, "predict", params={"w": torch.zeros(2)})
optimizer = torch.optim.SGD(model.parameters(), lr=0.05)
x, target = torch.tensor([1.0, 2.0]), torch.tensor(3.0)
loss = torch.nn.functional.mse_loss(model(x), target)
loss.backward()                      # gradients reach model.w
```

`pettorch.install_loss_ops(m)` registers `mse-loss`, `cross-entropy`, and `l1-loss` from `torch.nn.functional`. `pettorch.attach_optimizer(m, optimizer, name)` exposes the optimizer's `step` and `zero_grad` methods with effectful MeTTa names.

`pettorch.train_step(m, loss_function, optimizer, *batch)` evaluates one named loss term, requires exactly one tensor answer, clears gradients, backpropagates, steps the optimizer, and returns the loss as a float. The loss computation stays in equations that the engine can match and explain, while PyTorch performs differentiation.

See [`pettorch.train`](../reference/pettorch-train) for the exact operation names and error conditions.
