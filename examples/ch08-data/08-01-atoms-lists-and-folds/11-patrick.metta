!(import! &self (library lib_patrick))

;The as-pattern names the whole argument and destructures it at the same
;time. It is a function, so it goes in the body under a `let` that unifies it
;with the argument: a head is a pattern and matches structurally.
(= (mirror $A)
   (let $A (@ $L (cons $head $tail))
        (append (reverse $L) $tail)))

!(test (mirror (h a n n e s)) (s e n n a h a n n e s))

!(test (collapse (for $x (1 2 3 4 5 6)
                      (if (> $x 3) $x)))
       (4 5 6))
      
!(test (iterate 0 10
                1 (|-> ($i $x)
                       (+ $x $i)))
       46)
