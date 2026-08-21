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
!(test (match &petta (claim semiring ranked $p) $p) ordered)

;; Whether a context can emit change events at all is a declaration here
;; too, and not something the engine infers from a provider's methods: a
;; remote space can be written and its contents still change on the server.
;; So (events <ctx> <delivery> <order>) is what makes a foreign context
;; subscribable, with delivery drawn from messaging's own three promises.
!(test (match &petta (vocabulary delivery $a $b $c) ($a $b $c))
       (at-most-once at-least-once per-write-exactly))
!(test (match &petta (kind events $ctx $delivery $order) $delivery)
       (one-of delivery))

;; The value set is closed, so a promise nobody could act on is a loud
;; error at the write rather than an atom that never matches.
!(test (if-error (catch (add-atom &petta (events &feed eventually)))
                 refused admitted)
       refused)

;; Which reaction fires first when several match one write is a declared
;; policy too, with a stated default rather than assertion order by accident.
;; The words are production systems' own conflict-resolution vocabulary.
!(test (match &petta (vocabulary agenda-policy $a $b $c $d $e) ($a $b $c $d $e))
       (declaration recency specificity priority user))
!(test (match &petta (policy reaction-order $knob $default) ($knob $default))
       (agenda declaration))

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
;; extensions ride is metta_route_cap/4; EXTENDING.md section 8 walks the
;; whole path.
!(add-atom &petta (routed-by-shape freshness))
!(test (match &petta (routed-by-shape freshness) found) found)
