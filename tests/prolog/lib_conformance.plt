% Purpose: lib_conformance, the Prolog tier's conformance kit. The Python kit
%   takes an OBJECT and a Prolog provider is a set of multifile clauses, so
%   the seam's faster tier had no way to prove itself. These are the kit's own
%   kit: they assert it catches each mistake it exists for.
% Guarantees:
%   - a provider that under-approximates its match is refused, naming the atom
%     [tested: conformance_catches_an_under_approximating_matcher]
%   - a false exact pushdown claim is refused
%     [tested: conformance_catches_a_false_exact_claim]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).
:- initialization(consult('../../lib/lib_conformance.pl')).
:- initialization(user:consult('conformance_providers')).

:- begin_tests(lib_conformance).

test(conformance_passes_a_conforming_provider) :-
    metta_check_space_provider('&plunit_conf_good', Checks),
    assertion(memberchk("match: over-approximation holds over 2 atoms", Checks)),
    assertion(memberchk("pushdown: 0 of 2 patterns claimed exact, and are", Checks)),
    assertion(memberchk("match: declared, metta_foreign_match/3 has clauses", Checks)).

% The seam's central soundness claim: over-approximating is always correct and
% under-approximating never is. A provider that filters too eagerly answers an
% empty set in production with nothing to say why.
test(conformance_catches_an_under_approximating_matcher,
     [throws(error(petta_conformance_under_approximates('&plunit_conf_eager',
                                                        [edge, a, b]), _))]) :-
    metta_check_space_provider('&plunit_conf_eager', _).

% The one claim in the seam that costs answers, so the kit tests it rather
% than trusting it.
test(conformance_catches_a_false_exact_claim,
     [throws(error(petta_conformance_false_exact('&plunit_conf_liar', _, _), _))]) :-
    metta_check_space_provider('&plunit_conf_liar', _).

% A declaration with nothing behind it surfaces as a silent failure inside a
% callback; here it is a mistake named at check time.
test(conformance_catches_a_capability_with_no_hook,
     [throws(error(petta_conformance_no_hook('&plunit_conf_hookless', clear,
                                             metta_foreign_clear/1), _))]) :-
    metta_check_space_provider('&plunit_conf_hookless', _).

test(conformance_refuses_a_space_that_is_not_foreign,
     [throws(error(petta_conformance_not_foreign('&plunit_conf_absent'), _))]) :-
    metta_check_space_provider('&plunit_conf_absent', _).

:- end_tests(lib_conformance).
