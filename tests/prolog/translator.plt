% Purpose: direct PlUnit coverage for translator control forms and branch
%   rewrites whose failures are difficult to localize through whole examples.
% Open Obligations:
%   To Do: Add build_branch/4, merge_branch_returns/3, and the remaining
%     stream-rewrite determinism cases from the engine review.
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
