!(import! &self (library lib_measure))
!(import! &self (library lib_soft))

;Symbol closeness: identity is 1.0, declared similarity reads both ways,
;anything else is 0.0.
(similar cat feline 0.8)
(similar dog wolf 0.7)
!(test (sym-sim cat cat) 1.0)
!(test (sym-sim cat feline) 0.8)
!(test (sym-sim feline cat) 0.8)
!(test (sym-sim cat dog) 0.0)

;Weak unification: structure crisp, symbols soft, minimum aggregation.
!(test (soft-score (likes cat fish) (likes cat fish)) 1.0)
!(test (soft-score (likes feline fish) (likes cat fish)) 0.8)
!(test (soft-score (likes feline wolf) (likes cat dog)) 0.7)
!(test (soft-score (likes cat) (likes cat fish)) 0.0)
!(test (soft-score (likes cat fish) (hates cat fish)) 0.0)
!(test (soft-score 3 3) 1.0)
!(test (soft-score 3 4) 0.0)

;A variable binds at degree one, and the binding is real:
!(test (soft-score $x anything) 1.0)
!(test (let $probe (soft-score (likes $who fish) (likes cat fish)) ($probe $who)) (1.0 cat))

;Soft matching over a space, feeding the measure algebra:
!(add-atom &zoo (likes cat fish))
!(add-atom &zoo (likes dog bones))
!(add-atom &zoo (likes bird seeds))
!(test (collapse (soft-match &zoo (likes feline fish) 0.5)) ((0.8 (likes cat fish))))
!(test (soft-best &zoo (likes feline fish)) (likes cat fish))
;Attention over terms: every candidate scored, softmaxed into a distribution.
!(test (size-atom (collapse (soft-match &zoo (likes $x $y) 0.0))) 3)
!(test (< (abs-math (- (ws-total (ws-softmax (collapse (soft-match &zoo (likes feline $f) 0.0)) 1.0)) 1.0)) 1.0e-9) true)
