% Purpose: provide representation, parsing, grounded-operation errors, and numeric term recovery
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%%%%%%%%% Standard Library for MeTTa %%%%%%%%%%

%%% Representation and parsing conversions: %%%
id(X, X).
%noeval is the Atom mask on both sides: the declaration in
%lib/lib_builtin_types.metta stops the argument being reduced on the way in and
%its Atom return type stops the answer being reduced on the way out, so the
%body is the identity and the types are the whole implementation. That is how
%the reference defines it [source: metta-lang-docs, types_basics/metatypes:
%"This is the way noeval function is implemented"].
noeval(X, X).
repr(Term, R) :- sdisplay(Term, Text), R = Text.
repra(Term, R) :- term_to_atom(Term, R).
parse(Str, _) :- var(Str), !, refuse_unbound_input(parse, 1).
parse(Str, R) :- sread(Str, R).

%%% What a grounded operation answers when it cannot compute: %%%
%
%MeTTa's error channel is an ANSWER and not an exception. `(Error <call>
%<reason>)` is a value a program can test with if-error, compare with
%assertEqual and pass on, and the FORM AFTER IT STILL RUNS; a raise here ended
%the whole file instead, which is why eleven of the arbiter's grounded
%transcripts stopped at their first probe. So an operation handed an argument
%it cannot use answers, and which answer is decided by the argument's own type:
%
%  - a type the parameter RULES OUT is `(BadArgType <position> <expected>
%    <actual>)`, one answer per rejected actual type, positions left to right
%  - an argument whose type does not DECIDE, %Undefined% or a symbol declared
%    the right type but carrying no value, is the operation's own refusal: its
%    message where upstream gives it one, and otherwise the call left as
%    written, which is upstream's NoReduce
%
%[source: LeaTTa tests/semantics/grounded/07-partial-core.metta and
%08-partial-math.metta, both STATUS conforms and both byte-for-byte
%transcripts; tests/semantics/types-basic/44 through 49 for the multiplicity]
%[tested: operation_answers].
%
%NOTHING HERE IS ON A HOT PATH. Every caller reaches it only after its own
%ground fast path has already declined, so the type lookups below are paid by
%the call that was about to fail and by no other.
metta_operation_answer(Operation, Arguments, Answer) :-
    (   metta_error_operand(Arguments, Produced)
    ->  Answer = Produced
    ;   findall(Error,
                metta_bad_argument_error(Operation, Arguments, Error), Errors),
        (   Errors == []
        ->  (   metta_operation_refusal(Operation, Arguments, Message)
            ->  metta_error_atom(Operation, Arguments, Message, Answer)
            ;   Answer = [Operation|Arguments]
            )
        ;   member(Answer, Errors)
        )
    ).

%An operand that already IS an error atom finishes the call with that atom,
%unchanged, rather than being reported as an ErrorType argument: `(+ 1 (+ 1
%"bad"))` is `(Error (+ 1 "bad") (BadArgType 2 Number String))` and not a
%second error naming the first. That is the arbiter's rule for an operand the
%evaluation PRODUCED
%[source: LeaTTa tests/semantics/control-stdlib/07_error.metta, STATUS
%conforms: "A BadArgType raised while preparing a nested call must emerge
%unchanged"]. An operand WRITTEN as an error atom keeps the other reading,
%`(+ (Error source message) 1)` is `(BadArgType 1 Number ErrorType)`, and
%never reaches here: its static type is ErrorType, so refused_argument_call/2
%rejects the call at compile time and dispatch_mismatch_result/3 answers first
%[tested: test_the_error_vocabulary_answers_what_the_arbiter_answers].
%
%The head is COMPARED and the spine only inspected, never unified, so an
%ordinary expression holding an unbound variable in head position is left
%exactly as it was; unifying it bound that variable to the symbol Error.
metta_error_operand([A|_], A) :-
    nonvar(A), A = [Head|Tail], Head == 'Error', nonvar(Tail), !.
metta_error_operand([_|As], Error) :- metta_error_operand(As, Error).

metta_error_atom(Operation, Arguments, Reason,
                 ['Error', [Operation|Arguments], Reason]).

%A declared refusal retains both names: the rule that made the decision and
%the reason its author supplied. The ordinary BadArgType shape remains exact
%for shipped mismatches; only this user-declared case carries the fifth field
%[tested: test_a_user_typing_rule_participates_like_a_shipped_one;
%commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%THE GUARD IS ASKED ONCE. Both refusal shapes below opened with the same
%\+ metta_call_accepted/2, so an ACCEPTED call, which is every ordinary one,
%asked it twice: the first clause's negation failed and the second put the
%identical question again. metta_call_accepted/2 runs metta_arguments_match/3,
%which walks each argument's type, so on a term nested d deep that was two full
%walks per level and the compiled form emits one of these per level.
%The guard is a pure test that binds nothing, so hoisting it decides once and
%the two refusal shapes are tried underneath it, in the order they had.
metta_bad_argument_error(Operation, Arguments, Error) :-
    \+ metta_call_accepted(Operation, Arguments),
    metta_bad_argument_refusal(Operation, Arguments, Error).

metta_bad_argument_refusal(Operation, Arguments, Error) :-
    metta_operation_parameters(Operation, Arguments, ParameterTypes, Origins),
    current_metta_module(Module),
    metta_named_rule_refusal(Module, ParameterTypes, Origins, Arguments, 1,
                             Position, Expected, Actual, Rule, Reason),
    !,
    metta_error_atom(Operation, Arguments,
                     ['BadArgType', Position, Expected, Actual,
                      ['TypingRuleRefusal', Rule, Reason]], Error).

%One error per declared ARROW and per rejected ACTUAL type, arrows in
%declaration order and actual types in the order get-type reports them, which
%is the multiplicity and the order the arbiter pins.
metta_bad_argument_refusal(Operation, Arguments, Error) :-
    metta_operation_parameters(Operation, Arguments, ParameterTypes, Origins),
    metta_bad_argument(ParameterTypes, Origins, Arguments, 1,
                       Position, Expected, Actual),
    metta_error_atom(Operation, Arguments,
                     ['BadArgType', Position, Expected, Actual], Error).

metta_named_rule_refusal(Module, [Expected|_], [Origin|_],
                         [Argument|_], Position,
                         Position, Expected, Actual, Rule, Reason) :-
    typing_origin_family(Origin, Family),
    typing_refusal_actual(Module, Family, Argument, Actual),
    typing_rule_refusal(Module, Family, Actual, Expected, Rule, Reason).
metta_named_rule_refusal(Module, [_|Expected], [_|Origins], [_|Arguments], N,
                         Position, Reported, Actual, Rule, Reason) :-
    Next is N + 1,
    metta_named_rule_refusal(Module, Expected, Origins, Arguments, Next,
                             Position, Reported, Actual, Rule, Reason).

typing_origin_family(derived_variable, derived) :- !.
typing_origin_family(metatype, metatype) :- !.
typing_origin_family(_, ordinary).

typing_refusal_actual(_, metatype, Argument, Actual) :-
    metatype_of(Argument, Actual).
typing_refusal_actual(Module, Family, Argument, Actual) :-
    Family \== metatype,
    metta_argument_types_in(Module, Argument, Types),
    member(Actual, Types).

%Nothing is reported when SOME declared arrow takes every argument under ONE
%consistent assignment, even where another arrow, or another of an argument's
%own types, does not. Measured 2026-08-19 against the arbiter: with
%`(: a A)`, `(: a C)`, `(: b D)` and `(: g (-> C D Number))`, `!(g a b)`
%answers `[(g a b)]` and reports nothing, while the same program with
%`(: b B)` answers both `(BadArgType 1 C A)` and `(BadArgType 2 D B)`; and
%with two arrows where the second fits, `!(g a)` answers `[7]`.
%
%The search backtracks over each argument's types because that is what makes
%the assignment CONSISTENT: a chain naming one type variable twice is only
%accepted by a pair of types that agree.
metta_call_accepted(Operation, Arguments) :-
    metta_operation_parameters(Operation, Arguments, ParameterTypes, Origins),
    metta_arguments_match(ParameterTypes, Origins, Arguments),
    !.

%A compile-time refusal may use only the immediate types the shallow reader
%can prove. An unknown argument is compatible here: refusing it would turn a
%missing proof into a type error, while its nested call site or the runtime
%check can still decide it later. Shared formal variables remain shared across
%the walk, so two known arguments must still make one consistent assignment.
metta_arguments_match_shallow([], [], []).
metta_arguments_match_shallow([Expected|Rest], [Origin|Origins],
                              [Argument|Arguments]) :-
    (   Origin == metatype,
        satisfies_metatype(Argument, Expected)
    ->  true
    ;   shallow_argument_types(Argument, Types)
    ->  member(Actual, Types),
        metta_argument_type_matches(Actual, Expected, Origin)
    ;   true
    ),
    metta_arguments_match_shallow(Rest, Origins, Arguments).

metta_shallow_call_accepted(Operation, Arguments) :-
    metta_shallow_operation_parameters(Operation, Arguments,
                                       ParameterTypes, Origins),
    metta_arguments_match_shallow(ParameterTypes, Origins, Arguments),
    !.

%A refusal is proven only when at least one declaration has this arity and no
%such declaration accepts the immediate argument types. Double negation keeps
%the compile-time question from binding the source term or a declaration's
%type variables.
metta_shallow_call_refused(Operation, Arguments) :-
    \+ \+ ( \+ metta_shallow_call_accepted(Operation, Arguments),
            metta_shallow_operation_parameters(Operation, Arguments, _, _) ).

metta_arguments_match([], [], []).
metta_arguments_match([Expected|Rest], [Origin|Origins],
                      [Argument|Arguments]) :-
    check_argument_type(Argument, Expected, Origin),
    metta_arguments_match(Rest, Origins, Arguments).

metta_arguments_match_in(_, [], [], []).
metta_arguments_match_in(Module, [Expected|Rest], [Origin|Origins],
                         [Argument|Arguments]) :-
    check_argument_type_in(Module, Argument, Expected, Origin),
    metta_arguments_match_in(Module, Rest, Origins, Arguments).

%A FRESH copy per arrow: a chain naming a type variable has to be free to bind
%it again for the next call, and for the next arrow.
metta_operation_parameters(Operation, Arguments, ParameterTypes, Origins) :-
    current_metta_module(Module),
    (   type_declaration_in(Module, Operation, Chain0)
    ;   \+ type_declaration_in(Module, Operation, _),
        seam:builtin_type_declaration(Operation, Chain0)
    ),
    copy_term(Chain0, [->|Types]),
    append(ParameterTypes, [_], Types),
    metta_argument_type_origins(ParameterTypes, Origins),
    same_length(ParameterTypes, Arguments).

metta_shallow_operation_parameters(Operation, Arguments, ParameterTypes,
                                   Origins) :-
    shallow_declared_type(Operation, Chain0),
    copy_term(Chain0, [->|Types]),
    append(ParameterTypes, [_], Types),
    metta_argument_type_origins(ParameterTypes, Origins),
    same_length(ParameterTypes, Arguments).

%Keep whether a formal was a raw type variable before an earlier argument
%binds it. A derived Atom is an ordinary type constraint, not the literal
%Atom metatype wildcard written in the declaration.
metta_argument_type_origins(Types, Origins) :-
    maplist(metta_argument_type_origin(Types), Types, Origins).

metta_argument_type_origin(Types, Expected, derived_variable) :-
    var(Expected),
    member(Compound, Types),
    nonvar(Compound),
    term_variables(Compound, Variables),
    member(Variable, Variables),
    Variable == Expected,
    !.
metta_argument_type_origin(_, Expected, variable) :- var(Expected), !.
metta_argument_type_origin(_, Expected, metatype) :-
    nonvar(Expected),
    current_metta_module(Module),
    typing_rule_expected(Module, metatype, Expected),
    !.
metta_argument_type_origin(_, _, ordinary).

check_argument_type(Argument, Expected, Origin) :-
    current_metta_module(Module),
    check_argument_type_in(Module, Argument, Expected, Origin).

check_argument_type_in(Module, Argument, Expected, metatype) :-
    metatype_of(Argument, Actual),
    typing_rule_decision(Module, metatype, Actual, Expected,
                         Outcome, _, _),
    (   Outcome == accept
    ->  true
    ;   Outcome = [refuse, _]
    ->  fail
    ;   metta_argument_types_in(Module, Argument, Types),
        member(Reported, Types),
        typing_rule_accepts(Module, reporting, Reported, Expected)
    ).
check_argument_type_in(Module, Argument, Expected, derived_variable) :-
    metta_runtime_type_candidate(Module, Argument, Actual),
    metta_derived_types_match_in(Module, Actual, Expected).
check_argument_type_in(Module, Argument, Expected, Origin) :-
    Origin \== metatype,
    Origin \== derived_variable,
    (   metta_evaluating_type_rule
    ->  metta_argument_types_in(Module, Argument, Types),
        member(Actual, Types),
        metta_types_match_in(Module, Actual, Expected)
    ;   has_type_in(Module, Argument, Expected)
    ).

metta_runtime_type_candidate(Module, Argument, Actual) :-
    type_candidate_in(Module, Argument, Actual).
metta_runtime_type_candidate(Module, Argument, '%Undefined%') :-
    \+ once(type_candidate_in(Module, Argument, _)).

metta_argument_type_matches(Actual, Expected, variable) :-
    metta_types_match(Actual, Expected).
metta_argument_type_matches(Actual, Expected, derived_variable) :-
    metta_derived_types_match(Actual, Expected).
metta_argument_type_matches(Actual, Expected, metatype) :-
    metta_types_match(Actual, Expected).
metta_argument_type_matches(Actual, Expected, ordinary) :-
    metta_types_match(Actual, Expected).

%Every rejected actual type at a position, and then the positions after it,
%which is what the arbiter reports when one actual type of an argument matched
%and carried the check forward while another did not
%[source: types-basic/48-badargtype-argument-order.metta]. The cut commits to
%the first carrying type, because the check continues under ONE assignment.
%
%A parameter naming a METATYPE is settled by the argument's metatype alone and
%reports nothing, which is the other half of the compiled call site's
%`(has_type(A,T) *-> true ; get-metatype(A,T))`: `(format-args "{}" (1 2))`
%passes an Expression parameter whose argument's DECLARED type is the tuple
%`(Number Number)` [measured 2026-08-19 against the arbiter, which answers
%"1"]. The declared types still decide when the metatype does not, which is
%why `(: xs Expression)` also passes and `(: n Number)` does not.
metta_bad_argument([Expected|Rest], [Origin|Origins], [Argument|Arguments], N,
                   Position, Reported, Actual) :-
    metta_argument_types(Argument, Types),
    (   Origin == metatype,
        satisfies_metatype(Argument, Expected)
    ->  Next is N + 1,
        metta_bad_argument(Rest, Origins, Arguments, Next,
                           Position, Reported, Actual)
    ;   (   Position = N, Reported = Expected,
            member(Actual, Types),
            \+ metta_argument_type_matches(Actual, Expected, Origin)
        ;   member(Carried, Types),
            metta_argument_type_matches(Carried, Expected, Origin),
            !,
            Later is N + 1,
            metta_bad_argument(Rest, Origins, Arguments, Later,
                               Position, Reported, Actual)
        )
    ).

%The types an ARGUMENT CHECK may read, which is not everything get-type
%answers. A `get-type` EQUATION is a MeTTa program, and a program that types
%its argument by COMPUTING on it re-enters the operation whose refusal asked:
%examples/types/types_dependent.metta writes
%`(= (get-type $x) (catch (if (=alpha (% $x 2) 0) EvenNumber)))`, so asking
%get-type why `%` refused ran `%` again, and again
%[reproduced 2026-08-19: 16,777,031 frames and the 8Gb stack limit].
%
%Upstream reads the space's `(: x T)` atoms and the grounded object's own type
%here and nothing else, so the equations are off for the whole lookup rather
%than only at its top: the walk reaches them again through a list member's
%type. The flag is thread-local because the refusal is, and re-entrant because
%a nested lookup must not turn them back on when it finishes.
:- thread_local metta_reading_declared_types/0.

metta_argument_types(Argument, Types) :-
    current_metta_module(Module),
    metta_argument_types_in(Module, Argument, Types).

%THE COMPILE-TIME READING of the same question, and the difference is that it
%does not descend. A type walk over a nested call is proportional to the whole
%subtree, so asking it at every call site while compiling one made compilation
%quadratic in nesting depth: the translator's own linear-work test builds 400
%nested additions and holds compilation to at most double the work for double
%the depth [tested: translator_translation_depth:
%every_nesting_shape_compiles_in_linear_work].
%
%One lookup per argument answers what the refusal needs: a literal carries its
%own type, a call carries its head's declared RETURN type, and a symbol carries
%what was declared for it. Nothing else is decided, and an argument this cannot
%type is an argument the check accepts, so the compile-time decision is a
%SUBSET of the runtime one and a call it does not refuse compiles exactly as it
%did. The nesting is not lost either: the inner call is a call site of its own
%and is asked the same question when it is compiled.
%A VARIABLE first, and with a cut, because the clauses below match by head and
%an unbound argument would UNIFY with `true` and be typed Bool: the compiled
%body of `(= (qq $x) (+ $x 1))` came out as `qq(true, A)`, the check having
%bound the head's own variable before refusing the call it then reported
%[reproduced 2026-08-20].
shallow_argument_types(X, _) :- var(X), !, fail.
shallow_argument_types(X, ['Number']) :- number(X), !.
shallow_argument_types(X, ['String']) :- string(X), !.
shallow_argument_types(true, ['Bool']) :- !.
shallow_argument_types(false, ['Bool']) :- !.
shallow_argument_types([H|_], Types) :-
    atom(H), !,
    (   '$petta_atoms:&self':'&self'(':', H, _)
    ->  findall(Return,
                ( '$petta_atoms:&self':'&self'(':', H, Chain),
                  nonvar(Chain), Chain = [->|Rest], last(Rest, Return) ),
                Types),
        Types \== []
    ;   seam:builtin_type_declaration(H, Chain),
        nonvar(Chain), Chain = [->|Rest],
        last(Rest, Return),
        Types = [Return]
    ).
shallow_argument_types(X, Types) :-
    atom(X),
    (   '$petta_atoms:&self':'&self'(':', X, _)
    ->  findall(Type,
                ( '$petta_atoms:&self':'&self'(':', X, Type),
                  \+ ( nonvar(Type), Type = [->|_] ) ),
                Types),
        Types \== []
    ;   seam:builtin_type_declaration(X, Type),
        \+ ( nonvar(Type), Type = [->|_] ),
        Types = [Type]
    ).

%The two indexed registers, read directly: &self's own declarations and the
%engine's surface. type_declaration/2 would go through match/4 and the prelude,
%which is the door data_head_answer_dl/6's note measures at +44% on a compile
%path [measured 2026-08-19].
shallow_declared_type(Name, Type) :-
    '$petta_atoms:&self':'&self'(':', Name, Type).
shallow_declared_type(Name, Type) :-
    \+ '$petta_atoms:&self':'&self'(':', Name, _),
    seam:builtin_type_declaration(Name, Type).

metta_argument_types_in(Module, Argument, Types) :-
    (   metta_reading_declared_types
    ->  type_answers(Module, Argument, Types)
    ;   setup_call_cleanup(assertz(metta_reading_declared_types, Ref),
                           type_answers(Module, Argument, Types),
                           erase(Ref))
    ).

%The call site's compatibility relation is declared in type_rules.pl.
%%Undefined%, Atom, equality, and BigInt widening are shipped entries in the
%same registry a program extends. The wrapper keeps existing callers on the
%current execution module; module-aware call sites use the explicit form
%[tested: test_a_user_typing_rule_participates_like_a_shipped_one;
%commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
metta_types_match(Left, Right) :-
    current_metta_module(Module),
    metta_types_match_in(Module, Left, Right).

metta_types_match_in(Module, Left, Right) :-
    typing_rule_accepts(Module, ordinary, Left, Right).

%A raw type variable uses Atom as an ordinary bound once another formal has
%fixed it. The gradual unknown and numeric widening rules still apply.
metta_derived_types_match(Left, Right) :-
    current_metta_module(Module),
    metta_derived_types_match_in(Module, Left, Right).

metta_derived_types_match_in(Module, Left, Right) :-
    typing_rule_accepts(Module, derived, Left, Right).

%The operations that refuse BY NAME rather than leaving the call. Each text is
%upstream's own, quoted from the arbiter's transcript rather than invented, and
%upstream's noun is not uniform: sqrt-math and abs-math say `number` where every
%later unary operation says `input number`, and log-math names both arguments
%[source: LeaTTa tests/semantics/grounded/08-partial-math.metta, whose STATUS
%records that each text is pinned by an upstream unit test in math.rs].
%
%The ARGUMENTS are in the head because three of these operations word the
%refusal differently for different arguments, and the caller has them anyway.
metta_operation_refusal('/', _,
    "Divide expects two numbers: dividend and divisor").
metta_operation_refusal('sqrt-math', _, "sqrt-math expects one argument: number").
metta_operation_refusal('abs-math', _, "abs-math expects one argument: number").
metta_operation_refusal('pow-math', _,
    "pow-math expects two arguments: number (base) and number (power)").
metta_operation_refusal('log-math', _,
    "log-math expects two arguments: base (number) and input value (number)").
metta_operation_refusal(Operation, _, Message) :-
    metta_input_number_operation(Operation),
    format(string(Message), "~w expects one argument: input number",
           [Operation]).
%min-atom and max-atom carry three texts for three arguments: not an
%expression at all, an empty one, and one holding something that is not a
%number, which upstream quotes back as it formats it
%[source: the same file, whose STATUS names atom.rs:194,228; measured
%2026-08-19 against the arbiter: `(min-atom 5)` and `(min-atom ())` answer the
%first two].
%format-args words its refusal by WHICH argument is wrong: a first argument
%that is not a format string earns the long text, and a first that is one with
%a second that is not an expression earns the conversion's own
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, formatArgsOp's three
%cases].
metta_operation_refusal('format-args', [Format|_], Message) :-
    (   string(Format)
    ->  Message = "Atom is not an ExpressionAtom"
    ;   Message = "format-args expects format string as a first argument and expression as a second argument"
    ).
metta_operation_refusal('sort-strings', _,
    "sort-strings expects expression with strings as a first argument").
metta_operation_refusal(Operation, [Argument], Message) :-
    metta_numeric_expression_operation(Operation),
    (   non_list(Argument)
    ->  Message = "Atom is not an ExpressionAtom"
    ;   Argument == []
    ->  Message = "Empty expression"
    ;   \+ maplist(number, Argument),
        swrite(Argument, Written),
        format(string(Message), "Only numbers are allowed in expression: ~w",
               [Written])
    ).

metta_numeric_expression_operation('min-atom').
metta_numeric_expression_operation('max-atom').


metta_input_number_operation('sin-math').    metta_input_number_operation('cos-math').
metta_input_number_operation('tan-math').    metta_input_number_operation('asin-math').
metta_input_number_operation('acos-math').   metta_input_number_operation('atan-math').
metta_input_number_operation('trunc-math').  metta_input_number_operation('ceil-math').
metta_input_number_operation('floor-math').  metta_input_number_operation('round-math').
metta_input_number_operation('isnan-math').  metta_input_number_operation('isinf-math').
metta_input_number_operation('exp-math').    metta_input_number_operation(exp).

%One registry owns the numeric math family and its input arities. The runtime
%guards below and their exhaustive string-operand pin both read this table, so
%a newly admitted math operation cannot inherit SWI's one-character-string
%arithmetic by omission [tested:
%test_a_string_operand_to_math_refuses_instead_of_answering_its_char_code].
metta_math_operation('sqrt-math', 1).
metta_math_operation('abs-math', 1).
metta_math_operation('pow-math', 2).
metta_math_operation('log-math', 2).
metta_math_operation(Operation, 1) :- metta_input_number_operation(Operation).

%The math family's recovery, which decides between the two failures the host
%reports the same way. An argument that is not a number at all is the MeTTa
%operation's own refusal and an ANSWER; a numeric fault outside the licensed
%IEEE family remains a host error. It sits in the catch's recovery rather than
%in front of the call, so the fast path pays nothing: this runs only where
%is/2 has already raised
%[tested: operation_answers, metta_operation_errors].
metta_math_recovery(Operation, Arguments, Error, Answer) :-
    (   maplist(metta_numeric_operand, Arguments)
    ->  rethrow_metta_operation_error(Operation, Error)
    ;   metta_operation_answer(Operation, Arguments, Answer)
    ).

%The float-capable operations chain the two recoveries: an IEEE-class fault
%in a floating expression saturates to the value the arbiter's raw f64 answers
%(metta_saturating_recover), and everything else takes the split above, a
%wrong-typed operand answering and a numeric host error staying one.
metta_math_saturating_recovery(Operation, Expression, Arguments, Error, Out) :-
    (   metta_ieee_saturable(Expression, Error)
    ->  metta_saturating_recover(Operation, Expression, Out, Error)
    ;   metta_math_recovery(Operation, Arguments, Error, Out)
    ).

%Check the numeric input at the operation's own door, before is/2 can interpret
%a one-character string as its character code. The refusal itself is derived
%from seam:builtin_type_declaration/2 through metta_operation_answer/3, the same
%table that guards translated calls; computed and direct operands therefore
%name the operation, position, expected Number and actual String alike.
metta_math_eval(Operation, Expression, Arguments, Out) :-
    (   maplist(metta_numeric_operand, Arguments)
    ->  catch(Out is Expression, Error,
              metta_math_recovery(Operation, Arguments, Error, Out))
    ;   metta_operation_answer(Operation, Arguments, Out)
    ).

metta_math_saturating_eval(Operation, Expression, Arguments, Out) :-
    (   maplist(metta_numeric_operand, Arguments)
    ->  catch(Out is Expression, Error,
              metta_math_saturating_recovery(
                  Operation, Expression, Arguments, Error, Out))
    ;   metta_operation_answer(Operation, Arguments, Out)
    ).

%An unbound operand counts as numeric here, so the instantiation error is
%rethrown rather than turned into a type report: a missing value is not a
%wrong one, which is the split metta_arith_operands/2 already draws.
metta_numeric_operand(Value) :- var(Value), !.
metta_numeric_operand(Value) :- number(Value).
%The reader's source spellings remain evaluable atoms until is/2 consumes
%them. They are numeric inputs, unlike every other atom and every string.
metta_numeric_operand(inf).
metta_numeric_operand(nan).
