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

;"whatever its body did" means EVERY answer, not the first one. The body runs
;to exhaustion inside the transaction and its answers are replayed after the
;commit, so a three-answer body answers three times and all three answers'
;writes land or none of them do. Until 2026-08-19 this line answered (1),
;because SWI's transaction/1 runs its goal as once/1.
(= (tx-three) 1)
(= (tx-three) 2)
(= (tx-three) 3)
!(test (collapse (transaction (tx-three))) (1 2 3))
!(test (collapse (transaction (superpose ((add-atom &self (tx-each 1))
                                          (add-atom &self (tx-each 2))))))
       (() ()))
!(test (collapse (match &self (tx-each $x) $x)) (1 2))

;--------------------------------------------------------- atomically
;The same operation under the name the concurrency vocabulary uses for an
;atomic block, and sugar over transaction so the guarantees cannot drift.
;It belongs in this file for the reason the file exists: it is new, so
;nothing calls it yet, and a form nobody calls is a form nobody would
;notice breaking.
!(test (collapse (atomically (tx-three))) (1 2 3))

;What it does that transaction cannot. transaction is a special form and
;compiles its body into the call site, so a variable there is a value and
;the term comes back unrun; atomically takes its body as an unreduced Atom
;and evaluates it, so the body can be a term the program computed.
;The transaction line is written as a COUNT rather than as the term it
;answers, because test evaluates its expected side and the whole claim is
;that this term does not get evaluated: two answers from atomically, one
;unrun term from transaction.
(= (tx-body) (noeval (superpose ((+ 1 1) (+ 2 2)))))
!(test (collapse (let $b (tx-body) (atomically $b))) (2 4))
;The value is NAMED before the family operation reads it. `car-atom` and
;`size-atom` declare `Expression` parameters, so the operand reaches them AS
;WRITTEN; a `let` runs the form first and hands the answer over. The
;demonstration is unchanged, and so is the expected value
;[measured 2026-08-24: `!(let $v ((+ 1 2) b) (car-atom $v))` is 3 on LeaTTa
;9ea9f9d and on this engine].
!(test (let $answers (collapse (let $b (tx-body) (atomically $b)))
         (size-atom $answers))
       2)
!(test (let $answers (collapse (let $b (tx-body) (transaction $b)))
         (size-atom $answers))
       1)

;--------------------------------------------------------- elapsed
;Answers the value AND the seconds it took, as a pair, so the value is still
;usable rather than being replaced by a measurement.
!(test (let ($v $s) (elapsed (+ 1 2)) $v) 3)
!(test (let ($v $s) (elapsed (+ 1 2)) (< $s 60)) True)

;--------------------------------------------------------- timeout
;A bound that does not fire leaves the answer alone. The firing case cannot be
;an assertion here: a resource bound is a CONTROL exception, so a program's own
;(catch ...) deliberately cannot eat it and the run stops. bindings/python/tests covers
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
;Both branches ran and both answers came back, which is what collapse over
;hyperpose observes. The msort is the assertion's, not the form's: answers
;arrive in COMPLETION order, so (4 2) is as correct as (2 4) and this line
;flaked at 4 runs in 30 without it [measured 2026-08-18, engine alone].
;concurrent_and/3 is what hyperpose compiles to and its own documentation
;says answers "may be produced out of order" [source: SWI-Prolog
;library(thread), concurrent_and/2,3]; website/live/async.md says the same
;in MeTTa's vocabulary and tells you to compare sets. The same sort for the
;same reason is at examples/ch17-concurrency-and-the-loop/03-hyperpose_primes.metta:13.
!(test (msort (collapse (hyperpose ((+ 1 1) (+ 2 2))))) (2 4))

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
