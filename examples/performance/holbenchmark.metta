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

(= (range $n)
   (if (== $n 0) ()
       (let $rest (range (- $n 1)) (cons $n $rest))))

;These million-step benchmark kernels state a finite budget above the
;evaluator's 100000 default.
!(test (with-pragma! ((max-stack-depth 100000000))
                     (let $temp (map-flat (+ 1) (range 1000000))
                          (length $temp)))
       1000000)


(= (fold-nested $f $init ()) $init)
(= (fold-nested $f $init (cons $x $xs))
      (if (is-expr $x)
        (fold-nested $f (fold-nested $f $init $x) $xs)
        (fold-nested $f ($f $init $x) $xs)))

(= (deep-nest $n)
   (if (== $n 0) ()
       (let $row (range 50)
         (let $rest (deep-nest (- $n 1)) (cons $row $rest)))))

!(test (with-pragma! ((max-stack-depth 100000000))
                     (fold-nested + 0 (deep-nest 20000)))
       25500000)


(= (apply-many $f $n $x)
   (if (== $n 0) $x
       (apply-many $f (- $n 1) ($f $x))))

!(test (with-pragma! ((max-stack-depth 100000000))
                     (apply-many (+ 1) 100000 0))
       100000)

(= (poly $f $n)
   (if (== $n 0) 0
       (+ ($f $n) (poly $f (- $n 1)))))

!(test (with-pragma! ((max-stack-depth 100000000))
                     (poly (+ 1) 1000000))
       500001500000)
