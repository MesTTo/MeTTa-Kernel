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

; Too many arguments raise, both for compiled and runtime-dispatched calls,
; and the raise names the arities the function HAS beside the one the call
; asked for. A head that names nothing is left as written instead, because
; there is no arity to be wrong about.
!(test (repr (catch (+ 1 2 3)))
       "(Error (domain_error (function_input_arities + (2)) 3) none)")
!(test (repr (catch (reduce (+ 1 2 3))))
       "(Error (domain_error (function_input_arities + (2)) 3) none)")
!(test (repr (catch (empty 1 2)))
       "(Error (domain_error (function_input_arities empty (0)) 2) none)")
!(test (nosuchfn 1 2 3) (nosuchfn 1 2 3))

; A gap between overloaded arities is still a valid partial application.
(= (overloaded-curry $a) $a)
(= (overloaded-curry $a $b $c) (+ $a (+ $b $c)))
!(test (repr (overloaded-curry 1 2)) "(partial overloaded-curry (1 2))")
