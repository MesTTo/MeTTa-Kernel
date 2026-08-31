% Purpose: PlUnit coverage for bit-and, bit-or, bit-xor, bit-not and
%   floor-div, the operations completing the exact-integer family the shifts
%   opened, so a compiled Python body's &, |, ^, ~ and // pay no host
%   crossing.
% Guarantees:
%   - the four bitwise operations answer SWI's exact integers, negative
%     operands included [tested: bitwise_answers_exact_integers]
%   - floor-div is Python's floored quotient: integer for two integers,
%     the floored quotient as a float when a float rides in, and toward
%     negative infinity where truncation would differ [tested:
%     floor_div_is_pythons_floored_quotient]
%   - a zero divisor answers the same DivisionByZero error data integer
%     division answers [tested: a_zero_divisor_answers_error_data]
%   - a non-integer bitwise operand earns the ordinary argument refusal
%     [tested: a_non_integer_bitwise_operand_refuses]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(bit_family).

metta(Source, Results) :-
    with_output_to(string(_), process_metta_string(Source, Results)).

bitwise_case("(bit-and 12 10)", 8).
bitwise_case("(bit-and 7 0)", 0).
bitwise_case("(bit-or 12 10)", 14).
bitwise_case("(bit-xor 12 10)", 6).
bitwise_case("(bit-xor -1 1)", -2).
bitwise_case("(bit-not 0)", -1).
bitwise_case("(bit-not 7)", -8).
bitwise_case("(bit-and -8 13)", 8).

test(bitwise_answers_exact_integers, [forall(bitwise_case(Form, Expected))]) :-
    format(atom(Query), "!~w", [Form]),
    metta(Query, Results),
    Results == [Expected].

floor_case("(floor-div 7 2)", 3).
floor_case("(floor-div -7 2)", -4).
floor_case("(floor-div 7 -2)", -4).
floor_case("(floor-div 6 3)", 2).
floor_case("(floor-div 7.0 2)", 3.0).
floor_case("(floor-div -7.5 2)", -4.0).

test(floor_div_is_pythons_floored_quotient,
     [forall(floor_case(Form, Expected))]) :-
    format(atom(Query), "!~w", [Form]),
    metta(Query, Results),
    Results == [Expected].

test(a_zero_divisor_answers_error_data) :-
    metta("!(floor-div 7 0)", Results),
    Results == [['Error', ['floor-div', 7, 0], 'DivisionByZero']].

test(a_non_integer_bitwise_operand_refuses) :-
    metta("!(bit-and 1.5 2)", Results),
    Results = [['Error', _, _]].

test(bit_not_refuses_a_float) :-
    metta("!(bit-not 1.5)", Results),
    Results = [['Error', _, _]].

:- end_tests(bit_family).
