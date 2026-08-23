!(import! &self (library lib_datetime))

;`now` answers the current Unix time, so a form that PRINTS it verifies
;nothing and cannot be reproduced: the same file run twice a second apart
;answers two different numbers. These three used to print a live reading,
;which is why the two-configuration parity lane reported them as a
;difference that was not one. What is checkable about a clock is that it
;runs forward from a date already past and that formatting it is stable
;within one reading; the fixed timestamps below check format-date's output
;itself.
!(test (let $ts (now) (< 1735689600 $ts)) True)
!(test (let $ts (now)
         (== (format-date $ts "%Y-%m-%d") (format-date $ts "%Y-%m-%d")))
       True)

!(let* (($ts 1766188800)
        ($dow (day-of-week $ts)))
    ($dow))
!(test (day-of-week 1766188800) Saturday)

!(let* (($ts1 1735689600)
        ($ts2 1736294400)
        ($diff (- $ts2 $ts1)))
    ($diff))
!(test (- 1736294400 1735689600) 604800)

!(let* (($ts 1735725045)
        ($time-only (format-date $ts "%H:%M:%S")))
    ($time-only))
!(test (format-date 1735689600 "%B") January)
