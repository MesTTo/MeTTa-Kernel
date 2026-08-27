;Printing an answer tells you what happened. CHECKING one tells you whether
;it was right, and that is what every other file here does.
;
;    !(test <form> <expected>)
;
;runs the form, compares, and prints one line per check:
;
;    is 42, should 42. ✅
;
;Read `test` as an assertion with a trace: the line is printed whether the
;check passes or fails, so a passing run is still readable output. A mismatch
;prints ❌ and fails the process, which is what makes `sh test.sh` a suite.
!(test (+ 40 2) 42)

;`test` is THIS IMPLEMENTATION'S, not the MeTTa language's. KERNEL.md
;classifies it as a divergence: it is here because these examples are
;simultaneously the test suite, and a program you write has no need of it.
;The conforming spelling of the same idea is assertEqual, which answers a
;value rather than printing a line, and chapter 12 is where both belong.
!(test (assertEqual (+ 40 2) 42) True)

;Everything after this file is written with `test`, so the check is visible
;beside the thing it checks. When you read one, the form on the left is the
;program and the value on the right is the claim.
!(test (* 6 7) 42)
