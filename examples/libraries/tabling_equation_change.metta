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

;sort-atom, because a TABLED function does not answer in clause order. Answers
;come out of the answer trie, and SWI says so plainly: "Tabling effectively
;inverts the execution order for this case" [source: SWI-Prolog 10.1 Reference
;Manual, section 7.1]. Which order you get depends on the trie's layout, so it
;moves when anything unrelated moves. Written as (one two) this assertion
;flipped to (two one) when three facts that nothing calls were added to
;src/translator.pl, and flipped back when they were removed [measured
;2026-08-15]. The answer SET is what tabling preserves; assert that.
!(test (sort-atom (collapse (pick a))) (one two))

;Removing one again.
!(remove-atom &self (= (pick $x) one))

!(test (collapse (pick a)) (two))
