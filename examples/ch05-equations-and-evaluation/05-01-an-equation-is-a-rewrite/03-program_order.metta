; Purpose: show that runnable forms observe definitions in source order.
; Guarantees: a call before its equation stays unreduced, while the same call
; after the equation reduces [tested:
; test_a_bang_before_the_definition_answers_unreduced_not_a_host_error].

!(p121-example-respond me)
(= (p121-example-respond me) hello)
!(test (p121-example-respond me) hello)
