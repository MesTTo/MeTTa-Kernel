% Four providers for lib_conformance.plt: one that conforms and three that
% break one rule each. A FILE, not assertz'd clauses, because the seam's hooks
% are static multifile and that is how a library contributes to them.
:- multifile seam:foreign_space/1.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_match/3.
:- multifile seam:foreign_capability/2.
:- multifile seam:foreign_pushdown/3.

plunit_conf_atom(A) :- member(A, [[edge, a, b], [edge, b, c]]).

%Conforms: over-approximates, which is always correct.
seam:foreign_space('&plunit_conf_good').
seam:foreign_atoms('&plunit_conf_good', A) :- plunit_conf_atom(A).
seam:foreign_match('&plunit_conf_good', P, _) :- plunit_conf_atom(P).
seam:foreign_capability('&plunit_conf_good', C) :- member(C, [match, enumerate]).

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
