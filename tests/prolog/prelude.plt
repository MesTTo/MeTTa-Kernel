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
    %noeval hands over (f $a), so the produced set is ((f $a)) and the
    %expected set is written as data; =alpha renames the two apart.
    eval_string("(assertAlphaEqualToResult (noeval (f $a)) ((f $b)))",
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

:- begin_tests(prelude_docs).

doc_eval(Text, Results) :-
    sread(Text, Term),
    findall(R, eval(Term, R), Results).

test(get_doc_answers_the_engine_register_with_no_import) :-
    doc_eval("(get-doc type-cast)", [Doc]),
    Doc = ['@doc', 'type-cast' | _].

test(get_doc_answers_a_program_atom_as_written,
     [setup(metta_add_atom('&self',
                           ['@doc', 'plunit-doc-greet',
                            ['@desc', "Greets"]], _)),
      cleanup(metta_remove_atom('&self',
                                ['@doc', 'plunit-doc-greet', _], _))]) :-
    doc_eval("(get-doc plunit-doc-greet)",
             [['@doc', 'plunit-doc-greet', ['@desc', "Greets"]]]).

test(get_doc_of_an_undocumented_name_answers_nothing) :-
    doc_eval("(collapse (get-doc plunit-doc-nobody))", [[]]).

test(get_doc_space_selects_the_space,
     [setup(metta_add_atom('&plunit-doc-space',
                           ['@doc', 'plunit-doc-remote',
                            ['@desc', "Remote"]], _)),
      cleanup(metta_remove_atom('&plunit-doc-space',
                                ['@doc', 'plunit-doc-remote', _], _))]) :-
    doc_eval("(get-doc-space &plunit-doc-space plunit-doc-remote)",
             [['@doc', 'plunit-doc-remote', ['@desc', "Remote"]]]),
    %And the current context does NOT see it: the twin is the selection.
    doc_eval("(collapse (get-doc plunit-doc-remote))", [[]]).

test(help_prints_and_answers_unit,
     [setup(metta_add_atom('&self',
                           ['@doc', 'plunit-doc-help',
                            ['@desc', "For help"]], _)),
      cleanup(metta_remove_atom('&self',
                                ['@doc', 'plunit-doc-help', _], _))]) :-
    with_output_to(string(Out), doc_eval("(help! plunit-doc-help)", [[]])),
    once(sub_string(Out, _, _, _, "For help")),
    with_output_to(string(Missing), doc_eval("(help! plunit-doc-nobody)", [[]])),
    once(sub_string(Missing, _, _, _, "No documentation")).

test(enumerators_are_program_scoped,
     [setup(( metta_add_atom('&self',
                             [=, ['plunit-doc-fn', X], X], _),
              metta_add_atom('&self',
                             ['@doc', 'plunit-doc-fn',
                              ['@desc', "Mine"]], _),
              metta_add_atom('&self',
                             [=, ['plunit-doc-bare', Y], Y], _) )),
      cleanup(( metta_remove_atom('&self',
                                  [=, ['plunit-doc-fn', X2], X2], _),
                metta_remove_atom('&self',
                                  ['@doc', 'plunit-doc-fn', _], _),
                metta_remove_atom('&self',
                                  [=, ['plunit-doc-bare', Y2], Y2], _) ))]) :-
    %documented answers the program's names, never the engine's.
    doc_eval("(collapse (documented))", [Documented]),
    memberchk('plunit-doc-fn', Documented),
    \+ memberchk('type-cast', Documented),
    %undocumented reports the program's gap, engine vocabulary excluded.
    doc_eval("(collapse (undocumented))", [Undocumented]),
    memberchk('plunit-doc-bare', Undocumented),
    \+ memberchk('plunit-doc-fn', Undocumented),
    \+ memberchk('if-equal', Undocumented),
    %defined-name sees both program functions and no builtins.
    doc_eval("(collapse (defined-name))", [Defined]),
    memberchk('plunit-doc-fn', Defined),
    memberchk('plunit-doc-bare', Defined),
    \+ memberchk('assertEqual', Defined).

test(eviction_takes_the_prelude_docs_with_the_name,
     [setup(metta_add_atom('&self',
                           [=, ['type-cast', A, B, C], [shadow, A, B, C]],
                           _)),
      cleanup(( metta_remove_atom('&self',
                                  [=, ['type-cast', A2, B2, C2],
                                   [shadow, A2, B2, C2]], _),
                load_engine_prelude ))]) :-
    \+ prelude_doc_atom('type-cast', _),
    doc_eval("(collapse (get-doc type-cast))", [[]]).

test(the_doc_example_still_speaks_for_the_library,
     [condition(exists_file('../../examples/libraries/doc_lib.metta'))]) :-
    load_metta_file('../../examples/libraries/doc_lib.metta', _).

:- end_tests(prelude_docs).

% The derived forms: each ships as an equation in src/prelude.metta plus the
% one runnable the loader accepts, `!(add-translator-rule! NAME)`. That is the
% whole of what moving a form out of the compiler needs, and the registration
% is the prelude's to withdraw, because a program that defines the name has
% taken the form over and its equations are not a compile-time expander.
:- begin_tests(prelude_derived_forms).

prelude_derived('and-then').
prelude_derived('or-else').
prelude_derived('trace!').
prelude_derived(unique).
prelude_derived('alpha-unique').
prelude_derived(union).
prelude_derived(intersection).
prelude_derived(subtraction).

test(every_derived_form_is_registered_as_a_translator_rule,
     [forall(prelude_derived(Name))]) :-
    assertion(translator_rule(Name)),
    assertion(prelude_translator_rule(Name)).

%eval_string/2 belongs to the unit above, and a plunit unit is a module of
%its own, so this one reads the forms the same way for itself.
derived_answers(Text, Results) :-
    sread(Text, Term),
    findall(R, eval(Term, R), Results).

test(a_derived_form_answers_with_no_import) :-
    derived_answers("(and-then True yes)", [yes]),
    derived_answers("(or-else False fallback)", [fallback]),
    derived_answers("(collapse (unique (superpose (1 2 1))))", [[1, 2]]).

%The loader takes exactly one runnable shape, and only for a name the prelude
%itself defines, so a registration can never point at somebody else's
%equations.
test(a_registration_for_a_name_the_prelude_does_not_define_is_refused,
     [throws(error(existence_error(prelude_definition, 'no-such-prelude-name'),
                   _))]) :-
    load_prelude_form(runnable, "(add-translator-rule! no-such-prelude-name)",
                      ['add-translator-rule!', 'no-such-prelude-name']).

%A program that defines the name takes the whole form over: the prelude's
%equations go, and so does the registration, or the translator would call the
%program's own equations as a compile-time expander.
test(a_user_definition_withdraws_the_registration_with_the_clauses,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( 'remove-atom'('&self', [=, ['or-else'|_], _], _),
                 retractall(silent(_)), assertz(silent(false)),
                 load_engine_prelude )) ]) :-
    assertion(translator_rule('or-else')),
    process_metta_string("(= (or-else $a $b) taken-over)", _),
    assertion(\+ translator_rule('or-else')),
    assertion(\+ prelude_translator_rule('or-else')),
    process_metta_string("!(or-else True whatever)", Answers),
    assertion(Answers == ['taken-over']).

:- end_tests(prelude_derived_forms).
