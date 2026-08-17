;; The engine's own type surface, reported without being imported.
;;
;; Nothing here imports lib_builtin_types. The engine reads that file at boot
;; into builtin_type_declaration/2, which get_type_candidate/2 consults LAST,
;; so get-type answers the engine's own types while &self stays the program's
;; own space. builin_types.metta is the sibling that DOES import it and gets
;; the same declarations as live typed dispatch.
;;
;; Before this, 117 of the engine's 158 names answered %Undefined% for
;; operations that work, and a tool reading the surface, the metta-lsp port
;; included, had no way to tell "no type" from "a type nobody loaded".

;; Special forms are compiled by the translator and have no registry entry at
;; all, so they were the least reachable half of the surface.
!(test (get-type if) (-> Bool Atom Atom $t))
!(test (get-type let) (-> Atom %Undefined% Atom %Undefined%))
!(test (get-type chain) (-> Atom Variable Atom %Undefined%))
!(test (get-type quote) (-> Atom Atom))
!(test (get-type collapse) (-> Atom Atom))
!(test (get-type superpose) (-> Expression %Undefined%))
!(test (get-type match) (-> Symbol Atom Atom %Undefined%))
!(test (get-type map-atom) (-> Expression Variable Atom Expression))

;; Expression structure, from the reference corelib dump.
!(test (get-type car-atom) (-> Expression %Undefined%))
!(test (get-type cdr-atom) (-> Expression Expression))
!(test (get-type cons-atom) (-> Atom Expression Atom))
!(test (get-type size-atom) (-> Expression Number))
!(test (get-type index-atom) (-> Expression Number Atom))

;; PeTTa's own, with no dump entry to take.
!(test (get-type sort-atom) (-> Expression Expression))
!(test (get-type is-var) (-> Atom Bool))
!(test (get-type repr) (-> Atom String))
!(test (get-type current-time) (-> Number))

;; A DIVERGENCE from the dump, which types these over (StateMonad $t). PeTTa's
;; state is a named global: change-state! is nb_setval/2, so the first
;; argument is the NAME and there is no monadic cell to type over.
!(test (get-type change-state!) (-> Symbol %Undefined% Bool))
!(test (get-type get-state) (-> Symbol %Undefined%))

;; The surface is FACTS, not atoms in &self: a program still sees only its own
;; space. Putting them in &self was tried and it changes what every program
;; sees when it enumerates, which is not the engine's to do.
(: program-own-type MyType)
!(test (collapse (match &self (: $n $t) $n)) (program-own-type))

;; And a program's own declaration is answered ahead of the engine's, because
;; the table is consulted last.
(: car-atom MyOverride)
!(test (car-atom (a b)) a)
!(test (collapse (get-type car-atom)) (MyOverride (-> Expression %Undefined%)))
