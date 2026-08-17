;sealed makes the variables you name local to an expression. HE's own wording:
;"Replaces all occurrences of any var from var list inside atom by unique
;variable. Can be used to create a locally scoped variables."
;
;The rename happens when the expression is compiled, not when it runs. That
;distinction is the whole form: done at runtime, an outer binding has already
;bound the variable and there is nothing left to rename. Before this file
;existed the form had no test and no example anywhere in the tree, and the
;case below answered nothing at all.

;The canonical use. $x is 1 outside and 2 inside, and the two do not collide.
!(test (let $x 1 (sealed ($x) (let $x 2 $x))) 2)

;Sealing a variable that has no outer binding is simply a local variable.
!(test (sealed ($y) (let $y 5 $y)) 5)

;Only what you list is renamed. $z is not listed, so the expression still sees
;the outer 7; $w is listed, so it stays free.
!(test (collapse (let $z 7 (sealed ($w) ($z $w)))) ((7 $unbound)))

;Sealing nothing is the expression itself.
!(test (sealed () 42) 42)

;It nests, and each level's seal is its own.
!(test (let $n 1 (sealed ($n) (let $n 2 (sealed ($n) (let $n 3 $n))))) 3)

;--------------------------------------------------------- sealed and lambda
;Both exist because both are capture-avoiding renaming, at different places. A
;lambda renames its BINDERS on every application, automatically. sealed renames
;variables you NAME, in an atom that has no binder structure. LeaTTa puts the
;lambda half this way: "Before beta reduction, freshenLambda alpha-renames every
;binder in the entire lambda tree ... Free variables keep their names and are
;supplied by the surrounding rule bindings."
;
;So a sealed variable inside a lambda body is NOT a free variable of that
;lambda, and the lambda must not capture it. Applying the lambda twice gives two
;independent sealed variables.
(= (mk-tagger) (|-> ($item) (sealed ($fresh) (tagged $item $fresh))))
!(test (collapse (let $f (mk-tagger) (superpose (($f 1) ($f 2)))))
       ((tagged 1 $a) (tagged 2 $b)))

;A free variable inside a sealed expression keeps its surrounding binding; only
;the named ones are localised.
!(test (collapse (let $outer 7 (sealed ($local) (both $outer $local))))
       ((both 7 $c)))

;------------------------------------------------------ sealing data to store
;The use sealed is really for: give a rule its own variables before putting it
;in a space, so two stored rules do not share one.
;
;add-atom takes its atom AS WRITTEN, so the seal has to be forced first with a
;let. (add-atom &self (sealed ($r) ...)) stores the sealed expression itself.
!(let $rule (sealed ($r) (stored-rule $r ok)) (add-atom &self $rule))
!(let $rule (sealed ($r) (stored-rule $r ok)) (add-atom &self $rule))
!(test (collapse (match &self (stored-rule $x $y) ($x $y)))
       (($p ok) ($q ok)))

;----------------------------------------------- two divergences from upstream
;Both are pinned here so neither can drift without a test saying so.
;
;FIRST: the first argument's ROLE is inverted. This file's opening quote is
;HE's own older wording, "any var FROM VAR LIST", and PeTTa implements exactly
;that: the listed variables are the ones renamed. The current corelib dump says
;the opposite, "any var inside atom, EXCEPT list of variables to ignore"
;[source: LeaTTa/stdlib.md, the sealed entry]. So where PeTTa renames what you
;name, upstream renames everything you did NOT name.
;
;PeTTa's reading is what makes PeTTa's own uses work, every one of them above:
;you name the variable you want local. Under upstream's, the same call would
;localise the surrounding variables instead and the outer binding would be lost.
!(test (collapse (let $x 1 (let $y 2 (sealed ($x) (pair $x $y)))))
       ((pair $fresh 2)))

;SECOND: PeTTa EVALUATES the sealed expression where upstream answers the
;renamed atom as data. Upstream prints `[(pair $x#19 $x#19)]` for a sealed
;pair, the atom with its variables freshened and nothing reduced. PeTTa reduces
;it, so a sealed arithmetic expression comes back as a number and an unlisted
;variable arrives already bound, which is the 2 above rather than a `$y`.
;Evaluating is consistent with the rest of PeTTa, and `quote` is how to get the
;atom instead.
!(test (sealed ($v) (+ 1 2)) 3)
