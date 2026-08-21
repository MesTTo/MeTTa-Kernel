% Purpose: direct coverage for engine/trs.pl, the adapted term-rewriting library.
%   WHAT IT COVERS: REWRITING, the same as the file under test; nothing here
%   claims anything about narrowing, which tests/prolog/narrowing.plt covers.
%   Two things need pinning that no consumer of it can pin: that the PORT still
%   behaves as the public-domain original it names, which is what makes the
%   provenance in its header a claim rather than a courtesy, and that the
%   additions mirror the Lean side's definitions rather than merely resembling
%   them.
% Assumes:
%   - the working directory is tests/prolog, which is where check.sh runs every
%     Prolog lane from. engine/trs.pl needs no engine, so this suite loads it
%     directly and boots nothing.
% Guarantees:
%   - the documented 10-rule completion of the three group axioms is the one
%     the original documents, rule for rule.
%   - the documented "May not terminate!" caveat is REPRODUCED, not just
%     quoted: the counter-example the original names is run and the loop is
%     observed under an inference limit.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module('../../engine/trs.pl').

:- begin_tests(trs_port).

% The convergent system the original's own header lists, and the reason it is
% listed: i(i(X)) = X is one of the consequences of the three axioms.
test(the_group_axioms_complete_to_the_documented_ten_rules) :-
    group(Es),
    once(equations_trs(Es, Rs)),
    length(Rs, 10),
    forall(member(Documented, [ i(_*_) ==> i(_)*i(_),
                                _*i(_) ==> e,
                                i(i(_)) ==> _,
                                _*e ==> _,
                                _*_*_ ==> _*(_*_),
                                i(_)*_ ==> e,
                                e*_ ==> _,
                                i(_)*(_*_) ==> _,
                                i(e) ==> e,
                                _*(i(_)*_) ==> _ ]),
           ( member(Rule, Rs), subsumes_term(Documented, Rule) )).

test(the_completed_system_decides_the_documented_identity) :-
    group(Es),
    once(equations_trs(Es, Rs)),
    normal_form(Rs, i(i(x)), NF1),
    normal_form(Rs, i(i(i(i(x)))), NF2),
    NF1 == NF2.

% The original documents normal_form/3 as "May not terminate!" and names the
% counter-example. Both halves are checked: the loop happens, and the term it
% loops on really does have a normal form, which is what makes the caveat a
% caveat rather than a bug report.
test(normal_form_loops_on_the_documented_counter_example) :-
    call_with_inference_limit(
        normal_form([a ==> a, f(_) ==> b], f(a), _), 100000, Result),
    Result == inference_limit_exceeded.

test(the_looping_term_does_have_a_normal_form) :-
    step([f(_) ==> b, a ==> a], f(a), T),
    T == b.

% subsumes_term/2 then copy_term/2: a rule may not bind a variable of the term
% it is matched against. The engine's own heads are matched the same way.
test(step_matches_rather_than_unifies) :-
    \+ step([f(a) ==> b], f(_), _),
    ( step([f(a) ==> b], f(X), _) -> true ; true ),
    var(X).

test(critical_pairs_is_a_projection_of_overlaps) :-
    Rules = [f(g(_)) ==> a, g(b) ==> c],
    critical_pairs(Rules, CPs),
    overlaps(Rules, Overlaps),
    length(CPs, N),
    length(Overlaps, N),
    forall(nth1(I, Overlaps, overlap(_,_,_,_,L,R)),
           ( nth1(I, CPs, L1=R1), L1 == L, R1 == R )).

test(overlaps_names_the_two_rules_and_the_position) :-
    overlaps([f(g(_)) ==> a, g(b) ==> c], Overlaps),
    memberchk(overlap(1, 2, Position, Peak, Left, Right), Overlaps),
    Position == [1],
    Peak =@= f(g(b)),
    Left == a,
    Right =@= f(c).

test(a_variable_position_is_not_an_overlap) :-
    overlaps([f(_) ==> a, b ==> c], Overlaps),
    forall(member(overlap(I, J, Pos, _, _, _), Overlaps),
           ( I == J, Pos == [] )).

:- end_tests(trs_port).

:- begin_tests(trs_confluence).

test(one_step_enumerates_every_position_and_every_rule) :-
    one_steps([f(_) ==> b], f(f(a)), Us),
    msort(Us, Sorted),
    Sorted == [b, f(b)].

test(reachable_up_to_bounds_the_search) :-
    reachable_up_to([f(X) ==> f(s(X))], 3, f(a), Ts),
    length(Ts, 4).

test(bounded_join_reports_a_miss_rather_than_a_negative) :-
    \+ bounded_join([f(X) ==> f(s(X))], 3, f(a), f(s(s(s(s(a))))))  ,
    bounded_join([f(X) ==> f(s(X))], 4, f(a), f(s(s(s(s(a)))))).

test(a_divergent_pair_is_a_counterexample_and_a_joinable_one_is_not) :-
    confluence_check([f(a) ==> b, f(_) ==> c], 5, Clash),
    memberchk(verdict(1, 2, [], _, _, counterexample), Clash),
    confluence_check([f(a) ==> b, f(_) ==> b], 5, Agree),
    forall(member(verdict(_,_,_,_,_,Kind), Agree), Kind == joined).

% A pair that only misses because the bound ran out is `unknown`, never
% `counterexample`: the bound is the caller's, and a negative result may not be
% attributed to it. The same system at one more step joins, which is what makes
% this an observation about the bound rather than about the system.
test(a_bound_that_ran_out_is_unknown_not_a_counterexample) :-
    Rules = [f ==> g1, f ==> h, g1 ==> g2, g2 ==> g3, g3 ==> m, h ==> m],
    confluence_check(Rules, 2, Short),
    memberchk(verdict(1, 2, [], _, _, unknown), Short),
    \+ memberchk(verdict(_,_,_,_,_,counterexample), Short),
    confluence_check(Rules, 3, Long),
    forall(member(verdict(_,_,_,_,_,Kind), Long), Kind == joined).

% The peak's variables are numbered before the search, so a variable a rule
% with an extra variable invented on the way does not make two equal terms look
% different. Without that, this rule's overlap with itself reads as divergent.
test(an_invented_variable_does_not_make_a_pair_look_divergent) :-
    confluence_check([f(X) ==> g(X, _)], 3, Verdicts),
    forall(member(verdict(_,_,_,_,_,Kind), Verdicts), Kind == joined).

test(the_side_conditions_discriminate) :-
    left_linear([f(_, _) ==> a]),
    \+ left_linear([f(X, X) ==> a]),
    rhs_vars_in_lhs([f(X) ==> g(X)]),
    \+ rhs_vars_in_lhs([f(_) ==> g(_)]).

:- end_tests(trs_confluence).
