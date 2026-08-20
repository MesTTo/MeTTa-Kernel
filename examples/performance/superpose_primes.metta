;test deactivated with file name extension as it is computationally expensive, only feasible with the compiler
(= (find-divisor $n $test-divisor)
   (if (> (* $test-divisor $test-divisor) $n)
       $n
       (if (== 0 (% $n $test-divisor)) 
           $test-divisor
           (find-divisor $n (+ $test-divisor 1)))))

(= (prime? $n)
   (== $n (find-divisor $n 2)))

;Four divisor searches share one branch budget, so this benchmark states a
;finite allowance above the evaluator's 100000 default.
!(test (with-pragma! ((max-stack-depth 1000000))
         ((prime? 53537257)
          (prime? 53781811)
          (prime? 54218443)
          (prime? 54734431)))
       (True True True True))
