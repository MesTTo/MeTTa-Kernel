;An opaque native handle, held and used from MeTTa without ever becoming text.
;See the README beside this file for the build line and EXTENDING.md section 3
;for what a handle is and when to reach for one.
;
;The example skips itself when handle.so has not been built, because a C
;compiler is not one of the engine's requirements. It says so when it skips
;rather than passing quietly.

!(import! &self (library lib_import))
!(import! &self (library lib_file))

;The import is its own runnable, for the reason c_extension.metta explains: a
;call written in the same runnable as its import compiles while the name is
;still unregistered and stays unreduced.
!(if (file-exists "./examples/integration/c_extension/handle.so")
     (import_prolog_functions_from_file
        "./examples/integration/c_extension/handle_loader.pl"
        (vector-new vector-nth vector-bump vector-length))
     (println! "SKIPPED handle: handle.so is not built, see the README beside this file"))

;A thousand-element native vector reaches MeTTa as one value. Its CONTENTS
;never cross: reading one element is a call into C, not a walk over text.
!(if (file-exists "./examples/integration/c_extension/handle.so")
     (test (eval (vector-length (vector-new 1000))) 1000)
     True)

!(if (file-exists "./examples/integration/c_extension/handle.so")
     (test (eval (vector-nth (vector-new 1000) 700)) 700)
     True)

;The state behind the handle is the native one, not a copy of it, so three
;bumps through three separate MeTTa calls land on the same memory.
(= (bump-thrice)
   (let $v (vector-new 4)
        (progn (vector-bump $v 0) (vector-bump $v 0) (vector-bump $v 0))))

!(if (file-exists "./examples/integration/c_extension/handle.so")
     (test (eval (bump-thrice)) 3)
     True)

;It is an ordinary grounded value: it classifies as one and compares by
;identity, which is what makes two handles to two structures distinguishable.
;
;The handle is BOUND before it is asked about, because get-metatype takes an
;Atom and so does not reduce its argument: asking it about `(vector-new 1)`
;asks about the expression, which is an Expression, and that is the right
;answer to the question actually written.
!(if (file-exists "./examples/integration/c_extension/handle.so")
     (test (let $vector (vector-new 1) (get-metatype $vector)) Grounded)
     True)

!(if (file-exists "./examples/integration/c_extension/handle.so")
     (test (eval (let $v (vector-new 1) (== $v $v))) True)
     True)
