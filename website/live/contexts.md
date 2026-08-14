# Contexts and remotes

Spaces already isolate contexts inside one engine. Two mechanisms extend that across boundaries: bridge rules connect spaces, and `petta.remote` connects engines.

`petta.bridge(src, pattern, dst, template)` is a bridge rule in the multi-context-systems sense: when an atom unifying with the pattern arrives in the source space, the template's instantiation under the match's bindings lands in the target, and with `on="both"` a removal in the source removes the instantiation from the target. The rule is a standing query, delivered inside the write that triggered it, and `cancel()` ends it:

```python
def test_bridge_rules_connect_spaces(metta):
    src = metta.fresh_space()
    dst = metta.fresh_space()
    rule = bridge(src, S.alarm(V.zone), dst, S.notify(V.zone), on="both")
    try:
        src.add(S.alarm(S.kitchen))
        assert dst.query(S.notify(V.z)).one().z == S.kitchen
        src.remove(S.alarm(S.kitchen))
        assert dst.query(S.notify(V.z)) == []
    finally:
        rule.cancel()
        src.drop()
        dst.drop()
```

`petta.remote` makes an engine a context another engine can reach. `serve(m, spaces=[...])` exposes spaces over HTTP speaking the same tagged wire the local boundary speaks, with the allowlist as the whole access model; `attach(m, "&hq", url)` registers a served space here as a foreign space. A remote space then drops into `(match &hq ...)` like any space, one local match joins remote rows with local facts, and writes cross through `add-atom` and `remove-atom`. The local engine keeps unification for itself, so a stale or lying remote can only cost time, not soundness.

A context is a process: serving and attaching within one process cannot join through the local engine, because one runtime lock guards both sides of that call. Two engines, two processes, is the deployment this exists for; in-process, spaces already share the engine and need no wire.

The shape follows SingularityNET's DAS gateway, a single transport method carrying the space and pattern, and metta-wam's `metta_server`; the transport is injectable, so tests and other carriers replace HTTP with any callable of the same contract. The target of a bridge rule only needs `add` and `remove`, so a bridge into an attached remote space propagates facts between engines.

See [`petta.remote`](../reference/petta-remote) for the surface.
