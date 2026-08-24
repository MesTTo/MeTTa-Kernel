!(import! &self (library lib_nars))

;PLN IMPLICATION TO CLAUSE COMPILATION EXTENSION:
(: => (-> Atom Atom %Undefined% %Undefined%))
;A premise contributes only when it HAS a truth value: a term nothing defines
;reduces to itself, which is not one, and the (stv ...) pattern is what says
;so. Written as an equation rather than inline in the map below, because a
;lambda CAPTURES its free variables: inline, one (stv $s $conf) pattern is
;shared by every element and the second premise would have to match the
;first one's numbers. An equation gets fresh variables per call.
(: premise-truth (-> Atom %Undefined%))
(= (premise-truth $p) (let (stv $s $conf) (reduce $p) (stv $s $conf)))

;foldl-atom's list parameter is Expression and holds its operand as written,
;so the premises reach the fold as the conjunction's TERMS rather than as
;their truth values, and the map above is what turns them into values. The
;map also keeps the premises' shared variables bound TOGETHER, so each joint
;solution is one premise list.

(= (=> (cons , $args) $C $stvImp)
       (progn (cut)
         (add-atom &self
           (= $C (let $premises (map-atom $args $p (premise-truth $p))
                   (Truth_Deduction (foldl-atom $premises (stv 1.0 1.0) Truth_Deduction)
                         $stvImp))))))
(= (=> $A $C $stvImp)
   (add-atom &self (= $C (Truth_Deduction $A $stvImp))))

(: ? (-> Atom %Undefined%))
(= (? $term)
   ;unique-atom declares an `Expression` parameter, so the collapsed bag is
   ;NAMED before it reads it.
   (let $answers (collapse ($term (progn (reduce $term) ;ensures binding to specific answer, then combines evidence for all derived variants:
                                         ;foldl-atom's list parameter is Expression and holds its
                                         ;operand as written, so the collapsed evidence is NAMED first.
                                         (let $evidence (collapse (reduce $term))
                                           (foldl-atom $evidence (stv 0.5 0.0) Truth_Revision)))))
     (unique-atom $answers)))

;EXAMPLE:
!(=> (, (father $a $b) (father $b $c)) (grandfather $a $c) (stv 1.0 0.9))
!(=> (, (father $a $b) (mother $b $c)) (grandfather $a $c) (stv 1.0 0.9))
!(=> (grandfather $a $x) (old $a) (stv 1.0 0.9))

(= (father a b) (stv 1.0 0.9))
(= (father b c) (stv 1.0 0.9))

(= (father a y) (stv 1.0 0.9))
(= (mother y c) (stv 0.0 0.9))

!(test (? (grandfather a c))
       (noeval (((grandfather a c) (stv 1.0 0.7290000000000001)))))
!(test (? (grandfather $who c))
       (noeval (((grandfather a c) (stv 1.0 0.7290000000000001)))))
!(test (? (old $who))
       (noeval (((old a) (stv 1.0 0.6561000000000001)))))

