(: f (-> Type1 Type1))
(: f (-> Type2 Type2))
;=alpha rather than ==, and the reason is this file's own subject. f is
;declared for Type1 AND Type2, so $a arrives as either, and each comparison
;here is against a symbol of ONE of them: (== T2in T1in) is a comparison
;across two KNOWN and different types, which == refuses by name. =alpha is
;the comparison that takes anything and compares structurally, which is what
;a type-dispatch test wants. Both references refuse the == spelling too,
;measured 2026-08-19 on this very program: hyperon 0.2.10 and the LeaTTa
;mechanised interpreter each answer T1out and then
;(Error (== T2in T1in) (BadArgType 2 Type2 Type1)).
(= (f $a)
   (if (=alpha $a T1in)
       T1out
       (if (=alpha $a T2in)
           T2out
           Tdefault)))

(: T1in Type1)
(: T1out Type1)
(: T2in Type2)
(: T2out Type2)

(: T3in Type1)
(: Tdefault Type2)

!(test (f T1in) T1out)
!(test (f T2in) T2out)
!(test-no-answer (f T3in)) ;Type1 of T3in does not go along with Type2 output
(: T3in Type2)      ;But if we make T3in also of Type2 then it is fine if output is Type2:
!(test (f T3in) Tdefault)
