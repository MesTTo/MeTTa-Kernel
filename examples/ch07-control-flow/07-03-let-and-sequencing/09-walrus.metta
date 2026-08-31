;let* is Python's walrus: a binding usable where an expression stands, and
;visible to everything after it. The twin writes these two bodies with :=
;and compiles to exactly these equations.
(= (double-used $n)
   (let* (($big (* $n 10)))
     (+ $big $big)))
!(test (double-used 3) 60)

(= (guarded-half $n)
   (let* (($half (floor-div $n 2)))
     (if (< $half 10) $half nope)))
!(test (guarded-half 8) 4)
!(test (guarded-half 40) nope)
