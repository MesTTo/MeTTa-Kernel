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

%A DECLARED RESULT IS CHECKED, so a body that produces `(3)` under a declared
%`Variable` result answers nothing: `get-type` reports (Number) for it and
%`get-metatype` reports Expression, and neither is Variable. The argument still
%re-enters evaluation -- the `Atom` parameter holds `((+ 1 2))` as written and
%the body's `$x` reduces it to `(3)` -- but the result no longer escapes its
%own declaration [measured 2026-08-30: upstream answers nothing here too,
%because src/translator.pl:382-383 emits the same result check for any output
%type that is not %Undefined%, _ or Atom]. This asserted `[[3]]` while the
%engine emitted no result check at all, on the arbiter's reading that a
%declared result decides re-evaluation rather than filtering the value.
test(a_variable_result_is_checked_like_any_other) :-
    add_form("(: c2-pl-variable-result (-> Atom Variable))"),
    add_form("(= (c2-pl-variable-result $x) $x)"),
    both_doors("(c2-pl-variable-result ((+ 1 2)))", []),
    %The same body under a result type that constrains nothing DOES answer,
    %which is what separates the result check from the argument's evaluation.
    %It answers the argument AS WRITTEN: the Atom parameter held it, the body
    %is the identity, and a result does not re-enter evaluation
    %[measured 2026-08-30: both engines answer `((+ 1 2))`;
    %fixture=ai-tmp/petta-align/anyres.metta].
    add_form("(: c2-pl-any-result (-> Atom %Undefined%))"),
    add_form("(= (c2-pl-any-result $x) $x)"),
    both_doors("(c2-pl-any-result ((+ 1 2)))", [[['+', 1, 2]]]).

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
    %cons-atom's operands EVALUATE, so the resolved head applies the same mask
    %an ordinary call does and 20 + 22 is 42 before the cons sees it
    %[measured 2026-08-30, ai-tmp/tail.metta: upstream answers `(42 tail)`].
    both_doors("(let $head cons-atom ($head (+ 20 22) (tail)))",
               [[42, tail]]).

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

%`NotReducible` IS AN ORDINARY SYMBOL. A body that answers it answers it, and
%nothing in the engine reads it: the irreducibility marker is
%`$metta_not_reducible`, which MeTTa's reader cannot produce because `$` opens
%a variable. Both rows below are byte-identical to upstream, which has no
%NotReducible of any kind
%[measured 2026-08-30: `!(c2-pl-nr q)` is `NotReducible` and the chain row is
%`(c2-pl-held NotReducible)` on both engines;
%fixture=ai-tmp/petta-align/nr.metta]. They read `(c2-pl-nr q)` and the same
%chain row while the marker and the symbol shared a name.
test(a_program_symbol_named_not_reducible_is_data) :-
    add_form("(: c2-pl-nr (-> Atom Atom))"),
    add_form("(= (c2-pl-nr $x) NotReducible)"),
    both_doors("(c2-pl-nr q)", ['NotReducible']),
    both_doors("(chain (eval (c2-pl-nr q)) $r (c2-pl-held $r))",
               [['c2-pl-held', 'NotReducible']]).

test(the_raw_step_exposes_the_marker_only_to_control_consumers) :-
    Term = ['c2-pl-unknown-call'],
    findall(Answer, metta_eval_step(Term, Answer), Raw),
    findall(Answer, eval(Term, Answer), Ordinary),
    assertion(Raw == ['$metta_not_reducible']),
    assertion(Ordinary == [Term]).

test(a_function_returned_marker_uses_the_same_protocol) :-
    add_form("(: c2-pl-frame-nr (-> Atom %Undefined%))"),
    add_form("(= (c2-pl-frame-nr $x) (function (return NotReducible)))"),
    add_form("(= (c2-pl-frame-body-nr) NotReducible)"),
    add_form("(= (c2-pl-frame-body-call) (function (c2-pl-frame-body-nr)))"),
    %Each of these returns the SYMBOL NotReducible through a function frame, so
    %each answers that symbol. Upstream answers the frame unreduced --
    %`(function (return NotReducible))` -- because it has no function/return at
    %all and leaves the form as data; reducing it is this engine's superset,
    %and what the frame carries out is the program's own symbol either way
    %[measured 2026-08-30, fixture=ai-tmp/petta-align/nr2.metta].
    both_doors("(c2-pl-frame-nr q)", ['NotReducible']),
    both_doors("(c2-pl-frame-body-call)", ['NotReducible']),
    dynamic_answers("(function (c2-pl-frame-body-nr))", DirectMarker),
    assertion(DirectMarker == ['NotReducible']),
    both_doors("(function (c2-pl-frame-no-rule))",
               [['Error', [function, ['c2-pl-frame-no-rule']], 'NoReturn']]),
    both_doors("(chain (eval (c2-pl-frame-nr q)) $r (c2-pl-held $r))",
               [['c2-pl-held', 'NotReducible']]).

%The innermost equation answers the SYMBOL and the tail hands it out, which
%is byte-identical to upstream [measured 2026-08-30: `NotReducible` on both].
%This read `(c2-pl-tail Z)`, the retained call, while the marker shared the
%symbol's name.
test(a_tail_call_hands_out_the_symbol_its_base_case_answered) :-
    add_form("(= (c2-pl-tail Z) NotReducible)"),
    add_form("(= (c2-pl-tail (S $n)) (c2-pl-tail $n))"),
    both_doors("(c2-pl-tail (S (S Z)))", ['NotReducible']).

%The empty expression is a VALUE, and an irreducible eval answers its operand,
%so `(eval ())` is `()` rather than the retained frame or the marker. Both
%rows are byte-identical to upstream, whose eval is
%`translate_expr(C, Goals, Out)` and translates `()` to itself
%[measured 2026-08-30: `()` then `(())` on both engines;
%fixture=ai-tmp/petta-align/ev2.metta]. They read `(eval ())` and `((eval ()))`
%while eval handed its own written call back on an irreducible operand.
test(empty_expression_is_not_the_not_reducible_marker) :-
    both_doors("(eval ())", [[]]),
    both_doors("(collapse (eval ()))", [[[]]]).

%reduce ANSWERS ITS OPERAND rather than retaining its own frame, which is
%upstream's `Out = [F|Args]` for a head it cannot call
%[source: PeTTa@ae66fa8 src/translator.pl:84-86; measured 2026-08-30:
%`!(reduce (nofib 5))` is `(nofib 5)` there and here]. The empty operand is
%this engine's own: upstream aborts the run on `(reduce ())`.
test(reduce_answers_an_irreducible_operand) :-
    both_doors("(reduce (c2-pl-reduce-unknown))", [['c2-pl-reduce-unknown']]),
    both_doors("(reduce ())", [[]]),
    both_doors("(reduce (+ 20 22))", [42]).

test(a_deferred_library_call_keeps_empty_as_a_losing_race_branch) :-
    dynamic_answers("(import! &self (library lib_thread))", _),
    add_form("(= (c2-pl-race-inc $x) (+ $x 1))"),
    both_doors("(par-race ((superpose ()) (c2-pl-race-inc 41)))", [42]).

:- end_tests(conformance2).
