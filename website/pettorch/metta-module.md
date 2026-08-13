# `MettaModule`

Models cross the boundary in two directions. `pettorch.wrap(m, name, module)` registers a callable model as a MeTTa function and reflects an `nn.Module` into facts. Rules can then choose which model runs.

The example registers two linear experts and routes between them with MeTTa equations:

```python
# Symbolic routing over neural experts: which model runs is a rule.
double = torch.nn.Linear(1, 1, bias=False)
triple = torch.nn.Linear(1, 1, bias=False)
with torch.no_grad():
    double.weight.fill_(2.0)
    triple.weight.fill_(3.0)
pettorch.wrap(m, "expert-double", double)
pettorch.wrap(m, "expert-triple", triple)
m.run(
    "(route small expert-double)\n(route large expert-triple)\n"
    "(= (size-of $x) (if (< (t-item $x) 10.0) small large))\n"
    "(= (moe $x) (let $s (size-of $x)\n"
    "  (let $e (match (context-space) (route $s $r) $r) ($e $x))))"
)
check("routed small", m.run("!(t-item (moe (tensor (3.0))))"), [[6.0]])
check("routed large", m.run("!(t-item (moe (tensor (30.0))))"), [[90.0]])
```

`pettorch.MettaModule(m, function, params=...)` goes the other way. It creates an `nn.Module` whose `forward` evaluates the named MeTTa function. Parameters are registered as ordinary `nn.Parameter` objects and are available inside the equations through `(param name)`.

The forward pass must produce exactly one tensor. If the program is nondeterministic, reduce its answers inside MeTTa before returning. Forward runs eagerly because `torch.compile` cannot trace through the engine.

See [`pettorch.modules`](../reference/pettorch-modules) for both directions and their failure conditions.
