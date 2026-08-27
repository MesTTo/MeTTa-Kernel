!(add-atom &self (parent tom bob))
!(add-atom &self (parent tom liz))
!(add-atom &self (parent bob ann))
!(add-atom &self (parent bob pat))
!(add-atom &self (parent pat jim))

;Writing the same match twice is where a RULE comes in. `=` gives a name to
;a form, and every later use of that shape is replaced by the right-hand
;side. This is not assignment and not a function call: it is a rewrite, and
;chapter 5 is where it becomes the subject.
(= (children-of $someone)
   (match &self (parent $someone $child) $child))

!(test (children-of tom) (bob liz))
!(test (children-of bob) (ann pat))

;A rule may use another rule, so grandchild is children-of twice. The inner
;call answers each child in turn and the outer one runs for each of those,
;which is how a two-step question is written without a loop.
(= (grandchildren-of $someone)
   (children-of (children-of $someone)))

!(test (grandchildren-of tom) (ann pat))

;And a rule that reaches no atom answers nothing, exactly as the bare match
;did. Nothing has to be written for the empty case.
!(test (collapse (children-of jim)) ())
