;The HE vocabulary is part of the core engine now (engine/prelude.metta),
;so no import is needed; this one stays to show it remains a no-op.
!(import! &self (library lib_he))

!(test (is-function (-> Atom Atom)) True)
!(test (is-function Atom) False)
;type-cast answers the atom when it has the type and (Error $atom BadType) when
;it does not. Three ways to have it: the type is the atom's metatype, a
;declared type matches it, or the atom has no declaration at all, which the
;engine answers as %Undefined%, a wildcard that matches any requested type.
(: type1 Type)
(: A type1)

!(test (type-cast A type1 &self) A)
!(test (type-cast 1 type1 &self) (Error 1 BadType))

;A metatype counts, so any symbol casts to Symbol and any number to Grounded.
!(test (type-cast A Symbol &self) A)
!(test (type-cast 1 Number &self) 1)

;An atom nobody declared is not the wrong type.
!(test (type-cast B type1 &self) B)
;match-types is unification with wildcards, Hyperon's own contract:
;%Undefined% and Atom on EITHER side match anything, and otherwise the
;two types unify, so a type carrying a variable matches its instance.
!(test (match-types Atom Atom "Matched!" "Didn't match") "Matched!")
!(test (match-types Atom Number "Matched!" "Didn't match") "Matched!")
!(test (match-types Bool Number "Matched!" "Didn't match") "Didn't match")
!(test (match-types (List $x) (List Number) "Matched!" "Didn't match") "Matched!")
!(test (first-from-pair (A B)) A)
!(test (second-from-pair (A B)) B)
!(test (match-type-or True Number Bool) True)
