% Purpose: run SWI's source checks after compiling representative MeTTa code,
%     and enforce the two rules about src/ext_points.pl's seams that no SWI
%     check knows about: every seam declares its kind, and a seam whose kind
%     says every clause runs carries no cut.
% Assumes:
%   - ext_point_kind/2 in src/ext_points.pl is the taxonomy. This file reads it
%     rather than restating it, which is the whole point: the restated list it
%     replaced had metta_backend_selftest/0 missing and metta_dispatch_call/4
%     wrongly present [source: their call sites, main.pl:36 and
%     translator.pl:350].
%   - space_module/2 (src/spaces.pl:231-232) and native_storage_module_cache/2
%     (src/spaces.pl:54) are the engine's own, and correct, record of which
%     modules exist; candidate_engine_module/1 below discovers modules through
%     them rather than by naming one, which is what keeps every check in this
%     file from hardcoding `user` [source: ai-phase11-module-survey.md
%     section 1.2, workspace root, "space_module/2 is the only door"].
% Guarantees:
%   - The driver runs the four reviewed library(check) predicates and check/0
%     after a function with control flow has been compiled.
%   - var_branches warnings are fatal for repository engine sources without
%     attributing warnings from SWI's own libraries to the repository.
%   - Every unqualified multifile seam declared anywhere under src, lib,
%     python/petta or mork_ffi has exactly one ext_point_kind/2 fact, so a new
%     seam cannot go quietly unchecked [measured 2026-08-17: 28 seams].
%   - Each kind is declared the way its direction requires: a handler seam
%     multifile so an extension can add clauses, a service not, so a caller
%     cannot redefine what it was published to call
%     [measured 2026-08-17: 28 handler seams and 7 services].
%   - No cut in any clause of a seam whose kind says every clause runs,
%     checked twice over because neither reading sees the other's clauses: the
%     tree's sources including the clauses directives assert, and the live
%     database after the libraries load, which is the only way to see a
%     handler installed at run time, in every module candidate_engine_module/1
%     discovers rather than only in `user`
%     [measured 2026-08-19: 0 offenders in 19 source clauses and 71 live
%     ones].
%   - No backend calls an engine predicate that is not published surface: a
%     declared service, a declared seam, or a MeTTa builtin. The walk is SWI's
%     own prolog_walk_code/1, the one list_undefined/0 uses, so it reaches a
%     call through control structure, through a declared meta-argument, and
%     through a meta-predicate nobody declared, which it infers
%     [measured 2026-08-17: 0 offenders in 24 backend clauses].
%   - No compile-time-only helper reaches a generated clause body, over source
%     exercising a lambda, the three collection forms, sealed, and a
%     higher-order call the specializer takes. The walk covers every COMPOUND
%     SUBTERM of every clause of every registered function, in every module
%     candidate_engine_module/1 discovers rather than only in `user`
%     [measured 2026-08-19: 0 offenders in 276 bodies; up from 241 on
%     2026-08-17 as the prelude grew, plus one genuinely new body this walk
%     reaches that the `user`-only one never did: library(yall)'s own `/`/3,
%     reachable from `system` and distinct from, but same name and arity as,
%     the engine's MeTTa `/` in `user`].
%   - Five of the six checks prove themselves non-vacuous against a planted
%     offender before a clean result is accepted, and report WHICH plant
%     stopped firing rather than only that one did. This is not ceremony, and
%     every one of them has been wrong, the seam-direction probe within minutes
%     of being written: it planted swrite/2 to test the "a service must not be
%     multifile" fault, swrite/2 is not multifile, and the probe said so
%     instead of passing. The goal-position version of the helper
%     walk reported clean against a planted `>>`, the live hook scan reported
%     clean against a planted cut until cut_in_clause_scope/1 learned to
%     descend module qualification, and the backend surface walk reported clean
%     against maplist(register_prolog_arities, []) while it read clause bodies
%     by hand. Teaching it meta_predicate specs fixed that case and left the
%     one that mattered more, a backend's OWN helper taking a goal without
%     declaring itself a meta-predicate, which is why the walk is SWI's now
%     and its four doors are asserted as real clauses and walked for real.
%   - Two of those five, the compile-time-helper walk and the live-hook scan,
%     plant into a SECOND module as well as the one &self compiles into today,
%     one created at runtime and named and classed the way a Phase 11
%     execution module will be, and both plants have to be found for the
%     check to accept a clean result. That is the module-agnostic discovery
%     proved against two topologies at once, not just asserted
%     [measured 2026-08-19: no_compile_time_helper_in_a_compiled_body and
%     no_cut_in_a_live_hook_clause below].
% Fails when:
%   - a function is compiled into a space whose storage is FOREIGN (backed by
%     an external provider such as MORK) rather than native. See
%     known_metta_space/1's own note below; this is unchanged from before this
%     file discovered modules instead of naming `user`, since the `user`-only
%     walk never looked at a foreign space's module either.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(check)).
:- use_module(library(solution_sequences)).

%%%% Which modules the engine's predicates can live in %%%%
%
% Every check below used to assume `user`, which is where &self's compiled
% clauses and the engine's own seams happen to live TODAY because nothing in
% the tree has ever given them a module of their own. Phase 11
% (ai-phase11-module-survey.md section 2.1, workspace root) gives &self its
% own execution module, '$petta_exec:&self', based on a shared '$petta_core',
% and every other space '$petta_exec:<Space>' beside it. A check that keeps
% naming `user` would then examine the one module nothing compiles into any
% more and report clean, which is the failure this section exists to close.
%
% The fix asks the engine rather than guessing a name. space_module/2 is
% already the one place that answers "which module does this space compile
% into" (src/spaces.pl:231-232, ai-phase11-module-survey.md section 1.2's
% "only door"), so every space the engine currently knows about is walked up
% its OWN import chain and every module the walk visits is a candidate.
%
% default_module/2 is the walk, not current_module/1 or current_predicate/2
% run with the module argument unbound. Both of those silently skip any
% module whose SWI class is `system` when asked to GENERATE one, and
% `system` is exactly the class SWI gives an implicitly-created module named
% with a leading `$` [SWI-Prolog 10.1 Reference Manual sections 6.13, 6.15]
% -- precisely how a per-space execution module comes to exist, since a
% space's name is not known until the MeTTa program that creates it runs.
% default_module/2 walks from a MODULE THAT IS ALREADY KNOWN rather than
% generating over every module that exists, and that is what keeps it
% working: a bound starting point is a lookup, not an enumeration, so the
% class that hides a module from current_module/1's generate mode never
% enters into it [measured 2026-08-19: current_predicate(_, M:Head) called
% with M unbound found a class(user) module holding the target predicate
% and missed a sibling class(system) module holding the identical predicate
% under the identical name; default_module/2 walked from a bound starting
% module reached the class(system) module every time. Confirmed against the
% fully loaded engine plus a runtime-created second space and, further, a
% runtime-created module named and classed the way a Phase 11 execution
% module will be -- see no_compile_time_helper_in_a_compiled_body's and
% no_cut_in_a_live_hook_clause's anti-vacuity probes below, which are that
% same rehearsal turned into a standing check].
%
% known_metta_space/1 does not need its own proof of completeness: it reads
% native_storage_module_cache/2, the STORAGE family's own registry
% (src/spaces.pl:54), which every native add-atom or equation already
% populates as a side effect of storing into a space
% (src/spaces.pl:79-98,134-135,399-402), so it grows exactly when a space
% becomes worth scanning. '&self' is listed explicitly besides, because the
% invariant that it is always pre-seeded (src/spaces.pl:104) belongs to
% spaces.pl to keep, not to this file to assume silently.
%
% Fails when: a function is compiled into a FOREIGN space (one backed by an
% external provider such as MORK). add_equation/4's foreign clause
% (src/spaces.pl:394-398) compiles into that space's execution module the
% same way a native one does, but deliberately does not touch the native
% storage cache, so such a space is invisible to known_metta_space/1. This
% is not a narrowing: the `user`-only walk it replaces never looked at any
% space but &self either, foreign or native.
known_metta_space('&self').
known_metta_space(Space) :- native_storage_module_cache(Space, _).

candidate_engine_module(Module) :-
    distinct(Module,
             ( known_metta_space(Space),
               space_module(Space, SpaceModule),
               default_module(SpaceModule, Module) )).

:- ensure_loaded(surface_walk).
:- initialization(main, main).

main :-
    consult('../../src/metta.pl'),
    check_project_var_branches,
    every_seam_declares_one_kind,
    every_seam_kind_matches_its_direction,
    no_cut_in_an_event_hook,
    retractall(silent(_)),
    assertz(silent(true)),
    representative_source(Source),
    process_metta_string(Source, [3]),
    no_compile_time_helper_in_a_compiled_body,
    list_trivial_fails,
    list_redefined,
    list_void_declarations,
    list_autoload,
    check,
    a_backend_calls_only_published_surface,
    no_cut_in_a_live_hook_clause,
    every_engine_emitted_goal_is_protected.

%%%% Every seam declares one kind %%%%
%
% src/ext_points.pl gives each multifile seam an ext_point_kind/2 fact on the
% line after its declaration, and the two checks below read those rather than
% keeping a list of their own. That only works if the annotation is TOTAL: a
% seam added without a kind is silently exempt from the cut check, which is
% the drift this arrangement exists to stop. Restating the list by hand is
% what put metta_backend_selftest/0 outside the check and metta_dispatch_call/4
% wrongly inside it. So the declarations are read back out of the source and
% each one is required to have exactly one kind.
%
% A module-qualified seam is somebody else's protocol. prolog:message//1 and
% user:thread_message_hook/3 are SWI's and their contract is fixed there, so
% the shape below matches an unqualified indicator only and passes over them.
declared_seam(File, Seam) :-
    hook_source_file(File),
    source_term(File, (:- multifile Spec)),
    multifile_indicator(Spec, Seam).

multifile_indicator(Spec, _) :- var(Spec), !, fail.
multifile_indicator((A, B), Seam) :-
    !, ( multifile_indicator(A, Seam) ; multifile_indicator(B, Seam) ).
multifile_indicator(Name/Arity, Name/Arity) :- atom(Name), integer(Arity).
multifile_indicator(Name//Arity, Name/Total) :-
    atom(Name), integer(Arity), Total is Arity + 2.

every_seam_declares_one_kind :-
    findall(Seam, declared_seam(_, Seam), Declared0),
    sort(Declared0, Declared),
    findall(Seam-Count-File,
            ( member(Seam, Declared),
              aggregate_all(count, ext_point_kind(Seam, _), Count),
              Count =\= 1,
              once(declared_seam(File, Seam)) ),
            Wrong),
    (   Wrong == []
    ->  length(Declared, Total),
        aggregate_all(count, ext_point_every_clause_runs(_), Checked),
        format("static: ~d extension-point seams each declare one kind, \c
                ~d of which have every clause run~n", [Total, Checked])
    ;   forall(member(Seam-Count-File, Wrong),
               format(user_error,
                      'the seam ~w in ~w has ~d ext_point_kind/2 facts and \c
                       needs exactly one~ngive it event, ownership or \c
                       declaration on the line after its declaration, or the \c
                       cut check passes over it~n',
                      [Seam, File, Count])),
        fail
    ).

%%%% No cut in an event hook %%%%
%
% src/ext_points.pl states the rule this enforces: an OWNERSHIP seam answers
% one provider's request and may cut after its ownership test, while an EVENT
% or DECLARATION seam has every clause read and a cut in one of them silently
% disables every clause loaded after it. Only the second kind is checked,
% which is what makes the rule usable: lib/lib_redis.pl's cuts are correct
% and stay.
%
% lib/lib_tabling.pl cut after metta_tabling_declared, a global condition
% rather than an ownership test. With tabling declared, src/duals.pl's
% invalidation handler was ordered after it and never ran, so a changed
% function kept a stale dual and (not-provable (pq 2)) answered True and
% False at once. Nothing in the tree would have said so.
event_hook(Name, Arity) :- ext_point_every_clause_runs(Name/Arity).

no_cut_in_an_event_hook :-
    findall(File-Name/Arity,
            ( hook_source_file(File),
              event_hook_clause(File, Name, Arity, Body),
              cut_in_clause_scope(Body) ),
            Offenders),
    (   Offenders == []
    ->  source_scan_sees_a_planted_cut
    ;   forall(member(File-Indicator, Offenders),
               format(user_error,
                      'cut in an event hook clause: ~w in ~w~n\c
                       use ( Condition -> Action ; true ), which keeps the \c
                       guard and prunes no later handler~n',
                      [Indicator, File])),
        fail
    ).

% The same discipline the other two walks in this file carry: a scan that
% finds nothing and a scan that reads nothing print the same line. Two halves,
% because this scan has two halves. The count proves file discovery and
% reading reach real hook clauses, which is the part a changed directory list
% or a changed kind table would silently break; and a planted term proves the
% cut walker fires, once for a clause written in a file and once for one a
% directive asserts, which are separate paths through hook_clause_term/4 and
% only the first would otherwise be exercised.
source_scan_sees_a_planted_cut :-
    aggregate_all(count,
                  ( hook_source_file(File), event_hook_clause(File, _, _, _) ),
                  Examined),
    Written  = (metta_on_atom_added(_, _) :- (!, fail)),
    Asserted = (:- assertz((metta_on_atom_added(_, _) :- (!, fail)))),
    aggregate_all(count,
                  ( member(Term, [Written, Asserted]),
                    hook_clause_term(Term, _, _, Body),
                    cut_in_clause_scope(Body) ),
                  Seen),
    (   Examined >= 1, Seen =:= 2
    ->  format("static: no cut in any of ~d hook clauses across the tree's \c
                sources, and the scan saw a planted one by each door~n",
               [Examined])
    ;   format(user_error,
               'the source hook scan read ~d clauses and saw ~d of 2 planted \c
                cuts, so its clean result says nothing~n', [Examined, Seen]),
        fail
    ).

hook_source_file(File) :-
    member(Directory, ['../../src', '../../lib', '../../python/petta',
                       '../../mork_ffi']),
    atom_concat(Directory, '/*.pl', Pattern),
    expand_file_name(Pattern, Files),
    member(File, Files).

% Both spellings a handler arrives by: a clause in the file, and a clause
% asserted at run time, which is how a handler that should cost nothing until
% its feature is used installs itself.
event_hook_clause(File, Name, Arity, Body) :-
    source_term(File, Term),
    hook_clause_term(Term, Name, Arity, Body).

hook_clause_term(Term, Name, Arity, Body) :-
    nonvar(Term),
    (   Term = (Head :- Body0)
    ->  clause_head_hook(Head, Name, Arity), Body = Body0
    ;   Term = (:- Directive)
    ->  asserted_hook_clause(Directive, Name, Arity, Body)
    ;   fail
    ).

asserted_hook_clause(Goal, Name, Arity, Body) :-
    nonvar(Goal),
    (   Goal =.. [Assert, Clause], memberchk(Assert, [assertz, asserta, assert]),
        nonvar(Clause), Clause = (Head :- Body),
        clause_head_hook(Head, Name, Arity)
    ->  true
    ;   Goal =.. [_|Arguments],
        member(Argument, Arguments),
        asserted_hook_clause(Argument, Name, Arity, Body)
    ).

clause_head_hook(Head, Name, Arity) :-
    nonvar(Head),
    ( Head = _:Plain -> true ; Plain = Head ),
    nonvar(Plain),
    functor(Plain, Name, Arity),
    event_hook(Name, Arity).

source_term(File, Term) :-
    setup_call_cleanup(prolog_open_source(File, Stream),
                       source_stream_term(Stream, Term),
                       prolog_close_source(Stream)).

source_stream_term(Stream, Term) :-
    repeat,
    prolog_read_source_term(Stream, Read, _, []),
    ( Read == end_of_file -> !, fail ; Term = Read ).

%%%% No cut in a live hook clause %%%%
%
% The source scan reads every clause a file writes, including one a directive
% asserts, and that is still not all of them. lib/lib_thread.pl installs a
% metta_on_atom_added/2 handler from inside space_await_/4, Python
% subscriptions install their own, and a body built at run time is in no file
% to read. So the same rule is applied a second way, to the clauses that are
% actually in the database.
%
% Neither scan subsumes the other: this one sees only what this process has
% installed, and the source one sees a file nothing has loaded. The libraries
% are loaded first so their handlers are among the clauses, and that happens
% last in main/0 so a library load cannot perturb an earlier check.
% Walking every candidate module means a predicate that is only INHERITED
% (never locally defined) is reachable from more than one of them: SWI
% resolves a module-qualified clause/current_predicate query through the
% whole import chain, not just the named module, so the same physical
% clause answers under every descendant's name too
% [measured 2026-08-19: clause(Descendant:Head, Body, Ref) and
% clause(Ancestor:Head, Body, Ref) returned the IDENTICAL clause reference
% for a predicate defined only in Ancestor]. distinct/2 keyed on that
% reference, not on the (Module, Body) pair, is what keeps a shared or
% inherited clause counted once no matter how many candidate modules can
% see it.
live_hook_clause(Name/Arity, Body) :-
    ext_point_every_clause_runs(Name/Arity),
    functor(Head, Name, Arity),
    distinct(Ref,
             ( candidate_engine_module(Module),
               current_predicate(_, Module:Head),
               catch(clause(Module:Head, Body, Ref),
                     error(permission_error(_, _, _), _), fail) )).

no_cut_in_a_live_hook_clause :-
    forall(library_source(Library), ensure_loaded(Library)),
    findall(Seam,
            ( live_hook_clause(Seam, Body), cut_in_clause_scope(Body) ),
            Offenders0),
    sort(Offenders0, Offenders),
    (   Offenders == []
    ->  live_scan_sees_a_planted_cut
    ;   forall(member(Seam, Offenders),
               format(user_error,
                      'cut in a live clause of ~w, whose kind says every \c
                       clause runs~nit prunes every clause installed after \c
                       it; use ( Condition -> Action ; true )~n', [Seam])),
        fail
    ).

library_source(Library) :-
    expand_file_name('../../lib/*.pl', Files),
    member(Library, Files).

% A scan that finds nothing and a scan that looks at nothing print the same
% line, so the clean result is only accepted after the same walk has been
% shown to see a planted offender. The seam it plants into is dynamic and its
% handlers run on function removal, and the clause is retracted either way.
%
% The plant itself is discovered rather than named, via the same
% candidate_engine_module/1 the scan uses, so it moves with the scan instead
% of naming `user` beside it: a probe that cannot move with the scan is not a
% proof the scan still works after the scan's own target moves.
%
% A second, DIFFERENT space is planted alongside &self, created at runtime and
% given its execution module by space_module/2 exactly as a real one is, and
% registered as a known space the same way (src/spaces.pl's
% native_storage_module_cache/2). Seeing both is the two-space proof: one
% plant lands in &self's module and the other in a module that did not exist
% when this file was loaded, and the walk has to find both without being told
% where either one is. The plant asks space_module/2 for the module rather
% than using the space's own name: those were the same atom for every space
% but &self before Phase 11, and are different atoms for all of them now.
live_scan_sees_a_planted_cut :-
    aggregate_all(count, live_hook_clause(_, _), Live),
    Planted = metta_on_function_removed(_),
    space_module('&self', TodayModule),
    Fixture = '$static-check-fixture:&hook-probe',
    space_module(Fixture, FixtureModule),
    setup_call_cleanup(
        ( assertz((TodayModule:Planted :- (!, fail))),
          assertz(native_storage_module_cache(Fixture, unused)),
          assertz((FixtureModule:Planted :- (!, fail))) ),
        aggregate_all(count,
                      ( live_hook_clause(_, Body), cut_in_clause_scope(Body) ),
                      Seen),
        ( retract((TodayModule:Planted :- (!, fail))),
          retractall(native_storage_module_cache(Fixture, _)),
          retract((FixtureModule:Planted :- (!, fail))) )),
    (   Seen >= 2
    ->  format("static: no cut in any of ~d live clauses of the seams whose \c
                kind says every clause runs, and the scan saw a planted \c
                cut in today's module and in a second, runtime-created \c
                one~n", [Live])
    ;   format(user_error,
               'the live hook scan saw ~d of 2 planted cuts across two \c
                modules, so its clean result says nothing~n', [Seen]),
        fail
    ).

% A cut only cuts the clause from a transparent position. One inside \+/1, a
% findall/3 goal or an if-then-else CONDITION is local to that goal, so
% flagging it would be a false positive on correct code: the manual's own
% worked example is `t3 :- (a, !, b -> c ; d)` pruning a/0 and not t3/0
% [source: SWI-Prolog manual, !/0, scope-of-the-cut table]. The ;/2 case has
% to be tried before the ->/2 one, because (C -> T ; E) is ;(->(C,T), E) and
% descending it as a disjunction is what routes the condition to the clause
% that drops it.
%
% Module qualification is transparent too, and it is the case that matters
% here rather than a completeness flourish: a handler asserted as
% assertz((user:Head :- Body)), which is how a library or the Python bridge
% installs one from outside, comes back from clause/2 with the body READ AS
% user:(...). Without this clause the walk looks straight past exactly the
% shape the live scan exists to catch, and it did: the planted cut was
% invisible until this was added [measured 2026-08-17: `q :- user:(!, fail)`
% prunes q/0].
cut_in_clause_scope(Body) :-
    nonvar(Body),
    (   Body == !
    ->  true
    ;   Body = (A, B)      -> ( cut_in_clause_scope(A) -> true ; cut_in_clause_scope(B) )
    ;   Body = (A ; B)     -> ( cut_in_clause_scope(A) -> true ; cut_in_clause_scope(B) )
    ;   Body = (_ -> Then) -> cut_in_clause_scope(Then)
    ;   Body = (_ *-> Then) -> cut_in_clause_scope(Then)
    ;   Body = (_ : Inner) -> cut_in_clause_scope(Inner)
    ;   fail
    ).

check_project_var_branches :-
    setup_call_cleanup(
        style_check(+var_branches),
        forall(engine_source(Source), load_files(Source, [if(true)])),
        style_check(-var_branches)).

engine_source('../../src/ext_points.pl').
engine_source('../../src/parser.pl').
engine_source('../../src/translator.pl').
engine_source('../../src/specializer.pl').
engine_source('../../src/filereader.pl').
engine_source('../../lib/lib_gitimport.pl').
engine_source('../../src/spaces.pl').
engine_source('../../src/tracer.pl').
engine_source('../../src/metta.pl').

representative_source("
(= (static-check-inc $x) (+ $x 1))
(= (static-check-choose $x)
   (if (> $x 0) (static-check-inc $x) 0))
!(static-check-choose 2)").

%%%% No compile-time helper in a generated body %%%%
%
% A1 was one of these: the collection forms inlined their body into a yall
% lambda, so every generated clause carried a `>>` that copy_termed itself once
% per element, 3.6 to 4.7 times the inferences of the compiled closure that
% replaced it. The lesson generalises past yall. A translator helper is meant
% to run while COMPILING, and any of them that reaches a generated body runs
% once per call instead of once per call site.
%
% So the rule is stated over the helpers rather than over one of them, and it
% is checked by walking the bodies rather than by reading the emission sites:
% 22 `AfterHead = [...]` sites in translator.pl alone, and reading them is how
% A1 survived being read.
compile_time_helper('>>').           % yall, the A1 defect itself
compile_time_helper(traverse_list).  % specializer.pl's argument walk
compile_time_helper(specializable_vars).
compile_time_helper(variable_first_path).
compile_time_helper(seal_lambda_locals).
compile_time_helper(translate_expr).
compile_time_helper(translate_expr_dl).
compile_time_helper(translate_clause).

% Source reaching every form that compiles a closure or copies a term at
% compile time. Without the lambda, the collection forms and the sealed here,
% the walk would pass over bodies that never had the chance to carry one.
compile_time_helper_source("
(= (sch-dbl $x) (* $x 2))
(= (sch-map $l) (map-atom $l $x (sch-dbl $x)))
(= (sch-filter $l) (filter-atom $l $x (> (sch-dbl $x) 2)))
(= (sch-fold $l) (foldl-atom $l 0 $a $x (+ $a (sch-dbl $x))))
(= (sch-lambda) (|-> ($y) (sch-dbl $y)))
(= (sch-sealed $x) (sealed ($v) (let $v $x (+ $v 1))))
(= (sch-apply $f $x) ($f $x))
(= (sch-ho $l) (map-atom $l $x (sch-apply sch-dbl $x)))
!(sch-map (1 2 3))
!(sch-filter (1 2 3))
!(sch-fold (1 2 3))
!(sch-sealed 1)
!(sch-ho (1 2 3))").

% Every clause of every registered function, NOT only the translated_from
% ones. A lambda's clause carries no translated_from record, and the lambda is
% where A1 lived, so keying on that record would have walked past the defect
% this exists to catch.
% distinct/2 on the clause reference, not on (Module, Body): walking every
% candidate module reaches an INHERITED predicate once per descendant whose
% chain can see it, and clause/3 on two different descendants of the same
% definition returns the SAME reference, so keying on the reference is what
% keeps a shared or core-defined function counted once rather than once per
% space that can reach it [measured 2026-08-19, see live_hook_clause/2].
generated_clause(Owner, Body) :-
    fun(Owner),
    arity(Owner, Arity),
    compiled_function_name(Owner, Name),
    functor(Head, Name, Arity),
    distinct(Ref,
             ( candidate_engine_module(Module),
               current_predicate(_, Module:Head),
               predicate_property(Module:Head, number_of_clauses(_)),
               clause(Module:Head, Body, Ref) )).

no_compile_time_helper_in_a_compiled_body :-
    compile_time_helper_source(Source),
    process_metta_string(Source, _),
    aggregate_all(count, generated_clause(_, _), Bodies),
    findall(File-Name/Arity,
            ( generated_clause(File, Body),
              body_subterm(Body, Sub),
              functor(Sub, Name, Arity),
              compile_time_helper(Name) ),
            Offenders0),
    sort(Offenders0, Offenders),
    (   Offenders == []
    ->  detector_sees_a_planted_helper(Bodies)
    ;   forall(member(In-Indicator, Offenders),
               format(user_error,
                      'compile-time helper in a generated body: ~w in the \c
                       clause for ~w~nit runs once per CALL there, where the \c
                       translator meant it to run once per call site~n',
                      [Indicator, In])),
        fail
    ).

% A scan that finds nothing and a scan that looks at nothing print the same
% line. So the clean result is only accepted after the same walk has been shown
% to see a planted offender: one clause, one `>>` in its body, registered the
% way a generated function is, removed again either way.
%
% fun/1 and arity/2 stay unqualified, because generated_clause/2 itself reads
% them unqualified: they are the compiler's own flat, engine-wide bookkeeping
% of which names are known functions, not per-space state, and moving them
% under a module qualifier here would test a shape the real predicate does
% not have [verified 2026-08-19: a function compiled into a SECOND real space
% still registers a plain, unqualified fun/1 fact, readable from this file's
% own module]. Only the COMPILED CLAUSE is module-specific, so only that part
% is planted into a discovered module rather than a named one.
%
% Two plants, exactly as live_scan_sees_a_planted_cut/0 above: one in
% whatever module &self compiles into today, discovered rather than named,
% and a second in the execution module of a space created at runtime. Finding
% the helper in BOTH is the two-space proof for this check specifically;
% generated_clause/2 is the predicate the survey measured going from 275
% bodies to 1 while still reporting clean, and this is what closes that.
detector_sees_a_planted_helper(Bodies) :-
    Planted = 'static-check-planted-helper',
    space_module('&self', TodayModule),
    Fixture = '$static-check-fixture:&helper-probe',
    space_module(Fixture, FixtureModule),
    Head =.. [Planted, In, Out],
    setup_call_cleanup(
        ( assertz(fun(Planted)),
          assertz(arity(Planted, 2)),
          assertz(native_storage_module_cache(Fixture, unused)),
          assertz((TodayModule:Head :- maplist([A]>>(Out = A), [In]))),
          assertz((FixtureModule:Head :- maplist([A]>>(Out = A), [In]))) ),
        aggregate_all(count,
                      ( generated_clause(_, Body),
                        body_subterm(Body, Sub),
                        functor(Sub, Name, _),
                        compile_time_helper(Name) ),
                      Seen),
        ( retractall(fun(Planted)),
          retractall(arity(Planted, 2)),
          retractall(native_storage_module_cache(Fixture, _)),
          functor(Gone, Planted, 2),
          retractall(TodayModule:Gone),
          retractall(FixtureModule:Gone) )),
    (   Seen >= 2
    ->  format("static: no compile-time helper in any of ~d generated \c
                clause bodies, and the walk saw a planted one in today's \c
                module and one in a runtime-created second module~n",
               [Bodies])
    ;   format(user_error,
               'the compile-time-helper walk saw ~d of 2 planted helpers \c
                across two modules, so its clean result says nothing~n',
               [Seen]),
        fail
    ).

% Every compound SUBTERM of the body, not every goal in it. A1's `>>` was an
% ARGUMENT of maplist/3 and never stood in goal position, so a walk over the
% control structure alone looks straight past the defect this exists to catch.
% That is not hypothetical: the goal-position version of this walk was written
% first and reported clean against a planted `>>`, which is why
% detector_sees_a_planted_helper/1 exists.
body_subterm(Term, Term) :- compound(Term).
body_subterm(Term, Sub) :-
    compound(Term),
    arg(_, Term, Argument),
    body_subterm(Argument, Sub).


%%%% Every goal the engine emits into a body is protected %%%%
%
% A compiled body resolves its goals in the module the clause went into, so a
% MeTTa equation for the name of a goal the TRANSLATOR wrote would capture that
% goal in the space's own bodies: silently, and with a wrong answer rather than
% an error. metta_engine_emitted/1 (src/translator.pl) names those and
% protect_engine_emitted/1 (src/spaces.pl) binds each into every space's
% module, which is what makes the assert refuse.
%
% That list is a claim about what the translator emits, so it is RECOMPUTED
% here rather than read: every equation in the shipped corpus is translated and
% every goal is taken out of the resulting body. A goal is a finding when it is
% none of the engine's MeTTa dispatch names, is not already protected, and an
% assert for it into a fresh module of a space's shape SUCCEEDS, which is the
% test that says a MeTTa equation could take it.
%
% Fails when a translation rule is reachable only from a form no shipped
% equation uses. The corpus is the widest input the tree has and the check says
% how much of it it read, so a rule added with no example is visible as a count
% that did not move [measured 2026-08-19: 102 goal indicators over 1,040
% equations, 10 of them engine-emitted and capturable, all 10 named].
engine_emitted_corpus_dir('../../examples').
engine_emitted_corpus_dir('../../lib').

corpus_equation_body(Body) :-
    engine_emitted_corpus_dir(Dir),
    exists_directory(Dir),
    directory_member(Dir, File, [recursive(true), extensions([metta])]),
    \+ sub_atom(File, _, _, _, '/_fixtures/'),
    catch(( read_metta_source(File, Source),
            parse_metta_source(Source, Forms) ), _, fail),
    member(parsed(function, _, Form), Forms),
    Form = [=, _, _],
    \+ writes_a_raw_prolog_goal(Form),
    catch(translate_clause(Form, (_ :- Body)), _, fail).

% `Predicate` and `translatePredicate` are the escape hatch that turns a MeTTa
% expression into a raw Prolog goal, and a goal a PROGRAM writes that way is
% the program's own: it resolves in the program's space deliberately, and
% protecting its name would be refusing the feature. In a compiled body it is
% indistinguishable from one the translator wrote, so the equations that use
% the hatch are skipped whole. lib/lib_tabling.metta is the shipped instance,
% and open_string/2 and load_files/2 reach compiled bodies through it
% [measured 2026-08-19].
writes_a_raw_prolog_goal(Form) :-
    sub_term(Sub, Form),
    atom(Sub),
    memberchk(Sub, ['Predicate', translatePredicate]),
    !.

emitted_goal(V, _) :- var(V), !, fail.
emitted_goal((A, B), I) :- !, ( emitted_goal(A, I) ; emitted_goal(B, I) ).
emitted_goal((A ; B), I) :- !, ( emitted_goal(A, I) ; emitted_goal(B, I) ).
emitted_goal((A -> B), I) :- !, ( emitted_goal(A, I) ; emitted_goal(B, I) ).
emitted_goal((A *-> B), I) :- !, ( emitted_goal(A, I) ; emitted_goal(B, I) ).
emitted_goal(\+ A, I) :- !, emitted_goal(A, I).
emitted_goal(!, _) :- !, fail.
emitted_goal(_ : G, I) :- !, emitted_goal(G, I).
% Only an argument that is itself CONTROL is descended into. Every other
% argument is data, and reading those as goals reported every symbol a program
% writes: x/0, y/0 and the rest [measured 2026-08-19, first version of this].
emitted_goal(Goal, Indicator) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    (   Indicator = Name/Arity
    ;   compound(Goal),
        arg(_, Goal, Argument), nonvar(Argument), control_shaped(Argument),
        emitted_goal(Argument, Indicator)
    ).

control_shaped(T) :-
    compound(T),
    ( T = (_, _) ; T = (_ ; _) ; T = (_ -> _) ; T = (_ *-> _) ; T = (\+ _) ).

% Could a MeTTa equation take this name? Asked of a FRESH module of a space's
% shape, one per name, so an earlier probe cannot free a later one, and asked
% by doing the assert the engine would do rather than by reading a property.
capturable(Name/Arity) :-
    gensym('$static-check-capture:&probe', Space),
    space_module(Space, Module),
    functor(Probe, Name, Arity),
    catch(setup_call_cleanup(assertz((Module:Probe :- fail), Ref), true, erase(Ref)),
          error(permission_error(modify, static_procedure, _), _),
          fail).

every_engine_emitted_goal_is_protected :-
    findall(Indicator,
            ( corpus_equation_body(Body), emitted_goal(Body, Indicator) ),
            All0),
    sort(All0, All),
    length(All, Seen),
    findall(Name/Arity,
            ( member(Name/Arity, All),
              \+ metta_dispatch_name(Name, Arity),
              capturable(Name/Arity) ),
            Unprotected0),
    sort(Unprotected0, Unprotected),
    (   Unprotected == []
    ->  aggregate_all(count, metta_engine_emitted(_), Protected),
        format("static: every one of ~d goal indicators the corpus compiles is \c
                either a MeTTa name or one of the ~d the engine protects~n",
               [Seen, Protected])
    ;   forall(member(Indicator, Unprotected),
               format(user_error,
                      'the engine emits ~w into compiled bodies and a MeTTa \c
                       equation can take it: name it in metta_engine_emitted/1 \c
                       (src/translator.pl) or qualify the goal~n',
                      [Indicator])),
        fail
    ).

%%%% Each kind is declared the way its direction requires %%%%
%
% ext_point_clauses_from/2 splits the kinds by who writes the clauses, and the
% two halves are declared differently. A handler seam is multifile, because
% that is the permission an extension needs to add clauses to it. A service is
% NOT, because an extension calling one must not be able to redefine it, and
% multifile is exactly the permission to try. Neither half is checked by
% every_seam_declares_one_kind, which reads the multifile declarations and so
% cannot see a service at all: a service declared multifile by mistake would
% look like an ordinary handler seam, and a handler seam whose multifile
% declaration was dropped would vanish from every check in this file rather
% than fail one.
every_seam_kind_matches_its_direction :-
    findall(Seam-Kind-Fault,
            ( ext_point_kind(Seam, Kind),
              seam_direction_fault(Seam, Kind, Fault) ),
            Faults0),
    % A seam declared multifile in two files answers declared_seam/2 twice, and
    % reporting one fault twice would read as two.
    sort(Faults0, Faults),
    (   Faults == []
    ->  direction_check_sees_a_planted_fault
    ;   forall(member(Seam-Kind-Fault, Faults),
               format(user_error, 'the ~w seam ~w ~w~n', [Kind, Seam, Fault])),
        fail
    ).

% The same discipline as the walks below. This one is a scan over a fact table
% rather than a walk, and it fails the same way: a bug in seam_direction_fault/3
% reports the tree clean and nothing says so. Each of the three faults is
% planted against a name no tree will hold, and the check reports which one
% stopped firing.
direction_check_sees_a_planted_fault :-
    aggregate_all(count, ext_point_kind(_, service), Services),
    aggregate_all(count,
                  ( ext_point_kind(_, K), ext_point_clauses_from(K, extension) ),
                  Handlers),
    % The third pairs a seam that IS declared multifile with the service kind,
    % which is the only way that fault can arise and the reason the first
    % attempt at this probe was itself wrong: swrite/2 is a service and not
    % multifile, so planting it proved nothing and the check said so.
    Faults = [ undeclared_handler-(planted_seam/9)-event,
               undefined_service-(planted_seam/9)-service,
               multifile_service-(metta_foreign_space/1)-service ],
    % once/1, because a seam declared multifile in two files answers
    % declared_seam/2 twice and a fault that fired twice is still one fault.
    findall(Name,
            ( member(Name-Seam-Kind, Faults),
              once(seam_direction_fault(Seam, Kind, _)) ),
            Fired),
    length(Faults, Total),
    length(Fired, Seen),
    (   Seen =:= Total
    ->  format("static: ~d handler seams are multifile and ~d published \c
                services are not, and the check saw each of ~d planted \c
                faults~n", [Handlers, Services, Total])
    ;   findall(N, ( member(N-_-_, Faults), \+ memberchk(N, Fired) ), Missed),
        format(user_error,
               'the seam direction check saw ~d of ~d planted faults, so its \c
                clean result says nothing~nit is blind to: ~w~n',
               [Seen, Total, Missed]),
        fail
    ).

seam_direction_fault(Seam, Kind, Fault) :-
    ext_point_clauses_from(Kind, extension),
    \+ declared_seam(_, Seam),
    Fault = 'has no :- multifile declaration, so no check in this file \c
             can see its clauses'.
seam_direction_fault(Seam, Kind, Fault) :-
    ext_point_clauses_from(Kind, engine),
    declared_seam(_, Seam),
    Fault = 'is declared multifile, which lets a caller redefine the very \c
             predicate it was published to call'.
seam_direction_fault(Seam, Kind, Fault) :-
    ext_point_clauses_from(Kind, engine),
    Seam = Name/Arity,
    functor(Head, Name, Arity),
    \+ ( candidate_engine_module(Module), current_predicate(_, Module:Head) ),
    Fault = 'is published but not defined, so a caller reaching for it gets \c
             an existence error'.

%%%% A backend calls only published surface %%%%
%
% The seams in src/ext_points.pl say what the engine calls. This says what a
% backend may call BACK, which is the half that was missing: MORK reached into
% src/parser.pl for swrite/2 and metta_unwritable_symbol/2, wrapping the
% second under a private name, and nothing said it should not. SQLite publishes
% the same half deliberately, handing an extension an sqlite3_api_routines
% table so that it never links against internals [source:
% https://www.sqlite.org/loadext.html]; the four services now declared are that
% table and this is the linker that enforces it.
%
% Published surface is three things and all three are read as data rather than
% listed here: a declared service, a declared seam, and a MeTTa builtin, which
% a backend calls as the LANGUAGE and builtin_fun/1 already enumerates.
% Anything else in src/ is an internal that can be renamed under the backend.
%
% Backends are discovered the way the engine discovers them, by consulting
% backends/*.pl, so a backend that is not built loads nothing and is not
% scanned. That makes the count load-bearing and it is printed for that reason:
% on a tree without the MORK artefact this check reads zero backend clauses,
% which is the correct answer and not the same as a clean one.
a_backend_calls_only_published_surface :-
    forall(backend_entry(Entry), ensure_loaded(Entry)),
    backend_directories(Directories),
    reaches_past_surface(Directories, Reaches),
    (   Reaches == []
    ->  backend_scan_sees_a_planted_reach
    ;   forall(member(Caller-Callee, Reaches),
               format(user_error,
                      'the backend predicate ~w calls ~w, which is an engine \c
                       internal rather than published surface~ndeclare it \c
                       ext_point_kind(~w, service) in src/ext_points.pl if a \c
                       backend is meant to call it~n',
                      [Caller, Callee, Callee])),
        fail
    ).

backend_entry(Entry) :-
    expand_file_name('../../backends/*.pl', Files),
    member(Entry, Files).

% backends/ holds the declaration and the implementation lives beside the
% shared library it wraps, which is the split backends/mork.pl exists to make,
% so both are walked.
backend_directories(['../../backends', '../../mork_ffi']).

% The same discipline as the other three walks here, and carried further,
% because this one delegates to a library: a probe that exercised only code in
% THIS file would say nothing about whether prolog_walk_code/1 was called
% correctly. So each door is a real clause, asserted, walked by the real walk
% and retracted, and the check reports WHICH door stopped firing rather than
% only that one did.
%
% A backend that is not built contributes no clauses, so a clean result also
% has to be told apart from an empty one, which is what the count is for.
backend_scan_sees_a_planted_reach :-
    backend_directories(Directories),
    extension_clause_count(Directories, Examined),
    Internal = register_prolog_arities/1,
    (   published_surface(Internal)
    ->  format(user_error,
               'the planted reach ~w is published surface, so it proves \c
                nothing; pick an engine predicate that is not~n', [Internal]),
        fail
    ;   findall(Door, planted_reach(Door, _), Doors),
        length(Doors, Total),
        findall(Door, ( planted_reach(Door, Body), door_is_seen(Body) ), Fired),
        length(Fired, Seen),
        (   Seen =:= Total
        ->  format("static: no backend reaches past the published surface in \c
                    ~d backend clauses, and the walk saw a planted reach by \c
                    each of ~d doors~n", [Examined, Total])
        ;   findall(D, ( planted_reach(D, _), \+ memberchk(D, Fired) ), Missed),
            format(user_error,
                   'the backend surface walk saw ~d of ~d planted reaches, so \c
                    its clean result says nothing~nit is blind to: ~w~n',
                   [Seen, Total, Missed]),
            fail
        )
    ).

door_is_seen(Body) :-
    setup_call_cleanup(
        assertz((planted_probe :- Body), Reference),
        ( walked_reaches([Reference], Reaches),
          memberchk(planted_probe/0-(register_prolog_arities/1), Reaches) ),
        erase(Reference)).

% One per way a call can hide, because each is a separate path through the walk
% and only the first is exercised by the tree as it stands. The hand-written
% version of this walk was blind to the second, and blind to the fourth even
% after it learned meta_predicate specs: nothing declares planted_helper/2 a
% meta-predicate, and inferring that is the reason the walk is SWI's rather
% than this file's.
planted_reach(control_structure, (true, register_prolog_arities(_))).
planted_reach(declared_meta,     ignore(maplist(register_prolog_arities, []))).
planted_reach(caret_goal,        \+ bagof(_, _^register_prolog_arities(_), _)).
planted_reach(inferred_meta,     planted_helper(register_prolog_arities, [])).

planted_helper(Goal, List) :- maplist(Goal, List).
