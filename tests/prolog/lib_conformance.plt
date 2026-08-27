% Purpose: lib_conformance, the Prolog tier's conformance kit. The Python kit
%   takes an OBJECT and a Prolog provider is a set of multifile clauses, so
%   the seam's faster tier had no way to prove itself. These are the kit's own
%   kit: they assert it catches each mistake it exists for.
% Guarantees:
%   - a provider that under-approximates its match is refused, naming the atom,
%     and the family law catches a ground-only matcher
%     [tested: conformance_catches_an_under_approximating_matcher,
%     conformance_catches_a_ground_only_matcher]
%   - a false exact pushdown claim is refused
%     [tested: conformance_catches_a_false_exact_claim]
%   - a draining enumeration under the repeated default is refused, and a
%     dropped add is caught by the canary round trip
%     [tested: conformance_catches_a_source_that_drains,
%     conformance_catches_an_add_that_drops, conformance_round_trips_a_canary]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').
:- initialization(consult('../../lib/lib_conformance.pl')).
:- initialization(user:consult('conformance_providers')).

:- begin_tests(lib_conformance).

test(conformance_passes_a_conforming_provider) :-
    metta_check_space_provider('&plunit_conf_good', Checks),
    assertion(memberchk("match: over-approximation holds over 2 atoms and their pattern families", Checks)),
    assertion(memberchk("source: repeated, two enumerations agree", Checks)),
    assertion(memberchk("round trip: add then enumerate answers the atom, and remove takes it back", Checks)),
    assertion(memberchk("pushdown: 0 of 2 patterns claimed exact, and are", Checks)),
    assertion(memberchk("match: declared, seam:foreign_match/3 has clauses", Checks)).

% The seam's central soundness claim: over-approximating is always correct and
% under-approximating never is. A provider that filters too eagerly answers an
% empty set in production with nothing to say why.
test(conformance_catches_an_under_approximating_matcher,
     [throws(error(metta_conformance_under_approximates('&plunit_conf_eager',
                                                        [edge, a, b]), _))]) :-
    metta_check_space_provider('&plunit_conf_eager', _).

% The one claim in the seam that costs answers, so the kit tests it rather
% than trusting it.
test(conformance_catches_a_false_exact_claim,
     [throws(error(metta_conformance_false_exact('&plunit_conf_liar', _, _), _))]) :-
    metta_check_space_provider('&plunit_conf_liar', _).

% A declaration with nothing behind it surfaces as a silent failure inside a
% callback; here it is a mistake named at check time.
test(conformance_catches_a_capability_with_no_hook,
     [condition(\+ ( predicate_property(seam:foreign_clear(_),
                                       number_of_clauses(Count)),
                       Count > 0 )),
      throws(error(metta_conformance_no_hook('&plunit_conf_hookless', clear,
                                             seam:foreign_clear/1), _))]) :-
    metta_check_space_provider('&plunit_conf_hookless', _).

test(conformance_refuses_a_space_that_is_not_foreign,
     [throws(error(metta_conformance_not_foreign('&plunit_conf_absent'), _))]) :-
    metta_check_space_provider('&plunit_conf_absent', _).

% The pattern family: the self-match passes for a ground-only matcher, and
% a position opened to a fresh variable is where it dies in production, so
% it dies here instead, naming the pattern.
test(conformance_catches_a_ground_only_matcher,
     [throws(error(metta_conformance_family_missed('&plunit_conf_groundonly',
                                                   _, _, _), _))]) :-
    metta_check_space_provider('&plunit_conf_groundonly', _).

% A repeated source re-enumerates identically; one that drains is linear
% and must say so.
test(conformance_catches_a_source_that_drains,
     [setup(flag(plunit_conf_drain_reads, _, 0)),
      throws(error(metta_conformance_source_disagrees('&plunit_conf_drain',
                                                      repeated), _))]) :-
    metta_check_space_provider('&plunit_conf_drain', _).

% Add then enumerate is identity on the stored atom; a provider whose add
% drops the atom still answers the call, and firing alone would pass.
test(conformance_catches_an_add_that_drops,
     [throws(error(metta_conformance_round_trip('&plunit_conf_dropadd', _),
                   _))]) :-
    metta_check_space_provider('&plunit_conf_dropadd', _).

% The passing witness for the same law, isolated so a regression names the
% law rather than hiding inside the conforming provider's list.
test(conformance_round_trips_a_canary) :-
    metta_check_space_provider('&plunit_conf_good', Checks),
    assertion(memberchk("round trip: add then enumerate answers the atom, and remove takes it back", Checks)).

:- end_tests(lib_conformance).
