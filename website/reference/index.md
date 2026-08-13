# API reference

Each page reproduces the public definitions, source signatures, and docstrings of one module. Class pages also include public method docstrings.

## `petta`

| Module | Surface |
|---|---|
| [`petta.atoms`](./petta-atoms) | atoms, constructors, encoding, unification |
| [`petta.space`](./petta-space) | the `MeTTa` runtime, spaces, queries, operations |
| [`petta.ops`](./petta-ops) | Python operation registration and type declarations |
| [`petta.convert`](./petta-convert) | two-way object translation |
| [`petta.matching`](./petta-matching) | custom matchers |
| [`petta.measure`](./petta-measure) | weighted superpositions and relations |
| [`petta.subscribe`](./petta-subscribe) | standing queries |
| [`petta.remote`](./petta-remote) | spaces served and attached across processes |
| [`petta.das`](./petta-das) | the Distributed Atomspace over the command router |
| [`petta.lint`](./petta-lint) | space diagnostics for the silently-wrong class |
| [`petta.trace`](./petta-trace) | the reduction trace as events |
| [`petta.casting`](./petta-casting) | runtime typecasting through the engine's types |
| [`petta.aio`](./petta-aio) | the engine on an event loop, one dedicated worker thread |
| [`petta.persistent`](./petta-persistent) | fact spaces backed by persistency journals |
| [`petta.testing`](./petta-testing) | the hypothesis strategies the suite fuzzes itself with |
| [`petta.foreign`](./petta-foreign) | Python-backed spaces |
| [`petta.integrate`](./petta-integrate) | library integration tools |
| [`petta.arrays`](./petta-arrays) | array operations and embedding stores |
| [`petta.results`](./petta-results) | query rows and tables |

## Sibling repositories

Three packages live in their own repositories beside this one, docs and
tests included; each builds on the public surface documented here.
`pettorch` is the PyTorch integration, `pettaprove` is soft unification
and goal-directed soft proving (the engine-side equations stay here as
`lib/lib_soft.metta`), and `pettagrapher` draws terms, spaces, proofs,
and reductions as self-contained pages.

