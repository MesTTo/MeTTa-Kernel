;A space is a MULTISET, so removal has two honest readings and the engine
;ships both. `remove-atom` DRAINS: every atom that unifies leaves, which is
;what upstream answers and what `del space[pattern]` spells from Python.
;`subtract-atom` SUBTRACTS: one occurrence leaves and the answer says whether
;one was there, which is what `space -= atom` and `space.remove(atom)` spell.
;
;Three copies make the difference visible. Draining takes all three at once;
;subtracting walks them down one at a time.

(dup 1)
(dup 1)
(dup 1)
(keep 2)

;One occurrence goes, and True says one was there.
!(test (subtract-atom &self (dup 1)) True)
!(test (collapse (match &self (dup $n) $n)) (1 1))

;And again. Subtraction is not idempotent, which is the whole difference from
;the drain: each call takes one more.
!(test (subtract-atom &self (dup 1)) True)
!(test (collapse (match &self (dup $n) $n)) (1))

;When nothing is left to take, the answer is False rather than an error. This
;is the distinction `remove-atom` gives up by answering True either way.
!(test (subtract-atom &self (dup 1)) True)
!(test (subtract-atom &self (dup 1)) False)

;The drain, for contrast: three fresh copies leave together in one call.
!(add-atom &self (dup 7))
!(add-atom &self (dup 7))
!(add-atom &self (dup 7))
!(test (remove-atom &self (dup 7)) True)
!(test (collapse (match &self (dup $n) $n)) ())

;An UNBOUND atom names no single occurrence, so subtraction refuses rather
;than guessing which one or quietly draining the space. The drain is the door
;that takes a pattern, and it is named in the refusal.
!(test (subtract-atom &self $anything)
       (Error (subtract-atom &self $anything)
              "subtract-atom: the atom is unbound, so no single occurrence is named; use remove-atom to drain every atom, or name a pattern"))

;The atom that never matched is still here.
!(test (collapse (match &self (keep $n) $n)) (2))
