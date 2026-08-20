;sealed returns an Atom with fresh variables, except for variables named in
;its first argument's ignore list.
;
;The rename happens when the expression is compiled, not when it runs. That
;distinction is the whole form: done at runtime, an outer binding has already
;bound the variable and there is nothing left to rename. Before this file
;existed the form had no test and no example anywhere in the tree, and the
;case below answered nothing at all.

;Repeated occurrences receive one shared fresh identity.
!(test (sealed () (pair $x $x)) (pair $fresh $fresh))

;The ignore list preserves the identities it names.
!(test (sealed ($x) (pair $x $y)) (pair $x $fresh))

;An unignored variable is fresh even when an outer binding shares its spelling.
!(test (let $x 7 (sealed () (pair $x $x))) (pair $fresh $fresh))

;A ground Atom has no variable to rename.
!(test (sealed () 42) 42)

;The result is data. It is not evaluated as another expression.
!(sealed () (+ 1 2))

;--------------------------------------------------------- sealed and lambda
;Both exist because both are capture-avoiding renaming, at different places. A
;lambda renames its BINDERS on every application, automatically. sealed renames
;variables not named by its ignore set. LeaTTa puts the
;lambda half this way: "Before beta reduction, freshenLambda alpha-renames every
;binder in the entire lambda tree ... Free variables keep their names and are
;supplied by the surrounding rule bindings."
;
;So a sealed variable inside a lambda body is NOT a free variable of that
;lambda, and the lambda must not capture it. Applying the lambda twice gives two
;independent sealed variables.
(= (mk-tagger) (|-> ($item) (sealed ($item) (tagged $item $fresh))))
!(test (collapse (let $f (mk-tagger) (superpose (($f 1) ($f 2)))))
       ((tagged 1 $a) (tagged 2 $b)))

;An ignored variable keeps its surrounding binding. Every other variable in
;the sealed Atom is local.
!(test (collapse (let $outer 7 (sealed ($outer) (both $outer $local))))
       ((both 7 $c)))

;------------------------------------------------------ sealing data to store
;The use sealed is really for: give a rule its own variables before putting it
;in a space, so two stored rules do not share one.
;
;add-atom takes its atom AS WRITTEN, so the seal has to be forced first with a
;let. (add-atom &self (sealed () ...)) stores the sealed expression itself.
!(let $rule (sealed () (stored-rule $r ok)) (add-atom &self $rule))
!(let $rule (sealed () (stored-rule $r ok)) (add-atom &self $rule))
!(test (collapse (match &self (stored-rule $x $y) ($x $y)))
       (($p ok) ($q ok)))

;The final check pins the ignore-list half of the normative contract.
!(test (sealed ($x) (pair $x $y)) (pair $x $fresh))
