(= (fib $N)
   (if (< $N 2)
       $N
       (+ (fib (- $N 1))
          (fib (- $N 2)))))

;The deliberately exponential fib(30) tree exceeds the evaluator's default
;100000 fuel. Give this worked workload an explicit finite budget.
!(test (with-pragma! ((max-stack-depth 100000000)) (fib 30)) 832040)
