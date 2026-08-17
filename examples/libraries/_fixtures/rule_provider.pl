% A foreign space that holds RULES as well as facts. The whole of what it takes
% is declaring the `rules` capability; the provider stores an equation the way
% it stores any other atom and the engine compiles it, so nothing here has to
% know what an equation is.
:- metta_extension(rule_demo, [version('1.0.0')]).

:- multifile metta_foreign_space/1.
:- multifile metta_foreign_atoms/2.
:- multifile metta_foreign_match/3.
:- multifile metta_foreign_add/2.
:- multifile metta_foreign_remove/3.
:- multifile metta_foreign_capability/2.

:- dynamic rule_demo_atom/1.

metta_foreign_space('&rule_demo').
metta_foreign_atoms('&rule_demo', Atom) :- rule_demo_atom(Atom).
metta_foreign_match('&rule_demo', Pattern, _Options) :- rule_demo_atom(Pattern).
metta_foreign_add('&rule_demo', Atom) :- assertz(rule_demo_atom(Atom)).
metta_foreign_remove('&rule_demo', Atom, Removed) :-
    ( rule_demo_atom(Atom) -> Removed = true ; Removed = false ),
    retractall(rule_demo_atom(Atom)).
metta_foreign_capability('&rule_demo', Capability) :-
    member(Capability, [match, enumerate, add, remove, rules]).
