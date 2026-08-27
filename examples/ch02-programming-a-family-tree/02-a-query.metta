!(add-atom &self (parent tom bob))
!(add-atom &self (parent tom liz))
!(add-atom &self (parent bob ann))
!(add-atom &self (parent bob pat))
!(add-atom &self (parent pat jim))

;A question is a PATTERN and a template. match takes three things: which
;space, what shape to look for, and what to answer with when the shape fits.
;
;$child is a variable. It has no declaration and no type; it stands for
;whatever sits in that position.
!(test (match &self (parent tom $child) $child) (bob liz))

;Two atoms fit, so there are TWO answers, and the checking form above
;compared both. Many answers rather than one is the default here, and it is
;not a feature of match: any form may answer more than once.
;
;collapse turns those answers into ONE answer that is a list, which is what
;you need to hand them on to something else. Collapsing twice shows the
;difference: the inner collapse answers once, so the outer one wraps a
;single list rather than two names.
!(test (collapse (collapse (match &self (parent tom $child) $child)))
       ((bob liz)))

;The template need not be the variable alone. It is any structure, built
;with whatever the pattern bound.
!(test (match &self (parent $p ann) (mother-or-father-of-ann $p))
       (mother-or-father-of-ann bob))

;A pattern with no fitting atom answers nothing at all, which is an answer:
;collapse over it is the empty list rather than an error.
!(test (collapse (match &self (parent nobody $child) $child)) ())

;Chapter 4 is where matching becomes the subject, and chapter 6 is where
;many answers do.
