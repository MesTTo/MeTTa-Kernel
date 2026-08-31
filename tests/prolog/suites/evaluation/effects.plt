% Purpose: prove the engine's five-rank effect lattice, compatibility
%   projection, and reflected plan join.
% Assumes: engine/metta.pl has initialized the &metta catalog and its native
%   storage.
% Guarantees: rank, join, composition, canonical operation reflection,
%   fail-closed plans, complete embedded-operation coverage, native effect
%   floors, cache-purity projection, and deprecation explanation agree.
% [tested: tests/prolog/effects.plt; commit=173eeed021beb360b5e5f9f8461889e27190affc]

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

% A stand-in backend, declared exactly the way extensions/mork's bridge declares
% its own: one load-time multifile clause naming the builtin AND its effect
% class, then the same registration the engine runs over those declarations.
% It is what lets a_backend_declares_the_effect_of_the_builtin_it_registers
% fail in the plain configuration too, instead of passing vacuously wherever
% no backend artefact is built.
:- multifile seam:extension_builtin/2.
seam:extension_builtin('planted-backend-write', writesState).
:- register_builtin_fun('planted-backend-write').

% A bridge's own dispatch goal, planted the way the backend builtin above is.
% The engine knows no bridge by name and asks seam:effect_operation_name/3 to
% recover the operation behind one [source: engine/ext_points.pl,
% effect_operation_name/3]. No bridge is loaded in the plain configuration, so
% the fail-closed rule -- a recovered operation with no (effect ...) row is
% oracleIO -- has nothing to fire on unless the suite supplies one.
:- multifile seam:effect_operation_name/3.
seam:effect_operation_name(plunit_unclassified_bridge_dispatch(_, _),
                           'plunit-unclassified-bridge-op', 2).

effect_test_clear(Name) :-
    (   metta_contract_fact([effect, Name, Declared])
    ->  'remove-atom'('&metta', [effect, Name, Declared], _),
        effect_test_clear(Name)
    ;   metta_engine_module(Engine),
        retractall(Engine:metta_host_pure_operation(Name))
    ).

effect_test_add(Name, Class) :-
    'add-atom'('&metta', [effect, Name, Class], _).

effect_test_host_pure_add(Name) :-
    metta_engine_module(Engine),
    assertz(Engine:metta_host_pure_operation(Name)).

effect_test_interpreter_profile(
    pureStructural,
    [chain, 'cons-atom', 'decons-atom', function]).
effect_test_interpreter_profile(
    readOnlyLookup,
    ['context-space', 'get-metatype', 'get-state', 'get-atoms',
     'module-tree!', 'loaded-mods!',
     'skel-swap-pair-native', 'fuzzy-match-space',
     'fuzzy-match-context']).
effect_test_interpreter_profile(
    nondeterministicReadOnly,
    [unify, 'unify%', 'superpose-bind']).
effect_test_interpreter_profile(
    writesState,
    [eval, evalc, 'collapse-bind', metta, 'metta-thread', capture,
     'pragma!', match, 'match%', 'get-type', 'get-type-space',
     '_new-state', 'change-state!', 'new-space', 'fork-space', 'add-atom', 'remove-atom', 'bind!',
     'module-space-no-deps', 'print-mods!', 'println!', 'trace!', sealed]).
effect_test_interpreter_profile(
    oracleIO,
    ['git-import!', 'git-module!', 'import!', 'import-into!',
     'import-item!', include, 'mod-space!']).

:- begin_tests(effects_lattice).

test(the_five_effect_classes_are_ranked_in_catalog_order) :-
    Classes = [pureStructural,
               readOnlyLookup,
               nondeterministicReadOnly,
               writesState,
               oracleIO],
    assertion(metta_contract_fact([vocabulary, 'effect-class'|Classes])),
    findall(Class-Rank,
            ( member(Class, Classes), metta_effect_rank(Class, Rank) ),
            Ranked),
    assertion(Ranked == [pureStructural-0,
                         readOnlyLookup-1,
                         nondeterministicReadOnly-2,
                         writesState-3,
                         oracleIO-4]),
    findall(Class-Rank, metta_effect_rank(Class, Rank), Enumerated),
    assertion(Enumerated == Ranked).

test(legacy_effect_spellings_map_but_cannot_enter_the_canonical_catalog) :-
    assertion(metta_effect_rank(immutable, 0)),
    assertion(metta_effect_rank(stable, 1)),
    assertion(metta_effect_rank(volatile, 4)),
    forall(member(Legacy, [immutable, stable, volatile]),
           ( catch(( effect_test_add('effect-legacy-refused', Legacy),
                     Refused = none ),
                   error(metta_declaration_malformed(_, 2,
                                                     ['one-of', 'effect-class']),
                         _),
                   Refused = Legacy),
             assertion(Refused == Legacy) )),
    assertion(\+ metta_contract_fact([effect, 'effect-legacy-refused', _])).

test(effect_join_and_compose_choose_the_strongest_member) :-
    assertion(metta_effect_compose([], pureStructural)),
    assertion(metta_effect_join(readOnlyLookup,
                                nondeterministicReadOnly,
                                nondeterministicReadOnly)),
    assertion(metta_effect_join(writesState,
                                nondeterministicReadOnly,
                                writesState)),
    assertion(metta_effect_join(volatile, readOnlyLookup, oracleIO)),
    assertion(metta_effect_compose([pureStructural,
                                    nondeterministicReadOnly,
                                    readOnlyLookup,
                                    writesState],
                                   writesState)),
    Classes = [pureStructural,
               readOnlyLookup,
               nondeterministicReadOnly,
               writesState,
               oracleIO],
    forall(member(Class, Classes),
           ( metta_effect_join(Class, Class, Idempotent),
             assertion(Idempotent == Class),
             metta_effect_join(pureStructural, Class, Identity),
             assertion(Identity == Class) )),
    forall(( member(Left, Classes), member(Right, Classes) ),
           ( metta_effect_join(Left, Right, Joined),
             metta_effect_join(Right, Left, Reverse),
             assertion(Joined == Reverse) )),
    forall(( member(A, Classes), member(B, Classes), member(C, Classes) ),
           ( metta_effect_join(A, B, AB),
             metta_effect_join(AB, C, LeftAssociated),
             metta_effect_join(B, C, BC),
             metta_effect_join(A, BC, RightAssociated),
             assertion(LeftAssociated == RightAssociated) )).

test(every_embedded_operation_has_exactly_one_reviewed_effect_profile) :-
    findall(Name, translator:embedded_operation_head(Name), Embedded0),
    sort(Embedded0, Embedded),
    findall(Name,
            ( effect_test_interpreter_profile(_, Names), member(Name, Names) ),
            Profile0),
    sort(Profile0, Profile),
    assertion(Profile == Embedded),
    forall(( effect_test_interpreter_profile(Expected, Names),
             member(Name, Names) ),
           ( findall(Effect, metta_operation_effect(Name, Effect), Effects),
             assertion(Effects == [Expected]) )),
    assertion(metta_operation_effect('get-deps', readOnlyLookup)).

test(every_translator_special_form_has_a_canonical_effect_profile) :-
    findall(Name, translator:metta_special_form_head(Name), Names0),
    sort(Names0, Names),
    forall(member(Name, Names),
           ( findall(Effect, metta_operation_effect(Name, Effect), Effects),
             assertion(Effects = [_]),
             Effects = [Effect],
             assertion(metta_effect_rank(Effect, _)) )),
    assertion(metta_operation_effect(elapsed, oracleIO)),
    assertion(metta_operation_effect(timeout, oracleIO)),
    assertion(metta_operation_effect(annotation, readOnlyLookup)),
    assertion(metta_operation_effect(explain, readOnlyLookup)),
    assertion(metta_operation_effect(top, readOnlyLookup)).

% The other half of the same contract: the engine READS the classification a
% backend registers instead of falling to its own floor. Planted against a
% name no tree holds, so it says the same thing in the pure-kernel and the
% loaded-seat configuration rather than passing vacuously wherever MORK is
% absent, and the
% planted class is writesState so a resolution that ignored the seam would
% answer the oracleIO floor and fail loudly.
% The plant arrives the way a real backend's declaration does, as a load-time
% multifile clause rather than an assertz: the seam is multifile and NOT
% dynamic, which is itself part of the contract (a backend declares at load,
% and nothing can install a builtin's effect class while a program runs).
test(a_backend_declares_the_effect_of_the_builtin_it_registers) :-
    assertion(metta_operation_effect('planted-backend-write', writesState)),
    assertion(\+ metta_operation_effect('planted-backend-write', oracleIO)).

test(every_native_builtin_has_exactly_one_reviewed_effect_profile) :-
    findall(Name,
            ( builtin_fun(Name),
              \+ metta_semantic_effect(Name, _),
              \+ metta_builtin_effect_override(Name, _),
              % An extension's builtin is reviewed by that extension, in the same
              % fact that registers it. Without this the test asked the engine
              % to have reviewed a predicate it does not ship and cannot name:
              % under `-- extensions` it read
              % ['mm2-exec','mork-add-atoms','mork-flush'].
              \+ seam:extension_builtin(Name, _),
              \+ metta_builtin_structural(Name) ),
            Unreviewed0),
    sort(Unreviewed0, Unreviewed),
    assertion(Unreviewed == []),
    forall(builtin_fun(Name),
           ( findall(Effect, metta_operation_effect(Name, Effect), Effects),
             assertion(Effects = [_]),
             Effects = [Effect],
             assertion(metta_effect_rank(Effect, _)) )),
    forall(member(Name,
                  ['Predicate', 'atom-subst', 'format-args',
                   'noreduce-eq', 'pretty-atom', 'sort-strings', throw]),
           assertion(metta_operation_effect(Name, pureStructural))),
    assertion(metta_operation_effect('residual-goals', readOnlyLookup)),
    assertion(metta_operation_effect(unique,
                                     nondeterministicReadOnly)),
    assertion(metta_operation_effect(assertaPredicate, writesState)),
    assertion(metta_operation_effect(callPredicate, oracleIO)).

test(native_effect_profiles_are_lower_bounds_on_catalog_declarations,
     [ cleanup(( effect_test_clear('random-int'),
                 effect_test_clear('add-atom') )) ]) :-
    effect_test_add('random-int', pureStructural),
    effect_test_add('add-atom', pureStructural),
    assertion(metta_operation_effect('random-int', oracleIO)),
    assertion(metta_operation_effect('add-atom', writesState)).

test(lowered_semantic_groundings_keep_their_observable_cardinality) :-
    forall(member(Name,
                  [empty, hyperpose, 'near-match', superpose,
                   'superpose-bind', unify, 'unify%']),
           assertion(metta_operation_effect(
               Name, nondeterministicReadOnly))).

test(operation_effect_reflection_is_canonical_and_fail_closed,
    [ cleanup(( effect_test_clear('effect-reflected'),
                 effect_test_clear('effect-unclassified') )) ]) :-
    assertion(\+ metta_operation_effect('effect-unclassified', _)),
    effect_test_add('effect-reflected', pureStructural),
    effect_test_add('effect-reflected', writesState),
    assertion(metta_operation_effect('effect-reflected', writesState)),
    metta_explain(['effect-reflected'], Explanation),
    findall(Effect, member([effect, Effect], Explanation), EffectRows),
    assertion(EffectRows == [writesState]).

test(a_deprecation_row_drives_lookup_and_explanation,
     [ cleanup(metta_remove_atom('&metta',
                                 [deprecated, 'old-effect', '0.2.0',
                                  [use, 'new-effect']], _)) ]) :-
    add_sexp('&metta',
             [deprecated, 'old-effect', '0.2.0', [use, 'new-effect']], _),
    assertion(metta_deprecation('old-effect', '0.2.0', [use, 'new-effect'])),
    metta_explain(['old-effect', value], Explanation),
    assertion(member([deprecated, '0.2.0', [use, 'new-effect']], Explanation)).

test(an_operation_plan_joins_reflected_members_and_refuses_an_unknown_one,
     [ cleanup(( effect_test_clear('effect-plan-pure'),
                 effect_test_clear('effect-plan-read'),
                 effect_test_clear('effect-plan-write') )) ]) :-
    effect_test_add('effect-plan-pure', pureStructural),
    effect_test_add('effect-plan-read', nondeterministicReadOnly),
    effect_test_add('effect-plan-write', writesState),
    assertion(metta_operation_plan_effect([], pureStructural)),
    assertion(metta_operation_plan_effect(['effect-plan-pure',
                                           'effect-plan-read',
                                           'effect-plan-write'],
                                          writesState)),
    assertion(\+ metta_operation_plan_effect(['effect-plan-pure',
                                               'effect-plan-missing'], _)).

test(world_effect_coverage_composes_catalog_rows_to_the_strongest_rank,
     [ cleanup(forall(member(Row,
                             [[covers, '&effect-world', readOnlyLookup],
                              [covers, '&effect-world', writesState]]),
                      metta_remove_atom('&metta', Row, _))) ]) :-
    assertion(metta_world_effect_coverage('&effect-world', pureStructural)),
    add_sexp('&metta', [covers, '&effect-world', readOnlyLookup], _),
    add_sexp('&metta', [covers, '&effect-world', writesState], _),
    assertion(metta_world_effect_coverage('&effect-world', writesState)),
    assertion(metta_effect_covered(nondeterministicReadOnly, writesState)),
    assertion(\+ metta_effect_covered(oracleIO, writesState)).

%Both names in the row must be callable when it is written: a compensation
%for an operation nothing can run, or naming a recovery nothing can run, is a
%dangling promise that only shows up during recovery. The forward operation
%therefore carries a definition here as well as its effect declaration.
test(compensation_declarations_require_an_effectful_operation,
     [ cleanup(( forall(member(Row,
                                [[compensates, 'effect-saga-write',
                                  'effect-saga-reverse'],
                                 [=, ['effect-saga-reverse', _], done],
                                 [=, ['effect-saga-write', _], done],
                                 [=, ['effect-saga-pure', _], done]]),
                         ( metta_remove_atom('&metta', Row, _)
                         -> true
                         ;  metta_remove_atom('&self', Row, _) )),
                 effect_test_clear('effect-saga-write'),
                 effect_test_clear('effect-saga-pure') )) ]) :-
    effect_test_add('effect-saga-write', writesState),
    effect_test_add('effect-saga-pure', pureStructural),
    metta_add_atom('&self',
                   [=, ['effect-saga-reverse', _Receipt], done], true),
    metta_add_atom('&self',
                   [=, ['effect-saga-write', _Value], done], true),
    metta_add_atom('&self',
                   [=, ['effect-saga-pure', _Operand], done], true),
    add_sexp('&metta',
             [compensates, 'effect-saga-write', 'effect-saga-reverse'], _),
    assertion(metta_compensation('effect-saga-write',
                                 'effect-saga-reverse')),
    catch(( add_sexp('&metta',
                     [compensates, 'effect-saga-pure',
                      'effect-saga-reverse'], _),
            Refused = false ),
          error(metta_declaration_malformed(_, 1, _), _),
          Refused = true),
    assertion(Refused == true),
    assertion(\+ metta_contract_fact(
                    [compensates, 'effect-saga-pure', _])).

%A cache hides an ANSWER, so its question is narrower than a reified world's.
%The reviewed native profile is a floor under both: it can refuse a cache, but
%a control form it reports structural is not thereby something a cached result
%may stand in for. Coupling the two moved lib_strategy's traversals by an
%order of magnitude, which the seam clause's own note prices.
test(the_cache_purity_seam_reads_declarations_under_the_native_floor,
     [ cleanup(( effect_test_clear('random-int'),
                 effect_test_clear('effect-floor-declared') )) ]) :-
    forall(member(Control, [once, collapse, forall, chain, 'let*']),
           ( assertion(metta_operation_effect(Control, pureStructural)),
             assertion(\+ seam:pure_operation(Control)) )),
    forall(member(Primitive, ['+', 'car-atom']),
           assertion(seam:pure_operation(Primitive))),
    effect_test_add('effect-floor-declared', pureStructural),
    assertion(seam:pure_operation('effect-floor-declared')),
    effect_test_add('random-int', pureStructural),
    assertion(metta_operation_effect('random-int', oracleIO)),
    assertion(\+ seam:pure_operation('random-int')).

test(only_pure_structural_projects_to_the_cache_purity_seam,
     [ cleanup(( effect_test_clear('effect-seam-pure'),
                 effect_test_clear('effect-seam-read'),
                 effect_test_clear('effect-seam-nondet'),
                 effect_test_clear('effect-seam-write'),
                 effect_test_clear('effect-seam-oracle') )) ]) :-
    effect_test_add('effect-seam-pure', pureStructural),
    effect_test_add('effect-seam-read', readOnlyLookup),
    effect_test_add('effect-seam-nondet', nondeterministicReadOnly),
    effect_test_add('effect-seam-write', writesState),
    effect_test_add('effect-seam-oracle', oracleIO),
    assertion(seam:pure_operation('effect-seam-pure')),
    assertion(\+ seam:pure_operation('effect-seam-read')),
    assertion(\+ seam:pure_operation('effect-seam-nondet')),
    assertion(\+ seam:pure_operation('effect-seam-write')),
    assertion(\+ seam:pure_operation('effect-seam-oracle')).

test(the_legacy_host_pure_boolean_maps_to_pure_structural,
     [ setup(effect_test_host_pure_add('effect-legacy-pure-bool')),
       cleanup(effect_test_clear('effect-legacy-pure-bool')) ]) :-
    assertion(metta_operation_effect('effect-legacy-pure-bool',
                                     pureStructural)),
    assertion(seam:pure_operation('effect-legacy-pure-bool')).

test(effect_services_are_published) :-
    forall(member(Service, [metta_effect_rank/2,
                            metta_effect_join/3,
                            metta_effect_compose/2,
                            metta_effect_class_canonical/2,
                            metta_operation_effect/2,
                            metta_operation_plan_effect/2]),
           ( assertion(seam:kind(Service, service)),
             seam:seam_home(Service, Home),
             module_property(Home, exports(Exports)),
             assertion(memberchk(Service, Exports)) )).

%THE PLAN A HOST GETS FOR ONE COMPILED GOAL, and what makes it answerable at
%all: neither definition below publishes an (effect ...) summary, so the only
%route to add-atom's writesState is to FOLLOW the raw definitions --
%plunit-plan-caller into plunit-plan-writer and then into the operation that
%one calls. The join is the lattice's own, so a body reaching a pure and a
%writing operation answers the stronger of the two rather than either.
effect_plan_head('plunit-plan-writer').
effect_plan_head('plunit-plan-caller').
effect_plan_head('plunit-plan-pure').
effect_plan_head('plunit-plan-both').

effect_plan_definitions :-
    process_metta_string(
        "(= (plunit-plan-writer $a) (add-atom &plunit-plan-space (row $a)))\n\c
         (= (plunit-plan-caller $a) (plunit-plan-writer $a))\n\c
         (= (plunit-plan-pure $a) (+ $a 1))\n\c
         (= (plunit-plan-both $a) (let $x (+ $a 1) (plunit-plan-writer $x)))",
        _).

effect_plan_cleanup :-
    forall(effect_plan_head(Head),
           'remove-atom'('&self', [=, [Head|_], _], _)).

%The same two steps a host takes: translate the term, then hand the compiled
%body back with its source term in front, which is the shape
%metta_host_goal_effect_plan/4's first clause reads
%[source: extensions/python/metta/shim.pl, metta_py_world_effect_plan/4].
effect_goal_plan(Term, Operations, Effect) :-
    metta_self_module(Module),
    with_metta_module(Module,
                      ( translator:translate_cached_expr(Term, Goals, _),
                        translator:goals_list_to_conj(Goals, Compiled) )),
    metta_host_goal_effect_plan(Module,
                                (metta_effect_source_term(Term), Compiled),
                                Operations, Effect).

test(a_compiled_goal_plan_follows_raw_definitions_and_joins_operations,
     [ setup(effect_plan_definitions), cleanup(effect_plan_cleanup) ]) :-
    effect_goal_plan(['plunit-plan-caller', 1], Written, WrittenEffect),
    assertion(Written == [['add-atom', writesState]]),
    assertion(WrittenEffect == writesState),
    effect_goal_plan(['plunit-plan-pure', 1], Pure, PureEffect),
    assertion(Pure == [[+, pureStructural]]),
    assertion(PureEffect == pureStructural),
    effect_goal_plan(['plunit-plan-both', 1], Both, BothEffect),
    assertion(memberchk([+, pureStructural], Both)),
    assertion(memberchk(['add-atom', writesState], Both)),
    assertion(BothEffect == writesState).

%FAIL CLOSED, both ways an unclassified grounded call can arrive. A bridge
%dispatch whose recovered operation has no declaration is oracleIO under that
%operation's OWN name, so the row a host reads names what the program wrote;
%a goal the walk cannot see at all is oracleIO under <dynamic-operation>.
%Neither may pass as pureStructural, which is what a reified world admits
%without any coverage row.
test(an_unclassified_bridge_and_dynamic_call_fail_closed_at_oracle_io) :-
    assertion(\+ metta_operation_effect('plunit-unclassified-bridge-op', _)),
    metta_self_module(Module),
    metta_host_goal_effect_plan(
        Module, plunit_unclassified_bridge_dispatch(a, b),
        BridgeOperations, BridgeEffect),
    assertion(BridgeOperations == [['plunit-unclassified-bridge-op', oracleIO]]),
    assertion(BridgeEffect == oracleIO),
    metta_host_goal_effect_plan(Module, _Unseen,
                                DynamicOperations, DynamicEffect),
    assertion(DynamicOperations == [['<dynamic-operation>', oracleIO]]),
    assertion(DynamicEffect == oracleIO).

:- end_tests(effects_lattice).
