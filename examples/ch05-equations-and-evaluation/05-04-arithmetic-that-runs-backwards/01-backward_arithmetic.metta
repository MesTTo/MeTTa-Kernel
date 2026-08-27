;Backward arithmetic: + - * / are RELATIONS, and where they stop they say so.
;
;examples/ch05-equations-and-evaluation/05-04-arithmetic-that-runs-backwards/02-relational_arithmetic.metta is the # family, CLP(FD)
;constraints that run in every direction by construction. This file is the
;ordinary operators, which run backwards further than anything in the tree
;said, and the boundary past which they refuse.

;+ - * / each solve for ONE unbound slot among integers, so a function written
;forwards reads backwards for free. That fragment was already here and nothing
;recorded it.
(= (double $x) (* 2 $x))
!(test (double 5) 10)
!(test (let 10 (double $x) $x) 5)

!(test (let 5 (+ $p 2) $p) 3)
!(test (let 12 (* $q 4) $q) 3)
!(test (let 6 (- $r 4) $r) 10)
!(test (let 3 (/ $s 4) $s) 12)

;No integer answers it, so it FAILS rather than erroring. That is the
;relational reading: (* 2 $x) = 7 has no integer solution.
!(test (collapse (let 7 (double $x) $x)) ())

;Past one unknown the rearrangement runs out and a CONSTRAINT begins: 25 = X*X
;is nonlinear and no reordering of is/2 computes it. The engine posts it to
;CLP(FD) and labels what propagation leaves, so a nonlinear inverse answers
;every solution rather than one.
(= (square $x) (* $x $x))
!(test (collapse (let 25 (square $x) $x)) (noeval (-5 5)))
!(test (collapse (let 25 (* $x $y) ($x $y)))
       (noeval ((-25 -1) (-5 -5) (-1 -25) (1 25) (5 5) (25 1))))

;A domain the constraint leaves unbounded has nothing finite to search, and
;deciding a polynomial equation over the integers is undecidable in general
;(Hilbert's tenth problem), so the engine refuses BY NAME instead of guessing
;or raising SWI's bare "Arguments are not sufficiently instantiated":
;
;  !(let 10 (+ $x $y) ($x $y))
;  + ran backwards with more than one unknown, and what the constraint leaves
;  has no finite domain to search ...
;
;Bounding the unknowns first is what the message asks for, and the # family is
;how a MeTTa program bounds one. Then propagation alone decides it.
!(test (collapse (let True (#>= $x 0) (let 25 (square $x) $x))) (5))

;THE LIMIT, and the # family's real advantage. Ordinary evaluation is
;inside-out, so a composed backward query asks the INNER operation to run with
;two unknowns before the outer one exists: (let 20 (* (+ $a 1) 4) $a) refuses,
;because (+ $a 1) is reached with both $a and its own result unbound. The #
;operators POST rather than solve, so the inner constraint waits for the outer
;one to narrow it, and the same query answers. That is why
;examples/ch05-equations-and-evaluation/05-04-arithmetic-that-runs-backwards/02-relational_arithmetic.metta is still its own file.
!(test (let 20 (#* (#+ $a 1) 4) $a) 4)

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
