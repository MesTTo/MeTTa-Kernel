# Install and first steps

The `petta` package is the Python surface for the engine. Install it from the repository root with `pip install .`. The runtime is bundled. To use a checkout in place, point `PETTA_PATH` at the repository tree.

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

Examples that need DuckDB, NumPy, or PyTorch skip when that optional dependency is absent. When something misbehaves, `petta.backend_info()` answers the petta, janus, SWI-Prolog, and Python versions plus the consulted runtime tree in one dict, without starting the engine, which is exactly what a bug report needs. Continue with [atoms, operators, and term building](./atoms-terms).
