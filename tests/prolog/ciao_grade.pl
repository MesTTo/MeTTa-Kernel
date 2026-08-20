% Purpose: declare external Ciao-style contracts for the engine's removal and
%   translation funnels, then collect packaged rtchecks violations as data.
% Assumes:
%   - assertions@0.0.1, rtchecks@0.0.1, and xlibrary@0.0.2 are installed as
%     SWI-Prolog packs.
% Guarantees:
%   - ciao_grade_collect/2 drains stale findings, runs its goal with the
%     packaged runtime checker, and returns every assrchk/1 finding
%     [tested: test_the_ciao_grade_collects_a_planted_assertion_violation_as_data;
%     commit=dcfc20be4933c19140ccb5759291401d13058301].
% Decides:
%   - contracts remain in this external development side file, so production
%     engine loading neither imports the packs nor enables runtime checking.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(assertions)).
:- use_module(library(plprops)).
:- use_module(library(rtchecks)).
:- use_module(library(rtchecks_utils)).
:- init_expansors.

:- set_prolog_flag(runtime_checks, yes).
:- set_prolog_flag(rtchecks_check, yes).

:- type petta_boolean/1.

petta_boolean(true).
petta_boolean(false).

:- pred metta_remove_atom(Space, _, Removed)
   : atm(Space) => petta_boolean(Removed) + semidet.
:- pred unstore_atom(Space, _, Removed)
   : atm(Space) => petta_boolean(Removed) + semidet.
:- pred remove_equation(Space, _, Function, _, _, Removed)
   : (atm(Space), atm(Function)) => petta_boolean(Removed) + semidet.
:- pred translate_clause(_, _, ConstrainArgs)
   : petta_boolean(ConstrainArgs) + semidet.

% The planted contract belongs here rather than on an engine predicate. Its
% body accepts every term, which makes the one bad call an rtchecks finding
% instead of an unrelated engine or typed-development-build exception.
:- pred ciao_grade_planted(Value) : atm(Value).

ciao_grade_planted(_).

ciao_grade_collect(Goal, Findings) :-
    load_rtchecks(_),
    save_rtchecks(with_rtchecks(Goal)),
    load_rtchecks(Findings).

% Exercise each externally asserted funnel with an ordinary successful call.
% Every name and space is private to this process-local grade fixture.
ciao_grade_smoke :-
    Space = '&ciao-grade',
    add_sexp(Space, ['ciao-grade-remove', atom]),
    metta_remove_atom(Space, ['ciao-grade-remove', atom], true),
    add_sexp(Space, ['ciao-grade-unstore', atom]),
    unstore_atom(Space, ['ciao-grade-unstore', atom], true),
    Equation = [=, ['ciao-grade-equation', X], X],
    metta_add_atom(Space, Equation, true),
    remove_equation(Space, Equation, 'ciao-grade-equation', [X], X, true),
    once(translate_clause([=, ['ciao-grade-translation', Y], Y], _, true)).
