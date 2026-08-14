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
    once(call(Goal)),
    Out == 2.

test(concurrent_translation_creates_one_specialization,
     [ setup(setup_concurrent_specialization),
       cleanup(cleanup_concurrent_specialization) ]) :-
    concurrent_forall(between(1, 64, Worker),
                      run_concurrent_specialization(Worker),
                      [threads(64)]),
    findall(SpecName,
            ho_specialization('plunit-spec-race', SpecName),
            Specializations),
    Specializations = [SpecName],
    functor(Head, SpecName, 3),
    aggregate_all(count, clause(Head, _), 1),
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
    ho_specialization('plunit-spec-t2', SpecName),
    SpecName == 'plunit-spec-t2_Spec_[plunit-spec-inc]',
    functor(Head, SpecName, 3),
    findall(Head-Body, clause(Head, Body), Clauses),
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
    ho_specialization('plunit-spec-p2', SpecName),
    SpecName ==
        'plunit-spec-p2_Spec_[plunit-spec-inc2,plunit-spec-dbl2]',
    functor(Head, SpecName, 4),
    findall(Body, clause(Head, Body), Bodies),
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
    ho_specialization('plunit-spec-rep', SpecName),
    functor(Head, SpecName, 4),
    forall(clause(Head, Body),
           \+ ( sub_term(GenericCall, Body),
                compound(GenericCall),
                functor(GenericCall, 'plunit-spec-rep', 4) )),
    Goal =.. [SpecName, 'plunit-spec-step', 1000, 0, Result],
    once(call(Goal)),
    Result == 1000.

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

setup_variant_normalization :-
    retractall(silent(_)),
    assertz(silent(false)).

cleanup_variant_normalization :-
    findall(Name,
            ( fun(Name),
              atom(Name),
              sub_atom(Name, 0, _, _, lambda_) ),
            LambdaNames),
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
    SpecName = 'app_Spec_[partial(lambda_1,[_])]',
    once(sub_string(Output, _, _, _, SpecName)),
    \+ ho_specialization(app, _),
    \+ fun(SpecName),
    \+ arity(SpecName, _),
    \+ fun_meta_clause(SpecName, _, _),
    functor(SpecHead, SpecName, 3),
    \+ clause(SpecHead, _),
    \+ get_native_atom('&self', [=, [SpecName|_], _]).

:- end_tests(specializer).
