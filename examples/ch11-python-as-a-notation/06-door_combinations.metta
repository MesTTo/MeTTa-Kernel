;The door combinations: every way one definition kind appears inside
;another, each cell one runnable claim. The Python twin carries the host
;half of the matrix (op bodies, staging, construction-time folding);
;this side proves the engine half, where a DEFINE body is LOWERED
;(references become terms), equations are ATOMS a program can match and
;write, and a grounded operation is a priced call term like any other.

;A define inside a define: the ordinary call term, engine-only.
(= (dc-twice $x) (+ $x $x))
(= (dc-quad $x) (dc-twice (dc-twice $x)))
!(test (dc-quad 5) 20)

;A grounded operation inside a define: the op-call term, one host
;crossing per invocation.
(= (dc-upper $s) (py-call (.upper $s)))
!(test (dc-upper "ab") AB)

;Writing equations FROM a body: add-atom of an (= ...) atom, the
;self-modification face. The body runs, the space gains the equation,
;and the new name answers.
(= (dc-install) (add-atom &self (= (dc-nine) 9)))
!(dc-install)
!(test (dc-nine) 9)

;Equations are ordinary atoms, so a program can MATCH one: the meta
;face that makes rules-over-rules lawful.
!(test (match &self (= (dc-nine) $body) $body) 9)
