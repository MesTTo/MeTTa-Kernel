% Purpose: hold the engine's layering contract and gate it, the way
%     import-linter holds and gates the Python package's. The exact
%     lib/lib_tabling/lib_tabling.pl source file is included as the deep-library proof:
%     every engine subsystem it reaches must remain named here too.
% Assumes:
%     - the caller has consulted engine/metta.pl, because the walk reads the
%       DATABASE rather than the sources
%     - the working directory is tests/prolog
% Guarantees:
%     - every call from one engine subsystem into another, and every call from
%       lib_tabling into an engine subsystem, is named in the contract below,
%       or the lane exits nonzero naming caller, callee and the missing line
%       [tested: test_the_engine_layering_contract_holds_and_a_violation_is_named;
%       commit=WORKTREE]
%     - a contract line no call needs any more is reported, so the allow-list
%       cannot silently widen the surface as the engine changes
%     - a cross-subsystem call into a subsystem that declares a module reaches
%       one of that module's EXPORTS
%     - a new mutual recursion between subsystems is refused: the declared
%       tangles are the ones that exist, and the lane names any other
%     - a subsystem does not WRITE a name it does not define, which SWI accepts
%       silently and which sends the write to a predicate nothing reads
%     - a plain source unit below engine/<owner>/ is attributed to its umbrella
%       subsystem for call, export, SCC, and database-write checks
%       [tested: consulted_source_units_are_attributed_to_their_umbrella; commit=9a116762fb4372d55675e2ef64b7657092bc136d]
% Fails when:
%     - a call is assembled at run time from a term no analysis can see. That
%       is the residue this shares with every other static walk in the tree.
% Decides:
%     - a SUBSYSTEM is one engine/*.pl umbrella. A plain file below
%       engine/<owner>/ belongs to engine/<owner>.pl. The one reviewed library
%       node is lib_tabling, attributed only from lib/lib_tabling/lib_tabling.pl rather
%       than widening the gate to every unrelated library.
%     - the contract is an ALLOW-LIST, not a layer order, because the measured
%       graph is one large cycle and a layer order over it would be a fiction.
%       import-linter has both shapes; this is its `forbidden` contract with
%       the complement written down. The tangles below are what a layer order
%       would have to break first, and they are declared so a NEW one fails.
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: None

:- ensure_loaded(surface_walk).
:- use_module('../../engine/scc', [nodes_arcs_sccs/3]).
:- use_module(library(lists)).
:- use_module(library(solution_sequences)).

%%%% Measuring the graph %%%%
%
% The walk is surface_walk.pl's, through walk_clause_edges/2, so the library
% gate and this gate cannot disagree about what a call is: one option list,
% one inference of undeclared meta-predicates, one set of doors proven to fire.
%
% What is NEW here is attributing the callee to the file that DEFINES it. An
% edge arrives qualified with the module the call was compiled in, which stops
% being the defining module the moment a subsystem declares one and the engine
% imports its exports: `spaces.pl` calling `swrite/2` arrives as the engine
% module's swrite/2 and would be attributed to the caller's own file. SWI
% answers the real question directly, and this is the technique xtools'
% module_uses.pl uses for exactly this purpose
% [source: https://github.com/edisonm/xtools prolog/module_uses.pl at commit
% 9801a9a74861a0d574636ceabab0cd0f978d3bea, mu_caller_hook/7:
% `predicate_property(CM:Head, implementation_module(Module))`; Simplified BSD,
% Copyright (c) 2017 Edison Mera].

% CallerFile, CallerPI, CalleeFile, CalleeModule, CalleePI. The callee's
% MODULE is recorded beside its file, because the two stop agreeing as soon as
% a subsystem declares a seam whose clauses live elsewhere: engine/specializer.pl
% holds one clause of support_graph:support_invalidation_action/1, so the file
% is the specializer's and the module is the support graph's, and asking the
% file's module whether it exports the name said no about a predicate it does
% not own [measured 2026-08-22].
:- dynamic layer_edge/5.

engine_directory(Directory) :- tree_directory('../../engine', Directory).

tabling_source_file(File) :- absolute_file_name('../../lib/lib_tabling/lib_tabling.pl', File).

engine_subsystem_file(Base) :-
    source_file(File),
    engine_source_subsystem(File, Base).

% A consulted source unit preserves its umbrella's module and therefore its
% architectural ownership. Reading the first relative path component keeps the
% contract about subsystems instead of turning a source-layout split into new
% call-graph nodes.
engine_source_subsystem(File, Base) :-
    engine_directory(Directory),
    atom_concat(Directory, Relative, File),
    atomic_list_concat(Parts, '/', Relative),
    engine_relative_subsystem(Parts, Base).

% The two subsystems a reviewed file can belong to are EXCLUSIVE: an engine
% path never names lib/lib_tabling/lib_tabling.pl. Said as two clauses over a variable
% first argument, indexing cannot see that, so every engine file left the
% tabling clause behind as a choicepoint and engine_goal/4 became nondet the
% day this second case arrived. The gate reports that and the walks that call
% engine_goal/4 inside forall/2 pay for it [measured 2026-08-26: with the two
% clauses, plunit:call_det/2 answers false on contract_source_subsystem/2 and
% true on every predicate under it, and check.sh's plunit lane failed on
% layering.plt:116; the one call site, engine_goal/4 below, always has File
% bound and there is exactly one answer either way].
contract_source_subsystem(File, Base) :-
    (   engine_source_subsystem(File, EngineBase)
    ->  Base = EngineBase
    ;   tabling_source_file(File),
        Base = 'lib_tabling.pl'
    ).

engine_relative_subsystem([Base], Base).
engine_relative_subsystem([Owner, _|_], Base) :-
    file_name_extension(Owner, pl, Base).

subsystem_name(Base, Name) :- file_name_extension(Name, pl, Base).

measure_layer_edges :-
    ensure_loaded('../../lib/lib_tabling/lib_tabling.pl'),
    retractall(layer_edge(_, _, _, _, _)),
    extension_clauses(['../../engine'], EngineReferences),
    tabling_clause_references(TablingReferences),
    append(EngineReferences, TablingReferences, RawReferences),
    sort(RawReferences, References),
    walk_clause_edges(References, record_layer_edge),
    measure_write_edges.

%surface_walk's directory collector deliberately accepts whole trees. This
%proof asks for one exact third-party-shaped library, so select its clauses by
%their recorded source file and retain the multifile file check the shared
%collector uses.
tabling_clause_references(References) :-
    tabling_source_file(File),
    findall(Reference,
            ( source_file(Module:Head, File),
              Module \== system,
              catch(nth_clause(Module:Head, _, Reference), _, fail),
              clause_property(Reference, file(File)) ),
            References).

record_layer_edge(Callee, Caller, Location) :-
    catch(layer_edge_parts(Callee, Caller, Location), _, fail), !.
record_layer_edge(_, _, _).

layer_edge_parts(Callee, Caller, Location) :-
    caller_goal(Caller, Location, CallerFile, CallerPI),
    callee_goal(Callee, CallerFile, CalleeFile, CalleeModule, CalleePI),
    CallerFile \== CalleeFile,
    (   layer_edge(CallerFile, CallerPI, CalleeFile, CalleeModule, CalleePI)
    ->  true
    ;   assertz(layer_edge(CallerFile, CallerPI, CalleeFile, CalleeModule,
                           CalleePI))
    ).

%A multifile head's predicate_property(file/1) names one contributing file,
%not necessarily the clause being walked. The code walker supplies that
%clause's exact source location, so caller ownership comes from it; otherwise
%a callback implemented by lib_tabling is falsely attributed to ext_points
%and its real library-to-engine reach disappears.
caller_goal(Caller, Location, Base, PI) :-
    get_dict(file, Location, File),
    tabling_source_file(File),
    Base = 'lib_tabling.pl',
    caller_indicator(Caller, PI),
    !.
caller_goal(Caller, _, Base, PI) :- engine_goal(Caller, Base, _, PI).

%For the reviewed library, a declared seam is owned by ext_points even when
%predicate_property(file/1) happens to name one handler clause. Conversely,
%loading the library must not make an engine call to atom_removed/2 look like
%a new engine-to-library dependency merely because that is now its first
%contributing clause.
callee_goal(seam:Goal, 'lib_tabling.pl', 'ext_points.pl', seam, Name/Arity) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    seam:kind(Name/Arity, _),
    !.
callee_goal(Callee, CallerFile, Base, Definer, PI) :-
    engine_goal(Callee, FoundBase, FoundDefiner, PI),
    (   FoundBase == 'lib_tabling.pl',
        CallerFile \== 'lib_tabling.pl',
        Callee = seam:Goal,
        callable(Goal),
        seam:kind(PI, _)
    ->  Base = 'ext_points.pl',
        Definer = seam
    ;   Base = FoundBase,
        Definer = FoundDefiner
    ).

% implementation_module/1 first, so an imported name is attributed to the
% module that defines it; file/1 then names the subsystem. A goal neither an
% engine file nor the reviewed library defines is not an edge this contract is
% about and simply fails here.
engine_goal(Module:Goal, Base, Definer, Name/Arity) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    functor(Probe, Name, Arity),
    predicate_property(Module:Probe, implementation_module(Definer)),
    predicate_property(Definer:Probe, file(File)),
    contract_source_subsystem(File, Base).

%%%% Measuring the database writes %%%%
%
% A base module makes a name visible to a subsystem; it does not make a write
% land on it. assertz/1 or retractall/1 in a module that can only SEE a
% predicate creates a predicate of that name in the WRITING module, and the
% write goes there, where nothing reads it. SWI gives no warning, and
% predicate_property/2's imported_from/1 cannot tell an inherited name from an
% imported one before the write, because base inheritance reports the same
% property an import does, so the only reliable check is a static one: which
% engine file writes which name.
%
% WritingModule, Target, the clause the write is in. Measured for every write,
% owned or not, so the judgement below is a filter over a recorded graph rather
% than a walk of its own, and so the suite can plant a row.
:- dynamic write_edge/3.

measure_write_edges :-
    retractall(write_edge(_, _, _)),
    forall(measured_write(Module, Target, Caller),
           (   write_edge(Module, Target, Caller)
           ->  true
           ;   assertz(write_edge(Module, Target, Caller))
           )).

measured_write(FileModule, Name/Arity, Caller) :-
    source_file(ClauseModule:Head, File),
    engine_source_subsystem(File, _),
    functor(Head, CallerName, CallerArity),
    Caller = CallerName/CallerArity,
    % The clause has to be IN this file. A multifile seam declared here can
    % have clauses in three other files, and clause/2 enumerates every one of
    % them, so without this the lane attributes another subsystem's write here.
    catch(nth_clause(ClauseModule:Head, _, Reference), _, fail),
    clause_property(Reference, file(File)),
    % module/1 is the source context of the clause body. It differs from the
    % predicate module for an explicitly qualified multifile head, and remains
    % available for a plain consulted source unit whose file declares no module.
    clause_property(Reference, module(FileModule)),
    clause(ClauseModule:Head, Body, Reference),
    body_database_write(Body, Written),
    callable(Written),
    % An explicitly qualified write says where it lands and is not this defect.
    Written \= _:_,
    functor(Written, Name, Arity),
    Name \== (:-).

body_database_write(Body, _) :- var(Body), !, fail.
body_database_write((A, B), W) :-
    !, ( body_database_write(A, W) ; body_database_write(B, W) ).
body_database_write((A ; B), W) :-
    !, ( body_database_write(A, W) ; body_database_write(B, W) ).
body_database_write((A -> B), W) :-
    !, ( body_database_write(A, W) ; body_database_write(B, W) ).
body_database_write((A *-> B), W) :-
    !, ( body_database_write(A, W) ; body_database_write(B, W) ).
body_database_write(\+ A, W) :- !, body_database_write(A, W).
body_database_write(Goal, W) :- database_write(Goal, W).
% A write inside a term the clause passes somewhere else, which is how
% engine/spaces.pl spells several of them: forall(..., retractall(..)) arrives
% as an argument of the enclosing goal rather than as a control construct.
body_database_write(Body, W) :-
    compound(Body),
    \+ database_write(Body, _),
    arg(_, Body, Argument),
    compound(Argument),
    body_database_write(Argument, W).

database_write(assertz(W), W).
database_write(asserta(W), W).
database_write(assertz(W, _), W).
database_write(asserta(W, _), W).
database_write(retract(W), W).
database_write(retractall(W), W).

%%%% The contract %%%%
%
% One line per subsystem pair that may call across, with what the caller wants
% from the callee. A pair absent from this list is a violation; a pair here
% that nothing needs any more is reported so the list cannot rot into a
% permission nobody reviewed.

%!  reaches(?Caller, ?Callee, ?Why) is nondet.
%
%   Dynamic so tests/prolog/suites/seams/layering.plt can plant one line of each kind and
%   read what the lane says about it, through with_planted_contract/2 below.
%   Nothing at run time asserts here; the contract is these clauses.

:- dynamic reaches/3.
:- dynamic tangle/1.

%!  with_planted_contract(+Clause, :Goal) is semidet.
%
%   Assert Clause into THIS file's module for the duration of Goal, and erase
%   it afterwards however Goal ends. The suite plants through here rather than
%   asserting from its own module because a plunit unit is a module of its
%   own: an unqualified assertz(reaches(...)) there creates a SECOND, local
%   reaches/3 that shadows this one, after which every contract read answers
%   nothing and the lane reports a clean tree it never looked at
%   [measured 2026-08-22: the stale-line plant reported no finding, and the
%   nine later contract reads all failed, with the whole contract intact].

:- meta_predicate with_planted_contract(+, 0).

with_planted_contract(Clause, Goal) :-
    setup_call_cleanup(assertz(Clause, Reference), Goal, erase(Reference)).

reaches(duals, filereader, 'records the assertion of a generated dual clause').
reaches(duals, metta, 'reads the module context, the function registry and the type declarations it duals over').
reaches(duals, spaces, 'asserts the generated clause into the space it duals for').
reaches(duals, translator, 'duals are generated FROM translated clauses, so it reads the translator\'s metadata and reuses its expression compiler').
reaches(ext_points, filereader, 'a function-changed handler recompiles the affected source').
reaches(ext_points, tracer, 'the tracer is the shipped consumer of the function-changed seam').
reaches(ext_points, translator, 'names the compiled predicate a seam is about, and asks whether a function uses super').
reaches(filereader, metta, 'a load runs forms, which is the engine core\'s job').
reaches(filereader, ext_points, 'a completed source batch announces its compile-time analysis boundary').
reaches(filereader, parser, 'reading a source file is parsing it').
reaches(filereader, spaces, 'a load writes atoms and compiles equations into a space').
reaches(filereader, support_graph, 'a load records what its assertions support so a reload can invalidate them').
reaches(filereader, translator, 'a load compiles the forms it read').
reaches(filereader, type_rules, 'source compilation and rollback hold the typing policy stable while rebuilding affected clauses').
reaches(kernel, metta, 'the kernel builtins are typed and refuse through the core\'s own vocabulary').
reaches(kernel, spaces, 'the kernel builtins ask spaces about their atoms').
reaches(lib_tabling, ext_points, 'declared ownership and event seams route tabled calls and retire their registrations').
reaches(lib_tabling, metta, 'declared context, effect-walk and cache-policy services decide the executable owner and admissible table').
reaches(lib_tabling, parser, 'the published writer renders a rejected reflection row in the language\'s syntax').
reaches(lib_tabling, spaces, 'declared space, storage and module services resolve table dependencies; the ordinary atom doors store reflection rows').
reaches(metta, ext_points, 'installs the atom-write wrappers when a handler exists').
reaches(metta, filereader, 'import! and the file builtins are the loader\'s surface').
reaches(metta, parser, 'sread, swrite and sdisplay are the core\'s text builtins').
reaches(metta, spaces, 'the space builtins are the space subsystem\'s surface').
reaches(metta, support_graph, 'a world admits a program write only after walking who its recompilation reaches').
reaches(metta, translator, 'a runnable form is compiled before it runs').
reaches(metta, translator_rules, 'add-translator-rule! is the rule registry\'s door').
reaches(metta, type_rules, 'every type question resolves through the typing-rule registry').
reaches(parser, metta, 'refuses an unbound input in the core\'s error vocabulary').
reaches(spaces, ext_points, 'announces function changes and asks whether an atom hook is installed').
reaches(spaces, filereader, 'a write records or forgets what its source assertion supports').
reaches(spaces, metta, 'a space write reaches the core\'s registries, contract atoms and error vocabulary').
reaches(spaces, specializer, 'a changed function invalidates the specializations built over it').
reaches(spaces, support_graph, 'a cleared space forgets the support edges of its module').
reaches(spaces, translator, 'storing an equation compiles it').
reaches(spaces, type_rules, 'equation compilation holds the typing policy stable while installing translated clauses').
reaches(specializer, filereader, 'records and forgets the assertion of a generated specialization').
reaches(specializer, metta, 'reads the module and space context and the type declarations it specializes over').
reaches(specializer, parser, 'a minted specialization name must be a symbol the reader reads back').
reaches(specializer, spaces, 'a specialization is stored and compiled into the space it belongs to').
reaches(specializer, support_graph, 'a specialization is a derived artifact with support edges').
reaches(specializer, translator, 'a specialization is a translated clause').
reaches(specializer, type_rules, 'specialization holds the typing policy stable while deriving a compiled clause').
reaches(support_graph, filereader, 'the loader owns the assertion records the graph tracks').
reaches(support_graph, scc, 'the support graph classifies recursive call components').
reaches(support_graph, specializer, 'invalidating a support node runs the specializer\'s invalidation action').
reaches(tracer, filereader, 'a traced form is processed through the loader\'s string door').
reaches(tracer, translator, 'names the compiled predicate a trace wraps').
reaches(translator, duals, 'a negation compiles through the dual it needs').
reaches(translator, ext_points, 'a call may be claimed by a dispatch owner').
reaches(translator, filereader, 'reads whether a head is reducible in the source being loaded').
reaches(translator, metta, 'the core holds the function, arity and type registries the compiler writes and reads').
reaches(translator, parser, 'writes a term as MeTTa text for a compile-time diagnostic').
reaches(translator, spaces, 'compiles into a space\'s execution module and asks that space its capabilities').
reaches(translator, specializer, 'a higher-order call may specialize').
reaches(translator, translator_rules, 'the shipped rule set is the compiler\'s own first tier').
reaches(translator, type_rules, 'a compile-time type check resolves through the typing-rule registry').
reaches(translator_rules, metta, 'refuses an unbound input in the core\'s error vocabulary').
reaches(translator_rules, spaces, 'a shipped rule expands into space operations').
reaches(translator_rules, translator, 'a rule declares itself a special form to the compiler').
reaches(type_rules, filereader, 'records the assertion of a user typing rule').
reaches(type_rules, metta, 'reads the module context a user rule is scoped to').
reaches(type_rules, translator, 'a changed typing rule clears the translation cache').

%!  tangle(?Members) is nondet.
%
%   The subsystems that are mutually recursive TODAY, one line per strongly
%   connected component of the contract above with more than one member. They
%   are declared rather than tolerated silently: a new cycle fails the lane,
%   and shrinking one is a visible edit here. Untangling them is the work a
%   layer order would need first, and this is its measure.

tangle([duals, ext_points, filereader, metta, parser, spaces, specializer,
        support_graph, tracer, translator, translator_rules, type_rules]).

%%%% What the lane checks %%%%

undeclared_edges(Undeclared) :-
    findall(Caller-Callee-CallerPI-CalleePI,
            ( layer_edge(CallerFile, CallerPI, CalleeFile, _, CalleePI),
              subsystem_name(CallerFile, Caller),
              subsystem_name(CalleeFile, Callee),
              \+ reaches(Caller, Callee, _) ),
            Undeclared0),
    sort(Undeclared0, Undeclared).

stale_contract_lines(Stale) :-
    findall(Caller-Callee,
            ( reaches(Caller, Callee, _),
              \+ ( layer_edge(CallerFile, _, CalleeFile, _, _),
                   subsystem_name(CallerFile, Caller),
                   subsystem_name(CalleeFile, Callee) ) ),
            Stale0),
    sort(Stale0, Stale).

% A subsystem that declares a module has an export list, and that list is the
% surface the contract's edges are allowed to reach. Where a subsystem has no
% module the question does not arise and the pair is simply absent, which is
% how this gate stays meaningful while the engine is cut file by file.
unexported_reaches(Unexported) :-
    findall(Module-CalleePI-Caller,
            ( layer_edge(CallerFile, _, _, Module, CalleePI),
              subsystem_name(CallerFile, Caller),
              subsystem_module(Module),
              \+ module_exports(Module, CalleePI) ),
            Unexported0),
    sort(Unexported0, Unexported).

%A module the engine declares, which is what carries an export contract. The
%engine's own module is not one: it has no file of its own, and its cross-file
%calls are what the allow-list above is for.
subsystem_module(Module) :-
    module_property(Module, file(File)),
    engine_directory(Directory),
    sub_atom(File, 0, _, _, Directory).

module_exports(Module, PI) :-
    module_property(Module, exports(Exports)),
    memberchk(PI, Exports).

% The measured components, from the DECLARED graph rather than the walked one,
% because the contract is what a reader can act on and the two agree exactly
% when the lane is green.
contract_components(Components) :-
    findall(Name, distinct(Name, contract_node(Name)), Nodes),
    findall(arc(Caller, Callee),
            ( reaches(Caller, Callee, _), Caller \== Callee ),
            Arcs),
    nodes_arcs_sccs(Nodes, Arcs, Components0),
    maplist(msort, Components0, Components1),
    msort(Components1, Components).

contract_node(Name) :- reaches(Name, _, _).
contract_node(Name) :- reaches(_, Name, _).

new_tangles(New) :-
    contract_components(Components),
    findall(Members,
            ( member(Members, Components),
              Members = [_, _|_],
              \+ ( tangle(Declared), msort(Declared, Members) ) ),
            New).

vanished_tangles(Gone) :-
    contract_components(Components),
    findall(Sorted,
            ( tangle(Declared), msort(Declared, Sorted),
              \+ memberchk(Sorted, Components) ),
            Gone).

%%%% Proving the walk can still see %%%%
%
% A clean result says nothing on its own, so the lane plants the four reaches
% surface_walk.pl plants -- one per way a call can hide -- and runs them
% through THIS recorder rather than that file's, because the recorders differ
% and only the walk is shared. A door that stops firing is named.
layering_walk_sees_every_planted_reach(Total, Missed) :-
    findall(Door, planted_reach(Door, _), Doors),
    length(Doors, Total),
    findall(Door, ( planted_reach(Door, Body), \+ layering_door_is_seen(Body) ),
            Missed).

% The planted callee is register_prolog_arities/1, an engine/metta.pl
% predicate, and the planted caller's clause is asserted into a module that is
% not metta.pl's, so a seen door is a cross-subsystem edge this lane's own
% recorder produced.
% Into its own scratch relation rather than layer_edge/5, so proving the walk
% can see does not destroy the measured graph the rest of the lane reads.
:- dynamic planted_edge/2.

layering_door_is_seen(Body) :-
    planted_internal(Internal),
    once(nth_clause(planted_helper(_, _), 1, HelperReference)),
    setup_call_cleanup(
        assertz((planted_probe :- Body), Reference),
        ( retractall(planted_edge(_, _)),
          walk_clause_edges([Reference, HelperReference], record_planted_edge),
          planted_edge(planted_probe/0, Internal) ),
        erase(Reference)).

% The probe's own clause has no file, so engine_goal/3 cannot name a caller
% subsystem for it. The door test wants the CALLEE half, which is the half
% that decides whether the walk saw the call at all, and it reaches it through
% engine_goal/3 so the attribution this lane depends on is exercised too.
record_planted_edge(Callee, Caller, _Location) :-
    catch(( engine_goal(Callee, _CalleeFile, _CalleeModule, CalleePI),
            caller_indicator(Caller, CallerPI),
            assertz(planted_edge(CallerPI, CalleePI)) ),
          _, true), !.
record_planted_edge(_, _, _).

caller_indicator(_:Goal, PI) :- !, caller_indicator(Goal, PI).
caller_indicator(Goal, Name/Arity) :- callable(Goal), functor(Goal, Name, Arity).

%%%% The lane %%%%
% A write whose target the writing module does not define, and which the core
% has not declared shared. Measured on this tree, each caught after the fact
% and now caught before it: engine/spaces.pl retracting the core's fun/1 left a
% removed function REGISTERED, so a call to it stayed a call and raised
% existence_error(procedure, '$metta_exec:&self':f/2) where the language says
% the term is unreduced; retracting the core's import_life/3 in the clear left
% a cleared space unable to reload the file it had just forgotten; and
% engine/specializer.pl retracting the core's arity/2 was the same defect one
% subsystem along [measured 2026-08-22].
stray_writes(Strays) :-
    findall(Module-PI-Caller,
            ( write_edge(Module, PI, Caller), \+ owns_write(Module, PI) ),
            Strays0),
    sort(Strays0, Strays).

owns_write(Module, Name/Arity) :-
    functor(Probe, Name, Arity),
    catch(( predicate_property(Module:Probe, defined),
            predicate_property(Module:Probe, implementation_module(Module)) ),
          _, fail).
% The selected engine module deliberately imports writable registry services
% from explicit subsystem modules. An unqualified write compiled there resolves
% to that imported dynamic predicate; this is distinct from a space execution
% module inheriting the engine as a base, which is the unsafe case the lane was
% created to catch.
owns_write(Module, Name/Arity) :-
    metta_engine_module(Module),
    functor(Probe, Name, Arity),
    predicate_property(Module:Probe, imported_from(Owner)),
    predicate_property(Owner:Probe, dynamic).
% engine/metta.pl's declared shared tables, which every subsystem imports and
% may therefore write. The declaration is the review: adding a name there is a
% visible edit, and this lane is what makes the alternative visible too.
owns_write(_, PI) :- metta_shared_registry(PI).

%!  layering_finding(-Message) is nondet.
%
%   One message per violation, each naming the two parties and the contract
%   line that would settle it, so a reader can act on the message without
%   opening this file. Nondet rather than a list so the .plt can ask for one
%   planted violation and read what it says.

layering_finding(Message) :-
    undeclared_edges(Undeclared),
    member(Caller-Callee-CallerPI-CalleePI, Undeclared),
    format(atom(Message),
           "~w:~w calls ~w:~w, and no contract line lets it; add \c
            reaches(~w, ~w, '<why>') to tests/prolog/layering.pl, or change \c
            the caller",
           [Caller, CallerPI, Callee, CalleePI, Caller, Callee]).
layering_finding(Message) :-
    stale_contract_lines(Stale),
    member(Caller-Callee, Stale),
    format(atom(Message),
           "reaches(~w, ~w, _) is a contract line no call needs any more; \c
            delete it", [Caller, Callee]).
layering_finding(Message) :-
    unexported_reaches(Unexported),
    member(Callee-CalleePI-Caller, Unexported),
    format(atom(Message),
           "~w reaches ~w:~w, which ~w's module does not export; add it to \c
            the module's export list or change the caller",
           [Caller, Callee, CalleePI, Callee]).
layering_finding(Message) :-
    new_tangles(New),
    member(Members, New),
    format(atom(Message),
           "~w are mutually recursive and no tangle/1 line declares it; break \c
            the cycle or declare it", [Members]).
layering_finding(Message) :-
    stray_writes(Strays),
    member(Module-PI-Caller, Strays),
    format(atom(Message),
           "~w:~w writes ~w, which ~w does not own; a base module makes a name \c
            visible and not writable, so the write lands in ~w where nothing \c
            reads it. Declare it with metta_shared_registry/1 in \c
            engine/metta.pl, or let its owner do the write",
           [Module, Caller, PI, Module, Module]).
layering_finding(Message) :-
    vanished_tangles(Gone),
    member(Members, Gone),
    format(atom(Message),
           "tangle(~w) is declared and no longer exists; delete or shrink the \c
            line", [Members]).

% Entry point named rather than main/0, so tests/prolog/suites/seams/layering.plt can load
% this file for its own questions without running the lane. The gate consults
% the engine itself, which the suite has already done its own way; that is the
% shape tests/prolog/translator_confluence.pl uses for the same reason.
layering_gate :-
    consult('../../engine/qlf_boot.pl'),
    consult('../../engine/metta.pl'),
    measure_layer_edges,
    findall(Message, layering_finding(Message), Findings),
    report(Findings).

report([]) :-
    !,
    layering_walk_sees_every_planted_reach(Total, Missed),
    (   Missed == []
    ->  aggregate_all(count, layer_edge(_, _, _, _, _), Edges),
        aggregate_all(count, reaches(_, _, _), Lines),
        contract_components(Components),
        length(Components, Parts),
        format("layering: ~d cross-subsystem calls, all named by ~d contract \c
                lines; ~d components, and the walk saw a planted reach by each \c
                of ~d doors~n", [Edges, Lines, Parts, Total])
    ;   length(Missed, Blind),
        Seen is Total - Blind,
        format(user_error,
               'the layering walk saw ~d of ~d planted reaches, so its clean \c
                result says nothing~nit is blind to: ~w~n', [Seen, Total, Missed]),
        halt(1)
    ).
report(Findings) :-
    forall(member(Message, Findings),
           format(user_error, "layering: ~w~n", [Message])),
    % halt/1 rather than failing, because a failed goal prints `false` over the
    % report it just produced.
    halt(1).
