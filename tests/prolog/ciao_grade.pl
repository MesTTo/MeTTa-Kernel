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

% The type the contracts below are written against. It USED to be the engine's
% own metta_boolean/1, and this file deliberately did not define one, because
% both files load into `user` and a second copy is a REDEFINITION rather than a
% duplicate: SWI warns "Redefined static procedure metta_boolean/1" and
% DISCARDS the engine's clauses, and the lane runs under --on-warning=status.
% The engine's copy went on 2026-08-30 with the comparable_operands/2 guard it
% was the only caller of, so the two clauses live here now and the redefinition
% hazard is gone with the thing that could be redefined.
:- type metta_boolean/1.

metta_boolean(true).
metta_boolean(false).

:- pred metta_remove_atom(Space, _, Removed)
   : atm(Space) => metta_boolean(Removed) + semidet.
:- pred unstore_atom(Space, _, Removed)
   : atm(Space) => metta_boolean(Removed) + semidet.
:- pred remove_equation(Space, _, Function, _, _, Removed)
   : (atm(Space), atm(Function)) => metta_boolean(Removed) + semidet.
:- pred translate_clause(_, _, ConstrainArgs)
   : metta_boolean(ConstrainArgs) + semidet.

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
