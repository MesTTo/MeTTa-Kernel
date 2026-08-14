% Purpose: direct PlUnit coverage for core runtime builtins, their error
%   contracts, and Python import state cleanup.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(metta_assertions).

test(passing_test_returns_true_and_keeps_output) :-
    with_output_to(string(Output), test(1, 1, Result)),
    Result == true,
    Output == "is 1, should 1. ✅ \n".

test(failing_test_is_catchable,
     [throws(error(petta_test_failed(1, 2), _))]) :-
    test(1, 2, _).

test(failing_assert_is_catchable,
     [throws(error(petta_assertion_failed(fail), _))]) :-
    assert(fail, _).

test(assertion_errors_have_engine_messages) :-
    message_to_string(error(petta_test_failed(1, 2), none), Message),
    sub_string(Message, _, _, _, "MeTTa test failed: 1 does not match 2"),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(metta_assertions).

:- begin_tests(metta_metatypes).

metatype_case(partial(f, [1]), 'Grounded').
metatype_case(f(1), 'Grounded').
metatype_case([f, 1], 'Expression').
metatype_case(f, 'Symbol').

test(every_runtime_term_has_a_metatype,
     [forall(metatype_case(Term, Expected))]) :-
    'get-metatype'(Term, Actual),
    Actual == Expected.

:- end_tests(metta_metatypes).

:- begin_tests(metta_index_atom).

test(out_of_range_index_returns_the_empty_expression) :-
    'index-atom'([a, b], 5, Out),
    Out == [].

test(noninteger_index_returns_the_empty_expression) :-
    'index-atom'([a, b], bad, Out),
    Out == [].

test(prebound_wrong_output_is_rejected, [fail]) :-
    'index-atom'([a, b], 0, wrong).

test(variable_index_still_enumerates,
     [true(Pairs == [0-a, 1-b])]) :-
    findall(Index-Elem, 'index-atom'([a, b], Index, Elem), Pairs).

:- end_tests(metta_index_atom).

:- begin_tests(metta_builtin_outputs).

wrong_prebound_output('car-atom'([a, b], [])).
wrong_prebound_output('cdr-atom'([a, b], [])).
wrong_prebound_output('is-alpha-member'(a, [a, b], false)).
wrong_prebound_output('#<'(1, 2, false)).
wrong_prebound_output('#>'(2, 1, false)).
wrong_prebound_output('#='(1, 1, false)).
wrong_prebound_output('#\\='(1, 2, false)).
wrong_prebound_output(repr(true, true)).

produced_outputs(car, Out) :- 'car-atom'([a, b], Out).
produced_outputs(cdr, Out) :- 'cdr-atom'([a, b], Out).
produced_outputs(alpha_member, Out) :- 'is-alpha-member'(a, [a, b], Out).
produced_outputs(clp_less, Out) :- '#<'(1, 2, Out).
produced_outputs(clp_greater, Out) :- '#>'(2, 1, Out).
produced_outputs(clp_equal, Out) :- '#='(1, 1, Out).
produced_outputs(clp_different, Out) :- '#\\='(1, 2, Out).
produced_outputs(representation, Out) :- repr(true, Out).

expected_outputs(car, [a]).
expected_outputs(cdr, [[b]]).
expected_outputs(alpha_member, [true]).
expected_outputs(clp_less, [true]).
expected_outputs(clp_greater, [true]).
expected_outputs(clp_equal, [true]).
expected_outputs(clp_different, [true]).
expected_outputs(representation, ["true"]).

test(prebound_outputs_must_be_producible,
     [forall(wrong_prebound_output(Goal)), fail]) :-
    call(Goal).

test(unbound_outputs_remain_exact_and_deterministic,
     [forall(expected_outputs(Label, Expected))]) :-
    findall(Out, produced_outputs(Label, Out), Actual),
    Actual == Expected.

test(translated_let_rejects_an_impossible_comparison_output) :-
    setup_call_cleanup(assertz(silent(true), Ref),
                       process_metta_string("!(let false (#< 1 2) WRONG)",
                                            Results),
                       erase(Ref)),
    Results == [].

:- end_tests(metta_builtin_outputs).

:- begin_tests(metta_translator_rules,
               [ setup((retractall(user:translator_rule(_)),
                        assertz(user:translator_rule(first)),
                        assertz(user:translator_rule(second)))),
                 cleanup(retractall(user:translator_rule(_))) ]).

test(variable_removal_is_rejected_without_mutation,
     [throws(error(instantiation_error, _))]) :-
    catch('remove-translator-rule!'(_, _), Error,
          ( findall(Rule, user:translator_rule(Rule), Rules),
            Rules == [first, second],
            throw(Error) )).

test(ground_removal_only_removes_its_rule,
     [true(Rules == [second])]) :-
    'remove-translator-rule!'(first, true),
    findall(Rule, user:translator_rule(Rule), Rules).

:- end_tests(metta_translator_rules).

:- begin_tests(metta_python_import_cleanup).

write_import_fixture(Path) :-
    setup_call_cleanup(open(Path, write, Out),
                       format(Out, 'VALUE = 1~n', []),
                       close(Out)).

clear_python_test_module(Name) :-
    ( py_call(sys:modules:'__contains__'(Name), @(true))
      -> py_call(sys:modules:pop(Name), _)
       ; true ).

exercise_python_import_setup_failure(Directory) :-
    gensym(petta_cleanup_, Suffix),
    format(atom(MainName), 'petta_cleanup_main_~w', [Suffix]),
    format(atom(SiblingName), 'petta_cleanup_sibling_~w', [Suffix]),
    file_name_extension(MainName, py, MainFile),
    file_name_extension(SiblingName, py, SiblingFile),
    directory_file_path(Directory, MainFile, MainPath),
    directory_file_path(Directory, SiblingFile, SiblingPath),
    write_import_fixture(MainPath),
    write_import_fixture(SiblingPath),
    py_call(builtins:object(), OriginalModule, [py_object(true)]),
    py_call(builtins:id(OriginalModule), OriginalId),
    py_call(importlib:util, ImportUtil, [py_object(true)]),
    py_call(ImportUtil:spec_from_file_location, OriginalSpec,
            [py_object(true)]),
    py_call(builtins:int, RaisingCallable, [py_object(true)]),
    setup_call_cleanup(
        py_call(sys:modules:'__setitem__'(SiblingName, OriginalModule), _),
        setup_call_cleanup(
            py_setattr(ImportUtil, spec_from_file_location, RaisingCallable),
            ( catch(load_python_source(MainPath), Error, true),
              nonvar(Error),
              py_call(sys:modules:'__contains__'(SiblingName), Present),
              Present == @(true),
              py_call(sys:modules:get(SiblingName), RestoredModule,
                      [py_object(true)]),
              py_call(builtins:id(RestoredModule), RestoredId),
              RestoredId =:= OriginalId ),
            py_setattr(ImportUtil, spec_from_file_location, OriginalSpec)),
        clear_python_test_module(SiblingName)).

test(setup_failure_restores_preexisting_sibling_module) :-
    tmp_file(petta_python_import, Directory),
    setup_call_cleanup(make_directory(Directory),
                       exercise_python_import_setup_failure(Directory),
                       delete_directory_and_contents(Directory)).

:- end_tests(metta_python_import_cleanup).

:- begin_tests(metta_set_operations).

%The tuple set operations remove by equality, not by unification. select/3
%unified, so (subtraction-atom ($x) (a)) answered () and left $x bound to a
%afterwards. PeTTa's formalisation removes with removeFirstEq, an == test:
%MeTTapedia/lean/mettapedia/leanPeTTa/StreamOps.lean.
test(subtraction_keeps_an_unbound_element,
     [true(Out == [X])]) :-
    'subtraction-atom'([X], [a], Out).

test(subtraction_does_not_bind_its_input) :-
    'subtraction-atom'([X], [a], _),
    var(X).

test(intersection_does_not_match_a_variable_against_an_atom,
     [true(Out == [])]) :-
    'intersection-atom'([_X], [a], Out).

test(intersection_does_not_bind_its_input) :-
    'intersection-atom'([X], [a], _),
    var(X).

%Identical variables still cancel, so the operations stay multiset operations
%over the terms they are given.
test(subtraction_removes_an_identical_variable,
     [true(Out == [])]) :-
    'subtraction-atom'([X], [X], Out).

test(subtraction_keeps_documented_multiplicities,
     [true(Out == [a, b])]) :-
    'subtraction-atom'([a, b, b, c], [b, c, c, d], Out).

test(intersection_keeps_documented_multiplicities,
     [true(Out == [b, c, c])]) :-
    'intersection-atom'([a, b, c, c], [b, c, c, c, d], Out).

test(subtraction_of_a_non_list_is_empty,
     [true(Out == [])]) :-
    'subtraction-atom'(a, [a], Out).

:- end_tests(metta_set_operations).
