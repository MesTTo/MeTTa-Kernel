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

% Test providers are declared where the unit that uses them is, so each one
% reads beside its own tests.
:- discontiguous metta_foreign_space/1.
:- discontiguous metta_foreign_capability/2.

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

% Same expression, same situation, and the answer used to depend on how the
% space was implemented: a native space answered true for an atom that was
% never there, a foreign one answered false, and a MeTTa program branching on
% the result was correct against one and wrong against the other.
%
% The engine also disagreed with ITSELF. Removing an EQUATION already reported
% truthfully, so two of the three paths were honest and the plain-atom one was
% not, with the information one builtin away.
%The four operations the specification types with `(->)`, the unit type, and
%what each answers. `trace!` already answered unit and the other four answered
%`true`, so the engine disagreed with itself and with the arbiter's whole
%spaces corpus.
test(an_effectful_operation_answers_unit,
     [ setup(cleanup_arbitrary_space), cleanup(cleanup_arbitrary_space) ]) :-
    arbitrary_space(Space),
    'add-atom'(Space, [unit, probe], Added),
    assertion(Added == []),
    'remove-atom'(Space, [unit, probe], Gone),
    assertion(Gone == []),
    with_output_to(string(_), 'println!'(quiet, Printed)),
    assertion(Printed == []),
    'bind!'('&plunit-unit-cell', ['new-state', 1], Bound),
    assertion(Bound == []),
    %Unit is an Expression of size 0 and it is NOT the boolean, which is the
    %distinction that makes it a value rather than a failure.
    'get-metatype'([], Meta),
    assertion(Meta == 'Expression'),
    assertion([] \== true).

test(spaces_removal_answers_unit_and_reports_internally,
     [ setup(cleanup_arbitrary_space), cleanup(cleanup_arbitrary_space) ]) :-
    arbitrary_space(Space),
    add_sexp(Space, [pair, 1, 2]),
    add_sexp(Space, lonely),
    % The LANGUAGE-facing answer is unit whether or not anything went, and the
    % language says so: "if the given atom is not in the space, remove-atom
    % currently neither raises a error nor returns the empty result"
    % [source: the language's Working with spaces]. This test used to assert
    % true and false here, which was PeTTa reporting something real through a
    % slot the specification reserves for unit.
    'remove-atom'(Space, [pair, 1, 2], Present),
    assertion(Present == []),
    'remove-atom'(Space, [pair, 1, 2], Repeated),
    assertion(Repeated == []),
    'remove-atom'(Space, [never, there], Absent),
    assertion(Absent == []),
    % The information is not lost, it moved to where the ENGINE uses it:
    % metta_remove_atom/3 still answers whether anything was there, which is
    % what the loader's rollback and the storage modules read.
    metta_remove_atom(Space, lonely, Removed),
    assertion(Removed == true),
    metta_remove_atom(Space, nonesuch, Missing),
    assertion(Missing == false),
    % Removal still takes EVERY occurrence: a space is a multiset.
    add_sexp(Space, [twice, x]),
    add_sexp(Space, [twice, x]),
    'remove-atom'(Space, [twice, x], Both),
    assertion(Both == []),
    findall(A, get_native_atom(Space, A), Left),
    assertion(Left == []).

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
    forall(member(Term, Terms), 'add-atom'('&self', Term, _)),
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
    catch('add-atom'('&self', Term, _), Error, true),
    nonvar(Error),
    Error = error(type_error(atom, 5), _),
    \+ user:fun(5),
    \+ user:arity(5, _),
    \+ get_native_atom('&self', [=, [5, X], 4]).

test(change_hook_error_rolls_back_every_registration_write,
     [ setup(cleanup_registered_function(plunit_registration_rollback)),
       cleanup(cleanup_registered_function(plunit_registration_rollback)) ]) :-
    Term = [=, [plunit_registration_rollback, X], X],
    catch('add-atom'('&self', Term, _), Error, true),
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
    catch('add-atom'(Space, Term, _), Error, true),
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

test(space_names_enumerate_the_registered_spaces,
     [ setup(add_sexp('&plunit_names', [present])),
       cleanup(( retractall(native_storage_module_cache('&plunit_names', _)),
                 clear_native_atoms('&plunit_names') )) ]) :-
    metta_space_names(Names),
    % The boot spaces, a written native space, and a foreign provider all
    % appear; a name nothing ever wrote does not, because registration is
    % a side effect of writing or binding, never of naming.
    subtract(['&self', '&petta', '&plunit_names', '&plunit_enum_only'],
             Names, []),
    \+ memberchk('&plunit_never_written', Names),
    sort(Names, Names).

:- end_tests(spaces_registration).

% Two providers in the shape a library actually ships: one that enumerates and
% nothing else, which python/petta/foreign.py explicitly says is enough, and
% one that declares an operation it does not implement.
metta_foreign_space('&plunit_enum_only').
metta_foreign_capability('&plunit_enum_only', enumerate).
metta_foreign_atoms('&plunit_enum_only', Atom) :-
    member(Atom, [[edge, a, b], [edge, b, c], [node, a]]).

metta_foreign_space('&plunit_broken_write').
metta_foreign_capability('&plunit_broken_write', add).
metta_foreign_add('&plunit_broken_write', _) :- fail.

% A builtin is a static predicate compiled into the engine, so an equation for
% its name in &self would have to assert into it. SWI refuses with a
% permission error naming assertz/2, the Prolog arity and the absolute path of
% the engine source file, none of which is language the program that wrote the
% equation can act on.
% A declaration decides how a call site compiles, most sharply for an Atom
% parameter: (: f (-> Atom %Undefined%)) is the difference between the
% argument arriving evaluated and arriving as written, and that is what makes
% a control form possible at all. A call site compiled BEFORE the declaration
% landed kept evaluating the argument for ever, so the two spellings of one
% call behaved differently in the same program with nothing said.
:- begin_tests(spaces_late_type_declaration).

test(a_late_type_declaration_repairs_its_call_sites,
     [ cleanup(( remove_sexp('&self', [':', 'plunit-shape-of', _]),
                 'remove-atom'('&self', [=, ['plunit-shape-of', A], [shape, A]], _),
                 'remove-atom'('&self', [=, ['plunit-shape-caller'], _], _),
                 forget_late_name('plunit-shape-of'),
                 forget_late_name('plunit-shape-caller') )) ]) :-
    retractall(user:silent(_)),
    assertz(user:silent(true)),
    process_metta_string("(= (plunit-shape-of $x) (shape $x))", _),
    % Compiled while nothing declares the parameter Atom, so the argument is
    % evaluated: this is the call site the declaration has to repair.
    process_metta_string("(= (plunit-shape-caller) (plunit-shape-of (+ 1 2)))", _),
    reduce(['plunit-shape-caller'], Before, _),
    assertion(Before == [shape, 3]),
    'add-atom'('&self', [':', 'plunit-shape-of', [->, 'Atom', 'Atom']], _),
    reduce(['plunit-shape-caller'], After, _),
    assertion(After == [shape, ['+', 1, 2]]).

forget_late_name(Name) :-
    retractall(user:fun(Name)),
    retractall(user:arity(Name, _)),
    user:unregister_fun_everywhere(Name),
    user:clear_fun_meta(Name).

:- end_tests(spaces_late_type_declaration).

:- begin_tests(spaces_builtin_override).

test(a_builtin_equation_in_self_is_refused_in_metta_terms,
     [throws(error(petta_builtin_redefinition('+', 2, '&self'), _))]) :-
    'add-atom'('&self', [=, ['+', 1, 2], nine], _).

test(the_refusal_says_where_the_definition_can_go) :-
    catch('add-atom'('&self', [=, ['car-atom', _], nine], _), Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "cannot be redefined in &self")),
    assertion(sub_string(Text, _, _, _, "named space")).

% The other half of the same message: a named space compiles its clauses into
% a module of its own, so the same equation there shadows the builtin for that
% space and leaves every other space's alone.
test(a_named_space_may_shadow_a_builtin,
     [ cleanup(( 'remove-atom'('&plunit_shadow_builtin', [=, ['+', 1, 2], nine], _),
                 clear_native_atoms('&plunit_shadow_builtin') )) ]) :-
    'add-atom'('&plunit_shadow_builtin', [=, ['+', 1, 2], nine], _),
    space_module('&plunit_shadow_builtin', Module),
    with_metta_module(Module, reduce(['+', 1, 2], Shadowed, _)),
    assertion(Shadowed == nine),
    with_metta_module(user, reduce(['+', 1, 2], Ordinary, _)),
    assertion(Ordinary == 3).

:- end_tests(spaces_builtin_override).

:- begin_tests(spaces_foreign_contract).

% The finding: a bound pattern went straight to the match hook, so a
% provider with only enumeration answered NOTHING to every real query while
% the space demonstrably held matching atoms. Porting a working Python
% provider to Prolog for speed, which is what the extension guide recommends,
% turned every match into an empty answer set.
test(an_enumeration_only_provider_answers_a_bound_pattern) :-
    findall(V, match('&plunit_enum_only', [edge, a, V], V, _), Values),
    assertion(Values == [b]).

test(an_enumeration_only_provider_still_answers_an_unbound_pattern) :-
    findall(A, match('&plunit_enum_only', A, A, _), Atoms),
    assertion(length(Atoms, 3)).

test(an_enumeration_only_provider_answers_nothing_for_no_match) :-
    findall(V, match('&plunit_enum_only', [edge, zzz, V], V, _), Values),
    assertion(Values == []).

% Four of the five operations used to fail silently: a write vanished, a
% removal reported nothing removed, and a match answered the empty set.
test(an_undeclared_write_is_refused,
     [throws(error(permission_error(add, foreign_space, '&plunit_enum_only'), _))]) :-
    'add-atom'('&plunit_enum_only', [edge, x, y], _).

test(an_undeclared_removal_is_refused,
     [throws(error(permission_error(remove, foreign_space, '&plunit_enum_only'), _))]) :-
    'remove-atom'('&plunit_enum_only', [edge, a, b], _).

test(an_undeclared_clear_is_refused,
     [throws(error(permission_error(clear, foreign_space, '&plunit_enum_only'), _))]) :-
    clear_foreign_atoms('&plunit_enum_only').

% A write either happened or it did not, so a provider that simply fails has
% lost the caller's data with nothing said.
test(a_write_that_fails_is_an_error,
     [throws(error(petta_foreign_operation_failed('&plunit_broken_write', add), _))]) :-
    'add-atom'('&plunit_broken_write', [edge, x, y], _).

% A space that declares nothing keeps every capability, which is what every
% provider written before the declaration existed assumed.
test(an_undeclared_space_provides_everything) :-
    forall(member(C, [add, remove, match, enumerate, clear]),
           assertion(foreign_provides('&plunit_undeclared', C))).

:- end_tests(spaces_foreign_contract).

:- begin_tests(spaces_native_shape).

test(a_rational_tree_candidate_is_never_a_match_answer,
     [ setup(add_sexp('&plunit_rational', [rt, [f, X], X])),
       cleanup(( retractall(native_storage_module_cache('&plunit_rational', _)),
                 clear_native_atoms('&plunit_rational') )) ]) :-
    % The arbiter's matcher occurs-checks its variable cases, so
    % (rt $y $y) against a stored (rt (f $x) $x) has no answer, whatever
    % the out template mentions. Before the guard in native_expression,
    % the ground template answered while the pattern-as-template failed:
    % one match, two answers.
    \+ match('&plunit_rational', [rt, Y, Y], hit, _),
    \+ match('&plunit_rational', [rt, Y2, Y2], [rt, Y2, Y2], _),
    % The acyclic twin still answers through the same clause.
    add_sexp('&plunit_rational', [rt, ok, ok]),
    findall(R, match('&plunit_rational', [rt, Z, Z], hit, R), [hit]).

% add_sexp_in/4 writes the two clause bodies out rather than calling
% native_atom_clause/3, because calling it cost one goal per write, +2 on a
% seven-inference path [measured 2026-08-16: add-batch 62027 to 64028 over a
% thousand atoms]. That copy is only safe while the two agree, and they did
% not agree before: lib_import.pl's converter wrote its own third shape into
% the wrong module entirely.
native_shape_case([fact, a, 1]).
native_shape_case([one]).
native_shape_case([nested, [a, b], "text"]).
native_shape_case([with, _Variable]).
native_shape_case(bare_symbol).
native_shape_case(42).
native_shape_case([]).

test(native_storage_shapes_agree,
     [ cleanup(( clear_native_atoms('&plunit_shape'),
                 abolish('$petta_atoms:&plunit_shape':'&plunit_shape'/3) )) ]) :-
    forall(native_shape_case(Atom),
           ( add_sexp('&plunit_shape', Atom, Ref),
             clause_property(Ref, module(Module)),
             clause(Module:Asserted, true, Ref),
             native_atom_clause('&plunit_shape', Atom, Predicted),
             assertion(Asserted =@= Predicted) )).

:- end_tests(spaces_native_shape).

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
    'add-atom'(Space, [=, [Function, X], X], _).

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
    native_storage_module_ready(Space, StorageModule),
    \+ native_expression(StorageModule, Space, plunit_missing_storage_predicate, []),
    space_module(Space, ExecutionModule),
    catch(ExecutionModule:plunit_missing_execution_predicate,
          Error,
          true),
    nonvar(Error),
    Error = error(existence_error(procedure, _), _).

test(reading_atoms_requires_a_named_space,
     [ throws(error(instantiation_error, _)) ]) :-
    % The read sibling of the match guard: an unbound space enumerated every
    % space ever written to, so one space could read another's atoms.
    get_native_atom(_AnySpace, _Pattern).


test(matching_requires_a_named_space,
     [ throws(error(instantiation_error, _)) ]) :-
    % An unbound space would enumerate every space that has ever been
    % written to, so a program in one space could read another it never
    % names.
    match(_AnySpace, [plunit_secret, _X], conj, conj).


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
           'add-atom'(Space, Term, _)).

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
    'remove-atom'(Space, First, _),
    space_module(Space, Module),
    %fun_in/2 is a relation; the at-most-once intent is explicit, as at
    %every engine call site (filereader.plt:244 records the reasoning).
    once(fun_in(Module, 'get-type')),
    with_metta_module(Module,
                      'get-type'(plunit_scoped_two, Type)),
    Type == plunit_two.

:- end_tests(spaces_type_extensions).


% A foreign space holds RULES, not only facts. In MeTTa a space is BOTH a data
% source and where the program lives: evaluation is match against (= lhs rhs)
% atoms, facts and rules are the same kind of thing, and add-atom of an
% equation is how a program grows. The seam honoured only the first half, so
% an equation added to a foreign space was stored and INERT: (only-foreign 21)
% answered itself where the identical shape in a native named space answered
% 42 [reproduced 2026-08-16].
:- begin_tests(spaces_foreign_plan,
               [ setup(( user:consult('foreign_plan_provider'),
                         retractall(user:plunit_plan_atom(_, _)),
                         retractall(user:plunit_plan_claimed(_)) )),
                 cleanup(( retractall(user:plunit_plan_atom(_, _)),
                           retractall(user:plunit_plan_claimed(_)) )) ]).

% A conjunction is offered to the provider WHOLE before the engine splits it.
% Without this a provider never sees more than one pattern at a time, so its own
% join is unreachable and every conjunction is a nested-loop plan however fast
% the backend is.
%
% The oracle is the engine's own split over a native space holding the same
% atoms: whatever a claim answers, the split must answer too. A claim is the one
% place in the seam where a provider may NOT over-approximate, because there is
% no cheap re-check for a join, so the differential is what stands in for one.

plan_atoms([[edge, a, b], [edge, b, c], [edge, a, c], [edge, c, a],
            [tag, b, one], [tag, c, two]]).

plan_case(two_pattern,  [',', [edge, X, Y], [tag, Y, T]],        [X, Y, T]).
plan_case(shared_var,   [',', [edge, X, Y], [edge, Y, Z]],       [X, Y, Z]).
plan_case(triangle,     [',', [edge, X, Y], [edge, Y, Z], [edge, Z, X]], [X, Y, Z]).
plan_case(ground_first, [',', [edge, a, b], [tag, T, one]],      T).
plan_case(cartesian,    [',', [edge, X, _], [tag, Y, _]],        [X, Y]).
plan_case(unsatisfiable, [',', [edge, X, Y], [tag, Y, nothing]], [X, Y]).

%Both spaces cleared first: a plunit setup runs once per forall case, and a
%space that accumulated a copy per case would answer a multiset of every row.
fill_plan_spaces :-
    forall('get-atoms'('&plunit_native_plan', Old),
           'remove-atom'('&plunit_native_plan', Old, _)),
    plan_atoms(Atoms),
    forall(member(A, Atoms),
           ( 'add-atom'('&plunit_plan', A, _),
             'add-atom'('&plunit_noplan', A, _),
             'add-atom'('&plunit_native_plan', A, _) )).

rows(Space, Pattern, Out, Rows) :-
    copy_term(Pattern-Out, P-O),
    findall(O, match(Space, P, O, O), Unsorted),
    msort(Unsorted, Rows).

test(a_claimed_join_answers_what_the_split_answers,
     [ setup(fill_plan_spaces), forall(plan_case(_, Pattern, Out)) ]) :-
    rows('&plunit_plan', Pattern, Out, Claimed),
    rows('&plunit_native_plan', Pattern, Out, Split),
    assertion(Claimed =@= Split).

% and the differential is not passing because both sides took the split
test(the_claim_actually_fired, [setup(fill_plan_spaces)]) :-
    retractall(user:plunit_plan_claimed(_)),
    rows('&plunit_plan', [',', [edge, _, Y], [tag, Y, _]], Y, _),
    assertion(user:plunit_plan_claimed(yes)),
    retractall(user:plunit_plan_claimed(_)),
    rows('&plunit_noplan', [',', [edge, _, Z], [tag, Z, _]], Z, _),
    assertion(\+ user:plunit_plan_claimed(_)).

% A space that declares nothing about planning gets today's behaviour exactly,
% which is the seam's safe default: declining is what a provider does by
% writing no clause at all.
test(a_space_without_the_capability_is_split, [setup(fill_plan_spaces)]) :-
    rows('&plunit_noplan', [',', [edge, X, Y], [tag, Y, T]], [X, Y, T], Declined),
    rows('&plunit_native_plan', [',', [edge, X2, Y2], [tag, Y2, T2]], [X2, Y2, T2], Split),
    assertion(Declined =@= Split).

% A PARTIAL claim: the provider takes what it owns and leaves the rest, and the
% engine plans the remainder as it always did. This is what stops the seam
% being all-or-nothing, and it is the case a single-space reading would miss.
test(a_partial_claim_leaves_the_rest_to_the_engine, [setup(fill_plan_spaces)]) :-
    'add-atom'('&plunit_plan', [partial, b], _),
    'add-atom'('&plunit_native_plan', [partial, b], _),
    rows('&plunit_plan',
         [',', [edge, X, Y], [partial, Y]], [X, Y], Claimed),
    rows('&plunit_native_plan',
         [',', [edge, X2, Y2], [partial, Y2]], [X2, Y2], Split),
    assertion(Claimed =@= Split),
    assertion(Claimed == [[a, b]]).

% Claimed and Rest must PARTITION the conjunction. Dropping a conjunct answers
% rows the query never asked for, and nothing downstream would catch it: the
% engine plans Rest and never looks at the original patterns again.
test(a_claim_that_drops_a_conjunct_is_refused,
     [ setup(fill_plan_spaces),
       throws(error(petta_foreign_plan_is_not_a_partition('&plunit_plan', _, _, _), _)) ]) :-
    'add-atom'('&plunit_plan', [lossy, a], _),
    rows('&plunit_plan', [',', [lossy, X], [tag, X, nothing]], X, _).

% A single-conjunct conjunction is the ordinary match path and is not offered
% here, because offering it would only duplicate metta_foreign_match/3.
test(a_one_conjunct_conjunction_is_not_offered, [setup(fill_plan_spaces)]) :-
    retractall(user:plunit_plan_claimed(_)),
    rows('&plunit_plan', [',', [tag, X, one]], X, Rows),
    assertion(Rows == [b]),
    assertion(\+ user:plunit_plan_claimed(_)).

:- end_tests(spaces_foreign_plan).

:- begin_tests(spaces_batch_is_only_a_transport).

% A batch is a transport optimisation and never a semantic one: adding a list
% has to leave exactly the state adding its atoms one at a time leaves. The
% batch path decides which atoms may take a bulk crossing using its OWN copy of
% metta_add_atom/3's clause-head tests, because sharing one classifier cost
% three inferences of every twelve on the hottest write path in the engine
% [measured 2026-08-16]. This unit is what holds the two copies together: each
% shape goes in both ways and the results are compared, so a divergence is a
% test failure rather than a silent one.
%
% It is not hypothetical. A batched type declaration skipped the recompile the
% same atom performs alone, so m.add(decl) answered (+ 1 2) and
% m.add(decl, other) answered 3 [measured 2026-08-16].
%
% Each side uses its own function names and the same space, so the only
% difference between them is the route the atom took.

% The filler is what makes it a batch: a one-atom list would take the same
% decision either way and prove nothing.
added_in_a_batch(Space, Atom) :- metta_add_atoms(Space, [Atom, [batch, filler]]).

batch_side(alone, Space, Atom) :- 'add-atom'(Space, Atom, _).
batch_side(batch, Space, Atom) :- added_in_a_batch(Space, Atom).

% A late type declaration recompiles the call sites of an already-compiled
% function: the argument arrives as written instead of evaluated. This is the
% shape the batch path got wrong.
declaration_answer(Side, Answer) :-
    atom_concat('bt-', Side, Prefix),
    atom_concat(Prefix, '-q', Q),
    atom_concat(Prefix, '-c', C),
    'add-atom'('&self', [=, [Q, X], X], _),
    'add-atom'('&self', [=, [C], [Q, [+, 1, 2]]], _),
    batch_side(Side, '&self', [':', Q, [->, 'Atom', '%Undefined%']]),
    space_module('&self', Module),
    findall(A, with_metta_module(Module, reduce([C], A, _)), Answer).

test(a_batched_declaration_recompiles_like_a_lone_one) :-
    declaration_answer(alone, Alone),
    declaration_answer(batch, Batch),
    assertion(Alone == Batch),
    % and not vacuously: the declaration has to have taken effect on both
    assertion(Alone == [[+, 1, 2]]).

equation_answer(Side, Answer, Clauses) :-
    atom_concat('bt-eq-', Side, F),
    batch_side(Side, '&self', [=, [F, X], [*, 2, X]]),
    space_module('&self', Module),
    findall(A, with_metta_module(Module, reduce([F, 21], A, _)), Answer),
    functor(Head, F, 2),
    predicate_property(Module:Head, number_of_clauses(Clauses)).

test(a_batched_equation_compiles_like_a_lone_one) :-
    equation_answer(alone, Alone, AloneClauses),
    equation_answer(batch, Batch, BatchClauses),
    assertion(Alone == Batch),
    assertion(AloneClauses == BatchClauses),
    assertion(Alone == [42]).

test(a_batched_plain_atom_lands_like_a_lone_one) :-
    batch_side(alone, '&self', ['bt-plain', alone, 1]),
    batch_side(batch, '&self', ['bt-plain', batch, 1]),
    findall(S, 'get-atoms'('&self', ['bt-plain', S, 1]), Sides),
    msort(Sides, Sorted),
    assertion(Sorted == [alone, batch]).

% A declaration for a name that is NOT a function is an ordinary atom, and both
% routes have to agree about that too: the batch path's test asks fun/1 exactly
% as the write path's does.
test(a_declaration_for_a_plain_name_is_plain_either_way) :-
    batch_side(alone, '&self', [':', 'bt-not-a-fun-alone', 'Number']),
    batch_side(batch, '&self', [':', 'bt-not-a-fun-batch', 'Number']),
    findall(N, 'get-atoms'('&self', [':', N, 'Number']), Names),
    assertion(memberchk('bt-not-a-fun-alone', Names)),
    assertion(memberchk('bt-not-a-fun-batch', Names)).

% An equation whose head is a variable cannot name a function, and raises. The
% batch path must not quietly store it as a plain atom, which is what asking a
% classifier for `stored` would have let happen.
test(a_variable_headed_equation_raises_either_way) :-
    catch(batch_side(alone, '&self', [=, _, _]), AloneBall, true),
    catch(batch_side(batch, '&self', [=, _, _]), BatchBall, true),
    assertion(nonvar(AloneBall)),
    assertion(AloneBall =@= BatchBall).

:- end_tests(spaces_batch_is_only_a_transport).

:- begin_tests(spaces_foreign_rules,
               [ setup(( user:consult('foreign_rules_provider'),
                         retractall(user:plunit_rule_atom(_, _)) )),
                 cleanup(retractall(user:plunit_rule_atom(_, _))) ]).

% A space that holds rules is held to ONE standard: the same equations must
% behave exactly as they do in a native space. So every case below runs twice,
% once in a native named space and once in the foreign one, and the answer sets
% are compared. Native is the reference implementation rather than a second
% opinion, and that is what makes this stronger than a table of expectations: a
% hand-written expectation can be wrong, the compiler's own answer cannot.
%
% Each case is one of MeTTa's documented evaluation rules [source:
% metta-lang.dev/docs/learn, Basic evaluation and Recursion and control]. The
% first attempt at foreign rules matched the space for (= (f Args) Body) at call
% time and reduced whatever came back, which is the naive reading of evaluation
% that the language's own tutorial warns is not enough: "the interpreter is
% performing some additional processing on top of such equality queries". It
% failed nest, quote and lazy outright.
%
% Programs are written as MeTTa text and read with the engine's own parser,
% because a case is easier to check by eye than the list it reads into.

% a body is evaluated FURTHER, so a nested call must not reach + as a list
rule_case(nest, ["(= (fr-nest) (+ 1 (* 2 3)))"], "(fr-nest)").
% a bare-variable body must NOT be evaluated: under an Atom parameter the
% argument arrives as written and stays that way
rule_case(quote, ["(: fr-q (-> Atom %Undefined%))",
                  "(= (fr-q $x) $x)",
                  "(= (fr-quote) (fr-q (+ 1 2)))"], "(fr-quote)").
% if evaluates only the branch it takes, so the loop is never entered
rule_case(lazy, ["(= (fr-loop) (fr-loop))",
                 "(= (fr-lazy) (if True Success (fr-loop)))"], "(fr-lazy)").
rule_case(recursion, ["(= (fr-fact $x) (if (> $x 0) (* $x (fr-fact (- $x 1))) 1))"],
          "(fr-fact 5)").
rule_case(nondeterminism, ["(= (fr-bin) 0)", "(= (fr-bin) 1)"], "(fr-bin)").
% equations are not mutually exclusive: both answers come back
rule_case(overlapping, ["(= (fr-f special) caught)", "(= (fr-f $x) $x)"],
          "(fr-f special)").
% functions need not be total
rule_case(partial, ["(= (fr-only a) accepted)"], "(fr-only b)").
rule_case(pattern_head, ["(= (fr-swap (Pair $x $y)) (Pair $y $x))"],
          "(fr-swap (Pair A B))").
rule_case(higher_order, ["(= (fr-sq $x) (* $x $x))",
                         "(= (fr-twice $f $x) ($f ($f $x)))"], "(fr-twice fr-sq 2)").
% (empty) prunes the branch rather than answering something
rule_case(empty, ["(= (fr-pos $x) (if (> $x 0) yes (empty)))"], "(fr-pos -1)").
% The tutorial's own list spelling, and it is here because it once did not
% work: `::` was briefly PeTTa's in-place type annotation, so (:: $x $xs) bound
% $xs to the value's TYPE and the recursion did not terminate. The annotation
% is plain `:`, told apart by position, and `::` is an ordinary constructor
% like any other [source: metta-lang.dev/docs/learn, Recursion and control].
rule_case(recursive_data, ["(= (fr-len ()) 0)",
                           "(= (fr-len (:: $x $xs)) (+ 1 (fr-len $xs)))"],
          "(fr-len (:: A (:: B ())))").

read_case_atom(Text, Atom) :- sread(Text, Atom).

% Add the program, evaluate the call in the space's own module, take the answer
% SET, then take the program back out so the case leaves nothing behind.
answers_in(Space, Texts, CallText, Answers) :-
    maplist(read_case_atom, Texts, Atoms),
    forall(member(A, Atoms), 'add-atom'(Space, A, _)),
    read_case_atom(CallText, Call),
    space_module(Space, Module),
    findall(R, with_metta_module(Module, reduce(Call, R, _)), Unsorted),
    msort(Unsorted, Answers),
    forall(member(A, Atoms), 'remove-atom'(Space, A, _)).

test(a_foreign_space_evaluates_exactly_as_a_native_one,
     [forall(rule_case(_, Texts, CallText))]) :-
    answers_in('&plunit_native_rules', Texts, CallText, Native),
    answers_in('&plunit_rules', Texts, CallText, Foreign),
    assertion(Native =@= Foreign).

% The differential above cannot catch a break that is identical on both sides,
% so a few answers are pinned outright. These are the tutorial's own.
test(the_reference_answers_are_the_documented_ones) :-
    answers_in('&plunit_rules', ["(= (fr-pin) (+ 1 (* 2 3)))"], "(fr-pin)", Nest),
    assertion(Nest == [7]),
    answers_in('&plunit_rules',
               ["(= (fr-pinfact $x) (if (> $x 0) (* $x (fr-pinfact (- $x 1))) 1))"],
               "(fr-pinfact 5)", Fact),
    assertion(Fact == [120]),
    answers_in('&plunit_rules', ["(= (fr-pinbin) 0)", "(= (fr-pinbin) 1)"],
               "(fr-pinbin)", Bin),
    assertion(Bin == [0, 1]).

% An equation in a foreign space compiles the way a native one does, into the
% SPACE's module: one clause per equation, not one bridge per function. The
% space owns the atom and the engine owns the compiled code, which is the whole
% arrangement in one assertion.
test(a_foreign_equation_compiles_into_its_space_module) :-
    forall(between(1, 4, N),
           'add-atom'('&plunit_rules', [=, ['fr-many', N], N], _)),
    predicate_property('&plunit_rules':'fr-many'(_, _), number_of_clauses(Clauses)),
    assertion(Clauses == 4),
    findall(A, with_metta_module('&plunit_rules', reduce(['fr-many', 3], A, _)), As),
    assertion(As == [3]).

% And it un-compiles when the atom is removed. The removal path dispatched on
% storage before meaning exactly as the write path did, so a foreign space's
% equation kept answering after its atom was gone.
test(removing_a_foreign_equation_removes_its_clause) :-
    forall(member(Space, ['&plunit_native_rules', '&plunit_rules']),
           an_equation_stops_answering_when_removed(Space)).

% What a call answers once its last equation is gone is not [] but the term
% itself, because a MeTTa function need not be total and an unreduced call is
% its own answer. So this asks the native space the same question and requires
% the same answer, rather than pinning one that looked obvious and was not.
an_equation_stops_answering_when_removed(Space) :-
    space_module(Space, Module),
    'add-atom'(Space, [=, ['fr-gone'], here], _),
    findall(A, with_metta_module(Module, reduce(['fr-gone'], A, _)), Before),
    assertion(Before == [here]),
    'remove-atom'(Space, [=, ['fr-gone'], here], Answered),
    assertion(Answered == []),
    findall(A, with_metta_module(Module, reduce(['fr-gone'], A, _)), After),
    assertion(After == [['fr-gone']]).

% The space is still a DATA SOURCE. Holding rules is an addition, not a
% replacement, which is the whole of what "both" means here.
test(a_rule_holding_space_is_still_a_data_source) :-
    'add-atom'('&plunit_rules', [edge, a, b], _),
    findall(Y, match('&plunit_rules', [edge, a, Y], Y, Y), Ys),
    assertion(Ys == [b]).

test(adding_a_rule_to_a_ruleless_foreign_space_is_refused,
     [ throws(error(petta_foreign_space_holds_no_rules('&plunit_facts', _), _)) ]) :-
    'add-atom'('&plunit_facts', [=, ['fr-never', _], 1], _).

% And a plain atom still goes in, so the refusal is about equations and not
% about the space.
test(a_ruleless_foreign_space_still_takes_facts) :-
    'add-atom'('&plunit_facts', [fact, a], _),
    findall(A, metta_foreign_atoms('&plunit_facts', A), Atoms),
    assertion(memberchk([fact, a], Atoms)).

:- end_tests(spaces_foreign_rules).

% The provider's own pushdown method claims exact for EVERYTHING, which is
% the lie the declared route must be able to outrank shape by shape.
:- discontiguous metta_foreign_atoms/2.
metta_foreign_space('&plunit_handles').
metta_foreign_atoms('&plunit_handles', Atom) :-
    member(Atom, [[edge, a, b], [edge, b, c], [edge, d, d], [secret, s1]]).
metta_foreign_match('&plunit_handles', Pattern, _Options) :-
    metta_foreign_atoms('&plunit_handles', Pattern).
metta_foreign_pushdown('&plunit_handles', _, exact).

:- begin_tests(spaces_handles_guard).

guard_declare(Entry) :- 'add-atom'('&petta', Entry, _).
guard_retract(Entry) :- catch('remove-atom'('&petta', Entry, _), _, true).

test(a_declared_route_outranks_the_pushdown_method,
     [ setup(guard_declare([handles, '&plunit_handles', [edge, S, S], 'Sound'])),
       cleanup(guard_retract([handles, '&plunit_handles', [edge, S2, S2], 'Sound'])) ]) :-
    % The method says exact for everything; the declaration says Sound for
    % the repeated-variable shape, so the class drops to inexact there
    % while the undeclared shape keeps the method's answer.
    foreign_pushdown_class('&plunit_handles', [edge, Q, Q], Repeated),
    assertion(Repeated == inexact),
    foreign_pushdown_class('&plunit_handles', [edge, _, _], Distinct),
    assertion(Distinct == exact).

test(a_refuse_declaration_stops_the_match_before_the_provider,
     [ setup(guard_declare([handles, '&plunit_handles', [secret, _], 'Refuse'])),
       cleanup(guard_retract([handles, '&plunit_handles', [secret, _], 'Refuse'])),
       throws(error(petta_refused_shape('&plunit_handles', _, _), _)) ]) :-
    match('&plunit_handles', [secret, X], X, _).

test(other_shapes_still_answer_beside_a_refusal,
     [ setup(guard_declare([handles, '&plunit_handles', [secret, _], 'Refuse'])),
       cleanup(guard_retract([handles, '&plunit_handles', [secret, _], 'Refuse'])) ]) :-
    findall(V, match('&plunit_handles', [edge, a, V], V, _), Values),
    assertion(Values == [b]).

test(a_join_with_a_refused_access_pattern_is_refused_at_plan_time,
     [ setup(guard_declare([handles, '&plunit_handles', [edge, [in, _], _], 'Refuse'])),
       cleanup(guard_retract([handles, '&plunit_handles', [edge, [in, _], _], 'Refuse'])),
       throws(error(petta_refused_shape('&plunit_handles', _, _), _)) ]) :-
    % The nested loop binds the second conjunct's subject per row, the
    % refused access pattern, so the whole join is refused before a row.
    match('&plunit_handles', [',', [edge, _X, Y], [edge, Y, _Z]], done, _).

test(the_free_scan_is_untouched_by_the_adorned_refusal,
     [ setup(guard_declare([handles, '&plunit_handles', [edge, [in, _], _], 'Refuse'])),
       cleanup(guard_retract([handles, '&plunit_handles', [edge, [in, _], _], 'Refuse'])) ]) :-
    findall(X-Y, match('&plunit_handles', [edge, X, Y], X-Y, _), Rows),
    assertion(Rows == [a-b, b-c, d-d]).

test(a_declaration_conflict_surfaces_on_the_match_itself,
     [ setup(( guard_declare([handles, '&plunit_handles', [edge, a, _], 'Exact']),
               guard_declare([handles, '&plunit_handles', [edge, _, b], 'Sound']) )),
       cleanup(( guard_retract([handles, '&plunit_handles', [edge, a, _], 'Exact']),
                 guard_retract([handles, '&plunit_handles', [edge, _, b], 'Sound']) )),
       throws(error(petta_contract_conflict('&plunit_handles', _, _, _), _)) ]) :-
    match('&plunit_handles', [edge, a, b], done, _).

:- end_tests(spaces_handles_guard).

:- begin_tests(spaces_source_discipline).

% (source Ctx linear) makes a second physical touch of a drained source a
% loud error where the floor answers a silently empty set. The mark is a
% prolog flag: process-global, transaction-immune, reset only by
% petta_source_reset/1, the door a fresh provider arrives through.

source_declare(Entry) :- 'add-atom'('&petta', Entry, _).
source_retract(Entry) :- catch('remove-atom'('&petta', Entry, _), _, true).

test(a_linear_source_consumes_once_and_then_refuses,
     [ setup(( source_declare([source, '&plunit_handles', linear]),
               petta_source_reset('&plunit_handles') )),
       cleanup(( source_retract([source, '&plunit_handles', linear]),
                 petta_source_reset('&plunit_handles') )) ]) :-
    findall(V, match('&plunit_handles', [edge, a, V], V, _), Values),
    assertion(Values == [b]),
    catch(( match('&plunit_handles', [edge, a, _], _, _), Second = answered ),
          error(petta_source_discipline('&plunit_handles', linear), _),
          Second = refused),
    assertion(Second == refused).

test(a_join_over_a_linear_source_refuses_the_inner_touch,
     [ setup(( source_declare([source, '&plunit_handles', linear]),
               petta_source_reset('&plunit_handles') )),
       cleanup(( source_retract([source, '&plunit_handles', linear]),
                 petta_source_reset('&plunit_handles') )),
       throws(error(petta_source_discipline('&plunit_handles', linear), _)) ]) :-
    findall(X-Z,
            match('&plunit_handles',
                  [',', [edge, X, Y], [edge, Y, Z]], X-Z, _),
            _).

test(reset_makes_a_fresh_source,
     [ setup(( source_declare([source, '&plunit_handles', linear]),
               petta_source_reset('&plunit_handles') )),
       cleanup(( source_retract([source, '&plunit_handles', linear]),
                 petta_source_reset('&plunit_handles') )) ]) :-
    findall(V, match('&plunit_handles', [edge, a, V], V, _), First),
    petta_source_reset('&plunit_handles'),
    findall(V, match('&plunit_handles', [edge, a, V], V, _), Second),
    assertion(First == Second).

test(the_undeclared_floor_pays_nothing_and_repeats) :-
    findall(V, match('&plunit_handles', [edge, a, V], V, _), First),
    findall(V, match('&plunit_handles', [edge, a, V], V, _), Second),
    assertion(First == Second).

test(the_discipline_error_has_an_engine_message) :-
    message_to_string(error(petta_source_discipline('&c', linear), none), M),
    once(sub_string(M, _, _, _, "second")),
    once(sub_string(M, _, _, _, "linear")),
    \+ sub_string(M, _, _, _, "Unknown error term").

:- end_tests(spaces_source_discipline).

% A Prolog-hosted provider whose match THROWS mid-stream: its exceptions
% are ordinary catchable ones, so the engine's own fallback in
% petta_match_erring/6 enforces the declared mode, where a Python
% provider's tunnel past catch/3 makes the adapter hook do it instead.
metta_foreign_space('&plunit_flaky').
metta_foreign_space('&plunit_ctl').
metta_foreign_match('&plunit_ctl', _, _) :- throw(petta_py_interrupted).
metta_foreign_match('&plunit_flaky', Pattern, _Options) :-
    (   Pattern = [edge, a, b]
    ;   throw(error(type_error(backend, fell_over), flaky))
    ).

:- begin_tests(spaces_error_modes).

erring_declare(Entry) :- 'add-atom'('&petta', Entry, _).
erring_retract(Entry) :- catch('remove-atom'('&petta', Entry, _), _, true).

test(the_undeclared_floor_aborts,
     [throws(error(type_error(backend, fell_over), _))]) :-
    findall(V, match('&plunit_flaky', [edge, a, V], V, _), _).

test(keep_delivers_the_failure_as_the_error_answer,
     [ setup(erring_declare(['on-error', '&plunit_flaky', [edge, _, _], keep])),
       cleanup(erring_retract(['on-error', '&plunit_flaky', [edge, _, _], keep])) ]) :-
    findall(R, match('&plunit_flaky', [edge, a, _V], answered, R), Rs),
    assertion(Rs = [answered, ['Error', [edge, a, _], _]]).

test(empty_ends_the_stream_by_declaration,
     [ setup(erring_declare(['on-error', '&plunit_flaky', [edge, _, _], empty])),
       cleanup(erring_retract(['on-error', '&plunit_flaky', [edge, _, _], empty])) ]) :-
    findall(R, match('&plunit_flaky', [edge, a, _V], answered, R), Rs),
    assertion(Rs == [answered]).

test(a_control_signal_is_never_kept,
     [ setup(erring_declare(['on-error', '&plunit_ctl', [edge, _, _], keep])),
       cleanup(erring_retract(['on-error', '&plunit_ctl', [edge, _, _], keep])),
       throws(petta_py_interrupted) ]) :-
    petta_match_erring(keep, '&plunit_ctl', [edge, a, _], [], out, _).

:- end_tests(spaces_error_modes).

% A Prolog-hosted matchable: the term claims its own matching logic, so
% the walker's hook cases run with no Python in the process. The ground
% cases mirror the arbiter's measured decisions [source: LeaTTa
% tests/semantics/matching/grounded_value_matching.metta].
metta_matchable_value(plunit_interval(_, _)).
metta_custom_match(plunit_interval(Lo, Hi), Other) :-
    number(Other), Lo =< Other, Other =< Hi.

:- begin_tests(spaces_custom_match).

test(ground_equality) :- petta_match_atoms(a, a).
test(ground_difference, [fail]) :- petta_match_atoms(a, b).
test(numeric_promotion) :- petta_match_atoms(1, 1.0).
test(string_equality) :- petta_match_atoms("x", "x").
test(string_difference, [fail]) :- petta_match_atoms("x", "y").
test(occurs_check_rejects, [fail]) :-
    petta_match_atoms(X, [f, X]).
test(a_variable_binds, [true(X == [f, a])]) :-
    petta_match_atoms(X, [f, a]).
test(pointwise_bindings, [true(X-Y == a-b)]) :-
    petta_match_atoms([f, X, b], [f, a, Y]).
test(arity_mismatch_fails, [fail]) :-
    petta_match_atoms([f, a], [f, a, b]).
test(a_hook_accepts_inside_its_range, [nondet]) :-
    petta_match_atoms(plunit_interval(1, 5), 3).
test(a_hook_rejects_outside_its_range, [fail]) :-
    petta_match_atoms(plunit_interval(1, 5), 9).
test(the_grounded_side_is_handed_first, [nondet]) :-
    % the arbiter swaps arguments when the grounded operand is on the right
    petta_match_atoms(3, plunit_interval(1, 5)).
test(a_variable_beats_the_hook, [true(V == plunit_interval(1, 5))]) :-
    petta_match_atoms(V, plunit_interval(1, 5)).
test(a_space_operand_is_queried, [nondet]) :-
    petta_match_atoms('&plunit_handles', [edge, a, B]),
    B == b.
test(a_space_with_no_match_fails, [fail]) :-
    petta_match_atoms('&plunit_handles', [edge, q1, q2]).
test(an_unregistered_name_is_a_plain_symbol, [fail]) :-
    petta_match_atoms('&plunit_never_registered', [edge, a, b]).

:- end_tests(spaces_custom_match).
