!(import! &self (library lib_he))

!(test (let $result (catch (+ 40 2))
       (if-error $result
           Error
           $result))
       42)

;An operand an arithmetic operation cannot use is an error atom already, so
;if-error sees one with no catch in between. That holds whether the operand's
;type RULES THE CALL OUT -- `a` here is declared a String and the arrow says
;Number -- or merely fails to decide, because the two are the same event:
;upstream reaches is/2 for both and raises
;`type_error(evaluable, undeclared-operand/0)`
;[measured 2026-08-30 against PeTTa@ae66fa8]. This engine answers instead of
;raising, so the form after it still runs.
(: a String)
!(test (if-error (+ 40 a) Error fine) Error)
!(test (if-error (+ 40 undeclared-operand) Error fine) Error)

;catch is for a HOST error, the kind the language has no atom for. Two unbound
;arithmetic operands are one.
!(test (let $result (catch (+ $left $right))
            (if-error $result
                Error
                $result))
       Error)

;Integer division by zero already is Error data, so it needs no catch.
!(test (if-error (/ 40 0) Error fine) Error)

!(test (if-error (Error 5 BadType) "Error!" "No error")
       "Error!")

;At top level the reference's double return leaves one return instruction for
;an enclosing function frame. LeaTTa 9ea9f9d answers this exact call likewise.
!(test (return-on-error (Error 5 BadType) 6)
       (return (Error 5 BadType)))

!(test (return-on-error 5 6) 6)
