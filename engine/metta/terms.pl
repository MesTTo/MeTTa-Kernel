% Purpose: provide representation, parsing, grounded-operation errors, and numeric term recovery
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
%   Python numeric objects reach their owning operator seam only after the
%   native-number branch declines [tested:
%   test_numpy_numeric_family_keeps_python_result_types; commit=a0f1cc5f15a15e5ca6958fe02a20be8832c7237f].
%   Operation argument checks consume the same lexical declaration set as
%   compiled calls [tested:
%   test_an_inherited_arrow_does_not_veto_a_local_definition;
%   commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c].
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/suites/evaluation/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%%%%%%%%% Standard Library for MeTTa %%%%%%%%%%

%%% Representation and parsing conversions: %%%
id(X, X).
%noeval is the Atom mask on both sides: the declaration in
%lib/lib_builtin_types/lib_builtin_types.metta stops the argument being reduced on the way in and
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

%THE CHEAP QUESTION FIRST. This clause exists to find a NAMED refusal, and
%only a rule the program registered can produce one: engine/type_rules.pl
%ships nineteen typing rules and not one of them has a `refuse` outcome, so
%with no user rule in this module typing_rule_refusal/6 cannot succeed and
%everything this clause does before reaching it is dead.
%
%What it does is not cheap. metta_named_rule_refusal/10 walks every parameter
%and derives each argument's types through typing_refusal_actual/4, and the
%clause below then walks the same parameters again, so metta_operation_parameters/4
%ran twice per refused call with a full type derivation for nothing in
%between. One indexed probe on an EMPTY predicate is what a program with no
%typing rules pays instead.
%
%The saving is recorded as what it measured rather than what it looked like:
%nilbc does not reach this path often enough to move
%[measured 2026-08-30: 308,570,186 inferences before and after]. A refused
%call pays it, and a refused call is exactly where an error message is being
%built, so the work removed is work no answer depended on.
metta_bad_argument_refusal(Operation, Arguments, Error) :-
    current_metta_module(Module),
    registered_typing_rule(user, Module, _, _, _, _, _),
    !,
    metta_operation_parameters(Operation, Arguments, ParameterTypes, Origins),
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

%A type-position modifier is REPORTED and CHECKED by its value type: the
%arbiter answers `(BadArgType 1 Number String)` for a `(:Atom Number)`
%parameter, naming the type that decided rather than the pair that carried it
%[measured 2026-08-24 against LeaTTa 9ea9f9d]. The projection sits on the
%refusal path, which this file's own note above metta_operation_answer/3
%records as reached only after a caller's fast path has declined.
metta_named_rule_refusal(Module, [Declared|_], [Origin|_],
                         [Argument|_], Position,
                         Position, Expected, Actual, Rule, Reason) :-
    declared_type_for_check(Declared, Expected),
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
%A TYPE-POSITION MODIFIER pairs an unevaluated metatype with a separate value
%type, so a parameter can say "do not evaluate this, and it must still be a
%Number". Without it those are exclusive: the official "Controlling pattern
%matching" page records that a specific parameter type and a metatype cannot
%be supplied together and links trueagi-io/hyperon-experimental#177, and these
%two spellings are what close that quadrant
%[source: LeaTTa MettaHyperonFull/Core/Modifiers.lean:92-116, `typeMod?`,
%`declaredTypeForCheck` and `declaredTypeForEvaluation`].
%
%The registry is CLOSED and the arity is part of the shape: a three-element
%`(:Atom a b)` is ordinary data, exactly as `registeredMod?` requires.
type_position_modifier(Type, Metatype, ValueType) :-
    nonvar(Type),
    Type = [Head, ValueType],
    atom(Head),
    type_position_metatype(Head, Metatype).

type_position_metatype(':Atom', 'Atom').
type_position_metatype(':Expression', 'Expression').

%The checker reads the inner type of a modifier and every other declaration as
%written; argument preparation reads the metatype head. Two projections of one
%declaration, named as the reference names them.
declared_type_for_check(Type, ValueType) :-
    (   type_position_modifier(Type, _, Inner)
    ->  ValueType = Inner
    ;   ValueType = Type
    ).

metta_operation_parameters(Operation, Arguments, ParameterTypes, Origins) :-
    current_metta_module(Module),
    (   governing_type_declaration_in(Module, Operation, Chain0)
    ;   \+ type_declaration_in(Module, Operation, _),
        seam:builtin_type_declaration(Operation, Chain0)
    ),
    copy_term(Chain0, [->|Types]),
    %The types are read AS DECLARED. A type-position modifier is projected by
    %the consumers below, and only there: every declared argument check runs
    %through this reader, so projecting each parameter here costs an inference
    %per parameter per call and query-where paid 140 of them, 0.02%, for a
    %shape no shipped declaration uses [measured 2026-08-24].
    append(ParameterTypes, [_], Types),
    metta_argument_type_origins(ParameterTypes, Origins),
    same_length(ParameterTypes, Arguments).

metta_shallow_operation_parameters(Operation, Arguments, ParameterTypes,
                                   Origins) :-
    shallow_declared_type(Operation, Chain0),
    copy_term(Chain0, [->|Types]),
    %The types are read AS DECLARED. A type-position modifier is projected by
    %the consumers below, and only there: every declared argument check runs
    %through this reader, so projecting each parameter here costs an inference
    %per parameter per call and query-where paid 140 of them, 0.02%, for a
    %shape no shipped declaration uses [measured 2026-08-24].
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

%THE RUNTIME CHECK AND THE REPORTED TYPE ASK DIFFERENT QUESTIONS, and the
%arbiter answers them with different relations. Admitting an argument selects
%`.runtime`, "the permissive `match_types`", where `Atom` on either side is a
%match [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:4560-4582,
%`typeCheckArgsOutcomes`]. Reporting an application's type keeps the stricter
%`match_reducted_types`, where a literal `Atom` result is an ordinary type.
%
%Both are measured, on the same day and against LeaTTa 9ea9f9d. With
%`(: idv (-> Atom Atom))` declared, `(: vf (-> Variable %Undefined%))` ACCEPTS
%`!(vf (idv $y))` and answers `(quote (idv $y))`, while
%`!(get-type (needs-grounded (atom-result value)))` answers NOTHING for the
%same shape. One relation cannot serve both, and this engine used the
%reporting one for both until the evaluation mask made a masked parameter
%check its argument as written and the difference became reachable.
%The split is made HERE rather than behind another predicate. Every declared
%argument check runs this, so one extra call is one extra inference per check
%and a query workload pays it once per row: routing the two relations through
%a helper cost query-where 140 inferences, 0.02%, for a decision the clause
%head already makes [measured 2026-08-24].
check_argument_type(Argument, Expected, metatype) :-
    !,
    current_metta_module(Module),
    metatype_argument_admitted(Module, Argument, Expected, ordinary).
check_argument_type(Argument, Expected, Origin) :-
    current_metta_module(Module),
    check_argument_type_in(Module, Argument, Expected, Origin).

check_argument_type_in(Module, Argument, Expected, metatype) :-
    metatype_argument_admitted(Module, Argument, Expected, reporting).
check_argument_type_in(Module, Argument, Expected, derived_variable) :-
    metta_runtime_type_candidate(Module, Argument, Actual),
    metta_derived_types_match_in(Module, Actual, Expected).
%A BARE TYPE VARIABLE BINDS TO A CANDIDATE, it does not search for a
%membership witness. This is the parameter whose declared type is a variable
%the chain uses again, `(: bc (-> $a Nat $b $b))`, so the check exists to FIX
%$b from the argument rather than to test the argument against a known type.
%
%Upstream emits exactly a binding for it:
%`('get-type'(AV, T) *-> true ; 'get-metatype'(AV, T))`, and its get-type is
%`(get_type_candidate(X, T) *-> true ; T = '%Undefined%')` -- one candidate,
%and %Undefined% when there is none
%[source: PeTTa@ae66fa8 src/translator.pl:392-396 and src/metta.pl:186].
%
%This fell to the clause below, which for an unbound Expected reaches
%has_type_in/3 with a non-ground type and derives the argument's COMPLETE
%widened answer set. A nested type variable already took the candidate path
%through the derived_variable clause above; a bare one did not, and the
%asymmetry is what made a dependent-type backward chainer pay a full type
%derivation per recursive call. Argument checking is 99.4% of nilbc
%[measured 2026-08-30: 306,132,002 inferences against 1,866,723 with
%check_argument_type/3 stubbed to true].
check_argument_type_in(Module, Argument, Expected, variable) :-
    (   metta_runtime_type_candidate(Module, Argument, Expected)
    *-> true
    ;   Expected = '%Undefined%'
    ).

check_argument_type_in(Module, Argument, Expected, Origin) :-
    Origin \== metatype,
    Origin \== derived_variable,
    Origin \== variable,
    (   metta_evaluating_type_rule
    ->  metta_argument_types_in(Module, Argument, Types),
        member(Actual, Types),
        metta_types_match_in(Module, Actual, Expected)
    ;   has_type_in(Module, Argument, Expected)
    ).

%The metatype is asked first and decides on its own where it can; only where
%it defers do the argument's reported types answer, under the caller's chosen
%relation.
metatype_argument_admitted(Module, Argument, Expected, Relation) :-
    metatype_of(Argument, Actual),
    typing_rule_decision(Module, metatype, Actual, Expected,
                         Outcome, _, _),
    (   Outcome == accept
    ->  true
    ;   Outcome = [refuse, _]
    ->  fail
    ;   metta_argument_types_in(Module, Argument, Types),
        member(Reported, Types),
        typing_rule_accepts(Module, Relation, Reported, Expected)
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
metta_bad_argument([Declared|Rest], [Origin|Origins], [Argument|Arguments], N,
                   Position, Reported, Actual) :-
    %The value type of a type-position modifier is what decides and what is
    %named, on this refusal path for the same reason as above.
    declared_type_for_check(Declared, Expected),
    (   Origin == metatype,
        satisfies_metatype(Argument, Expected)
    ->  Next is N + 1,
        metta_bad_argument(Rest, Origins, Arguments, Next,
                           Position, Reported, Actual)
    ;   Origin \== metatype,
        metta_grounded_numeric_type(Argument, Expected)
    ->  Next is N + 1,
        metta_bad_argument(Rest, Origins, Arguments, Next,
                           Position, Reported, Actual)
    ;   metta_argument_types(Argument, Types),
        (   Position = N, Reported = Expected,
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
%examples/ch09-types/12-types_dependent.metta writes
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
    (   '$metta_atoms:&self':'&self'(':', H, _)
    ->  findall(Return,
                ( '$metta_atoms:&self':'&self'(':', H, Chain),
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
    (   '$metta_atoms:&self':'&self'(':', X, _)
    ->  findall(Type,
                ( '$metta_atoms:&self':'&self'(':', X, Type),
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
    '$metta_atoms:&self':'&self'(':', Name, Type).
shallow_declared_type(Name, Type) :-
    \+ '$metta_atoms:&self':'&self'(':', Name, _),
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

%THE SHIPPED ANSWER WITHOUT THE SEARCH. This is the call site's compatibility
%relation and the hottest type predicate the engine has; every typed argument
%of every typed call asks it.
%
%The registry stays the authority and a program that registers an ordinary or
%widening rule gets the full search. What the fast path serves is the case
%where nothing has: engine/type_rules.pl ships exactly five ordinary rules and
%one widening rule, and between them they accept precisely
%  %Undefined% on either side, Atom on either side, an exact match, and
%  BigInt against Number,
%which is the same six-way test this relation was before the registry existed.
%Reading them off the registry instead means decisive_typing_rule/7
%backtracking over the family's entries and running typing_pattern_openness/2
%and typing_rule_pattern_matches/3 per entry, where the test below is inline
%comparisons the VM does not count.
%
%That change cost 5.3x on a dependent-type program: nilbc went from 44,327,926
%inferences to 236,070,644 in one commit and has carried it since 2026-08-21,
%because check_upstream_parity.py's drift tripwire was reading a baseline path
%the file had moved out of and could not fail [measured 2026-08-30 at ecb213fc
%and its parent; reverting this hunk alone at that commit restores 44,328,446].
%
%The two paths must answer the same thing, and that is a test rather than an
%argument: a differential over every pair drawn from the shipped vocabulary,
%run with no user rule and again with one registered, so the fast path is
%checked for agreement AND for standing aside
%[tested: test_the_shipped_fast_path_answers_what_the_registry_answers;
%commit=WORKTREE].
metta_types_match_in(Module, Left, Right) :-
    (   metta_user_typing_rule_present(Module)
    ->  typing_rule_accepts(Module, ordinary, Left, Right)
    ;   metta_shipped_types_match(Left, Right)
    ).

%Whether anything can override the shipped answer here. Ordinary AND widening,
%because typing_check_decision/7 defers an ordinary rule to widening, so a
%user rule in either family changes what this relation answers.
metta_user_typing_rule_present(Module) :-
    (   registered_typing_rule(user, Module, _, ordinary, _, _, _)
    ->  true
    ;   registered_typing_rule(user, Module, _, widening, _, _, _)
    ).

metta_shipped_types_match(Left, Right) :-
    (   Left == '%Undefined%' -> true
    ;   Right == '%Undefined%' -> true
    ;   Left == 'Atom' -> true
    ;   Right == 'Atom' -> true
    ;   Left == 'BigInt', Right == 'Number' -> true
    ;   Left = Right
    ).

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
%EVERY NUMERIC OPERATION SAYS THE SAME THING. Only `/` did, so `(/ 40 a)`
%answered a refusal naming what it wanted while `(+ 40 a)`, `(< 1 a)` and
%`(min 1 a)` answered the call back as written, and a program could not tell
%those from a form that had simply not reduced yet. Upstream draws no such
%line: every one of them reaches is/2 or a comparison and raises, so
%`(repr (catch (+ 40 a)))` is
%"(Error (type_error evaluable (/ a 0)) (context (: system (/ is 2)) $_0))"
%there [measured 2026-08-30 against PeTTa@ae66fa8]. This engine ANSWERS where
%upstream raises, which is the choice metta_operation_answer/3 above records,
%and the answer names the operation and its operands
%[tested: metta_operation_errors:arithmetic_answers_a_non_number_argument_rather_than_raising,
%metta_operation_errors:divide_names_its_two_operands,
%examples/ch10-errors-and-refusals/01-he_error.metta; commit=WORKTREE].
metta_operation_refusal('/', Arguments,
                        "Divide expects two numbers: dividend and divisor") :-
    metta_numeric_operands_settled(Arguments).
metta_operation_refusal(Operation, Arguments, Message) :-
    metta_numeric_binary_operation(Operation),
    metta_numeric_operands_settled(Arguments),
    format(string(Message), "~w expects two numbers", [Operation]).


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
%min-atom and max-atom carry ONE text now, for a list holding something that
%is not a number. Their other two arguments follow upstream instead: a
%non-expression answers `()` and an empty expression answers nothing, both
%decided in engine/metta/operators.pl beside the clauses that do it
%[source: PeTTa@ae66fa8 src/metta.pl:85-88; measured 2026-08-30].
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
    ;   \+ maplist(number, Argument),
        swrite(Argument, Written),
        format(string(Message), "Only numbers are allowed in expression: ~w",
               [Written])
    ).

%An UNBOUND operand is not a WRONG one. The value may still arrive -- a
%backward arithmetic mode binds it, and a partially applied numeric form waits
%for it -- so the call stays as written until every operand is there. Only a
%bound operand that is not a number is the refusal
%[tested: test_python_numeric_dispatch_waits_for_every_operand].
metta_numeric_operands_settled(Arguments) :-
    is_list(Arguments),
    maplist(nonvar, Arguments).

%The ten that take two numbers and nothing else. `/` keeps the longer text it
%already had, which names its two operands.
metta_numeric_binary_operation('+').
metta_numeric_binary_operation('-').
metta_numeric_binary_operation('*').
metta_numeric_binary_operation('%').
metta_numeric_binary_operation('<').
metta_numeric_binary_operation('>').
metta_numeric_binary_operation('<=').
metta_numeric_binary_operation('>=').
metta_numeric_binary_operation(min).
metta_numeric_binary_operation(max).

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
%The NUMERIC branch hands the fault to metta_operation_recovery/4, the shared
%classifier the grounded doors already use, rather than rethrowing it here. A
%second copy of "what an arithmetic fault means" is how `(/ 7 0)` came to
%answer `(Error (/ 7 0) DivisionByZero)` while `(pow-math 0 -1)` KILLED THE
%RUN: same fault, same shape of call, two funnels, and only one of them knew
%the rule. Nothing saw it while pow-math coerced both operands with float/1,
%because the expression was then always floating and always saturated
%[measured 2026-08-30: `!(pow-math 0 -1)` aborted with
%`'pow-math': Arithmetic: evaluation error: zero_divisor` where `!(/ 7 0)`
%answered, and upstream aborts on BOTH, having no vocabulary for either
%(PeTTa@ae66fa8 src/metta.pl:69 is `Out is A ** B`, uncaught)].
metta_math_recovery(Operation, Arguments, Error, Answer) :-
    (   maplist(metta_numeric_operand, Arguments)
    ->  metta_operation_recovery(Operation, Arguments, Error, Answer)
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
    ;   metta_host_numeric_arguments(Arguments)
    ->  once(seam:grounded_numeric_operation(Operation, Arguments, Out))
    ;   metta_operation_answer(Operation, Arguments, Out)
    ).

metta_math_saturating_eval(Operation, Expression, Arguments, Out) :-
    (   maplist(metta_numeric_operand, Arguments)
    ->  catch(Out is Expression, Error,
              metta_math_saturating_recovery(
                  Operation, Expression, Arguments, Error, Out))
    ;   metta_host_numeric_arguments(Arguments)
    ->  once(seam:grounded_numeric_operation(Operation, Arguments, Out))
    ;   metta_operation_answer(Operation, Arguments, Out)
    ).

%An unbound operand counts as numeric here, so it does NOT become a type
%report: a missing value is not a wrong one, which is the split
%metta_arith_operands/2 already draws. It reaches metta_operation_recovery/4
%instead, where metta_arithmetic_rethrow/2 refuses it by the operation's own
%name as an unsolved arithmetic query -- the same answer the grounded doors
%have always given it, rather than a second spelling for one contract
%[tested: test_arithmetic_inverts_past_the_linear_case_or_refuses_with_the_reason].
metta_numeric_operand(Value) :- var(Value), !.
metta_numeric_operand(Value) :- number(Value).
%The reader's source spellings remain evaluable atoms until is/2 consumes
%them. They are numeric inputs, unlike every other atom and every string.
metta_numeric_operand(inf).
metta_numeric_operand(nan).

%A bridge owns both the admission fact and the operator that consumes it. Keep
%the value out of Prolog's number representation: the exact host object is the
%argument Python's reflected operator or array namespace must receive.
metta_grounded_numeric_type(Value, Expected) :-
    Expected == 'Number',
    nonvar(Value),
    \+ number(Value),
    once(seam:grounded_numeric(Value)).

metta_host_numeric_operand(Value) :- var(Value), !.
metta_host_numeric_operand(Value) :- number(Value), !.
metta_host_numeric_operand(Value) :-
    metta_grounded_numeric_type(Value, 'Number').

metta_host_numeric_arguments(Arguments) :-
    maplist(nonvar, Arguments),
    maplist(metta_host_numeric_operand, Arguments),
    member(Argument, Arguments),
    \+ number(Argument), !.
