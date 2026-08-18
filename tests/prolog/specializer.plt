% Purpose: verify higher-order specialization keys, per-clause bindings, and
%   recursive folding directly against generated Prolog clauses.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(specializer).

set_specializer_test_mode :-
    retractall(silent(_)),
    assertz(silent(true)).

cleanup_specializer_symbols(Names) :-
    forall(member(Name, Names),
           ( invalidate_specializations(Name),
             forget_symbol(Name) )),
    retractall(silent(_)),
    assertz(silent(false)).

load_specializer_regression(File, Results) :-
    directory_file_path('../regression', File, Path),
    load_metta_file(Path, Results).

setup_concurrent_specialization :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-race-inc $x) (+ $x 1))\n
(= (plunit-spec-race $f $x) ($f $x))\n
", _).

cleanup_concurrent_specialization :-
    cleanup_specializer_symbols(
        ['plunit-spec-race', 'plunit-spec-race-inc']).

run_concurrent_specialization(_) :-
    translate_expr(
        ['plunit-spec-race', 'plunit-spec-race-inc', 1], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    %A specialization is compiled into the module of the space whose code
    %triggered it, so a test that calls or reads it has to name that module.
    metta_self_module(Self),
    once(call(Self:Goal)),
    Out == 2.

test(concurrent_translation_creates_one_specialization,
     [ setup(setup_concurrent_specialization),
       cleanup(cleanup_concurrent_specialization) ]) :-
    concurrent_forall(between(1, 64, Worker),
                      run_concurrent_specialization(Worker),
                      [threads(64)]),
    findall(SpecName,
            ho_specialization(_, 'plunit-spec-race', SpecName),
            Specializations),
    Specializations = [SpecName],
    functor(Head, SpecName, 3),
    metta_self_module(Self),
    aggregate_all(count, clause(Self:Head, _), 1),
    aggregate_all(count,
                  get_native_atom('&self', [=, [SpecName|_], _]),
                  1).

setup_multiclause :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-inc $x) (+ $x 1))\n
(= (plunit-spec-t2 $f 0) ($f 100))\n
(= (plunit-spec-t2 $f $x) ($f ($f $x)))\n
", _),
    process_metta_string("!(plunit-spec-t2 plunit-spec-inc 5)", [7]).

cleanup_multiclause :-
    cleanup_specializer_symbols(['plunit-spec-t2', 'plunit-spec-inc']).

test(all_clauses_are_bound_independently,
     [setup(setup_multiclause), cleanup(cleanup_multiclause)]) :-
    ho_specialization(_, 'plunit-spec-t2', SpecName),
    SpecName == 'plunit-spec-t2_Spec_[plunit-spec-inc]',
    functor(Head, SpecName, 3),
    metta_self_module(Self),
    findall(Head-Body, clause(Self:Head, Body), Clauses),
    length(Clauses, 2),
    forall(member(ClauseHead-_, Clauses),
           arg(1, ClauseHead, 'plunit-spec-inc')),
    \+ ( member(_-ClauseBody, Clauses),
         sub_term(Reduce, ClauseBody),
         compound(Reduce),
         functor(Reduce, reduce, 2) ),
    process_metta_string("!(plunit-spec-t2 plunit-spec-inc 0)", [101, 2]).

setup_two_bindings :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-inc2 $x) (+ $x 1))\n
(= (plunit-spec-dbl2 $x) (* $x 2))\n
(= (plunit-spec-p2 $f $g 1) ($f 1))\n
(= (plunit-spec-p2 $f $g 2) ($g 2))\n
", _),
    process_metta_string(
        "!(plunit-spec-p2 plunit-spec-inc2 plunit-spec-dbl2 1)", [2]).

cleanup_two_bindings :-
    cleanup_specializer_symbols(
        ['plunit-spec-p2', 'plunit-spec-dbl2', 'plunit-spec-inc2']).

test(global_key_covers_every_specialized_argument_position,
     [setup(setup_two_bindings), cleanup(cleanup_two_bindings)]) :-
    ho_specialization(_, 'plunit-spec-p2', SpecName),
    SpecName ==
        'plunit-spec-p2_Spec_[plunit-spec-inc2,plunit-spec-dbl2]',
    functor(Head, SpecName, 4),
    metta_self_module(Self),
    findall(Body, clause(Self:Head, Body), Bodies),
    length(Bodies, 2),
    \+ ( member(Body, Bodies),
         sub_term(Reduce, Body),
         compound(Reduce),
         functor(Reduce, reduce, 2) ).

setup_recursive :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-step $x) (+ $x 1))\n
(= (plunit-spec-rep $f 0 $x) $x)\n
(= (plunit-spec-rep $f $n $x)\n
   (if (> $n 0)\n
       (plunit-spec-rep $f (- $n 1) ($f $x))\n
       (empty)))\n
", _),
    process_metta_string("!(plunit-spec-rep plunit-spec-step 3 0)", [3]).

cleanup_recursive :-
    cleanup_specializer_symbols(['plunit-spec-rep', 'plunit-spec-step']).

test(exact_recursive_key_folds_to_specialized_predicate,
     [setup(setup_recursive), cleanup(cleanup_recursive)]) :-
    ho_specialization(_, 'plunit-spec-rep', SpecName),
    functor(Head, SpecName, 4),
    metta_self_module(Self),
    forall(clause(Self:Head, Body),
           \+ ( sub_term(GenericCall, Body),
                compound(GenericCall),
                functor(GenericCall, 'plunit-spec-rep', 4) )),
    Goal =.. [SpecName, 'plunit-spec-step', 1000, 0, Result],
    once(call(Self:Goal)),
    Result == 1000.

% The test above checks that the recursive step does not name the generic
% predicate. reduce/2 is the OTHER way back to it, at run time and under a
% functor the clause body never mentions, so the absence of one is a separate
% question. It is asked of the two-binding specialization at
% global_key_covers_every_specialized_argument_position and was asked of the
% recursive one nowhere.
%
% Measured 2026-08-18, min of three: the specialized predicate costs 8,004
% inferences over 1,000 steps against the generic path's 24,004, and 804
% against 2,404 over 100, so the saving is per step rather than one-off.
test(the_recursive_specialization_never_re_enters_the_reducer,
     [setup(setup_recursive), cleanup(cleanup_recursive)]) :-
    ho_specialization(_, 'plunit-spec-rep', SpecName),
    functor(Head, SpecName, 4),
    metta_self_module(Self),
    findall(Body, clause(Self:Head, Body), Bodies),
    %The base case and the recursive one. Counted rather than left open,
    %because "no clause holds a reduce/2" is vacuously true of a predicate
    %with no clauses, which is what a specialization that failed to publish
    %would leave behind.
    length(Bodies, 2),
    \+ ( member(Body, Bodies),
         sub_term(Reduce, Body),
         compound(Reduce),
         functor(Reduce, reduce, 2) ).

setup_failed_specialization_memo :-
    set_specializer_test_mode,
    load_specializer_regression(
        'repro1_failed_specialization_memo.metta', [1, 2, 3, 4, 5]).

cleanup_failed_specialization_memo :-
    cleanup_specializer_symbols([wrap, pass, wrap2, myfun]).

test(repeated_failed_specialization_is_recorded_once_per_function,
     [ setup(setup_failed_specialization_memo),
       cleanup(cleanup_failed_specialization_memo) ]) :-
    findall(F-Arity-Key,
            ho_specialization_failed(F, Arity, Key),
            Failures),
    Failures == [pass-3-[myfun], wrap-3-[myfun]].

setup_failed_specialization_chain :-
    set_specializer_test_mode,
    load_specializer_regression(
        'repro2_exponential_failed_specialization.metta', [1]).

cleanup_failed_specialization_chain :-
    findall(Name,
            ( between(1, 12, Index),
              atom_concat(f, Index, Name) ),
            Functions),
    append(Functions, [g, myfun], Names),
    cleanup_specializer_symbols(Names).

test(branching_failed_specialization_is_linear_in_chain_depth,
     [ setup(setup_failed_specialization_chain),
       cleanup(cleanup_failed_specialization_chain) ]) :-
    aggregate_all(count, ho_specialization_failed(_, _, _), 11),
    forall(between(1, 11, Index),
           ( atom_concat(f, Index, Function),
             ho_specialization_failed(Function, 3, [myfun]) )).

setup_failed_specialization_type :-
    set_specializer_test_mode,
    load_specializer_regression(
        'repro3_failed_specialization_self_leak.metta', _).

cleanup_failed_specialization_type :-
    cleanup_specializer_symbols([wrap, wrap2, myfun]).

test(failed_specialization_does_not_leak_generated_type,
     [ setup(setup_failed_specialization_type),
       cleanup(cleanup_failed_specialization_type) ]) :-
    once(get_native_atom(
        '&self', [':', wrap, ['->', 'Number', 'Number', 'Number']])),
    ho_specialization_failed(wrap, 3, [myfun]),
    \+ ( get_native_atom('&self', [':', Name, _]),
         atom(Name),
         sub_atom(Name, 0, _, _, 'wrap_Spec_') ).

:- dynamic variant_normalization_preexisting_lambda/1.

setup_variant_normalization :-
    retractall(silent(_)),
    assertz(silent(false)),
    %Snapshot the lambdas that exist BEFORE the repro runs: the engine
    %prelude compiles a foldl lambda of its own at boot, and sweeping
    %every lambda_ name in cleanup would unregister the prelude's.
    retractall(variant_normalization_preexisting_lambda(_)),
    forall(( fun(Name), atom(Name), sub_atom(Name, 0, _, _, lambda_) ),
           assertz(variant_normalization_preexisting_lambda(Name))).

cleanup_variant_normalization :-
    findall(Name,
            ( fun(Name),
              atom(Name),
              sub_atom(Name, 0, _, _, lambda_),
              \+ variant_normalization_preexisting_lambda(Name) ),
            LambdaNames),
    retractall(variant_normalization_preexisting_lambda(_)),
    cleanup_specializer_symbols([app|LambdaNames]).

test(compound_partial_key_has_stable_anonymous_variables,
     [ setup(setup_variant_normalization),
       cleanup(cleanup_variant_normalization) ]) :-
    with_output_to(
        string(Output),
        catch(load_specializer_regression(
                  'repro4_variant_normalization.metta', _),
              Error,
              true)),
    Error = error(instantiation_error, _),
    %The subject here is the STABLE `_` in the variant key, not the
    %lambda's index: boot-time compiles (the engine prelude's own foldl
    %lambda among them) advance the shared sequence before this file
    %loads, so the index is whatever the boot left. Match the key by its
    %stable frame and recover the actual name from the output.
    re_matchsub("app_Spec_\\[partial\\(lambda_\\d+,\\[_\\]\\)\\]",
                Output, Sub, []),
    get_dict(0, Sub, SpecStr),
    atom_string(SpecName, SpecStr),
    \+ ho_specialization(_, app, _),
    \+ fun(SpecName),
    \+ arity(SpecName, _),
    \+ fun_meta_clause(SpecName, _, _),
    functor(SpecHead, SpecName, 3),
    \+ clause(SpecHead, _),
    \+ get_native_atom('&self', [=, [SpecName|_], _]).

setup_named_space_specialization :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-ns-bump $n) (+ $n 1))\n
(= (plunit-spec-ns-twice $f $x) ($f ($f $x)))\n
", _, '&plunit_spec_ns').

cleanup_named_space_specialization :-
    cleanup_specializer_symbols(['plunit-spec-ns-twice', 'plunit-spec-ns-bump']),
    clear_native_atoms('&plunit_spec_ns').

test(higher_order_code_runs_inside_a_named_space,
     [ setup(setup_named_space_specialization),
       cleanup(cleanup_named_space_specialization) ]) :-
    % The generated clause used to be asserted into user, where the space's
    % own functions do not exist, so this crashed on its first call with
    % Unknown procedure: plunit-spec-ns-bump/2.
    process_metta_string("!(plunit-spec-ns-twice plunit-spec-ns-bump 0)",
                         [2], '&plunit_spec_ns').

:- end_tests(specializer).

:- begin_tests(specializer_invalidation).

% invalidate_specializations/1 recurses through ho_specialization/3 and
% retracts only AFTER descending, so a cycle among those facts would not
% terminate. It is called unguarded from three engine write sites and, since
% the register-an-operation path stopped swallowing its failures, from there
% too, where a hang is worse than the swallowed failure it replaced.
%
% No cycle is reachable today, because the recursive-specialization fold
% reuses the active name rather than recording a new fact. This constructs one
% directly, which is the only way to exercise the guard at all: without the
% visited set the goal below does not return.
test(an_invalidation_cycle_terminates,
     [ setup(( assertz(user:ho_specialization(plunit_cycle_a, plunit_cycle_a,
                                              plunit_cycle_b)),
               assertz(user:ho_specialization(plunit_cycle_b, plunit_cycle_b,
                                              plunit_cycle_a)) )),
       cleanup(( retractall(user:ho_specialization(plunit_cycle_a, _, _)),
                 retractall(user:ho_specialization(plunit_cycle_b, _, _)) )) ]) :-
    call_with_inference_limit(invalidate_specializations(plunit_cycle_a),
                              100000, Outcome),
    assertion(Outcome \== inference_limit_exceeded),
    assertion(\+ user:ho_specialization(_, plunit_cycle_a, _)),
    assertion(\+ user:ho_specialization(_, plunit_cycle_b, _)).

test(a_tabled_function_never_specializes,
     [ setup(( sread("(= (spt-loop $x $y) (spt-loop $y $x))", Eq),
               add_sexp('&self', Eq),
               translate_clause(Eq, Clause),
               assertz(Clause),
               assertz(fun('spt-loop')),
               assertz(arity('spt-loop', 3)),
               add_sexp('&petta', [tabled, '&self', 'spt-loop', 2]) )),
       cleanup(( remove_sexp('&petta', [tabled, '&self', 'spt-loop', 2]),
                 remove_sexp('&self', [=, ['spt-loop'|_], _]),
                 retractall(fun('spt-loop')),
                 retractall(arity('spt-loop', _)) )) ]) :-
    % The reflection fact says spt-loop is tabled, so a call whose
    % argument names a defined function must NOT plan a specialization:
    % the clone would carry the recursion without the tabling. The
    % 27,525-frame precedent is recorded at maybe_specialize_call.
    \+ maybe_specialize_call('spt-loop', [d, x], _, _).

test(string_run_equation_invalidates_specializations,
     [ setup(assertz(user:ho_specialization(plunit_door_caller,
                                            'plunit-door-fn',
                                            plunit_door_spec))),
       cleanup(( retractall(user:ho_specialization(plunit_door_caller, _, _)),
                 remove_sexp('&self', [=, ['plunit-door-fn'|_], _]),
                 retractall(fun('plunit-door-fn')),
                 retractall(arity('plunit-door-fn', _)) )) ]) :-
    % The string-run door (process_form/3) used to notify
    % metta_on_function_changed and skip invalidate_specializations, so a
    % specialization of a name survived new equations for it. The one
    % compile door notifies completely; this pins that a run-defined
    % equation retracts the stale specialization record.
    process_metta_string("(= (plunit-door-fn $x) $x)", _),
    \+ user:ho_specialization(_, 'plunit-door-fn', _).

test(a_recursive_specialization_survives_its_compile,
     [ cleanup(( remove_sexp('&self', [=, ['plunit-tricky'|_], _]),
                 retractall(fun('plunit-tricky')),
                 retractall(arity('plunit-tricky', _)),
                 invalidate_specializations('plunit-tricky') )) ]) :-
    % A definition whose body calls ITSELF with a ground higher-order
    % argument compiles a clone for that call and a generic clause that
    % names it. Invalidating after the compile abolished that clone while
    % the clause naming it stood, so the generic path called an empty
    % predicate: the direct call still answered through its own
    % specialization, and a call arriving through a variable answered
    % NOTHING. Stale clones are dropped BEFORE the body compiles now.
    process_metta_string(
        "(= (plunit-tricky $f) (if (= ($f 1) 2) (plunit-tricky (+ 2)) ($f 1)))",
        _),
    process_metta_string("!(plunit-tricky (+ 1))", [Direct]),
    assertion(Direct == 3),
    process_metta_string("!(let $g (+ 1) (plunit-tricky $g))", [ViaVariable]),
    assertion(ViaVariable == 3).

:- end_tests(specializer_invalidation).
