% Seven providers for lib_conformance.plt: one that conforms and six that
% break one rule each. A FILE, not assertz'd clauses, because the seam's hooks
% are static multifile and that is how a library contributes to them.
:- multifile seam:foreign_space/1.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_match/3.
:- multifile seam:foreign_capability/2.
:- multifile seam:foreign_pushdown/3.
:- multifile seam:foreign_add/2.
:- multifile seam:foreign_remove/3.

plunit_conf_atom(A) :- member(A, [[edge, a, b], [edge, b, c]]).

%Conforms: over-approximates, which is always correct, and round-trips a
%write through a real store so the canary law has a passing witness.
:- dynamic plunit_conf_extra/1.
seam:foreign_space('&plunit_conf_good').
seam:foreign_atoms('&plunit_conf_good', A) :-
    ( plunit_conf_atom(A) ; plunit_conf_extra(A) ).
seam:foreign_match('&plunit_conf_good', P, _) :-
    ( plunit_conf_atom(P) ; plunit_conf_extra(P) ).
seam:foreign_add('&plunit_conf_good', Atom) :-
    assertz(plunit_conf_extra(Atom)).
seam:foreign_remove('&plunit_conf_good', Atom, true) :-
    retract(plunit_conf_extra(Atom)).
seam:foreign_capability('&plunit_conf_good', C) :-
    member(C, [match, enumerate, add, remove]).

%Filters too eagerly: answers nothing for an atom it holds.
seam:foreign_space('&plunit_conf_eager').
seam:foreign_atoms('&plunit_conf_eager', A) :- plunit_conf_atom(A).
seam:foreign_match('&plunit_conf_eager', _, _) :- fail.
seam:foreign_capability('&plunit_conf_eager', C) :- member(C, [match, enumerate]).

%Claims exact and over-approximates, which is the combination that loses
%answers: the caller truncates at its bound and fewer than N of the N
%candidates were answers.
seam:foreign_space('&plunit_conf_liar').
seam:foreign_atoms('&plunit_conf_liar', A) :- plunit_conf_atom(A).
seam:foreign_match('&plunit_conf_liar', P, _) :- plunit_conf_atom(P).
seam:foreign_capability('&plunit_conf_liar', C) :- member(C, [match, enumerate]).
seam:foreign_pushdown('&plunit_conf_liar', _, exact).

%Declares a capability with no hook behind it.
seam:foreign_space('&plunit_conf_hookless').
seam:foreign_atoms('&plunit_conf_hookless', A) :- plunit_conf_atom(A).
seam:foreign_capability('&plunit_conf_hookless', C) :-
    member(C, [enumerate, clear]).

%A RIVAL provider that really does implement clear, for its own space only,
%in the shipped ownership-guard shape: a variable head with the ownership
%test as the body's leading goal, exactly as MORK and redis write it. Its
%whole job here is to give seam:foreign_clear/1 a clause, so the hookless
%space above cannot pass on a whole-predicate count. Without a rival in the
%file the hookless test passed for the wrong reason whenever a backend was
%absent, and failed the day MORK gained a clear hook.
plunit_conf_rival('&plunit_conf_rival').
seam:foreign_space('&plunit_conf_rival').
seam:foreign_atoms('&plunit_conf_rival', A) :- plunit_conf_atom(A).
seam:foreign_capability('&plunit_conf_rival', C) :- member(C, [enumerate, clear]).
seam:foreign_clear(Space) :- plunit_conf_rival(Space).

%Handles only ground patterns, which the family law exists to catch: the
%self-match passes and a position opened to a variable answers nothing.
seam:foreign_space('&plunit_conf_groundonly').
seam:foreign_atoms('&plunit_conf_groundonly', A) :- plunit_conf_atom(A).
seam:foreign_match('&plunit_conf_groundonly', P, _) :-
    ground(P), plunit_conf_atom(P).
seam:foreign_capability('&plunit_conf_groundonly', C) :-
    member(C, [match, enumerate]).

%Drains on enumeration while claiming the repeated default: the first
%read answers the atoms and the second answers nothing. The flag counts
%calls, and the test resets it so a rerun starts fresh.
seam:foreign_space('&plunit_conf_drain').
seam:foreign_atoms('&plunit_conf_drain', A) :-
    flag(plunit_conf_drain_reads, N, N + 1),
    N =:= 0,
    plunit_conf_atom(A).
seam:foreign_match('&plunit_conf_drain', P, _) :- plunit_conf_atom(P).
seam:foreign_capability('&plunit_conf_drain', C) :-
    member(C, [match, enumerate]).

%Declares add and drops the atom, which firing alone would never see:
%the canary law asks the enumeration for it.
seam:foreign_space('&plunit_conf_dropadd').
seam:foreign_atoms('&plunit_conf_dropadd', A) :- plunit_conf_atom(A).
seam:foreign_match('&plunit_conf_dropadd', P, _) :- plunit_conf_atom(P).
seam:foreign_add('&plunit_conf_dropadd', _).
seam:foreign_remove('&plunit_conf_dropadd', _, true).
seam:foreign_capability('&plunit_conf_dropadd', C) :-
    member(C, [match, enumerate, add, remove]).
