# Pettorch

Pettorch connects PyTorch to PeTTa through PeTTa's public integration surface. Arrays use `petta.arrays`, losses and optimizers use `petta.integrate`, and the package adds the behavior that is specific to PyTorch: autograd operations, module wrappers, training helpers, architecture reflection, and neural predicates.

## Install from the checkout

Choose and install the PyTorch build for your CPU, CUDA, or ROCm environment with the [official PyTorch selector](https://pytorch.org/get-started/locally/). Then run this command from the pettorch checkout:

```bash
pip install .
```

Pettorch's `pyproject.toml` defines no `torch` extra and no runtime dependencies. PyTorch is deliberately chosen by the user because the correct build depends on the machine. The package imports PyTorch only when a PyTorch-backed feature is first used.

## Run the first tensor expression

In Python, import `petta` and `pettorch`, create `m = petta.MeTTa()`, and call `pettorch.install(m)`. Then evaluate `m.run("!(t-tolist (matmul (tensor ((1.0 2.0))) (tensor ((3.0) (4.0)))))")`. The expression multiplies a one-by-two tensor by a two-by-one tensor and returns `((11.0))` as a MeTTa expression.

`pettorch.install(m)` installs the shared array operations with PyTorch as the constructor default, then adds the PyTorch-specific operations. Tensors cross the engine boundary as the same live objects, so their autograd graph remains attached.

## Surface

| Surface | Direction |
|---|---|
| `install` | Register tensor operations, losses, and model reflection. |
| `wrap` | Expose a callable `torch.nn.Module` as a MeTTa function and reflect its structure. |
| `MettaModule` | Wrap a MeTTa forward function as a `torch.nn.Module` with live parameters. |
| `neural_predicate` | Register a network as a weighted relation over class atoms. |
| `reflect` | Write module, child, parameter, shape, and linear-layer facts into a space. |
| `attach_optimizer` and `train_step` | Expose optimizer effects or run one checked training step. |
| `EmbeddingStore` | Re-export the shared array-backed nearest-neighbour store. |

A wrapped PyTorch module lets MeTTa rules choose which model runs. `MettaModule` goes the other way: its `forward` evaluates a named MeTTa function, and parameters are available to equations through `(param name)`. The forward pass must answer exactly one tensor.

`neural_predicate` sends a network's softmax output through `petta.measure.weighted_relation`. Its answers are `(probability class)` pairs, so the same measure operations can select, normalize, or sample them.

Reflection writes ordinary facts such as `nn-module`, `nn-child`, `nn-param`, `nn-param-shape`, and `nn-linear`. Rules can match model structure beside application facts.

See the shared [`petta.arrays`](../reference/petta-arrays), [`petta.integrate`](../reference/petta-integrate), and [weighted relations](../reasoning/weighted-relations) pages for the PeTTa side of these seams.

## Repository status

The audited pettorch checkout at commit `a501f6e` has no configured remote, and no separate public pettorch repository is currently available to link. The public [PeTTa repository](https://github.com/trueagi-io/PeTTa) describes pettorch as a sibling project. A pettorch URL should be added here only after that checkout has an actual public remote.
