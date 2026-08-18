# Run and query

Use `run` for MeTTa source, `eval` for a term already built in Python, and `query` for structural matches against a space. Variables shared by several query patterns form joins. Rows expose the query variable names as attributes.

Queries also accept guards, answer bounds, temporary assumptions, and prepared shapes:

```python
m.add(S.Age(S.Tom, 62), S.Age(S.Bob, 40))
m.query(S.Age(V.p, V.n), where=(V.n >= 60) & (V.n <= 70))
# Rows[p, n]([Row(p=Sym('Tom'), n=Gnd(62))])

with m.assuming(S.Parent(S.Ann, S.Zoe)):
    m.query(S.Parent(S.Ann, V.c))    # Rows[c]([Row(c=Sym('Zoe'))])

grand = m.prepare(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
grand.solve()
# Rows[x, y, z]([Row(x=Sym('Tom'), y=Sym('Bob'), z=Sym('Ann'))])
```

`where=` is evaluated by the engine for each match. `limit=` stops the engine at the requested count. `assuming(...)` adds facts only for the `with` block. `prepare(...)` fixes the query shape once, and `solve(given=...)` can add facts for one solve without leaving them behind.

## Bounds, stats, and captured output

A query whose join size is unknown, or a program whose recursion depth is someone else's data, should not be able to hold your process. `timeout=` (seconds) and `inferences=` (engine steps) bound any `run`, `eval`, `value`, `query`, or `solve` call with the engine's own guards:

```python
try:
    m.run("!(spin 100000000)", timeout=0.05)
    raise AssertionError("the time bound did not fire")
except petta.TimeLimitError:
    check("a 50ms bound stops a spin that would run for minutes", True)
```

Each bound raises its own error, `TimeLimitError` or `InferenceLimitError`, both under `ResourceLimitError`. An inference bound is the deterministic twin of a timeout: the same call stops at the same step on every machine. Whatever the call completed before the stop, writes included, stands, which is what stopping a computation mid-way means everywhere. Ctrl-C reaches a running evaluation too: the runtime installs janus's heartbeat at startup, so a `KeyboardInterrupt` lands within milliseconds instead of queueing until the goal ends, at an interval measured to cost nothing.

`m.stats()` reads the engine's own counters around a with-block, and `capture=True` on `run` and `eval` returns the printed text beside the answers:

```python
m.add_table("edge", [(i, i + 1) for i in range(200)])
rows = m.query(S.edge(V.a, V.b), S.edge(V.b, V.c), timeout=30.0)
check("a generous bound changes nothing", len(rows), 199)

with m.stats() as s:
    m.query(S.edge(V.a, V.b), S.edge(V.b, V.c))
check("the stats block counts the engine steps spent", s.inferences > 100)

groups, text = m.run("!(println! (hello world)) !(+ 1 2)", capture=True)
check("captured print output", "(hello world)" in text)
check("the answers still arrive beside it", groups[1], [3])
```

After the block, `s.inferences`, `s.cputime`, `s.walltime`, `s.gc_count`, `s.gc_freed`, and `s.gc_time` carry what the block spent. The full runnable example is [`operations/engine_controls.py`](https://github.com/trueagi-io/PeTTa/blob/main/python/examples/operations/engine_controls.py).

Control signals hold everywhere, by engine design: a bound, a Ctrl-C, or an `interrupt()` cannot be eaten by the evaluation it is stopping, not even by a program's own `(catch ...)`. That is the same reasoning that puts `KeyboardInterrupt` outside `Exception` in Python.

## Errors are data, until you ask for a value

MeTTa reports a soft failure by answering an `(Error culprit reason)` atom: an error is a RESULT, one element of the answer multiset, so one failed branch never kills the others. Write the idiom with an `if` guard, because every matching equation runs:

```python
m.run('(= (safe-div $x $y) (if (== $y 0) '
      '(Error (safe-div $x $y) "division by zero") (/ $x $y)))')
m.eval("(safe-div 1 0)")
# [Expr('(Error (safe-div 1 0) "division by zero")')]
```

The doors split by what they answer. The aggregation doors, `eval()`, `run()`, `fn.all()` and the streams, keep error atoms as data, exactly as the multiset semantics says. A door that answers a single value has no multiset for the error to be data in, so `one()`, `first()` and calling a function raise `MettaResultError` instead, carrying the parts:

```python
try:
    m.fn("safe-div")(1, 0)
except petta.MettaResultError as e:
    e.atom                  # (Error (safe-div 1 0) "division by zero")
    e.culprit               # (safe-div 1 0)
    petta.decode(e.reason)  # 'division by zero'
```

Query rows are bindings rather than evaluation answers, so a stored error record flows through every `Rows` door untouched; `rows.raise_for_errors()` is the explicit bridge for callers who want the `raise_for_status` reading, raising one error plainly and several as one `ExceptionGroup`.

Two more things hold across the whole library. Every exception it raises on purpose carries machine-readable parts beside the message, the way `OSError.errno` does: `.atom`, `.space`, `.operation` and `.capability`, each `None` when the error has no such part. And an exception the library raises inside a Python callback, a space provider refusing a write for instance, crosses the engine and re-arrives as the very same object with its fields intact, rather than as a transcript of itself.

## Take the first few, without computing the rest

`query` is eager, so slicing it trims after the work is done:

```python
rows = m.query(pattern)[:3]        # computes every row, keeps three
rows = m.query(pattern, limit=3)   # the engine stops at three
with m.stream(pattern) as cursor:
    rows = cursor[:3]              # pulls three and stops
```

Over 2,000 stored atoms those measured 26,055, 2,232 and 20 inferences for the same three rows, and the first gap grows with the space. Reach for `limit=` when you want a bounded answer set and for `stream` when you want to take rows until you have seen enough; the cursor keeps the join's state inside an engine between pulls, so a huge join costs one row of work per row actually taken.

A cursor refuses what would need the whole stream, and each refusal says why: `len(cursor)` (use `space.count(pattern)`), `cursor[-1]`, `cursor[-3:]` and `cursor[::2]`. Skipping a row still pulls it, and counting from the end means knowing where the end is. Because a cursor implements the iterator protocol exactly, wrappers compose with no adapter: `tqdm(m.stream(pattern))` shows progress one pulled row at a time.

## Explain a query

`prepare(...).explain()` and a cursor's `explain()` answer the query's plan without running it, polars' `LazyFrame.explain` and SQL's `EXPLAIN` pointed at the space seam. When a query over a Python-backed space is slow, the first question is what pushed down, and this is that answer:

```python
sp = m.space("&db")
print(sp.prepare(parse("(edge $a $b)"), parse("(other $b $c)")).explain())
# query over &db: (edge $a $b), (other $b $c)
#   (edge $a $b)   exact    the provider's own pushdown method
#   (other $b $c)  inexact  unclaimed; silence is inexact and candidates re-unify
#   conjunction: no provider claim; the engine joins left to right
#   a bound reaches the provider only where the class is exact
```

Each pattern's line shows its pushdown class and which rule decided it: a declared `(handles ...)` entry, the provider's own `pushdown` method, or silence, in exactly the precedence the match uses. The conjunction line names what a planning provider claimed whole and what the engine joins. A shape a declaration refuses reports as `REFUSED` with the entry that said so, a stored space answers the one true line (engine unification), and a `where=` guard shows where it runs. Nothing is executed and no row is pulled; the report reflects decisions the seam has already made.

## Memoize a function

Tabling is the engine's own memoization: declare a function tabled, and every distinct call computes once, with later calls of the same shape answering from the table. After `!(import! &self (library lib_tabling))`, the declaration is `!(tabled (spin-down $n))`, made after the function is defined, because instrumenting a name that does not exist yet is refused by name and arity instead of silently tabling nothing.

```python
    with m.stats() as first:
        assert m.run("!(spin-down 200000)") == [[S.done]]
    with m.stats() as second:
        assert m.run("!(spin-down 200000)") == [[S.done]]
    # The second call answers from the table: orders of magnitude fewer
    # engine steps than the first recursion.
    assert second.inferences < first.inferences / 10
```

Tabling changes what a function means, so the admission burden is yours: it is sound for a pure function whose equations and read spaces stay put while its tables live, whose callers never observe answer order or duplicates, and whose call modes stay bounded. Hyphenated and uppercase names work, repeated declarations are cumulative and idempotent, and a named space's functions instrument their own module. `(untabled ...)` removes the instrumentation, `(table-clear ...)` abolishes one function's cached answers and keeps the declaration, `(table-clear-all)` abolishes every table, and `s.table_bytes` from `m.stats()` watches the memory.

Every live declaration is also a fact: `(tabled space name arity)` in the `&petta` reflection space, input arity, added on declare and removed on undeclare, so a program can ask what is memoized right now:

```python
    reflection = MeTTa(REFLECTION_SPACE)
    m.run("(= (reflected-fn $n) (+ $n 1))")
    assert m.run("!(tabled (reflected-fn $n))") == [[True]]
    pattern = S.tabled(S[m.space_name], S["reflected-fn"], V.a)
    assert [row.a for row in reflection.query(pattern)] == [1]
```

Tabling state dies with the space life. A dropped or cleared space takes its declarations, its tables, and its `&petta` records with it, so a pooled name's next life cannot be answered by a dead life's cache; the suite pins this by redefining a function in a reused space and requiring the new answer.

## Put a type where it prunes

A type declaration says what a function accepts. `(: $x T)` says it in the
**pattern**, where it can cut the search rather than only check the call:

```metta
(: Ann Person)
(: Rex Dog)
(= (greet (: $x Person)) (hello $x))
!(greet Ann)                            ; (hello Ann)
!(greet Rex)                            ; nothing, Rex never reaches the body
```

It is not a new type relation. `(: $x T)` desugars to a plain variable plus
exactly the acceptance a declared parameter of type `T` compiles, so the two
agree by construction. That is also why a **metatype** restriction needs
nothing extra: `has_type` fails on a symbol nobody declared, so `(: $c Symbol)`
falls through to `get-metatype` and accepts any symbol.

Leave the type a variable and it binds, one branch per declared type, and one
variable used twice constrains two positions to agree:

```metta
(= (type-of (: $x $t)) $t)
(= (same-kind (: $x $t) (: $y $t)) ($x $y))
```

The same works in a match query, which is where it prunes the search:

```metta
!(match &self (knows (: $x Human) (: $y Human)) ($x $y))
```

`(: ...)` is also ordinary data that a program may be about, and both readings
are wanted. Two gates keep them apart, and neither is a preference:

**A pattern that IS a colon expression stays structural.** So a knowledge base
query still retrieves the declarations somebody wrote, and an annotation is
always nested inside something:

```metta
!(match &self (: $x Human) $x)          ; retrieves stored (: Plato Human)
!(match &self (knows (: $x Human) $y) $y)   ; annotates
```

**Below that, the annotated position must hold a variable.** `(: a $rest)` is
an ordinary pattern, and nothing looks inside a colon whose value slot is not a
variable. That is what lets this repository's own `nilbc.metta`, a proof search
over 134 `(: proof theorem)` terms, keep every one of them.

Issue #177 proposes a separate spelling, `::`, "when position cannot
distinguish the two uses". Position can, so there is no second spelling to
learn.

## Name a host value inside one term

`using=` maps bare symbols to Python objects, and the object crosses by
identity, not by a copy or a repr:

```python
model = load_classifier()
answers = m.eval("(gated v)", using={"v": model.predict(row)})
verdict = m.one("(gated v)", using={"v": model.predict(row)})
```

The symbol is bare, `v`, not `$v`: a `$` name is a MeTTa variable the engine
will bind for you, while `using=` names something you already have. All four
evaluating doors take it, `run`, `eval`, `one` and `first`, plus their
`AsyncMeTTa` twins, so a value can be routed through a rule without first
being written into a space and removed afterwards.

It does not compose with `residuals=`, and the call says so rather than
quietly dropping one of them.

## Match something already known

A match pattern binds. `(:= X)` makes one position **check** instead:

```metta
!(add-atom &self (fact a))
!(match &self (fact $x) $x)             ; a, $x binds
!(match &self (fact (:= a)) hit)        ; hit, the atom already IS a
!(match &self (fact (:= c)) hit)        ; nothing
```

A free variable does not match a `:=` operand, which is the difference from an
ordinary pattern and the reason to reach for it: `(:= $y)` with `$y` unbound
matches nothing rather than everything.

The gate is arity. Exactly two elements is the modifier; `(:= a b)` is three,
so it stays ordinary data and matches structurally. That is not a PeTTa
convention, it is the reference's own registry rule, and it exists because
three-element `(:= ...)` atoms already appear in real programs.

`unify-mod` in `lib/minimal_metta_lib.pl` has read `:=` all along; the engine's
own `match` reads it too now. It costs nothing when you do not use it: the
modifier is lifted while the call site compiles, so a pattern without one
compiles to exactly what it always did.

## Arithmetic that runs backwards

`+` computes. `#+` **relates**, and the difference is what you can ask it.
Every `#` operation is a CLP(FD) constraint rather than an evaluation, so give
it any two of the three and it solves for the third by propagation rather than
by search:

```metta
!(#+ 1 2)                        ; 3, the same as +
!(let 5 (#+ $x 2) $x)            ; 3, which + cannot answer at all
!(let 20 (#* (#+ $a 1) 4) $a)    ; 4, solved through two constraints
```

`(+ $x 2)` with `$x` unbound raises `Arguments are not sufficiently
instantiated`. `(#+ $x 2)` posts a constraint and waits, so the same expression
is a definition in one direction and a question in the other.

The family is `#+ #- #* #div #// #mod #min #max` for arithmetic and
`#< #> #= #\= #=< #>=` for comparison. The comparisons answer `True` or
`False` rather than succeeding or failing, so they compose with `if` the way
the ordinary ones do, and a comparison on an unbound variable narrows its
domain instead of raising:

```metta
!(collapse (let $q (#+ $p 1) (#< $q 4)))   ; (True), with $p constrained below 3
```

Integers only: CLP(FD) is a finite-domain solver, so `(#* 2 $x)` cannot answer
`1/2`. `examples/basics/relational_arithmetic.metta` runs the whole family
forwards and backwards.

Two more solvers sit beside it, in a library rather than in the engine:
`!(import! &self (library lib_constraints))` gives each of them **one** entry
point taking its constraint as written, rather than another operator family.

```metta
!(let True (clpq (= (* 2 $x) 1)) (repr $x))    ; "1r2", an exact rational
!(clpq-entailed (>= $x 0))                      ; is this already implied?
!(clpb (card (1) ($p $q)))                      ; exactly one of these is true
!(clpb-labeling ($p $q))                        ; (0 1) and (1 0)
!(clpb-taut (+ $t (~ $t)))                      ; True, decided not enumerated
```

`clpq` is the rationals: exact arithmetic, entailment, disequations, and
projection, which reads the implied relation between two variables after
eliminating the others. `clpb` is the booleans over BDDs. Neither replaces the
engine's own `and`/`or`/`not`, which are generate-and-test over two values and
cheaper until a formula constrains every variable at once; on "exactly one of
N is true" the crossover is at twelve variables, and above it the gap grows
without bound, 16,777,154 inferences against 289,037 at twenty.
`examples/basics/constraint_domains.metta` has all of it.

Constructive negation reads these, which is the payoff. Negate a rule whose
body is a `#` bound and the answer is the opposite bound rather than an
enumeration:

```metta
(= (small $n) (#< $n 5))
!(collapse (let True (not-provable (small $x)) (residual-goals $x)))
; (((: clpfd (in $x (.. 5 sup)))))
```

`$x` comes back carrying `5..sup`, so "which n is not small" is answered over
an infinite set without visiting any of it. Negating a bare `(#< $y 4)` at top
level is the one shape that does not work: there is no rule to take the dual
OF, and a universally quantified variable carrying a finite-domain constraint
is refused by name rather than answered wrongly.

## Say two things stay different

`(!= $a $b)` and `(dif $a $b)` look like the same question and are not, and
picking the wrong one is the kind of mistake that works until it doesn't.

`!=` asks whether the two terms are identical **now**. It is Prolog's `\==`,
a test rather than a claim, so on an unbound variable it answers `True` and a
later binding may contradict it:

```metta
!(let $x 1 (!= $x 1))      ; False, $x is already 1
!(!= $x 1)                 ; True, and then $x may still become 1
```

`dif` answers `True` and **constrains** the two terms never to become
identical, so the later binding fails instead. That is what makes a
constructive negation constructive: the answer to "which bird is not a
penguin" is every bird except polly, carried as a constraint rather than
enumerated over a domain that may be infinite. `(residual-goals $x)` reads the
constraints an answer is still carrying, which is how an answer that prints as
a bare variable turns out to be saying something.

Neither replaces the other, and `!=` was deliberately not redefined as `dif`:
changing an existing builtin's meaning is not a fix, and the constraint is
available under its own name.

## The third truth value

Tabled negation gives this engine Well Founded Semantics: an answer can be true, false, or genuinely undefined, a loop through `tnot`. Before this surface, an undefined answer reached Python as an ordinary-looking unbound variable, which is silently wrong. Now every `eval` answer carries its truth: definite answers stay plain atoms, and an undefined one arrives as an `Undefined` holding the answer, the delay condition that makes it undefined, and, with `residuals=True`, the residual program, the clauses of the loop itself.

```python
def test_undefined_answers_cross_as_undefined(m, wfs_program):
    answers = m.eval("(translatePredicate (wfs_loop))")
    assert len(answers) == 1
    answer = answers[0]
    assert isinstance(answer, Undefined)
    assert "wfs_loop" in answer.why
```

`Undefined` refuses truthiness on purpose, so code cannot branch on it by accident, and `value()` refuses it outright: a caller asking for THE value has asserted a definite one exists. The carrier is the engine's own `call_delays`, applied per answer inside the enumeration, which is the only place the condition exists. It is unconditional because any "only when tabling" gate would answer silently wrong exactly once, on the first tabled call; the measured cost on the trivial-eval crossing is five to ten percent, amortized below that on real evaluations. `run()` mirrors the CLI and stays two-valued; evaluate through `eval()` when undefined truth matters.

`query()` computes and decodes every answer before you see the first one. `stream()` is the same conjunction and guard, pulled: the join's state stays alive inside an SWI engine between pulls, each pull is one ordinary call, and unrelated engine work interleaves freely.

```python
    m.add_table("edge", [(i, i + 1) for i in range(500)])
    with m.stream(S.edge(V.a, V.b), S.edge(V.b, V.c)) as rows:
        first = next(rows)
        assert (first.a, first.b, first.c) == (0, 1, 2)
        # Unrelated engine work interleaves while the cursor stays open,
        # which a raw janus cursor forbids.
        assert m.one("(+ 1 2)") == 3
        second = next(rows)
        assert (second.a, second.b, second.c) == (1, 2, 3)
```

Break out of the loop and nothing further is even joined. Exhaustion closes the cursor on its own, leaving the with-block closes it early, and a dropped cursor is reaped by its finalizer. On a stream, `timeout` bounds each pull's wall time while `inferences` is one budget for the cursor's whole engine work, because an engine's inferences are its own. The cursor enumerates under the engine's logical update view, so writes made after the first pull are not seen by it.

## Strings and regular expressions

Structural match reads terms; strings stay opaque to it. `lib_regex` opens them with the engine's own PCRE2: `(re-match pat text)` answers a boolean and therefore guards queries, `(re-find pat text)` answers every match nondeterministically, `(re-captures pat text)` answers the first match's groups as `((key value) ...)` pairs with a `_I` name suffix answering an integer, and `(re-split ...)`, `(re-replace ...)`, `(re-replace-all ...)` do what they say. Flags ride the pattern inline, PCRE2's `(?i)` style, and a MeTTa string reads a doubled backslash as one, so `"\\d"` spells the digit class, Python's own non-raw convention.

```python
def test_regex_guards_queries(rx, metta):
    with metta.new_space() as m:
        m.add(S.person(S.Ada), S.person(S.alan), S.person(S.Alice))
        rows = m.query(S.person(V.name), where='(re-match "^A" $name)')
        assert [row.name for row in rows] == [S.Ada, S.Alice]
```

The guard is also an optimization: patterns compile once into the engine's cache and every candidate row is tested in C, never crossing to Python. Against an equivalent Python-operation guard on a 2000-row scan, the regex guard measured 2.3x (317 against 138 queries per second, identical rows answered).

## Content hashes

`lib_crypto` opens the engine's own OpenSSL to MeTTa programs: `(crypto-hash sha256 "text")` answers the lowercase hex digest under any `library(crypto)` algorithm name, an unknown name refuses loudly, and `(crypto-random-hex 16)` answers thirty-two hex characters of cryptographically secure randomness for nonces and fresh ids. Hashes make content keys, so a fact can carry the identity of its own payload, and the digests agree with every other tool's:

```python
    (digest,) = cr.eval('(crypto-hash sha256 "hello")')
    assert digest == hashlib.sha256(b"hello").hexdigest()
```

The whole-space version of the same idea is [`digest()`](./spaces), one hash naming everything a space stores.

## Atomic and what-if runs

The engine has transactions, and a program can already use the inline `(transaction ...)` form for a scope inside itself. `atomic=True` lifts that over a whole `run`: every write, facts and equations alike, commits whole or rolls back whole when a directive throws.

```python
    with pytest.raises(EngineError):
        m.run("(kept fact) !(/ 1 0)", atomic=True)
    assert expr(S.kept, S.fact) not in m  # the fact rolled back with the throw
    m.run("(kept fact) !(+ 1 1)", atomic=True)
    assert expr(S.kept, S.fact) in m  # and commits whole on success
```

`speculative=True` is the what-if twin: the run executes against a frozen view, the answers return, and every write is discarded.

```python
    groups = m.run("(ghost fact) !(+ 2 2)", speculative=True)
    assert groups[-1] == [4]
    assert expr(S.ghost, S.fact) not in m
```

Both cover engine state. A Python operation's side effects, and subscription callbacks that already fired, stay where they happened; that is what rolling back a database can honestly mean.

For your OWN logic rather than a source string, `m.transaction(callable)` runs a zero-argument callable inside one engine transaction now and answers its return value, the same `petta_transaction/1` the MeTTa form compiles to, so foreign-space enlistment and nesting behave identically in both languages. A raise is the one rollback trigger, and it re-raises as itself: your `ValueError` arrives as `ValueError`, the engine boundary in its chain, with every stored atom and compiled equation rolled back. Transactions nest, an inner commit staying relative to its outer transaction. `m.transactional` is the decorator twin, one transaction per call:

```python
@m.transactional
def migrate():
    m.add(S.schema(2))
    m.remove(S.schema(1))
```

There is deliberately no `with m.transaction():` form: SWI's `transaction/1` takes a closed goal, there is no open begin/commit to hold across a block, and pretending otherwise would lie about the isolation actually provided.

## Profile a run

`m.profile(source)` runs source under the engine's statistical profiler and answers the groups beside a profile: sample counters, and one row per predicate with its calls, redos, and ticks, self-ticks first.

```python
    m.run("(= (prof-spin $n) (if (== $n 0) done (prof-spin (- $n 1))))")
    groups, prof = m.profile("!(prof-spin 10000000)")
    assert groups == [[S.done]]
    assert prof.samples > 0 and prof.ticks > 0
```

`prof.top(5)` is where the time went. The sampler is statistical, so profile something that runs; and profiling changes execution, so it is a debugging surface, not a mode to leave on.

## Trace a reduction

Where the profiler says where time went, `m.trace(source)` says what happened: it runs source with every compiled MeTTa function wrapped by the engine's own predicate wrapping, and answers one call event per reduction entered, depth-nested through the call tree, and one exit event per answer. A reduction that fails is a call with no exit, which is precisely what failing looks like:

```python
    m.run("(= (tr-fact $n) (if (== $n 0) 1 (* $n (tr-fact (- $n 1)))))")
    events = m.trace("!(tr-fact 3)")
    calls = [e for e in events if e.kind == "call"]
    exits = [e for e in events if e.kind == "exit"]
    assert [str(c.term) for c in calls] == [
        "(tr-fact 3)", "(tr-fact 2)", "(tr-fact 1)", "(tr-fact 0)",
    ]
    assert [c.depth for c in calls] == [0, 1, 2, 3]
```

Builtins inline and stay invisible, so the trace is about your program, not the engine. The source executes for real, writes included, exactly like a `run`; the wrap exists only while tracing, so untraced calls pay nothing. Printing an event indents it by depth, which makes `for e in m.trace(...): print(e)` a readable story of the evaluation.

## Lint a space

MeTTa fails open: a call to a misspelled function stays an unreduced expression, a call with the wrong argument count matches no equation, and a declared type nothing defines promises a function that cannot answer. `m.lint()` walks a space's declarations and equations against the engine's own registries and answers findings, each naming its kind, its subject, and the atom it stands on:

```python
    m.run("(: ghost-fn (-> Number Number))")
    findings = m.lint()
    assert _kinds(findings) == ["declared-but-undefined"]
    assert findings[0].subject == "ghost-fn"
```

The kinds: `declared-but-undefined`, `arrow-arity-mismatch` (the arrow's input count against the equations'), `declaration-types-the-symbol` (a declaration that is not an arrow, so it types the name and not a call to it), `arity-mismatch` (a call with an argument count no equation takes), `unbound-variable` (a body variable the head never bound, exempting equations with their own binding forms), `duplicate-equation` (the same equation stored twice, answering every call twice), `tabled-answer-order-read` (a `car-atom` or `index-atom` picking out of a collapse of a tabled function), and `possibly-undefined-reference`, which says in its own text that it is a heuristic, because an expression head that is no known function may be data on purpose. A healthy space answers an empty list.

"Known" there means known to the engine, and the engine gives a head meaning two ways. A function is one, and `fun/1` answers for it. A special form is the other: `if`, `case`, `collapse`, `unify`, `chain`, `once` and 20 more are compiled by the translator instead of being defined by equations, and 29 of the 47 answer `False` to `fun/1`, as do the six stream rewrites `trace!`, `unique`, `alpha-unique`, `union`, `intersection` and `subtraction`. The linter asks `metta_translated_head/1` as well, which reads the translator's clause heads rather than keeping a list, so a form added to the engine is known to the linter the day it is added.

`tabled-answer-order-read` is the one that catches a program working today for a reason that will not last. Tabling preserves the answer *set* and not its order, so `(car-atom (collapse (pick a)))` over a tabled `pick` answers whatever the trie happens to hold first, and that moves when something unrelated moves: adding three facts nothing calls to another engine file flipped one from `(one two)` to `(two one)`, and removing them flipped it back. Wrapping the collapse in `sort-atom` fixes it and silences the finding, which is what the tabling examples do.

`declaration-types-the-symbol` only reaches the linter from `add_atom`, because a source file is refused outright: see [types and casting](../tutorials/06-types-and-casting) for what the engine checks at load. Building a name's declarations one atom at a time passes through a state where only the first is stored, so the check that can refuse a whole source cannot refuse a single write.

## Cast a value

MeTTa's type discipline is checked, not asserted. `m.cast(value, type)` runs that check natively from Python: the exact acceptance the engine compiles for a typed argument position, with `(: name Type)` declarations from the space and `&self` in scope, answering the value narrowed to its Python-most spelling, so a ground atom unwraps to its Python value. What a typed call refuses silently (the mismatched call just reduces to nothing), `cast` refuses loudly:

```python
    m.run("(: Ann Person)")
    assert m.cast(S.Ann, "Person") is S.Ann
    with pytest.raises(CastError) as caught:
        m.cast(S.Ann, "Robot")
    assert "Person" in str(caught.value)
```

The check is duck-typed the way the engine already is. A protocol registered with `register_object_type` makes any object satisfying its predicate cast to the protocol's name, and a Python type as the target spells its MeTTa reading: `bool` is `Bool` before `int` is `Number`, `str` is `String`, and any other class is its own name, the names `get-type` itself answers:

```python
    integrate.register_object_type(lambda x: hasattr(x, "quack"), "Ducky")

    class Quacks:
        quack = "yes"

    class Silent:
        pass

    duck = Quacks()
    assert m.cast(duck, "Ducky") is duck
    assert m.cast(duck, Quacks) is duck
    with pytest.raises(CastError):
        m.cast(Silent(), "Ducky")
```

Structural targets work too: casting to `(List $t)` admits anything whose type unifies, and a repeated variable in the target constrains. Targets the engine never checks (`Atom`, `%Undefined%`, `_`) pass unchecked here as well. The surface is in [`petta.casting`](../reference/petta-casting).

`add_table(head, source)` reads a Polars frame, a pandas frame, a mapping of columns, or any iterable of rows into facts shaped as `(head v1 .. vn)`. In the other direction, `rows.table()` returns a dict of plain columns accepted by DataFrame constructors, and `rows.to_df()` / `rows.to_pl()` build the pandas or polars frame directly, DuckDB's conversion naming. `rows.build(column, Class)` rebuilds translated objects from a result column. In a notebook, rows render as a table on their own, and in a [rich](https://rich.readthedocs.io)-using terminal `print`ing rows through a rich console draws the same table. `rows.pipe(fn, *args)` is pandas' chaining shape, so a post-processing pipeline reads left to right: `m.query(pat).pipe(clean).pipe(score, weight=2)`.

Use `derivation(atom)` to obtain proof trees for an answer. Use `why(pattern)`
to explain one empty match. An empty result returned directly by `query()`
retains the query context, so `rows.why()` identifies a pattern miss, a join
with no shared binding, or a `where` guard that rejected every joined row. It
reads the space's current state. The complete runtime surface is in
[`petta.space`](../reference/petta-space), and result containers are in
[`petta.results`](../reference/petta-results).
