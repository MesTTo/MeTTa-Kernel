!(import! &self (library lib_pln))

(= (STV A) (stv 0.5 0.9))
(= (STV B) (stv 0.25 0.9))
(= (STV C) (stv 0.25 0.9))
(= (STV D) (stv 0.5 0.9))

(= (kb)
   ((Sentence ((Inheritance A B) (stv 0.25 0.9)) (1))
    (Sentence ((Inheritance A C) (stv 0.25 0.9)) (2))
    (Sentence ((Inheritance B D) (stv 0.5 0.9)) (3))
    (Sentence ((Inheritance C D) (stv 0.5 0.9)) (4))
   ))

;The bounded proof search is intentionally larger than the evaluator's default
;100000 fuel, so the example states its own finite budget.
!(test (with-pragma! ((max-stack-depth 100000000))
                     (PLN.Query (kb) (Inheritance A D)))
       ((stv 0.5 0.9473684210526316) (1 2 3 4)))
