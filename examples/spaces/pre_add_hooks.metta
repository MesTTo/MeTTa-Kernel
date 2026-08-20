;A pre-add hook claims the write door of one space for one function of one
;argument, the incoming atom. Every write into the claimed space consults it
;first, and the handler answers with one of four verdicts: (accept) lets the
;atom in as offered, (accept <atom>) lets a TRANSFORMED atom in instead,
;(refuse <words>) throws carrying the handler's own words, and (drop)
;skips the write silently while the caller sees success. This is the general
;mechanism behind capacity and admission: arbitrary MeTTa deciding what a
;space contains.

(= (guard (secret $x)) (refuse "no secrets in this pool"))
(= (guard (raw $x)) (accept (cooked $x)))
(= (guard (dup $x)) (drop))
(= (guard (plain $x)) (accept))

!(declare-pre-add! &pool guard)

;An accepted atom lands as offered.
!(add-atom &pool (plain 1))
!(test (match &pool (plain $x) $x) 1)

;A transformed atom lands in the handler's chosen form. The handler's output
;is the granted form and is not re-asked: one decision per request, the way
;a database BEFORE trigger's modified row does not re-fire the trigger. A
;handler that wants chained rewriting composes it in its own body.
!(add-atom &pool (raw 7))
!(test (match &pool (cooked $x) $x) 7)

;A dropped atom is skipped and the caller sees the success an accepted add
;answers, which is how set semantics is written as a rule.
!(add-atom &pool (dup 3))
!(test (collapse (match &pool (dup $x) $x)) ())

;A refusal carries the handler's own sentence to the caller.
!(test (repr (catch (add-atom &pool (secret 1))))
       "(Error (petta_add_refused &pool (secret 1) \"no secrets in this pool\") none)")

;A claimed handler whose equations do not cover the atom is a stuck state
;that says so, naming the space, the slot, the handler and the atom. Nothing
;is silently admitted and nothing silently vanishes; a handler that wants a
;default writes its own catch-all equation, one visible line.
!(test (repr (catch (add-atom &pool (uncovered 9))))
       "(Error (petta_hook_stuck &pool pre-add guard (uncovered 9)) none)")

;One claimant per name, checked when the claim is made: a second claimant is
;refused with both named, never raced at call time.
(= (other-guard $a) (accept))
!(test (repr (catch (declare-pre-add! &pool other-guard)))
       "(Error (petta_hook_conflict &pool pre-add guard other-guard) none)")

;Undeclaring is explicit and frees the claim; the space is direct again.
!(undeclare-pre-add! &pool)
!(add-atom &pool (uncovered 10))
!(test (match &pool (uncovered $x) $x) 10)
