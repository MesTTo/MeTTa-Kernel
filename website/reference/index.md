# API reference

Each page reproduces the public definitions, source signatures, and docstrings of one module. Class pages also include public method docstrings.

## Core

These modules define atoms, spaces, queries, and the rows returned to Python.

| Module | Surface |
|---|---|
| [`petta.atoms`](./petta-atoms) | atoms, constructors, encoding, unification |
| [`petta.paths`](./petta-paths) | lazy attributes and keys inside opaque handles |
| [`petta.space`](./petta-space) | the `MeTTa` runtime, spaces, queries, operations |
| [`petta.results`](./petta-results) | query rows and tables |

## Definition

These modules register Python behavior, translate structured objects, and enforce checked type boundaries.

| Module | Surface |
|---|---|
| [`petta.ops`](./petta-ops) | Python operation registration and type declarations |
| [`petta.convert`](./petta-convert) | two-way object translation |
| [`petta.casting`](./petta-casting) | runtime typecasting through the engine's types |

## Diagnostics

These modules expose reduction events, structural findings, similarity scores, and custom match behavior.

| Module | Surface |
|---|---|
| [`petta.trace`](./petta-trace) | the reduction trace as events |
| [`petta.lint`](./petta-lint) | space diagnostics for the silently-wrong class |

## Data and stores

These modules persist facts, operate on array protocols, and generate test data for public atoms.

| Module | Surface |
|---|---|
| [`petta.persistent`](./petta-persistent) | fact spaces backed by persistency journals |
| [`petta.structures`](./petta-structures) | pattern-keyed maps, indexes, and engine-backed views |
| [`petta.tables`](./petta-tables) | SQL tables bridged in as declared shapes |
| [`petta.arrays`](./petta-arrays) | array operations and embedding stores |
| [`petta.testing`](./petta-testing) | the hypothesis strategies the suite fuzzes itself with |

## Distribution

These modules connect spaces, processes, event loops, subscriptions, and external providers.

| Module | Surface |
|---|---|
| [`petta.remote`](./petta-remote) | spaces served and attached across processes |
| [`petta.spaces`](./petta-spaces) | union, readonly, mapped, and overlay combinators |
| [`petta.manifest`](./petta-manifest) | app assembly from a (boot ...) manifest |
| [`petta.das`](./petta-das) | the Distributed Atomspace over the command router |
| [`petta.aio`](./petta-aio) | the engine on an event loop, one dedicated worker thread |
| [`petta.events`](./petta-events) | the public event stream and the fold over it |
| [`petta.subscribe`](./petta-subscribe) | standing queries, the fold that delivers |
| [`petta.foreign`](./petta-foreign) | Python-backed spaces |
| [`petta.integrate`](./petta-integrate) | library integration tools |

## The MeTTa libraries

[`metta-libraries`](./metta-libraries) reproduces each `lib_*.metta` library's own `(@doc ...)` atoms through `bindings/python/tools/libdoc.py`, one pipeline with the Python reference above, with a coverage table as the burn-down surface.

[`stdlib-phrasebook`](./stdlib-phrasebook) is the other direction: every operation MeTTa's standard library declares, and what you write in Python instead. `bindings/python/tools/phrasebook.py` runs both sides of every row, on this engine and on LeaTTa, so the page states a coverage number rather than a claim.

## Sibling repositories

Three packages live in their own repositories beside this one, docs and
tests included; each builds on the public surface documented here.
`pettorch` is the PyTorch integration, `pettaprove` is soft unification
and goal-directed soft proving (the engine-side equations stay here as
`lib/lib_soft.metta`), and `pettagrapher` draws terms, spaces, proofs,
and reductions as self-contained pages.
