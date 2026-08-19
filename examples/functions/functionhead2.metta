;Check out functionhead.metta!
(= (living garfield) True)
(= (being garfield) True)
(= (small garfield) True)
(= (living snoopy) True)
(= (being snoopy) True)
(= (being roomba) True)
(= (small roomba) True)
(= (living cat42) True)
(= (being cat42) True)
(= (small cat42) True)

(= (only $C $X)
   (let $constraint $C $X))

(= (animal $X)
   (only ((living $X) (being $X)) $X))

;The relational constraint on the input goes in the body, where `let` unifies
;the argument with what `animal` produces. A head is a pattern, matched
;structurally, so it cannot ask for an argument that a call can produce.
(= (cat $A)
   (let $A (animal $X)
        (only (small $X) $X)))

!(test (msort (collapse (cat $X)))
       (cat42 garfield))
;Check out functionhead3.metta!
