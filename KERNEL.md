# The kernel and the forms built on it

The translator gives 57 heads a meaning of their own. 49 of them are clauses
of `translate_special_dl/5` in `src/translator.pl`, 54 clauses over those 49
heads, and the remaining 8 are equations in `src/prelude.metta` registered
with `add-translator-rule!`. A head in the second group costs the compiler
nothing: the rule says what the call expands to, the expansion goes back
through the ordinary translator, and one definition decides what the form
means.

This page is the ledger of which head is which, and why. It is the shrink
target: a form that can move out of the first group and into the second
should, unless moving it costs something measurable.

## The bar a head has to clear

The reference point is the state-free structural core of minimal MeTTa's
instruction set, which LeaTTa presents as fourteen names in
`tests/mettail/metta.mettail`: `eval`, `evalc`, `context-space`, `chain`,
`unify`, `unify%`, `cons-atom`, `decons-atom`, `collapse-bind`,
`superpose-bind`, `function`, `return`, `metta` and `call-native`. Its
`MettaDialect` proves those fourteen are exactly the primitive instruction
enum plus the accepted heads plus contextual `return`, and eight of them head
no rewrite at all: their configuration, matching, collection, type and host
semantics are named follow-up presentations rather than omissions.

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

## `translate_special_dl/5`, 49 heads

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
| `match` | core, follow-up | matching semantics is a named follow-up presentation; this is the space query |
| `add-atom` | core, follow-up | state is a named follow-up presentation |
| `remove-atom` | core, follow-up | the same |
| `add-atoms` | core, follow-up | the same. Derived in shape, since it and the four above share `translate_space_update_dl/5`, but the clause carries the DEEP Atom mask and the declaration does not: without the clause the argument's subexpressions evaluate, `(add-atom &self (foo (+ 1 2)))` compiles `+(1,2,V)` and stores `(foo V)`, and 15 corpus files change answers [measured 2026-08-19] |
| `add-reduct` | core, follow-up | the same |
| `add-reducts` | core, follow-up | the same |
| `super` | core, follow-up | reaches the definition a space's parent holds; space configuration |
| `get-metatype` | core, follow-up | type semantics is a named follow-up presentation |
| `noeval` | core, follow-up | the Atom mask itself: the argument is the answer |
| `quote` | core, follow-up | the same mask, and the one the programs write |
| `annotation` | core, divergence | reads the answer's own annotation, this engine's weighted-answer channel |
| `explain` | core, divergence | the derivation of an answer, same channel |
| `if` | derived, fused | Hyperon's stdlib defines `if` in minimal MeTTa. Fused because it is written 259 times in the corpus, behind only `test`, `collapse` and `let` [measured 2026-08-19], and because its clauses build the branches through `build_branch/4`, which is what lets `and-then` and `or-else` be prelude rules with no runtime cost |
| `case` | derived, fused | a nested `if` chain, `translate_case/5`; fused for the same reason, and it carries a runtime path for cases that arrive as a value |
| `let*` | derived, fused | nested `let`s, `letstar_to_rec_let/3`; fused for the same reason, and it carries the same runtime path |
| `progn` | derived, fused | `(let $_ $a $b)` chained. The rule form measured 188 compile-time inferences against 150 and adds one `unify_with_occurs_check/2` goal per call that the fused form does not emit [measured 2026-08-19] |
| `prog1` | derived, fused | `(let $r $a (let $_ $b $r))`. 205 against 146, and two extra goals a call [measured 2026-08-19] |
| `once` | derived, fused | `(take 1 $e)` is the MeTTa spelling, and it answers the same thing over the whole corpus, 206 files with every answer group identical. It compiles to `metta_take/2` where the fused form compiles to Prolog's `once/1`, which costs 2 inferences a CALL: 454,152 against 354,122 over a 50,000-call loop, +28%, and 73 compile-time inferences against 36 [measured 2026-08-19]. The rule ships in `lib/lib_derived.metta` for a program that wants the smaller instruction set anyway |
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
| `sealed` | core, divergence | renames the listed variables at COMPILE time, which is the only place the rename can work |
| `\|->` | core, divergence | a lambda, compiled into a generated predicate in the space that wrote it |

## The prelude's derived forms, 8 heads

Each is an equation in `src/prelude.metta` plus `!(add-translator-rule! NAME)`.
The `Atom` parameters make the arguments arrive as syntax and the `%Undefined%`
result type makes the `(quote ...)` body translate, since an `Atom` result
would leave the body untranslated and hand the quote itself back.

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
`libraries/he_minimalmetta.metta` at -1.606%, because the six stream rewrites
used to run on every compound the translator walked. Two got dearer, both of
them files that write the moved forms: `control/and_then_or_else.metta`
+1.447% and `data/streamops.metta` +0.352%, all of it compile time.
`performance/hyperpose_primes.metta` and `integration/git_import.metta` are
excluded because their counts are not deterministic, the first running
branches in threads and the second shelling out to git; `reasoning/tilepuzzle.metta`
is excluded because it runs for minutes. Every corpus answer is unchanged,
group for group, and the conformance lane's per-area agreement is unchanged
[measured 2026-08-19].

## What would move next

`progn`, `prog1` and `once` are derived and their rules are written out in the
table above, so moving them is a decision about cost rather than about
expressiveness. Each one's rule emits a goal the fused clause does not, and
the numbers are beside them.

`once` is the one whose rule is COMPLETE, since it has a single arity, so it
ships in `lib/lib_derived.metta` and a program that wants the smaller
instruction set imports it and pays the two inferences a call.
`examples/libraries/derived_forms.metta` runs the swap and the swap back.
`progn` and `prog1` are variadic and a translator rule has a fixed arity, so a
rule for either would rewrite some calls and leave the rest to the compiler,
which is two compilations of one form rather than one. That is what would have
to be solved first.

The five space-update heads are the interesting case. They are one clause
shared five ways, and what keeps them in the compiler is not their semantics
but the depth of the Atom mask: the declaration `(: add-atom (-> Symbol Atom
(->)))` masks the argument at the top level and the general dispatch path
still evaluates inside it, while the special clause passes the whole term
raw. Make the declared mask reach all the way down and those five heads
become five ordinary builtins.
