; exp-math completes the -math family: e^x through the host's own exp.
!(test (exp-math 0) 1.0)
!(test (exp-math 1.0) 2.718281828459045)
!(test (< (abs-math (- (exp-math 2.0) (* 2.718281828459045 2.718281828459045))) 1.0e-12) true)
; log-math is the inverse: log base e of e^x is x, within float error.
!(test (< (abs-math (- (log-math 2.718281828459045 (exp-math 3.0)) 3.0)) 1.0e-12) true)

; The random generators answer inside their bounds, every draw.
(= (in-range $lo $hi $x) (and (<= $lo $x) (<= $x $hi)))
!(test (in-range 1 6 (random-int 1 6)) true)
!(test (in-range 0.0 1.0 (random-float 0.0 1.0)) true)
!(test (in-range 5 5 (random-int 5 5)) true)
