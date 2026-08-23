% Purpose: evaluate data terms and provide runtime helpers emitted by translated forms
% Assumes: engine/translator.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/translator.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%Handle data list:
eval_data_term_dl(X, Goals, Goals, X) :- (var(X); atomic(X)), !.
eval_data_term_dl([F|As], Goals0, Goals, Val) :-
    ( atom(F), fun_here(F) -> translate_expr_dl([F|As], Goals0, Goals, Val)
                           ; eval_data_list_dl([F|As], Goals0, Goals, Val) ).

%Handle data list entry:
eval_data_list_dl([], Goals, Goals, []).
eval_data_list_dl([E|Es], Goals0, Goals, [V|Vs]) :-
    ( is_list(E) -> eval_data_term_dl(E, Goals0, AfterEntry, V)
                 ; V = E, AfterEntry = Goals0 ),
    eval_data_list_dl(Es, AfterEntry, Goals, Vs).

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
%The second pass knows each branch's position interval, so two AVL lookups prove
%that V is absent from the head, confined to this branch, and produced before
%the final unification. No branch re-scans the whole clause.
%
%Unbound variables are valid assoc keys while their standard-order relation is
%unchanged. All return bindings are therefore delayed until every lookup has
%finished: https://www.swi-prolog.org/pldoc/doc/_SWI_/library/assoc.pl
merge_branch_returns(Head, Body0, Body) :-
    empty_assoc(Empty),
    mbr_collect_stats(Head, 0, _HeadEnd, Empty, HeadStats),
    mbr_collect_stats(Body0, 0, End, Empty, Stats),
    mbr_goal(Body0, HeadStats, Stats, 0, WalkEnd, Body, Bindings, []),
    WalkEnd =:= End,
    mbr_bind_returns(Bindings).

%A variable goal is opaque and can only be walked as a term, which is what the
%catch-all clause at the bottom does. It needs saying here because a variable
%unifies with every control structure below: the conjunction clause bound it to
%a fresh (A , B) whose own left branch was again a variable, the cut committed,
%and the walk recursed on manufactured conjunctions forever. Reproduced
%2026-08-15: an unbound goal exceeded a depth limit of 3000 where `true`
%finishes at depth 2, and importing a library whose body held one exhausted the
%7.5Gb stack at 24,403,140 frames.
mbr_goal(Goal, _, _, P0, P, Goal, Bs, Bs) :- var(Goal), !,
    mbr_advance_term(Goal, P0, P).
mbr_goal((A , B), H, Stats, P0, P, (A1 , B1), Bs0, Bs) :- !,
    mbr_goal(A, H, Stats, P0, P1, A1, Bs0, Bs1),
    mbr_goal(B, H, Stats, P1, P, B1, Bs1, Bs).
mbr_goal((C -> T ; E), H, Stats, P0, P, (C -> T1 ; E1), Bs0, Bs) :- !,
    mbr_advance_term(C, P0, P1),
    mbr_branch(T, H, Stats, P1, P2, T1, Bs0, Bs1),
    mbr_branch(E, H, Stats, P2, P, E1, Bs1, Bs).
mbr_goal((A ; B), H, Stats, P0, P, (A1 ; B1), Bs0, Bs) :- !,
    mbr_branch(A, H, Stats, P0, P1, A1, Bs0, Bs1),
    mbr_branch(B, H, Stats, P1, P, B1, Bs1, Bs).
mbr_goal((C -> T), H, Stats, P0, P, (C -> T1), Bs0, Bs) :- !,
    mbr_advance_term(C, P0, P1),
    mbr_branch(T, H, Stats, P1, P, T1, Bs0, Bs).
mbr_goal(G, _, _, P0, P, G, Bs, Bs) :-
    mbr_advance_term(G, P0, P).

mbr_branch(B0, H, Stats, P0, P, B, Bs0, Bs) :-
    mbr_goal(B0, H, Stats, P0, P, B1, Bs0, Bs1),
    ( mbr_merge_candidate(B0, H, Stats, P0, P, V, Out)
      -> mbr_split(B1, B, _),
         Bs1 = [V-Out|Bs]
    ; B = B1,
      Bs1 = Bs ).

mbr_merge_candidate(B0, HeadStats, Stats, P0, P, V, Out) :-
    mbr_split(B0, _Prefix, (Out = V)),
    var(V),
    var(Out),
    V \== Out,
    \+ get_assoc(V, HeadStats, _),
    get_assoc(V, Stats, var_stat(Count, First, Last)),
    Count > 1,
    First >= P0,
    Last < P.

mbr_bind_returns([]).
mbr_bind_returns([V-Out|Bindings]) :-
    V = Out,
    mbr_bind_returns(Bindings).

%Split a conjunction into everything-but-last and its last conjunct:
mbr_split((A , B), Prefix, Last) :- !,
    ( mbr_split(B, P1, Last), ( P1 == true -> Prefix = A ; Prefix = (A , P1) ) ).
mbr_split(G, true, G).

%Collect every variable's occurrence count and traversal interval in one pass.
mbr_collect_stats(T, P0, P, Stats0, Stats) :-
    ( var(T)
      -> ( get_assoc(T, Stats0, var_stat(Count0, First, _))
           -> Count is Count0 + 1,
              put_assoc(T, Stats0, var_stat(Count, First, P0), Stats)
         ; put_assoc(T, Stats0, var_stat(1, P0, P0), Stats) ),
         P is P0 + 1
    ; compound(T)
      -> functor(T, _, N),
         mbr_collect_stats_args(1, N, T, P0, P, Stats0, Stats)
    ; P = P0,
      Stats = Stats0 ).

mbr_collect_stats_args(I, N, _, P, P, Stats, Stats) :- I > N, !.
mbr_collect_stats_args(I, N, T, P0, P, Stats0, Stats) :-
    arg(I, T, Arg),
    mbr_collect_stats(Arg, P0, P1, Stats0, Stats1),
    I1 is I + 1,
    mbr_collect_stats_args(I1, N, T, P1, P, Stats1, Stats).

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
                                                      constrain_args(K, Kc, Gc),
                                                      build_branch(ConV, VOut, Out, Then),
                                                      ( Rs == [] -> Goal = ((Kv = Kc) -> Then), KGi=[]
                                                                  ; translate_case(Rs, Kv, Out, Next, KGi),
                                                                    Goal = ((Kv = Kc) -> Then ; Next) ),
                                                      append([Gc,KGi], KGo).

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
    translate_expr_dl(X, Goals0, AfterExpr, V),
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
%`!(collapse (atomically (petta-three)))` in a named space answered
%((petta-three)) instead of ((1 2 3)) [measured 2026-08-21]. Logtalk threads
%both fields through every compiled clause for this exact reason
%(core.pl:25188); SWI's module system carries only the first, so Self stays in
%the global until a compiled clause carries it, which is P11.7's argument to
%add, not this row's.
hyperpose_branch(Module, Goal, Res, Out) :-
    b_setval('$petta_module', Module),
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
%match it. lib/minimal_metta_lib.pl has implemented it for unify-mod all along
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
%the reason is in this repository too: examples/libraries/minimal_metta.metta
%asserts that the THREE-element (:= a b) is ordinary data and matches the
%pattern (:= $x $y) structurally. Recognising := by name alone would
%reinterpret it [tested: translator_match_modifiers].
%GATE ONE: a pattern that IS a colon expression is a query for stored type
%declarations, not an annotation. `(match &self (: $x Human) $x)` retrieves the
%atoms somebody wrote, which is the reading a knowledge base needs and the one
%issue #177 names as the collision to avoid. An annotation is therefore always
%NESTED: `(match &self (knows (: $x Human) (: $y Human)) ($x $y))`
%[source: LeaTTa/ai-report-inplace-annotations.md, Design, gate 1].
lift_pattern_modifiers(Pattern, Lifted, Guards) :-
    (   colon_expression(Pattern)
    ->  Lifted = Pattern, Guards = []
    ;   lift_pattern_modifiers_(Pattern, Lifted, Guards, [])
    ).

lift_pattern_modifiers_(Pattern, Lifted, Guards0, Guards) :-
    (   nonvar(Pattern), Pattern = [_|_]
    ->  (   seam:pattern_modifier(Pattern, Lifted, Guard)
        ->  Guards0 = [Guard|Guards]
    %GATE TWO: a colon whose VALUE slot is not a variable is data, and the walk
    %does not look inside it. Without the second half a constructor that nests
    %colons inside a value, as LeaTTa's single_sided.metta does with
    %`(: (Sym (: (Sym (: $x $a)) $b)) $c)`, would have its inner colons
    %reinterpreted [source: LeaTTa/ai-report-inplace-annotations.md, Design].
        ;   colon_expression(Pattern)
        ->  Lifted = Pattern,
            Guards0 = Guards
        ;   lift_pattern_modifiers_list(Pattern, Lifted, Guards0, Guards)
        )
    ;   Lifted = Pattern,
        Guards0 = Guards
    ).

colon_expression(Pattern) :- nonvar(Pattern),
                             Pattern = [Colon, _, _],
                             nonvar(Colon),
                             Colon == ':'.

lift_pattern_modifiers_list([], [], Guards, Guards).
lift_pattern_modifiers_list([Item|Rest], [Lifted|LiftedRest], Guards0, Guards) :-
    lift_pattern_modifiers_(Item, Lifted, Guards0, Guards1),
    lift_pattern_modifiers_list(Rest, LiftedRest, Guards1, Guards).

%The two modifiers a pattern position can carry, each replaced by a fresh
%variable and a guard over it. `(:= X)` matches by EQUALITY, so a free
%variable does not match it; `(: $x T)` matches anything of type T and is the
%same acceptance a declared parameter of type T compiles, so a match query can
%restrict by type where only a top-level declaration could before.
%Every clause of this open ownership seam, the two below and a provider's own,
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
seam:pattern_modifier([Colon, Fresh, Type], Fresh,
                 (has_type(Fresh, Type) *-> true ; 'get-metatype'(Fresh, Type))) :-
    %The same nonvar-then-== reading as the clause above and as
    %colon_expression/1: ($A $B 0) against a stored () was compiled as "of
    %type 0" because the literal ':' unified with the pattern's own head
    %variable [measured 2026-08-21, hypothesis SpaceStateMachine].
    nonvar(Colon), Colon == ':',
    %An annotation annotates a VARIABLE, so anything else in that position
    %stays structural. Not a nicety: tests/prolog/duals.plt writes
    %`(= (pat-starts-a (: a $rest)) True)` as an ordinary cons-shaped pattern,
    %and without this gate it would be read as "the atom a has type $rest".
    var(Fresh).

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
									catch_recover(type_declaration(F, TypeChain), fail),
									TypeChain = [->|Types],
									append(_, [DeclaredOutType], Types),
									DeclaredOutType == OutType.
