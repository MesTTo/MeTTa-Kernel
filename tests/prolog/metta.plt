% Purpose: direct PlUnit coverage for core runtime builtins and their error
%   contracts, independent of the file reader and Python bridge.
% Open Obligations:
%   To Do: Add relational builtin and atom-registration cases from the engine
%     review.
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
