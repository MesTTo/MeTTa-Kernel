!(test (cons-atom 0 (1 2 3))
       (0 1 2 3))

!(test (car-atom (1 2 3))
       1)

!(test (cdr-atom (1 2 3))
       (2 3))

!(test (index-atom (1 2 3) 1)
       2)

!(test (id 5) 5)

!(test (=alpha (Father $X) (Father $Y)) True)

!(test (=alpha (Father $X) (Son $X)) False)

!(test (first-from-pair (A B)) A)

!(test (second-from-pair (A B)) B)

!(test (index-atom (1 2 3) 5) ())

!(test (index-atom (1 2 3) a) ())

!(test (size-atom 5) ())

!(test (sort-atom 5) ())

!(test (unique-atom 5) ())

!(test (alpha-unique-atom 5) ())

!(test (min-atom 5) ())

!(test (max-atom 5) ())

!(test (intersection-atom 5 (a)) ())

;A non-list is one thing; an UNBOUND VARIABLE is another, and the two used to
;be confused. Handing one where an expression is expected is a program error,
;not a pattern to solve for, and the operation refuses it by name. Until
;2026-08-19 (car-atom $u) unified $u with a fresh cons cell through the clause
;head and answered its fresh head, (size-atom $u) reached a list walk with
;both ends open, and (sort-atom $u) reported msort/2, a Prolog predicate no
;MeTTa program ever wrote.
;
;if-error rather than the error term written out: the term carries the
;operation and the argument, and
;extensions/python/tests/ch10_errors_and_refusals/test_builtin_inputs.py checks
;that naming over every guarded position at once, which is the claim. Here
;the claim is that the call REFUSES where it used to answer.
!(test (if-error (catch (car-atom $unbound)) refused answered) refused)
!(test (if-error (catch (size-atom $unbound)) refused answered) refused)
!(test (if-error (catch (sort-atom $unbound)) refused answered) refused)
!(test (if-error (catch (index-atom $unbound 0)) refused answered) refused)
!(test (if-error (catch (subtraction-atom $unbound (a b))) refused answered)
       refused)

;A bound argument is untouched, which is the half that makes the refusal
;worth anything.
!(test (if-error (catch (car-atom (1 2))) refused answered) answered)
!(test (car-atom (1 2)) 1)

;The refusal is narrow. index-atom's SECOND argument is relational by design,
;so an unbound index still enumerates every position in turn.
!(test (collapse (index-atom (a b c) $i)) (a b c))
