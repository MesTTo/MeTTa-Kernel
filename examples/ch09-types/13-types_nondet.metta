(: f (-> Type1 Type1))
(: f (-> Type2 Type2))
;== is the comparison here, and it takes any two operands: it is declared
;`(-> $a $b Bool)` with two INDEPENDENT type variables, so comparing a Type2
;symbol against a Type1 one asks a legitimate question whose answer is False.
;This file used =alpha between 2026-08-19 and 2026-08-30, while == was
;declared `(-> $a $a Bool)` and refused the pair by name.
(= (f $a)
   (if (== $a T1in)
       T1out
       (if (== $a T2in)
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
;NOTHING, because a declared result is CHECKED like any argument: T3in is a
;Type1, so only the (-> Type1 Type1) branch admits it, and that branch's own
;result check then rejects Tdefault, which is a Type2. The (-> Type2 Type2)
;branch never runs because its argument check refuses T3in.
!(test (f T3in) ())
(: T3in Type2)      ;But if we make T3in also of Type2 then it is fine if output is Type2:
!(test (f T3in) Tdefault)
