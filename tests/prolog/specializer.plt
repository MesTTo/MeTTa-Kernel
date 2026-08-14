% Purpose: verify higher-order specialization keys, per-clause bindings, and
%   recursive folding directly against generated Prolog clauses.
% Open Obligations:
%   To Do: Port the remaining shell-only failed-specialization regressions.
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(specializer).

set_specializer_test_mode :-
    retractall(silent(_)),
    assertz(silent(true)).

cleanup_specializer_symbols(Names) :-
    forall(member(Name, Names),
           ( invalidate_specializations(Name),
             forget_symbol(Name) )),
    retractall(silent(_)),
    assertz(silent(false)).

setup_multiclause :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-inc $x) (+ $x 1))\n
(= (plunit-spec-t2 $f 0) ($f 100))\n
(= (plunit-spec-t2 $f $x) ($f ($f $x)))\n
", _),
    process_metta_string("!(plunit-spec-t2 plunit-spec-inc 5)", [7]).

cleanup_multiclause :-
    cleanup_specializer_symbols(['plunit-spec-t2', 'plunit-spec-inc']).

test(all_clauses_are_bound_independently,
     [setup(setup_multiclause), cleanup(cleanup_multiclause)]) :-
    ho_specialization('plunit-spec-t2', SpecName),
    SpecName == 'plunit-spec-t2_Spec_[plunit-spec-inc]',
    functor(Head, SpecName, 3),
    findall(Head-Body, clause(Head, Body), Clauses),
    length(Clauses, 2),
    forall(member(ClauseHead-_, Clauses),
           arg(1, ClauseHead, 'plunit-spec-inc')),
    \+ ( member(_-ClauseBody, Clauses),
         sub_term(Reduce, ClauseBody),
         compound(Reduce),
         functor(Reduce, reduce, 2) ),
    process_metta_string("!(plunit-spec-t2 plunit-spec-inc 0)", [101, 2]).

setup_two_bindings :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-inc2 $x) (+ $x 1))\n
(= (plunit-spec-dbl2 $x) (* $x 2))\n
(= (plunit-spec-p2 $f $g 1) ($f 1))\n
(= (plunit-spec-p2 $f $g 2) ($g 2))\n
", _),
    process_metta_string(
        "!(plunit-spec-p2 plunit-spec-inc2 plunit-spec-dbl2 1)", [2]).

cleanup_two_bindings :-
    cleanup_specializer_symbols(
        ['plunit-spec-p2', 'plunit-spec-dbl2', 'plunit-spec-inc2']).

test(global_key_covers_every_specialized_argument_position,
     [setup(setup_two_bindings), cleanup(cleanup_two_bindings)]) :-
    ho_specialization('plunit-spec-p2', SpecName),
    SpecName ==
        'plunit-spec-p2_Spec_[plunit-spec-inc2,plunit-spec-dbl2]',
    functor(Head, SpecName, 4),
    findall(Body, clause(Head, Body), Bodies),
    length(Bodies, 2),
    \+ ( member(Body, Bodies),
         sub_term(Reduce, Body),
         compound(Reduce),
         functor(Reduce, reduce, 2) ).

setup_recursive :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-step $x) (+ $x 1))\n
(= (plunit-spec-rep $f 0 $x) $x)\n
(= (plunit-spec-rep $f $n $x)\n
   (if (> $n 0)\n
       (plunit-spec-rep $f (- $n 1) ($f $x))\n
       (empty)))\n
", _),
    process_metta_string("!(plunit-spec-rep plunit-spec-step 3 0)", [3]).

cleanup_recursive :-
    cleanup_specializer_symbols(['plunit-spec-rep', 'plunit-spec-step']).

test(exact_recursive_key_folds_to_specialized_predicate,
     [setup(setup_recursive), cleanup(cleanup_recursive)]) :-
    ho_specialization('plunit-spec-rep', SpecName),
    functor(Head, SpecName, 4),
    forall(clause(Head, Body),
           \+ ( sub_term(GenericCall, Body),
                compound(GenericCall),
                functor(GenericCall, 'plunit-spec-rep', 4) )),
    Goal =.. [SpecName, 'plunit-spec-step', 1000, 0, Result],
    once(call(Goal)),
    Result == 1000.

:- end_tests(specializer).
