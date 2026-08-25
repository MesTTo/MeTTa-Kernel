;; The catalog describes its own kinds. Every declaration the engine acts
;; on is a (head ...) atom in &petta, and the SHAPES of those declarations
;; are atoms there too: (kind head argspec...) rows give each head's
;; positional shape, (vocabulary name value...) rows give the value sets,
;; and (claim vocab value property...) rows attach per-value facts. One
;; generic checker validates every &petta write against the standing rows,
;; so a misspelled value is a loud error at the write instead of an atom
;; that silently never matches its consultation site.

;; The shipped rows are ordinary data, matchable like anything else: the
;; fidelity vocabulary is the four words the handles router acts on,
!(test (match &petta (vocabulary fidelity $a $b $c $d) ($a $b $c $d))
       (Exact Partial Sound Refuse))

;; the handles kind row is the shape every (handles ...) declaration must
;; fit,
!(test (match &petta (kind handles $ctx $entry $claim $det) $claim)
       (one-of fidelity))

;; and orderedness is a claim on a semiring value, which is what
;; (top k ...) consults rather than a word list compiled into the engine.
;; The claim carries the DIRECTION beside the property, because ordered
;; alone does not say which end a top-k slice takes: ranked and prob
;; count down from the best, tropical counts up from the cheapest.
!(test (match &petta (claim semiring ranked $p $dir) ($p $dir))
       (ordered descending))
!(test (match &petta (claim semiring tropical $p $dir) ($p $dir))
       (ordered ascending))

;; A third-party kind is the same machinery: declare its vocabulary and
;; its shape, and from that moment the same checker guards it that guards
;; the shipped kinds.
!(add-atom &petta (vocabulary freshness-level live cached stale))
!(add-atom &petta (kind freshness symbol pattern (one-of freshness-level)))
!(add-atom &petta (freshness &rows (edge $a $b) cached))
!(test (match &petta (freshness &rows $shape $level) $level) cached)

;; (routed-by-shape head) additionally gives the kind the SAME router the
;; shipped handles declarations use: entries are patterns, queries route
;; by the most specific matching entry, and disagreeing overlaps are loud
;; conflicts, all inherited rather than reimplemented. The routing seam
;; extensions ride is seam:route_cap/4; EXTENDING.md section 8 walks the
;; whole path.
!(add-atom &petta (routed-by-shape freshness))
!(test (match &petta (routed-by-shape freshness) found) found)
