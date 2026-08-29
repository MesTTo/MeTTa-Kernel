% Purpose: verify runnable translation caching, variant keys, and invalidation.

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(translation_cache).

clear_translation_cache_test_state :-
    user:clear_translation_cache.

:- dynamic translation_compile_count/1.

install_translation_compile_counter :-
    retractall(translation_compile_count(_)),
    assertz(translation_compile_count(0)),
    %The compiler's own module, not the engine's. wrap_predicate/4 on a name
    %the engine merely IMPORTS wraps the import and leaves the definition
    %alone, so the counter watched a link nothing inside the compiler follows
    %and every run looked like a cache hit [measured 2026-08-22].
    wrap_predicate(translator:translate_runnable_expr(_, _, _),
                   translation_cache_acceptance_counter, Wrapped,
                   count_translation_compile(Wrapped)).

remove_translation_compile_counter :-
    unwrap_predicate(translator:translate_runnable_expr/3,
                     translation_cache_acceptance_counter),
    retractall(translation_compile_count(_)).

count_translation_compile(Wrapped) :-
    retract(translation_compile_count(Before)),
    After is Before + 1,
    assertz(translation_compile_count(After)),
    call(Wrapped).

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
                  translator:translated_form_cache(_, _, _, _, _, _),
                  1).

test(variant_calls_share_a_template_without_sharing_call_variables,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    %`(quote V)` is the cheapest form that compiles to no goals at all, which
    %is why it is the probe here. It answers its PAYLOAD, the quote being an
    %evaluation barrier rather than a wrapper, so the template's value is the
    %variable itself.
    translate_cached_expr([quote, X], [], X),
    translate_cached_expr([quote, Y], [], Y),
    X = first,
    var(Y),
    aggregate_all(count,
                  translator:translated_form_cache(_, _, _, _, _, _),
                  1).

test(a_numbervars_literal_cannot_alias_a_real_variable_key,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    translate_cached_expr([quote, _], _, VariableValue),
    translate_cached_expr([quote, '$VAR'(0)], _, LiteralValue),
    VariableValue = Variable,
    var(Variable),
    LiteralValue == '$VAR'(0),
    aggregate_all(count,
                  translator:translated_form_cache(_, _, _, _, _, _),
                  2).

test(a_function_change_evicts_only_templates_that_mention_its_name,
     [ setup(clear_translation_cache_test_state),
       cleanup(( clear_translation_cache_test_state,
                 metta_self_module(Module),
                 specializer:forget_symbol(Module, 'tc-late') )) ]) :-
    run_translated(['tc-late', 2], ['tc-late', 2]),
    run_translated([+, 1, 2], 3),
    aggregate_all(count,
                  translator:translated_form_cache(_, _, _, _, _, _),
                  2),
    process_metta_string("(= (tc-late $x) (+ $x 1))", _),
    \+ translator:translated_form_mention('tc-late', _),
    aggregate_all(count,
                  translator:translated_form_cache(_, _, _, _, _, _),
                  1),
    run_translated(['tc-late', 2], 3),
    translator:translated_form_mention('tc-late', _),
    metta_remove_atom('&self',
                      [=, ['tc-late', X], [+, X, 1]], _),
    \+ translator:translated_form_mention('tc-late', _),
    run_translated(['tc-late', 2], ['tc-late', 2]).

test(concurrent_first_use_publishes_one_template,
     [ setup(clear_translation_cache_test_state),
       cleanup(clear_translation_cache_test_state) ]) :-
    concurrent_forall(between(1, 32, _),
                      run_translated([+, 40, 2], 42),
                      [threads(32)]),
    aggregate_all(count,
                  translator:translated_form_cache(_, _, _, _, _, _),
                  1).

test(test_a_repeated_eval_does_not_recompile_and_the_effects_cluster_conforms,
     [ setup(( clear_translation_cache_test_state,
               process_metta_string("(: tc-effect (-> Atom String))", _),
               process_metta_string(
                   "(= (tc-effect $l) (prog1 \"s\" (add-atom &self (tc-ran))))",
                   _),
               clear_translation_cache_test_state,
               install_translation_compile_counter )),
       cleanup(( remove_translation_compile_counter,
                 clear_translation_cache_test_state,
                 remove_sexp('&self', ['tc-ran']),
                 metta_self_module(Module),
                 specializer:forget_symbol(Module, 'tc-effect') )) ]) :-
    once(run_translated([+, 20, 22], 42)),
    translation_compile_count(AfterFirst),
    assertion(AfterFirst == 1),
    once(run_translated([+, 20, 22], 42)),
    translation_compile_count(AfterSecond),
    assertion(AfterSecond == 1),
    aggregate_all(count,
                  translator:translated_form_cache(_, _, _, _, _, _),
                  1),
    once(run_translated([+, 1, ['tc-effect', 'TC-MARK']], Answer)),
    swrite(Answer, Text),
    assertion(Text == "(Error (+ 1 (tc-effect TC-MARK)) (BadArgType 2 Number String))"),
    assertion(\+ get_native_atom('&self', ['tc-ran'])).

:- end_tests(translation_cache).
