% Purpose: hold the engine's layering contract and gate it, the way
%     import-linter holds and gates the Python package's.
% Assumes:
%     - the caller has consulted engine/metta.pl, because the walk reads the
%       DATABASE rather than the sources
%     - the working directory is tests/prolog
% Guarantees:
%     - every call from one engine subsystem into another is named in the
%       contract below, or the lane exits nonzero naming caller, callee and
%       the missing contract line
%     - a contract line no call needs any more is reported, so the allow-list
%       cannot silently widen the surface as the engine changes
%     - a cross-subsystem call into a subsystem that declares a module reaches
%       one of that module's EXPORTS
%     - a new mutual recursion between subsystems is refused: the declared
%       tangles are the ones that exist, and the lane names any other
% Fails when:
%     - a call is assembled at run time from a term no analysis can see. That
%       is the residue this shares with every other static walk in the tree.
% Decides:
%     - a SUBSYSTEM is one engine/*.pl file. That is the unit the row names
%       ("parser, translator, specializer, spaces, tracer, duals ... share one
%       namespace") and the unit a module declaration can carry.
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
:- use_module(scc, [nodes_arcs_sccs/3]).
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

:- dynamic layer_edge/4.        % CallerFile, CallerPI, CalleeFile, CalleePI

engine_directory(Directory) :- tree_directory('../../engine', Directory).

engine_subsystem_file(Base) :-
    engine_directory(Directory),
    source_file(File),
    sub_atom(File, 0, _, _, Directory),
    file_base_name(File, Base).

subsystem_name(Base, Name) :- file_name_extension(Name, pl, Base).

measure_layer_edges :-
    retractall(layer_edge(_, _, _, _)),
    extension_clauses(['../../engine'], References),
    walk_clause_edges(References, record_layer_edge).

record_layer_edge(Callee, Caller, _Location) :-
    catch(layer_edge_parts(Callee, Caller), _, fail), !.
record_layer_edge(_, _, _).

layer_edge_parts(Callee, Caller) :-
    engine_goal(Callee, CalleeFile, CalleePI),
    engine_goal(Caller, CallerFile, CallerPI),
    CallerFile \== CalleeFile,
    (   layer_edge(CallerFile, CallerPI, CalleeFile, CalleePI)
    ->  true
    ;   assertz(layer_edge(CallerFile, CallerPI, CalleeFile, CalleePI))
    ).

% implementation_module/1 first, so an imported name is attributed to the
% module that defines it; file/1 then names the subsystem. A goal no engine
% file defines is not an edge this contract is about and simply fails here.
engine_goal(Module:Goal, Base, Name/Arity) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    functor(Probe, Name, Arity),
    predicate_property(Module:Probe, implementation_module(Definer)),
    predicate_property(Definer:Probe, file(File)),
    engine_directory(Directory),
    sub_atom(File, 0, _, _, Directory),
    file_base_name(File, Base).

%%%% The contract %%%%
%
% One line per subsystem pair that may call across, with what the caller wants
% from the callee. A pair absent from this list is a violation; a pair here
% that nothing needs any more is reported so the list cannot rot into a
% permission nobody reviewed.

%!  reaches(?Caller, ?Callee, ?Why) is nondet.
%
%   Dynamic so tests/prolog/layering.plt can plant one line of each kind and
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
reaches(filereader, parser, 'reading a source file is parsing it').
reaches(filereader, spaces, 'a load writes atoms and compiles equations into a space').
reaches(filereader, support_graph, 'a load records what its assertions support so a reload can invalidate them').
reaches(filereader, translator, 'a load compiles the forms it read').
reaches(kernel, metta, 'the kernel builtins are typed and refuse through the core\'s own vocabulary').
reaches(kernel, spaces, 'the kernel builtins ask spaces about their atoms').
reaches(metta, ext_points, 'installs the atom-write wrappers when a handler exists').
reaches(metta, filereader, 'import! and the file builtins are the loader\'s surface').
reaches(metta, parser, 'sread, swrite and sdisplay are the core\'s text builtins').
reaches(metta, spaces, 'the space builtins are the space subsystem\'s surface').
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
reaches(specializer, filereader, 'records and forgets the assertion of a generated specialization').
reaches(specializer, metta, 'reads the module and space context and the type declarations it specializes over').
reaches(specializer, spaces, 'a specialization is stored and compiled into the space it belongs to').
reaches(specializer, support_graph, 'a specialization is a derived artifact with support edges').
reaches(specializer, translator, 'a specialization is a translated clause').
reaches(support_graph, filereader, 'the loader owns the assertion records the graph tracks').
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
            ( layer_edge(CallerFile, CallerPI, CalleeFile, CalleePI),
              subsystem_name(CallerFile, Caller),
              subsystem_name(CalleeFile, Callee),
              \+ reaches(Caller, Callee, _) ),
            Undeclared0),
    sort(Undeclared0, Undeclared).

stale_contract_lines(Stale) :-
    findall(Caller-Callee,
            ( reaches(Caller, Callee, _),
              \+ ( layer_edge(CallerFile, _, CalleeFile, _),
                   subsystem_name(CallerFile, Caller),
                   subsystem_name(CalleeFile, Callee) ) ),
            Stale0),
    sort(Stale0, Stale).

% A subsystem that declares a module has an export list, and that list is the
% surface the contract's edges are allowed to reach. Where a subsystem has no
% module the question does not arise and the pair is simply absent, which is
% how this gate stays meaningful while the engine is cut file by file.
unexported_reaches(Unexported) :-
    findall(Callee-CalleePI-Caller,
            ( layer_edge(CallerFile, _, CalleeFile, CalleePI),
              subsystem_name(CalleeFile, Callee),
              subsystem_name(CallerFile, Caller),
              subsystem_module(CalleeFile, Module),
              \+ module_exports(Module, CalleePI) ),
            Unexported0),
    sort(Unexported0, Unexported).

subsystem_module(Base, Module) :-
    engine_directory(Directory),
    atom_concat(Directory, Base, File),
    module_property(Module, file(File)).

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
% Into its own scratch relation rather than layer_edge/4, so proving the walk
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
    catch(( engine_goal(Callee, _CalleeFile, CalleePI),
            caller_indicator(Caller, CallerPI),
            assertz(planted_edge(CallerPI, CalleePI)) ),
          _, true), !.
record_planted_edge(_, _, _).

caller_indicator(_:Goal, PI) :- !, caller_indicator(Goal, PI).
caller_indicator(Goal, Name/Arity) :- callable(Goal), functor(Goal, Name, Arity).

%%%% The lane %%%%

% Entry point named rather than main/0, so tests/prolog/layering.plt can load
% this file for its own questions without a consulted engine being consulted
% twice. tests/prolog/translator_confluence.pl is the same shape.
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
    vanished_tangles(Gone),
    member(Members, Gone),
    format(atom(Message),
           "tangle(~w) is declared and no longer exists; delete or shrink the \c
            line", [Members]).

% Entry point named rather than main/0, so tests/prolog/layering.plt can load
% this file for its own questions without running the lane. The gate consults
% the engine itself, which the suite has already done its own way; that is the
% shape tests/prolog/translator_confluence.pl uses for the same reason.
layering_gate :-
    consult('../../engine/metta.pl'),
    measure_layer_edges,
    findall(Message, layering_finding(Message), Findings),
    report(Findings).

report([]) :-
    !,
    layering_walk_sees_every_planted_reach(Total, Missed),
    (   Missed == []
    ->  aggregate_all(count, layer_edge(_, _, _, _), Edges),
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
