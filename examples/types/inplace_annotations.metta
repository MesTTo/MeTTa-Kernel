;A type where it can PRUNE, in a head or a match query rather than only in a
;top-level declaration. hyperon-experimental issue #177's dynamic half.
;
;`(: $x T)` matches anything of type T and binds $x to it. It is not a new
;type relation: it desugars to a plain variable plus exactly the acceptance
;the engine already compiles for a DECLARED parameter of type T, so anyone who
;knows one knows the other.

(: Ann Person)
(: Ann Employee)
(: Bob Person)
(: Rex Dog)

;Restrict a head parameter. Rex never reaches the body.
(= (greet (: $x Person)) (hello $x))
!(test (collapse (greet Ann)) ((hello Ann)))
!(test (collapse (greet Rex)) ())

;Bind the type to a variable instead, and a symbol with two declared types
;gives a branch each, because nondeterminism is native rather than added.
(= (type-of (: $x $t)) $t)
!(test (collapse (type-of Ann)) (Person Employee))
!(test (collapse (type-of Rex)) (Dog))

;One type variable in two positions constrains them to agree.
(= (same-kind (: $x $t) (: $y $t)) ($x $y))
!(test (collapse (same-kind Ann Bob)) ((Ann Bob)))
!(test (collapse (same-kind Ann Rex)) ())

;A METATYPE restriction works for the same reason and needs nothing extra:
;has_type fails on a symbol nobody declared, so the acceptance falls through
;to get-metatype. This is issue #177's fmap fixture, and the clean spelling of
;the (if (== (get-metatype $c) Symbol) $c (superpose ())) workaround.
(= (fmap $f (: $c Symbol)) ($f $c))
!(test (collapse (fmap g sym)) ((g sym)))
!(test (collapse (fmap g 42)) ())

;And in a match query, which is where it prunes the search rather than the
;call. Zeus is a God, so the restricted query does not reach him.
(: Plato Human)
(: Socrates Human)
(: Zeus God)
!(add-atom &self (knows Plato Socrates))
!(add-atom &self (knows Plato Zeus))
!(test (collapse (match &self (knows (: $x Human) (: $y Human)) ($x $y)))
       ((Plato Socrates)))
!(test (collapse (match &self (knows (: $x $t) (: $y $t)) ($x $y $t)))
       ((Plato Socrates Human)))

;--------------------------------------------- why POSITION and not a spelling
;Issue #177 raises the collision with stored `(: name type)` atoms and proposes
;`::` "when position cannot distinguish the two uses". Position can, and LeaTTa
;proved it against a mechanised Hyperon semantics. Two gates, both needed:
;
;  1. a pattern that IS a colon expression stays structural, so a knowledge
;     base query still retrieves the declarations somebody wrote;
;  2. below that, only `(: $variable expected)` is an annotation, and a colon
;     whose value slot is not a variable is data nothing looks inside.
;
;The alternative was a new spelling and this tree tried two. `::` is what
;metta-lang.dev's tutorials use as a cons constructor, so it silently turned
;list code into a non-terminating recursion. `:>` collides with nothing and
;reads as a subtype bound to anyone who has met Scala. Both are worse than the
;collision they avoid.
;
;GATE 1, demonstrated: the whole pattern is a colon expression, so this
;retrieves the stored declaration rather than annotating anything.
!(test (collapse (match &self (: Zeus $t) $t)) (God))

;`::` means nothing special to the engine, which is the point of not having
;taken it. Here is the tutorial's own list program, verbatim.
(= (list-length ()) 0)
(= (list-length (:: $x $xs)) (+ 1 (list-length $xs)))
!(test (list-length (:: A (:: B (:: C ())))) 3)

;GATE 2, demonstrated. The annotation position must hold a VARIABLE, or the
;form stays structural and nothing looks inside it. That is what lets
;examples/reasoning/nilbc.metta keep its 134 `(: proof theorem)` terms: every
;one whose value slot is an expression is ordinary data, untouched.
(= (shape-of (: a $rest)) $rest)
!(test (collapse (shape-of (: a tail))) (tail))
!(test (collapse (shape-of (: z tail))) ())
