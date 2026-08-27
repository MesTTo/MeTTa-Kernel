; Purpose: demonstrate a translator rule that inspects its match and DECLINES
;   with its own words, instead of only matching or not matching.
; Guarantees: a declined call carries on to the next equation, and the reason
;   the rule gave is readable from &metta afterwards.
; [tested: examples/ch20-extending-the-engine/20-01-translator-rules/07-translatorrule_refusal.metta; commit=9330b5d7ebf607e34a85be950bb226fce65f45c0]

;A rule head says WHICH shape it rewrites. A guard inside the rule says
;whether the match it got is one the rewrite can honour, which is a different
;question and needs a different answer: `(refuse Reason)`. egg's tensor
;compiler does the same thing in Rust, validating the nodes it is about to
;build and returning nothing when they are invalid.
(: strength (-> Atom Atom %Undefined%))
(= (strength (dose $n) (unit mg))
   (if (> $n 1000)
       (refuse "a dose above 1000 is not a milligram strength")
       (noeval (mg $n))))

;A refusal is a decline, not an error: the call carries on down the rest of
;the dispatch chain, and a rule with another equation tries that one.
(= (strength (dose $n) (unit mg))
   (noeval (grams (/ $n 1000))))

!(add-translator-rule! strength)

;A match the rule can honour rewrites.
!(test (strength (dose 250) (unit mg)) (mg 250))

;A match it declines falls through to the second equation.
!(test (strength (dose 5000) (unit mg)) (grams 5))

;And the words are the rule's own. They are published into &metta, so a
;program can ask why a rewrite it expected did not happen.
!(test (match &metta (translator-rule-refusal strength $why) $why)
       "a dose above 1000 is not a milligram strength")
