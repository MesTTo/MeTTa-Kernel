% Purpose: pin conformance increment 2 through compiled and dynamic evaluation.
% Assumes: run from tests/prolog so ../../engine/metta.pl resolves to this tree.
% Guarantees: every semantic fix below produces the pinned LeaTTa 9ea9f9d
%   answer through an equation body and through eval/2.

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(conformance2).

compiled_answers(Text, Answers) :-
    sread(Text, Body),
    gensym('$conformance2_probe_', Name),
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

both_doors_raise_assertion(Text) :-
    catch(( compiled_answers(Text, _), Compiled = passed ),
          error(metta_assertion_failed(_), _),
          Compiled = failed),
    catch(( dynamic_answers(Text, _), Dynamic = passed ),
          error(metta_assertion_failed(_), _),
          Dynamic = failed),
    assertion(Compiled == failed),
    assertion(Dynamic == failed).

add_form(Text) :-
    sread(Text, Form),
    'add-atom'('&self', Form, _).

test(symbol_arguments_evaluate_for_declared_and_undeclared_functions,
     [nondet]) :-
    add_form("(: c2-pl-symbol (-> Symbol %Undefined%))"),
    add_form("(= (c2-pl-symbol $x) (quote $x))"),
    add_form("(= (c2-pl-symbol-caller) (c2-pl-symbol c2-pl-before))"),
    add_form("(= (c2-pl-open $x) (quote $x))"),
    add_form("(= c2-pl-before c2-pl-after)"),
    %`(quote $x)` is a BARRIER, so the body answers what $x is bound to with
    %no wrapper left; the point of the row is which value that is.
    both_doors("(c2-pl-symbol-caller)", ['c2-pl-after']),
    both_doors("(c2-pl-open c2-pl-before)", ['c2-pl-after']).

test(a_grounded_parameter_checks_the_evaluated_argument_type) :-
    add_form("(: c2-pl-grounded (-> Grounded %Undefined%))"),
    add_form("(= (c2-pl-grounded $x) (quote $x))"),
    Expected = [['Error', ['c2-pl-grounded', ['+', 1, 2]],
                 ['BadArgType', 1, 'Grounded', 'Number']]],
    both_doors("(c2-pl-grounded (+ 1 2))", Expected).

test(a_variable_result_reenters_evaluation) :-
    add_form("(: c2-pl-variable-result (-> Atom Variable))"),
    add_form("(= (c2-pl-variable-result $x) $x)"),
    both_doors("(c2-pl-variable-result ((+ 1 2)))", [[3]]).

test(an_open_equation_result_is_not_the_not_reducible_marker) :-
    add_form("(= (c2-pl-open-result (: $x $t)) $t)"),
    both_doors("(let $r (c2-pl-open-result $q) (get-metatype $r))",
               ['Variable']).

test(a_rest_atom_parameter_holds_every_variadic_argument) :-
    add_form("(: c2-pl-rest (-> Symbol (%Rest% Atom) %Undefined%))"),
    add_form("(= (c2-pl-rest $tag $x $y $z) (quote ($tag $x $y $z)))"),
    %The barrier is what keeps the three variadic arguments AS WRITTEN here:
    %the wrapper goes, the held arguments do not.
    both_doors("(c2-pl-rest keep (+ 1 2) (+ 3 4) (+ 5 6))",
               [[keep, ['+', 1, 2], ['+', 3, 4], ['+', 5, 6]]]).

test(a_declared_wrong_arity_is_an_error) :-
    add_form("(: c2-pl-arity (-> Atom Atom %Undefined%))"),
    add_form("(= (c2-pl-arity $x) (quote $x))"),
    both_doors("(c2-pl-arity (+ 1 2))",
               [['Error', ['c2-pl-arity', ['+', 1, 2]],
                 'IncorrectNumberOfArguments']]).

test(a_variable_head_applies_the_resolved_heads_mask) :-
    both_doors("(let $head cons-atom ($head (+ 20 22) (tail)))",
               [[['+', 20, 22], tail]]).

test(empty_car_and_cdr_are_exact_error_atoms) :-
    both_doors("(car-atom ())",
               [['Error', ['car-atom', []],
                 "car-atom expects a non-empty expression as an argument"]]),
    both_doors("(cdr-atom ())",
               [['Error', ['cdr-atom', []],
                 "cdr-atom expects a non-empty expression as an argument"]]).

test(collapse_bind_has_one_public_carrier) :-
    both_doors("(collapse-bind (superpose (left right)))",
               [[[left, [bindings]], [right, [bindings]]]]).

test(a_builtin_polymorphic_result_reenters_evaluation) :-
    both_doors("(id (noeval (+ 20 22)))", [42]).

test(collapse_evaluates_an_operand_arriving_through_an_atom_parameter) :-
    add_form("(: c2-pl-collapse (-> Atom %Undefined%))"),
    add_form("(= (c2-pl-collapse $x) (collapse $x))"),
    add_form("(= (c2-pl-many) one)"),
    add_form("(= (c2-pl-many) two)"),
    both_doors("(c2-pl-collapse (c2-pl-many))", [[one, two]]).

test(assert_equal_to_result_compares_result_bags) :-
    add_form("(: c2-pl-type-order First)"),
    add_form("(: c2-pl-type-order Second)"),
    both_doors("(get-type c2-pl-type-order)", ['First', 'Second']),
    both_doors(
        "(assertEqualToResult (superpose (first second)) (second first))",
        [true]),
    both_doors_raise_assertion(
        "(assertEqualToResult (superpose (same same other)) (same other other))").

test(the_reference_interpret_entry_runs_typed_evaluation) :-
    add_form("(: c2-pl-interpreted (-> Number Number))"),
    add_form("(= (c2-pl-interpreted $x) (+ $x 1))"),
    both_doors("(interpret (c2-pl-interpreted 41) Number &self)", [42]).

test(a_bare_not_reducible_result_retains_the_call_at_the_boundary) :-
    add_form("(: c2-pl-nr (-> Atom Atom))"),
    add_form("(= (c2-pl-nr $x) NotReducible)"),
    both_doors("(c2-pl-nr q)", [['c2-pl-nr', q]]),
    %An ORDINARY expression is the observation now, not a quote. chain's
    %%Undefined% result re-enters evaluation, so a body that answered the bare
    %`NotReducible` would hand that marker straight back to the protocol and
    %the call would be retained again; a head with no equations holds it where
    %the reader can see it. The quote used to do this because it was a value.
    both_doors("(chain (eval (c2-pl-nr q)) $r (c2-pl-held $r))",
               [['c2-pl-held', 'NotReducible']]).

test(the_raw_step_exposes_the_marker_only_to_control_consumers) :-
    Term = ['c2-pl-unknown-call'],
    findall(Answer, metta_eval_step(Term, Answer), Raw),
    findall(Answer, eval(Term, Answer), Ordinary),
    assertion(Raw == ['NotReducible']),
    assertion(Ordinary == [Term]).

test(a_function_returned_marker_uses_the_same_protocol) :-
    add_form("(: c2-pl-frame-nr (-> Atom %Undefined%))"),
    add_form("(= (c2-pl-frame-nr $x) (function (return NotReducible)))"),
    add_form("(= (c2-pl-frame-body-nr) NotReducible)"),
    add_form("(= (c2-pl-frame-body-call) (function (c2-pl-frame-body-nr)))"),
    both_doors("(c2-pl-frame-nr q)", [['c2-pl-frame-nr', q]]),
    both_doors("(c2-pl-frame-body-call)", [['c2-pl-frame-body-call']]),
    dynamic_answers("(function (c2-pl-frame-body-nr))", DirectMarker),
    assertion(DirectMarker == [[function, ['c2-pl-frame-body-nr']]]),
    both_doors("(function (c2-pl-frame-no-rule))",
               [['Error', [function, ['c2-pl-frame-no-rule']], 'NoReturn']]),
    both_doors("(chain (eval (c2-pl-frame-nr q)) $r (c2-pl-held $r))",
               [['c2-pl-held', 'NotReducible']]).

test(a_tail_call_retains_the_innermost_irreducible_call) :-
    add_form("(= (c2-pl-tail Z) NotReducible)"),
    add_form("(= (c2-pl-tail (S $n)) (c2-pl-tail $n))"),
    both_doors("(c2-pl-tail (S (S Z)))", [['c2-pl-tail', 'Z']]).

test(empty_expression_is_not_the_not_reducible_marker) :-
    both_doors("(eval ())", [[eval, []]]),
    both_doors("(collapse (eval ()))", [[[eval, []]]]).

test(reduce_retains_its_call_when_the_operand_is_irreducible) :-
    both_doors("(reduce (c2-pl-reduce-unknown))",
               [[reduce, ['c2-pl-reduce-unknown']]]),
    both_doors("(reduce ())", [[reduce, []]]),
    both_doors("(reduce (+ 20 22))", [42]).

test(a_deferred_library_call_keeps_empty_as_a_losing_race_branch) :-
    dynamic_answers("(import! &self (library lib_thread))", _),
    add_form("(= (c2-pl-race-inc $x) (+ $x 1))"),
    both_doors("(par-race ((superpose ()) (c2-pl-race-inc 41)))", [42]).

:- end_tests(conformance2).
