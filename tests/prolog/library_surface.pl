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
%       [tested: scan_sees_every_planted_reach, one planted door per way a
%       call hides; commit=8fa9d546b3eebf3424ef1d667feab40c6b0f32ae]
%     - exits nonzero when a shipped .metta library writes a head pattern
%       against a name the ENGINE gives meaning to, which the compiler matches
%       structurally and the engine's function then consumes
% Fails when:
%     - a call is assembled at run time from a term no analysis can see,
%       `Goal =.. L, call(Goal)` being the shape. That is the residue this
%       shares with every other static walk in the tree.
% Decides:
%     - lib/ is in scope and extensions/python/metta/shim.pl is not. shim.pl is consulted
%       by _engine.py as the Python tier's own implementation, so it is
%       engine-internal by construction rather than an extension
%       [source: extensions/python/metta/_engine.py, _consult_shim].
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
    consult('../../engine/qlf_boot.pl'),
    consult('../../engine/metta.pl'),
    forall(( expand_file_name('../../lib/*/*.pl', Files), member(File, Files) ),
           ensure_loaded(File)),
    library_directories(Directories),
    reaches_past_surface(Directories, Reaches0),
    findall(Callee-Caller, member(Caller-Callee, Reaches0), Reaches1),
    sort(Reaches1, Reaches),
    extension_clause_count(Directories, Examined),
    report(Reaches, Examined),
    no_library_shadows_an_engine_function.

%%%% The .metta half: a library must not write a head pattern against an
%%%% engine function's name %%%%
%
% The .pl half above asks what a library CALLS. This asks what a library
% NAMES, which is the same contract one tier down: lib/lib_pln/lib_pln.metta wrote
% (Evaluation (Predicate $x) ...) as PLN's predicate atom, and Predicate is the
% engine's Prolog-interop builder, the one callPredicate and assertaPredicate
% take their goal term from. A head-argument position holding a name the engine
% gives meaning to is matched STRUCTURALLY, so the rule only fires for a caller
% that hands the term unevaluated, and every ordinary caller evaluates it first
% and arrives as something else. Three PLN rules answered nothing at all for as
% long as that was true, and the file's own tests could not see it because no
% shipped example uses those rules [measured 2026-08-22: !(Predicate likes)
% answers [], and the three rules answered [] until the constructor was renamed
% to upstream's own PredicateNode].
%
% The engine already NOTICES this and says so through head_pattern_note/5. What
% was missing is that nobody was listening: the note goes to print_message/2 at
% import, where an import that prints and succeeds looks exactly like one that
% does not. Reading the table is what turns the note into an answer.
%
% Translated rather than imported, so nothing here starts a Redis connection or
% calls an LLM: translate_clause/2 alone raises the note
% [measured 2026-08-22].
library_metta_source(File) :-
    tree_directory('../../lib', Directory),
    directory_member(Directory, File, [recursive(true), extensions([metta])]).

library_equation(File, Form) :-
    library_metta_source(File),
    catch(( filereader:read_metta_source(File, Source),
            parse_metta_source(Source, Forms) ), _, fail),
    member(parsed(function, _, Form), Forms),
    Form = [=, _, _].

% Qualified, because head_pattern_note/5 is engine/translator.pl's table and an
% unqualified retractall here would make a second one in THIS module and clear
% that instead, leaving every note standing and this check reporting clean.
%BOTH reasons, because both say the same thing about the same head pattern:
%the engine gives that name a meaning. `defined_label(Route)` is a label whose
%name resolves through head_meaning_route/3; `functional_pattern` is a head
%argument that is a CALL to a known function, which the compiler runs backwards
%(engine/translator/analysis.pl, head_pattern_reason/7).
%
%Reading only defined_label/1 is what this check did until 2026-08-30, and
%functional patterns took the planted Predicate shadow out of its reach: the
%walk reported clean over every library while its own planted fault went
%unnamed. The self-test below is what said so, which is the whole reason it
%exists.
library_shadow(File, Fun, Label, Route) :-
    library_equation(File, Form),
    retractall(translator:head_pattern_note(_, _, _, _, _)),
    catch(translate_clause(Form, _), _, true),
    translator:head_pattern_note(_, Fun, _, Label, Reason),
    engine_meaning_reason(Reason, Route).

engine_meaning_reason(defined_label(Route), Route).
engine_meaning_reason(functional_pattern, functional_pattern).

no_library_shadows_an_engine_function :-
    findall(File-Fun-Label-Route, library_shadow(File, Fun, Label, Route),
            Shadows0),
    sort(Shadows0, Shadows),
    aggregate_all(count, library_equation(_, _), Equations),
    shadow_report(Shadows, Equations).

shadow_report([], Equations) :-
    !,
    (   planted_library_shadow_is_named
    ->  format("library surface: no head pattern in ~d shipped library \c
                equations names an engine function, and the check named a \c
                planted one~n", [Equations])
    ;   format(user_error,
               'the library head-pattern check reported clean against a \c
                planted shadow of the engine\'s Predicate, so its clean result \c
                says nothing~n', []),
        halt(1)
    ).
shadow_report(Shadows, Equations) :-
    length(Shadows, Count),
    format(user_error,
           "library surface: ~d head pattern(s) in ~d shipped library equations \c
            name a function the engine defines~n", [Count, Equations]),
    forall(member(File-Fun-Label-Route, Shadows),
           format(user_error,
                  "  ~w~t~40| ~w matches ~w, which the engine gives meaning to \c
                   as a ~w~n", [File, Fun, Label, Route])),
    format(user_error,
           "that position is matched structurally, so the rule fires only for a \c
            caller that hands the term unevaluated and the engine's own ~w \c
            consumes every other one. Rename the library's constructor~n", []),
    halt(1).

% The plant is an equation of the shape the real one had, translated through
% the same door, so a check that stops reading the table fails here rather than
% at the next library to collide.
planted_library_shadow_is_named :-
    sread("(= (metta-planted-shadow ((Evaluation (Predicate $x)) $t)) $x)", Form),
    retractall(translator:head_pattern_note(_, _, _, _, _)),
    catch(translate_clause(Form, _), _, true),
    translator:head_pattern_note(_, 'metta-planted-shadow', _, 'Predicate',
                                 Reason),
    engine_meaning_reason(Reason, _),
    retractall(translator:head_pattern_note(_, _, _, _, _)).

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
           "each is a decision: publish it with seam:kind(Name/Arity, \c
            service) in engine/ext_points.pl, or change the library not to need \c
            it~n", []),
    % halt/1 rather than failing, because a failed initialization goal prints
    % `user:main: false` over the report it just produced.
    halt(1).
