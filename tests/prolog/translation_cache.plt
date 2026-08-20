% Purpose: verify runnable translation caching, variant keys, and invalidation.

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(translation_cache).

clear_translation_cache_test_state :-
    user:clear_translation_cache.

run_translated(Expression, Answer) :-
    translate_cached_expr(Expression, Goals, Answer),
    current_metta_module(Module),
    call_goals_in_(Module, Goals).

test(a_repeated_eval_reuses_one_translated_template,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    run_translated([+, 20, 22], 42),
    run_translated([+, 20, 22], 42),
    aggregate_all(count,
                  user:translated_form_cache(_, _, _, _, _, _),
                  1).

test(variant_calls_share_a_template_without_sharing_call_variables,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    translate_cached_expr([quote, X], [], [quote, X]),
    translate_cached_expr([quote, Y], [], [quote, Y]),
    X = first,
    var(Y),
    aggregate_all(count,
                  user:translated_form_cache(_, _, _, _, _, _),
                  1).

test(a_numbervars_literal_cannot_alias_a_real_variable_key,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    translate_cached_expr([quote, _], _, VariableValue),
    translate_cached_expr([quote, '$VAR'(0)], _, LiteralValue),
    VariableValue = [quote, Variable],
    var(Variable),
    LiteralValue == [quote, '$VAR'(0)],
    aggregate_all(count,
                  user:translated_form_cache(_, _, _, _, _, _),
                  2).

test(a_function_change_evicts_only_templates_that_mention_its_name,
     [ setup(clear_translation_cache_test_state),
       cleanup(( clear_translation_cache_test_state,
                 metta_self_module(Module),
                 forget_symbol(Module, 'tc-late') )) ]) :-
    run_translated(['tc-late', 2], ['tc-late', 2]),
    run_translated([+, 1, 2], 3),
    aggregate_all(count,
                  user:translated_form_cache(_, _, _, _, _, _),
                  2),
    process_metta_string("(= (tc-late $x) (+ $x 1))", _),
    \+ user:translated_form_mention('tc-late', _),
    aggregate_all(count,
                  user:translated_form_cache(_, _, _, _, _, _),
                  1),
    run_translated(['tc-late', 2], 3),
    user:translated_form_mention('tc-late', _),
    metta_remove_atom('&self',
                      [=, ['tc-late', X], [+, X, 1]], _),
    \+ user:translated_form_mention('tc-late', _),
    run_translated(['tc-late', 2], ['tc-late', 2]).

test(concurrent_first_use_publishes_one_template,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    concurrent_forall(between(1, 32, _),
                      run_translated([+, 40, 2], 42),
                      [threads(32)]),
    aggregate_all(count,
                  user:translated_form_cache(_, _, _, _, _, _),
                  1).

:- end_tests(translation_cache).
