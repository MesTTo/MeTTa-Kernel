% Purpose: verify native and foreign space matching rejects cyclic answers
%   while preserving ordinary acyclic matches.
% Open Obligations:
%   To Do: Add direct coverage for arbitrary non-expression atoms.
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

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
