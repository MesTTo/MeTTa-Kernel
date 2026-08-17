% Two foreign spaces for spaces.plt's foreign-rules unit: one that declares it
% holds rules and one that does not. A FILE, because the seam's hooks are
% static multifile and that is how a library contributes to them.
:- multifile metta_foreign_space/1.
:- multifile metta_foreign_atoms/2.
:- multifile metta_foreign_match/3.
:- multifile metta_foreign_add/2.
:- multifile metta_foreign_remove/3.
:- multifile metta_foreign_capability/2.

:- dynamic plunit_rule_atom/2.

metta_foreign_space('&plunit_rules').
metta_foreign_space('&plunit_facts').

metta_foreign_atoms(Space, Atom) :- plunit_rule_atom(Space, Atom).
metta_foreign_match(Space, Pattern, _) :- plunit_rule_atom(Space, Pattern).
metta_foreign_add(Space, Atom) :- assertz(plunit_rule_atom(Space, Atom)).
%Declared, so it needs a clause behind it: a capability with no hook is what
%lib_conformance's check_space_provider refuses, and this fixture is held to
%the same contract as any other provider.
metta_foreign_remove(Space, Atom, Removed) :-
    ( plunit_rule_atom(Space, Atom) -> Removed = true ; Removed = false ),
    retractall(plunit_rule_atom(Space, Atom)).

%The one that holds rules says so. The one that does not declares everything
%else, which is what makes the refusal reachable: a space declaring NOTHING
%provides everything, rules included.
metta_foreign_capability('&plunit_rules', C) :-
    member(C, [add, remove, match, enumerate, rules]).
metta_foreign_capability('&plunit_facts', C) :-
    member(C, [add, remove, match, enumerate]).
