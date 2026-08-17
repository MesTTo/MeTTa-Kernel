;The special forms almost nothing used, each exercised for the property that
;makes it a special form rather than a function.
;
;This file exists because of `sealed`. It had ZERO uses anywhere in the tree,
;it was broken, and nothing said so: the case it exists for answered nothing at
;all. A form nobody calls is a form nobody would notice breaking, so a low
;usage count is a warning rather than a statistic. These nine were the thinnest
;after `sealed`: test-no-answer 1, transaction 1, elapsed 2, prog1 3, call 4,
;with_mutex 4, hyperpose 5, translatePredicate 5, timeout 6.

;--------------------------------------------------------- test-no-answer
;It distinguishes NO ANSWER from ONE ANSWER THAT IS THE EMPTY EXPRESSION,
;which is the whole reason it is not just (== x ()).
!(test-no-answer (superpose ()))
!(test (collapse (superpose ())) ())
!(test (collapse ()) (()))

;--------------------------------------------------------- prog1 and progn
;Both run every form; they differ in which one they answer.
!(test (prog1 (+ 1 1) (+ 2 2) (+ 3 3)) 2)
!(test (progn (+ 1 1) (+ 2 2) (+ 3 3)) 6)

;--------------------------------------------------------- transaction
;Every write inside is undone when the body fails, which is what a
;transaction is FOR and what a plain progn does not give.
!(test (collapse (transaction (progn (add-atom &self (tx-rolled a))
                                     (superpose ()))))
       ())
!(test (collapse (match &self (tx-rolled $x) $x)) ())

;A body that succeeds keeps its writes. The transaction answers whatever its
;body did, and add-atom answers the unit value the specification types it with.
!(test (collapse (transaction (add-atom &self (tx-kept a)))) (()))
!(test (collapse (match &self (tx-kept $x) $x)) (a))

;--------------------------------------------------------- elapsed
;Answers the value AND the seconds it took, as a pair, so the value is still
;usable rather than being replaced by a measurement.
!(test (let ($v $s) (elapsed (+ 1 2)) $v) 3)
!(test (let ($v $s) (elapsed (+ 1 2)) (< $s 60)) True)

;--------------------------------------------------------- timeout
;A bound that does not fire leaves the answer alone. The firing case cannot be
;an assertion here: a resource bound is a CONTROL exception, so a program's own
;(catch ...) deliberately cannot eat it and the run stops. python/tests covers
;that half, where the raise is the assertion.
(= (spin $n) (if (== $n 0) done (spin (- $n 1))))
!(test (timeout 5 (spin 10)) done)

;--------------------------------------------------------- with_mutex
;Named, so two different names do not serialise against each other.
!(test (with_mutex thin-lock-a (+ 1 2)) 3)
!(test (with_mutex thin-lock-b (+ 2 2)) 4)

;--------------------------------------------------------- hyperpose
;Runs its branches concurrently, so `once` over an expensive branch and a
;cheap one answers as soon as the cheap one is done.
!(test (once (hyperpose ((spin 3000000) (spin 3)))) done)
!(test (collapse (hyperpose ((+ 1 1) (+ 2 2)))) (2 4))

;--------------------------------------------------------- call
;Reaches a Prolog predicate with no registration at all, which is the point:
;msort/2 is SWI's and nothing here imported it.
!(test (call (msort (3 1 2))) (1 2 3))

;--------------------------------------------------------- translatePredicate
;Compiles ONE goal inline. It is a statement rather than a value, so it is
;written inside a progn whose last form is the variable the goal bound. That
;shape is the form's whole contract and is easy to get wrong: written as an
;equation body on its own, the function answers an unbound variable.
!(test (progn (translatePredicate (msort (3 1 2) $s)) $s) (1 2 3))
