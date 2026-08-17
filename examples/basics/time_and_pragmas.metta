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
!(test (car-atom (elapsed (spin 100))) done)

;;; sleep answers True, so it sequences with let like any other side effect.
!(test (sleep 0.01) True)

;;; MeTTa HE's metta/3 interprets an atom in a named space. PeTTa's evalc
;;; already is that, since PeTTa's eval is full evaluation rather than minimal
;;; MeTTa's single rewriting step, so the two agree.
!(test (metta (+ 1 2) %Undefined% &self) 3)
!(test (evalc (+ 1 2) &self) 3)

;;; Pragmas. An unknown key is an ERROR naming the keys that exist, because a
;;; typo is far likelier than forward compatibility, and a setting that
;;; silently never applies is worse than one that refuses.
!(test (pragma! max-time 30) True)
!(test (pragma! max-inferences 100000000) True)
;Passing none clears a bound again.
!(test (pragma! max-time none) True)
!(test (pragma! max-inferences none) True)
