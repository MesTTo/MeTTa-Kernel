# Where the engine's time and memory actually go (measured 2026-08-23)

## The instrument problem, settled at the VM source

`statistics/2` inferences **cannot see a clause scan**. Failing a clause head sends
the VM to `shallow_backtrack`, whose `CHP_CLAUSE` branch asks `nextClause/4` for the
next candidate and resumes at `NEXT_INSTRUCTION`; the counter is only raised on the
call and depart path
[source: SWI-Prolog `src/pl-vmi.c`, `VMH(shallow_backtrack)` against
`VMH(depart_or_retry_continue)`; V10.1.13, upstream commit
`fc7ef84b949378b729052c3ade79c90ce5416abb`].

Measured: a lookup that walks 20 clauses and one that walks 20,000 both report
**three** inferences. `prolog_trace_interception/4` sees it (one call, 19,999 redos);
plunit meta-calls its test bodies and cannot trace them, so timed tests are the only
option where this matters.

Every conclusion below is therefore CPU time and RSS, not inferences.

## The atom-add path

`examples/performance/scale.metta` adds 1,000,000 atoms. Per atom the engine does
`assertz(Module:Term, Ref)` (reference-returning) plus
`assertz(source_load_assertion(LoadId, Ref))`. Ablating both:

| variant                              | time   | RSS    |
|--------------------------------------|--------|--------|
| as shipped                           | 2.00 s | 640 MB |
| without the log fact                 | 1.60 s | 411 MB |
| without the log fact and the reference | 1.30 s | 412 MB |

So the bookkeeping is **0.70 s and 229 MB per million atoms**: 35% of the time and
36% of the resident set. Isolated at 1M asserts: plain `assertz/1` 0.24 s / 164 MB;
`assertz/2` + log fact 1.01 s / 392 MB.

The refs are NOT only a rollback log. `withdraw_source_load/3` resolves each one back
to its atom and routes it through `metta_remove_atom/3`, which cascades into
specializations, memo answers and live views. They are the file-ownership record for
dependency-aware reload.

## Every pure-Prolog alternative is worse on time

Per 1,000,000 references, against the shipped 0.90-1.01 s:

| scheme | time | note |
|---|---|---|
| `assertz/2` + log fact (shipped) | 0.90 s | 392 MB |
| `recorda/3` | 1.36 s | 342 MB |
| chunked buffer, `nb_getval`+`nb_setarg`, 64 per clause | 1.45 s | 15,625 clauses |
| SWI `transaction/1` | 0.40-0.71 s | 185 MB, but rollback only, not ownership |
| C array behind a foreign call, one call per atom | 0.87 s | 260 MB |

The shipped design is the best pure-Prolog choice for TIME. Its cost is memory.
A per-atom foreign call does not pay: the boundary costs about what the clause did.

`'$record_clause'/3,4` gives a clause a file owner for free (the owner lives in the
clause header), but it makes the predicate STATIC: `assertz`, `retract` and `erase`
all raise `permission_error(modify, static_procedure, _)` afterwards, and re-recording
under a second owner replaces the first owner's clauses. Unusable for space storage.

## What that leaves

The win needs the storage layer itself to be C, entered once per batch rather than
once per atom. CeTTa already is that: hash-consed atoms in arenas, a discrimination
trie after Vampire's SubstitutionTree, and a head-symbol equation index after its
LiteralIndex (`CeTTa/src/space.h`), instead of one SWI clause per atom with SWI's
single-argument JIT indexing and a parallel ownership registry on top.

## Dispatch analysis, measured on the same tree

Compiling one call site of a function with C equations was Theta(C):
the specializer walked every equation (`copy_term` + `specializable_vars` each) and
`dispatch_head_covers/4` walked them again under `subsumes_term/2`.

| C | before | after both changes |
|---|---|---|
| 200 | 324 us | 20 us |
| 800 | 1,325 us | 33 us |
| 3,200 | 4,939 us | 93 us |
| 12,800 | 21,628 us | 288 us |

The translator half (indexed candidate heads) is clean on the benchmark suite.
The specializer half (a call-side precondition) is SOUND - zero disagreements over
the whole suite - but a net LOSS on real programs, because it walks the call's
argument term while the original tests only the values aligned with head variables.
A long data argument makes it Theta(n) where the original is O(1). Dropped.

Shipped functions carry 1-4 equations, 69 at the most, so this axis is real only at
scale; it is filed rather than sold as a headline.

## The matcher is NOT defective (this retracts an earlier claim in this file)

I first reported that a `match` whose discriminating symbol sits deeper than
SWI's index reach scans the whole space, Theta(N). That was wrong. The number I
measured was the ONE-OFF index build plus the parse-and-compile cost of the
harness, not the query. Measured properly, calling the engine's `match/4`
directly in a loop:

| workload | result |
|---|---|
| ground key, nesting depth 2, 4 and 6 | flat 1.0-1.8 us, 8,000 to 128,000 atoms |
| deep pattern, VARIABLE leaf, rare ground spine | flat, 5.2 us for 3 answers of 320,000 |
| deep pattern, variable leaf, common spine | output-proportional, ~0.5 us an answer |
| add one atom then query, interleaved | flat 2.9 us, 20,000 to 320,000 atoms |
| remove one atom then query, interleaved | flat 1.7-2.0 us over the same range |

So SWI meets the bar the indexing literature sets, including the maintenance
question Nieuwenhuis, Hillenbrand, Riazanov and Voronkov 2001 is about:
insertion and deletion are incremental, not a rebuild. SWI also builds the deep
index lazily and goes far deeper than I first saw: after one query the chain
reaches eight levels, `2/2/1/2/1/2/1:2`.

What DOES cost is the first query of each new shape, because that builds the
index. At 1,000,000 atoms in the `scale.metta` shape:

| query | first | second | answers |
|---|---|---|---|
| `(r $x $y)` | 203.6 ms | 147.7 ms | 1,000,000 |
| `(r 7 $y)` | 208.6 ms | 0.0 ms | 1 |
| `(r $x 3)` | 114.7 ms | 22.3 ms | 100,000 |
| `(r 42 2)` | 0.0 ms | 0.0 ms | 1 |

About 300 ms of that 1.7 s run is one-off index construction. It pays for
itself after a few queries, so it is lumpy rather than wrong. The literature
name for the lumpiness is database cracking (Idreos, Kersten, Manegold, CIDR
2007) and adaptive merging (Graefe, Kuno, EDBT 2010); the static answer is
workload-driven index selection, which is what Souffle does and what Maude's
`FreePreNet` does for a fixed pattern set.

## Dispatch analysis: measured, then dropped

The translator half alone (indexed candidate heads) is gate-clean and sound,
but it is worth only about 10% of the compile-time dispatch analysis once the
specializer walk is left in place, and NOTHING measurable on real workloads:
loading peanofast, scale, matespace and lib_pln measured 9.91 s and 12.01 s on
the base against 11.02 s and 10.01 s with the change. It also moves the
`basics/identity.metta` twin budget by a layout step. Not landed.

## Interpreter complexity sweep, 2026-08-23

Method, after two false leads earlier in this file: measure the OPERATION rather
than a harness around it, warm it first so no index build is inside the clock,
take min-of-three CPU time, and scale each axis by 4x. Inference counts are
blind to clause scans, to `is_list/1`, and to anything a C builtin walks, so
they cannot be the instrument.

### Two class changes found and landed

`21881ec0` A recursive generator produces its i-th answer at recursion depth i.
The translator left a runtime `Out = V` trailing the recursive call, putting it
out of tail position, and enumerating K answers was quadratic. 903 us at K=400,
12,227 at 1,600 and 192,516 at 6,400 (15.8x per 4x) against 111, 404 and 1,906
(4.7x). merge_branch_returns/3 already existed to undo this; it offered `->`
arms to the merge and walked disjunction arms as ordinary goals, and superpose
compiles to a disjunction.

`2424bc59` `(== $l ())` is how a list is walked to its end, and
comparable_operands/2 asked `is_list/1` of the whole remaining list at every
step. 13,538 us at 3,200 elements and 137,949 at 12,800 (10.2x per 4x) against
5,048 and 26,883. One proper list is all the list branches need and () is one.

### Probed and clean

| axis | result |
|---|---|
| term size, term depth, arity, nested calls, let chains | linear |
| car-atom, cdr-atom, cons-atom, decons-atom | O(1), flat to 6,400 |
| size-atom | O(N), which is what counting costs |
| union, intersection, subtraction, unique, sort-atom | linear |
| match: ground key at depth 2, 4, 6 | flat, 8,000 to 128,000 atoms |
| match: variable leaf under a rare ground spine | flat, 3 answers of 320,000 |
| add or remove interleaved with query | flat, incremental maintenance |
| carrying a large term through a recursion | O(1) a call, one-off in the term |
| nested generators, destructuring recursion | linear in answers and in depth |
| accumulators, list building, error depth, type declarations | linear or flat |

### Found and rejected

`index-atom` classifies with `is_list/1`, so `(index-atom $l 0)` costs O(length)
where it should cost O(index): 10.15 us against a 6,400-element list. The
constant-time shape test that fixes `==` is NOT sound here, and a differential
over 60 view cases caught it: grounded_list_view/2 reads an improper `[a|b]` as
the compound `['[|]', a, b]`, so properness genuinely decides the view and
`(index-atom [a|b] 1)` answers `a` where the shape test answers `[]`. Reverted.

The answer path runs `acyclic_term(OutPattern)` per answer, which is O(size of
the output template): 7 nanoseconds an element an answer, so Theta(answers x
template). Real, but it only bites with a large template, so it is not the
general case.

## The shape question, and an instrument for it (2026-08-23)

`is_list/1` WALKS. Every engine site that asks it to classify a MeTTa value pays
Theta(length) for an answer the first cell already gives, and the inference
counter cannot see any of it. Two of the five class wins in this file were one
instance of that defect each, found by hand. The general form needed an
instrument.

### The instrument

`redefine_system_predicate(user:is_list(_))` replaces `is_list/1` with a
semantics-preserving version that classifies its argument through
`'$skip_list'/3`, one C pass, into proper, empty, partial, improper, var or
nonlist, and records the count against the CALLING CLAUSE, resolved through
`prolog_frame_attribute(Frame, parent, P)` and `clause_property(Ref,
line_count(L))`. Run the whole example corpus under it and every site's traffic
and every shape it has ever seen falls out.

The redefinition intercepts Prolog-level calls only. `PL_is_list` from foreign
code is not covered, which is fine here because only Prolog sites were changed.

### What the corpus said

253 example programs, 3.7 million `is_list/1` calls across 82 sites:

| class | sites | note |
|---|---|---|
| proper | 58 | the walk always ran to the end and answered yes |
| nonlist | 27 | answered no |
| var | 12 | |
| partial | 3 | bridge.pl:243, spaces.pl:5407, specializer.pl:454 |
| improper | 0 | **never, anywhere** |

Traffic is concentrated: `spaces.pl:4909` alone takes 2,250,355 calls and
`spaces.pl:4893` another 796,445, both of them the same
`( X == [] ; \+ is_list(X) )` "is this not an expression" dispatch, and both
seeing proper lists essentially always, so the walk ran to completion only to
FAIL its own guard. `metta.pl:3034` takes 465,366 and `metta.pl:1326` 181,777.

The three partial-list sites are the useful part. `spaces.pl:5407` is
`get_native_atom/3`, which calls `length/2` on the pattern immediately after, so
properness there is load-bearing rather than assumed: an open-tailed pattern
must be rejected and the walk is what rejects it. The probe separates a reader
entitled to assume the invariant from a check that enforces it, which no amount
of reading the code settles.

### The invariant

A MeTTa Expression IS a proper list. LeaTTa's `Atom` carries
`Atom.expr (List Atom)`, so an improper cons is not a term the semantics can
express, and `Builtins.consAtom` refuses a tail that is not an expression;
`tests/regression/instruction_interp.metta` pins native `cons-atom` and its
minimal mirror rejecting `(cons-atom a 1)` alike. PeTTa built `[a|1]` there and
then could not print it, `swrite/2` refusing a term whose printed form would
read back as a different value.

`'cons-atom'/3` and `cons/3` are the only two constructors, so guarding them
with the SHAPE, not with a walk, maintains the invariant at O(1) and leaves
list-building linear. That is what makes the readers' constant-time test sound,
and it retracts this file's earlier rejection of the `index-atom` fix: the
differential that refuted it was measuring PeTTa's own accident, an improper
cons that the semantics says cannot exist.

### The one thing the probe cannot tell you

That an unexercised site is safe. A site the corpus never reaches has no
evidence either way, and there are 82 of them against the 58 that ran.

## The conjunctive matcher, and why the counter was the only usable instrument

A path query over a chain answers once per starting node whatever K is, so the
per-answer cost isolates the JOIN PLANNING from the join. Measured that way,
`match_native/5` was quadratic in the conjunct count:

| K | before | after |
|---|---|---|
| 2 | 14.2 | 14.2 |
| 4 | 45.6 | 36.5 |
| 8 | 121.4 | 81.6 |
| 16 | 327.3 | 174.2 |
| 32 | 975.2 | 369.5 |
| 64 | 3,415.8 | 813.7 |

Inferences an answer. 2.7x to 3.5x per doubling of K before; a flat 2.1x to 2.2x
after, which is the linear cost of having K conjuncts at all.

`relational_conjuncts/1` is a precondition of the WHOLE conjunction, and it was
re-asked at every recursive step on a list that is always a SUBLIST of one
already accepted. It could not fail; it could only walk. Hoisting it is the same
loop-invariant motion `foreign_route/2` already got and `03b7f454` records.

**The measurement nearly went the other way.** This box sat at load average 31
while the work was done, and CPU time over these sizes reported the identical
change as a 2.9x win and as a 33% loss on consecutive interleaved runs of the
same two trees. `relational_conjuncts/1` is a Prolog predicate, so the inference
counter sees every step of the walk exactly and does not move with the load.
The rule this refines: the counter is blind to C builtins, so it cannot see
`is_list/1` or `acyclic_term/1`, and CPU time is blind to nothing but is
unusable under load. Choose per defect, and say which.

### One quadratic left, deliberately

`acyclic_term/1` runs on the whole output template at every level, so a
K-conjunct query with an M-element template walks Theta(K x M) per answer: at
K=64 a template growing with K cost 85 microseconds an answer against 36 for a
fixed two-element one. It stays: `4fa69d03` established the check belongs per
candidate rather than per answer, because bindings live outside the template.
Being a C builtin, no inference counter can see it, which is why it is recorded
here rather than left to be rediscovered.

## Enumeration order follows the predicate table, not the program

`get-atoms` on a native space enumerates through `current_predicate/1`, and SWI
iterates its predicate table in an order that moves when a name is interned.
Adding ONE never-called predicate to `engine/metta.pl`, an inert
`zzz_inert_layout_control/1` and nothing else, reorders what a native inherited
space answers. This is legal: "Result order within one directive's list is
unspecified; result multiplicity is specified" [source: LeaTTa
wiki/Specification.md].

It is worth writing down because it makes any test that depends on that order
one unrelated engine edit away from changing behaviour. One did:
`shaped_atom/1` took the first enumerated atom with arguments, so
`test_a_repeated_variable_selects_equal_positions` ran or skipped by accident.
`fe4415a2` takes the widest instead. Perturb with an inert clause before
believing that a reordering came from your change.

## Prior art read, and what it says PeTTa already has

Vergu, Tolmach and Visser, "Scopes and Frames Improve Meta-Interpreter
Specialization", ECOOP 2019 (doi:10.4230/LIPIcs.ECOOP.2019.4), is the closest
paper to what PeTTa is: a meta-interpreter for a language whose semantics are
specified rather than hand-compiled. Its two contributions measure at one to two
orders of magnitude, and PeTTa already has the shape of both:

- **Scopes and frames** replace a name-keyed environment with frame slots
  resolved statically, so a variable read is an offset rather than a lookup.
  PeTTa compiles MeTTa to Prolog and MeTTa variables BECOME Prolog variables,
  which is the same win taken at compile time. The one name-keyed structure left
  is the `Name-Var` list the reader carries for diagnostics
  (`petta_reader_variable_name/3`), which is printer-side and deliberately off
  the matcher path.
- **Rule cloning** derives a monomorphic rule per call site so the JIT can
  inline it. That is `engine/specializer.pl`, which specializes per call site
  already.

So the paper's lesson for PeTTa is not a missing mechanism; it is the
measurement discipline that separated the two effects, which is what the
per-answer normalization above copies.

## Loading a program was quadratic, and the counter could not see it (2026-08-24)

The strongest signal in this whole file: **inferences a form stay flat while the
TIME a form costs rises with everything already loaded.** The same 500-form batch
cost 119 microseconds a form into an empty program and 666 into a 16,000-form
one, at 1,043 and 1,081 inferences a form. A cost that grows with the program and
is invisible to the counter is a C builtin or a database operation.

### Finding it

Profiling by CALL COUNT said nothing: every count was a linear multiple of the
form count. Profiling by SELF TIME at two program sizes, and diffing, named it
in one step: `support_graph:supports/2` went from 21 ticks to 351 for a 16x
larger program while every other predicate stayed at 4 to 13.

`jiti_list/1` then gave the mechanism outright:

    support_graph:supports/2   32,000 clauses   Index 1   8 buckets   Speedup 4.0

An edge stores two NODE TERMS, and the node terms share only their functor:
`function/2`, `function_view/2`, `translated_form/2`, `compiled_function/2`.
SWI indexes an argument and can index a compound argument DEEPLY, but only where
the clauses agree on the functor there. Four functors, four buckets, and every
duplicate-edge probe scanned a quarter of the graph.

Validated rather than assumed, over 20,000 edges: one functor at argument one
gives a `1:2` deep index and a 0.350 microsecond probe; four functors give
speedup 4.0 and 132.6 microseconds; a hash column gives 0.198.

### Two false leads first

Neither survived measurement, and both are worth recording because both were
plausible. Interleaved assert-and-query does NOT thrash SWI's index: 0.87 to
1.08 microseconds an operation from 1,000 to 64,000 clauses, deep-index shape
and shallow alike, and alternating two query modes changes nothing.
`ensure_fun_registered/1` calling `current_predicate(N/Arity)` with the arity
UNBOUND genuinely is Theta(all predicates), 14.6 microseconds at 1,000 and 410.9
at 64,000 against a flat 0.25 fully bound, but ablating it moved the load
scaling not at all.

### Which endpoint to key

Both, and that had to be measured too. An edge is one of about sixty leaving its
support and one of about one reaching its derived node, so SWI reports a speedup
of 24,575 on the derived key against 528 on the support key. Keying the SUPPORT
side alone at the hot probes cost 365 microseconds a form against 82. Binding
both is better than binding the derived key alone, because the derived key on
its own hashes 32,000 edges with 8,417 collisions.

### The second quadratic, in the same file

A one-member strongly connected component is recursive exactly when it has a
self arc, and that was asked of the whole ARC LIST once per component. N
self-recursive functions, which is what memoization is usually asked for, cost
1,303, 12,112 and 156,346 microseconds at 200, 800 and 3,200. A RING of N
mutually recursive functions was already linear, because it is one component
rather than N, so the SHAPE had to be measured and not just the count.

### Where loading stands

Microseconds a form at 125 forms against 8,000:

| workload | before | after |
|---|---|---|
| distinct functions | 113.6 -> 406.0 | 70.0 -> 75.2 |
| one function, N equations | 70.9 -> 227.6 | 46.6 -> 55.0 |
| call sites to an undefined function | 83.9 -> 619.8 | 66.9 -> 68.7 |
| plain atoms | 9.8 -> 12.3 | 8.1 -> 10.2 |

### What the axes sweep found, and did not

Swept by inference count, which is deterministic under load where wall clock is
not: `case` by branch count and by which branch matches, `let*` chain length,
type lookup, a symbol's declared-type count, subtype chain depth, type
expression depth, arrow length, runtime equation dispatch, failing dispatch,
call arity, space inheritance depth against row count, collapse answer count,
recursion depth. Every one is flat or linear in what it must produce.

Two axes were NOT clean and both are now fixed: compiling a call site was
Theta(the callee's equation count), and loading was quadratic in program size.

**Two harness bugs nearly became findings.** `findall/3` COPIES its template, so
building a conjunctive query's conjuncts with it gave every conjunct fresh
variables and measured a cartesian product rather than a join. And loading the
same equation once per size in a sweep leaves N copies of it, so a two-equation
function answers 2^k times; that read as an engine blowup at depth 32 and was
the harness. Check the answer COUNT before believing a cost.

## Nesting depth is the axis the corpus does not exercise (2026-08-24)

Every earlier sweep varied WIDTH: term size, list length, atom count, equation
count. Depth was the blind spot, and two of the three defects found on it were
quadratic while every width axis was linear.

Swept by inference count at depths 25 to 400: evaluation, printing, `==`,
`add-atom`, `match`, `unify` and `collapse` are all linear in depth. Two were
not.

### Fixed: the translator walked an already-translated head

`1a8af157`. Translating a form nested N deep cost 1,437 inferences at 25,
20,712 at 100 and 322,812 at 400 (14.4x then 15.6x for 4x the depth), against a
parser that is linear on the same text. It is 213, 813 and 3,213 now.

### Found and NOT fixed: deriving a complete type is quadratic in depth

`get-type` of an N-deep value costs 778 inferences at depth 1 and 191,039 at 64,
converging on 4.0x per doubling, for an answer that is one type, N deep.

Ablating the product branch of `get_type_candidate/2` shows it is the whole
quadratic: 49,758 inferences at depth 32 become 2,851, and the curve turns
linear. `tuple_first_in/3` takes each member's FIRST type under a cut, and
`tuple_rest_types/3` then rebuilds every member's COMPLETE type set to
enumerate the combinations other than all-firsts. For a nested member that
rebuild is the whole recursive derivation again, once per level.

**There is no cheap guard, and that is the finding.** The branch produces
nothing unless some member has two or more types, and knowing whether a member
has two or more types is exactly the enumeration being avoided.
`deterministic/1` cannot stand in for it: it reports `false` even for `7`,
whose single candidate is committed by a cut. Merging the two enumerations so
each member is derived once was measured and is far worse, because
`tuple_first_in/3`'s cut is what keeps a member with many types from being
enumerated at all; `d62f3e48` records choosing that split deliberately for the
same reason, and `a51f168f` records that a structurally keyed memo stays
quadratic because hashing or copying a deep term is itself linear.

**It is also not on the hot path, which is why it is filed rather than fixed.**
A typed call that ACCEPTS its argument is already linear in the argument's
depth, 939 inferences at 4 and 3,279 at 64, against an untyped call's 715 and
3,535; `a51f168f` is what made that so. The quadratic is reached by explicit
`get-type` and by the rejection path, which derives the argument's complete type
to name it in a `BadArgType`. A typed call that REJECTS a 64-deep argument costs
755,395 inferences.

Anyone picking this up: the ablation above is the ceiling, and the obligation is
that a guard which wrongly reports "one type" silently DROPS type answers.
