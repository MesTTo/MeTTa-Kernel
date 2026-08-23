% Purpose: prove the host-visible function-catalogue generation contract.
% Assumes:
%   - petta_py_builtins/1 is the catalogue consumer and reads fun/1 plus the
%     engine's static special-form service.
% Guarantees:
%   - the process-wide generation advances exactly when the fun/1 set can
%     change through registration, definition, import, and removal routes
%     [tested: function_catalogue_generation; commit=4c9a794750103e0a3a2e9d883adde337ffb501f0]
%   - a rolled-back fun/1 assertion changes neither the visible set nor its
%     generation [tested: a_rolled_back_definition_is_generation_neutral;
%     commit=4c9a794750103e0a3a2e9d883adde337ffb501f0]
%   - plain evaluation and data writes are generation-neutral
%     [tested: function_catalogue_generation; commit=4c9a794750103e0a3a2e9d883adde337ffb501f0]
%   - runtime translator-rule addition and removal change neither generation
%     nor petta_py_builtins/1's answer set [tested:
%     translator_rules_are_catalogue_neutral; commit=4c9a794750103e0a3a2e9d883adde337ffb501f0]
%   - a mutation in one engine thread is visible to a host read in another
%     [tested: a_worker_mutation_is_visible_to_the_calling_thread;
%     commit=4c9a794750103e0a3a2e9d883adde337ffb501f0]
%   - loading this suite under the gate never runs the standalone CLI against
%     the gate's argv [tested: sh tests/prolog/run-tests.sh; commit=WORKTREE]
% Guarded by:
%   - SWI's last_modified_generation property is maintained by the dynamic
%     database and shared by all engine threads.

:- ensure_loaded('../../engine/metta.pl').
:- ensure_loaded('../../bindings/python/petta/shim.pl').

forget_generation_function(Name) :-
    retractall(fun(Name)),
    retractall(arity(Name, _)),
    retractall(fun_in(_, Name)),
    retractall(fun_scoped(Name)).

write_generation_source(Stream, Name) :-
    format(Stream, '(= (~w $x) $x)~n', [Name]).

:- begin_tests(function_catalogue_generation).

test(the_shim_reads_the_engine_generation) :-
    metta_host_function_generation(Engine),
    petta_py_function_generation(Shim),
    assertion(Shim =:= Engine).

test(a_fresh_registration_bumps_once_and_reregistration_does_not,
     [ cleanup(forget_generation_function('p14-generation-register')) ]) :-
    metta_host_function_generation(Before),
    register_fun('p14-generation-register'),
    metta_host_function_generation(Added),
    register_fun('p14-generation-register'),
    metta_host_function_generation(Repeated),
    assertion(Added > Before),
    assertion(Repeated =:= Added).

test(a_definition_bumps_once_for_the_function_set,
     [ cleanup(( metta_remove_atom('&self',
                                   [=, ['p14-generation-definition', _], _], _),
                 forget_generation_function('p14-generation-definition') )) ]) :-
    metta_host_function_generation(Before),
    process_metta_string(
        "(= (p14-generation-definition zero) 0)\n\
(= (p14-generation-definition one) 1)", _),
    metta_host_function_generation(After),
    assertion(After > Before).

test(an_import_bringing_an_equation_bumps_once,
     [ cleanup(forget_generation_function('p14-generation-import')) ]) :-
    tmp_file(p14_generation, Stem),
    atom_concat(Stem, '.metta', Path),
    setup_call_cleanup(
        open(Path, write, Stream, [encoding(utf8)]),
        ( write_generation_source(Stream, 'p14-generation-import'),
          close(Stream),
          metta_host_function_generation(Before),
          'import!'('&self', Path, _),
          metta_host_function_generation(After),
          assertion(After > Before) ),
        ( ( is_stream(Stream) -> close(Stream, [force(true)]) ; true ),
          ( exists_file(Path) -> delete_file(Path) ; true ) )).

test(the_last_definition_removal_bumps_but_a_partial_removal_does_not,
     [ cleanup(forget_generation_function('p14-generation-remove')) ]) :-
    First = [=, ['p14-generation-remove', zero], 0],
    Second = [=, ['p14-generation-remove', one], 1],
    metta_add_atom('&self', First, _),
    metta_add_atom('&self', Second, _),
    metta_host_function_generation(Added),
    metta_remove_atom('&self', First, _),
    metta_host_function_generation(Partial),
    metta_remove_atom('&self', Second, _),
    metta_host_function_generation(Removed),
    assertion(Partial =:= Added),
    assertion(Removed > Partial).

test(a_rolled_back_definition_is_generation_neutral,
     [ cleanup(forget_generation_function('p14-generation-rollback')) ]) :-
    metta_host_function_generation(Before),
    catch(transaction(( assertz(fun('p14-generation-rollback')),
                        throw(p14_generation_rollback) )),
          p14_generation_rollback, true),
    metta_host_function_generation(After),
    assertion(After =:= Before),
    assertion(\+ fun('p14-generation-rollback')).

test(plain_evaluation_and_plain_data_adds_do_not_bump) :-
    Space = '&p14-generation-data',
    setup_call_cleanup(
        true,
        ( metta_host_function_generation(Before),
          eval([+, 1, 2], 3),
          metta_add_atom(Space, [plain, data], _),
          metta_host_function_generation(After),
          assertion(After =:= Before) ),
        clear_native_atoms(Space)).

test(successive_set_changes_are_monotonic,
     [ cleanup(( forget_generation_function('p14-generation-monotonic-a'),
                 forget_generation_function('p14-generation-monotonic-b') )) ]) :-
    metta_host_function_generation(Before),
    register_fun('p14-generation-monotonic-a'),
    metta_host_function_generation(First),
    register_fun('p14-generation-monotonic-b'),
    metta_host_function_generation(Second),
    assertion(Before < First),
    assertion(First < Second).

test(a_worker_mutation_is_visible_to_the_calling_thread,
     [ cleanup(forget_generation_function('p14-generation-thread')) ]) :-
    metta_host_function_generation(Before),
    setup_call_cleanup(
        message_queue_create(Queue),
        ( thread_create(
              ( register_fun('p14-generation-thread'),
                metta_host_function_generation(WorkerSeen),
                thread_send_message(Queue, WorkerSeen) ),
              Thread, []),
          thread_join(Thread, true),
          thread_get_message(Queue, WorkerSeen),
          metta_host_function_generation(ParentSeen),
          assertion(WorkerSeen > Before),
          assertion(ParentSeen =:= WorkerSeen) ),
        message_queue_destroy(Queue)).

:- end_tests(function_catalogue_generation).

:- begin_tests(translator_rules_are_catalogue_neutral).

test(add_and_remove_leave_generation_and_builtins_unchanged,
     [ cleanup(( 'remove-translator-rule!'('p14-generation-translator', _),
                 metta_remove_atom('&self',
                                   [=, ['p14-generation-translator', _], _], _),
                 forget_generation_function('p14-generation-translator') )) ]) :-
    process_metta_string(
        "(= (p14-generation-translator $x) (noeval (translated $x)))", _),
    metta_host_function_generation(BeforeGeneration),
    petta_py_builtins(BeforeBuiltins),
    'add-translator-rule!'('p14-generation-translator', _),
    metta_host_function_generation(AddedGeneration),
    petta_py_builtins(AddedBuiltins),
    'remove-translator-rule!'('p14-generation-translator', _),
    metta_host_function_generation(RemovedGeneration),
    petta_py_builtins(RemovedBuiltins),
    assertion(AddedGeneration =:= BeforeGeneration),
    assertion(RemovedGeneration =:= BeforeGeneration),
    assertion(AddedBuiltins == BeforeBuiltins),
    assertion(RemovedBuiltins == BeforeBuiltins).

:- end_tests(translator_rules_are_catalogue_neutral).
