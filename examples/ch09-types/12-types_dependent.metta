;=alpha throughout, not ==. Each comparison here crosses KNOWN and different
;types, which == refuses by name: (% $x 2) is caught as an error term when $x
;is not a number, and (get-type $head) answers a type where EvenNumber is a
;symbol. =alpha is the comparison that takes anything.
;get-type extension for numbers:
;=alpha declares two `Atom` parameters, so `(% $x 2)` would reach it as WRITTEN
;and be compared with 0 rather than run. The remainder is NAMED first, which is
;what makes the extension fire; the arbiter answers False for the unsequenced
;form too [measured 2026-08-24: `!(=alpha (% 2 2) 0)` is False on LeaTTa
;9ea9f9d].
(= (get-type $x)
   (catch (let $remainder (% $x 2)
            (if (=alpha $remainder 0)
                EvenNumber))))

;try it:
(: f (-> EvenNumber EvenNumber EvenNumber))
(= (f $x $y)
   (+ $x $y))

!(test (f 2 4) 6)

;get-type extension for list of even numbers:
(= (get-type (cons $head $tail))
   (let $head-type (get-type $head)
     (if (=alpha $head-type EvenNumber)
         (if (=alpha $tail ())
             EvenNumberList
             (get-type $tail)))))

;try it:
(: g (-> EvenNumberList Bool))
(= (g $L)
   True)

!(test (g (2 4 6)) True)
