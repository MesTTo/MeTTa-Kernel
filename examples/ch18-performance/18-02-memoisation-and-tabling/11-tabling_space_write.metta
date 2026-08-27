;A table over a space stays fresh when the space changes. The engine
;declares the storage predicates the function reads incremental, so SWI
;invalidates and re-evaluates the table on the next call by itself.

!(import! &self (library lib_tabling))

!(add-atom &self (edge a b))
!(add-atom &self (edge b c))

(= (reach $x $y) (match &self (edge $x $y) $y))
(= (twohop $x $z) (match &self (, (edge $x $y) (edge $y $z)) $z))

!(tabled (reach $x $y))
!(tabled (twohop $x $z))

!(test (collapse (reach a $y)) (b))
!(test (collapse (twohop a $z)) (c))

;Adding an atom the table read. sort-atom for the same reason as
;tabling_equation_change.metta: a tabled function answers from its trie, not in
;clause order, so only the answer SET is stable.
!(add-atom &self (edge a c))
!(test (sort-atom (collapse (reach a $y))) (b c))

;Removing one.
!(remove-atom &self (edge a b))
!(test (collapse (reach a $y)) (c))

;A conjunction reads each of its patterns, so it tracks them all.
!(add-atom &self (edge c d))
!(test (collapse (twohop b $z)) (d))

;A read the engine cannot resolve to one space predicate is refused
;rather than tabled without the guarantee.
(= (bypattern $p) (match &self $p $p))
!(test (repr (catch (tabled (bypattern $p))))
       "(Error (metta_tabling_unresolved_read match $_0) none)")
