;A translator rule rewrites a call at compile time, and the rule's own head is
;a pattern like any other equation head. So a rule can carry a GUARD: it names
;the shape it rewrites, and a call of another shape is left to ordinary
;dispatch.

;This one rewrites a pair addition only when both arguments are written as
;pairs, which is the shape the rewrite knows how to add.
(: add-pairs (-> Atom Atom %Undefined%))
(= (add-pairs (pair $a $b) (pair $c $d))
   (noeval (pair (+ $a $c) (+ $b $d))))
!(add-translator-rule! add-pairs)

!(test (add-pairs (pair 1 2) (pair 10 20)) (pair 11 22))

;A call the rule does not match is not an error. It carries on to ordinary
;dispatch, and a name with equations is a function there, so a miss has no
;answer rather than bringing the translation down with it.
!(test (collapse (add-pairs 1 2)) ())

;That is what lets a guarded rule live inside a definition at all. Before the
;rule fell through, a definition holding a call the rule did not match failed
;to compile.
(= (holds-a-miss) (add-pairs 1 2))

!(test (collapse (holds-a-miss)) ())

;To hand a miss back as DATA instead, write the identity as a second equation.
;The rule tries them in order, so the guarded one still wins where it fits,
;and `noeval` stops the expansion from going round again.
(: hold-pairs (-> Atom Atom %Undefined%))
(= (hold-pairs (pair $a $b) (pair $c $d))
   (noeval (pair (+ $a $c) (+ $b $d))))
(= (hold-pairs $a $b) (noeval (noeval (hold-pairs $a $b))))
!(add-translator-rule! hold-pairs)

!(test (hold-pairs (pair 1 2) (pair 10 20)) (pair 11 22))
!(test (hold-pairs 1 2) (hold-pairs 1 2))

;The engine's own stream operations are written that way. `union` rewrites two
;superpositions into one `union-atom` over their collapses, and hands anything
;else back as the data it was written as.
!(test (collapse (union (superpose (1 2)) (superpose (2 3)))) (1 2 2 3))
!(test (union foo bar) (union foo bar))
