;Purpose: executable examples for numeric and real-valued math operations.
;Guarantees: mixed integer/float equality compares numeric values, so 1 and
;1.0 are equal [tested: test_mixed_numeric_equality_answers_what_the_arbiter_answers].
;A computed string reaches each math operation's own guard and is refused
;before the host can treat one character as its code [tested:
;test_a_string_operand_to_math_refuses_instead_of_answering_its_char_code].
;Integer division and remainder by zero answer contained DivisionByZero
;atoms [tested: test_integer_division_by_zero_answers_what_d1_decides].

!(test (== 1 1.0) True)
!(test (!= 1.0 1) False)
!(test (/ 7 0) (Error (/ 7 0) DivisionByZero))
!(test (% 7 0) (Error (% 7 0) DivisionByZero))
!(test (collapse (/ 7 0))
       (noeval ((Error (/ 7 0) DivisionByZero))))
(= (math-string) "s")
!(test (sqrt-math (math-string))
       (Error (sqrt-math "s") (BadArgType 1 Number String)))
!(test (pow-math 2 3) 8)
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
