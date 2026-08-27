;The engine gives 57 heads a meaning of their own. Eight of them are written
;in MeTTa, as prelude equations that say what a call expands to; the rest are
;clauses of the compiler. KERNEL.md is the ledger of which is which and why.
;
;A form is fused into the compiler either because it cannot be written as an
;expansion or because it can and the expansion measured worse. `once` is the
;second kind, and this library is where the expansion lives so a program that
;wants the smaller instruction set can swap it in.

;Before the import, `once` is the compiler's own clause.
!(test (once (superpose (1 2 3))) 1)

!(import! &self (library lib_derived))

;After it, `once` is an ordinary MeTTa equation that rewrites the call into
;`(take 1 ...)`, and it answers exactly the same thing.
!(test (once (superpose (1 2 3))) 1)
!(test (collapse (once (superpose (1 2 3)))) (1))
!(test (collapse (once (empty))) ())

;It is still the first answer of a generator that has side effects, so the
;rest of the generator does not run.
!(bind! &seen (new-space))
(= (noisy $x) (let $_ (add-atom &seen (saw $x)) $x))

!(test (once (superpose ((noisy a) (noisy b)))) a)
!(test (collapse (get-atoms &seen)) ((saw a)))

;The swap is a session decision, not a per-call one: `add-translator-rule!`
;registers globally. `remove-translator-rule!` puts the compiler's own clause
;back in charge.
!(remove-translator-rule! once)

!(test (once (superpose (1 2 3))) 1)
