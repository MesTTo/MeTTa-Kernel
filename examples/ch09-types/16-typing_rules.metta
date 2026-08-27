; Purpose: show a user typing-rule refusal overriding and then restoring the
;   shipped gradual-typing acceptance.
; Guarantees:
;   - add-typing-rule! changes the same checker ordinary typed calls use, and
;     remove-typing-rule! restores its prior result.
;   [tested: test_a_user_typing_rule_participates_like_a_shipped_one; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None

(: typing-rule-demo (-> DemoPayload Atom))
(= (typing-rule-demo $value) (seen $value))

!(test (typing-rule-demo unknown-demo) (seen unknown-demo))

!(add-typing-rule! deny-unknown-demo ordinary %Undefined% DemoPayload
                   (refuse unknown-demo-is-not-a-payload))
!(test (typing-rule-demo unknown-demo)
       (Error (typing-rule-demo unknown-demo)
              (BadArgType 1 DemoPayload %Undefined%
               (TypingRuleRefusal deny-unknown-demo
                                    unknown-demo-is-not-a-payload))))

!(remove-typing-rule! deny-unknown-demo)
!(test (typing-rule-demo unknown-demo) (seen unknown-demo))
