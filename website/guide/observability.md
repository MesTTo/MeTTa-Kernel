# Observability

Nine tools, each answering a different question about a running program. Find
your question in the left column.

| Your question | What answers it |
|---|---|
| Why is this answer set empty? | `rows.why()`, one sentence naming the pattern, join, or guard that killed it |
| How was this answer derived? | [`metta.derivation`](../reference/metta-derivation): `Derivation`, `Step`, `Fact` proof trees |
| What will this query do, before I run it? | `prepare(...).explain()` and `cursor.explain()`, the [plan reflected](./run-query#explain-a-query) |
| What did this evaluation do, step by step? | [`metta.trace`](../reference/metta-trace), the reduction trace as events |
| What did this call cost? | `m.stats()`, engine counter deltas over a `with` block |
| Where did the time go? | `m.profile()`, the engine's own profiler over a block |
| What is tabling holding? | `(table-stats)`: tables, answers, hits, invalidations |
| What is silently wrong in this space? | [`metta.lint`](../reference/metta-lint); `lint_file(path)` anchors each finding to its `file:line` |
| What is changing, as it changes? | `m.subscribe(pattern)`, a [standing query](../live/standing-queries) over writes |

## Three that save the most time

**Ask `why()` before adding prints.** When a query returns nothing, `why()`
already knows which conjunct produced no rows. Re-running with print statements
finds out the same thing more slowly.

**Read `explain()` before profiling a slow foreign query.** The usual cause is
a pattern that stopped pushing down into the backend, and `explain()` shows
that without running the query at all.

**Trust `stats()` inferences over wall clock.** The inference counter is
deterministic: the same workload gives the same number on any machine, under
any load. Wall clock does not. This repository gates its own benchmarks on
inferences for that reason.

## The engine describes itself

What the engine has registered, declared, and served is stored as ordinary
atoms in the `&metta` space, so you can query it the same way you query
anything else. [Reflection and steering](../live/reflection) covers that.
