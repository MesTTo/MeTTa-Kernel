# Integrations

Each page maps one Python library family onto MeTTa forms: tables to
facts, models to constructor expressions, stores to spaces, arrays to
one operation vocabulary. The examples behind these pages run in the
test suite, so every walkthrough stays true to the code.

- [Dataframes](./dataframes.md) crosses rows both ways: tables become facts and query answers become dataframes.
- [DuckDB as a space](./duckdb-space.md) lets SQL tables answer matches through a `SpaceProvider`.
- [SQLite BLOB images](./sqlite-blobs.md) chooses handle or structural crossings per type and context.
- [Pydantic models both ways](./pydantic-models.md) projects structured values into constructor expressions and rebuilds them.
- [Arrays and embeddings](./arrays-embeddings.md) gives DLPack array libraries one MeTTa operation vocabulary.
- [HTTP, routes, and solver loops](./http-routes-solvers.md) tells apart the three seams that share space operations.

## Shipping one as a package

A third-party package advertises what it brings through packaging entry points, pytest plugins' and SQLAlchemy dialects' own mechanism, three groups:

```toml
[project.entry-points."petta.integrations"]
mylib = "mylib.petta_glue"          # a module with install_petta(m)

[project.entry-points."petta.spaces"]
duck = "mylib.spaces:DuckProvider"  # a provider class or factory

[project.entry-points."petta.libraries"]
nars = "mylib:LIBRARY_DIR"          # the directory of sources it ships
```

Nothing auto-registers on import. `petta.integrate.entry_points(group)` answers the advertised names without loading anything, and the app loads by name, keeping control:

```python
from petta import attach, integrate

integrate.discover(m)                                     # install every advertised integration
attach("&duck", integrate.load_entry_point("duck"))
m.register_library_path(
    integrate.load_entry_point("nars", group=integrate.LIBRARIES_GROUP), "nars"
)
```

A callable target is a factory and is called with your arguments; a non-callable one answers as-is. An unknown name refuses by listing what is installed, so a typo reads as one.
