; A conditional arm whose value collapses to a clause parameter must not
; capture the clause's output at translate time: the other arm still runs
; its own unification. Found by differential fuzzing of compiled programs.
(= (pick-else $a $b) (if (< $a $a) (let* (($c $a)) $a) $b))
!(test (pick-else 1 2) 2)
(= (pick-then $a $b) (if (> $a 0) (let* (($c $a)) $a) $b))
!(test (pick-then 1 2) 1)
; The same shape through case, which builds its branches the same way.
(= (case-else $a $b) (case (< $a $a) ((True (let* (($c $a)) $a)) (False $b))))
!(test (case-else 3 4) 4)
; Both arms parameter-valued, both directions.
(= (both $a $b) (if (> $a $b) (let* (($c 1)) $a) (let* (($d 1)) $b)))
!(test (both 5 2) 5)
!(test (both 2 5) 5)
