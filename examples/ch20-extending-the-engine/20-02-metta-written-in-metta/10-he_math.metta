;Purpose: executable standard-library checks for numeric math operations.
;Guarantees: real-valued math promotes integers, and pow returns Float while
;enforcing the signed-i32 bound only for integer exponents [tested:
;test_real_valued_math_treats_integer_and_float_operands_alike].

!(test (pow-math 2 3) 8.0)
!(test (isnan-math (sqrt-math -1)) True)
!(test (isinf-math (pow-math 0 -1)) True)
!(test (pow-math 1 2147483648.0) 1.0)
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
