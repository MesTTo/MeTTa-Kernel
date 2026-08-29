;`match` finds every row BEFORE any output template runs, so a template that
;writes to the space cannot change what the match still has to answer. The
;language specifies this rather than leaving it open: "match first finds all
;the matches, and then instantiates the output pattern with them, which is
;evaluated outside match. If remove-atom and add-atom would be executed right
;away for each found matching, the condition of circular links would be broken
;after the first rewrite" (Working with spaces, the graph-rewriting example).

;Upstream's own example, verbatim. Three links form a loop and the fourth does
;not; the template reverses each loop link it is given. All three rows were
;found before the first reversal broke the cycle, so all three are reverted
;and only (link C E) is left alone.
(link A B)
(link B C)
(link C A)
(link C E)

!(test (collapse (match &self (, (link $x $y)
                                (link $y $z)
                                (link $z $x))
                             (let $_ (remove-atom &self (link $x $y))
                                      (add-atom &self (link $y $x)))))
       (true true true))

;The four atoms upstream prints, as a set: reversing one link and stopping,
;which is what running the templates during enumeration does, would leave
;(link B C) and (link C A) untouched.
!(test (collapse (match &self (link $x $y) ($x $y))) ((C E) (B A) (C B) (A C)))

;The single-pattern case is the arbiter's own experiment, reduced to its
;detector: two rows, and each template removes the OTHER one. A lazy query
;would lose the row it had not reached yet and answer once. The items are
;named alpha and beta rather than the experiment's first and second because
;`first` is a stdlib function, and an expected value that names one is a call
;rather than the literal a test wants to compare against.
!(bind! &snapshot (new-space))
!(add-atom &snapshot (item alpha))
!(add-atom &snapshot (item beta))

(= (visit alpha) (let $_ (remove-atom &snapshot (item beta)) alpha))
(= (visit beta) (let $_ (remove-atom &snapshot (item alpha)) beta))

!(test (collapse (match &snapshot (item $x) (visit $x))) (alpha beta))

;Both removals happened, so the space is empty: each row's template ran, and
;ran against the space the OTHER row's template had already written to.
!(test (collapse (get-atoms &snapshot)) ())
