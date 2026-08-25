; Purpose: exercise lib_strategy's reified combinators, traversal order, failure
;   behavior, and TP/TU schemes under the shipped example runner.
; Assumes: `test.sh` loads the standard engine and resolves shipped libraries
;   through `(library lib_strategy)`.
; Guarantees: all 35 assertions distinguish the strategy laws from plausible
;   eager, right-biased, host-callback, or non-traversing implementations
;   [tested: sh test.sh examples/libraries/strategy.metta; commit=WORKTREE]

!(import! &self (library lib_strategy))

; Named rewrite strategies explicitly return Empty when they decline. A missing
; equation is an irreducible successful term in MeTTa, not strategy failure.
(= (strategy-step strategy-a) strategy-b)
(= (strategy-step strategy-b) strategy-c)
(= (strategy-step strategy-c) Empty)
(= (strategy-step $x) Empty)
(= (strategy-fail $x) Empty)
(= (strategy-mark $x) (marked $x))
(= (strategy-only-a strategy-a) A)
(= (strategy-only-a $x) Empty)
(= (strategy-none $x) Empty)
(= (strategy-many strategy-a) A1)
(= (strategy-many strategy-a) A2)
(= (strategy-right strategy-a) WRONG)

; The plan is stored as ordinary data before it is queried and applied.
(strategy-policy fast (seq strategy-step strategy-step))

; These rewrites distinguish preorder, postorder, and innermost traversal.
(= (strategy-cap strategy-a) A)
(= (strategy-cap $x) Empty)
(= (strategy-fold strategy-a) A)
(= (strategy-fold (h A)) done)
(= (strategy-fold $x) Empty)

; id(t) = t. The second assertion uses the translator-lowered application door.
!(test (id strategy-a) strategy-a)
!(test (strategy-apply id strategy-a) strategy-a)

; fail(t) has no result.
!(test (collapse (fail strategy-a)) ())

; seq(s1,s2)(t) = s2(s1(t)).
!(test (seq strategy-step strategy-step strategy-a) strategy-c)

; choice(s1,s2) is left-biased: it falls back only when the complete left bag is
; empty, preserves every left answer, and never evaluates the right success.
!(test (choice strategy-fail strategy-step strategy-a) strategy-b)
!(test (choice strategy-step strategy-fail strategy-a) strategy-b)
!(test (collapse (choice strategy-many strategy-right strategy-a)) (A1 A2))

; try(s) = choice(s,id); gtry is LeaTTa's binary spelling of the same law.
!(test (try strategy-fail strategy-a) strategy-a)
!(test (gtry strategy-fail strategy-a) strategy-a)

; repeat(s) = choice(seq(s,repeat(s)),id), reaching the first normal form.
!(test (repeat strategy-step strategy-a) strategy-c)

; all(s) rewrites every immediate child, including the written expression head.
; Leaves and () are identities, while one declining child fails the whole term.
!(test (all strategy-mark (h strategy-a strategy-b))
       ((marked h) (marked strategy-a) (marked strategy-b)))
!(test (all strategy-mark leaf) leaf)
!(test (all strategy-mark ()) ())
!(test (collapse (all strategy-only-a (h strategy-a strategy-b))) ())

; one(s) answers every successful single-child choice from left to right. It
; fails for leaves, (), and a strategy that declines at every position.
!(test (collapse (one strategy-mark (h strategy-a strategy-b)))
       (((marked h) strategy-a strategy-b)
        (h (marked strategy-a) strategy-b)
        (h strategy-a (marked strategy-b))))
!(test (collapse (one strategy-only-a (h strategy-a strategy-b)))
       ((h A strategy-b)))
!(test (collapse (one strategy-none (h strategy-a strategy-b))) ())
!(test (collapse (one strategy-mark leaf)) ())
!(test (collapse (one strategy-mark ())) ())

; stratego-all(s) and stratego-one(s) are reified aliases of all(s) and one(s).
!(test (stratego-all strategy-mark (h strategy-a))
       ((marked h) (marked strategy-a)))
!(test (strategy-apply (stratego-all strategy-mark) (h strategy-a))
       ((marked h) (marked strategy-a)))
!(test (collapse (stratego-one strategy-only-a (h strategy-a strategy-b)))
       ((h A strategy-b)))

; Reified plans remain queryable before the translator lowers their application.
!(test (match &self (strategy-policy fast $strategy) $strategy)
       (noeval (seq strategy-step strategy-step)))
!(test (match &self (strategy-policy fast $strategy)
         (strategy-apply $strategy strategy-a))
       strategy-c)

; topdown(s) = seq(s,all(topdown(s))). Forgiveness is explicit through try(s);
; without it, a root decline makes the strict traversal fail.
!(test (topdown (try strategy-cap) (h strategy-a (g strategy-a)))
       (h A (g A)))
!(test (collapse (topdown strategy-cap (h strategy-a))) ())

; bottomup(s) = seq(all(bottomup(s)),s), so the rewritten child enables the root.
!(test (bottomup (try strategy-fold) (h strategy-a)) done)

; The same strategy under topdown sees the root before its child.
!(test (topdown (try strategy-fold) (h strategy-a)) (h A))

; innermost(s) = bottomup(try(seq(s,innermost(s)))) and revisits each reduct.
!(test (innermost strategy-step (h strategy-a)) (h strategy-c))

; TP is type-preserving; TU(r) admits strategies whose successful result is r.
(: strategy-demo-A Type)
(: strategy-demo-B Type)
(: strategy-demo-Summary Type)
(: strategy-demo-a strategy-demo-A)
(: strategy-demo-b strategy-demo-B)
(: strategy-preserve (-> strategy-demo-A strategy-demo-A))
(= (strategy-preserve $x) (marked $x))
(: strategy-summarize (-> strategy-demo-A strategy-demo-Summary))
(= (strategy-summarize $x) (summary $x))

!(test (get-type TP) Type)
!(test (get-type TU) (-> Type Type))
!(test (◁ strategy-preserve TP strategy-demo-a) (marked strategy-demo-a))
!(test (collapse (◁ strategy-preserve TP strategy-demo-b)) ())
!(test (◁ strategy-summarize (TU strategy-demo-Summary) strategy-demo-a)
       (summary strategy-demo-a))
!(test (collapse (◁ strategy-summarize (TU strategy-demo-B) strategy-demo-a)) ())
