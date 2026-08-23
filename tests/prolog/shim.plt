% Purpose: test the Python bridge's wire codec directly, in Prolog.
% Assumes:
%   - shim.pl loads without the engine, since the codec touches no engine
%     state [tested: every suite below consults only shim.pl].
% Guarantees:
%   - Every wire tag decodes to its term in both the atom and the string
%     spelling janus may deliver [tested: shim_wire_decoding].
%   - A malformed wire term fails rather than decoding to something
%     [tested: shim_wire_decoding:a_malformed_wire_term_fails].
%   - A payload outside the class its tag names fails too, in both the
%     plain and the sharing decode
%     [tested: shim_wire_decoding:a_payload_outside_its_tags_class_fails].
%   - native equality does not walk a whole expression merely to classify it
%     [tested: comparing_against_the_empty_expression_does_not_walk_the_other_operand;
%     commit=fddb28afcb066271d1f0c78fad8b578b2ab65ccd].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- consult('../../bindings/python/metta/shim.pl').

:- prolog_load_context(directory, TestDirectory),
   absolute_file_name('../../bindings/python', PythonBindingDirectory,
                      [relative_to(TestDirectory), file_type(directory)]),
   py_call(sys:path:insert(0, PythonBindingDirectory), _),
   py_call(sys:path:insert(0, TestDirectory), _).

% Both tables sit at file scope because a plunit unit is its own module and
% the suites below share them.
%
% tag, payload, the term it must decode to
decodes('n', 1, 1).
decodes('n', -2.5, -2.5).
decodes('s', "foo", foo).
decodes('s', bar, bar).
decodes('g', "text", "text").
decodes('b', true, true).
decodes('b', false, false).
decodes('b', '@'(true), true).
decodes('b', "true", true).
decodes('o', an_opaque_object, an_opaque_object).

malformed(['zz', 1]).            % a tag no clause claims
malformed([1, 2]).               % a tag that is neither atom nor string
malformed([f(x), 1]).            % a compound tag, which must not reach atom_string/2
malformed(['n']).                % a payload short of one
malformed(['n', 1, 2]).          % a payload long by one
malformed([]).
malformed(notalist).
malformed(['e', "notalist"]).

% A payload of the wrong class for its tag. Each of these decoded to
% SOMETHING before the tags carried a claim about their payloads: the
% first two to symbols, the next two to a string and to a number-tagged
% string, the variable to a fresh variable, and every unadmitted boolean
% payload to `false`, which answers rather than fails.
% bindings/python/metta/_atom_wire.py refuses all six.
wrong_class(['s', 1]).
wrong_class(['s', ["a"]]).
wrong_class(['g', 1]).
wrong_class(['n', "1/3"]).
wrong_class(['n', '@'(true)]).
wrong_class(['v', 1]).
wrong_class(['b', neither]).
wrong_class(['b', 1]).
wrong_class(['b', "maybe"]).

% The decoder used to decide a tag by asking petta_py_tag/2 about each
% candidate in turn, so every clause carried its own copy of that question and
% the shape of a wire term was never stated in one place. It is stated here
% instead: nothing else in the tree tests the codec from the Prolog side, and
% the Python side cannot see a leftover choicepoint or an unreachable clause.
:- begin_tests(shim_wire_decoding).

test(every_tag_decodes, [forall(decodes(Tag, Payload, Expected))]) :-
    petta_py_decode([Tag, Payload], Term),
    Term == Expected.

% janus delivers a Python str as either an atom or a string depending on the
% call, so both spellings of the tag itself have to reach the same clause.
test(a_tag_may_arrive_as_an_atom_or_a_string,
     [forall(decodes(Tag, Payload, Expected))]) :-
    atom_string(Tag, TagString),
    petta_py_decode([TagString, Payload], Term),
    Term == Expected.

test(both_boolean_payload_spellings_decode,
     [forall(member(Payload-Expected,
                    [true-true, false-false, '@'(true)-true, '@'(false)-false,
                     "true"-true, "false"-false]))]) :-
    petta_py_decode(['b', Payload], Term),
    Term == Expected.

test(a_payload_outside_its_tags_class_fails, [forall(wrong_class(Wire)), fail]) :-
    petta_py_decode(Wire, _).

test(a_payload_outside_its_tags_class_fails_when_sharing,
     [forall(wrong_class(Wire)), fail]) :-
    petta_py_decode_shared(Wire, _, _).

test(a_variable_decodes_to_a_variable) :-
    petta_py_decode(['v', "x"], Term),
    var(Term).

test(a_nested_expression_decodes_through) :-
    petta_py_decode(['e', [['s', "f"], ['n', 1], ['e', [['s', "g"], ['n', 2]]]]],
                    Term),
    Term == [f, 1, [g, 2]].

test(a_malformed_wire_term_fails, [forall(malformed(Wire)), fail]) :-
    petta_py_decode(Wire, _).

test(a_malformed_wire_term_fails_when_sharing,
     [forall(malformed(Wire)), fail]) :-
    petta_py_decode_shared(Wire, _, _).

:- end_tests(shim_wire_decoding).

% Sharing is the half of the codec that reading a query's answers depends on,
% and it is decided by the variable's NAME rather than by its position.
:- begin_tests(shim_wire_variable_sharing).

test(one_name_decodes_to_one_variable) :-
    petta_py_decode_shared(['e', [['v', "x"], ['v', "x"]]], Term, Bindings),
    Term = [A, B],
    A == B,
    Bindings == ['x'-A].

test(two_names_decode_to_two_variables) :-
    petta_py_decode_shared(['e', [['v', "x"], ['v', "y"]]], Term, Bindings),
    Term = [A, B],
    A \== B,
    length(Bindings, 2).

% The anonymous variable is fresh at every occurrence, exactly as the reader
% treats $_ in source. Recording it would make two underscores constrain each
% other, which is a wrong answer rather than an untidy one.
test(anonymous_variables_never_share) :-
    petta_py_decode_shared(['e', [['v', "_"], ['v', "_"]]], Term, Bindings),
    Term = [A, B],
    A \== B,
    Bindings == [].

test(a_name_shares_across_nesting) :-
    petta_py_decode_shared(['e', [['v', "x"], ['e', [['s', "f"], ['v', "x"]]]]],
                           Term, _),
    Term = [A, [f, B]],
    A == B.

% Every leaf below a shared decode is the plain decode with the bindings
% unchanged, so the two halves cannot answer different terms.
test(sharing_decodes_leaves_as_the_plain_decode_does,
     [forall(decodes(Tag, Payload, Expected))]) :-
    petta_py_decode_shared([Tag, Payload], Term, Bindings),
    Term == Expected,
    Bindings == [].

:- end_tests(shim_wire_variable_sharing).

% Python's scalar comparison and truth rules are decided in the engine when
% both values are represented losslessly by the wire. The explicit host
% predicate remains the oracle and the fallback for opaque objects.
:- begin_tests(shim_python_scalar_semantics).

python_eq_case(1, 1, true).
python_eq_case(1, 1.0, true).
python_eq_case(1.5, 1.5, true).
python_eq_case(true, 1, true).
python_eq_case("same", "same", true).
python_eq_case("same", same, false).
python_eq_case(-0.0, 0.0, true).
python_eq_case(1, "1", false).
python_eq_case(false, [], false).

python_truth_case(0, false).
python_truth_case(0.0, false).
python_truth_case(7, true).
python_truth_case("", false).
python_truth_case("text", true).
python_truth_case(false, false).
python_truth_case(true, true).
python_truth_case([], false).
python_truth_case([0], true).

python_host_eq(Left, Right, Result) :-
    petta_py_encode(Left, LeftWire),
    petta_py_encode(Right, RightWire),
    py_call(python_semantics_oracle:py_eq_wire(LeftWire, RightWire), Python),
    python_boolean_atom(Python, Result).

python_host_truthy(Value, Result) :-
    petta_py_encode(Value, Wire),
    py_call(python_semantics_oracle:py_truthy_wire(Wire), Python),
    python_boolean_atom(Python, Result).

python_boolean_atom('@'(true), true).
python_boolean_atom('@'(false), false).

test(the_native_and_host_equality_routes_agree,
     [forall(python_eq_case(Left, Right, Expected))]) :-
    once(petta_py_native_eq(Left, Right, Native)),
    python_host_eq(Left, Right, Host),
    Native == Expected,
    Host == Native.

test(the_native_and_host_truth_routes_agree,
     [forall(python_truth_case(Value, Expected))]) :-
    once(petta_py_native_truthy(Value, Native)),
    python_host_truthy(Value, Host),
    Native == Expected,
    Host == Native.

test(nan_is_not_equal_to_itself) :-
    NaN is nan,
    once(petta_py_native_eq(NaN, NaN, false)).

test(an_opaque_object_is_left_for_the_host, [fail]) :-
    petta_py_native_eq('$opaque'(value), '$opaque'(value), _).

test(an_opaque_objects_truth_is_left_for_the_host, [fail]) :-
    petta_py_native_truthy('$opaque'(value), _).

%is_list/1 is one inference however much C work it performs, so this defect
%class needs a CPU-time test. A sixteen-times-wider operand gives a wide margin:
%a whole-operand classification grows by about sixteen while the outer-cell
%classification remains constant. Both readings share one process and the
%lists are built before the timed region.
native_empty_expression_comparison_cost(Length, Seconds) :-
    findall(e, between(1, Length, _), Expression),
    forall(between(1, 100, _),
           petta_py_dispatch_eq(Expression, [], false)),
    statistics(cputime, Before),
    forall(between(1, 5000, _),
           petta_py_dispatch_eq(Expression, [], false)),
    statistics(cputime, After),
    Seconds is After - Before.

test(comparing_against_the_empty_expression_does_not_walk_the_other_operand) :-
    native_empty_expression_comparison_cost(400, Narrow),
    native_empty_expression_comparison_cost(6400, Wide),
    assertion(Wide < Narrow * 4).

:- end_tests(shim_python_scalar_semantics).

:- begin_tests(shim_answer_form).

% The explicit answer wire: ["a", Theta, Residue, K] with an optional
% trailing value. Theta binds the query frame's variables BY NAME, the
% names petta_py_encode/2 wrote, so these build the pattern first and ask
% for its variable's name the same way the encoder does.

answer_name(Variable, Name) :- term_to_atom(Variable, A), atom_string(A, Name).

test(theta_binds_the_pattern_variable_by_name) :-
    Pattern = [edge, a, Y],
    answer_name(Y, N),
    petta_py_answer_match(["a", [[N, ["s", "b"]]], '@'(true), '@'(none)], Pattern, '&plunit_ctx'),
    assertion(Y == b).

test(the_atom_tag_spelling_is_accepted_too) :-
    Pattern = [edge, a, Y],
    answer_name(Y, N),
    petta_py_answer_match([a, [[N, ["s", "b"]]], '@'(true), '@'(none)], Pattern, '&plunit_ctx'),
    assertion(Y == b).

test(an_explicit_value_unifies_under_theta) :-
    Pattern = [edge, a, Y],
    answer_name(Y, N),
    petta_py_answer_match(["a", [[N, ["s", "b"]]], '@'(true), '@'(none),
                           ["e", [["s", "edge"], ["s", "a"], ["s", "b"]]]],
                          Pattern, '&plunit_ctx'),
    assertion(Y == b).

test(a_value_contradicting_theta_drops_the_answer, [fail]) :-
    Pattern = [edge, a, Y],
    answer_name(Y, N),
    petta_py_answer_match(["a", [[N, ["s", "clash"]]], '@'(true), '@'(none),
                           ["e", [["s", "edge"], ["s", "a"], ["s", "b"]]]],
                          Pattern, '&plunit_ctx').

test(unknown_theta_names_stay_fresh_and_harmless) :-
    Pattern = [edge, a, Y],
    petta_py_answer_match(["a", [["nobody", ["n", 3]]], '@'(true), '@'(none)],
                          Pattern, '&plunit_ctx'),
    assertion(var(Y)).

test(theta_values_may_alias_the_patterns_own_variables) :-
    Pattern = [edge, X, Y],
    answer_name(X, NX),
    answer_name(Y, NY),
    petta_py_answer_match(["a", [[NY, ["v", NX]]], '@'(true), '@'(none)],
                          Pattern, '&plunit_ctx'),
    assertion(X == Y).

test(a_plain_wire_still_decodes_and_unifies) :-
    Pattern = [edge, a, Y],
    petta_py_answer_match(["e", [["s", "edge"], ["s", "a"], ["s", "b"]]],
                          Pattern, '&plunit_ctx'),
    assertion(Y == b).

test(a_residue_under_a_pushed_bound_is_refused,
     [throws(error(petta_answer_conditional_under_bound(_, _), _))]) :-
    petta_py_answer_match(["a", [], ["e", [["s", "check"]]], '@'(none)],
                          [edge, a, _], 2, '&plunit_ctx').

test(an_op_result_without_a_value_is_unit) :-
    Args = [X],
    answer_name(X, N),
    petta_py_answer_result(["a", [[N, ["n", 1]]], '@'(true), '@'(none)],
                           plunit_op, Args, Result),
    assertion(X == 1),
    assertion(Result == []).

test(an_op_result_with_a_value_decodes_under_theta) :-
    Args = [X],
    answer_name(X, N),
    petta_py_answer_result(["a", [[N, ["n", 1]]], '@'(true), '@'(none),
                            ["e", [["s", "pair"], ["v", N], ["s", "done"]]]],
                           plunit_op, Args, Result),
    assertion(X == 1),
    assertion(Result == [pair, 1, done]).

test(a_plain_op_result_shares_the_argument_variable) :-
    Args = [X],
    answer_name(X, N),
    petta_py_answer_result(["v", N], plunit_op, Args, Result),
    assertion(Result == X).

test(the_answer_errors_have_engine_messages) :-
    message_to_string(error(petta_answer_conditional_under_bound([edge, a, _],
                                                                 [check]),
                            none), M1),
    once(sub_string(M1, _, _, _, "residue")),
    once(sub_string(M1, _, _, _, "Sound")),
    \+ sub_string(M1, _, _, _, "Unknown error term"),
    message_to_string(error(petta_answer_annotation_undeclared('&c', 0.5), none),
                      M2),
    once(sub_string(M2, _, _, _, "annotation")),
    once(sub_string(M2, _, _, _, "ranked")),
    \+ sub_string(M2, _, _, _, "Unknown error term").

:- end_tests(shim_answer_form).
