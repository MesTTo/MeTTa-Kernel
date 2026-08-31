;; The engine's own type surface, reported without being imported.
;;
;; Nothing here imports lib_builtin_types. The engine reads that file at boot
;; into seam:builtin_type_declaration/2, which get_type_candidate/2 consults LAST,
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
!(test (get-type match) (-> SpaceType Atom Atom %Undefined%))
;map-atom carries two declared arrows, one per surface it offers: the
;three-argument template form and the two-argument callable form. Both are
;the two spellings of one operation. The list is EVALUATED in both, which is
;what upstream does: its map-atom clause begins by translating the list
;[source: PeTTa@ae66fa8 src/translator.pl:254-258, and
;`!(map-atom (cdr-atom (a b)) $y (q $y))` is `((q b))` there, the cdr taken
;first; measured 2026-08-30]. `Expression` in a parameter position is a TYPE
;here, not a hold: only `Atom` holds.
!(test (collapse (get-type map-atom))
       ((-> Expression Variable Atom Expression)
        (-> Expression Expression Expression)))

;; Expression structure, from the reference corelib dump.
!(test (get-type car-atom) (-> Expression %Undefined%))
!(test (get-type cdr-atom) (-> Expression Expression))
!(test (get-type cons-atom) (-> %Undefined% %Undefined% Atom))
!(test (get-type size-atom) (-> Expression Number))
!(test (get-type index-atom) (-> %Undefined% Number Atom))

;; MeTTa's own, with no dump entry to take.
;sort-atom sorts a VALUE, so its parameter cannot carry the evaluation mask:
;the reference declares no type for it at all and its argument therefore
;evaluates [measured 2026-08-24: `!(get-type sort-atom)` is `%Undefined%` on
;LeaTTa 9ea9f9d, and `!(sort-atom (cdr-atom (a c b)))` is `(b c)` there].
!(test (get-type sort-atom) (-> %Undefined% Expression))
!(test (get-type is-var) (-> Atom Bool))
;repr renders what its argument EVALUATED to, so its parameter says so.
!(test (get-type repr) (-> %Undefined% String))
!(test (get-type current-time) (-> Number))

;; The state cell is a VALUE and its type says what it holds, which is the
;; dump's own signature. A cell is a handle atom here, so a plain symbol still
;; names one and the older spelling keeps working; what the parametric cell
;; adds is that (new-state V) answers a cell you can pass and write through.
!(test (get-type new-state) (-> $t (StateMonad $t)))
!(test (get-type change-state!) (-> (StateMonad $t) $t Bool))
!(test (get-type get-state) (-> (StateMonad $t) $t))
!(test (get-type (new-state 5)) (StateMonad Number))
!(test (get-type (new-state "hi")) (StateMonad String))

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
