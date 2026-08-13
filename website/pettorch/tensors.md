# Tensors

Install the optional PyTorch surface with `pip install .[torch]`. `pettorch.install(m)` installs the generic `petta.arrays` operation set with PyTorch as the constructor default, then adds the operations that are specific to PyTorch.

```python
import petta, pettorch

m = petta.MeTTa()
pettorch.install(m)
m.run("!(t-tolist (matmul (tensor ((1.0 2.0))) (tensor ((3.0) (4.0)))))")
# [[Expr('((11.0))')]]
```

Array recognition uses DLPack. Operation semantics follow the Python array API through `array-api-compat`. NumPy, PyTorch, CuPy, JAX, Dask, and other conforming arrays therefore use one MeTTa operation set. The constructor default decides what `tensor`, `zeros`, `ones`, and the other constructors create. Operations dispatch on the library of their array argument.

Mixed-library binary operations convert the right operand through DLPack. `(t-as $x numpy)` requests a conversion. `get-type` answers the array's own classes and `DLTensor`, so one declaration over `DLTensor` applies across libraries.

Tensors cross the engine boundary by identity. A stored tensor returns as the same object, which preserves its autograd graph. PyTorch-specific operations include gradient controls, `gelu`, and device conversion.

See [`petta.arrays`](../reference/petta-arrays) for the shared operation layer and [`pettorch.tensors`](../reference/pettorch-tensors) for the PyTorch additions.
