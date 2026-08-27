;A state cell is a VALUE. (new-state V) answers one, get-state reads it, and
;change-state! answers the CELL it wrote, so a write composes with a read in
;one expression. bind! binds a name to the cell, which is why the older
;spelling reads and writes through the name exactly as it always did.
!(bind! state (new-state rest))
!(test (get-state state) rest)
!(test (get-state (change-state! state active)) active)
!(test (get-state state) active)

;The type says what the cell HOLDS, which is the upstream signature
;(: new-state (-> $t (StateMonad $t))).
!(test (get-type (new-state 5)) (StateMonad Number))
!(test (get-type (new-state "hi")) (StateMonad String))

;And a cell needs no name at all: it can be built, written and read in place.
!(test (get-state (change-state! (new-state 1) 2)) 2)
