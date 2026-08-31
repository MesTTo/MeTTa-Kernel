% Purpose: PlUnit coverage for bit-shift-left and bit-shift-right, the two
%   engine operations added so that every Python binary operator has a MeTTa
%   lowering (`x << y` and `x >> y` were the table's only two absences).
% Guarantees:
%   - shifting answers the exact integer, negative values included, and is
%     exact rather than binary64 [tested: shift_answers_exact_integers]
%   - a NEGATIVE count refuses instead of silently reinterpreting the
%     direction, which is what SWI's own `<<` does: `1 << -1` evaluates to 0
%     there [measured 2026-08-31 on SWI 10.1.13] [tested:
%     a_negative_count_refuses]
%   - a non-integer operand earns the operation's ordinary argument refusal
%     rather than being truncated or read as a character code [tested:
%     a_non_integer_operand_refuses]
%   - the result is unbounded, so a shift past 64 bits is exact rather than
%     wrapped [tested: shifting_past_the_word_is_exact]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(bit_shift).

metta(Source, Results) :-
    with_output_to(string(_), process_metta_string(Source, Results)).

shift_case("(bit-shift-left 1 3)", 8).
shift_case("(bit-shift-left 1 0)", 1).
shift_case("(bit-shift-left 0 5)", 0).
shift_case("(bit-shift-left -1 3)", -8).
shift_case("(bit-shift-right 8 2)", 2).
shift_case("(bit-shift-right -8 1)", -4).
shift_case("(bit-shift-right 1 3)", 0).

test(shift_answers_exact_integers, [forall(shift_case(Form, Expected))]) :-
    format(atom(Query), "!~w", [Form]),
    metta(Query, Results),
    Results == [Expected].

test(shifting_past_the_word_is_exact) :-
    metta("!(bit-shift-left 1 70)", Results),
    Results == [1180591620717411303424].

test(a_negative_count_refuses) :-
    metta("!(bit-shift-left 1 -1)", Results),
    Results = [['Error', ['bit-shift-left', 1, -1], Reason]],
    sub_string(Reason, _, _, _, "must not be negative").

negative_count_case("(bit-shift-left 1 -1)").
negative_count_case("(bit-shift-right 8 -2)").

test(both_directions_refuse_a_negative_count,
     [forall(negative_count_case(Form))]) :-
    format(atom(Query), "!~w", [Form]),
    metta(Query, Results),
    Results = [['Error', _, _]].

%A one-character string is the hazard this shares with the math family: SWI
%evaluates `"a" + 1` as 98, so an operation that reached is/2 with an
%unchecked operand would answer a character code. The integer guard in front
%of the evaluation is what closes it here.
non_integer_case("(bit-shift-left 1.5 2)").
non_integer_case("(bit-shift-left 1 1.5)").
non_integer_case("(bit-shift-left \"a\" 2)").

test(a_non_integer_operand_refuses, [forall(non_integer_case(Form))]) :-
    format(atom(Query), "!~w", [Form]),
    metta(Query, Results),
    Results = [['Error', _, _]].

:- end_tests(bit_shift).
