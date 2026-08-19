;=alpha throughout, not ==. Each comparison here crosses KNOWN and different
;types, which == refuses by name: (% $x 2) is caught as an error term when $x
;is not a number, and (get-type $head) answers a type where EvenNumber is a
;symbol. =alpha is the comparison that takes anything.
;get-type extension for numbers:
(= (get-type $x)
   (catch (if (=alpha (% $x 2) 0)
              EvenNumber)))

;try it:
(: f (-> EvenNumber EvenNumber EvenNumber))
(= (f $x $y)
   (+ $x $y))

!(test (f 2 4) 6)

;get-type extension for list of even numbers:
(= (get-type (cons $head $tail))
   (if (=alpha (get-type $head) EvenNumber)
       (if (=alpha $tail ())
           EvenNumberList
           (get-type $tail))))

;try it:
(: g (-> EvenNumberList Bool))
(= (g $L)
   True)

!(test (g (2 4 6)) True)
