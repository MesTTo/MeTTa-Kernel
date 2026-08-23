% Purpose: record module-qualified support edges and propagate invalidation
%   from changed inputs to the derived engine artifacts that depend on them.
% Guarantees:
%   - Replacing a derived node's support set removes its former incoming
%     edges before publishing the new set [tested:
%     support_graph:replacing_supports_detaches_the_old_source;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Forward invalidation visits a cycle once and invalidates every reachable
%     derived node [tested:
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports,
%     support_graph:an_invalidation_cycle_terminates,
%     support_graph:overlapping_roots_invalidate_the_shared_node_once;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Stabilization reuses a clean value and cuts off a second propagation
%     wave when recomputation is variant-equal [tested:
%     support_graph:an_unchanged_stabilization_cuts_off_propagation;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Type-marker and dispatch-policy changes are first-class support roots,
%     so language-policy registries can invalidate compiled dependants through
%     the same forward graph [tested:
%     support_graph:language_policy_roots_are_typed_and_module_qualified;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Automatic memo analysis preserves one call-occurrence list per retained
%     RHS and selects a recursive SCC only when one RHS calls that SCC at
%     least twice [tested:
%     test_a_doubly_branching_recursion_is_tabled_automatically_and_a_tail_recursion_is_not;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
% Owns resources: supports/2, support_function_module/2,
%   support_view_module/2, support_dirty_node/1, support_value/2,
%   support_memo_rule/4 and support_memo_changed/2 are transactional dynamic
%   state; support_forget/1, support_forget_module/1 and support_reset/0 release
%   their indexes, edges, dirtiness markers and retained values.
% Guarded by: '$petta_support_graph' serializes graph replacement,
%   invalidation, stabilization and cleanup; support_graph_locked/0 makes
%   callbacks into graph cleanup re-entrant in the owning thread.
% Decides: PeTTa uses demand-driven support graphs with eager dirtiness and a
%   stabilization cutoff. Edges are stored supports(Support, Derived), so a
%   mutation walks only the affected forward subgraph.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The surface is the graph's own vocabulary: what publishes an edge, what
%invalidates and forgets one, and the five seams a loader or a cache
%contributes clauses to. The seams keep the support_ prefix, because here it
%is the DOMAIN noun rather than a namespace the module stands in for: a
%support edge is what the graph is made of, and support_record/2 reads the
%same qualified or not. What the metta_ prefixes on the handler seams were
%doing, this one never did.
%
%Everything else is the graph's machinery: the dirty set, the stabilization
%cutoff, the deferral flags and the walk. A caller that wants one says
%support_graph: and means it, which is what tests/prolog/support_graph.plt now
%does for support_replace/2 and support_stabilize/3
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named,
%test_every_seam_is_reached_under_its_module].
:- module(support_graph,
          [ supports/2,
            support_publish/3,
            support_publish_compiled_form/5,
            support_memo_take_change/2,
            support_memo_sccs/2,
            support_record/2,
            support_invalidate/1,
            support_invalidate_many/1,
            support_forget/1,
            support_forget_module/1,
            support_prune_orphans/0,
            %The node tables and the deferral flag: engine/spaces.pl asks which
            %module a view belongs to and engine/filereader.pl asks the same of
            %a function before it repairs, so both are surface rather than
            %machinery even though they are dynamic.
            support_view_module/2,
            support_function_module/2,
            support_repairs_deferred/0,

            support_invalidation_action/1,
            support_repair_invalidations/0,
            support_assertions_tracked/0,
            support_assertion_record/1,
            support_assertion_records/1
          ]).

:- use_module(library(assoc)).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(nb_set)).
:- use_module(library(pairs)).
:- use_module(scc, [nodes_arcs_sccs/3]).

%An edge carries a HASH OF EACH ENDPOINT in front of the endpoints themselves,
%because SWI indexes an argument and the node terms share only their functor.
%Four node functors over 32,000 edges gave the whole predicate an eight-bucket
%index and a speedup of FOUR, so every duplicate-edge probe scanned a quarter of
%the graph, and a compile that adds edges per form made loading a program
%quadratic in its size [measured 2026-08-23: over 20,000 edges under four
%functors a both-bound probe cost 132.6 microseconds and costs 0.198, and the
%same 500 forms loaded into a 16,000-form program cost 666 microseconds a form].
%
%A ground node's hash is a discriminating first argument. A non-ground one
%leaves its key UNBOUND, which selects exactly the scan such a pattern asks for,
%so supports/2 below keeps its old meaning in every mode.
:- dynamic supports/4.

%The relation every caller reads, inside this module and out. Binding either
%endpoint binds that endpoint's key, so the mode the caller uses is the mode
%that gets indexed.
supports(Support, Derived) :-
    term_hash(Support, SupportKey),
    term_hash(Derived, DerivedKey),
    supports(SupportKey, DerivedKey, Support, Derived).

support_edge_assertz(Support, Derived) :-
    term_hash(Support, SupportKey),
    term_hash(Derived, DerivedKey),
    assertz(supports(SupportKey, DerivedKey, Support, Derived)).

support_edge_assertz(Support, Derived, Ref) :-
    term_hash(Support, SupportKey),
    term_hash(Derived, DerivedKey),
    assertz(supports(SupportKey, DerivedKey, Support, Derived), Ref).

support_edge_retractall(Support, Derived) :-
    term_hash(Support, SupportKey),
    term_hash(Derived, DerivedKey),
    retractall(supports(SupportKey, DerivedKey, Support, Derived)).
:- dynamic support_function_module/2.
:- dynamic support_view_module/2.
:- dynamic support_dirty_node/1.
:- dynamic support_value/2.
:- dynamic support_memo_rule/4.
:- dynamic support_memo_changed/2.
:- thread_local support_graph_locked/0.
:- thread_local support_repairs_deferred/0.

:- multifile support_invalidation_action/1.
seam:kind(support_invalidation_action/1, event).
:- multifile support_repair_invalidations/0.
seam:kind(support_repair_invalidations/0, event).
:- multifile support_assertions_tracked/0.
seam:kind(support_assertions_tracked/0, declaration).
:- multifile support_assertion_record/1.
seam:kind(support_assertion_record/1, event).
:- multifile support_assertion_records/1.
seam:kind(support_assertion_records/1, event).

:- meta_predicate support_stabilize(+, 1, -).
:- meta_predicate with_support_repairs_deferred(0).

% MeTTaLingo's profitability rule is deliberately syntactic and per RHS: a
% recursive component is worth memoizing when one body contains at least two
% calls whose heads belong to that component. Edges are deduplicated for
% Tarjan, while occurrence lists stay uncollapsed for the branch count
% [source: https://github.com/MesTTo/MeTTaScript/blob/5ec7857acc08c83af162e2436a035fe5ef16387d/packages/core/src/tabling.ts#L147-L218;
% commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
support_memo_take_change(Module, Fun) :-
    retract(support_memo_changed(Module, Fun)).

support_memo_sccs(Module, Components) :-
    must_be(atom, Module),
    findall(rule(Fun, Calls), support_memo_rule(Module, _, Fun, Calls), Rules),
    findall(Fun, member(rule(Fun, _), Rules), Nodes0),
    sort(Nodes0, Nodes),
    findall(arc(Fun, Callee),
            ( member(rule(Fun, Calls), Rules),
              member(Callee, Calls),
              memberchk(Callee, Nodes) ),
            Arcs0),
    sort(Arcs0, Arcs),
    (   Arcs == []
    ->  Components = []
    ;   nodes_arcs_sccs(Nodes, Arcs, RawSCCs),
        maplist(sort, RawSCCs, SortedSCCs0),
        sort(SortedSCCs0, SortedSCCs),
        include(support_memo_recursive_component(Arcs),
                SortedSCCs, RecursiveSCCs),
        support_memo_component_index(RecursiveSCCs, Rules, ComponentIndex,
                                     ComponentMaxima),
        maplist(support_memo_component(Arcs, ComponentIndex,
                                       ComponentMaxima),
                RecursiveSCCs, Components)
    ).

support_memo_recursive_component(_, Members) :- Members = [_,_|_], !.
support_memo_recursive_component(Arcs, [Only]) :-
    memberchk(arc(Only, Only), Arcs).

%Index each function to its component, then walk the RHS occurrence lists once.
%Scanning every rule again for every SCC made a source of N unrelated
%definitions quadratic merely to decide that none was recursive.
support_memo_component_index(SCCs, Rules, ComponentIndex, ComponentMaxima) :-
    findall(Fun-Id,
            ( nth0(Id, SCCs, Members), member(Fun, Members) ),
            MembershipPairs0),
    keysort(MembershipPairs0, MembershipPairs),
    list_to_assoc(MembershipPairs, ComponentIndex),
    findall(Id-Count,
            ( member(rule(Fun, Calls), Rules),
              get_assoc(Fun, ComponentIndex, Id),
              include(support_memo_same_component(ComponentIndex, Id),
                      Calls, Inside),
              length(Inside, Count) ),
            Counts0),
    keysort(Counts0, Counts),
    group_pairs_by_key(Counts, Grouped),
    maplist(support_memo_maximum, Grouped, Maxima),
    list_to_assoc(Maxima, ComponentMaxima).

support_memo_same_component(ComponentIndex, Id, Fun) :-
    get_assoc(Fun, ComponentIndex, Id).

support_memo_maximum(Id-Counts, Id-Maximum) :-
    max_list(Counts, Maximum).

support_memo_component(Arcs, ComponentIndex, ComponentMaxima, Members,
                       memo_scc(Members, Recursive, MaxCalls)) :-
    (   Members = [Only]
    ->  ( memberchk(arc(Only, Only), Arcs) -> Recursive = true
        ; Recursive = false )
    ;   Recursive = true
    ),
    Members = [First|_],
    get_assoc(First, ComponentIndex, Id),
    get_assoc(Id, ComponentMaxima, MaxCalls).

% Delta ML records the dynamic dependence trace and propagates a change only
% through the affected trace. The forward index below is that algorithmic
% choice, rather than a scan over every derived artifact.
% [source: Umut A. Acar and Ruy Ley-Wild, Self-adjusting computation with
%   Delta ML, DOI 10.1007/978-3-642-04652-0_1; commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa]
%
% Adapton makes dirtying eager and recomputation demand-driven. Incremental's
% stabilization semantics supplies the variant-equality cutoff: an unchanged
% recomputation does not start another propagation wave.
% [source: Hammer et al., Adapton, DOI 10.1145/2594291.2594324;
%   Jane Street Incremental commit
%   98b5750ec3c006641351bfd858a89136a5dbc52c, src/incremental_intf.ml
%   symbols necessary_if_alive and cutoff; commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa]
%
% IceDust is the language-level precedent for treating derived values as
% maintained declarations rather than bespoke cache callbacks.
% [source: IceDust, DOI 10.4230/LIPIcs.ECOOP.2016.11;
%   commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa]

support_node(function(Module, Name)) :-
    atom(Module),
    atom(Name).
support_node(function_view(Module, Name)) :-
    atom(Module),
    atom(Name).
support_node(specialization(Module, Name)) :-
    atom(Module),
    atom(Name).
support_node(memo(Module, Name, Arity)) :-
    atom(Module),
    atom(Name),
    integer(Arity),
    Arity >= 0.
support_node(compiled_function(Module, Name)) :-
    atom(Module),
    atom(Name).
support_node(translated_form(Module, Id)) :-
    atom(Module),
    ground(Id).
support_node(type_marker(Module, Name)) :-
    atom(Module),
    atom(Name).
support_node(dispatch_policy(Module, Name, Axis)) :-
    atom(Module),
    atom(Name),
    atom(Axis).
support_node(derived(Module, Key)) :-
    atom(Module),
    ground(Key).

must_be_support_node(Node) :-
    (   support_node(Node)
    ->  true
    ;   throw(error(domain_error(petta_support_node, Node),
                    context(support_graph,
                            'support nodes must be typed and module-qualified')))
    ).

support_atomic(Goal) :-
    (   support_graph_locked
    ->  call(Goal)
    ;   with_mutex('$petta_support_graph',
                   setup_call_cleanup(
                       asserta(support_graph_locked, Ref),
                       support_transaction(Goal),
                       erase(Ref)))
    ).

% The equation compile door already owns a database transaction. Reusing it
% avoids a nested transaction for every published source form; standalone graph
% operations still receive the same all-or-nothing database update.
support_transaction(Goal) :-
    ( current_transaction(_) -> call(Goal) ; transaction(Goal) ).

with_support_repairs_deferred(Goal) :-
    (   support_repairs_deferred
    ->  call(Goal)
    ;   setup_call_cleanup(asserta(support_repairs_deferred, Ref),
                           Goal,
                           erase(Ref))
    ).

% Replace the complete incoming support set of one derived artifact.
support_replace(Derived, Supports0) :-
    must_be_support_node(Derived),
    must_be(list, Supports0),
    maplist(must_be_support_node, Supports0),
    sort(Supports0, Supports),
    support_atomic(support_replace_locked(Derived, Supports)).

support_replace_locked(Derived, Supports) :-
    support_index_node_locked(Derived),
    maplist(support_index_node_locked, Supports),
    support_edge_retractall(_, Derived),
    forall(member(Support, Supports), assert_support_edge(Support, Derived)).

% Publish one replacement set and its fixed outgoing links under one lock and
% transaction. Compilation uses this to avoid three synchronization crossings
% per equation while retaining support_replace/2 as the general API.
support_publish(Derived, Supports0, Edges0) :-
    must_be_support_node(Derived),
    must_be(list, Supports0),
    maplist(must_be_support_node, Supports0),
    must_be(list, Edges0),
    maplist(must_be_support_edge, Edges0),
    sort(Supports0, Supports),
    sort(Edges0, Edges),
    support_atomic(support_publish_locked(Derived, Supports, Edges)).

must_be_support_edge(edge(Support, Derived)) :-
    !,
    must_be_support_node(Support),
    must_be_support_node(Derived).
must_be_support_edge(Edge) :-
    throw(error(domain_error(petta_support_edge, Edge),
                context(support_graph,
                        'a support edge is edge(Support, Derived)'))).

support_publish_locked(Derived, Supports, Edges) :-
    support_replace_locked(Derived, Supports),
    forall(member(edge(Support, Child), Edges),
           support_record_locked(Child, Support)).

% record_translated_from/3 has already established these types while it owns a
% fresh clause reference. Keeping its hot publication path here avoids
% re-validating four engine-built nodes for every source form.
support_publish_compiled_form(Module, G, Ref, Supports, Body) :-
    Form = translated_form(Module, Ref),
    Compiled = compiled_function(Module, G),
    Function = function(Module, G),
    View = function_view(Module, G),
    support_memo_body_calls(Module, G, Body, Calls),
    support_atomic(
        ( support_publish_compiled_locked(Supports, Form, Compiled,
                                          Function, View),
          support_publish_memo_rule(Module, G, Ref, Calls) )).

%Most definitions mention only builtins. Probe for one possible source-call
%head before allocating an occurrence list; only a body that can participate
%in a source SCC pays the complete walk.
support_memo_body_calls(Module, Fun, Body, Calls) :-
    once(( support_memo_call_head(Body, Candidate),
           support_memo_potential_callee(Module, Fun, Candidate) )),
    !,
    findall(Call,
            ( support_memo_call_head(Body, Call),
              support_memo_potential_callee(Module, Fun, Call) ),
            Calls).
support_memo_body_calls(_, _, _, []).

%quote/noeval payloads and Error diagnostics are data, not evaluable call
%positions. Counting their contents creates false recursion and was the
%concrete accumulator regression MeTTaLingo's later correction removed.
support_memo_call_head(Term, _) :- var(Term), !, fail.
support_memo_call_head([Head|_], _) :-
    nonvar(Head),
    % policy-inventory-exempt: arbiter-owned-language-law; reason=quote, noeval and Error payloads are syntax or data rather than executable calls; evidence=engine/support_graph.pl:support_memo_call_head/2
    memberchk(Head, [quote, noeval, 'Error']),
    !,
    fail.
support_memo_call_head([Head|_], Head) :- atom(Head).
support_memo_call_head([Head|Arguments], Call) :-
    member(Item, [Head|Arguments]),
    support_memo_call_head(Item, Call).

%Only a source-call edge can participate in a recursive SCC. Known builtins
%are absent unless this module already owns an equation of that name; a later
%definition invalidates and republishes its callers through the support graph,
%at which point the view exists and the edge is retained.
support_publish_memo_rule(Module, G, Ref, Calls) :-
    retractall(support_memo_rule(Module, Ref, _, _)),
    (   Calls == []
    ->  true
    ;   assertz(support_memo_rule(Module, Ref, G, Calls)),
        support_memo_mark_changed(Module, G)
    ).

support_memo_potential_callee(_, Fun, Fun) :- !.
support_memo_potential_callee(Module, _, Call) :-
    support_function_module(Call, Module), !.
support_memo_potential_callee(_, _, Call) :-
    \+ builtin_fun(Call).

support_memo_mark_changed(Module, Fun) :-
    ( support_memo_changed(Module, Fun) -> true
    ; assertz(support_memo_changed(Module, Fun)) ).

support_publish_compiled_locked(Supports, Form, Compiled, Function, View) :-
    maplist(support_index_node_locked, Supports),
    support_index_node_locked(Function),
    support_index_node_locked(View),
    publish_form_edges(Supports, Form, Compiled),
    support_record_persistent_locked(Function, Compiled),
    support_record_persistent_locked(View, Function).

% Clause references are materially more expensive than plain assertion and
% only a source-load rollback consumes them. Keep the common in-memory run
% path on assertz/1 while a tracked load receives the exact ownership group.
publish_form_edges(Supports, Form, Compiled) :-
    support_assertions_tracked,
    !,
    assert_new_support_edges(Supports, Form, Refs, Tail0),
    support_edge_assertz(Form, Compiled, FormRef),
    Tail0 = [FormRef],
    forall(support_assertion_records(Refs), true).
publish_form_edges(Supports, Form, Compiled) :-
    assert_new_support_edges_untracked(Supports, Form),
    support_edge_assertz(Form, Compiled).

assert_new_support_edges([], _, Tail, Tail).
assert_new_support_edges([Support|Supports], Derived, [Ref|Refs], Tail) :-
    support_edge_assertz(Support, Derived, Ref),
    assert_new_support_edges(Supports, Derived, Refs, Tail).

assert_new_support_edges_untracked([], _).
assert_new_support_edges_untracked([Support|Supports], Derived) :-
    support_edge_assertz(Support, Derived),
    assert_new_support_edges_untracked(Supports, Derived).

%Both endpoints are bound here, and binding BOTH keys is what lets SWI combine
%them: the derived key alone hashes 32,000 edges with 8,417 collisions, so a
%quarter of the probes still walk a bucket [measured 2026-08-23 by jiti_list].
support_record_persistent_locked(Derived, Support) :-
    term_hash(Support, SupportKey),
    term_hash(Derived, DerivedKey),
    (   supports(SupportKey, DerivedKey, Support, Derived)
    ->  true
    ;   support_edge_assertz(Support, Derived)
    ).

% Add one support without discarding the other observations for a coarse
% artifact such as a function-level memo cache.
support_record(Derived, Support) :-
    must_be_support_node(Derived),
    must_be_support_node(Support),
    support_atomic(support_record_locked(Derived, Support)).

support_record_locked(Derived, Support) :-
    support_index_node_locked(Derived),
    support_index_node_locked(Support),
    term_hash(Support, SupportKey),
    term_hash(Derived, DerivedKey),
    (   supports(SupportKey, DerivedKey, Support, Derived)
    ->  true
    ;   assert_support_edge(Support, Derived)
    ).

% SWI indexes the first predicate argument, not arbitrary fields inside a
% compound node. These two small indexes make "all module views of F" an
% exact first-argument lookup instead of a scan across every function_view/2
% edge during source compilation.
support_index_node_locked(function(Module, Name)) :-
    !,
    ( support_function_module(Name, Module) -> true
    ; assertz(support_function_module(Name, Module)) ).
support_index_node_locked(function_view(Module, Name)) :-
    !,
    ( support_view_module(Name, Module) -> true
    ; assertz(support_view_module(Name, Module)) ).
support_index_node_locked(_).

assert_support_edge(Support, Derived) :-
    (   support_assertions_tracked
    ->  support_edge_assertz(Support, Derived, Ref),
        forall(support_assertion_record(Ref), true)
    ;   support_edge_assertz(Support, Derived)
    ).

% Drop a retired artifact from both sides of the graph.
support_forget(Node) :-
    must_be_support_node(Node),
    support_atomic(support_forget_locked(Node)).

support_forget_locked(Node) :-
    support_forget_memo_rule(Node),
    support_edge_retractall(Node, _),
    support_edge_retractall(_, Node),
    retractall(support_dirty_node(Node)),
    retractall(support_value(Node, _)),
    support_unindex_node_locked(Node).

support_forget_memo_rule(translated_form(Module, Ref)) :-
    !,
    findall(Fun, retract(support_memo_rule(Module, Ref, Fun, _)), Funs),
    forall(member(Fun, Funs), support_memo_mark_changed(Module, Fun)).
support_forget_memo_rule(_).

support_unindex_node_locked(function(Module, Name)) :-
    !,
    retractall(support_function_module(Name, Module)).
support_unindex_node_locked(function_view(Module, Name)) :-
    !,
    retractall(support_view_module(Name, Module)).
support_unindex_node_locked(_).

% A pooled execution module is a resource boundary. Releasing it must not leave
% support roots that a later space life can observe under the recycled name.
support_forget_module(Module) :-
    must_be(atom, Module),
    support_atomic(support_forget_module_locked(Module)).

support_forget_module_locked(Module) :-
    findall(Ref,
            ( clause(supports(_, _, Support, Derived), true, Ref),
              ( support_node_module(Support, Module)
              ; support_node_module(Derived, Module) ) ),
            Refs0),
    sort(Refs0, Refs),
    forall(member(Ref, Refs), erase(Ref)),
    forall(support_module_pattern(Module, Node),
           ( retractall(support_dirty_node(Node)),
             retractall(support_value(Node, _)) )),
    retractall(support_function_module(_, Module)),
    retractall(support_view_module(_, Module)),
    retractall(support_memo_rule(Module, _, _, _)),
    retractall(support_memo_changed(Module, _)),
    support_prune_symbol_indexes_locked.

support_module_pattern(Module, function(Module, _)).
support_module_pattern(Module, function_view(Module, _)).
support_module_pattern(Module, specialization(Module, _)).
support_module_pattern(Module, memo(Module, _, _)).
support_module_pattern(Module, compiled_function(Module, _)).
support_module_pattern(Module, translated_form(Module, _)).
support_module_pattern(Module, type_marker(Module, _)).
support_module_pattern(Module, dispatch_policy(Module, _, _)).
support_module_pattern(Module, derived(Module, _)).

support_prune_symbol_indexes_locked :-
    forall(( support_function_module(Name, Module),
             \+ support_node_has_edge(function(Module, Name)) ),
           retractall(support_function_module(Name, Module))),
    forall(( support_view_module(Name, Module),
             \+ support_node_has_edge(function_view(Module, Name)) ),
           retractall(support_view_module(Name, Module))).

support_node_has_edge(Node) :-
    supports(Node, _),
    !.
support_node_has_edge(Node) :-
    supports(_, Node).

support_node_module(function(Module, _), Module).
support_node_module(function_view(Module, _), Module).
support_node_module(specialization(Module, _), Module).
support_node_module(memo(Module, _, _), Module).
support_node_module(compiled_function(Module, _), Module).
support_node_module(translated_form(Module, _), Module).
support_node_module(type_marker(Module, _), Module).
support_node_module(dispatch_policy(Module, _, _), Module).
support_node_module(derived(Module, _), Module).

% A failed source load erases its form-owned edges directly. Aggregate compiled
% and function links are shared across source units, so they are not owned by
% the first file that happened to assert them; prune them only when no form or
% artifact still contributes to the aggregate.
support_prune_orphans :-
    support_atomic(support_prune_orphans_locked).

support_prune_orphans_locked :-
    findall(Compiled-Function,
            ( supports(Compiled, Function),
              Compiled = compiled_function(Module, Name),
              Function = function(Module, Name),
              \+ supports(translated_form(Module, _), Compiled) ),
            Pairs0),
    sort(Pairs0, Pairs),
    forall(member(Compiled-_, Pairs), support_forget_locked(Compiled)),
    forall(member(_-Function, Pairs), support_prune_function_locked(Function)).

support_prune_function_locked(Function) :-
    Function = function(Module, Name),
    View = function_view(Module, Name),
    \+ supports(_, Function),
    \+ ( supports(Function, Other), Other \== View ),
    !,
    support_forget_locked(Function).
support_prune_function_locked(_).

% Invalidation is O(V_delta + E_delta) expected: nb_set gives an expected
% constant-time visited check, and each reachable node and forward edge is
% inspected once. The closure is fixed before callbacks mutate artifacts.
support_invalidate(Support) :-
    support_invalidate_many([Support]).

% Invalidate a set of changed roots as one wave. A shared visited set means a
% derived node reached from two roots still runs its invalidation action once.
support_invalidate_many(Supports0) :-
    must_be(list, Supports0),
    maplist(must_be_support_node, Supports0),
    sort(Supports0, Supports),
    support_invalidate_many_sorted(Supports).

support_invalidate_many_sorted([]) :- !.
support_invalidate_many_sorted(Supports) :-
    with_support_repairs_deferred(
        support_atomic(support_invalidate_many_locked(Supports))).

support_invalidate_many_locked(Supports) :-
    empty_nb_set(Seen),
    support_visit_list(Supports, Seen, Affected, []),
    forall(member(Node, Affected), support_mark_dirty(Node)),
    forall(( member(Node, Affected),
             support_invalidation_action(Node) ),
           true).

support_mark_dirty(Node) :-
    ( support_dirty_node(Node) -> true ; assertz(support_dirty_node(Node)) ).

support_visit(Node, Seen, Nodes, Tail) :-
    add_nb_set(Node, Seen, New),
    (   New == false
    ->  Nodes = Tail
    ;   Nodes = [Node|Rest],
        term_hash(Node, NodeKey),
        findall(Derived, supports(NodeKey, _, Node, Derived), DerivedNodes),
        support_visit_list(DerivedNodes, Seen, Rest, Tail)
    ).

support_visit_list([], _, Tail, Tail).
support_visit_list([Node|Nodes], Seen, Out, Tail) :-
    support_visit(Node, Seen, Out, Rest),
    support_visit_list(Nodes, Seen, Rest, Tail).

support_is_dirty(Node) :-
    support_dirty_node(Node).

% Compute is called as call(Compute, FreshValue). A clean retained value is
% returned without calling it. A changed value invalidates successors; an
% unchanged one clears this node and performs no second forward walk.
support_stabilize(Derived, Compute, Value) :-
    must_be_support_node(Derived),
    must_be(callable, Compute),
    support_atomic(support_stabilize_locked(Derived, Compute, Value)).

support_stabilize_locked(Derived, _, Value) :-
    \+ support_dirty_node(Derived),
    support_value(Derived, Stored),
    !,
    copy_term(Stored, Value).
support_stabilize_locked(Derived, Compute, Value) :-
    call(Compute, Fresh),
    (   support_value(Derived, Previous),
        Previous =@= Fresh
    ->  retractall(support_dirty_node(Derived))
    ;   retractall(support_value(Derived, _)),
        assertz(support_value(Derived, Fresh)),
        retractall(support_dirty_node(Derived)),
        support_invalidate_successors_locked(Derived)
    ),
    copy_term(Fresh, Value).

support_invalidate_successors_locked(Derived) :-
    term_hash(Derived, DerivedKey),
    findall(Child, supports(DerivedKey, _, Derived, Child), Children),
    empty_nb_set(Seen),
    add_nb_set(Derived, Seen),
    support_visit_list(Children, Seen, Affected, []),
    forall(member(Node, Affected), support_mark_dirty(Node)),
    forall(( member(Node, Affected),
             support_invalidation_action(Node) ),
           true).

% Test and engine lifecycle seam. Production callers normally retire one
% typed node with support_forget/1; a process-wide cache reset owns all nodes.
support_reset :-
    support_atomic(
        ( retractall(supports(_, _, _, _)),
          retractall(support_function_module(_, _)),
          retractall(support_view_module(_, _)),
          retractall(support_dirty_node(_)),
          retractall(support_value(_, _)),
          retractall(support_memo_rule(_, _, _, _)),
          retractall(support_memo_changed(_, _)) )).
