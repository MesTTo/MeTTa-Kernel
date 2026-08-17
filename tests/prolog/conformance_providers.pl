% Four providers for lib_conformance.plt: one that conforms and three that
% break one rule each. A FILE, not assertz'd clauses, because the seam's hooks
% are static multifile and that is how a library contributes to them.
:- multifile metta_foreign_space/1.
:- multifile metta_foreign_atoms/2.
:- multifile metta_foreign_match/3.
:- multifile metta_foreign_capability/2.
:- multifile metta_foreign_pushdown/3.

plunit_conf_atom(A) :- member(A, [[edge, a, b], [edge, b, c]]).

%Conforms: over-approximates, which is always correct.
metta_foreign_space('&plunit_conf_good').
metta_foreign_atoms('&plunit_conf_good', A) :- plunit_conf_atom(A).
metta_foreign_match('&plunit_conf_good', P, _) :- plunit_conf_atom(P).
metta_foreign_capability('&plunit_conf_good', C) :- member(C, [match, enumerate]).

%Filters too eagerly: answers nothing for an atom it holds.
metta_foreign_space('&plunit_conf_eager').
metta_foreign_atoms('&plunit_conf_eager', A) :- plunit_conf_atom(A).
metta_foreign_match('&plunit_conf_eager', _, _) :- fail.
metta_foreign_capability('&plunit_conf_eager', C) :- member(C, [match, enumerate]).

%Claims exact and over-approximates, which is the combination that loses
%answers: the caller truncates at its bound and fewer than N of the N
%candidates were answers.
metta_foreign_space('&plunit_conf_liar').
metta_foreign_atoms('&plunit_conf_liar', A) :- plunit_conf_atom(A).
metta_foreign_match('&plunit_conf_liar', P, _) :- plunit_conf_atom(P).
metta_foreign_capability('&plunit_conf_liar', C) :- member(C, [match, enumerate]).
metta_foreign_pushdown('&plunit_conf_liar', _, exact).

%Declares a capability with no hook behind it.
metta_foreign_space('&plunit_conf_hookless').
metta_foreign_atoms('&plunit_conf_hookless', A) :- plunit_conf_atom(A).
metta_foreign_capability('&plunit_conf_hookless', C) :-
    member(C, [enumerate, clear]).
