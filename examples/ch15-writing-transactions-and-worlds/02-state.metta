;A state cell is a VALUE. (new-state V) answers one, get-state reads it, and
;bind! binds a name to the cell, which is why the older spelling reads and
;writes through the name exactly as it always did.
!(bind! state (new-state rest))
!(test (get-state state) rest)

;change-state! runs for an EFFECT, so it answers `true` like add-atom and the
;rest of that family rather than answering the cell it wrote. A write and a
;read are therefore two steps: name the cell, write it, then read it. This
;example composed the two into (get-state (change-state! ...)) while the write
;answered the cell; that spelling now hands get-state the boolean instead.
!(test (change-state! state active) true)
!(test (get-state state) active)

;The type says what the cell HOLDS, which is the upstream signature
;(: new-state (-> $t (StateMonad $t))).
!(test (get-type (new-state 5)) (StateMonad Number))
!(test (get-type (new-state "hi")) (StateMonad String))

;And a cell needs no name at all: it can be built, written and read through a
;let that holds it while both happen.
!(test (let $cell (new-state 1)
            (let $_ (change-state! $cell 2) (get-state $cell)))
       2)
