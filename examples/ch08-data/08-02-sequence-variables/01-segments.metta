; Sequence variables: a pattern child that stands for a RUN of children.
;
; Two spellings. `...` is an anonymous gap and every occurrence of it is its
; own variable; `(:seg $x)` is a named one, and the run it took is the answer
; that name carries. Both are the law's [LeaTTa
; MettaHyperonFull/Core/Modifiers.lean, segment?].

!(add-atom &self (Order 7 x y))
!(add-atom &self (Order 8))
!(add-atom &self (Order 9 z))
!(add-atom &self (Note 1))

; A gap matches any number of children, zero included, so one pattern reads
; every arity the head has.
!(test (collapse (match &self (Order ...) matched)) (matched matched matched))

; A named gap answers the run it took, as the expression those children make.
!(test (collapse (match &self (Order 8 (:seg $rest)) $rest)) (()))
!(test (collapse (match &self (Order 7 (:seg $rest)) $rest)) ((x y)))

; The gap decides the arity, so it does not widen the head: (Note ...) reads
; only the Note atoms.
!(test (collapse (match &self (Note ...) matched)) (matched))

; PARSING BY UNIFICATION. Two gaps around a separator enumerate the splits,
; one answer per split, with no recursion written. The row below holds two
; separators, so the ask answers twice.
!(test (collapse (let ($pre ... SEP ... $post) (a b SEP c SEP d) ($pre $post)))
       ((a d) (a d)))

; A repeated named gap has to take the same run twice, compared the way every
; other atom position is compared.
!(test (collapse (let (f (:seg $run) mid (:seg $run)) (f a b mid a b) $run))
       ((a b)))
!(test (collapse (let (f (:seg $run) mid (:seg $run)) (f a b mid c) $run))
       ())

; A case arm reads a run the same way, and the first match wins as it always
; does.
!(test (case (Order 7 x y)
             (((Order $id (:seg $rest)) ($id $rest))
              ($_ nope)))
       (7 (x y)))

; TWO-SIDED. When both operands carry gaps the answer may stay open, and it
; prints as the pattern that would match it [LeaTTa
; MettaHyperonFull/Core/SeqRuntime.lean, SeqAtom.toSurface].
!(test (unify (f a (:seg $u)) (f a b (:seg $v)) $u none) (b (:seg $v)))

; THE FENCE. General sequence unification is INFINITARY (Kutsia, Journal of
; Symbolic Computation 42(3), 2007, Theorem 62): `X u = u X` has the family
; X = u^n for every n. Three restrictions are proved finite and are the ones
; this engine decides; outside them an ask REFUSES rather than searching, and
; the refusal names the rule.
!(test (get-metatype (catch (unify (f (:seg $x) a) (f a (:seg $x)) yes no)))
       Expression)

; A marker a variable carries is DATA, never a gap: only what the program
; WROTE is read as one [LeaTTa MettaHyperonFull/Core/SeqSyntax.lean,
; parseConcreteAtom].
!(add-atom &self (Marked ... tail))
!(test (collapse (match &self (Marked $slot tail) $slot)) (...))
