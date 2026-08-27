% Purpose: pin the typed development build's own behaviour as a plunit test,
%   so evidence tags in engine/ headers can name a test the runner executes.
%   The -O direction (checks stripped to nothing) cannot run inside this
%   already-started session; check.sh's dev-typed-selftest lane covers it.
% Guarantees:
%   - the development direction inserts checks and a planted violation is
%     typed, exactly dev_typed_selftest's own verdict [tested:
%     the_dev_build_inserts_checks_and_types_a_planted_violation]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult(dev_typed)).

:- begin_tests(dev_typed_build).

test(the_dev_build_inserts_checks_and_types_a_planted_violation) :-
    dev_typed_selftest.

:- end_tests(dev_typed_build).
