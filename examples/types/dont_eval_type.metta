; Purpose: demonstrate a user-declared evaluation mask with no naming rule.
; Guarantees:
;   - inspect-opaque receives its expression argument before it is evaluated.
;   [tested: test_a_user_declared_lazy_type_receives_its_argument_unevaluated; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]

(: OpaquePayload DontEvalType)
(: inspect-opaque (-> OpaquePayload Symbol))
(= (inspect-opaque $written) (get-metatype $written))

!(test (inspect-opaque (+ 1 2)) Expression)
