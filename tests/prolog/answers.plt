% Purpose: the explicit answer form against the live engine: residue
%   closure through eval/2, the bounded-conditional guard, and theta plan
%   rows. shim.plt covers the same predicates engineless; these need
%   eval/2 and native spaces, so this file loads engine AND shim, kept
%   apart from python_surface.plt because shim hooks change which bridge
%   answers the typing tests there.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).
:- initialization(consult('../../python/petta/shim.pl')).

:- begin_tests(python_answer_residue).

% Residue closure at the engine level: the residue decodes against the
% query's own variables and closes through eval/2, each not-false result
% one closure. The wires here are hand-built exactly as janus delivers
% them, so this runs without Python in the process.

residue_name(Variable, Name) :- term_to_atom(Variable, A), atom_string(A, Name).

test(a_true_condition_holds_and_a_false_one_drops) :-
    Pattern1 = [edge, a, Y1],
    residue_name(Y1, N1),
    petta_py_answer_match(["a", [[N1, ["n", 5]]], '@'(true), '@'(none)],
                          Pattern1, '&plunit_resk'),
    assertion(Y1 == 5),
    Pattern2 = [edge, a, Y2],
    residue_name(Y2, N2),
    petta_py_answer_match(
        ["a", [[N2, ["n", 5]]],
         ["e", [["s", ">"], ["v", N2], ["n", 3]]], '@'(none)],
        Pattern2, '&plunit_resk'),
    assertion(Y2 == 5),
    Pattern3 = [edge, a, Y3],
    residue_name(Y3, N3),
    \+ petta_py_answer_match(
        ["a", [[N3, ["n", 2]]],
         ["e", [["s", ">"], ["v", N3], ["n", 3]]], '@'(none)],
        Pattern3, '&plunit_resk').

test(a_match_residue_composes_one_closure_per_solution) :-
    'add-atom'('&plunit_resk', [allowed, b], _),
    'add-atom'('&plunit_resk', [allowed, d], _),
    Pattern = [edge, a, Y],
    residue_name(Y, N),
    findall(Y,
            petta_py_answer_match(
                ["a", [],
                 ["e", [["s", "match"], ["s", "&plunit_resk"],
                        ["e", [["s", "allowed"], ["v", N]]], ["v", N]]],
                 '@'(none)],
                Pattern, '&plunit_resk'),
            Values),
    assertion(Values == [b, d]).

test(a_nonreducing_residue_answers_itself_and_holds) :-
    Pattern = [edge, a, Y],
    residue_name(Y, N),
    petta_py_answer_match(
        ["a", [[N, ["s", "kept"]]],
         ["e", [["s", "plunit-no-equation"], ["s", "q"]]], '@'(none)],
        Pattern, '&plunit_resk'),
    assertion(Y == kept).

test(a_theta_plan_row_binds_the_claimed_patterns) :-
    Claimed = [[edge, X, Y], [edge, Y, Z]],
    residue_name(X, NX), residue_name(Y, NY), residue_name(Z, NZ),
    petta_py_plan_rows(Claimed,
                       [petta_answer('&plunit_resk',
                                     ["a",
                                      [[NX, ["s", a]], [NY, ["s", b]],
                                       [NZ, ["s", c]]],
                                      '@'(true), '@'(none)])]),
    assertion(Claimed == [[edge, a, b], [edge, b, c]]).

:- end_tests(python_answer_residue).

% The ranked provider, Prolog-side: the transport-agnostic half of the
% annotation story. A Prolog provider needs no wire; it sets the answer's
% annotation directly, backtrackably, and top reads it the same way it
% reads one a Python answer carried across.
:- multifile metta_foreign_space/1.
:- multifile metta_foreign_match/3.
metta_foreign_space('&plunit_topk').
metta_foreign_match('&plunit_topk', [scored, X], Options) :-
    nb_setval('$plunit_topk_options', Options),
    member(X-K, [a-0.5, b-0.9, c-0.1, d-0.7]),
    b_setval('$petta_answer_k', K).

:- begin_tests(answers_annotations).

kappa_declare(Entry) :- 'add-atom'('&petta', Entry, _).
kappa_retract(Entry) :- catch('remove-atom'('&petta', Entry, _), _, true).

test(an_undeclared_annotation_is_refused_naming_the_declaration,
     [throws(error(petta_answer_annotation_undeclared('&plunit_kap', _), _))]) :-
    petta_py_answer_match(["a", [], '@'(true), 0.5],
                          [edge, a, _], '&plunit_kap').

test(a_declared_annotation_is_admitted_and_rides_the_answer,
     [ setup(kappa_declare([annotations, '&plunit_kap', ranked])),
       cleanup(kappa_retract([annotations, '&plunit_kap', ranked])) ]) :-
    b_setval('$petta_answer_k', 1),
    petta_py_answer_match(["a", [], '@'(true), 0.8],
                          [edge, a, _], '&plunit_kap'),
    b_getval('$petta_answer_k', K),
    assertion(K == 0.8).

test(top_refuses_an_unordered_context,
     [throws(error(petta_top_unordered('&plunit_topk', bool), _))]) :-
    metta_top_match(2, '&plunit_topk', [scored, _], _).

test(top_answers_the_k_best,
     [ setup(kappa_declare([annotations, '&plunit_topk', ranked])),
       cleanup(kappa_retract([annotations, '&plunit_topk', ranked])) ]) :-
    findall(X, metta_top_match(2, '&plunit_topk', [scored, X], X), Best),
    assertion(Best == [b, d]).

test(top_collects_everything_when_the_push_is_not_declared,
     [ setup(kappa_declare([annotations, '&plunit_topk', ranked])),
       cleanup(kappa_retract([annotations, '&plunit_topk', ranked])) ]) :-
    nb_setval('$plunit_topk_options', unset),
    findall(X, metta_top_match(1, '&plunit_topk', [scored, X], X), Best),
    assertion(Best == [b]),
    nb_getval('$plunit_topk_options', Options),
    assertion(Options == []).

test(top_pushes_the_bound_under_the_three_declarations,
     [ setup(( kappa_declare([annotations, '&plunit_topk', ranked]),
               kappa_declare([emits, '&plunit_topk', 'best-first']),
               kappa_declare([handles, '&plunit_topk', [scored, _], 'Exact']) )),
       cleanup(( kappa_retract([annotations, '&plunit_topk', ranked]),
                 kappa_retract([emits, '&plunit_topk', 'best-first']),
                 kappa_retract([handles, '&plunit_topk', [scored, _], 'Exact']) )) ]) :-
    nb_setval('$plunit_topk_options', unset),
    findall(X, metta_top_match(2, '&plunit_topk', [scored, X], X), _),
    nb_getval('$plunit_topk_options', Options),
    assertion(Options == [limit(2)]).

test(the_plain_goal_form_orders_and_keeps_tie_stability) :-
    findall(X,
            metta_top(3,
                      ( member(X-K, [p-0.5, q-0.9, r-0.5, s-0.1]),
                        b_setval('$petta_answer_k', K) ),
                      X),
            Best),
    assertion(Best == [q, p, r]).

test(the_top_error_has_an_engine_message) :-
    message_to_string(error(petta_top_unordered('&c', bool), none), Message),
    once(sub_string(Message, _, _, _, "ranked")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(answers_annotations).
