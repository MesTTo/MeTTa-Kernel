!(add-atom &self (= (fib $N)
                    (if (< $N 2)
                        $N
                        (+ (fib (- $N 1))
                           (fib (- $N 2))))))

;The deliberately exponential fib(30) tree exceeds the evaluator's default
;100000 fuel, including when its equation arrived through add-atom.
!(test (with-pragma! ((max-stack-depth 100000000)) (fib 30)) 832040)
