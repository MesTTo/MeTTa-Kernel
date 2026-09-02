<!--
Purpose: explain provider capability declarations, answer fidelity, and the
attachment contract.
Guarantees: Python examples use canonical public atom classes.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# The contract: how backends attach

A backend joins MeTTa by declaring what it can do, as atoms in the
`&metta` space, and the engine routes queries by those declarations. No
backend gets its own code path inside the engine.

## One model

A query is an expression with variables. An answer is three things. A
substitution for the variables. A residue, meaning the part of the query the
answerer did not discharge, which the engine evaluates. And an annotation in
a declared semiring: a score, a probability, a source term, or the plain
Boolean 1 that makes all of this vanish. A provider that knows
nothing about any of this yields plain atoms, and that is the complete
degenerate case: substitution from unification, residue empty,
annotation 1. Everything a backend can declare refines this triple and
nothing else.

The routing rule is the language's own. A call dispatches by unifying
against equation heads; a query dispatches by unifying against declared
shapes, most specific first, and two overlapping declarations that
disagree are an error naming both and the query they disagree on. This
is the critical-pair condition from term rewriting, applied to
declarations instead of rules.

## The fidelity ladder

The load-bearing declaration is `handles`:

```metta
(handles &rows (edge $x $y) Exact)
(handles &rows (edge $x $x) Sound)
(handles &rows (edge (in $a) $b) Refuse)
```

`Exact` says every candidate the backend yields for this shape is an
answer, so the caller's bound may reach it: `(take 2 ...)` becomes the
backend's own `LIMIT 2`. `Sound` says the backend over-approximates and
the engine re-unifies, which is always safe. `Refuse` says the backend
cannot answer this shape at all, and asking is a loud error rather than
a silent empty set. `(in $a)` marks a position that must arrive bound,
so a scan-only source is two declarations: refuse bound lookups, serve
free scans exactly.

The same ladder appears in query engines as filter pushdown: Apache
DataFusion's `TableProviderFilterPushDown` distinguishes exact from
inexact in the same words, and Apache Calcite plans against declared
capabilities per source. The `(in ...)` adornments are the
bound-or-free argument annotations of the deductive-database literature
and Mercury's argument modes; the refusal of a join whose inner side
needs a bound lookup against a scan-only source is the classic
access-pattern check, done at plan time.

## What else a context declares

- `(source &s linear)` marks a one-shot source, a cursor or a feed. Its
  second consumption is an error; the undeclared floor answered a
  silently empty set from the drained object.
- `(on-error &s (edge $x $y) keep)` turns a mid-stream backend failure
  into one `(Error <query> <reason>)` answer beside the answers that
  already streamed. `empty` ends the stream by declaration; the default
  aborts. Transport failures, a connection gone rather than a backend
  wrong, always abort.
- `(writes &s transactional)` lets `(transaction ...)` commit or roll
  back the backend with the engine, through the provider's own
  begin/commit/rollback. Undeclared foreign writes inside a transaction
  are refused, because a write that survives a rollback is the wrong
  answer.
- `(context &s closed-world)` permits negation to consult the context.
  Negation as failure reads absence as falsity, and that is only sound
  over a world the answerer holds whole.
- `(annotations &s ranked)` fixes the semiring answers are weighted in.
  `(top k ...)` answers the k best; the bound reaches the backend only
  when it also declares `(emits &s best-first)` and the shape routes
  `Exact`, because the first k of a best-first emission are the k best
  and otherwise a pushed bound returns the wrong k. `prov` carries
  source terms, multiplied along joins, readable per answer with
  `(annotation)`; this is the provenance-semiring construction from
  database theory.
- `(merge (edge $x $y) fair)` interleaves several contexts' answer
  streams round-robin for `(match (superpose (&a &b)) ...)`; the
  default is depth, one space after another.
- `(on &src (fact $x) (insert &mirror (mirrored $x)))` is a bridge:
  when a matching atom lands, run the managed operation under the
  match's bindings. This is a bridge rule in the multi-context systems
  sense, with insert, retract and revise as the managed heads.
- `(admits &pool Space)` and `(capacity &pool 8)` make a pool: a space
  whose membership is a type judgement and whose size is bounded. A
  thread pool is a space whose atoms are spaces, queryable like
  anything else.

Ask the engine what it will do before running anything:

```metta
!(explain (match &rows (edge $x $y) $y))
```

answers the route as atoms: the entry that matched, its fidelity,
whether a bound would push, and every declaration above. What `explain`
says is what execution then does; the test suite holds it to that.

## Answers with bindings

A Python provider or operation may answer bindings for the query's own
variables instead of an atom:

```python
from metta import Answer, Bindings, Symbol, parse

def match(self, pattern, *, limit=None):
    yield Bindings({pattern.children[2]: Symbol("b")})
    yield Answer(value=parse("(edge a b)"), k=0.9)
```

The atoms stay derivable by applying the bindings to the pattern; an
explicit value is the candidate-with-bindings form and must agree with
its own bindings. A residue makes an answer conditional, closed by the
engine against any context. This is the grounded-operation calling
convention of Hyperon's `execute_bindings`, and the residue is the
answer-constraint store of constraint logic programming: `(> $y 3)`
travelling with an answer is the same object a CLP system returns.

## The floor

Undeclared is always today's behaviour. A provider written before any
of this, three methods on a class, keeps working unchanged, and every
declaration only adds: pushdown where none was licensed, loud errors
where silence was wrong, ordering where none existed. The conformance
kit (`metta.testing.check_space_provider`) checks a provider against
the same laws the engine holds it to, including the ones that only
show on open and repeated-variable patterns, and
`metta.testing.record_replay` makes a nondeterministic backend's
session a replayable oracle.

## Sources

Almost none of this is new. Each part of the contract comes from somewhere:

| Part of the contract | Where it comes from |
|---|---|
| filter pushdown, per-source planning | Apache Calcite, Apache DataFusion, Garlic |
| argument adornments and access patterns | Datalog binding-pattern analysis, Mercury modes |
| one-shot and consuming sources | Linda, whose `in` consumes where `rd` does not; Aardappel's linear tree spaces |
| translation with declared fidelity | the Distributed Ontology Language; multi-context systems with bridge rules |
| plan and capability interchange | Substrait, the WebAssembly Component Model |
| annotated answers | provenance semirings, K-relations |
| answers carrying bindings and residues | Hyperon's grounded interface, constraint logic programming |
| replayable host interaction | CakeML's foreign-function oracle |
