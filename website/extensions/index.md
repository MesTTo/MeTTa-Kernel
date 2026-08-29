<!--
Purpose: introduce the seat model and route to one area per shipped extension.
Guarantees: every folder under extensions/ carrying an extension.pl has an area
  here [tested: test_every_extension_has_a_site_area; commit=057cc60ec553c5820f95ee361f1fad057467f3c3]
-->

# Extensions

An extension is a folder under `extensions/` carrying an `extension.pl`, a
control file of facts the engine READS and never runs. Each one below owns its
own documentation in its own folder; these pages publish it.

There is no kind system. A folder is not a "binding" or a "backend": it is a
seat, and the two `entry/2` roles in its control file say which direction it
faces. `entry(engine, File)` is the engine reaching out and consulting the file
at boot; `entry(host, File)` is that seat's own runtime consulting it. Python
declares both, in two files. C declares both, in one. Node declares only `host`,
so the engine records the transport and never loads it. MORK declares only
`engine`.

| seat | what it is | roles |
|---|---|---|
| [PyMeTTa](./python/) | the `metta` library, and the engine reaching Python through janus | engine + host |
| [MeTTa-node](./node/) | MeTTa in TypeScript, the engine on swipl-wasm inside Node | host |
| [CMeTTa](./cmetta/) | the engine embedded in a C process through SWI's foreign interface | engine + host |
| [MORK](./mork/) | spaces on a Rust trie, over the FFI | engine |

The first three are hosts: you write a program in that language and it drives
the engine, so each carries a tutorial beside its page.
[PyMeTTa](./python/tutorial.md), [MeTTa-node](./node/tutorial.md) and
[CMeTTa](./cmetta/tutorial.md) each start from an empty directory and end at a
running program. MORK is a storage backend rather than a host, so there is no
program to write in it and its folder holds one page.

A seat whose declared needs are unmet loads nothing and says nothing, because
not built is not an error. A seat that is built and broken raises, because half
built is. A library that rests on one says so with
`!(require-extension! <name>)` and gets a refusal that names the missing half
and ends in the command that builds it.

## Adding one

[The contract for adding an extension](./adding.md) is what to put in the
folder: the control file's vocabulary, the five scripts and the exit rule they
share, where tests, examples and benchmarks go, and the three independent
choices a seat should offer: which direction it faces, whether a definition is
called or lowered, and what a value crosses as.

[Extending the engine](../engine/extending) is the other half of that story:
the nine extension points a seat is built out of, and what each one costs.
