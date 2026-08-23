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
