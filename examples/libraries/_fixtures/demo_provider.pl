% A foreign space provider, complete and deliberately small, for
% examples/libraries/conformance.metta to prove.
%
% It declares an EXTENSION and exports nothing, which is the shape of a
% provider-only file: metta_export is for functions and a provider has none.
:- metta_extension(demo_provider, [version('1.0.0')]).

:- multifile metta_foreign_space/1.
:- multifile metta_foreign_atoms/2.
:- multifile metta_foreign_match/3.
:- multifile metta_foreign_capability/2.

demo_edge([edge, a, b]).
demo_edge([edge, b, c]).

metta_foreign_space('&demo_provider').
metta_foreign_atoms('&demo_provider', Atom) :- demo_edge(Atom).

% Over-approximating: every atom, every time. Always correct, because the
% engine keeps unification.
metta_foreign_match('&demo_provider', Pattern, _Options) :- demo_edge(Pattern).

% Exactly what it provides, so the engine's own record is the truth.
metta_foreign_capability('&demo_provider', Capability) :-
    member(Capability, [match, enumerate]).
