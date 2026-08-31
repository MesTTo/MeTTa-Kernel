!(import! &self (library lib_spaces))

(friend tim tom)

(= (f $x) 42)

!(remove-all-atoms &self)

;The operation was imported INTO this space, so the first call took it out
;with everything else. A second call has no definition left to reduce it and
;answers itself: ONE answer, the expression as written, where a working call
;answers once per removed atom. Both sides name the space the same way, which
;is what keeps the claim true in a host's own home space as well as here;
;comparing printed TEXT would freeze whichever name this world uses.
!(test (collapse (remove-all-atoms &self))
       ((remove-all-atoms &self)))

!(test (repr (f 42))
       "(f 42)")

!(test (collapse (get-atoms &self))
       ())
