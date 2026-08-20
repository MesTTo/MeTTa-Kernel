; The language booleans cross py-call as Python booleans, in argument
; position and inside lists, and Python booleans come back as the language
; booleans. Uses only builtins, so this runs wherever janus does.
; Python strings return as symbols (janus str -> atom), so string-valued
; answers are asserted through repr. That is upstream py-call's conversion and
; it does not move; engine/python.pl's surface returns a MeTTa String.
!(test (repr (py-call (str true))) "True")
!(test (repr (py-call (str false))) "False")
; A list argument converts its booleans in, and a list answer converts its
; booleans back out, elementwise.
!(test (py-call (sorted (true false))) (false true))
!(test (py-call (len (true false true))) 3)
!(test (py-call (isinstance true (py-call (type false)))) true)
!(test (py-call (bool 1)) true)
!(test (py-call (bool 0)) false)
; A boolean receiver dispatches on bool, not on the text "true".
!(test (py-call (.bit_length true)) 1)
; Only the boolean atoms convert; other symbols stay text.
!(test (repr (py-call (.upper abc))) "ABC")
