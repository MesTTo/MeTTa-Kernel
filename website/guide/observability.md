# Observability: which door answers which question

Nine doors watch a running system, each answering a different question. They are deliberately distinct things, not one API, so the map is the feature:

| the question you have | the door that answers it |
|---|---|
| why is this answer set empty? | `rows.why()`, one sentence naming the pattern, join, or guard that killed it |
| how was this answer derived? | [`metta.derivation`](../reference/metta-derivation): `Derivation`, `Step`, `Fact` proof trees |
| what will this query do, before running it? | `prepare(...).explain()` and `cursor.explain()`, the [plan reflected](./run-query#explain-a-query) |
| what did this evaluation do, step by step? | [`metta.trace`](../reference/metta-trace), the reduction trace as events |
| what did this call cost? | `m.stats()`, engine counter deltas over a with-block |
| where did the time go? | `m.profile()`, the engine's own profiler over a block |
| what is tabling holding? | `(table-stats)`, tables, answers, hits, invalidations |
| what is silently wrong in this space? | [`metta.lint`](../reference/metta-lint); `lint_file(path)` anchors each finding to its `file:line` |
| what is changing, as it changes? | `m.subscribe(pattern)`, the [standing query](../live/standing-queries) watching writes |

Three habits make them compose. Reach for `why()` before re-running a query with prints, because it already knows which conjunct answered nothing. Read `explain()` before profiling a slow foreign query, because the usual cause is a pattern that stopped pushing down, and that is visible without running anything. And when a number needs to be trusted, use `stats()` inferences rather than wall clock: the counter is deterministic on any machine, which is also why this repository gates its own benchmarks on it.

The engine's own self-description is a space: [reflection](../live/reflection) reads the `&petta` contract atoms, so `explain`-style questions about what is declared, registered, and served are ordinary matches.
