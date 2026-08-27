% Purpose: find every engine predicate an extension file calls, and say which
%     of them are published surface.
% Assumes:
%     - the caller has already consulted engine/metta.pl and loaded whichever
%       extension files it wants walked, because this reads the DATABASE rather
%       than the sources: a handler whose body is built at run time is in no
%       file to read [source: the same split tests/prolog/static_checks.pl
%       makes between its source scan and its live scan]
%     - the working directory is tests/prolog, which is where check.sh runs
%       both of its callers from
%     - the engine is consulted before any of this runs, because the module
%       discovery below asks it which spaces exist. Both callers do that in
%       their own main/0.
% Guarantees:
%     - reaches_past_surface/2 answers every call from a clause under one of
%       the given directories to a predicate defined under engine/ that is neither
%       a declared extension point nor a MeTTa builtin, in whichever modules
%       candidate_engine_module/1 below discovers rather than only in `user`
%     - that discovery lives HERE rather than in a caller. It was written in
%       static_checks.pl and left as a contract the caller had to satisfy, and
%       the OTHER caller never did: tests/prolog/library_surface.pl raised
%       existence_error(procedure, candidate_engine_module/1) on every run and,
%       being a REPORT, printed it where a finding would go and exited nonzero,
%       which check.sh reads as findings. A lane reporting a hard error as its
%       working state is exactly what a REPORT tier must not hide
%       [measured 2026-08-19, and the same on c7126f1]
%     - the walk reaches a call through control structure, through a declared
%       meta-argument, and through a meta-predicate NOBODY declared, because
%       SWI infers those [tested: planted_reach/2 in static_checks.pl, one
%       clause per door, each asserted and walked for real]
% Fails when:
%     - a call is assembled at run time from a term no analysis can see,
%       `Goal =.. L, call(Goal)` being the shape. Nothing static catches that,
%       and list_undefined does not either; it is the residue.
%     - a function is compiled into a space whose storage is FOREIGN rather
%       than native, which candidate_engine_module/1 cannot discover. See its
%       own note below; the `user`-only walk it replaces never looked at a
%       foreign space's module either, so this narrows nothing.
% Owns:
%     - reach_found/2 is scratch for one walk and is cleared before each,
%       because prolog_walk_code/1 reports through a side effect rather than
%       by answering
% Decides:
%     - published means DECLARED, not merely reachable. A predicate that is
%       exported, callable and widely used is still an internal here until an
%       seam:kind/2 fact says otherwise, because the point is to make the
%       surface a decision somebody wrote down.
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: None

:- use_module(library(prolog_codewalk)).
:- use_module(library(solution_sequences)).      % distinct/2, for the module walk

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
    walk_clause_edges(References, record_reach),
    findall(Caller-Callee, reach_found(Caller, Callee), Reaches0),
    sort(Reaches0, Reaches).

% The walk itself, with the options that decide what it can see, so a second
% question about the same clauses asks it through this predicate rather than
% writing the option list again. tests/prolog/layering.pl is that second
% caller: it wants every cross-subsystem edge inside engine/ where this file
% wants the ones that reach past the published surface, and a walk configured
% differently would let the two gates disagree about what a call is
% [tested: the_layering_walk_sees_every_planted_reach, which plants the same
% four doors scan_sees_every_planted_reach plants and runs them through the
% layering recorder].
:- meta_predicate walk_clause_edges(+, 3).

walk_clause_edges(References, OnEdge) :-
    prolog_walk_code([ clauses(References),
                       trace_reference(_),
                       on_edge(OnEdge),
                       source(false),
                       infer_meta_predicates(all),
                       autoload(false),
                       undefined(ignore) ]).

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

%The clause has to be IN the file, not merely belong to a predicate the file
%defines. source_file/2 names the heads a file contributes and nth_clause/3
%then enumerates EVERY clause of that predicate, so a multifile seam with one
%handler in lib/ and another in engine/ had the engine's own handler walked as if
%the library had written it, and the engine's internal calls came back as the
%library reaching past the surface [measured 2026-08-19: three of the twenty-one
%findings, recompile_function_impl/1, uses_super/2 and metta_trace_target/1,
%are engine/ clauses of seam:function_changed/1].
%source_file/2 is MODULE-SENSITIVE, and asking it unqualified asks only about
%the module this file was loaded into. That was every engine and library
%predicate while nothing declared a module, and it stops being them the moment
%one does: with engine/kernel.pl declaring `:- module(kernel, ...)`, the
%unqualified form saw NONE of its four predicates while the qualified form saw
%all four, so the walk reported a file it had not looked at
%[measured 2026-08-22, on this tree, before and after the kernel cut].
extension_clauses(Directories, References) :-
    findall(Reference,
            ( member(Relative, Directories),
              tree_directory(Relative, Directory),
              source_file(File),
              sub_atom(File, 0, _, _, Directory),
              source_file(Module:Head, File),
              %SWI records '$load_context_module'/3 against the file it loaded,
              %in `system`, so the qualified form above hands back clauses
              %nobody in lib/ wrote. A user file cannot define a predicate in
              %`system`, so skipping it drops exactly those and nothing else
              %[measured 2026-08-22 over lib/: 442 clauses unqualified, 488
              %qualified, 454 qualified without `system`. The 12 the change
              %adds are the prolog:error_message//1 handlers four library files
              %define, which the unqualified form never walked; findings stayed
              %at 0 throughout].
              Module \== system,
              catch(nth_clause(Module:Head, _, Reference), _, fail),
              clause_property(Reference, file(File)) ),
            References).

extension_clause_count(Directories, Count) :-
    extension_clauses(Directories, References),
    length(References, Count).

% With the separator, so that a sibling named src_generated is not read as
% being inside src.
tree_directory(Relative, Directory) :-
    absolute_file_name(Relative, Absolute),
    atom_concat(Absolute, '/', Directory).

%%%% Which modules the engine's predicates can live in %%%%
%
% Both callers used to assume `user`, which is where &self's compiled clauses
% and the engine's own seams lived because nothing in the tree had given them
% a module of their own. Phase 11 gives &self the execution module
% '$metta_exec:&self' and every other space '$metta_exec:<Space>' beside it,
% each based on the module engine/metta.pl itself loaded into. A check that keeps
% naming `user` then examines the one module nothing compiles into any more
% and reports clean, which is the failure this section exists to close. The
% survey planned a shared '$metta_core' under both; the engine's own module is
% that base as shipped, since nothing needed moving out of it
% [source: engine/spaces.pl's spaces:metta_exec_module_base/2, and
% ai-phase11-module-survey.md section 2.1, workspace root, for the plan].
%
% The fix asks the engine rather than guessing a name. space_module/2 is
% already the one place that answers "which module does this space compile
% into" (engine/spaces.pl:231-232, ai-phase11-module-survey.md section 1.2's
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
% no_cut_in_a_live_hook_clause's anti-vacuity probes in static_checks.pl,
% which are that same rehearsal turned into a standing check].
%
% known_metta_space/1 does not need its own proof of completeness: it reads
% native_storage_module_cache/2, the STORAGE family's own registry
% (engine/spaces.pl:54), which every native add-atom or equation already
% populates as a side effect of storing into a space
% (engine/spaces.pl:79-98,134-135,399-402), so it grows exactly when a space
% becomes worth scanning. '&self' is listed explicitly besides, because the
% invariant that it is always pre-seeded (engine/spaces.pl:104) belongs to
% spaces.pl to keep, not to this file to assume silently.
%
% One space is out of reach, and deliberately: a function compiled into a
% FOREIGN space (one backed by an external provider such as MORK).
% spaces:add_equation/4's foreign clause
% (engine/spaces.pl:394-398) compiles into that space's execution module the
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

engine_predicate(Name/Arity) :-
    functor(Head, Name, Arity),
    candidate_engine_module(Module),
    catch(predicate_property(Module:Head, file(File)), _, fail),
    tree_directory('../../engine', EngineDir),
    sub_atom(File, 0, _, _, EngineDir).

% ASKED of the module system rather than read back out of the declaration
% table. engine/ext_points.pl turns every seam:kind/2 declaration into an
% export of the engine's module, so the export list IS the surface and this
% cannot drift from it: a seam declared and never defined is not exported and
% is not published here either, where reading the table would have called it
% published and left a caller with an existence error. The engine also exports
% every name it emits into compiled bodies, which is how those are bound into a
% space's module at all, so they are surface by the same rule and for a reason
% the kinds do not have to restate [source: engine/ext_points.pl,
% seam:publish/1 and engine/spaces.pl, protect_engine_emitted/1].
%
% A MeTTa builtin is the LANGUAGE, which an extension calls the way any program
% calls it, and builtin_fun/1 is where the language says which names those are.
%Asked of the seam's OWN module, because a seam stopped having one home the
%moment the engine's subsystems started declaring modules: a handler seam is
%exported by `seam`, a service by whichever subsystem defines it, and
%control_exception/1 by the engine core. seam_home/2 answers that by asking
%SWI which module implements the name, so this is still one list held by the
%module system rather than a second reading of the declaration table
%[measured 2026-08-22: asking the engine's module alone reported
%support_forget/1, support_invalidate/1 and support_record/2 as unpublished
%the moment engine/support_graph.pl became a module, with lib/lib_memo.pl
%calling all three exactly as before].
published_surface(Seam) :-
    seam:seam_home(Seam, Home),
    module_property(Home, exports(Exports)),
    memberchk(Seam, Exports).
published_surface(Name/_) :- builtin_fun(Name).

%%%% Proving the walk can still see %%%%
%
% A clean result from any of the three walks above says nothing on its own: a
% bug in record_reach/3, in published_surface/1 or in the options handed to
% prolog_walk_code/1 reports every tree clean and nothing says so. So each
% caller that reports clean proves its eyesight first, against a real clause
% asserted and walked by the real walk, one per way a call can hide, and names
% WHICH door stopped firing rather than only that one did.
%
% It lives here rather than in a caller for the reason the module discovery
% above does: it was written in static_checks.pl for the backend gate, the
% library walk had no equivalent, and the two would answer different questions
% about the same walker. One prover, one walker, both callers.
scan_sees_every_planted_reach(Total, Missed) :-
    findall(Door, planted_reach(Door, _), Doors),
    length(Doors, Total),
    findall(Door, ( planted_reach(Door, Body), \+ door_is_seen(Body) ), Missed).

% The planted callee has to be an engine predicate that is NOT published, or
% the probe proves nothing; a caller checks that before trusting the result.
planted_internal(register_prolog_arities/1).

% The helper's OWN clause is walked beside the probe, because that is how SWI
% comes to know it is a meta-predicate: library(prolog_codewalk) infers a spec
% only for a predicate whose clauses the walk has visited, and the inference is
% then remembered process-wide. Walking the probe alone therefore reported this
% door blind or seeing depending on what the caller had already walked --
% static_checks.pl reaches check/0 first, which walks the whole tree and infers
% it, and library_surface.pl walks nothing else and reported itself blind to
% exactly that one door [measured 2026-08-21]. Including the helper is also the
% faithful case: a backend's own undeclared meta-helper is a clause inside the
% directory being walked [source: library(prolog_codewalk),
% register_possible_meta_clause/1 and infer_new_meta_predicates/2].
door_is_seen(Body) :-
    planted_internal(Internal),
    once(nth_clause(planted_helper(_, _), 1, HelperReference)),
    setup_call_cleanup(
        assertz((planted_probe :- Body), Reference),
        ( walked_reaches([Reference, HelperReference], Reaches),
          memberchk(planted_probe/0-Internal, Reaches) ),
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
