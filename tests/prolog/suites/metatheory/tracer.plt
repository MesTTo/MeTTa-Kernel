% Purpose: verify tracing follows functions created by traced source and
%   records calls made by hyperpose worker threads.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(tracer).

cleanup_trace_function(F) :-
    findall(Ref,
            ( filereader:translated_from(Ref, [=, [F|_], _]),
              \+ clause_property(Ref, erased) ),
            Refs),
    forall(member(Ref, Refs),
           ( erase(Ref), retractall(filereader:translated_from(Ref, _)) )),
    remove_sexp('&self', [=, [F|_], _]),
    user:clear_fun_meta(_, F),
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
    tracer:metta_trace_source(Source, '&self', Events),
    Events == [event(0, call, [plunit_trace_new, 1], '', []),
               event(0, exit, [plunit_trace_new, 1], 2, [])].

test(function_defined_in_named_trace_stays_in_that_space,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    Space = '&plunit_trace_named',
    Source = "(= (plunit_trace_named $x) (+ $x 1))\n\
!(plunit_trace_named 1)",
    tracer:metta_trace_source(Source, Space, Events),
    space_module(Space, Module),
    functor(Head, plunit_trace_named, 2),
    clause(Module:Head, _, Ref),
    clause_property(Ref, module(Module)),
    \+ clause(user:Head, _, _),
    Events == [event(0, call, [plunit_trace_named, 1], '', []),
               event(0, exit, [plunit_trace_named, 1], 2, [])].

test(hyperpose_workers_share_the_trace_event_store,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    process_metta_string("(= (plunit_trace_hyperpose $x) (+ $x 1))", _),
    tracer:metta_trace_source(
        "!(hyperpose ((plunit_trace_hyperpose 1) (plunit_trace_hyperpose 2)))",
        '&self', Events),
    msort(Events, Sorted),
    msort([event(0, call, [plunit_trace_hyperpose, 1], '', []),
           event(0, call, [plunit_trace_hyperpose, 2], '', []),
           event(0, exit, [plunit_trace_hyperpose, 1], 2, []),
           event(0, exit, [plunit_trace_hyperpose, 2], 3, [])],
          Expected),
    Sorted == Expected.

cleanup_trace_type_extension :-
    findall(Ref,
            ( filereader:translated_from(
                  Ref,
                  [=, ['get-type', plunit_trace_type], _]),
              \+ clause_property(Ref, erased) ),
            Refs),
    forall(member(Ref, Refs),
           ( erase(Ref), retractall(filereader:translated_from(Ref, _)) )),
    remove_sexp('&self', [=, ['get-type', plunit_trace_type], _]),
    retractall(user:get_type_rule(plunit_trace_type, _)),
    drop_fun_meta(_, 'get-type', [plunit_trace_type], plunit_traced_type),
    unregister_fun_in(user, 'get-type').

test(type_extensions_keep_the_public_name,
     [ setup(cleanup_trace_type_extension),
       cleanup(cleanup_trace_type_extension) ]) :-
    Source = "(= (get-type plunit_trace_type) plunit_traced_type)\n\
!(get-type plunit_trace_type)",
    tracer:metta_trace_source(Source, '&self', Events),
    Events == [event(0, call, ['get-type', plunit_trace_type], '', []),
               event(0, exit, ['get-type', plunit_trace_type],
                     plunit_traced_type, [])].

%The events carried the term's text and the reader parsed it back, so a
%symbol whose spelling reads as something else arrived as something else.
%A stored (holds $notvar) traced as a variable, a semicolon truncated the
%rest of the term at the comment it starts, and a tab inside a symbol
%split the record into the wrong fields.
%In source $notvar is a variable, so the symbol of that spelling can only
%arrive from a store or from a host, which is where it used to be lost.
test(a_symbol_that_looks_like_a_variable_stays_a_symbol,
     [ setup(setup_trace_test),
       cleanup(( remove_sexp('&self', [plunit_trace_holds, _]),
                 cleanup_trace_test )) ]) :-
    process_metta_string("(= (plunit_trace_new $x) $x)", _),
    'add-atom'('&self', [plunit_trace_holds, '$notvar'], _),
    tracer:metta_trace_source(
        "!(match &self (plunit_trace_holds $v) (plunit_trace_new $v))",
        '&self', Events),
    Events == [event(0, call, [plunit_trace_new, '$notvar'], '', []),
               event(0, exit, [plunit_trace_new, '$notvar'],
                     '$notvar', [])].

%A semicolon cannot be written in source, where it starts a comment, so
%the symbol is stored and reached through a match.
test(a_symbol_holding_a_comment_character_stays_whole,
     [ setup(setup_trace_test),
       cleanup(( remove_sexp('&self', [plunit_trace_holds, _]),
                 cleanup_trace_test )) ]) :-
    process_metta_string("(= (plunit_trace_new $x) $x)", _),
    'add-atom'('&self', [plunit_trace_holds, 'semi;colon'], _),
    tracer:metta_trace_source(
        "!(match &self (plunit_trace_holds $v) (plunit_trace_new $v))",
        '&self', Events),
    Events == [event(0, call, [plunit_trace_new, 'semi;colon'], '', []),
               event(0, exit, [plunit_trace_new, 'semi;colon'],
                     'semi;colon', [])].

test(event_limit_error_removes_every_wrapper,
     [setup(setup_trace_test), cleanup(cleanup_trace_test)]) :-
    process_metta_string("(= (plunit_trace_hyperpose $x) (+ $x 1))", _),
    catch(tracer:metta_trace_source("!(plunit_trace_hyperpose 1)", '&self', 1, _),
          Error,
          true),
    nonvar(Error),
    Error = error(resource_error(metta_trace_events(1)), _),
    \+ tracer:metta_trace_session,
    \+ current_predicate_wrapper(user:plunit_trace_hyperpose(_, _),
                                  metta_tracer, _, _),
    tracer:metta_trace_source("!(plunit_trace_hyperpose 2)", '&self', Events),
    Events == [event(0, call, [plunit_trace_hyperpose, 2], '', []),
               event(0, exit, [plunit_trace_hyperpose, 2], 3, [])].

:- end_tests(tracer).
