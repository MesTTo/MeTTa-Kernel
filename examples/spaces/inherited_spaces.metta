; Purpose: show child-first inherited reads with front-only writes.

!(add-atom &family-parent (edge a b))
!(add-atom &family-parent (parent-only kept))
!(add-atom &family-parent (layer parent))
!(new-space &family-child (inherits &family-parent))
!(add-atom &family-child (edge b c))
!(add-atom &family-child (child-only local))
!(add-atom &family-child (layer child))

;One conjunction can join a parent fact to a child fact because each link is
;matched through the whole read chain.
!(test (collapse (match &family-child
                         (, (edge $x $y) (edge $y $z))
                         ($x $z)))
       ((a c)))

;Same-shaped facts pin child-first reads without relying on Prolog's clause
;enumeration order across different predicate arities. The capacity/count
;boundary sees only the writable front store.
!(test (collapse (match &family-child (layer $x) $x)) (child parent))
!(test (space-atom-count &family-child) 3)

;Writes never mutate an ancestor. The Python removal surface demonstrates the
;front-only miss because MeTTa's established remove-atom surface turns every
;absent-local removal into Error.
!(test (collapse (match &family-parent (parent-only $x) $x)) (kept))
!(test (collapse (match &family-child (parent-only $x) $x)) (kept))
!(test (collapse (match &family-parent (child-only $x) $x)) ())
