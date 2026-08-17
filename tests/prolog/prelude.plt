% Purpose: verify the engine prelude: the vocabulary promoted from lib_he is
%   reachable with no import, keeps the library's exact semantics, masks the
%   Atom parameters its declarations name, answers get-type, stores atoms in
%   no space, and stays additive under a user's own equations.
% Guarantees:
%   - assertEqualToResult's expected set arrives unevaluated
%     [tested: prelude:expected_set_is_not_evaluated].
%   - the prelude leaks no atom into &self enumeration
%     [tested: prelude:no_atom_leaks_into_self].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(prelude).

eval_string(Text, Results) :-
    sread(Text, Term),
    findall(R, eval(Term, R), Results).

% -- reachable with no import, both branches -------------------------------

test(if_equal_selects_then) :-
    eval_string("(if-equal 1 1 yes no)", [yes]).

test(if_equal_selects_else) :-
    eval_string("(if-equal 1 2 yes no)", [no]).

%The arbiter's contract: comparison is alpha-equivalence, so a consistent
%renaming matches and an inconsistent one does not.
test(if_equal_compares_alpha_equivalence) :-
    eval_string("(if-equal (f $x $x) (f $y $y) yes no)", [yes]),
    eval_string("(if-equal (f $x $x) (f $y $z) yes no)", [no]).

test(if_equal2_matches_if_equal) :-
    eval_string("(if-equal2 a b yes no)", [no]).

% -- the assert family ------------------------------------------------------

test(assertEqual_passes) :-
    eval_string("(assertEqual (+ 1 1) 2)", [true]).

test(assertEqual_failure_raises,
     [throws(error(petta_assertion_failed(_), _))]) :-
    eval_string("(assertEqual 1 2)", _).

test(assertAlphaEqual_renames_apart) :-
    eval_string("(assertAlphaEqual (f $x $x) (f $y $y))", [true]).

%Atom parameters on the non-Msg forms too, per the arbiter's
%declarations: both sides collapse to their result sets and the sets
%compare, the same body their Msg twins always had.
test(assertEqual_compares_result_sets) :-
    eval_string("(assertEqual (superpose (1 2)) (superpose (1 2)))", [true]).

%The corpus contract: all results of the first expression, second
%expression NOT evaluated, read as the set of expected results.
test(assertEqualToResult_collects_all_results) :-
    eval_string("(assertEqualToResult (superpose (1 2)) (1 2))", [true]).

test(expected_set_is_not_evaluated) :-
    %(+ 1 1) on the right must stay as written: the produced set is (2),
    %so a right side that evaluated to (2) would pass, and the unreduced
    %((+ 1 1)) must FAIL the comparison instead.
    catch(( eval_string("(assertEqualToResult (+ 1 1) ((+ 1 1)))", _),
            Verdict = passed ),
          error(petta_assertion_failed(_), _),
          Verdict = failed),
    Verdict == failed.

test(assertAlphaEqualToResult_over_variables) :-
    %eval strips the quote, so the produced set is ((f $a)) and the
    %expected set is written unquoted; =alpha renames the two apart.
    eval_string("(assertAlphaEqualToResult (quote (f $a)) ((f $b)))",
                [true]).

test(assertIncludes_subset_passes) :-
    eval_string("(assertIncludes (superpose (1 2 3)) (2 1))", [true]).

test(assertIncludes_missing_expectation_raises,
     [throws(error(petta_assertion_failed(_), _))]) :-
    eval_string("(assertIncludes (superpose (1 2)) (7))", _).

test(msg_variants_delegate) :-
    eval_string("(assertEqualMsg (+ 1 1) 2 ignored)", [true]),
    eval_string("(assertEqualToResultMsg (superpose (1 2)) (1 2) ignored)",
                [true]).

% -- error handling ---------------------------------------------------------

test(return_on_error_passes_a_clean_value) :-
    eval_string("(return-on-error 42 fallback)", [fallback]).

% -- evaluation control and quoting -----------------------------------------

test(for_each_in_atom_maps) :-
    eval_string("(for-each-in-atom (1 2 3) repr)", [["1", "2", "3"]]).

test(unquote_evaluates_the_quoted) :-
    eval_string("(unquote (quote (+ 2 3)))", [5]).

test(unquote_of_a_non_quote_stays_as_written) :-
    %Upstream's NotReducible reading, PeTTa-encoded: the quote-wrapping
    %catch-all keeps the call inert and printing as itself.
    eval_string("(repr (unquote 42))", ["(unquote 42)"]).

test(noreduce_eq_compares_unreduced) :-
    %Atom parameters: (+ 1 1) stays as written, so it is NOT == 2.
    eval_string("(noreduce-eq (+ 1 1) 2)", [false]),
    eval_string("(noreduce-eq (+ 1 1) (+ 1 1))", [true]).

% -- types ------------------------------------------------------------------

%The reader canonicalizes a source-level True/False to the engine's
%boolean, so these answer the lowercase form, exactly as the library's
%equations did through the same reader.
test(is_function_recognizes_arrows) :-
    eval_string("(is-function (-> Number Number))", [true]),
    eval_string("(is-function Number)", [false]).

%Upstream match-types: %Undefined% and Atom are wildcards on either
%side, and otherwise the two types UNIFY, so a type with a variable
%matches its instance where the library's == said no.
test(match_types_wildcards_and_unification) :-
    eval_string("(match-types A A t e)", [t]),
    eval_string("(match-types A B t e)", [e]),
    eval_string("(match-types %Undefined% B t e)", [t]),
    eval_string("(match-types B Atom t e)", [t]),
    eval_string("(match-types (List $x) (List Number) t e)", [t]).

%Upstream parameter order: accumulator, candidate, wanted.
test(match_type_or_folds) :-
    eval_string("(match-type-or False A A)", [true]),
    eval_string("(match-type-or False A B)", [false]),
    eval_string("(match-type-or True A B)", [true]).

test(type_cast_by_metatype) :-
    eval_string("(type-cast a Symbol &self)", [a]).

test(type_cast_undeclared_is_not_wrong) :-
    eval_string("(type-cast zz SomeType &self)", [zz]).

%Undeclared on purpose: the subject EVALUATES before the cast, so
%casting (+ 1 1) asks about 2, whose declared type is Number.
test(type_cast_evaluates_its_subject) :-
    eval_string("(type-cast (+ 1 1) Number &self)", [2]).

test(type_cast_declared_match_and_mismatch,
     [setup(metta_add_atom('&self', [':', tcx, 'TA'], _)),
      cleanup(metta_remove_atom('&self', [':', tcx, 'TA'], _))]) :-
    eval_string("(type-cast tcx TA &self)", [tcx]),
    eval_string("(type-cast tcx TB &self)", [['Error', tcx, 'BadType']]).

%The native get-type-space reaches a NAMED space's declarations, which
%the library's &self-literal stub never could.
test(get_type_space_selects_the_space,
     [setup(metta_add_atom('&prelude-tsp', [':', q, 'QT'], _)),
      cleanup(metta_remove_atom('&prelude-tsp', [':', q, 'QT'], _))]) :-
    eval_string("(get-type-space &prelude-tsp q)", Types),
    memberchk('QT', Types).

% -- the engine registers ---------------------------------------------------

test(get_type_answers_prelude_declarations) :-
    eval_string("(get-type assertEqualToResult)", Types),
    memberchk([->, 'Atom', 'Atom', '%Undefined%'], Types).

test(no_atom_leaks_into_self) :-
    %The prelude stores its atoms in no space: a fresh engine's &self
    %enumerates nothing of it, neither equations nor declarations.
    eval_string("(collapse (match &self (: $n $t) ($n $t)))", [Decls]),
    forall(member([N, _], Decls), \+ prelude_type_declaration(N, _)),
    \+ ( eval_string("(collapse (match &self (= (unquote $a) $b) found))",
                     [Found]),
         Found \== [] ).

test(a_user_equation_evicts_the_prelude_definition,
     [setup(metta_add_atom('&self',
                           [=, ['if-equal', A, A, T, E], [shadowed, T, E]],
                           _)),
      cleanup(( metta_remove_atom('&self',
                                  [=, ['if-equal', B, B, T2, E2],
                                   [shadowed, T2, E2]],
                                  _),
                %Reloading restores ONLY the evicted name: names still
                %owned skip whole, which is what makes the load safe to
                %repeat and this test order-independent.
                load_engine_prelude ))]) :-
    %The user's word replaces the engine's: defining a prelude-owned name
    %in &self evicts the prelude's clauses and declarations for it, so
    %the program's own definition answers ALONE, exactly as it did before
    %the name was promoted. Eviction is one-way in a running program; the
    %cleanup's explicit reload is the test restoring the engine for its
    %neighbours, not the engine resurrecting anything by itself.
    eval_string("(if-equal 1 1 yes no)", Results),
    Results == [[shadowed, yes, no]],
    \+ prelude_owned('if-equal'),
    \+ prelude_clause_ref('if-equal', _).

test(importing_the_tombstoned_library_is_a_noop) :-
    eval_string("(import! &self (library lib_he))", _),
    eval_string("(if-equal 1 1 yes no)", Results),
    memberchk(yes, Results).

:- end_tests(prelude).
