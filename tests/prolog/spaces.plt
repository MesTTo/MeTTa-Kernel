% Purpose: verify native and foreign space storage, isolation, registration,
%   matching, and lifecycle behavior, including what a selective match COSTS
%   as the space grows, which a scan would answer identically.
% Guarantees:
%   - Native storage modules do not inherit user predicates, while execution
%     modules keep undefined calls loud [tested: spaces_storage_modules].
%   - Every metta_engine_emitted/1 declaration is protected from capture in
%     a space [tested: test_every_engine_emitted_name_is_protected_by_derivation;
%     commit=dcfc20be4933c19140ccb5759291401d13058301].
%   - inherited reads are child-first unions, conjunctions join across
%     layers, and declaration failures leave no partial relation [tested:
%     spaces_inheritance;
%     commit=755330de329ece49eddcfb7d6db3061c3350a0ca].
%   - restricted spaces select curated grant profiles and raw calls pass the
%     sandbox boundary [tested: spaces_restricted_modules;
%     commit=6a08901f4125c2536f5b4032daac9937f793870f].
%   - parametric-space identifiers map bijectively to canonical modules and a
%     fixed private storage functor, with validation before cache publication
%     [tested: spaces_parametric; commit=3c7bcde6a0670ec5c563584b26977b41cc727580].
%   - duplicate declarations in one batch are detected before any member is
%     stored [tested: spaces_batch_is_only_a_transport; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).

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

scale_size(100).
scale_size(10000).

scale_space(Count, Space) :-
    atom_concat('&plunit_cycle_scale_', Count, Space).

fill_scale_space(Count) :-
    scale_space(Count, Space),
    forall(between(1, Count, I), add_sexp(Space, [fact, I])).

drop_scale_spaces :-
    forall(scale_size(Count),
           ( scale_space(Count, Space),
             clear_native_atoms(Space),
             retractall(native_storage_module_cache(Space, _)) )).

%The probe that MISSES, which is the discriminating one. A hit on a low key
%costs the same at both sizes under a scan too, because a scan stops at the
%first candidate, so comparing hits would pass whether the read is indexed or
%not. Concluding a miss is the case a scan cannot shortcut: it has to look at
%everything [measured 2026-08-18: a hit on the LAST atom costs 6,503 per 500
%at both sizes, the same as a hit on the first, so the read is indexed today].
missing_match_cost(Space, Inferences) :-
    forall(between(1, 200, _), \+ match(Space, [fact, -1], -1, _)),
    findall(Sample,
            ( between(1, 3, _),
              missing_match_sample(Space, Sample) ),
            Samples),
    min_list(Samples, Inferences).

missing_match_sample(Space, Inferences) :-
    garbage_collect,
    statistics(inferences, I0),
    forall(between(1, 500, _), \+ match(Space, [fact, -1], -1, _)),
    statistics(inferences, I1),
    Inferences is I1 - I0.

% A bound match is one indexed probe, not a scan, and the acyclic guard the
% tests above rely on does not change that: it runs on the ANSWER rather than
% on every candidate [source: engine/spaces.pl, the comment above
% native_expression/4]. So the cost of one probe is
% the same whatever the space holds, which is an equality rather than a bound
% and needs no threshold.
%
% Measured 2026-08-18, min of three over 500 probes: 5,503 inferences to
% conclude a miss on a space of 100 atoms and 5,503 on one of 10,000. A scan
% would read 100 against 10,000 clauses to reach the same conclusion.
%
% The hits are asserted alongside, because a space that had stopped answering
% would conclude its misses just as cheaply at both sizes.
test(a_selective_match_costs_the_same_on_a_hundredfold_larger_space,
     [ setup(forall(scale_size(Count), fill_scale_space(Count))),
       cleanup(drop_scale_spaces) ]) :-
    scale_space(100, Small),
    scale_space(10000, Large),
    findall(R, match(Small, [fact, 100], 100, R), [100]),
    findall(R, match(Large, [fact, 10000], 10000, R), [10000]),
    missing_match_cost(Small, SmallCost),
    missing_match_cost(Large, LargeCost),
    LargeCost == SmallCost.

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

test(spaces_removal_answers_unit_for_success_and_an_error_for_absence,
     [ setup(cleanup_arbitrary_space), cleanup(cleanup_arbitrary_space) ]) :-
    arbitrary_space(Space),
    add_sexp(Space, [pair, 1, 2]),
    add_sexp(Space, lonely),
    % Unit for a removal that happened and an error for one that found
    % nothing. The language's own complaint is what asks for the second half,
    % "if the given atom is not in the space, remove-atom currently neither
    % raises a error nor returns the empty result", and upstream carries the
    % same question unanswered as the TODO at stdlib/space.rs:219. The arbiter
    % rules it: LeaTTa Hyperon-Hacks-Register row 15, error for absence and
    % unit for success, SATISFIED in Metta.Minimal.removeAtomStep. This test
    % used to assert unit for all three.
    'remove-atom'(Space, [pair, 1, 2], Present),
    assertion(Present == []),
    'remove-atom'(Space, [pair, 1, 2], Repeated),
    assertion(Repeated = ['Error', ['remove-atom', Space, [pair, 1, 2]], _]),
    'remove-atom'(Space, [never, there], Absent),
    assertion(Absent = ['Error', ['remove-atom', Space, [never, there]],
                        "remove-atom: atom is not in the space"]),
    % The information is not lost, it moved to where the ENGINE uses it:
    % metta_remove_atom/3 still answers whether anything was there, which is
    % what the loader's rollback and the storage modules read.
    metta_remove_atom(Space, lonely, Removed),
    assertion(Removed == true),
    metta_remove_atom(Space, nonesuch, Missing),
    assertion(Missing == false),
    % Removal takes ONE occurrence, because a space is a multiset and
    % subtracting from a multiset takes one. This used to assert that two
    % adds and one removal left NOTHING, on the reasoning that "a MeTTa space
    % is a multiset unless something forbids it, so removal takes EVERY
    % occurrence", which argues for the opposite of what it concludes. The
    % arbiter agrees with the premise: MettaHyperonFullTests/Properties.lean
    % requires multiset subtraction on the reader-visible view of &self.
    add_sexp(Space, [twice, x]),
    add_sexp(Space, [twice, x]),
    'remove-atom'(Space, [twice, x], One),
    assertion(One == []),
    findall(A, get_native_atom(Space, A), Half),
    assertion(Half == [[twice, x]]),
    'remove-atom'(Space, [twice, x], Other),
    assertion(Other == []),
    findall(B, get_native_atom(Space, B), Left),
    assertion(Left == []),
    % And the two rulings compose: once the copies are gone the next removal
    % is an absence rather than a third silent unit.
    'remove-atom'(Space, [twice, x], Gone),
    assertion(Gone = ['Error', ['remove-atom', Space, [twice, x]], _]).

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
    user:clear_fun_meta(_, F),
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
    \+ user:fun_meta_clause(_, plunit_registration_rollback, _, _),
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

% No door calls one shared space test: each reaches the decision through the
% work it was already doing, because a test in front of every door cost one to
% three inferences on every space operation and four benchmarks saw it. Several
% spellings of one decision is exactly how they drift apart, so this is the
% guard, and it asks the DOORS rather than the spellings: each refuses exactly
% the terms petta_space_name/1 refuses, over every kind of term a caller can
% hand it. A space that exists and has nothing to answer answers nothing, which
% is not a refusal.
read_door_refuses('get-atoms', Term, Refused) :-
    (   'get-atoms'(Term, Answer),
        nonvar(Answer), Answer = ['Error'|_]
    ->  Refused = true
    ;   Refused = false
    ).
read_door_refuses(match, Term, Refused) :-
    (   match(Term, [plunit_door_probe, _], plunit_door_probe, Answer),
        nonvar(Answer), Answer = ['Error'|_]
    ->  Refused = true
    ;   Refused = false
    ).

test(the_read_doors_refuse_what_the_named_test_refuses,
     [ forall(( member(Term, ['&self', '&plunit_names', not_a_space, [], 0, 1.5,
                              "text", [a, b], f(x), _Unbound]),
                member(Door, ['get-atoms', match]) )) ]) :-
    ( petta_space_name(Term) -> Named = true ; Named = false ),
    read_door_refuses(Door, Term, Refused),
    %Accepted by the named test exactly when the door does not refuse it.
    assertion(( Named == true, Refused == false
              ; Named == false, Refused == true )).

:- end_tests(spaces_registration).

% Two providers in the shape a library actually ships: one that enumerates and
% nothing else, which bindings/python/petta/foreign.py explicitly says is enough, and
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
    user:clear_fun_meta(_, Name).

:- end_tests(spaces_late_type_declaration).

% The topology Phase 11 establishes, asserted rather than assumed. Nothing
% else in the tree would notice it drifting back, and drifting back is
% silent: an equation compiled into the module the engine resolves in
% REPLACES a predicate of that name instead of shadowing it.
:- begin_tests(spaces_execution_modules).

test(every_space_compiles_into_a_module_of_its_own) :-
    space_module('&self', Self),
    space_module('&plunit_exec_a', A),
    space_module('&plunit_exec_b', B),
    petta_engine_module(Engine),
    assertion(Self \== A), assertion(A \== B), assertion(Self \== B),
    assertion(Self \== Engine),
    assertion(Self \== user),
    assertion(A \== '&plunit_exec_a').

% system -> engine -> &self's module -> every other space's. Read off SWI with
% import_module/2 rather than believed: SWI decides an implicitly created
% module's base from the first character of its name, which would have given a
% `$`-prefixed one `system` and no way to reach the engine at all.
test(the_chain_is_engine_then_self_then_space) :-
    petta_engine_module(Engine),
    space_module('&self', Self),
    space_module('&plunit_exec_chain', Space),
    assertion(import_module(Self, Engine)),
    assertion(import_module(Space, Self)),
    assertion(\+ import_module(Self, Self)).

% metta_self_module/1 writes the name and space_module/2 computes it. They are
% two places, deliberately: the first is inlined at compile time so the hot
% paths pay nothing to read it, and the second is the mapping every other space
% goes through. This is what stops them drifting apart.
test(the_written_self_module_is_the_mapped_one) :-
    metta_self_module(Written),
    space_module('&self', Mapped),
    assertion(Written == Mapped),
    current_metta_module(Default),
    assertion(Default == Written).

test(the_module_to_space_map_is_the_inverse) :-
    forall(member(Space, ['&self', '&plunit_exec_inv', '&petta']),
           ( space_module(Space, Module),
             metta_module_space(Module, Back),
             assertion(Back == Space) )),
    % It fails on a module that is not a space's rather than passing one
    % through, because every caller has one in hand.
    petta_engine_module(Engine),
    assertion(\+ metta_module_space(Engine, _)),
    assertion(\+ metta_module_space(user, _)).

% The collision surface, as a check rather than as a claim. Each of these
% names is held by the module the ENGINE resolves in, an equation for it is
% accepted in &self, and what the engine holds is unchanged afterwards. Before
% Phase 11 the arity-2 `plus` was accepted and DESTROYED the predicate, which
% is what examples/functions/invertpeanoplus.metta did on every run
% [measured 2026-08-19 on c7126f1].
%
% Two tables, because the two ways the engine can hold a name need different
% evidence. An IMPORTED one keeps its imported_from/1; a name the engine
% DEFINES keeps its clause count.
engine_imports(plus, 2).
engine_imports(atom_number, 1).
engine_imports(with_output_to, 1).

engine_defines('car-atom', 1).
engine_defines(repr, 1).

shadow_in_self(Name, MettaArity, Self, Arity) :-
    Arity is MettaArity + 1,
    length(Args, MettaArity),
    'add-atom'('&self', [=, [Name|Args], plunit_shadowed], _),
    space_module('&self', Self).

%The engine's own removal drops an emptied local shadow so the module
%chain answers again [tested: removing_a_self_shadow_restores_the_builtin];
%nothing here needs to reach into the module behind its back.
unshadow_in_self(Name, MettaArity, _Arity) :-
    length(Args, MettaArity),
    'remove-atom'('&self', [=, [Name|Args], plunit_shadowed], _).

test(an_imported_engine_name_is_free_in_a_space,
     [forall(engine_imports(Name, MettaArity))]) :-
    petta_engine_module(Engine),
    Arity is MettaArity + 1,
    functor(Probe, Name, Arity),
    predicate_property(Engine:Probe, imported_from(Owner)),
    setup_call_cleanup(
        shadow_in_self(Name, MettaArity, Self, _),
        ( functor(Local, Name, Arity),
          % Asked as properties rather than with clause/3, which raises rather
          % than failing for a predicate it may not show: if the shadow had NOT
          % been created these would be the system predicate's, and clause/3
          % would report a permission error instead of the difference.
          assertion(predicate_property(Self:Local, number_of_clauses(1))),
          assertion(\+ predicate_property(Self:Local, imported_from(_))),
          assertion(predicate_property(Engine:Probe, imported_from(Owner))) ),
        unshadow_in_self(Name, MettaArity, Arity)).

test(a_name_the_engine_defines_is_free_in_a_space,
     [forall(engine_defines(Name, MettaArity))]) :-
    petta_engine_module(Engine),
    Arity is MettaArity + 1,
    functor(Probe, Name, Arity),
    predicate_property(Engine:Probe, number_of_clauses(Before)),
    setup_call_cleanup(
        shadow_in_self(Name, MettaArity, Self, _),
        ( functor(Local, Name, Arity),
          assertion(predicate_property(Self:Local, number_of_clauses(1))),
          assertion(\+ predicate_property(Self:Local, imported_from(_))),
          assertion(predicate_property(Engine:Probe,
                                       number_of_clauses(Before))) ),
        unshadow_in_self(Name, MettaArity, Arity)).

% The other half of the shadowing rule. A name the ENGINE compiles into
% function bodies cannot be taken, in any space, because taking it would
% capture the engine's own goal in that space's compiled clauses rather than
% shadowing a function: a wrong answer with no error. The refusal comes from
% SWI, because protect_engine_emitted/1 binds each of these into every space's
% module, and it names the right cause rather than calling them Prolog's.
assert_engine_emitted_name_is_protected(Name/Arity) :-
    MettaArity is Arity - 1,
    length(Args, MettaArity),
    catch('add-atom'('&self', [=, [Name|Args], plunit_captured], _), Error, true),
    assertion(Error = error(petta_engine_goal_redefinition(Name, MettaArity, '&self'), _)),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "compiles into function bodies")),
    % and the engine's own goal is still the one a space resolves
    petta_engine_module(Engine),
    space_module('&self', Self),
    functor(Head, Name, Arity),
    assertion(predicate_property(Self:Head, imported_from(_))),
    assertion(predicate_property(Engine:Head, defined)).

test(an_engine_emitted_name_cannot_be_taken,
     [ forall(metta_engine_emitted(Name/Arity)) ]) :-
    assert_engine_emitted_name_is_protected(Name/Arity).

test(test_every_engine_emitted_name_is_protected_by_derivation) :-
    findall(Name/Arity, metta_engine_emitted(Name/Arity), Emitted),
    assertion(Emitted \== []),
    forall(member(Entry, Emitted),
           assert_engine_emitted_name_is_protected(Entry)).

% Every space, not &self alone, which is what makes the protection a property
% of the topology rather than of one space.
test(an_engine_emitted_name_cannot_be_taken_in_a_named_space) :-
    catch('add-atom'('&plunit_emitted_probe', [=, [has_type, _], plunit_captured],
                     _), Error, true),
    assertion(Error = error(petta_engine_goal_redefinition(has_type, 1,
                                                           '&plunit_emitted_probe'), _)).

% A space has two halves and clearing it used to empty one. Storage went and
% the compiled clauses stayed, so a space holding NOTHING still answered its
% own functions, and since space names are pooled that is a previous life
% answering through a recycled name. It was masked by bindings/python/petta/shim.pl's
% clear, which funnels equations through the removal path before calling the
% engine's own door, so the Python surface was whole and every other caller
% was not.
test(clearing_a_space_empties_its_execution_module,
     [ cleanup(( clear_native_atoms('&plunit_life'),
                 retractall(fun('plunit-past-life')),
                 retractall(arity('plunit-past-life', _)) )) ]) :-
    Space = '&plunit_life',
    process_metta_string("(= (plunit-past-life) inherited)", _, Space),
    process_metta_string("!(plunit-past-life)", First, Space),
    assertion(First == [inherited]),
    space_module(Space, Module),
    aggregate_all(count, clause(Module:'plunit-past-life'(_), _), Compiled),
    assertion(Compiled == 1),

    clear_native_atoms(Space),

    findall(A, get_native_atom(Space, A), Left),
    assertion(Left == []),
    aggregate_all(count, clause(Module:'plunit-past-life'(_), _), Remaining),
    assertion(Remaining == 0),
    % The name is forgotten too, not just its clauses: nothing defines the
    % function any more, which is what remove_equation/6 decides for a single
    % removal and what the sweep used to skip.
    assertion(\+ fun('plunit-past-life')),
    % The whole point, asked the way a recycled name would ask it.
    process_metta_string("!(plunit-past-life)", Second, Space),
    assertion(Second == [['plunit-past-life']]).

% A declaration is the other shape with a compiled half, and it leaves through
% its own path for the same reason: dropping the atom alone would leave the
% call sites it was shaping compiled against a declaration that is gone.
test(clearing_a_space_takes_its_declarations_through_their_own_path,
     [ cleanup(( clear_native_atoms('&plunit_life_decl'),
                 retractall(fun('plunit-declared')),
                 retractall(arity('plunit-declared', _)) )) ]) :-
    Space = '&plunit_life_decl',
    process_metta_string("(: plunit-declared (-> Number Number))", _, Space),
    process_metta_string("(= (plunit-declared $x) $x)", _, Space),
    findall(A, get_native_atom(Space, A), Before),
    assertion(length(Before, 2)),
    clear_native_atoms(Space),
    findall(B, get_native_atom(Space, B), After),
    assertion(After == []),
    assertion(\+ fun('plunit-declared')),
    process_metta_string("!(plunit-declared 1)", Answer, Space),
    assertion(Answer == [['plunit-declared', 1]]).

% Plain atoms have no compiled half, so they stay on the sweep rather than
% going one at a time through the removal funnel. This is the guard on that:
% a space of plain atoms clears without any of them reaching remove_equation/6.
test(clearing_plain_atoms_stays_a_sweep,
     [ cleanup(clear_native_atoms('&plunit_life_bulk')) ]) :-
    Space = '&plunit_life_bulk',
    forall(between(1, 50, N), add_sexp(Space, [bulk, N])),
    add_sexp(Space, lonely),
    statistics(inferences, I0),
    clear_native_atoms(Space),
    statistics(inferences, I1),
    Spent is I1 - I0,
    findall(A, get_native_atom(Space, A), Left),
    assertion(Left == []),
    % One removal through the funnel costs more than this whole clear does;
    % the number is generous because the enumeration that looks for compiled
    % atoms is itself linear, and what it guards against is 51 removals.
    assertion(Spent < 1000).

:- end_tests(spaces_execution_modules).

:- begin_tests(spaces_match_snapshot).

% The language specifies this rather than leaving it open: "match first finds
% all the matches, and then instantiates the output pattern with them, which
% is evaluated outside match. If remove-atom and add-atom would be executed
% right away for each found matching, the condition of circular links would be
% broken after the first rewrite" [source: the language's Working with spaces].
% The arbiter pins it with an experiment built to tell an eager snapshot from
% a lazy query that happens to be fully consumed, and only the effect ORDER is
% a recorded free divergence [source: LeaTTa tests/semantics/matching/
% nondeterministic_match_snapshot.metta].
setup_snapshot_space :-
    cleanup_snapshot_space,
    forall(member(P, [[snap_link, a, b], [snap_link, b, c],
                      [snap_link, c, a], [snap_link, c, e]]),
           add_sexp('&plunit_snapshot', P)).

cleanup_snapshot_space :- clear_native_atoms('&plunit_snapshot').

% Upstream's own graph-rewrite example, which is where the divergence was
% measured: every row is found before the first template's remove-atom breaks
% the cycle for the rest. Reversing ONE edge instead of three is what a lazy
% conjunction does.
test(a_conjunction_finds_every_row_before_any_template_runs,
     [ setup(setup_snapshot_space), cleanup(cleanup_snapshot_space) ]) :-
    Space = '&plunit_snapshot',
    Pattern = [',', [snap_link, X, Y], [snap_link, Y, Z], [snap_link, Z, X]],
    findall(X-Y, ( match(Space, Pattern, out, out),
                   'remove-atom'(Space, [snap_link, X, Y], []),
                   'add-atom'(Space, [snap_link, Y, X], _) ),
            Rewritten),
    % Three loop rotations, all of them, and the fourth link is not in a loop.
    assertion(Rewritten == [a-b, b-c, c-a]),
    findall(L, get_native_atom(Space, L), Left),
    msort(Left, Sorted),
    assertion(Sorted == [[snap_link, a, c], [snap_link, b, a],
                         [snap_link, c, b], [snap_link, c, e]]).

% A single pattern needed no snapshot and must not have grown one: the logical
% update view already fixes what one goal over one dynamic predicate sees, so
% a template that removes the OTHER row still leaves that row to answer.
test(a_single_pattern_snapshots_through_the_logical_update_view,
     [ setup(setup_snapshot_space), cleanup(cleanup_snapshot_space) ]) :-
    Space = '&plunit_snapshot',
    findall(X-Y, ( match(Space, [snap_link, X, Y], out, out),
                   ( 'remove-atom'(Space, [snap_link, c, e], _) -> true ; true ) ),
            Rows),
    % Four rows, including the one the first template removed.
    assertion(length(Rows, 4)),
    assertion(memberchk(c-e, Rows)).

% And it still STREAMS, which is what the snapshot costs everywhere it is not
% needed: a first solution off a big space must not walk the space.
test(a_single_pattern_still_answers_the_first_row_without_walking_the_space,
     [ setup(setup_snapshot_space), cleanup(cleanup_snapshot_space) ]) :-
    Space = '&plunit_snapshot',
    forall(between(1, 2000, N), add_sexp(Space, [snap_bulk, N])),
    statistics(inferences, I0),
    once(match(Space, [snap_bulk, _], out, out)),
    statistics(inferences, I1),
    Spent is I1 - I0,
    % Walking two thousand atoms costs thousands; taking the first costs tens.
    assertion(Spent < 200).

% A conjunction's rows carry their annotation, which rides a BACKTRACKABLE
% global that the snapshot's findall would otherwise undo.
test(a_conjunction_keeps_each_row_annotation,
     [ setup(setup_snapshot_space), cleanup(cleanup_snapshot_space) ]) :-
    Space = '&plunit_snapshot',
    Pattern = [',', [snap_link, X, Y], [snap_link, Y, Z]],
    findall(K, ( match(Space, Pattern, out, out), petta_annotation(K) ), Ks),
    % Unannotated atoms read the semiring's 1, once per row rather than a
    % stale neighbour's value or nothing at all.
    assertion(Ks \== []),
    assertion(forall(member(K1, Ks), K1 == 1)),
    assertion(Z == Z).

:- end_tests(spaces_match_snapshot).

:- begin_tests(spaces_builtin_override).

% &self compiles into a module of its own, so an equation for a builtin name is
% a local SHADOW there exactly as it is in a named space, and the engine's own
% predicate of that name goes on answering. Before Phase 11 &self compiled into
% the module the engine itself resolves in, where the same equation REPLACED
% the predicate for the rest of the process: two shipped examples did that, and
% tests/prolog/engine_integrity.pl is the gate that would not let it back.
test(self_may_shadow_a_builtin,
     [ cleanup('remove-atom'('&self', [=, ['car-atom', _], nine], _)) ]) :-
    'add-atom'('&self', [=, ['car-atom', _], nine], _),
    metta_self_module(Self),
    with_metta_module(Self, reduce(['car-atom', [1, 2]], Shadowed, _)),
    assertion(Shadowed == nine),
    % The engine's own predicate is untouched, which is the whole point.
    petta_engine_module(Engine),
    assertion(Engine:'car-atom'([1, 2], 1)).

% Removing the shadow RESTORES the builtin. The erase used to leave an
% empty local 'car-atom'/2 in &self's module, which kept shadowing the
% engine's for the rest of the process: every &self-compiled caller of
% car-atom, the prelude's admission judge included, failed from then on
% [measured 2026-08-20].
test(removing_a_self_shadow_restores_the_builtin) :-
    'add-atom'('&self', [=, ['car-atom', _], nine], _),
    'remove-atom'('&self', [=, ['car-atom', _], nine], _),
    metta_self_module(Self),
    with_metta_module(Self, reduce(['car-atom', [1, 2]], Restored, _)),
    assertion(Restored == 1).

% What is left to refuse is SWI's protected core, and it is refused in EVERY
% space rather than in &self alone. sort/2 is one of the four names still taken
% at MeTTa arity 1 [measured 2026-08-19].
test(prologs_protected_core_is_still_refused,
     [throws(error(petta_builtin_redefinition(sort, 1, '&self'), _))]) :-
    'add-atom'('&self', [=, [sort, _], nine], _).

test(the_refusal_names_the_protected_core) :-
    catch('add-atom'('&self', [=, [call, _], nine], _), Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "protected core")),
    assertion(sub_string(Text, _, _, _, "no space can redefine")),
    assertion(sub_string(Text, _, _, _, "every other builtin name is free")).

% The same equation in a named space, so the two sides of the rule are one
% test apart: a shadow is local to the space that wrote it.
test(a_named_space_may_shadow_a_builtin,
     [ cleanup(( 'remove-atom'('&plunit_shadow_builtin', [=, ['+', 1, 2], nine], _),
                 clear_native_atoms('&plunit_shadow_builtin') )) ]) :-
    'add-atom'('&plunit_shadow_builtin', [=, ['+', 1, 2], nine], _),
    space_module('&plunit_shadow_builtin', Module),
    with_metta_module(Module, reduce(['+', 1, 2], Shadowed, _)),
    assertion(Shadowed == nine),
    metta_self_module(Self),
    with_metta_module(Self, reduce(['+', 1, 2], Ordinary, _)),
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


test(matching_requires_a_named_space) :-
    % An unbound space would enumerate every space that has ever been
    % written to, so a program in one space could read another it never
    % names. match/4 is a door a MeTTa program comes through, so the refusal
    % is the write path's answer rather than a throw: this used to raise
    % SWI's bare instantiation_error, which named neither the operation nor
    % the call [source: the note above match/4's last clause].
    findall(R, match(_AnySpace, [plunit_secret, _X], conj, R), Answers),
    Answers = [['Error', ['match', _, [plunit_secret, _], conj], Message]],
    Message == "match expects a space as the first argument",
    % A conjunctive pattern reaches its own routing clause and is refused
    % there too, rather than losing the refusal in match_routed/4's conj slot.
    findall(C, match(_Other, [',', [plunit_secret, _]], conj, C), Conjunctive),
    Conjunctive = [['Error', ['match'|_], _]].


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

%stored_atom_of_ref/3 is add_sexp_in/4 read backwards, and a reload depends on
%it telling an atom's clause reference from the compiled clauses and
%registrations a load records beside it. Both stored shapes and one negative,
%because answering for a reference that is not an atom's would send a
%registration through the removal funnel.
test(a_stored_atoms_reference_decodes_to_its_atom) :-
    Space = '&plunit_decode_ref',
    setup_call_cleanup(
        ( add_sexp(Space, [pair, a, b], ExprRef),
          add_sexp(Space, scalar, ScalarRef),
          assertz(user:plunit_not_an_atom(x), OtherRef) ),
        ( stored_atom_of_ref(ExprRef, ExprSpace, ExprAtom),
          stored_atom_of_ref(ScalarRef, ScalarSpace, ScalarAtom),
          \+ stored_atom_of_ref(OtherRef, _, _) ),
        ( clear_native_atoms(Space),
          retractall(user:plunit_not_an_atom(_)) )),
    ExprSpace-ExprAtom == Space-[pair, a, b],
    ScalarSpace-ScalarAtom == Space-scalar.

test(an_erased_reference_decodes_to_nothing) :-
    Space = '&plunit_decode_erased',
    add_sexp(Space, [gone, once], Ref),
    erase(Ref),
    \+ stored_atom_of_ref(Ref, _, _).

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

% A space may EXTEND an engine operation by writing an equation for its name,
% and taking that equation back must leave the engine's own operation where it
% was. It did not: removing the last equation asked whether any COMPILED clause
% for the name was left, the engine's builtin is not one, so the name-wide
% `fun/1` registration went with the equation and `!(get-type 1)` answered
% `(get-type 1)` unreduced for the rest of the process. Reproduced 2026-08-20
% through this file's own spaces_type_extensions cleanup, which left every
% later MeTTa-level get-type call unreduced.
:- begin_tests(builtin_survives_equation_removal).

builtin_extension_space('&plunit_builtin_survives').
builtin_extension_equation([=, ['get-type', 'plunit-bse-subject'],
                            'plunit-bse-type']).

test(removing_a_space_equation_leaves_the_builtin_registered,
     [cleanup(clear_native_atoms('&plunit_builtin_survives'))]) :-
    builtin_extension_space(Space),
    builtin_extension_equation(Equation),
    'add-atom'(Space, Equation, _),
    'remove-atom'(Space, Equation, _),
    assertion(fun('get-type')),
    process_metta_string("!(get-type 1)", Answers),
    assertion(Answers == ['Number']).

:- end_tests(builtin_survives_equation_removal).


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

test(a_duplicate_declaration_batch_is_refused_before_storage,
     [ setup(clear_native_atoms('&bt-duplicate-declaration')),
       cleanup(clear_native_atoms('&bt-duplicate-declaration')) ]) :-
    Space = '&bt-duplicate-declaration',
    Declaration = [':', 'bt-duplicate', [->, 'Number', 'Number']],
    catch(metta_add_atoms(Space, [Declaration, Declaration]), Error, true),
    assertion(Error = error(petta_duplicate_declaration(
                                Space, Declaration, Declaration), none)),
    findall(Atom, 'get-atoms'(Space, Atom), Atoms),
    assertion(Atoms == []).

% Admission gates the write itself, so a pool's batch has to meet the same
% refusal its atoms meet arriving alone. The store-only crossing used to
% write behind the admission door's back: a pool at capacity 2 held five
% atoms after a three-atom batch landed unrefused [measured 2026-08-20].
% The door is petta_admission_claim/2's guard on the general pre-add hook,
% so the refusal arrives as the hook's petta_add_refused with the judge's
% own words, not a bespoke error.
setup_batch_admission :-
    clear_native_atoms('&bt-pool'),
    metta_add_atom('&petta', [capacity, '&bt-pool', 2], _),
    petta_admission_claim('&bt-pool', '&self'),
    'add-atom'('&bt-pool', [a, 1], _),
    'add-atom'('&bt-pool', [a, 2], _).

% The claim comes off in cleanup so later tests in this process keep the
% direct write path they were written against; the guard equation comes
% out of &self so the next setup's claim rewrites it fresh.
cleanup_batch_admission :-
    metta_undeclare_hook(pre_add, '&bt-pool'),
    metta_remove_atom('&petta', [capacity, '&bt-pool', 2], _),
    (   metta_remove_atom('&self',
                          [=, ['space-admission-guard-&bt-pool', _], _], _)
    ->  true
    ;   true
    ),
    clear_native_atoms('&bt-pool').

test(a_batch_beyond_capacity_is_refused_like_lone_adds,
     [ setup(setup_batch_admission),
       cleanup(cleanup_batch_admission),
       throws(error(petta_add_refused('&bt-pool', [b, 1],
                                      ['pool-at-capacity', 2]), _)) ]) :-
    metta_add_atoms('&bt-pool', [[b, 1], [b, 2]]).

test(a_refused_batch_leaves_the_state_lone_adds_leave,
     [ setup(setup_batch_admission),
       cleanup(cleanup_batch_admission) ]) :-
    catch(metta_add_atoms('&bt-pool', [[b, 1], [b, 2]]),
          error(petta_add_refused('&bt-pool', _, ['pool-at-capacity', 2]), _),
          true),
    findall(A, 'get-atoms'('&bt-pool', A), Atoms),
    assertion(Atoms == [[a, 1], [a, 2]]).

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
    space_module('&plunit_rules', RulesModule),
    predicate_property(RulesModule:'fr-many'(_, _), number_of_clauses(Clauses)),
    assertion(Clauses == 4),
    findall(A, with_metta_module(RulesModule, reduce(['fr-many', 3], A, _)), As),
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
metta_foreign_match('&plunit_ctl', _, _) :- throw(metta_host_interrupted).
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
       throws(metta_host_interrupted) ]) :-
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

:- begin_tests(named_space_wrappers).

% Every special form that hands its goal to a HELPER predicate used to
% lose the module on the way in: the helper's findall called the goal
% back in user, so timeout, elapsed, take, top, transaction and the
% bound forms were silently unusable in ANY named space ("Unknown
% procedure" for a function the space plainly defines). The
% meta_predicate block above metta_timeout/3 is the fix; this pins it
% end to end through the loader's own named-space path.
test(wrapper_forms_run_in_named_spaces,
     [ setup(process_metta_string(
                 "(= (plunit-nsw-f $n) (+ $n 1))", _, '&plunit_nsw')),
       cleanup(( remove_sexp('&plunit_nsw', [=, ['plunit-nsw-f'|_], _]),
                 retractall(fun('plunit-nsw-f')),
                 retractall(arity('plunit-nsw-f', _)) )) ]) :-
    process_metta_string("!(timeout 30 (plunit-nsw-f 1))", [R1], '&plunit_nsw'),
    assertion(R1 == 2),
    process_metta_string("!(take 1 (plunit-nsw-f 1))", [R2], '&plunit_nsw'),
    assertion(R2 == 2),
    process_metta_string("!(inferences 100000 (plunit-nsw-f 1))", [R3],
                         '&plunit_nsw'),
    assertion(R3 == 2),
    process_metta_string(
        "!(with-pragma! ((max-inferences 100000)) (plunit-nsw-f 1))",
        [R4], '&plunit_nsw'),
    assertion(R4 == 2).

:- end_tests(named_space_wrappers).

% A space handle is a VALUE of the language rather than a bare symbol, and both
% questions about it have an answer: its metatype is Grounded and its declared
% type is SpaceType, which is upstream's own name for it
% [source: LeaTTa tests/semantics/spaces/space_identity.metta, STATUS conforms,
% whose transcript is hyperon 0.2.10 printing Grounded and SpaceType for &self,
% the same pair for a bound space, and SpaceType for a fresh (new-space) that
% nothing has been written to yet].
%
% The engine's own registry answers both, so a handle a program makes at
% runtime is covered the moment it exists rather than by naming it here.
:- begin_tests(space_handle_type).

test(the_ambient_space_is_grounded_and_typed) :-
    findall(M, 'get-metatype'('&self', M), Metatypes),
    assertion(Metatypes == ['Grounded']),
    findall(T, 'get-type'('&self', T), Types),
    assertion(Types == ['SpaceType']).

% Freshness is the case a write-registered handle would miss: `(new-space)`
% answers a space that exists, and asking its type must not be what makes it.
test(a_fresh_space_is_one_before_anything_is_written_to_it) :-
    'new-space'(Space),
    findall(M, 'get-metatype'(Space, M), Metatypes),
    assertion(Metatypes == ['Grounded']),
    findall(T, 'get-type'(Space, T), Types),
    assertion(Types == ['SpaceType']).

% Through the surface, where bind! makes the handle reachable by a name the
% reader substitutes away before the engine sees it.
test(a_bound_space_answers_the_same_through_its_token,
     [cleanup(retractall(metta_token('&plunit-handle-space', _)))]) :-
    process_metta_string("!(bind! &plunit-handle-space (new-space))", _),
    process_metta_string("!(add-atom &plunit-handle-space (handle-canary 1))",
                         _),
    process_metta_string("!(get-metatype &plunit-handle-space)", Metatypes),
    assertion(Metatypes == ['Grounded']),
    process_metta_string("!(get-type &plunit-handle-space)", Types),
    assertion(Types == ['SpaceType']).

% A symbol that names no space is untouched by any of it, which is the half
% that keeps the answer a fact about the handle rather than about the spelling.
test(a_symbol_that_names_no_space_is_unchanged) :-
    findall(M, 'get-metatype'('plunit-handle-not-a-space', M), Metatypes),
    assertion(Metatypes == ['Symbol']),
    findall(T, 'get-type'('plunit-handle-not-a-space', T), Types),
    assertion(Types == ['%Undefined%']).

:- end_tests(space_handle_type).

% A first argument that is not a space is refused BY NAME, with upstream's own
% text and the call that failed as the subject, and as an ANSWER rather than a
% throw so a collapse can hold it
% [source: LeaTTa tests/semantics/spaces/add_atom.metta, add_atoms, add_reduct,
% add_reducts, get_atoms and match, all six STATUS conforms and all six
% transcripts of hyperon 0.2.10; the texts are upstream's own `ok_or` strings
% at space.rs:143, :172 and :199]. The message is a STRING here and prints
% quoted, where the arbiter's writer prints the same text bare; the corpus
% comparison drops quotes on both sides and says so at
% tests/conformance/leatta.py, so the two records differ only in that.
%
% A space here is a NAME, so what is refused is a name that is not one: the
% rule is is-space/2's, an atom beginning with `&`, which evalc/3 has enforced
% at its own door since it was written and which bindings/python/petta/space.py enforces
% at the library's. The three doors below were the ones that did not, so
% `(add-atom not-a-space (bad add))` silently made a space called
% `not-a-space` while `(is-space not-a-space)` answered False in the same
% program.
:- begin_tests(space_argument_refusals).

refused_space_call("!(collapse (add-atom not-a-space (bad add)))",
                   "((Error (add-atom not-a-space (bad add)) \"add-atom expects a space as the first argument\"))").
refused_space_call("!(collapse (add-atoms not-a-space (bad batch)))",
                   "((Error (add-atom not-a-space bad) \"add-atom expects a space as the first argument\"))").
refused_space_call("!(collapse (get-atoms not-a-space))",
                   "((Error (get-atoms not-a-space) \"get-atoms expects a space as its argument\"))").
refused_space_call("!(collapse (match not-a-space (q a) a))",
                   "((Error (match not-a-space (q a) a) \"match expects a space as the first argument\"))").
%The reducing forms delegate the check to add-atom, so the error names add-atom
%and the REDUCED atom, which is where the write would have happened.
refused_space_call("!(collapse (add-reduct not-a-space (+ 7000 1)))",
                   "((Error (add-atom not-a-space 7001) \"add-atom expects a space as the first argument\"))").
%The scoped type lookup is a space door too, and the arbiter refuses it in the
%same shape [source: LeaTTa tests/semantics/spaces/get_type_space.metta and the
%four get_doc files, whose last line is this refusal reached through it].
refused_space_call("!(collapse (get-type-space not-a-space scoped-atom))",
                   "((Error (get-type-space not-a-space scoped-atom) \"get-type-space expects a space as the first argument\"))").

test(a_name_that_is_not_a_space_is_refused_by_name,
     [forall(refused_space_call(Source, Expected))]) :-
    process_metta_string(Source, [Answer]),
    swrite(Answer, Text),
    assertion(Text == Expected).

% The other half, and the reason the rule is the prefix rather than the
% registry: a space is still CREATED by writing to it, so a name nothing has
% bound yet is a space the moment a program uses it as one.
test(a_fresh_ampersand_name_is_still_created_by_writing_to_it,
     [cleanup(clear_native_atoms('&plunit-fresh-write'))]) :-
    process_metta_string("!(add-atom &plunit-fresh-write (canary 1))", Added),
    assertion(Added == [[]]),
    process_metta_string("!(match &plunit-fresh-write (canary $x) $x)", Found),
    assertion(Found == [1]).

% A space that exists and holds nothing answers nothing, which is not the same
% as a name that is not a space at all.
test(an_empty_space_answers_nothing_rather_than_refusing,
     [cleanup(clear_native_atoms('&plunit-empty-read'))]) :-
    process_metta_string("!(add-atom &plunit-empty-read (canary 1))", _),
    process_metta_string("!(remove-atom &plunit-empty-read (canary 1))", _),
    process_metta_string("!(collapse (get-atoms &plunit-empty-read))", Atoms),
    assertion(Atoms == [[]]),
    process_metta_string("!(collapse (match &plunit-empty-read (canary $x) $x))",
                         Found),
    assertion(Found == [[]]).

:- end_tests(space_argument_refusals).

% The two storage services a host talks to a space through, and their
% verdicts: metta_host_remove_reported/3 answers whether anything went
% (probed before the mutation), and metta_host_stored/2 enumerates stored
% atoms unifying a pattern without a whole-space walk for an indexed head.
:- begin_tests(spaces_host_storage_services).

test(a_reporting_removal_says_whether_anything_went,
     [ cleanup(clear_native_atoms('&plunit-host-remove')) ]) :-
    add_sexp('&plunit-host-remove', [stored, thing]),
    metta_host_remove_reported('&plunit-host-remove', [stored, thing], First),
    First == true,
    metta_host_remove_reported('&plunit-host-remove', [stored, thing], Again),
    Again == false,
    metta_host_remove_reported('&plunit-host-remove', [never, there], Never),
    Never == false.

test(stored_enumeration_is_pattern_directed,
     [ cleanup(clear_native_atoms('&plunit-host-stored')) ]) :-
    add_sexp('&plunit-host-stored', [edge, a, b]),
    add_sexp('&plunit-host-stored', [edge, b, c]),
    add_sexp('&plunit-host-stored', [node, a]),
    findall(X-Y, metta_host_stored('&plunit-host-stored', [edge, X, Y]),
            Edges),
    msort(Edges, [a-b, b-c]),
    \+ metta_host_stored('&plunit-host-stored', [edge, c, _]).

:- end_tests(spaces_host_storage_services).

% The explain mirror: what the seam already decided for a query, answered
% to a host as one term report so no binding re-derives routing precedence.
:- begin_tests(spaces_host_explain).

test(a_stored_space_explains_as_stored) :-
    metta_host_explain_match('&self', [[edge, _, _]], Report),
    Report == explain(stored, [], [], []).

test(a_bare_foreign_space_explains_unclaimed_inexact) :-
    metta_host_explain_match('&plunit_cycle_foreign', [[fact, _, _]], Report),
    Report = explain(foreign, [class(Class, Origin)], Claimed, Rest),
    Class == inexact,
    Origin == unclaimed,
    Claimed == [],
    Rest == [0].

:- end_tests(spaces_host_explain).

% The mirror of a_space_name_is_refused_where_a_module_is_asked: the
% space-name doors refuse a module argument by name instead of failing
% like a miss, so a wrong-argument call can never read as absence.
:- begin_tests(spaces_module_where_name_wanted).

test(test_a_module_where_a_space_name_is_wanted_refuses_by_name,
     [ throws(error(type_error(metta_space_name, _), _)) ]) :-
    metta_self_module(Module),
    metta_remove_atom(Module, [never, there], _).

test(the_read_door_refuses_the_same_way,
     [ throws(error(type_error(metta_space_name, _), _)) ]) :-
    metta_self_module(Module),
    get_native_atom(Module, _).

test(the_published_stored_door_inherits_the_refusal,
     [ throws(error(type_error(metta_space_name, _), _)) ]) :-
    metta_self_module(Module),
    metta_host_stored(Module, _).

:- end_tests(spaces_module_where_name_wanted).


%The synthetic foreign space the count-refusal test names; a file-level
%clause, because a fact inside the unit lands in plunit's unit module
%where the engine's multifile seam never sees it.
metta_foreign_space('&sac-foreign').

:- begin_tests(spaces_atom_count).

% The count is the store's own clause bookkeeping, so it must agree with
% enumeration over both stored shapes and cost property reads, not a walk.
test(counts_expressions_and_scalars_across_arities,
     [ cleanup(( remove_sexp('&sac-pool', [rel, _, _]),
                 remove_sexp('&sac-pool', [tag, _]),
                 remove_sexp('&sac-pool', scalar_probe) )) ]) :-
    'space-atom-count'('&sac-pool', Before), Before == 0,
    add_sexp('&sac-pool', [rel, a, b]),
    add_sexp('&sac-pool', [rel, a, c]),
    add_sexp('&sac-pool', [tag, x]),
    add_sexp('&sac-pool', scalar_probe),
    'space-atom-count'('&sac-pool', Count), Count == 4,
    remove_sexp('&sac-pool', [rel, a, b]),
    'space-atom-count'('&sac-pool', After), After == 3.

test(a_never_written_space_holds_nothing) :-
    'space-atom-count'('&sac-virgin', N), N == 0.

test(an_unbound_space_is_refused,
     [ throws(error(petta_unbound_input('space-atom-count', 1), _)) ]) :-
    'space-atom-count'(_, _).

test(a_non_space_is_refused,
     [ throws(error(type_error('SpaceType', 7), _)) ]) :-
    'space-atom-count'(7, _).

test(a_foreign_space_has_no_native_count,
     [ throws(error(petta_foreign_space_count('&sac-foreign'), _)) ]) :-
    'space-atom-count'('&sac-foreign', _).

:- end_tests(spaces_atom_count).

% Kernel vocabulary: one indexed probe for membership, the question a
% set-semantics rule asks per add. Unification is the store's own
% reading, so a pattern with variables asks "anything of this shape".
:- begin_tests(spaces_contains).

test(present_absent_and_scalar,
     [ cleanup(( remove_sexp('&sco-pool', [rel, _, _]),
                 remove_sexp('&sco-pool', scalar_probe) )) ]) :-
    add_sexp('&sco-pool', [rel, a, b]),
    add_sexp('&sco-pool', scalar_probe),
    'space-contains'('&sco-pool', [rel, a, b], R1), R1 == true,
    'space-contains'('&sco-pool', scalar_probe, R2), R2 == true,
    'space-contains'('&sco-pool', [rel, a, c], R3), R3 == false,
    'space-contains'('&sco-pool', [rel, a, _], R4), R4 == true.

test(a_never_written_space_contains_nothing) :-
    'space-contains'('&sco-virgin', [x], R), R == false.

test(an_unbound_space_is_refused,
     [ throws(error(petta_unbound_input('space-contains', 1), _)) ]) :-
    'space-contains'(_, [x], _).

test(an_unbound_atom_is_refused,
     [ throws(error(petta_unbound_input('space-contains', 2), _)) ]) :-
    'space-contains'('&sco-pool', _, _).

test(a_non_space_is_refused,
     [ throws(error(type_error('SpaceType', 7), _)) ]) :-
    'space-contains'(7, [x], _).

:- end_tests(spaces_contains).

:- begin_tests(spaces_inheritance).

release_inheritance_pair(Child, Parent) :-
    catch(metta_release_space(Child), _, true),
    catch(metta_release_space(Parent), _, true).

test(reads_are_child_first_and_conjunctions_join_across_layers,
     [ cleanup(release_inheritance_pair('&inh-child', '&inh-parent')) ]) :-
    add_sexp('&inh-parent', [edge, a, b]),
    add_sexp('&inh-parent', [copy, same]),
    add_sexp('&inh-parent', [layer, parent]),
    metta_declare_space_parent('&inh-child', '&inh-parent'),
    add_sexp('&inh-child', [edge, b, c]),
    add_sexp('&inh-child', [copy, same]),
    add_sexp('&inh-child', [layer, child]),
    findall(A, 'get-atoms'('&inh-child', A), Atoms),
    msort(Atoms, SortedAtoms),
    msort([[edge, b, c], [copy, same], [layer, child],
           [edge, a, b], [copy, same], [layer, parent]], SortedExpected),
    assertion(SortedAtoms == SortedExpected),
    findall(Layer,
            match('&inh-child', [layer, Layer], Layer, _),
            Layers),
    assertion(Layers == [child, parent]),
    findall(X-Z,
            match('&inh-child', [',', [edge, X, Y], [edge, Y, Z]],
                  X-Z, _),
            Rows),
    assertion(Rows == [a-c]),
    space_atom_count('&inh-child', OwnCount),
    assertion(OwnCount == 3),
    'space-contains'('&inh-child', [edge, a, b], Contains),
    assertion(Contains == true).

test(removing_a_variable_and_clearing_touch_only_the_child,
     [ cleanup(release_inheritance_pair('&inh-mutate-child',
                                        '&inh-mutate-parent')) ]) :-
    add_sexp('&inh-mutate-parent', [kept, parent]),
    metta_declare_space_parent('&inh-mutate-child', '&inh-mutate-parent'),
    metta_remove_atom('&inh-mutate-child', _, RemovedEmpty),
    assertion(RemovedEmpty == false),
    once(get_native_atom('&inh-mutate-parent', [kept, parent])),
    add_sexp('&inh-mutate-child', [gone, child]),
    metta_host_clear_space('&inh-mutate-child'),
    assertion(\+ get_native_atom('&inh-mutate-child', _)),
    once(get_native_atom('&inh-mutate-parent', [kept, parent])).

test(the_surface_constructor_returns_the_child_and_is_idempotent,
     [ cleanup(release_inheritance_pair('&inh-surface-child',
                                        '&inh-surface-parent')) ]) :-
    process_metta_string(
        "!(new-space &inh-surface-child (inherits &inh-surface-parent))",
        First),
    process_metta_string(
        "!(new-space &inh-surface-child (inherits &inh-surface-parent))",
        Second),
    assertion(First == ['&inh-surface-child']),
    assertion(Second == ['&inh-surface-child']),
    once(petta_contract_fact([inherits, '&inh-surface-child',
                              '&inh-surface-parent'])).

test(a_different_parent_is_refused,
     [ cleanup(( catch(metta_release_space('&inh-conflict-child'), _, true),
                 catch(metta_release_space('&inh-conflict-first'), _, true),
                 catch(metta_release_space('&inh-conflict-second'), _, true) )),
       throws(error(petta_space_parent_conflict('&inh-conflict-child',
                                                '&inh-conflict-first',
                                                '&inh-conflict-second'), _)) ]) :-
    metta_declare_space_parent('&inh-conflict-child', '&inh-conflict-first'),
    metta_declare_space_parent('&inh-conflict-child', '&inh-conflict-second').

test(a_cycle_is_named_before_the_already_used_refusal,
     [ cleanup(release_inheritance_pair('&inh-cycle-a', '&inh-cycle-b')),
       throws(error(petta_space_parent_cycle('&inh-cycle-b',
                                             '&inh-cycle-a'), _)) ]) :-
    metta_declare_space_parent('&inh-cycle-a', '&inh-cycle-b'),
    metta_declare_space_parent('&inh-cycle-b', '&inh-cycle-a').

test(a_parent_declared_after_first_use_is_refused,
     [ cleanup(release_inheritance_pair('&inh-used-child',
                                        '&inh-used-parent')),
       throws(error(petta_space_parent_after_use('&inh-used-child'), _)) ]) :-
    add_sexp('&inh-used-child', [already, used]),
    metta_declare_space_parent('&inh-used-child', '&inh-used-parent').

test(an_outer_transaction_rolls_back_the_index_and_contract) :-
    catch(transaction((
              metta_declare_space_parent('&inh-rollback-child',
                                         '&inh-rollback-parent'),
              throw(rollback_probe))),
          rollback_probe,
          true),
    assertion(\+ space_parent('&inh-rollback-child', _)),
    assertion(\+ petta_contract_fact([inherits, '&inh-rollback-child', _])),
    assertion(\+ metta_exec_module_known('&inh-rollback-child', _)),
    assertion(\+ metta_exec_module_parent(_, _)),
    assertion(\+ native_storage_module_cache('&inh-rollback-child', _)).

:- end_tests(spaces_inheritance).

:- begin_tests(spaces_parametric).

parametric_names([
    [cache, '&param-kb', 100],
    [cache, '&param-kb', 100.0],
    [cache, "&param-kb", 100],
    [cache, [nested, '&param-kb'], 100]
]).

release_parametric_spaces :-
    parametric_names(Names),
    forall(member(Name, Names), catch(metta_release_space(Name), _, true)),
    forall(member(Name, [[cache, '&param-left', 8],
                         [cache, '&param-right', 4],
                         [cache, '&param-surface', 7],
                         [cache, '&param-release', 5],
                         [cache, '&param-rollback', 3]]),
           catch(metta_release_space(Name), _, true)).

parametric_cache_counts(Parametric, Storage, Exec) :-
    aggregate_all(count, space_parametric(_), Parametric),
    aggregate_all(count, native_storage_module_cache(_, _), Storage),
    aggregate_all(count, metta_exec_module_known(_, _), Exec).

test(canonical_modules_are_distinct_and_invert_exactly,
     [ cleanup(release_parametric_spaces) ]) :-
    parametric_names(Names),
    maplist(metta_declare_parametric_space, Names),
    maplist(space_module, Names, ExecModules),
    maplist(native_storage_module, Names, StorageModules),
    sort(ExecModules, UniqueExec),
    sort(StorageModules, UniqueStorage),
    length(Names, Count),
    assertion(same_length(UniqueExec, Names)),
    assertion(same_length(UniqueStorage, Names)),
    forall(nth1(Index, Names, Name),
           ( nth1(Index, ExecModules, Exec),
             assertion(metta_module_space(Exec, Name)),
             assertion(space_parametric(Name)),
             assertion(petta_space_operand(Name)) )),
    assertion(Count == 4).

test(storage_equations_types_and_mutation_are_instance_local,
     [ cleanup(release_parametric_spaces) ]) :-
    Left = [cache, '&param-left', 8],
    Right = [cache, '&param-right', 4],
    metta_declare_parametric_space(Left),
    metta_declare_parametric_space(Right),
    add_sexp(Left, [edge, a, b], LeftRef),
    add_sexp(Left, [edge, b, c]),
    add_sexp(Left, scalar_left),
    add_sexp(Right, [edge, x, y]),
    add_sexp(Right, scalar_right),
    metta_add_atom(Left, [':', local_token, 'LeftToken'], true),
    metta_add_atom(Right, [':', local_token, 'RightToken'], true),
    metta_add_atom(Left, [=, [param_view], ['context-space']], true),
    metta_add_atom(Right, [=, [param_view], ['context-space']], true),
    once(stored_atom_of_ref(LeftRef, RefSpace, RefAtom)),
    assertion(RefSpace == Left),
    assertion(RefAtom == [edge, a, b]),
    findall(X-Z,
            match(Left, [',', [edge, X, Y], [edge, Y, Z]], X-Z, _),
            Rows),
    assertion(Rows == [a-c]),
    assertion(\+ match(Right, [edge, a, _], _, _)),
    space_module(Left, LeftModule),
    space_module(Right, RightModule),
    once(eval_metta_in_module(LeftModule, [param_view], LeftView)),
    once(eval_metta_in_module(RightModule, [param_view], RightView)),
    assertion(LeftView == Left),
    assertion(RightView == Right),
    once(type_declaration_in(LeftModule, local_token, LeftType)),
    once(type_declaration_in(RightModule, local_token, RightType)),
    assertion(LeftType == 'LeftToken'),
    assertion(RightType == 'RightToken'),
    metta_remove_atom(Left, [edge, a, b], Removed),
    assertion(Removed == true),
    assertion(\+ get_native_atom(Left, [edge, a, b])),
    assertion(get_native_atom(Right, [edge, x, y])),
    clear_native_atoms(Left),
    assertion(\+ get_native_atom(Left, _)),
    assertion(get_native_atom(Right, scalar_right)).

test(the_surface_constructor_is_idempotent_and_reflected_once,
     [ cleanup(release_parametric_spaces) ]) :-
    process_metta_string("!(new-space (cache &param-surface 7))", First),
    process_metta_string("!(new-space (cache &param-surface 7))", Second),
    Name = [cache, '&param-surface', 7],
    assertion(First == [Name]),
    assertion(Second == [Name]),
    findall(true, petta_contract_fact([parametric, Name]), Rows),
    assertion(Rows == [true]).

test(release_clears_the_registry_storage_and_execution_life,
     [ cleanup(release_parametric_spaces) ]) :-
    Name = [cache, '&param-release', 5],
    metta_declare_parametric_space(Name),
    add_sexp(Name, [entry, live]),
    native_storage_module_ready(Name, Storage),
    space_module(Name, Exec),
    metta_release_space(Name),
    assertion(\+ space_parametric(Name)),
    assertion(\+ petta_contract_fact([parametric, Name])),
    assertion(\+ native_storage_module_cache(Name, _)),
    assertion(\+ metta_exec_module_known(Name, _)),
    metta_declare_parametric_space(Name),
    assertion(native_storage_module_ready(Name, Storage)),
    assertion(space_module(Name, Exec)),
    assertion(\+ get_native_atom(Name, _)).

test(invalid_names_are_rejected_before_any_cache_is_published) :-
    parametric_cache_counts(P0, S0, E0),
    catch(metta_declare_parametric_space([]),
          error(domain_error(parametric_space_name, []), _), Empty = refused),
    catch(metta_declare_parametric_space([[cache], '&bad', 1]),
          error(domain_error(parametric_space_name, _), _), Head = refused),
    catch(metta_declare_parametric_space([cache, _Unbound, 1]),
          error(instantiation_error, _), Ground = refused),
    Cyclic = [cache|Cyclic],
    catch(metta_declare_parametric_space(Cyclic),
          error(type_error(acyclic_term, _), _), Finite = refused),
    assertion(Empty == refused),
    assertion(Head == refused),
    assertion(Ground == refused),
    assertion(Finite == refused),
    parametric_cache_counts(P1, S1, E1),
    assertion(P1-S1-E1 == P0-S0-E0).

test(an_outer_transaction_rolls_back_every_parametric_index) :-
    Name = [cache, '&param-rollback', 3],
    catch(transaction(( metta_declare_parametric_space(Name),
                        throw(rollback_probe) )),
          rollback_probe,
          true),
    assertion(\+ space_parametric(Name)),
    assertion(\+ petta_contract_fact([parametric, Name])),
    assertion(\+ native_storage_module_cache(Name, _)),
    assertion(\+ metta_exec_module_known(Name, _)).

:- end_tests(spaces_parametric).

:- begin_tests(spaces_restricted_modules).

release_restricted_space(Space) :- catch(metta_release_space(Space), _, true).

test(a_restricted_space_bases_on_the_curated_module,
     [ cleanup(release_restricted_space('&restricted-topology')) ]) :-
    metta_declare_restricted_space('&restricted-topology', []),
    metta_declare_restricted_space('&restricted-topology', []),
    space_module('&restricted-topology', Module),
    restricted_core_module(Core),
    assertion(import_module(Module, Core)),
    assertion(current_predicate(Core:'+'/3)).

test(a_different_grant_set_is_refused,
     [ cleanup(release_restricted_space('&restricted-conflict')),
       throws(error(petta_space_restriction_conflict('&restricted-conflict',
                                                      [file], [process]), _)) ]) :-
    metta_declare_restricted_space('&restricted-conflict', [file]),
    metta_declare_restricted_space('&restricted-conflict', [process]).

test(a_missing_capability_names_the_space_operation_and_capability,
     [ cleanup(release_restricted_space('&restricted-refusal')),
       throws(error(petta_space_capability_required('&restricted-refusal',
                                                     exists_file, file), _)) ]) :-
    metta_declare_restricted_space('&restricted-refusal', []),
    space_module('&restricted-refusal', Module),
    with_metta_module(Module,
                      metta_require_current_capability(exists_file, file)).

test(an_explicit_grant_publishes_only_its_capability,
     [ cleanup(release_restricted_space('&restricted-file')) ]) :-
    metta_declare_restricted_space('&restricted-file', [file]),
    space_module('&restricted-file', Module),
    with_metta_module(Module,
                      metta_require_current_capability(exists_file, file)),
    catch(with_metta_module(Module,
                            metta_require_current_capability(argv, process)),
          error(petta_space_capability_required('&restricted-file', argv,
                                                 process), _),
          Refused = true),
    assertion(Refused == true).

test(the_sandbox_accepts_a_pure_raw_goal_and_rejects_file_access,
     [ cleanup(release_restricted_space('&restricted-sandbox')) ]) :-
    metta_declare_restricted_space('&restricted-sandbox', []),
    space_module('&restricted-sandbox', Module),
    with_metta_module(Module, metta_require_safe_goal(atom(a))),
    catch(with_metta_module(Module,
                            metta_require_safe_goal(open('/tmp/nope', read,
                                                         _))),
          error(petta_space_capability_required('&restricted-sandbox', open,
                                                 file), _),
          Refused = true),
    assertion(Refused == true).

test(removing_an_ordinary_shadow_cannot_unpin_restricted_dispatch,
     [ cleanup(( clear_native_atoms('&restricted-shadow-owner'),
                 release_restricted_space('&restricted-after-shadow') )) ]) :-
    metta_declare_restricted_space('&restricted-after-shadow', []),
    add_sexp('&restricted-shadow-owner',
             [=, [exists_file, Path], Path]),
    metta_remove_atom('&restricted-shadow-owner',
                      [=, [exists_file, _], _], true),
    assertion(fun_scoped(exists_file)),
    space_module('&restricted-after-shadow', Module),
    catch(with_metta_module(Module,
                            reduce([exists_file, '/tmp'], _, _)),
          error(petta_space_capability_required('&restricted-after-shadow',
                                                 exists_file, file), _),
          Refused = true),
    assertion(Refused == true).

test(a_failed_outer_transaction_leaves_no_restriction) :-
    catch(transaction((
              metta_declare_restricted_space('&restricted-rollback', [file]),
              throw(rollback_probe))),
          rollback_probe,
          true),
    assertion(\+ space_restricted('&restricted-rollback', _)),
    assertion(\+ space_grant('&restricted-rollback', _)),
    assertion(\+ petta_contract_fact([restricted, '&restricted-rollback'])),
    assertion(\+ metta_exec_module_known('&restricted-rollback', _)),
    assertion(\+ native_storage_module_cache('&restricted-rollback', _)).

:- end_tests(spaces_restricted_modules).
