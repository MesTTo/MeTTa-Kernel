; Purpose: demonstrate recursive relational evaluation over successor facts.
; Guarantees: reaching either relation's unmatched boundary fails the search
;   instead of returning the P3 residual-call dispatch value.
; [tested: examples/reasoning/logicprog.metta; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
!(add-atom &petta (dispatch-policy successor NoMatchEnum NoMatchFail))
!(add-atom &petta (dispatch-policy later-in-alphabet NoMatchEnum NoMatchFail))

(= (successor b a) True)
(= (successor c b) True)
(= (successor d c) True)
(= (successor e d) True)
(= (successor f e) True)
(= (successor g f) True)

(= (later-in-alphabet $X $Y)
   (successor $X $Y))

(= (later-in-alphabet $X $Y)
   (and (successor $X $Z) (later-in-alphabet $Z $Y)))

;Alternative formulation of the previous function (still only with PeTTa though)
;(= (later-in-alphabet $X $Y)
;   (let $temp (successor $X $Z)
;        (later-in-alphabet $Z $Y)))

!(test (collapse ((later-in-alphabet d $1) $1))
       ((True c) (True b) (True a)))
