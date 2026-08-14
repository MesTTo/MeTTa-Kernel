!(import! &self (library lib_he))

!(test (assertEqual (+ 1 2) (- 6 3)) True)
!(test (assertAlphaEqual (h $x $y) (h $a $b)) True)
!(test (assertAlphaEqual (quote (+ $x $y)) (quote (+ $a $b))) True)

; The ToResult forms take the expected results as a tuple, not a bare value,
; and do not evaluate it. A single result is therefore written (3), not 3.
!(test (assertEqualToResult (+ 1 2) (3)) True)
!(test (assertEqualToResult (superpose (1 2)) (1 2)) True)
(= (adder) ($x))
!(test (assertAlphaEqualToResult (adder) (($y))) True)

; Every expected result must appear among those produced.
!(test (assertIncludes (superpose (1 2 3)) (2)) True)
!(test (assertIncludes (superpose (1 2 3)) (2 3)) True)

; The Msg variants take a failure message and otherwise behave as their bases.
!(test (assertEqualMsg (+ 1 2) (- 6 3) "sums differ") True)
!(test (assertAlphaEqualMsg (h $x $y) (h $a $b) "not alpha equal") True)
!(test (assertEqualToResultMsg (+ 1 2) (3) "not the expected result") True)
!(test (assertAlphaEqualToResultMsg (adder) (($y)) "not alpha equal") True)
