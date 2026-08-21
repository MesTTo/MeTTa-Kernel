% A complete foreign-space provider on every seam, consulted by
% ext_points.plt. It is a FILE rather than assertz'd clauses because that is
% how the seam is really used: the hooks are multifile and static, so a
% library contributes to them by consulting, and a runtime assertz raises
% "No permission to modify static procedure".
:- multifile seam:foreign_space/1.
:- multifile seam:foreign_add/2.
:- multifile seam:foreign_remove/3.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_match/3.
:- multifile seam:foreign_pushdown/3.
:- multifile seam:foreign_clear/1.
:- multifile seam:foreign_capability/2.

:- dynamic plunit_seam_atom/1.
:- dynamic plunit_seam_reached/1.

plunit_seam_reach(What) :-
    ( plunit_seam_reached(What) -> true ; assertz(plunit_seam_reached(What)) ).

seam:foreign_space('&plunit_seam') :- plunit_seam_reach(space).
seam:foreign_add('&plunit_seam', T) :-
    plunit_seam_reach(add), assertz(plunit_seam_atom(T)).
seam:foreign_remove('&plunit_seam', T, true) :-
    plunit_seam_reach(remove), retract(plunit_seam_atom(T)).
seam:foreign_atoms('&plunit_seam', T) :-
    plunit_seam_reach(enumerate), plunit_seam_atom(T).
seam:foreign_match('&plunit_seam', P, Options) :-
    plunit_seam_reach(match),
    ( Options == [] -> true ; plunit_seam_reach(bounded(Options)) ),
    plunit_seam_atom(P).
%Per PATTERN, which is the whole point of the classification: this provider
%answers exactly what a ground pattern names and scans for anything else, the
%way a backend is exact on an indexed equality and inexact on the rest. A
%provider claiming one class for everything it holds would have to claim the
%weaker one.
seam:foreign_pushdown('&plunit_seam', [_, Arg], Class) :-
    plunit_seam_reach(pushdown),
    ( ground(Arg) -> Class = exact ; Class = inexact ).

seam:foreign_clear('&plunit_seam') :-
    plunit_seam_reach(clear), retractall(plunit_seam_atom(_)).
seam:foreign_capability('&plunit_seam', C) :-
    plunit_seam_reach(capability),
    member(C, [add, remove, match, enumerate, clear]).
