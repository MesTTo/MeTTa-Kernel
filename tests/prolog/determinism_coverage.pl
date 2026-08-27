% Purpose: report which registered library predicates carry no determinism
%   declaration, so a leftover choice point in one has something that says so.
% Assumes:
%   - det/1 is the only determinism DIRECTIVE SWI has; semidet and nondet
%     appear in its libraries only inside PlDoc comments
%     [measured 2026-08-16: det/1 defined in system, the other four absent].
% Guarantees:
%   - a predicate SWI marked det is not reported, whether the declaration is
%     written here or came from a library's own :- det(...) [tested by running
%     it: lib_string, lib_json and lib_file report nothing].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

% A leftover choice point costs its caller about twice and is INVISIBLE to the
% inference counter: no-cut, cut and SSU dispatch of one workload all reported
% exactly 1,000,003 inferences while wall clock was 0.1887, 0.0928 and 0.1128.
%
% Two things already catch one. plunit fails the gate on any test that
% succeeds with a choicepoint, and SWI's det/1 raises at the predicate's own
% door for anything declared. Between them sits the gap this reports: a
% registered predicate that no test happens to call and that declares nothing.
%
% A REPORT rather than a GATE, and deliberately. Plenty of these are correctly
% nondeterministic, `get-keys` answering one key per solution the way
% `get-atoms` does, and a gate would demand a declaration for its own sake.
% What the list is for is deciding, once, which each one is.
main :-
    consult('../../engine/metta.pl'),
    metta_host_set_silent(true),
    load_reported_libraries,
    findall(Name/Arity, undeclared_library_predicate(Name, Arity), Undeclared0),
    sort(Undeclared0, Undeclared),
    length(Undeclared, Count),
    findall(D, declared_det(D), Declared0),
    sort(Declared0, Declared),
    length(Declared, DeclaredCount),
    format("determinism coverage: ~d registered library predicates declared \c
            det, ~d undeclared~n", [DeclaredCount, Count]),
    forall(member(Name/Arity, Undeclared),
           format("  ~w/~w~n", [Name, Arity])),
    ( Undeclared == []
      -> format("every registered library predicate declares its determinism~n")
      ;  true ).

%The libraries whose predicates this reports on. They load on import! rather
%than with the engine, so an engine that imported nothing has nothing to
%report and would answer "every one declares" while checking none.
reported_library(lib_string).   reported_library(lib_json).
reported_library(lib_file).     reported_library(lib_memo).
reported_library(lib_tabling).  reported_library(lib_text).
reported_library(lib_thread).   reported_library(lib_math).

load_reported_libraries :-
    forall(reported_library(Library),
           ( format(atom(Form), "!(import! &self (library ~w))", [Library]),
             catch(process_metta_string(Form, _), _, true) )).

declared_det(Name/Arity) :-
    registered_library_predicate(Name, Arity),
    functor(Head, Name, Arity),
    predicate_property(user:Head, det).

undeclared_library_predicate(Name, Arity) :-
    registered_library_predicate(Name, Arity),
    functor(Head, Name, Arity),
    \+ predicate_property(user:Head, det).

% A registered MeTTa function whose clauses came from a file under lib/. The
% file is read off a clause rather than off predicate_property(file(_)),
% which reports the FIRST file to define a predicate and so answers the wrong
% library after a redefinition.
registered_library_predicate(Name, Arity) :-
    fun(Name),
    arity(Name, Arity),
    functor(Head, Name, Arity),
    catch(nth_clause(user:Head, 1, Ref), _, fail),
    clause_property(Ref, file(File)),
    sub_atom(File, _, _, _, '/lib/').
