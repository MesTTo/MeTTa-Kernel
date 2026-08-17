;take answers at most k. once takes one and collapse takes all, and between
;them there was nothing, while the space seam had the idea one level down all
;along in a provider's match(pattern, limit=).

!(test (collapse (take 3 (superpose (a b c d e)))) (a b c))

;Fewer answers than the bound is not an error, and a bound of zero answers
;nothing, which is what "at most" means.
!(test (collapse (take 9 (superpose (a b)))) (a b))
!(test (collapse (take 0 (superpose (a b)))) ())

;The bound is applied OUTSIDE the producer, so it cuts one that would not stop
;on its own. This counts up forever and take ends it.
(= (from $n) (superpose ($n (from (+ $n 1)))))
!(test (collapse (take 4 (from 0))) (0 1 2 3))

;A count that is not a whole number is a mistake rather than an empty answer,
;because failing into "there is nothing there" sends you looking at your data.
!(test (car-atom (catch (take foo (superpose (a b))))) Error)

;For a FOREIGN space the bound also reaches the provider, so a backend can put
;it in its own query instead of enumerating and discarding. That happens when
;the expression is exactly one match over one space, and the shape below is
;the one that qualifies: the template is the pattern, so nothing between the
;provider's answers and take's can drop one.
;
;Across a join it does not, and that is not a limitation to work around. The
;bound belongs to the JOINED rows, and an outer match truncated at k loses the
;rows its later candidates would have joined to. The answers are bounded
;either way; only the backend's work changes.
(edge a b)
(edge b c)
(edge c d)
!(test (collapse (take 2 (match &self (edge $x $y) (edge $x $y))))
       ((edge a b) (edge b c)))
!(test (collapse (take 2 (match &self (, (edge $x $y) (edge $y $z)) ($x $z))))
       ((a c) (b d)))
