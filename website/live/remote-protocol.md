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
| `POST /match` | `{"space": "&self", "pattern": <atom>, "bound": <n>?}` | `{"atoms": [<atom>...]}` |
| `POST /atoms` | `{"space": "&self"}` | `{"atoms": [...]}` |
| `POST /add` | `{"space": "&self", "atom": <atom>}` | `{"added": true}` |
| `POST /remove` | `{"space": "&self", "atom": <atom>}` | `{"removed": <bool>}` |
| `POST /add_many` | `{"space": "&self", "atoms": [<atom>...]}` | `{"added": <n>}` |

`space` defaults to `&self` and selects which of the server's spaces
answers. `add_many` carries a batch in one request, the engine's own
bulk-door law on the wire: a batch is a transport optimisation and
never a semantic one, and `m.space(name).add(a, b, c)` against an
attached gateway crosses once.

`bound` on `/match` is optional and carries the caller's answer limit.
A server MAY honor it, and only exactly: at most `bound` answers, every
one a true match, which is only sound for a matcher that filters by
real unification, because truncating an over-approximated candidate
list can drop true answers past the cut. A server that cannot honor it
ignores the field entirely, which over-answers and stays sound. A
malformed bound (negative, fractional, or not a number) is a 400.

`GET /health` answers

```json
{"ok": true, "atoms": <n>, "protocol": 2,
 "capabilities": ["match", "enumerate", "add", "remove"],
 "bound": <bool>}
```

the wire contract naming its own revision before anyone speaks it.
Revision 2 adds the reflection the in-process seam already has:
`capabilities` names the seam operations the server admits, so a client
can ask before writing, and `bound` says whether `/match` honors the
bound field. `RemoteSpace.server_capabilities()` reads it from the
client side. An error is `{"error": "<sentence>"}` with a 4xx status; an
unknown operation is a 400 naming it; a non-POST method other than
`GET /health` is a 405. With a Bearer token configured,
a missing or wrong credential is refused with a 401 before the body is
read, and the comparison must be constant-time.

## What crosses the wire, and what does not

The in-process seam carries more than five operations, and the subset
that crosses is a decision, not drift. The projection:

| seam capability | on the wire | why |
|---|---|---|
| `match` | `POST /match` | the protocol's center |
| bounded match | `"bound"` on `/match`, advertised in health | trusted-Exact: only an exact matcher may truncate |
| `enumerate` | `POST /atoms` | |
| `add` | `POST /add` | |
| bulk add | `POST /add_many` | a transport batch, never a semantic one |
| `remove` | `POST /remove` | |
| capabilities | `"capabilities"` in health | reflection, ask before writing |
| `clear` | does not cross | destructive and tenant-wide; spell it `remove` with `$everything` |
| `plan` | does not cross | request-per-operation economics: a plan negotiation per match would cost more than it saves |
| pushdown classification | does not cross | the wire's match law is over-approximation, so exactness claims buy nothing remotely |
| `subscribe` | does not cross | request-response has no push channel; `lib_redis` is the standing-query story across processes |
| `rules` (equations) | does not cross | an equation compiles in the engine that stores it, and shipping source to another engine is a program migration, not a write |

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
than the engine's own matching is never allowed to be. That matching is
occurs-checked on purpose, Hyperon's own variable semantics, so a
rational-tree pair (`(f $y $y)` against a stored `(f (g $x) $x)`) is
NOT an answer a server owes; answering such a candidate anyway is legal
surplus the client discards. A server may answer candidates as the
stored atoms themselves or as the pattern instantiated by each match,
both of which preserve the pattern's answer set; the conformance suite
accepts either. This is what makes the protocol implementable in an
afternoon: filtering is an optimisation, not a correctness burden.
`petta.testing.check_space_provider` over an attached `RemoteSpace`
verifies exactly this, and its repeated-variable probes are the ones
that catch real matchers being subtly narrower than the law.

**Removal is by unification, one occurrence.** `remove` carries an atom
that may contain variables, and ONE stored atom unifying with it goes,
the multiset subtraction `remove-atom` is everywhere. Two stored copies
need two removals. Rename the pattern's and the stored atom's variables
apart before unifying: `(f $x 1)` must remove a stored `(f 2 $x)`.

**A space is a multiset.** Adding twice stores twice; `atoms` answers
duplicates; order promises nothing.

**Certifying an implementation.** `petta.testing.GatewayComplianceSuite`
is this page made executable: subclass it with a `gateway_url` fixture
and every promise above is checked against the running server, the
operations' semantics, the refusal ladder, the health reflection, bound
honored-or-ignored soundly, exact-or-refused wide integers,
and the conformance kit's match contract and round-trip law through an
attached `RemoteSpace`. Both reference servers pass it, and it caught
real divergences on both sides of the seam: MeTTaScript's unifier is
narrower than the wire unifier on some pairs, so its server carries the
reference unifier as a soundness envelope (over-approximation being
always legal, that server also ignores `bound` and advertises so), and
an early revision of the suite itself demanded rational-tree answers
the engine's occurs-checked matching never produces, which is the law
stated wrongly rather than a server behaving badly.

Measured on localhost with the reference server [2026-08-17]: a match
round trip is about 243 microseconds and an add about 216. The wire is
request-per-operation deliberately; a space whose queries are chatty
belongs behind the in-process seams instead, and `EXTENDING.md`
section 5 is that story.
