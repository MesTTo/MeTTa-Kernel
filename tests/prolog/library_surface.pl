% Purpose: report which engine predicates the shipped libraries call that are
%     not published surface. A REPORT, not a gate, and deliberately so.
% Assumes:
%     - surface_walk.pl decides what published means, so this file and the
%       backend GATE in static_checks.pl cannot drift apart on the definition
% Guarantees:
%     - exits nonzero when a library reaches past the published surface, which
%       check.sh reads as findings rather than as a break
%     - names the library and the predicate, grouped by callee, so the output
%       is a work list rather than a wall
% Fails when:
%     - taken for a gate. It is not one YET, and the reason is a decision
%       nobody has made: whether the library tier is meant to be arm's length
%       from the engine the way a backend is. Roughly twenty predicates are
%       involved and they are not one kind of thing. current_metta_module/1 and
%       parse_metta_source/2 read like a library API worth publishing;
%       native_storage_module/2 and space_module/2 read like plumbing a library
%       should not be touching. Declaring all of them service would make the
%       declaration mean nothing, which is worse than leaving it undeclared,
%       so the list is printed until somebody decides it one entry at a time.
% Decides:
%     - lib/ is in scope and bindings/python/petta/shim.pl is not. shim.pl is consulted
%       by _engine.py as the Python tier's own implementation, so it is
%       engine-internal by construction rather than an extension
%       [source: bindings/python/petta/_engine.py, _consult_shim].
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: decide the library tier's surface and promote this
%         to a GATE beside a_backend_calls_only_published_surface.

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
    format("library surface: no library reaches past the published surface \c
            in ~d clauses~n", [Examined]).
report([First|Rest], Examined) :-
    Reaches = [First|Rest],
    findall(Callee, member(Callee-_, Reaches), Callees0),
    sort(Callees0, Callees),
    length(Callees, Count),
    format("library surface: ~d engine predicates are called from lib/ \c
            without being published, over ~d clauses~n", [Count, Examined]),
    forall(member(Callee, Callees),
           ( findall(Caller, member(Callee-Caller, Reaches), Callers),
             format("  ~w~t~34| ~w~n", [Callee, Callers]) )),
    format("each is a decision: publish it with ext_point_kind(Name/Arity, \c
            service) in engine/ext_points.pl, or change the library not to need \c
            it~n"),
    % Findings, which check.sh reads from the exit status. halt/1 rather than
    % failing, because a failed initialization goal prints `user:main: false`
    % over the report it just produced.
    halt(1).
