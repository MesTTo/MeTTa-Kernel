% Purpose: evaluate data terms and provide runtime helpers emitted by translated forms
% Assumes: engine/translator.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% Guarantees: lift_pattern_modifiers/4 answers whether a pattern carries a sequence variable from the walk it already makes, and a case arm with one compiles to the gap matcher [tested: tests/prolog/suites/translator/translator.plt:the_walk_reports_a_written_gap, tests/prolog/suites/reader/segments.plt; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb].
% Guarantees: result finality is read from the declaration set that governs
% the function's owning space [tested:
% lib_strategy:an_inherited_arrow_does_not_veto_a_local_definition;
% commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c].
% [tested: tests/prolog/suites/translator/translator.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%Convert let* to recursive let. The singleton case is the recursive one over
%an empty rest, and writing it out as a third clause made the predicate
%answer the SAME expansion twice: harmless where the compiler took the first
%solution, and two identical answers a call once letstar_runtime/3 below
%started backtracking into it.
letstar_to_rec_let([], Body, Body) :- !.
letstar_to_rec_let([[Pat,Val]|Rest],Body,[let,Pat,Val,Out]) :- letstar_to_rec_let(Rest,Body,Out).

%Pairs a form reads as syntax have ARRIVED when the list is proper and every
%element of it is a term rather than a variable. That is the shape a rewrite
%may read: below it there is a variable standing where the spine or a pair
%should be, and reading it would unify the rewrite's own pattern INTO the
%source instead of reading what is there.
arrived_pairs(Pairs) :- is_list(Pairs), maplist(nonvar, Pairs).

%The pairs have NOT arrived when such a variable is there, which is different
%from a term that is no list at all: the first can still arrive as a value,
%the second keeps falling through as it always has. is_list/1 alone cannot
%tell those two apart, and '$skip_list'/3 can, walking the spine once and
%reporting the tail without instantiating it, the way library(error) tells a
%partial list from a bad one [source 2026-08-19: SWI-Prolog 10.1.13
%/usr/lib/swi-prolog/library/error.pl:311-315, not_a_list/2, and :428-430,
%is_list_or_partial_list/1].
%'$skip_list'/3 has already settled the spine by the time the elements are
%looked at, so this walks it once more rather than through arrived_pairs/1,
%whose is_list/1 would walk it a third time to learn what Tail == [] just
%said.
unarrived_pairs(Pairs) :-
    '$skip_list'(_, Pairs, Tail),
    ( var(Tail) -> true
                 ; Tail == [], \+ maplist(nonvar, Pairs) ).

%The bindings when they were not syntax. `(= (mylet $bs $b) (let* $bs $b))`
%reaches translation with no bindings to rewrite and receives them as a VALUE
%instead, so they are rewritten when that value arrives, through the same
%letstar_to_rec_let/3 the written-out form uses. One definition therefore
%decides what let* means either way. The shape is case_runtime/3's, and so
%are the costs: one translation per call, growing with the bindings, against
%a flat cost for the same bindings written out
%[measured 2026-08-19: 3 inferences a call at both 2 and 16 written-out
%bindings; 62 and 370 for the same bindings handed over, min of 3 over a
%1,000-call slope; tested translator_letstar_computed_bindings].
%
%This reaches compiled bodies, so it is named in seam:engine_emitted/1
%above: without that, `(= (letstar_runtime $bs $b) ...)` would take the goal
%over inside its own space, silently and with a wrong answer rather than an
%error, because a space resolves a body's goals in its own module first
%[source: tests/prolog/static_checks.pl, the scan that reads the goals out of
%every equation the corpus compiles and fails on a capturable one that is not
%named].
letstar_runtime(Bindings, Body, Out) :-
    checked_pair_list('let*', 'a list of (pattern value) bindings', Bindings),
    letstar_to_rec_let(Bindings, Body, RecursiveLet),
    translate_expr_to_conj(RecursiveLet, Conj, Value),
    build_branch(Conj, Value, Out, Branch),
    current_metta_module(Module),
    call_goals_in_(Module, [Branch]).

% Constructs the goal for a single branch of an if-then-else/case.
build_branch(true, Val, Out, (Out = Val)) :- !.
%A variable-valued branch unifies with the output at RUNTIME, inside the
%branch. Unifying at translate time (Val = Out) is only sound when Val is
%private to the branch, and it is not when the branch's value is a clause
%parameter (an if arm of (let* (($c $a)) $a) collapses to the parameter $a):
%aliasing the head's output with the parameter makes the other arm's
%unification corrupt it, so the clause fails wherever that arm runs.
%merge_branch_returns/3 restores the translate-time binding afterwards,
%exactly where the whole clause proves it private.
build_branch(Con, Val, Out, (Con, Out = Val)) :- var(Val), !.
build_branch(Con, Val, Out, (Val = Out, Con)).

%Restore last-call optimization where it is safe: a branch ending with the
%runtime unification (Out = V) keeps a tail-recursive loop from running in
%constant stack, since the recursive call is no longer last. The first pass
%records each variable's total occurrences and first/last traversal positions.
%The second pass knows each branch's position interval, so two O(1) attribute
%reads prove that V is absent from the head, confined to this branch, and
%produced before the final unification. No branch re-scans the whole clause.
%
%THE STATS LIVE ON THE VARIABLES THEMSELVES, as attributes, not in an AVL.
%This pass runs on every compiled clause, and the specializer compiles clauses
%at RUN time, so its constant is a per-clause tax the whole corpus pays: on
%examples/ch05-equations-and-evaluation/05-02-changing-the-equations/04-specialize.metta
%the assoc spelling was 26,171 inferences of compare/3, insert and rebalance
%that put_attr/get_attr do in O(1) each -- 16.3% of the file's whole silent
%load [measured 2026-08-30, the assoc and attribute spellings on one tree].
%A cheaper spine scan skips the walks entirely for a straight-line body,
%which cannot hold a branch return at all.
%
%The attribute discipline, in one place. Head variables are MARKED (the
%atom `head`) in the same walk that used to build HeadStats, and a marked
%variable's body occurrences update nothing, which is exactly the old
%\+ get_assoc(V, HeadStats, _) exclusion one step earlier. Attributes are
%backtrackable, so a throw unwinds them with the trail. They are STRIPPED
%before the return bindings run: copy_term/2 copies attributes, and a later
%pass or the translation cache copying a body must not carry compiler
%scratch into a stored term; stripping first also means the V = Out below
%never fires the unify hook at all. The hook still exists and succeeds,
%because any unification against an attributed variable would otherwise
%fail into silent misbehaviour.
merge_branch_returns(Head, Body0, Body) :-
    (   mbr_control_spine_branches(Body0)
    ->  merge_branch_returns_walk(Head, Body0, Body)
    ;   Body = Body0
    ).

%The C analyzer rides beside the engine as mbr.c, compiled to mbr.so by
%engine/build.sh, and is consulted exactly the way parser.pl consults the C
%reader: artifact present and loadable, METTA_C_MBR=off keeps the Prolog
%pass, METTA_C_MBR=differential runs BOTH and throws on any disagreement,
%which is what the translator suite's generator fuzzer exercises. A C-side
%FAILURE (the variable-table cap, a malformed control node) falls back to
%the Prolog pass per clause, so the cap degrades to the specification
%rather than to a miscompile.
%shlib exists to load mbr.so; a refused shlib is the same absence as a
%missing artifact, parser.pl's own reasoning for its reader and writer.
:- catch(use_module(library(shlib)), _, true).
:- dynamic metta_c_mbr_active/0.
:- dynamic metta_mbr_artifact/1.
:- prolog_load_context(directory, MbrDir),
   directory_file_path(MbrDir, 'mbr.so', MbrSo),
   assertz(metta_mbr_artifact(MbrSo)).

%Keep the load in a named directive, matching parser.pl's reader and writer
%loaders. Besides making the artifact path inspectable, this preserves the
%activation step when translator.pl is served from translator.qlf; the former
%anonymous compound directive ran only while that QLF was compiled, leaving a
%later engine process on the Prolog fallback despite a present mbr.so [tested:
%swipl -q -g "ensure_loaded('engine/qlf_boot.pl'),ensure_loaded('engine/metta'),translator:metta_c_mbr_active,halt";
%commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
metta_try_load_c_mbr :-
   (   \+ getenv('METTA_C_MBR', off),
       metta_mbr_artifact(MbrSo),
       exists_file(MbrSo),
       catch(load_foreign_library(MbrSo), _, fail),
       current_predicate(metta_c_mbr_analyze/4)
   ->  assertz(metta_c_mbr_active)
   ;   metta_c_mbr_stub
   ).

%The stub keeps the foreign name defined for the engine's
%undefined-predicate gate when the artifact is absent, parser.pl's reader
%and writer arrangement; the metta_c_mbr_active/0 guard on the one caller
%makes it unreachable.
metta_c_mbr_stub :-
    (   current_predicate(metta_c_mbr_analyze/4)
    ->  true
    ;   assertz((metta_c_mbr_analyze(_, _, _, _) :- fail))
    ).

:- metta_try_load_c_mbr.

merge_branch_returns_walk(Head, Body0, Body) :-
    metta_c_mbr_active,
    (   getenv('METTA_C_MBR', differential)
    ->  merge_branch_returns_differential(Head, Body0, Body)
    ;   metta_c_mbr_analyze(Head, Body0, Body, Bindings),
        mbr_bind_returns(Bindings)
    ),
    !.
merge_branch_returns_walk(Head, Body0, Body) :-
    merge_branch_returns_prolog(Head, Body0, Body).

%Both passes on one clause, compared BEFORE either binding set runs, then
%the Prolog result carries: variance on the rewritten bodies and on the
%binding pairs is the whole contract.
merge_branch_returns_differential(Head, Body0, Body) :-
    metta_c_mbr_analyze(Head, Body0, CBody, CBindings),
    copy_term(Head-Body0, CopiedHead-CopiedBody0),
    merge_branch_returns_check(CopiedHead, CopiedBody0, PBody, PBindings),
    (   CBody-CBindings =@= PBody-PBindings
    ->  true
    ;   throw(error(metta_c_mbr_divergence(CBody-CBindings, PBody-PBindings),
                    context(merge_branch_returns/3, differential)))
    ),
    mbr_bind_returns(CBindings),
    Body = CBody.

%Only the control spine can hold a branch: mbr_goal/6 walks conjunctions and
%the three branch forms and nothing else, so anything deeper is data to it.
mbr_control_spine_branches(G) :- var(G), !, fail.
mbr_control_spine_branches((A , B)) :- !,
    ( mbr_control_spine_branches(A) -> true ; mbr_control_spine_branches(B) ).
mbr_control_spine_branches((_ ; _)).
mbr_control_spine_branches((_ -> _)).

merge_branch_returns_prolog(Head, Body0, Body) :-
    merge_branch_returns_check(Head, Body0, Body, Bindings),
    mbr_bind_returns(Bindings).

%The analysis half alone, bindings handed back unbound, so the differential
%can compare the two implementations' DECISIONS before either commits them.
merge_branch_returns_check(Head, Body0, Body, Bindings) :-
    mbr_mark_head(Head),
    mbr_collect_stats(Body0, 0, End),
    mbr_goal(Body0, 0, WalkEnd, Body, Bindings, []),
    WalkEnd =:= End,
    mbr_strip_attributes(Body0, Head).

attr_unify_hook(_, _).

mbr_mark_head(T) :-
    ( var(T) -> put_attr(T, translator, head)
    ; compound(T) -> functor(T, _, N), mbr_mark_head_args(1, N, T)
    ; true ).

mbr_mark_head_args(I, N, _) :- I > N, !.
mbr_mark_head_args(I, N, T) :-
    arg(I, T, Arg), mbr_mark_head(Arg), I1 is I + 1, mbr_mark_head_args(I1, N, T).

mbr_strip_attributes(Body, Head) :-
    term_variables(Body-Head, Vs),
    mbr_del_attrs(Vs).

mbr_del_attrs([]).
mbr_del_attrs([V|Vs]) :- ( var(V) -> del_attr(V, translator) ; true ), mbr_del_attrs(Vs).

%A variable goal is opaque and can only be walked as a term, which is what the
%catch-all clause at the bottom does. It needs saying here because a variable
%unifies with every control structure below: the conjunction clause bound it to
%a fresh (A , B) whose own left branch was again a variable, the cut committed,
%and the walk recursed on manufactured conjunctions forever. Reproduced
%2026-08-15: an unbound goal exceeded a depth limit of 3000 where `true`
%finishes at depth 2, and importing a library whose body held one exhausted the
%7.5Gb stack at 24,403,140 frames.
mbr_goal(Goal, P0, P, Goal, Bs, Bs) :- var(Goal), !,
    mbr_advance_term(Goal, P0, P).
mbr_goal((A , B), P0, P, (A1 , B1), Bs0, Bs) :- !,
    mbr_goal(A, P0, P1, A1, Bs0, Bs1),
    mbr_goal(B, P1, P, B1, Bs1, Bs).
mbr_goal((C -> T ; E), P0, P, (C -> T1 ; E1), Bs0, Bs) :- !,
    mbr_advance_term(C, P0, P1),
    mbr_branch(T, P1, P2, T1, Bs0, Bs1),
    mbr_branch(E, P2, P, E1, Bs1, Bs).
mbr_goal((A ; B), P0, P, (A1 ; B1), Bs0, Bs) :- !,
    mbr_branch(A, P0, P1, A1, Bs0, Bs1),
    mbr_branch(B, P1, P, B1, Bs1, Bs).
mbr_goal((C -> T), P0, P, (C -> T1), Bs0, Bs) :- !,
    mbr_advance_term(C, P0, P1),
    mbr_branch(T, P1, P, T1, Bs0, Bs).
mbr_goal(G, P0, P, G, Bs, Bs) :-
    mbr_advance_term(G, P0, P).

mbr_branch(B0, P0, P, B, Bs0, Bs) :-
    mbr_goal(B0, P0, P, B1, Bs0, Bs1),
    ( mbr_merge_candidate(B0, P0, P, V, Out)
      -> mbr_split(B1, B, _),
         Bs1 = [V-Out|Bs]
    ; B = B1,
      Bs1 = Bs ).

mbr_merge_candidate(B0, P0, P, V, Out) :-
    %An unbound arm is never a candidate, and asking mbr_split/3 about one
    %with the pattern pre-bound UNIFIED the arm with (Out = V) and walked the
    %manufactured structure to a 1.0Gb overflow; the C twin already answers
    %no-candidate for it, and this is what keeps the two agreeing
    %[tested: mbr_split_variable_arm:a_variable_branch_arm_is_walked_as_opaque].
    nonvar(B0),
    mbr_split(B0, _Prefix, (Out = V)),
    var(V),
    var(Out),
    V \== Out,
    get_attr(V, translator, var_stat(Count, First, Last)),
    Count > 1,
    First >= P0,
    Last < P.

mbr_bind_returns([]).
mbr_bind_returns([V-Out|Bindings]) :-
    V = Out,
    mbr_bind_returns(Bindings).

%Split a conjunction into everything-but-last and its last conjunct.
%The variable clause is FIRST for the reason mbr_goal/6's is: an unbound
%goal unifies with (A , B), binds itself to a fresh conjunction whose left
%is again unbound, and the walk manufactures conjunctions until the stack
%goes -- 1.0Gb measured from a probe using a raw variable as a branch arm
%[measured 2026-08-30; recorded in ai-tmp/codex-mbr-suite/ai-findings.md].
%It serves only the generic all-outputs mode; the candidate probe calls with
%its pattern PRE-BOUND and guards itself with nonvar/1 above, because this
%clause would otherwise bind the arm to the pattern.
mbr_split(G, true, G) :- var(G), !.
mbr_split((A , B), Prefix, Last) :- !,
    ( mbr_split(B, P1, Last), ( P1 == true -> Prefix = A ; Prefix = (A , P1) ) ).
mbr_split(G, true, G).

%Collect every variable's occurrence count and traversal interval in one
%pass. A head-marked variable keeps its mark and gathers no stats, which is
%the head exclusion; every variable still advances the position by one so
%the intervals the second pass reads are unchanged.
mbr_collect_stats(T, P0, P) :-
    ( var(T)
      -> ( get_attr(T, translator, S0)
           -> ( S0 = var_stat(Count0, First, _)
                -> Count is Count0 + 1,
                   put_attr(T, translator, var_stat(Count, First, P0))
              ; true )
         ; put_attr(T, translator, var_stat(1, P0, P0)) ),
         P is P0 + 1
    ; compound(T)
      -> functor(T, _, N),
         mbr_collect_stats_args(1, N, T, P0, P)
    ; P = P0 ).

mbr_collect_stats_args(I, N, _, P, P) :- I > N, !.
mbr_collect_stats_args(I, N, T, P0, P) :-
    arg(I, T, Arg),
    mbr_collect_stats(Arg, P0, P1),
    I1 is I + 1,
    mbr_collect_stats_args(I1, N, T, P1, P).

%Advance over the same depth-first variable positions without rebuilding the
%association. This pass also reconstructs only the control nodes it changes.
mbr_advance_term(T, P0, P) :-
    ( var(T) -> P is P0 + 1
    ; compound(T) -> functor(T, _, N), mbr_advance_args(1, N, T, P0, P)
    ; P = P0 ).

mbr_advance_args(I, N, _, P, P) :- I > N, !.
mbr_advance_args(I, N, T, P0, P) :-
    arg(I, T, Arg),
    mbr_advance_term(Arg, P0, P1),
    I1 is I + 1,
    mbr_advance_args(I1, N, T, P1, P).

%The Empty pair is the default branch, taken when the key answered nothing,
%so it is removed from the branches the key is matched against. Found stays
%unbound through the select: unifying ['Empty', _] in during the search would
%let an ordinary case pair of two variables be picked as the default.
case_default_pair(Cases, DefaultExpr, Rest) :-
    select(Found, Cases, Rest),
    subsumes_term(['Empty', _], Found),
    !,
    Found = ['Empty', DefaultExpr].

%Translate case expression recursively into nested if:
translate_case([], _, _, fail, []) :- !.
translate_case([[K,VExpr]|Rs], Kv, Out, Goal, KGo) :- translate_expr_to_conj(VExpr, ConV, VOut),
                                                      constrain_args(K, Kc, Gc, [], _, _, invert),
                                                      metta_pattern_match_goal(Kc, Kv, Decide),
                                                      build_branch(ConV, VOut, Out, Then),
                                                      ( Rs == [] -> Goal = (Decide -> Then), KGi=[]
                                                                  ; translate_case(Rs, Kv, Out, Next, KGi),
                                                                    Goal = (Decide -> Then ; Next) ),
                                                      append([Gc,KGi], KGo).

%What decides one case arm, and one let binding: the plain unification both
%have always emitted, or the gap matcher when the pattern the program WROTE
%carries a sequence variable. The parse and the fragment decision happen HERE,
%once, while the arm compiles [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?], so the emitted goal
%names its certificate and nothing re-classifies per candidate. The subject is
%the arm's KEY VALUE, which is data by the time it arrives and therefore
%carries no gap, so the case is one_sided by construction.
%
%The guard in front is nonvar/1 and =/2 alone, which SWI compiles inline: an
%arm whose pattern is a variable, which is what `case _` and every ordinary
%let bind, pays nothing at all for the question.
%
%A refusal becomes a goal that throws when the arm is REACHED rather than an
%error while the file loads, so an unreachable arm with a bad pattern does not
%stop a program that never asks it.
metta_pattern_match_goal(Pattern, Subject, Goal) :-
    (   nonvar(Pattern),
        Pattern = [_|_],
        metta_seq_present(Pattern)
    ->  metta_seq_plan(Pattern, Subject, Asked),
        Goal = metta_match_atoms(Asked, Subject)
    ;   Goal = (Subject = Pattern)
    ).

%The cases when they were not syntax. A case written inside a definition of
%its own, `(= (switch $v $cs) (case $v $cs))`, reaches translation with no
%branches to compile and receives them as a VALUE instead, so they compile
%when that value arrives, through the same translate_case/5 the written-out
%form uses. One definition therefore decides what a case means either way: a
%second interpreter for the same form would be a second set of answers to
%keep in step [tested: translator_case_computed_cases]. The shape is
%hyperpose_runtime/2's, and the costs are eval/2's: one translation per call,
%growing with the cases at 78, 258 and 498 inferences a call for 3, 12 and 24
%of them against a flat 3 for the same cases written out [measured
%2026-08-19, min of 3, per-call slope over 100 and 1,100 calls], plus the
%generated-lambda growth the header's Fails when records. A compiled-goal
%cache would answer both and is deliberately not here: it would need
%invalidation kept in step with the specializer's and lib_memo's, which is a
%larger problem than the one this path exists to solve, and writing the cases
%out already pays neither cost.
%
%Writing them out is otherwise untouched: byte-identical compiled output over
%twelve case shapes, with the classification paid once at COMPILE time
%[measured 2026-08-19: 71 to 78 inferences translating a three-case form,
%min of 5].
%
%This and case_default_runtime/2 reach compiled bodies, so both are named in
%seam:engine_emitted/1 above. Without that, `(= (case_runtime $k $cs) ...)`
%would take the goal over inside its own space, silently and with a wrong
%answer rather than an error, because a space resolves a body's goals in its
%own module first [source 2026-08-19: tests/prolog/static_checks.pl:685-692,
%the scan that reads the goals out of every equation the corpus compiles and
%fails on a capturable one that is not named].
case_runtime(KeyValue, Cases, Out) :-
    checked_pair_list(case, 'a list of (pattern value) cases', Cases),
    ( case_default_pair(Cases, _, NormalCases) -> true ; NormalCases = Cases ),
    translate_case(NormalCases, KeyValue, Out, CaseGoal, KeyGoals),
    append(KeyGoals, [CaseGoal], Runtime),
    current_metta_module(Module),
    call_goals_in_(Module, Runtime).

%switch's rows when they were not syntax, case_runtime/3's twin. It keeps the
%Empty pair in the list rather than lifting it out, which is the one difference
%between the two forms.
switch_runtime(KeyValue, Cases, Out) :-
    checked_pair_list(switch, 'a list of (pattern value) cases', Cases),
    translate_case(Cases, KeyValue, Out, CaseGoal, KeyGoals),
    append(KeyGoals, [CaseGoal], Runtime),
    current_metta_module(Module),
    call_goals_in_(Module, Runtime).

%The key answered nothing, so the Empty pair is the answer. Cases carrying no
%Empty answer nothing at all, which is what the compiled form says by having
%no else branch to build in that case.
case_default_runtime(Cases, Out) :-
    checked_pair_list(case, 'a list of (pattern value) cases', Cases),
    case_default_pair(Cases, DefaultExpr, _),
    translate_expr_to_conj(DefaultExpr, DefaultConj, DefaultValue),
    build_branch(DefaultConj, DefaultValue, Out, DefaultBranch),
    current_metta_module(Module),
    call_goals_in_(Module, [DefaultBranch]).

%Pairs arriving as a value are checked before they are compiled, because
%nothing downstream can. An unbound cases list is what `case` used to
%allocate 7.5 Gb on, and a pair that is not (pattern value) would unify with
%translate_case/5's or letstar_to_rec_let/3's own head and compile a branch
%or a binding the program never wrote. Said in MeTTa's vocabulary through
%throw_metta_type_error/3, so the message names the FORM and prints the value
%the way the program would have written it instead of naming a predicate of
%the engine's [tested: translator_case_open_cases,
%translator_letstar_unarrived_bindings].
%
%A type error rather than the instantiation error ISO asks for when the
%culprit is unbound [source 2026-08-19: SWI-Prolog 10.1 manual A.16,
%instantiation_error/1, "an argument is under-instantiated"]. What arrives
%here is a MeTTa VALUE, not a Prolog input argument, and MeTTa gives an
%unbound one the metatype Variable where a cases list is an Expression
%[measured 2026-08-19: !(get-metatype $x) answers Variable and
%!(get-metatype (1 one)) answers Expression], so the wrong metatype is
%exactly what happened and the message can say which. The bare ISO error
%says only that something somewhere was not instantiated, which is the
%complaint against the engine's other unbound-argument raises.
checked_pair_list(Form, Expected, Pairs) :-
    (   is_list(Pairs),
        forall(member(Pair, Pairs), subsumes_term([_, _], Pair))
    ->  true
    ;   throw_metta_type_error(Form, Expected, Pairs)
    ).

%Translate arguments recursively:
translate_args([], [], []).
translate_args([X|Xs], Goals, [V|Vs]) :-
    translate_args_dl([X|Xs], Goals, [], [V|Vs]).

translate_args_dl([], Goals, Goals, []).
translate_args_dl([X|Xs], Goals0, Goals, [V|Vs]) :-
    translate_eager_argument_dl(X, Goals0, AfterExpr, V),
    translate_args_dl(Xs, AfterExpr, Goals, Vs).

%Build A ; B ; C ... from a list:
disj_list([], fail) :- !.
disj_list([G], G) :- !.
disj_list([G|Gs], (G ; R)) :- disj_list(Gs, R).

%Build one disjunct per branch: (Conj, Out = Val). A literal Empty member
%is the branch remover and contributes no branch at all, minimal MeTTa's
%"is not returned among other results" applied where it is free; a
%COMPUTED Empty is pruned at the collapse aggregation instead.
build_superpose_branches([], _, []).
build_superpose_branches([E|Es], Out, Bs) :- E == 'Empty', !,
                                             build_superpose_branches(Es, Out, Bs).
build_superpose_branches([E|Es], Out, [B|Bs]) :- translate_expr_to_conj(E, Conj, Val),
                                                 build_branch(Conj, Val, Out, B),
                                                 build_superpose_branches(Es, Out, Bs).

%Build hyperpose branch as a goal list for concurrent_and/3 to consume:
build_hyperpose_branches([], []).
build_hyperpose_branches([E|Es], [(Goal, Res)|Bs]) :- translate_expr_to_conj(E, Goal, Res),
                                                      build_hyperpose_branches(Es, Bs).

%Never ask for more workers than there are branches. library(thread)'s jobs/2
%defaults the pool to the cpu_count flag and concurrent_and/3 creates that many
%workers plus a generator on EVERY call, so a three-branch hyperpose was
%creating 33 OS threads on this 32-core box regardless of its width
%[measured 2026-08-15: 30 three-branch calls created 990 threads; sizing to the
%branch count made it 120 and 11.6x faster on the same answers].
hyperpose_pool_size(BranchCount, Jobs) :-
    ( current_prolog_flag(cpu_count, Cores), integer(Cores), Cores > 0
      -> Jobs is max(1, min(BranchCount, Cores))
    ; Jobs is max(1, BranchCount) ).

%Run each branch under the module the TRANSLATOR wrote into this goal. Module
%is a compile-time literal here, so the worker's space context comes from the
%BRANCH and not from the thread that spawned it: SWI's globals are per-thread,
%a worker starts with this one unset, and inheriting the caller's thread state
%is exactly what a fork cannot do. Binding it from the goal's own argument is
%the same shape Java's ScopedValue gives a StructuredTaskScope fork and Go's
%context.Context gives a goroutine, both of which exist because thread-local
%state is not inherited [source: JEP 506; golang/go#21355, which rejected
%goroutine-local storage for this reason].
%
%The binding is the whole of it: no save, because a worker's context starts
%unset and the thread ends with the branch; and no validation, because the
%module came from the compiler rather than from a caller. b_setval/2 unwinds on
%backtracking, so a worker handed a second branch from another space binds its
%own. with_metta_module/2 did all three and cost 8 inferences in every worker.
%
%FAILS WHEN called anywhere but a concurrent_and/3 worker. Without the restore
%a deterministic success leaves the calling thread's context pointing at
%Module, which is free in a worker that is about to end and wrong in a thread
%that goes on to do something else. The one caller is the goal
%translate_special_dl/5 emits above, and every shipped hyperpose shape was
%measured for the leak and has none, because concurrent_and/3 runs the goal in
%a worker even at threads(1); calling this predicate directly does leak
%[measured 2026-08-21, all four shapes and the direct call].
%
%[measured 2026-08-21, min-of-3 on the engine's own counters, and the saving is
%per branch rather than per call, so it grows with the width the construct
%exists for: 1108 -> 1097, 1570 -> 1548, 2498 -> 2457, 4380 -> 4296 and
%8240 -> 8072 inferences at 1, 2, 4, 8 and 16 branches, a flat -10.5 each; the
%same collapse over superpose is unchanged at 1471]
%[tested: translator_hyperpose:test_a_hyperpose_worker_inherits_its_space_context_structurally].
%
%WHY THE CONTEXT IS NOT DERIVED FROM THE CALL SITE, which is what the survey
%expected and what was built and measured first. SWI hands a module_transparent
%predicate the module of the CLAUSE that called it, which is Logtalk's `This`;
%what a space context means is Logtalk's `Self`, the space the program is
%running in. They differ under inheritance, and this engine inherits: the
%prelude's `(= (atomically $expr) (transaction (eval $expr)))` is compiled into
%&self's module and shared by every space, so with eval/2 reading its call site
%`!(collapse (atomically (metta-three)))` in a named space answered
%((metta-three)) instead of ((1 2 3)) [measured 2026-08-21]. Logtalk threads
%both fields through every compiled clause for this exact reason
%(core.pl:25188); SWI's module system carries only the first, so Self stays in
%the global until a compiled clause carries it, which is P11.7's argument to
%add, not this row's.
hyperpose_branch(Module, Goal, Res, Out) :-
    b_setval('$metta_module', Module),
    call(Module:Goal), Out = Res.

%Runtime hyperpose path for variable/computed list arguments.
hyperpose_runtime(Exprs, Out) :-
    is_list(Exprs),
    current_metta_module(Module),
    length(Exprs, BranchCount),
    hyperpose_pool_size(BranchCount, Jobs),
    concurrent_and(member(Expr, Exprs),
                   eval_metta_in_module(Module, Expr, Out),
                   [threads(Jobs)]).

eval_metta_in_module(Module, Expr, Out) :-
    with_metta_module(Module,
                      ( translate_expr(Expr, Goals, Out),
                        call_goals_in_(Module, Goals) )).

%A minimal `eval` is one equality step, not the full result-type continuation
%used by an ordinary MeTTa call.  In particular, a `%Undefined%` equation
%whose RHS is another call returns that call as its staged result.  A function
%RHS is the one exception: the reference's `evalResult` opens that frame and
%runs it until `return` before reporting the step.
%
%The retained clauses are the source equations before their RHSs were
%compiled.  Reading them here therefore preserves the stage boundary without
%duplicating the equation compiler.  Segment heads use their existing
%one-sided matcher, and parsing the RHS before matching preserves contextual
%splicing after the captured run arrives.
%[source: MettaHyperonFull/Minimal/Interpreter.lean:420-448 and 3360-3380,
%`evalResult` and `queryOp`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
metta_minimal_equation_step(Module, [Fun|Args], Out) :-
    function_evaluation_active,
    atom(Fun),
    \+ metta_grounded_token(Fun),
    %The retained-equation door reads fun_meta rows, and a deferred
    %function has none until its equations translate: unforced, a function
    %frame decided NotReducible-with-no-equations where the arbiter's
    %protocol wants one equality step over the source equations.
    metta_ensure_compiled(Fun),
    fun_meta_module(Module, Fun, _),
    !,
    (   metta_minimal_equation_body(Module, Fun, Args, Body)
    *-> metta_minimal_equation_result(Module, Body, Out)
    ;   Out = '$metta_not_reducible'
    ).

metta_minimal_equation_body(Module, Fun, Args, Body) :-
    dispatch_meta_clauses(Module, Fun, Clauses),
    member(dispatch_clause(Head0, Body0, _), Clauses),
    copy_term(Head0-Body0, Head-Body1),
    %The flag first, because this runs PER CALL and the walk behind it is a
    %scan of the equation head. Safe to read at call time: the flag is set
    %when a segment equation is recorded, so a later definition turns the walk
    %back on for the calls after it. The compile-time askers of
    %metta_seq_present/1 are deliberately NOT gated -- a goal built while the
    %flag was false would be wrong once a segment equation arrived.
    (   metta_any_segment_equation,
        metta_seq_present(Head)
    ->  metta_seq_head_plan(Head, HeadPlan),
        metta_seq_body_plan(Body1, BodyPlan),
        metta_seq_head_match(HeadPlan, Args),
        metta_seq_instantiate(BodyPlan, Body)
    ;   Head = Args,
        Body = Body1
    ).

metta_minimal_equation_result(Module, [function, Body], Out) :-
    !,
    call(Module:'function'(Body, Out)).
metta_minimal_equation_result(_, Body, Body).

%Execute one compiled sequence-head equation.  The head plan and body plan
%share their Prolog variables, so matching a segment run also supplies both
%the ordinary expression projection and every RHS splice.  Pattern matching
%precedes head constraints, exactly as ordinary Prolog head unification
%precedes the goals compiled from in-place annotations [tested:
%tests/prolog/suites/reader/segment_equations.plt; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_segment_rule_result(Module, Fun, HeadPlan, BodyPlan, Args, Out) :-
    metta_seq_head_match(HeadPlan, Args),
    metta_segment_body_result(Module, Fun, BodyPlan, Out).

metta_segment_body_result(Module, _, compiled(Goals, Value), Out) :-
    call(Module:Goals),
    Out = Value.
metta_segment_body_result(Module, Fun, spliced(Prefix, Template), Out) :-
    call(Module:Prefix),
    metta_seq_instantiate(Template, Instantiated),
    with_metta_module(Module,
                      translator:metta_segment_spliced_result(Fun,
                                                               Instantiated,
                                                               Out)).

%A splice makes the final expression shape depend on the matched run, so that
%one body is translated after instantiation.  The same declared-result rule as
%an ordinary equation still decides whether the constructed expression is
%data or a computation [source: LeaTTa
%MettaHyperonFull/Core/SeqRuntime.lean:95-104 and
%MettaHyperonFull/Minimal/Interpreter.lean:3786-3799; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_segment_spliced_result(Fun, Instantiated, Out) :-
    (   declared_output_type(Fun, 'Atom'),
        \+ function_frame_body(Instantiated)
    ->  Out = Instantiated
    ;   current_metta_module(Module),
        eval_metta_in_module(Module, Instantiated, Out)
    ).

%Calls whose actual arity differs from the written marker-bearing head cannot
%name a Prolog predicate of that arity.  Retained equations supply the finite
%set of candidate heads; reversing the asserta/1 metadata restores source
%order, and the one-sided matcher supplies shortest-first splits within each
%rule [tested: tests/prolog/suites/reader/segment_equations.plt;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_segment_dispatch(Module, Fun, Args, Out) :-
    metta_any_segment_equation,
    fun_meta_module(Module, Fun, Owner),
    findall(Head0-Body0,
            ( fun_meta_clause(Owner, Fun, Head0, Body0),
              metta_seq_present(Head0) ),
            NewestFirst),
    reverse(NewestFirst, Clauses),
    member(Head0-Body0, Clauses),
    copy_term(Head0-Body0, Head-Body),
    with_metta_module(Module,
                      translator:( metta_seq_head_plan(Head, HeadPlan),
                                   translate_segment_body_plan(Fun, Body,
                                                               [], BodyPlan) )),
    metta_segment_rule_result(Module, Fun, HeadPlan, BodyPlan, Args, Out).

metta_segment_equation(Fun) :-
    current_metta_module(Module),
    metta_segment_equation_in(Module, Fun, _).

metta_segment_equation_in(Module, Fun, Owner) :-
    metta_any_segment_equation,
    fun_meta_module(Module, Fun, Owner),
    fun_meta_clause(Owner, Fun, Head, _),
    metta_seq_present(Head),
    !.

%THE MARKER IS PRIVATE, and its name is why. It used to be the symbol
%`NotReducible`, which a MeTTa program can WRITE: `(= (f $x) NotReducible)`
%then answered `(f q)` here, the retained call, where upstream answers the
%symbol the equation returned. Upstream has no NotReducible of any kind --
%grep its whole src/ and lib/ -- so the name was ours leaking into the
%program's own vocabulary [measured 2026-08-30: `!(c2-pl-nr q)` is
%`NotReducible` upstream and was `(c2-pl-nr q)` here; and
%`!(collapse (eval ()))` is `(())` upstream].
%
%`$metta_not_reducible` cannot collide, because MeTTa's reader takes `$` as
%the start of a VARIABLE -- `var_symbol(V,E0,E) --> "$", token(Cs)` -- so no
%source text can produce this symbol
%[source: PeTTa@ae66fa8 src/parser.pl:71].
%
%A normal application consumes the marker by retaining the call as written.
%`eval` installs the one root allowed to observe it, which is what lets a
%minimal-MeTTa `chain (eval ...)` distinguish an irreducible call from a value.
metta_application_result(Written, Produced, Out) :-
    metta_application_result(Written, Written, Produced, Out).

%The source call identifies the active eval frame; the runtime call preserves
%arguments that have already crossed their declared evaluation mask.  Those
%are different for `(f (+ 1 2))`: a function that returns NotReducible keeps
%`(f 3)`, while an explicit eval still recognizes the source `(f (+ 1 2))` as
%its root and exposes the marker to chain.
metta_application_result(Source, Runtime, Produced, Out) :-
    Produced == '$metta_not_reducible',
    !,
    (   Source = [Frame, _], nonvar(Frame), Frame == function
    ->  Out = '$metta_not_reducible'
    ;   nb_current('$metta_not_reducible_root', Root),
        Root == Source
    ->  Out = '$metta_not_reducible'
    ;   Out = Runtime
    ).
metta_application_result(_, _, Produced, Produced).

%The outer runnable consumes the marker too, but retains its own written
%boundary.  Thus `!(eval (f))` keeps `(eval (f))`, while the same eval nested
%in chain exposes the bare marker to the continuation.
%THE ORIENTATION OF A COST-ORDERED REWRITE, asked once at the boundary every
%evaluated call crosses.
%
%A bidirectional rule and the inverse it derives are one equation read both
%ways, so a step is applied only in the direction that strictly lowers the
%form's cost; engine/translator_rules.pl states the measure and its ground in
%ordered rewriting. The measure belongs to the rewrite RELATION rather than to
%any one door, and asking it door by door had already missed one: the derived
%inverse is installed as an ORDINARY equation, so it compiles to a clause of
%the produced head that a plain call reaches with no gate in between, and
%`(eval (twin 1 1))` answered `(unpack (wrap (box 1)))` -- rewriting UP --
%where the same call written in source answered itself
%[measured 2026-08-30; fixture=ai-tmp/petta-align/tr9.py].
%
%THE ASKER FOR EVERY PATH THAT ENDS HERE: eval, evalc, the flat Python door
%and its fast path all cross this boundary. reduce/3 is the one door that
%does NOT -- the translator compiles `(reduce X)` to a direct reduce/3 call
%whose answer feeds the caller with no boundary in between -- so reduce/3
%keeps its own gate at its two dispatch sites. Removing them on the belief
%that this boundary covered reduce let `!(test (reduce (twin 1 1))
%(twin 1 1))` answer `(unpack (wrap (box 1)))`, an up-rewrite, and the
%direction example's own probes are what caught it
%[tested: examples/ch20-extending-the-engine/20-01-translator-rules/02-translatorrule_direction.metta].
%The registered-predicate dispatch cost stays under the 30 the interface
%claims because THAT path never enters reduce/3's gated branches
%[tested: tests/prolog/suites/host/prolog_interface.plt:
%a_registered_predicate_costs_no_more_than_a_metta_function].
%
%A blocked step leaves the form in normal form, and a form no rewrite applies
%to evaluates to itself, which is the answer this predicate already gives for
%a call that did not reduce. So the orientation reuses that branch rather than
%adding an outcome. Failing instead was measured and is wrong: a compiled
%equation that does not apply has no answer by construction, so the decline
%took the rule's FORWARD direction down with it [measured 2026-08-30, same
%fixture: all four probes answered nothing].
%
%NOT SHORT-CIRCUITED ON A NON-COMPOUND RESULT, and the reason is worth leaving
%here because the shortcut looks free and is wrong. `compound(Produced)` in
%front costs nothing and halves this test's price, on the reasoning that a
%non-list form costs 1 while a written call `[Name|Args]` costs at least 2, so
%the measure would already be satisfied. It is not: a rule may DECLARE its
%head's cost, `translator_rule_declaration([cost, Cost], ...)`, and a declared
%0 makes `[Name, Arg]` cost 1, against which an atomic answer's 1 is not
%strictly less. The rewrite would then be let through where the measure blocks
%it, which is the one thing an ordered rewrite may not do
%[source: engine/translator_rules.pl, translator_form_cost/2 and the cost
%declaration]. One inference is not worth a hole in the termination argument.
%
%SWAPPED, not probed. Nearly every program registers no cost-ordered rule:
%no shipped library passes a direction declaration, so the table this gate
%asks is EMPTY in the shipping configuration, and asking an empty dynamic
%predicate is the most expensive spelling of "off" SWI offers: the miss costs
%2 inferences and about 420 instructions through clause selection, per
%boundary crossing, at 11 crossings per py-method-call
%[measured: 2/2/4/2 inferences and 11.216G/12.396G/15.416G/11.216G
% instructions:u per 10M calls for a static fast body, a 1-clause dynamic
% fast body, the inline empty-table gate and a compile_predicates body;
% command=swipl ai-tmp/door_cost_probe.pl and perf stat -e instructions:u
% swipl ai-tmp/door_instr_probe.pl <shape>; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
%So this door, metta_reduce_result/5 and metta_eval_step_orients/2 hold
%ONE clause each at a time,
%swapped between the fast bodies, which only answer the irreducible marker,
%and the gated bodies, which add the orientation test, the same way the fuel
%charge is compiled away while no budget is configured. The gated bodies are
%complete in BOTH states (an empty table lets every answer through), so the
%swap is a cost move, never a semantic one. metta_rule_gates_refresh/0
%derives the mode from the table itself, which makes a reload heal rather
%than stack clauses, and installs inside transaction/1 so a concurrent
%reader sees one body or the other and never none. The only two writers of
%the table, note_cost_ordered_rule/2 and forget_translator_rule/1, call it
%after every mutation. A 1-clause dynamic call costs the same 2 inferences
%as the static call it replaces and +142 instructions in-engine (11.681G
%against 10.258G per 10M door calls, the second number with
%compile_predicates([translator:metta_boundary_result/3]) applied to the
%same live door), against the -2 inferences and about -420 instructions the
%removed probe paid per crossing. compile_predicates is the recorded upgrade
%if a workload ever measures the dynamic door itself: it works on the live
%door, but re-swapping then needs abolish/1, whose moment of emptiness a
%concurrent crossing could observe, so the doors stay dynamic while the
%transition rail is retract-and-assert inside a transaction
%[measured 2026-08-30; command=perf stat -e instructions:u swipl
% ai-tmp/door_static_probe.pl <mode>; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
:- dynamic metta_boundary_result/3.
:- dynamic metta_reduce_result/5.
:- dynamic metta_eval_step_orients/2.
:- dynamic metta_rule_gate_mode/1.

%The third door, metta_eval_step_orients/2, guards the pre-translation
%equation step: a cost-ordered translator rule's equation IS the rewrite, so
%a retained equation applied by metta_eval_core has to pass the same
%orientation gate the call site applies. Without it the inverse a
%bidirectional declaration derives rewrote UP through eval while the same
%call written in source did not: `(collapse (eval (twin 1 1)))` answered
%`(unpack (wrap (box 1)))` against the source form's `(twin 1 1)`
%[measured 2026-08-30; fixture=ai-tmp/petta-align/tr8.py]. It runs once per
%equation-step ANSWER, which made its inline probe the largest of the three
%rule-free costs, so its fast body is a fact.
metta_rule_gate_bodies(fast,
    (metta_boundary_result(Written, Produced, Out) :-
        (   Produced == '$metta_not_reducible'
        ->  Out = Written
        ;   Out = Produced
        )),
    (metta_reduce_result(Name, Args, Produced, Out, Status) :-
        (   Produced == '$metta_not_reducible'
        ->  Out = [Name|Args], Status = 'not-reducible'
        ;   Out = Produced, Status = reduced
        )),
    metta_eval_step_orients(_, _)).
metta_rule_gate_bodies(gated,
    (metta_boundary_result(Written, Produced, Out) :-
        (   Produced == '$metta_not_reducible'
        ->  Out = Written
        ;   Written = [Name|Args],
            atom(Name),
            translator_rules:cost_ordered_translator_rule(Name),
            \+ translator_rules:translator_rule_dispatch_orients(Name, Args, Produced)
        ->  Out = Written
        ;   Out = Produced
        )),
    (metta_reduce_result(Name, Args, Produced, Out, Status) :-
        (   Produced == '$metta_not_reducible'
        ->  Out = [Name|Args], Status = 'not-reducible'
        ;   translator_rules:cost_ordered_translator_rule(Name),
            \+ translator_rules:translator_rule_dispatch_orients(Name, Args, Produced)
        ->  Out = [Name|Args], Status = 'not-reducible'
        ;   Out = Produced, Status = reduced
        )),
    (metta_eval_step_orients(C0, Step) :-
        (   nonvar(C0), C0 = [F|Args], atom(F)
        ->  translator_rules:translator_rule_dispatch_orients(F, Args, Step)
        ;   true
        ))).

%Boot loads this file before translator_rules (engine/metta.pl's
%ensure_loaded order), so the table module does not exist yet when the
%load-end initialization below runs; an absent table and an empty table
%both mean fast, which is what the catch encodes. Post-boot the two table
%writers call this after every mutation, and the load-end run also heals a
%RELOAD of this file while gated, whatever reconsult did to the doors'
%clauses, because the mode is re-derived from the table rather than trusted.
metta_rule_gates_refresh :-
    (   catch(translator_rules:cost_ordered_translator_rule(_),
              error(existence_error(_, _), _),
              fail)
    ->  Mode = gated
    ;   Mode = fast
    ),
    metta_rule_gates_ensure(Mode).

%The transition windows are closed by ORDER, not by a lock: registration
%installs the gated bodies BEFORE its table row lands (note_cost_ordered_rule
%calls this with gated, then asserts), and removal retracts the row before
%the refresh derives fast, so both windows run the gated bodies over an
%empty table, which answer exactly as the fast bodies do. A concurrent
%reader therefore never sees a registered rule through an ungated door.
metta_rule_gates_ensure(Mode) :-
    (   metta_rule_gate_mode(Mode)
    ->  true
    ;   metta_rule_gate_bodies(Mode, Boundary, Reduce, StepOrients),
        transaction((
            retractall(metta_rule_gate_mode(_)),
            retractall(metta_boundary_result(_, _, _)),
            retractall(metta_reduce_result(_, _, _, _, _)),
            retractall(metta_eval_step_orients(_, _)),
            assertz(Boundary),
            assertz(Reduce),
            assertz(StepOrients),
            assertz(metta_rule_gate_mode(Mode))
        ))
    ).

:- initialization(metta_rule_gates_refresh).

:- meta_predicate with_not_reducible_root(+, 0).

with_not_reducible_root(Root, Goal) :-
    setup_call_cleanup(
        install_not_reducible_root(Root, Saved),
        Goal,
        restore_not_reducible_root(Saved)).

install_not_reducible_root(Root, saved(Previous)) :-
    nb_current('$metta_not_reducible_root', Previous), !,
    nb_linkval('$metta_not_reducible_root', Root).
install_not_reducible_root(Root, none) :-
    nb_linkval('$metta_not_reducible_root', Root).

restore_not_reducible_root(saved(Previous)) :- !,
    nb_linkval('$metta_not_reducible_root', Previous).
restore_not_reducible_root(none) :-
    nb_delete('$metta_not_reducible_root').

%A function frame, unlike ordinary full evaluation, recognizes `(return X)`
%before the return form's polymorphic declaration can evaluate X.  The flag is
%scoped over both runtime translation and execution: a chain can produce the
%return form several goals after it was compiled, and the frame must still be
%active when that continuation arrives.
metta_function_eval(Current, Next) :-
    metta_function_eval(Current, Next, _).

metta_function_eval(Current, Next, Status) :-
    setup_call_cleanup(
        install_function_evaluation(Saved),
        metta_function_eval_status(Current, Next, Status),
        restore_function_evaluation(Saved)).

%A successful equality step that RETURNS the bare marker is different from a
%query with no applicable equality.  metta_eval_step/2 intentionally presents
%both as the marker to chain, so function asks the retained-equation door first
%and carries this one bit of provenance into its frame loop.
metta_function_eval_status(Current, Next, Status) :-
    current_metta_module(Module),
    ( metta_minimal_equation_step(Module, Current, Step)
    *-> Next = Step,
        Status = reduced
    ;   metta_eval_step(Current, Next),
        ( Next == '$metta_not_reducible'
        -> Status = 'not-reducible'
        ;  Status = reduced
        )
    ).

install_function_evaluation(saved(Previous)) :-
    nb_current('$metta_function_evaluation', Previous), !,
    nb_setval('$metta_function_evaluation', true).
install_function_evaluation(none) :-
    nb_setval('$metta_function_evaluation', true).

restore_function_evaluation(saved(Previous)) :- !,
    nb_setval('$metta_function_evaluation', Previous).
restore_function_evaluation(none) :-
    nb_delete('$metta_function_evaluation').

function_evaluation_active :-
    nb_current('$metta_function_evaluation', true).

%Run the one reflected instruction handed to chain.  eval and evalc expose
%their raw control result here; translating the whole `(eval X)` term through
%the ordinary expression door would consume NotReducible at eval's own
%application boundary before chain could inspect it.  A value that arrived
%through chain's Atom parameter may reveal its head only at run time, so this
%recognizer also covers that dynamic door.
metta_chain_step([eval, Arg], Out) :- !,
    metta_eval_step(Arg, Out).
metta_chain_step([evalc, Arg, Space], Out) :- !,
    metta_evalc_step(Arg, Space, Out).
metta_chain_step(Nested, Out) :-
    embedded_operation(Nested),
    !,
    current_metta_module(Module),
    eval_metta_in_module(Module, Nested, Out).
metta_chain_step(Nested, Nested).

%A bare symbol is reduced only in value positions.  Scalar equality rules are
%stored in the atomspace rather than compiled as predicates, so the ordinary
%expression translator cannot see them.  Follow those rules to a fixpoint for
%an eager argument, preserving every nondeterministic right-hand side.
metta_evaluate_symbol(Symbol, Out) :-
    metta_evaluate_symbol(Symbol, [], Out).

metta_evaluate_symbol(Symbol, Seen, Out) :-
    (   memberchk_eq(Symbol, Seen)
    ->  Out = Symbol
    ;   current_metta_space(Space),
        (   match(Space, [=, Symbol, Body], Body, Body)
        *-> metta_evaluate_symbol_body(Body, [Symbol|Seen], Out)
        ;   Out = Symbol
        )
    ).

metta_evaluate_symbol_body(Body, Seen, Out) :-
    (   atom(Body)
    ->  metta_evaluate_symbol(Body, Seen, Out)
    ;   current_metta_module(Module),
        eval_metta_in_module(Module, Body, Produced),
        metta_application_result(Body, Produced, Out)
    ).

%Runtime twin of an eager argument translation.  It is used when a source
%variable may arrive as either a scalar rewrite or an expression; literals
%that cannot reduce pass through unchanged.
metta_evaluate_argument(Value, Out) :-
    (   var(Value)
    ->  Out = Value
    ;   atom(Value)
    ->  metta_evaluate_symbol(Value, Out)
    ;   is_list(Value)
    ->  current_metta_module(Module),
        eval_metta_in_module(Module, Value, Produced),
        metta_application_result(Value, Produced, Out)
    ;   Out = Value
    ).

%A VARIABLE argument is passed through, never re-evaluated at run time.
%Upstream decides evaluation while compiling the WRITTEN argument, and a
%variable translates to itself with no goal at all
%[source: PeTTa@ae66fa8 src/translator.pl:58,
%`translate_expr(X, [], X) :- ((var(X) ; atomic(X)) ; X = partial(_,_)), !.`].
%
%This carried a second branch until 2026-08-30: a head variable occurring only
%in held positions was marked, and a later unmasked use emitted
%metta_evaluate_argument/2 to perform the evaluation the mask had deferred.
%That is observable and it differed: with `(: passthru (-> Atom %Undefined%))`
%and `(= (passthru $b) (subtraction-atom $b (2)))`,
%`(passthru ((+ 1 1)))` answered `()` here and `((+ 1 1))` upstream, because
%the deferred evaluation turned the held `((+ 1 1))` into `(2)` before the
%subtraction saw it [measured 2026-08-30, ai-tmp/pass.metta under both
%engines]. It also costs a goal per such argument, which the passthrough does
%not.
translate_eager_argument_dl(X, Goals0, Goals, V) :-
    (   var(X)
    ->  V = X,
        Goals0 = Goals
    ;   atom(X)
    ->  (   metta_symbol_has_rule(X)
        ->  Goals0 = [metta_evaluate_symbol(X, V)|Goals]
        ;   V = X,
            Goals0 = Goals
        )
    ;   translate_expr_dl(X, Goals0, Goals, V)
    ).

%A literal without a scalar equation is already a value.  Settling that at
%translation time keeps the ordinary symbol path goal-free; adding or removing
%a scalar equation announces the same support-node change as a function, so a
%stored caller and the runnable cache are rebuilt before this decision can go
%stale [tested: conformance2:symbol_arguments_evaluate_for_declared_and_undeclared_functions;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_symbol_has_rule(Symbol) :-
    once(metta_symbol_step(Symbol, _)).

%`eval` applies one scalar equality rule.  It deliberately does not follow a
%symbol chain or evaluate an expression on the right: those are subsequent
%minimal steps and a surrounding full-evaluation context may perform them.
metta_symbol_step(Symbol, Out) :-
    current_metta_space(Space),
    match(Space, [=, Symbol, Body], Body, Out).

metta_eval_root_result(Module, Written, Produced, Out) :-
    (   Produced == '$metta_not_reducible'
    ->  Out = Produced
    ;   Written = [_|_],
        \+ metta_reducible_head(Module, Written)
    ->  Out = '$metta_not_reducible'
    ;   Out = Produced
    ).


%A call whose head arrived only at run time must be retranslated with its
%arguments still written.  The resolved head's declared mask then makes the
%same decisions as a source-written call.
%The two halves of the compiled dynamic-call branch.  The mask test asks the
%same two questions the compile-time classifier asks -- a registered builtin
%mask or any masking chain on a user function -- so a resolved head that
%holds arguments back gets the written tail, and every other head gets the
%call site's own precompiled argument goals.
metta_dynamic_head_masks(Head) :-
    atom(Head),
    (   builtin_call_mask(Head, _)
    ->  true
    ;   call_site_type_chains(Head, Chains),
        member(Chain, Chains),
        chain_masks_an_argument(Chain)
    ->  true
    ;   fail
    ).

%Dispatch on finished values: the site's compiled goals already evaluated
%the tail, so this mirrors metta_dynamic_call/3 minus every runtime
%translation.  The written tail still names the source call for the
%application boundary, the same Source/Runtime split the translated path
%keeps.
metta_dynamic_value_call(Head, Written, Values, Out) :-
    (   nonvar(Head), atom(Head)
    ->  (   head_has_dynamic_meaning(Head)
        ->  current_metta_module(Module),
            reduce_in_module(Module, [Head|Values], Produced),
            metta_application_result([Head|Written], [Head|Values],
                                     Produced, Out)
        ;   Out = [Head|Values]
        )
    ;   nonvar(Head), atomic(Head)
    ->  (   seam:grounded_apply(Head, Values, Applied)
        ->  Out = Applied
        ;   Out = [Head|Values]
        )
    ;   nonvar(Head)
    ->  current_metta_module(Module),
        reduce_in_module(Module, [Head|Values], Produced),
        metta_application_result([Head|Written], [Head|Values],
                                 Produced, Out)
    ;   Out = [Head|Values]
    ).

head_has_dynamic_meaning(Head) :-
    current_metta_module(Module),
    head_meaning_route(Module, Head, _).

reduce_in_module(Module, Call, Produced) :-
    with_metta_module(Module, reduce(Call, Produced, _)).

metta_dynamic_call(Head, Args, Out) :-
    (   nonvar(Head), atom(Head)
    ->  current_metta_module(Module),
        %Ask both questions before paying for evaluation: a symbol head with
        %meaning (equations, a builtin, a special form, or a translator rule)
        %takes the full evaluator, exactly as a written call would; a symbol
        %head WITHOUT meaning builds data, exactly as the compile-time data
        %branch does for a known symbol head.  An equation body like
        %`($_2 ___ $_3 ...)` reaches here once per state expansion in a
        %search, and full evaluation of the data answer cost tilepuzzle
        %181,441 states at evaluator prices: 3.4s of search became minutes
        %with every answer identical.
        (   head_meaning_route(Module, Head, _)
        ->  eval_metta_in_module(Module, [Head|Args], Produced),
            metta_application_result([Head|Args], Produced, Out)
        ;   translate_args(Args, Goals, Values),
            call_goals_in_(Module, Goals),
            Out = [Head|Values]
        )
    ;   nonvar(Head), atomic(Head)
    ->  translate_args(Args, Goals, Values),
        current_metta_module(Module),
        call_goals_in_(Module, Goals),
        (   seam:grounded_apply(Head, Values, Applied)
        ->  Out = Applied
        ;   Out = [Head|Values]
        )
    ;   nonvar(Head)
    ->  translate_args(Args, Goals, Values),
        current_metta_module(Module),
        call_goals_in_(Module, Goals),
        reduce([Head|Values], Produced, _),
        metta_application_result([Head|Args], [Head|Values], Produced, Out)
    ;   translate_args(Args, Goals, Values),
        current_metta_module(Module),
        call_goals_in_(Module, Goals),
        Out = [Head|Values]
    ).

%A collapse operand supplied through a masked variable is syntax only while
%the enclosing equation compiles.  Evaluate the value that arrives, then
%collect exactly the same alternatives as a written operand.
collapse_runtime(Expr, Out) :-
    current_metta_module(Module),
    findall(Value,
            ( eval_metta_in_module(Module, Expr, Produced),
              metta_boundary_result(Expr, Produced, Value) ),
            All),
    metta_prune_empty(All, Out).

%THE RESULT HALF of the arbiter's typed dispatch. A call whose declared result
%is the metatype `Atom` answers AS PRODUCED and stops; every other declared
%result re-enters evaluation:
%
%    declaredTypeForEvaluation declared == Atom
%
%is the whole test [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:
%3786-3799, `returnsAtom`, applied at :7454-7456 and :7520-7523]. The source
%self-interpreter states the same rule and names the two views that re-enter,
%mapping `Expression` onto `%Undefined%` before comparing
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:4370-4381,
%`interpret-result-type`].
%
%WHY IT MATTERS ONLY AFTER A MASKED CALL. Before the evaluation mask reached
%written builtin calls, every operand a call received had already been reduced,
%so its result was in normal form and re-entering evaluation was the identity.
%A masked operand is the one way an unreduced subterm reaches a result, which
%is what `!(car-atom ((+ 1 2) b))` shows: the arbiter holds the operand back,
%car-atom hands out `(+ 1 2)`, and the `%Undefined%` result is what turns it
%into 3 [measured 2026-08-24 against LeaTTa 9ea9f9d, both engines answering 3
%by different routes before this and by the same route after].
%
%The reducibility test comes first and is what keeps the walk off the ordinary
%path: a result with no redex in it is answered unchanged without compiling
%anything.
metta_masked_result(Value, Out) :-
    (   metta_result_reducible(Value)
    ->  current_metta_module(Module),
        eval_metta_in_module(Module, Value, Out)
    ;   Out = Value
    ).

%A term holds a redex when it is an application of a known function, or when
%any member of it does: tuple-member evaluation is what makes the second case
%observable, and the arbiter answers `(3)` for `!(car-atom (((+ 1 2)) b))`
%exactly because of it [measured 2026-08-24].
%
%An empty list and a non-list answer false in one indexed step, so a scalar
%result, which is most of them, costs a single call.
%nonvar/1 before the list test, and the tail walk refuses to look past an
%unbound tail: both are what stop the test BINDING the term it is inspecting. A
%bare variable unifies with `[Head|_]`, and a partial list's tail unifies with
%the walk's own head, either of which would turn a read into a write.
metta_result_reducible(Term) :-
    nonvar(Term),
    Term = [Head|_],
    (   atom(Head),
        fun_here(Head)
    ->  true
    ;   reducible_member(Term)
    ).

reducible_member([Head|Tail]) :-
    (   metta_result_reducible(Head)
    ->  true
    ;   nonvar(Tail),
        reducible_member(Tail)
    ).

%Compile Params and Body into a closure predicate and give back a Prolog
%callable that takes the body's own arguments after the captured ones. This is
%'|->' itself, which already names the predicate, captures the free variables
%and registers the arity; the difference-list arguments are the same variable
%because a lambda contributes no runtime goals of its own.
collection_closure(Params, Body, Closure) :-
    translate_special_dl('|->', [Params, Body], Tail, Tail, Lambda),
    (   Lambda = partial(Function, Captured)
    ->  Closure =.. [Function|Captured]
    ;   Closure = Lambda
    ).

%include/3's test for filter-atom. The condition's VALUE decides, so unify it
%with true rather than calling it. Calling it is what the yall version did, and
%(filter-atom (1 2 3) $x 42) then died with "callable expected, found (, true
%42)" where the same filter written (filter-atom (1 2 3) notbool) answered ().
%Unifying is also what the builtin 'filter-atom'/3 in metta.pl has always done.
metta_condition_holds(Closure, Item) :- call(Closure, Item, true).
%Declared meta so the lambda survives the hop through here. include/3 qualifies
%its own closure argument, which reaches this predicate's clause in the calling
%module, but Closure inside the clause is then a bare atom and call/3 resolves
%it in `user`. maplist/3 and foldl/4 never showed this because library(apply)
%declares them meta and this predicate is the only hand-written link in the
%chain: with the lambda in the space's module, filter-atom raised
%`metta_condition_holds/2: Unknown procedure: lambda_3/2` where map-atom and
%foldl-atom over the same lambda answered
%[tested: translator_lambda_space_scope]. Free: 10,013 inferences either way
%for a compiled filter-atom over 2,000 elements [measured 2026-08-16].
:- meta_predicate metta_condition_holds(2, ?).
%(:= X) inside a match pattern is the match-by-EQUALITY modifier: the atom
%matches only where it is already identical to X, so a free variable does not
%match it. lib/minimal_metta_lib/minimal_metta_lib.pl has implemented it for unify-mod all along
%and the engine's own match/4 did not know it, so the same modifier meant two
%different things depending on which matcher read it.
%
%Lifted at COMPILE time rather than taught to match/4, and that is the whole
%design. The modifier position is replaced by a fresh variable, so the space
%read keeps its ordinary shape and its clause indexing, and the equality is
%emitted as a ==/2 goal after the match. A pattern with no modifier in it
%produces no guards and an unchanged pattern. Only expression lists can denote
%a modifier; trying the ownership seam on leaf atoms added a fixed preparation
%tax without making a meaningful modifier possible [measured: query-2k-rows
%minimum 561467 versus 601709 on 2026-08-21 before leaf calls and per-row
%empty modifier
%calls were removed; command=python bench.py query-2k-rows --counter-only;
%fixture=20 queries over 2000 rows;
%commit=b54ecaaa1224eabb90f808275003cd9abeef8065]. Engine-compiled match/4
%pays nothing per row because this walk happens once while its call site compiles.
%
%That also matches what the modifier means. The reference states that the
%guard "does not receive the match state, so bindings accumulated earlier in
%the same match cannot affect it", which is exactly a ==/2 over the operand as
%written [source: LeaTTa/MettaHyperonFull/Proofs/Modifiers.lean, the checked
%matcher's modifier law].
%
%THE ARITY GATE IS COPIED, NOT INVENTED. The reference recognises a modifier
%only at `Atom.expr [Atom.sym s, x]`, exactly two elements
%[source: LeaTTa/MettaHyperonFull/Core/Modifiers.lean, registeredMod?], and
%the reason is in this repository too: examples/ch20-extending-the-engine/20-02-metta-written-in-metta/04-minimal_metta.metta
%asserts that the THREE-element (:= a b) is ordinary data and matches the
%pattern (:= $x $y) structurally. Recognising := by name alone would
%reinterpret it [tested: translator_match_modifiers].
%GAPS RIDE THIS WALK, and that is the whole reason the fourth argument exists.
%A sequence variable changes a pattern's ARITY, so the match door has to know
%about one before it builds a candidate head, and a walk of its own would cost
%what this walk already spends: the same visit to every child, once per
%compiled call site and once per host query. The test below is written from
%nonvar/1, =/2 and ==/2 alone, which SWI compiles inline and does not count as
%inferences, so a pattern with no gap pays exactly nothing for the question
%[measured 2026-08-24: 100,000 calls of a clause carrying three such guards
%cost 400,002 inferences against 400,003 for a clause carrying none].
%
%Only an ITEM is tested, never the enclosing list, because the root of a side
%is never a gap [source: LeaTTa MettaHyperonFull/Core/SeqSyntax.lean,
%parseSeqAtom]. The recogniser is engine/spaces/segment_matching.pl's
%metta_seq_surface_gap/3 written out: a call there would be one inference per
%child on the hottest compile-time walk the translator has.
lift_pattern_modifiers(Pattern, Lifted, Guards, Segments) :-
    lift_pattern_modifiers_(Pattern, Lifted, Guards, [], false, Segments).

lift_pattern_modifiers_(Pattern, Lifted, Guards0, Guards, Seen0, Seen) :-
    (   nonvar(Pattern), Pattern = [_|_]
    ->  (   seam:pattern_modifier(Pattern, Lifted, Guard)
        ->  Guards0 = [Guard|Guards], Seen = Seen0
        ;   lift_pattern_modifiers_list(Pattern, Lifted, Guards0, Guards, Seen0,
                                        Seen)
        )
    ;   Lifted = Pattern,
        Guards0 = Guards,
        Seen = Seen0
    ).

lift_pattern_modifiers_list([], [], Guards, Guards, Seen, Seen).
lift_pattern_modifiers_list([Item|Rest], [Lifted|LiftedRest], Guards0, Guards,
                            Seen0, Seen) :-
    (   nonvar(Item),
        (   Item == '...'
        ->  true
        ;   Item = [Marker, Named],
            nonvar(Marker),
            Marker == ':seg',
            var(Named)
        )
    ->  Carried = true
    ;   Carried = Seen0
    ),
    lift_pattern_modifiers_(Item, Lifted, Guards0, Guards1, Carried, Seen1),
    lift_pattern_modifiers_list(Rest, LiftedRest, Guards1, Guards, Seen1, Seen).

%The modifier a pattern position can carry, replaced by a fresh variable and a
%guard over it. `(:= X)` matches by EQUALITY, so a free variable does not
%match it.
%
%`(: $x T)` was a second one until 2026-08-30, restricting a match position by
%type. Upstream reads a colon pattern as ordinary structure, and the two
%disagree: with `(knows Ann Bob)` stored and Ann and Bob declared Person,
%`(match &self (knows (: $x Person) (: $y Person)) ($x $y))` answers nothing
%upstream and `((Ann Bob))` under the modifier
%[measured 2026-08-30 against PeTTa@ae66fa8]. It is gone with the head half,
%for the reason recorded above constrain_args/7.
%
%Every clause of this open ownership seam, the one below and a provider's own,
%takes a LIST, so SWI's first-argument index already separates it from nothing
%and the marker is what discriminates. The marker is therefore COMPARED rather
%than unified, which costs one nonvar and one == per clause tried, at
%compile time and never per match.
seam:pattern_modifier([Assign, Wanted], Fresh, Fresh == Wanted) :-
    %The marker is read the way colon_expression/1 reads its own, nonvar then
    %==, because a LITERAL in the head unifies with an unbound head instead of
    %rejecting it: a two-element pattern whose head is a variable, (match &s
    %($A $B) ...), unified $A with ':=' and compiled as the equality modifier,
    %so the query answered nothing and $A silently became ':=' in the template
    %[measured 2026-08-21: hypothesis's SpaceStateMachine drew (() ()) against
    %($A ()); every arity but two matches, and match/4 itself answers].
    nonvar(Assign), Assign == ':=',
    !.

%Like membercheck but with direct equality rather than unification
memberchk_eq(V, [H|T]) :- ( V == H -> true ; memberchk_eq(V, T) ).

%Generate a readable lambda name. The counter has to be process-wide: SWI
%global variables are thread-local, so a counter kept in one gave every
%hyperpose worker its own sequence starting at 1, and two threads compiling a
%lambda both produced lambda_1. assertz then added the second body to the first
%lambda's predicate rather than defining a new one, and one lambda answered
%with every colliding branch's result. gensym/2 counts in a process-wide flag
%and is the same generator filereader.pl already uses for load ids.
next_lambda_name(Name) :- gensym(lambda_, Name).

declared_output_type(F, OutType) :- atom(F),
									nonvar(OutType),
									catch_recover(
									    governing_type_declaration(F, TypeChain), fail),
									TypeChain = [->|Types],
									append(_, [DeclaredOutType], Types),
									declared_type_for_evaluation(DeclaredOutType, View),
									View == OutType.

declared_type_for_evaluation(Type, View) :-
    ( type_position_modifier(Type, Metatype, _) -> View = Metatype ; View = Type ).
