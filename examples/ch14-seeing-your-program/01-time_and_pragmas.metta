; Purpose: demonstrate time control, enforced pragmas, and relational arithmetic.
; Guarantees:
;   - every demonstrated pragma changes a live execution bound.
;   [tested: interpreter_pragmas; commit=e8270f8551083f236ce5134ca299adf5347d6898]
;
;Time control and interpreter pragmas, all core: no import needed.
;
;(sleep $seconds) suspends this evaluation. (timeout $seconds $expr) bounds an
;expression by wall clock. (elapsed $expr) answers what it produced together
;with what it cost. (pragma! $key $value) sets an interpreter setting.
;
;timeout and elapsed are special forms rather than functions, because their
;expression must reach them UNEVALUATED: as ordinary functions the argument
;would already have been computed, so the bound would apply to finished work
;and the clock would start after the work it is meant to time.

(= (spin $n) (if (> $n 0) (spin (- $n 1)) done))

;;; A bound that is not reached is invisible.
!(test (timeout 30 (spin 100)) done)
!(test (timeout 30 (+ 1 2)) 3)

;;; Crucially, bounding an expression does NOT collapse it to one answer. The
;;; built-in call_with_time_limit is once/1, so the obvious implementation
;;; would have answered (1) here.
!(test (collapse (timeout 30 (superpose (1 2 3)))) (1 2 3))

;;; elapsed answers (Value Seconds), so timing a call does not mean writing
;;; the clock by hand. Only the value is asserted here; the duration is real
;;; but not reproducible enough to assert on.
;The value is NAMED before the family operation reads it. `car-atom` and
;`size-atom` declare `Expression` parameters, so the operand reaches them AS
;WRITTEN; a `let` runs the form first and hands the answer over. The
;demonstration is unchanged, and so is the expected value
;[measured 2026-08-24: `!(let $v ((+ 1 2) b) (car-atom $v))` is 3 on LeaTTa
;9ea9f9d and on this engine].
!(test (let $timed (elapsed (spin 100)) (car-atom $timed)) done)

;;; sleep answers True, so it sequences with let like any other side effect.
!(test (sleep 0.01) True)

;;; MeTTa HE's metta/3 interprets an atom in a named space. MeTTa's evalc
;;; already is that, since MeTTa's eval is full evaluation rather than minimal
;;; MeTTa's single rewriting step, so the two agree.
!(test (metta (+ 1 2) %Undefined% &self) 3)
!(test (evalc (+ 1 2) &self) 3)

;;; Pragmas. Each answers the unit value (), the way add-atom and println! do.
;;; Every key must be in the interpreter registry. An unsupported key raises
;;; instead of pretending it changed evaluation. A bound's value is checked
;;; before it replaces a working setting: max-time takes positive seconds and
;;; max-inferences takes a positive integer.
!(test (pragma! max-time 30) ())
!(test (pragma! max-inferences 100000000) ())
;Passing none clears a bound again.
!(test (pragma! max-time none) ())
!(test (pragma! max-inferences none) ())

;;; max-stack-depth answers its own error rather than raising: the count it
;;; requires is checked in the answer, so the program that wrote it runs on.
!(test (pragma! max-stack-depth 0) ())
!(test (pragma! max-stack-depth -1)
       (Error (pragma! max-stack-depth -1) UnsignedIntegerIsExpected))
!(test (pragma! max-stack-depth none) ())

;;; A positive stack-depth setting caps the evaluator's branch-local fuel. A
;;; finite sibling survives when an overlapping recursive branch runs out.
!(pragma! max-stack-depth 20)
(= (bounded-factorial 0) 1)
(= (bounded-factorial $n) (* $n (bounded-factorial (- $n 1))))
;The answer group is (120 (Error -3 StackOverflow)).
!(bounded-factorial 5)
!(pragma! max-stack-depth none)

;;; (inferences $n $expr) is timeout's deterministic twin, the same
;;; kwarg vocabulary the Python tier's run(inferences=) speaks: the bound
;;; stops at the same step on every machine. A bound not reached is
;;; invisible, and the whole answer set computes under it.
!(test (inferences 100000 (spin 100)) done)
!(test (collapse (inferences 100000 (superpose (1 2 3)))) (1 2 3))

;;; (with-pragma! $settings $expr) scopes settings to ONE expression:
;;; the previous values come back on every exit path, and a bound that is
;;; not reached is invisible. Expiry is a CONTROL signal, so no catch can
;;; eat a budget, the same law the per-call kwargs follow; the expiring
;;; case is pinned in tests/prolog/suites/evaluation/metta.plt where a throw is assertable.
!(test (with-pragma! ((max-inferences 100000)) (+ 20 22)) 42)
!(test (with-pragma! ((max-time 30) (max-inferences 100000)) (spin 100)) done)
!(test (spin 2000) done)

;;; Relational integer arithmetic: one unbound argument among integers
;;; solves for it, so arithmetic runs BACKWARDS through let and unify.
;;; Exactness is honest: no integer doubles to 7, so that branch answers
;;; nothing rather than something approximate.
!(test (let 4 (- $x 1) $x) 5)
!(test (let 10 (+ $x 3) $x) 7)
!(test (let 6 (* $x 2) $x) 3)
!(test (let 3 (/ $x 2) $x) 6)
!(test (collapse (let 7 (* $x 2) $x)) ())
