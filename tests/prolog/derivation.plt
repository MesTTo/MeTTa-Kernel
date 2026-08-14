% Purpose: track derivation contracts whose executable implementation lives in
%   the Python Janus shim rather than the engine source tree.
% Open Obligations:
%   To Do: Enable both tests when python/petta/shim.pl exposes conditional
%     subgoals and searches proofs beyond the first failed clause.
%   Hacks: None
%   Future Enhancements: None

:- begin_tests(derivation_contract).

test(conditionals_are_expanded_into_derivation_subgoals,
     [blocked('derivation is implemented in python/petta/shim.pl')]) :-
    true.

test(proof_search_continues_after_a_failed_clause,
     [blocked('derivation is implemented in python/petta/shim.pl')]) :-
    true.

:- end_tests(derivation_contract).
