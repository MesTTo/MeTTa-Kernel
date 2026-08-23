% Purpose: lower runnable expressions, calls, arguments, and dispatch policies into Prolog goals
% Assumes: engine/translator.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/translator.plt, tests/prolog/static_checks.pl; commit=WORKTREE]

%% translate_cached_expr(+Expression, -Goals, -Value) is det.
% This cache stores translation templates, not evaluation answers. Any future
% entry that covers evaluation results must store the complete canonical result
% set, never only the first answer.
translate_cached_expr(C, Goals, Out) :-
    (   translation_cacheable(C)
    ->  current_metta_module(Module),
        translation_template(C, Template, Key),
        (   translated_form_hit(Module, Key, C, Goals, Out)
        ->  true
        ;   with_mutex('$petta_translation_cache',
                       translate_runnable_expr_cached(Module, Key, C,
                                                      Template, Goals, Out))
        )
    ;   translate_runnable_expr(C, Goals, Out)
    ).

%% translate_runnable_expr(+Expression, -Goals, -Value) is det.
translate_runnable_expr(C, Goals, Out) :-
    setup_call_cleanup(assertz(translating_runnable, Ref),
                       once(translate_expr(C, Goals, Out)),
                       erase(Ref)),
    (   runnable_import(_)
    ->  refuse_call_to_own_import(C)
    ;   true
    ),
    (   runnable_negation
    ->  retractall(runnable_negation),
        quantify_negations(Out, Goals)
    ;   true
    ).

%Collect one runnable with its reader-side Name-Var map inside findall's
%template. findall copies the answer and map as one term, so the printer can
%recover variable identity after collection without attributed variables on
%the matcher hot path [tested: test_variable_names_survive_to_the_printer;
%commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
%% translate_runnable_expr(+Expression, +Names, -Goals, -Answers) is det.
translate_runnable_expr(C, Names, Goals, Out) :-
    Context = '$petta_name_context'(Names, []),
    setup_call_cleanup(
        install_runnable_name_context(Context, SavedContext),
        translate_runnable_expr(C, InnerGoals, Value),
        restore_runnable_name_context(SavedContext)),
    arg(1, Context, CollectedReaderNames),
    arg(2, Context, CollectedNames),
    NameState = '$petta_name_state'(CollectedReaderNames,
                                    [RuntimeNames|CollectedNames]),
    goals_list_to_conj(InnerGoals, Conj),
    NamedConj = petta_run_named(CollectedReaderNames, Conj, RuntimeNames),
    FuelConj = petta_run_with_fuel(Value, FuelValue, NamedConj),
    (   Value == 'Empty'
    ->  Goals = [Out = []]
    ;   nonvar(Value)
    ->  Goals = [findall('$petta_answer'(FuelValue, NameState), FuelConj, Out)]
    ;   Goals = [(findall('$petta_answer'(FuelValue, NameState), FuelConj, All),
                  petta_prune_empty_answers(All, Out))]
    ).

install_runnable_name_context(Context, saved(Previous)) :-
    nb_current('$petta_runnable_name_context', Previous), !,
    nb_linkval('$petta_runnable_name_context', Context).
install_runnable_name_context(Context, none) :-
    nb_linkval('$petta_runnable_name_context', Context).

restore_runnable_name_context(saved(Previous)) :- !,
    nb_linkval('$petta_runnable_name_context', Previous).
restore_runnable_name_context(none) :-
    nb_delete('$petta_runnable_name_context').

%Record a compile-time freshening beside the reader map. sealed creates true
%Prolog variables before the runnable findall exists; extending the map here
%lets that findall copy the fresh variable and its source spelling together.
runnable_note_copied_variables([], []).
runnable_note_copied_variables([Original|Originals], [Copy|Copies]) :-
    (   nb_current('$petta_runnable_name_context', Context),
        Context = '$petta_name_context'(Names, _),
        petta_reader_variable_name(Names, Original, Name)
    ->  next_runnable_variable_epoch(Epoch),
        runnable_variable_base_name(Name, BaseName),
        EpochName = '$petta_epoch_name'(BaseName, Epoch),
        arg(1, Context, CurrentNames),
        setarg(1, Context, [EpochName-Copy|CurrentNames])
    ;   true
    ),
    runnable_note_copied_variables(Originals, Copies).

runnable_variable_base_name('$petta_epoch_name'(Name, _), Name) :- !.
runnable_variable_base_name(Name, Name).

next_runnable_variable_epoch(Epoch) :-
    (   nb_current('$petta_runnable_variable_epoch', Epoch)
    ->  Next is Epoch + 1,
        nb_setval('$petta_runnable_variable_epoch', Next)
    ;   Epoch = 0,
        nb_setval('$petta_runnable_variable_epoch', 1)
    ).

:- meta_predicate with_runnable_variable_epochs(0).
with_runnable_variable_epochs(Goal) :-
    (   nb_current('$petta_runnable_variable_epoch', _)
    ->  call(Goal)
    ;   setup_call_cleanup(
            nb_setval('$petta_runnable_variable_epoch', 0),
            call(Goal),
            nb_delete('$petta_runnable_variable_epoch'))
    ).

%Snapshot the names produced by already translated inner collapses, then add a
%slot for this collapse to the final runnable state. setarg/3 is confined to
%the deterministic translation pass; no run-time variable receives an
%attribute or mutable payload.
runnable_collapse_name_state(State, Slot) :-
    nb_current('$petta_runnable_name_context', Context),
    Context = '$petta_name_context'(Names, PriorSlots),
    State = '$petta_name_state'(Names, PriorSlots),
    setarg(2, Context, [Slot|PriorSlots]).

%A runnable is compiled WHOLE before any of it runs, so a registration inside
%one cannot affect its own compilation. The call compiles while the name is
%still unregistered, falls through to data dispatch, and the runnable answers
%the expression instead of the value with nothing said: (d23-double 21) rather
%than 42. Both C-extension examples in the tree carry a comment warning the
%next reader to split the runnable, which is the shape of a trap rather than
%of a rule.
%
%The expression is walked only when the translation ALREADY met an importer
%form, which translate_prolog_import_dl/5 records as it goes. A directive that
%imports nothing therefore pays one lookup on an empty thread_local, the same
%signal runnable_negation uses above and for the same reason: it is the
%cheapest cross-cutting flag Prolog has.
refuse_call_to_own_import(Expr) :-
    findall(N, runnable_import(N), Names0),
    retractall(runnable_import(_)),
    sort(Names0, Names),
    (   member(Name, Names),
        \+ fun_here(Name),
        calls_head(Expr, Name)
    ->  throw(error(petta_call_to_own_import(Name),
                    context(translate_runnable_expr/3,
                            'a runnable compiles before it runs')))
    ;   true
    ).

%A call whose head is Name, anywhere below this expression. An importer's own
%name list is data rather than a call, so the search does not descend into one.
calls_head([Head|Args], Name) :-
    (   Head == Name
    ->  true
    ;   atom(Head),
        prolog_function_importer(Head)
    ->  fail
    ;   member(Sub, Args),
        is_list(Sub),
        calls_head(Sub, Name)
    ).

%Print compiled clause:
maybe_print_compiled_clause(_, _, _) :- silent(true), !.
maybe_print_compiled_clause(Label, FormTerm, Clause) :-
    sdisplay(FormTerm, FormStr),
    ansi_format([fg(yellow)], "-->  ~w  -->~n", [Label]),
    ansi_format([fg(cyan)], "~w~n", [FormStr]),
    ansi_format([fg(yellow)], "--> prolog clause -->~n", []),
    %Module-qualified: ansi_format/4 calls its ~@ goal from library(ansi_term)'s
    %own context, so an unqualified portray_clause here resolves as
    %ansi_term:portray_clause/N, which is missing under autoload=false because
    %ansi_term.pl does not declare its own dependency on library(listing)
    %[same trap as filereader.pl:print_runnable_form/2, measured there].
    ansi_format([fg(green)], "~@", [prolog_listing:portray_clause(current_output, Clause)]),
    ansi_format([fg(yellow)], "^^^^^^^^^^^^^^^^^^^^^~n", []).

%Conjunction builder, turning goals list to a flat conjunction:
goals_list_to_conj([], true)      :- !.
goals_list_to_conj([G], G)        :- !.
goals_list_to_conj([G|Gs], (G,R)) :- goals_list_to_conj(Gs, R).

%A handler that caches by function has to know which module the call site
%lives in, because a named space compiles its own equations into its own
%module and the same name is a different function there. The handler reads
%current_metta_module/1 for itself rather than being handed it: this runs on
%every compiled call site and every reduced call, and resolving the module
%here cost between +0.09% and +0.41% inferences across six benchmarks
%[measured 2026-08-15: weighted-relation 483521 -> 485517].
resolve_dispatch(Fun, Args, Out, Goal) :-
    ( seam:dispatch_call(Fun, Args, Out, Goal)
    -> true
    ; append(Args, [Out], DirectArgs),
      Goal =.. [Fun|DirectArgs]
    ).

%The effective policy is late-bound from &petta, so adding or removing an
%override changes already-compiled call sites. spaces.pl materializes a
%reference-validated lookup for this hot path; the catalog remains the only
%authority and its write funnel invalidates the derived entry.
dispatch_policy_value(Fun, Axis, Value) :-
    petta_dispatch_value(Fun, Axis, Value).

dispatch_call_goal(Fun, Args, Out, Goal,
                   PolicyGoal) :-
    current_metta_module(Module),
    dispatch_call_goal_in(Module, Fun, Args, Out, Goal, PolicyGoal).

%Most calls retain the generated direct goal. Policy interpretation is needed
%only while a non-default selection policy is active or while the written
%arguments are not yet specific enough to decide whether any head applies.
%A head that subsumes the arguments proves the call cannot reach NoMatch; a
%call that cannot unify with any head is the opposite decided case and needs
%only the no-match policy. This keeps ordinary compiled recursion on the
%engine's direct tail-call path.
dispatch_call_goal_in(Module, Fun, _, _, Goal, Goal) :-
    \+ fun_meta_module(Module, Fun, _),
    !.
dispatch_call_goal_in(Module, Fun, Args, Out, Goal,
                      dispatch_policy_execute(Module, Fun, Args, Goal, Out)) :-
    (   dispatch_selection_override(Fun)
    ;   \+ dispatch_head_covers(Module, Fun, Args, Goal),
        dispatch_any_head_matches(Module, Fun, Args, Goal)
    ),
    !.
dispatch_call_goal_in(Module, Fun, Args, Out, Goal, PolicyGoal) :-
    (   dispatch_head_covers(Module, Fun, Args, Goal)
    ->  PolicyGoal = Goal
    ;   PolicyGoal = dispatch_no_match_result(Fun, Args, Out)
    ).

dispatch_selection_override(Fun) :-
    % policy-inventory-exempt: mechanism-internal; reason=these are the four axes whose nondefault values require the retained-clause interpreter instead of the compiled direct goal; evidence=engine/translator/lowering.pl:dispatch_selection_override/1
    member(Axis, ['EvaluationOrderEnum', 'FunctionResultEnum',
                  'ClauseFailedEnum', 'OutOfClausesEnum']),
    petta_catalog_row(['dispatch-policy', Fun, Axis, _]),
    !.

dispatch_head_covers(Module, Fun, Args, _) :-
    fun_meta_module(Module, Fun, Owner),
    fun_meta_clause(Owner, Fun, Head0, _),
    copy_term(Head0, Head),
    subsumes_term(Head, Args),
    !.
dispatch_head_covers(Module, _, Args, Goal) :-
    copy_term(Goal, Probe),
    catch_recover(clause(Module:Probe, _), fail),
    Probe =.. [_|All],
    append(HeadArgs, [_], All),
    subsumes_term(HeadArgs, Args),
    !.

%Demanding a user function goes through the six-axis policy interpreter. A
%builtin or host registration has no retained MeTTa equations and stays on its
%native goal, so a relational builtin's ordinary failure cannot be mistaken
%for a clause miss.
dispatch_policy_execute(Module, Fun, _, Goal, _) :-
    \+ fun_meta_module(Module, Fun, _),
    !,
    call(Module:Goal).
dispatch_policy_execute(Module, Fun, Args, Goal, Out) :-
    dispatch_effective_axes(Fun, Order, ResultMode, ClauseMode, Exhaustion),
    dispatch_fast_axes(Order, ResultMode, ClauseMode, Exhaustion),
    !,
    dispatch_fast_goal(Module, Fun, Args, Goal, Out).
dispatch_policy_execute(Module, Fun, Args, Goal, Out) :-
    dispatch_effective_axes(Fun, Order, ResultMode, ClauseMode, _),
    (   dispatch_result_goal(ResultMode,
                             dispatch_selected_goal(Order, ClauseMode,
                                                    Module, Fun, Args,
                                                    Goal, Out))
    *-> true
    ;   dispatch_failed_call(Module, Fun, Args, Out)
    ).

dispatch_effective_axes(Fun, Order, ResultMode, ClauseMode, Exhaustion) :-
    dispatch_policy_value(Fun, 'EvaluationOrderEnum', Order),
    dispatch_policy_value(Fun, 'FunctionResultEnum', ResultMode),
    dispatch_policy_value(Fun, 'ClauseFailedEnum', ClauseMode),
    dispatch_policy_value(Fun, 'OutOfClausesEnum', Exhaustion).

%The shipped clause-order/nondeterministic path decides head applicability
%before entering the generated predicate. A matching call can then tail-call
%the predicate directly instead of retaining a failure continuation around
%every recursive step. That continuation overflowed the Prolog stack in
%otherwise constant-space recursion. A non-default exhaustion, order, result,
%or clause-failure policy uses the general interpreter below because it must
%observe or replace the generated predicate's failure
%[tested: bindings/python/tests/test_aio.py::test_aio_keeps_the_loop_live_while_the_engine_spins;
%commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
dispatch_fast_axes('OrderClause', 'Nondeterministic', 'ClauseFailNonDet',
                   'FailureOriginal').

dispatch_fast_goal(Module, Fun, Args, Goal, _Out) :-
    dispatch_any_head_matches(Module, Fun, Args, Goal),
    !,
    call(Module:Goal).
dispatch_fast_goal(_, Fun, Args, _, Out) :-
    dispatch_policy_value(Fun, 'NoMatchEnum', Policy),
    dispatch_no_match(Policy, Fun, Args, Out).

%A proof interpreter needs to know whether it may open the written goal while
%preserving dispatch semantics. The shipped fast policy with a matching head
%is exactly that case. Every other route is executed here by the authoritative
%policy interpreter and reported opaque, so a host never reimplements fittest
%ordering, determinism, clause failure or exhaustion.
%[tested: test_depth_exhaustion_returns_a_partial_proof,
%test_the_python_binding_calls_only_the_published_host_surface;
%commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
metta_host_dispatch_proof_step(Module, Fun, Args, Goal, _, direct) :-
    dispatch_effective_axes(Fun, Order, ResultMode, ClauseMode, Exhaustion),
    dispatch_fast_axes(Order, ResultMode, ClauseMode, Exhaustion),
    dispatch_any_head_matches(Module, Fun, Args, Goal),
    !.
metta_host_dispatch_proof_step(Module, Fun, Args, Goal, Out, opaque) :-
    dispatch_policy_execute(Module, Fun, Args, Goal, Out).

dispatch_result_goal('Deterministic', Goal) :- !, once(Goal).
dispatch_result_goal('Nondeterministic', Goal) :- call(Goal).

dispatch_selected_goal('OrderClause', 'ClauseFailNonDet', Module, _, _, Goal,
                       _) :-
    !,
    call(Module:Goal).
dispatch_selected_goal(Order, ClauseMode, Module, Fun, Args, _, Out) :-
    dispatch_meta_clauses(Module, Fun, Clauses0),
    dispatch_ordered_clauses(Order, Module, Args, Clauses0, Clauses),
    dispatch_clause_goal(ClauseMode, Module, Args, Clauses, Out).

dispatch_meta_clauses(Module, Fun, Clauses) :-
    fun_meta_module(Module, Fun, Owner),
    findall(dispatch_clause(HeadArgs, Body, Types),
            fun_meta_clause_types(Owner, Fun, HeadArgs, Body, Types),
            NewestFirst),
    reverse(NewestFirst, Clauses),
    Clauses \== [].

dispatch_ordered_clauses('OrderClause', _, _, Clauses, Clauses) :- !.
dispatch_ordered_clauses('OrderFittest', Module, Args, Clauses, Ordered) :-
    findall((Negative-Index)-Clause,
            ( nth0(Index, Clauses, Clause),
              dispatch_clause_score(Module, Args, Clause, Score),
              Negative is -Score ),
            Scored),
    keysort(Scored, Sorted),
    dispatch_scored_values(Sorted, Ordered).

dispatch_scored_values([], []).
dispatch_scored_values([_-Value|Pairs], [Value|Values]) :-
    dispatch_scored_values(Pairs, Values).

dispatch_clause_score(Module, Args, dispatch_clause(Head, _, Types), Score) :-
    (   Types == []
    ->  include(nonvar, Head, Fixed), length(Fixed, Score)
    ;   findall(S,
                ( member(Chain, Types),
                  dispatch_type_chain_score(Module, Args, Chain, S) ),
                Scores),
        Scores \== [],
        max_list(Scores, Score)
    ).

dispatch_type_chain_score(Module, Args, Chain0, Score) :-
    copy_term(Chain0, [->|Types]),
    append(Expected, [_], Types),
    same_length(Expected, Args),
    metta_argument_type_origins(Expected, Origins),
    \+ \+ metta_arguments_match_in(Module, Expected, Origins, Args),
    maplist(dispatch_type_weight, Expected, Weights),
    sum_list(Weights, Score).

dispatch_type_weight(Type, 0) :- var(Type), !.
dispatch_type_weight('%Undefined%', 0) :- !.
dispatch_type_weight('_', 0) :- !.
dispatch_type_weight('Atom', 0) :- !.
dispatch_type_weight(_, 1).

dispatch_clause_goal('ClauseFailDet', Module, Args, Clauses, Out) :-
    !,
    member(dispatch_clause(Head0, Body0, _), Clauses),
    copy_term(Head0-Body0, Head-Body),
    Head = Args,
    !,
    eval_metta_in_module(Module, Body, Out).
dispatch_clause_goal('ClauseFailNonDet', Module, Args, Clauses, Out) :-
    member(dispatch_clause(Head0, Body0, _), Clauses),
    copy_term(Head0-Body0, Head-Body),
    Head = Args,
    eval_metta_in_module(Module, Body, Out).

dispatch_failed_call(Module, Fun, Args, Out) :-
    (   dispatch_any_head_matches(Module, Fun, Args)
    ->  dispatch_policy_value(Fun, 'OutOfClausesEnum', Policy),
        dispatch_out_of_clauses(Policy, Fun, Args, Out)
    ;   dispatch_policy_value(Fun, 'NoMatchEnum', Policy),
        dispatch_no_match(Policy, Fun, Args, Out)
    ).

dispatch_any_head_matches(Module, Fun, Args) :-
    resolve_dispatch(Fun, Args, _, Goal),
    dispatch_any_head_matches(Module, Fun, Args, Goal).

dispatch_any_head_matches(Module, Fun, Args, _) :-
    fun_meta_module(Module, Fun, Owner),
    fun_meta_clause(Owner, Fun, Head0, _),
    % unifiable/3 neither binds the live call nor copies it. copy_term/2 here
    % copied an entire remaining list for each recursive step even though an
    % equation head decides from its outer constructors, making map/fold over
    % N elements quadratic.
    % [measured: 2026-08-21, 4.10 seconds; command=/usr/bin/time -f 'hol_elapsed=%e maxrss=%M' timeout 300s sh run.sh --silent examples/performance/holbenchmark.metta; fixture=examples/performance/holbenchmark.metta; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
    unifiable(Head0, Args, _),
    !.
dispatch_any_head_matches(Module, _, _, Goal) :-
    copy_term(Goal, Probe),
    catch_recover(clause(Module:Probe, _), fail),
    !.

dispatch_no_match('NoMatchOriginal', Fun, Args, [Fun|Args]).
dispatch_no_match('NoMatchFail', _, _, _) :- fail.
dispatch_no_match('NoMatchError', Fun, Args,
                  ['Error', [Fun|Args], 'NoMatchingClause']).

dispatch_out_of_clauses('FailureOriginal', _, _, _) :- fail.
dispatch_out_of_clauses('FailureEmpty', _, _, []).
dispatch_out_of_clauses('FailureError', Fun, Args,
                        ['Error', [Fun|Args], 'OutOfClauses']).

dispatch_mismatch_result(Fun, Args, Out) :-
    dispatch_policy_value(Fun, 'MismatchEnum', Policy),
    dispatch_mismatch(Policy, Fun, Args, Out).

dispatch_mismatch('MismatchOriginal', Fun, Args, Out) :-
    metta_bad_argument_error(Fun, Args, Out).
dispatch_mismatch('MismatchError', Fun, Args,
                  ['Error', [Fun|Args], 'ArgumentTypeMismatch']).
dispatch_mismatch('MismatchFail', _, _, _) :- fail.

dispatch_no_match_result(Fun, Args, Out) :-
    dispatch_policy_value(Fun, 'NoMatchEnum', Policy),
    dispatch_no_match(Policy, Fun, Args, Out).
incomplete_application_kind(Fun, Arity, partial) :- ( arity(Fun, KnownArity), KnownArity >= Arity
                                                     ; \+ arity(Fun, _) ), !.
incomplete_application_kind(_, _, overapplied).

%An overapplied call ANSWERS rather than raising, because a wrong arity is an
%ordinary MeTTa error and the form after it still runs. WHICH answer is the
%declaration's: a head the engine or the program TYPED is refused by name, and
%an untyped one is left as written, which is what an expression whose head
%means nothing here already does
%[measured 2026-08-19 against the arbiter: `(+ 1 2 3)` and
%`(car-atom (1 2) extra)` answer `(Error <call> IncorrectNumberOfArguments)`
%while `(empty 1 2)`, `(match-types Number Number yes no extra)` and a user
%function's `(f 1 2)` are left as written; source: LeaTTa
%tests/semantics/eval-core/empty-argument-arity.metta].
function_overapplication(Fun, Arguments, Answer) :-
    (   metta_typed_head(Fun)
    ->  Answer = ['Error', [Fun|Arguments], 'IncorrectNumberOfArguments']
    ;   Answer = [Fun|Arguments]
    ).

metta_typed_head(Fun) :-
    atom(Fun),
    (   current_metta_module(Module),
        catch_recover(type_declaration_in(Module, Fun, [->|_]), fail)
    ->  true
    ;   seam:builtin_type_declaration(Fun, [->|_])
    ).

% Runtime dispatcher: call F if it's a registered fun/1, else keep as list.
%
% Resolution follows the current space's module, because that is where the
% space's equations were compiled. Looking in the calling module instead found
% nothing for them, so a function defined in a named space and reached through
% reduce/2 came back as a partial application instead of running: `(map-atom
% (1 2 3) double)` answered `((partial double (1)) ...)`. A builtin still
% resolves, through the module's own inheritance from user.
%The four evaluation outcomes of the Hyperon specification are value, Empty,
%NotReducible and Error, and PeTTa already produces all four: an answer, a
%failed goal, a term handed back unevaluated, and a thrown error. Only the
%third was unreportable, because the term it yields is indistinguishable from
%data. reduce/3 carries which of the two happened and reduce/2 keeps its exact
%behaviour, so every compiled call site is unchanged
%[source: the LeaTTa checkout's MettaHyperonFull/Core/Result.lean, EvalStatus]
%[tested: translator_reduction_status].
reduce(X, Out) :- reduce(X, Out, _).

%The cut sits immediately after each head, which is The Craft of Prolog's rule
%and the one SWI's =>/2 mechanises: Head :- Guard, !, Body, guard as early as
%possible [source: SWI-Prolog 10.1 Reference Manual, section 5.6]. It commits
%to the clause only. Choice points the BODY creates survive it, which they must,
%because a MeTTa function is nondeterministic and reduce/3 answers its whole
%answer set.
%
%Before this, the last clause had a variable first argument, so nothing could
%index it away and every reduce/3 call returned holding a choice point. That
%defeats last call optimisation in the caller: a 200,000 element map-atom
%through the dynamic dispatch path retained 86,400,000 bytes of local stack,
%432 bytes per element, for a choice point that could never yield an answer.
%Measured 2026-08-15. The last clause is now reachable only for a term that is
%neither [] nor [_|_], which is exactly what non_list/1 tested, so the test is
%gone with the choice point.
reduce([], Out, Status) :- !, Out = [], Status = 'not-reducible'.
%The parentheses around the whole if-then-else are load-bearing. Without them
%the cut is read as the first goal of the CONDITION, because , binds tighter
%than ->, and a cut inside a condition is local to that condition and commits
%to nothing.
reduce([F|Args], Out, Status) :- !,
    (   nonvar(F), atom(F),
        %Read once and reused twice below. A function no named space claims is
        %the base tier's, and the base tier is &self's module: an unqualified
        %call from here would resolve in the ENGINE's module instead, which is
        %the parent and cannot see a child's clauses.
        metta_self_module(Self),
        ( fun(F), \+ fun_scoped(F) -> Module = Self
        ; current_metta_module(Module), fun_here_in(Module, F) )
    ->  % --- Case 1: callable predicate ---
        length(Args, N),
        Arity is N + 1,
        %arity/2 rather than current_predicate/1, which is what
        %build_call_or_partial_dl/6 already asks, so the compiled path and the
        %reducer now agree about what is callable. It is also the only one of
        %the two that can be right here: current_predicate/1 sees whatever a
        %library exported into user, and library(yall) exports //2 through
        %//9, so (let $g / ($g 1 2 3)) resolved to yall's lambda and answered
        %`type_error(lambda_free, 1)`. register_prolog_arities/1 no longer
        %records those arities, and reading the registry is free where asking
        %predicate_property/2 per operator cost 2.39% on the typed-call
        %counter [measured 2026-08-17].
        (   ( Module == Self -> arity(F, Arity)
                              ; current_predicate(Module:F/Arity) ),
            \+ (Arity =< 2, current_op(_, _, F))
        ->  resolve_dispatch(F, Args, Out, Goal),
            % A host or builtin function in &self has no retained equation and
            % therefore no dispatch policy to interpret. Avoiding the inherited
            % metadata search keeps the direct Prolog door at its measured
            % transport cost; a retained MeTTa equation still takes the policy
            % route, as do named modules whose inherited owner must be resolved.
            % [tested: prolog_interface:a_registered_predicate_costs_no_more_than_a_metta_function;
            % commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
            (   Module == Self,
                \+ fun_meta_clause(Module, F, _, _)
            ->  call(Module:Goal)
            ;   dispatch_policy_execute(Module, F, Args, Goal, Out)
            ),
            Status = reduced
        ;   incomplete_application_kind(F, Arity, partial)
        ->  Out = partial(F,Args),
            Status = reduced
        ;   function_overapplication(F, Args, Out),
            Status = reduced )
    ;   % --- Case 2: partial closure ---
        compound(F), F = partial(Base, Bound)
    ->  append(Bound, Args, NewArgs),
        reduce([Base|NewArgs], Out, Status)
    ;   % --- Case 3: an APPLICABLE GROUNDED ATOM ---
        % MeTTa says a Grounded atom "may contain any binary object, for
        % example operation", and an operation is a thing you call. Nothing
        % here knows what makes one applicable: a bridge claims its own values
        % through seam:grounded_apply/3 and the engine applies whatever it
        % claims [source: metta-lang.dev/docs/learn, Atom kinds and types].
        %
        % Reached only for a head that is neither a function name nor a
        % partial, which used to fall straight through to case 4, so a Python
        % callable held in a MeTTa variable could not be applied at all and
        % ((py-atom numpy.absolute) -5) answered itself.
        %atomic/1 rather than \+ is_list/1, and the difference is not style: a
        %data head IS a list, so is_list/1 walked every one of them to decide
        %it was not this case. That cost 20% of the alpha-unique benchmark's
        %instructions [measured 2026-08-16: 3.70 to 4.45 billion]. A grounded
        %value is atomic, so one O(1) test excludes every list and compound.
        atomic(F), \+ atom(F),
        seam:grounded_apply(F, Args, Applied)
    ->  Out = Applied,
        Status = reduced
    ;   % --- Case 4: leave unevaluated ---
        Out = [F|Args],
        acyclic_term(Out),
        Status = 'not-reducible'
    ).
reduce(Culprit, _, _) :-
    throw_metta_type_error(reduce, list, Culprit).


%Calling reduce from aggregate function foldall needs this argument wrapping
agg_reduce(AF, Acc, Val, NewAcc) :- reduce([AF, Acc, Val], NewAcc, _).

%Combined expr translation to goals list

%% translate_expr_to_conj(+Expression, -Conjunction, -Value) is det.
translate_expr_to_conj(Input, Conj, Out) :- translate_expr(Input, Goals, Out),
                                            goals_list_to_conj(Goals, Conj).

%Expand one call through a translator rule. The rule is an ordinary MeTTa
%equation, so it lives in the module of the space that wrote it: called
%unqualified it resolved in the ENGINE's module and raised Unknown procedure
%for every rule [tested: examples/libraries/patrick.metta].
%
%A rule that does not APPLY fails here rather than raising, and the dispatch
%above then carries on down the chain exactly as it does for a special form
%no clause of translate_special_dl/5 fits. That is what lets a rule carry a
%guard in its head: `(= (union (superpose $a) (superpose $b)) ...)` rewrites
%the shape it names and leaves `(union foo bar)` to data dispatch, which is
%what rewrite_streamops/2's identity clause used to do for the same six
%forms. Wired as the THEN of its own if-then-else, a rule that did not match
%took the whole enclosing equation down with it: `(= (f) (union foo bar))`
%failed to translate and the message named process_form/4
%[tested: translator_derived_forms].
%
%EVERY TRANSLATOR RULE IS A CONDITIONAL REWRITE RULE, because a rule's BODY is
%its condition. A clause applies at a call when its head matches AND its body
%produces an expansion; a body with no answer declines, the next clause is
%tried, and if no clause applies the whole rule declines and the call goes to
%ordinary dispatch. The first clause that applies wins, so a rule is
%deterministic where the function of the same equations would answer every
%way. Measured 2026-08-21, policy-free: `(= (m5 a) (empty))` ahead of
%`(= (m5 $x) (noeval two))` compiles `(= (usem5) (m5 a))` to the fact
%`usem5(two)`, and the same first equation alone compiles
%`(= (usem6) (m6 a))` to the call `usem6(A) :- m6(a, A)`.
%
%That is the settled ruling and not an accident of call/1, and it is what
%every system this rule set is modelled on does:
%
%  - the arbiter's own conditional metatheory defines an oriented conditional
%    rewrite rule as one that "fires when its left side matches and each
%    condition `s ~> t` holds", following Avenhaus-Loria-Saenz 1994 and Lucas
%    JLAMP 2024 [source 2026-08-21: LeaTTa
%    MeTTaILProofs/ConditionalCP.lean, module header];
%  - CHR: "If the guard succeeds, the rule applies. Otherwise the next rule is
%    tried" [source 2026-08-21: sicstus.sics.se CHR, "How CHR Work"];
%  - Haskell: "If none of the guarded expressions for a given alternative
%    succeed, then matching continues with the next alternative"
%    [source 2026-08-21: Haskell 2010 Language Report, section 3.17];
%  - Rw-Prolog writes a rule as `Pattern := Template :- Conditions`, so a
%    condition that fails backtracks into the next rule
%    [source 2026-08-21: ai-tmp/rw-prolog/src/rewrite.pl, redex/3].
%
%The consequence for the confluence machinery is that the unconditional
%critical-pair verdict is a PROOF OBLIGATION about this rule set rather than a
%decision about it, which tests/prolog/translator_confluence.pl now says with
%every report [tested: test_an_answerless_translator_rule_body_behaves_as_ruled;
%commit=4465fc492071932eab0b2818a4ccd46f01f0d6aa].
%
%A rule that DECLINES with `(refuse Reason)` below is that same condition
%failing in the rule's own words rather than a different kind of rule. The
%words are published into &petta and the call falls through exactly as a body
%with no answer does, which is why the report COUNTS the rules that can refuse:
%the conditionality is the ruling above, and a refusal is where it is written
%down [tested: test_a_translator_rule_can_decline_with_its_own_words;
%commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%
%A GUARD THAT BINDS A PATTERN VARIABLE CANNOT CREATE A MATCH, which is why the
%call runs on a COPY and the copy is re-checked against the call afterwards.
%Prolog's call/1 UNIFIES, and unification runs both ways: the rule's guard,
%whether it is written as a head shape or as a goal in the rule's body, could
%reach back into the term being rewritten and instantiate it, so a rule fired
%on a call it does not match and rewrote the enclosing equation's own head
%while it was there. Both halves measured 2026-08-21 on the tip before this
%change:
%
%  (: gp (-> Atom %Undefined%))         (: bindguard (-> Atom %Undefined%))
%  (= (gp (pair $a $b)) (noeval ...))   (= (bindguard $a) (let $a planted ...))
%  (= (uses-gp $z) (gp $z))                (= (uses-bg $z) (bindguard $z))
%
%compiled to `uses-gp([pair, A, B], ...)` and `uses-bg(planted, ...)`. The programmer
%wrote a head that matches anything and got one that matches pairs, and one
%that matches the single symbol `planted`; `!(uses-gp 5)` and `!(uses-bg 5)` had no
%answer and nothing said why.
%
%This is a solved problem in three systems, and they agree.
%
%  - Rw-Prolog's redex/3 calls subsumes_term/2 TWICE around its guard for
%    exactly this reason: it matches a COPY of the redex against the rule, runs
%    the condition, checks again that the matched copy is still a
%    generalization of the redex, and only then commits by unifying the two
%    [source 2026-08-21: ai-tmp/rw-prolog/src/rewrite.pl, redex/3].
%  - CHR states it as a rule of the language: "the guard of a rule may not
%    contain any goal that binds a variable in the head of the rule", and the
%    runtime enforces it, "any guard fails when it binds a variable that
%    appears in the head of the rule", after which "the next rule is tried"
%    [source 2026-08-21: swi-prolog.org/pldoc/man?section=chr-syntax and
%    ?section=chr-semantics, check_guard_bindings; sicstus.sics.se CHR, "How
%    CHR Work"]. That is this rule and its fall-through, stated by the
%    formalism P2.13's confluence results are borrowed from.
%  - SWI's own single-sided-unification rules are compiled to exactly this
%    check: "The subsumes_term/2 guarantees the clause head is more generic
%    than the goal term and thus unifying the two does not affect any of the
%    arguments of the goal", with the guard restriction left UNENFORCED
%    because "we do not know about an efficient way to enforce unification
%    against head arguments" [source 2026-08-21:
%    swi-prolog.org/pldoc/man?section=ssu and ?section=ssu-guard]. Copying the
%    arguments and re-checking is that way, at the price of one copy per rule
%    application, which is a compile-time cost paid once per call site.
%
%Here the copy is the argument list, subsumes_term/2 rejects any binding the
%rule made into it, and the unification that follows can then only bind the
%copy. A rejected rule fails back into call/1, so the rule's next clause is
%tried and, if none matches, the chain carries on to ordinary dispatch: that is
%what the identity second equation in
%`(= (union $a $b) (noeval (noeval (union $a $b))))` is for, and it is now
%reachable from a call whose arguments are not yet known.
%
%copy_term_nat/2 rather than copy_term/2, as Rw-Prolog uses, so a constraint on
%an argument is not duplicated onto the copy; the commit below reattaches the
%originals.
%
%Limitation: Rw-Prolog checks BEFORE the guard as well, so a doomed match never
%runs one. The head unification here happens inside call/1 and cannot be
%observed separately, so the check is made once, after. That is the same
%correctness and one difference: a rule body with a side effect of its own runs
%it before the rule is rejected [tested: translator_rule_matching,
%test_a_guard_that_binds_a_pattern_variable_cannot_create_a_match;
%commit=4465fc492071932eab0b2818a4ccd46f01f0d6aa].
%
%THE THREE QUESTIONS BELOW ARE ASKED IN ONE ORDER, and it is the only order
%the two disciplines agree on: did the rule MATCH, did it then DECLINE, and
%does the rewrite it produced go the way that lowers the form's cost. Anything
%the rule says about a call it did not match is not about that call, so the
%re-check comes first; the declarations arrive as an argument because the
%caller already read the registry row that decided this was a rule at all.
apply_translator_rule_dl(HV, Declarations, Args, AfterHead, Goals, Out) :-
    (   catch_recover(type_declaration(HV, TypeChain), fail)
    ->  TypeChain = [->|Xs],
        append(ArgTypes, [_], Xs),
        translate_args_by_type_dl(Args, ArgTypes, AfterHead, AfterArgs, Values)
    ;   translate_args_dl(Args, AfterHead, AfterArgs, Values)
    ),
    copy_term_nat(Values, Matched),
    append(Matched, [Expansion], RuleArgs),
    HookCall =.. [HV|RuleArgs],
    current_metta_module(RuleModule),
    call(RuleModule:HookCall),
    %THE RULE MATCHED only if it did not reach back into the call. The body ran
    %on the copy, so subsumes_term/2 rejects a rule that instantiated the
    %arguments it was asked about, and the unification that follows can then
    %only bind the copy. A rejection fails back into call/1, so the rule's next
    %clause is tried and then ordinary dispatch, which is the same fall-through
    %a declining body takes. Asked BEFORE the refusal and the orientation
    %below: a rule that never matched has no standing to publish words about
    %this call, and a cost comparison against arguments it instantiated would
    %be pricing a form the program did not write.
    subsumes_term(Matched, Values),
    Matched = Values,
    %Both tests below are written so that a rule which declared nothing, which
    %is every rule that shipped before declarations existed, pays NOTHING for
    %them: `=/2` and `==/2` compile to inline instructions rather than calls,
    %so the whole block is zero inferences until a rule refuses or carries a
    %direction. Reading the declarations out of the registry here instead cost
    %six inferences on the file-load benchmark [measured 2026-08-21].
    %
    %A rule that inspected its match and DECLINED fails here, so the call
    %carries on down the dispatch chain exactly as one whose head did not
    %match, and a rule with a further equation tries that one next. The words
    %are recorded rather than dropped.
    %
    %A rule read BOTH ways has to be oriented per call, or it and the inverse
    %it derives rewrite each other forever: the rewrite goes through only when
    %it lowers the form's cost. A blocked rewrite hands the call back as the
    %DATA it was written as, which is the prelude's own idiom for the same
    %thing, `(noeval (noeval (union $a $b)))`. Falling through to ordinary
    %dispatch instead would compile a call to the rule's own equation, and that
    %equation IS the rewrite: measured 2026-08-21, `(unpack (wrap (box (a b
    %c))))` with the rewrite blocked at compile time still answered `(twin
    %(a b c) (a b c))` because the same equation ran at run time, so the
    %orientation decided nothing.
    (   Expansion = [refuse, Reason], nonvar(Reason)
    ->  note_translator_rule_refusal(HV, Values, Reason),
        fail
    ;   true
    ),
    (   Declarations == []
    ->  Rewritten = Expansion
    ;   translator_rule_orients(HV, Declarations, Values, Expansion)
    ->  Rewritten = Expansion
    ;   Rewritten = [noeval, [HV|Values]]
    ),
    translate_expr_dl(Rewritten, AfterArgs, Goals, Out),
    refuse_seam_expanded_to_data(HV, Out).

%Turn a MeTTa S-expression into a goal list. The internal difference list
%keeps a nested call from copying every goal produced below it.

%% translate_expr(+Expression, -Goals, -Value) is det.
translate_expr(Input, Goals, Out) :-
    translate_expr_dl(Input, Goals, [], Out).

translate_expr_dl(X, Goals, Goals, X) :-
    ((var(X) ; atomic(X)) ; X = partial(_,_)), !.
translate_expr_dl([H|T], Goals0, Goals, Out) :-
        translate_expr_dl(H, Goals0, AfterHead, HV),
        %--- Translator rules ---:
        ( nonvar(HV), translator_rule(HV, Declarations),
          apply_translator_rule_dl(HV, Declarations, T, AfterHead, Goals, Out)
          -> true
        ; atom(HV), translate_special_dl(HV, T, AfterHead, Goals, Out) -> true
        %The Prolog importer consumes its function-name list as data. Keeping
        %that argument literal makes its translation stable after those names
        %have become registered functions during an earlier space life.
        ; translate_prolog_import_dl(HV, T, AfterHead, Goals, Out) -> true
        %--- Automatic 'smart' dispatch, translator deciding when to create a predicate call, data list, or dynamic dispatch: ---
        ; %Known function => direct call:
          ( is_list(T),
            ( atom(HV), fun_here(HV),
              \+ runnable_head_awaits_its_definition(HV),
              Fun = HV, IsPartial = false, Bound = []
            ; compound(HV), HV = partial(Fun, Bound), IsPartial = true
            ) % Check for type definition [:,HV,TypeChain]
            -> ( runtime_guarded_builtin_call(Fun)
                 -> UniqueTypeChains = [], EffectsPrecheck = true
                  ; findall(TypeChain,
                            catch_recover(type_declaration(Fun, TypeChain),
                                          fail),
                            TypeChains),
                    list_to_set(TypeChains, UniqueTypeChains),
                    ( effects_prechecked_nonruntime_builtin(Fun)
                    -> EffectsPrecheck = true
                    ;  EffectsPrecheck = false ) ),
               ( EffectsPrecheck == true, refused_argument_call(Fun, T)
                 -> refused_argument_call_dl(Fun, UniqueTypeChains, T, IsPartial,
                                             Bound, Out, AfterHead, Goals)
              ; functioncall_dl(Fun, UniqueTypeChains, T, IsPartial, Bound, Out,
                                AfterHead, Goals))
          %A signature from later in this source is data at this position:
          ; atom(HV), runnable_head_awaits_its_definition(HV)
            -> note_symbol_head(HV),
               translate_data_args_dl(HV, T, AfterHead, AfterData, AVs),
               data_head_answer_dl(HV, T, AVs, Out, AfterData, Goals)
          %Literals (numbers, strings, etc.), known non-function atom => data:
          %A grounded head that is an OPERATION is a call, not data. Without
          %this it fell into the data branch below and never reached reduce/3,
          %so a token bound to a Python function built `(<fn> -5)` as a term
          %instead of calling it: the language's own idiom, `(bind! abs
          %(py-atom numpy.absolute))` then `(abs -5)`.
          ; ( atomic(HV), \+ atom(HV) , \+ seam:grounded_applicable(HV)
            ; atom(HV), \+ fun_here(HV) ) -> note_symbol_head(HV),
                                             translate_data_args_dl(HV, T, AfterHead, AfterData, AVs),
                                             data_head_answer_dl(HV, T, AVs, Out, AfterData, Goals)
          %Plain data list: evaluate inner fun-sublists
          ; is_list(HV) -> translate_args_dl(T, AfterHead, AfterArgs, AVs),
                           eval_data_term_dl(HV, AfterArgs, Goals, HV1),
                           Out = [HV1|AVs]
          %Unknown head (var/compound) => runtime dispatch:
          ; translate_args_dl(T, AfterHead, BeforeReduce, AVs),
            BeforeReduce = [reduce([HV|AVs], Out, _)|Goals] )).

%A source's signature pre-pass makes a later equation's name visible before
%the equation itself runs. That visibility is metadata, not a time machine:
%a runnable at the earlier source position still evaluates against the
%current equation prefix. source_pending_definition/2 names only those later
%heads, so imported metadata functions and builtins are never mistaken for
%forward definitions. Treating a pending name as callable emitted a
%host predicate that did not exist yet and raised Unknown procedure instead
%of leaving the call unreduced. Once any predicate for the name exists, the
%ordinary arity machinery below again decides calls and partial applications.
%This follows evalSequentialRun, whose bang branch evaluates against kb while
%only a non-bang form extends kb for the next step
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean,
%evalSequentialRun] [tested:
%test_a_bang_before_the_definition_answers_unreduced_not_a_host_error].
runnable_head_awaits_its_definition(Fun) :-
    translating_runnable,
    active_source_program(Id), !,
    source_pending_definition(Id, Fun),
    current_metta_module(Module),
    \+ current_predicate(Module:Fun/_).

%The declarations a CONSTRUCTOR compiles against, and there are two registers
%of them. type_declaration/2 holds what the program and its spaces declared;
%seam:builtin_type_declaration/2 holds the engine's own surface, parsed out of
%lib_builtin_types.metta at startup.
%
%Reading the engine's register here and NOT on the function path above is
%deliberate, and it was measured rather than chosen. `Atom` in a parameter
%position says the argument is not reduced before the call, which is exactly
%what a constructor like `(: Error (-> Atom Atom ErrorType))` wants. It is NOT
%what several of the engine's own declarations want: `(: maplist (-> Atom
%%Undefined% %Undefined%))` says its first argument is a closure the caller
%wrote, and the call site has to BUILD that closure, so masking it hands
%maplist/3 a list where it needs a goal. Those declarations describe the
%argument a caller writes rather than the value the predicate receives, and
%honouring them at every call site broke every one
%[measured 2026-08-16: examples/functions/lambda.metta, maplist/3 called with
%'[|]'/4].
%
%A constructor has no such gap, because there is no predicate underneath it to
%disagree with the declaration.
call_site_type_chains(Fun, UniqueTypeChains) :-
    findall(TypeChain, catch_recover(type_declaration(Fun, TypeChain), fail),
            TypeChains),
    (   TypeChains \== []
    ->  list_to_set(TypeChains, UniqueTypeChains)
    ;   findall(Masked,
                ( seam:builtin_type_declaration(Fun, Chain),
                  chain_masks_an_argument(Chain),
                  atom_positions_only(Chain, Masked) ),
                MaskedChains),
        list_to_set(MaskedChains, UniqueTypeChains)
    ).

%A DECLARED head with no equations is still checked against its declaration,
%because the declaration is what the arbiter reads: `(: aF (-> A R))` with
%`(: b B)` makes `(aF b)` `(Error (aF b) (BadArgType 1 A B))` there and left
%it as data here, which is why four type-cast files read the subject's own
%error where this engine reported none
%[source: LeaTTa tests/semantics/types-basic/50-type-cast-ill-typed-atom.metta
%through 53, and 44 through 49 for the multiplicity].
%
%The goal is emitted ONLY for a head that HAS an arrow, so an ordinary
%constructor compiles to exactly what it did and pays nothing. The arguments
%it reports are the ones AS WRITTEN, which is the form the arbiter names and
%the one whose types decide.
%
%ONE INDEXED CLAUSE LOOKUP decides it, the same door get_function_type/2 opens
%on the typed-call path, and not type_declaration/2, which goes through match/4
%and the prelude. A data head is the commonest thing in a MeTTa program and the
%alpha-unique benchmark compiles ten thousand of them: written with
%call_site_type_chains/2 this cost +44% there, 3.48 to 5.03 billion
%instructions [measured 2026-08-19], which is the same trap the note above
%data_head_masks/3 records at +20% for 2026-08-16.
%
%It reads &self, which is where a program's declarations go and is the limit
%get_function_type/2 already lives with; a declaration written only into a
%named space does not gate that space's data heads.
data_head_answer_dl(HV, Written, AVs, Out, Goals0, Goals) :-
    (   arrow_declared_data_head(HV),
        \+ written_args_settled(HV, Written)
    ->  Goals0 = [( metta_bad_argument_error(HV, Written, Out)
                  *-> true
                  ;   Out = [HV|AVs]
                  )|Goals]
    ;   Goals0 = Goals,
        Out = [HV|AVs]
    ).

%EXPERIMENT (worktree only): the check above traverses the argument AS WRITTEN,
%so nesting pays for it again at every level: a chain of arrow-declared data
%heads d deep emits d of these and the one at level i walks a term of depth i,
%which is Theta(d^2). This is the shape gradual typing calls a DEEP check at
%every boundary, and the shallow, first-order alternative is what Transient
%checks do instead: they "do not traverse values" and each costs O(1), with the
%deep guarantee accumulating because every level is checked at its own boundary
%[source: Greenman et al., Deep and Shallow Types for Gradual Languages, PLDI
%2022; Vitousek and Siek, Optimizing and evaluating transient gradual typing,
%which is a static analysis removing exactly the redundant checks below].
%
%A written argument is SETTLED when its own boundary already decided it: it is
%an application of an arrow-declared head whose single declared arrow returns
%exactly the parameter type this call expects, at matching arity. That inner
%application emits its own metta_bad_argument_error/3 through this same clause,
%so the guarantee is established there and asking again cannot change it. The
%direction is monotone-safe: type candidates are ADDITIVE, so a later get-type
%extension can only add types to the value and never remove the one the declared
%arrow gives.
written_args_settled(HV, Written) :-
    '$petta_atoms:&self':'&self'(':', HV, Chain),
    nonvar(Chain),
    Chain = [->|Types],
    append(ParameterTypes, [_Result], Types),
    same_length(ParameterTypes, Written),
    ParameterTypes \== [],
    maplist(written_arg_settled, ParameterTypes, Written).

written_arg_settled(Expected, Written) :-
    nonvar(Expected),
    nonvar(Written),
    Written = [Head|Args],
    atom(Head),
    findall(C, ( '$petta_atoms:&self':'&self'(':', Head, C),
                 nonvar(C), C = [->|_] ), [[->|InnerTypes]]),
    append(InnerParameters, [Result], InnerTypes),
    InnerParameters = [_|_],
    same_length(InnerParameters, Args),
    ground(Result),
    Result == Expected.

arrow_declared_data_head(HV) :-
    atom(HV),
    '$petta_atoms:&self':'&self'(':', HV, Chain),
    nonvar(Chain),
    Chain = [->|_],
    !.

%A CONSTRUCTOR can mask too, and this is where the language's rule is wider
%than "function": it is about what a head DECLARES, not about whether it has
%equations. `(: Error (-> Atom Atom ErrorType))` is a declaration on a data
%head, and it is the whole reason an error term can carry the malformed
%expression that caused it. Without it `(Error (+ 1 2) (+ 1 +))` raised while
%evaluating its own argument, which is an error channel unable to report the
%one thing it exists to report.
%
%The cheap test comes first: an ordinary constructor has no declaration in
%either register and fails an indexed lookup, so nothing else runs for it.
translate_data_args_dl(HV, Args, Goals0, Goals, AVs) :-
    (   atom(HV), is_list(Args), data_head_masks(HV, Args, ArgTypes)
    ->  translate_args_by_type_dl(Args, ArgTypes, Goals0, Goals, AVs)
    ;   translate_args_dl(Args, Goals0, Goals, AVs)
    ).

%ONE indexed lookup, and the index is why. Deriving this per head cost 21
%inferences, 16 of them inside type_declaration/2, and a data head is the
%commonest thing in a MeTTa program: the alpha-unique benchmark compiles ten
%thousand of them and paid 20% more instructions for it
%[measured 2026-08-16: 3.70 to 4.45 billion]. The engine's declaration surface
%is static once loaded, so the masking heads are computed once and looked up
%by name after that.
data_head_masks(HV, Args, ArgTypes) :-
    masking_data_head(HV, ArgTypes),
    same_length(ArgTypes, Args),
    !.

%Built from the engine's own declaration register after it loads. A program's
%own `(: MyErr (-> Atom Atom MyType))` is NOT indexed here, so a user-declared
%constructor does not mask; that is a real limit and it is here rather than
%hidden, because closing it means testing every add-atom for a declaration and
%the measurement above is what that costs.
:- dynamic masking_data_head/2.

index_masking_data_heads :-
    retractall(masking_data_head(_, _)),
    forall(( seam:builtin_type_declaration(Name, Chain),
             chain_masks_an_argument(Chain),
             atom_positions_only(Chain, [->|Masked]),
             append(ArgTypes, [_], Masked) ),
           ( masking_data_head(Name, ArgTypes)
             -> true
             ;  assertz(masking_data_head(Name, ArgTypes)) )).

chain_masks_an_argument([->|Types]) :-
    append(Args, [_], Types),
    memberchk('Atom', Args).

atom_positions_only([->|Types], [->|Masked]) :-
    append(Args, [Out], Types), !,
    maplist(atom_position_or_undefined, Args, MaskedArgs),
    append(MaskedArgs, [Out], Masked).
atom_positions_only(Chain, Chain).

atom_position_or_undefined(T, Masked) :-
    ( T == 'Atom' -> Masked = 'Atom' ; Masked = '%Undefined%' ).

%A BUILTIN CALL WHOSE DECLARED TYPES ALREADY REFUSE IT does not run its
%arguments.
%Upstream type-checks an application before interpreting its operands
%(`hyperon-experimental@3f76dc4` interpreter.rs:1224-1258 against :1352-1395),
%and the arbiter's eight effects files are built to see the difference: each
%pairs a control with an experiment whose operand emits a marker from inside
%itself, and no marker appears for a rejected operand
%[source: LeaTTa tests/semantics/grounded/13-effects-arithmetic.metta through
%21-effects-strings-metatype.metta, all STATUS conforms]. This engine ran the
%operand first and then reported the REDUCED value, so `(+ 1 (effect-string
%PLUS-WRONG True))` printed the marker and answered
%`(Error (+ 1 s) (BadArgType 2 Number String))` where the arbiter answers the
%call as written and prints nothing.
%
%DECIDED HERE, at compile time, because that is where it is free. The types of
%a written call are known once its head is declared, so the refusal is a
%property of the call text rather than of the run, and a call the declarations
%accept compiles to exactly what it compiled to before. Asking at run time
%would put a type walk in front of every operation, which is the shape the
%benchmarks refuse [measured 2026-08-20: one extra inference per space
%operation was +30,002 on py-method-call].
%
%The emitted goal asks AGAIN rather than carrying the answer, and falls back to
%the ordinary compilation when it finds nothing: a declaration this engine
%recompiles call sites for can be retracted between the compile and the run,
%and a call whose types no longer refuse it must still run its arguments
%[tested: operation_answers:a_wrongly_typed_operand_does_not_run,
%an_operand_of_the_right_type_still_runs, an_undecided_operand_still_runs].
%\+ \+ so the decision leaves NOTHING bound: this runs over the call as
%written, whose variables are the compiled clause's own, and a check that bound
%one would compile the binding into the clause.
refused_argument_call(Fun, Args) :-
    is_list(Args),
    metta_shallow_call_refused(Fun, Args).

%Only built-ins whose own runtime contract already promises BadArgType get the
%earlier ordering. Other operations deliberately own different refusals:
%get-atoms names its space error, size-atom on a number answers nothing, and a
%host may register an untyped operation called last over Prolog's same-named
%predicate. Applying every declaration here replaced all three contracts with
%a synthetic BadArgType during the full battery
%[tested: bindings/python/tests/test_ops.py::test_a_name_prolog_owns_registers_and_leaves_prolog_alone,
%bindings/python/tests/test_space_operation_errors.py::test_a_non_symbol_first_argument_is_refused_by_the_read_path,
%examples/data/atomops.metta; commit=8d0027a3942000c799daccb45bf0abe1b46b10aa]. format-args is the one effects
%probe outside runtime_type_guarded/1; its first String operand is evaluated,
%so the same ordering is required there, while its Expression operand remains
%quoted by ordinary typed translation.
effects_prechecked_nonruntime_builtin('format-args') :-
    \+ metta_builtin_overridden('format-args').

refused_argument_call_dl(Fun, Chains, Args, IsPartial, Bound, Out, Goals0, Goals) :-
    functioncall_dl(Fun, Chains, Args, IsPartial, Bound, OrdinaryOut,
                    OrdinaryGoals, []),
    goals_list_to_conj(OrdinaryGoals, Ordinary),
    Goals0 = [( dispatch_mismatch_result(Fun, Args, Out)
              *-> true
              ;   Ordinary, Out = OrdinaryOut
              )|Goals].

%The ordinary compilation of a call, extracted so the refusal above can wrap it
%without re-entering the translator, which recursed into its own decision.
functioncall_dl(Fun, Chains, Args, IsPartial, Bound, Out, Goals0, Goals) :-
    (   typed_functioncall_dl(Fun, Chains, Args, IsPartial, Bound, Out,
                              Goals0, Goals)
    ->  true
    ;   translate_call_args_dl(Args, Goals0, AfterArgs, AVs, Evaluated),
        ( IsPartial -> append(Bound, AVs, AllAVs) ; AllAVs = AVs ),
        build_call_or_partial_dl(Fun, AllAVs, Out, CallGoals, [], []),
        undeclared_call_operands(Fun, Evaluated, Guarded),
        guard_error_arguments(Guarded, Out, CallGoals, AfterArgs, Goals)
    ).
