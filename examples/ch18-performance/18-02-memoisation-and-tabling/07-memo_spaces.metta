;Memoization belongs to a space, not to a function name. Each space compiles
;its own equations into its own module, so two spaces defining the same name
;hold two functions, and each one caches on its own.

!(import! &self (library lib_memo))

!(bind! &metric (new-space))
!(add-atom &metric (= (shipping-cost $w) (* $w 9)))

(= (shipping-cost $w) (* $w 2))

!(test (shipping-cost 3) 6)
!(test (evalc (shipping-cost 3) &metric) 27)
!(test (is-memoized shipping-cost) false)
!(test (evalc (is-memoized shipping-cost) &metric) false)

;Memoizing here caches this space's function and leaves the other alone.
!(memoize shipping-cost)

!(test (is-memoized shipping-cost) true)
!(test (evalc (is-memoized shipping-cost) &metric) false)

;Both answers stand, and stand again on the call that hits the cache.
!(test (shipping-cost 3) 6)
!(test (shipping-cost 3) 6)
!(test (evalc (shipping-cost 3) &metric) 27)
!(test (evalc (shipping-cost 3) &metric) 27)

;Memoizing the other space's function adds a second cache, not a shared one.
!(evalc (memoize shipping-cost) &metric)

!(test (evalc (is-memoized shipping-cost) &metric) true)
!(test (evalc (shipping-cost 3) &metric) 27)
!(test (evalc (shipping-cost 3) &metric) 27)
!(test (shipping-cost 3) 6)

;Changing one space's equation invalidates that space's cache and answers
;the new value, while the other space keeps answering its own.
!(remove-atom &self (= (shipping-cost $w) (* $w 2)))
(= (shipping-cost $w) (* $w 3))

!(test (shipping-cost 3) 9)
!(test (evalc (shipping-cost 3) &metric) 27)
