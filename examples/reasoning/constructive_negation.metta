;Constructive negation. (not-provable E) answers True for the arguments that
;E cannot prove and False for the ones it can, and it answers over an infinite
;domain by constraining rather than by enumerating.
;
;Before this the engine had no negation at all. `not` is a boolean function: it
;maps True to False and False to True. A MeTTa expression that no equation
;matches does not reduce to False, it stays as data. So with only
;(= (penguin polly) True) declared, (penguin tweety) has no answer and
;(not (penguin tweety)) has no answer either. There was nothing to write.

(= (bird tweety) True)
(= (bird polly) True)
(= (penguin polly) True)

;`not` still cannot say it.
!(test (collapse (not (penguin tweety))) ())

;not-provable can.
!(test (not-provable (penguin tweety)) True)
!(test (not-provable (penguin polly)) False)

;Default reasoning, which is what this is for: birds fly unless they are
;penguins. The negation runs with $x already bound by (bird $x).
(= (flies $x) (and (bird $x) (not-provable (penguin $x))))
!(test (collapse (let True (flies $x) $x)) (tweety))

;;;; The two defects this repairs ;;;;
;
;Both are named in The Art of Prolog, 2nd edition, section 11.3, page 199.
;Negation as failure "is not guaranteed to work correctly for nonground
;goals", and the book gives two cases where it silently answers wrongly.

;The first. Their program is
;    unmarried_student(X) :- not married(X), student(X).
;with student(bill) and married(joe) in the database. Prolog FAILS on
;unmarried_student(X), "ignoring that X=bill is a solution logically implied
;by the rule and two facts". The negation runs first, with X unbound, and
;negation as failure cannot bind.
(= (student bill) True)
(= (married joe) True)
(= (unmarried-student $x)
   (and (not-provable (married $x)) (student $x)))
!(test (collapse (let True (unmarried-student $x) $x)) (bill))

;The second, from the same page: `not (X=1), X=2` fails in Prolog although
;X=2 is a solution. Here the negation leaves a disequality behind instead of
;a failed proof, and the later binding satisfies it.
(= (two-but-not-one $x)
   (and (not-provable (== $x 1)) (let $x 2 True)))
!(test (collapse (let True (two-but-not-one $x) $x)) (2))

;;;; A variable local to the negation is universally quantified ;;;;
;
;Section 11.5, page 207, is a default rule for welfare payments. Their cut
;version "only works correctly to determine the pension to which a given
;person is entitled"; the negated one answers in every direction. Its rule is
;    entitlement(X, nothing) :- not pension(X, Y).
;where Y occurs nowhere else, so it means "no pension at all" rather than
;"some Y that is not a pension". A variable that only the negation reads is
;existential there, so it is universal under the negation.

(= (invalid mc-tavish) True)
(= (over-65 mc-tavish) True)
(= (over-65 mc-donald) True)
(= (over-65 mc-duff) True)
(= (paid-up mc-tavish) True)
(= (paid-up mc-donald) True)

(= (pension $p invalid-pension) (invalid $p))
(= (pension $p old-age-pension) (and (over-65 $p) (paid-up $p)))
(= (pension $p supplementary-benefit) (over-65 $p))

(= (entitlement $p $what) (pension $p $what))
(= (entitlement $p nothing) (not-provable (pension $p $any)))

!(test (collapse (let True (entitlement mc-tavish $w) $w))
       (invalid-pension old-age-pension supplementary-benefit))
!(test (collapse (let True (entitlement mc-duff $w) $w))
       (supplementary-benefit))
!(test (collapse (let True (entitlement someone-else $w) $w)) (nothing))

;;;; Reading a constructive answer ;;;;
;
;"Which node has no outgoing edge" has infinitely many answers, so the answer
;is a constraint and not a list. Printed on its own it is an unbound variable,
;which reads as no answer at all; residual-goals says what it is carrying.

(= (edge a b) True)
(= (edge b c) True)
(= (has-no-outgoing $x) (not-provable (edge $x $y)))

!(test (has-no-outgoing c) True)
!(test (has-no-outgoing a) False)

;The constraint is live: bind the variable afterwards and it decides.
!(test (collapse (let True (has-no-outgoing $x) (let $x c $x))) (c))
!(test (collapse (let True (has-no-outgoing $x) (let $x zzz $x))) (zzz))
!(test (collapse (let True (has-no-outgoing $x) (let $x a $x))) ())

;;;; dif, and how it differs from != ;;;;
;
;dif is the constraint the duals are built from, and it is a function in its
;own right. It answers True and holds for as long as the answer does.
!(test (dif 1 2) True)
!(test (collapse (let True (dif $q 5) (let $q 6 $q))) (6))
!(test (collapse (let True (dif $q 5) (let $q 5 $q))) ())

;!= is a different operation and both are worth having. It asks whether two
;terms are identical NOW and answers immediately, so on an unbound variable it
;says True and lets a later binding contradict it. dif answers True and makes
;that later binding fail instead. Reach for != to compare two things you have,
;and for dif to state something about a value you do not have yet.
!(test (!= 1 2) True)
!(test (!= 1 1) False)
!(test (collapse (let True (!= $r 5) (let $r 5 $r))) (5))

;;;; let, and quantifying over a generator ;;;;
;
;A let is True when SOME answer of its value makes its body True, so it is not
;True when EVERY one of them fails. That is a universal quantification over a
;generator rather than over every term there is, and it is a much cheaper
;thing: the values can simply all be checked.
;
;Getting it wrong is the difference between checking one answer and checking
;all of them. carol has two marks and one of them passes, so she IS provable;
;dave has two and neither does.

(= (marks carol) 90)
(= (marks carol) 30)
(= (marks dave) 10)
(= (marks dave) 20)
(= (any-pass $w) (let $m (marks $w) (> $m 50)))

!(test (collapse (any-pass carol)) (True False))
!(test (not-provable (any-pass carol)) False)
!(test (not-provable (any-pass dave)) True)

;A value with no answer leaves the let with no answer, so it is not True.
!(test (not-provable (any-pass nobody)) True)

;And the answer stays constructive. What the generator narrows a variable to
;belongs in the answer rather than being quantified away, which is what
;collapse-bind already says an answer is: one binding per alternative. So this
;answers once per student who fails, and once more for everyone the marks say
;nothing about.
!(test (collapse (let True (not-provable (any-pass $w)) (let $w dave $w)))
       (dave))
!(test (collapse (let True (not-provable (any-pass $w)) (let $w carol $w))) ())
!(test (collapse (let True (not-provable (any-pass $w)) (let $w erin $w)))
       (erin))

;;;; Negating a space query ;;;;
;
;A match over a space is a generator too, and a better behaved one than a let:
;a space is finite, so what it narrows a variable to is always an enumeration
;and never a constraint.
;
;Note which variable is which. $y is local to the match and $x is not, and that
;is the whole difference: $y is quantified away, so "has a child" means "some
;y", while $x is answered, so "who has no child" is a real question.

!(bind! &kin (new-space))
!(add-atom &kin (parent alice bob))
!(add-atom &kin (parent carol dave))
(= (has-child $x) (match &kin (parent $x $y) True))

!(test (not-provable (has-child alice)) False)
!(test (not-provable (has-child bob)) True)
!(test (not-provable (has-child stranger)) True)

;And who has no child, answered by narrowing over the space and taking the
;complement of what it found.
!(test (collapse (let True (not-provable (has-child $w)) (let $w bob $w)))
       (bob))
!(test (collapse (let True (not-provable (has-child $w)) (let $w alice $w))) ())
!(test (collapse (let True (not-provable (has-child $w)) (let $w nobody $w)))
       (nobody))

;;;; case, and the forms that answer nothing ;;;;
;
;A case commits to the FIRST pattern its key matches, so its dual is the same
;chain with each branch dualised. The chain ends in True rather than failing:
;a key that matches no pattern leaves the case with no answer, and no answer
;is not True.

(= (band $n) (case $n ((90 True) (40 False))))
!(test (not-provable (band 90)) False)
!(test (not-provable (band 40)) True)
!(test (not-provable (band 55)) True)

;A superpose answers each element in turn, so it is not True exactly when none
;of them is. A collapse yields a LIST, always, so it is never True at all.
!(test (not-provable (superpose (False True))) False)
!(test (not-provable (superpose (False False))) True)
!(test (not-provable (superpose ())) True)

;;;; What has no dual ;;;;
;
;A form whose negation cannot be computed soundly raises rather than answering
;from an incomplete dual, because an incomplete dual answers "not provable"
;for something that is provable, which is a wrong answer and not a missing
;one. A builtin has no equations to negate, so (not-provable (+ 1 2)) raises;
;so does a special form. The comparisons are the exception, because each one's
;opposite is another comparison.
!(test (not-provable (> 1 2)) True)
!(test (not-provable (> 2 1)) False)
!(test (not-provable (== 1 1)) False)

;;;; Negating an arithmetic bound narrows a domain ;;;;
;
;The # family is CLP(FD), so its dual is not a test either: negating (#< $x 5)
;POSTS $x #>= 5 and leaves it standing. That is the point of doing negation
;with constraints rather than with search. It cuts the domain down instead of
;enumerating it, which is what makes a negated bound usable on a variable that
;has no value yet.
!(test (not-provable (#< 5 1)) True)
!(test (collapse (let True (not-provable (#< $x 5)) (let $x 7 $x))) (7))
!(test (collapse (let True (not-provable (#< $x 5)) (let $x 3 $x))) ())
!(test (collapse (let True (not-provable (#= $y 4)) (let $y 9 $y))) (9))
!(test (collapse (let True (not-provable (#= $y 4)) (let $y 4 $y))) ())
