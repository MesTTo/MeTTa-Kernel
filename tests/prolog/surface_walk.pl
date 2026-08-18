% Purpose: find every engine predicate an extension file calls, and say which
%     of them are published surface.
% Assumes:
%     - the caller has already consulted src/metta.pl and loaded whichever
%       extension files it wants walked, because this reads the DATABASE rather
%       than the sources: a handler whose body is built at run time is in no
%       file to read [source: the same split tests/prolog/static_checks.pl
%       makes between its source scan and its live scan]
%     - the working directory is tests/prolog, which is where check.sh runs
%       both of its callers from
%     - candidate_engine_module/1 is defined by the caller. This file has no
%       module of its own and no fixed name for the engine's: static_checks.pl
%       loads this file specifically so engine_predicate/1 can ask it which
%       modules to check rather than naming `user`, which is the one module
%       Phase 11 stops using for this
%       [source: ai-phase11-module-survey.md section 2.1, workspace root;
%       static_checks.pl's own header explains the discovery].
% Guarantees:
%     - reaches_past_surface/2 answers every call from a clause under one of
%       the given directories to a predicate defined under src/ that is neither
%       a declared extension point nor a MeTTa builtin, in whichever module
%       candidate_engine_module/1 says the engine's predicates live in rather
%       than only in `user`
%     - the walk reaches a call through control structure, through a declared
%       meta-argument, and through a meta-predicate NOBODY declared, because
%       SWI infers those [tested: planted_reach/2 in static_checks.pl, one
%       clause per door, each asserted and walked for real]
% Fails when:
%     - a call is assembled at run time from a term no analysis can see,
%       `Goal =.. L, call(Goal)` being the shape. Nothing static catches that,
%       and list_undefined does not either; it is the residue.
% Owns:
%     - reach_found/2 is scratch for one walk and is cleared before each,
%       because prolog_walk_code/1 reports through a side effect rather than
%       by answering
% Decides:
%     - published means DECLARED, not merely reachable. A predicate that is
%       exported, callable and widely used is still an internal here until an
%       ext_point_kind/2 fact says otherwise, because the point is to make the
%       surface a decision somebody wrote down.
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: None

:- use_module(library(prolog_codewalk)).

%%%% Which calls reach past the published surface %%%%
%
% The walk is SWI's own, the one list_undefined/0 uses, rather than a reading
% of clause bodies written here. That was the second version. The first walked
% control structure by hand and reported a backend clean while it reached an
% engine internal through maplist(register_prolog_arities, []); teaching it
% meta_predicate specs fixed that case and still left the one that matters
% more, a backend's OWN helper that takes a goal and never declared itself a
% meta-predicate. prolog_walk_code/1 infers those, which is not a thing worth
% reimplementing badly [source: SWI-Prolog library(prolog_codewalk),
% infer_meta_predicates option].
%
% trace_reference(_) is what makes it report every edge rather than calls to
% one goal: the library filters with subsumes_term/2 and an unbound reference
% subsumes everything.

:- dynamic reach_found/2.

reaches_past_surface(Directories, Reaches) :-
    extension_clauses(Directories, References),
    walked_reaches(References, Reaches).

walked_reaches(References, Reaches) :-
    retractall(reach_found(_, _)),
    prolog_walk_code([ clauses(References),
                       trace_reference(_),
                       on_edge(record_reach),
                       source(false),
                       infer_meta_predicates(all),
                       autoload(false),
                       undefined(ignore) ]),
    findall(Caller-Callee, reach_found(Caller, Callee), Reaches0),
    sort(Reaches0, Reaches).

record_reach(Callee, Caller, _Location) :-
    indicator(Callee, CalleeIndicator),
    engine_predicate(CalleeIndicator),
    \+ published_surface(CalleeIndicator),
    indicator(Caller, CallerIndicator),
    (   reach_found(CallerIndicator, CalleeIndicator)
    ->  true
    ;   assertz(reach_found(CallerIndicator, CalleeIndicator))
    ).
record_reach(_, _, _).

% Edges arrive module-qualified and a caller can be the atom
% '<initialization>', which has no arity and is not one of ours.
indicator(_:Goal, Indicator) :- !, indicator(Goal, Indicator).
indicator(Goal, Name/Arity) :- callable(Goal), functor(Goal, Name, Arity).

extension_clauses(Directories, References) :-
    findall(Reference,
            ( member(Relative, Directories),
              tree_directory(Relative, Directory),
              source_file(File),
              sub_atom(File, 0, _, _, Directory),
              source_file(Head, File),
              catch(nth_clause(Head, _, Reference), _, fail) ),
            References).

extension_clause_count(Directories, Count) :-
    extension_clauses(Directories, References),
    length(References, Count).

% With the separator, so that a sibling named src_generated is not read as
% being inside src.
tree_directory(Relative, Directory) :-
    absolute_file_name(Relative, Absolute),
    atom_concat(Absolute, '/', Directory).

engine_predicate(Name/Arity) :-
    functor(Head, Name, Arity),
    candidate_engine_module(Module),
    catch(predicate_property(Module:Head, file(File)), _, fail),
    tree_directory('../../src', EngineDir),
    sub_atom(File, 0, _, _, EngineDir).

% Read as data rather than listed here. A declared extension point is the
% contract in either direction, and a MeTTa builtin is the LANGUAGE, which an
% extension calls the way any program calls it.
published_surface(Seam) :- ext_point_kind(Seam, _).
published_surface(Name/_) :- builtin_fun(Name).
