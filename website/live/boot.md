# Deployment as knowledge

Assembling an app is imperative ceremony: construct an engine, load sources, attach remotes, declare bridges, start a server. Each of those calls already exists on the surface, so a deployment can be written as what it is, knowledge. A manifest is a MeTTa file of `(boot ...)` forms:

```metta
;; app.metta
(boot (load "rules.metta"))
(boot (attach &crm "http://crm:8700"))
(boot (bridge &db (edge $a $b) (row edges (a $a) (b $b))))
(boot (serve (&self &crm) 8700))
```

and `metta.boot("app.metta")` performs it:

```python
import metta, sqlite3

booted = metta.boot("app.metta", connections={"&db": sqlite3.connect("app.db")})
booted.m.run('!(match &db (edge $a $b) ($a $b))')
```

Each form is sugar for exactly one existing call, performed in source order:

| form | the call it performs |
|---|---|
| `(load "rules.metta")` | `m.load`, the path resolved against the manifest's own directory |
| `(attach &crm "http://crm:8700")` | `metta.attach` over `metta.remote.RemoteSpace`, an optional third symbol naming the remote-side space |
| `(bridge &db <shape> <row>)` | `metta.tables.declare` then `TableBridge.from_context`, registered under the name |
| `(serve (&self &crm) 8700)` | `metta.remote.serve` with that space allowlist; port 0 picks a free one |

The vocabulary is closed and that is deliberate: Spring's config-XML era is what happens when a manifest grows into a second API. Boot forms only name calls the surface already documents, mixing manifest and imperative code is normal, and anything the vocabulary does not know refuses with every problem listed before a single form performs. A manifest declares rather than runs, so a `!` directive or an `(= ...)` definition in one refuses too; definitions belong in a file the manifest loads.

Two things cannot be written as atoms. A live database connection has no MeTTa spelling, so every bridged name must appear in `connections` and every connection must be claimed by a bridge. Serve policy is Python's: the `host`, `token`, `authorize`, and `ssl_context` keywords apply to every server the manifest starts.

## The deployment is queryable

Each performed form lands as its own `(boot ...)` atom in the booted space, which is what makes this more than config-file support. The running app answers questions about its own wiring:

```metta
!(match &self (boot (attach $space $url)) ($space $url))
; (&crm "http://crm:8700")
```

so `explain` can say what the app is attached to, a program can reason about its own topology, and the manifest stays live knowledge instead of dead YAML.

`boot` answers a `Boot` handle: `.m` is the engine (a fresh one, or pass `m=` to boot into your own), `.servers` holds every started server, `.performed` the forms that ran. The handle is a context manager and `close()` stops the servers it started; loaded knowledge and registered providers stay, because passive state belongs to the space, not to the assembler. A manifest that fails mid-way keeps the writes its performed prefix made, the same law the engine's own guards follow, closes any servers it started, and names the failing form.

See [`metta.manifest`](../reference/metta-manifest) for the surface, [Contexts and remotes](./contexts.md) for attach and serve themselves, and [`metta.tables`](../reference/metta-tables) for bridges.
