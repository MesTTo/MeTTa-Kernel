% Purpose: direct PlUnit coverage for translator control forms and branch
%   rewrites whose failures are difficult to localize through whole examples.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(translator_hyperpose).

hyperpose_space('&plunit_hyperpose').

hyperpose_form("(= (plunit-dbl $x) (* $x 2))").
hyperpose_form("(= (plunit-viamap) (map-atom (1 2 3) plunit-dbl))").
hyperpose_form("(= (plunit-viahyper) (hyperpose ((plunit-viamap) (plunit-viamap))))").

add_hyperpose_form(Space, Text) :-
    sread(Text, Term),
    'add-atom'(Space, Term, true).

remove_hyperpose_form(Space, Text) :-
    sread(Text, Term),
    'remove-atom'(Space, Term, _).

setup_hyperpose :-
    retractall(silent(_)),
    assertz(silent(true)),
    hyperpose_space(Space),
    forall(hyperpose_form(Text), add_hyperpose_form(Space, Text)).

cleanup_hyperpose :-
    hyperpose_space(Space),
    forall(hyperpose_form(Text), remove_hyperpose_form(Space, Text)),
    retractall(silent(_)),
    assertz(silent(false)).

test(named_space_static_branches_use_calling_module,
     [setup(setup_hyperpose), cleanup(cleanup_hyperpose)]) :-
    hyperpose_space(Space),
    space_module(Space, Module),
    findall(Result,
            call_goals_in(Module, ['plunit-viahyper'(Result)]),
            Results),
    Results == [[2, 4, 6], [2, 4, 6]].

test(named_space_runtime_branches_use_calling_module,
     [setup(setup_hyperpose), cleanup(cleanup_hyperpose)]) :-
    hyperpose_space(Space),
    space_module(Space, Module),
    findall(Result,
            with_metta_module(
                Module,
                hyperpose_runtime([['plunit-viamap'], ['plunit-viamap']], Result)),
            Results),
    Results == [[2, 4, 6], [2, 4, 6]].

:- end_tests(translator_hyperpose).

:- begin_tests(translator_meta_store).

meta_store_function('$plunit_meta_store').

setup_meta_store :-
    meta_store_function(F),
    clear_fun_meta(F),
    retractall(arity(F, _)).

cleanup_meta_store :-
    setup_meta_store.

test(function_store_keeps_newest_first,
     [setup(setup_meta_store), cleanup(cleanup_meta_store)]) :-
    meta_store_function(F),
    translate_clause([=, [F, X], [first, X]], _),
    translate_clause([=, [F, Y], [second, Y]], _),
    fun_meta_clauses(F, [fun_meta(SecondArgs, SecondBody),
                         fun_meta(FirstArgs, FirstBody)]),
    (SecondArgs-SecondBody) =@= ([Y]-[second, Y]),
    (FirstArgs-FirstBody) =@= ([X]-[first, X]).

test(drop_fun_meta_removes_one_variant_only,
     [setup(setup_meta_store), cleanup(cleanup_meta_store)]) :-
    meta_store_function(F),
    translate_clause([=, [F, X], [same, X]], _),
    translate_clause([=, [F, Y], [same, Y]], _),
    drop_fun_meta(F, [Z], [same, Z]),
    aggregate_all(count, fun_meta_clause(F, _, _), 1).

test(engine_state_does_not_use_function_names,
     [ setup((setup_meta_store,
              nb_setval(specneeded, user_spec_state),
              nb_setval(lambda_counter, user_lambda_state),
              ( nb_current('$petta_lambda_counter', _)
                -> nb_delete('$petta_lambda_counter')
                ; true ))),
       cleanup((cleanup_meta_store,
                nb_delete(specneeded),
                nb_delete(lambda_counter),
                ( nb_current('$petta_lambda_counter', _)
                  -> nb_delete('$petta_lambda_counter')
                  ; true ))) ]) :-
    translate_clause([=, [specneeded, X], X], _),
    translate_clause([=, [lambda_counter, Y], Y], _),
    next_lambda_name(lambda_1),
    nb_getval(specneeded, user_spec_state),
    nb_getval(lambda_counter, user_lambda_state).

:- end_tests(translator_meta_store).

:- begin_tests(translator_let).

test(self_reference_cannot_create_a_rational_tree,
     [occurs_check(false), timeout(1)]) :-
    translate_expr([let, X, [g, X], X], Goals, _),
    \+ call_goals(Goals).

test(acyclic_binding_keeps_let_semantics,
     [occurs_check(false)]) :-
    translate_expr([let, X, [value, 42], X], Goals, Out),
    once(call_goals(Goals)),
    Out == [value, 42].

:- end_tests(translator_let).

:- begin_tests(translator_stream_rewrites).

stream_rewrite_case(['trace!', 1, 2],
                    [progn, ['println!', 1], 2]).
stream_rewrite_case([unique, [superpose, a, a]],
                    [call, [superpose,
                            ['unique-atom', [collapse, [superpose, a, a]]]]]).
stream_rewrite_case(['alpha-unique', [superpose, a, a]],
                    [call, [superpose,
                            ['alpha-unique-atom',
                             [collapse, [superpose, a, a]]]]]).
stream_rewrite_case([union, [superpose, a], [superpose, b]],
                    [call, [superpose,
                            ['union-atom', [collapse, [superpose, a]],
                                           [collapse, [superpose, b]]]]]).
stream_rewrite_case([intersection, [superpose, a], [superpose, b]],
                    [call, [superpose,
                            ['intersection-atom', [collapse, [superpose, a]],
                                                  [collapse, [superpose, b]]]]]).
stream_rewrite_case([subtraction, [superpose, a], [superpose, b]],
                    [call, [superpose,
                            ['subtraction-atom', [collapse, [superpose, a]],
                                                 [collapse, [superpose, b]]]]]).

test(each_stream_rewrite_has_exactly_one_solution,
     [ forall(stream_rewrite_case(Input, Expected)),
       true(Solutions == [Expected]) ]) :-
    findall(Out, rewrite_streamops(Input, Out), Solutions).

test(trace_form_has_one_compilation) :-
    findall(Goals-Out, translate_expr(['trace!', 1, 2], Goals, Out),
            Solutions),
    Solutions = [[Print]-2],
    Print =@= 'println!'(1, _).

:- end_tests(translator_stream_rewrites).

:- begin_tests(translator_translation_depth).

nested_add(0, 0) :- !.
nested_add(N, ['+', 1, Inner]) :-
    N1 is N - 1,
    nested_add(N1, Inner).

test(nested_calls_compile_with_linear_work,
     [ true((GoalCount == 400, Inferences < 50000)) ]) :-
    nested_add(400, Expr),
    statistics(inferences, I0),
    translate_expr(Expr, Goals, _),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    length(Goals, GoalCount).

:- end_tests(translator_translation_depth).

:- begin_tests(translator_typed_currying,
               [ setup((retractall(user:fun(plunit_typed_curry)),
                        retractall(user:arity(plunit_typed_curry, _)),
                        retractall(user:'&self'(:, plunit_typed_curry, _)),
                        assertz(user:fun(plunit_typed_curry)),
                        assertz(user:arity(plunit_typed_curry, 3)),
                        assertz(user:'&self'(:, plunit_typed_curry,
                                             [->, 'Number', 'Number', 'Number'])))),
                 cleanup((retractall(user:fun(plunit_typed_curry)),
                          retractall(user:arity(plunit_typed_curry, _)),
                          retractall(user:'&self'(:, plunit_typed_curry, _)))) ]).

test(output_type_check_waits_for_a_return_value) :-
    translate_expr([plunit_typed_curry, 1], Goals, Partial),
    goals_list_to_conj(Goals, Goal),
    call(Goal),
    Partial == partial(plunit_typed_curry, [1]).

:- end_tests(translator_typed_currying).

:- begin_tests(translator_empty_forms).

empty_form_translation([superpose, []], [fail], _).
empty_form_translation(['let*', [], 42], [], 42).
empty_form_translation([case, 1, []], [fail], _).
empty_form_translation([reduce, []], [], []).
empty_form_translation([progn], [], []).

test(each_empty_special_form_has_defined_translation,
     [forall(empty_form_translation(Expr, ExpectedGoals, ExpectedOut))]) :-
    translate_expr(Expr, Goals, Out),
    Goals =@= ExpectedGoals,
    Out =@= ExpectedOut.

test(empty_reduce_is_a_value) :-
    reduce([], Out),
    Out == [].

:- end_tests(translator_empty_forms).

:- begin_tests(translator_evaluation_errors).

dynamic_arithmetic_error :-
    reduce(['+', 1, undefined_sym], _).

compiled_arithmetic_error :-
    translate_expr(['+', 1, undefined_sym], Goals, _),
    goals_list_to_conj(Goals, Conjunction),
    call(Conjunction).

captured_error(Goal, Type) :-
    catch(call(Goal), error(Type, _), true),
    nonvar(Type).

test(dynamic_and_compiled_calls_report_the_same_error) :-
    captured_error(dynamic_arithmetic_error, DynamicType),
    captured_error(compiled_arithmetic_error, CompiledType),
    DynamicType == type_error(evaluable, undefined_sym/0),
    CompiledType == DynamicType.

test(dynamic_errors_are_not_converted_to_failure,
     [throws(error(type_error(evaluable, undefined_sym/0), _))]) :-
    dynamic_arithmetic_error.

:- end_tests(translator_evaluation_errors).

:- begin_tests(translator_test_answers).

test(one_empty_expression_answer_is_a_value) :-
    translate_expr([test, [quote, []], []], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    with_output_to(string(Output), call(Goal)),
    Out == true,
    Output == "is (), should (). ✅ \n".

test(no_answer_is_not_an_empty_expression,
     [throws(error(petta_test_no_answer, _))]) :-
    translate_expr([test, [empty], []], Goals, _),
    goals_list_to_conj(Goals, Goal),
    call(Goal).

test(explicit_no_answer_assertion_keeps_the_existing_output) :-
    translate_expr(['test-no-answer', [empty]], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    with_output_to(string(Output), call(Goal)),
    Out == true,
    Output == "is (), should (). ✅ \n".

test(explicit_no_answer_rejects_an_empty_value,
     [throws(error(petta_test_failed([[]], []), _))]) :-
    translate_expr(['test-no-answer', [quote, []]], Goals, _),
    goals_list_to_conj(Goals, Goal),
    with_output_to(string(_), call(Goal)).

:- end_tests(translator_test_answers).

:- begin_tests(translator_branch_returns).

test(build_branch_without_goals_unifies_at_runtime) :-
    build_branch(true, Value, Out, Branch),
    Value \== Out,
    Branch == (Out = Value).

test(build_branch_keeps_variable_value_private_until_runtime) :-
    build_branch(produce(Value), Value, Out, Branch),
    Value \== Out,
    Branch == (produce(Value), Out = Value).

test(build_branch_moves_a_ground_value_before_its_goals) :-
    build_branch(check_value, answer, Out, Branch),
    Branch == (answer = Out, check_value).

test(private_branch_return_is_merged) :-
    Head = branch_private(Input, Out),
    Body0 = (guard -> (produce(Input, Value), Out = Value) ; Out = none),
    merge_branch_returns(Head, Body0, Body),
    Value == Out,
    Body == (guard -> produce(Input, Out) ; Out = none).

test(head_parameter_is_not_merged) :-
    Head = branch_head(Value, Out),
    Body0 = (guard -> (produce(Value), Out = Value) ; Out = none),
    merge_branch_returns(Head, Body0, Body),
    Value \== Out,
    Body == Body0.

test(value_used_outside_its_branch_is_not_merged) :-
    Head = branch_shared(Out),
    Body0 = (guard -> (produce(Value), Out = Value) ; consume(Value)),
    merge_branch_returns(Head, Body0, Body),
    Value \== Out,
    Body == Body0.

%The generator fuzzer found this third condition: a value produced before the
%conditional is not private to either arm, even when one arm returns it.
test(value_produced_before_the_branch_is_not_merged) :-
    Head = branch_prebound(Input, Out),
    Body0 = (produce(Input, Value),
             (guard -> Out = Value ; Out = none)),
    merge_branch_returns(Head, Body0, Body),
    Value \== Out,
    Body == Body0.

test(nested_alternatives_can_produce_one_private_return) :-
    Head = branch_nested(Out),
    Body0 = (guard -> ((choice -> left(Value) ; right(Value)),
                       Out = Value)
                   ; Out = none),
    merge_branch_returns(Head, Body0, Body),
    Value == Out,
    Body == (guard -> (choice -> left(Out) ; right(Out)) ; Out = none).

:- end_tests(translator_branch_returns).
