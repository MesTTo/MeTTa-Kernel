# The remote space protocol

`petta.remote.serve()` exposes spaces over HTTP and `attach()` consumes
them, and the wire between them is small enough to implement in an
afternoon in any language. This page is the contract for the other end:
what a server must answer so that `(match &yours ...)` in a PeTTa
program reaches atoms your process holds.

Two reference implementations ship in the repository under
`bindings/python/examples/integration/typescript_space/`: a zero-dependency
TypeScript server, and a variant whose atoms live in a MeTTaScript
space, so two MeTTa engines meet through this one seam. Both pass the
conformance kit through `attach()`.

## Operations

Eight POST operations, JSON bodies both ways. `Content-Length` is
required (no `Transfer-Encoding`), bodies are capped at 16 MiB, and the
body must be one JSON object.

| request | body | answer |
|---|---|---|
| `POST /match` | `{"space": "&self", "pattern": <atom>, "bound": <n>?}` | `{"atoms": [<atom>...]}` |
| `POST /ask` | `{"space": "&self", "pattern": <atom>, "batch": <n>?, "bound": <n>?}` | `{"atoms": [...], "cursor": <id>\|null}` |
| `POST /next` | `{"cursor": <id>, "batch": <n>?}` | `{"atoms": [...], "cursor": <id>\|null}` |
| `POST /stop` | `{"cursor": <id>}` | `{"stopped": <bool>}` |
| `POST /atoms` | `{"space": "&self"}` | `{"atoms": [...]}` |
| `POST /add` | `{"space": "&self", "atom": <atom>}` | `{"added": true}` |
| `POST /remove` | `{"space": "&self", "atom": <atom>}` | `{"removed": <bool>}` |
| `POST /add_many` | `{"space": "&self", "atoms": [<atom>...]}` | `{"added": <n>}` |

`space` defaults to `&self` and selects which of the server's spaces
answers. `add_many` carries a batch in one request, the engine's own
bulk-door law on the wire: a batch is a transport optimisation and
never a semantic one, and `m.space(name).add(a, b, c)` against an
attached gateway crosses once.

`bound` on `/match` and `/ask` is optional and carries the caller's
answer limit. A server MAY honor it, and only exactly: at most `bound`
answers, every one a true match, which is only sound for a matcher that
filters by real unification, because truncating an over-approximated
candidate list can drop true answers past the cut. A server that cannot
honor it ignores the field entirely, which over-answers and stays sound.
A malformed bound (negative, fractional, or not a number) is a 400.

`GET /health` answers

```json
{"ok": true, "atoms": <n>, "protocol": 3,
 "capabilities": ["match", "enumerate", "add", "remove", "stream"],
 "bound": <bool>}
```

the wire contract naming its own revision before anyone speaks it.
Revision 2 added the reflection the in-process seam already has:
`capabilities` names the seam operations the server admits, so a client
can ask before writing, and `bound` says whether `/match` honors the
bound field. Revision 3 adds `stream`, the ask/next/stop lifecycle
below, which every gateway at this revision speaks.
`RemoteSpace.server_capabilities()` reads it from the
client side. An error is `{"error": "<sentence>"}` with a 4xx status; an
unknown operation is a 400 naming it; a non-POST method other than
`GET /health` is a 405. With a Bearer token configured,
a missing or wrong credential is refused with a 401 before the body is
read, and the comparison must be constant-time.

## Lazy answers: the ask/next/stop lifecycle

This is the part of the contract every binding inherits, in any
language, over any transport. `/match` computes the whole answer set
before anything crosses, which is what `m.query()` does in-process.
`/ask` opens a cursor and answers the first chunk, `/next` pulls the
next one, and `/stop` releases it, which is what `m.stream()` does
in-process. A client that wants two answers of a million-answer join
takes them and stops, and the serving engine computes two.

```
POST /ask   {"space": "&hq", "pattern": ["e", [["s","users"],["v","id"],["v","n"]]], "batch": 1}
     ->     {"atoms": [ ...one atom... ], "cursor": "Yy8mB1Rk..."}
POST /next  {"cursor": "Yy8mB1Rk...", "batch": 1}
     ->     {"atoms": [ ...one atom... ], "cursor": "Yy8mB1Rk..."}
POST /stop  {"cursor": "Yy8mB1Rk..."}
     ->     {"stopped": true}
```

The lineage is SWI's own `library(pengines)`, whose create/ask/next/stop
is the same lifecycle over the same kind of wire, and Tarau's engines
(*A Hitchhiker's Guide to Reinventing a Prolog Machine*, ICLP 2017),
which state it as a design law: an engine yields one answer and, if
asked, resumes.

**A batch is a chunk, a bound is a cut.** `batch` says how many answers
one reply may carry and defaults to 1, pengines' own default for the
same field. Chunking is sound for every server, because it hands back
part of an answer set with the rest still reachable. Bounding is only
sound for an exact matcher, for the reason `bound` already carries
above. A reply may carry fewer atoms than the batch and never more.

**The cursor is the continuation, and it is also the more-flag.** A
reply whose `cursor` is a string names the token `/next` and `/stop`
take. A reply whose `cursor` is `null` ends the stream: the server has
already released it, and a client that keeps the token gets a refusal
rather than an empty answer. This is what keeps the promise honest,
because a boolean "is there another one" could only be answered by
computing another one, and the whole point is not to.

**A short chunk ends the stream.** A server that has nothing further
answers the atoms it has and a `null` cursor. An empty chunk beside a
live cursor is a protocol violation, since it would spin a client
forever; the shipped client refuses one rather than looping.

**`/next` on a cursor the server no longer holds is an error, not an
empty answer.** Answering nothing would say the enumeration ended, and
under-approximating is the one thing this protocol forbids. `/stop` on
one is the plain `{"stopped": false}`, because a client calls stop from
a finally-block where the stream may have ended already, and stop is
idempotent by design.

**A cursor is server state, so it is bounded and owned.** A server
releases a cursor nobody has pulled from after an idle deadline, refuses
to hold more than a ceiling of them at once, and releases every one it
still holds when it shuts down. pengines bounds the same resource the
same two ways and picks 300 seconds for the first; `petta.remote.serve`
takes `cursor_idle` and `cursor_limit`, and the TypeScript reference
server takes `--cursor-idle` and `--cursor-limit`.

**Whether a server actually defers the work is its own affair.** What
the contract fixes is the shape that makes deferring possible, so that
a client can rely on it: a store holding ten atoms in an array has
nothing to defer, and a gateway over a real query engine has everything
to. PeTTa's own gateway defers: each cursor is an SWI engine holding the
join's state between pulls, so taking two answers costs two answers'
work. Measured 2026-08-20 over real HTTP, 1,250 inferences for two
answers whether the enumeration held ten or ten thousand, against 1,839
and 1,490,407 for the eager door over the same spaces
[`test_two_answers_cross_the_wire_without_the_third_being_computed`].

**An answer set past the body cap crosses only in chunks.** Bodies are
capped at 16 MiB in both directions, so `/match` cannot answer a set
larger than that at all; the lifecycle is what carries it
[`test_an_answer_set_too_large_for_one_body_still_crosses_in_chunks`].

On the client side `RemoteSpace.stream(pattern, batch=...)` is the lazy
door and `match()` stays the eager one, the same split `stream()` and
`query()` make in-process. `petta.remote.attach(m, "&hq", url, batch=1)`
puts an attached space's matching on the lazy door, so a MeTTa `once`
over it stops the serving engine too.

## What crosses the wire, and what does not

The in-process seam carries more than five operations, and the subset
that crosses is a decision, not drift. The projection:

| seam capability | on the wire | why |
|---|---|---|
| `match` | `POST /match` | the protocol's center |
| bounded match | `"bound"` on `/match` and `/ask`, advertised in health | trusted-Exact: only an exact matcher may truncate |
| streamed answers (`m.stream`) | `POST /ask`, `/next`, `/stop`, advertised as `stream` | lazy answers are part of the contract on every transport |
| `enumerate` | `POST /atoms` | one shot: the give-me-everything door has no early exit to protect |
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
speaks: `["e", [["s","edge"], ["s","a"], ["v","x"]]]` is `(edge a $x)`.

`CODEC.md` in the repository root is the grammar, and it is the one
authority for it: the tags and their payloads, the identity law for
variables, the exactness law for numbers, and
`tests/codec/corpus.json`, the golden corpus your server can be run
against. A gateway speaks the CORE PROFILE, `s v n g e`. Read that page
before writing the parsing half of a server; everything below is the
HTTP half, which is this page's own.

Two of its rules bite a gateway in particular, both about answering a
different atom than the one you were given. PeTTa's numbers are exact at
any width, so a server whose JSON parser rounds past 2^53 must refuse
the payload; the reference implementation answers 400 naming the
literal. And an integer and a float are different atoms even at the same
value, `!(== 1.0 1)` being `False`, so a language with one number type
has to carry the distinction some other way or refuse it.

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
honored-or-ignored soundly, exact-or-refused wide integers, the
ask/next/stop lifecycle answering the eager door's answer set at every
batch and refusing a cursor it no longer holds,
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
