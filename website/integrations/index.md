# Integrations

Each page maps one Python library family onto MeTTa forms: tables to
facts, models to constructor expressions, stores to spaces, arrays to
one operation vocabulary. The examples behind these pages run in the
test suite, so every walkthrough stays true to the code.

- [Dataframes](./dataframes.md) crosses rows both ways: tables become facts and query answers become dataframes.
- [DuckDB as a space](./duckdb-space.md) lets SQL tables answer matches through a `SpaceProvider`.
- [Pydantic models both ways](./pydantic-models.md) projects structured values into constructor expressions and rebuilds them.
- [Arrays and embeddings](./arrays-embeddings.md) gives DLPack array libraries one MeTTa operation vocabulary.
- [HTTP, routes, and solver loops](./http-routes-solvers.md) tells apart the three seams that share space operations.
