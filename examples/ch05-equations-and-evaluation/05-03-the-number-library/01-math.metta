;Purpose: executable examples for numeric and real-valued math operations.
;Guarantees: == and != are TERM equality, so the integer 1 and the float 1.0
;are NOT equal; comparing two different kinds answers False rather than
;refusing [tested: test_mixed_numeric_equality_is_term_equality;
;source: PeTTa@ae66fa8 src/metta.pl:40-41].
;A computed string reaches each math operation's own guard and is refused
;before the host can treat one character as its code [tested:
;test_a_string_operand_to_math_refuses_instead_of_answering_its_char_code].
;Integer division and remainder by zero answer contained DivisionByZero
;atoms [tested: test_integer_division_by_zero_answers_what_d1_decides].
;Real-valued sqrt, log and trig promote integer operands to Float. POW DOES
;NOT: it keeps its operands' own numeric kinds, so `(pow-math 2 3)` is the
;integer 8, which is what upstream's `Out is A ** B` answers. Pow additionally
;bounds integer exponents to signed i32 [tested:
;test_real_valued_math_treats_integer_and_float_operands_alike;
;source: PeTTa@ae66fa8 src/metta.pl:69].

!(test (== 1 1.0) False)
!(test (!= 1.0 1) True)
!(test (== 1 "s") False)
!(test (== true 1) False)
!(test (/ 7 0) (Error (/ 7 0) DivisionByZero))
!(test (% 7 0) (Error (% 7 0) DivisionByZero))
!(test (collapse (/ 7 0))
       (noeval ((Error (/ 7 0) DivisionByZero))))
(= (math-string) "s")
!(test (sqrt-math (math-string))
       (Error (sqrt-math "s") (BadArgType 1 Number String)))
!(test (pow-math 2 3) 8)
!(test (isnan-math (sqrt-math -1)) True)
;An all-integer zero division is a contained answer, the same vocabulary
;`(/ 7 0)` above uses; the FLOAT arm saturates to the raw f64 value instead.
!(test (pow-math 0 -1) (noeval (Error (pow-math 0 -1) DivisionByZero)))
!(test (isinf-math (pow-math 0.0 -1.0)) True)
!(test (pow-math 2 2147483648)
       (noeval (Error (pow-math 2 2147483648)
                      "power argument is too big, try using float value")))
;SWI's `**` special-cases base 1 and answers the INTEGER 1, exponent's kind
;notwithstanding, which is what upstream answers here too
;[measured 2026-08-30: `X is 1 ** 2147483648.0` is 1, and `2 ** 3.0` is 8.0].
!(test (pow-math 1 2147483648.0) 1)
!(test (sqrt-math 9) 3.0)
!(test (abs-math -5) 5)
!(test (log-math 10 100) 2.0)
!(test (trunc-math 5.6) 5)
!(test (ceil-math 5.2) 6)
!(test (floor-math 5.8) 5)
!(test (round-math 5.4) 5)
!(test (round-math 5.6) 6)
!(test (sin-math 0) 0.0)
!(test (asin-math 0) 0.0)
!(test (cos-math 0) 1.0)
!(test (acos-math 1) 0.0)
!(test (tan-math 0) 0.0)
!(test (atan-math 0) 0.0)
!(test (isnan-math 0.0) False)
!(test (isinf-math 0.0) False)
!(test (min-atom (2 6 7 4 9 3)) 2)
!(test (max-atom (2 6 7 4 9 3)) 9)
!(test (isinf-math inf) True)
!(test (isnan-math nan) True)
