; Purpose: transcribe the five pinned Scallop README examples as executable
; MeTTa programs and assert the README's printed answers.
; Guarantees: all five oracles pass through ordinary equations, folds,
; stratified not-provable, and set-valued uniqueness.
; Guarded by: test_the_scallop_readme_examples_answer_identically_through_the_seams
; [tested: test_the_scallop_readme_examples_answer_identically_through_the_seams; commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]

; Path over edges: README result {(0,1), (0,2), (1,2)}.
(sc-edge 0 1)
(sc-edge 1 2)
(= (sc-edge-to $a)
   (match (context-space) (sc-edge $a $b) $b))
(= (sc-path-to $a) (sc-edge-to $a))
(= (sc-path-to $a)
   (let $b (sc-edge-to $a) (sc-path-to $b)))
(= (sc-paths)
   (collapse
      (let $a (match (context-space) (sc-edge $a $_) $a)
        (let $b (sc-path-to $a) ($a $b)))))
!(test (sc-paths) ((0 1) (0 2) (1 2)))

; Stratified even/odd: negation sees the finite number relation whole.
(sc-number 0) (sc-number 1) (sc-number 2) (sc-number 3)
(sc-number 4) (sc-number 5) (sc-number 6) (sc-number 7)
(sc-number 8) (sc-number 9) (sc-number 10)
(= (sc-odd? 1) True)
(= (sc-odd? $x)
   (let $n (match (context-space) (sc-number $x) $x)
     (sc-odd? (- $n 2))))
(= (sc-evens)
   (collapse
      (let $y (match (context-space) (sc-number $y) $y)
        (let True (not-provable (sc-odd? $y)) $y))))
!(test (sc-evens) (0 2 4 6 8 10))

; Count per color through the general fold operation.
(sc-object-color 0 "blue")
(sc-object-color 1 "green")
(sc-object-color 2 "blue")
(= (sc-one-color $c)
   (let $o (match (context-space) (sc-object-color $o $c) $o) 1))
(= (sc-color-count $c) (foldall + (sc-one-color $c) 0))
(= (sc-color-counts)
   (collapse
      (let $c (superpose ("blue" "green"))
        ($c (sc-color-count $c)))))
!(test (sc-color-counts) (("blue" 2) ("green" 1)))

; Argmax per class through an open reducer rather than a closed aggregate list.
(sc-class-student-grade 0 "tom" 50)
(sc-class-student-grade 0 "jerry" 70)
(sc-class-student-grade 0 "alice" 60)
(sc-class-student-grade 1 "bob" 80)
(sc-class-student-grade 1 "sherry" 90)
(sc-class-student-grade 1 "frank" 30)
(= (sc-pick-max $a $b) (if (> $a $b) $a $b))
(= (sc-class-max $c)
   (foldall sc-pick-max
            (match (context-space)
                   (sc-class-student-grade $c $_ $g)
                   $g)
            -1))
(= (sc-class-top)
   (collapse
      (let $c (superpose (0 1))
        (let $g (sc-class-max $c)
          (let $s
            (match (context-space)
                   (sc-class-student-grade $c $s $g)
                   $s)
            ($c $s))))))
!(test (sc-class-top) ((0 "jerry") (1 "sherry")))

; The probabilistic animal example counts relation values as a set. The raw
; proof multiset has four derivations, while unique makes Scallop's two.
(sc-is-a giraffe mammal)
(sc-is-a tiger mammal)
(sc-is-a mammal animal)
(sc-name 1 giraffe)
(sc-name 1 tiger)
(sc-name 2 giraffe)
(sc-name 2 tiger)
(= (sc-parent-kind $x)
   (match (context-space) (sc-is-a $x $y) $y))
(= (sc-ancestor-kind $x) (sc-parent-kind $x))
(= (sc-ancestor-kind $x)
   (let $y (sc-parent-kind $x) (sc-ancestor-kind $y)))
(= (sc-animal-object)
   (let ($o $kind)
     (match (context-space) (sc-name $o $kind) ($o $kind))
     (let $ancestor (sc-ancestor-kind $kind)
       (if (== $ancestor animal) $o (empty)))))
(= (sc-one-animal)
   (let $o (unique (sc-animal-object)) 1))
(= (sc-animal-count) (foldall + (sc-one-animal) 0))
!(test (sc-animal-count) 2)
