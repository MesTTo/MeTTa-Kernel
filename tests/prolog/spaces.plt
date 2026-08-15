% Purpose: verify native and foreign space storage, isolation, registration,
%   matching, and lifecycle behavior.
% Guarantees:
%   - Native storage modules do not inherit user predicates, while execution
%     modules keep undefined calls loud [tested: spaces_storage_modules].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- dynamic plunit_storage_added_event/2.

metta_foreign_space('&plunit_cycle_foreign').
metta_foreign_match('&plunit_cycle_foreign', [fact, X, X]) :-
    X = [g, X].

:- begin_tests(spaces_cycles).

cycle_space('&plunit_cycle_native').

setup_cycle_space :-
    cycle_space(Space),
    add_sexp(Space, [fact, Y, [g, Y]]),
    add_sexp(Space, [fact, ordinary, [g, ordinary]]).

cleanup_cycle_space :-
    cycle_space(Space),
    remove_sexp(Space, [fact, _, _]).

test(native_match_rejects_cycle_created_by_unification,
     [ setup(setup_cycle_space),
       cleanup(cleanup_cycle_space),
       occurs_check(false),
       fail ]) :-
    cycle_space(Space),
    match(Space, [fact, X, X], X, _).

test(foreign_match_rejects_provider_cycle,
     [occurs_check(false), fail]) :-
    match('&plunit_cycle_foreign', [fact, X, X], X, _).

test(ordinary_native_match_is_unchanged,
     [setup(setup_cycle_space), cleanup(cleanup_cycle_space)]) :-
    cycle_space(Space),
    once(match(Space,
               [fact, ordinary, [g, ordinary]],
               ordinary,
               Result)),
    Result == ordinary.

:- end_tests(spaces_cycles).

:- begin_tests(spaces_arbitrary_atoms).

arbitrary_space('&plunit_arbitrary_atoms').

setup_arbitrary_space :-
    cleanup_arbitrary_space,
    arbitrary_space(Space),
    add_sexp(Space, foo),
    add_sexp(Space, 5),
    add_sexp(Space, "text"),
    add_sexp(Space, []),
    add_sexp(Space, [foo]),
    add_sexp(Space, [pair, 1, 2]).

cleanup_arbitrary_space :-
    arbitrary_space(Space),
    clear_native_atoms(Space).

test(get_atoms_preserves_scalars_and_expressions,
     [ setup(setup_arbitrary_space),
       cleanup(cleanup_arbitrary_space),
       true(Sorted == [5, "text", [], foo, [foo], [pair, 1, 2]]) ]) :-
    arbitrary_space(Space),
    findall(Atom, 'get-atoms'(Space, Atom), Atoms),
    msort(Atoms, Sorted).

test(scalar_and_singleton_expression_match_separately,
     [ setup(setup_arbitrary_space),
       cleanup(cleanup_arbitrary_space),
       true((ScalarMatches == [scalar], ExpressionMatches == [expression])) ]) :-
    arbitrary_space(Space),
    findall(scalar, match(Space, foo, scalar, scalar), ScalarMatches),
    findall(expression,
            match(Space, [foo], expression, expression),
            ExpressionMatches).

test(scalar_participates_in_native_conjunctions,
     [ setup(setup_arbitrary_space),
       cleanup(cleanup_arbitrary_space),
       true(Matches == [joined]) ]) :-
    arbitrary_space(Space),
    findall(joined,
            match(Space, [',', foo, [pair, 1, 2]], joined, joined),
            Matches).

test(removing_scalar_keeps_singleton_expression,
     [ setup(setup_arbitrary_space),
       cleanup(cleanup_arbitrary_space),
       true(Atoms == [[foo]]) ]) :-
    arbitrary_space(Space),
    remove_sexp(Space, foo),
    findall(Atom, ('get-atoms'(Space, Atom), (Atom == foo ; Atom == [foo])), Atoms).

test(removing_singleton_expression_keeps_scalar,
     [ setup(setup_arbitrary_space),
       cleanup(cleanup_arbitrary_space),
       true(Atoms == [foo]) ]) :-
    arbitrary_space(Space),
    remove_sexp(Space, [foo]),
    findall(Atom, ('get-atoms'(Space, Atom), (Atom == foo ; Atom == [foo])), Atoms).

% Scalars live outside the space predicate so expression matches keep clause
% indexing, which means a caller that wipes only the space predicate leaves
% them standing and a pooled name's next life inherits them.
test(clearing_a_space_drops_its_scalars_too,
     [ setup(setup_arbitrary_space),
       cleanup(cleanup_arbitrary_space),
       true(Atoms == []) ]) :-
    arbitrary_space(Space),
    clear_native_atoms(Space),
    findall(Atom, 'get-atoms'(Space, Atom), Atoms).

:- end_tests(spaces_arbitrary_atoms).

:- multifile metta_on_function_changed/1.

metta_on_function_changed(plunit_registration_rollback) :-
    throw(error(plunit_injected_change_hook_failure, none)).

:- begin_tests(spaces_registration).

registration_terms(F,
                   [[=, [F, 1], one],
                    [=, [F, 2], two],
                    [=, [F, 3], three],
                    [=, [F, 4], four]]).

cleanup_registered_function(F) :-
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

test(add_atom_records_one_arity_for_many_equations,
     [ setup(cleanup_registered_function(plunit_add_arity)),
       cleanup(cleanup_registered_function(plunit_add_arity)) ]) :-
    registration_terms(plunit_add_arity, Terms),
    forall(member(Term, Terms), 'add-atom'('&self', Term, true)),
    findall(Arity, user:arity(plunit_add_arity, Arity), Arities),
    Arities == [2].

test(file_loader_records_one_arity_for_many_equations,
     [ setup(cleanup_registered_function(plunit_load_arity)),
       cleanup(cleanup_registered_function(plunit_load_arity)) ]) :-
    Source = "(= (plunit_load_arity 1) one)\n\
(= (plunit_load_arity 2) two)\n\
(= (plunit_load_arity 3) three)\n\
(= (plunit_load_arity 4) four)",
    process_metta_string(Source, _),
    findall(Arity, user:arity(plunit_load_arity, Arity), Arities),
    Arities == [2].

test(non_symbol_function_head_is_rejected_before_mutation,
     [ setup((retractall(user:fun(5)), retractall(user:arity(5, _)),
              remove_sexp('&self', [=, [5|_], _]))),
       cleanup((retractall(user:fun(5)), retractall(user:arity(5, _)),
                remove_sexp('&self', [=, [5|_], _]))) ]) :-
    Term = [=, [5, X], 4],
    catch('add-atom'('&self', Term, true), Error, true),
    nonvar(Error),
    Error = error(type_error(atom, 5), _),
    \+ user:fun(5),
    \+ user:arity(5, _),
    \+ get_native_atom('&self', [=, [5, X], 4]).

test(change_hook_error_rolls_back_every_registration_write,
     [ setup(cleanup_registered_function(plunit_registration_rollback)),
       cleanup(cleanup_registered_function(plunit_registration_rollback)) ]) :-
    Term = [=, [plunit_registration_rollback, X], X],
    catch('add-atom'('&self', Term, true), Error, true),
    nonvar(Error),
    Error = error(plunit_injected_change_hook_failure, none),
    \+ user:fun(plunit_registration_rollback),
    \+ user:arity(plunit_registration_rollback, _),
    \+ user:fun_meta_clause(plunit_registration_rollback, _, _),
    \+ user:translated_from(_, Term),
    \+ get_native_atom('&self',
                        [=, [plunit_registration_rollback, X], X]),
    functor(Head, plunit_registration_rollback, 2),
    \+ clause(user:Head, _, _).

test(failed_first_registration_keeps_storage_reusable,
     [ cleanup(clear_native_atoms('&plunit_registration_first_failure')) ]) :-
    Space = '&plunit_registration_first_failure',
    clear_native_atoms(Space),
    Term = [=, [plunit_registration_rollback, X], X],
    catch('add-atom'(Space, Term, true), Error, true),
    Error = error(plunit_injected_change_hook_failure, none),
    native_storage_module_ready(Space, _),
    \+ get_native_atom(Space, Term),
    add_sexp(Space, [after_failure]),
    once(get_native_atom(Space, [after_failure])).

test(rolled_back_first_write_keeps_storage_reusable,
     [ cleanup(clear_native_atoms('&plunit_transaction_first_write')) ]) :-
    Space = '&plunit_transaction_first_write',
    clear_native_atoms(Space),
    \+ transaction((add_sexp(Space, [rolled_back]), fail)),
    native_storage_module(Space, Module),
    native_storage_ready(Module),
    \+ native_storage_module_cache(Space, _),
    add_sexp(Space, [after_rollback]),
    once(get_native_atom(Space, [after_rollback])).

test(naming_the_storage_module_does_not_claim_it,
     [ cleanup(( retractall(native_storage_module_cache('&plunit_named', _)),
                 clear_native_atoms('&plunit_named') )) ]) :-
    % SWI creates a module as a side effect of merely naming it, including
    % from read-only introspection, so an ownership test cannot be
    % current_module/1: this once made the space throw on every later write
    % for the life of the process, with no way back.
    native_storage_module('&plunit_named', Module),
    ( catch(predicate_property(Module:anything, dynamic), _, true) -> true ; true ),
    add_sexp('&plunit_named', [fact, one]),
    findall(P, get_native_atom('&plunit_named', P), Atoms),
    Atoms == [[fact, one]].

test(an_occupied_storage_module_is_still_refused,
     [ setup(assertz('$petta_atoms:&plunit_taken':squatter(1))),
       cleanup(retractall('$petta_atoms:&plunit_taken':squatter(_))),
       throws(error(permission_error(create, native_space_storage, _), _)) ]) :-
    ensure_native_storage_module('&plunit_taken', _).

:- end_tests(spaces_registration).

:- begin_tests(spaces_storage_modules,
               [ setup(setup_storage_module_space),
                 cleanup(cleanup_storage_module_space) ]).

storage_module_space('&plunit_storage_module').
storage_module_function(plunit_storage_identity).

setup_storage_module_space :-
    cleanup_storage_module_space,
    storage_module_space(Space),
    assertz(user:plunit_storage_leak),
    assertz(user:'&plunit_storage_module'(from_user)),
    add_sexp(Space, [from_space]),
    storage_module_function(Function),
    'add-atom'(Space, [=, [Function, X], X], true).

cleanup_storage_module_space :-
    storage_module_space(Space),
    storage_module_function(Function),
    'remove-atom'(Space, [=, [Function, X], X], _),
    clear_native_atoms(Space),
    retractall(user:plunit_storage_leak),
    retractall(user:'&plunit_storage_module'(from_user)).

test(atoms_live_only_in_the_private_module) :-
    storage_module_space(Space),
    native_storage_module(Space, Module),
    native_storage_ready(Module),
    current_prolog_flag(Module:unknown, fail),
    \+ default_module(Module, user),
    functor(StoredHead, Space, 1),
    arg(1, StoredHead, from_space),
    clause(Module:StoredHead, true),
    \+ clause(user:StoredHead, true),
    \+ Module:plunit_storage_leak.

test(user_predicates_do_not_appear_as_space_atoms) :-
    storage_module_space(Space),
    findall(Atom, 'get-atoms'(Space, Atom), Atoms),
    memberchk([from_space], Atoms),
    \+ member([from_user], Atoms).

test(missing_storage_arities_fail_without_changing_execution_errors) :-
    storage_module_space(Space),
    \+ native_expression(Space, plunit_missing_storage_predicate, []),
    space_module(Space, ExecutionModule),
    catch(ExecutionModule:plunit_missing_execution_predicate,
          Error,
          true),
    nonvar(Error),
    Error = error(existence_error(procedure, _), _).

test(concurrent_first_writes_publish_one_storage_module,
     [ cleanup(clear_native_atoms('&plunit_concurrent_storage')) ]) :-
    Space = '&plunit_concurrent_storage',
    concurrent_forall(between(1, 64, Row),
                      add_sexp(Space, [row, Row]),
                      [threads(64)]),
    findall(Row, get_native_atom(Space, [row, Row]), Rows),
    sort(Rows, UniqueRows),
    length(UniqueRows, 64),
    native_storage_module(Space, Module),
    native_storage_ready(Module),
    findall(CachedModule,
            native_storage_module_cache(Space, CachedModule),
            CachedModules),
    CachedModules == [Module].

test(custom_added_hooks_keep_every_batch_event,
     [ cleanup((clear_native_atoms('&plunit_hooked_batch'),
                retractall(user:plunit_storage_added_event(_, _)))) ]) :-
    Space = '&plunit_hooked_batch',
    setup_call_cleanup(
        assertz(user:(metta_on_atom_added(EventSpace, Term) :-
                         assertz(plunit_storage_added_event(
                             EventSpace, Term))), HookRef),
        metta_add_atoms(Space, [[observed, 1], [observed, 2]]),
        erase(HookRef)),
    findall(Term,
            user:plunit_storage_added_event(Space, Term),
            Events),
    Events == [[observed, 1], [observed, 2]].

:- end_tests(spaces_storage_modules).

:- begin_tests(spaces_type_extensions,
               [ setup(setup_type_extension_space),
                 cleanup(cleanup_type_extension_space) ]).

type_extension_space('&plunit_type_extensions').
type_extension_term(plunit_scoped_one,
                    [=, ['get-type', plunit_scoped_one], plunit_one]).
type_extension_term(plunit_scoped_two,
                    [=, ['get-type', plunit_scoped_two], plunit_two]).

setup_type_extension_space :-
    cleanup_type_extension_space,
    type_extension_space(Space),
    forall(type_extension_term(_, Term),
           'add-atom'(Space, Term, true)).

cleanup_type_extension_space :-
    type_extension_space(Space),
    forall(type_extension_term(_, Term),
           'remove-atom'(Space, Term, _)),
    space_module(Space, Module),
    retractall(Module:get_type_rule(_, _)),
    unregister_fun_in(Module, 'get-type'),
    clear_native_atoms(Space).

test(removing_one_rule_keeps_the_other_visible) :-
    type_extension_space(Space),
    type_extension_term(plunit_scoped_one, First),
    'remove-atom'(Space, First, true),
    space_module(Space, Module),
    fun_in(Module, 'get-type'),
    with_metta_module(Module,
                      'get-type'(plunit_scoped_two, Type)),
    Type == plunit_two.

:- end_tests(spaces_type_extensions).
