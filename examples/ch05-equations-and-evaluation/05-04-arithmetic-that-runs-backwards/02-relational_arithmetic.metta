;Relational arithmetic. The # operators are CLP(FD) constraints rather than
;evaluations, so they run in every direction: give any two of the three and the
;engine solves for the third, by propagation rather than by search.
;
;engine/metta.pl loads library(clpfd) and has exposed these all along. Nothing in
;examples/ or lib/ used a single one of them before this file, which is how two
;of the six comparisons came to be missing without anyone noticing: (#=< 1 2)
;had no operation behind it and so came back as the expression (#=< 1 2), which
;reads like a result.

;Forwards, the same as ordinary arithmetic.
!(test (#+ 1 2) 3)
!(test (#* 3 4) 12)
!(test (#- 10 4) 6)

;Backwards. Ordinary arithmetic runs backwards too, which this file used to
;deny: examples/ch05-equations-and-evaluation/05-04-arithmetic-that-runs-backwards/01-backward_arithmetic.metta is where + - * / do it, where
;they stop, and what the # operators still buy past that point.
!(test (let 5 (#+ $x 2) $x) 3)
!(test (let 12 (#* $y 4) $y) 3)
!(test (let 6 (#- $z 4) $z) 10)

;Integer division, remainder, and the two extremes.
!(test (#div 13 4) 3)
!(test (#mod 13 4) 1)
!(test (#min 3 7) 3)
!(test (#max 3 7) 7)

;All six comparisons, answering True or False rather than succeeding or
;failing, so they compose with if.
!(test (#< 1 2) True)
!(test (#< 2 1) False)
!(test (#> 2 1) True)
!(test (#= 3 3) True)
!(test (#\= 3 4) True)
!(test (#=< 1 2) True)
!(test (#=< 2 1) False)
!(test (#>= 2 1) True)
!(test (#>= 1 2) False)

;Composed, and still solvable backwards through two constraints.
!(test (let 20 (#* (#+ $a 1) 4) $a) 4)
