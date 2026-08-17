;Minimal MeTTa's instruction set, running with no Python at all.
;
;That is the point of this file. `function`, `collapse-bind`, `superpose-bind`
;and `unify-mod` used to be grounded PYTHON operations, so the language's own
;inference control was unavailable to any program run through run.sh or the
;packaged CLI. They are Prolog now, and this example is in the ordinary
;examples gate, which runs the engine on its own.
;
;Measured 2026-08-15, one harness, min-of-5, on (function (return 42)), which
;runs no evaluation loop at all: 36.14 inferences and 3.95us as a Python
;operation against 11.14 and 0.21us as a Prolog predicate. Against a plain
;MeTTa function the wall-clock cost falls from 24.65x to 1.30x.

!(import! &self (library minimal_metta_lib))

;--------------------------------------------------------------- function
;The specification: "It evaluates the <atom> until it becomes (return <atom>).
;Then (function (return <atom>)) expression returns the <atom>."
!(test (function (return 42)) 42)
!(test (function (chain (+ 1 2) $x (return $x))) 3)

;`return` is deliberately not registered, so it survives evaluation as data.
;Registering it as the identity its (-> $t $t) signature suggests makes
;(return 3) reduce to 3 before `function` can see it, and every body answers
;NoReturn.
!(test (return 7) (return 7))

;A branch that ends without a return is the specification's own error, and it
;carries the ORIGINAL body rather than wherever the walk stopped. The body is
;an unreducible form because `test` evaluates its expected value too, so
;(Error (+ 1 2) NoReturn) written out would have its (+ 1 2) reduced to 3.
!(test (function (foo bar)) (Error (foo bar) NoReturn))

;--------------------------------------------------------------- unify-mod
;The specification names two pieces of matching as future work. Both are here.
;First: (unify $x Empty then else) takes the `then` branch, because a free
;variable unifies with anything.
!(test (unify-mod $a Empty then else) then)

;(:= x) matches by EQUALITY, which is the fix.
!(test (unify-mod $a (:= Empty) then else) else)

;The arity gate matters. (:= a b) with two arguments is ordinary data, because
;real corpora already contain forms like (:= (Green Sam) T).
!(test (unify-mod (:= a b) (:= $x $y) then else) then)

;... matches any number of atoms, so (A ... D ...) matches (A B C D E).
!(test (unify-mod (A B C D E) (A ... D ...) matched nomatch) matched)

;Matching binds, and the bindings reach the chosen branch. Without that,
;(unify-mod (p 5) (p $x) (got $x) else) answers (got $x) with $x still free.
!(test (unify-mod (p 5) (p $x) (got $x) else) (got 5))

;--------------------------------------------------------------- switch
;The specification's recursive switch, written in the minimal instruction set.
;It is the reason the library exists: if function, return, chain and unify are
;right, this runs.
!(test (mm-switch 1 ((1 one) (2 two))) one)
!(test (mm-switch 2 ((1 one) (2 two))) two)
!(test (mm-switch (p 5) (((p $x) (got $x)))) (got 5))

;No case matches: the branch finishes as Empty, the branch remover, and
;collapse prunes it, so the collapsed list is empty. The bare (test ...)
;forms elsewhere in this file still observe a raw Empty result, because
;test is this engine's observation window rather than an aggregation.
!(test (collapse (mm-switch 9 ((1 one) (2 two)))) ())

;--------------------------------------------------------------- reduce
;The specification's evaluation loop: evaluate until nothing changes, then
;substitute into the template.
(= (step-down $n) (if (> $n 0) (step-down (- $n 1)) done))
!(test (mm-reduce (step-down 3) $x $x) done)
!(test (mm-reduce (step-down 3) $x (wrapped $x)) (wrapped done))
!(test (mm-reduce (+ 1 2) $y $y) 3)

;--------------------------------------------------------- collapse-bind
;Every alternative, each paired with the values its own branch bound. The
;shape is LeaTTa's: one expression of (<atom> <bindings>) pairs.
;
;The left of each (<- ...) is the CALLER'S OWN VARIABLE, one shared across
;every row, which is why $v appears twice below rather than once per row.
!(add-atom &self (edge a b))
!(add-atom &self (edge a c))
!(test (collapse-bind (match &self (edge a $y) (found $y)))
       (((found b) (bindings (<- $v b))) ((found c) (bindings (<- $v c)))))

;superpose-bind puts the rows back into the plan, one answer each.
!(test (collapse (superpose-bind (collapse-bind (match &self (edge a $y) (found $y)))))
       ((found b) (found c)))

;And RESTORES that row's bindings while it does, which is the whole reason the
;pair of instructions exists: "superpose-bind applied to the result of
;collapse-bind will restore the value of this variable in each context". Read
;$y outside the collapse and it carries the row's own value.
!(test (collapse (chain (collapse-bind (match &self (edge a $y) (found $y))) $c
                   (chain (superpose-bind $c) $x ($x $y))))
       (((found b) b) ((found c) c)))

;--------------------------------------------------------- Turing machine
;The specification's own Turing-completeness witness. Flip a 0 to a 1 and walk
;right until a 1 is read, then halt.
(= (rule S 0) (S 1 R))
(= (rule S 1) (HALT 1 N))

;Already on a 1: halt without moving.
!(test (mm-tm rule S (() 1 ())) (() 1 ()))

;One step: write 1, move right onto the 1, halt.
!(test (mm-tm rule S (() 0 (1))) ((1) 1 ()))

;Three steps, so the tape to the left accumulates.
!(test (mm-tm rule S (() 0 (0 0 1))) ((1 1 1) 1 ()))

;The tape is ($head $hole $tail): cells to the left in reverse, the cell under
;the machine, and the cells to the right. Running off either end reads a blank.
!(test (mm-move (() 0 (7)) 1 R) ((1) 7 ()))
!(test (mm-move ((9) 0 ()) 1 L) (() 9 (1)))
!(test (mm-move (() 0 ()) 1 R) ((1) 0 ()))
!(test (mm-move ((1) 0 (2)) 9 N) ((1) 9 (2)))

;--------------------------------------------------------- partial functions
;"Each instruction in a minimal instruction set is a total function.
;Nevertheless Empty allows defining partial functions in MeTTa."
!(test (if-partial True yes) yes)
!(test (if-partial False yes) Empty)
