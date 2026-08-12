## PeTTa

Efficient MeTTa language implementation in Prolog.

Please check out the [Wiki](https://github.com/patham9/PeTTa/wiki) for more information.

### Dependencies

- SWI-Prolog >= 9.3.x
- Python 3.x (for janus Python interop)

### Usage

Example run:

`time sh run.sh ./examples/nars_tuffy.metta`

### MORK and FAISS spaces

If MORK and FAISS is installed, execute `sh build.sh` to support MORK-based atom spaces and FAISS-based atom-vector spaces.

The following projects are cloned and built by build.sh:

**Repository:** [mork_ffi](https://github.com/patham9/mork_ffi) dependent on [trueagi-io/mork](https://github.com/trueagi-io/mork)

**Repository:** [faiss_ffi](https://github.com/patham9/faiss_ffi) dependent on [facebookresearch/faiss](https://github.com/facebookresearch/faiss)

### Python library

The `petta` package is a full Python surface for the engine. Install it with
`pip install .` (the runtime is bundled, so nothing else needs a checkout),
or use it in place from a clone with `PETTA_PATH` pointing at the tree.

Atoms are Python values. `S.likes` is the symbol `likes`, `V.x` is the
variable `$x`, and applying a symbol builds an expression, so structure never
costs an engine call:

```python
from petta import MeTTa, S, V

m = MeTTa()
m.run("(= (foo) boo) !(foo)")        # [[Sym('boo')]]
m.run("!(+ 40 2)")                   # [[42]]

m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
m.query(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
# Rows[x, y, z]([Row(x=Sym('Tom'), y=Sym('Bob'), z=Sym('Ann'))])
```

`run` returns one list of answers per `!` directive, computed by the engine's
own reader, compiler and evaluator, so pasted CLI programs behave
identically; a differential suite in `python/tests` holds the library to the
CLI's output program by program. Grounded answers compare as their Python
values, symbols stay symbols, and a Python object stored in a space comes
back as the very same object.

Python functions become MeTTa functions with a decorator. Annotations become
a type declaration, a generator is nondeterministic, and returning None
answers nothing:

```python
@m.op
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.op
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

Named spaces isolate both stored atoms and equations, each space compiling
into its own module; `(context-space)` names the space the current code runs
in. `m.derivation(atom)` builds proof trees naming the equations and stored
facts behind an answer, and `m.why(pattern)` explains an empty match. A
`%%metta` cell magic for the ordinary Python kernel ships as
`%load_ext petta.ipython`.

### PeTTorch

`pettorch` integrates PyTorch deeply in both directions (install with
`pip install .[torch]`). Tensors cross the boundary as themselves, so the
autograd graph survives the engine.

```python
import petta, pettorch

m = petta.MeTTa()
pettorch.install(m)
m.run("!(t-tolist (matmul (tensor ((1.0 2.0))) (tensor ((3.0) (4.0)))))")
# [[Expr('((11.0))')]]
```

An `nn.Module` becomes a MeTTa function with `pettorch.wrap`, so rules
decide which model runs. The other direction is `pettorch.MettaModule`: an
`nn.Module` whose forward pass evaluates MeTTa equations, its parameters
reachable from MeTTa through `(param name)` as the same live tensors, so an
ordinary optimizer trains a program written as equations:

```python
m.run("(= (predict $x) (t-sum (t* (param w) $x)))")
model = pettorch.MettaModule(m, "predict", params={"w": torch.zeros(2)})
optimizer = torch.optim.SGD(model.parameters(), lr=0.05)
loss = torch.nn.functional.mse_loss(model(x), target)
loss.backward()                      # gradients reach model.w
```

`pettorch.reflect` lowers a model's architecture into facts
(`nn-module`, `nn-child`, `nn-param`, `nn-param-shape`, `nn-linear`) that
rules can match, `pettorch.attach_optimizer` gives an optimizer MeTTa
spellings so a whole training loop can be MeTTa source, and
`pettorch.EmbeddingStore` registers `(name-knn $query $k)` as a
nondeterministic operation yielding `(key score)` pairs best-first, making
similarity a match modality beside structure.

Grounded host objects participate in the type system: `get-type` of a stored
tensor answers `Tensor` (then its base classes, nondeterministically, the way
MeTTa types already work), so a declared `(-> Tensor Tensor Tensor)` is
checked for real. The CLI-reachable half is `lib/lib_torch.metta`, plain
`py-call` wrappers usable from a `.metta` file with no Python-side setup; see
`examples/torch_lib.metta`.

### Extension libraries

Please check out [Extension libraries](https://github.com/trueagi-io/PeTTa/wiki/Extension-libraries) for a set of extension libraries that can be invoked from MeTTa files directly from the git repository.

Git imports retain the legacy URL-only, URL/build-command, and
URL/build-command/base-directory forms. For a reproducible detached checkout,
pass a fourth input in the order URL, build command, base directory, commit:

```metta
!(git-import! "https://example/repo.git" "" "./repos" "0123456789abcdef0123456789abcdef01234567")
```

Pinned imports accept only a full 40-character hexadecimal commit SHA;
abbreviated SHAs, branches, and tags are rejected.

## Notebooks, Servers, Browser

### Jupyter Notebook Support

A Jupyter kernel for PeTTa is available in a separate repository for interactive MeTTa development in notebooks.

**Repository:** [trueagi-io/jupyter-petta-kernel](https://github.com/trueagi-io/jupyter-petta-kernel)

Quick install:

```bash
# Set PETTA_PATH to this PeTTa installation
export PETTA_PATH=/path/to/PeTTa

# Clone and install the kernel
git clone https://github.com/trueagi-io/jupyter-petta-kernel.git
cd jupyter-petta-kernel
./install.sh
```

Please see the [jupyter-petta-kernel README](https://github.com/trueagi-io/jupyter-petta-kernel/blob/main/README.md) for detailed installation instructions and usage.

### MeTTa server

A HTTP server running MeTTa code is also available:

**Repository:** [MettaWamJam](https://github.com/trueagi-io/MettaWamJam)

Please see the [MettaWamJam README](https://github.com/trueagi-io/MettaWamJam/blob/main/README.md) for detailed installation instructions and usage.

### MeTTa in WASM

Since Swi-Prolog can be compiled to Web Assembly, one can embed PeTTa into websites.

Please see [Execution-in-browser](https://github.com/patham9/PeTTa/wiki/Execution-in-browser) for more information.
