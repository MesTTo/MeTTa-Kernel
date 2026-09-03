# The kernel and the forms built on it

The translator gives 67 heads a meaning of their own. 59 of them are clauses
of `translate_special_dl/5` in `engine/translator/special_forms.pl`, 64 clauses
over those 59 heads, and the remaining 8 are equations in
`engine/prelude.metta` registered with `add-translator-rule!`. Ask the engine
rather than this paragraph: `metta_special_form_head/1` is
`clause(translate_special_dl(Name,_,_,_,_), _)` and answers the first number,
and the four counts here were each wrong before 2026-09-03 because nothing
read this file. The `kernel-ledger` lane now derives both rosters and every
count from those predicates, then refuses a missing or stale row. A head in the
second group costs the compiler nothing: the rule says what the call expands
to, the expansion goes back through the ordinary translator, and one
definition decides what the form means.

This page is the ledger of which head is which, and why. It is the shrink
target: a form that can move out of the first group and into the second
should, unless moving it costs something measurable.

## The bar a head has to clear

The reference point is the state-free structural core of minimal MeTTa's
instruction set, which LeaTTa's own `tests/mettail/metta.mettail` presents as
fourteen names: `eval`, `evalc`, `context-space`, `chain`, `unify`, `unify%`,
`cons-atom`, `decons-atom`, `collapse-bind`, `superpose-bind`, `function`,
`return`, `metta` and `call-native`. Its `MettaDialect` proves those fourteen
are exactly the primitive instruction enum plus the accepted heads plus
contextual `return`, and eight of them head no rewrite at all: their
configuration, matching, collection, type and host semantics are named
follow-up presentations rather than omissions.

That presentation is a yardstick for what counts as core and nothing more.
The conformance reference this engine gates on is the vendored upstream PeTTa
corpus in `tests/conformance/petta/`, which says what a program ANSWERS; the
two questions are separate and this page asks only the first.

So "core" here has three readings, and the table says which one applies:

- **counterpart**, the head is one of the fourteen or is the same instruction
  under another name;
- **follow-up**, the head belongs to a semantics the presentation names as a
  later presentation, so there is nothing yet to be a counterpart to;
- **divergence**, the head is this engine's own and the presentation has no
  place for it. A divergence is not a defect, but it is a claim, so the table
  says what it buys.

`derived` means the form is expressible as an expansion into other heads. A
derived form that is already a prelude rule says `prelude`; a derived form
still fused into the compiler says why, and every one of those reasons is
measured.

## `translate_special_dl/5`, 59 heads

| head | kind | reason |
|---|---|---|
| `eval` | core, counterpart `eval` | evaluates an atom in the current space, the presented instruction under its own name |
| `evalc` | core, counterpart `evalc` | the same with the space given, which is `context-space` supplied per call |
| `chain` | core, counterpart `chain` | binds a nested result and continues, the presented sequencing instruction |
| `let` | core, counterpart `chain` | one clause with `chain`, `translate_let_dl/4`; `let` is the surface spelling |
| `unify` | core, counterpart `unify` | four-argument unify with a then and an else branch |
| `superpose` | core, counterpart `superpose-bind` | one branch per element, which is what `superpose-bind` selects over |
| `collapse` | core, counterpart `collapse-bind` | the answer set as a value, the collection instruction |
| `call` | core, counterpart `call-native` | compiles one Prolog goal named as a list, the host seam |
| `translatePredicate` | core, counterpart `call-native` | the other direction of the same seam: a MeTTa head backed by a Prolog predicate |
| `reduce` | core, counterpart `metta` | runtime dispatch on a head that is not known at compile time |
| `metta-thread` | core, counterpart `metta` | the nested full evaluator keeps its Atom operand written while it evaluates eager positions to a fixpoint; compiled and runtime doors both preserve `(quote (+ 1 2))` through an Atom result where an ordinary eager call would consume it [tested: `metta_thread:eager_arguments_reach_a_fixpoint_and_atom_arguments_stay_written`] |
| `return` | core, counterpart `return` | only a `function` frame consumes it as the structural `[return, Value]` instruction; outside that compile-time frame it remains an ordinary polymorphic call, so the compiler context is the distinction |
| `match` | core, follow-up | matching semantics is a named follow-up presentation; this is the space query |
| `get-atoms` | core, follow-up | enumerates the selected space; fused so `translate_space_expr_dl/4` preserves a registered expression as a space identity instead of evaluating its callable head |
| `space-atom-count` | core, follow-up | counts atoms the native space itself owns from per-predicate clause metadata, refusing a foreign enumeration that would lie about the cost; the enumerating predecessor cost 4,569.70 inferences per add at 1,000 atoms where a plain add cost 49.01, while this path is independent of atom count [measured 2026-08-20] |
| `space-contains` | core, follow-up | one indexed membership probe about an Atom as written, with a registered expression preserved as the space identity; its set-semantics caller costs 57.01 inferences per add at 2,000 atoms and 57.00 at 10,000 [measured 2026-08-21] |
| `add-atom` | core, follow-up | state is a named follow-up presentation |
| `remove-atom` | core, follow-up | the same |
| `subtract-atom` | core, follow-up | removes one multiset occurrence and answers whether it did; fused with the other space updates so the deep Atom mask keeps an equation-shaped atom written rather than evaluating it before the removal |
| `add-atoms` | core, follow-up | the same. Derived in shape, since it and the four above share `translate_space_update_dl/5`, but the clause carries the DEEP Atom mask and the declaration does not: without the clause the argument's subexpressions evaluate, `(add-atom &self (foo (+ 1 2)))` compiles `+(1,2,V)` and stores `(foo V)`, and 15 corpus files change answers [measured 2026-08-19] |
| `add-reduct` | core, follow-up | the same |
| `add-reducts` | core, follow-up | the same |
| `new-space` | core, follow-up | constructs and registers a space before first use; the one-input form must recognise a ground expression as a parametric identity before that identity exists in the registry, including when its family head is callable [tested: `spaces_parametric:the_surface_constructor_is_idempotent_and_reflected_once`] |
| `super` | core, follow-up | reaches the definition a space's parent holds; space configuration |
| `get-metatype` | core, follow-up | type semantics is a named follow-up presentation |
| `noeval` | core, follow-up | the Atom mask itself: the argument is the answer |
| `quote` | core, follow-up | the same mask, and the one the programs write; an evaluation BARRIER under upstream PeTTa, so `(quote X)` answers X itself unevaluated and no wrapper survives [source: commit 8355e945, the arbiter alignment] |
| `annotation` | core, divergence | reads the answer's own annotation, this engine's weighted-answer channel |
| `explain` | core, divergence | the derivation of an answer, same channel |
| `if` | derived, fused | Hyperon's stdlib defines `if` in minimal MeTTa. Fused because it is written 259 times in the corpus, behind only `test`, `collapse` and `let` [measured 2026-08-19], and because its clauses build the branches through `build_branch/4`, which is what lets `and-then` and `or-else` be prelude rules with no runtime cost |
| `case` | derived, fused | a nested `if` chain, `translate_case/5`; fused for the same reason, and it carries a runtime path for cases that arrive as a value |
| `switch` | derived, fused | the recursive minimal definition exists, but a one-line alias to `case` is wrong when the key answers nothing; written rows compile once and cost 3 inferences per call at 3, 12 and 24 cases, against 78, 258 and 498 when the same rows arrive at runtime [measured 2026-08-19] |
| `let*` | derived, fused | nested `let`s, `letstar_to_rec_let/3`; fused for the same reason, and it carries the same runtime path |
| `progn` | derived, fused | `(let $_ $a $b)` chained. The rule form measured 188 compile-time inferences against 150 and adds one `unify_with_occurs_check/2` goal per call that the fused form does not emit [measured 2026-08-19] |
| `prog1` | derived, fused | `(let $r $a (let $_ $b $r))`. 205 against 146, and two extra goals a call [measured 2026-08-19] |
| `nop` | derived, fused | `progn`'s other half, `(let $_ $a (let $_ $b ()))`, and fused for `progn`'s reason: it takes any arity and a translator rule has a fixed one. Upstream cannot write it in MeTTa at all, says so at `stdlib.metta:608-609` and grounds it in Rust instead |
| `once` | derived, fused | `(take 1 $e)` is the MeTTa spelling, and it answers the same thing over the whole corpus, 206 files with every answer group identical. It compiles to `metta_take/2` where the fused form compiles to Prolog's `once/1`, which costs 2 inferences a CALL: 454,152 against 354,122 over a 50,000-call loop, +28%, and 73 compile-time inferences against 36 [measured 2026-08-19]. The rule ships in `lib/lib_derived/lib_derived.metta` for a program that wants the smaller instruction set anyway |
| `take` | core, divergence | a bounded take over a generator, with a `match` special case that pushes the bound into the space query |
| `top` | core, divergence | the same, ordered |
| `test` | core, divergence | the corpus's own verdict form; needs the answer LIST unpruned, which `collapse` cannot give |
| `test-no-answer` | core, divergence | the same, and the reason is measurable: the `collapse` spelling prunes `Empty`, so `(test-no-answer (quote ()))` would pass where it must fail [tested: translator_test_answers] |
| `cut` | core, divergence | Prolog's cut, reachable from MeTTa |
| `not-provable` | core, divergence | constructive negation; `metta_not_provable_goal/3` plus the runnable-negation bookkeeping the dual builder reads |
| `catch` | core, divergence | turns an exception into an `Error` term without eating a control signal |
| `forall` | core, divergence | compiles to Prolog's `forall/2`, which is what makes it stop a generator |
| `foldall` | core, divergence | a fold over a generator's answers |
| `map-atom` | core, divergence | `maplist/3` over a list, through `collection_closure/3` |
| `filter-atom` | core, divergence | `include/3` over a list, same closure |
| `foldl-atom` | core, divergence | `foldl/4` over a list, same closure |
| `hyperpose` | core, divergence | concurrent branches, `concurrent_and/3`, plus a runtime path for a list that is not syntax |
| `with_mutex` | core, divergence | host concurrency |
| `timeout` | core, divergence | host resource bound |
| `inferences` | core, divergence | inference bound, the engine's own counter |
| `elapsed` | core, divergence | wall clock around an expression |
| `transaction` | core, divergence | all-or-nothing space writes |
| `with-pragma!` | core, divergence | scoped engine settings |
| `with-seed` | core, divergence | a dynamically scoped random generator: the body is compiled in place, and `setup_call_cleanup/3` restores the prior state after success, failure, cut or exception; two scopes with the same seed repeat their draws without moving the outside generator [tested: `test_a_seed_scope_repeats_its_draws_and_leaves_the_outside_alone`] |
| `sealed` | core, divergence | renames the listed variables at COMPILE time, which is the only place the rename can work |
| `\|->` | core, divergence | a lambda, compiled into a generated predicate in the space that wrote it |

## The prelude's derived forms, 8 heads

Each is an equation in `engine/prelude.metta` plus `!(add-translator-rule! NAME)`.
The `Atom` parameters make the arguments arrive as syntax and the `%Undefined%`
result type makes the `(noeval ...)` body translate, since an `Atom` result
would leave the body untranslated and hand noeval itself back.

| head | expands to | measured |
|---|---|---|
| `and-then` | `(if $a $b False)` | one goal FEWER than the clause it replaced, which built the same conditional by hand and kept an empty conjunct. Identical runtime cost over 200,000 calls, 1,203,968 against 1,203,986 inferences, the whole difference being the one-time compile; +43 inferences per compiled site |
| `or-else` | `(if $a True $b)` | the same |
| `trace!` | `(progn (println! $m) $v)` | byte-identical compiled goals |
| `unique` | `(call (superpose (unique-atom (collapse $s))))` | byte-identical |
| `alpha-unique` | `(call (superpose (alpha-unique-atom (collapse $s))))` | byte-identical |
| `union` | `(call (superpose (union-atom (collapse $a) (collapse $b))))` | byte-identical; guarded on both arguments being `(superpose ...)`, with a second equation handing anything else back through `noeval`, which is what the compiler's identity clause did |
| `intersection` | the same with `intersection-atom` | byte-identical |
| `subtraction` | the same with `subtraction-atom` | byte-identical |

Over the 201 corpus examples whose inference count is deterministic, moving
those eight out of the compiler cost **-0.2313%** in total, 252,806,743
inferences against 252,222,109. 199 examples got cheaper, the largest being
`ch20-extending-the-engine/20-02-metta-written-in-metta/05-he_minimalmetta.metta` at -1.606%, because the six stream rewrites
used to run on every compound the translator walked. Two got dearer, both of
them files that write the moved forms: `ch07-control-flow/07-01-if-and-booleans/10-and_then_or_else.metta`
+1.447% and `ch06-many-answers/09-streamops.metta` +0.352%, all of it compile time.
`ch17-concurrency-and-the-loop/03-hyperpose_primes.metta` and `ch20-extending-the-engine/20-04-modules-and-the-catalog/06-git_import.metta` are
excluded because their counts are not deterministic, the first running
branches in threads and the second shelling out to git; `ch22-a-reasoner-you-can-serve/22-03-search/02-tilepuzzle.metta`
is excluded because it runs for minutes. Every corpus answer is unchanged,
group for group, and the conformance lane's per-area agreement is unchanged
[measured 2026-08-19].

## What fusing a head costs, and what moving one costs

This page's shrink target is a performance claim, so here is the shape of the
evidence behind it. A head in the compiler and the same head as a prelude rule
differ in three measurable places, and a proposal to move one has to say which
of them it changes.

**Compile time.** A rule is consulted while the translator walks the program,
so it is paid once per compiled site and it is paid by every source, including
sources that never write the form. `progn` measured 188 compile-time inferences
as a rule against 150 fused, `prog1` 205 against 146, and `once` 73 against 36.
The corpus-wide figure is the one that matters, because it nets that cost
against what the compiler stops doing: moving the prelude's eight heads out
cost **-0.2313%** over the 201 corpus examples whose inference count is
deterministic, 252,806,743 against 252,222,109, and 199 of the 201 got cheaper.

**Run time.** A rule that expands to a form the compiler already handles well
emits the same goals, and six of the eight prelude heads are byte-identical in
their compiled output. A rule that expands to a DIFFERENT form pays whatever
that form costs on every call: `once` compiles to `metta_take/2` as a rule and
to Prolog's `once/1` when fused, which is 2 inferences a call, 454,152 against
354,122 over a 50,000-call loop, **+28%**.

**Expressiveness.** A translator rule has a fixed arity, so a variadic head
cannot be one rule. `progn`, `prog1` and `nop` are variadic, and a rule for any
of them would rewrite some calls and leave the rest to the compiler, which is
two compilations of one form rather than one. That is not a cost to weigh, it
is a blocker to solve first.

So the decision rule is: move a head when its rule emits the same goals, keep
it fused when the rule's expansion is a form that costs more per call, and
treat a variadic head as blocked until the arity problem is answered. `once` is
the case where all three are known, which is why its rule ships in
`lib/lib_derived/lib_derived.metta` rather than being switched on by default: a
program that wants the smaller instruction set imports it and pays the two
inferences a call knowingly.

Two measurement rules apply to any such claim, and both have caught a wrong one
here. Read inferences rather than wall clock, because they are deterministic
while wall clock on this box swings several percent on the same workload. And
exclude the examples whose counts are not deterministic:
`ch17-concurrency-and-the-loop/03-hyperpose_primes.metta` runs branches in
threads and `ch20-extending-the-engine/20-04-modules-and-the-catalog/06-git_import.metta`
shells out to git, so neither can be part of a total that is compared against
another total.

## Numeric ground types

`Number` and `BigInt` are the two numeric types. A float and an integer from
-9223372036854775808 through 9223372036854775807 have type `Number`. An
integer outside that inclusive range has type `BigInt`. Both use signed
decimal source syntax. SWI stores every integer as an unbounded exact value,
so this split changes typing and host crossing, not arithmetic values.

The boundary follows upstream's current `Number::Integer(i64)` carrier and
its tokenizer test naming an integer past that capacity as a case for the
future bigint. Upstream publishes no suffix, subtype relation, or arithmetic
promotion table. [source 2026-08-20:
https://github.com/trueagi-io/hyperon-experimental/blob/3f76dc460da6961f57f69f6c3e550c59c74ada83/hyperon-atom/src/gnd/number.rs]
[source 2026-08-20:
https://github.com/trueagi-io/hyperon-experimental/blob/3f76dc460da6961f57f69f6c3e550c59c74ada83/lib/src/metta/text.rs#L866-L877]

An actual `BigInt` satisfies an existing `Number` parameter. An actual
`Number` does not satisfy a `BigInt` parameter. That directed compatibility
keeps existing numeric declarations valid for every integer result the engine
already computed. It does not claim that `BigInt` is formally a subtype or
species of `Number`; that glossary relation remains unpublished upstream.
[assumed 2026-08-20]

Arithmetic may cross the boundary in either direction according to the exact
result value. Integer equality remains exact across the two types.

### Host-width divergence

Integer arithmetic is deliberately unbounded here. Hyperon's current host
stores an integer in `i64`, implements `+`, `-`, and `*` with the corresponding
checked operation, and turns overflow into `ArithmeticOverflow`. In particular,
its multiplication cannot answer `(* 4611686018427387904 4)` as an integer.
[source: https://github.com/trueagi-io/hyperon-experimental/blob/3f76dc460da6961f57f69f6c3e550c59c74ada83/lib/src/metta/runner/stdlib/arithmetics.rs#L10-L16; commit=080c41a762aa5f7b59a8d52a6817b2fd6cff0de9]

Upstream PeTTa computes `*` with SWI-Prolog's own arithmetic, which is
unbounded, so the exact answer `18446744073709551616` is what the conformance
reference produces and the Hyperon error is a host-width divergence. The
vendored corpus carries a 21-digit integer as upstream's own printed answer,
so this is pinned rather than inferred. The acceptance pin exercises that
same multiplication at the public Python surface.
[source: PeTTa@ae66fa8 src/metta.pl:36, `'*'(A,B,R) :- R is A * B.`]
[source: tests/conformance/petta/expected/patrick_iterate_fib.metta.out, `354224848179261915075`]
[tested: test_integer_arithmetic_is_unbounded_where_hyperon_checks_i64; commit=080c41a762aa5f7b59a8d52a6817b2fd6cff0de9]

The wire keeps one `n` tag because the exact payload recovers the type. A
second tag would duplicate that information and add a mismatched
tag-and-width refusal class. A host that cannot preserve every digit must
refuse the value. Python receives integers as unbounded `int` values through
Janus. The Node bridge carries canonical decimal text and constructs a
JavaScript `BigInt` for every Prolog integer, so neither route passes a wide
value through binary64.

The vendored corpus pins `(get-metatype 1)` as `Grounded` and the arithmetic
signatures as `Number`, and it exercises no wide-integer type case at all, so
the type a wide integer reports is this engine's own decision rather than
something the conformance reference adjudicates. Re-run the boundary,
declared-type compatibility, arithmetic result type and equality cases when
that changes.

## What would move next

`progn`, `prog1`, `nop` and `once` are derived and their rules are written out
in the table above, so moving them is a decision about cost rather than about
expressiveness. Each one's rule emits a goal the fused clause does not, and
the numbers are beside them.

`once` is the one whose rule is COMPLETE, since it has a single arity, so it
ships in `lib/lib_derived/lib_derived.metta` and a program that wants the smaller
instruction set imports it and pays the two inferences a call.
`examples/ch20-extending-the-engine/20-01-translator-rules/08-derived_forms.metta` runs the swap and the swap back.
`progn`, `prog1` and `nop` are variadic and a translator rule has a fixed
arity, so a rule for any of them would rewrite some calls and leave the rest to
the compiler, which is two compilations of one form rather than one. That is
what would have to be solved first.

The five space-update heads are the interesting case. They are one clause
shared five ways, and what keeps them in the compiler is not their semantics
but the depth of the Atom mask: the declaration `(: add-atom (-> Symbol Atom
(->)))` masks the argument at the top level and the general dispatch path
still evaluates inside it, while the special clause passes the whole term
raw. Make the declared mask reach all the way down and those five heads
become five ordinary builtins.
