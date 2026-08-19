(= (f $a $b) (+ $a $b))

(= (g $a $b $c) (+ $c (+ $a $b)))

(= (show) (repr (f 1)))

!(test (repr (f 1)) "(partial f (1))")
!(test ((f 1) 2) 3)
!(test (repr (g 1 2)) "(partial g (1 2))")

(= (h $A $B)
   (append ($A) $B))

!(test ((h 42) (1 2 3)) (42 1 2 3))
!(test (repr (h 42)) "(partial h (42))")
!(test (map-atom (1 2 3) (+ 1)) (2 3 4))

; Too many arguments are an error, both for compiled and runtime-dispatched
; calls, and the error is an ANSWER: no catch stands between the call and it,
; and the form after it still runs. A head nothing TYPES is left as written
; instead, because there is no arity to be wrong about.
!(test (+ 1 2 3) (Error (+ 1 2 3) IncorrectNumberOfArguments))
!(test (reduce (+ 1 2 3)) (Error (+ 1 2 3) IncorrectNumberOfArguments))
!(test (empty 1 2) (empty 1 2))

; A gap between overloaded arities is still a valid partial application.
(= (overloaded-curry $a) $a)
(= (overloaded-curry $a $b $c) (+ $a (+ $b $c)))
!(test (repr (overloaded-curry 1 2)) "(partial overloaded-curry (1 2))")
