% Purpose: run SWI's source checks after compiling representative MeTTa code,
%     and enforce the two rules about engine/ext_points.pl's seams that no SWI
%     check knows about: every seam declares its kind, and a seam whose kind
%     says every clause runs carries no cut.
% Assumes:
%   - seam:kind/2 in engine/ext_points.pl is the taxonomy. This file reads it
%     rather than restating it, which is the whole point: the restated list it
%     replaced had seam:backend_selftest/0 missing and seam:dispatch_call/4
%     wrongly present [source: their call sites, main.pl:36 and
%     translator.pl:350].
%   - space_module/2 (engine/spaces.pl:231-232) and native_storage_module_cache/2
%     (engine/spaces.pl:54) are the engine's own, and correct, record of which
%     modules exist; candidate_engine_module/1 below discovers modules through
%     them rather than by naming one, which is what keeps every check in this
%     file from hardcoding `user` [source: ai-phase11-module-survey.md
%     section 1.2, workspace root, "space_module/2 is the only door"].
% Guarantees:
%   - The driver runs the four reviewed library(check) predicates and check/0
%     after a function with control flow has been compiled.
%   - var_branches warnings are fatal for repository engine sources without
%     attributing warnings from SWI's own libraries to the repository.
%   - Every unqualified multifile seam declared anywhere under engine, lib,
%     extensions/python/metta or extensions/mork/mork_ffi has exactly one seam:kind/2 fact, so a new
%     seam cannot go quietly unchecked [measured 2026-08-17: 28 seams].
%   - Each kind is declared the way its direction requires: a handler seam
%     multifile so an extension can add clauses, a service not, so a caller
%     cannot redefine what it was published to call
%     [measured 2026-08-17: 28 handler seams and 7 services].
%   - No cut in any clause of a seam whose kind says every clause runs,
%     checked twice over because neither reading sees the other's clauses: the
%     tree's sources including consulted engine/<owner> source units and the
%     clauses directives assert, and the live
%     database after the libraries load, which is the only way to see a
%     handler installed at run time, in every module candidate_engine_module/1
%     discovers rather than only in `user`
%     [measured 2026-08-19: 0 offenders in 19 source clauses and 71 live
%     ones].
%     [tested: `sh check.sh prolog-static` retains the pre-cut hook-clause
%     scoreboard after source-unit extraction; commit=9a116762fb4372d55675e2ef64b7657092bc136d].
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
%   - Every goal an engine file CONSTRUCTS rather than calls is reachable from
%     a space's execution module, which is the other route to the same question
%     every_engine_emitted_goal_is_protected asks of the shipped corpus. The
%     corpus route sees a translation rule only when an example uses the form;
%     this one sees every rule. Four real defects on the tree it was written
%     for, none of them reachable from examples/: metta_top/3, metta_top_match/5,
%     metta_merged_match/3 and metta_verified_specialization/2
%     [measured 2026-08-22: 39 constructed goals, 4 unreachable before the
%     exports, 0 after].
%   - Every space name the live database registers, over the engine, every
%     library, every backend and every host binding, is an ATOM carrying the
%     '&' prefix that metta_space_operand/1 refuses an atom without. The seam
%     it reads is open, so a provider can name a space every door that CREATES
%     one would have refused, and the result would be a quiet no rather than an
%     error [tested: `sh check.sh prolog-static` against
%     tests/prolog/unprefixed_space_provider.pl].
%   - Seven of the eight checks prove themselves non-vacuous against a planted
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
%     plant through a SECOND module as well as the one &self compiles into
%     today, one created at runtime and named and classed the way a Phase 11
%     execution module will be, and both plants have to be found for the
%     check to accept a clean result. That is the module-agnostic discovery
%     proved against two topologies at once, not just asserted
%     [measured 2026-08-19: no_compile_time_helper_in_a_compiled_body and
%     no_cut_in_a_live_hook_clause below]. The live-hook scan's PAIR is two
%     clause references and not two modules holding a clause each, because the
%     seam it plants is module-qualified; the note above that check carries the
%     measurement and what the plant does and does not prove.
% Fails when:
%   - a function is compiled into a space whose storage is FOREIGN (backed by
%     an external provider such as MORK) rather than native. The module
%     discovery is surface_walk.pl's candidate_engine_module/1, and the note
%     beside it says why; this is unchanged from before the checks discovered
%     modules instead of naming `user`, since the `user`-only walk never
%     looked at a foreign space's module either.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(check)).
:- use_module(library(solution_sequences)).
:- ensure_loaded(surface_walk).
:- initialization(main, main).

main :-
    %BEFORE the consult, because engine/metta.pl reads argv while it loads to
    %decide whether to read the seats' control files, and both checks below
    %walk what those files pull in. The same reason reachability.pl sets it,
    %and the same reason the plunit lane appends it.
    set_prolog_flag(argv, [extensions]),
    consult('../../engine/metta.pl'),
    check_project_var_branches,
    every_seam_declares_one_kind,
    every_seam_kind_matches_its_direction,
    no_cut_in_an_event_hook,
    arithmetic_expansion_stays_at_run_time,
    metta_host_set_silent(true),
    representative_source(Source),
    process_metta_string(Source, [3]),
    no_compile_time_helper_in_a_compiled_body,
    list_trivial_fails,
    list_redefined,
    list_void_declarations,
    list_autoload,
    check,
    a_backend_calls_only_published_surface,
    a_host_binding_calls_only_published_surface,
    no_cut_in_a_live_hook_clause,
    every_engine_emitted_goal_is_protected,
    every_emitted_goal_is_reachable,
    every_registered_space_name_is_an_ampersand_atom.

%%%% Every seam declares one kind %%%%
%
% engine/ext_points.pl gives each multifile seam an seam:kind/2 fact on the
% line after its declaration, and the two checks below read those rather than
% keeping a list of their own. That only works if the annotation is TOTAL: a
% seam added without a kind is silently exempt from the cut check, which is
% the drift this arrangement exists to stop. Restating the list by hand is
% what put seam:backend_selftest/0 outside the check and seam:dispatch_call/4
% wrongly inside it. So the declarations are read back out of the source and
% each one is required to have exactly one kind.
%
% A seam qualified with a module OTHER than `seam` is somebody else's
% protocol. prolog:message//1 and user:thread_message_hook/3 are SWI's and
% their contract is fixed there, so the shape below matches an unqualified
% indicator, which is what engine/ext_points.pl writes inside its own module,
% or a `seam:` one, which is what every extension writes, and passes over the
% rest.
declared_seam(File, Seam) :-
    hook_source_file(File),
    source_term(File, (:- multifile Spec)),
    multifile_indicator(Spec, Seam).

multifile_indicator(Spec, _) :- var(Spec), !, fail.
multifile_indicator((A, B), Seam) :-
    !, ( multifile_indicator(A, Seam) ; multifile_indicator(B, Seam) ).
%`seam:` and no other module. A handler seam lives in the seam module now, so
%every extension declares it the way SWI's own hooks are declared,
%`:- multifile seam:atom_added/2.`, and this scan reads the file as TEXT
%rather than asking the database: without this clause it saw none of them.
%Matching ANY module would drag in prolog:message//1 and
%user:thread_message_hook/3, which the note above passes over on purpose.
multifile_indicator(seam:Spec, Seam) :-
    !, multifile_indicator(Spec, Seam).
multifile_indicator(Name/Arity, Name/Arity) :- atom(Name), integer(Arity).
multifile_indicator(Name//Arity, Name/Total) :-
    atom(Name), integer(Arity), Total is Arity + 2.

every_seam_declares_one_kind :-
    findall(Seam, declared_seam(_, Seam), Declared0),
    sort(Declared0, Declared),
    findall(Seam-Count-File,
            ( member(Seam, Declared),
              aggregate_all(count, seam:kind(Seam, _), Count),
              Count =\= 1,
              once(declared_seam(File, Seam)) ),
            Wrong),
    (   Wrong == []
    ->  length(Declared, Total),
        aggregate_all(count, seam:every_clause_runs(_), Checked),
        format("static: ~d extension-point seams each declare one kind, \c
                ~d of which have every clause run~n", [Total, Checked])
    ;   forall(member(Seam-Count-File, Wrong),
               format(user_error,
                      'the seam ~w in ~w has ~d seam:kind/2 facts and \c
                       needs exactly one~ngive it event, ownership or \c
                       declaration on the line after its declaration, or the \c
                       cut check passes over it~n',
                      [Seam, File, Count])),
        fail
    ).

%%%% No cut in an event hook %%%%
%
% engine/ext_points.pl states the rule this enforces: an OWNERSHIP seam answers
% one provider's request and may cut after its ownership test, while an EVENT
% or DECLARATION seam has every clause read and a cut in one of them silently
% disables every clause loaded after it. Only the second kind is checked,
% which is what makes the rule usable: lib/lib_redis/lib_redis.pl's cuts are correct
% and stay.
%
% lib/lib_tabling/lib_tabling.pl cut after metta_tabling_declared, a global condition
% rather than an ownership test. With tabling declared, engine/duals.pl's
% invalidation handler was ordered after it and never ran, so a changed
% function kept a stale dual and (not-provable (pq 2)) answered True and
% False at once. Nothing in the tree would have said so.
event_hook(Name, Arity) :- seam:every_clause_runs(Name/Arity).

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
    Written  = (seam:atom_added(_, _) :- (!, fail)),
    Asserted = (:- assertz((seam:atom_added(_, _) :- (!, fail)))),
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
    member(Pattern, ['../../engine/*.pl', '../../engine/*/*.pl',
                     '../../lib/*/*.pl', '../../extensions/python/metta/*.pl',
                     '../../extensions/mork/mork_ffi/*.pl']),
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
% asserts, and that is still not all of them. lib/lib_thread/lib_thread.pl installs a
% seam:atom_added/2 handler from inside space_await_/4, Python
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
    seam:every_clause_runs(Name/Arity),
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
    expand_file_name('../../lib/*/*.pl', Files),
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
% registered as a known space the same way (engine/spaces.pl's
% native_storage_module_cache/2), so candidate_engine_module/1 has to discover
% a module that did not exist when this file was loaded. The plant asks
% space_module/2 for the module rather than using the space's own name: those
% were the same atom for every space but &self before Phase 11, and are
% different atoms for all of them now.
%
% WHAT THE TWO PLANTS PROVE, measured rather than assumed: both CLAUSES land
% in module `seam`, because Planted is already qualified and SWI resolves
% M1:(M2:Head) to M2. The discovery half is still exercised -- the walk
% enumerates the runtime-created module and reaches the seam's clauses through
% it -- but the pair is two clause REFERENCES that distinct/2 has to keep
% apart, not two modules holding a clause each
% [measured 2026-08-28: after both asserts, module seam holds
% [true, user:(!,fail), user:(!,fail)] and each execution module holds none].
%
% The removal is by clause REFERENCE. assertz/1 stores the body of a clause
% whose head resolves to another module qualified with the CALLING context, so
% the clause above is stored as `user:(!,fail)` and
% retract((Module:Planted :- (!, fail))) cannot match it. That retract led a
% cleanup CONJUNCTION, and setup_call_cleanup/3 ignores a cleanup that fails,
% so both planted cuts and the fixture's storage row survived every run: the
% space-name scan below reported the fixture as a registered space with no '&'
% prefix, which is how this was found [measured 2026-08-28].
live_scan_sees_a_planted_cut :-
    aggregate_all(count, live_hook_clause(_, _), Live),
    Planted = seam:function_removed(_),
    space_module('&self', TodayModule),
    Fixture = '$static-check-fixture:&hook-probe',
    space_module(Fixture, FixtureModule),
    setup_call_cleanup(
        ( assertz((TodayModule:Planted :- (!, fail)), TodayRef),
          assertz(native_storage_module_cache(Fixture, unused)),
          assertz((FixtureModule:Planted :- (!, fail)), FixtureRef) ),
        aggregate_all(count,
                      ( live_hook_clause(_, Body), cut_in_clause_scope(Body) ),
                      Seen),
        ( erase(TodayRef),
          retractall(native_storage_module_cache(Fixture, _)),
          erase(FixtureRef) )),
    (   Seen >= 2
    ->  format("static: no cut in any of ~d live clauses of the seams whose \c
                kind says every clause runs, and the scan saw both cuts \c
                planted through today's module and through a second, \c
                runtime-created one~n", [Live])
    ;   format(user_error,
               'the live hook scan saw ~d of 2 planted cuts, so its clean \c
                result says nothing~n', [Seen]),
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

engine_source('../../engine/ext_points.pl').
engine_source('../../engine/parser.pl').
engine_source('../../engine/translator.pl').
engine_source('../../engine/specializer.pl').
engine_source('../../engine/filereader.pl').
engine_source('../../lib/lib_gitimport/lib_gitimport.pl').
engine_source('../../engine/spaces.pl').
engine_source('../../engine/tracer.pl').
engine_source('../../engine/metta.pl').

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
(= (sch-sealed $x) (sealed ($x) (let $v $x (+ $v 1))))
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
% an error. seam:engine_emitted/1 (engine/translator.pl) names those and
% protect_engine_emitted/1 (engine/spaces.pl) binds each into every space's
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
%A name is MeTTa's when the engine's own dispatch registry knows it: arity/2
%is what reduce/3 and translator:build_call_or_partial_dl/6 consult to decide a head is a
%call, fun/1 what the translator consults to decide it is not data, and
%builtin_fun/1 what keeps a builtin visible in every space. A name none of the
%three holds was written by the translator and by nothing else.
metta_dispatch_name(Name, Arity) :- arity(Name, Arity), !.
metta_dispatch_name(Name, _) :- fun(Name), !.
metta_dispatch_name(Name, _) :- builtin_fun(Name).

engine_emitted_corpus_dir('../../examples').
engine_emitted_corpus_dir('../../lib').

corpus_equation_body(Body) :-
    engine_emitted_corpus_dir(Dir),
    exists_directory(Dir),
    directory_member(Dir, File, [recursive(true), extensions([metta])]),
    \+ sub_atom(File, _, _, _, '/_fixtures/'),
    catch(( filereader:read_metta_source(File, Source),
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
% the hatch are skipped whole. lib/lib_tabling/lib_tabling.metta is the shipped instance,
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
% A goal the emitter qualified with a CONCRETE engine module resolves there
% no matter what any space asserts, which is the "or qualify the goal"
% remedy this check's own message offers; system:b_setval is the fuel
% charge's documented shape. An unbound qualifier decides at run time and
% stays exposed, so it is still walked.
emitted_goal(M : G, I) :- !,
    (   nonvar(M), M == system
    ->  fail
    ;   emitted_goal(G, I)
    ).
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
    ->  aggregate_all(count, seam:engine_emitted(_), Protected),
        format("static: every one of ~d goal indicators the corpus compiles is \c
                either a MeTTa name or one of the ~d the engine protects~n",
               [Seen, Protected])
    ;   forall(member(Indicator, Unprotected),
               format(user_error,
                      'the engine emits ~w into compiled bodies and a MeTTa \c
                       equation can take it: name it in seam:engine_emitted/1 \c
                       (engine/translator.pl) or qualify the goal~n',
                      [Indicator])),
        fail
    ).

%%%% Every goal the engine emits can be REACHED from a space's module %%%%
%
% The other half of the check above, by the other route. That one recompiles
% the shipped corpus and reads the goals out of the bodies, so it sees a
% translation rule only when some shipped equation uses the form; this one
% reads what the engine's own sources CONSTRUCT, so it sees every rule whether
% an example exercises it or not. Both are needed: the corpus half catches a
% goal a LIBRARY teaches the engine to emit through seam:dispatch_call/4, which
% is not in any source here, and the source half catches a rule with no example.
%
% Constructed-not-called is what makes the source half precise. A goal an
% engine file CALLS is a step of its own and library(prolog_codewalk) names
% exactly those; what is left is what the compiler writes into a body for a
% space module to run later. That module's base is the ENGINE module, so a name
% defined in a subsystem module is invisible there unless the subsystem exports
% it, and protect_engine_emitted/1 skips a declared name the engine cannot see
% rather than refusing it.
%
% Four real defects on the tree this was written for, none of which the corpus
% half could reach [measured 2026-08-22]: metta_top/3 and metta_top_match/5,
% behind (top k ...), which appears in examples/ only inside a comment and which
% the benchmark suite caught as existence_error(procedure,
% '$metta_exec:&pyspace_1':metta_top/3); metta_merged_match/3, behind a literal
% (match (superpose (&a &b)) ...), which nothing in the tree ran at all; and
% metta_verified_specialization/2, behind (pragma! verify-specializations true),
% which had been broken outright since engine/specializer.pl became a module.
% Over engine MODULES rather than engine files, so a clause an extension or
% this check itself ASSERTS into one is read too. An asserted clause has no
% file, so a file-driven scan would pass over exactly the plant that proves
% this check can still see, and over a translation rule a library installs.
emitted_goal_module(Module) :-
    tree_directory('../../engine', Directory),
    module_property(Module, file(File)),
    sub_atom(File, 0, _, _, Directory).

:- dynamic emitted_goal_called/2.

measure_called_goals :-
    retractall(emitted_goal_called(_, _)),
    extension_clauses(['../../engine'], References),
    walk_clause_edges(References, record_emitted_goal_call).

record_emitted_goal_call(Callee, _Caller, _Location) :-
    ( Callee = _:Goal -> true ; Goal = Callee ),
    callable(Goal),
    functor(Goal, Name, Arity),
    (   emitted_goal_called(Name, Arity)
    ->  true
    ;   assertz(emitted_goal_called(Name, Arity))
    ), !.
record_emitted_goal_call(_, _, _).

constructed_goal(Name/Arity) :-
    emitted_goal_module(Module),
    current_predicate(Module:PredicateName/PredicateArity),
    functor(Head, PredicateName, PredicateArity),
    catch(predicate_property(Module:Head, implementation_module(Module)), _, fail),
    catch(clause(Module:Head, Body), _, fail),
    % The head's ARGUMENTS as well as the body, because SWI folds a leading
    % `Arg = Term` body goal into head unification and the constructed term
    % then lives in the head [measured 2026-08-22: an asserted
    % (h(C) :- C = metta_capacity_remove_sexp(_,_,_)) reads back with the body
    % `true`]. The head's own functor is skipped, since a predicate's head is
    % not something it constructs.
    (   constructed_subterm(Body, Sub)
    ;   compound(Head), arg(_, Head, HeadArgument),
        constructed_subterm(HeadArgument, Sub)
    ),
    functor(Sub, Name, Arity),
    Arity > 0, atom(Name),
    \+ emitted_goal_called(Name, Arity),
    engine_defined(Name/Arity).

constructed_subterm(T, _) :- var(T), !, fail.
% assert/1 resolves an unqualified body goal against the module that CALLED it,
% so a goal written literally inside an assert lands in the asserting file's own
% module and is not this defect [measured 2026-08-22: engine/duals.pl asserts
% (seam:function_changed(F) :- drop_duals_of(F)) and clause/2 reads the stored
% body back as duals:drop_duals_of(_)]. The clauses the translator asserts into
% a space module are built into a variable first, so nothing of theirs is
% literal here and this exclusion cannot hide one.
constructed_subterm(T, _) :- assert_shaped(T), !, fail.
% An explicitly qualified construction says where it lands, so only its
% ARGUMENTS are still candidates.
constructed_subterm(_:G, S) :- !, nonvar(G), compound(G), arg(_, G, A),
                               constructed_subterm(A, S).
constructed_subterm(T, T) :- compound(T).
constructed_subterm(T, S) :- compound(T), arg(_, T, A), constructed_subterm(A, S).

assert_shaped(assertz(_)).
assert_shaped(asserta(_)).
assert_shaped(assertz(_, _)).
assert_shaped(asserta(_, _)).

engine_defined(PI) :- engine_defined_in(PI, _).

space_module_sees(Name/Arity) :-
    metta_engine_module(Engine),
    functor(Head, Name, Arity),
    catch(predicate_property(Engine:Head, defined), _, fail).

unreachable_constructed_goals(Constructed, Blind) :-
    findall(PI, distinct(PI, constructed_goal(PI)), Constructed),
    findall(PI, ( member(PI, Constructed), \+ space_module_sees(PI) ), Blind).

% A clean result is a claim about a scan, so the scan is asked to prove it can
% still see. The plant is a clause asserted into an engine module whose body
% CONSTRUCTS a goal a space module cannot reach; the planted name is
% engine/spaces.pl's capacity-removal body, which that module defines and
% deliberately does not export, so it is the real shape rather than an invented
% one. It is asserted rather than written into a file, which is why the scan
% above reads engine MODULES instead of engine files.
planted_unreachable_goal(metta_capacity_remove_sexp/3).

with_planted_emitter(Goal) :-
    planted_unreachable_goal(Name/Arity),
    functor(Planted, Name, Arity),
    setup_call_cleanup(
        assertz((translator:'$static-check-planted-emitter'(Flag, Constructed) :-
                    Flag == emit, Constructed = Planted),
                Reference),
        Goal,
        erase(Reference)).

planted_emitter_is_named :-
    planted_unreachable_goal(PI),
    unreachable_constructed_goals(_, Blind),
    memberchk(PI, Blind).

every_emitted_goal_is_reachable :-
    measure_called_goals,
    unreachable_constructed_goals(Constructed, Blind),
    length(Constructed, Seen),
    (   Blind == []
    ->  (   with_planted_emitter(planted_emitter_is_named)
        ->  format("static: every one of ~d goals the engine constructs rather \c
                    than calls is reachable from a space's module, and the scan \c
                    named a planted unreachable one~n", [Seen])
        ;   planted_unreachable_goal(Planted),
            format(user_error,
                   'the constructed-goal scan reported clean against a planted \c
                    ~w, so its clean result says nothing~n', [Planted]),
            fail
        )
    ;   forall(member(Name/Arity, Blind),
               ( ( engine_defined_in(Name/Arity, Definer) -> true ; Definer = '?' ),
                 format(user_error,
                        'the engine writes ~w into a compiled body and a space \c
                         module cannot see it: ~w defines it and does not export \c
                         it, so the goal raises existence_error the first time \c
                         a program reaches that form. Export it from ~w and name \c
                         it in seam:engine_emitted/1 (engine/translator.pl)~n',
                        [Name/Arity, Definer, Definer]) )),
        fail
    ).

engine_defined_in(Name/Arity, Module) :-
    functor(Head, Name, Arity),
    tree_directory('../../engine', Directory),
    current_module(Module),
    catch(( predicate_property(Module:Head, defined),
            predicate_property(Module:Head, implementation_module(Module)),
            predicate_property(Module:Head, file(File)),
            sub_atom(File, 0, _, _, Directory) ),
          _, fail), !.

%%%% Each kind is declared the way its direction requires %%%%
%
% seam:clauses_from/2 splits the kinds by who writes the clauses, and the
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
            ( seam:kind(Seam, Kind),
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
    aggregate_all(count, seam:kind(_, service), Services),
    aggregate_all(count,
                  ( seam:kind(_, K), seam:clauses_from(K, extension) ),
                  Handlers),
    % The third pairs a seam that IS declared multifile with the service kind,
    % which is the only way that fault can arise and the reason the first
    % attempt at this probe was itself wrong: swrite/2 is a service and not
    % multifile, so planting it proved nothing and the check said so.
    Faults = [ undeclared_handler-(planted_seam/9)-event,
               undefined_service-(planted_seam/9)-service,
               multifile_service-(foreign_space/1)-service ],
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
    seam:clauses_from(Kind, extension),
    \+ declared_seam(_, Seam),
    Fault = 'has no :- multifile declaration, so no check in this file \c
             can see its clauses'.
seam_direction_fault(Seam, Kind, Fault) :-
    seam:clauses_from(Kind, engine),
    declared_seam(_, Seam),
    Fault = 'is declared multifile, which lets a caller redefine the very \c
             predicate it was published to call'.
seam_direction_fault(Seam, Kind, Fault) :-
    seam:clauses_from(Kind, engine),
    Seam = Name/Arity,
    functor(Head, Name, Arity),
    \+ ( candidate_engine_module(Module), current_predicate(_, Module:Head) ),
    Fault = 'is published but not defined, so a caller reaching for it gets \c
             an existence error'.

%%%% Arithmetic expansion stays at run time %%%%
%
% library(arithmetic) installs `system:goal_expansion(Math, MathGoal) :-
% math_goal_expansion(Math, MathGoal)` (arithmetic.pl:319-320), consulted
% while compiling EVERY module, and its one raise site is a COMPILE-time
% type_error(evaluable, F) that drops the clause in flight --
% tests/prolog/suites/evaluation/metta.plt registered 233 tests instead of 234 until
% engine/metta.pl guarded that clause at boot and armed a prolog_listen/2
% watcher for its reinstallation. Both of those know arithmetic's clause by
% shape; this check holds the CLASS invariant on the loaded tree instead:
% expanding a goal whose expression SWI compiles and raises on at RUN time
% must neither throw nor rewrite, whatever library an import pulled in. The
% plunit lane's load-ERROR detector is the paired net over what the suites
% pull in, which is more than this file loads. The plant is a throwing
% expander of the same shape as the fault the check must catch.
expansion_leaves_run_time_arithmetic(Report) :-
    Probe = (_ is foo + 1),
    catch(( expand_goal(Probe, Expanded),
            (   Expanded =@= Probe
            ->  Report = clean
            ;   Report = rewrote(Expanded)
            ) ),
          Error,
          Report = threw(Error)).

arithmetic_expansion_stays_at_run_time :-
    expansion_leaves_run_time_arithmetic(Report),
    (   Report == clean
    ->  (   setup_call_cleanup(
                assertz(( system:goal_expansion(Math, _) :-
                              Math = (_ is _),
                              throw(error(type_error(evaluable, planted), _)) ),
                        PlantRef),
                expansion_leaves_run_time_arithmetic(Planted),
                erase(PlantRef)),
            Planted = threw(_)
        ->  format("static: expanding a run-time arithmetic error neither \c
                    throws nor rewrites, and the scan caught a planted \c
                    compile-time expander~n", [])
        ;   format(user_error,
                   'the arithmetic-expansion check reported clean against a \c
                    planted throwing expander, so its clean result says \c
                    nothing~n', []),
            fail
        )
    ;   format(user_error,
               'arithmetic is being judged at compile time: expanding \c
                `_ is foo + 1` gave ~q. A library loaded into this process \c
                installed a process-global system:goal_expansion/2 that \c
                refuses source SWI itself compiles. \c
                guard_arithmetic_goal_expansion/0 in engine/metta.pl covers \c
                library(arithmetic); this is a new expander -- guard it the \c
                same way~n',
               [Report]),
        fail
    ).

%%%% A backend calls only published surface %%%%
%
% The seams in engine/ext_points.pl say what the engine calls. This says what a
% backend may call BACK, which is the half that was missing: MORK reached into
% engine/parser.pl for swrite/2 and metta_unwritable_symbol/2, wrapping the
% second under a private name, and nothing said it should not. SQLite publishes
% the same half deliberately, handing an extension an sqlite3_api_routines
% table so that it never links against internals [source:
% https://www.sqlite.org/loadext.html]; the four services now declared are that
% table and this is the linker that enforces it.
%
% Published surface is three things and all three are read as data rather than
% listed here: a declared service, a declared seam, and a MeTTa builtin, which
% a backend calls as the LANGUAGE and builtin_fun/1 already enumerates.
% Anything else in engine/ is an internal that can be renamed under the backend.
%
% Backends are discovered the way the engine discovers them, by reading
% extensions/*/extension.pl (the same glob engine/metta.pl walks), so a backend
% that is not built loads nothing and is not scanned. That makes the count
% load-bearing and it is printed for that reason: on a tree without the MORK
% artefact this check reads zero backend clauses, which is the correct answer
% and not the same as a clean one. The spelling before this one globbed the
% seat root for .pl files directly, which predated the per-seat folders and
% matched nothing, so the walk passed on zero clauses with the artefact
% present.
a_backend_calls_only_published_surface :-
    forall(seat_control(Control), metta_load_extension(Control)),
    backend_directories(Directories),
    reaches_past_surface(Directories, Reaches),
    (   Reaches == []
    ->  backend_scan_sees_a_planted_reach
    ;   forall(member(Caller-Callee, Reaches),
               format(user_error,
                      'the backend predicate ~w calls ~w, which is an engine \c
                       internal rather than published surface~ndeclare it \c
                       seam:kind(~w, service) in engine/ext_points.pl if a \c
                       backend is meant to call it~n',
                      [Caller, Callee, Callee])),
        fail
    ).

%%%% The host binding calls only published surface %%%%
%
% The backends' check aimed the other way down the same wire: what the HOST
% BINDING's transport may call back. extensions/python/metta/shim.pl is the shipped
% transport, the host_service kind in engine/ext_points.pl is its measured,
% declared list, and this walk keeps the list honest: a shim call to an
% engine internal fails here naming the pair. The walker's own eyesight is
% proven by the backend check's planted reaches in the same run, one proof
% for one shared walker.
% Every shipped host transport: the file that loads it, and the directory its
% clauses live in. A fact each, so the next binding is a line here rather than
% a second copy of the walk, and so the count below is the tree's rather than a
% number in this comment.
host_transport('../../extensions/python/metta/shim.pl', '../../extensions/python/metta').
host_transport('../../extensions/node/bridge.pl', '../../extensions/node').
host_transport('../../extensions/cetta/bridge.pl', '../../extensions/cetta').

%A seat that declares a host transport and has no host_transport/2 row above.
%
%WHICH seats need a row is read off the control files: an entry(host, _) row
%IS the seat saying it has a transport its own runtime consults, so a seat
%with no host role needs none and is not a host binding. That is what tells
%MORK apart from the other three now that all four sit in one folder; before
%the merge the folder did it, which is the same answer by a weaker means.
%
%The rows themselves still cannot be DERIVED, because what they carry is the
%DIRECTORY the transport's clauses live in and entry/2 names only the file:
%the Python seat's clauses are in metta/ beside shim.pl while the Node and C
%seats' are at the seat's top. "Declares seam clauses" does not discriminate
%either, because extensions/python/bridge.pl declares eleven of them without
%being the transport. So the list stays hand-written, and what changes is that
%leaving a seat off it is LOUD.
%
%That is the whole harm ai-cetta-c-constraints.md C4 named: the control-file
%glob is automatic, this fact is not, "and a seat absent from the first is
%silently unchecked" -- the gate reporting "every one of 2 host bindings" and
%meaning it. An unregistered seat is refused by name here rather than passing
%by absence.
unregistered_host_binding(Directory) :-
    seat_control(Control),
    metta_extension_controls(Control, Controls),
    memberchk(entry(host, _), Controls),
    file_directory_name(Control, Directory),
    file_base_name(Directory, Name),
    \+ ( host_transport(_, Registered),
         file_base_name(Registered, RegisteredName),
         %The registered directory is either the seat itself or a directory
         %inside it, which is why this compares against the seat's own name and
         %the registered path rather than the two paths directly.
         (   RegisteredName == Name
         ;   sub_atom(Registered, _, _, _, Name)
         ) ).

a_host_binding_calls_only_published_surface :-
    findall(Unregistered, unregistered_host_binding(Unregistered), Missing),
    (   Missing == []
    ->  true
    ;   forall(member(Seat, Missing),
               format(user_error,
                      'the host binding ~w has no host_transport/2 row in \c
                       tests/prolog/static_checks.pl, so nothing checks that \c
                       its transport calls only published surface~n',
                      [Seat])),
        fail
    ),
    forall(host_transport(Entry, _), ensure_loaded(Entry)),
    findall(Directory, host_transport(_, Directory), Directories),
    reaches_past_surface(Directories, Reaches),
    length(Directories, Bindings),
    (   Reaches == []
    ->  format("static: every one of ~d host bindings calls only published \c
                surface~n", [Bindings])
    ;   forall(member(Caller-Callee, Reaches),
               format(user_error,
                      'the host transport predicate ~w calls ~w, an engine \c
                       internal rather than published surface~ndeclare it \c
                       seam:kind(~w, host_service) in \c
                       engine/ext_points.pl if the host transport is meant to \c
                       call it~n',
                      [Caller, Callee, Callee])),
        fail
    ).

%Every seat's control file, the same glob engine/metta.pl reads. Both checks
%above start here, because the two of them are the two ROLES a control file
%declares rather than two kinds of seat: entry(engine, _) is what the engine
%consults and entry(host, _) is what the seat's own runtime consults, and one
%seat may declare both.
%
%The engine's loader is the one door: it reads the file, checks its declared
%needs, and loads its entries exactly as a boot would, so the walk examines
%the same clauses a real process gets rather than a second hand-rolled load
%path that could drift from the first.
seat_control(Control) :-
    expand_file_name('../../extensions/*/extension.pl', Files),
    member(Control, Files).

% The seat holds the declaration and the implementation lives beside the
% shared library it wraps, which is the split extensions/mork/extension.pl exists to make,
% so both are walked.
backend_directories(['../../extensions/mork', '../../extensions/mork/mork_ffi']).

% The eyesight proof is surface_walk.pl's, shared with the library gate, for
% the reason the walk itself is shared: two callers proving the same walker two
% ways would answer different questions about it. What stays here is what the
% BACKEND direction adds -- a backend that is not built contributes no clauses,
% so a clean result also has to be told apart from an empty one, which is what
% the count is for.
backend_scan_sees_a_planted_reach :-
    backend_directories(Directories),
    extension_clause_count(Directories, Examined),
    planted_internal(Internal),
    (   published_surface(Internal)
    ->  format(user_error,
               'the planted reach ~w is published surface, so it proves \c
                nothing; pick an engine predicate that is not~n', [Internal]),
        fail
    ;   scan_sees_every_planted_reach(Total, Missed),
        (   Missed == []
        ->  format("static: no backend reaches past the published surface in \c
                    ~d backend clauses, and the walk saw a planted reach by \c
                    each of ~d doors~n", [Examined, Total])
        ;   length(Missed, Blind),
            Seen is Total - Blind,
            format(user_error,
                   'the backend surface walk saw ~d of ~d planted reaches, so \c
                    its clean result says nothing~nit is blind to: ~w~n',
                   [Seen, Total, Missed]),
            fail
        )
    ).

%%%% Every registered space name is an ampersand atom %%%%
%
% metta_space_operand/1 refuses an atom without the '&' prefix before it
% probes either registry, which is what makes it 3 inferences on an ordinary
% symbol instead of 8 on the nine hot paths that ask it
% [source: engine/spaces/bounded_matching.pl]. The prefix is the engine's own
% rule at every door that CREATES a space -- metta_space_name/1,
% metta_require_space_name/2, register_provider in the Python seat, and both
% wire decoders -- but seam:foreign_space/1 is an open ownership seam, so a
% provider can name a space those doors would have refused. The consequence is
% not an error: the matcher, get-metatype, the three type-candidate resolvers,
% operation admission, the translator and the codec would all quietly answer
% that the name is no space. This scan is what turns that into a refusal.
%
% Checked twice over, for the reason the cut checks above are: neither reading
% sees the other's names. The LIVE reading enumerates the seam after every
% library, backend and host binding has loaded, which is the only way to see a
% name a provider registered at run time, but a provider whose clause head is a
% VARIABLE answers no name at all when asked with the argument unbound, so
% enumeration cannot reach it. The SOURCE reading is the other half: it reads
% every hook file's seam:foreign_space/1 clause heads as text, so a provider
% file this configuration never loads is still checked, and a run-time provider
% whose head names its space is checked before it is ever consulted. What
% remains outside both is a rule that computes its names, and each of the two
% in this tree carries the prefix in its own guard: mork_owns_space/1 tests
% '&mork' and metta_py_register_foreign/3 is fed by a Python door that refuses
% any other spelling.
%
% A parametric space is named by a nonempty list rather than an atom and
% reaches metta_space_operand/1's second clause, which the prefix does not
% guard, so atom/1 below is the scan's subject and not an oversight.
registered_space_name(Name) :-
    distinct(Name, (   seam:foreign_space(Name)
                   ;   native_storage_module_cache(Name, _)
                   )).

% The clause heads a hook file writes, whether or not this configuration
% loaded the file. Every head is counted, because the count is what proves the
% file discovery and the reading still reach real seam:foreign_space/1 clauses;
% only an ATOM head is judged, because a variable head is a rule that computes
% its names at run time and is the live reading's business. Every clause in the
% four hook directories is of the second kind today, which is why the count and
% the judgement are separated rather than folded together.
declared_space_clause(File, Name) :-
    hook_source_file(File),
    source_term(File, Term),
    foreign_space_clause_head(Term, Name).

declared_space_name(File, Name) :-
    declared_space_clause(File, Name),
    atom(Name).

foreign_space_clause_head(Term, Name) :-
    nonvar(Term),
    Term \= (:- _),
    (   Term = (Head :- _)
    ->  true
    ;   Head = Term
    ),
    nonvar(Head),
    (   Head = seam:foreign_space(Name)
    ->  true
    ;   Head = foreign_space(Name)
    ).

unprefixed_space_name(live, Name) :-
    registered_space_name(Name),
    atom(Name),
    \+ sub_atom(Name, 0, 1, _, '&').
unprefixed_space_name(File, Name) :-
    declared_space_name(File, Name),
    \+ sub_atom(Name, 0, 1, _, '&').

every_registered_space_name_is_an_ampersand_atom :-
    findall(Where-Name, unprefixed_space_name(Where, Name), Offenders0),
    sort(Offenders0, Offenders),
    (   Offenders == []
    ->  aggregate_all(count, registered_space_name(_), Registered),
        aggregate_all(count, declared_space_clause(_, _), Declared),
        space_name_scan_sees_a_planted_name(Registered, Declared)
    ;   forall(member(Where-Name, Offenders),
               format(user_error,
                      'the space ~q, in ~w, is named without the & prefix \c
                       metta_space_operand/1 requires before it probes either \c
                       registry~nevery matcher, metatype, type-candidate and \c
                       codec question about it answers no~nname it with the \c
                       prefix, which is what every door that creates a space \c
                       already demands~n', [Name, Where])),
        fail
    ).

% A scan that finds nothing and a scan that looks at nothing print the same
% line, and this one has two readings to prove.
%
% The LIVE half is proved by a real provider, consulted and then unloaded. It
% is a FILE rather than assertz'd clauses because seam:foreign_space/1 is
% multifile and STATIC, the same constraint seam_provider.pl records, and
% unload_file/1 is how ext_points.plt removes one again.
%
% The SOURCE half is proved the way source_scan_sees_a_planted_cut above
% proves its own: a count, which is what a changed directory list would
% silently break, and a planted TERM through the recogniser in both shapes a
% provider writes, a bare fact and a guarded rule. A planted FILE is not
% available here without leaving a bad provider inside engine/, lib/,
% bindings/python/metta/ or backends/, which is the shipped tree.
space_name_scan_sees_a_planted_name(Registered, Declared) :-
    absolute_file_name('unprefixed_space_provider', File,
                       [file_type(prolog), access(read)]),
    setup_call_cleanup(
        user:consult(File),
        findall(Name, unprefixed_space_name(live, Name), Planted),
        unload_file(File)),
    Fact = seam:foreign_space('static-check-source-name-without-ampersand'),
    Rule = (seam:foreign_space('static-check-source-rule-without-ampersand')
                :- some_guard),
    aggregate_all(count,
                  ( member(Term, [Fact, Rule]),
                    foreign_space_clause_head(Term, Read),
                    atom(Read),
                    \+ sub_atom(Read, 0, 1, _, '&') ),
                  SeenInSource),
    (   Planted == ['static-check-space-without-ampersand'],
        Declared >= 1,
        SeenInSource =:= 2
    ->  format("static: all ~d registered space names carry the & prefix \c
                metta_space_operand/1 requires, and none of the ~d \c
                seam:foreign_space/1 clause heads the sources write names one \c
                without it; the scan saw a planted provider the live reading \c
                enumerates and a planted head of each shape the source \c
                reading reads~n", [Registered, Declared])
    ;   format(user_error,
               'the space-name scan enumerated ~q where the planted provider \c
                was the only expected answer, read ~d source-declared names, \c
                and recognised ~d of 2 planted heads, so its clean result \c
                says nothing~n', [Planted, Declared, SeenInSource]),
        fail
    ).
