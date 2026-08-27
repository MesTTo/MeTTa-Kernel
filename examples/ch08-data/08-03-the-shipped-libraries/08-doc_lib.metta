;Documentation through lib_doc, with MeTTa HE's vocabulary. The design is HE's
;and it is the mettafied one: documentation is ATOMS IN A SPACE, so help! is a
;query rather than a separate mechanism and a program can reason about its own
;docs. The whole library is MeTTa; there is no Prolog beside it, because the
;doc forms are data constructors and retrieval is a match.
!(import! &self (library lib_doc))

(@doc greet (@desc "Greets somebody by name"))
(= (greet $who) $who)

(@doc add-two
      (@desc "Adds two numbers")
      (@params ((@param "the first") (@param "the second")))
      (@return "their sum"))
(= (add-two $a $b) (+ $a $b))

;;; Retrieval is a match, so it answers the atom that was written.
!(test (get-doc greet) (@doc greet (@desc "Greets somebody by name")))

;;; @doc carries two, three or four parts depending on how much was written,
;;; and get-doc answers whichever shape exists.
!(test (get-doc add-two)
       (@doc add-two
             (@desc "Adds two numbers")
             (@params ((@param "the first") (@param "the second")))
             (@return "their sum")))

;;; An undocumented name answers nothing at all, rather than an empty doc, so
;;; you test for it with a match.
!(test (collapse (get-doc greet-nobody)) ())

;;; Because docs are data, a program can ask what it knows about itself.
!(test (collapse (get-doc missing)) ())

;;; And it can ask what it has NOT documented, which is the gap worth closing
;;; in a real codebase. Both functions below are documented, so neither shows.
!(test (collapse (undocumented)) ())
