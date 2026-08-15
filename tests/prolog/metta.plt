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

host_error_case('+', '+'(1, invalid_number, _)).
host_error_case('+', '+'(1.0e308, 1.0e308, _)).
host_error_case('-', '-'(1, invalid_number, _)).
host_error_case('-', '-'(1.0e308, -1.0e308, _)).
host_error_case('*', '*'(1, invalid_number, _)).
host_error_case('*', '*'(1.0e308, 2.0, _)).
host_error_case('/', '/'(1, invalid_number, _)).
host_error_case('/', '/'(1, 0, _)).
host_error_case('/', '/'(1.0e308, 1.0e-308, _)).
host_error_case('%', '%'(1, invalid_number, _)).
host_error_case('%', '%'(1, 0, _)).
host_error_case('<', '<'(1, invalid_number, _)).
host_error_case('>', '>'(1, invalid_number, _)).
host_error_case('<=', '<='(1, invalid_number, _)).
host_error_case('>=', '>='(1, invalid_number, _)).
host_error_case(min, min(1, invalid_number, _)).
host_error_case(max, max(1, invalid_number, _)).
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
host_error_case('exp-math', 'exp-math'(10000, _)).
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

:- end_tests(metta_operation_errors).

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
    assertz(user:get_type_rule([plunit_type_a, plunit_type_b],
                               [plunit_a, plunit_b])).

cleanup_type_answers :-
    forall(type_answer_fact(Term, _),
           remove_sexp('&self', [':', Term, _])),
    retractall(user:get_type_rule([plunit_type_a, plunit_type_b], _)).

test(user_boundary_returns_each_type_once) :-
    findall(Type,
            'get-type'([plunit_type_a, plunit_type_b], Type),
            Types),
    Types == [[plunit_a, plunit_b]].

test(alpha_equivalent_polymorphic_types_are_one_answer,
     [ setup((assertz(user:get_type_rule(plunit_poly_type,
                                        ['->', A, A])),
              assertz(user:get_type_rule(plunit_poly_type,
                                        ['->', B, B])))),
       cleanup(retractall(user:get_type_rule(plunit_poly_type, _)))
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

:- end_tests(metta_type_answers).

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

:- end_tests(metta_set_operations).
