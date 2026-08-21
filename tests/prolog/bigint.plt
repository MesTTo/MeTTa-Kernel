% Purpose: PlUnit coverage for the signed-i64 Number/BigInt boundary, typed
%   calls, exact unbounded arithmetic, and mixed numeric equality.
% Guarantees:
%   - get-type is total at both sides of the boundary [tested:
%     bigint_and_number_type_every_integer]
%   - Number parameters admit BigInt and BigInt parameters reject Number
%     [tested: number_accepts_bigint_but_bigint_stays_narrow]
%   - arithmetic and equality keep their exact SWI integer values [tested:
%     arithmetic_promotes_and_demotes_by_result_width,
%     mixed_bigint_number_equality_is_exact]
% Open Obligations:
%   To Do: Re-verify these rules when LeaTTa adds its announced BigInt type.
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(bigint_number).

metta(Source, Results) :-
    with_output_to(string(_), process_metta_string(Source, Results)).

numeric_type_case(-9223372036854775809, 'BigInt').
numeric_type_case(-9223372036854775808, 'Number').
numeric_type_case(0, 'Number').
numeric_type_case(9223372036854775807, 'Number').
numeric_type_case(9223372036854775808, 'BigInt').

test(bigint_and_number_type_every_integer,
     [forall(numeric_type_case(Value, Expected))]) :-
    format(atom(Query), "!(get-type ~w)", [Value]),
    metta(Query, Types),
    Types == [Expected].

test(arithmetic_promotes_and_demotes_by_result_width) :-
    metta("!(let $x (+ 9223372036854775807 1) (get-type $x))", Promoted),
    Promoted == ['BigInt'],
    metta("!(let $x (- 9223372036854775808 1) (get-type $x))", Demoted),
    Demoted == ['Number'],
    metta("!(* 4611686018427387904 4)", Exact),
    Exact == [18446744073709551616].

test(number_accepts_bigint_but_bigint_stays_narrow) :-
    forall(member(Form,
                  [ "(: p145-pl-number (-> Number Atom))",
                    "(= (p145-pl-number $x) (number-accepted $x))",
                    "(: p145-pl-bigint (-> BigInt Atom))",
                    "(= (p145-pl-bigint $x) (bigint-accepted $x))" ]),
           metta(Form, _)),
    metta("!(p145-pl-number 9223372036854775808)", NumberAnswer),
    assertion(NumberAnswer == [['number-accepted', 9223372036854775808]]),
    metta("!(p145-pl-bigint 9223372036854775808)", BigIntAnswer),
    assertion(BigIntAnswer == [['bigint-accepted', 9223372036854775808]]),
    metta("!(p145-pl-bigint 1)", [Rejected]),
    assertion(Rejected == ['Error', ['p145-pl-bigint', 1],
                           ['BadArgType', 1, 'BigInt', 'Number']]).

test(mixed_bigint_number_equality_is_exact) :-
    metta("!(== 9223372036854775808 9223372036854775808)", Same),
    Same == [true],
    metta("!(== 9223372036854775808 9223372036854775807)", Different),
    Different == [false],
    metta("!(!= 9223372036854775808 9223372036854775807)", NotEqual),
    NotEqual == [true].

:- end_tests(bigint_number).
