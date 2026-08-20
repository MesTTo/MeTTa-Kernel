!(import! &self (library lib_he))

(= (div $x $y $accum)
   (chain (eval (- $x $y)) $r1
     (chain (eval (< $r1 0)) $r2
       (chain (unify $r2 True
         $accum
         (chain (eval (+ 1 $accum)) $inc
           (chain (eval (div $r1 $y $inc)) $r4 $r4)
         )) $r3 $r3
       )
     )
   )
)

;The 70000-step interpreter exercise states a budget above the engine default.
!(test (with-pragma! ((max-stack-depth 1000000))
                     (chain (eval (div 350000 5 0)) $rr $rr))
       70000)
