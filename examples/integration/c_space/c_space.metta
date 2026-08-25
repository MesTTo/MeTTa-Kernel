;A space whose atoms live in C. cstore.pl puts four multifile clauses on
;the foreign-space seam and cstore.c holds the atoms as the engine's own
;text, so (add-atom &cstore ...) and (match &cstore ...) reach C with
;nothing engine-side knowing the backend exists. See the README beside
;this file for the build line, and EXTENDING.md section 5 for the seam.
;
;The example skips itself when cstore.so has not been built, because a C
;compiler is not one of the engine's requirements. It says so when it
;skips rather than passing quietly.

!(import! &self (library lib_import))
!(import! &self (library lib_file))
!(import! &self (library lib_conformance))

;The load has to be its own runnable, so the provider's clauses exist
;before anything below compiles a query against the space.
!(if (file-exists "./examples/integration/c_space/cstore.so")
     (let "./examples/integration/c_space/cstore.pl" (consult_global) provider)
     (println! "SKIPPED c_space: cstore.so is not built, see the README beside this file"))

;Writes and reads cross into C; the engine keeps unification for itself.
;The provider declares enumerate and no match, so a bound pattern is the
;engine filtering the C enumeration, which is the seam's own contract.
!(if (file-exists "./examples/integration/c_space/cstore.so")
     (progn (add-atom &cstore (edge a b))
            (add-atom &cstore (edge a c))
            (add-atom &cstore (edge b c))
            (test (collapse (match &cstore (edge a $x) $x)) (b c)))
     True)

;Removal means what remove-atom means everywhere: ONE occurrence that
;unifies goes, multiset subtraction, and the store answers whether one was
;there. Two stored atoms match (edge a $any), so clearing them takes two
;removals rather than one.
!(if (file-exists "./examples/integration/c_space/cstore.so")
     (progn (remove-atom &cstore (edge a $any))
            (test (let $answers (collapse (match &cstore (edge $x $y) ($x $y)))
                    (size-atom $answers))
                  2)
            (remove-atom &cstore (edge a $other))
            (test (collapse (match &cstore (edge $x $y) ($x $y))) ((b c))))
     True)

;Identical copies are where the reading matters most, and where this store
;used to disagree with the seam it implements: three adds gave count 3 and
;one removal gave count 0. Subtraction walks the count down one at a time.
!(if (file-exists "./examples/integration/c_space/cstore.so")
     (progn (add-atom &cstore (dup 1))
            (add-atom &cstore (dup 1))
            (add-atom &cstore (dup 1))
            (remove-atom &cstore (dup 1))
            (test (let $answers (collapse (match &cstore (dup $n) $n))
                    (size-atom $answers))
                  2)
            (remove-atom &cstore (dup 1))
            (remove-atom &cstore (dup 1))
            (test (let $answers (collapse (match &cstore (dup $n) $n))
                    (size-atom $answers))
                  0))
     True)

;The seam's own proof harness, asked of the C provider: every declared
;capability has clauses behind it, the match family holds over the one
;atom the store holds here (the atom itself, each position opened to a
;fresh variable, repeated-variable folds), the source discipline reads
;as declared, a canary atom survives the add-enumerate-remove round trip
;through the C-backed writes, and no pushdown claim overreaches. It
;RAISES on a violation, so the answer below is what a healthy provider
;reports.
!(if (file-exists "./examples/integration/c_space/cstore.so")
     (test (check-space-provider &cstore)
           ("enumerate: declared, seam:foreign_atoms/2 has clauses"
            "add: declared, seam:foreign_add/2 has clauses"
            "remove: declared, seam:foreign_remove/3 has clauses"
            "clear: declared, seam:foreign_clear/1 has clauses"
            "match: over-approximation holds over 1 atoms and their pattern families"
            "source: repeated, two enumerations agree"
            "round trip: add then enumerate answers the atom, and remove takes it back"
            "pushdown: 0 of 1 patterns claimed exact, and are"
            "plan: not declared, so a conjunction takes the engine's split"))
     True)

;Concurrent writers: hyperpose runs the branches on worker threads, and
;the store's mutex plus snapshot enumeration keep every line whole. The
;count is deterministic however the branches interleave.
!(if (file-exists "./examples/integration/c_space/cstore.so")
     (progn (collapse (hyperpose ((add-atom &cstore (row 1))
                                  (add-atom &cstore (row 2))
                                  (add-atom &cstore (row 3))
                                  (add-atom &cstore (row 4)))))
            (test (let $answers (collapse (match &cstore (row $n) $n))
                    (size-atom $answers))
                  4))
     True)
