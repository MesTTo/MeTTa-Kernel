% Purpose: the DEVELOPMENT build, where a PlDoc mode line above a clause is a
%   checked type and `swipl -O` compiles the same clause to nothing extra.
%
%   Loading this file is the whole mechanism. It puts vendor/ on the library
%   path and imports mavis, whose expansion is a GLOBAL user:term_expansion, so
%   every file consulted AFTER it that carries a mode line gets `the/2` goals at
%   the head of its clause bodies. engine/*.pl gains no directive, no import and no
%   dependency: a production run never loads this file and never sees mavis, and
%   a mode line there is a comment like any other.
%
%   Two ways to use it, both from tests/prolog, which is where check.sh runs
%   every Prolog lane from:
%
%     swipl -q --on-error=status -g dev_typed_report -t 'halt(0)' dev_typed.pl
%       loads the engine typed and prints every predicate that gained checks.
%
%     swipl -q -g dev_typed_suites -t 'halt(0)' dev_typed.pl -- spaces.plt
%       runs existing plunit suites against the typed engine, which is what
%       says the annotations are TRUE of everything those suites do. The suites
%       come through argv rather than as further script files, because swipl
%       takes exactly one script file and treats the rest as arguments:
%       `swipl dev_typed.pl spaces.plt` loaded dev_typed.pl, put spaces.plt in
%       argv, and printed "No tests to run" [measured 2026-08-19].
%
%   The pack's own contract for a check is `when(ground(Value), must_be(Type,
%   Value))`, so a bound argument is checked at the call and an unbound one is
%   checked if and when it becomes ground. That is the whole reason the
%   annotated arguments are the ones that arrive GROUND, and it is a
%   correctness rule rather than a taste: a check on a non-ground value is a
%   when/2 coroutine, an ATTRIBUTE on every variable in that value, and a term
%   carrying one is no longer a VARIANT of the same term without one. The
%   engine compares stored terms with =@=/2, so annotating a term under
%   construction changes answers. Two suites said so
%   [measured 2026-08-19: translator_meta_store:function_store_keeps_newest_first
%   and specializer:compound_partial_key_has_stable_anonymous_variables].
% Assumes:
%   - the working directory is tests/prolog.
%   - mavis decides at LOAD time which half of itself to compile, reading
%     current_prolog_flag(optimise), so the two builds are two processes and
%     never one process choosing [source: vendor/mavis.pl, its
%     `:- if(current_prolog_flag(optimise,true)).`].
%   - vendor/quickcheck.pl declares has_type/2 multifile and vendor/mavis.pl
%     drops its no-op checks with subsumes_term/2. Both are changes this build
%     needs and both are recorded where they were made; without the first,
%     every must_be/2 in the engine became a binding type INFERENCE
%     [measured 2026-08-19].
% Guarantees:
%   - the development build is TRANSPARENT: every plunit suite in this
%     directory passes under it, which is what dev_typed_suites/0 is for and
%     what says the annotations are TRUE rather than merely inserted
%     [measured 2026-08-19: 4,716ms for every suite typed against 4,113ms for
%     one untyped configuration, min of 3 each].
%   - dev_typed_report/0 fails the run if an annotated predicate gained NO
%     check, so a lane cannot pass because a mode line stopped parsing
%     [tested: test_the_engines_funnels_are_checked_in_the_development_build].
%   - dev_typed_selftest/0 prints `checked` or `stripped` for the planted
%     violation and never guesses which build it is in: it reads the same
%     optimise flag mavis reads
%     [tested: test_the_dev_build_checks_a_planted_type_violation_and_optimise_strips_it].
% Decides:
%   - the fixture lives here rather than in engine/, because a planted defect in
%     the engine's own source is a defect in the engine's own source.
%   - an argument that is a term under construction is left UNTYPED rather than
%     given a type that would both never be tested and change what the engine
%     stores. That is why the translation funnel carries one checked type and
%     three mode lines that record only modes.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/vendor', Vendor),
   asserta(user:file_search_path(library, Vendor)).

:- use_module(library(mavis)).
:- use_module(library(apply), [maplist/3]).

% The expansion only sees SOURCE. engine/qlf_boot.pl leaves .qlf beside every
% engine unit, and an extensionless ensure_loaded resolves a fresh one
% (boot/init.pl '$qlf_file'/5), which skips term_expansion and reports every
% funnel as 0 inserted checks. The source flag is SWI's own bypass: its
% '$qlf_file' clause loads the .pl whenever the flag is true, no artifact
% deleted, nothing racing a concurrent warm boot.
:- set_prolog_flag(source, true).

%%%%%%%%%% The planted violation, and it is planted in BOTH directions %%%%%%%%%%

% A mode line and a body that disagree with it the moment a caller passes a
% non-integer. Under the dev build the clause gains `the(integer, X)` before the
% body and the call is refused naming the type; under `swipl -O` the clause body
% is the body alone and the same call reaches the arithmetic, which reports a
% different error about a different thing.

%% dev_typed_planted_double(+Number:integer, -Doubled:integer) is det.
dev_typed_planted_double(Number, Doubled) :- Doubled is Number * 2.

% And a control with no mode line at all, so "the body changed" cannot be
% confused with "every body changed".
dev_typed_unannotated_double(Number, Doubled) :- Doubled is Number * 2.

%%%%%%%%%% Reading the two builds apart %%%%%%%%%%

% Which build this process is, asked the way mavis asks it.
dev_typed_build(Build) :-
    (   current_prolog_flag(optimise, true)
    ->  Build = optimised
    ;   Build = development
    ).

% Whether a predicate's first clause body starts with inserted the/2 goals, and
% how many. This is the clause/2 comparison the whole item rests on: the
% question is not "did it raise" but "what did it compile to".
dev_typed_inserted_checks(Head, Count) :-
    clause(Head, Body),
    dev_typed_leading_checks(Body, 0, Count).

dev_typed_leading_checks((First, Rest), Seen, Count) :- !,
    (   subsumes_term(the(_, _), First)
    ->  Next is Seen + 1,
        dev_typed_leading_checks(Rest, Next, Count)
    ;   Count = Seen
    ).
dev_typed_leading_checks(Goal, Seen, Count) :-
    ( subsumes_term(the(_, _), Goal) -> Count is Seen + 1 ; Count = Seen ).

%%%%%%%%%% The selftest %%%%%%%%%%

% Run in both builds and the two outputs are the proof:
%   swipl -q --on-error=status -g dev_typed_selftest -t 'halt(0)' dev_typed.pl
%   swipl -O -q --on-error=status -g dev_typed_selftest -t 'halt(0)' dev_typed.pl
% The control is what makes this a differential rather than an assertion about
% one predicate. `dev_typed_unannotated_double/2` is the same body with no mode
% line above it, so under -O the two clauses must be the SAME clause and the two
% calls must give the SAME error. Reading only the annotated one would let
% "stripped" mean "raised something", and under -O the raw arithmetic raises a
% type_error too, just about a different thing.
dev_typed_selftest :-
    dev_typed_build(Build),
    dev_typed_inserted_checks(dev_typed_planted_double(_, _), Annotated),
    dev_typed_inserted_checks(dev_typed_unannotated_double(_, _), Control),
    dev_typed_bodies(Bodies),
    dev_typed_outcome(dev_typed_planted_double(abc, _), AnnotatedError),
    dev_typed_outcome(dev_typed_unannotated_double(abc, _), ControlError),
    format("build: ~w~n", [Build]),
    format("annotated clause checks: ~w~n", [Annotated]),
    format("unannotated clause checks: ~w~n", [Control]),
    format("clause bodies: ~w~n", [Bodies]),
    format("annotated call: ~q~n", [AnnotatedError]),
    format("unannotated call: ~q~n", [ControlError]),
    dev_typed_selftest_verdict(Build, Annotated, Control, Bodies,
                               AnnotatedError, ControlError).

dev_typed_outcome(Goal, Outcome) :-
    ( catch(Goal, Error, true) -> ( var(Error) -> Outcome = succeeded ; Outcome = Error )
    ; Outcome = failed ).

% The clause/2 comparison the item rests on: what the two clauses COMPILED to,
% not what they did when called.
dev_typed_bodies(Verdict) :-
    clause(dev_typed_planted_double(_, _), Annotated),
    clause(dev_typed_unannotated_double(_, _), Control),
    ( Annotated =@= Control -> Verdict = identical ; Verdict = different ).

dev_typed_selftest_verdict(development, Annotated, Control, Bodies,
                           AnnotatedError, ControlError) :-
    !,
    (   Annotated >= 2, Control =:= 0, Bodies == different,
        subsumes_term(error(type_error(integer, abc), _), AnnotatedError),
        subsumes_term(error(type_error(evaluable, abc/0), _), ControlError)
    ->  format("verdict: checked~n", [])
    ;   format(user_error,
               "the development build did not check the planted violation~n", []),
        halt(1)
    ).
dev_typed_selftest_verdict(optimised, Annotated, Control, Bodies,
                           AnnotatedError, ControlError) :-
    % The two errors agree on the FORMAL part and differ only in the context,
    % which names whichever predicate reported it and therefore must differ.
    (   Annotated =:= 0, Control =:= 0, Bodies == identical,
        AnnotatedError = error(Formal, _), ControlError = error(Formal, _),
        subsumes_term(type_error(evaluable, abc/0), Formal)
    ->  format("verdict: stripped~n", [])
    ;   format(user_error,
               "the optimised build did not strip the planted check~n", []),
        halt(1)
    ).

%%%%%%%%%% The report over the engine %%%%%%%%%%

% Every annotated predicate in the engine, and how many checks its first clause
% gained. A lane runs this: it consults the engine typed, which is itself the
% check that no annotation is malformed, and it FAILS if the total is zero,
% because a mode line that stopped parsing would otherwise read as success.
dev_typed_report :-
    dev_typed_engine,
    dev_typed_build(Build),
    format("build: ~w~n", [Build]),
    findall(Indicator-Clauses-Checks,
            ( dev_typed_annotated(Name, Arity),
              Indicator = Name/Arity,
              functor(Head, Name, Arity),
              findall(Count, dev_typed_inserted_checks(Head, Count), PerClause),
              length(PerClause, Clauses),
              sum_list(PerClause, Checks) ),
            Found),
    forall(member(Indicator-Clauses-Checks, Found),
           format("~w: ~w clause(s), ~w inserted check(s)~n",
                  [Indicator, Clauses, Checks])),
    maplist(dev_typed_checks, Found, Counts),
    sum_list(Counts, Total),
    length(Found, Predicates),
    format("typed: ~w predicates, ~w inserted checks~n", [Predicates, Total]),
    findall(Indicator, member(Indicator-_-0, Found), Unchecked),
    % A mode line has to be its own comment block: a `%%` line under a `%` line
    % is one comment starting with `%`, which is not a structured comment, and
    % PlDoc silently collects nothing. spaces:unstore_atom/3 was written that way and
    % reported 0 while every other funnel reported its checks [measured
    % 2026-08-19], so an annotation that stopped parsing FAILS the report
    % rather than quietly leaving one funnel unchecked.
    (   Build == development, Unchecked \== []
    ->  forall(member(Indicator, Unchecked),
               format(user_error,
                      "~w is listed as annotated and gained no check: its mode \c
                       line is not a structured comment, or the expansion \c
                       stopped firing~n", [Indicator])),
        halt(1)
    ;   true
    ).

dev_typed_checks(_-_-Checks, Checks).

%%%%%%%%%% Running the existing suites typed %%%%%%%%%%

% The report says the checks were INSERTED; this says they are TRUE. Every
% plunit suite named on argv is consulted here rather than passed as a further
% script file, because swipl takes exactly one of those.
dev_typed_suites :-
    current_prolog_flag(argv, Suites),
    (   Suites == []
    ->  format(user_error,
               "dev_typed_suites: name at least one .plt file after --~n", []),
        halt(2)
    ;   true
    ),
    forall(member(Suite, Suites), consult(Suite)),
    ( run_tests -> true ; halt(1) ).

% The engine, loaded once. A .plt used as the second file has already consulted
% it by the time an initialization goal runs, so this must not consult twice.
dev_typed_engine :-
    (   current_predicate(user:swrite/2)
    ->  true
    ;   consult('../../engine/metta.pl')
    ).

% The funnels annotated so far. Named here rather than discovered, because
% "which predicates are supposed to be typed" is the thing a report should be
% able to be WRONG about: a predicate that lost its mode line shows up as zero
% checks instead of vanishing from the list.
dev_typed_annotated(metta_remove_atom, 3).
dev_typed_annotated(unstore_atom, 3).
dev_typed_annotated(remove_equation, 6).
dev_typed_annotated(translate_clause, 3).
