% Purpose: direct coverage for engine/narrowing.pl, the route from termination of
%   narrowing to termination of rewriting.
%   WHAT IT COVERS: NARROWING. The reduction to REWRITING is the file under
%   test's own claim and the one place the two relations meet. Two things need pinning. The
%   published worked examples are reproduced, which is what makes the citation
%   in its header a claim about behaviour rather than a reading list: the
%   authors' own tool prints one filtered system for its AG01 3.12 example, and
%   the paper prints two more for its Examples 14 and 16, and all three come
%   back from this implementation. And the answer is ALWAYS established or a
%   named failure, since a termination analyser that can quietly answer neither
%   is the one shape that would make everything above it unfalsifiable.
% Assumes:
%   - the working directory is tests/prolog. engine/narrowing.pl needs no engine.
%   - '$bottom' here is what TNT prints as nullVar and what the paper writes as
%     the fresh constant for a variable the filtering left unbound.
% Guarantees:
%   - the binding-time analysis is shown to PROPAGATE rather than to return its
%     input: four different declarations over the same rule set produce four
%     different divisions, and each is the one the call graph dictates.
%   - every precondition the theory needs is shown to be checked, by a rule set
%     that breaks exactly one of them and is named for it.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module('../../../../engine/trs.pl').
:- use_module('../../../../engine/narrowing.pl').

% The example the authors' own tool ships and documents a session for
% [source: github.com/mistupv/tnt, examples/AG01/#3.12.trs and README.md].
ag01_3_12([ app(nil, Y1) ==> Y1,
            app(add(N2, X2), Y2) ==> add(N2, app(X2, Y2)),
            reverse(nil) ==> nil,
            reverse(add(N4, X4)) ==> app(reverse(X4), add(N4, nil)),
            shuffle(nil) ==> nil,
            shuffle(add(N6, X6)) ==> add(N6, shuffle(reverse(X6))) ]).

% The paper's Example 9, which its Examples 14 and 16 filter two ways.
append_reverse([ append(nil, Y1) ==> Y1,
                 append(cons(X2, Xs2), Y2) ==> cons(X2, append(Xs2, Y2)),
                 reverse(nil) ==> nil,
                 reverse(cons(X4, Xs4)) ==> append(reverse(Xs4),
                                                   cons(X4, nil)) ]).

% Two systems are the same up to the naming of their variables.
same_rules(As, Bs) :-
    length(As, N),
    length(Bs, N),
    forall(nth1(I, As, A), ( nth1(I, Bs, B), A =@= B )).

:- begin_tests(narrowing_filtering).

% TNT's published session: one declaration in, three modes out.
test(the_published_tnt_example_is_reproduced) :-
    ag01_3_12(Rules),
    defined_symbols(Rules, Ds),
    binding_time_division(Rules, Ds, app/2-[g,v], Division),
    Division == [app/2-[g,v], reverse/1-[g], shuffle/1-[g]],
    division_filtering(Division, Filtering),
    Filtering == [app/2-[1], reverse/1-[1], shuffle/1-[1]],
    aft(Rules, Filtering, Filtered),
    same_rules(Filtered,
               [ app(nil) ==> '$bottom',
                 app(add(N2, X2)) ==> add(N2, app(X2)),
                 reverse(nil) ==> nil,
                 reverse(add(_, X4)) ==> app(reverse(X4)),
                 shuffle(nil) ==> nil,
                 shuffle(add(N6, X6)) ==> add(N6, shuffle(reverse(X6))) ]).

% The inference is a propagation, not a constant: four declarations over one
% rule set give four divisions, each the one its call graph dictates. Declaring
% the shuffle entry non-ground makes reverse non-ground because shuffle calls
% it, and leaves app's first argument ground because app is only ever called on
% a reversed list.
test(one_declaration_infers_the_rest_through_the_call_graph) :-
    ag01_3_12(Rules),
    defined_symbols(Rules, Ds),
    findall(Division,
            ( member(Entry, [app/2-[g,v], shuffle/1-[g],
                             shuffle/1-[v], reverse/1-[v]]),
              binding_time_division(Rules, Ds, Entry, Division) ),
            Divisions),
    Divisions == [ [app/2-[g,v], reverse/1-[g], shuffle/1-[g]],
                   [app/2-[g,g], reverse/1-[g], shuffle/1-[g]],
                   [app/2-[g,v], reverse/1-[v], shuffle/1-[v]],
                   [app/2-[g,v], reverse/1-[v], shuffle/1-[g]] ].

% The paper's Example 14: a variable left unbound by the filtering becomes the
% fresh constant, which is the whole content of its [l -> r] bottom notation.
test(a_variable_the_filtering_unbinds_becomes_the_fresh_constant) :-
    append_reverse(Rules),
    aft(Rules, [append/2-[1], reverse/1-[1]], Filtered),
    same_rules(Filtered,
               [ append(nil) ==> '$bottom',
                 append(cons(X2, Xs2)) ==> cons(X2, append(Xs2)),
                 reverse(nil) ==> nil,
                 reverse(cons(_, Xs4)) ==> append(reverse(Xs4)) ]).

% The paper's Example 16: filtering away the argument that CARRIED a recursive
% call would hide it, so the transformation adds a rule for it. Without the
% added rule the filtered system loses reverse's recursion entirely.
test(the_transformation_adds_a_rule_for_a_call_it_filtered_away) :-
    append_reverse(Rules),
    aft(Rules, [append/2-[2], reverse/1-[1]], Filtered),
    same_rules(Filtered,
               [ append(Y1) ==> Y1,
                 append(Y2) ==> cons('$bottom', append(Y2)),
                 reverse(nil) ==> nil,
                 reverse(cons(X4, _)) ==> append(cons(X4, nil)),
                 reverse(cons(_, Xs4)) ==> reverse(Xs4) ]).

:- end_tests(narrowing_filtering).

:- begin_tests(narrowing_termination).

% A structural recursion terminates when its argument is declared ground, and
% does NOT when it is not, which is the whole reason the analysis takes a mode.
% Narrowing len($x) with an unbound argument enumerates every list.
test(a_ground_declaration_decides_what_an_unknown_one_cannot) :-
    Rules = [ len(nil) ==> zero, len(cons(_, Xs)) ==> s(len(Xs)) ],
    narrowing_terminates(Rules, len(g), Ground),
    Ground = established(_),
    narrowing_terminates(Rules, len(v), Unknown),
    Unknown = not_established(no_rpo_order(_)).

% The compile-time shape the engine ships: a macro whose right-hand side calls
% nothing that has an equation. Every such rule set is decided.
test(a_rule_set_with_no_recursion_is_shown_terminating) :-
    Rules = [ for(Var, Coll, Body) ==>
                  quote(let(Var, superpose(Coll), Body)) ],
    narrowing_terminates(Rules, for(v,v,v), Outcome),
    Outcome = established(route(_, _, rpo(Precedence, _))),
    last(Precedence, for).

% A recursion that decreases only under the INTERPRETATION of a builtin is not
% decided by a path order, and saying so is the required answer. This is the
% shipped translatorrule_fib.metta shape, where the compile-time computation
% terminates because minus counts down and the abstraction cannot see that.
test(a_recursion_that_needs_an_interpretation_is_named_not_claimed) :-
    Rules = [ compilefib(N1) ==> fib(N1),
              fib(N2) ==> fib_tr(N2, zero, one),
              fib_tr(N3, A3, B3) ==> if(eq(N3, zero),
                                        A3,
                                        fib_tr(minus(N3, one), B3,
                                               plus(A3, B3))) ],
    narrowing_terminates(Rules, compilefib(g), Outcome),
    Outcome = not_established(no_rpo_order(_)).

:- end_tests(narrowing_termination).

:- begin_tests(narrowing_preconditions).

% One rule set per precondition, each breaking exactly that one, each named for
% it. The theory is stated for left-linear constructor systems without extra
% variables, and an analysis that quietly ran on something else would be
% answering about a different system.
broken(not_left_linear(1), [ f(X, X) ==> a ], f(g)).
broken(extra_variables(1), [ f(_) ==> g(_) ], f(g)).
broken(symbol_at_two_arities(f), [ f(a) ==> b, g(f(a, a)) ==> c ], g(g)).
broken(not_constructor_system(2), [ f(a) ==> b, g(f(a)) ==> c ], g(g)).
broken(unknown_entry(h/1), [ f(a) ==> b ], h(g)).

test(every_precondition_is_checked_and_named) :-
    forall(broken(Reason, Rules, Abstract),
           ( narrowing_terminates(Rules, Abstract, Outcome),
             Outcome == not_established(Reason) )).

% A mode that is neither g nor v is a caller's mistake, and it raises. Failing
% would leave narrowing_terminates/3 answering neither, which is the third
% state the item forbids, wearing a caller error's clothes.
test(a_mode_that_is_not_a_mode_raises,
     throws(error(type_error(abstract_term, _), _))) :-
    narrowing_terminates([f(_) ==> a], f(maybe), _).

% No third answer. Every rule set above, broken or not, comes back as one of
% the two.
test(there_is_no_third_answer) :-
    ag01_3_12(Ag01),
    append_reverse(AppendReverse),
    findall(Rules-Abstract,
            ( member(Rules-Abstract, [Ag01-app(g,v), AppendReverse-append(g,v)])
            ; broken(_, Rules, Abstract) ),
            Cases),
    forall(member(Rules-Abstract, Cases),
           ( narrowing_terminates(Rules, Abstract, Outcome),
             functor(Outcome, Name, 1),
             memberchk(Name, [established, not_established]) )).

:- end_tests(narrowing_preconditions).
