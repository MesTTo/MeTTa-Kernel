; Purpose: demonstrate guarded translator rules and their ordinary-dispatch
;   fallback.
; Guarantees: a guarded `add-pairs` miss is the empty relational result this
;   example teaches, selected explicitly from the P3 dispatch catalog.
; [tested: examples/translation/translatorrule_guard.metta; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
!(add-atom &petta (dispatch-policy add-pairs NoMatchEnum NoMatchFail))

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

;A RULE'S BODY IS ITS CONDITION, which is the other half of the same rule and
;the one a head shape cannot say. A clause applies when its head matches AND
;its body produces an expansion; a body with no answer declines, and the next
;clause is tried. So this rule rewrites `(pick a)` through its second equation,
;because the first one's body has nothing to answer for `a`.
(: pick (-> Atom %Undefined%))
(= (pick a) (empty))
(= (pick $x) (noeval (picked $x)))
!(add-translator-rule! pick)

!(test (pick a) (picked a))
!(test (pick b) (picked b))

;And when NO clause applies, the whole rule declines and the call carries on to
;ordinary dispatch, exactly as an unmatched head shape does. `only-a` has one
;equation whose body never answers, so the compiled call is an ordinary one to
;the function of the same name, which has no answer either.
(: only-a (-> Atom %Undefined%))
(= (only-a a) (empty))
!(add-translator-rule! only-a)

!(test (collapse (only-a a)) ())

;A rule is DETERMINISTIC in a way the function of the same equations is not:
;the first clause that applies supplies the expansion and the rest are never
;reached. Written as a plain function the same two equations answer twice.
(= (both-ways $x) bw-one)
(= (both-ways $x) bw-two)
!(test (collapse (both-ways q)) (bw-one bw-two))
