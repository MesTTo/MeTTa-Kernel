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
              nb_setval(lambda_counter, user_lambda_state))),
       cleanup((cleanup_meta_store,
                nb_delete(specneeded),
                nb_delete(lambda_counter))) ]) :-
    translate_clause([=, [specneeded, X], X], _),
    translate_clause([=, [lambda_counter, Y], Y], _),
    next_lambda_name(First),
    next_lambda_name(Second),
    First \== Second,
    nb_getval(specneeded, user_spec_state),
    nb_getval(lambda_counter, user_lambda_state).

%A lambda name must be unique across the whole process, not per thread. SWI
%global variables are thread-local, so a counter kept in one gave each
%hyperpose worker its own sequence from 1: two threads generated lambda_1 and
%the second assertz added its body to the first lambda's predicate, so one
%lambda answered with both branches' results.
test(lambda_names_are_unique_across_threads) :-
    next_lambda_name(Main),
    concurrent_maplist([_,Name]>>next_lambda_name(Name), [1,2,3,4], Workers),
    msort([Main|Workers], Sorted),
    sort([Main|Workers], Unique),
    Sorted == Unique.

:- end_tests(translator_meta_store).

:- begin_tests(translator_let).

test(a_data_self_reference_cannot_create_a_rational_tree,
     [occurs_check(false), timeout(1)]) :-
    translate_expr([let, X, [g, X], X], Goals, _),
    \+ call_goals(Goals).

%[g, X] above is data and needs no goals, so the check sees the whole value
%wherever it is emitted. A value that has to be computed does not: emitted
%ahead of the goals that build it, the check ran on an unbound result, could
%not fail, and the binding became a rational tree.
test(a_computed_self_reference_cannot_create_a_rational_tree,
     [occurs_check(false), timeout(1)]) :-
    translate_expr([let, X, ['cons-atom', X, []], X], Goals, _),
    \+ call_goals(Goals).

%A value that shares no variable with the pattern cannot be built out of the
%pattern, so its check stays ahead of the value's goals, where it runs on two
%unbound variables and costs nothing. Moving every let's check behind its
%value measured 2.7x wall clock on a let-heavy workload.
test(an_unshared_value_keeps_its_check_ahead_of_the_value_goals) :-
    translate_expr([let, _X, ['cons-atom', a, []], done], Goals, _),
    Goals = [unify_with_occurs_check(_, _)|_].

test(a_shared_value_moves_its_check_behind_the_value_goals) :-
    translate_expr([let, X, ['cons-atom', X, []], done], Goals, _),
    last(Goals, unify_with_occurs_check(_, _)).

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

:- begin_tests(translator_prolog_imports).

prolog_importer(import_prolog_functions_from_file).
prolog_importer(import_prolog_functions_from_module).

test(each_prolog_import_has_one_translation,
     [ forall(prolog_importer(Importer)),
       true(Solutions = [_]) ]) :-
    findall(Goals-Out,
            translate_expr([Importer, source, [imported_function]], Goals,
                           Out),
            Solutions),
    Solutions = [[Goal]-_],
    functor(Goal, Importer, 3).

:- end_tests(translator_prolog_imports).

:- begin_tests(translator_translation_depth).

nested_add(0, 0) :- !.
nested_add(N, ['+', 1, Inner]) :-
    N1 is N - 1,
    nested_add(N1, Inner).

nested_head(0, _) :- !.
nested_head(N, [Inner]) :-
    N1 is N - 1,
    nested_head(N1, Inner).

test(nested_calls_compile_with_linear_work,
     [ true((GoalCount == 400, Inferences < 50000)) ]) :-
    nested_add(400, Expr),
    statistics(inferences, I0),
    translate_expr(Expr, Goals, _),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    length(Goals, GoalCount).

test(nested_heads_compile_with_linear_work,
     [ true((GoalCount == 400, Inferences < 50000)) ]) :-
    nested_head(400, Expr),
    statistics(inferences, I0),
    translate_expr(Expr, Goals, _),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    length(Goals, GoalCount).

:- end_tests(translator_translation_depth).

:- begin_tests(translator_reduction_status).

test(a_called_function_reports_reduced) :-
    reduce(['+', 1, 2], Out, Status),
    Out == 3,
    Status == reduced.

test(an_uncallable_head_reports_not_reducible) :-
    reduce([plunit_no_such_head, 1], Out, Status),
    Out == [plunit_no_such_head, 1],
    Status == 'not-reducible'.

test(the_empty_expression_reports_not_reducible) :-
    reduce([], Out, Status),
    Out == [],
    Status == 'not-reducible'.

test(reduce_of_arity_two_keeps_its_exact_behaviour) :-
    % Every compiled call site uses reduce/2; the status must be additive.
    reduce(['+', 1, 2], Out),
    Out == 3.

:- end_tests(translator_reduction_status).

:- begin_tests(translator_special_dispatch).

expected_special_heads([
    'add-atom', 'and-then', 'catch', 'filter-atom', 'foldall',
    'foldl-atom', 'forall', 'let*', 'map-atom', 'or-else',
    'remove-atom', 'test-no-answer', '|->', call, case, chain, collapse,
    cut, eval, hyperpose, if, let, match, once, prog1, progn, quote,
    reduce, sealed, superpose, test, transaction, translatePredicate,
    with_mutex
]).

special_dispatch_expression([superpose, [1, 2]]).
special_dispatch_expression([collapse, [quote, answer]]).
special_dispatch_expression([if, true, yes, no]).
special_dispatch_expression([let, X, 1, X]).
special_dispatch_expression([quote, [a, b]]).
special_dispatch_expression(['catch', [quote, answer]]).

test(each_special_form_clause_has_an_indexable_head) :-
    findall(Head,
            clause(user:translate_special_dl(Head, _, _, _, _), _),
            Heads0),
    sort(Heads0, Heads),
    expected_special_heads(Expected0),
    sort(Expected0, Expected),
    Heads == Expected.

test(dispatch_uses_a_realised_first_argument_index) :-
    forall(between(1, 1000, _),
           once(translate_expr([quote, answer], _, _))),
    predicate_property(user:translate_special_dl(_, _, _, _, _),
                       indexed(Indexes)),
    once(( member(Index, Indexes),
           Index.arguments == [1],
           Index.realised == true )).

test(representative_forms_each_have_one_translation,
     [forall(special_dispatch_expression(Expr))]) :-
    findall(Goals-Out, translate_expr(Expr, Goals, Out), Solutions),
    Solutions = [_].

test(variable_heads_are_not_bound_to_a_special_form) :-
    % The emitted goal is reduce/3: a variable head is decided at runtime,
    % and that is the decision the evaluation status comes from.
    translate_expr([Head, 1], Goals, _),
    var(Head),
    Goals = [reduce([Head, 1], _, _)].

test(space_predicates_use_space_storage,
     [ setup(add_sexp('&self', [plunit_space_predicate, a, b])),
       cleanup(remove_sexp('&self',
                           [plunit_space_predicate, _, _])) ]) :-
    translate_expr(
        [translatePredicate, ['&self', plunit_space_predicate, A, B]],
        Goals,
        _),
    goals_list_to_conj(Goals, Goal),
    once(call(Goal)),
    A-B == a-b,
    'Predicate'(['&self', plunit_space_predicate, C, D], Constructed),
    once(call(Constructed)),
    C-D == a-b.

:- end_tests(translator_special_dispatch).

:- begin_tests(translator_typed_currying,
               [ setup((retractall(user:fun(plunit_typed_curry)),
                        retractall(user:arity(plunit_typed_curry, _)),
                        remove_sexp('&self',
                                    [':', plunit_typed_curry, _]),
                        assertz(user:fun(plunit_typed_curry)),
                        assertz(user:arity(plunit_typed_curry, 3)),
                        add_sexp('&self',
                                 [':', plunit_typed_curry,
                                  [->, 'Number', 'Number', 'Number']]))),
                 cleanup((retractall(user:fun(plunit_typed_curry)),
                          retractall(user:arity(plunit_typed_curry, _)),
                          remove_sexp('&self',
                                      [':', plunit_typed_curry, _]))) ]).

test(output_type_check_waits_for_a_return_value) :-
    translate_expr([plunit_typed_curry, 1], Goals, Partial),
    goals_list_to_conj(Goals, Goal),
    call(Goal),
    Partial == partial(plunit_typed_curry, [1]).

:- end_tests(translator_typed_currying).

:- begin_tests(translator_typed_single_pass,
               [ setup((retractall(user:fun(plunit_typed_once)),
                        retractall(user:arity(plunit_typed_once, _)),
                        remove_sexp('&self', [':', plunit_typed_once, _]),
                        assertz(user:fun(plunit_typed_once)),
                        assertz(user:arity(plunit_typed_once, 3)),
                        add_sexp('&self',
                                 [':', plunit_typed_once,
                                  [->, '%Undefined%', 'Number', 'Number']]))),
                 cleanup((retractall(user:fun(plunit_typed_once)),
                          retractall(user:arity(plunit_typed_once, _)),
                          remove_sexp('&self',
                                      [':', plunit_typed_once, _]))) ]).

%next_lambda_name/1 counts in gensym's process-wide flag, whose key gensym/2
%builds as '$gs_' followed by the base.
lambda_counter_value(Value) :-
    flag('$gs_lambda_', Value, Value).

cleanup_generated_lambdas(First) :-
    lambda_counter_value(Last),
    Start is First + 1,
    forall(between(Start, Last, Number),
           ( format(atom(Name), 'lambda_~d', [Number]),
             forget_symbol(Name) )).

test(typed_argument_is_compiled_once) :-
    lambda_counter_value(Before),
    setup_call_cleanup(
        true,
        ( translate_expr(
              [plunit_typed_once, ['|->', [X], ['+', X, 1]], 41],
              _Goals, _Out),
          lambda_counter_value(After),
          After - Before =:= 1 ),
        cleanup_generated_lambdas(Before)).

:- end_tests(translator_typed_single_pass).

:- begin_tests(translator_typed_checks,
               [ setup(setup_typed_checks),
                 cleanup(cleanup_typed_checks) ]).

typed_check_fact(plunit_typed_x, plunit_a).
typed_check_fact(plunit_typed_y, plunit_b).
typed_check_fact([plunit_typed_x, plunit_typed_y],
                 [plunit_a, plunit_b]).
typed_check_fact(plunit_multi_type, plunit_a).
typed_check_fact(plunit_multi_type, plunit_b).
typed_check_fact(plunit_only_b, plunit_b).

setup_typed_checks :-
    cleanup_typed_checks,
    forall(typed_check_fact(Term, Type),
           add_sexp('&self', [':', Term, Type])),
    add_sexp('&self',
             [':', plunit_same_type,
              [->, Shared, Shared, 'Number']]),
    assertz(user:fun(plunit_same_type)),
    assertz(user:arity(plunit_same_type, 3)),
    assertz(user:plunit_same_type(_, _, 1)).

cleanup_typed_checks :-
    forall(typed_check_fact(Term, _),
           remove_sexp('&self', [':', Term, _])),
    remove_sexp('&self', [':', plunit_same_type, _]),
    retractall(user:plunit_same_type(_, _, _)),
    retractall(user:arity(plunit_same_type, _)),
    retractall(user:fun(plunit_same_type)).

test(argument_checks_do_not_multiply_duplicate_derivations) :-
    Expr = [plunit_typed_x, plunit_typed_y],
    translate_expr([plunit_same_type, Expr, Expr], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    findall(Out, call(Goal), Answers),
    Answers == [1].

test(shared_type_variables_can_reach_a_later_consistent_type) :-
    translate_expr([plunit_same_type, plunit_multi_type, plunit_only_b],
                   Goals, Out),
    goals_list_to_conj(Goals, Goal),
    findall(Out, call(Goal), Answers),
    Answers == [1].

:- end_tests(translator_typed_checks).

:- begin_tests(translator_type_extensions).

test(get_type_equations_compile_behind_the_answer_boundary) :-
    Source = [=, ['get-type', plunit_extended_type], plunit_extension],
    setup_call_cleanup(
        true,
        ( translate_clause(Source, Clause),
          Clause = (Head :- _),
          functor(Head, get_type_rule, 2),
          setup_call_cleanup(
              assertz(user:Clause, Ref),
              ( findall(Type, 'get-type'(plunit_extended_type, Type), Types),
                Types == [plunit_extension] ),
              erase(Ref)) ),
        drop_fun_meta('get-type', [plunit_extended_type],
                      plunit_extension)).

:- end_tests(translator_type_extensions).

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

captured_operation_error(Goal, Type, Operation) :-
    catch(call(Goal), Error, true),
    nonvar(Error),
    Error = error(Type, context(Operation, _)).

test(dynamic_and_compiled_calls_report_the_same_error) :-
    captured_error(dynamic_arithmetic_error, DynamicType),
    captured_error(compiled_arithmetic_error, CompiledType),
    DynamicType == type_error(number, undefined_sym),
    CompiledType == DynamicType.

test(dynamic_and_compiled_calls_name_the_written_operation) :-
    captured_operation_error(dynamic_arithmetic_error, DynamicType,
                             DynamicOperation),
    captured_operation_error(compiled_arithmetic_error, CompiledType,
                             CompiledOperation),
    DynamicType == type_error(number, undefined_sym),
    CompiledType == DynamicType,
    DynamicOperation == '+',
    CompiledOperation == DynamicOperation.

test(dynamic_errors_are_not_converted_to_failure,
     [throws(error(type_error(number, undefined_sym), _))]) :-
    dynamic_arithmetic_error.

test(an_unknown_head_remains_inert_data) :-
    translate_expr([plunit_inert_head, 1], Goals, Out),
    Goals == [],
    Out == [plunit_inert_head, 1].

test(quote_keeps_an_invalid_builtin_call_inert) :-
    translate_expr([quote, ['+', 1, undefined_sym]], Goals, Out),
    call_goals(Goals),
    Out == ['+', 1, undefined_sym].

cleanup_builtin_type_declarations(Path, ParsedForms) :-
    forall(member(parsed(expression, _, Term), ParsedForms),
           remove_sexp('&self', Term)),
    retractall(compiled_metta_source(Path)),
    retractall(imported_metta_source('&self', Path)),
    retractall(import_life('&self', Path, _)).

test(builtin_type_import_keeps_runtime_errors_loud) :-
    once(( absolute_file_name('../../lib/lib_builtin_types.metta', Path,
                              [access(read)]),
           read_metta_source(Path, Source),
           parse_metta_source(Source, ParsedForms) )),
    setup_call_cleanup(
        once(load_metta_file(Path, _)),
        once(( captured_operation_error(compiled_arithmetic_error,
                                        ArithmeticType,
                                        ArithmeticOperation),
               ArithmeticType == type_error(number, undefined_sym),
               ArithmeticOperation == '+',
               translate_expr([and, true, 5], BoolGoals, _),
               goals_list_to_conj(BoolGoals, BoolGoal),
               captured_operation_error(BoolGoal, BoolType, BoolOperation),
               BoolType == type_error(boolean, 5),
               BoolOperation == and,
               translate_expr(['min-atom', 5], MinGoals, MinOut),
               goals_list_to_conj(MinGoals, MinGoal),
               call(MinGoal),
               MinOut == [] )),
        cleanup_builtin_type_declarations(Path, ParsedForms)).

:- end_tests(translator_evaluation_errors).

:- begin_tests(translator_terminal_output).

test(nonterminal_compiler_output_has_no_ansi_escapes) :-
    with_output_to(string(Output),
                   maybe_print_compiled_clause(test_label,
                                               [=, [f, x], x],
                                               (f(X, X) :- true))),
    once(sub_string(Output, _, _, _, "-->  test_label  -->")),
    \+ sub_string(Output, _, _, _, "\e[").

:- end_tests(translator_terminal_output).

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
