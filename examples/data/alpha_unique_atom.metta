; tests for alpha-unique-atom
;=alpha declares two `Atom` parameters, so both operands reach it AS WRITTEN
;and a call in that position would be compared rather than run. The result
;is NAMED first; the arbiter answers the same way for the unsequenced form
;[measured 2026-08-24: `!(=alpha (alpha-unique-atom ((link $x human)))
;((link $a human)))` is False on LeaTTa 9ea9f9d too].

; 1 Basic duplicates with different variables
!(test (let $unique (alpha-unique-atom ((link $x human) (link $y human) (link $z human)))
         (=alpha $unique ((link $a human))))
       True)

!(test (let $unique (alpha-unique-atom ((parent $x human) (parent $y human) (child $z human)))
         (=alpha $unique ((parent $a human) (child $b human))))
       True)

; 2 Different functors
!(test (let $unique (alpha-unique-atom ((parent $x human) (child $y human) (friend $z human)))
         (=alpha $unique ((parent $a human) (child $b human) (friend $c human))))
       True)

!(test (let $unique (alpha-unique-atom ((likes $x) (hates $y) (knows $z)))
         (=alpha $unique ((likes $a) (hates $b) (knows $c))))
       True)

; 3 Nested structures
!(test (let $unique (alpha-unique-atom ((link (foo $x) human) (link (foo $y) human) (link (bar $z) human)))
         (=alpha $unique ((link (foo $a) human) (link (bar $b) human))))
       True)

!(test (let $unique (alpha-unique-atom ((parent (child $x) human) (parent (child $y) human) (parent (child $x) human)))
         (=alpha $unique ((parent (child $a) human))))
       True)

; 4 Mix of unique and duplicates
!(test (let $unique (alpha-unique-atom ((link $x human) (parent $x human) (link $y human) (parent $z human) (link $x human)))
         (=alpha $unique ((link $a human) (parent $a human))))
       True)

!(test (let $unique (alpha-unique-atom ((foo $x) (foo $y) (bar $x) (foo $x) (bar $y)))
         (=alpha $unique ((foo $a) (bar $a))))
       True)

; 5 Numbers and atoms
!(test (let $unique (alpha-unique-atom (1 2 2 3 1 4 4 5))
         (=alpha $unique (1 2 3 4 5)))
       True)

!(test (let $unique (alpha-unique-atom (a b a c b d e a))
         (=alpha $unique (a b c d e)))
       True)

; 6 Empty and single-element lists
!(test (let $unique (alpha-unique-atom ())
         (=alpha $unique ()))
       True)

!(test (let $unique (alpha-unique-atom (1))
         (=alpha $unique (1)))
       True)

!(test (let $unique (alpha-unique-atom ((link $x human)))
         (=alpha $unique ((link $a human))))
       True)
