;The Python surface against a real library, and these are the language's own
;tutorial examples rather than ones invented here
;[source: metta-lang.dev/docs/learn/tutorials/python_use/py_atom].
;
;Needs numpy, the way examples/integration/torch.metta needs torch.

!(bind! np-abs (py-atom numpy.absolute))

;A numpy scalar stays a numpy object. That is what the tutorial shows too, in
;as many words: its `(+ (abs -5) 10)` prints `np.int64(15)` rather than 15.
;Teaching `+` to accept one is a separate thing, the `py_ops` import.
!(test (py-dot (py-dot (np-abs -5) __class__) __name__) "int64")
!(test ((py-dot (np-abs -5) item)) 5)

;A Python expression as an argument, which is the tutorial's own line for it.
!(bind! np-array (py-atom numpy.array))
!(test (py-dot (py-dot (np-array (py-atom "[1, 2, 3]")) __class__) __name__)
       "ndarray")

;Keyword arguments, so a call can skip the defaults it does not care about.
;`arange` is the tutorial's example because it takes start, stop and step and
;means different things by how many you give it.
!(bind! np-arange (py-atom numpy.arange))
!(test (collapse (py-iter ((py-dot (np-arange 4) tolist)))) (0 1 2 3))
!(test (collapse (py-iter ((py-dot (np-arange (Kwargs (step 2) (stop 8))) tolist))))
       (0 2 4 6))
!(test (collapse (py-iter ((py-dot (np-arange (Kwargs (start 2) (stop 10) (step 3)))
                                   tolist))))
       (2 5 8))

;A SUBMODULE held as a value, then reached into. `(py-atom numpy.random.randint)`
;also works, and the tutorial's point is that holding `numpy.random` once and
;reaching into it is the cheaper shape when you want several of its functions.
!(bind! np-random (py-atom numpy.random))
!(test (py-dot (py-dot ((py-dot np-random randint) 25) __class__) __name__) "int")
