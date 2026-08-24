(= (mymap $f ()) ())
;The recursive tail is SEQUENCED before the cons. `cons` is `cons-atom`'s
;un-suffixed spelling and its tail parameter is declared `Expression`, so the
;operation receives that operand AS WRITTEN; a `let` names the mapped tail
;first and hands the value over, which is how the reference's own stdlib
;writes every list rebuild [source: LeaTTa MettaHyperonFull/Minimal/
;Stdlib.lean:2701-2709, `map-atom`, whose recursive call is bound by a `chain`
;before `cons-atom` sees it].
(= (mymap $f (cons $x $xs))
   (let $head ($f $x)
     (let $rest (mymap $f $xs) (cons $head $rest))))

(= (eq $a $b) (== $a $b))

!(test (mymap (== 1) (1 2 3)) (mymap (eq 1) (1 2 3)))
