# 02. Spaces and matching

Put three facts in a space, then ask for a shared relationship. A space keeps atoms and provides structural matching over them.

![Three parent facts and a selected query pattern](/visuals/02-spaces-and-matching.svg)

The first tutorial example in the repository stores a family chain and joins two patterns:

```python
# Atoms are Python values: S mints symbols, V variables, application builds
# expressions, and none of it costs an engine call.
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann), S.Parent(S.Ann, S.Zoe))
rows = m.match(S.Parent(V.gp, V.p), S.Parent(V.p, V.gc))
check("join count", len(rows), 2)
check("first grandparent", (rows[0].gp, rows[0].gc), (S.Tom, S.Ann))
```

Each `Parent` expression is stored without evaluation. In the first pattern, `$gp` and `$p` can bind. In the second, the same `$p` must keep the value already found. Shared variables therefore form a join.

For the visual's smaller question, the pattern `(parent Ada $child)` has the same head and arity as each fact. It accepts `Ben` and `Cleo` at the open position. The fact `(parent Ben Dana)` does not match because its second child is not `Ada`.

`m.match(...)` returns `Rows`. Variable names become columns in first-appearance order, so `$child` is available as `row.child`. No match produces an empty `Rows`, not a null atom.

Use the [spaces guide](../guide/spaces) for named spaces, persistence, and Python-backed providers. Use [Run and query](../guide/run-query) for joins, guards, limits, assumptions, and prepared queries. Next, define a rewrite in [03. Equations and evaluation](./03-equations-and-evaluation).
