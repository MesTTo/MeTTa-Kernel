% Purpose: direct PlUnit coverage for core runtime builtins, their error
%   contracts, and Python import state cleanup.
% Guarantees:
%   - test/3 displays host-only partial applications without claiming they are
%     serializable MeTTa text [tested:
%     a_partial_application_remains_visible_in_test_output; commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%   - every pragma! key is registered or refused, and a bound's value is
%     validated, disabled by `none`, or refused before it can replace a
%     working setting.
%     [tested: interpreter_pragmas; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(metta_assertions).

test(passing_test_returns_true_and_keeps_output) :-
    with_output_to(string(Output), test(1, 1, Result)),
    Result == true,
    Output == "is 1, should 1. ✅ \n".

test(a_partial_application_remains_visible_in_test_output) :-
    Partial = partial(+, [1]),
    with_output_to(string(Output), test(Partial, Partial, Result)),
    Result == true,
    Output == "is (partial + (1)), should (partial + (1)). ✅ \n".

test(failing_test_is_catchable,
     [throws(error(petta_test_failed(1, 2), _))]) :-
    test(1, 2, _).

test(failing_assert_is_catchable,
     [throws(error(petta_assertion_failed(fail), _))]) :-
    assert(fail, _).

test(assertion_errors_have_engine_messages) :-
    message_to_string(error(petta_test_failed(1, 2), none), Message),
    sub_string(Message, _, _, _, "MeTTa test failed: 1 does not match 2"),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(metta_assertions).

:- begin_tests(metta_metatypes).

metatype_case(partial(f, [1]), 'Grounded').
metatype_case(f(1), 'Grounded').
metatype_case([f, 1], 'Expression').
metatype_case(f, 'Symbol').

test(every_runtime_term_has_a_metatype,
     [forall(metatype_case(Term, Expected))]) :-
    'get-metatype'(Term, Actual),
    Actual == Expected.

% A NAME's metatype is the one answer that is not read off the term, and no
% registry of this engine's own decides it: `car-atom` is a Prolog predicate
% here and a standard-library equation there, `superpose` is a compiled special
% form here and a grounded token there, and the arbiter answers for the name
% rather than for whichever route an engine took. So the classification is
% upstream's, adopted whole [source: LeaTTa
% MettaHyperonFull/Minimal/Interpreter.lean, groundedTokens], and these are the
% names its corpus pins, tests/semantics/types-meta/02 and 03 and
% grounded/12-metatypes.metta, all three STATUS conforms and byte-for-byte
% transcripts of hyperon 0.2.10.
grounded_name_case('+').             % arithmetic, and a fun/1 here
grounded_name_case('/').
grounded_name_case('==').
grounded_name_case(and).
grounded_name_case('sqrt-math').
grounded_name_case('size-atom').
grounded_name_case(superpose).       % a special form here, a token there
grounded_name_case(nop).             % the same, since PeTTa's nop is variadic
grounded_name_case(match).
grounded_name_case('add-atom').
grounded_name_case('println!').
grounded_name_case('&self').         % a space handle, grounded for that reason

symbol_name_case('car-atom').        % a fun/1 here, a stdlib equation there
symbol_name_case('cdr-atom').
symbol_name_case('cons-atom').       % a fun/1 here, an instruction there
symbol_name_case('decons-atom').
symbol_name_case(empty).
symbol_name_case('get-doc').
symbol_name_case('new-state').       % the token is `_new-state`, not this
symbol_name_case('type-cast').
symbol_name_case(eval).              % a special form here, an instruction there
symbol_name_case(chain).
symbol_name_case(unify).
symbol_name_case(if).
symbol_name_case(let).
symbol_name_case(case).
symbol_name_case(quote).
symbol_name_case(collapse).
symbol_name_case('no-such-operation').

test(a_grounded_token_this_engine_holds_is_grounded,
     [forall(grounded_name_case(Name))]) :-
    'get-metatype'(Name, Metatype),
    Metatype == 'Grounded'.

test(an_instruction_or_equation_name_is_a_symbol,
     [forall(symbol_name_case(Name))]) :-
    'get-metatype'(Name, Metatype),
    Metatype == 'Symbol'.

% Membership in the table is half the answer and this engine holding the
% operation is the other half, which is the arbiter's own rule: its metaTypeOf
% asks `groundedTokenNames.contains s && w.opAdmitted s`, and it measured
% hyperon answering Symbol for `flip` before `!(import! &self random)` and
% Grounded after. A name nothing here gives meaning to gets the answer an
% unknown name gets, which is what `no-such-operation` above pins.
test(a_token_this_engine_does_not_hold_is_a_symbol,
     [forall(member(Name, ['fuzzy-match', 'near-match', 'div-euclid',
                           'skel-swap-pair-native']))]) :-
    assertion(metta_grounded_token(Name)),
    assertion(\+ metta_operation_admitted(Name)),
    'get-metatype'(Name, Metatype),
    Metatype == 'Symbol'.

% The registry decides, so a name the engine gains answers for it. Registering
% a fun/1 is how a library or a Python binding arrives, and the metatype has to
% follow the same day rather than at the next edit of the table.
test(a_token_becomes_grounded_when_the_engine_gains_it,
     [ setup(( \+ metta_operation_admitted('fuzzy-match'),
               assertz(user:fun('fuzzy-match')) )),
       cleanup(retractall(user:fun('fuzzy-match'))) ]) :-
    'get-metatype'('fuzzy-match', Metatype),
    Metatype == 'Grounded'.

:- end_tests(metta_metatypes).

:- begin_tests(metta_operation_errors).

%+, - and * have no evaluation-error case: on two numbers they are TOTAL
%now, the whole IEEE family saturating to values the way the reader's
%literals do (overflow to the infinities, the NaN class to NaN) [tested:
%engine_operations_saturate_where_raw_is_still_raises,
%a_twice_faulting_compound_saturates_all_the_way], and a non-number operand
%raises the argument GUARD's error, which is the next unit's context.
%Integer division and remainder by zero are language Error answers now. They
%stay outside the IEEE retry, then the shared operation recovery contains
%them as DivisionByZero instead of rethrowing the host fault.
host_error_case('#+', '#+'(1, invalid_number, _)).
host_error_case('#-', '#-'(1, invalid_number, _)).
host_error_case('#*', '#*'(1, invalid_number, _)).
host_error_case('#div', '#div'(1, invalid_number, _)).
host_error_case('#//', '#//'(1, invalid_number, _)).
host_error_case('#mod', '#mod'(1, invalid_number, _)).
host_error_case('#min', '#min'(1, invalid_number, _)).
host_error_case('#max', '#max'(1, invalid_number, _)).
host_error_case('#<', '#<'(1, invalid_number, _)).
host_error_case('#>', '#>'(1, invalid_number, _)).
host_error_case('#=', '#='(1, invalid_number, _)).
host_error_case('#\\=', '#\\='(1, invalid_number, _)).
%The -math family has no numeric-domain host-error row: its real-valued
%members promote integers to Float, so negative sqrt and out-of-domain trig
%answer NaN just like their explicitly floating spellings. Wrong types remain
%operation Error answers, and overflow saturates through the IEEE recovery.
host_error_case('random-int', 'random-int'(1, invalid_number, _)).
host_error_case('random-float', 'random-float'(1, invalid_number, _)).
host_error_case('random-float',
                'random-float'(1.0e308, -1.0e308, _)).
%bind! HAS NO ROW HERE since P14.8 made new-state an operation that answers a
%cell: the state form lost its own clause, so a non-symbol name is refused by
%bind!'s own typed check before any host predicate sees it. That refusal is
%covered by bind_refuses_a_name_that_is_not_a_symbol below; the rows that
%remain are the two that still reach nb_setval/2 and nb_getval/2 directly.
host_error_case('change-state!', 'change-state!'([invalid_key], 1, _)).
host_error_case('get-state', 'get-state'([invalid_key], _)).

test(test_integer_division_by_zero_answers_what_d1_decides) :-
    findall(Answer, '/'(7, 0, Answer), DivisionAnswers),
    DivisionAnswers == [['Error', ['/', 7, 0], 'DivisionByZero']],
    findall(Answer, '%'(7, 0, Answer), RemainderAnswers),
    RemainderAnswers == [['Error', ['%', 7, 0], 'DivisionByZero']],
    process_metta_string("!(/ 7 0)", Direct),
    Direct == [['Error', ['/', 7, 0], 'DivisionByZero']],
    process_metta_string("!(collapse (/ 7 0))", Collapsed),
    Collapsed == [[['Error', ['/', 7, 0], 'DivisionByZero']]].

real_unary_pair('sqrt-math', 4, 2.0).
real_unary_pair('sin-math', 0, 0.0).
real_unary_pair('cos-math', 0, 1.0).
real_unary_pair('tan-math', 0, 0.0).
real_unary_pair('asin-math', 0, 0.0).
real_unary_pair('acos-math', 1, 0.0).
real_unary_pair('atan-math', 0, 0.0).

test(test_real_valued_math_treats_integer_and_float_operands_alike) :-
    forall(real_unary_pair(Operation, Integer, Expected),
           ( GoalInteger =.. [Operation, Integer, IntegerAnswer],
             Float is float(Integer),
             GoalFloat =.. [Operation, Float, FloatAnswer],
             call(GoalInteger), call(GoalFloat),
             float(IntegerAnswer), float(FloatAnswer),
             IntegerAnswer =:= Expected, FloatAnswer =:= Expected )),
    'log-math'(10, 100, IntegerLog),
    'log-math'(10.0, 100.0, FloatLog),
    IntegerLog =:= 2.0, FloatLog =:= 2.0,
    'sqrt-math'(-1, SqrtIntNan), 'isnan-math'(SqrtIntNan, true),
    'sqrt-math'(-1.0, SqrtFloatNan), 'isnan-math'(SqrtFloatNan, true),
    'log-math'(10, -5, LogIntNan), 'isnan-math'(LogIntNan, true),
    'log-math'(10.0, -5.0, LogFloatNan),
    'isnan-math'(LogFloatNan, true),
    'asin-math'(2, AsinIntNan), 'isnan-math'(AsinIntNan, true),
    'asin-math'(2.0, AsinFloatNan), 'isnan-math'(AsinFloatNan, true),
    'acos-math'(2, AcosIntNan), 'isnan-math'(AcosIntNan, true),
    'acos-math'(2.0, AcosFloatNan), 'isnan-math'(AcosFloatNan, true),
    'pow-math'(2, 3, Power), Power == 8.0,
    'pow-math'(1, -2147483648, LowerBound), LowerBound == 1.0,
    'pow-math'(1, 2147483647, UpperBound), UpperBound == 1.0,
    'pow-math'(0, -1, InfinitePower),
    'isinf-math'(InfinitePower, true),
    'pow-math'(1, 2147483648.0, UnboundedFloatPower),
    UnboundedFloatPower == 1.0,
    'pow-math'(2, 2147483648, TooBig),
    TooBig == ['Error', ['pow-math', 2, 2147483648],
               "power argument is too big, try using float value"],
    'pow-math'(2, -2147483649, TooSmall),
    TooSmall == ['Error', ['pow-math', 2, -2147483649],
                 "power argument is too big, try using float value"],
    %exp-math is PeTTa doctrine, not part of LeaTTa's floatUn table.
    'exp-math'(1, IntegerExp), 'exp-math'(1.0, FloatExp),
    IntegerExp =:= FloatExp.

%The guarded operators refuse a non-number argument themselves rather than
%letting is/2 coerce it, and the refusal is an ANSWER: `invalid_number` is an
%undeclared symbol, so its type decides nothing and the call is left as
%written, which is upstream's NoReduce. Only `/` names itself instead
%[source: LeaTTa tests/semantics/grounded/07-partial-core.metta].
number_operand_case('+', '+'(1, invalid_number, R), R).
number_operand_case('-', '-'(1, invalid_number, R), R).
number_operand_case('*', '*'(1, invalid_number, R), R).
number_operand_case('%', '%'(1, invalid_number, R), R).
number_operand_case('<', '<'(1, invalid_number, R), R).
number_operand_case('>', '>'(1, invalid_number, R), R).
number_operand_case('<=', '<='(1, invalid_number, R), R).
number_operand_case('>=', '>='(1, invalid_number, R), R).
number_operand_case(min, min(1, invalid_number, R), R).
number_operand_case(max, max(1, invalid_number, R), R).

test(arithmetic_answers_a_non_number_argument_rather_than_raising,
     [forall(number_operand_case(Operation, Goal, Result))]) :-
    findall(Result, call(Goal), Answers),
    Answers == [[Operation, 1, invalid_number]].

test(divide_refuses_by_name_where_the_others_leave_the_call) :-
    findall(R, '/'(1, invalid_number, R), Answers),
    Answers == [['Error', ['/', 1, invalid_number],
                 "Divide expects two numbers: dividend and divisor"]].

%The same operations handed an argument that is not a number at all. Each
%answers in upstream's own words, and upstream's noun is not uniform: sqrt-math
%and abs-math say `number` where every later unary operation says `input
%number`, and pow-math and log-math name both of theirs
%[source: LeaTTa tests/semantics/grounded/08-partial-math.metta].
math_refusal_case('sqrt-math'(invalid_number, R), R,
                  "sqrt-math expects one argument: number").
math_refusal_case('abs-math'(invalid_number, R), R,
                  "abs-math expects one argument: number").
math_refusal_case('sin-math'(invalid_number, R), R,
                  "sin-math expects one argument: input number").
math_refusal_case('isinf-math'(invalid_number, R), R,
                  "isinf-math expects one argument: input number").
math_refusal_case(exp(invalid_number, R), R,
                  "exp expects one argument: input number").
math_refusal_case('pow-math'(1, invalid_number, R), R,
                  "pow-math expects two arguments: number (base) and number (power)").
math_refusal_case('log-math'(1, invalid_number, R), R,
                  "log-math expects two arguments: base (number) and input value (number)").

test(a_math_operation_answers_its_own_refusal_by_name,
     [forall(math_refusal_case(Goal, Result, Message))]) :-
    findall(Result, call(Goal), Answers),
    Answers = [['Error', _, Reason]],
    Reason == Message.

%Drive every position from the engine's math-operation registry. SWI accepts a
%one-character string as an arithmetic character code, so this must exercise
%the direct operation door rather than relying on translated-call filtering.
test(test_a_string_operand_to_math_refuses_instead_of_answering_its_char_code) :-
    forall(( metta_math_operation(Operation, Arity),
             between(1, Arity, Position) ),
           ( length(Arguments, Arity),
             PrefixLength is Position - 1,
             length(Prefix, PrefixLength),
             append(Prefix, ["s"|Suffix], Arguments),
             maplist(=(2), Prefix),
             maplist(=(2), Suffix),
             append(Arguments, [Answer], CallArguments),
             Goal =.. [Operation|CallArguments],
             once(call(Goal)),
             Answer = ['Error', [Operation|Arguments],
                       ['BadArgType', Position, 'Number', 'String']] )).

%min-atom and max-atom carry three texts for three arguments, and the third
%quotes the offending expression back the way upstream formats it.
expression_refusal_case('min-atom'(5, R), R, "Atom is not an ExpressionAtom").
expression_refusal_case('max-atom'(5, R), R, "Atom is not an ExpressionAtom").
expression_refusal_case('min-atom'([], R), R, "Empty expression").
expression_refusal_case('min-atom'([1, u, 3], R), R,
                        "Only numbers are allowed in expression: (1 u 3)").
expression_refusal_case('max-atom'([1, u, 3], R), R,
                        "Only numbers are allowed in expression: (1 u 3)").

test(the_numeric_expression_operations_answer_their_own_refusal,
     [forall(expression_refusal_case(Goal, Result, Message))]) :-
    findall(Result, call(Goal), Answers),
    Answers = [['Error', _, Reason]],
    Reason == Message.

%A cell NAME is a symbol, and bind! says so itself rather than letting a host
%predicate say it about a key: the message names the operation and what a name
%has to be [tested by this clause; the row it replaced is above].
test(bind_refuses_a_name_that_is_not_a_symbol) :-
    catch('bind!'([invalid_key], ['new-state', 1], _), Error, true),
    nonvar(Error),
    Error = error(type_error(symbol, [invalid_key]), context('bind!'/2, _)).

test(host_errors_name_the_written_operation,
     [forall(host_error_case(Operation, Goal))]) :-
    catch(call(Goal), Error, true),
    nonvar(Error),
    Error = error(Formal,
                  context(Operation, 'while evaluating MeTTa operation')),
    nonvar(Formal).

%A Number where a Bool was declared is decided, so it is a BadArgType ANSWER
%naming the position, not a raise [source: the same file, `(and True n)` is
%`(BadArgType 2 Bool Number)`].
boolean_error_case(and, and(true, 5, R), R, 2).
boolean_error_case(or, or(false, 5, R), R, 2).
boolean_error_case(not, not(5, R), R, 1).
boolean_error_case(xor, xor(true, 5, R), R, 2).
boolean_error_case(implies, implies(false, 5, R), R, 2).

test(boolean_type_errors_answer_the_position_they_refuse,
     [forall(boolean_error_case(_Operation, Goal, Result, Position))]) :-
    findall(Result, call(Goal), Answers),
    Answers = [['Error', _, Reason]],
    Reason == ['BadArgType', Position, 'Bool', 'Number'].

test(boolean_operations_remain_relational) :-
    findall(A-B-C, and(A, B, C), Rows),
    Rows == [true-true-true, true-false-false,
             false-true-false, false-false-false].

test(non_list_reduce_throws_its_own_type_error,
     [throws(error(type_error(list, invalid_reduce),
                   context(reduce, 'invalid MeTTa operation argument')))]) :-
    reduce(invalid_reduce, _).

test(variable_reduce_keeps_its_existing_empty_answer) :-
    findall(Input-Out, reduce(Input, Out), Answers),
    Answers == [[]-[]].

test(control_exceptions_are_not_recontextualized) :-
    Original = error(resource_error(stack), original_context),
    catch(rethrow_metta_operation_error('+', Original), Error, true),
    Error == Original.

% SWI's own errors carry context(PI, _) with the second argument UNBOUND, so a
% message clause that matched context(Operation, 'invalid MeTTa operation
% argument') in its head BOUND that variable and then rendered every ordinary
% type error in PeTTa's operation vocabulary. `X is foo+1` was reported as
% "system:(is)/2: evaluable expected, found (/ foo 0)", naming an engine
% internal and a culprit the program never wrote, which is exactly what an
% extension author saw when their own predicate's is/2 refused a value.
test(an_unrelated_type_error_keeps_swi_s_own_message) :-
    catch(_ is foo + 1, Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "is not a function")),
    assertion(\+ sub_string(Text, _, _, _, "expected, found")).

test(an_unknown_procedure_keeps_swi_s_own_message) :-
    catch(plunit_no_such_predicate(1, 2), Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "Unknown procedure")).

test(a_metta_operation_error_still_names_the_operation) :-
    catch('#+'(foo, 1, _), Error, true),
    message_to_string(Error, Text),
    assertion(sub_string(Text, _, _, _, "#+: ")).

:- end_tests(metta_operation_errors).

:- dynamic plunit_break_type_bridge/0.
:- multifile seam:grounded_type_names/2.
seam:grounded_type_names(_, _) :- plunit_break_type_bridge, throw(plunit_broken_bridge).

% evalc's space argument selects the module the goals resolve in and nothing
% else. PeTTa's eval is a full evaluation of compiled goals rather than
% minimal MeTTa's single rewriting step, and evalc keeps that, so the two
% agree everywhere except which space's equations answer.
:- begin_tests(metta_evalc,
               [ setup(setup_evalc), cleanup(cleanup_evalc) ]).

setup_evalc :-
    retractall(user:silent(_)),
    assertz(user:silent(true)),
    process_metta_string("(= (plunit-evalc-pick) here)", _),
    'add-atom'('&plunit_evalc_kb', [=, ['plunit-evalc-pick'], there], _),
    process_metta_string("(= (plunit-evalc-echo $x) $x)", _),
    sread("(= (plunit-evalc-echo $x) $x)", KbEcho),
    'add-atom'('&plunit_evalc_kb', KbEcho, _).

cleanup_evalc :-
    'remove-atom'('&plunit_evalc_kb', [=, ['plunit-evalc-pick'], there], _),
    'remove-atom'('&self', [=, ['plunit-evalc-pick'], here], _),
    sread("(= (plunit-evalc-echo $x) $x)", KbEcho),
    'remove-atom'('&plunit_evalc_kb', KbEcho, _),
    sread("(= (plunit-evalc-echo $x) $x)", SelfEcho),
    'remove-atom'('&self', SelfEcho, _),
    clear_native_atoms('&plunit_evalc_kb').

test(evalc_answers_from_the_space_it_is_given) :-
    evalc(['plunit-evalc-pick'], '&self', InSelf),
    assertion(InSelf == here),
    evalc(['plunit-evalc-pick'], '&plunit_evalc_kb', InKb),
    assertion(InKb == there).

test(evalc_agrees_with_eval_in_the_default_space) :-
    eval(['plunit-evalc-pick'], ViaEval),
    evalc(['plunit-evalc-pick'], '&self', ViaEvalc),
    assertion(ViaEval == ViaEvalc).

% A space is an atom beginning with &, so an argument that is not one is a
% type error rather than a silently empty space.
test(evalc_refuses_an_argument_that_is_not_a_space,
     [throws(error(type_error(_, not_a_space), _))]) :-
    evalc(['plunit-evalc-pick'], not_a_space, _).

% &self is a reader token: it resolves where source text is parsed, and
% nowhere later, so a term built at run time keeps the literal atom
% through both eval doors. evalc especially must not substitute, because
% a reader-pinned token is lexical (the space hosting the source), and
% re-aiming it at evalc's dynamic target would change what pinned code
% means. The runtime walks that once substituted here also cost
% alpha-unique's counter twelve percent [measured 2026-08-17].
test(evalc_keeps_a_runtime_literal_self_as_written) :-
    sread("(plunit-evalc-echo &self)", T),
    evalc(T, '&plunit_evalc_kb', Out),
    assertion(Out == '&self').

test(eval_keeps_a_runtime_literal_self_as_written) :-
    sread("(plunit-evalc-echo &self)", T),
    eval(T, Out),
    assertion(Out == '&self').

:- end_tests(metta_evalc).

:- begin_tests(metta_object_types).

% A bridge whose seam:grounded_type_names/2 clause THROWS used to be read as "no
% bridge answered", and the class walk ran instead. One broken protocol
% predicate therefore destroyed typing for every host object in the process,
% and get-type answered Box, the envelope's own class, for all of them, with
% no error at any point. bindings/python/petta/_ops.py states the rule for the same
% probe on its own side: a broken probe is the registrant's bug.
% The clause is static and flag-guarded, because seam:grounded_type_names/2 is
% multifile without being dynamic: a bridge contributes its clause at load
% time and cannot be installed later.
test(a_throwing_type_bridge_is_the_registrants_bug,
     [ setup(assertz(user:plunit_break_type_bridge)),
       cleanup(retractall(user:plunit_break_type_bridge)),
       throws(plunit_broken_bridge) ]) :-
    metta_grounded_type(plunit_not_really_an_object, _).

% A bridge that is ABSENT is an ordinary configuration, not a failure: a
% program reaching Python through py-call alone still gets its objects typed
% by the class walk.
test(an_absent_type_bridge_falls_back_to_the_class_walk) :-
    py_call(datetime:datetime(2020, 1, 1), Object),
    findall(T, metta_grounded_type(Object, T), Types),
    assertion(memberchk(datetime, Types)),
    assertion(\+ memberchk(object, Types)).

:- end_tests(metta_object_types).

:- begin_tests(metta_type_answers,
               [ setup(setup_type_answers),
                 cleanup(cleanup_type_answers) ]).

type_answer_fact(plunit_type_a, plunit_a).
type_answer_fact(plunit_type_b, plunit_b).
type_answer_fact([plunit_type_a, plunit_type_b],
                 [plunit_a, plunit_b]).
type_answer_fact(plunit_pair_one, ['Pair', plunit_ta]).
type_answer_fact(plunit_pair_one, ['Pair', plunit_tb]).

setup_type_answers :-
    cleanup_type_answers,
    forall(type_answer_fact(Term, Type),
           add_sexp('&self', [':', Term, Type])),
    metta_self_module(Self),
    assertz(Self:get_type_rule([plunit_type_a, plunit_type_b],
                               [plunit_a, plunit_b])).

cleanup_type_answers :-
    forall(type_answer_fact(Term, _),
           remove_sexp('&self', [':', Term, _])),
    metta_self_module(Self),
    retractall(Self:get_type_rule([plunit_type_a, plunit_type_b], _)).

test(user_boundary_returns_each_type_once) :-
    findall(Type,
            'get-type'([plunit_type_a, plunit_type_b], Type),
            Types),
    Types == [[plunit_a, plunit_b]].

test(alpha_equivalent_polymorphic_types_are_one_answer,
     [ setup((metta_self_module(S),
                assertz(S:get_type_rule(plunit_poly_type,
                                        ['->', A, A])),
                assertz(S:get_type_rule(plunit_poly_type,
                                        ['->', B, B])))),
       cleanup((metta_self_module(S2),
                retractall(S2:get_type_rule(plunit_poly_type, _))))
     ]) :-
    findall(Type, user:'get-type'(plunit_poly_type, Type), Types),
    Types =@= [['->', T, T]].

test(fixed_internal_check_uses_one_witness) :-
    findall(true,
            has_type([plunit_type_a, plunit_type_b],
                     [plunit_a, plunit_b]),
            Witnesses),
    Witnesses == [true].

test(a_parametric_expected_type_enumerates_its_witnesses) :-
    % (Pair $t) is nonvar but not ground, so a first-witness commit here
    % binds $t from whichever declaration came first and never reaches the
    % assignment a second argument needs.
    findall(T,
            has_type(plunit_pair_one, ['Pair', T]),
            Types),
    msort(Types, Sorted),
    Sorted == [plunit_ta, plunit_tb].

test(a_ground_expected_type_still_stops_at_one_witness) :-
    findall(true,
            has_type(plunit_pair_one, ['Pair', plunit_ta]),
            Witnesses),
    Witnesses == [true].

%A tuple type is %Undefined% as soon as one member's type is, so the shape is
%never reported with a hole sitting inside it. Written against the engine's
%own answer rather than through janus, because the collapse is a rule of the
%type derivation and not of the boundary.
test(a_tuple_with_an_untyped_member_is_undefined) :-
    findall(T, 'get-type'([plunit_type_a, plunit_type_b], T), Typed),
    assertion(Typed == [[plunit_a, plunit_b]]),
    findall(T, 'get-type'([plunit_type_a, plunit_never_declared], T), Holed),
    assertion(Holed == ['%Undefined%']),
    findall(T, 'get-type'([plunit_never_declared], T), Alone),
    assertion(Alone == ['%Undefined%']).

%Bottom-up, so an inner tuple carrying a hole makes the outer one undefined
%without the rule saying anything about nesting.
test(the_collapse_reaches_a_nested_tuple) :-
    findall(T, 'get-type'([plunit_type_a, [plunit_type_a, plunit_type_b]], T),
            Nested),
    assertion(Nested == [[plunit_a, [plunit_a, plunit_b]]]),
    findall(T,
            'get-type'([plunit_type_a, [plunit_type_a, plunit_never_declared]], T),
            Holed),
    assertion(Holed == ['%Undefined%']).

%The tuple rule reads one set of types per member and then combines them.
%Combining by BACKTRACKING re-derives every member to the RIGHT of each retry,
%so k members carrying c types each cost Theta(c^k) even when one untyped
%member makes %Undefined% the only answer there is. Doubling the width must
%therefore roughly double the cost rather than raise it by a power: at the
%three types below the old shape charged 3^6 = 729x between these two widths,
%where deriving each member's set once charges 2x. The bound is on the RATIO,
%not on an inference count, so it keeps testing the complexity class as
%ordinary constants move [measured 2026-08-22: 581,130,797 inferences to
%1,589 at width 15].
test(a_wide_expression_types_in_time_linear_in_its_width,
     [ setup(setup_wide_members), cleanup(cleanup_wide_members) ]) :-
    wide_typing_cost(6, Narrow),
    wide_typing_cost(12, Wide),
    assertion(Wide < Narrow * 4).

wide_member_count(12).

wide_member(Index, Member) :- atom_concat(plunit_wide_s, Index, Member).

wide_member_type(Index, Type) :- atom_concat(plunit_wide_t, Index, Type).

setup_wide_members :-
    cleanup_wide_members,
    forall(wide_declaration(Member, Type),
           add_sexp('&self', [':', Member, Type])).

cleanup_wide_members :-
    forall(wide_declaration(Member, _),
           remove_sexp('&self', [':', Member, _])).

wide_declaration(Member, Type) :-
    wide_member_count(Count),
    between(1, Count, Index),
    wide_member(Index, Member),
    between(1, 3, Which),
    wide_member_type(Which, Type).

%The same expression, asked the other question. Deciding `X : T` by
%SYNTHESISING X's types and comparing each to T walks the product until it
%reaches T, so the cost depends on where T sits in that enumeration rather than
%on the question: checking the last combination cost 29,496,420 inferences at
%thirteen members where the first cost 312. The bound is on the ratio between
%two widths, so it keeps testing the complexity class as constants move.
test(a_wide_expression_checks_against_its_last_tuple_type_in_linear_time,
     [ setup(setup_wide_members), cleanup(cleanup_wide_members) ]) :-
    wide_check_cost(6, Narrow),
    wide_check_cost(12, Wide),
    assertion(Wide < Narrow * 4).

%And a member that is itself an expression decomposes the same way. Enumerating
%a nested member's types to find the one wanted is the product again, one level
%down, so checking this displaced the exponential rather than removing it: 614
%inferences at two inner members rising 9x per added one to 43,097,295 at eight.
test(a_nested_expression_checks_against_its_last_tuple_type_in_linear_time,
     [ setup(setup_wide_members), cleanup(cleanup_wide_members) ]) :-
    nested_check_cost(6, Narrow),
    nested_check_cost(12, Wide),
    assertion(Wide < Narrow * 4).

nested_check_cost(Width, Cost) :-
    numlist(1, Width, Indices),
    maplist(wide_member, Indices, Inner),
    wide_member_type(3, Last),
    length(InnerExpected, Width),
    maplist(=(Last), InnerExpected),
    wide_member(1, Outer),
    statistics(inferences, Before),
    (   has_type([Inner, Outer], [InnerExpected, Last])
    ->  Held = true
    ;   Held = false
    ),
    statistics(inferences, After),
    Cost is After - Before,
    assertion(Held == true).

wide_check_cost(Width, Cost) :-
    numlist(1, Width, Indices),
    maplist(wide_member, Indices, Expression),
    wide_member_type(3, Last),
    length(Expected, Width),
    maplist(=(Last), Expected),
    statistics(inferences, Before),
    (   has_type(Expression, Expected)
    ->  Held = true
    ;   Held = false
    ),
    statistics(inferences, After),
    Cost is After - Before,
    assertion(Held == true).

wide_typing_cost(Width, Cost) :-
    numlist(1, Width, Indices),
    maplist(wide_member, Indices, Members),
    append(Members, [plunit_wide_never_declared], Expression),
    statistics(inferences, Before),
    findall(Type, 'get-type'(Expression, Type), Types),
    statistics(inferences, After),
    Cost is After - Before,
    assertion(Types == ['%Undefined%']).

:- end_tests(metta_type_answers).

% A form may span lines, and asking sread_command/2 the whole buffered text
% again for every one of them is Theta(L^2) in the form's length: 1,600 lines
% spent 132,673,790,292 instructions where the same text on ONE line spent
% 1,484,324,191. read_form_step/4 carries the scanner state instead, so each
% line is read once. The differential is what makes that trustworthy: line by
% line must reach the same verdict on every PREFIX as the whole text does.
:- begin_tests(metta_form_reader).

form_reader_case(["(f a)"]).
form_reader_case(["(f", "a)"]).
form_reader_case(["(a (b (c", "))", ")"]).
form_reader_case(["; comment", "(f a)"]).
form_reader_case(["(f \"str", "ing\" a)"]).
form_reader_case(["", "   ", "(f a)"]).
form_reader_case(["(f a) ; trailing"]).
form_reader_case(["(= (f $x)", "  (g $x))"]).
form_reader_case(["(f a))"]).
form_reader_case(["(f \"a", "b\\", "c\")"]).
form_reader_case(["(f ; )", ")"]).

test(the_line_scan_agrees_with_the_whole_text_scan) :-
    forall(form_reader_case(Lines), line_scan_agrees(Lines)).

line_scan_agrees(Lines) :-
    line_scan_agrees(Lines, [], read_form_state(0, outside, false)).

line_scan_agrees([], _, _).
line_scan_agrees([Line|Rest], Seen, State0) :-
    append(Seen, [Line], Prefix),
    atomic_list_concat(Prefix, '\n', Joined),
    atom_string(Joined, Text),
    whole_text_verdict(Text, Expected),
    read_form_step(Line, State0, State, Answer),
    assertion(Answer == Expected),
    (   Answer == incomplete
    ->  line_scan_agrees(Rest, Prefix, State)
    ;   true
    ).

%sread_command/2 asks one question the line scan carries as a flag, whether the
%text has any CONTENT, and answers incomplete for a blank or comment-only one.
%A malformed text RAISES there and is the atom malformed here.
whole_text_verdict(Text, Verdict) :-
    (   catch(sread_command(Text, Read), _, fail)
    ->  ( Read == incomplete -> Verdict = incomplete ; Verdict = complete )
    ;   Verdict = malformed
    ).

:- end_tests(metta_form_reader).

:- begin_tests(metta_builtin_scoping).

test(a_named_space_defining_a_builtin_name_keeps_it_working_elsewhere,
     [ cleanup(( retractall(fun_in('&plunit_shadow', '+')),
                 retractall(fun_scoped('+')) )) ]) :-
    % One named space defining + once turned + into inert data in every
    % other space, and in engines built afterwards.
    assertz(fun_in('&plunit_shadow', '+')),
    assertz(fun_scoped('+')),
    metta_self_module(Self),
    with_metta_module(Self, fun_here('+')).

test(a_scoped_user_function_stays_scoped,
     [ cleanup(( retractall(fun(plunit_scoped_fn)),
                 retractall(fun_in('&plunit_shadow', plunit_scoped_fn)),
                 retractall(fun_scoped(plunit_scoped_fn)) )) ]) :-
    % The builtin fallback must not make every scoped name global.
    assertz(fun(plunit_scoped_fn)),
    assertz(fun_in('&plunit_shadow', plunit_scoped_fn)),
    assertz(fun_scoped(plunit_scoped_fn)),
    metta_self_module(Self),
    \+ with_metta_module(Self, fun_here(plunit_scoped_fn)).

:- end_tests(metta_builtin_scoping).

:- begin_tests(metta_arithmetic_operands).

%What these three reproductions pin is that the operand is not COERCED, and
%that is unchanged; how the refusal is DELIVERED did change, from a raise to
%an answer, so the expectations are written out rather than hidden behind a
%catch [source: LeaTTa tests/semantics/grounded/07-partial-core.metta].
test(a_one_element_expression_is_not_a_character_code) :-
    % (+ 1 (g)) answered 104, the character code of g.
    findall(R, '+'(1, [g], R), Plus),
    findall(R, '*'(2, [z], R), Times),
    Plus == [['+', 1, [g]]],
    Times == [['*', 2, [z]]].

test(a_string_is_not_a_character_code) :-
    findall(R, '+'(1, "s", R), Answers),
    Answers == [['Error', ['+', 1, "s"],
                 ['BadArgType', 2, 'Number', 'String']]].

test(an_evaluable_atom_does_not_outrank_a_metta_definition) :-
    % SWI's pi answered 3.14159 over a user's own (= pi 3.14).
    findall(R, '+'(1, pi, R), Answers),
    Answers == [['+', 1, pi]].

test(comparisons_refuse_the_same_operands) :-
    findall(R, '<'(1, [f, 2], R), Less),
    findall(R, max([a], 1, R), Max),
    Less == [['<', 1, [f, 2]]],
    Max == [[max, [a], 1]].

test(numbers_still_compute) :-
    '+'(1, 2, Three), Three == 3,
    '+'(1.5, 2.5, Four), Four == 4.0,
    max(3, 7, Seven), Seven == 7,
    '<'(1.5, 2, True), True == true.

:- end_tests(metta_arithmetic_operands).

:- begin_tests(metta_index_atom).

test(out_of_range_index_returns_the_empty_expression) :-
    'index-atom'([a, b], 5, Out),
    Out == [].

test(noninteger_index_returns_the_empty_expression) :-
    'index-atom'([a, b], bad, Out),
    Out == [].

test(prebound_wrong_output_is_rejected, [fail]) :-
    'index-atom'([a, b], 0, wrong).

test(variable_index_still_enumerates,
     [true(Pairs == [0-a, 1-b])]) :-
    findall(Index-Elem, 'index-atom'([a, b], Index, Elem), Pairs).

%Reading the first element is an O(1) question and it used to be answered by a
%walk of the whole list, because indexable_list/2 classified its argument with
%is_list/1. TIMED rather than counted: is_list/1 is one C builtin call and
%reads as a single inference whatever the length of the list it walks.
index_cost(N, Micros) :-
    numlist(1, N, List),
    ( between(1, 50, _), \+ \+ 'index-atom'(List, 0, _), fail ; true ),
    findall(D, ( between(1, 3, _),
                 statistics(cputime, T0),
                 ( between(1, 2000, _), \+ \+ 'index-atom'(List, 0, _), fail
                 ; true ),
                 statistics(cputime, T1),
                 D is (T1 - T0) * 1000000 / 2000 ), Ds),
    min_list(Ds, Micros).

test(reading_the_first_element_does_not_walk_the_list) :-
    index_cost(400, Narrow),
    index_cost(25600, Wide),
    assertion(Wide < Narrow * 4).

:- end_tests(metta_index_atom).

:- begin_tests(metta_expression_invariant).

%A MeTTa Expression is a proper list, and every reader in the engine is entitled
%to assume it because the two constructors maintain it.
shape_case([],         true).
shape_case([a],        true).
shape_case([a, b, c],  true).
shape_case([[a], [b]], true).
shape_case(foo,        false).
shape_case(1,          false).
shape_case("s",        false).
shape_case(3.5,        false).
shape_case(f(a, b),    false).
shape_case(-(1, 2),    false).

test(the_shape_decides_what_is_an_expression) :-
    forall(shape_case(Term, Expected),
           ( ( list_shaped(Term) -> Got = true ; Got = false ),
             assertion(Got == Expected) )).

%An unbound term is not an Expression, which is what is_list/1 answered for one
%and what each caller of list_shaped/1 relies on.
test(an_unbound_term_is_not_an_expression, [fail]) :-
    list_shaped(_).

%The tail's declared type is Expression, and a tail that is decidedly not one is
%refused rather than built into a cons the engine cannot print: (cons-atom a 1)
%used to answer [a|1], which swrite/2 then refused as a term whose printed form
%would read back as a different value.
test(a_non_expression_tail_is_refused) :-
    'cons-atom'(a, 1, Out),
    Out == ['Error', ['cons-atom', a, 1],
            ['BadArgType', 2, 'Expression', 'Number']],
    cons(a, "s", Out2),
    Out2 == ['Error', [cons, a, "s"],
             ['BadArgType', 2, 'Expression', 'String']].

%A tail whose type is not DECIDED, an undeclared symbol, is left unreduced. The
%result is the ordinary three-element expression, so the invariant holds there
%too.
test(an_undecided_tail_is_left_unreduced_as_an_expression) :-
    'cons-atom'(a, foo, Out),
    Out == ['cons-atom', a, foo],
    assertion(list_shaped(Out)).

%An unbound tail still builds, which is what relational_input_position/2
%declares for position 2 and what lets lib_roman write (cons $x $xs) as a
%pattern and the third argument decompose a list.
test(an_unbound_tail_still_builds_and_still_decomposes) :-
    'cons-atom'(a, T, Out),
    Out == [a|T],
    var(T),
    cons(H, Rest, [a, b, c]),
    H == a, Rest == [b, c].

:- end_tests(metta_expression_invariant).

:- begin_tests(metta_alpha_membership).

test(success_does_not_retain_unification_bindings) :-
    'is-alpha-member'([1, X], [[1, 2], [3, 4]], Bool),
    Bool == true,
    var(X).

test(translated_success_leaves_the_query_variable_unbound) :-
    setup_call_cleanup(
        assertz(silent(true), Ref),
        process_metta_string(
            "!(let $b (is-alpha-member (1 $x) ((1 2) (3 4))) $x)",
            [Result]),
        erase(Ref)),
    var(Result).

:- end_tests(metta_alpha_membership).

:- begin_tests(metta_alpha_unique).

test(synthetic_hash_collision_keeps_inequivalent_terms) :-
    empty_assoc(Empty),
    alpha_bucket_insert(forced_hash, alpha, Empty, SeenAlpha, true),
    alpha_bucket_insert(forced_hash, beta, SeenAlpha, SeenBoth, true),
    get_assoc(forced_hash, SeenBoth, Bucket),
    Bucket == [beta, alpha].

test(identity_inside_a_hash_bucket_rejects_a_duplicate) :-
    empty_assoc(Empty),
    alpha_bucket_insert(forced_hash, alpha, Empty, Seen, true),
    alpha_bucket_insert(forced_hash, alpha, Seen, SeenAgain, false),
    SeenAgain == Seen.

test(surface_deduplication_keeps_first_alpha_variant) :-
    'alpha-unique-atom'([[link, X, human],
                        [link, Y, human],
                        [child, Z, human]],
                        Unique),
    Unique == [[link, X, human], [child, Z, human]],
    X \== Y.

:- end_tests(metta_alpha_unique).

:- begin_tests(metta_builtin_outputs).

wrong_prebound_output('car-atom'([a, b], [])).
wrong_prebound_output('cdr-atom'([a, b], [])).
wrong_prebound_output('is-alpha-member'(a, [a, b], false)).
wrong_prebound_output('#<'(1, 2, false)).
wrong_prebound_output('#>'(2, 1, false)).
wrong_prebound_output('#='(1, 1, false)).
wrong_prebound_output('#\\='(1, 2, false)).
wrong_prebound_output(repr(true, true)).

produced_outputs(car, Out) :- 'car-atom'([a, b], Out).
produced_outputs(cdr, Out) :- 'cdr-atom'([a, b], Out).
produced_outputs(alpha_member, Out) :- 'is-alpha-member'(a, [a, b], Out).
produced_outputs(clp_less, Out) :- '#<'(1, 2, Out).
produced_outputs(clp_greater, Out) :- '#>'(2, 1, Out).
produced_outputs(clp_equal, Out) :- '#='(1, 1, Out).
produced_outputs(clp_different, Out) :- '#\\='(1, 2, Out).
produced_outputs(representation, Out) :- repr(true, Out).

expected_outputs(car, [a]).
expected_outputs(cdr, [[b]]).
expected_outputs(alpha_member, [true]).
expected_outputs(clp_less, [true]).
expected_outputs(clp_greater, [true]).
expected_outputs(clp_equal, [true]).
expected_outputs(clp_different, [true]).
%`True`, not `true`: repr/2 is swrite/2, which writes the language's own
%spelling of the boolean the reader mapped onto Prolog's
%[tested: parser_roundtrip:booleans_print_in_the_languages_own_spelling].
expected_outputs(representation, ["True"]).

test(prebound_outputs_must_be_producible,
     [forall(wrong_prebound_output(Goal)), fail]) :-
    call(Goal).

test(unbound_outputs_remain_exact_and_deterministic,
     [forall(expected_outputs(Label, Expected))]) :-
    findall(Out, produced_outputs(Label, Out), Actual),
    Actual == Expected.

test(translated_let_rejects_an_impossible_comparison_output) :-
    setup_call_cleanup(assertz(silent(true), Ref),
                       process_metta_string("!(let false (#< 1 2) WRONG)",
                                            Results),
                       erase(Ref)),
    Results == [].

:- end_tests(metta_builtin_outputs).

:- begin_tests(metta_translator_rules,
               [ setup((retractall(user:translator_rule(_, _)),
                        assertz(user:translator_rule(first, [])),
                        assertz(user:translator_rule(second, [])))),
                 cleanup(retractall(user:translator_rule(_, _))) ]).

%The refusal NAMES the operation now. It used to be a bare
%instantiation_error, which told a MeTTa program that a value was missing and
%not which operation wanted it; the no-mutation half is what this test is
%really for and is unchanged.
test(variable_removal_is_rejected_without_mutation,
     [throws(error(petta_unbound_input('remove-translator-rule!', 1), _))]) :-
    catch('remove-translator-rule!'(_, _), Error,
          ( findall(Rule, user:translator_rule(Rule), Rules),
            Rules == [first, second],
            throw(Error) )).

test(ground_removal_only_removes_its_rule,
     [true(Rules == [second])]) :-
    'remove-translator-rule!'(first, true),
    findall(Rule, user:translator_rule(Rule), Rules).

:- end_tests(metta_translator_rules).

:- begin_tests(metta_python_import_cleanup).

write_import_fixture(Path) :-
    setup_call_cleanup(open(Path, write, Out),
                       format(Out, 'VALUE = 1~n', []),
                       close(Out)).

clear_python_test_module(Name) :-
    ( py_call(sys:modules:'__contains__'(Name), @(true))
      -> py_call(sys:modules:pop(Name), _)
       ; true ).

exercise_python_import_setup_failure(Directory) :-
    gensym(petta_cleanup_, Suffix),
    format(atom(MainName), 'petta_cleanup_main_~w', [Suffix]),
    format(atom(SiblingName), 'petta_cleanup_sibling_~w', [Suffix]),
    file_name_extension(MainName, py, MainFile),
    file_name_extension(SiblingName, py, SiblingFile),
    directory_file_path(Directory, MainFile, MainPath),
    directory_file_path(Directory, SiblingFile, SiblingPath),
    write_import_fixture(MainPath),
    write_import_fixture(SiblingPath),
    py_call(builtins:object(), OriginalModule, [py_object(true)]),
    py_call(builtins:id(OriginalModule), OriginalId),
    py_call(importlib:util, ImportUtil, [py_object(true)]),
    py_call(ImportUtil:spec_from_file_location, OriginalSpec,
            [py_object(true)]),
    py_call(builtins:int, RaisingCallable, [py_object(true)]),
    setup_call_cleanup(
        py_call(sys:modules:'__setitem__'(SiblingName, OriginalModule), _),
        setup_call_cleanup(
            py_setattr(ImportUtil, spec_from_file_location, RaisingCallable),
            ( catch(load_python_source(MainPath), Error, true),
              nonvar(Error),
              py_call(sys:modules:'__contains__'(SiblingName), Present),
              Present == @(true),
              py_call(sys:modules:get(SiblingName), RestoredModule,
                      [py_object(true)]),
              py_call(builtins:id(RestoredModule), RestoredId),
              RestoredId =:= OriginalId ),
            py_setattr(ImportUtil, spec_from_file_location, OriginalSpec)),
        clear_python_test_module(SiblingName)).

test(setup_failure_restores_preexisting_sibling_module) :-
    tmp_file(petta_python_import, Directory),
    setup_call_cleanup(make_directory(Directory),
                       exercise_python_import_setup_failure(Directory),
                       delete_directory_and_contents(Directory)).

:- end_tests(metta_python_import_cleanup).

:- begin_tests(metta_registration).

%A registered name with no predicate records no arity, and
%translator:incomplete_application_kind/3 reads a missing arity as "not applied far
%enough", so every call to that name compiles to a partial application: (sqrt
%4) answered (partial sqrt (4)) rather than computing or failing. A special
%form is exempt because the translator consumes it before dispatch, and so is
%a name whose predicate exists under some other arity.
special_form(Name) :- clause(translator:translate_special_dl(Name, _, _, _, _), _).

test(every_registered_function_is_callable_or_a_special_form,
     [true(Unbacked == [])]) :-
    findall(Name,
            ( fun(Name),
              \+ arity(Name, _),
              \+ special_form(Name),
              \+ current_predicate(Name/_) ),
            Names),
    sort(Names, Unbacked).

:- end_tests(metta_registration).

:- begin_tests(metta_set_operations).

%The tuple set operations remove by equality, not by unification. select/3
%unified, so (subtraction-atom ($x) (a)) answered () and left $x bound to a
%afterwards. PeTTa's formalisation removes with removeFirstEq, an == test:
%MeTTapedia/lean/mettapedia/leanPeTTa/StreamOps.lean.
test(subtraction_keeps_an_unbound_element,
     [true(Out == [X])]) :-
    'subtraction-atom'([X], [a], Out).

test(subtraction_does_not_bind_its_input) :-
    'subtraction-atom'([X], [a], _),
    var(X).

test(intersection_does_not_match_a_variable_against_an_atom,
     [true(Out == [])]) :-
    'intersection-atom'([_X], [a], Out).

test(intersection_does_not_bind_its_input) :-
    'intersection-atom'([X], [a], _),
    var(X).

%Identical variables still cancel, so the operations stay multiset operations
%over the terms they are given.
test(subtraction_removes_an_identical_variable,
     [true(Out == [])]) :-
    'subtraction-atom'([X], [X], Out).

test(subtraction_keeps_documented_multiplicities,
     [true(Out == [a, b])]) :-
    'subtraction-atom'([a, b, b, c], [b, c, c, d], Out).

test(intersection_keeps_documented_multiplicities,
     [true(Out == [b, c, c])]) :-
    'intersection-atom'([a, b, c, c], [b, c, c, c, d], Out).

test(subtraction_of_a_non_list_is_empty,
     [true(Out == [])]) :-
    'subtraction-atom'(a, [a], Out).

test(subtraction_with_a_non_list_right_operand_is_empty,
     [true(Out == [])]) :-
    'subtraction-atom'([a], not_a_list, Out).

test(intersection_with_a_non_list_right_operand_is_empty,
     [true(Out == [])]) :-
    'intersection-atom'([a], not_a_list, Out).

test(union_atom_answers_the_empty_tuple_for_a_non_list) :-
    % Its two siblings already did. A non-list left operand failed silently,
    % and a non-list right operand built the improper list printed as
    % (cons a b), which no tuple operation can consume.
    'union-atom'(a, [b], Left), Left == [],
    'union-atom'([a], b, Right), Right == [].

test(union_atom_keeps_its_multiplicities) :-
    'union-atom'([a, b, b, c], [b, c, c, d], Out),
    Out == [a, b, b, c, b, c, c, d].

:- end_tests(metta_set_operations).


% An operation error names its culprit in the syntax the program wrote it
% in. The ISO formal term is unchanged, because the MeTTa catch form and
% the host's structured surface both read it; only the rendering differs.

:- begin_tests(metta_operation_error_message).

operation_error_text(Operation, Expected, Culprit, Text) :-
    catch(throw_metta_type_error(Operation, Expected, Culprit), Error, true),
    message_to_string(Error, Text).

test(the_culprit_reads_as_metta) :-
    operation_error_text('+', number, ['State', 5], Text),
    Text == "+: number expected, found (State 5)".

test(a_scalar_culprit_reads_as_itself) :-
    operation_error_text('<', number, foo, Text),
    Text == "<: number expected, found foo".

test(the_formal_term_stays_iso) :-
    catch(throw_metta_type_error('+', number, ['State', 5]), Error, true),
    Error = error(Formal, context(Operation, Explanation)),
    Formal == type_error(number, ['State', 5]),
    Operation == '+',
    Explanation == 'invalid MeTTa operation argument'.

%Every other error SWI renders keeps its own message. once/1 because this asks
%whether the text CONTAINS the fragment, and sub_string/5 with every position
%unbound is a search: it answers, then keeps a choice point open looking for
%another occurrence.
test(an_unrelated_type_error_is_untouched) :-
    catch(type_error(number, ['State', 5]), Error, true),
    message_to_string(Error, Text),
    once(sub_string(Text, _, _, _, "['State',5]")).

:- end_tests(metta_operation_error_message).

:- begin_tests(metta_decons_total).

%decons-atom answers for EVERY expression including the empty one, because
%failing there does not mean "no decomposition", it drops the whole
%continuation: (chain (decons-atom ()) $l TEMPLATE) never runs its template
%and the branch after it is unreachable.
test(decons_atom_is_total) :-
    'decons-atom'([a, b, c], Split),
    Split == [a, [b, c]],
    'decons-atom'([], Empty),
    Empty = ['Error', ['decons-atom', []], Message],
    string(Message).

%Three elements, and that is load-bearing. lib_measure.metta and
%lib_soft.metta write (let ($h $t) (decons-atom $ps) ...) and rely on the
%empty case not matching, so a two-element error would bind $h to Error and
%answer a wrong result in silence.
test(the_empty_error_does_not_destructure_as_a_pair) :-
    'decons-atom'([], Empty),
    \+ Empty = [_, _].

:- end_tests(metta_decons_total).

:- begin_tests(metta_builtin_type_surface).

%get-type has to report the engine's own surface, or every tool reading it is
%told the engine has no types for its own builtins. != is the worked case: it
%IS a builtin, IS registered and IS declared in lib_builtin_types.metta, and
%before this it answered %Undefined% for an operation that works.
surface_case('!=',        [->, _, _, 'Bool']).
surface_case('==',        [->, _, _, 'Bool']).
surface_case('+',         [->, 'Number', 'Number', 'Number']).
surface_case('sqrt-math', [->, 'Number', 'Number']).

test(get_type_reports_the_engines_own_builtins,
     [forall(surface_case(Name, Shape))]) :-
    'get-type'(Name, Type),
    subsumes_term(Shape, Type).

%A declared type is a claim that the operation can be CALLED that way, and
%this one could not be called at all. exists_file was registered bare, so the
%engine read SWI's exists_file/1's only argument as the output slot and made
%it a zero-input operation: a path could never be passed in. Declaring
%(-> %Undefined% Bool) for it said otherwise.
%
%Answering false rather than failing is the other half. A test that FAILS is
%indistinguishable from a test that was never reached, which is how the
%original symptom stayed hidden: lib_import.metta records dropping a guard
%because "It made a missing file fail SILENTLY, with no answer".
%An operator whose name a LIBRARY also exports had every one of that
%library's arities recorded as its own. library(yall) exports //2 through //9
%into user as its free-variables lambda, so `/` was registered at seven
%arities where + and * have one, and (/ 1 2 3) compiled to a direct
%'/'(1,2,3,_) call, which is yall's lambda: it answered
%`type_error(lambda_free, 1)` where every other operator answers the engine's
%own error naming the operator. Nothing was ever wrong with the ANSWERS,
%currying included; the message was simply unactionable.
test(metta_registration_arities,
     [forall(member(Operator, ['/', '+', '-', '*', min, max]))]) :-
    findall(Arity, arity(Operator, Arity), Arities),
    sort(Arities, Sorted),
    assertion(Sorted == [3]).

%A wrong arity is an ordinary MeTTa error and an ANSWER, not a raise, and the
%operator it names is the one the program wrote
%[source: LeaTTa tests/semantics/eval-core/empty-argument-arity.metta;
%measured 2026-08-19 against the arbiter, which answers
%`(Error (+ 1 2 3) IncorrectNumberOfArguments)`].
test(metta_arity_errors_name_the_operator,
     [forall(member(Operator, ['/', '+', '-', '*', min, max]))]) :-
    findall(Answer, reduce([Operator, 1, 2, 3], Answer, _), Answers),
    assertion(Answers == [['Error', [Operator, 1, 2, 3],
                           'IncorrectNumberOfArguments']]).

test(builtin_exists_file) :-
    library('lib_builtin_types.metta', Present),
    'exists_file'(Present, Found),
    assertion(Found == true),
    'exists_file'('/nonexistent/petta/definitely-not-here', Missing),
    assertion(Missing == false),
    %The declaration and the callable shape agree, which is the pairing that
    %was broken: get-type promised one input and the registration took none.
    'get-type'(exists_file, Type),
    assertion(subsumes_term([->, _, 'Bool'], Type)),
    catch('exists_file'(5, _), error(Formal, _), true),
    assertion(nonvar(Formal)).

%The table has exactly two legitimate sources: the file, and the engine
%prelude's declarations. Stated as a SET identity rather than as
%file + ledger == table, because the two sources are allowed to OVERLAP and
%the arithmetic identity silently forbade it. get-type is written in both,
%once for the type surface the file is and once so the call site honours its
%Atom mask, and counting rows read that legitimate overlap as a double write.
%The set identity says the same no-foreign-rows thing without the assumption,
%and the row-count pair says the no-double-writes half directly instead of
%leaving it to be inferred from a total.
%
%Rows are numbervar'd first. Several declarations are non-ground, `(: == (->
%$t $t Bool))` among them, and every findall renames those variables fresh,
%so an untreated == compares two structurally identical lists as different
%and sort/2 keeps two copies of a row written twice. Grounding first makes
%both comparisons say what they mean.
%Each row is numbered on its own, from zero, because numbering the whole
%list would make a row's numbers depend on how many rows preceded it and the
%two lists arrive in different orders.
canonical_row(Row, Canonical) :-
    copy_term(Row, Canonical),
    numbervars(Canonical, 0, _).

canonical_rows(Rows, Canonical) :-
    maplist(canonical_row, Rows, Numbered),
    sort(Numbered, Canonical).

test(the_table_is_built_from_the_file_rather_than_written_twice) :-
    library('lib_builtin_types.metta', Path),
    read_file_to_string(Path, Text, []),
    parse_metta_source(Text, Forms),
    findall(Name-Type,
            ( member(parsed(expression, _, [':', Name, Type]), Forms),
              atom(Name) ),
            InFile),
    findall(Name-Type, prelude_type_declaration(Name, Type), FromPrelude),
    findall(Name-Type, seam:builtin_type_declaration(Name, Type), Loaded),
    append(InFile, FromPrelude, Sources),
    canonical_rows(Sources, ExpectedRows),
    canonical_rows(Loaded, LoadedRows),
    assertion(ExpectedRows == LoadedRows),
    length(Loaded, RowCount),
    length(LoadedRows, DistinctCount),
    assertion(RowCount == DistinctCount),
    InFile \== [],
    FromPrelude \== [].

%The overlap the row above allows is real and has a mechanism: a row the
%prelude found already written stays out of its eviction ledger, so a program
%redeclaring the name takes the prelude's row away and leaves the file's.
%Without that split, retractall/1 could not tell two identical rows apart and
%eviction deleted the engine's own type surface entry for the name.
test(a_shared_declaration_is_evicted_only_from_the_register_that_wrote_it) :-
    Shared = 'get-type',
    findall(Type, prelude_type_declaration(Shared, Type), Declared),
    findall(Type, seam:builtin_type_declaration(Shared, Type), Surface),
    assertion(Declared \== []),
    assertion(Surface \== []),
    %Written by the file, so the prelude found it rather than putting it there.
    assertion(\+ prelude_wrote_builtin_type(Shared, _)),
    setup_call_cleanup(
        true,
        ( retract_prelude_declarations(Shared),
          findall(Type, seam:builtin_type_declaration(Shared, Type), Survived),
          findall(Type, prelude_type_declaration(Shared, Type), Gone),
          assertion(Survived == Surface),
          assertion(Gone == []) ),
        forall(member(Type, Declared),
               assertz(prelude_type_declaration(Shared, Type)))).

%The declarations are FACTS, not atoms in &self. Putting them in &self changes
%what every program sees of its own space, which is not the engine's to do.
test(the_surface_is_invisible_to_a_program_enumerating_its_own_space) :-
    \+ ( 'get-atoms'('&self', Atom),
         Atom = [':', Name, _],
         seam:builtin_type_declaration(Name, _) ).

%Last in the candidate order, so a program's own declaration wins.
test(a_program_declaration_is_answered_before_the_engines,
     [ setup(( retractall(silent(_)), assertz(silent(true)),
               'add-atom'('&self', [':', 'sqrt-math', 'PlunitOverride'], _) )),
       cleanup(( 'remove-atom'('&self', [':', 'sqrt-math', 'PlunitOverride'], _),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    findall(T, 'get-type'('sqrt-math', T), Types),
    Types = ['PlunitOverride'|_].

:- end_tests(metta_builtin_type_surface).

%comparable_operands/3 at the predicate's own door, where the answer is a
%Prolog one and no MeTTa reduction stands between the operands and the
%verdict.
:- begin_tests(comparable_operands).

%The refusal names the position, the type the first operand fixed and the type
%the second carries, which is what `(-> $a $a Bool)` says and what the arbiter
%answers [source: LeaTTa tests/semantics/grounded/07-partial-core.metta,
%`(== 1 a)` with `(: a String)` is `(BadArgType 2 Number String)`].
test(two_known_and_different_kinds_are_refused,
     [forall(member(A-B-Reason,
                    [1-"s"-['BadArgType', 2, 'Number', 'String'],
                     true-1-['BadArgType', 2, 'Bool', 'Number'],
                     "s"-1-['BadArgType', 2, 'String', 'Number'],
                     1-true-['BadArgType', 2, 'Number', 'Bool']]))]) :-
    findall(R, '=='(A, B, R), Answers),
    Answers = [['Error', _, Actual]],
    assertion(Actual == Reason).

test(a_pair_of_one_kind_is_compared,
     [forall(member(A-B-R, [1-1-true, 1-2-false, "s"-"s"-true,
                            true-false-false]))]) :-
    '=='(A, B, Answer),
    assertion(Answer == R).

%An operand nothing declares contradicts nothing, so the comparison happens.
test(an_undeclared_operand_is_compared_rather_than_refused) :-
    '=='(1, plunit_no_declaration, First),
    assertion(First == false),
    '=='(plunit_no_declaration, "s", Second),
    assertion(Second == false).

%Expressions are the axis the two references disagree on, so the guard leaves
%them alone and the collapse-and-compare idiom keeps working.
test(an_expression_operand_is_never_refused,
     [forall(member(A-B-R, [[1,2,3]-[]-false, []-[]-true, [1,2]-[3,4]-false,
                            []-1-false, "s"-[]-false]))]) :-
    '=='(A, B, Answer),
    assertion(Answer == R).

%Deciding WHETHER two operands are comparable must not walk them. One proper
%list is all the list branches need, and () is one, so an operand that is ()
%settles the question without is_list/1 walking the other. `(== $l ())` is how
%a list is walked to its end, so asking is_list/1 of the whole remaining list
%at every step made traversing N elements quadratic: the walk cost 13,538
%microseconds at 3,200 elements and 137,949 at 12,800, 10.2x per 4x, against
%5,048 and 26,883 now [measured 2026-08-23].
%
%The test is TIMED rather than counted. is_list/1 is one C builtin call and
%reads as a single inference whatever the length of the list it walks, so the
%counter cannot see this at all; process CPU time can, it does not move with
%machine load, and both readings come from one process. One comparison against
%a 6,400-element list cost 8.88 microseconds and costs 0.53, while the same
%comparison against a 400-element list cost 1.19 and costs 0.42.
comparison_cost(Length, Seconds) :-
    findall(e, between(1, Length, _), List),
    forall(between(1, 100, _), '=='(List, [], _)),
    statistics(cputime, Before),
    forall(between(1, 2000, _), '=='(List, [], _)),
    statistics(cputime, After),
    Seconds is After - Before.

test(comparing_against_the_empty_list_does_not_walk_the_other_operand) :-
    comparison_cost(400, Narrow),
    comparison_cost(6400, Wide),
    assertion(Wide < Narrow * 4).

test(the_refusal_names_the_metta_operation) :-
    catch('=='(1, "s", _), error(_, Context), true),
    assertion(Context = context('==', _)),
    catch('!='(1, "s", _), error(_, NeContext), true),
    assertion(NeContext = context('!=', _)).

:- end_tests(comparable_operands).


:- begin_tests(metta_constraint_domains).

%CLP(Q) and CLP(B) each arrive as ONE entry point taking its constraint as
%written, rather than as a prefixed operator family like `#`. Mirroring `#`
%would have needed about thirty names; these are five.
constraint_case("!(let True (clpq (= (* 2 $x) 1)) (repr $x))", ["1r2"]).
constraint_case("!(let True (clpq (= (* 2 $x) 1)) (* 2 $x))", [1]).
constraint_case("!(collapse (let True (clpq (>= $a 0)) (clpq-entailed (>= $a 0))))",
                [[true]]).
constraint_case("!(collapse (let True (clpq (>= $b 0)) (clpq-entailed (>= $b 5))))",
                [[false]]).
constraint_case("!(collapse (let True (clpq (= $c 1)) (clpq (= $c 2))))", [[]]).
constraint_case("!(collapse (let True (clpb (card (1) ($m $n))) \c
                              (clpb-labeling ($m $n))))",
                [[[0, 1], [1, 0]]]).
constraint_case("!(clpb-taut (+ $t (~ $t)))", [true]).
constraint_case("!(clpb-taut (* $u (~ $u)))", [false]).

test(each_constraint_domain_answers,
     [ forall(constraint_case(Source, Expected)),
       setup(( retractall(silent(_)), assertz(silent(true)),
               process_metta_string(
                   "!(import! &self (library lib_constraints))", _) )),
       cleanup(( retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string(Source, Results),
    Results == Expected.

%The constraint arrives AS WRITTEN. Evaluated first, (* 2 $x) would run as
%ordinary arithmetic and raise before the solver saw it. The Atom parameter
%in the library's declarations is what does it, which is the documented way a
%Prolog-registered predicate takes an argument unevaluated.
test(a_constraint_is_not_evaluated_before_the_solver_sees_it,
     [setup(( retractall(silent(_)), assertz(silent(true)),
              process_metta_string(
                  "!(import! &self (library lib_constraints))", _) )),
      cleanup(( retractall(silent(_)), assertz(silent(false)) ))]) :-
    translate_runnable_expr([clpq, [=, [*, 2, _X], 1]], Goals, _),
    term_string(Goals, Text),
    %the constraint reaches clpq/2 as the list it was written as, with no
    %arithmetic goal emitted ahead of it
    once(sub_string(Text, _, _, _, "clpq([=,[*,2,")),
    \+ sub_string(Text, _, _, _, "*(2,").

%A list whose head is a symbol is an operator application; any other list
%stays a list, because these solvers take lists as arguments too.
test(a_list_argument_stays_a_list,
     [setup(( retractall(silent(_)), assertz(silent(true)),
              process_metta_string(
                  "!(import! &self (library lib_constraints))", _) )),
      cleanup(( retractall(silent(_)), assertz(silent(false)) ))]) :-
    metta_constraint_term([card, [1], [A, B]], Term),
    Term = card(Counts, Vars),
    Counts == [1],
    Vars = [A1, B1],
    A1 == A, B1 == B.

:- end_tests(metta_constraint_domains).

:- begin_tests(metta_subtyping).

%`:<` is upstream's spelling, SUB_TYPE_SYMBOL at lib/src/metta/mod.rs:22, and
%the arrow points from the subtype UP to the supertype: `(:< Dog Animal)` says
%Dog is below Animal. It is not `:>`.
%
%The mechanism is the part that is easy to get wrong. Upstream never DECIDES a
%subtyping relation while checking an argument; it WIDENS the argument's type
%LIST and runs the ordinary check against the wider list, so the matcher learns
%nothing about subtyping and `get-type` is where it shows. Every expectation
%below is the arbiter's measured answer from pinned hyperon 0.2.10 at 3f76dc4
%[source: LeaTTa ai-report-subtype-graph.md].

subtype_case(Setup, Query, Expected) :-
    forall(member(Form, Setup), process_metta_string(Form, _)),
    format(atom(Ask), "!(collapse (get-type ~w))", [Query]),
    process_metta_string(Ask, [Answered]),
    assertion(Answered == Expected).

test(a_declared_type_widens_to_its_supertype) :-
    subtype_case(["(: sub-a A1)", "(:< A1 B1)"], 'sub-a', ['A1', 'B1']).

%A grounded literal's built-in type is NOT widened: upstream's
%get_atom_types_internal queries the space only for symbols and expressions.
test(a_literals_builtin_type_is_not_widened) :-
    subtype_case(["(:< Number SubFoo)"], 1, ['Number']).

%Nor is an application's return type.
test(an_application_return_type_is_not_widened) :-
    subtype_case(["(: sub-c C1)", "(: sub-f (-> C1 D1))", "(:< D1 E1)"],
                 '(sub-f sub-c)', ['D1']).

%Tuple products first, then the direct declarations already widened, then one
%more widening over the whole list. A single pass answers ((A B) D C E) and
%upstream answers ((A B) D E C), so the order is the test.
test(an_expression_widens_in_two_phases) :-
    subtype_case(["(: sub-p P1)", "(: sub-q Q1)", "(: (sub-p sub-q) R1)",
                  "(:< (P1 Q1) S1)", "(:< R1 T1)"],
                 '(sub-p sub-q)', [['P1', 'Q1'], 'R1', 'T1', 'S1']).

%The diamond answers D TWICE. add_super_types checks presence against the list
%as it stood when the round BEGAN, so both B and C reach D in the same round
%and both append it. Reproducing the duplicate is what makes this parity rather
%than a tidier answer of our own.
test(the_diamond_reproduces_upstreams_duplicate) :-
    subtype_case(["(:< DA DB)", "(:< DA DC)", "(:< DB DD)", "(:< DC DD)",
                  "(: sub-x DA)"],
                 'sub-x', ['DA', 'DB', 'DC', 'DD', 'DD']).

%And it reaches the argument check, which is what the feature is FOR: a value
%declared Dog satisfies a parameter declared Animal.
test(an_argument_is_accepted_through_its_supertype) :-
    forall(member(Form, ["(: Rex ADog)", "(:< ADog AnAnimal)",
                         "(: sub-speak (-> AnAnimal String))",
                         "(= (sub-speak $a) \"woof\")"]),
           process_metta_string(Form, _)),
    process_metta_string("!(sub-speak Rex)", Answer),
    assertion(Answer == ["woof"]).

%With no edge declared the type path is untouched, which is what keeps this
%free for every program that does not use it.
test(no_edge_leaves_types_alone) :-
    process_metta_string("(: sub-plain PlainType)", _),
    process_metta_string("!(collapse (get-type sub-plain))", [Types]),
    assertion(Types == ['PlainType']).

:- end_tests(metta_subtyping).

:- begin_tests(metta_metatype_parameters).

%A parameter written as a metatype accepts any atom of that kind. Before this
%none of the five checked at all, so `(: PyList (-> Expression PyList))` typed
%a call to it as the tuple product of its arguments, and a container, which has
%no fixed arity, could not be declared. `Expression` is how HE declares
%`(: superpose (-> Expression Atom))`.
%
%The mechanism is one equality with a wildcard, not the `:<` graph:
%`*typ == ATOM_TYPE_ATOM || *typ == get_meta_type(atom)`
%[source: LeaTTa tests/semantics/types-meta/00_metatypes.metta, quoting
%hyperon-experimental@3f76dc4 lib/src/metta/types.rs:606-617].

metatype_call(Declaration, Argument, Answer) :-
    process_metta_string(Declaration, _),
    format(atom(Ask), "!(collapse ~w)", [Argument]),
    process_metta_string(Ask, [Answer]).

test(a_variadic_constructor_can_be_declared) :-
    process_metta_string("(: MetaPyList (-> Expression MetaPyList))", _),
    process_metta_string("!(collapse (get-type (MetaPyList (1 2 3))))", [Types]),
    assertion(Types == ['MetaPyList']).

test(a_symbol_parameter_takes_a_symbol_and_nothing_else) :-
    process_metta_string("(: meta-sym (-> Symbol Atom))", _),
    process_metta_string("(= (meta-sym $s) (got $s))", _),
    metatype_call("", "(meta-sym foo)", Accepted),
    assertion(Accepted == [[got, foo]]),
    metatype_call("", "(meta-sym (1 2))", RejectsExpression),
    assertion(RejectsExpression == [['Error', ['meta-sym', [1, 2]],
                                     ['BadArgType', 1, 'Symbol',
                                      ['Number', 'Number']]]]),
    metatype_call("", "(meta-sym 7)", RejectsNumber),
    assertion(RejectsNumber == [['Error', ['meta-sym', 7],
                                 ['BadArgType', 1, 'Symbol', 'Number']]]).

%A metatype parameter refuses a value of a KNOWN and different type, and lets
%through a value whose type nothing declares, which is the gradual rule and
%not a hole in the metatype check: %Undefined% is consistent with every type
%(Siek and Taha's ? relation), so no violation is provable for `foo`.
%
%This test used to say "and nothing else" and assert that `foo` was refused.
%Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
%interpreter, byte-identical across both: `!(meta-expr foo)` answers
%`(got foo)` and `!(meta-expr 7)` is `(BadArgType 1 Expression Number)`. The
%source the old comment quoted, `*typ == ATOM_TYPE_ATOM || *typ ==
%get_meta_type(atom)`, describes ONE of the routes into the check; the
%declared-type route runs first and admits the unknown.
test(an_expression_parameter_refuses_a_known_other_type_and_admits_an_unknown) :-
    process_metta_string("(: meta-expr (-> Expression Atom))", _),
    process_metta_string("(= (meta-expr $e) (got $e))", _),
    metatype_call("", "(meta-expr (1 2))", Accepted),
    assertion(Accepted == [[got, [1, 2]]]),
    metatype_call("", "(meta-expr 7)", RejectsNumber),
    assertion(RejectsNumber == [['Error', ['meta-expr', 7],
                                 ['BadArgType', 1, 'Expression', 'Number']]]),
    metatype_call("", "(meta-expr foo)", AdmitsUnknown),
    assertion(AdmitsUnknown == [[got, foo]]).

%Atom is the wildcard, which is the whole of what the tutorial's "supertype"
%wording means once it is read off the source rather than the prose.
%A distinct name per case: plunit's forall re-runs the whole body, so one
%shared name would redefine the equation and answer once more each time round.
test(an_atom_parameter_takes_every_kind,
     [forall(member(Name-Argument, ["meta-any-sym"-"foo",
                                    "meta-any-expr"-"(1 2)",
                                    "meta-any-num"-"7",
                                    "meta-any-str"-"\"s\""]))]) :-
    format(atom(Declare), "(: ~w (-> Atom Atom))", [Name]),
    process_metta_string(Declare, _),
    format(atom(Define), "(= (~w $a) (got $a))", [Name]),
    process_metta_string(Define, _),
    format(atom(Ask), "!(collapse (~w ~w))", [Name, Argument]),
    process_metta_string(Ask, [Answer]),
    assertion(Answer = [[got, _]]).

%get-metatype/2 was only correct with its second argument UNBOUND. The clauses
%are ordered and cut on the value, so asking with it bound let an earlier
%clause's head fail to unify and the catch-all at the bottom claim the call,
%which made every value answer Grounded. Both callers ask with it bound.
%The same gradual rule from the Grounded side. This test used to assert that
%a Grounded parameter REJECTS a symbol; measured 2026-08-19 on hyperon 0.2.10
%and on the LeaTTa mechanised interpreter, byte-identical across both,
%`!(meta-gnd foo)` answers `(gotg foo)`. An undeclared symbol has no declared
%type to contradict Grounded with. A symbol that IS declared does, and that is
%the half this pins as still refusing.
test(a_grounded_parameter_admits_an_unknown_and_refuses_a_declared_other) :-
    process_metta_string("(: meta-gr (-> Grounded Atom))", _),
    process_metta_string("(= (meta-gr $g) (got $g))", _),
    metatype_call("", "(meta-gr 7)", Accepted),
    assertion(Accepted == [[got, 7]]),
    metatype_call("", "(meta-gr foo)", AdmitsUnknown),
    assertion(AdmitsUnknown == [[got, foo]]),
    process_metta_string("(: meta-gr-typed MetaGrOther)", _),
    metatype_call("", "(meta-gr meta-gr-typed)", RejectsDeclared),
    assertion(RejectsDeclared == [['Error', ['meta-gr', 'meta-gr-typed'],
                                   ['BadArgType', 1, 'Grounded',
                                    'MetaGrOther']]]).

test(get_metatype_answers_the_same_bound_or_unbound,
     [forall(member(Value-Metatype, [foo-'Symbol', 7-'Grounded',
                                     "s"-'Grounded', [1,2]-'Expression']))]) :-
    'get-metatype'(Value, Computed),
    assertion(Computed == Metatype),
    assertion('get-metatype'(Value, Metatype)),
    forall(( member(Other, ['Symbol', 'Grounded', 'Expression', 'Variable']),
             Other \== Metatype ),
           assertion(\+ 'get-metatype'(Value, Other))).

:- end_tests(metta_metatype_parameters).

:- begin_tests(metta_module_context).

% current_metta_module/1 is one of the seven services engine/ext_points.pl
% publishes for extensions to CALL, and it was the only one of the seven with
% no test of its own: EXTENDING.md has told handler authors to read it for
% longer than anything declared it, and lib_memo and lib_thread do. A published
% predicate nothing exercises can change under every extension at once.

%&self's own module, not Prolog's `user`: an equation compiled into the
%module the engine itself resolves in REPLACES a predicate of that name
%instead of shadowing it.
test(the_default_context_is_selfs_own_module) :-
    current_metta_module(Module),
    space_module('&self', Self),
    assertion(Module == Self),
    assertion(Module \== user).

% The argument is the module a space compiles into, which space_module/2
% answers. It used to be the space's own name for every space but &self, and a
% test that wrote the space name passed by coincidence.
test(a_named_module_is_in_force_inside_the_switch) :-
    space_module('&probe', Probe),
    with_metta_module(Probe, current_metta_module(Inside)),
    assertion(Inside == Probe).

test(a_space_name_is_refused_where_a_module_is_asked,
     [throws(error(type_error(metta_execution_module, '&probe'), _))]) :-
    with_metta_module('&probe', true).

test(the_previous_module_is_restored_after) :-
    space_module('&probe', Probe),
    with_metta_module(Probe, true),
    current_metta_module(After),
    metta_self_module(Self),
    assertion(After == Self).

% The restore is setup_call_cleanup/3's, so it has to survive the goal
% throwing. Without that a library that raises inside a named space leaves
% every later compile pointed at a module the caller never asked for.
test(the_previous_module_is_restored_after_a_throw) :-
    space_module('&probe', Probe),
    catch(with_metta_module(Probe, throw(deliberate)), deliberate, true),
    current_metta_module(After),
    metta_self_module(Self),
    assertion(After == Self).

test(switches_nest_and_unwind_in_order) :-
    space_module('&outer', OuterModule),
    space_module('&inner', InnerModule),
    with_metta_module(OuterModule,
                      ( current_metta_module(Outer),
                        with_metta_module(InnerModule,
                                          current_metta_module(Inner)),
                        current_metta_module(Back),
                        assertion(Outer == OuterModule),
                        assertion(Inner == InnerModule),
                        assertion(Back == OuterModule) )),
    current_metta_module(Final),
    metta_self_module(Self),
    assertion(Final == Self).

% P11.5's question, answered by counting rather than by reading the sources.
% The row proposed threading the space context through every compiled clause as
% an extra argument, Logtalk's `Self` field, so that compiled code stops
% consulting the global while it runs. Compiled code DOES consult it, and the
% rate is what decides the row.
%
% reduce/3, the runtime dispatcher, reads it once per dispatch on an atom head
% that is NOT a plain shared-tier function, and not at all for one that is:
% `fun(F), \+ fun_scoped(F) -> Module = Self` settles the second case without
% asking, and everything else falls through to `current_metta_module(Module),
% fun_here_in(Module, F)`. A DATA CONSTRUCTOR is the common case rather than a
% space-scoped function, which is worth writing down because the name of the
% branch suggests otherwise: examples/performance/matespacefast.metta reduces
% (num (M $t)) and (M $t) at every node of a binary tree of depth 19, and that
% is the whole of its 262,144 reads. The space-update capability check is a
% second and separate reader, once per update. This test pins all three rates,
% so a change that made the fast path start asking, or either of the others ask
% twice, fails here.
%
% Measured over the shipped corpus, one process per example the way the corpus
% lane runs one: 468,624 of 486,309 reads are on the evaluation path, and two
% examples are almost all of it, examples/performance/matespacefast.metta with
% 262,144 and examples/reasoning/nilbc.metta with 182,012, every one of
% matespacefast's attributed to reduce/3 [measured 2026-08-22].
%
% And priced, in the same unit both sides have to be compared in. One read
% costs about 600 instructions, of which nb_current/2 is 491 above a trivial
% builtin and nb_getval/2 would be 376. matespacefast runs 97.1 billion
% instructions, so its 262,144 reads are 0.16% of it. One extra argument on a
% compiled predicate, threaded through its recursive call the way the route
% would thread it, costs 24.7 instructions per call and +2.08% on a
% call-dominated workload (236,825,346 against 241,759,755 over 200,000 steps),
% while costing nothing measurable in inferences (+88 over 40,000 calls). Every
% compiled call would pay that; only a named-space dispatch reads. Paying 2.08%
% on every call to remove 0.16% on the most read-heavy program in the tree is
% the row's own stop condition, so the global stays.
%
% Reading the caller's module instead of the global would be WRONG rather than
% cheaper, which is why the route had to be the expensive one: the prelude is
% compiled into &self's module and shared by every space through the base
% chain, so a shared clause would report where it was COMPILED and not where it
% is RUNNING -- Logtalk's `This` where the dispatcher needs `Self`.
test(test_the_module_context_is_read_once_per_unresolved_dispatch_and_once_per_space_update,
     [ cleanup(( catch(unwrap_predicate(ContextModule:current_metta_module/1,
                                        context_read_probe), _, true),
                 catch(unwrap_predicate(SelfModule:'ctx-sum'/2,
                                        context_eval_probe), _, true),
                 catch(unwrap_predicate(SelfModule:'ctx-grow'/2,
                                        context_eval_probe), _, true) )) ]) :-
    petta_engine_module(ContextModule),
    metta_self_module(SelfModule),
    process_metta_string("(= (ctx-sum $n) \c
                             (if (== $n 0) 0 (+ $n (ctx-sum (- $n 1)))))", _),
    process_metta_string("(= (ctx-grow $x) \c
                             (let $_ (add-atom (context-space) (ctx-row $x)) \c
                                  $x))", _),
    % Warm both compiles, so each counting window below holds an evaluation and
    % not a translation.
    process_metta_string("!(ctx-sum 3)", Warm),
    assertion(Warm == [6]),
    process_metta_string("!(ctx-grow 0)", _),
    process_metta_string("(= (ctxfn $x) (+ $x 1))", _),
    process_metta_string("!(ctxfn 1)", _),

    % One: a function of the SHARED tier dispatches without asking. reduce/3
    % settles `fun(F), \+ fun_scoped(F)` without a context read, and that is
    % the engine's hottest path.
    context_reads(SelfModule:'ctx-sum'(_, _),
                  process_metta_string("!(ctx-sum 120)", Summed),
                  Dispatches, Quiet),
    assertion(Summed == [7260]),
    assertion(Dispatches > 100),
    assertion(Quiet == 0),

    % Two: a space UPDATE asks, once per evaluation, because the capability
    % check has to know which space is in force.
    context_reads(SelfModule:'ctx-grow'(_, _),
                  forall(between(1, 40, _),
                         process_metta_string("!(ctx-grow 1)", _)),
                  Updates, Asked),
    assertion(Updates == 40),
    assertion(Asked == 40),

    % Three: reduce/3 asks once per runtime dispatch on an atom head that is
    % NOT a plain shared-tier function, and not at all for one that is. A data
    % constructor is the common case and it is the rate the corpus is almost
    % entirely made of: examples/performance/matespacefast.metta reduces
    % (num (M $t)) and (M $t) at every node of a binary tree of depth 19, which
    % is where its 262,144 reads come from [measured 2026-08-22].
    petta_dispatch_reads([ctxfn, 1], FunctionReads),
    assertion(FunctionReads == 0),
    petta_dispatch_reads(['CtxData', 1], DataReads),
    assertion(DataReads == 40).

%Count reads of the module context that happen while Watched is on the stack.
%Watched is the COMPILED PREDICATE itself rather than a proxy for it, so
%"while compiled code runs" is the engine's own answer; the opening count is
%returned so a zero cannot mean the window never opened.
:- meta_predicate context_reads(+, 0, -, -).

context_reads(Watched, Goal, Openings, Reads) :-
    petta_engine_module(ContextModule),
    nb_setval('$petta_context_reads', 0),
    nb_setval('$petta_evaluating', 0),
    nb_setval('$petta_evaluations', 0),
    setup_call_cleanup(
        ( wrap_predicate(Watched, context_eval_probe, Evaluated,
                         setup_call_cleanup(context_eval_enter, Evaluated,
                                            context_eval_exit)),
          wrap_predicate(ContextModule:current_metta_module(_),
                         context_read_probe, Inner,
                         ( nb_getval('$petta_evaluating', Depth),
                           (   Depth > 0
                           ->  nb_getval('$petta_context_reads', Was),
                               Now is Was + 1,
                               nb_setval('$petta_context_reads', Now)
                           ;   true
                           ),
                           Inner )) ),
        Goal,
        ( catch(unwrap_predicate(ContextModule:current_metta_module/1,
                                 context_read_probe), _, true),
          context_unwrap(Watched) )),
    nb_getval('$petta_evaluating', Balanced),
    assertion(Balanced == 0),
    nb_getval('$petta_evaluations', Openings),
    nb_getval('$petta_context_reads', Reads).

%Forty dispatches through the engine's runtime dispatcher, counting the reads.
%reduce/3 is what a compiled body calls for a head it could not resolve at
%compile time, so calling it here is the same door and not a proxy for one.
petta_dispatch_reads(Term, Reads) :-
    petta_engine_module(ContextModule),
    nb_setval('$petta_context_reads', 0),
    setup_call_cleanup(
        wrap_predicate(ContextModule:current_metta_module(_),
                       context_read_probe, Inner,
                       ( nb_getval('$petta_context_reads', Was),
                         Now is Was + 1,
                         nb_setval('$petta_context_reads', Now),
                         Inner )),
        forall(between(1, 40, _), reduce(Term, _, _)),
        catch(unwrap_predicate(ContextModule:current_metta_module/1,
                               context_read_probe), _, true)),
    nb_getval('$petta_context_reads', Reads).

context_unwrap(Module:Head) :-
    functor(Head, Name, Arity),
    catch(unwrap_predicate(Module:Name/Arity, context_eval_probe), _, true).

context_eval_enter :-
    nb_getval('$petta_evaluating', D), D1 is D + 1,
    nb_setval('$petta_evaluating', D1),
    nb_getval('$petta_evaluations', N), N1 is N + 1,
    nb_setval('$petta_evaluations', N1).
context_eval_exit :-
    nb_getval('$petta_evaluating', D), D1 is D - 1,
    nb_setval('$petta_evaluating', D1).

:- end_tests(metta_module_context).

:- begin_tests(metta_engine_module).

% `user` was two different jobs wearing one name: the HOST module SWI resolves
% its own hooks and consulted files in, and the module the ENGINE's clauses
% happen to be in. Every wrap_predicate/4 target and every clause/2 read of the
% translator's own compilation tables meant the second one, and asking for it
% is what lets a space stop being the first one.

test(it_answers_exactly_one_module) :-
    findall(Module, petta_engine_module(Module), Modules),
    assertion(Modules = [_]).

% Checked against SWI rather than against the atom `user`, so the test says
% what the predicate is FOR instead of repeating its current answer. The head
% asked about is the CORE's own: reduce/3 was this test's witness until P11.7
% gave the compiler a module, after which it is the translator's and reaches
% the core as an import, which is a different and equally correct answer.
test(it_names_the_module_the_engines_own_clauses_are_in) :-
    petta_engine_module(Engine),
    functor(Head, current_metta_module, 1),
    assertion(predicate_property(Engine:Head, defined)),
    assertion(\+ predicate_property(Engine:Head, imported_from(_))),
    % and a subsystem's own predicate reaches the core as an import rather
    % than by living there, which is what a declared module surface means
    functor(Compiled, reduce, 3),
    assertion(predicate_property(Engine:Compiled, imported_from(translator))).

% The Group F reads: metta_special_form/1 and metta_translated_head/1 ask the
% compiler's own clause table for which heads the translator gives meaning to.
% A read pointed at the wrong module answers for no form at all, silently.
test(the_translators_own_tables_are_read_from_it) :-
    assertion(metta_special_form(if)),
    assertion(metta_translated_head(collapse)),
    assertion(\+ metta_special_form(petta_no_such_form)).

:- end_tests(metta_engine_module).

:- begin_tests(metta_handles_route).

% (handles Ctx Pattern Fidelity [Det]) entries route a query by the most
% specific matching pattern, (in $x) marks a position that must arrive
% bound, and two maximal entries that disagree are a loud conflict.

handles_declare(Entry) :- 'add-atom'('&petta', Entry, _).
handles_retract(Entry) :- catch('remove-atom'('&petta', Entry, _), _, true).

test(strip_keeps_a_variable_headed_pair_entry) :-
    petta_adorn_strip([F, A], Stripped, Requirements),
    assertion(Stripped == [F, A]),
    assertion(Requirements == []),
    assertion(var(F)).

test(strip_keeps_the_symbol_in_as_data_mid_expression) :-
    petta_adorn_strip([foo, in, X], Stripped, Requirements),
    assertion(Stripped == [foo, in, X]),
    assertion(Requirements == []).

test(strip_collects_the_adorned_position) :-
    petta_adorn_strip([edge, [in, A], B], Stripped, Requirements),
    assertion(Stripped == [edge, A, B]),
    assertion(Requirements == [A]).

test(strip_handles_a_nested_wrapper) :-
    petta_adorn_strip([f, [in, [g, [in, X]]]], Stripped, Requirements),
    assertion(Stripped == [f, [g, X]]),
    assertion(Requirements == [[g, X], X]).

test(route_picks_the_most_specific_entry,
     [ setup(( handles_declare([handles, '&plunit_hr', [edge, _, _], 'Exact']),
               handles_declare([handles, '&plunit_hr', [edge, S, S], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hr', [edge, _, _], 'Exact']),
                 handles_retract([handles, '&plunit_hr', [edge, S2, S2], 'Sound']) )) ]) :-
    petta_handles_route('&plunit_hr', [edge, Q, Q], Repeated, _),
    assertion(Repeated == 'Sound'),
    petta_handles_route('&plunit_hr', [edge, _, _], Distinct, _),
    assertion(Distinct == 'Exact').

test(route_reads_the_det_slot_and_defaults_it,
     [ setup(( handles_declare([handles, '&plunit_hr5', [p, _], 'Exact', det]),
               handles_declare([handles, '&plunit_hr5', [q, _], 'Exact']) )),
       cleanup(( handles_retract([handles, '&plunit_hr5', [p, _], 'Exact', det]),
                 handles_retract([handles, '&plunit_hr5', [q, _], 'Exact']) )) ]) :-
    petta_handles_route('&plunit_hr5', [p, _], _, DetP),
    assertion(DetP == det),
    petta_handles_route('&plunit_hr5', [q, _], _, DetQ),
    assertion(DetQ == none).

test(route_fails_where_nothing_is_declared) :-
    \+ petta_handles_route('&plunit_hr_nobody', [p, _], _, _).

test(disagreeing_maximal_entries_throw_a_conflict,
     [ setup(( handles_declare([handles, '&plunit_hrc', [edge, a, _], 'Exact']),
               handles_declare([handles, '&plunit_hrc', [edge, _, b], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hrc', [edge, a, _], 'Exact']),
                 handles_retract([handles, '&plunit_hrc', [edge, _, b], 'Sound']) )),
       throws(error(petta_contract_conflict('&plunit_hrc', _, _, _), _)) ]) :-
    petta_handles_route('&plunit_hrc', [edge, a, b], _, _).

test(agreeing_maximal_entries_answer_their_shared_claim,
     [ setup(( handles_declare([handles, '&plunit_hra', [edge, a, _], 'Exact']),
               handles_declare([handles, '&plunit_hra', [edge, _, b], 'Exact']) )),
       cleanup(( handles_retract([handles, '&plunit_hra', [edge, a, _], 'Exact']),
                 handles_retract([handles, '&plunit_hra', [edge, _, b], 'Exact']) )) ]) :-
    petta_handles_route('&plunit_hra', [edge, a, b], Fidelity, _),
    assertion(Fidelity == 'Exact').

test(an_adorned_entry_requires_the_bound_argument,
     [ setup(handles_declare([handles, '&plunit_hri', [edge, [in, _], _], 'Refuse'])),
       cleanup(handles_retract([handles, '&plunit_hri', [edge, [in, _], _], 'Refuse'])) ]) :-
    petta_handles_route('&plunit_hri', [edge, bound, _], Bound, _),
    assertion(Bound == 'Refuse'),
    \+ petta_handles_route('&plunit_hri', [edge, _, _], _, _).

test(subsumption_never_binds_the_query,
     [ setup(handles_declare([handles, '&plunit_hrb', [edge, a, _], 'Exact'])),
       cleanup(handles_retract([handles, '&plunit_hrb', [edge, a, _], 'Exact'])) ]) :-
    % (edge $q b) is outside (edge a $y): routing it must not bind $q to a.
    \+ petta_handles_route('&plunit_hrb', [edge, _Q, b], _, _).

test(coherence_accepts_specificity_resolved_overlaps,
     [ setup(( handles_declare([handles, '&plunit_hco', [edge, _, _], 'Exact']),
               handles_declare([handles, '&plunit_hco', [edge, C, C], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hco', [edge, _, _], 'Exact']),
                 handles_retract([handles, '&plunit_hco', [edge, C2, C2], 'Sound']) )) ]) :-
    % The overlap exists and the repeated-variable entry wins it by
    % specificity, so there is no conflict to find.
    petta_handles_coherent('&plunit_hco').

test(coherence_throws_on_a_disagreeing_tie,
     [ setup(( handles_declare([handles, '&plunit_hct', [edge, a, _], 'Exact']),
               handles_declare([handles, '&plunit_hct', [edge, _, b], 'Sound']) )),
       cleanup(( handles_retract([handles, '&plunit_hct', [edge, a, _], 'Exact']),
                 handles_retract([handles, '&plunit_hct', [edge, _, b], 'Sound']) )),
       throws(error(petta_contract_conflict('&plunit_hct', _, _, _), _)) ]) :-
    petta_handles_coherent('&plunit_hct').

test(the_scan_only_idiom_is_coherent_and_routes_by_adornment,
     [ setup(( handles_declare([handles, '&plunit_hcb', [edge, [in, _], _], 'Refuse']),
               handles_declare([handles, '&plunit_hcb', [edge, _, _], 'Exact']) )),
       cleanup(( handles_retract([handles, '&plunit_hcb', [edge, [in, _], _], 'Refuse']),
                 handles_retract([handles, '&plunit_hcb', [edge, _, _], 'Exact']) )) ]) :-
    % The adorned entry matches strictly fewer queries, so it is the more
    % specific one: bound-subject lookups are refused, the free scan stays
    % exact, and the pair is coherent rather than a tie.
    petta_handles_coherent('&plunit_hcb'),
    petta_handles_route('&plunit_hcb', [edge, bound, _], Bound, _),
    assertion(Bound == 'Refuse'),
    petta_handles_route('&plunit_hcb', [edge, _, _], Free, _),
    assertion(Free == 'Exact').

test(strip_reports_renaming_invariant_paths) :-
    petta_adorn_strip([edge, [in, A], [in, B]], Stripped, Requirements, Paths),
    assertion(Stripped == [edge, A, B]),
    assertion(Requirements == [A, B]),
    assertion(Paths == [[1], [2]]).

test(a_narrower_pattern_outranks_any_adornment,
     [ setup(( handles_declare([handles, '&plunit_hcn', [edge, S, S], 'Sound']),
               handles_declare([handles, '&plunit_hcn', [edge, [in, _], _], 'Refuse']) )),
       cleanup(( handles_retract([handles, '&plunit_hcn', [edge, S2, S2], 'Sound']),
                 handles_retract([handles, '&plunit_hcn', [edge, [in, _], _], 'Refuse']) )) ]) :-
    % A bound self-loop query falls under both; the repeated-variable
    % pattern is narrower than the adorned one, so its claim wins.
    petta_handles_route('&plunit_hcn', [edge, a, a], Fidelity, _),
    assertion(Fidelity == 'Sound').

test(the_conflict_error_names_both_entries) :-
    message_to_string(error(petta_contract_conflict('&c', [edge, a, _],
                                                    [edge, _, b], [edge, a, b]),
                            none), Message),
    once(sub_string(Message, _, _, _, "disagree")),
    once(sub_string(Message, _, _, _, "&c")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

test(the_refusal_error_names_the_space_and_shape) :-
    message_to_string(error(petta_refused_shape('&c', [secret, s1],
                                                [secret, [in, _]]), none),
                      Message),
    once(sub_string(Message, _, _, _, "Refuse")),
    once(sub_string(Message, _, _, _, "&c")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(metta_handles_route).

:- begin_tests(relational_arithmetic).

% The four operators run BACKWARDS over integers: one unbound argument
% among integers solves for it, MeTTaLog's plus/3 compilation adopted at
% the predicate rather than the compiler, so every call site inherits it.

test(subtraction_solves_for_its_first_argument) :-
    '-'(X, 1, 4),
    X == 5.

test(addition_solves_either_slot) :-
    '+'(A, 3, 10), A == 7,
    '+'(2, B, 9),  B == 7.

test(multiplication_solves_exact_division) :-
    '*'(X, 2, 6),
    X == 3.

test(multiplication_fails_on_inexact_division, [fail]) :-
    '*'(_, 2, 7).

test(division_solves_both_directions) :-
    '/'(X, 2, 3), X == 6,
    '/'(6, B, 2), B == 3.

test(division_fails_on_inexact_backward, [fail]) :-
    '/'(7, _, 2).

test(ground_and_float_paths_are_unchanged) :-
    '+'(2, 3, R1), R1 == 5,
    '/'(7, 2.0, R2), R2 == 3.5.

test(two_unbound_arguments_still_refuse,
     [throws(error(_, _))]) :-
    '+'(_, _, _).

test(a_float_beside_a_variable_still_refuses,
     [throws(error(_, _))]) :-
    '+'(_, 1.5, _).

:- end_tests(relational_arithmetic).

:- begin_tests(inference_bound_form).

%[nondet] by design: the form answers each value of the bounded goal, so
%a choicepoint after the first is the multiplicity, not untidiness.
test(inferences_bounds_and_answers, [nondet]) :-
    metta_inferences(100000, member(X, [1, 2]), X),
    X == 1.

test(inferences_keeps_every_answer) :-
    findall(V, metta_inferences(100000, member(V, [1, 2, 3]), V), Vs),
    Vs == [1, 2, 3].

test(inferences_expiry_throws_the_reserved_envelope,
     [throws(error(metta_control_signal(inference_limit, 50), _))]) :-
    metta_inferences(50, (between(1, 100000, N), N > 99999), N).

test(inferences_refuses_a_non_positive_bound,
     [throws(error(type_error(_, _), _))]) :-
    metta_inferences(0, true, _).

:- end_tests(inference_bound_form).

:- begin_tests(scoped_pragmas).

test(with_pragma_scopes_and_restores) :-
    \+ metta_pragma('max-inferences', _),
    metta_with_pragmas([['max-inferences', 100000]], member(X, [7]), X),
    X == 7,
    \+ metta_pragma('max-inferences', _).

test(with_pragma_expiry_throws_the_reserved_envelope,
     [throws(error(metta_control_signal(inference_limit, 200), _))]) :-
    metta_with_pragmas([['max-inferences', 200]],
                       (between(1, 100000, N), N > 99999), N).

test(with_pragma_restores_after_expiry) :-
    catch(metta_with_pragmas([['max-inferences', 200]],
                             (between(1, 100000, N), N > 99999), N),
          error(metta_control_signal(inference_limit, _), _),
          true),
    \+ metta_pragma('max-inferences', _).

test(with_pragma_restores_a_previous_value) :-
    'pragma!'('max-time', 30, _),
    metta_with_pragmas([['max-time', 5]], member(X, [1]), X),
    metta_pragma('max-time', Restored),
    Restored == 30,
    'pragma!'('max-time', none, _).

test(limit_expiry_is_a_control_signal_no_recovery_catch_eats) :-
    control_exception(error(metta_control_signal(inference_limit, 200), c)),
    control_exception(error(metta_control_signal(time_limit, 1.0), c)).

test(with_pragma_refuses_a_malformed_setting,
     [throws(error(domain_error(metta_pragma_setting, _), _))]) :-
    metta_with_pragmas([broken], true, _).

test(with_pragma_refuses_an_unknown_key,
     [throws(error(domain_error(metta_pragma_key, 'invented-by-a-typo'), _))]) :-
    metta_with_pragmas([['invented-by-a-typo', 1]], true, _).

:- end_tests(scoped_pragmas).

:- begin_tests(operation_answers).

%The multiplicity and the order of BadArgType, on the arbiter's own four
%programs: one error per rejected ACTUAL type, one per declared ARROW, the two
%composing arrow-major and actual-minor, and a position whose sibling actual
%type carried the check forward still reporting its failure before the later
%position's [source: LeaTTa tests/semantics/types-basic/
%44-badargtype-per-actual.metta through 49-badargtype-widened-actuals.metta].
%Each program names its own symbols, so the five run in one space without a
%teardown between them and one case cannot inherit another's declarations.
badargtype_program("(: pa-a pa-A)\n(: pa-a pa-B)\n(: pa-g (-> pa-C Number))",
                   'pa-g', ['pa-a'],
                   [['BadArgType', 1, 'pa-C', 'pa-A'],
                    ['BadArgType', 1, 'pa-C', 'pa-B']]).
badargtype_program("(: pr-a pr-A)\n(: pr-g (-> pr-C Number))\n(: pr-g (-> pr-D Number))",
                   'pr-g', ['pr-a'],
                   [['BadArgType', 1, 'pr-C', 'pr-A'],
                    ['BadArgType', 1, 'pr-D', 'pr-A']]).
badargtype_program("(: cp-a cp-A)\n(: cp-a cp-B)\n(: cp-g (-> cp-C Number))\n(: cp-g (-> cp-D Number))",
                   'cp-g', ['cp-a'],
                   [['BadArgType', 1, 'cp-C', 'cp-A'],
                    ['BadArgType', 1, 'cp-C', 'cp-B'],
                    ['BadArgType', 1, 'cp-D', 'cp-A'],
                    ['BadArgType', 1, 'cp-D', 'cp-B']]).
badargtype_program("(: ao-a ao-A)\n(: ao-a ao-C)\n(: ao-b ao-B)\n(: ao-g (-> ao-C ao-D Number))",
                   'ao-g', ['ao-a', 'ao-b'],
                   [['BadArgType', 1, 'ao-C', 'ao-A'],
                    ['BadArgType', 2, 'ao-D', 'ao-B']]).
badargtype_program("(: wa-a wa-A)\n(:< wa-A wa-B)\n(:< wa-B wa-C)\n(: wa-g (-> wa-D Number))",
                   'wa-g', ['wa-a'],
                   [['BadArgType', 1, 'wa-D', 'wa-A'],
                    ['BadArgType', 1, 'wa-D', 'wa-B'],
                    ['BadArgType', 1, 'wa-D', 'wa-C']]).

test(badargtype_multiplicity_and_order,
     [forall(badargtype_program(Source, Operation, Arguments, Expected))]) :-
    ( silent(true) -> true ; assertz(silent(true)) ),
    process_metta_string(Source, _),
    findall(Reason,
            ( metta_operation_answer(Operation, Arguments, Answer),
              Answer = ['Error', _, Reason] ),
            Reasons),
    Reasons == Expected.

%An argument whose type does not DECIDE is not an error: the call is left as
%written, which is upstream's NoReduce, and only an operation with its own
%message answers one instead [source: LeaTTa
%tests/semantics/grounded/07-partial-core.metta, `[(+ 1 b)]` against
%`[((Error (/ 2 b) Divide expects two numbers: dividend and divisor))]`].
test(an_undecided_argument_leaves_the_call_unreduced) :-
    findall(A, metta_operation_answer('+', [1, 'plunit-undeclared'], A), Answers),
    Answers == [['+', 1, 'plunit-undeclared']].

test(an_operation_with_its_own_message_answers_it) :-
    findall(A, metta_operation_answer('/', [2, 'plunit-undeclared'], A), Answers),
    Answers == [['Error', ['/', 2, 'plunit-undeclared'],
                 "Divide expects two numbers: dividend and divisor"]].

%A chain naming one type variable twice reports the type its FIRST argument
%fixed, not the variable [source: the same file, `(== 1 a)` is
%`(BadArgType 2 Number String)` with `(: a String)`].
test(a_shared_type_variable_reports_what_the_first_argument_fixed) :-
    findall(A, metta_operation_answer('==', [1, "text"], A), Answers),
    Answers == [['Error', ['==', 1, "text"],
                 ['BadArgType', 2, 'Number', 'String']]].

%An argument whose DECLARED type is already wrong is refused where it stands,
%so the error names the call the program wrote and the argument never runs.
%The arbiter's eight effects files are built to see exactly that: each pairs a
%control with an experiment whose operand emits a marker, and the marker is
%absent for the rejected operand on hyperon 0.2.10, which type-checks a call
%before interpreting its arguments
%[source: LeaTTa tests/semantics/grounded/13-effects-arithmetic.metta through
%21-effects-strings-metatype.metta, all STATUS conforms, quoting
%hyperon-experimental@3f76dc4 interpreter.rs:1224-1258 against :1352-1395].
test(a_wrongly_typed_operand_is_named_as_written,
     [setup(( process_metta_string("(: ew-string (-> Atom String))", _),
              process_metta_string("(= (ew-string $l) \"s\")", _) ))]) :-
    process_metta_string("!(collapse (+ 1 (ew-string EW-MARK)))", [[Answer]]),
    swrite(Answer, Text),
    assertion(Text == "(Error (+ 1 (ew-string EW-MARK)) (BadArgType 2 Number String))").

test(a_wrongly_typed_operand_does_not_run,
     [ setup(( process_metta_string("(: ew-effect (-> Atom String))", _),
               process_metta_string(
                   "(= (ew-effect $l) (prog1 \"s\" (add-atom &self (ew-ran))))",
                   _) )),
       cleanup(remove_sexp('&self', ['ew-ran'])) ]) :-
    process_metta_string("!(collapse (+ 1 (ew-effect EW-MARK)))", _),
    assertion(\+ get_native_atom('&self', ['ew-ran'])).

%The other half, which is what keeps the refusal from swallowing a working
%program: an operand whose type is %Undefined% or right is evaluated exactly as
%it was, effect and all, and the call answers what it answered
%[source: the same files, whose first four lines per operation are the
%%Undefined% and Number controls].
test(an_operand_of_the_right_type_still_runs,
     [ setup(( process_metta_string("(: ew-number (-> Atom Number))", _),
               process_metta_string(
                   "(= (ew-number $l) (prog1 7 (add-atom &self (ew-number-ran))))",
                   _) )),
       cleanup(remove_sexp('&self', ['ew-number-ran'])) ]) :-
    process_metta_string("!(collapse (+ 1 (ew-number EW-MARK)))", [[Answer]]),
    assertion(Answer == 8),
    assertion(get_native_atom('&self', ['ew-number-ran'])).

test(an_undecided_operand_still_runs,
     [ setup(( process_metta_string("(: ew-undef (-> Atom %Undefined%))", _),
               process_metta_string(
                   "(= (ew-undef $l) (prog1 ew-u (add-atom &self (ew-undef-ran))))",
                   _) )),
       cleanup(remove_sexp('&self', ['ew-undef-ran'])) ]) :-
    process_metta_string("!(collapse (+ 1 (ew-undef EW-MARK)))", [[Answer]]),
    swrite(Answer, Text),
    assertion(Text == "(+ 1 ew-u)"),
    assertion(get_native_atom('&self', ['ew-undef-ran'])).

:- end_tests(operation_answers).

% A BUILT-IN MODULE is one the engine ships rather than one a program keeps in
% a file, and `!(import! &self skel)` names it directly. Upstream loads six of
% them at startup and `skel` is its own skeleton, the one that uses every tier
% at once: three declarations, one MeTTa equation, and one grounded operation
% [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, skelBuiltin,
% transcribed from upstream's builtin_mods/skel.metta and skel.rs; corpus
% tests/semantics/grounded/28-builtin-module-skel.metta, 29 and 32, all three
% STATUS conforms]. This engine resolved every import against the filesystem,
% so all three read `existence_error(source_sink, skel)`.
:- begin_tests(builtin_modules).

test(skel_admits_both_tiers_and_is_idempotent,
     [ cleanup(( forget_registered_function('skel-swap-pair-native'),
                 forget_registered_function('skel-swap-pair'),
                 remove_sexp('&self', [':', 'PairType', _]),
                 remove_sexp('&self', [':', 'Pair', _]) )) ]) :-
    %The tier discriminator before the import: an operation the engine does not
    %hold yet is a Symbol, which is the arbiter's own answer for it.
    process_metta_string("!(get-metatype skel-swap-pair-native)", Before),
    assertion(Before == ['Symbol']),
    process_metta_string("!(import! &self skel)", Imported),
    assertion(Imported == [[]]),
    process_metta_string("!(skel-swap-pair (Pair a b))", Equation),
    assertion(Equation == [['Pair', b, a]]),
    process_metta_string("!(skel-swap-pair-native (Pair a b))", Native),
    assertion(Native == [['Pair', b, a]]),
    %A repeated import is a no-op and does not duplicate the equation.
    process_metta_string("!(import! &self skel)", Again),
    assertion(Again == [[]]),
    process_metta_string("!(skel-swap-pair (Pair a b))", Once),
    assertion(Once == [['Pair', b, a]]),
    %The two tiers report what they are.
    process_metta_string("!(get-metatype skel-swap-pair)", EquationKind),
    assertion(EquationKind == ['Symbol']),
    process_metta_string("!(get-metatype skel-swap-pair-native)", NativeKind),
    assertion(NativeKind == ['Grounded']).

%A module cannot reach a built-in by its bare name, because a built-in is a
%child of the TOP and the same name written inside a module is relative to that
%module. Accepting it there would be worse than refusing: the import would
%report success while the operation stayed unreduced
%[source: LeaTTa tests/semantics/modules/35-builtin-from-module, whose STATUS
%is diverges because the two engines word the refusal differently, both
%refusing]. The two files are the arbiter's own shape: the top imports a
%module, and the MODULE writes the bare built-in name.
plunit_builtin_module_tree(Directory) :-
    tmp_file(builtin_from_module, Directory),
    make_directory(Directory),
    directory_file_path(Directory, 'usesskel.metta', Module),
    open(Module, write, ModuleStream),
    write(ModuleStream, "!(import! &self skel)\n"),
    close(ModuleStream),
    directory_file_path(Directory, 'main.metta', Main),
    open(Main, write, MainStream),
    write(MainStream, "!(import! &self usesskel)\n"),
    close(MainStream).

test(a_module_cannot_reach_a_builtin_by_its_bare_name,
     [ setup(( plunit_builtin_module_tree(Directory),
               nb_setval(plunit_builtin_dir, Directory) )),
       cleanup(( nb_getval(plunit_builtin_dir, Old),
                 delete_directory_and_contents(Old) )) ]) :-
    nb_getval(plunit_builtin_dir, Directory),
    directory_file_path(Directory, 'main.metta', Main),
    catch(( load_metta_file(Main, _), Outcome = imported ),
          error(existence_error(source_sink, Name), _),
          Outcome = refused(Name)),
    assertion(Outcome == refused(skel)).

:- end_tests(builtin_modules).

:- begin_tests(module_colon_paths).

%A module NAME may be a COLON PATH: `pkg:child` names pkg/child.metta beside
%the file that imports it, `top:` names the outermost module's directory and
%`self:` the importing module's own, which is also what a bare path means
%[source: LeaTTa tests/semantics/modules/22-path-colon, 23-path-top and
%24-path-self, all STATUS conforms].
plunit_module_tree(Top, Package, Child) :-
    tmp_file(modules, Top),
    make_directory(Top),
    atomic_list_concat([Top, '/pkg'], Package),
    make_directory(Package),
    atomic_list_concat([Package, '/child.metta'], Child),
    setup_call_cleanup(open(Child, write, Out),
                       write(Out, '(path-value colon)\n'),
                       close(Out)).

test(a_colon_path_names_a_file_beside_the_importer) :-
    plunit_module_tree(Top, _, Child),
    setup_call_cleanup(
        asserta(filereader:working_dir(Top)),
        ( resolve_metta_import_path('pkg:child', Colon),
          resolve_metta_import_path('top:pkg:child', FromTop),
          same_file(Colon, Child),
          same_file(FromTop, Child) ),
        ( retract(filereader:working_dir(Top)),
          delete_directory_and_contents(Top) )).

%Two modules deep, where the three bases stop agreeing: `self:` and a bare
%path follow the INNER directory while `top:` follows the outer one.
test(self_and_top_name_different_directories) :-
    plunit_module_tree(Top, Package, Child),
    setup_call_cleanup(
        ( asserta(filereader:working_dir(Top)),
          asserta(filereader:working_dir(Package)) ),
        ( resolve_metta_import_path('self:child', Self),
          resolve_metta_import_path('top:pkg:child', FromTop),
          same_file(Self, Child),
          same_file(FromTop, Child),
          \+ catch(resolve_metta_import_path('pkg:child', _), _, fail) ),
        ( retract(filereader:working_dir(Package)),
          retract(filereader:working_dir(Top)),
          delete_directory_and_contents(Top) )).

%A name carrying a separator already is a PATH and is left alone, so nothing
%that resolved before starts resolving somewhere else.
test(a_written_path_is_not_rewritten) :-
    plunit_module_tree(Top, _, Child),
    setup_call_cleanup(
        asserta(filereader:working_dir(Top)),
        ( resolve_metta_import_path('pkg/child', Written),
          same_file(Written, Child) ),
        ( retract(filereader:working_dir(Top)),
          delete_directory_and_contents(Top) )).

:- end_tests(module_colon_paths).

:- begin_tests(module_inclusion).

%`include` PASTES a module's source into the space that included it and
%answers what its LAST directive answered, where import! gives the file its
%own space and answers unit [source: LeaTTa
%MettaHyperonFull/Minimal/Interpreter.lean, the include dispatch;
%tests/semantics/modules/04-include-no-directive.metta and
%05-include-directive.metta].
plunit_include_tree(Top, Quiet, Loud) :-
    tmp_file(include, Top),
    make_directory(Top),
    atomic_list_concat([Top, '/quiet.metta'], Quiet),
    atomic_list_concat([Top, '/loud.metta'], Loud),
    setup_call_cleanup(open(Quiet, write, QuietOut),
                       write(QuietOut, '(= (plunit-included) pasted)\n'),
                       close(QuietOut)),
    setup_call_cleanup(open(Loud, write, LoudOut),
                       write(LoudOut,
                             '(= (plunit-included-loud) pasted)\n!(+ 1 2)\n'),
                       close(LoudOut)).

test(include_pastes_a_module_and_answers_its_last_directive,
     [setup(( silent(true) -> true ; assertz(silent(true)) ))]) :-
    plunit_include_tree(Top, _, _),
    setup_call_cleanup(
        asserta(filereader:working_dir(Top)),
        ( findall(A, include(quiet, A), Quiet),
          findall(A, include(loud, A), Loud),
          Quiet == [],
          Loud == [3],
          process_metta_string("!(plunit-included)", Quietly),
          process_metta_string("!(plunit-included-loud)", Loudly),
          Quietly == [pasted],
          Loudly == [pasted] ),
        ( retract(filereader:working_dir(Top)),
          delete_directory_and_contents(Top) )).

%`self` and `top` are BASES rather than modules, and a name that resolves to
%nothing is refused in upstream's own words [measured 2026-08-19 against the
%arbiter: `!(include nosuchfile)` answers
%`(Error (include nosuchfile) no module named nosuchfile is available)`].
test(include_refuses_a_base_and_a_name_that_resolves_to_nothing) :-
    findall(A, include(self, A), Base),
    Base == [['Error', [include, self],
              "include: the running context is not a module"]],
    findall(A, include('plunit-no-such-module', A), Missing),
    Missing == [['Error', [include, 'plunit-no-such-module'],
                 "no module named plunit-no-such-module is available"]].

:- end_tests(module_inclusion).

:- begin_tests(runtime_format_strings).

%format-args interpolates through the dyn_fmt crate's Arguments, not Rust's
%own format!, and that formatter is looser than it looks: a `}` in the literal
%state is dropped and the character after it taken literally, a `}` in the
%argument state consumes the next argument or produces NOTHING once they run
%out, and any other character there ends the argument and is taken literally
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, formatPiece and
%formatArg; measured 2026-08-19 against the arbiter, each row below].
format_case("Probability of {} is {}%", [head, 50],
            "Probability of head is 50%").
format_case("{} and {}", [only], "only and ").
format_case("{}", [a, b, c], "a").
format_case("{{}}{}", [1], "{}1").
format_case("{x}{}", [1, 2], "x{").
format_case("a{}b", ["s"], "asb").
format_case("{", [1], "").
format_case("no holes", [1], "no holes").

test(format_args_follows_the_arbiters_formatter,
     [forall(format_case(Format, Arguments, Expected))]) :-
    'format-args'(Format, Arguments, Out),
    Out == Expected.

%A first argument that is not a format string earns the long text, a second
%that is not an expression earns the conversion's own, and a DECIDED wrong
%type earns a BadArgType before either [source: the same file, formatArgsOp's
%three cases; LeaTTa tests/semantics/grounded/07-partial-core.metta].
test(format_args_words_its_refusal_by_which_argument_is_wrong) :-
    'format-args'(not-a-format, [], First),
    First == ['Error', ['format-args', not-a-format, []],
              "format-args expects format string as a first argument and expression as a second argument"],
    'format-args'("{}", not-an-expression, Second),
    Second == ['Error', ['format-args', "{}", not-an-expression],
               "Atom is not an ExpressionAtom"],
    findall(R, 'format-args'(1, [], R), Decided),
    Decided == [['Error', ['format-args', 1, []],
                 ['BadArgType', 1, 'String', 'Number']]].

test(sort_strings_sorts_strings_and_refuses_anything_else) :-
    'sort-strings'(["pear", "apple", "fig", "apple"], Sorted),
    Sorted == ["apple", "apple", "fig", "pear"],
    'sort-strings'([a, b], Symbols),
    Symbols == ['Error', ['sort-strings', [a, b]],
                "sort-strings expects expression with strings as a first argument"],
    findall(R, 'sort-strings'("text", R), Decided),
    Decided == [['Error', ['sort-strings', "text"],
                 ['BadArgType', 1, 'Expression', 'String']]].

:- end_tests(runtime_format_strings).

:- begin_tests(interpreter_pragmas).

%An unsupported name cannot pretend it changed evaluation.
test(pragma_refuses_an_unknown_key,
     [throws(error(domain_error(metta_pragma_key,
                                'completely-invented-key'), _))]) :-
    'pragma!'('completely-invented-key', 42, _).

test(pragma_answers_unit_for_a_known_key) :-
    'pragma!'('type-check', auto, Known),
    Known == [],
    'pragma!'('type-check', none, _).

test(pragma_answers_unit_for_an_enforced_key) :-
    'pragma!'('max-inferences', 100000, Result),
    Result == [],
    metta_pragma('max-inferences', 100000),
    'pragma!'('max-inferences', none, _).

%The one key the arbiter validates, and the whole of what it validates
%[measured 2026-08-19 against the arbiter: `abc`, `1.5` and `-1` each answer
%the error below, while (pragma! type-check -1) answers unit; the unknown-key
%case is the engine-registry divergence pinned separately above].
test(max_stack_depth_answers_its_own_error_for_a_value_that_is_not_a_count,
     [forall(member(Bad, [-1, 1.5, abc]))]) :-
    'pragma!'('max-stack-depth', Bad, Result),
    Result == ['Error', ['pragma!', 'max-stack-depth', Bad],
               'UnsignedIntegerIsExpected'],
    \+ metta_pragma('max-stack-depth', _).

test(max_stack_depth_accepts_a_count) :-
    'pragma!'('max-stack-depth', 0, Result),
    Result == [],
    metta_pragma('max-stack-depth', 0),
    'pragma!'('max-stack-depth', none, _),
    \+ metta_pragma('max-stack-depth', _).

test(max_time_refuses_invalid_values_without_replacing_the_bound,
     [ forall(member(Bad, [not-a-number, 0, -1])),
       setup('pragma!'('max-time', 30, _)),
       cleanup('pragma!'('max-time', none, _)) ]) :-
    catch('pragma!'('max-time', Bad, _), Error, true),
    assertion(Error = error(domain_error(metta_pragma_value,
                                         ['max-time', Bad]), _)),
    assertion(metta_pragma('max-time', 30)).

test(max_inferences_refuses_invalid_values_without_replacing_the_bound,
     [ forall(member(Bad, [not-a-number, 0, -1, 1.5])),
       setup('pragma!'('max-inferences', 100000, _)),
       cleanup('pragma!'('max-inferences', none, _)) ]) :-
    catch('pragma!'('max-inferences', Bad, _), Error, true),
    assertion(Error = error(domain_error(metta_pragma_value,
                                         ['max-inferences', Bad]), _)),
    assertion(metta_pragma('max-inferences', 100000)).

test(scoped_pragmas_preflight_all_values_before_changing_any_setting,
     [ setup('pragma!'('max-time', 30, _)),
       cleanup('pragma!'('max-time', none, _)) ]) :-
    catch(metta_with_pragmas([['max-time', 5], ['max-inferences', 0]],
                             true, _),
          Error, true),
    assertion(Error = error(domain_error(metta_pragma_value,
                                         ['max-inferences', 0]), _)),
    assertion(metta_pragma('max-time', 30)),
    assertion(\+ metta_pragma('max-inferences', _)).

:- end_tests(interpreter_pragmas).

%petta_transaction/1 at the predicate level, where the answer set is a plain
%Prolog one and no MeTTa reduction stands between the goal and the count.
:- begin_tests(transaction_answers).

:- dynamic tx_probe/1.

test(a_transaction_yields_every_solution_of_its_goal) :-
    findall(X, petta_transaction(member(X, [a,b,c])), Answers),
    assertion(Answers == [a,b,c]).

test(a_goal_with_no_solution_fails_the_transaction) :-
    assertion(\+ petta_transaction(fail)),
    assertion(\+ petta_transaction(member(_, []))).

%Every solution's writes are inside the one transaction, so they land
%together or not at all. retractall/1 rather than a fixture, because a
%rolled-back transaction must leave the store exactly as it found it.
test(every_solution_writes_inside_the_one_transaction) :-
    retractall(tx_probe(_)),
    findall(X, petta_transaction(( member(X, [1,2,3]),
                                   assertz(tx_probe(X)) )), Answers),
    assertion(Answers == [1,2,3]),
    findall(P, tx_probe(P), Written),
    assertion(Written == [1,2,3]),
    retractall(tx_probe(_)).

test(a_failure_after_several_writes_undoes_all_of_them) :-
    retractall(tx_probe(_)),
    assertion(\+ petta_transaction(( member(X, [1,2,3]),
                                     assertz(tx_probe(X)),
                                     fail ))),
    findall(P, tx_probe(P), Written),
    assertion(Written == []).

test(a_throw_after_several_writes_undoes_all_of_them) :-
    retractall(tx_probe(_)),
    catch(petta_transaction(( member(X, [1,2,3]),
                              assertz(tx_probe(X)),
                              throw(tx_boom) )),
          Thrown, true),
    assertion(Thrown == tx_boom),
    findall(P, tx_probe(P), Written),
    assertion(Written == []).

%A nested transaction runs inside the outer one and collects for the same
%reason: SWI's transaction/1 is once-like at every depth.
test(a_nested_transaction_yields_every_solution_too) :-
    findall(X, petta_transaction(petta_transaction(member(X, [a,b]))),
            Answers),
    assertion(Answers == [a,b]).

:- end_tests(transaction_answers).

%The generated probe P1.7 and P1.8 ask for: every position the engine's own
%type surface declares strict, on a builtin PeTTa defines, called with that
%position unbound and the rest filled. The table is guarded_input_position/3,
%so this cannot go stale by hand: declaring a type for a new builtin adds a
%row here in the same stroke.
:- begin_tests(builtin_input_guards).

guard_filler('Expression', [a, b]) :- !.
guard_filler('Number', 1) :- !.
guard_filler('BigInt', 9223372036854775808) :- !.
guard_filler('String', "s") :- !.
guard_filler('Bool', true) :- !.
guard_filler('Symbol', '&probe-space') :- !.
guard_filler('Variable', '$probevar') :- !.
guard_filler(_, a).

%The outcome of calling Name/Arity with Position unbound: `ok` when it refused
%and named the MeTTa operation, and otherwise a description of what it did
%instead. A one-second limit, because two of these used to enumerate every
%list there is.
guard_outcome(Name, Arity, Position, Outcome) :-
    seam:builtin_type_declaration(Name, ['->'|Chain]),
    append(Inputs, [_], Chain),
    length(Chain, Arity),
    findall(Value,
            ( nth1(Index, Inputs, Type),
              ( Index =:= Position -> true ; guard_filler(Type, Value) ) ),
            Filled),
    append(Filled, [Out], Args),
    Goal =.. [Name|Args],
    nth1(Position, Filled, Hole),
    copy_term(Hole, Before),
    (   catch(call_with_time_limit(1, catch(Goal, Error, true)),
              time_limit_exceeded, Error = guard_probe_timeout)
    ->  (   nonvar(Error)
        ->  guard_refusal(Error, Name, Outcome)
        ;   guard_success(Hole, Before, Out, Name, Outcome)
        )
    ;   Outcome = 'failed silently'
    ).

guard_refusal(guard_probe_timeout, _, 'ran away') :- !.
guard_refusal(error(resource_error(R), _), _, Outcome) :- !,
    format(atom(Outcome), "exhausted ~w", [R]).
guard_refusal(error(_, context(Named, _)), Name, ok) :- Named == Name, !.
guard_refusal(error(Formal, Context), _, Outcome) :-
    format(atom(Outcome), "refused as ~q in ~q, which is not its own name",
           [Formal, Context]).

guard_success(Hole, Before, _, _, Outcome) :- nonvar(Hole), var(Before), !,
    format(atom(Outcome), "bound its own input to ~q", [Hole]).
guard_success(_, _, Out, _, 'answered a fresh variable') :- var(Out), !.
guard_success(_, _, Out, Name, ok) :-
    Out = ['Error', [Named|_], _], Named == Name, !.
guard_success(_, _, Out, _, Outcome) :-
    format(atom(Outcome), "answered ~q", [Out]).

test(every_builtin_refuses_an_unbound_input_by_name) :-
    findall(Name-Arity-Position, guarded_input_position(Name, Arity, Position),
            Rows0),
    sort(Rows0, Rows),
    %A table that emptied itself would pass every assertion below.
    length(Rows, Count),
    assertion(Count >= 80),
    findall(Name/Arity-Position-Outcome,
            ( member(Name-Arity-Position, Rows),
              guard_outcome(Name, Arity, Position, Outcome),
              Outcome \== ok ),
            Wrong),
    assertion(Wrong == []).

%The explicit residue register stays defined and empty, so a later exception
%cannot silently disappear by deleting the completeness question.
test(test_the_residual_positions_refuse_by_their_own_names) :-
    assertion(\+ unguarded_input_position(_, _)).

:- end_tests(builtin_input_guards).


:- begin_tests(metta_has_declared_type).

% A witness, never a consistency judgement: a declaration answers True, and
% an atom nothing declares answers False for every type.
test(a_declaration_witnesses_and_absence_answers_false,
     [ setup(process_metta_string("(: hdt-probe HDT)", _)),
       cleanup(metta_remove_atom('&self', [':', 'hdt-probe', 'HDT'], _)) ]) :-
    'has-declared-type'('hdt-probe', 'HDT', R1), R1 == true,
    'has-declared-type'('hdt-probe', 'Other', R2), R2 == false,
    'has-declared-type'(unheralded, 'HDT', R3), R3 == false.

test(unbound_inputs_are_refused,
     [ throws(error(petta_unbound_input('has-declared-type', 1), _)) ]) :-
    'has-declared-type'(_, 'HDT', _).

test(an_unbound_type_is_refused,
     [ throws(error(petta_unbound_input('has-declared-type', 2), _)) ]) :-
    'has-declared-type'('hdt-probe', _, _).

:- end_tests(metta_has_declared_type).


:- begin_tests(translator_rule_protected_core).

% The measured harm, as a unit test: a translator rule is consulted one line
% before translator:translate_special_dl/5, so before the refusal existed this
% registration made `if` mean whatever the rule said, for the whole process.
test(a_protected_core_head_is_refused_with_its_name,
     [ throws(error(permission_error(register, metta_protected_core, if), _)) ]) :-
    'add-translator-rule!'(if, _).

test(every_protected_head_refuses) :-
    findall(Name,
            ( protected_core_head(Name),
              \+ catch('add-translator-rule!'(Name, _),
                       error(permission_error(register, metta_protected_core,
                                              Name), _),
                       true) ),
            Accepted),
    assertion(Accepted == []).

% The other half: a head the compiler also gives meaning to but does not
% protect stays the program's to take over, and the register says what it
% went ahead of. lib/lib_derived.metta ships exactly this rule for `once`.
test(an_unprotected_special_form_is_taken_over_and_the_register_says_so,
     [ cleanup(( 'remove-translator-rule!'(once, _),
                 retractall(translator_rule_override(once, _)) )) ]) :-
    'add-translator-rule!'(once, R),
    assertion(R == true),
    assertion(translator_rule_override(once, special_form)).

% A name that meant nothing before records nothing, so an empty register
% reads as "this rule took nothing over" rather than as "nobody looked".
test(a_free_name_records_no_override,
     [ cleanup('remove-translator-rule!'('plunit-p215-free', _)) ]) :-
    'add-translator-rule!'('plunit-p215-free', _),
    assertion(\+ translator_rule_override('plunit-p215-free', _)).

:- end_tests(translator_rule_protected_core).


:- begin_tests(translator_rule_direction).

% Reading a rule backwards has preconditions and each one is CHECKED, so a
% declaration that cannot be honoured says which precondition stopped it
% rather than registering a rule that does not fire.
plant(Text) :- process_metta_string(Text, _).

uninvertible(Text, Name, Reason) :-
    plant(Text),
    catch('add-translator-rule!'(Name, [[direction, bidirectional]], _),
          error(petta_uninvertible_rule(Name, Got), _),
          true),
    Reason = Got.

test(a_computed_expansion_cannot_be_read_backwards) :-
    uninvertible("(= (p2b-computed $x) (cons 1 $x))", 'p2b-computed', Reason),
    assertion(Reason == computed_expansion).

test(an_expansion_that_is_not_a_form_cannot_be_read_backwards) :-
    uninvertible("(= (p2b-bare $x) (noeval $x))", 'p2b-bare', Reason),
    assertion(Reason == expansion_is_not_a_form).

% Twee keeps an unorientable equation only when both sides carry the same set
% of variables; a side that invents one leaves it unbound the other way round.
test(a_variable_on_one_side_only_cannot_be_read_backwards) :-
    uninvertible("(= (p2b-drops $x $y) (noeval (kept $x)))", 'p2b-drops', Reason),
    assertion(Reason == extra_variables).

test(a_rule_that_is_its_own_inverse_is_refused) :-
    uninvertible("(= (p2b-swap $x $y) (noeval (p2b-swap $y $x)))", 'p2b-swap',
                 Reason),
    assertion(Reason == inverse_is_the_rule_itself).

test(an_inverse_rooted_at_a_protected_head_is_refused,
     [ setup(plant("(= (p2b-hijack $x $y $z) (noeval (if $x $y $z)))")),
       throws(error(permission_error(register, metta_protected_core, if), _)) ]) :-
    'add-translator-rule!'('p2b-hijack', [[direction, bidirectional]], _).

test(a_rule_with_no_equation_cannot_be_read_backwards,
     [ throws(error(existence_error(translator_rule_equation,
                                    'p2b-equationless'), _)) ]) :-
    'add-translator-rule!'('p2b-equationless', [[direction, bidirectional]], _).

test(an_unknown_declaration_is_refused,
     [ throws(error(domain_error(translator_rule_declaration,
                                 [speed, fast]), _)) ]) :-
    'add-translator-rule!'('p2b-unknown', [[speed, fast]], _).

test(a_declaration_written_twice_is_refused,
     [ throws(error(petta_repeated_translator_rule_declaration(direction), _)) ]) :-
    'add-translator-rule!'('p2b-twice',
                           [[direction, forward], [direction, bidirectional]], _).

test(a_second_declaration_for_one_name_is_refused,
     [ setup('add-translator-rule!'('p2b-once-only', _)),
       cleanup('remove-translator-rule!'('p2b-once-only', _)),
       throws(error(petta_duplicate_translator_rule('p2b-once-only', []), _)) ]) :-
    'add-translator-rule!'('p2b-once-only', [[direction, forward]], _).

:- end_tests(translator_rule_direction).


:- begin_tests(translator_rule_refusal).

% The words are recorded WITH the call that was declined, so an author asking
% why a rewrite did not happen gets the reason and the site, not one of them.
test(a_decline_records_its_reason_and_the_call_it_declined,
     [ setup(process_metta_string("(: p2b-guarded (-> Atom %Undefined%))
(= (p2b-guarded (over $n))
   (if (> $n 10) (refuse \"over ten\") (noeval (kept $n))))
(= (p2b-guarded $x) (noeval (noeval (p2b-guarded $x))))", _)),
       cleanup(( 'remove-translator-rule!'('p2b-guarded', _),
                 retractall(translator_rule_refusal('p2b-guarded', _, _)) )) ]) :-
    'add-translator-rule!'('p2b-guarded', _),
    process_metta_string("!(p2b-guarded (over 3))", Kept),
    assertion(Kept == [[kept, 3]]),
    assertion(\+ translator_rule_refusal('p2b-guarded', _, _)),
    process_metta_string("!(p2b-guarded (over 99))", Declined),
    assertion(Declined == [['p2b-guarded', [over, 99]]]),
    translator_rule_refusal('p2b-guarded', Reason, Call),
    assertion(Reason == "over ten"),
    assertion(Call == ['p2b-guarded', [over, 99]]).

:- end_tests(translator_rule_refusal).


:- begin_tests(translator_rule_cost_and_conjunction).

% A cost is the measure a bidirectional rewrite has to lower, so it has to be
% a natural number or the descent it is supposed to make is not well founded.
test(a_negative_cost_is_refused,
     [ throws(error(domain_error(translator_rule_declaration, [cost, -1]), _)) ]) :-
    'add-translator-rule!'('p2b-cheap', [[cost, -1]], _).

test(a_fractional_cost_is_refused,
     [ throws(error(domain_error(translator_rule_declaration, [cost, 2.5]), _)) ]) :-
    'add-translator-rule!'('p2b-fractional', [[cost, 2.5]], _).

% A declared cost prices the HEAD, and the form's cost is that plus its
% children's, which is how an extractor's cost function folds.
test(a_declared_cost_prices_every_form_headed_by_the_name,
     [ setup(( process_metta_string("(= (p2b-priced $x) (noeval (p2b-priced $x)))", _),
               'add-translator-rule!'('p2b-priced', [[cost, 40]], _) )),
       cleanup('remove-translator-rule!'('p2b-priced', _)) ]) :-
    translator_rules:translator_form_cost(['p2b-priced', 7], Priced),
    assertion(Priced == 41),
    translator_rules:translator_form_cost([unpriced, 7], Plain),
    assertion(Plain == 2).

test(a_left_side_without_a_right_side_is_refused,
     [ throws(error(petta_conjunctive_left_side('p2b-halfrule', right), _)) ]) :-
    'add-translator-rule!'('p2b-halfrule',
                           [[left, [['p2b-halfrule', _]]]], _).

test(a_right_side_without_a_left_side_is_refused,
     [ throws(error(petta_conjunctive_left_side('p2b-orphan', missing), _)) ]) :-
    'add-translator-rule!'('p2b-orphan', [[right, [answer]]], _).

% The first pattern of a conjunctive left side is the call being rewritten, so
% a left side rooted at somebody else's name would register a rule that can
% never fire.
test(a_left_side_rooted_elsewhere_is_refused,
     [ throws(error(petta_conjunctive_left_side('p2b-misrooted',
                                                [elsewhere, _]), _)) ]) :-
    'add-translator-rule!'('p2b-misrooted',
                           [[left, [[elsewhere, _]]], [right, [answer]]], _).

test(a_conjunctive_left_side_cannot_be_read_backwards,
     [ throws(error(petta_uninvertible_rule(left, conjunctive_left_side), _)) ]) :-
    'add-translator-rule!'('p2b-bothways',
                           [[left, [['p2b-bothways', _]]], [right, [answer]],
                            [direction, bidirectional]], _).

% Two spellings of one declaration differ only in the variables their patterns
% happen to hold, so re-registering with a fresh copy is the no-op it always
% was rather than a conflicting redeclaration.
test(a_declaration_repeated_with_fresh_variables_is_the_same_declaration,
     [ setup(process_metta_string("(= (p2b-variant $x) (noeval (kept $x)))", _)),
       cleanup('remove-translator-rule!'('p2b-variant', _)) ]) :-
    'add-translator-rule!'('p2b-variant',
                           [[left, [['p2b-variant', First]]], [right, [kept, First]]],
                           _),
    'add-translator-rule!'('p2b-variant',
                           [[left, [['p2b-variant', Second]]], [right, [kept, Second]]],
                           Again),
    assertion(Again == true).

:- end_tests(translator_rule_cost_and_conjunction).


:- begin_tests(translator_rule_extra_variables_exemption).

% An exemption without a reason is a silenced check, so the declaration form
% requires one and a bare flag is not a declaration this registry knows.
test(an_exemption_without_a_reason_is_not_a_declaration,
     [ throws(error(domain_error(translator_rule_declaration,
                                 ['extra-variables-exempt']), _)) ]) :-
    'add-translator-rule!'('p2b-bare-exemption',
                           [['extra-variables-exempt']], _).

test(an_exemption_records_the_reason_it_was_given,
     [ setup(process_metta_string("(= (p2b-invents $x) (noeval (pair $x $y)))", _)),
       cleanup('remove-translator-rule!'('p2b-invents', _)) ]) :-
    'add-translator-rule!'('p2b-invents',
                           [['extra-variables-exempt', "the second is a binder"]],
                           _),
    translator_rule_extra_variables_exempt('p2b-invents', Reason),
    assertion(Reason == "the second is a binder"),
    assertion(\+ translator_rule_extra_variables_exempt('p2b-invents-not', _)).

:- end_tests(translator_rule_extra_variables_exemption).
