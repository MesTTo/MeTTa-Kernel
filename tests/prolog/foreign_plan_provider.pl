% A foreign space that CLAIMS conjunctions, for spaces.plt's plan unit. Two
% spaces: one that declares `plan` and one that does not, so the default
% (decline, and the engine splits) is reachable in the same run.
%
% The claim is answered with an ordinary Prolog nested loop, because what the
% unit tests is the SEAM: that a whole conjunction is offered, that the answers
% the provider gives are the answers the engine reports, and that they equal
% what the split produces. A provider's actual strategy is invisible to the
% engine by design, so a fast one would test nothing extra here. MORK's real
% worst-case-optimal join is exercised from bindings/python/tests/test_mork_space.py,
% which skips when the native library is not built.
:- multifile metta_foreign_space/1.
:- multifile metta_foreign_atoms/2.
:- multifile metta_foreign_match/3.
:- multifile metta_foreign_add/2.
:- multifile metta_foreign_remove/3.
:- multifile metta_foreign_capability/2.
:- multifile metta_foreign_plan/5.

:- dynamic plunit_plan_atom/2.
%Set when a claim is answered, so a differential cannot pass by quietly taking
%the split on both sides.
:- dynamic plunit_plan_claimed/1.

metta_foreign_space('&plunit_plan').
metta_foreign_space('&plunit_noplan').

metta_foreign_atoms(Space, Atom) :- plunit_plan_atom(Space, Atom).
metta_foreign_match(Space, Pattern, _) :- plunit_plan_atom(Space, Pattern).
%Idempotent, so a unit that fills the space more than once does not accumulate
%copies and turn every answer set into a multiset of them.
metta_foreign_add(Space, Atom) :-
    ( plunit_plan_atom(Space, Atom) -> true ; assertz(plunit_plan_atom(Space, Atom)) ).
metta_foreign_remove(Space, Atom, Removed) :-
    ( plunit_plan_atom(Space, Atom) -> Removed = true ; Removed = false ),
    retractall(plunit_plan_atom(Space, Atom)).

metta_foreign_capability('&plunit_plan', C) :-
    member(C, [add, remove, match, enumerate, plan]).
metta_foreign_capability('&plunit_noplan', C) :-
    member(C, [add, remove, match, enumerate]).

%The whole conjunction, claimed. Rest is [] because this provider answers all
%of it; a partial claim is tested separately, by the clause below.
metta_foreign_plan('&plunit_plan', Conjuncts, Conjuncts, [],
                   plunit_plan_solve('&plunit_plan', Conjuncts)) :-
    \+ member([partial|_], Conjuncts),
    \+ member([lossy|_], Conjuncts).
%A PARTIAL claim: a conjunct this provider will not take is left for the
%engine, which is what makes the seam not all-or-nothing.
metta_foreign_plan('&plunit_plan', Conjuncts, Claimed, Rest,
                   plunit_plan_solve('&plunit_plan', Claimed)) :-
    \+ member([lossy|_], Conjuncts),
    partition([C]>>(C = [partial|_]), Conjuncts, Rest, Claimed),
    Claimed \== [].

plunit_plan_solve(_, []) :- !, assertz(plunit_plan_claimed(yes)).
plunit_plan_solve(Space, [Pattern|Patterns]) :-
    plunit_plan_atom(Space, Pattern),
    plunit_plan_solve(Space, Patterns).

%A provider that drops a conjunct instead of leaving it, which the engine
%refuses. Reachable only for a space that asks for it by name, so the sound
%clauses above stay the ones every other test exercises.
metta_foreign_plan('&plunit_plan', Conjuncts, [Head], [], true) :-
    Conjuncts = [Head|[_|_]],
    Head = [lossy|_].
