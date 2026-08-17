;and-then and or-else are the SHORT-CIRCUITING boolean connectives. They are
;special forms rather than functions, which is the whole point: a function's
;arguments are evaluated before the call, so a function could not skip its
;second one.
;
;They are not a second spelling of and and or. Those are RELATIONAL: they
;evaluate both sides and can solve for an unbound argument, which is what
;examples/basics/booleansolver.metta shows when
;(if (and (or $x True) $y) ($x $y)) answers ((True True) (False True)).
;
;The two pairs trade one property for the other, measured 2026-08-15:
;
;                        skips its second argument   solves for an unbound one
;   and / or                       no                          yes
;   and-then / or-else             yes                         no
;
;So reach for and or or when you want the relation, and for and-then or or-else
;when the second argument must not run. Neither of the latter had a single use
;anywhere in examples/ or lib/ before this file, so nothing checked that they
;skip at all.

!(test (and-then True yes) yes)
!(test (and-then False yes) False)
!(test (or-else True no) True)
!(test (or-else False fallback) fallback)

;They take expressions, not just literals.
!(test (and-then (> 2 1) (> 3 2)) True)
!(test (or-else (> 1 2) (> 3 2)) True)

;The skipping itself, which is the reason they are special forms. A branch that
;is skipped must leave no trace, so this records what actually ran.
!(bind! &ran (new-space))
(= (note $tag) (let $_ (add-atom &ran (ran $tag)) True))

!(and-then False (note skipped-by-and-then))
!(or-else True (note skipped-by-or-else))
!(and-then True (note taken-by-and-then))
!(or-else False (note taken-by-or-else))

!(test (collapse (get-atoms &ran))
       ((ran taken-by-and-then) (ran taken-by-or-else)))

;The contrast, in one place: `and` does NOT skip, so its second argument runs
;even though the first is False.
!(bind! &ran2 (new-space))
(= (note2 $tag) (let $_ (add-atom &ran2 (ran $tag)) True))
!(and False (note2 and-runs-it))
!(and-then False (note2 and-then-skips-it))
!(test (collapse (get-atoms &ran2)) ((ran and-runs-it)))

;And the other side of the trade: and-then cannot be solved backwards, where
;`and` can.
!(test (collapse (if (and-then (or-else $p True) $q) ($p $q))) ())
