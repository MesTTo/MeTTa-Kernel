!(import! &self (library lib_he))

!(test (let $result (catch (+ 40 2))
       (if-error $result
           Error
           $result))
       42)

;An operand whose type RULES THE CALL OUT is an error atom already, so
;if-error sees one with no catch in between: `a` here is declared a String and
;the arrow says Number.
(: a String)
!(test (if-error (+ 40 a) Error fine) Error)

;An operand whose type merely does not DECIDE is not an error. The call is
;left as written, which is what upstream's NoReduce does, so if-error takes
;its second branch.
!(test (if-error (+ 40 undeclared-operand) Error fine) fine)

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

!(test (return-on-error (Error 5 BadType) 6)
       (Error 5 BadType))

!(test (return-on-error 5 6) 6)
