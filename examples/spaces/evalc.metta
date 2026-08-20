;Purpose: show evaluation and equation lifetime in a named space.
;Guarantees: evalc evaluates an expression in a space you name, where eval evaluates it
;where it is written. Each space compiles its own equations into its own
;module, so the same name can be a different function in each one, and
;naming the space is how you reach the other definition. Removing a named
;space's equation removes its compiled answer too [tested:
;test_removing_an_equation_from_a_named_space_stops_its_answers].

!(bind! &metric (new-space))
!(add-atom &metric (= (distance $x) (* $x 1000)))

(= (distance $x) (* $x 5280))

;The ambient space answers in feet, the named one in metres.
!(test (distance 2) 10560)
!(test (evalc (distance 2) &metric) 2000)

;&self names the ambient space, so evalc there is eval.
!(test (evalc (+ 5 5) &self) 10)
!(test (eval (+ 5 5)) 10)

;The expression is handed over unevaluated. Were it not, it would already
;have been reduced here before the space argument could select another one.
!(test (evalc (distance (+ 1 1)) &metric) 2000)

;context-space, read inside evalc, reports the space evalc selected.
!(test (context-space) &self)
!(test (evalc (context-space) &metric) &metric)

;The space is evaluated, so a function that answers a space name can name it.
(= (preferred-space) &metric)
!(test (evalc (distance 2) (preferred-space)) 2000)

;A space is an atom beginning with &. Anything else is a type error rather
;than a silently empty space.
!(test (repr (catch (evalc (distance 2) 7)))
       "(Error (type_error SpaceType 7) (context evalc invalid MeTTa operation argument))")

;The removal funnel owns both the stored equation and its compiled clause, so
;the named 2000 answer leaves and the inherited &self equation is visible.
!(remove-atom &metric (= (distance $x) (* $x 1000)))
!(test (evalc (distance 2) &metric) 10560)
