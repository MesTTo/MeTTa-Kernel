;PCRE2 regular expressions through lib_regex: boolean guards, nondet
;match enumeration, typed named captures, split, and replace. A MeTTa
;string reads \\ as one backslash, so "\\d" spells the regex \d, the
;same convention as Python's non-raw strings.
!(import! &self (library lib_regex))

!(test (re-match "(?i)^needle" "Needle in a haystack") True)
!(test (re-match "^x" "abc") False)
!(test (collapse (re-find "\\d+" "a1 b22 c333")) ("1" "22" "333"))
!(test (re-captures "(?<year_I>\\d\\d\\d\\d)-(?<month_I>\\d\\d)" "2017-04-20")
       ((0 "2017-04") (month 4) (year 2017)))
!(test (re-split ":\\s*" "Age: 33") ("Age" ": " "33"))
!(test (re-replace-all "a+" "X" "banana") "bXnXnX")
!(test (re-replace "(?<y>\\d+)" "[$y]" "n 42 n") "n [42] n")
