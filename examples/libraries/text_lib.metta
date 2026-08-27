;Text and files, imported the way C reaches for string.h. Neither library is
;loaded until you ask for it, so a program that never touches text never pays
;for it.
!(import! &self (library lib_string))
!(import! &self (library lib_file))

;;; Measuring and slicing. string-slice is half-open, From included and To not.
!(test (string-length "hello") 5)
!(test (string-slice "hello world" 0 5) "hello")
;An over-long end clamps instead of erroring, which is what every language
;with slicing does.
!(test (string-slice "hello" 3 999) "lo")
!(test (string-slice "hello" 99 120) "")

;;; Splitting and joining are inverses.
!(test (string-split "," "a,b,c") ("a" "b" "c"))
!(test (string-join ", " ("a" "b" "c")) "a, b, c")
!(test (string-trim "  padded  ") "padded")
!(test (string-upper "shout") "SHOUT")
!(test (string-lower "QUIET") "quiet")

;;; The tests answer True or False, so they guard a query.
!(test (string-starts-with "hello" "he") True)
!(test (string-ends-with "hello" "lo") True)
!(test (string-contains "hello" "ell") True)
!(test (string-contains "hello" "zzz") False)

;;; index-of answers -1 rather than failing: asking "where is it" deserves an
;;; answer either way.
!(test (string-index-of "hello" "l") 2)
!(test (string-index-of "hello" "z") -1)

;;; replace changes every occurrence.
!(test (string-replace "banana" "a" "X") "bXnXnX")

;;; chars are one-character STRINGS, not char symbols, so the pieces are the
;;; same kind of thing as the whole and feed straight back in.
!(test (string-chars "abc") ("a" "b" "c"))
!(test (string-from-chars ("a" "b" "c")) "abc")
!(test (string-repeat "ab" 3) "ababab")
!(test (string-pad-left "7" 3 "0") "007")
!(test (string-pad-right "7" 3 ".") "7..")

;;; format-args is MeTTa HE's spelling, and this is HE's own example.
!(test (format-args "Probability of {} is {}%" (head 50))
       "Probability of head is 50%")
;A short argument list produces NOTHING for the placeholders it cannot fill,
;which is the dyn_fmt formatter upstream interpolates through.
!(test (format-args "{} and {}" (only)) "only and ")

!(test (sort-strings ("pear" "apple" "fig")) ("apple" "fig" "pear"))
!(test (parse-number "42") 42)
!(test (number-to-string 42) "42")

;;; Text operations accept a Symbol or a Number where a String is wanted,
;;; because a symbol arriving where a string was meant is ordinary in MeTTa.
!(test (string-length hello) 5)
!(test (string-upper hello) "HELLO")

;;; Files. Written under a distinctive name so the concurrent example runner
;;; cannot collide with itself, and removed at the end.
!(test (write-file! "/tmp/metta-text-example.txt" "one\ntwo\nthree\n") True)
!(test (read-file! "/tmp/metta-text-example.txt") "one\ntwo\nthree\n")
;file-lines! drops the trailing empty line a final newline would produce.
!(test (file-lines! "/tmp/metta-text-example.txt") ("one" "two" "three"))
!(test (append-file! "/tmp/metta-text-example.txt" "four\n") True)
!(test (file-lines! "/tmp/metta-text-example.txt") ("one" "two" "three" "four"))

;;; The handle surface is MeTTa HE's exactly: r read, w write, c create,
;;; a append, t truncate.
!(test (let $h (file-open! "/tmp/metta-text-example.txt" "r")
         (let $head (file-read-exact! $h 3)
           (let $_ (file-close! $h) $head)))
       "one")

;;; file-space! is the mettafied reading of reading a file: its lines become
;;; (line Number Text) atoms in a space, so the file is QUERYABLE with match
;;; rather than being one long string you then have to take apart. The line
;;; number is kept because a space is unordered.
!(test (let $log (file-space! "/tmp/metta-text-example.txt")
         (collapse (match $log (line $n $t) ($n $t))))
       ((1 "one") (2 "two") (3 "three") (4 "four")))
;Asking for one line is a match, not a scan.
!(test (let $log (file-space! "/tmp/metta-text-example.txt")
         (collapse (match $log (line 2 $t) $t)))
       ("two"))

!(test (delete-file! "/tmp/metta-text-example.txt") True)
