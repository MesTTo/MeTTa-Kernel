% Purpose: pin the full-evaluator loop used by the minimal MeTTa metta-thread instruction.
% Assumes: run from tests/prolog so ../../engine/metta.pl resolves to this tree.
% Guarantees:
%   - eager arguments reach a fixpoint while Atom arguments remain written
%   - one prepared application step does not evaluate an Atom-returned value twice
%   - collapse-bind carriers remain inert and duplicate equation answers survive
%   - the compiled equation-body door and runtime eval/2 door agree
% [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:3682-3700,
%   7361-7524; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]

:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(metta_thread).

compiled_answers(Text, Answers) :-
    sread(Text, Body),
    gensym('$metta_thread_probe_', Name),
    translate_clause([=, [Name], Body], Clause),
    current_metta_module(Module),
    compiled_function_name(Name, Predicate),
    Goal =.. [Predicate, Answer],
    setup_call_cleanup(assertz(Module:Clause, Ref),
                       findall(Answer, Module:Goal, Answers),
                       erase(Ref)).

dynamic_answers(Text, Answers) :-
    sread(Text, Term),
    findall(Answer, eval(Term, Answer), Answers).

both_doors(Text, Expected) :-
    compiled_answers(Text, Compiled),
    dynamic_answers(Text, Dynamic),
    assertion(Compiled == Expected),
    assertion(Dynamic == Expected).

both_doors_variant(Text, Expected) :-
    compiled_answers(Text, Compiled),
    dynamic_answers(Text, Dynamic),
    assertion(Compiled =@= Expected),
    assertion(Dynamic =@= Expected).

add_form(Text) :-
    sread(Text, Form),
    'add-atom'('&self', Form, _).

test(eager_arguments_reach_a_fixpoint_and_atom_arguments_stay_written) :-
    add_form("(: c2-thread-choice (-> Bool Atom %Undefined%))"),
    add_form("(= (c2-thread-choice False $held) (quote $held))"),
    both_doors(
        "(metta-thread (c2-thread-choice (if-equal Number Atom True (if-equal Number Grounded True False)) (+ 1 2)) %Undefined% &self)",
        [[quote, ['+', 1, 2]]]).

test(a_prepared_call_does_not_evaluate_an_atom_result_twice) :-
    add_form("(: c2-thread-hold (-> Atom Atom))"),
    add_form("(= (c2-thread-hold $value) $value)"),
    add_form("(: c2-thread-observe (-> %Undefined% Atom))"),
    add_form("(= (c2-thread-observe $value) (quote $value))"),
    both_doors(
        "(metta-thread (c2-thread-observe (c2-thread-hold (+ 1 2))) %Undefined% &self)",
        [[quote, ['+', 1, 2]]]).

test(a_collapse_bind_carrier_is_an_inert_evaluated_expression) :-
    both_doors(
        "(metta-thread (collapse-bind (superpose (left right))) %Undefined% &self)",
        [[[left, [bindings]], [right, [bindings]]]]),
    both_doors(
        "(metta-thread (((+ 1 2) (bindings))) %Undefined% &self)",
        [[[['+', 1, 2], [bindings]]]]),
    both_doors_variant(
        "(metta-thread (((+ 1 2) (bindings (<- (:seg $tail) (a b)) (seq $free)))) %Undefined% &self)",
        [[[['+', 1, 2],
           [bindings, ['<-', [':seg', _], [a, b]], [seq, _]]]]]).

test(function_steps_preserve_duplicate_equation_answers) :-
    add_form("(: c2-thread-many (-> %Undefined%))"),
    add_form("(= (c2-thread-many) c2-thread-answer)"),
    add_form("(= (c2-thread-many) c2-thread-answer)"),
    both_doors(
        "(function (chain (evalc (c2-thread-many) &self) $value (return $value)))",
        ['c2-thread-answer', 'c2-thread-answer']),
    both_doors(
        "(metta-thread (c2-thread-many) %Undefined% &self)",
        ['c2-thread-answer', 'c2-thread-answer']).

:- end_tests(metta_thread).
