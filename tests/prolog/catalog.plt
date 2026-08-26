/* Purpose: the catalog describes its own kinds and one generic checker
   validates every declaration against them, at both '&metta' write doors.
   Assumes:
     - engine/metta.pl loads spaces.pl, whose presets populate '&metta' at
       consult time [tested: the_shipped_catalog_is_queryable_data]
   Guarantees:
     - a declaration violating its kind row is a hard error naming the
       atom, the position and the argspec, never a silent inert atom
       [tested: a_malformed_shipped_declaration_is_refused_loudly]
     - a head with no kind row passes untouched, the open data axis
       [tested: an_undeclared_head_stays_plain_data]
     - materialized annotation and algebra descriptors follow catalog adds,
       removals, and same-name replacements [tested:
       algebra_descriptor_caches_follow_catalog_edits; commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]
     - the deprecated kind is queryable with exact name, since, and remedy
       fields [tested: the_shipped_catalog_is_queryable_data;
       commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0]
     - every shipped callable has exactly one visibility row and the internal
       documentation helpers stay classified without leaving the callable set
       [tested: every_shipped_callable_has_one_visibility;
       commit=8779452fed89853c3f77c3469f7a6ec7b12e9efa]
   Open Obligations:
     To Do: None
     Hacks: None
     Future Enhancements: None
*/
:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(catalog_self_description).

%The presets are ordinary atoms: the schema of handles is matchable the
%way any data is, which is the self-description the row asks for.
test(the_shipped_catalog_is_queryable_data) :-
    once('get-atoms'('&metta', [kind, handles|Spec])),
    Spec == [symbol, pattern, ['one-of', fidelity],
             [optional, ['one-of', determinism]]],
    once('get-atoms'('&metta', [vocabulary, fidelity|Values])),
    Values == ['Exact', 'Partial', 'Sound', 'Refuse'],
    once('get-atoms'('&metta', [kind, deprecated|DeprecatedSpec])),
    DeprecatedSpec == [symbol, term, term],
    once('get-atoms'('&metta', [vocabulary, visibility|VisibilityValues])),
    VisibilityValues == ['PUBLIC', 'INTERNAL'],
    once('get-atoms'('&metta', [kind, visibility|VisibilitySpec])),
    VisibilitySpec == [symbol, ['one-of', visibility]],
    once('get-atoms'('&metta', [kind, covers|CoverageSpec])),
    CoverageSpec == [term, ['one-of', 'effect-class']],
    once('get-atoms'('&metta', [kind, compensates|CompensationSpec])),
    CompensationSpec == [symbol, symbol].

test(every_shipped_callable_has_one_visibility) :-
    findall(Name,
            ( fun(Name)
            ; metta_special_form_head(Name)
            ),
            Callable0),
    sort(Callable0, Callable),
    findall(Name-Visibility,
            petta_contract_fact([visibility, Name, Visibility]),
            Rows0),
    sort(Rows0, Rows),
    findall(Name, member(Name-_, Rows), Visible0),
    sort(Visible0, Visible),
    assertion(Visible == Callable),
    assertion(memberchk('get-doc-atom'-'INTERNAL', Rows)),
    assertion(memberchk('get-doc-function'-'INTERNAL', Rows)),
    assertion(memberchk('get-doc-params'-'INTERNAL', Rows)),
    assertion(memberchk('get-doc-single-atom'-'INTERNAL', Rows)),
    assertion(memberchk(interpret-'INTERNAL', Rows)),
    assertion(memberchk('match-type-or'-'INTERNAL', Rows)),
    assertion(memberchk('get-doc'-'PUBLIC', Rows)).

test(a_malformed_shipped_declaration_is_refused_loudly,
     [error(petta_declaration_malformed([source, '&cat1', bogus], 2,
                                        ['one-of', 'source-kind']))]) :-
    add_sexp('&metta', [source, '&cat1', bogus], _).

test(a_missing_mandatory_argument_is_refused,
     [error(petta_declaration_malformed([annotations, '&cat2'], 2, _))]) :-
    add_sexp('&metta', [annotations, '&cat2'], _).

test(a_surplus_argument_is_refused,
     [error(petta_declaration_malformed([inverse, f, extra], 2, _))]) :-
    add_sexp('&metta', [inverse, f, extra], _).

test(an_optional_trailing_argument_may_be_omitted_or_given) :-
    add_sexp('&metta', [handles, '&cat3', [p, _X], 'Exact'], Ref1),
    add_sexp('&metta', [handles, '&cat3', [q, _Y], 'Sound', semidet], Ref2),
    erase(Ref1),
    erase(Ref2).

test(an_undeclared_head_stays_plain_data) :-
    add_sexp('&metta', ['third-party-note', anything, [odd, shape], 42], Ref),
    erase(Ref).

%A third party's whole schema path: vocabulary, kind, a valid instance,
%and the invalid instance refused by the same generic checker that guards
%the shipped kinds.
test(a_third_party_kind_is_declared_and_enforced,
     [cleanup(forall(member(A, [[vocabulary, 'cat-level', hot, cold],
                                [kind, 'cat-kind', symbol,
                                 ['one-of', 'cat-level']]]),
                     ( 'get-atoms'('&metta', A)
                     -> metta_remove_atom('&metta', A, _)
                     ;  true )))]) :-
    add_sexp('&metta', [vocabulary, 'cat-level', hot, cold], _),
    add_sexp('&metta', [kind, 'cat-kind', symbol, ['one-of', 'cat-level']], _),
    add_sexp('&metta', ['cat-kind', '&thing', hot], Ref),
    erase(Ref),
    catch(( add_sexp('&metta', ['cat-kind', '&thing', tepid], _),
            fail ),
          error(petta_declaration_malformed(_, 2, ['one-of', 'cat-level']), _),
          true).

test(a_kind_naming_an_undeclared_vocabulary_is_refused,
     [error(petta_declaration_malformed([kind, 'cat-orphan', symbol,
                                         ['one-of', 'never-declared']],
                                        3, _))]) :-
    add_sexp('&metta', [kind, 'cat-orphan', symbol,
                        ['one-of', 'never-declared']], _).

test(a_kind_with_a_nonsense_argspec_is_refused,
     [error(petta_declaration_malformed([kind, 'cat-bad', wobbly], 2, _))]) :-
    add_sexp('&metta', [kind, 'cat-bad', wobbly], _).

test(rest_anywhere_but_final_position_is_refused,
     [error(petta_declaration_malformed(_, 2,
                                        'rest only in final position'))]) :-
    add_sexp('&metta', [kind, 'cat-rest', [rest, symbol], integer], _).

test(a_second_kind_row_for_one_head_is_refused,
     [error(petta_declaration_malformed([kind, source, symbol, term], 1,
                                        _))]) :-
    add_sexp('&metta', [kind, source, symbol, term], _).

test(a_second_vocabulary_row_for_one_name_is_refused,
     [error(petta_declaration_malformed([vocabulary, fidelity, loose], 1,
                                        _))]) :-
    add_sexp('&metta', [vocabulary, fidelity, loose], _).

test(a_claim_on_a_value_outside_its_vocabulary_is_refused,
     [error(petta_declaration_malformed([claim, semiring, sideways, ordered],
                                        2, _))]) :-
    add_sexp('&metta', [claim, semiring, sideways, ordered], _).

:- dynamic cat_parked_spec/1.

test(a_removed_kind_row_stops_checking_that_head,
     [setup(( 'get-atoms'('&metta', [kind, cache|CacheSpec]),
              metta_remove_atom('&metta', [kind, cache|CacheSpec], _),
              assertz(cat_parked_spec(CacheSpec)) )),
      cleanup(( retract(cat_parked_spec(Spec)),
                add_sexp('&metta', [kind, cache|Spec], _) ))]) :-
    add_sexp('&metta', [cache, anything, 'not-a-cache-mode'], Ref),
    erase(Ref).

%A third-party kind enters the ONE shape router through catalog rows
%alone: vocabulary, kind, routed-by-shape, entries. Specificity, adornment
%and coherence are inherited, not reimplemented.
test(a_third_party_shape_routed_kind_rides_the_one_router,
     [setup(( add_sexp('&metta', [vocabulary, 'fr-level', live, cached, stale], _),
              add_sexp('&metta', [kind, freshness, symbol, pattern,
                                  ['one-of', 'fr-level']], _),
              add_sexp('&metta', ['routed-by-shape', freshness], _) )),
      cleanup(forall(member(A, [[freshness, '&fr', [edge, _, _], cached],
                                [freshness, '&fr', [edge, [in, _], _], live],
                                ['routed-by-shape', freshness],
                                [kind, freshness, symbol, pattern,
                                 ['one-of', 'fr-level']],
                                [vocabulary, 'fr-level', live, cached, stale]]),
                     metta_remove_atom('&metta', A, _)))]) :-
    add_sexp('&metta', [freshness, '&fr', [edge, _A, _B], cached], _),
    add_sexp('&metta', [freshness, '&fr', [edge, [in, _C], _D], live], _),
    petta_shape_route(freshness, '&fr', [edge, bound, _E], _, [Level]),
    Level == live,
    petta_shape_route(freshness, '&fr', [edge, _F, _G], _, [General]),
    General == cached.

test(two_disagreeing_maximal_entries_conflict_loudly,
     [setup(( add_sexp('&metta', [vocabulary, 'hot-level', hot, cold], _),
              add_sexp('&metta', [kind, hotness, symbol, pattern,
                                  ['one-of', 'hot-level']], _),
              add_sexp('&metta', ['routed-by-shape', hotness], _),
              add_sexp('&metta', [hotness, '&h', [p, _, q], hot], _),
              add_sexp('&metta', [hotness, '&h', [p, r, _], cold], _) )),
      cleanup(forall(member(A, [[hotness, '&h', [p, _, q], hot],
                                [hotness, '&h', [p, r, _], cold],
                                ['routed-by-shape', hotness],
                                [kind, hotness, symbol, pattern,
                                 ['one-of', 'hot-level']],
                                [vocabulary, 'hot-level', hot, cold]]),
                     metta_remove_atom('&metta', A, _))),
      error(petta_contract_conflict(_, _, _, _))]) :-
    petta_shape_route(hotness, '&h', [p, r, q], _, _).

test(removing_the_routing_row_stops_the_route,
     [setup(( add_sexp('&metta', [vocabulary, 'wet-level', wet, dry], _),
              add_sexp('&metta', [kind, wetness, symbol, pattern,
                                  ['one-of', 'wet-level']], _),
              add_sexp('&metta', ['routed-by-shape', wetness], _),
              add_sexp('&metta', [wetness, '&w', [w, _], wet], _) )),
      cleanup(forall(member(A, [[wetness, '&w', [w, _], wet],
                                [kind, wetness, symbol, pattern,
                                 ['one-of', 'wet-level']],
                                [vocabulary, 'wet-level', wet, dry]]),
                     metta_remove_atom('&metta', A, _)))]) :-
    petta_shape_route(wetness, '&w', [w, 1], _, [wet]),
    metta_remove_atom('&metta', ['routed-by-shape', wetness], true),
    \+ petta_shape_declared(wetness, '&w').

test(a_routing_row_without_its_kind_is_refused,
     [error(petta_declaration_malformed(['routed-by-shape', 'never-kinded'],
                                        1, _))]) :-
    add_sexp('&metta', ['routed-by-shape', 'never-kinded'], _).

test(a_routing_row_over_an_unroutable_kind_is_refused,
     [setup(add_sexp('&metta', [kind, 'flat-kind', symbol, symbol], _)),
      cleanup(metta_remove_atom('&metta', [kind, 'flat-kind', symbol, symbol],
                                _)),
      error(petta_declaration_malformed(['routed-by-shape', 'flat-kind'],
                                        1, _))]) :-
    add_sexp('&metta', ['routed-by-shape', 'flat-kind'], _).

%The advisors' fold at the route classification: a loaded seam:route_cap/4
%clause may demote the declared Exact to inexact or refuse it loudly, and a
%cap outside the vocabulary is the advisor's own bug, refused as one.
:- dynamic cap_clause_ref/1.

%The advisor clause and its cap level are asserted into user explicitly:
%plunit runs setup and bodies in the unit's own module, and a hook clause
%asserted there is invisible to the engine's multifile call.
test(a_route_cap_demotes_and_refuses_through_the_published_seam,
     [setup(( retractall(user:cap_level(_)),
              add_sexp('&metta', [handles, '&cap1', [p, _X], 'Exact'], _),
              assertz(user:( seam:route_cap('&cap1', _, Cap, capped_by_test) :-
                                 cap_level(Cap) ),
                      Ref),
              assertz(cap_clause_ref(Ref)) )),
      cleanup(( retractall(user:cap_level(_)),
                retract(cap_clause_ref(Ref)),
                erase(Ref),
                metta_remove_atom('&metta',
                                  [handles, '&cap1', [p, _Y], 'Exact'],
                                  true) ))]) :-
    foreign_pushdown_class('&cap1', [p, v], exact),
    assertz(user:cap_level(inexact)),
    foreign_pushdown_class('&cap1', [p, v], inexact),
    retractall(user:cap_level(_)),
    assertz(user:cap_level(refuse)),
    catch(( foreign_pushdown_class('&cap1', [p, v], _),
            fail ),
          error(petta_route_capped('&cap1', _, capped_by_test), _),
          true),
    retractall(user:cap_level(_)),
    assertz(user:cap_level(sideways)),
    catch(( foreign_pushdown_class('&cap1', [p, v], _),
            fail ),
          error(petta_route_cap_invalid('&cap1', sideways, _), _),
          true).

%Orderedness is an independent claim in the catalog, so two third-party
%algebras may use the same operations while only the claimed one serves top.
test(a_claimed_ordered_value_orders_and_an_unclaimed_one_does_not,
     [setup(( 'get-atoms'('&metta', [vocabulary, semiring|Shipped]),
              metta_remove_atom('&metta', [vocabulary, semiring|Shipped], _),
              assertz(cat_parked_spec(Shipped)),
              append([vocabulary, semiring|Shipped], [cost, heap], Widened),
              add_sexp('&metta', Widened, _),
              add_sexp('&metta', [algebra, cost, min, '+', infinity, 0,
                                  [laws], [carrier], [requires]], _),
              add_sexp('&metta', [algebra, heap, min, '+', infinity, 0,
                                  [laws], [carrier], [requires]], _),
              add_sexp('&metta', [claim, semiring, cost, ordered], _),
              add_sexp('&metta', [annotations, '&ord1', cost], _),
              add_sexp('&metta', [annotations, '&ord2', heap], _) )),
      cleanup(( forall(member(A, [[claim, semiring, cost, ordered],
                                  [annotations, '&ord1', cost],
                                  [annotations, '&ord2', heap],
                                  [algebra, cost, min, '+', infinity, 0,
                                   [laws], [carrier], [requires]],
                                  [algebra, heap, min, '+', infinity, 0,
                                   [laws], [carrier], [requires]]]),
                       metta_remove_atom('&metta', A, _)),
                retract(cat_parked_spec(Shipped)),
                append([vocabulary, semiring|Shipped], [cost, heap], Widened),
                metta_remove_atom('&metta', Widened, _),
                add_sexp('&metta', [vocabulary, semiring|Shipped], _) ))]) :-
    petta_annotations_ordered('&ord1'),
    \+ petta_annotations_ordered('&ord2').

test(a_false_algebra_law_is_refused_before_the_catalog_row_lands,
     [throws(error(petta_algebra_law_violation(
                       p4_bad_zero, 'extend-zero-annihilates', _, _, _), _))]) :-
    add_sexp('&metta',
             [algebra, p4_bad_zero, min, min, 1, 0,
              [laws, 'extend-zero-annihilates'], [carrier, 0, 1], [requires]],
             _).

test(an_amplitude_context_without_the_whole_fragment_is_refused_by_name,
     [throws(error(petta_amplitude_fragment_refused('&p4-amp', finite), _))]) :-
    add_sexp('&metta', [annotations, '&p4-amp', amplitude], _).

test(algebra_descriptor_caches_follow_catalog_edits,
     [cleanup(forall(member(Row,
                             [[annotations, '&p4-cache-context',
                               'p4-cache-algebra'],
                              [algebra, 'p4-cache-algebra', '+', '*', 0,
                               unit, [laws], [carrier], [requires]],
                              [algebra, 'p4-cache-algebra', '+', '*', 0,
                               replacement, [laws], [carrier], [requires]]]),
                     ( metta_remove_atom('&metta', Row, _)
                     -> true
                     ;  true )))]) :-
    petta_annotations('&p4-cache-context', bool),
    add_sexp('&metta',
             [algebra, 'p4-cache-algebra', '+', '*', 0, unit,
              [laws], [carrier], [requires]], _),
    add_sexp('&metta',
             [annotations, '&p4-cache-context', 'p4-cache-algebra'], _),
    petta_annotations('&p4-cache-context', 'p4-cache-algebra'),
    petta_algebra_descriptor('p4-cache-algebra', '+', '*', 0, unit,
                             [laws], [carrier], [requires]),
    metta_remove_atom('&metta',
                      [annotations, '&p4-cache-context', 'p4-cache-algebra'],
                      true),
    petta_annotations('&p4-cache-context', bool),
    metta_remove_atom('&metta',
                      [algebra, 'p4-cache-algebra', '+', '*', 0, unit,
                       [laws], [carrier], [requires]], true),
    add_sexp('&metta',
             [algebra, 'p4-cache-algebra', '+', '*', 0, replacement,
              [laws], [carrier], [requires]], _),
    petta_algebra_descriptor('p4-cache-algebra', '+', '*', 0, replacement,
                             [laws], [carrier], [requires]).

%The export parser's word lists are the catalog's volatility vocabulary,
%consulted as data: widening the row widens what the parser accepts.
test(the_export_parser_reads_the_volatility_vocabulary,
     [setup(( 'get-atoms'('&metta', [vocabulary, volatility|Shipped]),
              metta_remove_atom('&metta', [vocabulary, volatility|Shipped], _),
              assertz(cat_parked_spec(Shipped)),
              append([vocabulary, volatility|Shipped], [frozen], Widened),
              add_sexp('&metta', Widened, _) )),
      cleanup(( retractall(metta_function_volatility('cat-vol-f', _)),
                retract(cat_parked_spec(Shipped)),
                append([vocabulary, volatility|Shipped], [frozen], Widened),
                metta_remove_atom('&metta', Widened, _),
                add_sexp('&metta', [vocabulary, volatility|Shipped], _) ))]) :-
    metta_export("(volatility cat-vol-f frozen)"),
    metta_function_volatility('cat-vol-f', frozen),
    catch(( metta_export("(volatility cat-vol-g melty)"),
            fail ),
          error(petta_export_form(_), _),
          true).

%The bulk door refuses the whole batch before any of it lands.
test(the_bulk_door_checks_before_it_writes) :-
    catch(( metta_add_atoms('&metta', [[source, '&cat4', repeated],
                                       [source, '&cat5', wrong]]),
            fail ),
          error(petta_declaration_malformed(_, _, _), _),
          true),
    \+ 'get-atoms'('&metta', [source, '&cat4', repeated]).

:- end_tests(catalog_self_description).
