;A space can redefine a function it inherits, and `super` is how the new
;definition reaches the old one. Without it an override is replace-or-nothing:
;a guard that wants to check a call and then let it through has no way through.

;The definition every space below this one inherits.
(= (store $atom) (stored $atom))

;A space that gates it. `super` names the next definition up THIS space's
;chain, which is the one above, so the guard delegates without naming it.
!(bind! &guarded (new-space))
!(add-atom &guarded (= (store $atom)
                       (if (== $atom bad) refused (super (store $atom)))))

;The guard lets an ordinary atom through to the definition it shadows,
!(test (evalc (store good) &guarded) (stored good))
;and refuses the one it was written to refuse.
!(test (evalc (store bad) &guarded) refused)

;The space above is untouched by the shadow, which is what makes a shadow a
;shadow rather than a replacement.
!(test (store bad) (stored bad))

;`super` reaches the ENGINE's own definitions too, so a builtin can be
;WRAPPED rather than only replaced.
!(bind! &wrapping (new-space))
!(add-atom &wrapping (= (car-atom $expr) (wrapped (super (car-atom $expr)))))

!(test (evalc (car-atom (1 2 3)) &wrapping) (wrapped 1))

;And every other space still gets the builtin it always had.
!(test (car-atom (1 2 3)) 1)

;`evalc` is the other direction, and both are worth having: it names the space
;to evaluate in, absolutely, where `super` names the next definition along,
;relatively. Absolute addressing does not compose. Two guards on one name,
;each delegating to the same named space, both run, and an atom the first
;refuses is stored anyway by the second, because neither of them names the
;other.
!(test (evalc (store good) &self) (stored good))
