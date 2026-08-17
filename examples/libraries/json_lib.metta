;JSON through lib_json, with MeTTa HE's names. The design decision worth
;noticing is HE's and it is the mettafied one: a JSON object decodes into a
;SPACE of (key value) atoms rather than an opaque dict, so looking a key up is
;a match and a decoded document is queryable like any other space.
!(import! &self (library lib_json))

;;; An object becomes a space. get-keys answers one key per solution, the way
;;; get-atoms does, so collapse it for a tuple.
!(test (let $d (json-decode "{\"a\":1,\"b\":2}") (collapse (get-keys $d)))
       (a b))
!(test (let $d (json-decode "{\"a\":1,\"b\":2}") (get-value $d a)) 1)
;An absent key answers nothing at all, so you test it with a match.
!(test (let $d (json-decode "{\"a\":1}") (collapse (get-value $d missing))) ())

;;; Arrays become expressions, scalars stay themselves.
!(test (json-decode "[1,2,3]") (1 2 3))
!(test (json-decode "\"plain\"") "plain")
!(test (json-decode "42") 42)
!(test (json-decode "true") True)
!(test (json-decode "null") Null)

;;; Nesting decodes all the way down, so an inner object is a space too.
!(test (let $outer (json-decode "{\"c\":{\"d\":2}}")
         (let $inner (get-value $outer c) (get-value $inner d)))
       2)

;;; Encoding inverts decoding.
!(test (json-decode (json-encode (1 2 3))) (1 2 3))
!(test (json-decode (json-encode "text")) "text")
!(test (let $d (json-decode (json-encode (dict-space ((k 1))))) (get-value $d k))
       1)

;;; dict-space builds one from pairs directly, without going through text.
!(test (let $d (dict-space ((name "ann") (age 3))) (get-value $d name)) "ann")
