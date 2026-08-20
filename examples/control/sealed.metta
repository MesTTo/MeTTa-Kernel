;sealed returns an Atom with fresh variables, except for variables named in
;its first argument's ignore list. The caller uses eval when it wants to run
;that returned Atom.
;
;The rename happens when the expression is compiled, not after an outer
;binding has already consumed the variable. Repeated occurrences receive one
;fresh identity.
!(test (let $atom (sealed () (let $x 2 $x)) (eval $atom)) 2)

;An unbound variable is freshened the same way.
!(test (let $atom (sealed () (let $y 5 $y)) (eval $atom)) 5)

;The ignore list keeps the surrounding identity. Every other variable in the
;returned Atom is fresh.
!(test (collapse (let $z 7 (sealed ($z) ($z $w)))) ((7 $unbound)))

;A ground Atom has no variable to rename.
!(test (sealed () 42) 42)

;Nested sealed forms produce nested data. Each eval consumes one returned
;layer, and each layer owns a distinct fresh variable.
!(test (let $atom (sealed () (let $n 2 (sealed () (let $n 3 $n))))
         (let $step (eval $atom) (eval $step)))
       3)

;--------------------------------------------------------- sealed and lambda
;A lambda renames its binders on every application. sealed freshens the other
;variables in its returned Atom. The ignored lambda parameter remains
;captured, while $fresh does not become another lambda argument.
(= (mk-tagger) (|-> ($item) (sealed ($item) (tagged $item $fresh))))
!(test (collapse (let $f (mk-tagger) (superpose (($f 1) ($f 2)))))
       ((tagged 1 $a) (tagged 2 $b)))

;An ignored variable keeps its surrounding binding.
!(test (collapse (let $outer 7 (sealed ($outer) (both $outer $local))))
       ((both 7 $c)))

;------------------------------------------------------ sealing data to store
;Freshen a rule's variables before adding it so two stored rules do not share
;one identity. let forces sealed first; placing sealed directly under add-atom
;would store the sealed expression itself.
!(let $rule (sealed () (stored-rule $r ok)) (add-atom &self $rule))
!(let $rule (sealed () (stored-rule $r ok)) (add-atom &self $rule))
!(test (collapse (match &self (stored-rule $x $y) ($x $y)))
       (($p ok) ($q ok)))

;The ignored $y keeps its binding; the unignored $x is fresh.
!(test (collapse (let $x 1 (let $y 2 (sealed ($y) (pair $x $y)))))
       ((pair $fresh 2)))

;The returned Atom stays inert until eval is asked to run it.
!(test (let $atom (sealed () (+ 1 2)) (eval $atom)) 3)
