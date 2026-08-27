;The four pieces together, and one more: a rule that calls ITSELF, which is
;how a question with no fixed depth is asked.
;
;Everything here has been forward-referenced on purpose. Nothing so far said
;what a variable IS, what a space IS, or what `=` does to the engine; the
;program runs anyway, and the chapters after this one go back over each of
;them properly. That order is deliberate: a whole small program first, the
;parts after.
!(add-atom &self (parent tom bob))
!(add-atom &self (parent tom liz))
!(add-atom &self (parent bob ann))
!(add-atom &self (parent bob pat))
!(add-atom &self (parent pat jim))

(= (children-of $someone)
   (match &self (parent $someone $child) $child))

;Two equations for one name, and both apply. The first says a child is a
;descendant; the second says a child's descendants are too. There is no
;base case to write and no recursion keyword: the first equation simply
;stops answering when children-of does.
(= (descendants-of $someone)
   (children-of $someone))
(= (descendants-of $someone)
   (descendants-of (children-of $someone)))

!(test (collapse (children-of tom)) (bob liz))
!(test (collapse (descendants-of tom)) (bob liz ann pat jim))

;Reading that answer back: bob and liz are tom's children, ann and pat are
;bob's, and jim is pat's. Five descendants from five facts and three
;equations, with the search written nowhere.
!(test (collapse (descendants-of bob)) (ann pat jim))
!(test (collapse (descendants-of jim)) ())
