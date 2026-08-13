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
| [`petta.soft`](./petta-soft) | soft unification and proving |
| [`petta.subscribe`](./petta-subscribe) | standing queries |
| [`petta.web`](./petta-web) | fact-backed route dispatch |
| [`petta.multishot`](./petta-multishot) | program parts and external truths |
| [`petta.foreign`](./petta-foreign) | Python-backed spaces |
| [`petta.integrate`](./petta-integrate) | library integration tools |
| [`petta.arrays`](./petta-arrays) | array operations and embedding stores |
| [`petta.results`](./petta-results) | query rows and tables |

## `pettorch`

| Module | Surface |
|---|---|
| [`pettorch`](./pettorch) | package installation |
| [`pettorch.tensors`](./pettorch-tensors) | array operations with PyTorch constructors and autograd controls |
| [`pettorch.modules`](./pettorch-modules) | wrapped models and `MettaModule` |
| [`pettorch.train`](./pettorch-train) | losses, optimizers, and training steps |
| [`pettorch.reflect`](./pettorch-reflect) | model architecture as facts |
| [`pettorch.neural`](./pettorch-neural) | neural predicates |
| [`pettorch.knn`](./pettorch-knn) | compatibility export for `EmbeddingStore` |
