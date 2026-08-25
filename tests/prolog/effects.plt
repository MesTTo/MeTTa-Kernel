% Purpose: prove the engine's five-rank effect lattice, compatibility
%   projection, and reflected plan join.
% Assumes: engine/metta.pl has initialized the &petta catalog and its native
%   storage.
% Guarantees: rank, join, composition, canonical operation reflection,
%   fail-closed plans, and cache-purity projection agree.
% [tested: tests/prolog/effects.plt; commit=WORKTREE]

:- ensure_loaded('../../engine/metta.pl').

effect_test_clear(Name) :-
    (   petta_contract_fact([effect, Name, Declared])
    ->  'remove-atom'('&petta', [effect, Name, Declared], _),
        effect_test_clear(Name)
    ;   petta_engine_module(Engine),
        retractall(Engine:metta_host_pure_operation(Name))
    ).

effect_test_add(Name, Class) :-
    'add-atom'('&petta', [effect, Name, Class], _).

effect_test_host_pure_add(Name) :-
    petta_engine_module(Engine),
    assertz(Engine:metta_host_pure_operation(Name)).

:- begin_tests(effects_lattice).

test(the_five_effect_classes_are_ranked_in_catalog_order) :-
    Classes = [pureStructural,
               readOnlyLookup,
               nondeterministicReadOnly,
               writesState,
               oracleIO],
    assertion(petta_contract_fact([vocabulary, 'effect-class'|Classes])),
    findall(Class-Rank,
            ( member(Class, Classes), petta_effect_rank(Class, Rank) ),
            Ranked),
    assertion(Ranked == [pureStructural-0,
                         readOnlyLookup-1,
                         nondeterministicReadOnly-2,
                         writesState-3,
                         oracleIO-4]),
    findall(Class-Rank, petta_effect_rank(Class, Rank), Enumerated),
    assertion(Enumerated == Ranked).

test(legacy_effect_spellings_map_but_cannot_enter_the_canonical_catalog) :-
    assertion(petta_effect_rank(immutable, 0)),
    assertion(petta_effect_rank(stable, 1)),
    assertion(petta_effect_rank(volatile, 4)),
    forall(member(Legacy, [immutable, stable, volatile]),
           ( catch(( effect_test_add('effect-legacy-refused', Legacy),
                     Refused = none ),
                   error(petta_declaration_malformed(_, 2,
                                                     ['one-of', 'effect-class']),
                         _),
                   Refused = Legacy),
             assertion(Refused == Legacy) )),
    assertion(\+ petta_contract_fact([effect, 'effect-legacy-refused', _])).

test(effect_join_and_compose_choose_the_strongest_member) :-
    assertion(petta_effect_compose([], pureStructural)),
    assertion(petta_effect_join(readOnlyLookup,
                                nondeterministicReadOnly,
                                nondeterministicReadOnly)),
    assertion(petta_effect_join(writesState,
                                nondeterministicReadOnly,
                                writesState)),
    assertion(petta_effect_join(volatile, readOnlyLookup, oracleIO)),
    assertion(petta_effect_compose([pureStructural,
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
           ( petta_effect_join(Class, Class, Idempotent),
             assertion(Idempotent == Class),
             petta_effect_join(pureStructural, Class, Identity),
             assertion(Identity == Class) )),
    forall(( member(Left, Classes), member(Right, Classes) ),
           ( petta_effect_join(Left, Right, Joined),
             petta_effect_join(Right, Left, Reverse),
             assertion(Joined == Reverse) )),
    forall(( member(A, Classes), member(B, Classes), member(C, Classes) ),
           ( petta_effect_join(A, B, AB),
             petta_effect_join(AB, C, LeftAssociated),
             petta_effect_join(B, C, BC),
             petta_effect_join(A, BC, RightAssociated),
             assertion(LeftAssociated == RightAssociated) )).

test(operation_effect_reflection_is_canonical_and_fail_closed,
    [ cleanup(( effect_test_clear('effect-reflected'),
                 effect_test_clear('effect-unclassified') )) ]) :-
    assertion(\+ petta_operation_effect('effect-unclassified', _)),
    effect_test_add('effect-reflected', pureStructural),
    effect_test_add('effect-reflected', writesState),
    assertion(petta_operation_effect('effect-reflected', writesState)),
    petta_explain(['effect-reflected'], Explanation),
    findall(Effect, member([effect, Effect], Explanation), EffectRows),
    assertion(EffectRows == [writesState]).

test(an_operation_plan_joins_reflected_members_and_refuses_an_unknown_one,
     [ cleanup(( effect_test_clear('effect-plan-pure'),
                 effect_test_clear('effect-plan-read'),
                 effect_test_clear('effect-plan-write') )) ]) :-
    effect_test_add('effect-plan-pure', pureStructural),
    effect_test_add('effect-plan-read', nondeterministicReadOnly),
    effect_test_add('effect-plan-write', writesState),
    assertion(petta_operation_plan_effect([], pureStructural)),
    assertion(petta_operation_plan_effect(['effect-plan-pure',
                                           'effect-plan-read',
                                           'effect-plan-write'],
                                          writesState)),
    assertion(\+ petta_operation_plan_effect(['effect-plan-pure',
                                               'effect-plan-missing'], _)).

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
    assertion(petta_operation_effect('effect-legacy-pure-bool',
                                     pureStructural)),
    assertion(seam:pure_operation('effect-legacy-pure-bool')).

test(effect_services_are_published) :-
    forall(member(Service, [petta_effect_rank/2,
                            petta_effect_join/3,
                            petta_effect_compose/2,
                            petta_effect_class_canonical/2,
                            petta_operation_effect/2,
                            petta_operation_plan_effect/2]),
           ( assertion(seam:kind(Service, service)),
             seam:seam_home(Service, Home),
             module_property(Home, exports(Exports)),
             assertion(memberchk(Service, Exports)) )).

:- end_tests(effects_lattice).
