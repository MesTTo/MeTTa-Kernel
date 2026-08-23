% Purpose: prove the engine's layering contract holds on the tree as it
%   stands, and that each way of breaking it produces a message naming the two
%   parties and the line that would settle it.
% Assumes:
%   - run from tests/prolog, which is where check.sh runs every suite from
% Guarantees:
%   - the contract's allow-list, its export half and its declared tangles are
%     all satisfied by the measured call graph
%     [tested: test_the_engine_layering_contract_holds_and_a_violation_is_named;
%     commit=dd407a40f623b16eda0bb51a74458f7dd3760e21]
%   - each of the six violation kinds is NAMED rather than only counted, and
%     the walk that finds them is proven to still see every planted reach
%     [tested: test_the_engine_layering_contract_holds_and_a_violation_is_named,
%     the_layering_walk_sees_every_planted_reach;
%     commit=dd407a40f623b16eda0bb51a74458f7dd3760e21]
%   - included source units are attributed to their umbrella subsystem rather
%     than becoming accidental new layer nodes
%     [tested: included_source_units_are_attributed_to_their_umbrella; commit=WORKTREE]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').
:- ensure_loaded(layering).

:- begin_tests(engine_layering).

% Measured once and left in layer_edge/5, because the walk is the expensive
% part and every test below reads the same graph. A planted edge is retracted
% again so the tests do not depend on each other's order.
measured :-
    (   layer_edge(_, _, _, _, _)
    ->  true
    ;   measure_layer_edges
    ).

test(test_the_engine_layering_contract_holds_and_a_violation_is_named) :-
    measured,
    findall(Message, layering_finding(Message), Clean),
    assertion(Clean == []),
    forall(planted_violation(Kind, Clauses, Expected),
           plant_all(Clauses, violation_names(Kind, Expected))),
    findall(Message, layering_finding(Message), Restored),
    assertion(Restored == []).

plant_all([], Goal) :- call(Goal).
plant_all([Clause|Clauses], Goal) :-
    with_planted_contract(Clause, plant_all(Clauses, Goal)).

violation_names(Kind, Expected) :-
    findall(Message, layering_finding(Message), Messages),
    (   forall(member(Fragment, Expected),
               ( member(Message, Messages),
                 sub_atom(Message, _, _, _, Fragment) ))
    ->  true
    ;   format(user_error,
               "the ~w plant was reported as ~w, which does not name every \c
                one of ~w~n", [Kind, Messages, Expected]),
        fail
    ).

% One plant per way the contract can break, so a message that stops naming its
% parties fails here rather than at the next person to read a lane's output.
% The undeclared edge is spelled as parser calling a space builtin, which is a
% cross-subsystem call the contract deliberately does not allow.
planted_violation(undeclared_edge,
                  [layer_edge('parser.pl', sread/2, 'spaces.pl', spaces, 'add-atom'/3)],
                  ['parser:sread/2', 'spaces:add-atom/3',
                   'reaches(parser, spaces']).
planted_violation(stale_contract_line,
                  [reaches(parser, kernel, 'planted by the suite')],
                  ['reaches(parser, kernel, _)', 'no call needs any more']).
planted_violation(new_tangle,
                  [reaches(kernel, parser, 'planted by the suite'),
                   reaches(parser, kernel, 'planted by the suite')],
                  ['mutually recursive', 'no tangle/1 line declares it']).
planted_violation(vanished_tangle,
                  [tangle([parser, kernel])],
                  ['no longer exists']).

% The write half is planted as a measured row rather than as a clause in an
% engine file, because an asserted clause has no file property and the walk
% that finds these reads clause_property(_, file(_)) on purpose: it is what
% keeps a multifile seam's clauses attributed to the file they are written in.
% The planted target is a name no module defines and the registry does not
% declare, which is exactly the shape of the three real ones this caught.
planted_violation(stray_write,
                  [write_edge(parser, 'petta-not-owned'/7, sread/2)],
                  ['parser:sread/2', 'petta-not-owned/7',
                   'petta_shared_registry/1']).

% The export half needs a subsystem the engine LOADS and that declares a
% module. The rewriting and narrowing libraries beside it declare one and the
% engine does not load them, so they are not it; engine/kernel.pl is. Nothing
% cross-calls the kernel, which is why the plant supplies the edge and its
% contract line as well as the missing export.
planted_violation(unexported_reach,
                  [reaches(metta, kernel, 'planted by the suite'),
                   layer_edge('metta.pl', 'petta-probe'/1,
                              'kernel.pl', kernel, 'petta-not-exported'/9)],
                  ['does not export', 'petta-not-exported/9']).

% The clean result above is a claim about a walk, so the walk is asked to prove
% it can still see, one planted reach per way a call can hide. This is
% surface_walk.pl's prover run through THIS lane's recorder, because the two
% share the walk and not the recording.
test(the_layering_walk_sees_every_planted_reach) :-
    layering_walk_sees_every_planted_reach(Total, Missed),
    assertion(Total >= 4),
    assertion(Missed == []).

test(included_source_units_are_attributed_to_their_umbrella) :-
    engine_goal(filereader:metta_source_changed(_), Base, Definer, Indicator),
    assertion(Base == 'filereader.pl'),
    assertion(Definer == filereader),
    assertion(Indicator == metta_source_changed/1),
    measured,
    assertion(layer_edge('filereader.pl', support_invalidate_function_change/2,
                         'support_graph.pl', support_graph,
                         support_invalidate_many/1)).

% The contract's own shape, said out loud: the engine is one large mutual
% recursion plus whatever sits outside it. A reader who expects a layer order
% should see the number that says there is not one yet.
test(the_contract_names_every_subsystem_it_measures) :-
    measured,
    forall(( layer_edge(CallerFile, _, CalleeFile, _, _) ),
           ( subsystem_name(CallerFile, Caller),
             subsystem_name(CalleeFile, Callee),
             assertion(reaches(Caller, Callee, _)) )),
    contract_components(Components),
    assertion(Components \== []).

test(scc_components) :-
    Nodes = [a, b, c, d],
    Arcs = [arc(a, b), arc(b, a), arc(b, c), arc(c, d), arc(d, c)],
    nodes_arcs_sccs(Nodes, Arcs, Raw),
    maplist(sort, Raw, Sorted0),
    sort(Sorted0, Sorted),
    assertion(Sorted == [[a, b], [c, d]]).

test(scc_is_order_independent) :-
    Nodes = [a, b, c, d],
    Arcs = [arc(a, b), arc(b, a), arc(b, c), arc(c, d), arc(d, c)],
    reverse(Arcs, Reversed),
    nodes_arcs_sccs(Nodes, Arcs, First0),
    nodes_arcs_sccs(Nodes, Reversed, Second0),
    maplist(sort, First0, First1),
    maplist(sort, Second0, Second1),
    sort(First1, First),
    sort(Second1, Second),
    assertion(First == Second).

:- end_tests(engine_layering).
