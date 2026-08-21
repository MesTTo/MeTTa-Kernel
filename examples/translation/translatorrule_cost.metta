; Purpose: demonstrate a translator rule that carries a COST, and one whose
;   left side is a CONJUNCTION of patterns rather than a single head.
; Guarantees: the declared cost decides which of two equivalent forms the
;   compiler emits, and a conjunctive left side joins its patterns on the
;   variables they share.
; [tested: examples/translation/translatorrule_cost.metta; commit=WORKTREE]

;A bidirectional rule says two forms are equivalent. Something then has to
;choose which one the compiler emits, and that is what a COST is for: an
;e-graph extractor minimises exactly this number over the forms a term can
;take. A rewrite fires only when it lowers the total, and a form's cost is
;its node count unless a rule declares one for its head.
(: pow2 (-> Atom %Undefined%))
(= (pow2 $x) (noeval (mul $x $x)))
!(add-translator-rule! pow2 ((direction bidirectional) (cost 10)))

;`(pow2 3)` costs 10 for the head plus 1 for the argument; `(mul 3 3)` costs
;three nodes. So the squaring is expanded.
!(test (pow2 3) (mul 3 3))

;The same declaration collapses the multiplication back when the argument is
;big enough to make writing it twice the more expensive side: eleven nodes
;each way against ten plus the head's ten.
!(test (mul (a b c d e f g h i j) (a b c d e f g h i j))
       (pow2 (a b c d e f g h i j)))

;Without the declared cost the head would count as one node like any other,
;and both of those calls would collapse to `pow2`. The cost is the whole
;difference.

;A CONJUNCTIVE left side names several patterns that must all match. The
;first is the call the rule rewrites and the rest are matched against the
;space, so a rule can look at the program around the call it is rewriting.
(unit mass kg)
(unit length m)

(: unit-of (-> Atom %Undefined%))
!(add-translator-rule! unit-of
   ((left ((unit-of $q) (unit $q $u)))
    (right (in $u))))

;`$q` joins the call to the space pattern and `$u` carries the answer out.
;Nothing here merges substitutions: the patterns are one written form, so
;they share their variables already.
!(test (unit-of mass) (in kg))
!(test (unit-of length) (in m))

;A call whose conjuncts do not match is a rule miss like any other, so it has
;no answer rather than bringing the translation down.
!(test (collapse (unit-of time)) ())

;The rule compiles to the equation an author would have written by hand, with
;the conjuncts as a `match` chain: the engine's own conjunctive query does the
;join.
!(test (match &self (= (unit-of $q) $body) (car-atom $body)) match)
