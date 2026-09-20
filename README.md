# MeTTa-Kernel is retired

The engine in this repository now lives in
[MesTTo/MeTTa](https://github.com/MesTTo/MeTTa) under `engine/`, as ordinary
tracked files rather than a submodule. Every commit here is reachable from that
repository's `main`: the absorbing commit names this repository's tip as its
second parent, so nothing was left behind.

Nothing here is maintained. Read it for history.

## Where the project went

One language was split into components, each its own repository, mounted
together by [MesTTo/MeTTa](https://github.com/MesTTo/MeTTa).

| Component | Repository | What it holds |
|---|---|---|
| everything, mounted | [MeTTa](https://github.com/MesTTo/MeTTa) | the engine, the libraries, the examples and all three surfaces |
| the engine | *this repository, now `engine/` in MeTTa* | translator, matcher, spaces, catalog, extension points, the C half |
| the libraries | [MeTTa-Library-Pack](https://github.com/MesTTo/MeTTa-Library-Pack) | 61 libraries, written in MeTTa |
| the examples | [MeTTa-Examples](https://github.com/MesTTo/MeTTa-Examples) | 360 executable programs, the semantics documentation |
| Python | [PyMeTTa](https://github.com/MesTTo/PyMeTTa) | the Python surface |
| integrations | [PyMeTTa-Extensions](https://github.com/MesTTo/PyMeTTa-Extensions) | pandas, polars, duckdb, arrow, faiss and the rest, each its own distribution |
| TypeScript | [TSMeTTa](https://github.com/MesTTo/TSMeTTa) | the TypeScript surface, on a WebAssembly engine |
| C | [CMeTTa](https://github.com/MesTTo/CMeTTa) | the C surface |
| a storage backend | [MeTTa-MORK](https://github.com/MesTTo/MeTTa-MORK) | spaces on MORK's Rust trie |

## Why it was split this way

The engine is the kernel every other component reaches through a declared
seam, so each one can be built, versioned and published on its own:

- a **surface** reaches the engine through the wire codec rather than a port,
  which is why Python, TypeScript and C are three consumers of one engine
  rather than three engines;
- a **backend** claims the space names it owns through `seam:foreign_space/1`
  and fails for the rest, which is what lets the next provider answer;
- an **integration** registers a row against a declared extension point, and
  the core names no third-party library at all;
- a **library** is written in MeTTa over the primitives, so it survives a
  change of engine.

`engine/ext_points.pl` in MeTTa declares every point, in four kinds, and
`clauses_from/2` says who may contribute each.

## The last state of this repository

The tip is `b694f34`, which added the Apache-2.0 licence. The engine has
since gained a README and moved its C sources under `engine/c/`, both in
MeTTa.
