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

:- begin_tests(metta_operation_errors).

%+, - and * have no evaluation-error case: on two numbers they are TOTAL
%now, the whole IEEE family saturating to values the way the reader's
%literals do (overflow to the infinities, the NaN class to NaN) [tested:
%engine_operations_saturate_where_raw_is_still_raises,
%a_twice_faulting_compound_saturates_all_the_way], and a non-number operand
%raises the argument GUARD's error, which is the next unit's context.
%Integer division by zero is the fault that remains, deliberately: the
%operand guard keeps it outside the IEEE retry.
host_error_case('/', '/'(1, 0, _)).
host_error_case('%', '%'(1, 0, _)).
host_error_case(exp, exp(invalid_number, _)).
host_error_case('#+', '#+'(1, invalid_number, _)).
host_error_case('#-', '#-'(1, invalid_number, _)).
host_error_case('#*', '#*'(1, invalid_number, _)).
host_error_case('#div', '#div'(1, invalid_number, _)).
host_error_case('#//', '#//'(1, invalid_number, _)).
host_error_case('#mod', '#mod'(1, invalid_number, _)).
host_error_case('#min', '#min'(1, invalid_number, _)).
host_error_case('#max', '#max'(1, invalid_number, _)).
host_error_case('#<', '#<'(1, invalid_number, _)).
host_error_case('#>', '#>'(1, invalid_number, _)).
host_error_case('#=', '#='(1, invalid_number, _)).
host_error_case('#\\=', '#\\='(1, invalid_number, _)).
host_error_case('pow-math', 'pow-math'(1, invalid_number, _)).
host_error_case('pow-math', 'pow-math'(0, -1, _)).
host_error_case('sqrt-math', 'sqrt-math'(invalid_number, _)).
host_error_case('sqrt-math', 'sqrt-math'(-1, _)).
host_error_case('abs-math', 'abs-math'(invalid_number, _)).
host_error_case('log-math', 'log-math'(1, invalid_number, _)).
host_error_case('exp-math', 'exp-math'(invalid_number, _)).
host_error_case('trunc-math', 'trunc-math'(invalid_number, _)).
host_error_case('ceil-math', 'ceil-math'(invalid_number, _)).
host_error_case('floor-math', 'floor-math'(invalid_number, _)).
host_error_case('round-math', 'round-math'(invalid_number, _)).
host_error_case('sin-math', 'sin-math'(invalid_number, _)).
host_error_case('cos-math', 'cos-math'(invalid_number, _)).
host_error_case('tan-math', 'tan-math'(invalid_number, _)).
host_error_case('asin-math', 'asin-math'(invalid_number, _)).
host_error_case('asin-math', 'asin-math'(2, _)).
host_error_case('acos-math', 'acos-math'(invalid_number, _)).
host_error_case('acos-math', 'acos-math'(2, _)).
host_error_case('atan-math', 'atan-math'(invalid_number, _)).
host_error_case('isnan-math', 'isnan-math'(invalid_number, _)).
host_error_case('isinf-math', 'isinf-math'(invalid_number, _)).
host_error_case('min-atom', 'min-atom'([invalid_number], _)).
host_error_case('max-atom', 'max-atom'([invalid_number], _)).
host_error_case('random-int', 'random-int'(1, invalid_number, _)).
host_error_case('random-float', 'random-float'(1, invalid_number, _)).
host_error_case('random-float',
                'random-float'(1.0e308, -1.0e308, _)).
host_error_case('bind!', 'bind!'([invalid_key], ['new-state', 1], _)).
host_error_case('change-state!', 'change-state!'([invalid_key], 1, _)).
host_error_case('get-state', 'get-state'([invalid_key], _)).

%The guarded operators refuse a non-number argument themselves rather than
%letting is/2 coerce it, so these are argument refusals, not host errors.
number_operand_case('+', '+'(1, invalid_number, _)).
number_operand_case('-', '-'(1, invalid_number, _)).
number_operand_case('*', '*'(1, invalid_number, _)).
number_operand_case('/', '/'(1, invalid_number, _)).
number_operand_case('%', '%'(1, invalid_number, _)).
number_operand_case('<', '<'(1, invalid_number, _)).
number_operand_case('>', '>'(1, invalid_number, _)).
number_operand_case('<=', '<='(1, invalid_number, _)).
number_operand_case('>=', '>='(1, invalid_number, _)).
number_operand_case(min, min(1, invalid_number, _)).
number_operand_case(max, max(1, invalid_number, _)).

test(arithmetic_refuses_a_non_number_argument,
     [forall(number_operand_case(Operation, Goal))]) :-
    catch(call(Goal), Error, true),
    nonvar(Error),
    Error = error(type_error(number, invalid_number),
                  context(Operation, 'invalid MeTTa operation argument')).

test(host_errors_name_the_written_operation,
     [forall(host_error_case(Operation, Goal))]) :-
    catch(call(Goal), Error, true),
    nonvar(Error),
    Error = error(Formal,
                  context(Operation, 'while evaluating MeTTa operation')),
    nonvar(Formal).

boolean_error_case(and, and(true, 5, _)).
boolean_error_case(or, or(false, 5, _)).
boolean_error_case(not, not(5, _)).
boolean_error_case(xor, xor(true, 5, _)).
boolean_error_case(implies, implies(false, 5, _)).

test(boolean_type_errors_are_loud,
     [forall(boolean_error_case(Operation, Goal))]) :-
    catch(call(Goal), Error, true),
    nonvar(Error),
    Error = error(type_error(boolean, 5),
                  context(Operation, 'invalid MeTTa operation argument')).

test(boolean_operations_remain_relational) :-
    findall(A-B-C, and(A, B, C), Rows),
    Rows == [true-true-true, true-false-false,
             false-true-false, false-false-false].

test(non_list_reduce_throws_its_own_type_error,
     [throws(error(type_error(list, invalid_reduce),
                   context(reduce, 'invalid MeTTa operation argument')))]) :-
    reduce(invalid_reduce, _).

test(variable_reduce_keeps_its_existing_empty_answer) :-
    findall(Input-Out, reduce(Input, Out), Answers),
    Answers == [[]-[]].

test(control_exceptions_are_not_recontextualized) :-
    Original = error(resource_error(stack), original_context),
    catch(rethrow_metta_operation_error('+', Original), Error, true),
    Error == Original.

% SWI's own errors carry context(PI, _) with the second argument UNBOUND, so a
% message clause that matched context(Operation, 'invalid MeTTa operation
% argument') in its head BOUND that variable and then rendered every ordinary
% type error in PeTTa's operation vocabulary. `X is foo+1` was reported as
% "system:(is)/2: evaluable expected, found (/ foo 0)", naming an engine
% internal and a culprit the program never wrote, which is exactly what an
% extension author saw when their own predicate's is/2 refused a value.
test(an_unrelated_type_error_keeps_swi_s_own_message) :-
    catch(_ is foo + 1, Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "is not a function")),
    assertion(\+ sub_string(Text, _, _, _, "expected, found")).

test(an_unknown_procedure_keeps_swi_s_own_message) :-
    catch(plunit_no_such_predicate(1, 2), Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "Unknown procedure")).

test(a_metta_operation_error_still_names_the_operation) :-
    catch('+'(foo, 1, _), Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "+: number expected, found foo")).

:- end_tests(metta_operation_errors).

:- dynamic plunit_break_type_bridge/0.
:- multifile py_object_type_names/2.
py_object_type_names(_, _) :- plunit_break_type_bridge, throw(plunit_broken_bridge).

% evalc's space argument selects the module the goals resolve in and nothing
% else. PeTTa's eval is a full evaluation of compiled goals rather than
% minimal MeTTa's single rewriting step, and evalc keeps that, so the two
% agree everywhere except which space's equations answer.
:- begin_tests(metta_evalc,
               [ setup(setup_evalc), cleanup(cleanup_evalc) ]).

setup_evalc :-
    retractall(user:silent(_)),
    assertz(user:silent(true)),
    process_metta_string("(= (plunit-evalc-pick) here)", _),
    'add-atom'('&plunit_evalc_kb', [=, ['plunit-evalc-pick'], there], _),
    process_metta_string("(= (plunit-evalc-echo $x) $x)", _),
    sread("(= (plunit-evalc-echo $x) $x)", KbEcho),
    'add-atom'('&plunit_evalc_kb', KbEcho, _).

cleanup_evalc :-
    'remove-atom'('&plunit_evalc_kb', [=, ['plunit-evalc-pick'], there], _),
    'remove-atom'('&self', [=, ['plunit-evalc-pick'], here], _),
    sread("(= (plunit-evalc-echo $x) $x)", KbEcho),
    'remove-atom'('&plunit_evalc_kb', KbEcho, _),
    sread("(= (plunit-evalc-echo $x) $x)", SelfEcho),
    'remove-atom'('&self', SelfEcho, _),
    clear_native_atoms('&plunit_evalc_kb').

test(evalc_answers_from_the_space_it_is_given) :-
    evalc(['plunit-evalc-pick'], '&self', InSelf),
    assertion(InSelf == here),
    evalc(['plunit-evalc-pick'], '&plunit_evalc_kb', InKb),
    assertion(InKb == there).

test(evalc_agrees_with_eval_in_the_default_space) :-
    eval(['plunit-evalc-pick'], ViaEval),
    evalc(['plunit-evalc-pick'], '&self', ViaEvalc),
    assertion(ViaEval == ViaEvalc).

% A space is an atom beginning with &, so an argument that is not one is a
% type error rather than a silently empty space.
test(evalc_refuses_an_argument_that_is_not_a_space,
     [throws(error(type_error(_, not_a_space), _))]) :-
    evalc(['plunit-evalc-pick'], not_a_space, _).

% &self is a reader token: it resolves where source text is parsed, and
% nowhere later, so a term built at run time keeps the literal atom
% through both eval doors. evalc especially must not substitute, because
% a reader-pinned token is lexical (the space hosting the source), and
% re-aiming it at evalc's dynamic target would change what pinned code
% means. The runtime walks that once substituted here also cost
% alpha-unique's counter twelve percent [measured 2026-08-17].
test(evalc_keeps_a_runtime_literal_self_as_written) :-
    sread("(plunit-evalc-echo &self)", T),
    evalc(T, '&plunit_evalc_kb', Out),
    assertion(Out == '&self').

test(eval_keeps_a_runtime_literal_self_as_written) :-
    sread("(plunit-evalc-echo &self)", T),
    eval(T, Out),
    assertion(Out == '&self').

:- end_tests(metta_evalc).

:- begin_tests(metta_object_types).

% A bridge whose py_object_type_names/2 clause THROWS used to be read as "no
% bridge answered", and the class walk ran instead. One broken protocol
% predicate therefore destroyed typing for every host object in the process,
% and get-type answered Box, the envelope's own class, for all of them, with
% no error at any point. python/petta/_ops.py states the rule for the same
% probe on its own side: a broken probe is the registrant's bug.
% The clause is static and flag-guarded, because py_object_type_names/2 is
% multifile without being dynamic: a bridge contributes its clause at load
% time and cannot be installed later.
test(a_throwing_type_bridge_is_the_registrants_bug,
     [ setup(assertz(user:plunit_break_type_bridge)),
       cleanup(retractall(user:plunit_break_type_bridge)),
       throws(plunit_broken_bridge) ]) :-
    py_object_type(plunit_not_really_an_object, _).

% A bridge that is ABSENT is an ordinary configuration, not a failure: a
% program reaching Python through py-call alone still gets its objects typed
% by the class walk.
test(an_absent_type_bridge_falls_back_to_the_class_walk) :-
    py_call(datetime:datetime(2020, 1, 1), Object),
    findall(T, py_object_type(Object, T), Types),
    assertion(memberchk(datetime, Types)),
    assertion(\+ memberchk(object, Types)).

:- end_tests(metta_object_types).

:- begin_tests(metta_type_answers,
               [ setup(setup_type_answers),
                 cleanup(cleanup_type_answers) ]).

type_answer_fact(plunit_type_a, plunit_a).
type_answer_fact(plunit_type_b, plunit_b).
type_answer_fact([plunit_type_a, plunit_type_b],
                 [plunit_a, plunit_b]).
type_answer_fact(plunit_pair_one, ['Pair', plunit_ta]).
type_answer_fact(plunit_pair_one, ['Pair', plunit_tb]).

setup_type_answers :-
    cleanup_type_answers,
    forall(type_answer_fact(Term, Type),
           add_sexp('&self', [':', Term, Type])),
    metta_self_module(Self),
    assertz(Self:get_type_rule([plunit_type_a, plunit_type_b],
                               [plunit_a, plunit_b])).

cleanup_type_answers :-
    forall(type_answer_fact(Term, _),
           remove_sexp('&self', [':', Term, _])),
    metta_self_module(Self),
    retractall(Self:get_type_rule([plunit_type_a, plunit_type_b], _)).

test(user_boundary_returns_each_type_once) :-
    findall(Type,
            'get-type'([plunit_type_a, plunit_type_b], Type),
            Types),
    Types == [[plunit_a, plunit_b]].

test(alpha_equivalent_polymorphic_types_are_one_answer,
     [ setup((metta_self_module(S),
                assertz(S:get_type_rule(plunit_poly_type,
                                        ['->', A, A])),
                assertz(S:get_type_rule(plunit_poly_type,
                                        ['->', B, B])))),
       cleanup((metta_self_module(S2),
                retractall(S2:get_type_rule(plunit_poly_type, _))))
     ]) :-
    findall(Type, user:'get-type'(plunit_poly_type, Type), Types),
    Types =@= [['->', T, T]].

test(fixed_internal_check_uses_one_witness) :-
    findall(true,
            has_type([plunit_type_a, plunit_type_b],
                     [plunit_a, plunit_b]),
            Witnesses),
    Witnesses == [true].

test(a_parametric_expected_type_enumerates_its_witnesses) :-
    % (Pair $t) is nonvar but not ground, so a first-witness commit here
    % binds $t from whichever declaration came first and never reaches the
    % assignment a second argument needs.
    findall(T,
            has_type(plunit_pair_one, ['Pair', T]),
            Types),
    msort(Types, Sorted),
    Sorted == [plunit_ta, plunit_tb].

test(a_ground_expected_type_still_stops_at_one_witness) :-
    findall(true,
            has_type(plunit_pair_one, ['Pair', plunit_ta]),
            Witnesses),
    Witnesses == [true].

%A tuple type is %Undefined% as soon as one member's type is, so the shape is
%never reported with a hole sitting inside it. Written against the engine's
%own answer rather than through janus, because the collapse is a rule of the
%type derivation and not of the boundary.
test(a_tuple_with_an_untyped_member_is_undefined) :-
    findall(T, 'get-type'([plunit_type_a, plunit_type_b], T), Typed),
    assertion(Typed == [[plunit_a, plunit_b]]),
    findall(T, 'get-type'([plunit_type_a, plunit_never_declared], T), Holed),
    assertion(Holed == ['%Undefined%']),
    findall(T, 'get-type'([plunit_never_declared], T), Alone),
    assertion(Alone == ['%Undefined%']).

%Bottom-up, so an inner tuple carrying a hole makes the outer one undefined
%without the rule saying anything about nesting.
test(the_collapse_reaches_a_nested_tuple) :-
    findall(T, 'get-type'([plunit_type_a, [plunit_type_a, plunit_type_b]], T),
            Nested),
    assertion(Nested == [[plunit_a, [plunit_a, plunit_b]]]),
    findall(T,
            'get-type'([plunit_type_a, [plunit_type_a, plunit_never_declared]], T),
            Holed),
    assertion(Holed == ['%Undefined%']).

:- end_tests(metta_type_answers).

:- begin_tests(metta_builtin_scoping).

test(a_named_space_defining_a_builtin_name_keeps_it_working_elsewhere,
     [ cleanup(( retractall(fun_in('&plunit_shadow', '+')),
                 retractall(fun_scoped('+')) )) ]) :-
    % One named space defining + once turned + into inert data in every
    % other space, and in engines built afterwards.
    assertz(fun_in('&plunit_shadow', '+')),
    assertz(fun_scoped('+')),
    metta_self_module(Self),
    with_metta_module(Self, fun_here('+')).

test(a_scoped_user_function_stays_scoped,
     [ cleanup(( retractall(fun(plunit_scoped_fn)),
                 retractall(fun_in('&plunit_shadow', plunit_scoped_fn)),
                 retractall(fun_scoped(plunit_scoped_fn)) )) ]) :-
    % The builtin fallback must not make every scoped name global.
    assertz(fun(plunit_scoped_fn)),
    assertz(fun_in('&plunit_shadow', plunit_scoped_fn)),
    assertz(fun_scoped(plunit_scoped_fn)),
    metta_self_module(Self),
    \+ with_metta_module(Self, fun_here(plunit_scoped_fn)).

:- end_tests(metta_builtin_scoping).

:- begin_tests(metta_arithmetic_operands).

arith_refusal(Goal, Culprit) :-
    catch(( call(Goal), fail ), error(type_error(number, Culprit), _), true).

test(a_one_element_expression_is_not_a_character_code) :-
    % (+ 1 (g)) answered 104, the character code of g.
    arith_refusal('+'(1, [g], _), [g]),
    arith_refusal('*'(2, [z], _), [z]).

test(a_string_is_not_a_character_code) :-
    arith_refusal('+'(1, "s", _), "s").

test(an_evaluable_atom_does_not_outrank_a_metta_definition) :-
    % SWI's pi answered 3.14159 over a user's own (= pi 3.14).
    arith_refusal('+'(1, pi, _), pi).

test(comparisons_refuse_the_same_operands) :-
    arith_refusal('<'(1, [f, 2], _), [f, 2]),
    arith_refusal(max([a], 1, _), [a]).

test(numbers_still_compute) :-
    '+'(1, 2, Three), Three == 3,
    '+'(1.5, 2.5, Four), Four == 4.0,
    max(3, 7, Seven), Seven == 7,
    '<'(1.5, 2, True), True == true.

:- end_tests(metta_arithmetic_operands).

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

:- begin_tests(metta_alpha_membership).

test(success_does_not_retain_unification_bindings) :-
    'is-alpha-member'([1, X], [[1, 2], [3, 4]], Bool),
    Bool == true,
    var(X).

test(translated_success_leaves_the_query_variable_unbound) :-
    setup_call_cleanup(
        assertz(silent(true), Ref),
        process_metta_string(
            "!(let $b (is-alpha-member (1 $x) ((1 2) (3 4))) $x)",
            [Result]),
        erase(Ref)),
    var(Result).

:- end_tests(metta_alpha_membership).

:- begin_tests(metta_alpha_unique).

test(synthetic_hash_collision_keeps_inequivalent_terms) :-
    empty_assoc(Empty),
    alpha_bucket_insert(forced_hash, alpha, Empty, SeenAlpha, true),
    alpha_bucket_insert(forced_hash, beta, SeenAlpha, SeenBoth, true),
    get_assoc(forced_hash, SeenBoth, Bucket),
    Bucket == [beta, alpha].

test(identity_inside_a_hash_bucket_rejects_a_duplicate) :-
    empty_assoc(Empty),
    alpha_bucket_insert(forced_hash, alpha, Empty, Seen, true),
    alpha_bucket_insert(forced_hash, alpha, Seen, SeenAgain, false),
    SeenAgain == Seen.

test(surface_deduplication_keeps_first_alpha_variant) :-
    'alpha-unique-atom'([[link, X, human],
                        [link, Y, human],
                        [child, Z, human]],
                        Unique),
    Unique == [[link, X, human], [child, Z, human]],
    X \== Y.

:- end_tests(metta_alpha_unique).

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

%The refusal NAMES the operation now. It used to be a bare
%instantiation_error, which told a MeTTa program that a value was missing and
%not which operation wanted it; the no-mutation half is what this test is
%really for and is unchanged.
test(variable_removal_is_rejected_without_mutation,
     [throws(error(petta_unbound_input('remove-translator-rule!', 1), _))]) :-
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

:- begin_tests(metta_registration).

%A registered name with no predicate records no arity, and
%incomplete_application_kind/3 reads a missing arity as "not applied far
%enough", so every call to that name compiles to a partial application: (sqrt
%4) answered (partial sqrt (4)) rather than computing or failing. A special
%form is exempt because the translator consumes it before dispatch, and so is
%a name whose predicate exists under some other arity.
special_form(Name) :- clause(translate_special_dl(Name, _, _, _, _), _).

test(every_registered_function_is_callable_or_a_special_form,
     [true(Unbacked == [])]) :-
    findall(Name,
            ( fun(Name),
              \+ arity(Name, _),
              \+ special_form(Name),
              \+ current_predicate(Name/_) ),
            Names),
    sort(Names, Unbacked).

:- end_tests(metta_registration).

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

test(subtraction_with_a_non_list_right_operand_is_empty,
     [true(Out == [])]) :-
    'subtraction-atom'([a], not_a_list, Out).

test(intersection_with_a_non_list_right_operand_is_empty,
     [true(Out == [])]) :-
    'intersection-atom'([a], not_a_list, Out).

test(union_atom_answers_the_empty_tuple_for_a_non_list) :-
    % Its two siblings already did. A non-list left operand failed silently,
    % and a non-list right operand built the improper list printed as
    % (cons a b), which no tuple operation can consume.
    'union-atom'(a, [b], Left), Left == [],
    'union-atom'([a], b, Right), Right == [].

test(union_atom_keeps_its_multiplicities) :-
    'union-atom'([a, b, b, c], [b, c, c, d], Out),
    Out == [a, b, b, c, b, c, c, d].

:- end_tests(metta_set_operations).


% An operation error names its culprit in the syntax the program wrote it
% in. The ISO formal term is unchanged, because the MeTTa catch form and
% the host's structured surface both read it; only the rendering differs.

:- begin_tests(metta_operation_error_message).

operation_error_text(Operation, Expected, Culprit, Text) :-
    catch(throw_metta_type_error(Operation, Expected, Culprit), Error, true),
    message_to_string(Error, Text).

test(the_culprit_reads_as_metta) :-
    operation_error_text('+', number, ['State', 5], Text),
    Text == "+: number expected, found (State 5)".

test(a_scalar_culprit_reads_as_itself) :-
    operation_error_text('<', number, foo, Text),
    Text == "<: number expected, found foo".

test(the_formal_term_stays_iso) :-
    catch(throw_metta_type_error('+', number, ['State', 5]), Error, true),
    Error = error(Formal, context(Operation, Explanation)),
    Formal == type_error(number, ['State', 5]),
    Operation == '+',
    Explanation == 'invalid MeTTa operation argument'.

%Every other error SWI renders keeps its own message. once/1 because this asks
%whether the text CONTAINS the fragment, and sub_string/5 with every position
%unbound is a search: it answers, then keeps a choice point open looking for
%another occurrence.
test(an_unrelated_type_error_is_untouched) :-
    catch(type_error(number, ['State', 5]), Error, true),
    message_to_string(Error, Text),
    once(sub_string(Text, _, _, _, "['State',5]")).

:- end_tests(metta_operation_error_message).

:- begin_tests(metta_decons_total).

%decons-atom answers for EVERY expression including the empty one, because
%failing there does not mean "no decomposition", it drops the whole
%continuation: (chain (decons-atom ()) $l TEMPLATE) never runs its template
%and the branch after it is unreachable.
test(decons_atom_is_total) :-
    'decons-atom'([a, b, c], Split),
    Split == [a, [b, c]],
    'decons-atom'([], Empty),
    Empty = ['Error', ['decons-atom', []], Message],
    string(Message).

%Three elements, and that is load-bearing. lib_measure.metta and
%lib_soft.metta write (let ($h $t) (decons-atom $ps) ...) and rely on the
%empty case not matching, so a two-element error would bind $h to Error and
%answer a wrong result in silence.
test(the_empty_error_does_not_destructure_as_a_pair) :-
    'decons-atom'([], Empty),
    \+ Empty = [_, _].

:- end_tests(metta_decons_total).

:- begin_tests(metta_builtin_type_surface).

%get-type has to report the engine's own surface, or every tool reading it is
%told the engine has no types for its own builtins. != is the worked case: it
%IS a builtin, IS registered and IS declared in lib_builtin_types.metta, and
%before this it answered %Undefined% for an operation that works.
surface_case('!=',        [->, _, _, 'Bool']).
surface_case('==',        [->, _, _, 'Bool']).
surface_case('+',         [->, 'Number', 'Number', 'Number']).
surface_case('sqrt-math', [->, 'Number', 'Number']).

test(get_type_reports_the_engines_own_builtins,
     [forall(surface_case(Name, Shape))]) :-
    'get-type'(Name, Type),
    subsumes_term(Shape, Type).

%A declared type is a claim that the operation can be CALLED that way, and
%this one could not be called at all. exists_file was registered bare, so the
%engine read SWI's exists_file/1's only argument as the output slot and made
%it a zero-input operation: a path could never be passed in. Declaring
%(-> %Undefined% Bool) for it said otherwise.
%
%Answering false rather than failing is the other half. A test that FAILS is
%indistinguishable from a test that was never reached, which is how the
%original symptom stayed hidden: lib_import.metta records dropping a guard
%because "It made a missing file fail SILENTLY, with no answer".
%An operator whose name a LIBRARY also exports had every one of that
%library's arities recorded as its own. library(yall) exports //2 through //9
%into user as its free-variables lambda, so `/` was registered at seven
%arities where + and * have one, and (/ 1 2 3) compiled to a direct
%'/'(1,2,3,_) call, which is yall's lambda: it answered
%`type_error(lambda_free, 1)` where every other operator answers the engine's
%own error naming the operator. Nothing was ever wrong with the ANSWERS,
%currying included; the message was simply unactionable.
test(metta_registration_arities,
     [forall(member(Operator, ['/', '+', '-', '*', min, max]))]) :-
    findall(Arity, arity(Operator, Arity), Arities),
    sort(Arities, Sorted),
    assertion(Sorted == [3]).

test(metta_arity_errors_name_the_operator,
     [forall(member(Operator, ['/', '+', '-', '*', min, max]))]) :-
    catch(( reduce([Operator, 1, 2, 3], _, _), Formal = none ),
          error(Formal, _), true),
    assertion(Formal = domain_error(function_input_arities(Operator, _), _)).

test(builtin_exists_file) :-
    library('lib_builtin_types.metta', Present),
    'exists_file'(Present, Found),
    assertion(Found == true),
    'exists_file'('/nonexistent/petta/definitely-not-here', Missing),
    assertion(Missing == false),
    %The declaration and the callable shape agree, which is the pairing that
    %was broken: get-type promised one input and the registration took none.
    'get-type'(exists_file, Type),
    assertion(subsumes_term([->, _, 'Bool'], Type)),
    catch('exists_file'(5, _), error(Formal, _), true),
    assertion(nonvar(Formal)).

%The table has exactly two legitimate sources: the file, and the engine
%prelude's declarations. Stated as a SET identity rather than as
%file + ledger == table, because the two sources are allowed to OVERLAP and
%the arithmetic identity silently forbade it. get-type is written in both,
%once for the type surface the file is and once so the call site honours its
%Atom mask, and counting rows read that legitimate overlap as a double write.
%The set identity says the same no-foreign-rows thing without the assumption,
%and the row-count pair says the no-double-writes half directly instead of
%leaving it to be inferred from a total.
%
%Rows are numbervar'd first. Several declarations are non-ground, `(: == (->
%$t $t Bool))` among them, and every findall renames those variables fresh,
%so an untreated == compares two structurally identical lists as different
%and sort/2 keeps two copies of a row written twice. Grounding first makes
%both comparisons say what they mean.
%Each row is numbered on its own, from zero, because numbering the whole
%list would make a row's numbers depend on how many rows preceded it and the
%two lists arrive in different orders.
canonical_row(Row, Canonical) :-
    copy_term(Row, Canonical),
    numbervars(Canonical, 0, _).

canonical_rows(Rows, Canonical) :-
    maplist(canonical_row, Rows, Numbered),
    sort(Numbered, Canonical).

test(the_table_is_built_from_the_file_rather_than_written_twice) :-
    library('lib_builtin_types.metta', Path),
    read_file_to_string(Path, Text, []),
    parse_metta_source(Text, Forms),
    findall(Name-Type,
            ( member(parsed(expression, _, [':', Name, Type]), Forms),
              atom(Name) ),
            InFile),
    findall(Name-Type, prelude_type_declaration(Name, Type), FromPrelude),
    findall(Name-Type, builtin_type_declaration(Name, Type), Loaded),
    append(InFile, FromPrelude, Sources),
    canonical_rows(Sources, ExpectedRows),
    canonical_rows(Loaded, LoadedRows),
    assertion(ExpectedRows == LoadedRows),
    length(Loaded, RowCount),
    length(LoadedRows, DistinctCount),
    assertion(RowCount == DistinctCount),
    InFile \== [],
    FromPrelude \== [].

%The overlap the row above allows is real and has a mechanism: a row the
%prelude found already written stays out of its eviction ledger, so a program
%redeclaring the name takes the prelude's row away and leaves the file's.
%Without that split, retractall/1 could not tell two identical rows apart and
%eviction deleted the engine's own type surface entry for the name.
test(a_shared_declaration_is_evicted_only_from_the_register_that_wrote_it) :-
    Shared = 'get-type',
    findall(Type, prelude_type_declaration(Shared, Type), Declared),
    findall(Type, builtin_type_declaration(Shared, Type), Surface),
    assertion(Declared \== []),
    assertion(Surface \== []),
    %Written by the file, so the prelude found it rather than putting it there.
    assertion(\+ prelude_wrote_builtin_type(Shared, _)),
    setup_call_cleanup(
        true,
        ( retract_prelude_declarations(Shared),
          findall(Type, builtin_type_declaration(Shared, Type), Survived),
          findall(Type, prelude_type_declaration(Shared, Type), Gone),
          assertion(Survived == Surface),
          assertion(Gone == []) ),
        forall(member(Type, Declared),
               assertz(prelude_type_declaration(Shared, Type)))).

%The declarations are FACTS, not atoms in &self. Putting them in &self changes
%what every program sees of its own space, which is not the engine's to do.
test(the_surface_is_invisible_to_a_program_enumerating_its_own_space) :-
    \+ ( 'get-atoms'('&self', Atom),
         Atom = [':', Name, _],
         builtin_type_declaration(Name, _) ).

%Last in the candidate order, so a program's own declaration wins.
test(a_program_declaration_is_answered_before_the_engines,
     [ setup(( retractall(silent(_)), assertz(silent(true)),
               'add-atom'('&self', [':', 'sqrt-math', 'PlunitOverride'], _) )),
       cleanup(( 'remove-atom'('&self', [':', 'sqrt-math', 'PlunitOverride'], _),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    findall(T, 'get-type'('sqrt-math', T), Types),
    Types = ['PlunitOverride'|_].

:- end_tests(metta_builtin_type_surface).

%comparable_operands/3 at the predicate's own door, where the answer is a
%Prolog one and no MeTTa reduction stands between the operands and the
%verdict.
:- begin_tests(comparable_operands).

test(two_known_and_different_kinds_are_refused,
     [forall(member(A-B, [1-"s", true-1, "s"-1, 1-true]))]) :-
    catch(( '=='(A, B, _), Formal = none ), error(Formal, _), true),
    assertion(Formal = type_error(_, _)).

test(a_pair_of_one_kind_is_compared,
     [forall(member(A-B-R, [1-1-true, 1-2-false, "s"-"s"-true,
                            true-false-false]))]) :-
    '=='(A, B, Answer),
    assertion(Answer == R).

%An operand nothing declares contradicts nothing, so the comparison happens.
test(an_undeclared_operand_is_compared_rather_than_refused) :-
    '=='(1, plunit_no_declaration, First),
    assertion(First == false),
    '=='(plunit_no_declaration, "s", Second),
    assertion(Second == false).

%Expressions are the axis the two references disagree on, so the guard leaves
%them alone and the collapse-and-compare idiom keeps working.
test(an_expression_operand_is_never_refused,
     [forall(member(A-B-R, [[1,2,3]-[]-false, []-[]-true, [1,2]-[3,4]-false,
                            []-1-false, "s"-[]-false]))]) :-
    '=='(A, B, Answer),
    assertion(Answer == R).

test(the_refusal_names_the_metta_operation) :-
    catch('=='(1, "s", _), error(_, Context), true),
    assertion(Context = context('==', _)),
    catch('!='(1, "s", _), error(_, NeContext), true),
    assertion(NeContext = context('!=', _)).

:- end_tests(comparable_operands).


:- begin_tests(metta_constraint_domains).

%CLP(Q) and CLP(B) each arrive as ONE entry point taking its constraint as
%written, rather than as a prefixed operator family like `#`. Mirroring `#`
%would have needed about thirty names; these are five.
constraint_case("!(let True (clpq (= (* 2 $x) 1)) (repr $x))", ["1r2"]).
constraint_case("!(let True (clpq (= (* 2 $x) 1)) (* 2 $x))", [1]).
constraint_case("!(collapse (let True (clpq (>= $a 0)) (clpq-entailed (>= $a 0))))",
                [[true]]).
constraint_case("!(collapse (let True (clpq (>= $b 0)) (clpq-entailed (>= $b 5))))",
                [[false]]).
constraint_case("!(collapse (let True (clpq (= $c 1)) (clpq (= $c 2))))", [[]]).
constraint_case("!(collapse (let True (clpb (card (1) ($m $n))) \c
                              (clpb-labeling ($m $n))))",
                [[[0, 1], [1, 0]]]).
constraint_case("!(clpb-taut (+ $t (~ $t)))", [true]).
constraint_case("!(clpb-taut (* $u (~ $u)))", [false]).

test(each_constraint_domain_answers,
     [ forall(constraint_case(Source, Expected)),
       setup(( retractall(silent(_)), assertz(silent(true)),
               process_metta_string(
                   "!(import! &self (library lib_constraints))", _) )),
       cleanup(( retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string(Source, Results),
    Results == Expected.

%The constraint arrives AS WRITTEN. Evaluated first, (* 2 $x) would run as
%ordinary arithmetic and raise before the solver saw it. The Atom parameter
%in the library's declarations is what does it, which is the documented way a
%Prolog-registered predicate takes an argument unevaluated.
test(a_constraint_is_not_evaluated_before_the_solver_sees_it,
     [setup(( retractall(silent(_)), assertz(silent(true)),
              process_metta_string(
                  "!(import! &self (library lib_constraints))", _) )),
      cleanup(( retractall(silent(_)), assertz(silent(false)) ))]) :-
    translate_runnable_expr([clpq, [=, [*, 2, _X], 1]], Goals, _),
    term_string(Goals, Text),
    %the constraint reaches clpq/2 as the list it was written as, with no
    %arithmetic goal emitted ahead of it
    once(sub_string(Text, _, _, _, "clpq([=,[*,2,")),
    \+ sub_string(Text, _, _, _, "*(2,").

%A list whose head is a symbol is an operator application; any other list
%stays a list, because these solvers take lists as arguments too.
test(a_list_argument_stays_a_list,
     [setup(( retractall(silent(_)), assertz(silent(true)),
              process_metta_string(
                  "!(import! &self (library lib_constraints))", _) )),
      cleanup(( retractall(silent(_)), assertz(silent(false)) ))]) :-
    metta_constraint_term([card, [1], [A, B]], Term),
    Term = card(Counts, Vars),
    Counts == [1],
    Vars = [A1, B1],
    A1 == A, B1 == B.

:- end_tests(metta_constraint_domains).

:- begin_tests(metta_subtyping).

%`:<` is upstream's spelling, SUB_TYPE_SYMBOL at lib/src/metta/mod.rs:22, and
%the arrow points from the subtype UP to the supertype: `(:< Dog Animal)` says
%Dog is below Animal. It is not `:>`.
%
%The mechanism is the part that is easy to get wrong. Upstream never DECIDES a
%subtyping relation while checking an argument; it WIDENS the argument's type
%LIST and runs the ordinary check against the wider list, so the matcher learns
%nothing about subtyping and `get-type` is where it shows. Every expectation
%below is the arbiter's measured answer from pinned hyperon 0.2.10 at 3f76dc4
%[source: /home/user/Dev/LeaTTa/ai-report-subtype-graph.md].

subtype_case(Setup, Query, Expected) :-
    forall(member(Form, Setup), process_metta_string(Form, _)),
    format(atom(Ask), "!(collapse (get-type ~w))", [Query]),
    process_metta_string(Ask, [Answered]),
    assertion(Answered == Expected).

test(a_declared_type_widens_to_its_supertype) :-
    subtype_case(["(: sub-a A1)", "(:< A1 B1)"], 'sub-a', ['A1', 'B1']).

%A grounded literal's built-in type is NOT widened: upstream's
%get_atom_types_internal queries the space only for symbols and expressions.
test(a_literals_builtin_type_is_not_widened) :-
    subtype_case(["(:< Number SubFoo)"], 1, ['Number']).

%Nor is an application's return type.
test(an_application_return_type_is_not_widened) :-
    subtype_case(["(: sub-c C1)", "(: sub-f (-> C1 D1))", "(:< D1 E1)"],
                 '(sub-f sub-c)', ['D1']).

%Tuple products first, then the direct declarations already widened, then one
%more widening over the whole list. A single pass answers ((A B) D C E) and
%upstream answers ((A B) D E C), so the order is the test.
test(an_expression_widens_in_two_phases) :-
    subtype_case(["(: sub-p P1)", "(: sub-q Q1)", "(: (sub-p sub-q) R1)",
                  "(:< (P1 Q1) S1)", "(:< R1 T1)"],
                 '(sub-p sub-q)', [['P1', 'Q1'], 'R1', 'T1', 'S1']).

%The diamond answers D TWICE. add_super_types checks presence against the list
%as it stood when the round BEGAN, so both B and C reach D in the same round
%and both append it. Reproducing the duplicate is what makes this parity rather
%than a tidier answer of our own.
test(the_diamond_reproduces_upstreams_duplicate) :-
    subtype_case(["(:< DA DB)", "(:< DA DC)", "(:< DB DD)", "(:< DC DD)",
                  "(: sub-x DA)"],
                 'sub-x', ['DA', 'DB', 'DC', 'DD', 'DD']).

%And it reaches the argument check, which is what the feature is FOR: a value
%declared Dog satisfies a parameter declared Animal.
test(an_argument_is_accepted_through_its_supertype) :-
    forall(member(Form, ["(: Rex ADog)", "(:< ADog AnAnimal)",
                         "(: sub-speak (-> AnAnimal String))",
                         "(= (sub-speak $a) \"woof\")"]),
           process_metta_string(Form, _)),
    process_metta_string("!(sub-speak Rex)", Answer),
    assertion(Answer == ["woof"]).

%With no edge declared the type path is untouched, which is what keeps this
%free for every program that does not use it.
test(no_edge_leaves_types_alone) :-
    process_metta_string("(: sub-plain PlainType)", _),
    process_metta_string("!(collapse (get-type sub-plain))", [Types]),
    assertion(Types == ['PlainType']).

:- end_tests(metta_subtyping).

:- begin_tests(metta_metatype_parameters).

%A parameter written as a metatype accepts any atom of that kind. Before this
%none of the five checked at all, so `(: PyList (-> Expression PyList))` typed
%a call to it as the tuple product of its arguments, and a container, which has
%no fixed arity, could not be declared. `Expression` is how HE declares
%`(: superpose (-> Expression Atom))`.
%
%The mechanism is one equality with a wildcard, not the `:<` graph:
%`*typ == ATOM_TYPE_ATOM || *typ == get_meta_type(atom)`
%[source: LeaTTa tests/semantics/types-meta/00_metatypes.metta, quoting
%hyperon-experimental@3f76dc4 lib/src/metta/types.rs:606-617].

metatype_call(Declaration, Argument, Answer) :-
    process_metta_string(Declaration, _),
    format(atom(Ask), "!(collapse ~w)", [Argument]),
    process_metta_string(Ask, [Answer]).

test(a_variadic_constructor_can_be_declared) :-
    process_metta_string("(: MetaPyList (-> Expression MetaPyList))", _),
    process_metta_string("!(collapse (get-type (MetaPyList (1 2 3))))", [Types]),
    assertion(Types == ['MetaPyList']).

test(a_symbol_parameter_takes_a_symbol_and_nothing_else) :-
    process_metta_string("(: meta-sym (-> Symbol Atom))", _),
    process_metta_string("(= (meta-sym $s) (got $s))", _),
    metatype_call("", "(meta-sym foo)", Accepted),
    assertion(Accepted == [[got, foo]]),
    metatype_call("", "(meta-sym (1 2))", RejectsExpression),
    assertion(RejectsExpression == []),
    metatype_call("", "(meta-sym 7)", RejectsNumber),
    assertion(RejectsNumber == []).

%A metatype parameter refuses a value of a KNOWN and different type, and lets
%through a value whose type nothing declares, which is the gradual rule and
%not a hole in the metatype check: %Undefined% is consistent with every type
%(Siek and Taha's ? relation), so no violation is provable for `foo`.
%
%This test used to say "and nothing else" and assert that `foo` was refused.
%Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
%interpreter, byte-identical across both: `!(meta-expr foo)` answers
%`(got foo)` and `!(meta-expr 7)` is `(BadArgType 1 Expression Number)`. The
%source the old comment quoted, `*typ == ATOM_TYPE_ATOM || *typ ==
%get_meta_type(atom)`, describes ONE of the routes into the check; the
%declared-type route runs first and admits the unknown.
test(an_expression_parameter_refuses_a_known_other_type_and_admits_an_unknown) :-
    process_metta_string("(: meta-expr (-> Expression Atom))", _),
    process_metta_string("(= (meta-expr $e) (got $e))", _),
    metatype_call("", "(meta-expr (1 2))", Accepted),
    assertion(Accepted == [[got, [1, 2]]]),
    metatype_call("", "(meta-expr 7)", RejectsNumber),
    assertion(RejectsNumber == []),
    metatype_call("", "(meta-expr foo)", AdmitsUnknown),
    assertion(AdmitsUnknown == [[got, foo]]).

%Atom is the wildcard, which is the whole of what the tutorial's "supertype"
%wording means once it is read off the source rather than the prose.
%A distinct name per case: plunit's forall re-runs the whole body, so one
%shared name would redefine the equation and answer once more each time round.
test(an_atom_parameter_takes_every_kind,
     [forall(member(Name-Argument, ["meta-any-sym"-"foo",
                                    "meta-any-expr"-"(1 2)",
                                    "meta-any-num"-"7",
                                    "meta-any-str"-"\"s\""]))]) :-
    format(atom(Declare), "(: ~w (-> Atom Atom))", [Name]),
    process_metta_string(Declare, _),
    format(atom(Define), "(= (~w $a) (got $a))", [Name]),
    process_metta_string(Define, _),
    format(atom(Ask), "!(collapse (~w ~w))", [Name, Argument]),
    process_metta_string(Ask, [Answer]),
    assertion(Answer = [[got, _]]).

%get-metatype/2 was only correct with its second argument UNBOUND. The clauses
%are ordered and cut on the value, so asking with it bound let an earlier
%clause's head fail to unify and the catch-all at the bottom claim the call,
%which made every value answer Grounded. Both callers ask with it bound.
%The same gradual rule from the Grounded side. This test used to assert that
%a Grounded parameter REJECTS a symbol; measured 2026-08-19 on hyperon 0.2.10
%and on the LeaTTa mechanised interpreter, byte-identical across both,
%`!(meta-gnd foo)` answers `(gotg foo)`. An undeclared symbol has no declared
%type to contradict Grounded with. A symbol that IS declared does, and that is
%the half this pins as still refusing.
test(a_grounded_parameter_admits_an_unknown_and_refuses_a_declared_other) :-
    process_metta_string("(: meta-gr (-> Grounded Atom))", _),
    process_metta_string("(= (meta-gr $g) (got $g))", _),
    metatype_call("", "(meta-gr 7)", Accepted),
    assertion(Accepted == [[got, 7]]),
    metatype_call("", "(meta-gr foo)", AdmitsUnknown),
    assertion(AdmitsUnknown == [[got, foo]]),
    process_metta_string("(: meta-gr-typed MetaGrOther)", _),
    metatype_call("", "(meta-gr meta-gr-typed)", RejectsDeclared),
    assertion(RejectsDeclared == []).

test(get_metatype_answers_the_same_bound_or_unbound,
     [forall(member(Value-Metatype, [foo-'Symbol', 7-'Grounded',
                                     "s"-'Grounded', [1,2]-'Expression']))]) :-
    'get-metatype'(Value, Computed),
    assertion(Computed == Metatype),
    assertion('get-metatype'(Value, Metatype)),
    forall(( member(Other, ['Symbol', 'Grounded', 'Expression', 'Variable']),
             Other \== Metatype ),
           assertion(\+ 'get-metatype'(Value, Other))).

:- end_tests(metta_metatype_parameters).

:- begin_tests(metta_module_context).

% current_metta_module/1 is one of the seven services src/ext_points.pl
% publishes for extensions to CALL, and it was the only one of the seven with
% no test of its own: EXTENDING.md has told handler authors to read it for
% longer than anything declared it, and lib_memo and lib_thread do. A published
% predicate nothing exercises can change under every extension at once.

%&self's own module, not Prolog's `user`: an equation compiled into the
%module the engine itself resolves in REPLACES a predicate of that name
%instead of shadowing it.
test(the_default_context_is_selfs_own_module) :-
    current_metta_module(Module),
    space_module('&self', Self),
    assertion(Module == Self),
    assertion(Module \== user).

% The argument is the module a space compiles into, which space_module/2
% answers. It used to be the space's own name for every space but &self, and a
% test that wrote the space name passed by coincidence.
test(a_named_module_is_in_force_inside_the_switch) :-
    space_module('&probe', Probe),
    with_metta_module(Probe, current_metta_module(Inside)),
    assertion(Inside == Probe).

test(a_space_name_is_refused_where_a_module_is_asked,
     [throws(error(type_error(metta_execution_module, '&probe'), _))]) :-
    with_metta_module('&probe', true).

test(the_previous_module_is_restored_after) :-
    space_module('&probe', Probe),
    with_metta_module(Probe, true),
    current_metta_module(After),
    metta_self_module(Self),
    assertion(After == Self).

% The restore is setup_call_cleanup/3's, so it has to survive the goal
% throwing. Without that a library that raises inside a named space leaves
% every later compile pointed at a module the caller never asked for.
test(the_previous_module_is_restored_after_a_throw) :-
    space_module('&probe', Probe),
    catch(with_metta_module(Probe, throw(deliberate)), deliberate, true),
    current_metta_module(After),
    metta_self_module(Self),
    assertion(After == Self).

test(switches_nest_and_unwind_in_order) :-
    space_module('&outer', OuterModule),
    space_module('&inner', InnerModule),
    with_metta_module(OuterModule,
                      ( current_metta_module(Outer),
                        with_metta_module(InnerModule,
                                          current_metta_module(Inner)),
                        current_metta_module(Back),
                        assertion(Outer == OuterModule),
                        assertion(Inner == InnerModule),
                        assertion(Back == OuterModule) )),
    current_metta_module(Final),
    metta_self_module(Self),
    assertion(Final == Self).

:- end_tests(metta_module_context).

:- begin_tests(metta_engine_module).

% `user` was two different jobs wearing one name: the HOST module SWI resolves
% its own hooks and consulted files in, and the module the ENGINE's clauses
% happen to be in. Every wrap_predicate/4 target and every clause/2 read of the
% translator's own compilation tables meant the second one, and asking for it
% is what lets a space stop being the first one.

test(it_answers_exactly_one_module) :-
    findall(Module, petta_engine_module(Module), Modules),
    assertion(Modules = [_]).

% Checked against SWI rather than against the atom `user`, so the test says
% what the predicate is FOR instead of repeating its current answer.
test(it_names_the_module_the_engines_own_clauses_are_in) :-
    petta_engine_module(Engine),
    functor(Head, reduce, 3),
    assertion(predicate_property(Engine:Head, defined)),
    assertion(\+ predicate_property(Engine:Head, imported_from(_))).

% The Group F reads: metta_special_form/1 and metta_translated_head/1 ask the
% engine's own clause table for which heads the translator gives meaning to. A
% read pointed at the wrong module answers for no form at all, silently.
test(the_translators_own_tables_are_read_from_it) :-
    assertion(metta_special_form(if)),
    assertion(metta_translated_head(collapse)),
    assertion(\+ metta_special_form(petta_no_such_form)).

:- end_tests(metta_engine_module).

:- begin_tests(metta_handles_route).

% (handles Ctx Pattern Fidelity [Det]) entries route a query by the most
% specific matching pattern, (in $x) marks a position that must arrive
% bound, and two maximal entries that disagree are a loud conflict.

handles_declare(Entry) :- 'add-atom'('&petta', Entry, _).
handles_retract(Entry) :- catch('remove-atom'('&petta', Entry, _), _, true).

test(strip_keeps_a_variable_headed_pair_entry) :-
    petta_adorn_strip([F, A], Stripped, Requirements),
    assertion(Stripped == [F, A]),
    assertion(Requirements == []),
    assertion(var(F)).

test(strip_keeps_the_symbol_in_as_data_mid_expression) :-
    petta_adorn_strip([foo, in, X], Stripped, Requirements),
    assertion(Stripped == [foo, in, X]),
    assertion(Requirements == []).

test(strip_collects_the_adorned_position) :-
    petta_adorn_strip([edge, [in, A], B], Stripped, Requirements),
    assertion(Stripped == [edge, A, B]),
    assertion(Requirements == [A]).

test(strip_handles_a_nested_wrapper) :-
    petta_adorn_strip([f, [in, [g, [in, X]]]], Stripped, Requirements),
    assertion(Stripped == [f, [g, X]]),
    assertion(Requirements == [[g, X], X]).

test(route_picks_the_most_specific_entry,
     [ setup(( handles_declare([handles, '&plunit_hr', [edge, _, _], 'Exact']),
               handles_declare([handles, '&plunit_hr', [edge, S, S], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hr', [edge, _, _], 'Exact']),
                 handles_retract([handles, '&plunit_hr', [edge, S2, S2], 'Sound']) )) ]) :-
    petta_handles_route('&plunit_hr', [edge, Q, Q], Repeated, _),
    assertion(Repeated == 'Sound'),
    petta_handles_route('&plunit_hr', [edge, _, _], Distinct, _),
    assertion(Distinct == 'Exact').

test(route_reads_the_det_slot_and_defaults_it,
     [ setup(( handles_declare([handles, '&plunit_hr5', [p, _], 'Exact', det]),
               handles_declare([handles, '&plunit_hr5', [q, _], 'Exact']) )),
       cleanup(( handles_retract([handles, '&plunit_hr5', [p, _], 'Exact', det]),
                 handles_retract([handles, '&plunit_hr5', [q, _], 'Exact']) )) ]) :-
    petta_handles_route('&plunit_hr5', [p, _], _, DetP),
    assertion(DetP == det),
    petta_handles_route('&plunit_hr5', [q, _], _, DetQ),
    assertion(DetQ == none).

test(route_fails_where_nothing_is_declared) :-
    \+ petta_handles_route('&plunit_hr_nobody', [p, _], _, _).

test(disagreeing_maximal_entries_throw_a_conflict,
     [ setup(( handles_declare([handles, '&plunit_hrc', [edge, a, _], 'Exact']),
               handles_declare([handles, '&plunit_hrc', [edge, _, b], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hrc', [edge, a, _], 'Exact']),
                 handles_retract([handles, '&plunit_hrc', [edge, _, b], 'Sound']) )),
       throws(error(petta_contract_conflict('&plunit_hrc', _, _, _), _)) ]) :-
    petta_handles_route('&plunit_hrc', [edge, a, b], _, _).

test(agreeing_maximal_entries_answer_their_shared_claim,
     [ setup(( handles_declare([handles, '&plunit_hra', [edge, a, _], 'Exact']),
               handles_declare([handles, '&plunit_hra', [edge, _, b], 'Exact']) )),
       cleanup(( handles_retract([handles, '&plunit_hra', [edge, a, _], 'Exact']),
                 handles_retract([handles, '&plunit_hra', [edge, _, b], 'Exact']) )) ]) :-
    petta_handles_route('&plunit_hra', [edge, a, b], Fidelity, _),
    assertion(Fidelity == 'Exact').

test(an_adorned_entry_requires_the_bound_argument,
     [ setup(handles_declare([handles, '&plunit_hri', [edge, [in, _], _], 'Refuse'])),
       cleanup(handles_retract([handles, '&plunit_hri', [edge, [in, _], _], 'Refuse'])) ]) :-
    petta_handles_route('&plunit_hri', [edge, bound, _], Bound, _),
    assertion(Bound == 'Refuse'),
    \+ petta_handles_route('&plunit_hri', [edge, _, _], _, _).

test(subsumption_never_binds_the_query,
     [ setup(handles_declare([handles, '&plunit_hrb', [edge, a, _], 'Exact'])),
       cleanup(handles_retract([handles, '&plunit_hrb', [edge, a, _], 'Exact'])) ]) :-
    % (edge $q b) is outside (edge a $y): routing it must not bind $q to a.
    \+ petta_handles_route('&plunit_hrb', [edge, _Q, b], _, _).

test(coherence_accepts_specificity_resolved_overlaps,
     [ setup(( handles_declare([handles, '&plunit_hco', [edge, _, _], 'Exact']),
               handles_declare([handles, '&plunit_hco', [edge, C, C], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hco', [edge, _, _], 'Exact']),
                 handles_retract([handles, '&plunit_hco', [edge, C2, C2], 'Sound']) )) ]) :-
    % The overlap exists and the repeated-variable entry wins it by
    % specificity, so there is no conflict to find.
    petta_handles_coherent('&plunit_hco').

test(coherence_throws_on_a_disagreeing_tie,
     [ setup(( handles_declare([handles, '&plunit_hct', [edge, a, _], 'Exact']),
               handles_declare([handles, '&plunit_hct', [edge, _, b], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hct', [edge, a, _], 'Exact']),
                 handles_retract([handles, '&plunit_hct', [edge, _, b], 'Sound']) )),
       throws(error(petta_contract_conflict('&plunit_hct', _, _, _), _)) ]) :-
    petta_handles_coherent('&plunit_hct').

test(the_scan_only_idiom_is_coherent_and_routes_by_adornment,
     [ setup(( handles_declare([handles, '&plunit_hcb', [edge, [in, _], _], 'Refuse']),
               handles_declare([handles, '&plunit_hcb', [edge, _, _], 'Exact']) )),
       cleanup(( handles_retract([handles, '&plunit_hcb', [edge, [in, _], _], 'Refuse']),
                 handles_retract([handles, '&plunit_hcb', [edge, _, _], 'Exact']) )) ]) :-
    % The adorned entry matches strictly fewer queries, so it is the more
    % specific one: bound-subject lookups are refused, the free scan stays
    % exact, and the pair is coherent rather than a tie.
    petta_handles_coherent('&plunit_hcb'),
    petta_handles_route('&plunit_hcb', [edge, bound, _], Bound, _),
    assertion(Bound == 'Refuse'),
    petta_handles_route('&plunit_hcb', [edge, _, _], Free, _),
    assertion(Free == 'Exact').

test(strip_reports_renaming_invariant_paths) :-
    petta_adorn_strip([edge, [in, A], [in, B]], Stripped, Requirements, Paths),
    assertion(Stripped == [edge, A, B]),
    assertion(Requirements == [A, B]),
    assertion(Paths == [[1], [2]]).

test(a_narrower_pattern_outranks_any_adornment,
     [ setup(( handles_declare([handles, '&plunit_hcn', [edge, S, S], 'Sound']),
               handles_declare([handles, '&plunit_hcn', [edge, [in, _], _], 'Refuse']) )),
       cleanup(( handles_retract([handles, '&plunit_hcn', [edge, S2, S2], 'Sound']),
                 handles_retract([handles, '&plunit_hcn', [edge, [in, _], _], 'Refuse']) )) ]) :-
    % A bound self-loop query falls under both; the repeated-variable
    % pattern is narrower than the adorned one, so its claim wins.
    petta_handles_route('&plunit_hcn', [edge, a, a], Fidelity, _),
    assertion(Fidelity == 'Sound').

test(the_conflict_error_names_both_entries) :-
    message_to_string(error(petta_contract_conflict('&c', [edge, a, _],
                                                    [edge, _, b], [edge, a, b]),
                            none), Message),
    once(sub_string(Message, _, _, _, "disagree")),
    once(sub_string(Message, _, _, _, "&c")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

test(the_refusal_error_names_the_space_and_shape) :-
    message_to_string(error(petta_refused_shape('&c', [secret, s1],
                                                [secret, [in, _]]), none),
                      Message),
    once(sub_string(Message, _, _, _, "Refuse")),
    once(sub_string(Message, _, _, _, "&c")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(metta_handles_route).

:- begin_tests(relational_arithmetic).

% The four operators run BACKWARDS over integers: one unbound argument
% among integers solves for it, MeTTaLog's plus/3 compilation adopted at
% the predicate rather than the compiler, so every call site inherits it.

test(subtraction_solves_for_its_first_argument) :-
    '-'(X, 1, 4),
    X == 5.

test(addition_solves_either_slot) :-
    '+'(A, 3, 10), A == 7,
    '+'(2, B, 9),  B == 7.

test(multiplication_solves_exact_division) :-
    '*'(X, 2, 6),
    X == 3.

test(multiplication_fails_on_inexact_division, [fail]) :-
    '*'(_, 2, 7).

test(division_solves_both_directions) :-
    '/'(X, 2, 3), X == 6,
    '/'(6, B, 2), B == 3.

test(division_fails_on_inexact_backward, [fail]) :-
    '/'(7, _, 2).

test(ground_and_float_paths_are_unchanged) :-
    '+'(2, 3, R1), R1 == 5,
    '/'(7, 2.0, R2), R2 == 3.5.

test(two_unbound_arguments_still_refuse,
     [throws(error(_, _))]) :-
    '+'(_, _, _).

test(a_float_beside_a_variable_still_refuses,
     [throws(error(_, _))]) :-
    '+'(_, 1.5, _).

:- end_tests(relational_arithmetic).

:- begin_tests(inference_bound_form).

%[nondet] by design: the form answers each value of the bounded goal, so
%a choicepoint after the first is the multiplicity, not untidiness.
test(inferences_bounds_and_answers, [nondet]) :-
    metta_inferences(100000, member(X, [1, 2]), X),
    X == 1.

test(inferences_keeps_every_answer) :-
    findall(V, metta_inferences(100000, member(V, [1, 2, 3]), V), Vs),
    Vs == [1, 2, 3].

test(inferences_expiry_throws_the_reserved_envelope,
     [throws(error(petta_py_exception(inference_limit, 50), _))]) :-
    metta_inferences(50, (between(1, 100000, N), N > 99999), N).

test(inferences_refuses_a_non_positive_bound,
     [throws(error(type_error(_, _), _))]) :-
    metta_inferences(0, true, _).

:- end_tests(inference_bound_form).

:- begin_tests(scoped_pragmas).

test(with_pragma_scopes_and_restores) :-
    \+ metta_pragma('max-inferences', _),
    metta_with_pragmas([['max-inferences', 100000]], member(X, [7]), X),
    X == 7,
    \+ metta_pragma('max-inferences', _).

test(with_pragma_expiry_throws_the_reserved_envelope,
     [throws(error(petta_py_exception(inference_limit, 200), _))]) :-
    metta_with_pragmas([['max-inferences', 200]],
                       (between(1, 100000, N), N > 99999), N).

test(with_pragma_restores_after_expiry) :-
    catch(metta_with_pragmas([['max-inferences', 200]],
                             (between(1, 100000, N), N > 99999), N),
          error(petta_py_exception(inference_limit, _), _),
          true),
    \+ metta_pragma('max-inferences', _).

test(with_pragma_restores_a_previous_value) :-
    'pragma!'('max-time', 30, _),
    metta_with_pragmas([['max-time', 5]], member(X, [1]), X),
    metta_pragma('max-time', Restored),
    Restored == 30,
    'pragma!'('max-time', none, _).

test(limit_expiry_is_a_control_signal_no_recovery_catch_eats) :-
    control_exception(error(petta_py_exception(inference_limit, 200), c)),
    control_exception(error(petta_py_exception(time_limit, 1.0), c)).

test(with_pragma_refuses_a_malformed_setting,
     [throws(error(domain_error(metta_pragma_setting, _), _))]) :-
    metta_with_pragmas([broken], true, _).

:- end_tests(scoped_pragmas).

%petta_transaction/1 at the predicate level, where the answer set is a plain
%Prolog one and no MeTTa reduction stands between the goal and the count.
:- begin_tests(transaction_answers).

:- dynamic tx_probe/1.

test(a_transaction_yields_every_solution_of_its_goal) :-
    findall(X, petta_transaction(member(X, [a,b,c])), Answers),
    assertion(Answers == [a,b,c]).

test(a_goal_with_no_solution_fails_the_transaction) :-
    assertion(\+ petta_transaction(fail)),
    assertion(\+ petta_transaction(member(_, []))).

%Every solution's writes are inside the one transaction, so they land
%together or not at all. retractall/1 rather than a fixture, because a
%rolled-back transaction must leave the store exactly as it found it.
test(every_solution_writes_inside_the_one_transaction) :-
    retractall(tx_probe(_)),
    findall(X, petta_transaction(( member(X, [1,2,3]),
                                   assertz(tx_probe(X)) )), Answers),
    assertion(Answers == [1,2,3]),
    findall(P, tx_probe(P), Written),
    assertion(Written == [1,2,3]),
    retractall(tx_probe(_)).

test(a_failure_after_several_writes_undoes_all_of_them) :-
    retractall(tx_probe(_)),
    assertion(\+ petta_transaction(( member(X, [1,2,3]),
                                     assertz(tx_probe(X)),
                                     fail ))),
    findall(P, tx_probe(P), Written),
    assertion(Written == []).

test(a_throw_after_several_writes_undoes_all_of_them) :-
    retractall(tx_probe(_)),
    catch(petta_transaction(( member(X, [1,2,3]),
                              assertz(tx_probe(X)),
                              throw(tx_boom) )),
          Thrown, true),
    assertion(Thrown == tx_boom),
    findall(P, tx_probe(P), Written),
    assertion(Written == []).

%A nested transaction runs inside the outer one and collects for the same
%reason: SWI's transaction/1 is once-like at every depth.
test(a_nested_transaction_yields_every_solution_too) :-
    findall(X, petta_transaction(petta_transaction(member(X, [a,b]))),
            Answers),
    assertion(Answers == [a,b]).

:- end_tests(transaction_answers).

%The generated probe P1.7 and P1.8 ask for: every position the engine's own
%type surface declares strict, on a builtin PeTTa defines, called with that
%position unbound and the rest filled. The table is guarded_input_position/3,
%so this cannot go stale by hand: declaring a type for a new builtin adds a
%row here in the same stroke.
:- begin_tests(builtin_input_guards).

guard_filler('Expression', [a, b]) :- !.
guard_filler('Number', 1) :- !.
guard_filler('String', "s") :- !.
guard_filler('Bool', true) :- !.
guard_filler('Symbol', '&probe-space') :- !.
guard_filler('Variable', '$probevar') :- !.
guard_filler(_, a).

%The outcome of calling Name/Arity with Position unbound: `ok` when it refused
%and named the MeTTa operation, and otherwise a description of what it did
%instead. A one-second limit, because two of these used to enumerate every
%list there is.
guard_outcome(Name, Arity, Position, Outcome) :-
    builtin_type_declaration(Name, ['->'|Chain]),
    append(Inputs, [_], Chain),
    length(Chain, Arity),
    findall(Value,
            ( nth1(Index, Inputs, Type),
              ( Index =:= Position -> true ; guard_filler(Type, Value) ) ),
            Filled),
    append(Filled, [Out], Args),
    Goal =.. [Name|Args],
    nth1(Position, Filled, Hole),
    copy_term(Hole, Before),
    (   catch(call_with_time_limit(1, catch(Goal, Error, true)),
              time_limit_exceeded, Error = guard_probe_timeout)
    ->  (   nonvar(Error)
        ->  guard_refusal(Error, Name, Outcome)
        ;   guard_success(Hole, Before, Out, Name, Outcome)
        )
    ;   Outcome = 'failed silently'
    ).

guard_refusal(guard_probe_timeout, _, 'ran away') :- !.
guard_refusal(error(resource_error(R), _), _, Outcome) :- !,
    format(atom(Outcome), "exhausted ~w", [R]).
guard_refusal(error(_, context(Named, _)), Name, ok) :- Named == Name, !.
guard_refusal(error(Formal, Context), _, Outcome) :-
    format(atom(Outcome), "refused as ~q in ~q, which is not its own name",
           [Formal, Context]).

guard_success(Hole, Before, _, _, Outcome) :- nonvar(Hole), var(Before), !,
    format(atom(Outcome), "bound its own input to ~q", [Hole]).
guard_success(_, _, Out, _, 'answered a fresh variable') :- var(Out), !.
guard_success(_, _, Out, Name, ok) :-
    Out = ['Error', [Named|_], _], Named == Name, !.
guard_success(_, _, Out, _, Outcome) :-
    format(atom(Outcome), "answered ~q", [Out]).

test(every_builtin_refuses_an_unbound_input_by_name) :-
    findall(Name-Arity-Position, guarded_input_position(Name, Arity, Position),
            Rows0),
    sort(Rows0, Rows),
    %A table that emptied itself would pass every assertion below.
    length(Rows, Count),
    assertion(Count >= 80),
    findall(Name/Arity-Position-Outcome,
            ( member(Name-Arity-Position, Rows),
              guard_outcome(Name, Arity, Position, Outcome),
              Outcome \== ok ),
            Wrong),
    assertion(Wrong == []).

%The same probe over the positions this rule does NOT cover, so the gap stays
%measured rather than assumed: each still misbehaves, and the day one stops,
%this test says so and the row comes out of unguarded_input_position/2.
test(the_uncovered_positions_are_still_uncovered) :-
    findall(Name-Position,
            ( unguarded_input_position(Name, Position),
              arity(Name, Arity),
              functor(Head, Name, Arity),
              predicate_property(Head, defined),
              guard_outcome(Name, Arity, Position, ok) ),
            Fixed),
    assertion(Fixed == []).

:- end_tests(builtin_input_guards).
