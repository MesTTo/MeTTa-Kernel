;Concurrency through lib_thread: parallel evaluation over a list, racing,
;futures, channels, bounded pools, blocking on a space, and a lock that keeps
;every answer. Assertions here are all order-independent or order-preserving,
;because a race and a hyperpose answer in completion order by design.
!(import! &self (library lib_thread))

(= (inc $x) (+ $x 1))
(= (big? $x) (> $x 2))
(= (spin $n) (if (> $n 0) (spin (- $n 1)) done))
(= (slow $x) (let $_ (spin 300000) $x))

;par-map preserves the input list's order however the elements finish.
!(test (par-map inc (1 2 3 4)) (2 3 4 5))
!(test (par-map inc ()) ())
!(test (par-filter big? (1 2 3 4 5)) (3 4 5))
!(test (par-forall big? (3 4 5)) True)
!(test (par-forall big? (1 4 5)) False)

;par-any stops at the first element that holds. It answers True even though
;the elements before it fail, which the obvious first_solution/3 spelling of
;this got wrong.
!(test (par-any big? (1 2 9)) True)
!(test (par-any big? (1 2)) False)

;The fast branch wins and the slow one is stopped, so this returns without
;waiting for (slow 1).
!(test (par-race ((slow 1) (inc 41))) 42)
;A branch that fails drops out rather than ending the race.
!(test (par-race ((superpose ()) (inc 41))) 42)

;A future evaluates on its own thread; await waits for it. Two of them
;overlap, which is the whole point.
!(test (let $f (spawn (inc 41)) (await $f)) 42)
!(test (let $a (spawn (slow 1)) (let $b (spawn (slow 2)) (+ (await $a) (await $b)))) 3)
;Awaiting twice answers the same thing without waiting again.
!(test (let $f (spawn (inc 1)) (let $_ (await $f) (await $f))) 2)

;A future IS a space, so it holds the expression's whole ANSWER SET rather
;than just the first answer. That is the point: a MeTTa expression does not
;have a value, it has a set, and a future has to carry the same.
!(test (collapse (await (spawn (superpose (1 2 3))))) (1 2 3))
!(test (collapse (await (spawn (superpose ())))) ())
!(test (is-space (spawn (inc 1))) True)
;Being a space, it reads back with the ordinary space operations too.
!(test (let $f (spawn (inc 41)) (let $_ (await $f) (collapse (get-atoms $f)))) (42))

;Timers are futures that start later, so (after ...) is setTimeout and there is
;no separate clearTimeout: the same (cancel ...) that stops a spawn stops a
;timer. A pending timer is simply not settled yet.
!(test (collapse (await (after 0.05 (inc 41)))) (42))
!(test (let $t (after 30 (inc 41)) (let $s (settled? $t) (let $_ (cancel $t) $s))) False)
!(test (let $t (after 0.05 (inc 41))
         (let $_ (cancel $t)
           (let $__ (sleep 0.25) (collapse (get-atoms $t)))))
       ())

;A channel is a mailbox. The term is copied across, so the receiver gets its
;own copy and no binding crosses.
!(test (let $c (channel) (let $_ (send $c hello) (recv $c))) hello)
!(test (let $c (channel) (let $_ (send $c one) (channel-size $c))) 1)

;A pool bounds the fan-out; submit answers the same handle await takes.
!(test (let $_ (pool demo-pool 2) (let $h (submit demo-pool (inc 9)) (await $h))) 10)

;Blocking until another thread writes the atom, event-driven through the
;engine's own write hooks. The spawned branch does the writing.
!(test (let $w (spawn (add-atom &self (ready now)))
         (let $seen (await-atom &self (ready $what) 10)
           (let $_ (await $w) $seen)))
       (ready now))

;with-lock keeps every answer. SWI's with_mutex, which the built-in form uses,
;is once/1 and would answer (1) here.
!(test (collapse (with-lock demo-lock (superpose (1 2 3)))) (1 2 3))
!(test (collapse (with_mutex demo-lock (superpose (1 2 3)))) (1))

;Bounding by wall clock keeps the answers too, unlike a bare
;call_with_time_limit which is once/1.
!(test (collapse (timeout 10 (superpose (1 2 3)))) (1 2 3))
!(test (timeout 10 (inc 41)) 42)
