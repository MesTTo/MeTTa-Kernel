;Linda's two blocking binds over a MeTTa space, from lib_thread. A space is a
;tuple space: (peek-atom $space $pattern) waits until a matching atom is there
;and answers it LEAVING it, which is Linda's rd, and (take-atom $space
;$pattern) does the same and REMOVES exactly one, which is Linda's in. The
;difference is the coordination model itself: a read is one-to-n, every
;consumer sees the tuple, and a take is one-of-n, exactly one consumer gets
;it. Both are event-driven through the engine's own write hooks rather than
;polls, and both take an optional deadline in seconds.
;
;The non-blocking pair needs nothing new: (match ...) is Linda's rdp and
;(remove-atom ...) is its inp.
!(import! &self (library lib_thread))

(= (inc $x) (+ $x 1))

;A peek leaves the atom, so two peeks answer the same job.
!(add-atom &jobs (job 7))
!(test (peek-atom &jobs (job $n)) (job 7))
!(test (peek-atom &jobs (job $n)) (job 7))

;await-atom is the older name for the same thing and stays as sugar.
!(test (await-atom &jobs (job $n)) (job 7))

;A take removes the one it answers, so the second one finds nothing and gives
;up on its deadline instead of answering the same job twice.
!(test (take-atom &jobs (job $n)) (job 7))
!(test (collapse (take-atom &jobs (job $n) 0.05)) ())
!(test (collapse (get-atoms &jobs)) ())

;A worker is the point: take a job, do it, take the next. Each take consumes
;its own job, so two takes drain two and the space is empty after them.
!(add-atom &work (job 1))
!(add-atom &work (job 2))
!(test (let $x (take-atom &work (job $a) 1)
         (let $y (take-atom &work (job $b) 1)
           (+ $a $b)))
       3)
!(test (collapse (get-atoms &work)) ())

;Blocking means blocking: the take below starts before the atom exists and
;another thread writes it, which is the rendezvous a channel would otherwise
;be needed for.
!(test (let $w (spawn (add-atom &inbox (msg hello)))
         (let $seen (take-atom &inbox (msg $what) 10)
           (let $_ (await $w) $seen)))
       (msg hello))
!(test (collapse (get-atoms &inbox)) ())
