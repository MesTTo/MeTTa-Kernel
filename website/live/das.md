# The Distributed Atomspace

[DAS](https://github.com/singnet/das) is SingularityNET's distributed atomspace: a query engine over pluggable atom databases, with an attention broker that keeps Short-Term Importance values per context and orders query answers most-promising first, so a caller can stop early instead of drowning in a combinatorially large result. Around the query engine sit agents for link creation, inference, and evolutionary answer search, all reachable through one command-router service speaking HTTP and WebSocket with JSON both ways.

`petta.das` is the first-class client for that router. `DAS("http://localhost:40009")` opens a connection that pings, runs queries, counts, cancels, and passes any router command through with its parameters validated server-side. `query()` renders petta patterns as DAS MeTTa text, `$x` becoming DAS's `%x`, sends them as one execution, and streams the STI-ordered answers back over the WebSocket, each one carrying its variable bindings as petta atoms, the matched expressions themselves, and the attention numbers:

```python
    assert [a["x"] for a in answers] == [Gnd("monkey"), Gnd("chimp")]
    assert answers[0].expressions == [parse('(Similarity "human" "monkey")')]
    assert answers[0].importance == 0.5
```

Several patterns compose as `(and ...)`, DAS's own query tree, so the conjunction runs server-side where the attention ordering can prune it. `count()` runs the router's count mode and answers the server's own total without shipping answers. `execute()` is the escape hatch for the other agent commands, evolution, link creation, and context management, with parameters passed through verbatim. Streaming needs the `websocket-client` package, named in the error when absent.

`DASSpace` registers a connection as a read-only petta space, so DAS answers flow through the engine's own unification and join with native facts:

```python
        space = metta.space("&das-scripted")
        rows = space.query(S.Similarity(S.human, V.who))
        assert [row.who for row in rows] == [S.monkey]
```

Writes refuse by design: knowledge loads into DAS through [das-cli](https://github.com/singnet/das-toolbox), which owns the databases, the agents, and the `metta check` and `metta load` pipeline, and the refusal message says exactly that. The protocol shapes in `petta.das` are pinned by tests against the router's own event schema, and a live round-trip test runs whenever `PETTA_DAS_URL` answers ping.
