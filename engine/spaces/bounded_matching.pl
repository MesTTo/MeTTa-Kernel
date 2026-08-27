% Purpose: propagate output bounds through conjunction matching, ordering, and best-first merge policies
% Assumes: engine/spaces.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/spaces.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% Guarantees: metta_match_atoms/2 dispatches a gap operand by its wrapper alone, and a merged read routes a gap pattern while reading its declared policy from what the program wrote [tested: tests/prolog/suites/reader/segments.plt; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb].
% Guarantees: an ordered carrier's declared ascending or descending direction
% is applied before a top prefix is selected [tested:
% test_ranked_and_tropical_slices_are_stable_best_prefixes; commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa].
% [tested: tests/prolog/suites/spaces/spaces.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%%% the bound the caller wrote, reaching the matcher %%%%
%
%(once (match &s (, ...) ...)) and (take N (match &s (, ...) ...)) know a
%bound match/4 does not, and the conjunctive door is the one place knowing it
%saves work: the snapshot above finds EVERY row before the first one leaves,
%so an unbounded conjunction walks the whole join to answer one row. Taking
%one row of a two-conjunct self-join cost 1,328 inferences over 10 edges and
%6,398 over 400; with the bound reaching here it is 1,222 over both, so the
%cost stopped tracking the join at all [measured 2026-08-21].
%
%The win is ASYMPTOTIC and OUTPUT-SENSITIVE rather than a constant factor. The
%unbounded collection is O(rows in the join) in time AND in the space the
%collected list holds, whatever the caller reads; bounded it is O(bound) in
%both, so first-answer latency stops growing with the data. The decision is
%amortized to COMPILE time, one unification per translated form and nothing per
%call, which is why every unbounded lane measures unchanged. Nothing here is
%shared between calls, so a bound adds no contention: limit/2's counter is a
%term local to the goal, and the collection is per call as it was.
%
%SOUND because of the shape the translator requires before it emits this: the
%bounded expression compiles to exactly one match goal, so nothing runs
%between a row and the answer it becomes, N rows are N answers, and a producer
%stopped at N cannot under-answer. A goal after the match could fail and make
%the (N+1)th row the answer, which is why the only thing that emits this is
%engine/translator.pl's `Conj = match(Space, Pattern, Template, Result)` shape
%test, written inline at translate_special_dl/5's once, take and top clauses
%[tested: test_a_bounded_conjunctive_match_stops_at_the_bound].
%
%Only the CONJUNCTIVE door takes the bound. A single pattern already streams
%under the logical update view and has nothing to stop, and a name that is not
%a space has no rows to bound and reaches match/4's own refusal through the
%second branch, so this predicate adds a door rather than a second matcher
%[tested: test_a_bounded_match_on_an_unbound_space_answers_the_error].
match_bounded(Bound, Space, Pattern, OutPattern, Result) :-
    (   bounded_conjunction(Bound, Space, Pattern)
    ->  conjunctive_match(limit(Bound,
                                match_conjunction(Space, Pattern, OutPattern)),
                          Space, Pattern, OutPattern, Result)
    ;   match(Space, Pattern, OutPattern, Result)
    ).

%A bound is usable when it is a whole number of rows, the pattern is a
%conjunction, and the space is one the engine holds. The last conjunct is what
%keeps the refusal in one place: a name that is not a space fails here and
%match/4 answers the Error atom it has always answered.
bounded_conjunction(Bound, Space, Pattern) :-
    integer(Bound),
    Bound >= 1,
    nonvar(Pattern),
    Pattern = [Comma|_],
    Comma == ',',
    metta_space_name(Space).

%THE ENGINE'S OWN READ of a space, the counterpart of get_native_atom/2 behind
%'get-atoms'/2 and there for the same reason: its callers hold a space name the
%ENGINE gave them rather than one a program wrote, so there is nothing to
%refuse and an error atom would be read back as a stored atom. The type lookups
%are why it has to exist rather than being a tidy split: a declaration lookup
%runs on every typed call, and routing those through the door made each one pay
%the door's refusal decision whenever the space had no atoms yet
%[measured 2026-08-20: py-method-call 2,250,095 inferences against 2,220,093,
%three per call over 10,000 evaluations in a space nothing had written to].
match_stored(Space, Pattern, OutPattern, Result) :-
    nonvar(Space), seam:foreign_space(Space), !,
    match_foreign(Space, Pattern, OutPattern, Result).
match_stored([Family|Parameters], Pattern, OutPattern, Result) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    native_storage_module_cache(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).
match_stored(Space, Pattern, OutPattern, Result) :-
    atom(Space),
    native_storage_module_cache(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).

%Choose the provider once for the whole conjunction. It may enumerate millions
%of native candidates, so deciding per candidate would repeat the foreign-space
%probe every time. A native space is a Prolog predicate named after the space
%and stays on the direct helper; anything else routes each conjunct back
%through match/4, which is how a space implemented by its own clause sees it.
match_conjunction(Space, Pattern, OutPattern) :- seam:foreign_space(Space), !,
                                                 match_foreign(Space, Pattern, OutPattern, _).
match_conjunction(Space, Pattern, OutPattern) :- native_storage_module_cache(Space, Module), !,
                                                 (   space_parent(Space, _)
                                                 ->  match_routed(Space, Pattern,
                                                                  OutPattern, _)
                                                 ;   match_native(Module, Space,
                                                                  Pattern,
                                                                  OutPattern, _)
                                                 ).
match_conjunction(Space, Pattern, OutPattern) :- match_routed(Space, Pattern, OutPattern, _).

match_inherited_space(Space, OwnModule, Pattern, OutPattern, Result) :-
    space_read_chain(Space, Each),
    (   Each == Space
    ->  match_native(OwnModule, Space, Pattern, OutPattern, Result)
    ;   match_read_link(Each, Pattern, OutPattern, Result)
    ).

match_read_link(Space, Pattern, OutPattern, Result) :-
    seam:foreign_space(Space),
    !,
    match_foreign(Space, Pattern, OutPattern, Result).
match_read_link(Space, Pattern, OutPattern, Result) :-
    native_storage_module_ready(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).

match_routed(_, LComma, OutPattern, Result) :- LComma == [','], !,
                                               Result = OutPattern.
%The same reordering as match_native/5's, for a space whose reads go through a
%parent chain. The conjuncts here are matched by match/4 rather than read from
%one storage module, so the probe asks match/4 the same cheap question: has
%this conjunct at most one match under the bindings so far. An inherited space
%joins across the chain, `(new-space &child (inherits &parent))` in
%examples/ch19-spaces-backed-by-anything/19-01-spaces-of-your-own/01-inherited_spaces.metta, and pays the same quadratic under skew
%without it. A read through the chain is a child-first multiset union and each
%conjunct routes through it independently, so which conjunct is taken first
%changes neither the rows nor how many times each appears.
%
%match_foreign_routed/6's own split is deliberately NOT reordered. That one
%combines each conjunct's annotation along the join with the algebra's declared
%extend, and `extend-commutative` is optional: the shipped prob and prov
%algebras do not declare it, so the order conjuncts are visited in is part of
%the answer there [source: website/guide/contract.md:73-80]. A foreign
%provider's own join is reachable through foreign_plan/5, which is offered the
%whole conjunction before any split happens.
match_routed(Space, [Comma|Conjuncts], OutPattern, Result) :-
    Comma == ',',
    Conjuncts = [_, _|_],
    routed_cheapest_conjunct(Space, Conjuncts, Head, Rest),
    !,
    match(Space, Head, conj, conj),
    match_routed(Space, [','|Rest], OutPattern, Result).
match_routed(Space, [','|[Head|Tail]], OutPattern, Result) :-
    match(Space, Head, conj, conj),
    match_routed(Space, [','|Tail], OutPattern, Result).

routed_cheapest_conjunct(Space, [First|More], Best, Rest) :-
    (   goal_matches_at_most_one(match(Space, First, conj, conj))
    ->  Best = First,
        Rest = More
    ;   routed_selective_conjunct(Space, More, Found, Others)
    ->  Best = Found,
        Rest = [First|Others]
    ;   Best = First,
        Rest = More
    ).

routed_selective_conjunct(Space, Conjuncts, Best, Rest) :-
    select(Best, Conjuncts, Rest),
    goal_matches_at_most_one(match(Space, Best, conj, conj)),
    !.

%One matching step of Hyperon's unify: each solution is one binding set,
%bindings applied by Prolog unification itself. The clause order is the
%case order of the arbiter's matcher, LeaTTa
%MettaHyperonFull/Core/Matching.lean matchAtomsWith (209-241): variables
%bind before anything is consulted, with the occurs check the arbiter's
%variable cases carry; expressions match pointwise, consistency kept by
%the shared bindings; then a grounded operand's own matching logic runs,
%left before right, which is how a space becomes queryable inside unify
%(Hyperon: `impl CustomMatch for DynSpace` is query, hyperon-space
%engine/lib.rs); a host value with declared matching runs its hook the same
%way; numbers compare promoted, so 1 matches 1.0 [source: LeaTTa
%tests/semantics/matching/grounded_value_matching.metta, measured
%2026-08-11]; everything else is ground equality. A space is named by a
%symbol here rather than a grounded atom, so the operand test is the
%registered-space probe, and an unregistered name falls through to
%equality like any symbol. The leading identity clause is the arbiter's
%diagonal collapsed to one C comparison: two identical operands match
%with the empty binding set case for case (equal grounds trivially; a
%shared variable is the same-variable case; identical compounds decide
%pointwise to the same), and it spares the per-leaf probe cascade on the
%equal-operand traffic that dominates eval-branch tests
%[measured 2026-08-17: test_unify_eval_branches].
%A GAP OPERAND arrives wrapped, carrying the fragment its call site decided
%[source: LeaTTa MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?]. The
%wrapper is what makes the question free: nonvar/1 and =/2 compile inline and
%are not counted as inferences, and a clause whose head does not unify costs
%none either, so every ordinary unify, let and case pays exactly what it did
%[measured 2026-08-24: 100,000 calls through three such guards cost 400,002
%inferences against 400,003 through none].
metta_match_atoms(L, R) :-
    nonvar(L),
    L = '$metta_seq'(Plan, Parsed),
    !,
    metta_seq_unify(Plan, Parsed, R).
metta_match_atoms(L, R) :- L == R, !.
metta_match_atoms(L, R) :- ( var(L) ; var(R) ), !,
                           unify_with_occurs_check(L, R).
%A cons cell and () never match, and deciding that must not WALK the cons.
%Every route below reaches the same failure: read as lists they differ at the
%very first cell, and the clauses past the list branch all decide by equality,
%which a cons and () fail too. `(unify $l () ...)` is how a list is walked to
%its end, so is_list/1 walking the whole remaining list at every step made the
%walk quadratic [measured 2026-08-23: 114 microseconds over 200 elements and
%7,550 over 3,200, 10.1x per 4x, and one probe of a 6,400-element list against
%() cost 9.16 microseconds against 0.5 now].
%
%Confirmed rather than argued: over 26 cases spanning proper, improper,
%partial, error-shaped and mixed-type cons cells in both operand positions,
%every one already failed.
metta_match_atoms(L, R) :- L == [], nonvar(R), R = [_|_], !, fail.
metta_match_atoms(L, R) :- R == [], nonvar(L), L = [_|_], !, fail.
metta_match_atoms(L, R) :- is_list(L), is_list(R), !,
                           metta_match_all(L, R).
metta_match_atoms(L, R) :- metta_space_operand(L), !, match(L, R, [], _).
metta_match_atoms(L, R) :- metta_space_operand(R), !, match(R, L, [], _).
metta_match_atoms(L, R) :- seam:matchable_value(L), !,
                           seam:custom_match(L, R).
metta_match_atoms(L, R) :- seam:matchable_value(R), !,
                           seam:custom_match(R, L).
metta_match_atoms(L, R) :- number(L), number(R), !, L =:= R.
metta_match_atoms(L, R) :- L == R.

metta_match_all([], []).
metta_match_all([X|Xs], [Y|Ys]) :-
    metta_match_atoms(X, Y),
    metta_match_all(Xs, Ys).

%Whether an operand names a space this engine can query: a foreign
%provider or a native storage module. Both probes are indexed lookups.
%
%The '&' test in front of them is the engine's OWN space-name rule, applied
%where it is cheapest instead of only where a space is created. It is not a
%new assumption: metta_space_name/1 refuses any other spelling at the
%creation door [source: engine/spaces/catalog.pl, metta_space_name/1],
%metta_require_space_name/2 refuses it at new-space and inherits [source:
%engine/spaces/lifecycle.pl], register_provider refuses it at the Python
%door [source: bindings/python/metta/foreign.py, "a space name starts with
%&"], both wire codecs refuse to decode any other spelling [source:
%bindings/python/metta/shim.pl metta_py_decode_(p, ...) and
%bindings/node/bridge.pl], MORK's own ownership test is the same prefix
%[source: backends/mork/mork_ffi/morkspaces.pl, mork_owns_space/1], and a
%state cell spells its handle the same way [source: engine/metta/control.pl,
%metta_state_cell/1]. Every seam:foreign_space/1 clause in this tree names a
%'&' atom, so the rule was already universal and this predicate was the one
%place that paid to re-discover it.
%
%What it buys: an ordinary symbol - nearly every atom this engine ever tests
%- fails here for one inference instead of paying both probes, on the nine
%hot paths that ask [measured 2026-08-28 in the shipped Python configuration,
%20,000 iterations against a bare loop: 8 inferences per non-space atom
%before, 3 after; metta_match_atoms/2 asks twice per atom position].
%
%Limitation: seam:foreign_space/1 is an open ownership seam, so an extension
%that adds a clause naming an atom without the prefix stops being seen as a
%space here. That configuration is already broken upstream of this
%predicate - neither wire codec can carry such a name - and the live-database
%check in tests/prolog/static_checks.pl now refuses it by name rather than
%letting it fail quietly [tested: every_foreign_space_is_an_ampersand_name].
metta_space_operand(S) :-
    atom(S),
    !,
    sub_atom(S, 0, 1, _, '&'),
    (   seam:foreign_space(S)
    ->  true
    ;   native_storage_module_cache(S, _)
    ).
%A PARAMETRIC name is always a nonempty list: metta_require_parametric_space_name/1
%refuses anything else at the only door that asserts space_parametric/1
%[source: engine/spaces/lifecycle.pl]. Saying so here costs nothing - both
%tests compile inline - and stops every number, string and non-list compound
%the matcher meets from probing the table to be told what its shape already
%said. engine/spaces/foreign.pl:321 already guards the same table this way.
metta_space_operand(S) :-
    nonvar(S),
    S = [_|_],
    space_parametric(S).


%Every space name this engine registers: '&self' and '&metta' from load time,
%every atomic or parametric native space that new-space made or that has been
%written to, and every foreign provider currently bound. Naming a space never
%registers it, only creating it, writing to it or binding one does, so this is
%the same set metta_space_operand/1 accepts. sort/2 makes the answer stable and
%duplicate-free.
metta_space_names(Names) :-
    findall(S, native_storage_module_cache(S, _), Native),
    findall(S, seam:foreign_space(S), Foreign),
    append(Native, Foreign, All),
    sort(All, Names).

%The Empty prune behind every computed collapse. The gate is memberchk
%NEGATED, which makes it sound AND C-fast: when nothing in the list
%unifies with Empty (the overwhelmingly common all-ground case,
%4 inferences however long the list), the list is shared untouched; when
%something unified, the negation has already undone the binding, and the
%identity (==) walk decides whether it was a real Empty or an unbound
%answer variable. Bare memberchk once BOUND such a variable and pruned
%it, which turned `!(let $b (is-alpha-member (1 $x) ...) $x)`'s unbound
%answer into nothing
%[tested translated_success_leaves_the_query_variable_unbound].
metta_prune_empty(All, Kept) :-
    (   \+ memberchk('Empty', All)
    ->  Kept = All
    ;   metta_member_empty_(All)
    ->  metta_drop_empty_(All, Kept)
    ;   Kept = All
    ).

metta_member_empty_([X|Xs]) :-
    (   X == 'Empty'
    ->  true
    ;   metta_member_empty_(Xs)
    ).

metta_drop_empty_([], []).
metta_drop_empty_([X|Xs], Kept) :-
    (   X == 'Empty'
    ->  metta_drop_empty_(Xs, Kept)
    ;   Kept = [X|Kept1],
        metta_drop_empty_(Xs, Kept1)
    ).

%The runnable collector carries each answer beside its reader names. Prune on
%the answer slot while retaining the side map for every surviving answer.
%This mirrors metta_prune_empty/2's identity test, so a free answer variable
%is not mistaken for Empty [tested: test_variable_names_survive_to_the_printer;
%commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
metta_prune_empty_answers(All, Kept) :-
    (   \+ memberchk('$metta_answer'('Empty', _), All)
    ->  Kept = All
    ;   metta_member_empty_answer_(All)
    ->  metta_drop_empty_answers_(All, Kept)
    ;   Kept = All
    ).

metta_member_empty_answer_(['$metta_answer'(X, _)|Xs]) :-
    (   X == 'Empty'
    ->  true
    ;   metta_member_empty_answer_(Xs)
    ).

metta_drop_empty_answers_([], []).
metta_drop_empty_answers_(['$metta_answer'(X, Names)|Xs], Kept) :-
    (   X == 'Empty'
    ->  metta_drop_empty_answers_(Xs, Kept)
    ;   Kept = ['$metta_answer'(X, Names)|Kept1],
        metta_drop_empty_answers_(Xs, Kept1)
    ).

%Unwrap a nested collapse for evaluation while retaining each copied name
%state in the enclosing runnable's side map. Term and state came out of one
%findall template, so their variables still share identity here.
metta_answer_terms([], [], []).
metta_answer_terms(['$metta_answer'(Term, Names)|Answers],
                   [Term|Terms], [Names|NameStates]) :-
    metta_answer_terms(Answers, Terms, NameStates).


%A foreign provider enumerates candidates. Unification against the pattern
%stays here, so an approximate provider cannot change matching soundness.
%Which way this space answers, decided ONCE for the whole match. It depends
%only on Space, so asking per conjunct is invariant work inside a loop:
%measured at 8.00 inferences of the seam's 9.00 fixed overhead, paid once per
%OUTER ROW in a join because the inner conjunct is re-dispatched on every
%backtrack. Hoisting it took a 200-row join from 1.89x a direct match/4 clause
%to 1.10x, saving 8.01 per row.
%
%match_native/5 one clause up already does this and says why: "The recursive
%helper keeps the provider decision outside the candidate loop."
foreign_route(Space, Route) :-
    (   foreign_provides(Space, match)
    ->  Route = match
    ;   refuse_absent_capability(Space, enumerate),
        Route = enumerate
    ).

%Whether a provider takes this conjunction, decided ONCE and committed to. A
%provider that could yield a row and then decline would leave the engine unable
%to tell "no rows" from "not mine", which is the ambiguity seam:foreign_match/3
%was fixed for; once/1 here and the cut at the call site are what prevent it.
foreign_claims_plan(Space, Conjuncts, Rest, Goal) :-
    foreign_provides(Space, plan),
    once(seam:foreign_plan(Space, Conjuncts, Claimed, Rest, Goal)),
    Claimed \== [],
    refuse_lossy_plan(Space, Conjuncts, Claimed, Rest).

%Claimed and Rest have to PARTITION the conjunction. Both sides hold the
%CALLER'S OWN pattern terms (the Python seam resolves its answer back to
%them by wire identity), so this compares like with like and is a real
%check; it used to double as the mechanism that reconnected freshly
%decoded copies to the caller, which worked only while both lists
%happened to sort into the same order. A provider that drops a
%conjunct answers more rows than the query asks for, and nothing downstream
%would catch it: the engine plans Rest and never looks at the original patterns
%again, so the dropped conjunct is simply not part of the query any more. Once
%per join and never per row.
refuse_lossy_plan(Space, Patterns, Claimed, Rest) :-
    append(Claimed, Rest, Both),
    msort(Both, Sorted),
    (   msort(Patterns, Sorted)
    ->  true
    ;   throw(error(metta_foreign_plan_is_not_a_partition(Space, Patterns,
                                                          Claimed, Rest),
                    context(match/4,
                            'a claim must partition the conjunction')))
    ).

%A declared Refuse fires on ANY match of its shape, bounded or not: the
%author said this context cannot answer it, and a silent partial answer is
%the failure the declaration exists to prevent. One route consultation per
%query, never per answer. Handles entries describe MATCH shapes, so a
%conjunction is decomposed and each conjunct asked on its own; offering the
%raw [','|_] term instead let an ($f ...) entry capture the comma itself.
metta_refuse_guard(Space, _) :-
    \+ metta_ctx_declared(Space),
    !.
metta_refuse_guard(Space, Pattern) :-
    (   nonvar(Pattern), Pattern = [Comma|Conjuncts], Comma == ','
    ->  \+ \+ metta_refuse_guard_conjuncts(Conjuncts, Space)
    ;   %The route is computed with fidelity UNBOUND and tested after, so
        %the coherence check inside it runs on every consultation; asking
        %for 'Refuse' directly would fail out before two disagreeing
        %entries are compared, and the conflict would surface only under a
        %bound instead of on every match.
        metta_handles_route(Space, Pattern, Entry, Fidelity, _),
        Fidelity == 'Refuse'
    ->  throw(error(metta_refused_shape(Space, Pattern, Entry), none))
    ;   true
    ).

%Left-to-right, the way the nested loop executes: a conjunct's variables are
%bound by the time later conjuncts run, so each is checked with the earlier
%ones' variables marked bound. This is adornment-level analysis, Mercury's
%modes and the database bindability check: an (in $x) refusal fires here at
%plan time, while a refusal keyed to a literal VALUE can only fire on a
%direct query where the value is visible. The double negation above undoes
%the marker bindings; a throw passes through it.
metta_refuse_guard_conjuncts([], _).
metta_refuse_guard_conjuncts([Conjunct|Rest], Space) :-
    metta_refuse_guard(Space, Conjunct),
    term_variables(Conjunct, Vars),
    maplist(=('$metta_bound'), Vars),
    metta_refuse_guard_conjuncts(Rest, Space).

match_foreign(Space, Pattern, OutPattern, Result) :-
    metta_refuse_guard(Space, Pattern),
    metta_negation_world_guard(Space),
    foreign_route(Space, Route),
    match_foreign_routed(Space, Route, Pattern, [], OutPattern, Result).

match_foreign_routed(_, _, LComma, _, OutPattern, Result) :- LComma == [','], !,
                                                             Result = OutPattern.
%The conjunction is offered to the provider WHOLE before it is split, which is
%the only way a backend's own join is reachable: the split below is a
%nested-loop plan, and a provider that never sees more than one pattern at a
%time cannot do better than one however fast it is.
%
%Two or more conjuncts, because a single one is the ordinary match path and
%offering it here would only duplicate that.
match_foreign_routed(Space, Route, [Comma|Conjuncts], _, OutPattern, Result) :-
    Comma == ',', Conjuncts = [_, _|_],
    foreign_claims_plan(Space, Conjuncts, Rest, Goal), !,
    call(Goal),
    match_foreign_routed(Space, Route, [','|Rest], [], OutPattern, Result).
match_foreign_routed(Space, Route, [Comma|[Head|Tail]], _, OutPattern, Result) :-
    Comma == ',', !,
    match_foreign_routed(Space, Route, Head, [], conj, conj),
    metta_annotation(Space, HeadK),
    match_foreign_routed(Space, Route, [','|Tail], [], OutPattern, Result),
    %The declared extend operation threads annotations along the join. Its
    %declared one combines without a write, so an unannotated join stays cheap;
    %the LAST conjunct combines with nothing, since the base case that
    %follows it contributes no answer of its own.
    metta_algebra_one(Space, One),
    (   HeadK == One
    ->  true
    ;   Tail == []
    ->  true
    ;   metta_annotation(Space, TailK),
        metta_k_extend(Space, HeadK, TailK, RowK),
        b_setval('$metta_answer_k', RowK)
    ).
%An unbound pattern is enumeration whichever way the space answers matches, so
%it asks for that capability on its own rather than riding the route.
match_foreign_routed(Space, _, PatternVar, _, OutPattern, Result) :-
    var(PatternVar), !,
    refuse_absent_capability(Space, enumerate),
    %The source guard sits at the three clauses that PHYSICALLY touch the
    %provider, not at the conjunction entry: a join's inner conjunct is
    %its own touch per outer row, and that second touch of a drained
    %linear source is exactly what must be loud.
    metta_source_guard(Space),
    seam:foreign_atoms(Space, PatternVar),
    acyclic_term(OutPattern),
    Result = OutPattern.
match_foreign_routed(Space, match, Pattern, Options, OutPattern, Result) :- !,
    licensed_options(Space, Pattern, Options, Licensed),
    metta_source_guard(Space),
    (   metta_on_error_mode(Space, Pattern, Mode),
        Mode \== abort
    ->  metta_match_erring(Mode, Space, Pattern, Licensed, OutPattern, Result)
    ;   seam:foreign_match(Space, Pattern, Licensed),
        acyclic_term(OutPattern),
        Result = OutPattern
    ).

match_foreign_routed(Space, enumerate, Pattern, _, OutPattern, Result) :-
    metta_source_guard(Space),
    seam:foreign_atoms(Space, Candidate),
    Candidate = Pattern,
    acyclic_term(OutPattern),
    Result = OutPattern.
%A declared keep delivers the provider's own failure as one final (Error
%...) answer beside the answers that already streamed, LeaTTa's
%adjudicated reading of evaluation errors turned to the provider
%boundary; empty ends the stream by declaration. Control signals and
%transport failures pass through both, always: an interrupt is the
%caller's, and an absent backend is never a data answer.
%
%WHERE the failure is caught depends on the provider's host, and that is
%not a style choice: a Python exception raised mid-iteration TUNNELS
%through py_iter back to the outer Python interpreter and no Prolog
%catch/3 can hold it [measured 2026-08-17: a catch-all around py_iter
%still surfaced the raw ValueError in janus.query_once], so a Python
%provider's mode is enforced on the Python side of the crossing, with a
%kept failure arriving as the reserved ["x","error",...] wire item
%through the seam:foreign_erring/5 adapter hook. A provider whose host
%is Prolog throws ordinary catchable exceptions, and the fallback below
%handles those here; catch/3 keeps the goal's choice points, so streamed
%answers survive the wrapping.
metta_match_erring(Mode, Space, Pattern, Licensed, OutPattern, Result) :-
    (   seam:foreign_erring(Space, Pattern, Licensed, Mode, Item)
    *-> (   Item == answer
        ->  acyclic_term(OutPattern),
            Result = OutPattern
        ;   Item = kept(Kept),
            Result = Kept
        )
    ;   catch(( seam:foreign_match(Space, Pattern, Licensed),
                Outcome = answer ),
              Error,
              metta_match_error_outcome(Error, Mode, Outcome)),
        (   Outcome == answer
        ->  acyclic_term(OutPattern),
            Result = OutPattern
        ;   Outcome = kept(E),
            metta_error_answer(Pattern, E, Result)
        )
    ).

metta_match_error_outcome(Error, _, _) :-
    control_exception(Error), !, throw(Error).
metta_match_error_outcome(Error, _, _) :-
    metta_transport_failure(Error), !, throw(Error).
metta_match_error_outcome(Error, keep, kept(Error)).

%A bound pattern went straight to the match hook, so a provider that
%implements only enumeration answered NOTHING to every real query while the
%space demonstrably held matching atoms. extensions/python/metta/foreign.py states the
%opposite contract for the same seam, in as many words: "An Enumerable
%provider need not implement Matcher: enumeration is the correct default
%candidate set". Porting a working Python provider to Prolog for speed, which
%is exactly what EXTENDING.md recommends, turned every match into an empty
%answer set.
%
%The provider is handed a FRESH variable and the filter happens here, so a
%provider written to enumerate never sees a bound pattern it was not written
%for. Unification staying on this side is also what makes over-approximation
%sound, which is the seam's central claim.
%The same match, carrying what the caller intends to do with it. Honouring an
%option is the provider's decision and not the engine's; see engine/ext_points.pl.
%Unification and the engine's own bound stay here whatever the provider does,
%so an option cannot make an answer wrong, only cheaper.
match_foreign(Space, Pattern, Options, OutPattern, Result) :-
    metta_refuse_guard(Space, Pattern),
    metta_negation_world_guard(Space),
    foreign_route(Space, Route),
    match_foreign_routed(Space, Route, Pattern, Options, OutPattern, Result).

%The bound reaches a provider that PROMISED it can act on it, and nobody else.
%
%It used to reach everyone as advice, with the rule for using it soundly
%written in the contract: honour it only where an exact match is
%distinguishable from a candidate, because N candidates are not N answers and
%truncating without knowing which of them unify under-answers. That rule is
%correct and it is a trap, since nothing checked whether a provider that
%truncated was entitled to. This engine's own test fixture had "its match is
%exact" in a docstring and nothing testing it.
%
%So the number goes to a provider that declared exact for this pattern, and
%the trap closes by construction: a provider that never promised is never
%given a number it could truncate to. Apache DataFusion's planner does the
%same thing with the same reasoning, dropping its own FilterExec only for a
%source that answered Exact.
%
%What the engine deliberately does NOT do with the class is stop pulling
%earlier. That was the obvious use and it buys nothing, measured both ways: a
%Prolog provider is already cut by the caller's own limit/2 after the Nth
%answer, and a Python one is pulled one ahead by janus's py_iter whatever the
%engine asks for, so limit(3) produced 3 and 4 candidates respectively with
%and without the classification wired to it [measured 2026-08-16,
%ai-tmp/x7pl.pl]. Unification is not skippable either: it is not a filter here
%but the step that binds the pattern's variables. An exact claim can therefore
%make a provider cheaper and can never make an answer wrong.
licensed_options(Space, Pattern, Options, Licensed) :-
    (   selectchk(limit(_), Options, WithoutBound)
    ->  (   foreign_pushdown_class(Space, Pattern, exact)
        ->  Licensed = Options
        ;   Licensed = WithoutBound
        )
    ;   Licensed = Options
    ).

%%%% take: at most K answers, and the bound the provider gets %%%%
%
%limit/2 is applied OUTSIDE the producer in both clauses, and that is what
%makes the whole thing correct rather than merely fast: it cuts the producer
%after the Kth answer whatever the producer did, so an infinite one terminates
%and a pushdown below it cannot change an answer. The pushdown decides only
%how much work the backend does before the first one.
metta_take(Count, Goal) :-
    metta_take_count(take, Count),
    limit(Count, Goal).

%The bound reaches the PROVIDER only when the expression is exactly one match
%over one space. Across a join the bound belongs to the joined rows, and an
%outer match truncated at N loses the rows its later candidates would have
%joined to; that is the rule metta_py_query_limit_all/5 already follows for
%m.match(limit=), and this is the same rule at the MeTTa level rather than a
%second one.
%
%A provider that never claimed `exact` for this pattern is not handed the
%number at all, which licensed_options/4 enforces on the way through, so the
%one thing the contract forbids stays impossible from here too.
%
%The native side goes through match_bounded/5, which is where the count stops
%a conjunctive snapshot instead of only cutting its answers; a single pattern
%reaches match/4 from there exactly as it did.
metta_take_match(Count, Space, Pattern, OutPattern, Result) :-
    metta_take_count(take, Count),
    (   nonvar(Space),
        seam:foreign_space(Space)
    ->  limit(Count, match_foreign(Space, Pattern, [limit(Count)], OutPattern,
                                   Result))
    ;   limit(Count, match_bounded(Count, Space, Pattern, OutPattern, Result))
    ).

%A count that is not a number is a mistake rather than an empty answer, for
%the reason every refusal here is: failing into "there is nothing there" sends
%the author looking at their data. A count of zero or less answers nothing,
%which is what "at most K" means and what limit/2 already does.
metta_take_count(_, Count) :- integer(Count), !.
metta_take_count(Form, Count) :-
    throw(error(type_error(integer, Count),
                context(Form/2, 'take needs a whole number of answers'))).

%%%% top: the k BEST by annotation, where take is any k %%%%
%
%Two bounds, two specifications. take k is "at most k, no promise which",
%correct for unordered contexts. top k is the k best in the context's
%declared semiring order, the operation a vector index actually
%implements. Each answer's annotation rides '$metta_answer_k',
%backtrackably: the seam sets it per explicit answer and the default 1
%is restored on redo, so an unannotated answer between two annotated
%ones reads 1 rather than a stale neighbour.
:- meta_predicate metta_take(+, 0), metta_top(+, 0, ?).
%The same reason the block above metta_timeout/3 in metta.pl records:
%without this the bounded goal loses its module and a named space's own
%functions are unreachable inside take and top.

metta_top(Count, Goal, Out) :-
    metta_take_count(top, Count),
    current_metta_space(Ctx),
    metta_algebra_one(Ctx, One),
    findall(Annotation-Out,
            ( b_setval('$metta_answer_k', One),
              call(Goal),
              b_getval('$metta_answer_k', Annotation) ),
            Pairs),
    metta_top_best(Ctx, Count, Pairs, Best),
    member(Out, Best).

%The single-match form checks the context's declared order and decides the
%push. The bound reaches the provider only when three declarations hold
%together: the route is Exact for this shape, the annotations are ordered,
%and the merge policy is best-first, since the first k of a best-first
%emission ARE the k best. Drop any one and a pushed bound can return the
%wrong k, not merely a permutation, so the bound stays here and the
%ordering happens after collection.
metta_top_match(Count, Space, Pattern, OutPattern, Result) :-
    metta_take_count(top, Count),
    (   metta_annotations_ordered(Space)
    ->  true
    ;   metta_effective_algebra(Space, Semiring),
        throw(error(metta_top_unordered(Space, Semiring), none))
    ),
    (   nonvar(Space),
        seam:foreign_space(Space)
    ->  (   metta_top_pushable(Space, Pattern)
        ->  Options = [limit(Count)]
        ;   Options = []
        ),
        Producer = match_foreign(Space, Pattern, Options, OutPattern, Result)
    ;   %A native space that declares an ordered semiring still stores
        %plain atoms, so every annotation reads 1 and top k keeps the
        %first k by emission order, the all-ties reading.
        Producer = match(Space, Pattern, OutPattern, Result)
    ),
    metta_algebra_one(Space, One),
    findall(Annotation-Result,
            ( b_setval('$metta_answer_k', One),
              Producer,
              b_getval('$metta_answer_k', Annotation) ),
            Pairs),
    metta_top_best(Space, Count, Pairs, Best),
    member(Result, Best).

metta_top_pushable(Space, Pattern) :-
    %A cap below exact, or a cap refusal, declines the pushdown here and
    %lets the match itself surface the loud error, so (top k) never pushes
    %a bound an advisor has withdrawn the licence for.
    catch(( metta_handles_route(Space, Pattern, 'Exact', _),
            metta_route_cap_apply(Space, Pattern, exact, exact) ),
          _, fail),
    metta_emits(Space, 'best-first').

%Best first, ties in emission order: sort/4 with @>= keeps duplicates and
%is stable, so equal annotations keep the provider's own order.
metta_top_best(Ctx, Count, Pairs, Best) :-
    (   metta_annotations_order(Ctx, ascending)
    ->  sort(1, @=<, Pairs, Ordered)
    ;   sort(1, @>=, Pairs, Ordered)
    ),
    metta_top_prefix(Count, Ordered, Best).

metta_top_prefix(Count, Ordered, Best) :-
    length(Ordered, Total),
    Keep is min(Count, Total),
    length(Prefix, Keep),
    append(Prefix, _, Ordered),
    findall(Out, member(_-Out, Prefix), Best).

:- multifile prolog:error_message//1.
prolog:error_message(metta_top_unordered(Ctx, Semiring)) -->
    [ '(top k ...) asks for the k BEST and ~w declares the ~w semiring, \c
       which carries no order. Declare (annotations ~w ranked) if this \c
       context annotates its answers, or use (take k ...) for any \c
       k'-[Ctx, Semiring, Ctx] ].

%What the seam already decided for a query, shown to a host without running
%it: refusal preflighted through the same metta_refuse_guard that
%match_foreign consults, per-pattern classes through foreign_pushdown_class
%with each pattern asked standalone, and the conjunction claim through the
%same guarded seam:foreign_plan call the execution commits to, the
%lossy-partition check included. Claimed and Rest come back as indexes into
%the pattern list, so a host renders its own atoms and its caller's variable
%names survive. A stored space answers explain(stored, [], [], []): the
%engine joins by unification and no provider is consulted. Origins are
%TERMS, declared(Entry, Fidelity, Det), provider, unclaimed or
%refused(Entry); prose is the host's own presentation.
metta_host_explain_match(Space, Patterns, Report) :-
    (   \+ seam:foreign_space(Space)
    ->  Report = explain(stored, [], [], [])
    ;   ( Patterns = [Whole] -> true ; Whole = [','|Patterns] ),
        catch(
            ( \+ \+ metta_refuse_guard(Space, Whole),
              maplist(metta_host_explain_class(Space), Patterns, Classes),
              metta_host_explain_plan(Space, Patterns, ClaimedIdx, RestIdx),
              Report = explain(foreign, Classes, ClaimedIdx, RestIdx) ),
            error(metta_refused_shape(_, _, Entry), _),
            Report = explain(refused, [Entry], [], []))
    ).

metta_host_explain_class(Space, Pattern, class(Class, Origin)) :-
    catch(
        ( foreign_pushdown_class(Space, Pattern, Class),
          metta_host_explain_origin(Space, Pattern, Origin) ),
        error(metta_refused_shape(_, _, Refusing), _),
        ( Class = refused,
          Origin = refused(Refusing) )).

%The origin consult mirrors foreign_pushdown_class's own precedence: a
%declared (handles ...) entry outranks the provider's method, and silence
%is the closed-world inexact.
metta_host_explain_origin(Space, Pattern, Origin) :-
    (   metta_handles_route(Space, Pattern, Entry, Fidelity, Det)
    ->  Origin = declared(Entry, Fidelity, Det)
    ;   seam:foreign_pushdown(Space, Pattern, _)
    ->  Origin = provider
    ;   Origin = unclaimed
    ).

metta_host_explain_plan(Space, Patterns, ClaimedIdx, RestIdx) :-
    (   Patterns = [_, _|_],
        foreign_provides(Space, plan),
        once(seam:foreign_plan(Space, Patterns, Claimed, Rest, _Goal)),
        Claimed \== []
    ->  refuse_lossy_plan(Space, Patterns, Claimed, Rest),
        maplist(metta_host_explain_index(Patterns), Claimed, ClaimedIdx),
        maplist(metta_host_explain_index(Patterns), Rest, RestIdx)
    ;   ClaimedIdx = [],
        findall(I, nth0(I, Patterns, _), RestIdx)
    ).

metta_host_explain_index(Patterns, Term, Index) :-
    nth0(Index, Patterns, Candidate),
    Candidate == Term, !.

%What a provider claims about its own filtering for THIS pattern. Silence is
%inexact, which is Prolog's own closed-world reading of the question, "any
%conclusion that cannot be proved to follow from the facts and rules in the
%database is false" [source: Bramer, Logic Programming with Prolog, 3.1], and
%the cautious answer: an inexact provider gets no bound to truncate to and its
%candidates are re-unified.
foreign_pushdown_class(Space, Pattern, Class) :-
    foreign_pushdown_declared_class(Space, Pattern, Declared),
    metta_route_cap_apply(Space, Pattern, Declared, Class).

foreign_pushdown_declared_class(Space, Pattern, Class) :-
    (   metta_handles_route(Space, Pattern, Entry, Fidelity, _Det)
    ->  %A declared (handles ...) entry outranks the provider's own method:
        %the declaration is the author's claim, checked by its lanes, and
        %the method stays as the dynamic floor for the undeclared. Exact
        %licenses the bound; Partial and Sound are candidates needing
        %re-unification, today's inexact; Refuse is the author's NO and it
        %is loud, the same precedence volatile has over unchecked.
        (   Fidelity == 'Exact'  -> Class = exact
        ;   Fidelity == 'Refuse' -> throw(error(metta_refused_shape(Space,
                                                                    Pattern,
                                                                    Entry),
                                                none))
        ;   Class = inexact
        )
    ;   seam:foreign_pushdown(Space, Pattern, Claimed)
    ->  Class = Claimed
    ;   Class = inexact
    ).

%The advisors' fold: every seam:route_cap/4 clause is a voice and the
%most conservative wins, refuse below inexact below exact, so an advisor
%can only DEMOTE what the declaration or the method proposed. refuse is
%loud and names the advisor's Why; a cap outside the vocabulary is a bug
%in the advisor and refuses as one. The common engine has no advisor
%loaded, and that costs one failed indexed call; with advisors present
%the probe's work is repeated inside findall, which is accepted, advisors
%being rare and the fold running only at route classification, never per
%answer.
metta_route_cap_apply(Space, Pattern, Class0, Class) :-
    (   \+ seam:route_cap(Space, Pattern, _, _)
    ->  Class = Class0
    ;   findall(Cap-Why, seam:route_cap(Space, Pattern, Cap, Why), Caps),
        (   member(BadCap-BadWhy, Caps),
            % policy-inventory-exempt: mechanism-internal; reason=exact inexact and refuse are the route-advisor fold states rather than a user policy vocabulary; evidence=engine/spaces/bounded_matching.pl:metta_route_cap_apply/4
            \+ memberchk(BadCap, [exact, inexact, refuse])
        ->  throw(error(metta_route_cap_invalid(Space, BadCap, BadWhy),
                        none))
        ;   member(refuse-Why, Caps)
        ->  throw(error(metta_route_capped(Space, Pattern, Why), none))
        ;   memberchk(inexact-_, Caps)
        ->  Class = inexact
        ;   Class = Class0
        )
    ).

:- multifile prolog:error_message//1.
prolog:error_message(metta_route_capped(Space, Pattern, Why)) -->
    { swrite(Pattern, PatternText) },
    [ 'a route advisor refuses ~w for ~w: ~w. The cap rides \c
       seam:route_cap/4; remove the advisor''s reason or its declaration \c
       to route again'-[Space, PatternText, Why] ].
prolog:error_message(metta_route_cap_invalid(Space, Cap, Why)) -->
    [ 'a route advisor for ~w answered the cap ~w (why: ~w), outside \c
       exact, inexact and refuse; an unknown cap would silently advise \c
       nothing, so it is an error in the advisor'-[Space, Cap, Why] ].

%%%% Multi-context matching: one query over several spaces %%%%
%
%(match (superpose (&a &b ...)) P T), the multi-context idiom, merges
%the spaces' answer streams under the declared (merge <pattern>
%<policy>): depth is today's space-after-space order and the undeclared
%floor; fair interleaves the streams round-robin through SWI engines,
%LogicT's msplit in the engine's own machinery (the reified-backtracking
%meta-interpreter shape, threadless); best-first is a k-way ordered
%merge by annotation, sound only when every context's own emission is
%best-first, which its (emits ...) declaration promises and this
%refuses loudly without.
%A GAP PATTERN arrives wrapped, and the declared route is read from what the
%program wrote rather than from the wrapper, so `(merge <pattern> fair)`
%selects the same policy for a gap query as for any other. The read itself
%keeps the wrapper, which is what routes it to the gap door inside match/4.
metta_merged_match(Spaces, Pattern, Out) :-
    (   nonvar(Pattern),
        Pattern = '$metta_seq'(_, Declared)
    ->  Route = Declared
    ;   Route = Pattern
    ),
    (   metta_merge_route(Route, Policy)
    ->  metta_merged_match_(Policy, Spaces, Pattern, Out)
    ;   member(Space, Spaces),
        match(Space, Pattern, Out, Out)
    ).

metta_merged_match_(depth, Spaces, Pattern, Out) :-
    member(Space, Spaces),
    match(Space, Pattern, Out, Out).
metta_merged_match_(fair, Spaces, Pattern, Out) :-
    maplist(metta_match_engine(Pattern, Out), Spaces, Engines),
    setup_call_cleanup(true,
                       metta_round_robin(Engines, Pattern-Out),
                       maplist(metta_engine_done, Engines)).
metta_merged_match_('best-first', Spaces, Pattern, Out) :-
    forall(member(Space, Spaces),
           (   metta_emits(Space, 'best-first')
           ->  true
           ;   throw(error(metta_merge_unordered(Space, Pattern), none))
           )),
    maplist(metta_scored_engine(Pattern, Out), Spaces, Engines),
    setup_call_cleanup(true,
                       metta_best_merge(Engines, Pattern-Out),
                       maplist(metta_engine_done, Engines)).

metta_match_engine(Pattern, Out, Space, Engine) :-
    engine_create(Pattern-Out, match(Space, Pattern, Out, Out), Engine).

metta_scored_engine(Pattern, Out, Space, Engine) :-
    metta_algebra_one(Space, One),
    engine_create(K-(Pattern-Out),
                  ( b_setval('$metta_answer_k', One),
                    match(Space, Pattern, Out, Out),
                    b_getval('$metta_answer_k', K) ),
                  Engine).

metta_engine_done(Engine) :-
    catch(engine_destroy(Engine), _, true).

metta_round_robin([], _) :- fail.
metta_round_robin([Engine|Engines], Template) :-
    (   engine_next(Engine, Answer)
    ->  (   Answer = Template
        ;   append(Engines, [Engine], Rotated),
            metta_round_robin(Rotated, Template)
        )
    ;   metta_round_robin(Engines, Template)
    ).

%One lookahead per stream; deliver the best, refill that stream. Each
%stream is itself best-first by declaration, so the maximum of the
%lookaheads is the maximum of everything unseen.
metta_best_merge(Engines, Template) :-
    foldl(metta_prime_engine, Engines, [], Primed),
    metta_best_merge_(Primed, Template).

metta_prime_engine(Engine, Primed0, Primed) :-
    (   engine_next(Engine, Answer)
    ->  Primed = [Engine-Answer|Primed0]
    ;   Primed = Primed0
    ).

metta_best_merge_([], _) :- fail.
metta_best_merge_(Primed, Template) :-
    Primed = [_|_],
    foldl(metta_better_head, Primed, none, Engine-Best),
    selectchk(Engine-Best, Primed, Rest),
    Best = _-Answer0,
    (   Answer0 = Template
    ;   metta_prime_engine(Engine, Rest, Refilled),
        metta_best_merge_(Refilled, Template)
    ).

metta_better_head(Engine-(K-Answer), none, Engine-(K-Answer)) :- !.
metta_better_head(Engine-(K-Answer), _-(BestK-_), Engine-(K-Answer)) :-
    K @> BestK, !.
metta_better_head(_, Best, Best).

:- multifile prolog:error_message//1.
prolog:error_message(metta_merge_unordered(Ctx, Pattern)) -->
    [ 'a best-first merge over ~q needs every context emitting best \c
       first, and ~w declares no (emits ~w best-first): merging ordered \c
       streams is only sound when each stream is ordered'-[Pattern, Ctx,
                                                           Ctx] ].
