;What the incremental machinery actually did, rather than what it is meant to
;do. A write to a space a tabled function reads invalidates its table, and the
;next call re-evaluates it. Until these counters existed the guarantee was
;testable only by its EFFECT, a fresh answer, which a table rebuilt from
;scratch produces just as well.

!(import! &self (library lib_tabling))

!(add-atom &self (edge a b))
(= (reach $x $y) (match &self (edge $x $y) $y))
!(tabled (reach $x $y))

;Nothing has happened yet: one call, one answer, no invalidation.
!(collapse (reach a $y))
!(test (table-stats (reach $x $y))
       ((tables 1) (answers 1) (complete-call 1) (invalidated 0) (reevaluated 0)))

;--------------------------------------------- what does NOT invalidate a table
;A write under a key this subgoal does not read leaves the table alone. Not
;"leaves the answers alone", which a rebuild would too: the table is never
;invalidated at all, and the counters are cumulative, so reading them BEFORE
;the next call is what shows it.
!(add-atom &self (edge b d))
!(test (table-stats (reach $x $y))
       ((tables 1) (answers 1) (complete-call 1) (invalidated 0) (reevaluated 0)))

;Nor does an atom with a different head in the same space.
!(add-atom &self (unrelated x y))
!(test (table-stats (reach $x $y))
       ((tables 1) (answers 1) (complete-call 1) (invalidated 0) (reevaluated 0)))

;This is finer than the manual's own summary, which says invalidation "is done
;at the level of tables. Notably asserting a clause invalidates all affected
;tables" and closes with "Future versions may implement a more fine grained
;approach" [source: SWI-Prolog 10.1 Reference Manual, 7.7]. Measured
;2026-08-16 on SWI 10: a write the subgoal does not read does not invalidate.
;It is what makes tabling worth having over a space that is written to often,
;so it is pinned here rather than assumed.

;------------------------------------------------ what DOES invalidate a table
!(add-atom &self (edge a c))
!(test (table-stats (reach $x $y))
       ((tables 1) (answers 1) (complete-call 1) (invalidated 1) (reevaluated 0)))

;Re-evaluation is on demand, so it takes a call. reevaluated LOWER than
;invalidated would be SWI deciding a dependency changed without changing this
;table's answers, which is the incremental win rather than a rebuild. The
;shared table has completed one original call and one re-evaluation call.
!(test (sort-atom (collapse (reach a $y))) (b c))
!(test (table-stats (reach $x $y))
       ((tables 1) (answers 2) (complete-call 2) (invalidated 1) (reevaluated 1)))
