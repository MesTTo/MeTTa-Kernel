;; The event layer's own declarations, as catalog rows. Whether a context can
;; emit change events at all, and which reaction fires first when several
;; match one write, are both DECLARED here rather than inferred: the catalog
;; describes their shapes the way it describes every other declaration kind,
;; so a program reads exactly what the engine acts on.

;; Subscribability is not something the seam can read off a provider's
;; methods. A remote space can be written and its contents still change on
;; the server, so (events <ctx> <delivery> <order>) is what makes a foreign
;; context subscribable, with delivery drawn from messaging's own three
;; promises and order the second axis, because a channel may deliver every
;; write and still deliver them out of order.
!(test (match &petta (vocabulary delivery $a $b $c) ($a $b $c))
       (at-most-once at-least-once per-write-exactly))
!(test (match &petta (vocabulary event-order $a $b) ($a $b))
       (ordered unordered))
!(test (match &petta (kind events $ctx $delivery $order) $delivery)
       (one-of delivery))

;; The value set is closed, so a promise nobody could act on is a loud error
;; at the write rather than an atom that never matches its consultation site.
!(test (if-error (catch (add-atom &petta (events &feed eventually)))
                 refused admitted)
       refused)

;; A native space needs no declaration and is watchable anyway: every write
;; into the engine's own store already runs its write hooks, which is a fact
;; about this engine rather than a promise a provider is making. explain says
;; so without anything having been declared.
!(add-atom &native-events (reading 1))
!(test (collapse (match &petta (events &native-events $d $o) declared)) ())

;; Which reaction fires first is the second declaration, and its default is
;; STATED rather than accidental: declaration order is what the engine
;; produced before this was a policy at all, and the policy inventory now
;; says so. The other four words are production systems' own conflict
;; resolution vocabulary.
!(test (match &petta (vocabulary agenda-policy $a $b $c $d $e) ($a $b $c $d $e))
       (declaration recency specificity priority user))
!(test (match &petta (policy reaction-order $knob $default) ($knob $default))
       (agenda declaration))
!(test (match &petta (kind agenda $ctx $policy $fn) $policy)
       (one-of agenda-policy))

;; A reaction carries its own priority as an optional fifth field, so every
;; (on ...) written before the agenda existed keeps its meaning and reads
;; as 0.
!(test (match &petta (kind on $ctx $pattern $op $priority) $priority)
       (optional integer))
