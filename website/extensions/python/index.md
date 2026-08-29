<!--
Purpose: introduce the PyMeTTa seat and route to the sections that document it.
Assumes: the tutorials, guide, integrations, live-systems, reasoning and
  reference sections are this seat's documentation, so this page routes to them
  rather than repeating them.
Guarantees: every section named here exists in the navigation
  [tested: test_every_site_page_is_reachable_from_the_navigation; commit=WORKTREE]
-->

# PyMeTTa

PyMeTTa is the Python seat. It is on PyPI as `pymetta` and imports as `metta`,
and [its tutorial](./tutorial.md) installs it and runs a first program.

The seat is two directions at once, which is why its control file is the
one that declares both `entry/2` roles in two files:

```prolog
title('MeTTa in Python: the janus bridge and the metta library''s transport').
needs(prolog_library(janus)).
entry(engine, 'bridge.pl').
entry(host, 'metta/shim.pl').
```

`entry(engine, 'bridge.pl')` is the ENGINE reaching Python: `py-atom` resolves a
dotted name, `py-call` applies it, and a Python generator arrives as
nondeterminism. The engine consults that file at boot. `entry(host,
'metta/shim.pl')` is Python reaching the ENGINE: it is the `metta` library's
transport, consulted by the library when it boots, and the engine records it
without ever loading it.

Its one need is `library(janus)`, SWI's own Python bridge. A build without it,
the WebAssembly build or a stripped install, cannot host this seat at all, so the
seat loads nothing and says nothing rather than reporting a fault.

## Its documentation is most of this site

This seat is the one you are reading about everywhere else:

- [Tutorials](../../tutorials/) teach MeTTa from Python, one concept at a time.
- [Guide](../../guide/) covers the surface by task: queries, definitions,
  spaces, threads, observability, notebooks.
- [Integrations](../../integrations/) are the library boundaries: dataframes,
  DuckDB, Pydantic, arrays, HTTP.
- [Live systems](../../live/) cover standing queries, remotes and the event
  loop.
- [Reasoning](../../reasoning/) covers custom matching and weighted relations.
- [Reference](../../reference/) reproduces every public module's signatures and
  docstrings, generated from the source.

Install SWI-Prolog first, then `pip install 'pymetta[engine]'`, or
`pip install '.[engine]'` from the repository root, or point `METTA_PATH` at a
clone. [The PyMeTTa tutorial](./tutorial.md) walks that install and the first
program; [Install and first steps](../../guide/getting-started.md) is the
guide's version of the same ground.
