;Prove a foreign space provider before its users find out.
;
;`petta.testing.check_space_provider` takes a Python OBJECT, so the seam's
;faster tier had no way to prove itself: a Prolog provider is a set of
;multifile clauses and there is nothing to pass. This is the same three checks
;asked of a space NAME.

!(import! &self (library lib_conformance))

;The provider under test is a complete one in eight lines,
;_fixtures/demo_provider.pl. It declares an EXTENSION and exports nothing,
;which is the shape of a provider-only file: metta_export is for functions and
;a provider has none.
!(import_prolog_functions_from_file "./examples/libraries/_fixtures/demo_provider.pl" ())

;The checks that ran, in order: one per declared capability, then the
;over-approximation contract, then the pushdown claim.
!(test (check-space-provider &demo_provider)
       ("match: declared, metta_foreign_match/3 has clauses"
        "enumerate: declared, metta_foreign_atoms/2 has clauses"
        "match: over-approximation holds over 2 atoms"
        "pushdown: 0 of 2 patterns claimed exact, and are"
        "plan: not declared, so a conjunction takes the engine's split"))

;And it answers through the seam, which is the point of proving it.
!(test (sort-atom (collapse (match &demo_provider (edge a $y) $y))) (b))
