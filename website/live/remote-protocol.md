# The remote space protocol

`petta.remote.serve()` exposes spaces over HTTP and `attach()` consumes
them, and the wire between them is small enough to implement in an
afternoon in any language. This page is the contract for the other end:
what a server must answer so that `(match &yours ...)` in a PeTTa
program reaches atoms your process holds.

Two reference implementations ship in the repository under
`python/examples/integration/typescript_space/`: a zero-dependency
TypeScript server, and a variant whose atoms live in a MeTTaScript
space, so two MeTTa engines meet through this one seam. Both pass the
conformance kit through `attach()`.

## Operations

Four POST operations, JSON bodies both ways. `Content-Length` is
required (no `Transfer-Encoding`), bodies are capped at 16 MiB, and the
body must be one JSON object.

| request | body | answer |
|---|---|---|
| `POST /match` | `{"space": "&self", "pattern": <atom>}` | `{"atoms": [<atom>...]}` |
| `POST /atoms` | `{"space": "&self"}` | `{"atoms": [...]}` |
| `POST /add` | `{"space": "&self", "atom": <atom>}` | `{"added": true}` |
| `POST /remove` | `{"space": "&self", "atom": <atom>}` | `{"removed": <bool>}` |
| `POST /add_many` | `{"space": "&self", "atoms": [<atom>...]}` | `{"added": <n>}` |

`space` defaults to `&self` and selects which of the server's spaces
answers. `add_many` carries a batch in one request, the engine's own
bulk-door law on the wire: a batch is a transport optimisation and
never a semantic one, and `m.space(name).add(a, b, c)` against an
attached gateway crosses once. `GET /health` answers
`{"ok": true, "atoms": <n>, "protocol": 1}`, the wire contract naming
its own revision before anyone speaks it. An error is `{"error": "<sentence>"}` with a 4xx status; an
unknown operation is a 400 naming it. With a Bearer token configured,
a missing or wrong credential is refused with a 401 before the body is
read, and the comparison must be constant-time.

## Atoms on the wire

An atom is a tagged JSON array, the same wire the local Python boundary
speaks:

```json
["s", "edge"]                 a symbol
["v", "x"]                    a variable
["n", 42]                     a number
["g", "text"]                 a grounded value; strings cross this way
["e", [["s","edge"], ["s","a"], ["v","x"]]]   an expression
```

Wide integers deserve a decision, not an accident: PeTTa's own numbers
are exact at any width, so a server whose JSON parser rounds past 2^53
must refuse such a payload rather than store a different atom. The
reference implementation answers 400 naming the literal.

## Semantics a server must keep

**Match may over-approximate and may never under-approximate.** The
attaching engine keeps unification for itself and re-unifies every
candidate, which is how bindings enter the local program; answering
every stored atom for every pattern is always correct, answering fewer
than unify is never allowed to be. This is what makes the protocol
implementable in an afternoon: filtering is an optimisation, not a
correctness burden. `petta.testing.check_space_provider` over an
attached `RemoteSpace` verifies exactly this, and its repeated-variable
probes are the ones that catch real matchers being subtly narrower
than unification, a rational-tree divergence included.

**Removal is by unification, every occurrence.** `remove` carries an
atom that may contain variables, and every stored atom unifying with it
goes, the multiset reading `remove-atom` has everywhere. Rename the
pattern's and the stored atom's variables apart before unifying:
`(f $x 1)` must remove a stored `(f 2 $x)`.

**A space is a multiset.** Adding twice stores twice; `atoms` answers
duplicates; order promises nothing.

**Certifying an implementation.** `petta.testing.GatewayComplianceSuite`
is this page made executable: subclass it with a `gateway_url` fixture
and every promise above is checked against the running server, the
four operations' semantics, the refusal ladder, wide-integer refusal,
and the conformance kit's match contract and round-trip law through an
attached `RemoteSpace`. Both reference servers pass it, and it caught a
real one: MeTTaScript's unifier refuses rational-tree matches that the
protocol's law answers, so its server carries the reference unifier as
a soundness envelope, over-approximation being always legal.

Measured on localhost with the reference server [2026-08-17]: a match
round trip is about 243 microseconds and an add about 216. The wire is
request-per-operation deliberately; a space whose queries are chatty
belongs behind the in-process seams instead, and `EXTENDING.md`
section 5 is that story.
