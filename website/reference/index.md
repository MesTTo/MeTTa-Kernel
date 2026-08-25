<!--
Purpose: index the public Python modules and handle APIs documented by the generated reference pages.
Guarantees: deleted module doors have no reference link, the Space handle is not presented as a module, and the reified strategy satellite points to its executable phrasebook.
[tested: npm run docs:build; commit=WORKTREE]
-->

# API reference

Each page reproduces the public definitions, source signatures, and docstrings of one module. Class pages also include public method docstrings.

## Core

These modules define atoms, spaces, queries, and the rows returned to Python.

| Module | Surface |
|---|---|
| [`metta.atoms`](./metta-atoms) | atoms, constructors, encoding, unification |
| [`metta.paths`](./metta-paths) | lazy attributes and keys inside opaque handles |
| [`metta.Space`](./metta-space) | the space handle returned by `metta.space()` |
| [`metta.results`](./metta-results) | query rows and tables |

## Definition

These modules register Python behavior, translate structured objects, and enforce checked type boundaries.

| Module | Surface |
|---|---|
| [`metta.ops`](./metta-ops) | Python operation registration and type declarations |
| [`metta.convert`](./metta-convert) | two-way object translation |
| [`metta.casting`](./metta-casting) | runtime typecasting through the engine's types |
| [`metta.strategies`](./stdlib-phrasebook#rewriting-strategies) | reified strategy constructors and TP/TU traversal schemes |

## Diagnostics

These modules expose reduction events, structural findings, similarity scores, and custom match behavior.

| Module | Surface |
|---|---|
| [`metta.trace`](./metta-trace) | the reduction trace as events |
| [`metta.derivation`](./metta-derivation) | proof trees and their steps |
| [`metta.lint`](./metta-lint) | space diagnostics for the silently-wrong class |

## Data and stores

These modules operate on array protocols and generate test data for public atoms. Journal-backed stores are created through `metta.space(journal=...)`.

| Module | Surface |
|---|---|
| [`metta.structures`](./metta-structures) | pattern-keyed maps, indexes, and engine-backed views |
| [`metta.tables`](./metta-tables) | SQL tables bridged in as declared shapes |
| [`metta.arrays`](./metta-arrays) | array operations and embedding stores |
| [`metta.testing`](./metta-testing) | the hypothesis strategies the suite fuzzes itself with |

## Distribution

These modules connect spaces, processes, event loops, subscriptions, and external providers.

| Module | Surface |
|---|---|
| [`metta.remote`](./metta-remote) | spaces served and attached across processes |
| [`metta.spaces`](./metta-spaces) | union, readonly, mapped, and overlay combinators |
| [`metta.manifest`](./metta-manifest) | app assembly from a (boot ...) manifest |
| [`metta.aio`](./metta-aio) | the engine on an event loop, one dedicated worker thread |
| [`metta.events`](./metta-events) | the public event stream and the fold over it |
| [`metta.subscribe`](./metta-subscribe) | standing queries, the fold that delivers |
| [`metta.foreign`](./metta-foreign) | Python-backed spaces |
| [`metta.integrate`](./metta-integrate) | library integration tools |

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
