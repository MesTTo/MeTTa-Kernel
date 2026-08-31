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
%   - relation rows bind indexed call arguments in one monotone argument walk,
%     filter contradictory ground candidates, and terminal generator errors
%     retain their Python class [tested: shim_relation_form; commit=6917bef7ca902671999eafcae3a7a86db8f69723].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- consult('../../../../extensions/python/metta/shim.pl').

%The bridge normally reaches the engine matcher here. This engineless codec
%suite supplies its structural core so the relation-frame indexing can be
%tested without changing the suite's load contract; test_ops.py exercises the
%real matcher, including numeric promotion.
metta_match_atoms(Left, Right) :-
    unify_with_occurs_check(Left, Right).

%The same, for the species question the `p` tag asks. The encoder consults
%engine/spaces.pl's metta_space_operand/1, so engine-free it consults this:
%the two spaces the engine holds from boot, which is what that predicate
%answers in a fresh runtime. The codec's SHAPE is what this suite tests, and
%test_r2_space_handle.py, test_codec_conformance.py and test_c_binding.py
%exercise the real question against a live engine.
metta_space_operand('&self').
metta_space_operand('&metta').

%extensions/python/bridge.pl's, which this engine-free suite does not load.
%metta_py_encode/2's tuple clause calls it before its compound clause, so
%without this every non-list compound raises Unknown procedure here while
%encoding perfectly well in a live engine. Supplied for the same reason the
%two predicates above are: the CODEC is what this suite tests.
metta_py_tuple_arguments(Tuple, Arguments) :-
    compound(Tuple),
    compound_name_arity(Tuple, -, _),
    compound_name_arguments(Tuple, -, Arguments).

%Both directories are resolved against THIS FILE rather than against the
%working directory, because a load-time directive is. python_semantics_oracle
%lives beside the .pl machinery in tests/prolog, two levels up from a suite
%group, and it is what the equality and truth tests call across the wire.
:- prolog_load_context(directory, SuiteDirectory),
   absolute_file_name('../../../../extensions/python', PythonBindingDirectory,
                      [relative_to(SuiteDirectory), file_type(directory)]),
   absolute_file_name('../..', PrologTestDirectory,
                      [relative_to(SuiteDirectory), file_type(directory)]),
   py_call(sys:path:insert(0, PythonBindingDirectory), _),
   py_call(sys:path:insert(0, PrologTestDirectory), _).

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
% extensions/python/metta/_atom_wire.py refuses all six.
wrong_class(['s', 1]).
wrong_class(['s', ["a"]]).
wrong_class(['g', 1]).
wrong_class(['n', "1/3"]).
wrong_class(['n', '@'(true)]).
wrong_class(['v', 1]).
wrong_class(['b', neither]).
wrong_class(['b', 1]).
wrong_class(['b', "maybe"]).

% Every variable name a wire term carries, in the order the encoder wrote
% them. The proof-tree tests below ask how MANY distinct names one term
% spends, which is the question metta_py_encode_tree/4 answers wrongly when a
% variable is named once per occurrence instead of once per variable.
wire_variable_name([Tag, Name], Name) :- metta_py_tag(Tag, v).
wire_variable_name([Tag, Elements], Name) :-
    metta_py_tag(Tag, e),
    member(Element, Elements),
    wire_variable_name(Element, Name).

wire_variable_names(Term, Names) :-
    findall(Name, wire_variable_name(Term, Name), Found),
    sort(Found, Names).

% The decoder used to decide a tag by asking metta_py_tag/2 about each
% candidate in turn, so every clause carried its own copy of that question and
% the shape of a wire term was never stated in one place. It is stated here
% instead: nothing else in the tree tests the codec from the Prolog side, and
% the Python side cannot see a leftover choicepoint or an unreachable clause.
:- begin_tests(shim_wire_decoding).

test(every_tag_decodes, [forall(decodes(Tag, Payload, Expected))]) :-
    metta_py_decode([Tag, Payload], Term),
    Term == Expected.

% janus delivers a Python str as either an atom or a string depending on the
% call, so both spellings of the tag itself have to reach the same clause.
test(a_tag_may_arrive_as_an_atom_or_a_string,
     [forall(decodes(Tag, Payload, Expected))]) :-
    atom_string(Tag, TagString),
    metta_py_decode([TagString, Payload], Term),
    Term == Expected.

test(both_boolean_payload_spellings_decode,
     [forall(member(Payload-Expected,
                    [true-true, false-false, '@'(true)-true, '@'(false)-false,
                     "true"-true, "false"-false]))]) :-
    metta_py_decode(['b', Payload], Term),
    Term == Expected.

test(a_payload_outside_its_tags_class_fails, [forall(wrong_class(Wire)), fail]) :-
    metta_py_decode(Wire, _).

test(a_payload_outside_its_tags_class_fails_when_sharing,
     [forall(wrong_class(Wire)), fail]) :-
    metta_py_decode_shared(Wire, _, _).

test(a_variable_decodes_to_a_variable) :-
    metta_py_decode(['v', "x"], Term),
    var(Term).

test(a_nested_expression_decodes_through) :-
    metta_py_decode(['e', [['s', "f"], ['n', 1], ['e', [['s', "g"], ['n', 2]]]]],
                    Term),
    Term == [f, 1, [g, 2]].

test(a_malformed_wire_term_fails, [forall(malformed(Wire)), fail]) :-
    metta_py_decode(Wire, _).

test(a_malformed_wire_term_fails_when_sharing,
     [forall(malformed(Wire)), fail]) :-
    metta_py_decode_shared(Wire, _, _).

:- end_tests(shim_wire_decoding).

% Sharing is the half of the codec that reading a query's answers depends on,
% and it is decided by the variable's NAME rather than by its position.
:- begin_tests(shim_wire_variable_sharing).

test(one_name_decodes_to_one_variable) :-
    metta_py_decode_shared(['e', [['v', "x"], ['v', "x"]]], Term, Bindings),
    Term = [A, B],
    A == B,
    Bindings == ['x'-A].

test(two_names_decode_to_two_variables) :-
    metta_py_decode_shared(['e', [['v', "x"], ['v', "y"]]], Term, Bindings),
    Term = [A, B],
    A \== B,
    length(Bindings, 2).

% The anonymous variable is fresh at every occurrence, exactly as the reader
% treats $_ in source. Recording it would make two underscores constrain each
% other, which is a wrong answer rather than an untidy one.
test(anonymous_variables_never_share) :-
    metta_py_decode_shared(['e', [['v', "_"], ['v', "_"]]], Term, Bindings),
    Term = [A, B],
    A \== B,
    Bindings == [].

test(a_name_shares_across_nesting) :-
    metta_py_decode_shared(['e', [['v', "x"], ['e', [['s', "f"], ['v', "x"]]]]],
                           Term, _),
    Term = [A, [f, B]],
    A == B.

% Every leaf below a shared decode is the plain decode with the bindings
% unchanged, so the two halves cannot answer different terms.
test(sharing_decodes_leaves_as_the_plain_decode_does,
     [forall(decodes(Tag, Payload, Expected))]) :-
    metta_py_decode_shared([Tag, Payload], Term, Bindings),
    Term == Expected,
    Bindings == [].

% A proof tree is one term, so one variable in it is one name however many
% times it occurs. Naming each OCCURRENCE through term_to_atom/2 spends a
% name per print, and SWI prints an unbound variable from its global-stack
% offset, so a collection between two occurrences wrote two names and the
% sharing decoder above read two variables.
%
% These three count names rather than spell them: the contract is that one
% variable spends one name, not that the first one is called "_0". The
% spelling is pinned nowhere, so a renaming scheme is free to change.
test(one_equation_variable_spends_one_name) :-
    Equation = ['=', [fact, V],
                [if, ['>', V, 0], ['*', V, [fact, ['-', V, 1]]], 1]],
    metta_py_encode_tree([step(fact(5, 120), Equation, [])], [fact, 5], 120,
                         Encoded),
    wire_variable_names(Encoded, Names),
    length(Names, 1).

test(two_equation_variables_spend_two_names) :-
    Equation = ['=', [swap, X, Y], [swap, Y, X]],
    metta_py_encode_tree([step(swap(1, 2, [swap, 2, 1]), Equation, [])],
                         [swap, 1, 2], [swap, 2, 1], Encoded),
    wire_variable_names(Encoded, Names),
    length(Names, 2).

% The naming has to reach the GOALS as well as the equations. A goal is a
% compiled call, which is a non-list compound, and metta_py_encode_named/3
% carries its pairs through variables and lists only; naming half a tree and
% not the other half splits a variable a parent equation and a child goal
% share, which is the same wrong answer by another route. Three variables
% here: the root's answer, the outer equation's, and the inner equation's.
test(a_variable_shared_by_a_parent_equation_and_a_child_goal_spends_one_name) :-
    Outer = ['=', [outer, A], [inner, A]],
    Inner = ['=', [inner, B], B],
    metta_py_encode_tree([step(outer(1, Out), Outer,
                               [step(inner(A, Out), Inner, [])])],
                         [outer, 1], Out, Encoded),
    wire_variable_names(Encoded, Names),
    length(Names, 3).

% A leaf that crosses as text still holds the tree's variables, so it spells
% them the way the structured nodes do. The solver records goals such as
% builtin(\\+ A) whose A an equation beside it also holds, and term_string/2
% wrote that leaf's cell address while the equation carried the tree's name.
test(a_text_leaf_spells_a_variable_as_the_equation_beside_it_does) :-
    Equation = ['=', [guarded, A], A],
    metta_py_encode_tree([step(guarded(1, 1), Equation, [builtin(\+ A)])],
                         [guarded, 1], 1, Encoded),
    wire_variable_names(Encoded, [Name]),
    Encoded = ["e", [_, _, ["e", [_, _, _, ["e", [_, ["g", Text]]]]]]],
    atom_string(NameAtom, Name),
    sub_atom(Text, _, _, _, NameAtom).

% A query row is one crossing too. Its columns used to be encoded one at a
% time, each restarting the numbering, so the first variable of every column
% was named alike and (= $head $body) answered a head and a body whose
% distinct variables had collided.
test(a_rows_columns_do_not_share_a_name_between_distinct_variables) :-
    metta_py_row([head, body], [head-[f, _X], body-[g, _Y]], Row),
    Row = [["e", [_, ["v", NameX]]], ["e", [_, ["v", NameY]]]],
    NameX \== NameY.

test(one_variable_in_two_columns_crosses_under_one_name) :-
    metta_py_row([head, body], [head-[f, Z], body-[g, Z]], Row),
    Row = [["e", [_, ["v", NameLeft]]], ["e", [_, ["v", NameRight]]]],
    NameLeft == NameRight.

% A column holding a variable that another column also holds crosses under
% one name, and it is a MINTED one rather than the caller's spelling for the
% column: a caller's name says which column, not which cell, and it is the
% same in every row, so spelling a cell with it would make two rows' distinct
% variables one.
test(a_variable_a_column_holds_agrees_with_the_column_that_is_it) :-
    metta_py_row([head, body], [head-[f, Free], body-Free], Row),
    Row = [["e", [_, ["v", Inside]]], ["v", Column]],
    Inside == Column,
    Inside \== "body".

% A column the match did not bind AT ALL keeps the name the caller asked for.
% It names no cell, so it cannot collide with one.
test(a_column_with_no_binding_keeps_the_querys_own_name) :-
    metta_py_row([head, body], [head-[f, _Free]], Row),
    Row = [["e", [_, ["v", _]]], ["v", Column]],
    Column == body.

% The counts above are one half of the contract. The other half is that two
% cells are never one name ACROSS crossings, which is what keeps two
% separately answered variables apart on the host: a metta atom compares by
% spelling, so two matches whose answers both said $_0 would put ONE variable
% into whatever expression a host built from them [measured 2026-08-31:
% `(p (f $x))` and `(p (g $y))` answered `(f $_0)` and `(g $_0)` while a term
% numbered its own variables]. The two halves pull apart, and only the map
% plus a session counter holds both: numbering per term gives the counts and
% loses this, while the cell's printed address gave this and lost the counts
% by moving under a collection.
test(two_crossings_do_not_share_a_name_between_distinct_variables) :-
    metta_py_encode([f, _A], ["e", [_, ["v", NameA]]]),
    metta_py_encode([g, _B], ["e", [_, ["v", NameB]]]),
    NameA \== NameB.

% A seeded spelling is kept rather than renamed, and a variable the seed does
% not name is minted beside it rather than colliding with it.
test(a_seeded_name_survives_beside_a_minted_one) :-
    metta_py_encode_named([pair, Seeded, _Fresh], ['x'-Seeded],
                          ["e", [_, ["v", Kept], ["v", Minted]]]),
    Kept == "x",
    Minted \== "x".

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
    metta_py_encode(Left, LeftWire),
    metta_py_encode(Right, RightWire),
    py_call(python_semantics_oracle:py_eq_wire(LeftWire, RightWire), Python),
    python_boolean_atom(Python, Result).

python_host_truthy(Value, Result) :-
    metta_py_encode(Value, Wire),
    py_call(python_semantics_oracle:py_truthy_wire(Wire), Python),
    python_boolean_atom(Python, Result).

python_boolean_atom('@'(true), true).
python_boolean_atom('@'(false), false).

test(the_native_and_host_equality_routes_agree,
     [forall(python_eq_case(Left, Right, Expected))]) :-
    once(metta_py_native_eq(Left, Right, Native)),
    python_host_eq(Left, Right, Host),
    Native == Expected,
    Host == Native.

test(the_native_and_host_truth_routes_agree,
     [forall(python_truth_case(Value, Expected))]) :-
    once(metta_py_native_truthy(Value, Native)),
    python_host_truthy(Value, Host),
    Native == Expected,
    Host == Native.

test(nan_is_not_equal_to_itself) :-
    NaN is nan,
    once(metta_py_native_eq(NaN, NaN, false)).

test(an_opaque_object_is_left_for_the_host, [fail]) :-
    metta_py_native_eq('$opaque'(value), '$opaque'(value), _).

test(an_opaque_objects_truth_is_left_for_the_host, [fail]) :-
    metta_py_native_truthy('$opaque'(value), _).

%is_list/1 is one inference however much C work it performs, so this defect
%class needs a CPU-time test. A sixteen-times-wider operand gives a wide margin:
%a whole-operand classification grows by about sixteen while the outer-cell
%classification remains constant. Both readings share one process and the
%lists are built before the timed region.
native_empty_expression_comparison_cost(Length, Seconds) :-
    findall(e, between(1, Length, _), Expression),
    forall(between(1, 100, _),
           metta_py_dispatch_eq(Expression, [], false)),
    statistics(cputime, Before),
    forall(between(1, 5000, _),
           metta_py_dispatch_eq(Expression, [], false)),
    statistics(cputime, After),
    Seconds is After - Before.

test(comparing_against_the_empty_expression_does_not_walk_the_other_operand) :-
    native_empty_expression_comparison_cost(400, Narrow),
    native_empty_expression_comparison_cost(6400, Wide),
    assertion(Wide < Narrow * 4).

:- end_tests(shim_python_scalar_semantics).

:- begin_tests(shim_answer_form).

% The explicit answer wire: ["a", Theta, Residue, K] with an optional
% trailing value. Theta binds the query frame's variables BY NAME, the names
% the encoder wrote, and the encoder now HANDS BACK the map it wrote rather
% than leaving a caller to reconstruct one. These tests therefore encode the
% pattern the way a crossing does and read the name out of that map, which is
% also the only thing that keeps the two sides agreeing once a collection has
% moved the cells.

answer_table(Term, Table) :- metta_py_encode(Term, [], Table, _).

answer_name(Table, Variable, Name) :-
    metta_py_var_name(Table, Variable, Written),
    atom_string(Written, Name).

test(theta_binds_the_pattern_variable_by_name) :-
    Pattern = [edge, a, Y],
    answer_table(Pattern, Table),
    answer_name(Table, Y, N),
    metta_py_answer_match(["a", [[N, ["s", "b"]]], '@'(true), '@'(none)],
                          Pattern, Table, '&plunit_ctx'),
    assertion(Y == b).

test(the_atom_tag_spelling_is_accepted_too) :-
    Pattern = [edge, a, Y],
    answer_table(Pattern, Table),
    answer_name(Table, Y, N),
    metta_py_answer_match([a, [[N, ["s", "b"]]], '@'(true), '@'(none)],
                          Pattern, Table, '&plunit_ctx'),
    assertion(Y == b).

test(an_explicit_value_unifies_under_theta) :-
    Pattern = [edge, a, Y],
    answer_table(Pattern, Table),
    answer_name(Table, Y, N),
    metta_py_answer_match(["a", [[N, ["s", "b"]]], '@'(true), '@'(none),
                           ["e", [["s", "edge"], ["s", "a"], ["s", "b"]]]],
                          Pattern, Table, '&plunit_ctx'),
    assertion(Y == b).

test(a_value_contradicting_theta_drops_the_answer, [fail]) :-
    Pattern = [edge, a, Y],
    answer_table(Pattern, Table),
    answer_name(Table, Y, N),
    metta_py_answer_match(["a", [[N, ["s", "clash"]]], '@'(true), '@'(none),
                           ["e", [["s", "edge"], ["s", "a"], ["s", "b"]]]],
                          Pattern, Table, '&plunit_ctx').

test(unknown_theta_names_stay_fresh_and_harmless) :-
    Pattern = [edge, a, Y],
    answer_table(Pattern, Table),
    metta_py_answer_match(["a", [["nobody", ["n", 3]]], '@'(true), '@'(none)],
                          Pattern, Table, '&plunit_ctx'),
    assertion(var(Y)).

test(theta_values_may_alias_the_patterns_own_variables) :-
    Pattern = [edge, X, Y],
    answer_table(Pattern, Table),
    answer_name(Table, X, NX),
    answer_name(Table, Y, NY),
    metta_py_answer_match(["a", [[NY, ["v", NX]]], '@'(true), '@'(none)],
                          Pattern, Table, '&plunit_ctx'),
    assertion(X == Y).

test(a_plain_wire_still_decodes_and_unifies) :-
    Pattern = [edge, a, Y],
    answer_table(Pattern, Table),
    metta_py_answer_match(["e", [["s", "edge"], ["s", "a"], ["s", "b"]]],
                          Pattern, Table, '&plunit_ctx'),
    assertion(Y == b).

test(a_residue_under_a_pushed_bound_is_refused,
     [throws(error(metta_answer_conditional_under_bound(_, _), _))]) :-
    Pattern = [edge, a, _],
    answer_table(Pattern, Table),
    metta_py_answer_match(["a", [], ["e", [["s", "check"]]], '@'(none)],
                          Pattern, 2, Table, '&plunit_ctx').

test(an_op_result_without_a_value_is_unit) :-
    Args = [X],
    metta_py_encode_arguments(Args, _, Table),
    answer_name(Table, X, N),
    metta_py_answer_result(["a", [[N, ["n", 1]]], '@'(true), '@'(none)],
                           plunit_op, Table, Result),
    assertion(X == 1),
    assertion(Result == []).

test(an_op_result_with_a_value_decodes_under_theta) :-
    Args = [X],
    metta_py_encode_arguments(Args, _, Table),
    answer_name(Table, X, N),
    metta_py_answer_result(["a", [[N, ["n", 1]]], '@'(true), '@'(none),
                            ["e", [["s", "pair"], ["v", N], ["s", "done"]]]],
                           plunit_op, Table, Result),
    assertion(X == 1),
    assertion(Result == [pair, 1, done]).

test(a_plain_op_result_shares_the_argument_variable) :-
    Args = [X],
    metta_py_encode_arguments(Args, _, Table),
    answer_name(Table, X, N),
    metta_py_answer_result(["v", N], plunit_op, Table, Result),
    assertion(Result == X).

% Two arguments, two DISTINCT variables. Encoding argument by argument would
% restart the numbering at each one and name both _0, and the decoder shares
% by name, so a value returned for the first would land in the second as well.
test(two_arguments_do_not_share_a_name_between_distinct_variables) :-
    Args = [X, Y],
    metta_py_encode_arguments(Args, [["v", NX], ["v", NY]], Table),
    NX \== NY,
    answer_name(Table, X, NX),
    answer_name(Table, Y, NY),
    metta_py_answer_result(["a", [[NX, ["n", 1]]], '@'(true), '@'(none)],
                           plunit_op, Table, _),
    assertion(X == 1),
    assertion(var(Y)).

% One variable in two argument positions is ONE variable, so it crosses under
% one name and a value for it lands in both places.
test(one_variable_in_two_arguments_crosses_under_one_name) :-
    Args = [X, X],
    metta_py_encode_arguments(Args, [["v", N], ["v", N]], Table),
    metta_py_answer_result(["a", [[N, ["n", 7]]], '@'(true), '@'(none)],
                           plunit_op, Table, _),
    assertion(X == 7).

test(the_answer_errors_have_engine_messages) :-
    message_to_string(error(metta_answer_conditional_under_bound([edge, a, _],
                                                                 [check]),
                            none), M1),
    once(sub_string(M1, _, _, _, "residue")),
    once(sub_string(M1, _, _, _, "Sound")),
    \+ sub_string(M1, _, _, _, "Unknown error term"),
    message_to_string(error(metta_answer_annotation_undeclared('&c', 0.5), none),
                      M2),
    once(sub_string(M2, _, _, _, "annotation")),
    once(sub_string(M2, _, _, _, "ranked")),
    \+ sub_string(M2, _, _, _, "Unknown error term").

:- end_tests(shim_answer_form).

:- begin_tests(shim_relation_form).

shim_relation_field(Index, [Index, ["s", "same"]]).

test(a_positional_candidate_binds_call_arguments_and_answers_unit) :-
    Args = [Origin, lyon],
    metta_py_encode_arguments(Args, _, Table),
    once(metta_py_relation_result(
             [[0, ["s", "paris"]], [1, ["s", "lyon"]]], Args, Table, Result)),
    assertion(Origin == paris),
    assertion(Result == []).

test(a_candidate_contradicting_a_ground_argument_is_filtered, [fail]) :-
    Args = [paris, lyon],
    metta_py_encode_arguments(Args, _, Table),
    metta_py_relation_result([[0, ["s", "paris"]], [1, ["s", "nice"]]],
                             Args, Table, _).

test(a_wide_candidate_walk_does_not_restart_with_nth0) :-
    \+ ( clause(metta_py_relation_fields(_, _, _, _), Body4),
         sub_term(Sub4, Body4), nonvar(Sub4), functor(Sub4, nth0, 3) ),
    \+ ( clause(metta_py_relation_fields(_, _, _, _, _), Body5),
         sub_term(Sub5, Body5), nonvar(Sub5), functor(Sub5, nth0, 3) ),
    numlist(0, 4999, Indices),
    maplist(shim_relation_field, Indices, Fields),
    length(Args, 5000),
    maplist(=(same), Args),
    metta_py_encode_arguments(Args, _, Table),
    once(metta_py_relation_result(Fields, Args, Table, [])).

test(a_terminal_generator_error_keeps_its_python_class) :-
    metta_py_stream_error(["x", "raise", "ValueError", planted], Error),
    assertion(Error == error(python_error('ValueError', planted), none)).

:- end_tests(shim_relation_form).
