# Extending MeTTa without forking it

MeTTa has nine extension points. You should not need to change the engine to
add a feature, and you should not have to guess which mechanism to reach for.
This page lists them in order of runtime cost, measured rather than asserted,
and says what each one is for.

The short version: **C, Prolog, macros and native-proved compiled Python cost
about what a MeTTa function costs. Python protocol dispatch costs a Janus
crossing.** Pick by how hot the code is, and by which language the work is
already in.

## Where the Prolog seams live

Every seam you write clauses for is in the `seam` module, so a handler is
declared and defined under it:

```prolog
:- multifile seam:atom_added/2.
seam:atom_added(Space, Atom) :- format("~w gained ~w~n", [Space, Atom]).
```

That is SWI's own hook shape, the one `prolog:message//1` has always used, and
the module is why the names are short. The old prefixed spellings
(`metta_on_atom_added/2` and friends) are gone rather than aliased: a prefix is
a convention and cannot refuse anything, so two libraries could declare one
seam name and corrupt each other by import order. Unqualified is not a
spelling either. `:- multifile atom_added/2.` declares a predicate of your own
that nothing consults.

Services go the other way. A service is a predicate the engine defines and you
call, so you call it unqualified and the engine's module puts it in scope:
`swrite/2`, `space_module/2`, `current_metta_module/1`. `seam:kind/2` says
which of the two any given seam is.

## What each one costs

Measured by `extensions/python/benchmarks/extension_cost.py`, which `check.sh`
re-runs as a GATE against a committed baseline, so these numbers cannot drift.
Every tier is measured in one process against one driver shape, and the
driver's own cost is measured separately and subtracted, so a row is the
marginal cost of **one call** rather than of the loop around it.

| extension point | inferences/call | vs MeTTa | microseconds/call | vs MeTTa |
|---|---|---|---|---|
| C foreign predicate | 1.00 | 0.33x | 0.01 | 0.17x |
| translator rule (a macro) | 2.00 | 0.67x | 0.03 | 0.39x |
| Prolog grounded predicate | 2.00 | 0.67x | 0.02 | 0.27x |
| ordinary MeTTa function | 3.00 | 1.00x | 0.08 | 1.00x |
| @m.define, annotated | 3.00 | 1.00x | 0.10 | 1.15x |
| Python operation, transport="raw" | 12.00 | 4.00x | 1.16 | 13.85x |
| Python operation, encoded | 20.00 | 6.67x | 4.05 | 48.22x |
| @m.define, no annotations | 28.00 | 9.33x | 5.13 | 61.12x |

Six of each operation row's inferences are the scheduler admission probe: every
operation call asks the effect and lane question that lets an `oracleIO` call
detach onto an offload thread inside a scheduler, and the unscheduled call pays
the same probe.

This is one run's output, not a best-of, because the columns divide by each
other and mixing runs would give ratios no run measured. The inference column
is exact; the microsecond column is not, because the four native tiers land
near the timer's resolution. The annotated `@m.define` row has varied between
about 1.1x and 1.7x on runs minutes apart at the same load, while its inference
figure was identical every time. Any native-tier ratio inside about 2x is timer
noise. [measured: table output above; command=python -m
benchmarks.extension_cost --update; fixture=3000 calls, min-of-3, C reader and
C extension enabled; commit=c350f51a5e1318187c4446fb2ceba04fba82e262]

### Three choices, and none of them is the other two

The table above prices ONE of three decisions you make when something crosses
between MeTTa and a host language. They are independent, and reading the table
without separating them is how a reader concludes that the fast choice and the
translated choice are the same choice.

| the choice | its poles | what already names it |
|---|---|---|
| who calls whom | the host drives, or the engine calls out | `entry(host, File)` and `entry(engine, File)` in a seat's `extension.pl` |
| where the body lives | CALLED, or LOWERED | nothing yet; `mt_lower` and "lowered-source define" are the far end's name in two seats |
| what a value crosses as | transparent, or opaque | the `registry-image` vocabulary, and `py-atom`'s metatype argument |

**Where the body lives** is what this table prices. A CALLED definition is a
host function the engine can only call: it must be TOLD its effect class,
because the engine cannot see inside it, and its body stays in the host
language and stays late-bound. A LOWERED definition is compiled into equations,
which the engine reads, specialises, matches on and reasons about. Each seat
spells the pair its own way, and it is one idea:

| seat | called | lowered |
|---|---|---|
| Python | `m.op` | `@m.define` |
| C | `mt_def` | `mt_lower` |
| TypeScript | `op` | `define` |

**What a value crosses as** is the third choice, and where the words
*transparent* and *opaque* belong. They describe an IMAGE, not a definition: a
transparent value is translated into MeTTa structure, an opaque one is carried
whole as a blob the engine holds and does not read. `py-atom` takes the choice
as an argument, `Expression` for a snapshot and `Grounded` for the live
reference. Holding a blob is a first-class thing to do rather than a lesser
one: it keeps host identity and skips a translation that may not be wanted. An
iterator is always opaque, because measuring one drains it.

The two are orthogonal. A LOWERED body can take an OPAQUE argument, and a
CALLED host function can be handed a TRANSPARENT one. Do not read "lowered" as
"transparent", and do not reach for *opaque* and *transparent* to describe how
a definition was installed.

### What the other two axes cost

The table above prices the middle axis only. These are the other two, measured
by `extensions/python/benchmarks/axes.py`. They are reported as retired
instructions beside engine inferences, because inferences are BLIND across the
janus boundary: foreign code retires none, so the inference column understates
every row here and is printed to show that. Reproduce with
`cd extensions/python && python -m benchmarks.axes` [measured 2026-08-29].

The two columns carry different weight, and the difference is worth knowing
before you plan around either. The instruction figures are a recorded run: they
are load-robust but nothing pins them. The inference figures are deterministic
and carry the claims this section actually argues from, so they have a test
rather than a date. `tests/ch18_performance/test_axes.py` asserts that an
opaque crossing stays flat in the value's size, that a transparent one stays
linear AND stays at four inferences an element, and that the engine-out row
keeps agreeing with the gated cost table's 12.00. Both halves are needed: the
class alone would admit a transparent crossing costing a hundred inferences an
element, and the rate alone would not notice it becoming quadratic. A few
percent of drift is not a failure and either change is.

**Who calls whom.** The same trivial work on either side, one crossing per
item, 20,000 items, each figure a difference against the same loop with the
crossing removed:

| direction | instructions/crossing | inferences/crossing |
|---|---|---|
| the engine calls out, a Python `op` from MeTTa | 19,557 | 12.03 |
| the host drives in, `space.eval` of a built term | 96,771 | 108.07 |
| the host drives in, `space.eval` of source text | 97,485 | 106.07 |

**Letting the engine call out is about five times cheaper per crossing than
driving it from Python.** A host-driven call re-enters the engine, opens a
query and tears it down for every item; an engine-driven call is already inside
and pays the crossing alone. So a loop over many items belongs in MeTTa calling
out rather than in Python calling in. The engine-out row's 12.03 inferences is
the same figure the gated table pins at 12.00 for a raw Python operation, which
is the cross-check that these two harnesses agree.

The two host-driven rows are within noise of each other, and that refutes the
obvious guess: at this call shape the source string's parse is not what costs,
the re-entry is. Build terms for the reasons the library gives elsewhere, not
for this one.

**What a value crosses as.** One Python list returned per crossing, built once,
so what is priced is the crossing and not the construction:

| elements | transparent instructions | transparent inferences | opaque instructions | opaque inferences |
|---|---|---|---|---|
| 1 | 73,514 | 21.32 | 24,613 | 12.31 |
| 10 | 161,979 | 57.32 | 24,543 | 12.31 |
| 100 | 1,042,933 | 417.31 | 24,475 | 12.31 |
| 1,000 | 10,270,349 | 4,017.31 | 24,521 | 12.31 |

**This axis is a complexity class, not a constant factor**, and the fit says so
rather than the ratio. Fitted in log-log space by the same `power_fit` the
scaling gate uses, the transparent ladder's consecutive-pair slopes climb
0.43, 0.86, 0.98 toward 1, which is linear with a fixed per-crossing cost
washing out as the values get bigger; the opaque ladder fits an exponent of
exactly 0.0 and reports no R-squared at all, which is what a flat curve does.
In plain terms a transparent crossing costs four inferences per element plus a
fixed 17.3 and an opaque one costs 12.31 whatever the size, so at a thousand
elements the gap is 419 times the instructions and 326 times the inferences,
and it keeps growing.

The same shape appears twice more on this page, in the argument-size table
below and in the C handle against a serialisation in section 3, because it is
one fact: translating a structure costs its size and referencing it does not.

Read the two tables together rather than separately. An opaque value is cheap
to cross and gives the engine nothing to match on, so a value the program will
take apart pays the translation here or pays it in `car-atom` later, while a
value the program only carries should never be translated at all.

### What a write costs

The write door has its own table, in the same harness against the same
committed baseline: what an `add-atom` costs once something claims the space it
writes into. The hook row is the price of consulting an arbitrary-MeTTa policy
per write, paid only by the space that asked; the handler's call site is
translated once when the claim is made, not per write. The pool rows go through
the shipped `pool.admits` and `pool.capacity` surface, which claims the pool's
pre-add hook with the `space-admission-verdict` judge.

| write door | inferences/add | vs plain add | microseconds/add | vs plain add |
|---|---|---|---|---|
| add-atom, no claims on the space | 30.00 | 1.00x | 1.70 | 1.00x |
| add-atom through an accept-all pre-add hook | 47.00 | 1.57x | 2.57 | 1.51x |
| add-atom into a pool with a declared admits type | 57.00 | 1.90x | 2.73 | 1.60x |
| add-atom into a pool with a declared capacity | 67.00 | 2.23x | 4.78 | 2.81x |

A space nothing claimed keeps the direct write path, which is what holds the
plain row where it is. The capacity row used to read 4569.69 at a thousand held
atoms and grew with every one, because the check counted the pool by
enumeration per add. A native capacity claim installs one rollback-safe dynamic
count instead, updated only on that pool's accepted writes and reset by its
removal and clear doors, so the judge reads an indexed fact in 3.00 inferences
and the row no longer depends on the atom count or the number of stored
arities. A pool with no capacity claim owns no counter, and a space with no
hook claim never probes for one.

### Read both columns, because each one hides something

**Inferences understate Python.** The janus crossing counts as one inference
and costs real microseconds, so inferences say a raw Python operation is 1.7
times a MeTTa function while wall clock says **more than ten times**. If you
are deciding whether to move a hot loop out of Python, trust the microseconds.

**Inferences flatter C.** A foreign predicate is one inference no matter how
much work it does inside, so the 1.00 above measures the call, not the
computation. C wins on this table because the operation is trivial; what it
buys you is that the work inside is invisible to the Prolog engine.

**An annotation can select the native operator path.** `@m.define` compiles a
Python body into MeTTa equations, but it must preserve Python's live operator
protocol when an operand's type is unknown. The unannotated `x + 1` row
therefore calls Python and costs 28.00 inferences. Declaring `x: int` proves
that the same source can use the pure engine `+` head, so the annotated row is
back at the hand-written equation's 3.00.

The declaration also asks the engine to check the contract. A literal argument
of the declared type is discharged while the call site compiles. A parameter
whose enclosing declaration proves the required type is discharged under the
same module policy, and recompilation restores the check if a user typing rule
changes that policy. A check the compiler cannot prove remains. `Number`,
`String` and `Bool` checks are specialised to one Prolog builtin before the
general lookup.

SWI compiles `number/1` to a VM instruction and does not count it as an
inference. The annotated row's inference parity is therefore not a claim that
every contract is free. The separate `declared_contracts.py` benchmark covers
proved and unproved parameters directly; `check.sh` also gates the
`typed-call` retired-instruction ceiling in `benchmarks/baseline.json`.

Annotate a numeric twin when its Python operator is meant to become the native
MeTTa head. Leave it unannotated when Python overload or reflected-method
semantics are part of the function's contract.

**The Python operation has two paths and they are not close.**
`transport="raw"` skips the wire encoding both ways. The encoded path WALKS the
term, so the single number above is its best case, on a one-argument integer:

| argument | encoded | `transport="raw"` | ratio |
|---|---|---|---|
| integer | 20.00 | 12.00 | 1.67x |
| flat, 4 items | 31.00 | 12.00 | 2.58x |
| flat, 16 items | 55.00 | 12.00 | 4.58x |
| flat, 64 items | 151.00 | 12.00 | 12.58x |
| nested, depth 4 | 63.00 | 12.00 | 5.25x |
| nested, depth 8 | 103.00 | 12.00 | 8.58x |

The raw path is **flat whatever the argument is**. The encoded one costs about
two inferences per flat item and about eight per nesting level, so a 64-item
list through an encoded operation costs 144 inferences against a Prolog
predicate's 2.

One of the raw path's inferences is the catch that turns a Python failure into
a MeTTa error naming your call. It is the floor rather than a choice, the
manual putting `catch/3` at "comparable to `call/1`", and against a crossing
costing 0.87 microseconds where a MeTTa function costs 0.05 it decides nothing.
What raw transport gives up is the symbol-string distinction: symbols reach a
raw operation as plain strings. `pettorch` uses it throughout for that reason.

The four native tiers are within two inferences of each other, so choose
between them on what the code is, not on speed: a macro when the shape is known
at compile time, Prolog when you are writing new logic, C when you are wrapping
something that already exists in C or Rust, and `@m.define` when the logic is
easier to say in Python than in MeTTa.

The macro row is the only one that can go lower than it says. Its cost is the
cost of the code it emitted, and a rule that settles the answer at compile time
emits no code at all, leaving a fact to look up. *Writing the rule in Prolog*
below is how a library reaches that.

## 1. Translator rules: macros, and they cost nothing at all

`add-translator-rule!` makes a MeTTa function run at **compile time**. Whatever
it returns, quoted, becomes the compiled code. The call is not there at
runtime.

```metta
(: for (-> Atom Atom Atom %Undefined%))
(= (for $var $collection $body)
   (quote (let $var (superpose $collection) $body)))

!(add-translator-rule! for)

(= (myfun $L)
   (for $x $L (if (== (% $x 2) 0) (even $x) (odd $x))))
```

`for` is now part of the language. Nobody forked the engine to add it.

That it really disappears is visible in the compiled clause. Given

```metta
(= (inc $x) (quote (+ $x 1)))
!(add-translator-rule! inc)
(= (uses-macro $n) (inc $n))
```

the engine compiles `uses-macro` to

```prolog
'uses-macro'(A, B) :- +(A, 1, B).
```

This is the right tool for new syntax, for control forms, and for anything
where the shape is known when the program is written. Examples:
`examples/ch20-extending-the-engine/20-01-translator-rules/01-translatorrule.metta`,
`translatorrule_for.metta`, `translatorrule_fib.metta`, and `lib_patrick.metta`
and `lib_spaces.metta` in the library tree.

### A rule's body is its condition

A clause applies at a call when its head matches *and* its body produces an
expansion. A body with no answer declines, the next clause is tried, and if no
clause applies the whole rule declines and the call carries on to ordinary
dispatch. So a rule is a conditional rewrite rule, the way a CHR rule with a
guard or a Haskell equation with guards is: the head says which calls it is
*about*, and the body decides whether it *applies*.

```metta
(: pick (-> Atom %Undefined%))
(= (pick a) (empty))
(= (pick $x) (noeval (picked $x)))
!(add-translator-rule! pick)
```

`(pick a)` compiles to `(picked a)`, through the second equation, because the
first equation's body has no answer for `a`.

Two things follow. A rule cannot instantiate the call it was asked about: a
head shape the call does not have, or a body goal that would bind one of the
call's variables, makes the clause decline rather than narrow the equation the
call sits in. And the first clause that applies supplies the expansion, so a
rule is deterministic where the plain function of the same equations would
answer every way; when two clauses both apply, the order they were written in
decides, which is what `translator_confluence.pl` reports on.
`examples/ch20-extending-the-engine/20-01-translator-rules/03-translatorrule_guard.metta`
runs all of it.

### Declining a match, out loud

A rule head says which shape the rule rewrites. Whether the match it got is one
the rewrite can honour is a different question, and `(refuse Reason)` is the
answer to it:

```metta
(: strength (-> Atom Atom %Undefined%))
(= (strength (dose $n) (unit mg))
   (if (> $n 1000)
       (refuse "a dose above 1000 is not a milligram strength")
       (noeval (mg $n))))
(= (strength (dose $n) (unit mg))
   (noeval (grams (/ $n 1000))))
!(add-translator-rule! strength)
```

A refusal is a decline, not an error. The call carries on down the rest of the
dispatch chain, and a rule with another equation tries that one, so
`(strength (dose 5000) (unit mg))` answers `(grams 5)`. The reason does not
disappear: it is published into `&metta`, so a program can ask why a rewrite it
expected did not happen.

```metta
!(match &metta (translator-rule-refusal $rule $why) (refused $rule $why))
```

A rule that refuses is not a new kind of rule; it writes its conditionality
where a reader can see it. Confluence of terminating conditional systems is
undecidable in general, so the report's verdict decides the extracted
unconditional system, counts the rules that make their condition explicit by
refusing, and reports a set holding one as `NOT DECIDED` with its critical
pairs listed as proof obligations rather than giving a verdict it cannot
support.
`examples/ch20-extending-the-engine/20-01-translator-rules/07-translatorrule_refusal.metta`
runs all of this.

### Declaring a rule's direction

A registration can carry declarations, written as a list after the name:

```metta
(: unpack (-> Atom %Undefined%))
(= (unpack (wrap (box $x))) (noeval (twin $x $x)))
!(add-translator-rule! unpack ((direction bidirectional)))
```

`forward` is the default and is the rewrite you already have. `bidirectional`
says the equation is a two-way equivalence, and the engine derives the inverse
equation, adds it to the space and registers the head it is rooted at.

Both directions now rewrite, and which one fires is decided per call by the
form's **cost**, which is its node count. A rewrite fires only when it lowers
the cost, so `(unpack (wrap (box 1)))` (four nodes) becomes `(twin 1 1)`
(three), while `(twin (a b c) (a b c))` (seven) becomes
`(unpack (wrap (box (a b c))))` (six). A call already at its cheapest is left
as written. That is what keeps the two directions from rewriting each other
forever.

Reading a rule backwards has preconditions, and each is checked with the
failure named. The rule has to **write** its expansion, as `(= Lhs (noeval Rhs))`,
because a body that computes its expansion would have to have the computation
inverted. The expansion has to be a form with a symbol at its head, that head
may not be a protected one, and both sides have to carry the same variables, or
one of them arrives unbound the other way round.

`!(remove-translator-rule! unpack)` withdraws the derived equation with the
rule, so the inverse never outlives the declaration that produced it.
`examples/ch20-extending-the-engine/20-01-translator-rules/02-translatorrule_direction.metta`
runs all of this.

### Pricing a rule, and a conjunctive left side

A bidirectional rule says two forms are equivalent, and something has to choose
which one the compiler emits. `(cost N)` is that choice: it prices a form
headed by the rule's name, and a form's total cost is its head's price plus its
children's, the way an e-graph extractor's cost function folds. A form whose
head no rule prices costs one node.

```metta
(: pow2 (-> Atom %Undefined%))
(= (pow2 $x) (noeval (mul $x $x)))
!(add-translator-rule! pow2 ((direction bidirectional) (cost 10)))
```

`(pow2 3)` now costs eleven against `(mul 3 3)`'s three, so it expands; the
same rule collapses `(mul BIG BIG)` back when writing the argument twice costs
more than the priced head. Drop the `(cost 10)` and both calls go the other
way. A cost has to be a whole number that is not negative, because it is the
measure the rewrite has to lower.

A left side can also be a **conjunction** of patterns. The first is the call
the rule rewrites and the rest are matched against the space, so a rule can
look at the program around the call:

```metta
(unit mass kg)

(: unit-of (-> Atom %Undefined%))
!(add-translator-rule! unit-of
   ((left ((unit-of $q) (unit $q $u)))
    (right (in $u))))
```

`(unit-of mass)` compiles to `(in kg)`. `$q` joins the call to the space
pattern and `$u` carries the answer out; the patterns share their variables
because they are one written form, so nothing merges substitutions. The rule
compiles to the equation you would have written by hand, with the conjuncts as
a `match` chain, and a call whose conjuncts do not match is a rule miss like
any other. A conjunctive left side cannot be declared bidirectional: reading it
backwards would have to assert the conjuncts it matched, which is a different
operation.
`examples/ch20-extending-the-engine/20-01-translator-rules/04-translatorrule_cost.metta`
runs all of this.

### A variable the right side invents

The termination analysis behind the confluence report needs every variable a
rule writes on its right to be bound on its left, because one that is not can
be instantiated to anything. Some are not: a variable that is a **binder** of
the expansion, like `catch`'s ball pattern or a `case` branch's pattern, never
takes a value from the term being rewritten. A rule says so, with the reason:

```metta
!(add-translator-rule! succeedsPredicate
   ((extra-variables-exempt "the catch ball pattern and the case branch pattern are binders of the expansion, so neither takes a value from the term being rewritten")))
```

The reason is required, because an exemption without one is a silenced check.
The report prints it beside the termination line, so a waived precondition is
stated rather than assumed, and a rule that invents a variable and says nothing
still reports `extra_variables`.

### What a rule may not take over

A rule is consulted before the compiler's own forms, so a rule named after one
of them replaces it for the rest of the process. Fourteen heads are protected
against that, and the registration is refused with the name in the message:

```metta
!(add-translator-rule! if)
; No permission to register metta_protected_core `if'
```

The protected heads are `eval`, `evalc`, `chain`, `let`, `unify`, `superpose`,
`collapse`, `call`, `translatePredicate` and `reduce`, which are this engine's
counterparts of minimal MeTTa's structural instruction set, plus `if`, `case`,
`catch` and `cut`, the control forms. `KERNEL.md` says which counterpart is
which.

Every other head stays yours, including ones the compiler also gives a meaning:
`lib/lib_derived/lib_derived.metta` registers a rule for `once` on purpose, and
`examples/ch20-extending-the-engine/20-01-translator-rules/08-derived_forms.metta`
swaps it in and back out. A rule that goes ahead of a compiler form or a
builtin that way is recorded, and the confluence report prints it beside the
name.

### Writing the rule in Prolog, and deciding how your forms compile

A rule runs as a Prolog predicate. The translator appends one argument for the
expansion and calls it, so a rule whose MeTTa body is a single call to a
registered predicate has all of its logic in Prolog. Combined with
`translatePredicate`, which compiles one goal inline, that is a library
deciding how its own forms compile rather than only what they mean.

Here is a planner that fuses a scale into an add:

```prolog
% in your library's .pl file
'vs-plan'(Form, Out, Goal) :-
    (   Form = ['vec-add', Inner, W], nonvar(Inner),
        Inner = ['vec-scale', V, K]
    ->  Goal = ['translatePredicate', ['vec_saxpy', K, V, W, Out]]
    ;   Form = ['vec-add', A, B]
    ->  Goal = ['translatePredicate', ['vec_add', A, B, Out]]
    ;   Form = ['vec-scale', V, K]
    ->  Goal = ['translatePredicate', ['vec_scale', K, V, Out]]
    ).
```

```metta
(: vecop (-> Atom Atom %Undefined%))
(= (vecop $form $out) (vs-plan $form $out))
!(add-translator-rule! vecop)
```

`(vecop (vec-add (vec-scale $v $k) $w) $z)` now compiles to a single
`vec_saxpy` goal, and the intermediate vector the two-step spelling would build
is never created. Over 500-element vectors the fused form ran 68,161
inferences against 69,176 for the same result written as two `vecop` calls,
which is the one traversal it removed [measured 2026-08-16].

Because the rule runs at compile time it can also settle the answer outright.
A planner that computes a ground result emits a unification instead of a call:

```prolog
'add-plan'(A, B, Out, Goal) :-
    (   integer(A), integer(B)
    ->  C is A + B, Goal = ['translatePredicate', ['=', Out, C]]
    ;   Goal = ['translatePredicate', ['plus', A, B, Out]] ).
```

Given `(= (twenty-two-more) (progn (addop 20 22 $z) $z))` the equation compiles
to a fact, and the same rule still emits a real goal where it cannot fold:

```prolog
'twenty-two-more'(42).
'at-runtime'(A, B, C) :- plus(A, B, C).
```

Three things make this work, and each is easy to get wrong.

Declare the form's parameters `Atom`, as *Taking an argument unevaluated* below
describes, or the translator evaluates them before your rule sees them and a
planner meaning to inspect `(vec-scale $v $k)` receives that vector's value.

Guard every shape test with `nonvar/1` first. A planner sees unbound subterms
whenever a value comes from an earlier goal, and `['vec-add', S, W]` with `S`
unbound unifies happily with the fused shape, so the rule emits a scale that
never happens.

Return the form itself, with no `quote` around it. A rule written in MeTTa
evaluates its own `quote` and expands to whatever `quote` returned; a rule that
builds the term in Prolog is already holding that term, so quoting it there
hands the translator a list it can only read as data. The engine refuses that
by name, as it refuses a `translatePredicate` or `call` whose shape it cannot
compile.

## 2. Prolog grounded predicates: new primitives, native speed

A predicate follows the compiled calling convention, inputs then one output,
and is registered from MeTTa:

```metta
!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_mine.pl) (my-op other-op))
```

No boundary is crossed: the engine is Prolog, so this is an ordinary call. Use
it for anything that needs a real implementation and is called often. Every
library in `lib/` that is not pure MeTTa works this way, including
`lib_string`, `lib_file`, `lib_json` and `lib_thread`.

### What the interface guarantees

A registered predicate is compiled into a direct call. `(my-double 21)` becomes
`'my-double'(21, A)`, with no dispatch and no boundary in between, and its
**nondeterminism is the MeTTa function's answer set**: a predicate that offers
three solutions gives `(collapse (my-pick 7))` the answer `(7 7 7)`.

Three things it refuses rather than doing quietly, because each used to produce
a silent wrong answer:

- **A name with no predicate behind it.** A registration records the arities
  the name is callable at, so a name with nothing behind it records none, and
  `incomplete_application_kind/3` reads a missing arity as "not applied far
  enough": every later call compiled into a *partial application* instead of
  failing. `!(no-such-predicate 1)` answered `(partial no-such-predicate (1))`
  and the import reported success. It raises now, where the name is written.
  **This trap is the reason every registration door on this page names its
  predicates explicitly rather than discovering them.**
- **A file that is not there.** `consult/1` throws
  `existence_error(source_sink, Path)` and names the file.
- **A source that does not load cleanly.** SWI PRINTS a syntax error inside a
  consulted file and the load then succeeds with the predicate undefined, so
  the author's whole diagnostic used to be one line on stderr while the API
  reported success. The load now raises with the file, the line and the column.

### Which module your predicate lands in

Your predicate must be in the HOST module, `user`, which is where
`consult_global/1` puts it. A Prolog library loaded from inside a named space
defines itself in that space's module, where the registration cannot see it,
and every call to it used to compile to a partial application. That is an error
too.

`user` is the host, and it is not where MeTTa code lives. Every space, `&self`
included, compiles its equations into a module of its own, which
`space_module/2` names, and those modules inherit the engine's and through it
`user`. So a predicate you consult into `user` is reachable from every space,
and an equation a program writes cannot replace it: the equation lands in the
space's own module and shadows it there. Two consequences:

- Ask `space_module/2` for a module; never write one. `with_metta_module/2`
  takes that module and REFUSES a space name, because the two are different
  atoms and passing the wrong one would silently run your goal against a module
  nothing compiles into.
- If you call a MeTTa function from Prolog, qualify it with that module. An
  unqualified call resolves where YOUR clause was compiled, which for a
  consulted extension is `user`, and `user` is the parent: it cannot see a
  space's clauses. If you hand a goal to one of the engine's own predicates
  instead, the engine's `meta_predicate` declarations carry the module for you.

A registration also records WHERE its clauses live, which is what keeps it
working after a space defines an equation of the same name. Without that, one
named space claiming a name turned every registered predicate into inert data
in every space. That space's own equation still shadows it, which is the
behaviour that should happen.

### Add a builtin type without replacing the type table

A Prolog library may add an intrinsic type by contributing one clause to the
`seam:builtin_type_declaration/2` declaration seam:

```prolog
:- metta_extension(my_blob_types, [version('0.1.0')]).
seam:builtin_type_declaration('my-blob', 'MyBlob').
```

Do not redeclare the predicate in the library. The engine declares it
`multifile`, so this clause joins the builtins parsed from
`lib_builtin_types.metta`; unloading the extension removes only the library's
clause. The engine's other arrows remain present before, during, and after the
extension's lifetime [tested:
`test_a_library_types_its_own_blob_without_destroying_the_table`;
commit=1a5459b9e81b168ee402bf9eda2c407e55f7eae0].

### Taking an argument unevaluated

Declare the parameter `Atom` and the argument arrives as written:

```metta
(: shape-of (-> Atom Atom))
!(shape-of (+ 1 2))            ; the predicate sees (+ 1 2), not 3
```

This is what a control form needs, and it is not Python-only: it works on a
Prolog-registered predicate exactly as on a Python one. Minimal MeTTa's
`function` and `unify-mod` are built on it, which is how the whole instruction
set moved out of Python. Measured 2026-08-15: `(function (return 42))` cost
36.14 inferences and 3.95us as a Python operation and 11.14 and 0.21us as a
Prolog predicate, so 3.2x fewer inferences and 18.8x faster.

Declare it only where you mean it. An operation whose argument must arrive
*evaluated* and is declared `Atom` receives the literal expression instead of
its value, which is a silent wrong answer rather than an error.

The same distinction is visible at the Python decorator. Given `(= (side) 42)`,
a registered `def anyatom(x: metta.Atom)` receives and may return `(side)`,
while an otherwise identical unannotated `def anyval(x)` receives `42`. The
annotation changes the call's evaluation order; it is not documentation applied
after evaluation.

### Calling a Prolog goal without registering anything

Registration publishes a name. For a goal you do not want to publish, or a
one-off, MeTTa can reach Prolog three ways, and they do not cost the same.

**`(call (goal ...))` compiles straight into the clause body and needs no
registration at all.** It follows the same convention, inputs then one output:

```metta
!(call (succ_or_zero 3))       ; compiles to succ_or_zero(3, Out)
```

`translatePredicate` is the same idea with the output slot written out:

```metta
!(progn (translatePredicate (is $x 2))
        (translatePredicate (+ $x 40 $z))
        $z)                              ; 42
```

`translatePredicate` is written for its BINDINGS rather than its value: it
compiles the goal inline and leaves the variables bound for the rest of the
form, which is why it appears inside a `progn`. Both are live in the tree:
`lib/lib_tabling/lib_tabling.metta`, `lib/lib_spaces/lib_spaces.metta`,
`examples/ch20-extending-the-engine/20-02-metta-written-in-metta/01-callquoteevalreduce.metta`
and
`examples/ch20-extending-the-engine/20-03-prolog-underneath/01-translatepredicate.metta`.

**`(callPredicate (Predicate ...))` builds the goal term at run time** through
`=../2` and meta-calls it, which costs about five inferences more than the two
above:

```metta
(= (consult_file $prologfile)
   (callPredicate (Predicate (quote (consult_global $prologfile)))))
```

`quote` matters here and is not optional decoration. `Predicate` is an ordinary
registered function, so **its argument is evaluated first**. When the goal names
something that is also a MeTTa function, the unquoted form applies that
function and raises a domain error naming arities you never wrote. Quote it and
the goal reaches `Predicate` as written. `assertaPredicate`, `assertzPredicate`
and `retractPredicate` are the same idea for the database.

### Arguments are bidirectional, and the output slot takes an input

The convention does not stop a value flowing into the last argument, because
Prolog unification does not care which way a value flows. The output slot is
just an argument, and a `let` puts a value into it:

```metta
(= (consult-it $path) (let $path (consult_global) done))
```

Read that carefully, because the shape is the point. `consult_global/1` has one
Prolog argument, which the convention makes the OUTPUT slot, so its MeTTa arity
is zero and it is written `(consult_global)` with nothing in the parentheses.
The `let` then unifies the path INTO that slot. `lib/lib_import/lib_import.metta`
already relies on this.

The same fact runs the other way. A registered predicate can BIND a caller's
unbound variable, and the binding escapes into the MeTTa program:

```metta
!(let $v (binds-its-input $free) ($free $v))
```

**If you get `is/2: Arguments are not sufficiently instantiated`, you wrote the
output slot first.** It is the most likely mistake at this tier, and the
message names `is/2` rather than your predicate because by then the engine is
inside arithmetic and has no way to know which argument you meant as the
answer. `'scale'(Out, X) :- Out is X * 2.` called as `(scale 21)` becomes
`'scale'(21, Out)`, so it computes `21 is Out * 2` and stops. Inputs first, one
output last:

```prolog
'scale'(X, Out) :- Out is X * 2.
```

Wrapping it in `rethrow_metta_operation_error/2` puts your predicate's name on
the message, which is worth doing anyway; it does not tell you the argument
order is the cause, so this paragraph does.

So reach for `let` first, and for `callPredicate` only when the goal really has
to be built at run time. Both directions are pinned:
`the_output_slot_takes_an_input` and
`a_registered_predicate_binds_a_callers_variable` in
`tests/prolog/suites/host/prolog_interface.plt`, the second asserting the exact
bindings that escape, `((a a!) (b b!) (c c!))`.

## 3. C foreign predicates: wrapping what is already native

When the work already exists in C or Rust, you do not need Prolog in the
middle. Follow SWI's foreign interface and the same calling convention, inputs
then one output:

```c
#include <SWI-Prolog.h>

static foreign_t pl_c_bump(term_t x, term_t y)
{ int64_t v;
  if ( !PL_get_int64_ex(x, &v) ) return FALSE;
  return PL_unify_int64(y, v + 1);
}

install_t install_cbump(void)
{ PL_register_foreign("c-bump", 2, pl_c_bump, 0);
}
```

Build it with `swipl-ld`, which knows where the headers are:

```sh
swipl-ld -shared -o cbump cbump.c
```

From Python, one call loads it and registers what it defines:

```python
m.register_foreign_library(Path(__file__).parent / "cbump.so",
                           entry="install_cbump", names=["c-bump"])
```

`entry` is the C initialiser, `install_cbump` in
`install_t install_cbump(void)`; leave it out when the entry is plain
`install`. The path is resolved to an absolute one for you: a relative path
resolves against the working directory, SWI deprecates that and warns on every
load, so a library shipping one works from the repo root and warns or fails
anywhere else.

From MeTTa, load and register it the same way as any other Prolog:

```prolog
% loader.pl
:- use_module(library(shlib)).
:- use_foreign_library('/abs/path/cbump.so', install_cbump).
```

```metta
!(import! &self (library lib_import))
!(import_prolog_functions_from_file "loader.pl" (c-bump))
!(c-bump 41)                                    ; 42
```

Give `use_foreign_library/2` an absolute path or a `foreign(Name)` alias.

Two obligations the convention puts on you. Return `TRUE` or `FALSE`, and use
the `_ex` accessors (`PL_get_int64_ex` and friends) so a wrong argument type
raises a proper Prolog type error rather than failing silently. And if your
predicate has more than one solution, that is `PL_retry`/`PL_foreign_control`
with the `PL_FA_NONDETERMINISTIC` flag; a deterministic foreign predicate that
should have been nondeterministic loses answers with no sign that it did.

`extensions/mork/mork_ffi/mork.c` is the worked example in this repo, and it
shows the other load route: `LD_PRELOAD` in `run.sh`, which is right when the
library must be present before the engine boots.

The engine itself ships one C unit at this seam: `engine/reader.c`, the
shipped-mode MeTTa reader, which `engine/parser.pl` loads from `reader.so`
beside it and consults for every parse while no custom token class is
registered. `check.sh` builds it with `swipl-ld -shared -O2`; without the
artifact, or with `METTA_C_READER=off` in the environment, every parse runs the
Prolog grammar, which remains the reader's specification and is held equal to
the C port by `tests/prolog/suites/reader/reader_c.plt` over the shipped
corpus, an adversarial battery, and generated number spellings. A custom
`register-token!` class always routes to the Prolog grammar, so a token
extension never has to know the C reader exists.

### Hand back a handle, not a serialisation

The expensive mistake at this boundary is converting your structure to text.
`extensions/mork/mork_ffi/mork.c` does exactly that: reading MORK's answer for
a single `(fact a 1)` costs **4.49us and 149 inferences to parse**, against
**0.37us and 2 inferences for the FFI call that produced it**
[measured 2026-08-16]. The crossing is cheap. The text is not.

Give MeTTa an opaque handle instead. SWI's blob interface does this and the
engine needs no changes for it: a blob already answers `Grounded` to
`get-metatype`, compares by identity, and prints through the type's own
callback, so it is an ordinary MeTTa value.

```c
static PL_blob_t vector_blob =
{ PL_BLOB_MAGIC, PL_BLOB_NOCOPY, "vector",
  release_vector, NULL, write_vector, NULL
};

static foreign_t pl_vector_new(term_t length, term_t out)
{ vector_t *v = ...;                      /* malloc'ed, owned by the blob */
  return PL_unify_blob(out, v, sizeof(*v), &vector_blob);
}
```

```metta
!(vector-length (vector-new 1000))       ; 1000
!(vector-nth (vector-new 1000) 700)      ; 700
```

`examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/handle.c` is the
worked version, with its own example and README beside it. On a
thousand-element vector, reading one element through the handle costs
**0.1968us and 2.00 inferences**, while writing that vector as text costs
**389.94us and 16,906 inferences** and reading it back costs **919.35us and
44,600** [measured 2026-08-16]. The handle's cost is flat in the structure's
size and the text's is linear, the same shape as raw transport against the
encoded path in the argument-size table above.

The handle crosses to Python too, by reference. A blob reaching the Python
boundary arrives as `metta.Handle`, an opaque atom carrying a registry id and
the blob's own printed text; hand it back and the very same native object
answers, so identity and mutation survive the round trip, and a Python function
can unpack the structure through whatever accessors the extension registered
[measured 2026-08-17; pinned in
`extensions/python/tests/ch19_spaces_backed_by_anything/test_c_handle_crossing.py`].
`release()` retracts the engine-side registry entry that keeps the blob alive;
a released handle raises by id instead of answering wrongly.

Two things the blob interface asks of you. `PL_BLOB_NOCOPY` means SWI keeps the
pointer you hand `PL_unify_blob`, so hand it heap memory and not the address of
a local. And write a release callback, because that is where the structure is
freed when SWI garbage-collects the handle; without one, every handle leaks.
## 4. Python grounded operations: reaching the host

```python
@m.op(name="my-op", effect="pureStructural")
def my_op(x):
    return x + 1
```

This is how you reach NumPy, PyTorch, an LLM, a database, or anything else
Python can see. It costs the janus crossing, so it earns its price when the
work on the other side is substantial and loses it when the operation is
trivial. `lib_torch` and the `arrays` integration are both this.

### Writing logic in Python: use `@m.define`, not `op`

`op` is for **reaching Python libraries**: NumPy, an LLM, a database, anything
whose value is on the other side of the crossing. It is not for writing logic
in Python. For that there is `@m.define`, which reads the function's source
with `ast` and lowers it into MeTTa equations:

```python
@m.define
def classify(n):
    if n < 0:
        return "negative"
    return "positive" if n else "zero"
```

Those equations compile like any others, so the call costs within one inference
of a hand-written MeTTa equation: 5.00 against the hand-written 4.00 in the
table above, which is a compiler result rather than a coincidence. There is no
crossing at run time and no Python in the loop.

The subset is a real subset, and a construct outside it is refused by name and
line rather than silently falling back to a Python operation. `_define_twins`
keeps the original function reachable as `.py`, so a compiled equation can be
checked against its Python twin on any ground input.

Annotate it and every call goes through typed dispatch. That is the right trade
where you want the checking and the wrong one in an inner loop over values the
compiler cannot see; a literal argument costs nothing extra, because its type is
settled while the call site compiles. What the check costs, and why the
inference counter cannot see it, is under the cost table above.

### Relational generators and distinct inverses

A generator operation can state a relation once. Yield an exact tuple for a
positional candidate row, or an exact dict keyed by parameter name for a sparse
row. The engine unifies each candidate against the call, so the same body serves
free, partially bound, and ground arguments:

```python
@m.op
def route(origin, destination):
    yield (S.paris, S.lyon)
    yield (S.paris, S.lyon)       # multiplicity is data
    yield {"destination": S.nice}  # origin is unconstrained
```

```python
all_routes = m.fn.route(V.origin, V.destination)
list(all_routes)                  # [UNIT, UNIT, UNIT]
list(all_routes.destination)      # [lyon, lyon, nice]

from_paris = m.fn.route(S.paris, V.destination)
list(from_paris.destination)      # [lyon, lyon, nice]

to_lyon = m.fn.route(V.origin, S.lyon)
list(to_lyon.origin)              # [paris, paris]
```

Every yielded occurrence is considered once, so an effectful generator fires its
effect exactly once per candidate searched, including a candidate a bound
argument rejects. The third row leaves its origin unbound, so its row projection
carries the query's alpha-renamed origin variable. Ground arguments filter rows;
variables bind through the engine matcher, including its custom grounded and
space matching. `Answer(value=...)` is the explicit escape when an exact tuple
or dict is one result value rather than a parameter row. Relational rows require
encoded transport, because raw arguments cannot carry unbound positions.

`inverse=` serves a different shape: the forward operation produces a result,
and a separate implementation recovers arguments from that result. Supply it
when that backward algorithm is genuinely distinct:

```python
m.op(
    lambda head, tail: (head, *tail),
    name="concat",
    inverse=lambda whole: (whole[0], tuple(whole[1:])),
    effect="pureStructural",
)
```

```metta
!(concat 1 (2 3))                          ; -> (1 2 3)
!(let (concat $h $t) (1 2 3) ($h $t))      ; -> (1 (2 3))
```

The inverse takes the result and returns the arguments, as a tuple of the
operation's width, or the bare value at arity one. It is a **relation**, not a
function, so a generator enumerates every preimage and `None` or `Decline` means
there is none, which fails rather than raising:

```python
def roots(y):
    yield (int(y ** 0.5),)
    yield (-int(y ** 0.5),)

m.op(
    lambda x: x * x,
    name="sq",
    inverse=roots,
    effect="nondeterministicReadOnly",
)
# !(collapse (let (sq $r) 9 $r))  ->  (3 -3)
```

It runs only when the arguments are not ground and the result is, so a forward
call never reaches it. An operation that declares no inverse compiles exactly
the clause it compiled before. A relational generator needs no inverse, because
its tuple or dict rows already bind the arguments directly.

An arbitrary foreign function cannot be narrowed automatically, which is why the
declaration exists at all: Curry does not invert its own `external` functions
either, and Prolog's `plus/3` and `succ/2` use mode-aware implementations.
`ch08-data/08-01-atoms-lists-and-folds/06-invertfunction.metta` shows what an
equation can derive instead, including solving `$X + 35 = 42` through a
constraint while destructuring a list in the same pattern.

### Keep the Python when you rewrite it in Prolog

The reason to write the reference in Python and the fast one in Prolog is that
you then have two implementations of one function, which is a differential
oracle. Declare them together and it stays one:

```python
@m.define(prolog=Path(__file__).parent / "fast.pl")
def vec_dot(a, b):
    """The readable reference."""
    return sum(x * y for x, y in zip(a, b))
```

The Prolog is registered and answers `(vec-dot ...)`; the Python is not compiled
and stays reachable as `vec_dot.py`. The file must register that function's own
MeTTa name, at the twin's arity of inputs then one output, and says so if it
does not. Its `metta_export` declaration owns the types, so annotations on the
Python are documentation.

Then run the pair:

```python
from metta import testing

def test_the_fast_one_still_agrees():
    testing.check_twin(vec_dot, [((1, 2), (3, 4)), ((0,), (9,))])
```

`cases` is an iterable of argument tuples; drive it with hypothesis for a real
sweep, using the strategies `metta.testing` already exports. A generator twin is
compared answer by answer in order, and a twin that RAISES on a case requires
the engine to answer nothing for it, which is the disagreement most worth
catching: a reference with no answer and a fast side that invents one.

### Building a fast library on pymetta

`op` is the extension point most people find first, and it is the slowest tier.
If you are writing a library **on top of pymetta** and its hot path is
arithmetic, matching or list work, ship Prolog and register it from Python:

```python
# inline, for a small helper
m.register_prolog("'vec-dot'(A, B, Out) :- ... .", names=["vec-dot"])

# or a file shipped beside your Python package
m.register_prolog(path=Path(__file__).parent / "fast.pl",
                  names=["vec-dot", "vec-norm"])
```

Those predicates run at tier 2 speed, about a third of the cost of the same
operation written as a Python op, while your library still installs with
`pip install` and configures itself in Python.

Four things are refused, all of them before the source loads, because a
consulted predicate replaces the engine's own the moment it loads and no later
refusal can undo that:

- a name with **no predicate** behind it, the partial-application trap in
  section 2;
- a **builtin's** name, because your clauses would replace the engine's for
  every program in the process. A named space compiles its own clauses, so an
  equation there shadows a builtin for that space alone;
- a **special form's** name, because the translator compiles those before
  function dispatch, so the registration could never be reached;
- a name **another tier already owns**. One name has one owning tier, refused in
  both directions, with the incumbent left usable.

Nothing is registered unless every name can be, so a typo in the list changes
nothing. The consulted source does stay loaded on failure, which is deliberate:
loading it again is the retry, and it is idempotent, because the source is
identified by a hash of its own content.

### Declare your exports in the file that implements them

Passing `names=` works and is fine for a snippet. For a library, declare in the
`.pl` instead, and the name, the arity and the type stop being three statements
nothing keeps in agreement:

```prolog
:- metta_extension(pettorch, [version('0.3.1')]).
:- metta_export("
    (: vec-dot (-> Number Number Number))
    (: shape-of (-> Atom Atom))
    (export vec-helper 1)
").

'vec-dot'(A, B, Out) :- ...
```

```python
m.register_prolog(path=Path(__file__).parent / "fast.pl")   # no names=
m.unregister_prolog("pettorch")                              # everything, gone
```

The declaration is MeTTa, in a string, because the types are MeTTa types and the
reader that parses them is the engine's own. The MeTTa arity comes from the type
chain, so `(-> Number Number Number)` means `'vec-dot'/3` and a declaration
naming an arity the file does not define is refused rather than registered.
`(export name arity)` is the form for a name whose type you do not want to
state.

Three things follow, and the middle one is the reason to bother:

- **A helper that shares your prefix is not published.** The arity used to be
  DISCOVERED from whatever `current_predicate/1` held, so a library shipping a
  public `'vec-dot'/3` and an internal `'vec-dot'/2` published both.
- **The type cannot land late.** It arrives with the name, so the ordering trap
  cannot open: a call site compiled before a separate `(: ...)` declaration
  keeps evaluating an `Atom` argument for ever, and nothing warns.
- **The registrations go together.** `unregister_prolog` releases every name the
  extension installed, its type declarations, and its clauses. There is no
  uninstall to write, and no way to release one member on its own, which is what
  stops one registry keeping a claim on a name another route replaced.

### Say what a caller may assume

```prolog
:- metta_export("
    (: now (-> Number))
    (volatility now volatile)
").
```

PostgreSQL's ladder, because purity is not a boolean: `volatile` makes no
assumptions, `stable` gives the same answer within one evaluation, and
`immutable` gives the same answer forever. A `volatile` function refuses to be
memoized, naming itself, because caching a function whose answers are not
reproducible skips whatever the call does on the second one.

Silence stays permission, deliberately. Memoization is already opt-in by the
CALLER, so making an undeclared function refuse would break every existing
`(memoize f)` without telling anyone anything they did not know. What was
missing is the LIBRARY's ability to say no.

### Say how many answers there are

```prolog
:- metta_export("
    (: vec-dot (-> Expression Expression Number))
    (determinism vec-dot det)
").
```

A predicate that leaves a choice point behind costs its callers about twice, and
**the inference counter cannot see it**: no-cut, cut and SSU dispatch of the
same workload all reported exactly 1,000,003 inferences while wall clock was
0.1887, 0.0928 and 0.1128. Declare `det` and SWI's own `det/1` raises where the
leak is, at your door, instead of taxing everyone who calls you.

Read `det` as **exactly one answer, always**, not at most one. SWI raises
`Deterministic procedure f/2 failed` as readily as it raises on a choice point,
so a function whose empty answer set is a legitimate result is `semidet`, not
`det`. Getting this wrong turns a normal no-answer into an error.

`semidet` and `nondet` are recorded rather than checked, since SWI has a
directive for `det` alone. They are still worth writing, because
`profile_extension` reports them beside the redo count: a redo on a function
declaring `nondet` is the function working, and a redo on one that declared
nothing is a question.

### Say which seam you were written against

```prolog
:- metta_extension(pettorch, [version('0.3.1'), requires(1-0)]).
```

A library built on today's `ext_points.pl` will be loaded into a later engine,
and with nothing to check against a removed or renamed hook shows up as silence.
Erlang's NIF loader is the model: the major must match and the minor must not be
newer, or the load fails, naming both versions. A library that declares nothing
keeps working, so this costs nothing until you use it.

### Say what platform you need

```prolog
:- metta_requires(concurrency).
:- use_module(library(thread)).
```

Every platform library the engine loads is optional, because a real build can
lack them: SWI compiled to WebAssembly, which the browser playground and the
Node binding run on, has no `library(thread)`, no `library(time)` and no
`library(process)`, and an SWI built without its pcre, zlib, fastrw or memfile
packages lacks the rest. The engine records what it found at boot, and
`metta_platform/4` is the census:

```prolog
?- forall(metta_platform(C, S, R, Costs), format("~w ~w ~w~n  ~w~n", [C,S,R,Costs])).
concurrency present library(thread)
  (hyperpose ...), and lib_thread's par-map, spawn, await, channels, pools ...
deadlines present library(time)
  (timeout N Expr) and (pragma! max-time N); a wall-clock bound has to ...
subprocess present library(process)
  (git-import! ...), and anything else that starts a program
regex present library(pcre)
  lib_regex, so (re-match ...), (re-find ...), (re-captures ...) ...
compressed-sources present library(zlib)
  reading or writing a .gz program or space file; the same content ...
fast-cache present [library(fastrw),library(memfile)]
  saving a space in the fast binary format and loading one back; every ...
```

A row rests on one library or on several, and the status is `present` only when
every one of them resolves. What an absence COSTS is the row's own text and it
varies: `regex` takes forms away, so those forms refuse; the `.gz` reader loses
a file format, so a compressed path refuses naming the file while the same
program uncompressed loads; and the fast cache costs no MeTTa form at all,
because the engine never reads a cache of its own accord.

If your library cannot work without one of those, say so at the top of the file
that imports it. The engine reads the declaration out of your source *before it
runs the source*, the same scan that reads your `metta_export` block, so an
import on a build without the capability refuses naming the capability, the
library and what its absence costs, and your file never half-loads. Declaring
nothing keeps working, and a capability name the engine does not know is refused
where you wrote it rather than at the first call.

For a decision your own code makes at run time, ask the census, or call
`metta_require_platform(Form, Capability)` to refuse in the engine's own words:

```prolog
my_parallel_map(Goal, In, Out) :-
    metta_require_platform('(my-par-map f xs)', concurrency),
    concurrent_maplist(Goal, In, Out).
```

### Prove your provider before your users do

```python
from metta import testing

def test_my_provider_conforms():
    testing.check_space_provider(MyProvider(rows))
```

It drives every capability the provider declares, refuses one declared without a
method behind it, and checks the contract that everything else rests on: a
provider may over-approximate its match and may never under-approximate, so
every stored atom must be answered by a pattern that is the atom itself. A
provider that filters too eagerly fails there rather than answering an empty set
in production. From MeTTa the same three checks are
`(check-space-provider &mine)` in `lib_conformance`.

### Find out where YOUR library's time goes

The table at the top of this page answers what a tier costs in general. Once
your library is written, the question is narrower: of the functions I
registered, which one is costing me, and is anything wrong with how it went in.

```python
groups, costs = m.profile_extension("!(my-workload)", extension="mylib")
for cost in costs:
    print(cost)
# <mylib-join/3 prolog: 40100 calls, 39900 redos, 812 ticks, index 1x>
# <mylib-norm/2 prolog: 40100 calls, 0 redos, 41 ticks, index 300x>
```

Every declared member gets a row, including one the workload never reached,
which is the answer to "did that registration take". `names=[...]` takes an
explicit list instead.

Two columns are worth reading before the ticks. **Redos** are the engine
re-entering your predicate for another answer, which is what a leftover choice
point looks like from outside. **speedup** is the ratio SWI computes for the
clause index it chose, so `index 1x` means no argument discriminates and every
call walks your clause list; `indexed` False on a function nothing has called
much only means SWI has not built the index yet, since it builds them on first
need. A row also carries what the library DECLARED, so redos read against
intent.

Calls and redos are counted, so they are exact. Ticks are sampled, so profile
something that runs.

### Dispatching on a value's type

Almost every registered predicate starts by asking what it was handed. Write
that as an if-then-else chain and stop worrying about the order:

```prolog
my_text(Value, Text) :-
    (   string(Value) -> Text = Value
    ;   atom(Value)   -> atom_string(Value, Text)
    ;   number(Value) -> number_string(Value, Text)
    ;   throw_metta_type_error('my-op', 'String', Value)
    ).
```

SWI inlines `var/1`, `atom/1`, `number/1`, `string/1`, `atomic/1`, `compound/1`
and `callable/1`, so a chain of them costs the same whichever order you write it
in: testing a number after passing over `string` and `atom` is 3.00 inferences,
exactly what testing it first costs [measured 2026-08-16]. Order them so the
code reads well.

Four tests are not inlined and every call that passes over one pays for it:
`is_list/1`, `is_dict/1` and `blob/2` cost two inferences each, `ground/1` costs
one. Put those last, or guard them with an inlined test the way the engine's own
type probe guards its `blob/2` with `atomic(X), \+ atom(X)`.

The three alternatives are all worse for this, which is worth saying because
each of them is right somewhere else. Per call, on the same inputs [measured
2026-08-16]:

| shape | inferences/call |
|---|---|
| if-then-else chain | 4.17 |
| a clause per type, guard and cut | 6.17 |
| SSU `=>` rules with guards | 8.17 |
| compute a tag, dispatch on it | 11.17 |

A type test cannot be a clause index, because indexing needs the argument's
principal functor in the head and "any string" is not one. Computing a tag to
get an indexable first argument does not rescue it either: a four-clause
predicate gets **no index at all**, still `none` after 50,000 calls, and the tag
has already cost you seven inferences. Reach for SSU when the clauses would
otherwise leave a **choice point**, which is a different problem and one the
inference counter cannot see; the chain above already leaves none.

### Two libraries cannot take one name

A consulted file REPLACES a static predicate of the same name, and SWI only
warns about it, on stderr, where no caller sees. Two libraries each shipping
`'norm'/2` used to mean the second silently wiped the first: library A's answer
changed the moment B loaded, and both registrations reported success. A second
Prolog source claiming a name another one owns is now refused, naming the file
that owns it. The refusal necessarily comes after the load, because SWI prints
rather than throws and no `catch/3` can see it, so the only reliable check is a
positive one afterwards.

A refusal is the right answer when one of the two libraries is wrong. It is the
wrong answer when neither is: two packages you do not control both export
`norm/2`, and you need both. Ship them as Prolog **modules** and rename at the
import, which is how Prolog has resolved this for thirty years:

```prolog
:- module(liba, ['norm'/2]).      % in each library's own file
```

```python
m.register_prolog(path="liba.pl", names={"norm": "liba-norm"})
m.register_prolog(path="libb.pl", names={"norm": "libb-norm"})

m.one("(liba-norm -5)")     # 5
m.one("(libb-norm -5)")     # 25
```

`names` as a mapping is `{the module's own name: the MeTTa name}`. The arity
comes from the module's export list, so you write two names and no arity, and a
name the module does not export is refused with the list of what it does. This
is SWI's own `use_module/2` import list underneath, so the renamed name is a
real imported predicate rather than a wrapper, and costs nothing per call.
Without it SWI declines the second import, prints `No permission to import
libb:'norm'/2 into user (already imported from liba)` on stderr, and continues,
which leaves the newcomer silently bound to the incumbent's code.

### Ship files beside your Python package

```python
# in your package's __init__
m.register_library_path(Path(__file__).parent / "prolog", "pettorch")
```

Or say nothing at all and let `pip install` be the whole of the wiring. An
integration that ships Prolog and no Python setup names its files:

```python
# in your package's __init__
METTA_PROLOG = ["fast.pl"]
```

`m.integrate(pettorch)` and `metta.integrate.discover(m)` then register the
library path and every file, and each file declares its own exports, so there is
no name list anywhere. `(library pettorch fast.pl)` then resolves, from MeTTa and
from `register_prolog(path=...)`. Without it a pip-installed library is under
neither the engine's `lib/` nor a git checkout, so it has to compute absolute
paths from `__file__` by hand. This is SWI's own `file_search_path/2`, so an
alias registered here is one every SWI tool already understands, and aliases
compose.

Use Python for what Python is for, the host libraries and the configuration, and
Prolog for the inner loop.

**There is no public "call any Prolog goal from Python" surface, deliberately.**
The supported way to reach your own Prolog from Python is to register it and
call it as a MeTTa function, which keeps one set of conversion rules, one error
taxonomy and one lock. A raw goal is janus's job, and janus is importable
directly. `m.prolog()` opens the interactive toplevel, which is for debugging.

## 5. Reader token classes: adding literal syntax

Use a reader token class when a domain value needs a compact literal rather than
a function call. A class maps one full-token regular expression to a
constructor. The Python door retains a callable:

```python
from metta import S

m.register_token(
    r"[0-9]+kg",
    lambda token: S.kilograms(int(token.removesuffix("kg"))),
)
assert m.parse("12kg") == S.kilograms(12)
m.unregister_token(r"[0-9]+kg")
```

MeTTa source can register a symbol constructor. It receives the complete matched
spelling as its argument:

```metta
!(register-token! "[A-Z][0-9]+" tagged)
; A7 now reads as (tagged "A7")
!(unregister-token! "[A-Z][0-9]+")
```

Matching is against the complete token. A later registration of the same pattern
replaces its constructor, and custom rows precede the shipped numeric and string
rows. Registration changes future parses only: an atom already returned by
`parse` is a value and is not reinterpreted. If a constructor raises or fails
after claiming a token, parsing fails; the reader does not silently turn that
spelling back into a symbol.

The engine owns the table and its replacement lifecycle.
`metta_host_register_reader_token/2` and
`metta_host_unregister_reader_token/1` are the transport doors, while
`seam:host_reader_token_construct/3` is the host ownership callback used to
invoke a retained constructor. A host binding should call those doors rather
than maintaining a second registry.

## 6. Space providers: where atoms actually live

A provider answers `match`, `add`, `remove` and enumeration for a named space
whose atoms live wherever you keep them: a SQL table, a dataframe, a service, a
remote engine. The engine keeps unification for itself, so a provider may
over-approximate its filtering and stay correct; pushing the bound parts of a
pattern down into the backend is a performance lever, never a correctness
requirement.

There are two ways in, and they differ in cost the same way tiers 2 and 3 do.

**From Python**, implement the `SpaceProvider` protocol in
`extensions/python/metta/foreign.py` and `register_space`. Every match crosses
the janus boundary, which is right when the atoms live somewhere Python already
talks to. `das.py`, `remote.py` and `persistent.py` are three real instances.

**From Prolog**, add clauses to the multifile seams in the `seam` module:

```prolog
:- multifile seam:foreign_space/1.     % this space is mine
:- multifile seam:foreign_add/2.       % add an atom
:- multifile seam:foreign_remove/3.    % remove one
:- multifile seam:foreign_atoms/2.     % enumerate
:- multifile seam:foreign_match/3.     % answer a pattern
:- multifile seam:foreign_clear/1.     % empty the space
:- multifile seam:foreign_erring/5.    % a declared error mode's stream
:- multifile seam:foreign_begin/1.     % transactional participation:
:- multifile seam:foreign_commit/1.    %   one begin at the first write,
:- multifile seam:foreign_rollback/1.  %   one commit or rollback after
```

A provider file declares an EXTENSION and exports nothing, which is what makes
it loadable at all:

```prolog
:- metta_extension(mylib_space, [version('1.0.0')]).
```

`metta_export` is for functions and a provider has none.
`m.register_prolog(path=...)` accepts the file and answers `()`, because it
registered no functions. Ship it the way section 4 ships any `.pl`, by listing
it in your package's `METTA_PROLOG`. A file that declares NEITHER is refused
before it loads.

The engine consults `seam:foreign_space/1` before reaching its own storage, so
your clauses take the space over entirely, with no boundary crossing. This is
how MORK plugs a Rust trie in underneath MeTTa:
`extensions/mork/mork_ffi/morkspaces.pl` is a complete worked example, and
`examples/ch19-spaces-backed-by-anything/19-02-a-space-in-c/` is the smallest
one, a mutex-guarded C store behind four clauses, proven by the conformance kit
inside its own example and driven concurrently by `hyperpose` and a Python
thread pool.

Worked instances exist per language and per backend class, so start from the one
nearest yours: C
(`examples/ch19-spaces-backed-by-anything/19-02-a-space-in-c/`), SQL derived
from one declaration (`extensions/python/metta/tables.py` with
`extensions/python/examples/integration/sqlite_space.py`; DuckDB with pushdown
in `duckdb_space.py` beside it), another MeTTa runtime as a subprocess
(`cmetta_space.py`), TypeScript over the wire
(`extensions/python/examples/integration/typescript_space/`, which also
documents the remote protocol itself; `metta.testing.GatewayComplianceSuite`
certifies any implementation of that protocol by URL), and Redis
(`lib/lib_redis/lib_redis.pl`).

Prove it before your users do with `check_space_provider`, in section 4.

**The seam is order-independent, and that is the point of it.** Every one of the
operations above consults `seam:foreign_space/1` as a guard before reaching
native storage, so it does not matter when your file loads. Do not add raw
`match/4` clauses instead: declaring `match/4`, `add-atom/3`, `remove-atom/3`
and `get-atoms/2` multifile puts your clauses ahead of the engine's whenever
your file loads first, which makes the engine's own instantiation guards
unreachable. MORK did that and `(get-atoms $any)` answered from MORK rather than
refusing.

### Naming a space

Name your space with a leading `&`, as `&mork` and `&plunit_seam` do. That is
the engine's rule for every atomic space name and not a convention: the door
that creates a space refuses any other spelling, `new-space` refuses it,
`register_provider` refuses it on the Python side, and neither wire codec can
carry it. `metta_space_operand/1` reads the prefix before it asks either
registry, so a provider that skips it is answered "no space" by the matcher,
`get-metatype`, the type-candidate resolvers, the translator and the codec,
without an error anywhere. `sh check.sh prolog-static` scans the loaded database
and refuses such a name by name. A **parametric** space is named by a ground
expression rather than an atom and carries no prefix.

#### Take the name, so a second provider cannot

`seam:foreign_space/1` is a CONDITION on a name, so it answers "is this one
yours" and nothing else: the engine cannot enumerate claimed names and you
cannot see your peers without naming them. Two providers whose clauses both
matched one name resolved by clause order, and an atom landed in whichever store
loaded first with nothing said.

Take the name through the engine when your provider goes live, and give it back
when it stops:

```prolog
metta_claim_space('&shared', redis)          % this name is mine
metta_claim_space(prefix('&mork'), mork)     % every name under this one is
metta_disclaim_space('&shared', redis)       % and here it is back
metta_space_claim(Extent, Owner)             % the table, enumerable
```

A claim that meets a live claim of another owner refuses naming both and the
remedy; one that meets only your own succeeds, so a re-registration and a
narrower claim by the same provider both pass. Releasing a claim that is not
there passes too, because a teardown may run twice; releasing someone else's
refuses.

`prefix(P)` is there because ownership is sometimes genuinely a namespace.
MORK's is: every space beginning `&mork` is its, each `&mork:<name>` store is
created on first use, and there is no per-name attach point an exact claim could
hang on. Linux's char-device registry is the same shape and settled it the same
way: a claim is a RANGE, a duplicate is `-EBUSY`, and `/proc/devices` enumerates
the table (`fs/char_dev.c`, `__register_chrdev_region`).

Put the call at your ATTACH point, whatever that is. `lib_redis` claims in
`redis-attach` before it opens a socket and releases on any later failure, the
Python seat claims as it registers a provider, and MORK claims its namespace in
a load-time directive because loading is when it goes live. Nothing on an
operation's path calls any of this, and that is deliberate: a duplicate
ownership test there would cost a second solution on every space operation
[measured 2026-08-28: 2,000 MORK adds and a flush, 2,000 MORK matches, and a
2,000-atom native write-and-match read 256,979, 531,796 and 78,028 inferences
identically before and after, five runs each].

### Say what your provider answers

```prolog
:- multifile seam:foreign_capability/2.
seam:foreign_capability('&mine', Capability) :-
    member(Capability, [add, remove, match, enumerate]).
```

The capabilities are `add`, `remove`, `match`, `enumerate` and `clear`. A space
declares what it provides and the declaration means exactly what it says:
declaring nothing provides nothing, and an operation a space does not declare is
refused naming the capability. Declaring buys two further things.

**Enumeration is enough.** A provider that declares `enumerate` and not `match`
has its enumeration filtered by the engine for a bound pattern, instead of
answering nothing.

**A missing operation refuses instead of vanishing.** An operation a space did
not declare raises `permission_error(Operation, foreign_space, Space)`, naming
both. Four of the five used to fail silently: a write vanished, a removal
reported nothing removed, and a match answered the empty set while the space
demonstrably held matching atoms. A write that merely FAILS is an error too,
because a write either happened or it did not.

### Say why you are saying no

A capability your space does not provide is refused by the engine, and the
refusal is generic unless you write one:

```prolog
:- multifile seam:foreign_refuse/2.

seam:foreign_refuse('&mine', add) :-
    throw(error(metta_readonly_space('&mine'), context(add, 'load it with the importer'))).
```

It THROWS rather than answering; reaching the end of it means the engine and
your provider disagree about what you provide. A Python provider gets this for
free from its `refusal()` method, which is why "does not implement add" reads
differently there from "declines this add request".

### Take a whole batch in one crossing

One crossing per atom is the wrong shape for bulk ingestion, so a seventh hook
is optional:

```prolog
:- multifile seam:foreign_add_many/2.  % a list of atoms, your way

seam:foreign_add_many('&mine', Atoms) :- mine_bulk_load(Atoms).
```

Write it and `m.add(a, b, c)`, `add-atom` over a list, and any other bulk write
reach you once with the list. Leave it out and you get one `seam:foreign_add/2`
per atom. The write hooks are yours either way.
`extensions/mork/mork_ffi/morkspaces.pl` implements it by joining the atoms into
one payload that MORK parses itself.

**A batch is a transport optimisation and never a semantic one.** Whatever the
engine does for an atom on its own it must still do when the atoms arrive
together, so it routes only atoms whose add is a store and nothing more through
this hook: an equation or a type declaration anywhere in the list drops the
whole batch to `add-atom/3` per atom, and you never see it here. That is
enforced upstream rather than asked of you, because it was got wrong: the Python
bridge chose the bulk path for MORK itself and so skipped the rule, and an
equation added alongside any other atom was stored inert while the same equation
added alone compiled.

### Claim a whole join

The engine splits a conjunction one pattern at a time and re-dispatches the next
on every binding of the previous. That is a nested-loop plan, and a provider that
never sees more than one pattern cannot do better than one however fast it is.
Say you take conjunctions and you get them whole:

```prolog
:- multifile seam:foreign_plan/5.

%   seam:foreign_plan(Space, Patterns, Claimed, Rest, Goal)
seam:foreign_plan('&mine', Patterns, Patterns, [], mine_join('&mine', Patterns)).
```

```python
class Joins(SpaceProvider):
    def plan(self, patterns):
        rows = my_backend.join(patterns)      # or None to decline
        return list(patterns), [], iter(rows)
```

Nothing about the MeTTa changes.
`(match &mine (, (edge $x $y) (edge $y $z)) ($x $z))` is the same query it always
was; the claim happens underneath it. That is the point of doing this as a space
rather than as a query API: a backend is reached the way every other space is
reached.

**Declining is the default and always legal.** No clause, or `None`, and you get
exactly today's behaviour. **A partial claim is legal too**: take the two
patterns you own and leave the third in `Rest`, and the engine plans the
remainder as it always did. `Claimed` and `Rest` must partition the conjunction;
dropping a conjunct is refused, because the engine plans only what you leave, so
a dropped pattern stops constraining the query and the join answers rows nobody
asked for.

**A claim is exact, and this is the one place the seam's usual rule is
reversed.** Everywhere else you may over-approximate freely because the engine
re-unifies each candidate you yield, which costs a unification. There is no
cheap re-check for a join: verifying one row means running the join. So the
engine trusts a claim, a provider that cannot answer a conjunction exactly must
decline it, and `check_space_provider` verifies the claim against the engine's
own split instead of taking your word for it.

What it is worth, measured on MORK's real join against the engine's split over
the same store. Two workloads, because they say different things:

| workload | split grows | claimed grows | ratio |
|---|---|---|---|
| triangle, output-bound (2,730 rows from 3,060 edges) | n^2.95 | n^3.3 | 27x to 19x, shrinking |
| triangle over two hubs, intermediates ~N² and output ~2N | n^1.99 | n^1.49 to n^1.79 | 33x to **68x**, growing |

The first is a large constant factor and nothing more: when the answer itself is
most of the work, both plans have to enumerate it and the gap closes. The second
is the case worst-case-optimal joins exist for, where the pairwise intermediates
blow up and the answer does not. There the split is pinned to the intermediate
size and the claim is not, and the ratio grows with the data [measured
2026-08-16, `instructions:u`, min of 2 per point, baseline subtracted].

### Letting the backend do less

Two levers a provider backing a SQL table or a vector index needs are already in
place, and both are easy to miss.

**The bound parts of a pattern reach you, including from a join.** Query
`(fact $k $v)` and `(other $k $w)` together and your `match` is called once with
`(fact $_ $_)` and then once per outer row with `(other a0 $_)`,
`(other a1 $_)` and so on. Those ground positions are your `WHERE` clause.

**The engine stops pulling as soon as it has enough.** A provider is driven
lazily, so a `limit=3` query against a provider holding a thousand atoms pulls
four of them and abandons the generator [measured 2026-08-16]. You do not need
to be careful about yielding a lot; you need to be lazy about producing it.

What neither tells you is a COUNT, which is what a backend needs to write
`LIMIT 3` rather than fetch a page and throw it away. Take a `limit` keyword and
you are told:

```python
class Rows(SpaceProvider):
    def match(self, pattern, *, limit=None):
        sql = "select subject, object from facts where subject = ?"
        if limit is not None:
            sql += f" limit {limit}"
        ...
```

```prolog
seam:foreign_match('&mine', Pattern, Options) :-
    ( memberchk(limit(N), Options) -> true ; N = unbounded ),
    ...
```

It is **optional on the Python side**. A provider whose `match` takes no `limit`
keyword is called without one, decided from the signature the way capabilities
are decided from the narrow protocols. In Prolog there is one match hook and the
options are always passed, so a provider with nothing to do with them writes
`_Options` and is done.

There is deliberately no `order` option. MeTTa's match promises no answer order,
so a provider ordering its output changes nothing a program can see, and no
consumer can ask for one.

### Say when your filtering is exact, and get the bound

The bound is only safe for a provider whose candidates ARE its answers. You may
over-approximate, so N candidates are generally not N answers, and truncating at
N without knowing which of them unify answers fewer rows than exist, which is
the one thing the contract forbids. So the number goes to a provider that has
said, for this pattern, that it does not over-approximate:

```python
class Rows(SpaceProvider):
    def match(self, pattern, *, limit=None): ...

    def pushdown(self, pattern):
        # Exact when the WHERE clause covers everything the pattern
        # constrains: a ground position becomes a comparison, and a variable
        # needs none, so what is left is what the query would ignore.
        unfiltered = (
            arg for arg in pattern.args
            if not isinstance(arg, Gnd) and not isinstance(arg, Var)
        )
        return "inexact" if next(unfiltered, None) is not None else "exact"
```

```prolog
:- multifile seam:foreign_pushdown/3.
seam:foreign_pushdown('&mine', [_|Args], Class) :-
    ( forall(member(A, Args), (var(A) ; ground(A))) -> Class = exact
    ; Class = inexact ).
```

Answer `"exact"` when every candidate you yield for that pattern unifies with
it, and `"inexact"` otherwise. Say nothing and you are inexact, which is always
safe: you are called exactly as a provider written before this was, and you are
never handed a number you could wrongly truncate to.

Ask **per pattern**, not per provider. A backend is usually exact on an indexed
equality and inexact on a scan, and one flag for the whole provider would force
it to claim the weaker answer everywhere.

**The claim is about the whole pattern, not your best column.** A provider that
indexes the subject and answers `(fact a $n)` precisely is still inexact for
`(fact a 1)` if its query ignores the second position, because it yields
`(fact a 3)` too. Filtering brilliantly on one position while the pattern
constrains another is inexact however good that one filter is.

**Where the number comes from.** Two callers set one, and they follow the same
rule: `m.match(pattern, limit=k)` from Python, and `take` from MeTTa.

```metta
!(collapse (take 3 (match &mine (fact $k $v) (fact $k $v))))
```

Both push the bound down only when the request is ONE pattern against ONE space,
because across a join the bound belongs to the joined rows and an outer match
truncated at k loses the rows its later candidates would have joined to. In
MeTTa that means the match's template has to be the pattern itself, as above;
give it a computed template or a conjunction and you get the answers bounded and
no number, which costs you nothing but a chance to be faster.

The bound is always applied by the engine as well, so honouring it can make you
cheaper and can never make an answer wrong. That is why ignoring it is always
correct.

This is Apache DataFusion's `TableProviderFilterPushDown`, whose `Exact` rung
reads "Your source guarantees that no output rows will have a false value for
this predicate. Because the filter is fully evaluated at the source, DataFusion
will not add a `FilterExec` for it", against `Inexact`, "Your source has the
ability to reduce the data produced, but the output may still include rows that
do not satisfy the predicate". Spark's DataSourceV2 draws the same line, as
filters "that need to be evaluated after scanning" against those that do not.
DataFusion's third rung, `Unsupported`, has no counterpart here: it exists
because its planner decides whether to send a filter at all, and the pattern is
the only thing a MeTTa provider is given.

A claim that is wrong costs answers, so `check_space_provider` tests it against
your own output, matching every stored atom against itself and failing if a
pattern you called exact yields anything that does not match. It is the one
claim in the seam that unification cannot cover for you: everything else you say
is protected by the engine re-unifying, and this is the one that licenses you to
stop early. The worked instance is
`extensions/python/examples/integration/duckdb_space.py`, whose `pushdown` reads
exactly the positions its `WHERE` clause covers and whose claim the kit
confirms: `pushdown: 3 of 3 patterns claimed exact, and are`.

### Hold rules, not only facts

In MeTTa a space is BOTH a data source and where the program lives, and that is
the point rather than a nuance: evaluation is match against `(= lhs rhs)` atoms,
facts and rules are the same kind of thing, and `add-atom` of an equation is how
a program grows. `&self` is a knowledge base and a program at once.

Say your space holds equations and the engine evaluates through it:

```prolog
seam:foreign_capability('&mine', Capability) :-
    member(Capability, [match, enumerate, add, remove, rules]).
```

```python
class Rules(SpaceProvider):
    def can_run(self, capability, /, **request):
        if capability == "rules":
            return True
        return super().can_run(capability, **request)
```

Nothing else is asked of you. You store an equation the way you store any other
atom, and the engine compiles it, so
`(add-atom &mine (= (double $x) (* 2 $x)))` then makes `(double 21)` answer
`42`. Nothing in your provider has to know what an equation is.

That the engine compiles it is the whole of the design, because the obvious
alternative is wrong. Reading evaluation as "match the space for
`(= (f Args) $body)` and reduce `$body`" is the naive reading, and MeTTa's own
tutorial says where it falls short: the interpreter "is performing some
additional processing on top of such equality queries". Three of those
differences bite immediately. A body is evaluated further, so
`(= (nest) (+ 1 (* 2 3)))` must not hand `(* 2 3)` to `+` as a list. A
bare-variable body must NOT be evaluated, or an `Atom` parameter comes back
reduced. And `if` evaluates only the branch it takes, so `(= (loop) (loop))`
under an `if` has to terminate. Going through the compiler gets all of them and
every future one for free; a second evaluator would get them wrong one at a
time. The suite pins this as a differential: the same eleven programs run in a
native space and in a foreign one and must answer identically
[`tests/prolog/suites/spaces/spaces.plt`,
`a_foreign_space_evaluates_exactly_as_a_native_one`].

Two things to know. A rule you hold BELONGS TO YOUR SPACE, exactly as a native
named space's equations belong to it, so it is called from there:
`(metta (double 21) %Undefined% &mine)` rather than `(double 21)` in `&self`.
And the engine learns about an equation when it goes through `add-atom`, so one
that appears in your space by another door, your own bulk loader or a backend
calculus like MORK's `mm2-exec`, is stored and inert.

Say nothing and an equation added to your space is REFUSED at `add-atom`, naming
the capability.

### Say what your change events promise

`subscribe` is the sixth capability and the only one no method can answer. The
other five ask what your provider implements; this one asks what your CONTEXT
can deliver, and the difference is the whole of it: a remote space implements
`add` and `remove` and its contents still change on the server, so a watcher
here would hear this process's own writes and silently miss every other one.

```prolog
:- multifile seam:context_events/3.
seam:context_events('&mine', 'per-write-exactly', ordered).
```

```python
class Announcing(SpaceProvider):
    def delivers(self):
        return ("per-write-exactly", "ordered")
```

Delivery is `at-most-once`, `at-least-once` or `per-write-exactly`, and order is
`ordered` or `unordered`. Say `per-write-exactly` and `ordered` when every change
to your space comes through this engine, because then the engine's own write
hooks are an exact event source; say what your channel promises when you have
one of your own, as a Redis-attached space says `at-most-once` and `unordered`
because pub/sub is fire and forget; and **say nothing at all when your contents
change where no channel reports it**. A space that declares nothing is refused a
subscription, a `bridge` and a `space.reaction`, naming the missing capability,
instead of serving a watcher that quietly misses writes.

A Python provider's answer is written for it, as the space's ordinary
`(events <ctx> <delivery> <order>)` declaration in `&metta`, so a MeTTa program
reads the promise the engine acts on. Use `seam:context_events/3` when you own a
FAMILY of names rather than one, the way every `&mork` space belongs to one
backend, and there is no single name to write the atom about. A native space
declares nothing and is watchable anyway: that is a fact about the engine's own
store, not a promise a provider is making.

Use the Prolog seam when the backend is reachable from Prolog or C and the query
volume is high; use the Python one when the backend is a Python library.

### A value that owns its own matching

Two seams carry custom matching, Hyperon's CustomMatch: a grounded value may own
its matching logic, consulted by `(unify ...)` when the value meets a
non-variable operand.

```prolog
:- multifile seam:matchable_value/1.   % this value owns its matching
:- multifile seam:custom_match/2.      % one solution per binding set
```

`seam:matchable_value/1` says a value has such logic, and `seam:custom_match/2`
enumerates one solution per binding set, binding the other operand's variables
through ordinary unification; no solutions means no match. Variables always bind
the value whole without consulting it, and a value nobody claims falls through to
ground equality. The Python side implements both for any object whose class
defines `match_` (see `metta.foreign.CustomMatch`), so a Python value
participates with no registration at all; a Prolog-hosted value participates by
adding clauses to these seams.

### Shipping a native backend

A backend whose implementation is a shared library needs one thing a Prolog
provider does not: somewhere to be loaded from. That is a folder in
`extensions/` carrying an `extension.pl`, a control file of FACTS the engine
reads and never runs.

```prolog
% extensions/mine/extension.pl
title('Spaces on mine').
needs(artefact('mine_ffi/target/release/libmine.so')).
needs(predicate(open_shared_object/3)).
entry(engine, 'mine_ffi/minespaces.pl').
```

`extensions/README.md` is that file's own contract: the whole `needs/1` and
`entry/2` vocabulary, what each script must do, and which lane fails when it
does not. Two rules matter from here. The engine knows no seat by name and reads
every control file in `extensions/` when the host passes `extensions`, so a boot
without the token reads none of them, which is the pure kernel. And **not built
is not an error while half built is**: a seat with an unmet need loads nothing
and says nothing at boot, and one whose needs hold and whose entry is broken
raises.

Two multifile hooks go with it, and both exist so the engine never has to name a
backend:

```prolog
:- multifile seam:extension_builtin/2.  % a builtin your extension provides, and its effect
:- multifile seam:backend_selftest/0.   % your smoke test, run by the CLI demo

seam:extension_builtin('mine-add', writesState).
seam:extension_builtin('mine-run', oracleIO).
```

Declare `seam:extension_builtin/2` in the file that DEFINES the predicates, not
in `extensions/mine/extension.pl`, so the names exist exactly when the predicates
do: registering a name whose predicate is absent is the partial-application trap
in section 2.

The second argument is the builtin's effect class, and it is required. Your
builtin becomes an ordinary `builtin_fun`, and a world's coverage declaration is
checked against every operation it might run, so an unclassified builtin would
have to take the engine's fail-closed `oracleIO` floor: safe, but it says
"nobody looked" in the same voice as "reviewed and unbounded", and no world
covering `writesState` could then call your writer. The engine cannot review it
for you, because reviewing means naming, and naming your predicates here is the
thing this page promises you never have to force.

Declare the WEAKEST of the five ranked classes that is honestly true:
`pureStructural`, `readOnlyLookup`, `nondeterministicReadOnly`, `writesState`,
`oracleIO`. Overstating refuses programs that should run; understating admits
ones that should not. If what your builtin reaches is decided at run time by
data, or by a foreign library the engine cannot bound, it is `oracleIO`. That is
a review, not a default, and it is why MORK's `mm2-exec` is one while its two
writers are `writesState`.

One thing your file must NOT do: load a library that installs a process-global
`system:goal_expansion/2` or `system:term_expansion/2` that can REFUSE source it
does not understand. Those hooks run while compiling every module in the
process, so an expander that raises silently drops other people's clauses. SWI's
own `library(arithmetic)` does exactly this, and the engine repairs that one at
boot and re-repairs it whenever it is installed again
(`guard_arithmetic_goal_expansion/0` in `engine/metta.pl`, with a
`prolog_listen/2` watcher). A benign rewriting expansion is fine; scope anything
sharper inside your own module. `sh check.sh prolog-static` holds the canary,
`_ is foo + 1` must expand to itself without an exception, and the plunit lane
fails any suite that prints ERROR while it loads.

#### Saying that a library rests on a seat

A seat loads at boot. A `lib/` module loads when a program imports it. When the
second rests on the first, say so in its first form:

```metta
!(require-extension! mork)
```

It answers the unit and costs one indexed lookup when the seat is loaded. When
it is not, it refuses and the message is TRANSITIVE: it names the extension, why
that extension is not loaded, and the command that clears it.

```
'lib/lib_mm2/lib_mm2.metta': extension mork is required and not loaded:
artefact extensions/mork/mork_ffi/target/release/libmork_ffi.so is absent
(run extensions/mork/build.sh) (while loading MeTTa file)
```

The requiring file comes from the loader's own frame rather than from the form,
so a require typed at a REPL names only what is missing. A need of kind
`extension(Other)` is followed into `Other`'s own cause, so a chain two seats
deep is one message; the walk carries a seen list and reports a cycle instead of
looping.

`lib/lib_mm2/lib_mm2.metta` is the shipped case, five operators over `&mork`
calling MORK's own builtins. PostgreSQL has the same two-half split and answers
it the same way: `pg_stat_statements` is a preloaded C module plus a
per-database `CREATE EXTENSION`, and the second without the first raises
`pg_stat_statements must be loaded via shared_preload_libraries`. What this adds
is that `needs/1` is data, so the cause can be followed and the message can end
in the remedy.

### What you may call back

Everything above is the engine calling you. This is the other direction, and it
is short on purpose: seven predicates you may call, and they are the only ones.

```prolog
swrite(Term, Text)                  % a MeTTa atom as text
sread(Text, Term)                   % text back as a MeTTa atom
metta_symbol_writable(Symbol)       % does this name survive the round trip
metta_unwritable_symbol(Term, Bad)  % the first value in Term that does not

throw_metta_type_error(Op, Expected, Got)   % raise as a builtin would
rethrow_metta_operation_error(Op, Error)    % put your name on somebody else's
current_metta_module(Module)                % which module the call site is in
```

You need the first four because being a shared library is a text problem. Your
atoms live on the far side of a boundary that carries bytes, so every atom you
store gets written and every atom you hand back gets read, and both spellings
have to be the engine's rather than yours.

The last two of those four are one rule worth knowing before you store anything.
`swrite/2` will happily print a symbol that `sread/2` does not read back as the
same symbol, because MeTTa has no quoted-symbol syntax: a name with a space, a
parenthesis or a quote in it comes back as something else. You cannot decide
that for yourself, the grammar owns it, so ask and refuse:

```prolog
seam:foreign_add('&mine', Atom) :-
    (   metta_unwritable_symbol(Atom, Bad)
    ->  throw(error(domain_error(mine_text_symbol, Bad),
                    context('add-atom'/3,
                            'that name cannot cross a text boundary')))
    ;   swrite(Atom, Text),
        mine_store(Text)
    ).
```

MeTTa's own builtins are published too and are not repeated in that list. Call
`'add-atom'/3` or `match/4` the way any program calls them.

Anything else under `engine/` is an internal, and calling one is a gate failure
rather than a style note:

```
the backend predicate mine_store/1 calls register_prolog_arities/1, which is
an engine internal rather than published surface
```

`tests/prolog/static_checks.pl` reads the declaration in `engine/ext_points.pl`
rather than a list of its own, so a backend that reaches for an eighth thing
fails the gate with the line above. The walk is SWI's `prolog_walk_code/1`,
which means a call hidden in a `maplist/3` argument or in a helper of yours that
takes a goal is found too. If you need something that is not there, say so and
it can be declared; the last three above arrived that way. The point is that the
surface is written down, not that it is small.

### Native spaces with a declared base

The constructors below are the engine's own rather than provider seams, and they
decide where a space's atoms are read from and which module its equations
compile into.

A space may name one parent at creation:

```metta
!(new-space &child (inherits &parent))
```

Its execution module bases on the parent's module, and its stored-atom reads
form a child-first multiset union over the same chain. Each conjunct routes
through that union independently, so a child fact can join a parent fact. Adds,
removals, clear, and `space-atom-count` stay local to the child. Declare the
parent before first use; the same declaration is idempotent, while a different
parent, a cycle, or dropping a parent that still has a live child is refused by
name. Python spells the same constructor `runtime.new_space(inherits=parent)`,
and dropping the child only unlinks the child.

A restricted space selects a curated execution base instead of `&self`:

```metta
!(new-space &locked (restricted))
!(new-space &reader (restricted (grants file)))
```

The curated base publishes computation but withholds file, process, and network
operations. A missing operation raises
`metta_space_capability_required(Space, Operation, Capability)` at runtime, so
`catch` can observe it and Python receives `SpaceCapabilityError` with the same
three fields. Grants are explicit and fixed at creation. Raw
`translatePredicate` and `call` goals also pass SWI's `sandbox:safe_goal/1`; an
unsafe unclassified host goal requires the `process` grant. Restriction and
inheritance are alternative execution bases and cannot be combined.

A ground expression may itself identify a native space:

```metta
!(new-space (cache &kb 100))
!(add-atom
   (cache &kb 100)
   (= (cache-config)
      (let (cache $base $limit)
           (context-space)
           (config $base $limit))))
!(evalc (cache-config) (cache &kb 100)) ; (config &kb 100)
```

The constructor accepts one finite, ground, nonempty expression headed by a
symbol, and validates that shape before publishing any module cache. The exact
term is the identity: numeric kind, strings, nesting, and every parameter are
part of it. Each identity maps through canonical term text to private storage
and execution modules; stored expressions use one reserved predicate functor
inside the already-private storage module, because a compound cannot be a Prolog
functor.

Parameters need no second reflection builtin. Logtalk's parametric-object model
makes the identifier visible to the entity's predicates; here the existing
`context-space` supplies that identifier and ordinary head-pattern destructuring
reads it. A registered expression stays literal in a SpaceType position. An
unregistered expression still evaluates, preserving computed space code such as
`(add-atom (space-name) atom)`.
## 7. Atom hooks: reacting to writes

`seam:atom_added/2` and `seam:atom_removed/2` are multifile predicates in
`engine/ext_points.pl`. Assert a clause and every write to a space calls it.
This is how Python subscriptions deliver, and how `lib_thread`'s `await-atom`
blocks on a space without polling.

**Shipping the clause in a consulted file works too**, which is what the
`multifile` declaration is for and what a library usually wants:

```prolog
:- multifile seam:atom_added/2.
seam:atom_added(Space, Term) :- my_index_update(Space, Term).
```

The write wrapper is installed lazily, and a clause arriving from a FILE reaches
the channel that installs it just as an `assertz` does. That is worth saying
because `prolog_listen/2`'s documented action list does not mention loading, so
reading the manual suggests the opposite; it was probed, and the hook fires on
the next write either way.

Assert it instead when the handler is only needed once a feature is used: a
resident clause costs four inferences on every compiled equation, and a library
that installs on first use pays nothing until then. The cost is per write and
only while a hook exists. `metta_add_hooks_idle/1` takes a space off the bulk
fast path exactly when somebody is listening, so an unobserved space pays
nothing.

A HOST is asked the same question about its own hooks, through
`seam:host_add_hooks_idle/2` and `seam:host_remove_hooks_idle/2`. The engine
hands over the whole handler census as clause references and the host answers
whether every one of them is its own and idle for that space, so a host that
installed one bridging clause can take the bulk path back without the engine
knowing anything about how the host tracks its subscriptions:

```prolog
:- multifile seam:host_add_hooks_idle/2.
seam:host_add_hooks_idle(Space, [OnlyRef]) :- my_bridge_clause(OnlyRef),
                                              \+ my_subscriber(Space, _).
```

With no host loaded the seams have no clause and the engine's own no-handlers
test has already answered, so nothing is paid for the question.

That census question works while every handler belongs to a host. It stops
working the moment one does not: the engine's own reaction bridge is a single
`seam:atom_added/2` clause with an unbound `Space`, because any space might
carry a reaction, so its head cannot say which spaces it watches and no host
can answer for it either. The census then held two references where a host
clause matches one, the answer was "not idle" for every space, and the batched
program-atom door fell back to the per-atom one: a forty-equation fast-cache
restore went from 30,274 inferences to 4,496,299, 149x, because of one reaction
on a space it never touched.

`seam:atom_hook_ref_idle/2` is the per-reference half. Whoever installed a hook
answers whether that ONE reference is idle for one space, from whatever table
it keeps, and the engine subtracts every reference so claimed before asking the
host census about the rest. A host that installed one bridging clause is still
asked the question it was written for.

```prolog
:- multifile seam:atom_hook_ref_idle/2.
seam:atom_hook_ref_idle(Space, Ref) :- my_bridge_clause(Ref),
                                       \+ my_reaction(Space, _).
```

Answer only for references you installed. A clause that claims someone else's
reference idle turns their handler off.

### The one way to get a handler wrong

Write your guard as `( Condition -> Action ; true )`, not `Condition, !`:

```prolog
% wrong: silently disables every handler loaded after yours
seam:atom_added(Space, Term) :-
    my_space(Space), !, my_index_update(Term).

% right: same guard, same cost, prunes nothing
seam:atom_added(Space, Term) :-
    ( my_space(Space) -> my_index_update(Term) ; true ).
```

Atom hooks run through `forall/2`, so every handler is called. A cut in your
clause prunes the remaining clauses of `seam:atom_added/2`, and those are the
other libraries' handlers. Nothing reports it. `lib_tabling` cut after a global
condition once, `duals.pl`'s invalidation handler was ordered after it and never
ran, and `(not-provable (pq 2))` answered True and False at once.

**This rule differs by seam, and it governs every seam on this page.** Each one
carries its kind as a fact beside its declaration in `engine/ext_points.pl`:

```prolog
?- seam:kind(seam:atom_added/2, Kind).
Kind = event.

?- seam:kind(seam:foreign_match/3, Kind).
Kind = ownership.
```

- An **event** seam runs for its effect and runs every handler, so no cut. The
  callers enumerate handlers with `forall/2`, and a cut in one clause silently
  disables every handler loaded after it.
- A **declaration** seam is a fact table the engine reads, so no cut there
  either.
- An **ownership** seam is claimed by the first handler that succeeds, so a cut
  after a guard proving the request is yours is correct and fast. The
  foreign-space hooks are these: `lib_redis` cuts after
  `redis_space_conn(Space, _)`, which fails for a space redis does not own, so
  no other provider's clauses are touched. The question to ask of your guard is
  whether it proves the request is yours or is merely true.
- A **service** is the odd one out, because it runs the other way: you write the
  clauses of the first three and the engine calls them, while a service is a
  predicate the engine defines and you call. `swrite/2` is one, and it cuts,
  correctly.

`seam:clauses_from/2` is what says which way a kind runs, and the cut checks
read that rather than the kind, so a service is not mistaken for a handler that
has gone wrong. Two checks enforce it, so a cut in the wrong place fails the
build rather than surfacing as a wrong answer months later: one scans the tree's
sources, the other scans the live database after the libraries load, because a
handler installed with `assertz` at run time is in no file to read.

From MeTTa the same list is `(extension-points)` in `lib_reflect`, answering
`(name arity kind)` one per solution, both directions included.

### Owning a pattern modifier

`seam:pattern_modifier/3` is the ownership seam for structural pattern views. A
clause receives the source pattern, returns the pattern the store should match,
and returns a guard that runs over the resulting bindings. The first clause that
succeeds owns that pattern position, so its guard must establish the modifier's
full semantics rather than acting as an event notification.

Call the engine service `lift_pattern_modifiers/3` when an extension builds a
pattern outside the ordinary translator. It walks nested patterns, applies the
same first-success ownership rule at each eligible position, and returns the
guards in evaluation order. The built-in `(:= value)` equality view and
`(: $variable Type)` typed-variable view are the reference implementations in
`engine/translator.pl` [source: engine/ext_points.pl, seam:pattern_modifier/3
and engine/translator.pl, lift_pattern_modifiers/3;
commit=ea0bd45cc9f3991e41f61d8f6bf4d4e6cb992776].

### Making your errors read like a builtin's

A library predicate that throws reports in the vocabulary of whatever threw.
`'i16-scale'(X, Y) :- Y is X * 2.` given a symbol says
`system:(is)/2: Arithmetic: 'foo/0' is not a function`, which names an engine
internal rather than the operation the program wrote. Builtins avoid that with
`rethrow_metta_operation_error/2`, which keeps the ISO formal term so a MeTTa
`catch` still inspects it and replaces only the host context:

```prolog
'vec-dot'(A, B, Out) :-
    catch(vec_dot_(A, B, Out), Error,
          rethrow_metta_operation_error('vec-dot', Error)).
```

Measured on the same predicate both ways, given a symbol where a number belongs:

```
unwrapped   EngineError:          is/2: Arithmetic: `foo/0' is not a function
wrapped     MettaOperationError:  'vec-dot': Arithmetic: `foo/0' is not a function
```

Both halves change: the name becomes the operation the program wrote, and the
CLASS becomes `MettaOperationError`, so a caller can catch a library's operation
errors specifically instead of catching every engine error. This is a convention
rather than a hook, so it costs nothing on the path that does not use it.

For an error your library raises itself, throw a term of your own and give it a
rendering:

```prolog
:- multifile prolog:error_message//1.

vec_dot_or_refuse(A, B) :-
    ( same_length(A, B) -> true
    ; throw(error(vec_length_mismatch(A, B), context(vec_dot/3, _))) ).

prolog:error_message(vec_length_mismatch(A, B)) -->
    [ 'vec-dot needs two vectors of one length; got ~w and ~w'-[A, B] ].
```

The formal term is what a `catch` inspects, so keep the data in it and put the
prose only in the message clause. Two rules, both learned the hard way in this
engine. **Match on your own formal alone**, never on SWI's `context/2` with an
unbound argument: a clause head that binds it relabels every ordinary error of
that shape, which once made every type error in the process report as a MeTTa
operation error. And **keep a file's message clauses together**, because SWI
warns about discontiguous clauses of a multifile predicate and the warning is
easy to lose in a load.

### A signal that must not be recovered from

An error your library raises for a caller to handle is one thing. A CANCELLATION
is another: a budget your library enforces, a stop your library's worker was
told to make, a deadline. If you throw one as an ordinary term, the first
recovery catch it meets swallows it and the program continues as though nothing
happened. A swallowed limit signal here also disarmed
`call_with_inference_limit` for the rest of the call, measured at six million
inferences spent under a thousand-inference budget.

So say so, and every recovery site in the engine will let it through:

```prolog
:- multifile control_exception/1.

control_exception(mylib_cancelled).
control_exception(error(mylib_budget_exceeded(_), _)).
```

This is KeyboardInterrupt living outside Exception. The engine's own entries are
the limits, the abort and the interrupt; yours join them, and an ordinary error
from your library still takes the recovery it should.

It has to arrive by CONSULTING, not by `assertz`: the seam is static, like the
foreign-space hooks, so a runtime assert raises "No permission to modify static
procedure". Declare it in the file that raises the signal.

### Make a value applicable

MeTTa's own definition of a Grounded atom is that it "may contain any binary
object, for example operation (including deep neural networks), collection or
value". An operation is a thing you call, and the engine could not call one: a
head that was neither a function name nor a partial application was left
unreduced, so a Python function, a compiled model or any other host callable
held in a MeTTa variable was a value you could pass around and never apply.

```prolog
:- multifile seam:grounded_apply/3.

%   seam:grounded_apply(Value, Args, Out)
seam:grounded_apply(Obj, Args, Out) :- my_callable(Obj), my_apply(Obj, Args, Out).
```

Succeed to claim the head and bind `Out`; **fail and the expression stays
unreduced**, which is what a value that is not an operation should do rather than
raising.

A companion answers the same question with no arguments to hand:

```prolog
:- multifile seam:grounded_applicable/1.

seam:grounded_applicable(Obj) :- my_callable(Obj).
```

`bind!` needs it. A name bound to a callable is callable by that name, which is
the language's own idiom (`(bind! abs (py-atom numpy.absolute))` then
`(abs -5)`), and deciding that at bind time means asking whether a value is an
operation before there are any arguments. The engine consults this only for a
head that is neither a function name nor a partial application, so an ordinary
MeTTa call never reaches it.

Nothing in the engine knows what makes a value applicable, which is the point.
`extensions/python/bridge.pl` claims Python callables, which is what makes
`((py-atom numpy.absolute) -5)` work; a bridge for something else claims its own.

### Make a value numeric without converting it

A host's numeric object may be a MeTTa `Number` without becoming a Prolog
number. Keep recognition and execution in the host that owns the value:

```prolog
:- multifile seam:grounded_numeric/1.
:- multifile seam:grounded_numeric_operation/3.

seam:grounded_numeric(Value) :- my_numeric_object(Value).

% seam:grounded_numeric_operation(Name, Arguments, Result)
seam:grounded_numeric_operation(Name, Arguments, Result) :-
    member(Value, Arguments),
    my_numeric_object(Value), !,
    my_numeric_call(Name, Arguments, Result).
```

`seam:grounded_numeric/1` is the admission question. The engine asks it only
after the unchanged native `number/1` branch declines, once for each operand.
When every operand is numeric and at least one belongs to a host,
`seam:grounded_numeric_operation/3` receives the operation name and the whole
argument list. The first owning provider supplies one result. A value no
provider admits reaches the ordinary `BadArgType` answer with the same class
walk and multiplicity it had before.

Do the operation through the value's own protocol rather than converting it to a
Prolog `float` or `integer`. The Python bridge recognizes `numbers.Number` and
uses Python's reflected operators or the object's array namespace, so a NumPy
scalar remains the same object at the transport boundary and adding it produces
the NumPy result type. Native arithmetic never consults either seam, so its
existing fast path and inference count do not move.

### Give a value a structure, without giving up the value

MeTTa names three things a grounded value may define for itself: "Grounded value
type creators can define custom **type**, **execution** and **matching** logic
for the value". Type is the class walk below, execution is
`seam:grounded_apply/3`, and this is matching.

```prolog
:- multifile seam:grounded_structure/2.

%   seam:grounded_structure(Value, Expression)
seam:grounded_structure(Obj, Elements) :- my_sequence(Obj, Elements).
```

The problem it solves is that a host container wants to be two things at once.
Held as a value it must stay the host's own object, so that identity survives, a
mutation is visible, and passing it back hands over the same thing. Taken apart
it should read like any MeTTa expression. Answer this and it does both:
`car-atom`, `cdr-atom`, `size-atom`, `sort-atom`, `index-atom` and `decons-atom`
all consult it, and only for an argument that is not already an expression, so
nothing you do here can slow an ordinary list down.

It is one atom with two readings, not two answers, and the disambiguation is the
language's own. A space atom nested in another space already behaves this way: a
query that is "just a variable, e.g. `$x`" matches the atom itself, and a
structured query is delegated inward. So a variable binds your value and a
pattern reads its elements.

Two things to get right. **Check cheaply before you build anything**: this is
consulted for every term that is not a MeTTa expression, so a guard that
allocates before it can fail is a cost with no result. Reading a functor with
`compound_name_arity/3` allocates nothing where `compound_name_arguments/3`
builds the whole argument list first, and the difference measured at 402 million
instructions on one benchmark while showing up nowhere in its inference count.
And **the second argument may arrive partly bound**: if it is a proper list you
can reject on length alone, which is how matching `($x $y)` against a
million-element host container costs one question rather than a million.

A value with no structural reading simply has no clause here, and that is a real
answer rather than a gap: `extensions/python/bridge.pl` gives one to Python
sequences and withholds it from a `dict`, a `set` and a `str`, following PEP
634's rule for which objects a sequence pattern may take apart.

### Say how a value prints

```prolog
:- multifile seam:grounded_text/2.

%   seam:grounded_text(Value, Text)
seam:grounded_text(Obj, Text) :- my_object(Obj), my_render(Obj, Text).
```

The writer has no other way to know. With no provider it falls back to the
term's own text, so this is never required and can never fail a print, but that
fallback names an address where the value could have named itself:
`extensions/python/bridge.pl` answers with `repr`, which is why
`(py-atom "[1, 2, 3]")` displays `[1, 2, 3]` and a numpy array displays
`array([1, 2, 3])`.

### Classify every operation, then compose effects

Every Python operation must name its strongest observable effect. Four
decorators are the short way to say it, and each is `op` with `effect` filled
in, so `transport=` and every other argument compose with them:

```python
@m.pure                      # nothing but its arguments
def size(items) -> int:
    return len(items)

@m.io(name="now")            # a clock, randomness, a network, a file
def read_clock() -> float:
    return time.time()

m.op(len, name="size", effect=EffectClass.pureStructural)   # the longhand
```

`pure`, `reads`, `writes` and `io` are the four. There is no `nondet`: a
generator IS nondeterministic, and the registration decides that from the
function itself rather than asking the author to restate it.

The five classes form one ordered lattice:

| class | strongest behavior it admits |
|---|---|
| `pureStructural` | depends only on structural arguments |
| `readOnlyLookup` | reads stable state without changing it |
| `nondeterministicReadOnly` | reads without writing and may answer several ways |
| `writesState` | changes engine or host state |
| `oracleIO` | observes an external oracle, including clocks, randomness, or I/O |

Registration without effect metadata refuses before the engine changes and names
all five choices. A generator, or an operation with a generator inverse, is
LIFTED to `nondeterministicReadOnly` when it declared a read-only class below
it: the lift only raises the rank, so it widens the answer-count claim and
never weakens an effect claim. It happens before the catalog is built, so the
reflected row carries the lifted class; a generator left reflected as
`pureStructural` would be cacheable, which is a wrong answer rather than a
wordier one. The operation's reflection always carries one canonical
`(effect name class)` row in `&metta`.

Composition takes the strongest member. In Python,
`EffectClass.compose(step.effect for step in plan)` computes that join from
reflected `Operation.effect` values; `join` is associative, commutative and
idempotent, and an empty plan is `pureStructural`. The engine uses the same law
for an operation plan. A compiled `@define` clause joins the classes of every
operation it calls, and stacked clauses join again, so the definition's
reflected effect follows the strongest reachable call rather than a hand-written
boolean.

Only `pureStructural` projects to the cache-safe allow-list. Tabling and
memoization refuse every stronger class unless the caller explicitly chooses the
existing unchecked policy:

```prolog
:- multifile seam:pure_operation/1.

seam:pure_operation(my_lookup).
```

Anything that may hand back a CACHED answer later reads this. Declare an
operation here when it only inspects its arguments, and leave it out when it
reads or writes a space, reads or writes state, prints, draws at random, reads
the clock, or crosses to a host.

It is an **allow-list**, and the asymmetry is the whole argument. A missing entry
in a deny-list is a silent wrong answer; a missing entry here is a loud refusal
that someone adds a line for. Before this list existed, tabling treated an
unrecognised goal as inert, and that cached a random draw so two calls answered
from one draw, printed a `println!` once for two calls, performed a space write
once for two calls, and kept answering from the cache after the Python data
behind an operation had changed.

Your library's operations are yours to declare. The engine ships its own core
list and knows nothing about yours, so an operation nobody declares is refused
rather than assumed, which is the safe direction to be wrong in.

The former volatility spellings remain accepted only as compatibility input, and
canonicalize conservatively: `immutable` to `pureStructural`, `stable` to
`readOnlyLookup`, and `volatile` to `oracleIO`. `Operation.pure` remains as the
boolean projection of `effect is EffectClass.pureStructural`; it is not a second
classification.

### Two seams only a bridge needs

A BRIDGE is a tier that compiles a MeTTa operation into a call on a dispatcher
of its own. `op` and `register_prolog` are not this; the Python bridge
underneath `op` is.

**Say who your dispatch goal really is.**

```prolog
:- multifile seam:effect_operation_name/3.

%   seam:effect_operation_name(Goal, Name, Arity)
seam:effect_operation_name(my_dispatch(Name, Args, _), Name, Arity) :-
    length(Args, Arity).
```

The purity refusal above reads the goal it is refusing, and for a bridge that
goal is yours and not the program's. Without this the Python bridge's refusal
said `metta_py_dispatch_det/3` and advised declaring THAT pure: not a name any
author wrote, and not one a declaration could have matched. Answer here and the
message names what the program wrote and what `seam:pure_operation/1` will
match.

**Say that a goal you make the engine emit must not be taken over.** A goal your
dispatcher makes the engine compile into a function body is written in the
space's own module, so an equation in that space for the same name at the same
arity would capture it: the program's own call would run where your goal should,
silently and with a wrong answer rather than an error.

```prolog
:- multifile seam:engine_emitted/1.

%   seam:engine_emitted(Name/Arity)      the PROLOG arity, one more than MeTTa's
seam:engine_emitted(my_dispatch/3).
```

Naming it binds it into every space's module by import, which SWI then refuses
to let an equation overwrite, and the engine turns that refusal into a MeTTa one
that says the name is the engine's rather than calling it a Prolog builtin. The
addition is safe on a running engine: it reaches spaces that already exist, so
it is checked against them, and a space that already defines a function of that
name is REFUSED with both parties named rather than settled by which import
happened first. Rename one of the two; there is no ordering that makes both
work.

### The seams this page has not named yet

`engine/ext_points.pl` declares more than the atom hooks, and several of the
rest are exactly what a performance library wants.

**`seam:dispatch_call/4`** is consulted at every compiled call site, which makes
it the seam for installing your OWN caching strategy rather than using
`lib_memo`'s. `lib/lib_memo/lib_memo.pl` is one implementation of it, not the
only possible one. A handler reads `current_metta_module/1` to learn which
module the call site is in, because a named space compiles its equations into a
module of its own and a function name alone does not identify a function.

**`seam:function_changed/1` and `seam:function_removed/1`** are how any library
keeps derived state coherent when equations change. The specializer, the memo
cache, tabling and the dual predicates all hang off them. The pair is dynamic
and costs per compiled equation while a handler exists, which is why a library
should install its handler when its feature is first used rather than when its
file loads: a resident handler clause measured four inferences on every compiled
equation.

**`seam:function_clauses_changed/1`** is the compiled-clause half of the same
story. `function_changed` fires when a definition ARRIVES, and under deferred
translation that can be before any clause exists: a source's equations are
registered on arrival and compiled when something first reaches them. A consumer
that needs the predicate itself, as the tracer does when it wraps compiled
clauses, hangs off this event instead, which fires once per compiled equation,
arrival-translated and materialised alike.

Four narrower events let an analysis avoid repeating work on every equation.
`seam:function_call_graph_changed/2` carries a function and its execution module
only when that function's retained source-call edges changed.
`seam:source_program_compiled/0` marks the end of a definition-bearing source
unit, so a graph consumer can batch one whole-source decision instead of running
it for each form. `seam:cache_policy_changed/1` reports an added or removed
`(cache <name> force|refuse)` catalog declaration or a change to an explicit
`(tabled <space> <name> <arity>)` declaration.

`seam:deferred_translation_settled/0` is the point after a deferred function's
clauses stand and no predicate is still half-built. The call-graph event above
fires from INSIDE the function's own compilation guard, which is early enough
to hear the news and too early to act on it: a handler that recompiles would
recompile the predicate its caller is in the middle of building. This event
fires once per materialisation, and it is where a decision that must reach the
function's FIRST call belongs, because deferred translation means that call is
the next thing to happen. `lib_memo` decides automatic caching here; deciding
it at the source's flush instead decided after the recursion it was about had
already run.

**`seam:automatic_cache_explanation/3`** is the declaration seam behind the cache
item in `(explain ...)`: the function name is followed by the selected choice and
its structured reason. `lib_memo` supplies `automatic`, `forced`, `refused`,
`declined`, and `manual` decisions. A different caching extension may publish its
own decision without moving that state into the engine.

**`seam:grounded_extra_type/2`, `seam:grounded_type_names/2` and
`seam:grounded_class_type/2`** are how a host value gets a TYPE. The class walk
itself is the host bridge's clause of `seam:grounded_class_type/2`, because
enumerating a value's classes is host code by nature: the shipped Python bridge
answers every class on the object's MRO except `object`, so a `torch.Linear` is
a `Linear` and a `Module`, and an engine with no host loaded has no clause
there, which is the right answer for a configuration in which no host value can
exist. `seam:grounded_extra_type/2` adds names beyond the walk, which is how a
protocol an object satisfies can name a type and a declared
`(-> Tensor Tensor Tensor)` can hold for values the host made.
`seam:grounded_type_names/2` replaces the walk entirely, for a bridge that knows
how to read its own objects and answers every name at once.

**`seam:extension_builtin/2`, `seam:host_import/1`, `seam:form_rewriter/1` and
`seam:host_object/1`** are how a whole HOST plugs in, and the shipped Python
bridge is their one worked example. `seam:host_object/1` answers whether a value
is a live object of the bridge at all, the question in front of every
grounded-type lookup, so an engine with no host loaded answers no at one failed
lookup and never initializes anything. `seam:extension_builtin/2` declares the
bridge's own operations and their effect class (`py-call`, `py-atom` and their
family there, all `oracleIO` because each one crosses into a Python runtime the
engine cannot bound); the engine's registry directive registers whatever was
declared, so no list inside the engine names a host. It is the same seam a
native backend uses, for the same reason. `seam:host_import/1` lets a bridge
CLAIM an import whose source is its own kind of file and perform the whole job
itself, lifecycle included, through the same published `import_when/4` the
engine uses; with no host loaded, or none claiming, every import is a MeTTa
import. `seam:form_rewriter/1` is a registration slot: a rewriter installed there
runs over every loaded form, and a bridge installs one only while the feature
needs it, the way the Python bridge registers its import-as alias rewrite when
the first alias lands, so a program that never uses the feature pays one failed
lookup per form and nothing more.

A clause of either that THROWS is your bug and is not caught. Reading a throw as
"no bridge answered" once ran the class walk instead, and one broken protocol
predicate silently destroyed typing for every host object in the process, with
`get-type` answering the envelope's own class for all of them. The fallback
exists for a bridge that is ABSENT, which is ordinary configuration, not for one
that is broken.

**`seam:host_transport_failure/1` and `seam:host_error_reason/2`** are the two
questions the engine asks about a host's OWN exceptions. The first says whether
an error term is your transport dying, the backend absent rather than wrong, so
no declared keep-or-empty mode owns it and retrying is the caller's decision; the
Python bridge's one clause matches its janus `python_error('TransportFailure', _)`
wrapping. The second renders your exception as the reason inside a MeTTa
`(Error <culprit> <reason>)` answer, for shapes only your bridge can read, a live
exception object being the case that motivates it; an error no host claims
renders through SWI's message system instead. Declare clauses for your own
exception shapes only. Both are declared by the ENGINE, so a process with no host
loaded answers no at one failed lookup.

**Every seam in this section is an EVENT seam.** A cut in one silently disables
every handler loaded after it. See *The one way to get a handler wrong* above,
and write `( Condition -> Action ; true )`.

### The `host_service` surface

The other half of the host contract is the engine predicates a host BINDING's
transport may call back, measured from the shipped shim and declared in
`engine/ext_points.pl` as `host_service` so the static walk can keep the list
honest. Today's list: `catch_recover/2`, `match_foreign/5`, `metta_add_atoms/2`,
`metta_host_adopt_function/4`, `metta_host_clear_defined/1`,
`metta_host_clear_space/1`, `metta_host_digest/2`,
`metta_host_drop_function/2`, `metta_host_explain_match/3`,
`metta_host_fast_header/1`, `metta_host_forget_function/1`,
`metta_host_inference_budget/3`, `metta_host_load_fast/2`,
`metta_host_load_file/3`, `metta_host_open_function/3`,
`metta_host_operation_error/5`, `metta_host_read_forms/2`,
`metta_host_register_reader_token/2`, `metta_host_remove_reported/3`,
`metta_host_run_source/4`, `metta_host_run_source_status/3`,
`metta_host_save_fast/3`, `metta_host_set_silent/1`, `metta_host_stored/2`,
`metta_host_substitute/3`, `metta_host_unregister_reader_token/1`,
`metta_reducible_head/2`, `metta_source_declarations/2`, `metta_space_names/1`,
`metta_string_declarations/2`, `metta_substitute_self/3`,
`metta_trace_source/4`, `metta_annotations/2`, `metta_contract_fact/1`,
`metta_error_answer/3`, `metta_handles_coherent/1`, `metta_on_error_mode/3`,
`metta_source_reset/1`, `metta_transaction/1`, `metta_transport_failure/1`,
`sread_with_names/3`, `translate_expr/3`, `unregister_metta_extension/1` and
`with_metta_module/2`. Shrinking this list is the shim-thinning work's
scoreboard; growing it is a deliberate publication, not a drive-by.
`metta_host_set_silent/1` is the row whose ADDITION shrank the floor: it sets
the print-suppression flag `engine/filereader.pl` decides from `argv` at load
time, which an embedded host therefore cannot reach, and the Python and C seats
had each written the same retract-then-assert privately before it existed.

Registering an operation is four of those calls, the engine's own protocol
rather than bookkeeping a binding restates.

1. `metta_host_open_function(Name, Tier, PredArity)` proves the name free
   BEFORE you assert anything. A taken name refuses here, naming its owner.
2. You assert your dispatch clause into the base tier's module.
3. `metta_host_adopt_function(Name, Tier, Kind, PredArity)` makes the asserted
   clause a claimed function and recompiles the definitions that had been
   treating the name as data.
4. On the way out, `metta_host_drop_function/2` retires one arity, while
   `metta_host_forget_function/1` releases a name nothing defines any more and
   recompiles its mentions back to data.

Reading and removing stored atoms is two more.
`metta_host_stored(Space, Pattern)` enumerates stored atoms unifying a pattern,
index-directed on a native space and provider-enumerated on a foreign one, and
`metta_host_remove_reported(Space, Term, Verdict)` removes with the
whether-anything-went verdict a host API wants. And
`metta_host_explain_match(Space, Patterns, Report)` answers what the seam
already decided for a query without running it, as one term report holding
per-pattern classes with structured origins, the plan's claimed and rest
indexes, and preflighted refusals, so a transport renders prose instead of
re-deriving routing precedence.

**Bounding a lazy cursor, and where the bound has to go.** If your binding offers
a cursor with an inference budget, call
`metta_host_inference_budget(Goal, Inferences, Bounded)` and hand `Bounded` to
`engine_create/3`. Do not write the bound yourself, and in particular do not put
it around `engine_next/2` on your own side.

An SWI engine has its OWN inference counter and the thread that created it cannot
see that counter. So `statistics/2` either side of a pull measures your pull loop
and nothing the engine did: 1,000 pulls of a goal costing about 402 inferences
each move the calling thread's counter by 2,003, half a percent of the work. A
meter built that way reports a total that tracks the budget by construction,
which looks like a working meter in a sweep and stops nothing. Two of this
repository's bindings shipped that meter independently before the service
existed.

Placing the bound inside the goal is necessary and not sufficient, which is the
second half of why this is published rather than described.
`call_with_inference_limit/3` bounds inferences for each SOLUTION of its goal, so
it is re-armed at every answer and a generator answering cheaply forever never
reaches it. The service keeps that limiter, because it is the only bound that
stops a resume which never yields an answer at all, and adds the engine's own
counter read against a base taken when the goal starts, which is the cumulative
budget the per-solution contract cannot express.

A non-positive `Inferences` means no bound and installs no wrapper, so an
unbounded cursor pays nothing; a bounded one costs two engine inferences per
answer. `Goal` is qualified with your module, so it may name your binding's own
predicates. The service raises the engine's reserved
`metta_control_signal(inference_limit, N)` envelope, the same one a program's own
`(pragma! max-inferences N)` raises, so classify that shape rather than inventing
a second one.

### Tabling is the deep-control proof

`lib/lib_tabling/lib_tabling.pl` changes predicate execution, owns state below
the evaluator, observes space writes, invalidates that state when equations
change, and publishes control-plane rows. It does all of that as a library
through the declared surfaces above. No tabling case is built into the
evaluator.

The ownership half uses the same mechanism as `lib_memo`. A declaration asks
which module owns the predicate visible from the current call-site module,
following SWI's `imported_from/1` when the function is inherited. It then
installs one ground-headed `seam:dispatch_call/4` handler for the enabled name.
The handler repeats that late-bound ownership question and returns the exact
qualified predicate that was tabled, so the declaration and execution paths
cannot drift into two module-name conventions.

The table itself is `shared`. A Python `Answers` view holds a lazy cursor whose
query runs in its own SWI engine, while a source run and a later statistics query
may run in another. SWI's `table/1` `shared` option gives those engines one
answer trie; `incremental` remains beside it for tables that read native spaces.
A first live Python call consequently leaves one table, one answer and one
completed call for the next door to observe, and a repeated call reuses that
completed table.

The remaining integration is ordinary declared traffic. `function_changed/1` and
`function_removed/1` clear derived tables. `atom_removed/2` retires the indexed
dispatch handler when its `(tabled ...)` row leaves `&metta`, including
space-pool cleanup. The `(tabled space name arity)` and `(defined space name)`
heads have catalog kinds, so malformed rows are rejected by the generic catalog
validator. Every actual reflection add or remove must return the language's exact
unit answer; failure is a named tabling error and a new table is rolled back with
it.

`tests/prolog/layering.pl` walks the exact `lib/lib_tabling/lib_tabling.pl`
source file as a contract node. Its four `reaches(lib_tabling, ...)` rows name
the declared seam, context and effect services, space and storage services,
ordinary atom doors, and the published writer. Adding a reach to another engine
subsystem fails `layering.plt`. This is the executable boundary behind the
extension claim: a third party can reproduce tabling-grade control with the
published seams and SWI's public tabling API, without changing an engine file.

## 8. Custom matchers: how things match

Matching has two tiers, and they answer to different authorities.

**Inside unification, the value's own matcher is the authority.** A grounded
value that defines matching logic (section 6's `seam:matchable_value/1` and
`seam:custom_match/2`, or any Python object whose class defines `match_`) is
consulted when `(unify ...)` meets it, and its binding sets are final: nothing
re-derives or re-checks them, exactly as Hyperon's CustomMatch behaves. That is
the point. An embedding matcher's "close enough" has no structural check even in
principle, and a space is exactly such a value whose matcher is query. The
bindings it yields are arbitrary by design, okBind semantics;
`extensions/python/examples/integration/cmetta_space.py`'s `CMettaMatch` is a
worked instance whose bindings come from a different MeTTa runtime entirely.

**Above unification, scored matching is a library convention.** A scoring
matcher is a MeTTa function answering `(score value)` pairs, generating
best-first when the candidate is unbound; `lib/lib_soft/lib_soft.metta` and
`lib/lib_measure/lib_measure.metta` are that story, in user space on the general
seam, deliberately not in the engine or the Python package. Matchers compose
through ordinary MeTTa evaluation and nondeterminism, never through new syntax,
because fixing one notion of closeness in the core would exclude every other.

## 9. The contract: declarations in `&metta`, the extension story itself

Everything above is a MECHANISM. What ties them into one seam is the contract:
declarations are ordinary atoms in the `&metta` space, and the engine routes
queries by them. A backend attaches by declaring what it can do, not by the
engine growing a case for it.

Each declaration is one atom, written through a sugar that validates the
vocabulary or added like any atom. Queries route by the most specific matching
shape, exactly as evaluation dispatches a call against equation heads; two
overlapping entries that disagree are a loud conflict naming both and the query
they disagree on.

| declaration | what it decides | sugar |
|---|---|---|
| `(op <name> <arity> <kind>)` | how a registered operation compiles; `op` asserts these and compiles FROM them | `op` |
| `(effect <name> pureStructural\|readOnlyLookup\|nondeterministicReadOnly\|writesState\|oracleIO)` | the operation's required effect rank; a composition and a compiled definition take the strongest member | `op(effect=...)` |
| `(cache <name> unchecked)` | the caller accepts stale answers for an impure body | add the atom |
| `(cache <name> force\|refuse)` | override automatic memo profitability for one function; purity remains a hard refusal | add or remove the atom |
| `(handles <ctx> <pattern> Exact\|Partial\|Sound\|Refuse [det])` | how faithful a context's own filtering is, per shape; `Exact` licenses count pushdown, `Refuse` makes the query a loud error; `(in $x)` marks a position that must arrive bound | `space.handles` |
| `(source <ctx> linear\|repeated\|peek)` | consumption discipline; a linear source's second touch is loud where the floor answered silently empty | `space.source` |
| `(on-error <ctx> <shape> keep\|empty\|abort)` | what a provider failure becomes: an `(Error ...)` answer, declared silence, or the abort floor | `space.on_error` |
| `(writes <ctx> transactional\|atomic-single\|best-effort)` | whether `(transaction ...)` delegates, refuses, or proceeds by declared acceptance | `space.atomicity` |
| `(context <ctx> closed-world\|open-world)` | whether negation may consult the context at all | `space.context` |
| `(algebra <name> <combine> <extend> <zero> <one> (laws ...) (carrier ...) (requires ...))` | the operations and checked laws that govern tagged derivations; a finite carrier makes public law claims declaration-time checkable | `space.algebra` |
| `(annotations <ctx> <algebra> [(capabilities ...)])` | the declared algebra answer annotations live in; `ranked` is what `(top k ...)` consumes, `prov` carries source terms, and required fragment capabilities are checked before the row lands | `space.annotations` |
| `(emits <ctx> depth\|fair\|best-first)` | the context's own emission order; best-first lets `top` push its bound | `space.emits` |
| `(merge <pattern> depth\|fair\|best-first)` | how the engine merges one shape's answers ACROSS contexts | `space.merge` |
| `(on <ctx> <pattern> <op>)` | a bridge: when a matching atom lands, run `(insert ...)`, `(retract ...)` or `(revise ...)` under the match's bindings | `space.reaction` |
| `(admits <pool> <Type>)`, `(capacity <pool> <n>)` | a typed, bounded pool; a space of spaces is the thread-pool reading | `pool.admits`, `pool.capacity` |
| `(inherits <child> <parent>)` | the child's execution base and child-first read chain; writes remain local | `(new-space <child> (inherits <parent>))`, `new_space(inherits=...)` |
| `(restricted <space>)`, `(grants <space> <capability>)` | a curated execution base; file, process, and network vocabulary is creation-granted | `(new-space <space> (restricted (grants ...)))`, `new_space(restricted=True, grants=...)` |
| `(parametric <expression>)` | the exact ground expression registered as a native space identifier | `(new-space (<family> <parameter> ...))` |

Ask the seam itself what it will do: `!(explain (match &s <pattern> $x))` answers
the route as atoms, which entry matched, at what fidelity, whether a bound would
push, and every declaration above. What explain says is what execution does; that
law has its own tests.

Undeclared is always today's behaviour: the contract is monotone, and a provider
written before any of this keeps working unchanged.

### The catalog describes its own kinds, and yours

Every row in the table above is an instance of a KIND, and the kinds are
themselves rows in `&metta`:

```
(vocabulary fidelity Exact Partial Sound Refuse)   ; a value set
(kind handles symbol pattern (one-of fidelity)     ; a declaration's shape
      (optional (one-of determinism)))
(claim semiring ranked ordered)                    ; a per-value fact
(algebra prob + * 0 1 (laws ...) (carrier) (requires))
(routed-by-shape handles)                          ; entries route by shape
```

One generic checker validates every `&metta` write against the standing kind
rows, and a violation is a hard error naming the atom, the argument position and
the argspec it missed, where it used to sit silently and never match. A head with
no kind row passes untouched, so your own kind starts as plain data and becomes
schema-checked the moment you declare its rows. Argspecs are `symbol`,
`integer`, `pattern`, `term`, `(one-of <vocabulary>)`, trailing
`(optional <spec>)` and final `(rest <spec>)`. Removing a row withdraws it:
remove-then-redeclare is how a program deliberately widens a shipped kind, and
the presets return on the next engine boot only where their subject has no row
standing.

`(routed-by-shape <head> [context|global])` gives your kind the SAME router the
shipped ones use: entries are patterns, queries route by the most specific
matching entry with `(in $x)` adornments and loud coherence conflicts, all
inherited, none reimplemented. Read the routed view back with the published
service `metta_shape_route/5`.

To make the engine ACT on your kind, ship exploitation rules riding the published
seams. The routing seam is `seam:route_cap/4`: consulted where the declared
fidelity or the provider's method proposes a route class, and every loaded
advisor may only DEMOTE, the most conservative voice winning (`refuse` below
`inexact` below `exact`, refuse loud and naming your Why). A freshness kind is
the worked instance, an ordinary extension file:

```prolog
:- metta_extension(freshness, [requires(1-1)]).

:- multifile seam:route_cap/4.
seam:route_cap(Space, Pattern, inexact, freshness(cached)) :-
    metta_shape_route(freshness, Space, Pattern, _, [cached]).
seam:route_cap(Space, Pattern, refuse, freshness(stale)) :-
    metta_shape_route(freshness, Space, Pattern, _, [stale]).
```

With `(vocabulary freshness-level live cached stale)`,
`(kind freshness symbol pattern (one-of freshness-level))` and
`(routed-by-shape freshness)` declared,
`(freshness &rows (edge $a $b) cached)` demotes the engine's bound pushdown to
re-unification for that shape, and `stale` refuses the route outright; the whole
path is pinned by
`test_a_third_party_declaration_kind_changes_routing_through_published_seams`. A
freshness vocabulary gating routes is a production discipline rather than an
invention here: Oracle's `QUERY_REWRITE_INTEGRITY` decides whether a stale
materialized view may keep serving rewrites, and its `RELY` constraint state is a
per-declaration trust claim the optimizer acts on.

The contract language is MeTTa on purpose, and it reaches the boundary itself: a
backend's whole conversion can be ONE declaration relating the atom shape to the
backend's shape, `(bridge (edge $a $b) (row edges (a $a) (b $b)))`, used in both
directions the way any MeTTa pattern is. `extensions/python/metta/tables.py`
derives a complete SQL provider from such atoms: WHERE from bound positions, the
equalities repeated variables demand, INSERT from grounding, and honest pushdown
claims, with the conformance kit checking the derived claims the way the lens
laws check a bidirectional transformation, the round-trip law now a named check.
A provider takes a SCHEMA, any number of declarations, shapes answering together
the way overlapping equations do; `tables.declare` writes them into `&metta`
ctx-scoped, MeTTa source can add the same atoms itself, and
`TableBridge.from_context` reads them back, so a program carries its schema as
knowledge and the attach is one line. Writing the consistency relation and
deriving both directions is the bidirectional-transformations literature's third
approach, and MeTTa's pattern pairs are already the right notation for it.

One rule governs every name an extension adds, on either side of the seam: one
concept has one name, and its two spellings map mechanically, hyphen to
underscore, ceremony dropped, never a synonym. `add-atom` is `add`, `new-space`
is `new_space`, and a Python method that stores `(on ...)` atoms is named after
`on`, not after a metaphor. If the Python name cannot be derived from the MeTTa
name by that rule, it is the wrong name; the guide's Concepts page holds the full
table.

## Choosing

| you want to | use |
|---|---|
| add syntax or a control form | a translator rule |
| add a primitive that is called often | a Prolog predicate |
| wrap something already written in C or Rust | a C foreign predicate |
| write logic in Python and run it at MeTTa speed | `@m.define` |
| reach a Python library | a Python operation, `transport="raw"` if the argument is big |
| ship a fast library that installs with pip | `register_prolog` from Python |
| add a domain-specific literal | a reader token class |
| put atoms somewhere else | a space provider |
| react when a space changes | an atom hook |
| cache calls your own way | `seam:dispatch_call/4` |
| keep derived state coherent | `seam:function_changed/1` |
| change what counts as a match | a matcher, by convention |
| ship a whole seat, with its own build and scripts | `extensions/README.md` |
| reach the engine from a language it has never been used from | the wire codec, [CODEC.md](CODEC.md) |

Three of those are **declared seams** in `engine/ext_points.pl`, and a change to
one is a breaking change: the foreign-space hooks, the atom hooks, and the memo
and function-change hooks. The rest are mechanisms. Custom matchers in
particular are a **convention** rather than a hook, deliberately: they compose
through ordinary evaluation and nondeterminism, so there is nothing to declare.

If none of these fits, that is worth reporting as a gap rather than working
around: the point of having nine is that forking should never be the answer.
