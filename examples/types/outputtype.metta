(: f (-> Number %Undefined%))
(= (f $x) (+ $x 42))

(: g (-> Number Atom))
(= (g $x) (+ $x 42))

(: h (-> Atom Atom))
(= (h $x) (+ $x 42))

!(test (f (+ 1 1)) 44)
; quote retains its wrapper in LeaTTa types-meta/30_evaluation_control.metta;
; noeval is the payload-preserving form these expected expressions require.
!(test (g (+ 1 1)) (noeval (+ 2 42)))
!(test (h (+ 1 1)) (noeval (+ (+ 1 1) 42)))
