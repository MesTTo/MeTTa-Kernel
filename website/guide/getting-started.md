<!--
Purpose: install PeTTa and introduce its module primitives, runtime context, and Space handle.
Guarantees: examples use the current narrow public surface.
[tested: npm run docs:build; commit=5fe3175632a6b60b3b54ca9125b75607ac82401a]
-->

# Install and first steps

The `metta` module is the Python surface for the engine. Install the `pymetta` distribution from the repository root with `pip install .`. The runtime is bundled. To use a checkout in place, point `PETTA_PATH` at the repository tree.

The shortest spelling needs no instance at all: the module functions run over one lazily created default engine, `random`'s and `logging`'s own shape, and `metta.engine()` hands the context over the moment you want control.

```python
import metta

metta.add("(parent Tom Bob)")
metta.match("(parent Tom $x)")       # Rows[x]([Row(x=Symbol('Bob'))])
metta.run("!(+ 40 2)")               # [[42]]
```

Every module function is one line over the default context's `Space` handle. The rungs, each sugar for the one below it:

| today | shorter |
|---|---|
| `m = metta.space()` in every script | `import metta; metta.match(...)` |
| `timeout=` / `inferences=` on every call | one `with m.limits(...)` block |
| query, then reshape rows by hand | `m.match(..., into=Edge)` |
| add-loops crossing per atom | `with m.batch():` crosses once |
| hand-rolled engine fixtures in your tests | the shipped pytest plugin's `metta` and `scratch_space` |

Create a `Space` handle, run source, then move between source terms and Python atoms:

```python
from metta import S, V, space

m = space()
m.run("(= (foo) boo) !(foo)")        # [[Symbol('boo')]]
m.run("!(+ 40 2)")                   # [[42]]

m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
m.match(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
# Rows[x, y, z]([Row(x=Symbol('Tom'), y=Symbol('Bob'), z=Symbol('Ann'))])
```

`run` uses the engine's reader, compiler, and evaluator. It returns one answer list for each `!` directive. Grounded answers compare as Python values. Symbols stay symbols. Stored Python objects return as the same objects.

## Python version floor

PeTTa supports Python 3.12 and newer. The floor spelling builds terms directly,
such as `term = S.Order(7, 5)`, and reconstructs or calls `__replace__` on a
PeTTa-defined record when one field changes. Those forms work on 3.12.

Python 3.13 adds `copy.replace(edge, b="new")` as the general functional
update spelling. Python 3.14 adds t-string syntax, which creates a structured
`Template`; it is optional integration sugar and is not accepted directly by
`Space.run`. Neither feature changes the 3.12 floor. See
[term building](./atoms-terms.md#build-terms-not-source-text) and
[record replacement](./python-functions.md#declaring-a-data-class) for the
runnable forms.

The repository has thirteen self-verifying Python examples organised by topic. Run the first from the repository root:

```bash
PYTHONPATH=bindings/python/examples python bindings/python/examples/basics/first_steps.py
```

The installed wheel is a complete command-line tool too, `-m` fashion:

```bash
python -m metta run program.metta        # run files, print each ! answer group
python -m metta repl                     # interactive loop, multi-line forms
python -m metta serve kb.metta --port 8700   # expose spaces over HTTP
python -m metta boot app.metta           # assemble a (boot ...) manifest
python -m metta lint program.metta       # diagnostics; nonzero exit on findings
python -m metta doc car-atom             # a name's (@doc ...) documentation
```

Each subcommand exits nonzero on failure, so all of them script. The bare `metta` console command keeps the direct-file launcher contract, running a file through `swipl` directly.

Examples that need DuckDB, NumPy, or PyTorch skip when that optional dependency is absent. When something misbehaves, `metta.engine().info()` answers the PeTTa, janus, SWI-Prolog, and Python versions plus the consulted runtime tree in one dict, which is exactly what a bug report needs. The library logs under the `metta` namespace and installs a `NullHandler`, so it stays silent until your app configures it; `logging.getLogger("metta").setLevel(logging.DEBUG)` with a handler is the whole debug incantation. Continue with [atoms, operators, and term building](./atoms-terms).
