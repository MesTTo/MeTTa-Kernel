; Purpose: demonstrate a translator rule that declares its DIRECTION, and a
;   bidirectional rule whose inverse the engine derives instead of the author
;   writing it twice.
; Guarantees: both directions of one declaration fire here, and which one
;   fires is decided per call by the form's cost, so neither runs away.
; [tested: examples/ch20-extending-the-engine/20-01-translator-rules/02-translatorrule_direction.metta; commit=9330b5d7ebf607e34a85be950bb226fce65f45c0]

;A rule is left-to-right by default, and saying so explicitly changes nothing.
(: celsius (-> Atom %Undefined%))
(= (celsius (degrees $c)) (noeval (kelvin (+ $c 273))))
!(add-translator-rule! celsius ((direction forward)))

!(test (celsius (degrees 27)) (kelvin 300))

;A BIDIRECTIONAL rule is ONE declaration. The engine derives the inverse
;equation and registers the head it is rooted at; nobody writes it out. egg's
;own users write it out: TenSat's rewrites.rs opens with a note that egg now
;has bidirectional rules "which should cut down this list in half" and then
;lists about forty rules twice, the second copy prefixed with a minus.
(: unpack (-> Atom %Undefined%))
(= (unpack (wrap (box $x))) (noeval (twin $x $x)))
!(add-translator-rule! unpack ((direction bidirectional)))

;Both sides are now rewritable, so something has to decide which way a given
;call goes, or the two rewrite each other forever. The decision is the form's
;COST, and a rewrite fires only when it LOWERS it. Cost here is the node
;count: `(unpack (wrap (box 1)))` is four nodes and `(twin 1 1)` is three, so
;this call goes forwards.
!(test (unpack (wrap (box 1))) (twin 1 1))

;The same rule goes the other way when the argument is big enough to turn the
;count around: `(twin (a b c) (a b c))` is seven nodes and
;`(unpack (wrap (box (a b c))))` is six, because the argument is written twice
;on one side and once on the other.
!(test (twin (a b c) (a b c)) (unpack (wrap (box (a b c)))))

;A call already at its cheapest is left alone. That is the normal form of the
;rewrite, and the compiler hands the form back as the data it was written as.
!(test (twin 1 1) (twin 1 1))
!(test (unpack (wrap (box (a b c)))) (unpack (wrap (box (a b c)))))

;Withdrawing the rule withdraws the derived equation with it, so the inverse
;never outlives the declaration that produced it.
!(remove-translator-rule! unpack)

!(test (twin (a b c) (a b c)) (twin (a b c) (a b c)))
