;The row is NAMED before cons reads it: `cons` is `cons-atom`'s spelling and
;its tail parameter is declared `Expression`, so the operand arrives as
;written. Naming the superposed pair first is what still stores one atom per
;alternative.
!(let $row (superpose ((1 (superpose (a b c)))
                       (2 (superpose (d e f)))
                       (3 (superpose (a b)))))
      (let $x (cons set $row) (add-atom &self $x)))

!(test (collapse (match &self (set $x $y) (set $x $y)))
       ((set 1 a) (set 1 b) (set 1 c) (set 2 d) (set 2 e) (set 2 f) (set 3 a) (set 3 b)))
