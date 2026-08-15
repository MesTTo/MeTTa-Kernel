;A table answers from the equations compiled when it was built, so
;changing an equation makes it stale. The engine's own change funnel
;drops the tables, and the next call rebuilds them.

!(import! &self (library lib_tabling))

(= (pick $x) one)

!(tabled (pick $x))

!(test (collapse (pick a)) (one))
!(test (collapse (pick a)) (one))

;A second equation for the same function. Without invalidation the table
;keeps answering (one).
(= (pick $x) two)

!(test (collapse (pick a)) (one two))

;Removing one again.
!(remove-atom &self (= (pick $x) one))

!(test (collapse (pick a)) (two))
