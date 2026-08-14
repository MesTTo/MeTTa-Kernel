!(import! &self (library lib_tabling))

(= (fib $N)
   (if (< $N 2)
       $N
       (+ (fib (- $N 1))
          (fib (- $N 2)))))

;Declare AFTER defining: tabling instruments the compiled function, so
;the name is refused loudly while it does not exist yet.
!(tabled (fib $N))

!(test (fib 30) 832040)
