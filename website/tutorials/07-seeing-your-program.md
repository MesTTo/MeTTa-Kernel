# 07. Seeing your program

Use a trace to see what ran, lint to inspect stored program structure, and a derivation to see why an answer holds.

![An ancestor target beside its three supporting parent facts](/visuals/07-seeing-your-program.svg)

## Trace the reduction

`m.trace` runs source and records calls and answers. Depth follows recursive calls:

```python
def test_trace_nests_calls_and_carries_answers(m):
    m.run("(= (tr-fact $n) (if (== $n 0) 1 (* $n (tr-fact (- $n 1)))))")
    events = m.trace("!(tr-fact 3)")
    calls = [e for e in events if e.kind == "call"]
    exits = [e for e in events if e.kind == "exit"]
    assert [str(c.term) for c in calls] == [
        "(tr-fact 3)", "(tr-fact 2)", "(tr-fact 1)", "(tr-fact 0)",
    ]
    assert [c.depth for c in calls] == [0, 1, 2, 3]
    assert str(exits[-1].term) == "(tr-fact 3)"
    assert exits[-1].answer == 6
    assert events[0].kind == "call"
```

Calls enter from depth zero to the base case. Exit events carry answers back out. Builtins stay inside the compiled step, so the trace centers your equations.

## Lint the space

MeTTa can leave an unmatched expression unreduced. Lint catches common cases where that permissive behavior hides a mistake:

```python
def test_declared_but_undefined(m):
    m.run("(: ghost-fn (-> Number Number))")
    findings = m.lint()
    assert _kinds(findings) == ["declared-but-undefined"]
    assert findings[0].subject == "ghost-fn"
```

Lint also checks arrow arity, call arity, unbound body variables, duplicate equations, and possible undefined references. The final category is heuristic because an unfamiliar expression head may be intentional data.

## Read a derivation

A derivation records the equations and stored facts that support one answer:

```python
def test_multi_step_proof_names_equations_and_facts(metta):
    metta.run(
        "(par-d Tom Bob)\n(par-d Bob Ann)\n"
        "(= (anc-d $x $y) (match &self (par-d $x $y) $y))\n"
        "(= (anc-d $x $y) (let $m (match &self (par-d $x $m0) $m0) (anc-d $m $y)))"
    )
    proofs = metta.derivation(S["anc-d"](S.Tom, S.Ann))
    assert len(proofs) == 1
    proof = proofs[0]
    assert proof.answer == S.Ann
    assert {f.atom for f in proof.facts} == {
        S["par-d"](S.Tom, S.Bob),
        S["par-d"](S.Bob, S.Ann),
    }
    assert len(proof.rules) == 2
    text = str(proof)
    assert "by (= (anc-d $a $b)" in text
    assert "fact (par-d Tom Bob)" in text
```

See [Run and query](../guide/run-query#trace-a-reduction) for trace, lint, derivations, profiling, and failure explanations. Next, learn how the same atoms become diagrams in [08. The graph view](./08-graph-view).
