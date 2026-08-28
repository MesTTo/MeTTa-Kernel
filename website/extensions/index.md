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
| [Python](./python.md) | the `metta` library, and the engine reaching Python through janus | engine + host |
| [Node](./node.md) | MeTTa in TypeScript, the engine on swipl-wasm inside Node | host |
| [C](./cetta.md) | the engine embedded in a C process through SWI's foreign interface | engine + host |
| [MORK](./mork.md) | spaces on a Rust trie, over the FFI | engine |

A seat whose declared needs are unmet loads nothing and says nothing, because
not built is not an error. A seat that is built and broken raises, because half
built is. A library that rests on one says so with
`!(require-extension! <name>)` and gets a refusal that names the missing half
and ends in the command that builds it.

[Extending the engine](../engine/EXTENDING.md) is the other half of this story:
the nine extension points a seat is built out of, and what each one costs.
