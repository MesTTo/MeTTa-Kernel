;Clean separation from Python calls
(= (make-object) (py-call (types.SimpleNamespace)))
(= (get-attribute $obj $name) (py-call (getattr $obj $name)))
(= (set-attribute $obj $name $value) (py-call (setattr $obj $name $value)))
(= (import $name) (py-call (importlib.import_module $name)))
(= (math.pi) (get-attribute (import math) pi))

;Clean program using objects and pi:
!(test (let* (($obj (make-object))
              ($temp (set-attribute $obj foo (math.pi))))
             (get-attribute $obj foo))
       3.141592653589793)

;Verify py-call on methods of strings and numbers (see #188)
!(test (py-call (.upper "abc")) ABC)
!(test (py-call (.__add__ 5 3)) 8)

;Keyword arguments ride a bound callable: applying a py-atom splits a
;terminal (Kwargs ...) form into Python keywords, while py-call itself
;keeps upstream's plain positional semantics.
!(bind! py-round (py-atom round))
!(test (py-round 3.14159 (Kwargs (ndigits 2))) 3.14)

;A Python collection stays ONE object on this surface: the dict is held
;whole, and reading it is asking it, the same method-call shape as above.
!(bind! prefs (py-atom "dict(colour='green', size=7)"))
!(test (py-call (.get prefs size)) 7)

;The object loop closes with reflection: type answers the class, and the
;class is an object with attributes like any other.
!(test (py-dot (py-call (type (make-object))) __name__) "SimpleNamespace")
