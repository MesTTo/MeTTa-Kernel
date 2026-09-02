<!--
Purpose: explain what an extension is, list the four that ship, and say
where to go next.
Guarantees: every folder under extensions/ carrying an extension.pl has an area
    here [tested: test_every_extension_has_a_site_area;
  commit=057cc60ec553c5820f95ee361f1fad057467f3c3]
-->

# Extensions

An extension puts another language on the engine, or another storage backend
underneath it. Four ship today.

| Extension | What you get |
|---|---|
| [PyMeTTa](./python/) | write MeTTa programs in Python, via the `metta` package |
| [MeTTa-node](./node/) | write them in TypeScript, running on swipl-wasm inside Node |
| [CMeTTa](./cmetta/) | embed the engine in a C program |
| [MORK](./mork/) | store spaces in a Rust trie instead of in memory |

The first three are languages you write programs in, so each has a tutorial
that starts from an empty directory and ends at a running program:
[Python](./python/tutorial.md), [TypeScript](./node/tutorial.md),
[C](./cmetta/tutorial.md). MORK is storage, so there is nothing to write in it
and it has a single page.

## How one is put together

An extension is a folder under `extensions/` containing a file called
`extension.pl`. That file holds facts, not code: the engine reads it and never
executes it.

The facts that matter most say which side loads what. `entry(engine, File)`
means the engine consults `File` when it boots. `entry(host, File)` means the
other language's runtime consults it instead. An extension can declare either
or both:

- **Python** declares both, so the engine can call into Python and Python can
  drive the engine.
- **C** declares both as well, in one file.
- **TypeScript** declares only `host`. The engine records that the extension
  exists and never loads anything, because the TypeScript side owns its own
  copy of the engine.
- **MORK** declares only `engine`. There is no MORK program to run; the engine
  reaches down to it for storage.

## When something is missing

If an extension's prerequisites are absent, it loads nothing and prints
nothing.

If it is built but broken, it raises, because that is a real fault.

A library that depends on one asks for it explicitly:

```metta
!(require-extension! mork)
```

If it is not there, the refusal names what is missing and gives you the command
that builds it.

## Adding your own

[The contract for adding an extension](./adding.md) covers what goes in the
folder: the vocabulary of the control file, the five scripts every extension
provides and the exit code they agree on, and where tests and benchmarks
live.

It also covers the three choices you make: which direction your extension
faces, whether a definition is called or compiled, and what a value looks
like when it crosses.

[Extending the engine](../engine/extending) is the other half: the nine points
the engine offers, and what each one costs.
