% Purpose: pin the evaluation mask and the result rule at BOTH doors, so a
%   compiled call site and a term built at run time answer the same thing.
% Assumes: run from tests/prolog, which is what check.sh does; the relative
%   load path resolves against the working directory.
% Guarantees:
%   - a parameter declared Atom, Variable or Expression receives its argument
%     as written, and one declared Symbol, Grounded, Number or %Undefined%
%     does not, which is the arbiter's own `declaredTypeEvaluates`
%     [source: LeaTTa MettaHyperonFull/Core/Modifiers.lean:118-124]
%   - a masked builtin whose declared result is `Atom` answers as produced, and
%     one whose declared result is `%Undefined%` or `Expression` sends that
%     answer back through evaluation
%     [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:3786-3799]
%   - the compiled door and the dynamic door agree on every row, which is what
%     lets a self-interpreter dispatch a family call through `metta` and get
%     the answer a written call gets
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(metatype_mask).

% THE COMPILED DOOR: the form is an equation body, which is the path a source
% file takes. A fresh name per row keeps one row's clause out of the next.
compiled_answers(Text, Answers) :-
    sread(Text, Body),
    gensym('$metatype_mask_probe_', Name),
    translate_clause([=, [Name], Body], Clause),
    current_metta_module(Module),
    compiled_function_name(Name, Predicate),
    Goal =.. [Predicate, Answer],
    setup_call_cleanup(assertz(Module:Clause, Ref),
                       findall(Answer, Module:Goal, Answers),
                       erase(Ref)).

% THE DYNAMIC DOOR: eval/2 runs the translator on a term that exists only at
% run time, which is how `(metta ($strategy $child) %Undefined% &self)` reaches
% a family call inside the reference's own strategy basis.
dynamic_answers(Text, Answers) :-
    sread(Text, Term),
    findall(Answer, eval(Term, Answer), Answers).

both_doors(Text, Answers) :-
    compiled_answers(Text, Answers),
    dynamic_answers(Text, DynamicAnswers),
    assertion(DynamicAnswers == Answers).

% Every expected value below was measured on LeaTTa 9ea9f9d on 2026-08-24,
% through both its `--file` and its `--min` door where both accept the form.
mask_row("(cons-atom (+ 1 2) (b))",      [[['+', 1, 2], b]]).
mask_row("(cons-atom a ((+ 1 2) c))",    [[a, ['+', 1, 2], c]]).
mask_row("(decons-atom ((+ 1 2) b))",    [[['+', 1, 2], [b]]]).
mask_row("(decons-atom (cdr-atom (a b c)))",
         [['cdr-atom', [[a, b, c]]]]).
mask_row("(cdr-atom (cdr-atom (a b c)))", [[[a, b, c]]]).
mask_row("(index-atom ((+ 1 2) b) 0)",   [['+', 1, 2]]).
mask_row("(size-atom ((+ 1 2) b))",      [2]).
mask_row("(cons-atom (cons-atom a (b)) (c))",
         [[['cons-atom', a, [b]], c]]).
% car-atom's %Undefined% result is what turns the extracted operand into 3:
% the operand itself reaches the operation unreduced.
mask_row("(car-atom ((+ 1 2) b))",       [3]).
mask_row("(car-atom (((+ 1 2)) b))",     [[3]]).
% cdr-atom's Expression result re-enters evaluation for the same reason.
mask_row("(cdr-atom (a (+ 1 2)))",       [[3]]).
% chain holds its nested operand as written and its %Undefined% result
% re-enters, so the two together answer the sum.
mask_row("(chain (+ 1 2) $x (quote $x))", [[quote, ['+', 1, 2]]]).
mask_row("(chain (+ 1 2) $x $x)",         [3]).
mask_row("(chain (+ 1 2) $x (cons-atom $x (b)))", [[3, b]]).
% let evaluates its value, which is the whole difference between the two.
mask_row("(let $x (+ 1 2) (cons-atom $x (b)))", [[3, b]]).
% atom-subst holds all three operands and answers its template as produced.
mask_row("(atom-subst (+ 1 2) $x ($x $x))",
         [[['+', 1, 2], ['+', 1, 2]]]).
mask_row("(atom-subst A $x (f ($x (g $x))))",
         [[f, ['A', [g, 'A']]]]).
% A tuple's members evaluate, so the mask is a property of a DECLARED
% parameter and not of nesting.
mask_row("((+ 1 2) b)",                  [[3, b]]).

test(every_family_row_answers_what_the_arbiter_answers,
     [forall(mask_row(Text, Expected))]) :-
    both_doors(Text, Answers),
    assertion(Answers == Expected).

% A parameter type outside the mask evaluates its argument, and the register is
% what says which: union-atom's `Expression` holds, min-atom's `%Undefined%`
% does not.
test(a_masked_parameter_holds_and_an_unmasked_one_evaluates) :-
    both_doors("(union-atom ((+ 1 2)) ((+ 3 4)))",
               [[['+', 1, 2], ['+', 3, 4]]]),
    both_doors("(min-atom ((+ 1 2) 7))", [3]).

% The two doors are the same translator, so a form built at run time cannot
% drift from the same form written in a source file. Asserted directly rather
% than only through the forall above, because that is the property the
% self-interpreter acceptance depends on.
test(the_two_doors_answer_alike_on_every_row) :-
    forall(mask_row(Text, _),
           ( compiled_answers(Text, Compiled),
             dynamic_answers(Text, Dynamic),
             assertion(Compiled == Dynamic) )).

% An `Empty` answer is no answer, including inside a nested evaluation, which
% is what lets a strategy decline a child without leaving a symbol behind.
test(a_nested_evaluation_prunes_an_empty_answer) :-
    dynamic_answers("(superpose ())", []),
    dynamic_answers("(collapse (superpose ()))", [[]]).

% THE COLLECTION FORMS, both spellings. Each declares its list `Expression`
% and foldl-atom declares its seed `Atom`, so both cross as written and the
% fold runs over the parts of an unrun call. Measured on LeaTTa 9ea9f9d on
% 2026-08-24: the binder and the closure spelling answer identically, and
% `!(foldl-atom (1) (+ 1 2) $a $b (size-atom $a))` is 3, the size of the held
% `(+ 1 2)`, where an evaluated seed would refuse a Number.
collection_row("(map-atom (cdr-atom (a b)) $y (q $y))",
               [[[q, 'cdr-atom'], [q, [a, b]]]]).
collection_row("(map-atom (cdr-atom (a b)) (|-> ($y) (q $y)))",
               [[[q, 'cdr-atom'], [q, [a, b]]]]).
collection_row("(filter-atom (cdr-atom (a b)) $y (== $y b))", [[]]).
collection_row("(filter-atom (cdr-atom (a b)) (|-> ($y) (== $y b)))", [[]]).
collection_row("(foldl-atom (cdr-atom (a b)) 0 $a $b (+ 1 $a))", [2]).
collection_row("(foldl-atom (cdr-atom (a b)) 0 (|-> ($a $b) (+ 1 $a)))", [2]).
collection_row("(foldl-atom (1) (+ 1 2) $a $b (size-atom $a))", [3]).
% The list's own members are NOT reduced on the way in; the Expression result
% is what reduces them on the way out.
collection_row("(map-atom ((+ 1 2) 4) $y (q $y))", [[[q, 3], [q, 4]]]).
collection_row("(map-atom (1 2 3) $x (+ $x 1))", [[2, 3, 4]]).
collection_row("(filter-atom (1 2 3 4 5) $x (> $x 3))", [[4, 5]]).
collection_row("(foldl-atom (1 2 3 4) 0 $acc $x (+ $acc $x))", [10]).

test(a_collection_form_holds_its_list_in_either_spelling,
     [forall(collection_row(Text, Expected))]) :-
    both_doors(Text, Answers),
    assertion(Answers == Expected).

% A LAMBDA CAPTURES WHAT IS BOUND OUTSIDE IT, never what its own body binds.
% Applied to many elements the closure is ONE term, so a captured body-local
% would carry the first element's binding into the second: here the filter
% depends on the element, so the two answers differ and only a per-element
% local can produce both.
test(a_lambda_does_not_capture_a_binder_of_its_own_body) :-
    dynamic_answers(
        "(let $x (0 1) (map-atom $x (|-> ($v) (let $h (filter-atom $x (|-> ($w) (< $v $w))) (q $h)))))",
        Answers),
    assertion(Answers == [[[q, [1]], [q, []]]]).

% unquote EVALUATES its operand, `(-> %Undefined% %Undefined%)` in the
% reference's own prelude, which is what lets the quote arrive from a
% computation rather than only from source.
test(unquote_evaluates_its_operand) :-
    both_doors("(unquote (car-atom ((quote (+ 1 2)))))", [3]),
    both_doors("(unquote (cdr-atom (a b)))", [[unquote, [b]]]),
    both_doors("(unquote 42)", [[unquote, 42]]).

:- end_tests(metatype_mask).
