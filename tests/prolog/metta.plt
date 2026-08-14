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
