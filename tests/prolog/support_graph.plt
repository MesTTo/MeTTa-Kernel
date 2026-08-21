% Purpose: verify forward support invalidation, cycle safety, support-set
%   replacement, and stabilization cutoff against the engine graph API.
% Guarantees:
%   - The exact P3.6 acceptance test removes a transitive derived fact while
%     preserving an unrelated fact [tested:
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Cycles are visited once and replacing supports detaches the old source
%     [tested: support_graph:an_invalidation_cycle_terminates,
%     support_graph:overlapping_roots_invalidate_the_shared_node_once,
%     support_graph:replacing_supports_detaches_the_old_source;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Releasing a module removes only that module's retained graph state
%     [tested: support_graph:forgetting_a_module_releases_only_its_nodes;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Type-marker and dispatch-policy roots use the same typed, module-scoped
%     invalidation API as derived runtime state [tested:
%     support_graph:language_policy_roots_are_typed_and_module_qualified;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - A change-driven recompile keeps the fuel wrapper on a recursive clause
%     [tested: support_graph:a_recompiled_recursive_clause_keeps_its_fuel_wrapper;
%     commit=e8270f8551083f236ce5134ca299adf5347d6898].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

:- dynamic p36_supported_fact/1.
:- dynamic p36_action_count/2.
:- dynamic p36_compute_count/1.

% The seam's home is the support_graph module now, so the fixture declares
% and writes it there. Unqualified it would have made a second, local
% support_invalidation_action/1 that the graph never consults, and every test
% below would have watched a handler that could not fire.
:- multifile support_graph:support_invalidation_action/1.
support_graph:support_invalidation_action(derived(p36_test, Key)) :-
    retractall(p36_supported_fact(Key)),
    ( retract(p36_action_count(Key, Before)) -> true ; Before = 0 ),
    After is Before + 1,
    assertz(p36_action_count(Key, After)).

p36_compute(Value, Value) :-
    ( retract(p36_compute_count(Before)) -> true ; Before = 0 ),
    After is Before + 1,
    assertz(p36_compute_count(After)).

p36_node(base, derived(p36_test, base)).
p36_node(middle, derived(p36_test, middle)).
p36_node(derived, derived(p36_test, derived)).
p36_node(other, derived(p36_test, other)).
p36_node(old, derived(p36_test, old)).
p36_node(new, derived(p36_test, new)).
p36_node(target, derived(p36_test, target)).
p36_node(cycle_a, derived(p36_test, cycle_a)).
p36_node(cycle_b, derived(p36_test, cycle_b)).
p36_node(cutoff, derived(p36_test, cutoff)).
p36_node(cutoff_child, derived(p36_test, cutoff_child)).
p36_node(other_module, derived(p36_other, target)).
p36_node(type_dependent, derived(p36_test, type_dependent)).
p36_node(dispatch_dependent, derived(p36_test, dispatch_dependent)).
p36_node(type_function, function(p36_test, p33_user)).
p36_node(type_view, function_view(p36_test, p33_user)).
p36_node(dispatch_function, function(p36_test, p31_target)).
p36_node(dispatch_view, function_view(p36_test, p31_target)).

p36_cleanup :-
    forall(p36_node(_, Node), user:support_forget(Node)),
    retractall(user:p36_supported_fact(_)),
    retractall(user:p36_action_count(_, _)),
    retractall(user:p36_compute_count(_)).

:- begin_tests(support_graph, [cleanup(p36_cleanup)]).

test(test_a_derived_fact_is_invalidated_forward_from_what_it_supports) :-
    p36_node(base, Base),
    p36_node(middle, Middle),
    p36_node(derived, Derived),
    assertz(user:p36_supported_fact(base)),
    assertz(user:p36_supported_fact(middle)),
    assertz(user:p36_supported_fact(derived)),
    assertz(user:p36_supported_fact(unrelated)),
    support_graph:support_replace(Middle, [Base]),
    support_graph:support_replace(Derived, [Middle]),
    retractall(user:p36_supported_fact(base)),
    user:support_invalidate(Base),
    assertion(\+ user:p36_supported_fact(base)),
    assertion(\+ user:p36_supported_fact(middle)),
    assertion(\+ user:p36_supported_fact(derived)),
    assertion(user:p36_supported_fact(unrelated)).

test(an_invalidation_cycle_terminates) :-
    p36_node(cycle_a, A),
    p36_node(cycle_b, B),
    assertz(user:p36_supported_fact(cycle_a)),
    assertz(user:p36_supported_fact(cycle_b)),
    support_graph:support_replace(A, [B]),
    support_graph:support_replace(B, [A]),
    call_with_inference_limit(user:support_invalidate(A), 10000, Outcome),
    assertion(Outcome \== inference_limit_exceeded),
    assertion(user:p36_action_count(cycle_a, 1)),
    assertion(user:p36_action_count(cycle_b, 1)).

test(overlapping_roots_invalidate_the_shared_node_once) :-
    p36_node(old, Old),
    p36_node(new, New),
    p36_node(target, Target),
    assertz(user:p36_supported_fact(target)),
    support_graph:support_replace(Target, [Old, New]),
    user:support_invalidate_many([Old, New]),
    assertion(user:p36_action_count(target, 1)).

test(replacing_supports_detaches_the_old_source) :-
    p36_node(old, Old),
    p36_node(new, New),
    p36_node(target, Target),
    assertz(user:p36_supported_fact(target)),
    support_graph:support_replace(Target, [Old]),
    support_graph:support_replace(Target, [New]),
    user:support_invalidate(Old),
    assertion(user:p36_supported_fact(target)),
    user:support_invalidate(New),
    assertion(\+ user:p36_supported_fact(target)).

test(an_unchanged_stabilization_cuts_off_propagation) :-
    p36_node(cutoff, Cutoff),
    p36_node(cutoff_child, Child),
    support_graph:support_replace(Child, [Cutoff]),
    support_graph:support_stabilize(Cutoff, p36_compute(same), same),
    retractall(user:p36_action_count(cutoff_child, _)),
    assertz(user:p36_supported_fact(cutoff_child)),
    user:support_invalidate(Cutoff),
    assertion(user:p36_action_count(cutoff_child, 1)),
    support_graph:support_stabilize(Cutoff, p36_compute(same), same),
    assertion(user:p36_action_count(cutoff_child, 1)),
    support_graph:support_stabilize(Cutoff, p36_compute(unused), same),
    assertion(user:p36_compute_count(2)).

test(forgetting_a_module_releases_only_its_nodes) :-
    p36_node(base, Base),
    p36_node(middle, Middle),
    p36_node(other_module, Other),
    support_graph:support_replace(Middle, [Base]),
    support_graph:support_replace(Other, [derived(p36_other, source)]),
    user:support_forget_module(p36_test),
    assertion(\+ user:supports(Base, Middle)),
    assertion(user:supports(derived(p36_other, source), Other)).

test(language_policy_roots_are_typed_and_module_qualified) :-
    TypeRoot = type_marker(p36_test, p33_late),
    DispatchRoot = dispatch_policy(p36_test, p31_target, argument_mode),
    p36_node(type_function, TypeFunction),
    p36_node(type_view, TypeView),
    p36_node(type_dependent, TypeDependent),
    p36_node(dispatch_function, DispatchFunction),
    p36_node(dispatch_view, DispatchView),
    p36_node(dispatch_dependent, DispatchDependent),
    assertz(user:p36_supported_fact(type_dependent)),
    assertz(user:p36_supported_fact(dispatch_dependent)),
    support_graph:support_replace(TypeFunction, [TypeRoot]),
    support_graph:support_replace(TypeView, [TypeFunction]),
    support_graph:support_replace(TypeDependent, [TypeView]),
    support_graph:support_replace(DispatchFunction, [DispatchRoot]),
    support_graph:support_replace(DispatchView, [DispatchFunction]),
    support_graph:support_replace(DispatchDependent, [DispatchView]),
    user:support_invalidate_many([TypeRoot, DispatchRoot]),
    assertion(\+ user:p36_supported_fact(type_dependent)),
    assertion(\+ user:p36_supported_fact(dispatch_dependent)).

%The clause-compile door instruments a recursive definition with the fuel
%wrapper, and the change-driven recompile that support invalidation queues
%must keep it: the repair path re-translates the stored equation, and at the
%typing-cluster merge it re-asserted the clause uninstrumented, silently
%unbounding recursion the moment anything the function mentions changed.
%Neither parent could show it: one kept the wrapper with no recompile queue,
%the other had the queue and no wrapper.
test(a_recompiled_recursive_clause_keeps_its_fuel_wrapper,
     [ setup(( process_metta_string("(= (sg-fuel-helper $x) $x)", _),
               process_metta_string("(= (sg-fuel-rec $n) (if (> $n 0) (sg-fuel-rec (sg-fuel-helper (- $n 1))) done))", _) )),
       cleanup(( remove_sexp('&self', [=, ['sg-fuel-rec', _], _]),
                 remove_sexp('&self', [=, ['sg-fuel-helper', _], _]) )) ]) :-
    space_module('&self', Module),
    forall(clause(Module:'sg-fuel-rec'(_, _), Before),
           ( term_to_atom(Before, BeforeText),
             assertion(sub_atom(BeforeText, _, _, _, petta_fuel_step)) )),
    process_metta_string("(= (sg-fuel-helper 0) 0)", _),
    forall(clause(Module:'sg-fuel-rec'(_, _), After),
           ( term_to_atom(After, AfterText),
             assertion(sub_atom(AfterText, _, _, _, petta_fuel_step)) )).

:- end_tests(support_graph).
