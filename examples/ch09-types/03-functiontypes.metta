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
; written; its `%Undefined%` RESULT then sends the tuple the body built back
; through evaluation, and that is where the sum reduces. Both halves of the
; rule are the arbiter's own and it answers the same
; [measured 2026-08-24: `!(wu1 (+ 2 4) (+ 4 2))` is `(42 6 6)` on LeaTTa
; 9ea9f9d]. Declaring the result `Atom` instead is what keeps the operand
; unreduced all the way out, which wu1b below shows.
!(test (wu1 (+ 2 4) (+ 4 2)) (42 6 6))

(: wu1b (-> Number Atom Atom))
(= (wu1b $a $b)
   (42 $a $b))

!(test (wu1b (+ 2 4) (+ 4 2)) (noeval (42 6 (+ 4 2))))

!(test (wu2 (+ 2 4) (+ 4 2)) 12)

!(test (wu3 42 0) (a list not a number))

!(test (wu3 2 0) 2)
