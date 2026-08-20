/* Purpose: the catalog describes its own kinds and one generic checker
   validates every declaration against them, at both '&petta' write doors.
   Assumes:
     - src/metta.pl loads spaces.pl, whose presets populate '&petta' at
       consult time [tested: the_shipped_catalog_is_queryable_data]
   Guarantees:
     - a declaration violating its kind row is a hard error naming the
       atom, the position and the argspec, never a silent inert atom
       [tested: a_malformed_shipped_declaration_is_refused_loudly]
     - a head with no kind row passes untouched, the open data axis
       [tested: an_undeclared_head_stays_plain_data]
   Open Obligations:
     To Do: None
     Hacks: None
     Future Enhancements: None
*/
:- initialization(consult('../../src/metta.pl')).

:- begin_tests(catalog_self_description).

%The presets are ordinary atoms: the schema of handles is matchable the
%way any data is, which is the self-description the row asks for.
test(the_shipped_catalog_is_queryable_data) :-
    once('get-atoms'('&petta', [kind, handles|Spec])),
    Spec == [symbol, pattern, ['one-of', fidelity],
             [optional, ['one-of', determinism]]],
    once('get-atoms'('&petta', [vocabulary, fidelity|Values])),
    Values == ['Exact', 'Partial', 'Sound', 'Refuse'].

test(a_malformed_shipped_declaration_is_refused_loudly,
     [error(petta_declaration_malformed([source, '&cat1', bogus], 2,
                                        ['one-of', 'source-kind']))]) :-
    add_sexp('&petta', [source, '&cat1', bogus], _).

test(a_missing_mandatory_argument_is_refused,
     [error(petta_declaration_malformed([annotations, '&cat2'], 2, _))]) :-
    add_sexp('&petta', [annotations, '&cat2'], _).

test(a_surplus_argument_is_refused,
     [error(petta_declaration_malformed([inverse, f, extra], 2, _))]) :-
    add_sexp('&petta', [inverse, f, extra], _).

test(an_optional_trailing_argument_may_be_omitted_or_given) :-
    add_sexp('&petta', [handles, '&cat3', [p, _X], 'Exact'], Ref1),
    add_sexp('&petta', [handles, '&cat3', [q, _Y], 'Sound', semidet], Ref2),
    erase(Ref1),
    erase(Ref2).

test(an_undeclared_head_stays_plain_data) :-
    add_sexp('&petta', ['third-party-note', anything, [odd, shape], 42], Ref),
    erase(Ref).

%A third party's whole schema path: vocabulary, kind, a valid instance,
%and the invalid instance refused by the same generic checker that guards
%the shipped kinds.
test(a_third_party_kind_is_declared_and_enforced,
     [cleanup(forall(member(A, [[vocabulary, 'cat-level', hot, cold],
                                [kind, 'cat-kind', symbol,
                                 ['one-of', 'cat-level']]]),
                     ( 'get-atoms'('&petta', A)
                     -> metta_remove_atom('&petta', A, _)
                     ;  true )))]) :-
    add_sexp('&petta', [vocabulary, 'cat-level', hot, cold], _),
    add_sexp('&petta', [kind, 'cat-kind', symbol, ['one-of', 'cat-level']], _),
    add_sexp('&petta', ['cat-kind', '&thing', hot], Ref),
    erase(Ref),
    catch(( add_sexp('&petta', ['cat-kind', '&thing', tepid], _),
            fail ),
          error(petta_declaration_malformed(_, 2, ['one-of', 'cat-level']), _),
          true).

test(a_kind_naming_an_undeclared_vocabulary_is_refused,
     [error(petta_declaration_malformed([kind, 'cat-orphan', symbol,
                                         ['one-of', 'never-declared']],
                                        3, _))]) :-
    add_sexp('&petta', [kind, 'cat-orphan', symbol,
                        ['one-of', 'never-declared']], _).

test(a_kind_with_a_nonsense_argspec_is_refused,
     [error(petta_declaration_malformed([kind, 'cat-bad', wobbly], 2, _))]) :-
    add_sexp('&petta', [kind, 'cat-bad', wobbly], _).

test(rest_anywhere_but_final_position_is_refused,
     [error(petta_declaration_malformed(_, 2,
                                        'rest only in final position'))]) :-
    add_sexp('&petta', [kind, 'cat-rest', [rest, symbol], integer], _).

test(a_second_kind_row_for_one_head_is_refused,
     [error(petta_declaration_malformed([kind, source, symbol, term], 1,
                                        _))]) :-
    add_sexp('&petta', [kind, source, symbol, term], _).

test(a_second_vocabulary_row_for_one_name_is_refused,
     [error(petta_declaration_malformed([vocabulary, fidelity, loose], 1,
                                        _))]) :-
    add_sexp('&petta', [vocabulary, fidelity, loose], _).

test(a_claim_on_a_value_outside_its_vocabulary_is_refused,
     [error(petta_declaration_malformed([claim, semiring, sideways, ordered],
                                        2, _))]) :-
    add_sexp('&petta', [claim, semiring, sideways, ordered], _).

:- dynamic cat_parked_spec/1.

test(a_removed_kind_row_stops_checking_that_head,
     [setup(( 'get-atoms'('&petta', [kind, cache|CacheSpec]),
              metta_remove_atom('&petta', [kind, cache|CacheSpec], _),
              assertz(cat_parked_spec(CacheSpec)) )),
      cleanup(( retract(cat_parked_spec(Spec)),
                add_sexp('&petta', [kind, cache|Spec], _) ))]) :-
    add_sexp('&petta', [cache, anything, 'not-a-cache-mode'], Ref),
    erase(Ref).

%The bulk door refuses the whole batch before any of it lands.
test(the_bulk_door_checks_before_it_writes) :-
    catch(( metta_add_atoms('&petta', [[source, '&cat4', repeated],
                                       [source, '&cat5', wrong]]),
            fail ),
          error(petta_declaration_malformed(_, _, _), _),
          true),
    \+ 'get-atoms'('&petta', [source, '&cat4', repeated]).

:- end_tests(catalog_self_description).
