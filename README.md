<!--
Purpose: introduce MeTTa, its narrow Python surface, and the commands needed to use and develop it.
Guarantees: every Python code block executes against the documented public API.
[tested: python -m pytest bindings/python/tests/repository/test_readme.py -q; commit=3cfbe0d7417b1c453c2dc12d47e2e47e7de461f7]
-->

## MeTTa

Efficient MeTTa language implementation in Prolog.

Please check out the [Wiki](https://github.com/patham9/PeTTa/wiki) for more information.
Contributor setup, gates, and measurement rules are in [DEVELOPING.md](DEVELOPING.md),
and what a contribution has to be is in [CONTRIBUTING.md](CONTRIBUTING.md).
Report a vulnerability privately, the way [SECURITY.md](SECURITY.md) describes,
rather than in an issue.

### Lineage

This is Patrick Hammer's MeTTa implementation. Its canonical repository is
[trueagi-io/PeTTa](https://github.com/trueagi-io/PeTTa), begun under
[patham9/PeTTa](https://github.com/patham9/PeTTa), where the Wiki still
lives. The `python-library` branch develops the `metta` Python module on
top of the engine: the engine's behaviour is the upstream contract, held by
a gate that runs every shipped example through both the engine and the
library and requires identical verdicts, and the Python surface is this
branch's own. `backends/mork/mork_ffi/` vendors
[patham9/mork_ffi](https://github.com/patham9/mork_ffi) over
[trueagi-io/mork](https://github.com/trueagi-io/mork) for the optional
MORK backend.
Release changes are recorded in [CHANGELOG.md](CHANGELOG.md). Citation metadata
is available in [CITATION.cff](CITATION.cff).

### Python quick start

From a checkout, install the Python package and run a query:

```bash
python -m pip install .
```

```python
from metta import S, V, space

m = space()
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
rows = m.match(S.Parent(S.Tom, V.child))
assert rows.to_dicts() == [{"child": "Bob"}]
```

The [Python guide](https://trueagi-io.github.io/PeTTa/guide/) starts with the
atom model and builds through queries, equations, types, and integrations.

### Dependencies

- SWI-Prolog >= 9.3.x
- Python >= 3.12 (for janus Python interop)

### Usage

Example run:

`time sh run.sh ./examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/09-nars_tuffy.metta`

### MORK and FAISS spaces

`sh build.sh` builds the MORK backend, which gives you MORK-based atom spaces.
The crate itself ships in this tree, at `backends/mork/mork_ffi`; what the
script clones, beside the repository and at validated revisions, is what that
crate builds against by relative path:

**Repository:** [trueagi-io/MORK](https://github.com/trueagi-io/MORK)

**Repository:** [Adam-Vandervorst/PathMap](https://github.com/Adam-Vandervorst/PathMap)

FAISS-based atom-vector spaces come from a MeTTa library rather than a backend,
so the engine fetches it when a program asks for it instead of the build script
cloning it:

```metta
!(git-import! "https://github.com/patham9/faiss_ffi" "build.sh")
```

That line is `examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/07-git_import2.metta`,
which lands the checkout under `repos/`. Its dependency is
[facebookresearch/faiss](https://github.com/facebookresearch/faiss).

### Python library

The `metta` module is a full Python surface for the engine. The runtime is
bundled, so nothing else needs a checkout. You can also use it in place from a
clone with `METTA_PATH` pointing at the tree. Install optional integrations by
feature:

```bash
pip install "pymetta[arrays]"       # array API, NumPy, and FAISS
pip install "pymetta[dataframes]"   # pandas and polars result conversion
```

Configure process-wide limits before creating the first engine. Stack and
heartbeat settings freeze after startup because SWI-Prolog owns them for the
process. Declaration and row-display limits remain live:

```python
import logging
import metta

metta.config.configure(
    declaration_limit=256,
    display_rows=50,
)
logging.basicConfig(level=logging.DEBUG)
logging.getLogger("metta").setLevel(logging.DEBUG)
```

The same settings accept `METTA_STACK_LIMIT`, `METTA_HEARTBEAT_INTERVAL`,
`METTA_DECLARATION_LIMIT` and `METTA_DISPLAY_ROWS` as positive decimal
integers. Set `metta.config.stack_limit` and
`metta.config.heartbeat_interval` before creating the first engine when you
configure them in Python. The package installs only a `NullHandler`, so
applications choose where `metta.*` lifecycle and recovery records go.

Atoms are Python values. `S.likes` is the symbol `likes`, `V.x` is the
variable `$x`, and applying a symbol builds an expression, so structure never
costs an engine call. Operators build terms too: `V.age >= 18` is the
expression `(>= $age 18)` and `&`, `|`, `~` compose the boolean terms,
while arithmetic on grounded values stays ordinary Python arithmetic:

```python
from metta import S, V, space

m = space()
m.run("(= (foo) boo) !(foo)")        # [[Symbol('boo')]]
m.run("!(+ 40 2)")                   # [[Grounded(42)]]

m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
m.match(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
# Rows[x, y, z]([Row(x=Symbol('Tom'), y=Symbol('Bob'), z=Symbol('Ann'))])
```

`term.map(transform)` rebuilds an atom tree from the leaves upward.
Its iterative walk handles deeply nested terms without a Python recursion
limit, and leaves unchanged expression objects intact.

`metta.engine().self` names the shared `&self` space. Use `metta.space()` to
create an anonymous handle, or `with metta.space() as scratch:` when the
space should be dropped on leaving the block.
`load()` adds a program to the current space and keeps what is already there.

`run` returns one list of answers per `!` directive, computed by the engine's
own reader, compiler and evaluator, so pasted CLI programs behave
identically; a differential suite in `bindings/python/tests` holds the library to the
CLI's output program by program. Grounded answers compare as their Python
values, symbols stay symbols, and a Python object stored in a space comes
back as the very same object.

Python functions become MeTTa functions with a decorator. Each registration
declares its effect as `pureStructural`, `readOnlyLookup`,
`nondeterministicReadOnly`, `writesState`, or `oracleIO`; a composed plan takes
the strongest class. Annotations become type declarations in the engine's own
idiom. A TypeVar declares
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
@m.op(effect="pureStructural")
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.op(effect="nondeterministicReadOnly")
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

`m.unregister_op(name)` removes every arity registered under that name.

Queries carry guards, bounds, assumptions and preparation. A `where=` term
is evaluated by the engine per match, `limit=` bounds the answers,
`assuming` holds facts for a block alone, and `prepare` wires a query once
to solve many times, with `given=` facts existing for that call only:

```python
m.add(S.Age(S.Tom, 62), S.Age(S.Bob, 40))
m.match(S.Age(V.p, V.n), where=S[">="](V.n, 60) & S["<="](V.n, 70))
# Rows[p, n]([Row(p=Symbol('Tom'), n=Grounded(62))])

with m.assuming(S.Parent(S.Ann, S.Zoe)):
    m.match(S.Parent(S.Ann, V.c))    # Rows[c]([Row(c=Symbol('Zoe'))])

grand = m.prepare(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
grand.solve()
# Rows[x, y, z]([Row(x=Symbol('Tom'), y=Symbol('Bob'), z=Symbol('Ann'))])
```

An empty result returned directly by `match()` retains its patterns. Call
`rows.why()` to distinguish a pattern miss, an incompatible join, and a
`where` guard that rejected every joined row. The explanation reads the
space's current state.

Tables cross both ways on the same reading: `metta.tables.add(m, head, source)`
reads any tabular source by the interface it offers (polars `iter_rows`,
pandas `itertuples`, a mapping of columns, any iterable of rows) into
`(head v1 .. vn)` facts, and `rows.table()` answers the dict of columns
every DataFrame constructor takes.

Named spaces isolate both stored atoms and equations, each space compiling
into its own module; `(context-space)` names the space the current code runs
in. `m.derivation(atom)` builds proof trees naming the equations and stored
facts behind an answer, and `m.why(pattern)` explains an empty match. A
`%%metta` cell magic for the ordinary Python kernel ships as
`%load_ext metta.ipython`.

The library also describes itself into `&metta`, a space of its own:
`(op name arity kind)` for every registered operation, `(defined space
name)` for every `@define` function, `(subscription space pattern on)` for
every standing query, each removed when its subject goes. It is an ordinary
space, so MeTTa programs can query the library's whole surface, and the
composition runs the other way too: a Python subscription on `&metta`
reacts to control atoms a MeTTa program writes there, which is steering the
integration from inside MeTTa, no fork needed.

### Two more paradigms in the common tongue, as examples

MeTTa is built to be a lingua franca, and the examples folder carries two
whole paradigms translated into it on the core surface alone, deliberately
as examples rather than package modules, since the point is what the core
already carries. `bindings/python/examples/integration/web_routes.py` builds FastAPI's
routing semantics in some eighty lines: an app is a space, the route table
is facts, a request is a term, dispatch is unification in registration
order, path parameters are typed variables, the 404 is the absence of a
match and the 422 a parameter refusing its type, and a MeTTa program
extends the running table by adding a `(route ...)` fact whose handler is
an equation. `bindings/python/examples/integration/multishot_solving.py` builds clingo's
multi-shot solving (Gebser et al., arXiv 1705.09811) in two short classes:
a part is a parameterized program template grounded once per
instantiation, an external is a truth toggled between solves, and the
incremental loop grounds one more step and solves again while the world
persists. Both examples verify themselves in the test suite.

### Examples

`bindings/python/examples/` holds thirteen runnable, self-verifying integrations,
grouped by basics, operations, data, integration, reasoning, and live systems.
They run from first steps through SQL spaces, array interoperability, evolution
in a space, PLN, standing queries as actors, custom matchers,
FastAPI-shaped web routes and clingo-shaped multi-shot solving; the test
suite runs them all, so the folder cannot drift. The torch examples
(attention as matching, FabricPC, deep routing) travel with the pettorch
repository. Start there. The engine-side
libraries this work added (`lib_measure`, `lib_soft`) test themselves in
the engine's own convention, `examples/*.metta` with `!(test ...)`, run by
both `test.sh` and the python suite.

### Writing MeTTa in Python

The `@m.define` decorator compiles a Python function into MeTTa equations,
read as syntax and lowered deterministically. It exists because fluency is
real: people and language models alike write Python readily and
s-expressions haltingly, and the compiled subset lets that fluency produce
MeTTa programs.

```python
@m.define
def fact(n):
    if n == 0:
        return 1
    return n * fact(n - 1)

m.run("!(fact 5)")       # [[Grounded(120)]]
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

Annotations declare types. Engine functions remain available through ordinary
MeTTa evaluation on the space handle.

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
decorators share one naming policy: an implicit Python name maps underscores
to MeTTa hyphens, while `name=` preserves its authored spelling exactly.
Anything
outside the subset is a refusal naming the construct, the line, and what
to write instead, never a silent fallback; a body only the engine can run
(a match, a constructor) gets a twin that says so instead of a NameError.
Every other definition keeps its Python twin callable as `.py`, stacked
clauses dispatching first-match; a CSmith-style fuzzer generates random
programs in the subset and holds engine and twin to identical answers.

### Integrating any library

`metta.integrate` is the interface a Python library implements to work
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
(Enums become symbols with declarations, dataclasses and pydantic models
become constructor expressions, all by default, a model rebuilding through
itself so validation runs where pydantic runs it); `register_object_type` makes a protocol a
type; `install_reflection_ops` gives `(py-field $obj $name)` in both modes,
enumeration included; and a `SpaceProvider` implements a space in Python, so
`(match &db (users $id $name) ...)` runs against a database with bound
positions pushed down as a WHERE clause while the engine keeps unification,
and therefore soundness, for itself. The worked SQL instance lives whole
in `bindings/python/examples/integration/duckdb_space.py`, deliberately as an example: a
DuckDB provider is a page of code on this interface. A package advertises itself through the
`metta.integrations` entry-point group, and `m.integrate(module)` installs
anything defining `install_metta(m)`. Declare an integration in package
metadata like this:

Installation is idempotent for one live space. `space.drop()` releases that
record with the stored facts, so a later space using the same name installs
again.

Process-wide extension registrations have exact removal counterparts.
Use `convert.unregister_type`, `integrate.unregister_object_type`,
`integrate.unregister_repr`, and `integrate.unregister_reflector` with the
same objects passed at registration. Protocol atom formatters pair
`integrate.register_repr` with `integrate.unregister_repr`. Removing a
registration that is not live raises `KeyError`.

```toml
[project.entry-points."metta.integrations"]
my-library = "my_library.metta"
```

The library ships no built-in integration of its own; sibling packages
publish into that group from their own manifests and `m.discover()`
finds them.

This leans on Python's metaprogramming the way SQLAlchemy and Pydantic do:
introspected signatures become arities and types, the AST becomes equations,
protocols become types, and entry points become discovery.

Beyond operations and spaces, the surface carries: `@m.define` on an Enum,
dataclass or NamedTuple, which declares the class into a space with constructor
declarations and one accessor equation per field; `m.type(atom)`, which reads
the atom's declared type; `rows.build(col, Person)`, which rebuilds
answers as instances and preserves `Person` for type checkers;
`rows.to_dicts()` returning one plain mapping per answer;
`with m.bind(df=df): m.run(...)`, naming host values by bare symbol with
identity intact; `m.subscribe(pattern,
callback)`, a standing query delivered inside the very write that matched
it (or queued for `drain()`), which is the actors-and-pub-sub reading of a
space; `m.save(path)` writing a space back as loadable source, with
`m.load(path)` adding that source rather than replacing current atoms; and
`metta.current_space()`, callable from inside any operation to learn the
space whose program called it.

### Custom matching

Matching is open the way MeTTa itself says it is: a grounded value can
define its own matching logic. Any Python object whose class defines
`match_` participates in `(unify ...)` with no registration, yielding
bindings for the operand it met, and a space operand routes through the
engine's own match, which is how `(unify &self (friend $who Alice) $who
no-friends)` answers each friend. Scored matching is an ordinary
operation: answer each candidate with the degree as the answer's
annotation, declare its value algebra, and `(top k ...)` orders while
`(annotation)` reads the degree beside its answer. Fuzzy, regex and
semantic closeness are each a few lines on that surface;
`bindings/python/examples/reasoning/custom_matchers.py` builds all three.
`lib/lib_measure/lib_measure.metta` stays pure MeTTa over explicit `(weight value)`
pairs, annotated-disjunction shaped: `ws-normalize`, `ws-softmax` with a
temperature, `ws-best`, `ws-top`, `ws-sample!`, `ws-collapse`,
`ws-expect`; `lib/lib_soft/lib_soft.metta` extends it over terms with Sessa's weak
unification, structure crisp, symbols close to declared degrees
(`pettaprove.link_store` materializes them from embeddings), variables
binding as ever. `(pair (annotation) $answer)` bridges an annotated
operation's answers into that pair world when you want them there.
`bindings/python/bench.py` runs the pytest-benchmark suite. `--list` prints its named
cases and `--counter-only` runs the deterministic regression gate without
using wall time. The gate uses `--keep-going`, so every case reports before a
failure exits. Engine cases compare the minimum of three `stats().inferences`
samples with `bindings/python/benchmarks/baseline.json`; join and let cases also compare
inference growth between two fixed workload sizes.
`bindings/python/benchmarks/check_instructions.py` measures the Python codecs and the
primitive-heavy let, digest, alpha-unique, sort, source-load, Python-method,
and space-name paths with `perf stat -e instructions:u`. Setup is outside the
counted interval. Wall results remain advisory and can be written with `--json`.

On top of that closeness sits a prover, `pettaprove.prove`, layered
BESIDE the core in its own repository because it is built entirely on
the public surface: backward
chaining where every unification is soft, the reading of End-to-End
Differentiable Proving (Rocktaschel and Riedel 2017) and IBM's Braid. A
goal proves through stored facts, through `=` rules whose bodies prove in
turn, through conjunction goals conjunct by conjunct, and through ground
guards the engine itself evaluates; degrees aggregate by minimum, every
step must clear the threshold, and the answer is a `Proof` carrying the
substitutions, the aggregate similarity and every step:

```python
import pettaprove as soft
from metta import space

k = space()
k.add(S["parent-of"](S.homer, S.bart), S["father-of"](S.abe, S.homer))
k.run("(= (grandpa-of $x $y) (and (father-of $x $z) (parent-of $z $y)))")
soft.similar(k, "grandpa-of", "grandfather-of", 0.9)

proof = soft.prove(k, S["grandfather-of"](V.who, S.bart))
proof.substitutions["who"], proof.similarity     # (Symbol('abe'), 0.9)
```

`grandfather-of` never appears in the knowledge, only `grandpa-of` does;
the declared similarity carries the proof across, and `proof.steps` names
every rule, fact and guard on the way.

### Arrays: every DLPack library, one operation set

`metta.arrays` carries tensors for every library speaking the standard
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

The PyTorch integration lives in its own repository beside this one,
`pettorch`, built on the metta module's public surface: the whole tensor
set through `metta.arrays` with torch as the constructor default, losses
and optimizers through `metta.integrate`, `MettaModule` running a MeTTa
forward pass under autograd, architecture reflection as facts, and the
neural predicate as an annotated relation on the same surface.
Its docs, tests and torch examples travel with it. The CLI-reachable half
stays here as `lib/lib_torch/lib_torch.metta`; see `examples/ch11-python-as-a-notation/08-torch_lib.metta`.

### Extension libraries

Please check out [Extension libraries](https://github.com/trueagi-io/PeTTa/wiki/Extension-libraries) for a set of extension libraries that can be invoked from MeTTa files directly from the git repository.

### Git dependencies

A file can declare the repositories it needs as plain forms:

```metta
(git-dependency "https://example/repo.git" "0123456789abcdef0123456789abcdef01234567")
!(import! &self (library repo somelib))
```

Declarations are satisfied after the file is parsed and before any of its forms
run, so the checkout exists when the import resolves. The commit must be a full
40-character SHA; the checkout is verified against it on every run and retargeted
when the pin changes, so a fresh clone and a machine with an existing checkout
behave identically. Optional third and fourth values give a build command and a
base directory: `(git-dependency url rev "build.sh" "./repos")`. A dependency can
declare its own dependencies in a `deps.metta` file at its repository root, and
these are acquired transitively.

For dynamic acquisition, the core `git-import!` primitive supports URL-only,
URL/build-command, and
URL/build-command/base-directory forms. For a reproducible detached checkout,
pass a fourth input in the order URL, build command, base directory, commit:

```metta
!(git-import! "https://example/repo.git" "" "./repos" "0123456789abcdef0123456789abcdef01234567")
```

Pinned imports accept only a full 40-character hexadecimal commit SHA;
abbreviated SHAs, branches, and tags are rejected.

The first argument of the three-argument `library` form is the repository name.
It resolves through the exact canonical checkout registered by Git acquisition,
including when a custom base directory is used.

### The website

`website/` is a VitePress site that teaches the Python library: eight
tutorials that assume Python and no MeTTa, feature guides, integration
walkthroughs, live-system pages, and a generated API reference, with
pettagrapher renders as the illustrations. Build and preview it locally:

```bash
cd website
npm install
npm run docs:build
npm run docs:preview
```

The site is built for project hosting under the `/PeTTa/` path, so the
preview answers at `http://localhost:4173/PeTTa/` and the server root
shows the site's 404 page. `npm run docs:dev` serves the same content
live at `http://localhost:5173/PeTTa/`. The reference pages and the
visuals are committed; after changing docstrings or the illustrations,
regenerate them with `bindings/python/tools/reference.py --write` and
`website/scripts/generate_visuals.py`, and `website/scripts/audit_snippets.py`
verifies that every tutorial code fence is an exact excerpt from the
repository's own sources.

## Notebooks, Servers, Browser

### Jupyter Notebook Support

A Jupyter kernel is available in a separate repository for interactive MeTTa development in notebooks.

**Repository:** [trueagi-io/jupyter-petta-kernel](https://github.com/trueagi-io/jupyter-petta-kernel)

Quick install:

```bash
# Set METTA_PATH to this installation
export METTA_PATH=/path/to/checkout

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

Since Swi-Prolog can be compiled to Web Assembly, one can embed MeTTa into websites.

Please see [Execution-in-browser](https://github.com/patham9/PeTTa/wiki/Execution-in-browser) for more information.

### MeTTa in TypeScript

`bindings/node/` runs the engine inside a Node process over the same WebAssembly
build, so a TypeScript program needs no SWI-Prolog on the machine and no socket.
It is the sibling of the Python library: atoms, spaces, the three definition
doors, worlds and scopes, spelled the way TypeScript spells things.

```ts
import { metta, S, type Term, V } from "./bindings/node/src/index.ts";

const m = await metta();
m.add(S.parent(S.tom, S.bob), S.parent(S.bob, S.ann));

// Rows are keyed by the pattern's own variable names.
for await (const { child } of m.match(S.parent(S.tom, V.child))) {
  console.log(String(child));                  // bob
}

// An ordinary TypeScript function becomes ONE equation the engine holds, so a
// call costs no host crossing at all.
const twice = m.define(function twice(n: number): number { return n * 2; });
await twice(21).one();                         // 42

// A generator body is traced into clauses; `yield*` asks, `yield` emits.
const grandparent = m.define(function* grandparent(x: Term) {
  const { y } = yield* m.match(S.parent(x, V.y));
  const { z } = yield* m.match(S.parent(y, V.z));
  return z;
});

// And a TypeScript function the engine calls back into, from the middle of a
// reduction, awaited if it answers with a promise.
m.op(async function fetchJson(url: string) { return (await fetch(url)).json(); });
```

See [bindings/node/README.md](bindings/node/README.md) for the whole surface,
what the WebAssembly build does not carry, and how the binding is held to the
same conformance corpus the Python library answers.
