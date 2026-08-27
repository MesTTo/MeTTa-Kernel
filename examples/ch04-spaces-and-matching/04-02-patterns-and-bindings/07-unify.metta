;unify is the stdlib's matching conditional: (unify a b then else) runs
;the then branch once per binding set under which a and b match, and the
;else branch exactly when no binding set exists. The operands cross
;unevaluated, all four arguments are typed Atom, and only the selected
;branch runs.

;Ground decisions, including numeric promotion: 1 matches 1.0.
!(test (unify 1 1 same different) same)
!(test (unify 1 2 same different) different)
!(test (unify 1 1.0 same different) same)
!(test (unify "x" "x" same different) same)
!(test (unify "x" "y" same different) different)

;Bindings flow from the match into the branch, both directions at once.
!(test (unify (f $x b) (f a $y) (pair $x $y) nope) (pair a b))

;The occurs check rejects a cyclic binding.
!(test (unify $x (f $x) cyclic sound) sound)

;Only the selected branch evaluates: each probe leaves a marker, and
;exactly one marker lands per query.
(= (then-probe) (chain (add-atom &self then-ran) $_ 3))
(= (else-probe) (chain (add-atom &self else-ran) $_ 4))
!(test (unify A A (then-probe) (else-probe)) 3)
!(test (collapse (match &self else-ran hit)) ())
!(test (unify A B (then-probe) (else-probe)) 4)
!(test (collapse (match &self then-ran hit)) (hit))

;A space is a grounded atom whose custom matching is query, so a space
;operand routes through match: one then-answer per stored match, the
;else branch when nothing matches.
(friend Bob Alice)
(friend Sam Alice)
!(test (collapse (unify &self (friend $who Alice) $who no-friends))
       (Bob Sam))
!(test (unify &self (friend Pol $who) $who no-friends) no-friends)

;A variable operand binds the space whole without querying it.
!(test (unify $s &self bound queried) bound)

;Empty in a branch is the branch remover: the else here answers nothing
;at all, so collapse answers the empty list.
!(test (collapse (unify a b then Empty)) ())
