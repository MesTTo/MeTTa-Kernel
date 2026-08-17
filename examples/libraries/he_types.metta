!(import! &self (library lib_he))

!(test (is-function (-> Atom Atom)) True)
!(test (is-function Atom) False)
;type-cast answers the atom when it has the type and (Error $atom BadType) when
;it does not. Three ways to have it: the type is the atom's metatype, a
;declared type equals it, or the atom has no declaration at all, which PeTTa
;answers as %Undefined% and HE's own type-cast-check treats as matching.
(: type1 Type)
(: A type1)

!(test (type-cast A type1 &self) A)
!(test (type-cast 1 type1 &self) (Error 1 BadType))

;A metatype counts, so any symbol casts to Symbol and any number to Grounded.
!(test (type-cast A Symbol &self) A)
!(test (type-cast 1 Number &self) 1)

;An atom nobody declared is not the wrong type.
!(test (type-cast B type1 &self) B)
!(test (match-types Atom Atom "Matched!" "Didn't match") "Matched!")
!(test (match-types Atom Number "Matched!" "Didn't match") "Didn't match")
!(test (first-from-pair (A B)) A)
!(test (second-from-pair (A B)) B)
!(test (match-type-or True Number Bool) True)
