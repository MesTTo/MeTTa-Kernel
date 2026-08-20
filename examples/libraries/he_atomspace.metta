!(import! &self (library lib_he))

!(add-atom &self (= (addnormal) (+ 1 3)))
!(add-reduct &self (= (addreduct) (+ 1 3)))

; quote retains its wrapper in LeaTTa types-meta/30_evaluation_control.metta;
; noeval holds the stored body without adding that wrapper.
!(test (match &self (= (addnormal) $X) $X) (noeval (+ 1 3)))
;4, not (4). add-reduct is an engine builtin now and reduces the definition's
;body to a VALUE; the lib_he shim it replaced took `(cdr-atom $headbody)` and
;stored the body still wrapped in the one-element list that came back, so this
;expectation had been recording that wrapping.
!(test (match &self (= (addreduct) $X) (noeval $X)) 4)

!(get-type 1)

(: a A)
!(test (get-type-space &self a) A)

(hello world)
!(test (unify &self (hello world) Yes No) Yes)
!(test (unify &self (hello dream) Yes No) No)
