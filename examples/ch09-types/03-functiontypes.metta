(: wu1 (-> Number Atom %Undefined%))
(= (wu1 $a $b)
   (42 $a $b))

(: wu2 (-> Number Number Number))
(= (wu2 $a $b)
   (+ $a $b))

(: wu3 (-> Number Number %Undefined%))
(= (wu3 $a $b)
   (if (< $a 10)
       (+ $a $b)
       (a list not a number)))

; wu1's SECOND parameter is `Atom`, so `(+ 4 2)` reaches the equation as
; written and stays that way all the way out: a RESULT does not re-enter
; evaluation, so the tuple the body built is the answer. The result type does
; not change that, which wu1b shows by declaring `Atom` and answering the same
; thing [measured 2026-08-30: both spellings are `(42 6 (+ 4 2))` on this
; engine and upstream, byte-identical; source: PeTTa@ae66fa8
; src/translator.pl:25-28, whose equation compiler emits no result
; continuation at all]. The engine re-entered evaluation here until then, on
; the arbiter's returnsAtom rule, and answered `(42 6 6)` for wu1.
!(test (wu1 (+ 2 4) (+ 4 2)) (noeval (42 6 (+ 4 2))))

(: wu1b (-> Number Atom Atom))
(= (wu1b $a $b)
   (42 $a $b))

!(test (wu1b (+ 2 4) (+ 4 2)) (noeval (42 6 (+ 4 2))))

!(test (wu2 (+ 2 4) (+ 4 2)) 12)

!(test (wu3 42 0) (a list not a number))

!(test (wu3 2 0) 2)
