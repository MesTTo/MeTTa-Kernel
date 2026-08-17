;A foreign space that holds RULES, not only facts.
;
;In MeTTa a space is BOTH a data source and where the program lives: evaluation
;is match against (= lhs rhs) atoms, facts and rules are the same kind of
;thing, and add-atom of an equation is how a program grows. The foreign seam
;honoured only the first half, so an equation added to a foreign space was
;stored and INERT: the call answered itself.
;
;A provider says it holds equations by declaring the `rules` capability. The
;provider under test is in _fixtures/rule_provider.pl, thirteen lines. Nothing
;else about the provider changes: the engine compiles the equation, so a rule
;in a foreign space is the same compiled clause a native one is, and every
;evaluation rule below is the compiler's, not a second implementation of it.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file "./examples/libraries/_fixtures/rule_provider.pl" ())

;A rule, added to the foreign space, evaluating.
;
;(metta $atom $type $space) is how you evaluate IN a space. A rule belongs to
;the space that holds it, exactly as a native named space's equations belong
;to it: calling (fdouble 21) from &self would find nothing, because &self does
;not hold that equation and neither does its module.
!(add-atom &rule_demo (= (fdouble $x) (* 2 $x)))
!(test (metta (fdouble 21) %Undefined% &rule_demo) 42)

;Several equations for one name are an answer SET, which is what MeTTa
;promises. sort-atom because a set has no order.
!(add-atom &rule_demo (= (fpick) one))
!(add-atom &rule_demo (= (fpick) two))
!(test (sort-atom (collapse (metta (fpick) %Undefined% &rule_demo))) (one two))

;A body that is not a call IS the answer, the way a native equation with a
;bare atom body behaves.
!(add-atom &rule_demo (= (fplain) settled))
!(test (metta (fplain) %Undefined% &rule_demo) settled)

;A body is evaluated FURTHER, so a nested call is evaluated inside out. This is
;the case that decided the design: reading evaluation as "match the space for
;(= (f Args) $body) and reduce $body" is the naive reading, and the language's
;own tutorial says why it falls short, that "the interpreter is performing some
;additional processing on top of such equality queries". Here that shows up as
;(* 2 3) reaching + as a list instead of as 6.
!(add-atom &rule_demo (= (fnest) (+ 1 (* 2 3))))
!(test (metta (fnest) %Undefined% &rule_demo) 7)

;Recursion, and if evaluating only the branch it takes. Neither is special
;here: the equation compiles, so it recurses the way any compiled equation
;does.
!(add-atom &rule_demo (= (ffact $x) (if (> $x 0) (* $x (ffact (- $x 1))) 1)))
!(test (metta (ffact 5) %Undefined% &rule_demo) 120)

;And the space is still a data source. Holding rules is an addition, not a
;replacement, which is the whole of what "both" means.
!(add-atom &rule_demo (edge a b))
!(test (collapse (match &rule_demo (edge $x $y) ($x $y))) ((a b)))

;The one thing to know before relying on this: the engine learns about an
;equation when it goes through add-atom. An equation that appears in the space
;by some other door, a backend's own bulk loader or MORK's mm2-exec, is stored
;and inert, because nothing told the engine to compile it.
