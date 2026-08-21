% Purpose: gate that no shipped library calls an engine predicate the engine
%     does not publish, the same contract a_backend_calls_only_published_surface
%     holds a backend to.
% Assumes:
%     - surface_walk.pl decides what published means, so this file and the
%       backend GATE in static_checks.pl cannot drift apart on the definition
% Guarantees:
%     - exits nonzero when a library reaches past the published surface, naming
%       the library predicate, the engine predicate and the remedy
%     - exits nonzero when the walk stops seeing a planted reach, so a clean
%       result is a claim this file has just tested rather than an assumption
%       [tested: surface_walk.pl's four planted doors, one per way a call hides]
% Fails when:
%     - a call is assembled at run time from a term no analysis can see,
%       `Goal =.. L, call(Goal)` being the shape. That is the residue this
%       shares with every other static walk in the tree.
% Decides:
%     - lib/ is in scope and bindings/python/petta/shim.pl is not. shim.pl is consulted
%       by _engine.py as the Python tier's own implementation, so it is
%       engine-internal by construction rather than an extension
%       [source: bindings/python/petta/_engine.py, _consult_shim].
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: None

% A REPORT until 2026-08-21, and the reason it stayed one was a decision nobody
% had made rather than a walk nobody trusted: whether the library tier is meant
% to be arm's length from the engine the way a backend is. Nineteen predicates
% were involved and they were not one kind of thing, so declaring them wholesale
% would have made `service` mean "whatever anyone happens to call", which
% enforces nothing. They are decided one at a time now, in engine/ext_points.pl,
% each with the contract it promises written beside it, and the queue is empty.
%
% What makes the declaration mean something is that it is no longer only a
% comment: a declared seam is EXPORTED by the engine's module, and
% published_surface/1 asks the module system for that export list rather than
% reading the declaration table a second time. So a seam declared and never
% defined is not exported and does not pass this gate either.

:- ensure_loaded(surface_walk).
:- initialization(main, main).

library_directories(['../../lib']).

main :-
    consult('../../engine/metta.pl'),
    forall(( expand_file_name('../../lib/*.pl', Files), member(File, Files) ),
           ensure_loaded(File)),
    library_directories(Directories),
    reaches_past_surface(Directories, Reaches0),
    findall(Callee-Caller, member(Caller-Callee, Reaches0), Reaches1),
    sort(Reaches1, Reaches),
    extension_clause_count(Directories, Examined),
    report(Reaches, Examined).

report([], Examined) :-
    !,
    planted_internal(Internal),
    (   published_surface(Internal)
    ->  format(user_error,
               'the planted reach ~w is published surface, so it proves \c
                nothing; pick an engine predicate that is not~n', [Internal]),
        halt(1)
    ;   scan_sees_every_planted_reach(Total, Missed),
        (   Missed == []
        ->  format("library surface: no library reaches past the published \c
                    surface in ~d clauses, and the walk saw a planted reach by \c
                    each of ~d doors~n", [Examined, Total])
        ;   length(Missed, Blind),
            Seen is Total - Blind,
            format(user_error,
                   'the library surface walk saw ~d of ~d planted reaches, so \c
                    its clean result says nothing~nit is blind to: ~w~n',
                   [Seen, Total, Missed]),
            halt(1)
        )
    ).
report([First|Rest], Examined) :-
    Reaches = [First|Rest],
    findall(Callee, member(Callee-_, Reaches), Callees0),
    sort(Callees0, Callees),
    length(Callees, Count),
    format(user_error,
           "library surface: ~d engine predicates are called from lib/ \c
            without being published, over ~d clauses~n", [Count, Examined]),
    forall(member(Callee, Callees),
           ( findall(Caller, member(Callee-Caller, Reaches), Callers),
             format(user_error, "  ~w~t~34| ~w~n", [Callee, Callers]) )),
    format(user_error,
           "each is a decision: publish it with ext_point_kind(Name/Arity, \c
            service) in engine/ext_points.pl, or change the library not to need \c
            it~n", []),
    % halt/1 rather than failing, because a failed initialization goal prints
    % `user:main: false` over the report it just produced.
    halt(1).
