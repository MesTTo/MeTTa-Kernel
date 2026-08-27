;The finger tree from lib_datastructures: O(1) at both ends, O(log n)
;concatenation, one structure serving as sequence and deque at once.

!(import! &self (library lib_datastructures))

;Build from both ends: push-front prepends, push-back appends.
!(test (ft-to-list (ft-push-front 1 (ft-push-back 3 (ft-push-front 2 (ft-empty)))))
       (1 2 3))

;A round trip through from-list keeps the order.
!(test (ft-to-list (ft-from-list (a b c d e f g h i j))) (a b c d e f g h i j))

;Both peeks, the tree untouched.
!(test (ft-front (ft-from-list (a b c))) a)
!(test (ft-back (ft-from-list (a b c))) c)

;Pops answer the element and the remaining tree, from either end.
!(test (let ($x $rest) (ft-pop-front (ft-from-list (a b c)))
            ($x (ft-to-list $rest)))
       (a (b c)))
!(test (let ($x $rest) (ft-pop-back (ft-from-list (a b c)))
            ($x (ft-to-list $rest)))
       (c (a b)))

;Deep trees: enough elements to force nodes into the middle, then a
;full drain from the front keeps the order exact.
!(test (ft-to-list (ft-from-list (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)))
       (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15))

;A deque workout: alternate ends, then read the whole thing.
!(test (ft-to-list
         (ft-push-back 9 (ft-push-front 0 (ft-from-list (4 5 6)))))
       (0 4 5 6 9))

;Concatenation is app3, the O(log n) join.
!(test (ft-to-list (ft-concat (ft-from-list (1 2 3 4 5))
                              (ft-from-list (6 7 8 9 10))))
       (1 2 3 4 5 6 7 8 9 10))
!(test (ft-to-list (ft-concat (ft-empty) (ft-from-list (x y)))) (x y))
!(test (ft-to-list (ft-concat (ft-from-list (x y)) (ft-empty))) (x y))
!(test (ft-to-list (ft-concat (ft-push-front a (ft-empty))
                              (ft-from-list (b c d e f g h))))
       (a b c d e f g h))

;Emptiness is a question, not an error.
!(test (ft-is-empty (ft-empty)) True)
!(test (ft-is-empty (ft-push-front 1 (ft-empty))) False)

;The documentation vocabulary reaches the tree's own docs.
!(test (ft-front (ft-from-list ((nested pair) plain))) (nested pair))
