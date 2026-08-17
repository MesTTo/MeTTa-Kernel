# Install and first steps

The `petta` package is the Python surface for the engine. Install it from the repository root with `pip install .`. The runtime is bundled. To use a checkout in place, point `PETTA_PATH` at the repository tree.

The shortest spelling needs no instance at all: the module functions run over one lazily created default engine, `random`'s and `logging`'s own shape, and `petta.default_engine()` hands the instance over the moment you want control.

```python
import petta

petta.add("(parent Tom Bob)")
petta.query("(parent Tom $x)")       # Rows[x]([Row(x=Sym('Bob'))])
petta.run("!(+ 40 2)")               # [[42]]
```

Every module function is one line of sugar over the `MeTTa` class, documented as such, and that is the library's whole ladder: simple things simple, every knob still there. The rungs, each sugar for the one below it:

| today | shorter |
|---|---|
| `m = petta.MeTTa()` in every script | `import petta; petta.query(...)` |
| `timeout=` / `inferences=` on every call | one `with m.limits(...)` block |
| query, then reshape rows by hand | `m.query(..., into=Edge)` |
| add-loops crossing per atom | `with m.batch():` crosses once |
| hand-rolled engine fixtures in your tests | the shipped pytest plugin's `metta` and `scratch_space` |

Create a `MeTTa` instance, run source, then move between source terms and Python atoms:

```python
from petta import MeTTa, S, V

m = MeTTa()
m.run("(= (foo) boo) !(foo)")        # [[Sym('boo')]]
m.run("!(+ 40 2)")                   # [[42]]

m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
m.query(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
# Rows[x, y, z]([Row(x=Sym('Tom'), y=Sym('Bob'), z=Sym('Ann'))])
```

`run` uses the engine's reader, compiler, and evaluator. It returns one answer list for each `!` directive. Grounded answers compare as Python values. Symbols stay symbols. Stored Python objects return as the same objects.

The repository has thirteen self-verifying Python examples organised by topic. Run the first from the repository root:

```bash
PYTHONPATH=python/examples python python/examples/basics/first_steps.py
```

The installed wheel is a complete command-line tool too, `-m` fashion:

```bash
python -m petta run program.metta        # run files, print each ! answer group
python -m petta repl                     # interactive loop, multi-line forms
python -m petta serve kb.metta --port 8700   # expose spaces over HTTP
python -m petta boot app.metta           # assemble a (boot ...) manifest
python -m petta lint program.metta       # diagnostics; nonzero exit on findings
python -m petta doc car-atom             # a name's (@doc ...) documentation
```

Each subcommand exits nonzero on failure, so all of them script. The bare `petta` console command keeps upstream's launcher contract, running a file through `swipl` directly.

Examples that need DuckDB, NumPy, or PyTorch skip when that optional dependency is absent. When something misbehaves, `petta.backend_info()` answers the petta, janus, SWI-Prolog, and Python versions plus the consulted runtime tree in one dict, without starting the engine, which is exactly what a bug report needs. The library logs under the `petta` namespace and installs a `NullHandler`, so it stays silent until your app configures it; `logging.getLogger("petta").setLevel(logging.DEBUG)` with a handler is the whole debug incantation. Continue with [atoms, operators, and term building](./atoms-terms).
