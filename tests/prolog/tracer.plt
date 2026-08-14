% Purpose: verify tracing follows functions created by traced source and
%   records calls made by hyperpose worker threads.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(tracer).

cleanup_trace_function(F) :-
    findall(Ref,
            ( user:translated_from(Ref, [=, [F|_], _]),
              \+ clause_property(Ref, erased) ),
            Refs),
    forall(member(Ref, Refs),
           ( erase(Ref), retractall(user:translated_from(Ref, _)) )),
    remove_sexp('&self', [=, [F|_], _]),
    user:clear_fun_meta(F),
    retractall(user:arity(F, _)),
    retractall(user:fun(F)),
    user:unregister_fun_everywhere(F).

setup_trace_test :-
    retractall(user:silent(_)),
    assertz(user:silent(true)),
    cleanup_trace_function(plunit_trace_new),
    cleanup_trace_function(plunit_trace_named),
    retractall(user:'&plunit_trace_named'(=,
                                          [plunit_trace_named|_], _)),
    cleanup_trace_function(plunit_trace_hyperpose).

cleanup_trace_test :-
    cleanup_trace_function(plunit_trace_new),
    cleanup_trace_function(plunit_trace_named),
    cleanup_trace_function(plunit_trace_hyperpose),
    retractall(user:'&plunit_trace_named'(=,
                                          [plunit_trace_named|_], _)),
    retractall(user:silent(_)),
    assertz(user:silent(false)).

test(function_defined_in_source_is_traced,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    Source = "(= (plunit_trace_new $x) (+ $x 1))\n\
!(plunit_trace_new 1)",
    metta_trace_source(Source, '&self', Events),
    Events == ["0\tcall\t(plunit_trace_new 1)\t",
               "0\texit\t(plunit_trace_new 1)\t2"].

test(function_defined_in_named_trace_stays_in_that_space,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    Space = '&plunit_trace_named',
    Source = "(= (plunit_trace_named $x) (+ $x 1))\n\
!(plunit_trace_named 1)",
    metta_trace_source(Source, Space, Events),
    space_module(Space, Module),
    functor(Head, plunit_trace_named, 2),
    clause(Module:Head, _, Ref),
    clause_property(Ref, module(Module)),
    \+ clause(user:Head, _, _),
    Events == ["0\tcall\t(plunit_trace_named 1)\t",
               "0\texit\t(plunit_trace_named 1)\t2"].

test(hyperpose_workers_share_the_trace_event_store,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    process_metta_string("(= (plunit_trace_hyperpose $x) (+ $x 1))", _),
    metta_trace_source(
        "!(hyperpose ((plunit_trace_hyperpose 1) (plunit_trace_hyperpose 2)))",
        '&self', Events),
    msort(Events, Sorted),
    msort(["0\tcall\t(plunit_trace_hyperpose 1)\t",
           "0\tcall\t(plunit_trace_hyperpose 2)\t",
           "0\texit\t(plunit_trace_hyperpose 1)\t2",
           "0\texit\t(plunit_trace_hyperpose 2)\t3"],
          Expected),
    Sorted == Expected.

cleanup_trace_type_extension :-
    findall(Ref,
            ( user:translated_from(
                  Ref,
                  [=, ['get-type', plunit_trace_type], _]),
              \+ clause_property(Ref, erased) ),
            Refs),
    forall(member(Ref, Refs),
           ( erase(Ref), retractall(user:translated_from(Ref, _)) )),
    remove_sexp('&self', [=, ['get-type', plunit_trace_type], _]),
    retractall(user:get_type_rule(plunit_trace_type, _)),
    drop_fun_meta('get-type', [plunit_trace_type], plunit_traced_type),
    unregister_fun_in(user, 'get-type').

test(type_extensions_keep_the_public_name,
     [ setup(cleanup_trace_type_extension),
       cleanup(cleanup_trace_type_extension) ]) :-
    Source = "(= (get-type plunit_trace_type) plunit_traced_type)\n\
!(get-type plunit_trace_type)",
    metta_trace_source(Source, '&self', Events),
    Events == ["0\tcall\t(get-type plunit_trace_type)\t",
               "0\texit\t(get-type plunit_trace_type)\tplunit_traced_type"].

test(event_limit_error_removes_every_wrapper,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    process_metta_string("(= (plunit_trace_hyperpose $x) (+ $x 1))", _),
    catch(metta_trace_source("!(plunit_trace_hyperpose 1)", '&self', 1, _),
          Error,
          true),
    nonvar(Error),
    Error = error(resource_error(petta_trace_events(1)), _),
    \+ user:metta_trace_session,
    \+ current_predicate_wrapper(user:plunit_trace_hyperpose(_, _),
                                  petta_tracer, _, _),
    metta_trace_source("!(plunit_trace_hyperpose 2)", '&self', Events),
    Events == ["0\tcall\t(plunit_trace_hyperpose 2)\t",
               "0\texit\t(plunit_trace_hyperpose 2)\t3"].

:- end_tests(tracer).
