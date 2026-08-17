;The three constraint domains, and why there are three.
;
;`#` is CLP(FD): integers, and relational rather than computed, so it runs in
;every direction. examples/basics/relational_arithmetic.metta is its file.
;This one is the other two.
;
;ONE ENTRY POINT EACH rather than a prefixed operator family. Mirroring `#`'s
;shape would need fourteen names for the rationals and a handful more for the
;booleans, about thirty; `clpq` and `clpb` are two, and each solver already
;has a single entry point of its own. It is also the rule this engine set for
;`dif` beside `!=`: a new capability arrives under its own name rather than by
;changing what an existing operator means.
;
!(import! &self (library lib_constraints))

;Both take their constraint AS WRITTEN. Evaluated first, `(= (* 2 $x) 1)`
;would run `(* 2 $x)` as ordinary arithmetic and raise
;`Arguments are not sufficiently instantiated`, and a constraint over an
;unbound variable is the whole point of a constraint.

;------------------------------------------------------------------ CLP(Q)
;Exact rationals. clpfd has no answer to this at all, because 1/2 is not an
;integer, and ordinary arithmetic cannot solve backwards. Asserted through
;repr, because the reader has no rational literal to write 1r2 as: it would
;read back as a symbol and compare unequal to the number.
!(test (let True (clpq (= (* 2 $x) 1)) (repr $x)) "1r2")
!(test (let True (clpq (= (* 2 $x) 1)) (* 2 $x)) 1)

;Entailment: is this constraint already implied by what has been posted? That
;is the question a plain post cannot ask.
!(test (collapse (let True (clpq (>= $a 0)) (clpq-entailed (>= $a 0)))) (True))
!(test (collapse (let True (clpq (>= $b 0)) (clpq-entailed (>= $b 5)))) (False))

;A contradiction fails rather than answering, which is how a constraint says no.
!(test (collapse (let True (clpq (= $c 1)) (clpq (= $c 2)))) ())

;Disequations over the rationals, dif's numeric analogue.
!(test (collapse (let True (clpq (= $d 1))
                   (let True (clpq (= $e 2))
                     (clpq (=\= $d $e)))))
       (True))

;The constraints an answer still carries read back through residual-goals, the
;same way a dif does. Rendered with repr rather than compared as a term,
;because a test's expected value is EVALUATED and `(>= $g 0)` inside it would
;run as arithmetic on an unbound variable and raise.
!(test (let True (clpq (>= $f 0))
         (let True (clpq (=< $f 3))
           (repr (residual-goals $f))))
       "(({} (, (>= $_0 0) (=< $_0 3))))")

;------------------------------------------------------------------ CLP(B)
;A formula over booleans, posted and then labelled. `(card (1) ($p $q))` is
;"exactly one of these is true": a list of admissible counts and a list of
;variables, so a list here stays a list rather than becoming an operator.
!(test (collapse (let True (clpb (card (1) ($m $n))) (clpb-labeling ($m $n))))
       ((0 1) (1 0)))

;Tautology and contradiction, decided without enumerating anything.
!(test (clpb-taut (+ $t (~ $t))) True)
!(test (clpb-taut (* $u (~ $u))) False)

;The engine's own and/or/not are NOT replaced by this and should not be. They
;are generate-and-test over two values, which is cheaper than building a BDD
;until the formula constrains every variable at once. On "exactly one of N is
;true" the crossover is at twelve variables: 243 inferences against clpb's
;5,408 at four, 65,498 against 59,443 at twelve, and 16,777,154 against
;289,037 at twenty. MeTTa programs live below that line; this is for the ones
;that do not.
!(test (if (and (or $x True) $y) ($x $y)) ((True True) (False True)))
