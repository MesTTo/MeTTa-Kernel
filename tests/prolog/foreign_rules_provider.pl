% Two foreign spaces for spaces.plt's foreign-rules unit: one that declares it
% holds rules and one that does not. A FILE, because the seam's hooks are
% static multifile and that is how a library contributes to them.
:- multifile seam:foreign_space/1.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_match/3.
:- multifile seam:foreign_add/2.
:- multifile seam:foreign_remove/3.
:- multifile seam:foreign_capability/2.

:- dynamic plunit_rule_atom/2.

seam:foreign_space('&plunit_rules').
seam:foreign_space('&plunit_facts').

seam:foreign_atoms(Space, Atom) :- plunit_rule_atom(Space, Atom).
seam:foreign_match(Space, Pattern, _) :- plunit_rule_atom(Space, Pattern).
seam:foreign_add(Space, Atom) :- assertz(plunit_rule_atom(Space, Atom)).
%Declared, so it needs a clause behind it: a capability with no hook is what
%lib_conformance's check_space_provider refuses, and this fixture is held to
%the same contract as any other provider.
seam:foreign_remove(Space, Atom, Removed) :-
    ( plunit_rule_atom(Space, Atom) -> Removed = true ; Removed = false ),
    retractall(plunit_rule_atom(Space, Atom)).

%The one that holds rules says so. The one that does not declares everything
%else, which is what makes the refusal reachable: a space declaring NOTHING
%provides everything, rules included.
seam:foreign_capability('&plunit_rules', C) :-
    member(C, [add, remove, match, enumerate, rules]).
seam:foreign_capability('&plunit_facts', C) :-
    member(C, [add, remove, match, enumerate]).
