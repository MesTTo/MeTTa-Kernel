% Purpose: decompose a directed graph into strongly connected components for
%   shipped engine analyses such as automatic memoization.
% Assumes:
%   - nodes are ground terms and arcs name nodes that appear in the node list;
%     an arc naming an unlisted node fails the assoc lookup rather than being
%     ignored, which is upstream's behaviour
% Guarantees:
%   - nodes_arcs_sccs(+Nodes, +Arcs, -SCCs) answers one list per component,
%     every node in exactly one, in O(|V| + log(|V|)*|E|)
%     [tested: scc_components; commit=9e7d5dc2cad810940e5386d52636ac6946df279d]
%   - the answer is independent of arc order, because components are keyed by
%     Tarjan lowlink and then grouped [tested: scc_is_order_independent;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d]
% Fails when:
%   - an arc names a node absent from Nodes, or a node is not ground
% Owns resources:
%   - attributes on fresh variables local to one call; the catch/throw at the
%     end of nodes_arcs_sccs/3 drops them all when those variables leave scope
% Decides:
%   - this is PORTED code, not ours. Markus Triska wrote it (May 2011) and
%     released it into the public domain; Edison Mera vendors it in xtools as
%     prolog/scc.pl [source: https://github.com/edisonm/xtools/blob/9801a9a74861a0d574636ceabab0cd0f978d3bea/prolog/scc.pl;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d]. The algorithm below is unchanged.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- module(scc, [nodes_arcs_sccs/3]).

:- use_module(library(assoc)).
:- use_module(library(apply)).
:- use_module(library(pairs)).

%!  nodes_arcs_sccs(+Ns, +As, -SCCs) is det.
%
%   Ns is a list of ground nodes, As a list of arc(From, To) terms, and SCCs
%   a list of lists of nodes sharing a strongly connected component.

nodes_arcs_sccs(Ns, As, Ss) :-
        catch((maplist(node_var_pair, Ns, Vs, Ps),
               list_to_assoc(Ps, Assoc),
               maplist(attach_arc(Assoc), As),
               scc(Vs, successors),
               maplist(v_with_lowlink, Vs, Ls1),
               keysort(Ls1, Ls2),
               group_pairs_by_key(Ls2, Ss1),
               pairs_values(Ss1, Ss),
               % reset all attributes
               throw(scc(Ss))),
              scc(Ss),
              true).

% Associate a fresh variable with each node, so that attributes can be
% attached to variables that correspond to nodes.

node_var_pair(N, V, N-V) :- put_attr(V, node, N).

v_with_lowlink(V, L-N) :-
        get_attr(V, lowlink, L),
        get_attr(V, node, N).

successors(V, Vs) :-
        (   get_attr(V, successors, Vs) -> true
        ;   Vs = []
        ).

attach_arc(Assoc, arc(X,Y)) :-
        get_assoc(X, Assoc, VX),
        get_assoc(Y, Assoc, VY),
        successors(VX, Vs),
        put_attr(VX, successors, [VY|Vs]).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Tarjan's strongly connected components algorithm.

   DCGs are used to implicitly pass around the global index, stack
   and the predicate relating a vertex to its successors.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

scc(Vs, Succ) :- phrase(scc(Vs), [s(0,[],Succ)], _).

scc([])     --> [].
scc([V|Vs]) -->
        (   vindex_defined(V) -> scc(Vs)
        ;   scc_(V), scc(Vs)
        ).

scc_(V) -->
        vindex_is_index(V),
        vlowlink_is_index(V),
        index_plus_one,
        s_push(V),
        successors(V, Tos),
        each_edge(Tos, V),
        (   { get_attr(V, index, VI),
              get_attr(V, lowlink, VI) } -> pop_stack_to(V, VI)
        ;   []
        ).

vindex_defined(V) --> { get_attr(V, index, _) }.

vindex_is_index(V) -->
        state(s(Index,_,_)),
        { put_attr(V, index, Index) }.

vlowlink_is_index(V) -->
        state(s(Index,_,_)),
        { put_attr(V, lowlink, Index) }.

index_plus_one -->
        state(s(I,Stack,Succ), s(I1,Stack,Succ)),
        { I1 is I+1 }.

s_push(V)  -->
        state(s(I,Stack,Succ), s(I,[V|Stack],Succ)),
        { put_attr(V, in_stack, true) }.

vlowlink_min_lowlink(V, VP) -->
        { get_attr(V, lowlink, VL),
          get_attr(VP, lowlink, VPL),
          VL1 is min(VL, VPL),
          put_attr(V, lowlink, VL1) }.

successors(V, Tos) --> state(s(_,_,Succ)), { call(Succ, V, Tos) }.

pop_stack_to(V, N) -->
        state(s(I,[First|Stack],Succ), s(I,Stack,Succ)),
        { del_attr(First, in_stack) },
        (   { First == V } -> []
        ;   { put_attr(First, lowlink, N) },
            pop_stack_to(V, N)
        ).

each_edge([], _) --> [].
each_edge([VP|VPs], V) -->
        (   vindex_defined(VP) ->
            (   v_in_stack(VP) ->
                vlowlink_min_lowlink(V, VP)
            ;   []
            )
        ;   scc_(VP),
            vlowlink_min_lowlink(V, VP)
        ),
        each_edge(VPs, V).

v_in_stack(V) --> { get_attr(V, in_stack, true) }.

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   DCG rules to access the state, using right-hand context notation.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

state(S), [S] --> [S].

state(S1, S), [S] --> [S1].
