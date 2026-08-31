!(import! &self (library lib_spaces))

(friend tim tom)

(= (f $x) 42)

!(remove-all-atoms &self)

;The call no longer reduces, so it stays the expression it was written as.
;Its HEAD is what says so in any world: &self names the space this code
;lives in, which is the default space here and a context's own home when a
;host runs the same file inside one, so the printed text carries that name
;rather than the four literal characters.
!(test (car-atom (remove-all-atoms &self)) remove-all-atoms)

!(test (repr (f 42))
       "(f 42)")

!(test (collapse (get-atoms &self))
       ())
