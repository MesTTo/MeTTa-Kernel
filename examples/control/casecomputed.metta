;The cases of a `case` are usually written out, and then they are syntax: the
;form compiles one nested conditional out of them once, and a call pays the
;same however many branches there are. They do not have to be written out. A
;cases argument that arrives as a VALUE is compiled when it arrives, so the
;branches can be decided while the program runs.

;That is what lets you give `case` another name, as an ordinary definition.
(= (switch $value $cases) (case $value $cases))

!(test (switch 2 ((1 one) (2 two))) two)

;Handed over or written out, the same cases answer the same thing.
!(test (case 2 ((1 one) (2 two))) two)

;Cases the program builds are cases too.
(= (numbered-cases) (cons-atom (1 one) ((2 two))))

!(test (switch 1 (numbered-cases)) one)
!(test (switch 2 (numbered-cases)) two)

;`Empty` is the branch a key with NO ANSWERS takes, and it means that on both
;paths. Here the key is `(empty)`, so the default answers.
(= (key-of-nothing $cases) (case (empty) $cases))

!(test (key-of-nothing ((1 one) (Empty none))) none)
!(test (case (empty) ((1 one) (Empty none))) none)

;A key that answers but matches no branch is a different thing, and it answers
;nothing whether an `Empty` branch is there or not.
!(test (collapse (switch 9 ((1 one) (Empty none)))) ())
!(test (collapse (case 9 ((1 one) (Empty none)))) ())

;Cases are checked when they arrive, because nothing after that point can
;check them. A value that is not a list of (pattern value) pairs is refused
;naming the form, rather than compiling a branch the program never wrote.
!(test (car-atom (catch (switch 1 foo))) Error)

;Written out, `(case 1 foo)` is not a case with bad cases, it is a program
;using the name as data, and it still reduces to itself.
!(test (case 1 foo) (case 1 foo))

;Which one to write. Cases written out are compiled once, so a `case` on a hot
;path is worth writing out. Cases handed over are translated on every call, at
;a cost that grows with how many there are, and that is the price of deciding
;the branches at run time.
