# Model reflection

`pettorch.reflect(m, root_name, module)` lowers an `nn.Module` architecture into ordinary facts and returns the number written. `pettorch.wrap(...)` performs the same reflection for wrapped modules.

The current vocabulary records:

| Fact | Meaning |
|---|---|
| `nn-module` | a named module and its type symbol |
| `nn-child` | a parent, child name, and qualified child name |
| `nn-param` | a live parameter tensor on a named module |
| `nn-param-shape` | the dimensions of that parameter |
| `nn-linear` | the input and output features of a linear layer |

The reflector is registered through `petta.integrate`. Once registered, `pettorch.reflect` and `petta.integrate.reflect` dispatch through the same registry. Rules can query architecture facts with ordinary matching, alongside any facts produced by the rest of the application.

The current layer-specific vocabulary covers `Linear`. Module, child, parameter, and parameter-shape facts apply to every reflected module.

See [`pettorch.reflect`](../reference/pettorch-reflect) for the vocabulary source and [`petta.integrate`](../reference/petta-integrate) for the general reflector registry.
