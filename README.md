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
costs an engine call. Operators build terms too: `V.age >= 18` is the
expression `(>= $age 18)` and `&`, `|`, `~` compose the boolean terms,
while arithmetic on grounded values stays ordinary Python arithmetic:

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
type declarations in the engine's own idiom. A TypeVar declares
parametrically, so `def first_of(items: Sequence[A]) -> A` is
`(: first-of (-> Expression $a))`. A Union declares one arrow per member,
and the members superpose the way the checker already reads repeated
declarations. `Callable[[int], int]` declares the arrow `(-> Number Number)`
and `tuple[int, str]` the elementwise `(Number String)`. A dataclass, Enum
or plain class in a signature becomes a declared type of its own, its
constructor arrow read from the field annotations. A generator is
nondeterministic, and returning None answers nothing, which is why an
Optional return declares the value type:

```python
@m.op
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.op
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

Queries carry guards, bounds, assumptions and preparation. A `where=` term
is evaluated by the engine per match, `limit=` bounds the answers,
`assuming` holds facts for a block alone, and `prepare` wires a query once
to solve many times, with `given=` facts existing for that call only:

```python
m.add(S.Age(S.Tom, 62), S.Age(S.Bob, 40))
m.query(S.Age(V.p, V.n), where=(V.n >= 60) & (V.n <= 70))
# Rows[p, n]([Row(p=Sym('Tom'), n=Gnd(62))])

with m.assuming(S.Parent(S.Ann, S.Zoe)):
    m.query(S.Parent(S.Ann, V.c))    # Rows[c]([Row(c=Sym('Zoe'))])

grand = m.prepare(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
grand.solve()
# Rows[x, y, z]([Row(x=Sym('Tom'), y=Sym('Bob'), z=Sym('Ann'))])
```

Named spaces isolate both stored atoms and equations, each space compiling
into its own module; `(context-space)` names the space the current code runs
in. `m.derivation(atom)` builds proof trees naming the equations and stored
facts behind an answer, and `m.why(pattern)` explains an empty match. A
`%%metta` cell magic for the ordinary Python kernel ships as
`%load_ext petta.ipython`.

### Examples

`python/examples/` holds fourteen runnable, self-verifying integrations,
from first steps through SQL spaces, the one array layer, attention as
matching, FabricPC predictive coding, evolution in a space, PLN, standing
queries as actors, custom matchers and soft unification; the test suite
runs them all, so the folder cannot drift. Start there. The engine-side
libraries this work added (`lib_measure`, `lib_soft`) test themselves in
the engine's own convention, `examples/*.metta` with `!(test ...)`, run by
both `test.sh` and the python suite.

### Writing MeTTa in Python

The `@m.define` decorator compiles a Python function into MeTTa equations,
read as syntax and lowered deterministically. It exists because fluency is
real: people and language models alike write Python readily and
s-expressions haltingly, and the compiled subset lets that fluency produce
PeTTa programs.

```python
@m.define
def fact(n):
    if n == 0:
        return 1
    return n * fact(n - 1)

m.run("!(fact 5)")       # [[120]]
fact.py(5)               # 120: the ordinary Python twin, kept callable
```

Clauses stack the way MeTTa equations do, with a literal default reading as
the head pattern and the compiler deriving the first-match guards the
stacked Python means:

```python
@m.define
def fib(n=0):
    return 0

@m.define
def fib(n=1):
    return 1

@m.define
def fib(n):
    return fib(n - 1) + fib(n - 2)   # m.run("!(fib 10)") -> [[55]]
```

Annotations declare types, and `m.fn("car-atom")` turns any engine function
into an ordinary Python callable.

The subset is Python as Python means it. Rebinding works (`x = x + 1`
compiles through static single assignment), `while` and `for` become their
own tail-recursive equations running in constant stack, nested defs
lambda-lift, a generator compiles to nondeterminism (each yield one
answer, `yield from` and `for` included), a lambda to the engine's own
`|->`, comprehensions (several `for` clauses too) to `map-atom` and
`filter-atom`, and `match(parent(gp, mid), ...)` to a match against the
running space, lowercase pattern names binding as variables. Semantics are
exact where the engine's functions differ from Python's: truthiness
decides every test, `and`/`or` answer the deciding operand, `==` holds
across `4 == 4.0`, `in` is membership and substring, indexing and slices
take Python's negatives, `round` banks, f-strings format; each definition
lists the runtime-backed operations it leaned on as `.runtime_ops`. Both
decorators share one naming policy (underscores read as hyphens). Anything
outside the subset is a refusal naming the construct, the line, and what
to write instead, never a silent fallback; a body only the engine can run
(a match, a constructor) gets a twin that says so instead of a NameError.
Every other definition keeps its Python twin callable as `.py`, stacked
clauses dispatching first-match; a CSmith-style fuzzer generates random
programs in the subset and holds engine and twin to identical answers.

### Integrating any library

`petta.integrate` is the interface a Python library implements to work
deeply with the engine, and the toolkit that makes it a page of code. The
frame behind it: MeTTa's own semantics subsume the concepts libraries are
made of, so integration means mapping onto them rather than inventing
machinery.

| the library has | it becomes |
|---|---|
| functions, methods | grounded MeTTa functions; a call is a reduction |
| objects with state | grounded atoms with identity |
| tables, frames, indexes | spaces; a query is a match |
| dispatch (routes, handlers) | equations over one head; the catch-all is the 404 |
| generators, search, retrieval | nondeterminism; each yield one answer |
| schemas, records, enums | constructor expressions and `(: ...)` declarations |
| configuration, structure | facts that rules match over |

The toolkit covers each row: `module_ops(m, math, ["sqrt", "gcd"])`
registers callables in bulk; `wrap_object` turns an instance's methods into
operations (a Python None answers True, the engine's convention for an
effect); `register_type` teaches the two-way translator in the pytree shape
(Enums become symbols with declarations, dataclasses become constructor
expressions, both by default); `register_object_type` makes a protocol a
type; `install_reflection_ops` gives `(py-field $obj $name)` in both modes,
enumeration included; and a `SpaceProvider` implements a space in Python, so
`(match &db (users $id $name) ...)` runs against a database with bound
positions pushed down as a WHERE clause while the engine keeps unification,
and therefore soundness, for itself. `petta.integrations.duckdb_space`
ships as the worked SQL instance. A package advertises itself through the
`petta.integrations` entry-point group, and `m.integrate(module)` installs
anything defining `install_petta(m)`.

This leans on Python's metaprogramming the way SQLAlchemy and Pydantic do:
introspected signatures become arities and types, the AST becomes equations,
protocols become types, and entry points become discovery.

Beyond operations and spaces, the surface carries: `@m.type`, which
declares an Enum, dataclass or NamedTuple into a space with constructor
declarations and one accessor equation per field, `rows.build(col, Person)`
rebuilding answers as instances; `m.run(src, using={"df": df})`, naming
host values by bare symbol with identity intact; `m.subscribe(pattern,
callback)`, a standing query delivered inside the very write that matched
it (or queued for `drain()`), which is the actors-and-pub-sub reading of a
space; `m.save(path)` writing a space back as loadable source; and
`petta.current_space()`, callable from inside any operation to learn the
space whose program called it.

### Custom matchers and the measure algebra

Matching is open: `petta.matching.matcher(m, name, score=..., generate=...)`
registers any notion of closeness as a two-mode MeTTa function, scoring a
bound candidate or generating unbound ones best first, always answering
`(score value)` pairs. `install_fuzzy` ships lexical closeness (difflib);
an `EmbeddingStore.matcher()` is the semantic instance, with an exact
faiss backend when the package is present. `lib/lib_measure.metta` is the
algebra those pairs feed, pure MeTTa in the shape of annotated
disjunctions: `ws-normalize`, `ws-softmax` with a temperature, `ws-best`,
`ws-top`, `ws-sample!`, `ws-collapse`, `ws-expect`. So
`(ws-softmax (collapse (semmatch $q $x)) 0.5)` is attention through your
matcher, and `lib/lib_soft.metta` extends it over terms: Sessa's weak
unification, structure crisp, symbols close to declared degrees
(`petta.soft.link_store` materializes them from embeddings), variables
binding as ever. `petta.measure.weighted_relation` closes the loop from the
producing side: any callable answering one weight per class registers as a
dual-mode relation in the same `(weight value)` shape, so a lookup table, a
heuristic scorer or a neural network all feed the algebra identically.
`python/bench.py` is the performance harness that keeps all of this
measured.

On top of that closeness sits a prover, `petta.soft.prove`: backward
chaining where every unification is soft, the reading of End-to-End
Differentiable Proving (Rocktaschel and Riedel 2017) and IBM's Braid. A
goal proves through stored facts, through `=` rules whose bodies prove in
turn, through conjunction goals conjunct by conjunct, and through ground
guards the engine itself evaluates; degrees aggregate by minimum, every
step must clear the threshold, and the answer is a `Proof` carrying the
substitutions, the aggregate similarity and every step:

```python
from petta import soft

k = MeTTa().fresh_space()
k.add(S["parent-of"](S.homer, S.bart), S["father-of"](S.abe, S.homer))
k.run("(= (grandpa-of $x $y) (and (father-of $x $z) (parent-of $z $y)))")
soft.similar(k, "grandpa-of", "grandfather-of", 0.9)

proof = soft.prove(k, S["grandfather-of"](V.who, S.bart))
proof.substitutions["who"], proof.similarity     # (Sym('abe'), 0.9)
```

`grandfather-of` never appears in the knowledge, only `grandpa-of` does;
the declared similarity carries the proof across, and `proof.steps` names
every rule, fact and guard on the way.

### Arrays: every DLPack library, one operation set

`petta.arrays` carries tensors for every library speaking the standard
protocols, not one: recognition is DLPack (`__dlpack__`), semantics are the
Python array API standard through array-api-compat, so the same MeTTa
functions serve NumPy, PyTorch, CuPy, JAX and whatever conforms next.
`install(m, default=numpy)` chooses only what the constructors build in;
every other operation dispatches on its argument's own library, a mixed
call converts the right operand through `from_dlpack`, `(t-as $x numpy)`
converts on request, and `get-type` of any array answers its own classes
plus `DLTensor`, the protocol type, so one declared
`(-> DLTensor DLTensor DLTensor)` holds across libraries. The embedding
store and its nondeterministic `(name-knn $q $k)` retrieval live here too,
running on whichever library the vectors arrived from.

### PeTTorch

`pettorch` integrates PyTorch in both directions (install with
`pip install .[torch]`), and it is deliberately thin: the whole tensor set
is `petta.arrays` with torch as the constructor default, losses come
through `module_ops` over `torch.nn.functional`, optimizers through
`wrap_object`, architecture reflection through the reflector registry, and
what remains genuinely torch is autograd, gelu and the nn.Module packaging.
The package is the existence proof that the general interface carries a
deep integration whole. Tensors cross the boundary as themselves, so the
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
import torch

m.run("(= (predict $x) (t-sum (t* (param w) $x)))")
model = pettorch.MettaModule(m, "predict", params={"w": torch.zeros(2)})
optimizer = torch.optim.SGD(model.parameters(), lr=0.05)
x, target = torch.tensor([1.0, 2.0]), torch.tensor(3.0)
loss = torch.nn.functional.mse_loss(model(x), target)
loss.backward()                      # gradients reach model.w
```

`pettorch.neural_predicate` is DeepProbLog's neural predicate: a network
registered as a probabilistic relation, its softmaxed forward pass
answering `(probability class)` pairs that feed the measure algebra, so
`ws-best` is the argmax reading and `ws-sample!` the stochastic one. It is
`petta.measure.weighted_relation` with the network as the callable; pass
`with_grad=True` and the probabilities stay on the autograd graph, the
DeepProbLog training reading:

```python
network = torch.nn.Linear(2, 3, bias=False)
with torch.no_grad():
    network.weight.copy_(torch.tensor([[0.1, 0.9], [2.0, 0.1], [0.2, 0.2]]))
pettorch.neural_predicate(m, "guess", network, [S.zero, S.one, S.two])

m.run("!(import! (context-space) (library lib_measure))")
m.run("!(ws-best (collapse (guess (tensor (1.0 0.0)))))")   # [[Sym('one')]]
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
