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

;Backwards.
!(test (let 5 (#+ $x 2) $x) 3)
!(test (let 12 (#* $y 4) $y) 3)
!(test (let 6 (#- $z 4) $z) 10)

;------------------------------------------- the ORDINARY operators invert too
;
;This is where the # family's reason to exist actually lies, and it is not
;"ordinary arithmetic cannot run backwards", which this file used to say. It
;can. + - * / each solve for ONE unbound slot among integers, so a function
;written forwards reads backwards for free.
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
;one to narrow it, and the same query answers.
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
