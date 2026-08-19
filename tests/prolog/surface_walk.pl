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
%     - the engine is consulted before any of this runs, because the module
%       discovery below asks it which spaces exist. Both callers do that in
%       their own main/0.
% Guarantees:
%     - reaches_past_surface/2 answers every call from a clause under one of
%       the given directories to a predicate defined under src/ that is neither
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
%       ext_point_kind/2 fact says otherwise, because the point is to make the
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

%The clause has to be IN the file, not merely belong to a predicate the file
%defines. source_file/2 names the heads a file contributes and nth_clause/3
%then enumerates EVERY clause of that predicate, so a multifile seam with one
%handler in lib/ and another in src/ had the engine's own handler walked as if
%the library had written it, and the engine's internal calls came back as the
%library reaching past the surface [measured 2026-08-19: three of the twenty-one
%findings, recompile_function_impl/1, uses_super/2 and metta_trace_target/1,
%are src/ clauses of metta_on_function_changed/1].
extension_clauses(Directories, References) :-
    findall(Reference,
            ( member(Relative, Directories),
              tree_directory(Relative, Directory),
              source_file(File),
              sub_atom(File, 0, _, _, Directory),
              source_file(Head, File),
              catch(nth_clause(Head, _, Reference), _, fail),
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
% '$petta_exec:&self' and every other space '$petta_exec:<Space>' beside it,
% each based on the module src/metta.pl itself loaded into. A check that keeps
% naming `user` then examines the one module nothing compiles into any more
% and reports clean, which is the failure this section exists to close. The
% survey planned a shared '$petta_core' under both; the engine's own module is
% that base as shipped, since nothing needed moving out of it
% [source: src/spaces.pl's metta_exec_module_base/2, and
% ai-phase11-module-survey.md section 2.1, workspace root, for the plan].
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
% no_cut_in_a_live_hook_clause's anti-vacuity probes in static_checks.pl,
% which are that same rehearsal turned into a standing check].
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
% One space is out of reach, and deliberately: a function compiled into a
% FOREIGN space (one backed by an external provider such as MORK).
% add_equation/4's foreign clause
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
