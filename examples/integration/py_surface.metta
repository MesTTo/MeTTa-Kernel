;MeTTa's Python surface: py-atom RESOLVES where py-call APPLIES.
;
;This is hyperon-experimental's surface and what the language's own tutorials
;teach. py-call is PeTTa's older spelling and still works exactly as it did;
;the difference is that baking the call into the operator means a Python
;function is never a value, so it cannot be held, passed or applied.
;
;Nothing here needs the petta Python package. The engine ships engine/petta_py.py
;and adds it to Python's path itself, so this runs under plain run.sh.

;A name resolves to an ATOM, and applying it is a separate step MeTTa does.
!(test ((py-atom len) (py-list (1 2 3))) 3)
!(test ((py-atom abs) -5) 5)

;A dotted path of any depth. Splitting on the first dot could not reach a
;submodule's attribute, so os.path.join was unreachable.
!(test ((py-atom os.path.join) "a" "b") "a/b")

;A STRING argument is a Python expression rather than a name, which is how one
;operator covers both.
!(test ((py-atom len) (py-atom "[1, 2, 3, 4]")) 4)

;py-dot READS an attribute. py-call's `.name` always calls, so a property or a
;plain field needed getattr by hand.
!(test (py-dot (py-atom "complex(3, 4)") real) 3.0)
!(test (py-dot (py-atom "complex(3, 4)") imag) 4.0)

;A bound method taken as a value, then applied. This is what "a callable is a
;value" buys: the method is an atom before it is a call.
!(test ((py-dot "  padded  " strip)) "padded")

;Keyword arguments, in the language's own spelling. Anything before Kwargs is
;positional.
!(test (collapse (py-iter ((py-atom "sorted") (py-list (3 1 2))
                                            (Kwargs (reverse true)))))
       (3 2 1))

;Python's containers, BUILT from MeTTa rather than only received.
!(test (py-dot (py-dot (py-tuple (1 2)) __class__) __name__) "tuple")
!(test (py-dot (py-dot (py-dict (("a" 1))) __class__) __name__) "dict")

;They NEST, which is what the language's own examples show:
;`(py-list (1 (2 (3 "3"))))` is `[1, [2, [3, "3"]]]`.
!(test (repr (py-list (1 (2 (3 "3"))))) "[1, [2, [3, '3']]]")
!(test (repr (py-dict (("a" "b") ("b" "c")))) "{'a': 'b', 'b': 'c'}")
!(test ((py-atom max) (py-list (-5 5 -3 10 8))) 10)

;A nested expression with no constructor around it is a LIST, and you say what
;you mean by nesting the constructor. So the default is the common case and the
;other one is one word away, rather than the outer container deciding for the
;inner one.
!(test (repr (py-tuple (1 (2 3)))) "(1, [2, 3])")
!(test (repr (py-tuple (1 (py-tuple (2 3))))) "(1, (2, 3))")

;Iteration is lazy and nondeterministic, which is MeTTa's own way of spelling a
;sequence. Nothing is drained: the generator below runs one step per answer, so
;an unbounded one still works and a million-element array costs the same as a
;small one.
!(test (collapse (py-iter (py-atom "iter([10, 20, 30])"))) (10 20 30))

;One element out of a billion, without materialising a billion. `once` takes
;the first answer and stops, which is only possible because py-iter yields one
;at a time: draining the iterator first would never return.
!(test (once (py-iter (py-atom "iter(range(10 ** 9))"))) 0)

;`bind!` gives the atom a name, which is the idiom the tutorial writes. It is
;a TOKEN: the specification says bind! "registers a new token which is replaced
;with an atom during the parsing of the rest of the program", and PeTTa's
;bind! used to accept only (new-state V) and fail silently on anything else.
!(bind! py-abs (py-atom "abs"))
!(test (py-abs -5) 5)

;A token holds any atom, not only a callable.
!(bind! greeting (Hello world))
!(test greeting (Hello world))

;And a state cell is still a state cell: that form binds no token, because
;PeTTa models a state by NAME and substituting the name away would take
;get-state with it.
!(bind! counter (new-state 7))
!(test (get-state counter) 7)

;A Python value that is a sequence has TWO readings, and you do not choose
;between them. It stays the Python object, so it passes back to Python as
;itself, and it also reads as a MeTTa expression when you take it apart.
!(test (car-atom (py-atom "(1, 2, 3)")) 1)
!(test (cdr-atom (py-atom "(1, 2, 3)")) (2 3))
!(test (size-atom (py-atom "(1, 2, 3)")) 3)
!(test (index-atom (py-atom "(10, 20, 30)") 1) 20)
;And the same value is still a tuple on the way in.
!(test (py-dot (py-dot (py-atom "(1, 2)") __class__) __name__) "tuple")

;A list reads the same way while staying LIVE, which is the difference that
;decides why it is a reference and a tuple need not be: appending through it is
;visible afterwards, because nothing was copied.
!(bind! numbers (py-atom "[7, 8]"))
!(test (car-atom numbers) 7)
!(test (let $ignored ((py-dot numbers append) 9) (size-atom numbers)) 3)

;Which values have a reading is Python's own rule, PEP 634's: a sequence other
;than a string. So a string stays one atom rather than becoming its characters,
;and a dict has no reading at all.
!(test (car-atom (py-atom "'abc'")) ())
!(test (car-atom (py-atom "{'a': 1}")) ())

;None is the unit value, `()`. That is what makes a method called only for its
;effect usable: it returns a value that a let binds, where Empty would have
;made the whole let vanish.
!(test (py-atom "None") ())
!(test (== (py-atom "None") ()) true)

;When you want MeTTa data rather than a reference, ask for it by type. Grounded
;and Expression are the language's own metatypes: Grounded is the live
;reference, Expression is a snapshot, and a snapshot unifies like anything else
;because that is all it is.
!(test (py-atom "[1, 2, 3]" Expression) (1 2 3))
!(test (let ($a $b $c) (py-atom "[1, 2, 3]" Expression) (sum $a $b $c)) (sum 1 2 3))
!(test (py-atom "[[1, 2], (3, 4)]" Expression) ((1 2) (3 4)))

;The same argument DECLARES a type when it is not a metatype, and get-type
;reports it beside the object's own Python classes. Everything arriving from
;Python is %Undefined% otherwise, so a Python function could not be reported
;as anything at all.
!(test (let $pow (py-atom math.pow (-> Number Number Number)) (collapse (get-type $pow)))
       (builtin_function_or_method (-> Number Number Number)))
;Declare nothing and the classes are the whole answer. The object is built
;first, the same way the line above builds it: get-type does not evaluate its
;argument, so asking about the unreduced (py-atom math.sqrt) reports what
;that EXPRESSION is declared to be, not what building it would produce.
!(test (let $sqrt (py-atom math.sqrt) (collapse (get-type $sqrt)))
       (builtin_function_or_method))

;The reading in between is py-iter, which is superpose for a Python sequence,
;and collapse turns it back into an expression one level deep. Nothing here is
;a new way to say something MeTTa could not already say.
!(test (collapse (py-iter (py-atom "[1, 2, 3]"))) (1 2 3))

;A Python exception is a MeTTa error. `catch` is the form that catches one, and
;what it answers is an ordinary atom: the class to branch on, the message to
;read, and your own call to point at. Nothing in it is a live Python object, so
;it prints, compares, and outlives the failure.
!(bind! divide (py-atom "lambda a, b: a / b"))
!(test (car-atom (catch (divide 1 0))) Error)
!(test (catch (divide 6 3)) 2.0)

;And it takes apart, which is most of what an error is for: a program that can
;see THAT a call failed but not WHAT failed cannot do anything about it.
(= (failure-of $e) (index-atom $e 1))
(= (class-of $e) (index-atom (failure-of $e) 1))
(= (message-of $e) (index-atom (failure-of $e) 2))
!(test (class-of (catch (divide 1 0))) ZeroDivisionError)
!(test (message-of (catch (divide 1 0))) "division by zero")

;The context names the call that failed, arguments included, which is what a
;failure three levels down needs: Python's own report names a Python function
;and a Python file and no MeTTa call at all.
(= (call-of $e) (index-atom (index-atom $e 2) 1))
!(test (car-atom (call-of (catch (py-atom "nosuchmodule.thing")))) py-atom)
!(test (class-of (catch (py-atom "nosuchmodule.thing"))) NameError)
