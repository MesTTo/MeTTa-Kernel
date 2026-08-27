(= (map-flat $f ()) ())
;The recursive tail is SEQUENCED before the cons. `cons` is `cons-atom`'s
;un-suffixed spelling and its tail parameter is declared `Expression`, so the
;operation receives that operand AS WRITTEN; a `let` names the mapped tail
;first and hands the value over, which is how the reference's own stdlib
;writes every list rebuild [source: LeaTTa MettaHyperonFull/Minimal/
;Stdlib.lean:2701-2709, `map-atom`, whose recursive call is bound by a `chain`
;before `cons-atom` sees it].
(= (map-flat $f (cons $x $xs))
   (let $head ($f $x)
     (let $rest (map-flat $f $xs) (cons $head $rest))))

!(test (map-flat (+ 1) (1 2 3)) (2 3 4))

(= (map-flat2 (() $f)) ())
(= (map-flat2 ((cons $x $xs) $f))
   (let $head ($f $x)
     (let $rest (map-flat2 ($xs $f)) (cons $head $rest))))

!(test (map-flat2 ((1 2 3) (+ 1))) (2 3 4))

(: map-flat3 (-> Atom %Undefined%))
(= (map-flat3 ($f ())) ())
(= (map-flat3 ($f (cons $x $xs)))
   (let $head ($f $x)
     (let $rest (map-flat3 ($f $xs)) (cons $head $rest))))

(= (p1 $x) (+ 1 $x))

!(test (map-flat3 (p1 (1 2))) (2 3))

(: map-flat4 (-> Atom %Undefined%))
(= (map-flat4 ($v ($f ()))) ())
(= (map-flat4 ($v ($f (cons $x $xs))))
   (let $head ($f $x)
     (let $rest (map-flat4 ($v ($f $xs))) (cons $head $rest))))

!(test (map-flat4 (x (p1 (1 2)))) (2 3))

(= (wrapper $f $list) (map-flat $f $list))

!(test (wrapper (+ 1) (1 2 3)) (2 3 4))

(= (wrapper2 $f) (id $f))

!(test (wrapper2 (+ 1)) (+ 1))

(= (trickyspec $f) (if (= ($f 1) 2) (trickyspec (+ 2)) ($f 1)))

!(test (trickyspec (+ 4)) 5)
!(test (trickyspec (+ 1)) 3)

(= (fold-nested $f $init ()) $init)
(= (fold-nested $f $init (cons $x $xs))
      (if (is-expr $x)
        (fold-nested $f (fold-nested $f $init $x) $xs)
        (fold-nested $f ($f $init $x) $xs)))

!(test (fold-nested + 0 (1 (2 3))) 6)

(= (higher-order-fun $a $b) (($a 1) ($b 1)))

(= (fun2) (higher-order-fun (+ 1) (* 1)))
(= (fun3) (higher-order-fun (* 1) (+ 1)))

!(test (fun2) (2 1))
!(test (fun3) (1 2))
