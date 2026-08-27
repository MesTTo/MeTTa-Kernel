; Purpose: define the standard vocabulary the engine loads with no import.
; Guarantees:
;   - the doc family receives the upstream Atom masks and formal signatures
;     [tested: test_the_doc_family_answers_what_upstream_answers].
;   - is-function observes the unit arrow as an arrow while the internal type
;     classifier remains free to require a result child.
;   [tested: test_the_empty_expressions_type_follows_the_arbiters_ruling; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None
;
; %%%% The engine's prelude: standard vocabulary, no import needed. %%%%
;
; Every form here is part of the core engine. The loader in metta.pl
; compiles these equations into the base tier at startup and registers
; each name as a builtin, so they are reachable from every space with no
; import!, shadowable per named space exactly as builtins are, and their
; atoms appear in NO space: a program enumerating &self sees only its
; own writes. Declarations land in the engine's prelude type register,
; where get-type and the call-site compiler read them after a program's
; own declarations, so a user redeclaration wins.
;
; The forms are Hyperon's standard vocabulary, promoted from
; lib/lib_he/lib_he.metta by the same route unify, add-reduct, add-atoms,
; add-reducts and evalc took before them: standard library operations
; rather than compatibility shims, and a program should not have to
; import anything to reach them. The equations ARE the executable spec;
; the parameter-evaluation decisions (which arguments are Atom) are
; carried over from the library unchanged, with the reasoning kept
; beside each.

;;; Equality and reduction ;;;

;if-equal compares by ALPHA-EQUIVALENCE, not ==: Hyperon implements it
;with core.rs atoms_are_equivalent, atoms equal up to a consistent
;variable renaming, and the arbiter mechanises exactly that
;[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, ifEqualOp]. The
;library shim compared with ==, which misses (f $x $x) against
;(f $y $y); the promotion fixes the contract, the same way add-reduct's
;promotion fixed its.
(: if-equal (-> Atom Atom Atom Atom %Undefined%))
(= (if-equal $A $B $Then $Else)
   (if (=alpha $A $B) $Then $Else))

(: if-equal2 (-> Atom Atom Atom Atom %Undefined%))
(= (if-equal2 $A $B $Then $Else)
   (if (=alpha $A $B) $Then $Else))

;A structural comparison whose operands stay written.  This declaration must
;precede the assert family because the engine prelude is compiled form by form;
;assertEqualToResult uses it to keep its expected-result tuple inert.
(: noreduce-eq (-> Atom Atom Bool))
(= (noreduce-eq $A $B)
   (=alpha $A $B))

;The non-Msg assert forms take Atom parameters and compare RESULT SETS,
;exactly as their own Msg twins below always did and as the arbiter
;declares them [source: same file, (: assertEqual (-> Atom Atom (->)))].
;The library evaluated the arguments applicatively and asserted once per
;combination, so a nondeterministic side asserted pairwise instead of
;set-wise; the two spellings agreed only on deterministic arguments.
;collapse owns the full evaluation.  Wrapping its operand in eval would add a
;minimal one-step frame, so `(collapse (eval 2))` correctly retains `(eval 2)`
;instead of producing the singleton value set this assertion needs.
;The return type stays %Undefined% for the reason type-cast's note
;records: an Atom RESULT type would leave the body untranslated.
(: assertEqual (-> Atom Atom %Undefined%))
(= (assertEqual $A $B)
   (assert (== (collapse $A) (collapse $B))))

;=alpha holds both operands as written, so a caller that wants the RESULT
;sets compared has to collapse them into variables first and hand those
;over. The arbiter's own stdlib writes the same sequence with chain
;[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:2891-2895,
;(= (assertAlphaEqual $actual $expected) (chain (context-space) $space
;(chain (metta (collapse $actual) ...) $actual-results ...)))]. The == forms
;need no such step because (: == (-> $a $a Bool)) is a type variable and a
;type variable evaluates.
(: assertAlphaEqual (-> Atom Atom %Undefined%))
(= (assertAlphaEqual $A $B)
   (let $Actual (collapse $A)
     (let $Expected (collapse $B)
       (assert (=alpha $Actual $Expected)))))

;The ToResult forms do not evaluate their second argument: it is the set
;of expected results, written as a tuple. Both parameters are Atom so
;neither is evaluated on the way in, and the first is collapsed here into
;the tuple of every result it produces. Hyperon's own corpus states the
;contract, in tests/corpus/a1_symbols.metta: "assertEqualToResult checks
;all the results of the first expression; it doesn't evaluate the second
;expression, which is treated as a set of expected results."
;The comparison is NAMED here and the verdict is what crosses to assert.
;assert holds its operand and evaluates it, so handing it `(== $Actual $B)`
;would evaluate $B's value a second time and `(assertEqualToResult (+ 1 1)
;((+ 1 1)))` would pass, where the arbiter answers
;`(Error ... "\nExpected: [(+ 1 1)]\nGot: [2]...")`
;[measured 2026-08-24 against LeaTTa 9ea9f9d]. A Bool has no structure left to
;re-evaluate, which is why the verdict travels and the comparison does not.
;The arbiter reaches the same place by routing these forms around assert
;entirely, through the quoting `_assert-results-are-equal`
;[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:2871-2874 and :759-760].
;That operation compares MULTISETS: order is ignored, but one occurrence on
;one side consumes exactly one occurrence on the other.  The two directed
;subtractions below are the same bag-difference test using this engine's
;identity-preserving subtraction-atom.  Both must be empty, so `(a a b)` does
;not equal `(a b b)` even though their ordinary sets agree
;[source: LeaTTa@9ea9f9d MettaHyperonFull/Minimal/Stdlib.lean:364-438,
;`bagDiffBy` and `assertResultsEqOp`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
;Only the comparison changes.  The public MeTTa contract remains the existing
;True answer on success and metta_assertion_failed exception on failure.
(: assertEqualToResult (-> Atom Atom %Undefined%))
(= (assertEqualToResult $A $B)
   (let $Actual (collapse $A)
     (let $Missed (subtraction-atom $B $Actual)
       (let $Excessive (subtraction-atom $Actual $B)
         (let $Same (noreduce-eq ($Missed $Excessive) (() ()))
           (assert $Same))))))

(: assertAlphaEqualToResult (-> Atom Atom %Undefined%))
(= (assertAlphaEqualToResult $A $B)
   (let $Actual (collapse $A)
     (assert (=alpha $Actual $B))))

;Every expected result must appear among the results produced.
;Subtracting the produced set from the expected one leaves nothing when
;all of them did. subtraction-atom's two parameters are Expression and so
;hold their arguments as written, which is why the collapse is named first
;and the variable handed over; the arbiter's own definition sequences it the
;same way [source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:2834-2840,
;(= (assertIncludes $atom $content) (let $eval_atom (collapse $atom) (let
;$diff (subtraction-atom $content $eval_atom) ...)))].
(: assertIncludes (-> Atom Atom %Undefined%))
;The verdict crosses to assert rather than the comparison, for the reason
;assertEqualToResult above records: the difference is a set of WRITTEN
;expectations and == would evaluate it.
(= (assertIncludes $A $B)
   (let $Actual (collapse $A)
     (let $Diff (subtraction-atom $B $Actual)
       (let $Empty (== $Diff ())
         (assert $Empty)))))

;The Msg variants carry a failure message. assert/2 already reports the
;failing expression, so each delegates and the message is accepted but
;unused.
(: assertEqualMsg (-> Atom Atom Atom %Undefined%))
(= (assertEqualMsg $A $B $M)
   (assert (== (collapse $A) (collapse $B))))

(: assertAlphaEqualMsg (-> Atom Atom Atom %Undefined%))
(= (assertAlphaEqualMsg $A $B $M)
   (let $Actual (collapse $A)
     (let $Expected (collapse $B)
       (assert (=alpha $Actual $Expected)))))

(: assertEqualToResultMsg (-> Atom Atom Atom %Undefined%))
(= (assertEqualToResultMsg $A $B $M)
   (assertEqualToResult $A $B))

(: assertAlphaEqualToResultMsg (-> Atom Atom Atom %Undefined%))
(= (assertAlphaEqualToResultMsg $A $B $M)
   (assertAlphaEqualToResult $A $B))

;Minimal MeTTa's three frame/carrier instructions are engine vocabulary. Their
;Prolog bodies live in lib/minimal_metta_lib/minimal_metta_lib.pl because a function frame needs
;a bounded evaluation loop and collapse-bind must retain branch bindings.
;These declarations precede every equation whose RHS is a function frame so
;the form is held and entered as a frame instead of being compiled as a call.
(: function (-> Atom Atom))
(: collapse-bind (-> Atom Expression))
(: superpose-bind (-> Expression Atom))

;;; Error handling ;;;

;The `function` wrapper is part of if-error's protocol, not presentation.
;Minimal `eval` stages an ordinary equation RHS but enters a returned function
;frame, so this reference body works through both native and reflected doors.
;[source: MettaHyperonFull/Minimal/Stdlib.lean:4015-4032, `if-error`;
;commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
(= (if-error $atom $then $else)
   (function (chain (eval (get-metatype $atom)) $meta
     (eval (if-equal $meta Expression
       (eval (if-equal $atom ()
         (return $else)
         (chain (decons-atom $atom) $list
           (unify $list ($head $tail)
             (eval (if-equal $head Error (return $then) (return $else)))
             (return $else)))))
       (return $else))))))

;throw is the half of the error story a program could not reach. It could
;BUILD an (Error ...) atom and it could CATCH a host exception, but a built
;atom is DATA: its refusal is decided from its static type, so
;`(+ (Error source message) 1)` is a BadArgType about an ErrorType operand
;rather than that error escaping. throw PRODUCES one, and a produced error
;finishes the enclosing call with it, so the atom a program raises here
;travels exactly as one the engine raised
;[source: ai-plan-synthesis-draft.md 8.10, "the only one that changes
;expressiveness, since a program can build (Error ...) and catch host
;exceptions but cannot raise"]
;[tested: test_a_thrown_reason_travels_as_a_produced_error].
;
;Re-raising is the same call: a reason that is ALREADY an error atom is
;handed on unchanged rather than wrapped a second time, so
;`(throw (catch (/ 1 0)))` raises the host error the catch reified instead of
;burying it. Upstream has no throw, so nothing here diverges from it; the
;shape follows the vocabulary's own, (Error <culprit> <reason>), with the
;throw call as the culprit.
(: throw (-> %Undefined% %Undefined%))
(= (throw $reason)
   (if-error $reason $reason (Error (throw $reason) $reason)))

;Like if-error, this outer frame is the staging boundary consumed by eval.
;[source: MettaHyperonFull/Minimal/Stdlib.lean:4033-4043,
;`return-on-error`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
(= (return-on-error $atom $then)
   (function (eval (if-equal $atom Empty (return (return Empty))
     (eval (if-error $atom (return (return $atom))
       (return $then)))))))

;;; Evaluation control ;;;

(= (for-each-in-atom $L $f)
   (map-atom $L $f))

;;; Atomicity ;;;

;atomically runs its argument inside one transaction, the name the
;concurrency vocabulary uses for an atomic block: Haskell's STM spells it
;`atomically`, Clojure's spells it `dosync`, and `transaction` is the same
;operation under the database name. Before this it did not exist, so
;!(atomically (+ 1 1)) answered (atomically 2), an unknown head applied to
;its evaluated argument, rather than running anything atomically.
;
;It is sugar over (transaction ...), deliberately, so the two forms cannot
;drift: every guarantee here is metta_transaction/1's, answer preservation
;and whole-set commit-or-rollback included, and there is one implementation
;of them.
;
;They are still not the same operation, and this is the difference.
;transaction is a SPECIAL FORM whose body is compiled into the call site, so
;the body has to be written there: (let $b <a term> (transaction $b))
;answers the TERM, unrun, because there is nothing to compile at the call
;site but a variable. atomically takes its body as an unreduced Atom and
;evaluates it, so the body may be a term the program computed. The 183
;inferences that separate them, 773.05 against 956.07 over a three-answer
;body [measured 2026-08-19], are what evaluating a runtime term costs
;against compiling the body in place.
(: atomically (-> Atom %Undefined%))
(= (atomically $expr) (transaction (eval $expr)))

;;; Quoting ;;;

;Upstream's single clause suffices now that a missed equation carries the
;NotReducible protocol and the application boundary retains the written call.
;The operand EVALUATES, `(: unquote (-> %Undefined% %Undefined%))` in the
;arbiter's own prelude, and that is what lets the quote arrive from a
;computation rather than only from source: `!(unquote (car-atom ((quote
;(+ 1 2)))))` is 3 there and was the whole unreduced call here
;[measured 2026-08-24 against LeaTTa 9ea9f9d]. The two clauses below are
;unaffected by the change, because a `(quote ...)` operand evaluates to itself:
;quote's declared `Atom` result is what makes its answer final.
(: unquote (-> %Undefined% %Undefined%))
(= (unquote (quote $A))
   (let $cut (cut) (eval $A)))

;The reference stdlib's public evaluator entry is `interpret`, whose first
;operand is held and whose Atom result is already final.  The full extracted
;stdlib replaces this bootstrap equation with its source interpreter.  Before
;that source is loaded, the native `metta` operation supplies the same typed
;evaluation boundary; a function frame is required so the Atom result rule
;does not return the `(metta ...)` call itself as inert data.
;[source: LeaTTa@9ea9f9d MettaHyperonFull/Minimal/Stdlib.lean:4311-4336,
;`interpret`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
(: interpret (-> Atom Type SpaceType Atom))
(= (interpret $atom $type $space)
   (function
     (chain (eval (metta $atom $type $space)) $result
       (return $result))))

;;; Types ;;;

;An arrow type is variadic.  Inspecting its first element handles every arity;
;the old pair of fixed heads recognized only `(->)` and one-argument arrows,
;so the ordinary `(-> Number Number Number)` function type was classified as
;False by the source interpreter.
;[source: MettaHyperonFull/Minimal/Stdlib.lean:4010-4038,
;`is-function`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
(: -> (-> (%Rest% Type) Type))
(: is-function (-> Type Bool))
(= (is-function $type)
   (let $mtype (get-metatype $type)
     (unify $mtype Expression
       (let $size (size-atom $type)
         (unify $size 0
           False
           (let ($head $tail) (decons-atom $type)
             (unify $head -> True False))))
       False)))

;get-type-space is a native builtin now: the engine's own get-type run
;with the selected space as context, upstream's selected-space spelling
;[source: pinned stdlib.md:849-868 via the arbiter]. The library's stub
;matched the literal &self and answered nothing for any named space.

;These two declarations are HERE rather than only in
;lib/lib_builtin_types/lib_builtin_types.metta because this is the register the CALL SITE
;reads. Asking for a type is a question about an expression, and the
;engine was answering it by running the expression first: an op that
;appends to a Python list fired on (get-type (metta-effectful)) and the
;answer was Number, the type of what it returned. Every linter walk and
;every REPL inspection was invisibly effectful on a seam whose whole
;purpose is arbitrary effects.
;
;An Atom parameter in the engine's own surface register is deliberately
;NOT honoured at call sites, because several of those declarations
;describe the argument a CALLER writes rather than the value the
;predicate receives, and honouring them broke every maplist call
;[source: call_site_type_chains/2 in engine/translator.pl]. get-type has no
;such gap: the declaration and the predicate agree that the argument
;arrives unreduced, so the prelude register, which IS honoured at call
;sites, is where it belongs.
;
;The answer then comes from the declaration, which is what the arbiter
;answers: (get-type (literal-return 2)) is Atom for
;(: literal-return (-> Number Atom)), whatever its body would reduce to
;[source: LeaTTa tests/semantics/types-meta/20_atom_return_literal.metta,
;MEASURED [Atom] from the mechanised interpreter and from hyperon
;0.2.10 alike].
;
;Both arrows are upstream's, written exactly as upstream writes them:
;get-type is (-> Atom %Undefined%) and get-type-space is
;(-> SpaceType Atom Atom) at pinned stdlib.md:849-868. The first parameter
;said Symbol here while a space handle answered Symbol, and had to move with
;the handle's own type [tested: spaces:space_handle_type]. Either return spelling behaves identically in
;this engine, measured 2026-08-19 over an effectful call, a declared
;return, a value and a builtin application, so upstream's is kept because
;matching it costs nothing.
(: get-type (-> Atom %Undefined%))
(: get-type-space (-> SpaceType Atom Atom))

;match-types is UNIFICATION with wildcards, not equality: %Undefined%
;and Atom on either side match anything, and otherwise the two types unify,
;bindings and all. The function frame is the reference's one-step boundary.
;[source: MettaHyperonFull/Minimal/Stdlib.lean:4114-4125, `match-types`;
;commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
(= (match-types $type1 $type2 $then $else)
   (function (eval (if-equal $type1 %Undefined%
     (return $then)
     (eval (if-equal $type2 %Undefined%
       (return $then)
       (eval (if-equal $type1 Atom
         (return $then)
         (eval (if-equal $type2 Atom
           (return $then)
           (unify $type1 $type2 (return $then) (return $else))))))))))))

;Upstream's parameter order: the fold accumulator FIRST, then the
;candidate type, then the wanted type [source: same file,
;(= (match-type-or $folded $next $type) ...)]. The library had the
;accumulator first but swapped the two types through its own helper.
(= (match-type-or $folded $next $type)
   (function
     (chain (eval (match-types $next $type True False)) $matched
       (chain (eval (or $folded $matched)) $or (return $or)))))

;The fold used by type-cast is defined before its caller so the engine prelude's
;single-pass compiler sees an executable function rather than a constructor.
;foldl-atom's list parameter is Expression, so the collected declarations are
;named before it reads them.
(= (type-cast-holds $atom $type $space)
   (let $declarations (collapse (get-type-space $space $atom))
     (foldl-atom $declarations False $acc $declared
        (match-type-or $acc $declared $type))))

;type-cast, upstream's contract: the atom when the cast holds, the flat
;(Error $atom BadType) when it does not. UNDECLARED ON PURPOSE, and the
;absence carries behaviour: upstream ships this equation with no
;(: type-cast ...) line, so the operands evaluate before the equation
;runs, and an ill-typed subject reports its OWN error instead of being
;swallowed by an Atom mask. The arbiter measured exactly that against
;pinned Hyperon 0.2.10 [source: LeaTTa Stdlib.lean, the type-cast note
;and tests/semantics/types-basic/50-53]. The library declared Atom
;parameters and compared metatypes with ==; both diverged.
;The atom's metatype is NAMED before the comparison. Both of =alpha's declared
;parameters are `Atom`, so an operand written as a call reaches the comparison
;unreduced and `(=alpha Symbol (get-metatype A))` compares a symbol with a call
;instead of with `Symbol`; the reference's own type-cast names the same value
;first, through a chain [source: LeaTTa MettaHyperonFull/Minimal/
;Stdlib.lean:4206-4209, `(chain (eval (get-metatype $atom)) $meta ...)`].
(= (type-cast $atom $type $space)
   (let $meta (get-metatype $atom)
     (if (=alpha $type $meta)
         $atom
         (if (type-cast-holds $atom $type $space)
             $atom
             (Error $atom BadType)))))

;;; Documentation ;;;
;
;The prelude documents its own vocabulary; the loader routes these into
;the engine's doc register, get-doc's first tier, so (help! type-cast)
;answers with no import and a program's own (@doc ...) atoms stay the
;program's. Descriptions follow the pinned corelib's where it has them.

;The unary get-doc is MeTTa's raw-document convenience. The two-input arrow
;and the four helpers are upstream's formal family. Atom keeps each documented
;subject and prose part unevaluated while the engine joins them with the type
;from the selected space [source: hyperon-experimental@3f76dc4,
;lib/src/metta/runner/stdlib/stdlib.metta:795-875].
(: get-doc (-> Atom %Undefined%))
(: get-doc (-> SpaceType Atom %Undefined%))
(: get-doc-atom (-> SpaceType Atom %Undefined%))
(: get-doc-single-atom (-> SpaceType Atom %Undefined%))
(: get-doc-function (-> SpaceType Atom Type %Undefined%))
(: get-doc-params (-> Expression Atom Expression (Expression Atom)))

(@doc if-equal
  (@desc "Selects the third argument when the first two are alpha-equivalent, atoms equal up to a consistent variable renaming, and the fourth otherwise")
  (@params ((@param "First atom") (@param "Second atom") (@param "Result on equivalence") (@param "Result otherwise")))
  (@return "Third or fourth argument"))
(@doc if-equal2
  (@desc "if-equal under its second historical name")
  (@params ((@param "First atom") (@param "Second atom") (@param "Result on equivalence") (@param "Result otherwise")))
  (@return "Third or fourth argument"))
(@doc assertEqual
  (@desc "Compares the result sets of two expressions; passes silently or raises a failed assertion naming the expression")
  (@params ((@param "First expression, not evaluated on the way in") (@param "Second expression, not evaluated on the way in")))
  (@return "unit"))
(@doc assertAlphaEqual
  (@desc "assertEqual up to alpha-equivalence of the result sets")
  (@params ((@param "First expression") (@param "Second expression")))
  (@return "unit"))
(@doc assertEqualToResult
  (@desc "Checks all the results of the first expression against the second expression, which is not evaluated and is read as the set of expected results")
  (@params ((@param "Expression to evaluate") (@param "Expected results, as written")))
  (@return "unit"))
(@doc assertAlphaEqualToResult
  (@desc "assertEqualToResult up to alpha-equivalence")
  (@params ((@param "Expression to evaluate") (@param "Expected results, as written")))
  (@return "unit"))
(@doc assertIncludes
  (@desc "Passes when every expected result appears among the results the first expression produces")
  (@params ((@param "Expression to evaluate") (@param "Expected subset, as written")))
  (@return "unit"))
(@doc assertEqualMsg
  (@desc "assertEqual with a message argument, accepted and unused because the assertion already names the failing expression")
  (@params ((@param "First expression") (@param "Second expression") (@param "Message")))
  (@return "unit"))
(@doc assertAlphaEqualMsg
  (@desc "assertAlphaEqual with a message argument, accepted and unused")
  (@params ((@param "First expression") (@param "Second expression") (@param "Message")))
  (@return "unit"))
(@doc assertEqualToResultMsg
  (@desc "assertEqualToResult with a message argument, accepted and unused")
  (@params ((@param "Expression to evaluate") (@param "Expected results") (@param "Message")))
  (@return "unit"))
(@doc assertAlphaEqualToResultMsg
  (@desc "assertAlphaEqualToResult with a message argument, accepted and unused")
  (@params ((@param "Expression to evaluate") (@param "Expected results") (@param "Message")))
  (@return "unit"))
(@doc if-error
  (@desc "Selects the second argument when the first is an (Error ...) expression and the third otherwise")
  (@params ((@param "Value to inspect") (@param "Result on error") (@param "Result otherwise")))
  (@return "Second or third argument"))
(@doc return-on-error
  (@desc "Answers the first argument when it is an (Error ...) expression, stopping the computation there, and the second otherwise")
  (@params ((@param "Value to inspect") (@param "Result when the first is not an error")))
  (@return "The error, or the second argument"))
(@doc for-each-in-atom
  (@desc "Applies a function to every element of an expression; map-atom under its historical name")
  (@params ((@param "Expression to walk") (@param "Function to apply")))
  (@return "The mapped expression"))
(@doc unquote
  (@desc "Unquotes a quoted atom and evaluates it, e.g. (unquote (quote $x)) evaluates $x; a non-quote argument stays as written")
  (@params ((@param "Quoted atom")))
  (@return "Unquoted atom"))
(@doc noreduce-eq
  (@desc "Compares two atoms as written, neither evaluated")
  (@params ((@param "First atom, as written") (@param "Second atom, as written")))
  (@return "True or False"))
(@doc is-function
  (@desc "True when the argument is an arrow type")
  (@params ((@param "Type atom")))
  (@return "True or False"))
(@doc match-types
  (@desc "Checks if two types can be unified and returns the third argument if so, the fourth otherwise; %Undefined% and Atom on either side match anything")
  (@params ((@param "First type") (@param "Second type") (@param "Atom to be returned if types can be unified") (@param "Atom to be returned if types cannot be unified")))
  (@return "Third or fourth argument"))
(@doc match-type-or
  (@desc "Checks if two types (second and third arguments) can be unified and returns the result of OR between the first argument and the type checking result")
  (@params ((@param "Boolean value") (@param "First type") (@param "Second type")))
  (@return "True or False"))
(@doc type-cast
  (@desc "Casts atom passed as a first argument to the type passed as a second argument using space as a context")
  (@params ((@param "Atom to be casted") (@param "Type to cast atom to") (@param "Context atomspace")))
  (@return "Atom if casting is successful, (Error ... BadType) otherwise"))
(@doc type-cast-holds
  (@desc "Whether any declared type of the atom in the space unifies with the requested type; type-cast's fold, named because MeTTa is applicative where the corelib chains")
  (@params ((@param "Atom") (@param "Requested type") (@param "Context atomspace")))
  (@return "True or False"))
(@doc get-type-space
  (@desc "get-type run with the selected space as the context")
  (@params ((@param "Space to select") (@param "Atom to type")))
  (@return "The type, as get-type answers it in that space"))
(@doc get-doc
  (@desc "Returns formal documentation for an atom or function in a selected space; the one-argument MeTTa overload returns the raw (@doc ...) atom")
  (@params ((@param "The space to search") (@param "The atom or function to document")))
  (@return "An (@doc-formal ...) atom"))
(@doc get-doc-atom
  (@desc "Builds formal atom documentation from prose and the selected space's type")
  (@params ((@param "The space to search") (@param "The atom to document")))
  (@return "An atom-shaped (@doc-formal ...) atom"))
(@doc get-doc-single-atom
  (@desc "Dispatches one atom to function or atom documentation according to its selected-space type")
  (@params ((@param "The space to search") (@param "The atom to document")))
  (@return "An (@doc-formal ...) atom"))
(@doc get-doc-function
  (@desc "Builds formal function documentation by pairing parameter and return prose with an arrow type")
  (@params ((@param "The space to search") (@param "The function name") (@param "Its arrow type")))
  (@return "A function-shaped (@doc-formal ...) atom"))
(@doc get-doc-params
  (@desc "Pairs informal parameter and return descriptions with their types")
  (@params ((@param "The (@param ...) list") (@param "The (@return ...) description") (@param "The parameter and return types")))
  (@return "The formal parameter list and return description"))
(@doc get-doc-space
  (@desc "get-doc run against the selected space")
  (@params ((@param "Space to select") (@param "The name to look up")))
  (@return "The (@doc ...) atom"))
(@doc help!
  (@desc "Prints the documentation for a name, the engine's own vocabulary included")
  (@params ((@param "The name to look up")))
  (@return "unit"))
(@doc documented
  (@desc "Every name the CURRENT SPACE documents, one per solution; program-scoped on purpose, so the engine's own vocabulary does not bury yours")
  (@params ())
  (@return "A name"))
(@doc documented-space
  (@desc "documented, against the selected space")
  (@params ((@param "Space to select")))
  (@return "A name"))
(@doc defined-name
  (@desc "Every function name the current space defines, builtins excluded, once each")
  (@params ())
  (@return "A name"))
(@doc undocumented
  (@desc "Every defined name in the current space with no documentation anywhere; the gap worth closing")
  (@params ())
  (@return "A name"))
(@doc undocumented-space
  (@desc "undocumented, against the selected space")
  (@params ((@param "Space to select")))
  (@return "A name"))

;;; Derived forms ;;;
;
; A form below is written in MeTTa, as an equation that says what the call
; EXPANDS TO, plus the registration that makes the translator consult it
; before it reaches its own special-form table. Nothing here needs a clause in
; the compiler: the expansion goes back through the ordinary translator, so
; one definition decides what the form means and the kernel carries one form
; fewer. The Atom parameters are what make an argument arrive as syntax; the
; %Undefined% RESULT type is what makes the (noeval ...) body translate, since
; an Atom result would leave the body untranslated and hand the noeval itself
; back as the expansion.
;
; Every form here was A/B'd against the compiler clause it replaced, on the
; goals it compiles to and on compile-time inference counts, over the whole
; examples corpus [tested: translator_derived_forms,
; test_a_prelude_derived_form_matches_its_fused_twin_on_the_corpus].

;and-then and or-else ARE `if` with one branch decided, which is what their
;compiler clauses spelled out by hand. The expansion compiles one goal FEWER
;than the clause did, because if builds its branches through build_branch/4
;and drops the empty conjunct the hand-written pair kept [measured 2026-08-19:
;the same conditional, minus one `true` conjunct].
(: and-then (-> Atom Atom %Undefined%))
(= (and-then $a $b) (noeval (if $a $b False)))
!(add-translator-rule! and-then)

(: or-else (-> Atom Atom %Undefined%))
(= (or-else $a $b) (noeval (if $a True $b)))
!(add-translator-rule! or-else)

;The stream operations. Each was a rewrite rule in the compiler that produced
;exactly the MeTTa term below, so moving them changes nothing but where they
;live [measured 2026-08-19: byte-identical compiled goals].
(: trace! (-> Atom Atom %Undefined%))
(= (trace! $message $value) (noeval (progn (println! $message) $value)))
!(add-translator-rule! trace!)

(: unique (-> Atom %Undefined%))
(= (unique $stream)
   (noeval (let $collapsed (collapse $stream)
             (let $kept (unique-atom $collapsed)
               (superpose $kept)))))
!(add-translator-rule! unique
   ((extra-variables-exempt "the let binders the expansion introduces name the collapsed answer sets before the masked family operation reads them, so none takes a value from the term being rewritten")))

(: alpha-unique (-> Atom %Undefined%))
(= (alpha-unique $stream)
   (noeval (let $collapsed (collapse $stream)
             (let $kept (alpha-unique-atom $collapsed)
               (superpose $kept)))))
!(add-translator-rule! alpha-unique
   ((extra-variables-exempt "the let binders the expansion introduces name the collapsed answer sets before the masked family operation reads them, so none takes a value from the term being rewritten")))

;The set operations name the shape they rewrite, `(superpose ...)` on both
;sides, exactly as the compiler's rewrite rules did. The second equation is
;what the compiler's identity clause was: a call that is not that shape is a
;program using the name as data, and `noeval` hands it back unevaluated
;rather than letting the expansion recurse [tested: translator_derived_forms].
(: union (-> Atom Atom %Undefined%))
(= (union (superpose $a) (superpose $b))
   (noeval (let $left (collapse (superpose $a))
             (let $right (collapse (superpose $b))
               (let $combined (union-atom $left $right)
                 (superpose $combined))))))
(= (union $a $b) (noeval (noeval (union $a $b))))
!(add-translator-rule! union
   ((extra-variables-exempt "the let binders the expansion introduces name the collapsed answer sets before the masked family operation reads them, so none takes a value from the term being rewritten")))

(: intersection (-> Atom Atom %Undefined%))
(= (intersection (superpose $a) (superpose $b))
   (noeval (let $left (collapse (superpose $a))
             (let $right (collapse (superpose $b))
               (let $combined (intersection-atom $left $right)
                 (superpose $combined))))))
(= (intersection $a $b) (noeval (noeval (intersection $a $b))))
!(add-translator-rule! intersection
   ((extra-variables-exempt "the let binders the expansion introduces name the collapsed answer sets before the masked family operation reads them, so none takes a value from the term being rewritten")))

(: subtraction (-> Atom Atom %Undefined%))
(= (subtraction (superpose $a) (superpose $b))
   (noeval (let $left (collapse (superpose $a))
             (let $right (collapse (superpose $b))
               (let $combined (subtraction-atom $left $right)
                 (superpose $combined))))))
(= (subtraction $a $b) (noeval (noeval (subtraction $a $b))))
!(add-translator-rule! subtraction
   ((extra-variables-exempt "the let binders the expansion introduces name the collapsed answer sets before the masked family operation reads them, so none takes a value from the term being rewritten")))

; has-declared-type asks whether (: <atom> <type>) is declared, about the
; atom AS ITSELF: the first parameter carries the Atom mask so the question
; is asked of the unreduced atom, the way get-type asks
; [tested: metta_has_declared_type in tests/prolog/suites/evaluation/metta.plt].
(: has-declared-type (-> Atom %Undefined% Bool))

; space-contains asks whether the space holds an atom unifying with the
; given one, about the atom AS ITSELF: one indexed probe against the
; store, flat however large the space grows, which is what a
; set-semantics rule wants per add.
(: space-contains (-> %Undefined% Atom Bool))

; %%%% Space admission: the shipped judge over (admits ...) and (capacity ...) %%%%
;
; The judge itself is the engine builtin space-admission-verdict,
; Prolog-bodied by measurement: the same chain written here as equations
; cost 131.01 inferences per add against the builtin body, the two
; collapse-over-match reads of &metta being the gap, and a pool is a
; millions-of-adds surface (bindings/python/benchmarks/extension_cost.py's
; write-door table is the record). The declaration below is the half of
; its contract that lives at this level: the Atom mask keeps the offered
; atom unreduced, so a pool judges the atom AS ITSELF
; [tested: the_sugar_judges_the_offered_atom_as_itself in tests/prolog/suites/spaces/hooks.plt].
; metta_admission_claim/2 writes a one-line guard equation,
;   (= (space-admission-guard-<pool> $x) (space-admission-verdict <pool> $x))
; into the declaring space and claims the pool's pre-add hook with it, so
; enforcement rides the general one-claimant registry and a space may
; shadow the judge like any builtin. The same judge written in MeTTa runs
; as executable documentation, with a differential against this builtin,
; in examples/ch15-writing-transactions-and-worlds/04-admission_pools.metta.
(: space-admission-verdict (-> %Undefined% Atom %Undefined%))
