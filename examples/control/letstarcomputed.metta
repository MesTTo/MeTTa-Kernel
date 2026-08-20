;The bindings of a `let*` are usually written out, and then they are syntax:
;the form rewrites them into nested `let`s once, and a call pays the same
;however many there are. They do not have to be written out. A bindings
;argument that arrives as a VALUE is rewritten when it arrives, so a program
;can decide its own bindings while it runs.

;That is what lets you give `let*` another name, as an ordinary definition.
;The body has to reach the definition unevaluated for the bindings to bind
;anything in it, and `Atom` is the metatype that says so.
(: mylet (-> Atom Atom %Undefined%))
(= (mylet $bindings $body) (let* $bindings $body))

!(test (mylet (($x 1) ($y 2)) (+ $x $y)) 3)

;Handed over or written out, the same bindings answer the same thing.
!(test (let* (($x 1) ($y 2)) (+ $x $y)) 3)

;The bindings and the body have to be written in the same place, because that
;is what makes a variable in one the same variable as in the other. Bindings
;built somewhere else carry their own variables and can bind nothing here.

;A binding is a (pattern value) pair, not only (variable value), and a
;pattern that does not match gives the whole form no answer.
!(test (mylet ((($a $b) (1 2))) $b) 2)
!(test (mylet ((5 5)) matched) matched)
!(test (collapse (mylet ((5 6)) matched)) ())

;Without the `Atom` metatype the arguments evaluate on the way in, so this is
;the other way to hand bindings over: `noeval` carries them as data, and the
;body is a variable the same call site wrote.
(= (mylet-evaluating $bindings $body) (let* $bindings $body))

!(test (mylet-evaluating (noeval (($x 1))) $x) 1)

;Bindings are checked when they arrive, because nothing after that point can
;check them. A value that is not a list of (pattern value) pairs is refused
;naming the form, rather than binding something the program never wrote.
!(test (car-atom (catch (mylet-evaluating (noeval ((1 2 3))) done))) Error)

;A bindings argument that is no list at all is not bindings, it is a program
;using the name as data, and it stays the unapplied form it always was.
!(test (repr (let* foo ok)) "(partial let* (foo ok))")

;Which one to write. Bindings written out are rewritten once, so a `let*` on a
;hot path is worth writing out. Bindings handed over are rewritten and
;compiled on every call, at a cost that grows with how many there are, and
;that is the price of deciding them at run time.
