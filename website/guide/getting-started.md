<!--
Purpose: install PeTTa and introduce its module primitives, runtime context, and Space handle.
Guarantees: examples use the current narrow public surface.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Install and first steps

The `petta` package is the Python surface for the engine. Install it from the repository root with `pip install .`. The runtime is bundled. To use a checkout in place, point `PETTA_PATH` at the repository tree.

The shortest spelling needs no instance at all: the module functions run over one lazily created default engine, `random`'s and `logging`'s own shape, and `petta.engine()` hands the context over the moment you want control.

```python
import petta

petta.add("(parent Tom Bob)")
petta.query("(parent Tom $x)")       # Rows[x]([Row(x=Symbol('Bob'))])
petta.run("!(+ 40 2)")               # [[42]]
```

Every module function is one line over the default context's `Space` handle. The rungs, each sugar for the one below it:

| today | shorter |
|---|---|
| `m = petta.space()` in every script | `import petta; petta.query(...)` |
| `timeout=` / `inferences=` on every call | one `with m.limits(...)` block |
| query, then reshape rows by hand | `m.query(..., into=Edge)` |
| add-loops crossing per atom | `with m.batch():` crosses once |
| hand-rolled engine fixtures in your tests | the shipped pytest plugin's `metta` and `scratch_space` |

Create a `Space` handle, run source, then move between source terms and Python atoms:

```python
from petta import S, V, space

m = space()
m.run("(= (foo) boo) !(foo)")        # [[Symbol('boo')]]
m.run("!(+ 40 2)")                   # [[42]]

m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
m.query(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
# Rows[x, y, z]([Row(x=Symbol('Tom'), y=Symbol('Bob'), z=Symbol('Ann'))])
```

`run` uses the engine's reader, compiler, and evaluator. It returns one answer list for each `!` directive. Grounded answers compare as Python values. Symbols stay symbols. Stored Python objects return as the same objects.

The repository has thirteen self-verifying Python examples organised by topic. Run the first from the repository root:

```bash
PYTHONPATH=bindings/python/examples python bindings/python/examples/basics/first_steps.py
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

Examples that need DuckDB, NumPy, or PyTorch skip when that optional dependency is absent. When something misbehaves, `petta.engine().info()` answers the petta, janus, SWI-Prolog, and Python versions plus the consulted runtime tree in one dict, which is exactly what a bug report needs. The library logs under the `petta` namespace and installs a `NullHandler`, so it stays silent until your app configures it; `logging.getLogger("petta").setLevel(logging.DEBUG)` with a handler is the whole debug incantation. Continue with [atoms, operators, and term building](./atoms-terms).
