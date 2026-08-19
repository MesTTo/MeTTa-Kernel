% Purpose: PlUnit coverage for constructive negation: the dual transformation
%   in src/duals.pl and the (not-provable ...) form it answers.
%
%   The two defects negation as failure has, which these duals repair, are
%   named in The Art of Prolog, 2nd ed, section 11.3 pages 199-201, and the
%   relational default rule they enable is section 11.5 page 207. Those three
%   cases are tested here in the words the book uses, because they are the
%   reason the feature exists rather than examples chosen to pass.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

%The clpfd operators, in/2 and \/ among them, so duals_domain_coverage below
%can be READ. The engine imports clpfd too, but that happens when the
%initialization above runs, which is after this file has been read.
:- use_module(library(clpfd)).
:- use_module(library(time)).

%Run MeTTa source and answer the result groups. The engine prints its
%compilation unless started with the quiet flag, which a test run is not.
metta(Source, Results) :-
    with_output_to(string(_), user:process_metta_string(Source, Results)).

metta(Source) :- metta(Source, _).

%A directive contributes exactly one element to the result groups, so a test
%that runs one names the answer directly.
metta_answer(Source, Answer) :- metta(Source, [Answer]).

:- begin_tests(duals_art_of_prolog).

%"The query unmarried_student(X)? fails with respect to the preceding data,
%ignoring that X=bill is a solution logically implied by the rule and two
%facts. The failure occurs in the goal not married(X), since there is a
%solution X=joe." [The Art of Prolog, 2nd ed, page 199]
test(negation_before_its_generator_still_binds) :-
    metta("(= (aop-student bill) True)\n\c
           (= (aop-married joe) True)\n\c
           (= (aop-unmarried-student $x)\n\c
              (and (not-provable (aop-married $x)) (aop-student $x)))"),
    metta("!(collapse (let True (aop-unmarried-student $x) $x))", Results),
    Results == [[bill]].

%"A similar example is the query not (X=1), X=2?, which fails although there
%is a solution X=2." [page 199]
test(disequality_survives_until_the_later_binding) :-
    metta("(= (aop-defect2 $x)\n\c
              (and (not-provable (== $x 1)) (let $x 2 True)))"),
    metta("!(collapse (let True (aop-defect2 $x) $x))", Results),
    Results == [[2]].

%Section 11.5's entitlement relation. Their cut version "only works correctly
%to determine the pension to which a given person is entitled" [page 207]; the
%negated one answers in every direction, and needs the body variable of
%`not pension(X,Y)` universally quantified to do it.
aop_pension_program(
    "(= (aop-invalid mc-tavish) True)\n\c
     (= (aop-over-65 mc-tavish) True)\n\c
     (= (aop-over-65 mc-donald) True)\n\c
     (= (aop-over-65 mc-duff) True)\n\c
     (= (aop-paid-up mc-tavish) True)\n\c
     (= (aop-paid-up mc-donald) True)\n\c
     (= (aop-pension $p invalid-pension) (aop-invalid $p))\n\c
     (= (aop-pension $p old-age-pension) (and (aop-over-65 $p) (aop-paid-up $p)))\n\c
     (= (aop-pension $p supplementary-benefit) (aop-over-65 $p))\n\c
     (= (aop-entitlement $p $what) (aop-pension $p $what))\n\c
     (= (aop-entitlement $p nothing) (not-provable (aop-pension $p $any)))").

aop_entitlement(mc-tavish, ['invalid-pension', 'old-age-pension',
                            'supplementary-benefit']).
aop_entitlement(mc-duff, ['supplementary-benefit']).
aop_entitlement(nobody-at-all, [nothing]).

test(default_rule_answers_relationally,
     [forall(aop_entitlement(Person, Expected)), setup(aop_pension_setup)]) :-
    format(atom(Query), "!(collapse (let True (aop-entitlement ~w $w) $w))",
           [Person]),
    metta(Query, Results),
    Results == [Expected].

aop_pension_setup :-
    metta_self_module(Self),
    (   current_predicate(Self:'aop-pension'/3)
    ->  true
    ;   aop_pension_program(Program),
        metta(Program)
    ).

:- end_tests(duals_art_of_prolog).

:- begin_tests(duals_patterns).

test(a_fact_is_negated_by_disequality_not_by_a_failed_proof) :-
    metta("(= (pat-penguin polly) True)"),
    metta_answer("!(not-provable (pat-penguin tweety))", true),
    metta_answer("!(not-provable (pat-penguin polly))", false).

%A repeated head variable is a real condition, so its dual is a disequality
%between two of the call's own arguments.
test(a_non_linear_head_duals_to_a_disequality) :-
    metta("(= (pat-same $a $a) True)"),
    metta_answer("!(collapse (not-provable (pat-same 1 1)))", [false]),
    metta_answer("!(collapse (not-provable (pat-same 1 2)))", [true]).

%A head holding a structure that still has variables in it cannot be negated
%with a disequality, because the dual has to say "not ANY term of this shape".
test(a_structured_head_matches_by_shape) :-
    metta("(= (pat-starts-a (: a $rest)) True)"),
    metta_answer("!(not-provable (pat-starts-a (: a (: b ()))))", false),
    metta_answer("!(not-provable (pat-starts-a (: z (: b ()))))", true).

test(a_name_no_equation_defines_is_not_provable_at_all) :-
    metta_answer("!(not-provable (pat-undefined-name 1 2))", true).

:- end_tests(duals_patterns).

:- begin_tests(duals_quantification).

%A variable occurring only inside a negation is existential there, so it is
%universal under the negation. Without this, "no y is an edge from x" reads as
%"some y is not an edge from x", which is true of every node.
test(a_variable_local_to_the_negation_is_universally_quantified) :-
    metta("(= (q-edge a b) True)\n\c
           (= (q-edge b c) True)\n\c
           (= (q-has-outgoing $x) (q-edge $x $y))"),
    metta_answer("!(not-provable (q-has-outgoing a))", false),
    metta_answer("!(not-provable (q-has-outgoing c))", true).

%The same rule holds for a top-level query, which has no head: a variable
%nothing else reads is local to the negation there too.
test(a_top_level_query_quantifies_the_same_way) :-
    metta("(= (q-edge2 a b) True)"),
    metta_answer("!(collapse (let True (not-provable (q-edge2 a $y)) yes))", []).

%A variable the rest of the clause reads is NOT quantified, or the answer
%could not be constructive at all.
test(a_shared_variable_stays_free) :-
    metta("(= (q-edge3 a b) True)\n\c
           (= (q-edge3 b c) True)\n\c
           (= (q-no-outgoing $x) (not-provable (q-edge3 $x $y)))"),
    metta_answer("!(collapse (let True (q-no-outgoing $x) (let $x c $x)))", [c]),
    metta_answer("!(collapse (let True (q-no-outgoing $x) (let $x a $x)))", []).

:- end_tests(duals_quantification).

:- begin_tests(duals_recursion).

test(a_dual_may_call_itself) :-
    metta("(= (rec-nat z) True)\n\c
           (= (rec-nat (s $n)) (rec-nat $n))"),
    metta_answer("!(not-provable (rec-nat (s (s z))))", false),
    metta_answer("!(not-provable (rec-nat (s (s foo))))", true).

test(two_duals_may_call_each_other) :-
    metta("(= (rec-even z) True)\n\c
           (= (rec-even (s $n)) (rec-odd $n))\n\c
           (= (rec-odd (s $n)) (rec-even $n))"),
    metta_answer("!(not-provable (rec-even (s (s z))))", false),
    metta_answer("!(not-provable (rec-even (s z)))", true).

%A dual is read at the GREATEST fixpoint, not the least. (= (loops $x) (loops
%$x)) has no derivation, so under the well-founded semantics it is false and
%its negation is true; read inductively the dual clause not-loops :- not-loops
%just loops. A call that recurs to a variant of itself is therefore decided by
%the parity of the negations crossed on the way, which is s(CASP)'s rule.
%
%The time limit is the point of the test: without the coinductive check this
%does not fail, it hangs, and a hang in a suite is worse than a red test.
test(a_dual_that_recurs_to_itself_succeeds_coinductively) :-
    metta("(= (co-loops $x) (co-loops $x))"),
    call_with_time_limit(10, user:metta_dual_goal('co-loops', [q])).

%The positive branch of (not-provable G) is an ordinary evaluation of G, so it
%inherits G's own termination. Only the dual is loop-safe, and that is why the
%dual is reachable under its own name.
test(the_dual_is_reachable_under_its_own_name) :-
    metta("(= (co-fact tweety) True)"),
    metta_answer("!(not-provable (co-fact polly))", true),
    %The dual is compiled into the module of the space that defined the
    %function it negates, which is &self's own module.
    metta_self_module(Self),
    call_with_time_limit(10, Self:'not-co-fact'(polly, true)).

:- end_tests(duals_recursion).

:- begin_tests(duals_match).

%A match over a space is a generator, and a better behaved one than a let: a
%space is finite, so what it narrows a variable to is always an enumeration.
match_program(
    "!(bind! &kin (new-space))\n\c
     !(add-atom &kin (parent alice bob))\n\c
     !(add-atom &kin (parent carol dave))\n\c
     (= (mt-has-child $x) (match &kin (parent $x $y) True))").

match_setup :-
    metta_self_module(Self),
    (   current_predicate(Self:'mt-has-child'/2)
    ->  true
    ;   match_program(Program),
        metta(Program)
    ).

test(a_match_duals_over_the_space, [setup(match_setup)]) :-
    metta_answer("!(not-provable (mt-has-child alice))", false),
    metta_answer("!(not-provable (mt-has-child bob))", true),
    metta_answer("!(not-provable (mt-has-child stranger))", true).

%$y is local to the match and $x is not, and that is the whole difference: $y
%is quantified away, $x is answered. Getting it wrong would constrain the PAIR
%and let alice back in with a different child.
test(the_match_answers_which_terms_it_narrows_to_nothing,
     [setup(match_setup)]) :-
    metta_answer("!(collapse (let True (not-provable (mt-has-child $w)) \c
                               (let $w bob $w)))", [bob]),
    metta_answer("!(collapse (let True (not-provable (mt-has-child $w)) \c
                               (let $w alice $w)))", []),
    metta_answer("!(collapse (let True (not-provable (mt-has-child $w)) \c
                               (let $w stranger $w)))", [stranger]).

test(an_empty_space_proves_nothing) :-
    metta("!(bind! &nothing (new-space))\n\c
           (= (mt-anything $x) (match &nothing (thing $x) True))"),
    metta_answer("!(not-provable (mt-anything whatever))", true).

:- end_tests(duals_match).

:- begin_tests(duals_answer_sets).

%A superpose answers each element in turn, so it is not True exactly when none
%of them is.
test(a_superpose_duals_to_the_conjunction_of_its_elements) :-
    metta("(= (as-yes) True)\n\c
           (= (as-no) False)\n\c
           (= (as-any) (superpose ((as-no) (as-yes) (as-no))))\n\c
           (= (as-none) (superpose ((as-no) (as-no))))\n\c
           (= (as-empty) (superpose ()))"),
    metta_answer("!(not-provable (as-any))", false),
    metta_answer("!(not-provable (as-none))", true),
    metta_answer("!(not-provable (as-empty))", true).

%A collapse yields a LIST, always, so it is never the atom True. Confirmed
%rather than assumed: it compiles to findall/3 and its metatype is Expression.
test(a_collapse_is_never_true) :-
    metta("(= (as-one) True)\n(= (as-gather) (collapse (as-one)))"),
    metta_answer("!(== (collapse (as-one)) True)", false),
    metta_answer("!(get-metatype (collapse (as-one)))", 'Expression'),
    metta_answer("!(not-provable (as-gather))", true).

%Where a collapse's value is what matters it is an argument to something else,
%and that path never reaches the collapse dual at all.
test(a_collapse_as_an_argument_still_evaluates) :-
    metta("(= (as-known 1) True)\n\c
           (= (as-absent $x) (== (collapse (as-known $x)) ()))"),
    metta_answer("!(not-provable (as-absent 1))", true),
    metta_answer("!(not-provable (as-absent 2))", false).

:- end_tests(duals_answer_sets).

:- begin_tests(duals_case).

%A case commits to the first pattern its key matches, so its dual is the same
%chain with each body dualised. The chain ends in TRUE rather than fail: a key
%matching no pattern leaves the case with no answer, and no answer is not True.
test(a_case_duals_branch_by_branch) :-
    metta("(= (cs-passing $n) (case $n ((90 True) (40 False))))"),
    metta_answer("!(not-provable (cs-passing 90))", false),
    metta_answer("!(not-provable (cs-passing 40))", true),
    metta_answer("!(not-provable (cs-passing 55))", true).

%An Empty branch answers when the KEY has no answer, and foreach/2 over an
%empty generator succeeds vacuously, so the two have to be told apart before
%quantifying.
test(an_empty_branch_answers_for_a_key_with_no_answer) :-
    metta("(= (cs-lookup alice) 90)\n\c
           (= (cs-checked $w)\n\c
              (case (cs-lookup $w) ((90 True) (40 False) (Empty True))))\n\c
           (= (cs-checked2 $w)\n\c
              (case (cs-lookup $w) ((90 True) (Empty False))))"),
    metta_answer("!(cs-checked nobody)", true),
    metta_answer("!(not-provable (cs-checked nobody))", false),
    metta_answer("!(cs-checked2 nobody)", false),
    metta_answer("!(not-provable (cs-checked2 nobody))", true),
    metta_answer("!(not-provable (cs-checked alice))", false).

:- end_tests(duals_case).

:- begin_tests(duals_connectives).

%and-then and or-else are the short-circuiting connectives and dual exactly as
%and and or do: and-then answers False without running its second argument
%when the first is not True, and False is not True, which is the disjunct the
%dual of and already has.
short_circuit("(and-then (sc-no) (sc-yes))", true).
short_circuit("(and-then (sc-yes) (sc-yes))", false).
short_circuit("(and-then (sc-yes) (sc-no))", true).
short_circuit("(or-else (sc-no) (sc-yes))", false).
short_circuit("(or-else (sc-no) (sc-no))", true).
short_circuit("(or-else (sc-yes) (sc-no))", false).

test(short_circuiting_connectives_dual_like_their_relational_twins,
     [forall(short_circuit(Body, Expected)), setup(short_circuit_setup)]) :-
    format(atom(Source), "!(not-provable ~w)", [Body]),
    metta_answer(Source, Answer),
    Answer == Expected.

short_circuit_setup :-
    metta_self_module(Self),
    (   current_predicate(Self:'sc-yes'/1)
    ->  true
    ;   metta("(= (sc-yes) True)\n(= (sc-no) False)")
    ).

%quote hands its argument back unevaluated, so its value IS that term.
test(quote_asks_only_whether_the_term_is_true) :-
    metta_answer("!(not-provable (quote True))", false),
    metta_answer("!(not-provable (quote other))", true).

:- end_tests(duals_connectives).

:- begin_tests(duals_constraints).

%A constructive answer over an infinite domain is a constraint, not an
%enumeration, and residual-goals is how to read one.
test(the_answer_is_a_constraint_that_can_be_read) :-
    metta("(= (con-penguin polly) True)"),
    metta_answer("!(collapse (let True (not-provable (con-penguin $p)) \c
                                (residual-goals $p)))", [Goals]),
    Goals = [[dif, Var, polly]],
    var(Var).

test(a_ground_term_carries_no_constraints) :-
    metta_answer("!(residual-goals 42)", []).

test(dif_is_a_first_class_constraint) :-
    metta_answer("!(dif 1 2)", true),
    metta_answer("!(collapse (let True (dif $q 5) (let $q 6 $q)))", [6]),
    metta_answer("!(collapse (let True (dif $q 5) (let $q 5 $q)))", []).

:- end_tests(duals_constraints).

:- begin_tests(duals_invalidation).

%A dual is a compiled summary of a function's equations, so an equation added
%after it was built has to rebuild it.
test(an_equation_added_later_rebuilds_the_dual) :-
    metta("(= (inv-mammal cat) True)"),
    metta_answer("!(not-provable (inv-mammal dog))", true),
    metta("(= (inv-mammal dog) True)"),
    metta_answer("!(not-provable (inv-mammal dog))", false).

%The handler that does that is installed on the first dual, not on load,
%because it runs once per compiled equation.
test(the_invalidation_handler_is_installed_lazily) :-
    user:dual_hooks_installed,
    clause(user:metta_on_function_changed(_), user:drop_duals_of(_)).

:- end_tests(duals_invalidation).

:- begin_tests(duals_refusals).

%Every form without a sound dual raises. An incomplete dual would answer "not
%provable" for something provable, which is a wrong answer rather than a
%missing one.
test(a_builtin_has_no_equations_to_negate,
     [throws(error(type_error(dualisable_function, (+)/3), _))]) :-
    metta("!(not-provable (+ 1 2))").

%A special form is compiled rather than defined by equations, and most are not
%registered as functions either, so "no equations" must not be read as
%"nothing can prove it": that made (not-provable (case 1 ((1 True)))) answer
%True beside its correct False, before case had a dual of its own.
test(a_special_form_has_no_equations_to_negate,
     [throws(error(type_error(dualisable_function, foldall/4), _))]) :-
    metta("!(not-provable (foldall + (superpose (1 2)) 0))").

test(an_unnamed_call_cannot_be_negated,
     [throws(error(type_error(dualisable_body, _), _))]) :-
    metta("!(not-provable $g)").

%An in-place type annotation in a head argument compiles to a goal that the
%retained equation no longer holds, so a dual built from that equation would
%ignore the constraint and claim more than it can prove. It is the only head
%argument that still compiles to a goal: a head argument that is a call is a
%PATTERN and matches structurally, so it duals like any other structure
%[tested: a_head_holding_a_call_duals_structurally].
test(an_annotated_head_has_no_dual,
     [throws(error(type_error(dualisable_function, 'fp-positive'), _))]) :-
    metta("(= (fp-positive (: $n Number)) True)"),
    metta("!(not-provable (fp-positive 10))").

%The control. A head holding a call used to be refused for the same reason,
%because the call became a goal; matched structurally it is ordinary
%structure, so it duals like any other structure and no longer raises.
test(a_head_holding_a_call_is_no_longer_refused) :-
    metta("(= (fp-dbl $n) (#* 2 $n))\n\c
           (= (fp-halfof (fp-dbl $n)) True)"),
    metta_answer("!(not-provable (fp-halfof 10))", true).

:- end_tests(duals_refusals).

:- begin_tests(duals_supported_bodies).

%The comparisons have exact duals, so they need no equations of their own.
comparison_case("(> 2 1)", false).
comparison_case("(> 1 2)", true).
comparison_case("(<= 1 2)", false).
comparison_case("(<= 2 1)", true).
comparison_case("(== 1 1)", false).
comparison_case("(!= 1 2)", false).

test(a_comparison_duals_to_its_opposite,
     [forall(comparison_case(Expression, Expected))]) :-
    format(atom(Query), "!(not-provable ~w)", [Expression]),
    metta_answer(Query, Answer),
    Answer == Expected.

test(the_boolean_connectives_dual_by_de_morgan) :-
    metta("(= (sb-p) True)\n\c
           (= (sb-q) False)"),
    metta_answer("!(not-provable (and (sb-p) (sb-q)))", true),
    metta_answer("!(not-provable (or (sb-p) (sb-q)))", false),
    metta_answer("!(not-provable (not (sb-q)))", false).

%The CLP(FD) family's dual is a constraint rather than a decision, so a
%negated bound narrows the variable's domain and a later binding meets it.
test(a_negated_arithmetic_bound_narrows_the_domain) :-
    metta_answer("!(collapse (let True (not-provable (#< $x 5)) (let $x 7 $x)))",
                 [7]),
    metta_answer("!(collapse (let True (not-provable (#< $x 5)) (let $x 3 $x)))",
                 []),
    metta_answer("!(collapse (let True (not-provable (#= $y 4)) (let $y 9 $y)))",
                 [9]),
    metta_answer("!(collapse (let True (not-provable (#= $y 4)) (let $y 4 $y)))",
                 []).

test(if_duals_through_both_of_its_branches) :-
    metta("(= (sb-pick $x) (if (> $x 0) True False))"),
    metta_answer("!(not-provable (sb-pick 1))", false),
    metta_answer("!(not-provable (sb-pick -1))", true).

:- end_tests(duals_supported_bodies).

:- begin_tests(duals_let).

%A let is True when SOME answer of its value makes the body True, so its dual
%has to hold for EVERY one of them. That is a quantification over a generator,
%and getting it wrong is the difference between checking one answer and
%checking all of them.
test(a_let_duals_through_its_value) :-
    metta("(= (lt-grade alice) 90)\n\c
           (= (lt-grade bob) 40)\n\c
           (= (lt-passes $who) (let $s (lt-grade $who) (> $s 50)))"),
    metta_answer("!(not-provable (lt-passes alice))", false),
    metta_answer("!(not-provable (lt-passes bob))", true).

%The case naive negation gets wrong: one answer of the generator passes, so
%the let IS provable even though another answer fails.
test(every_answer_of_the_generator_must_fail) :-
    metta("(= (lt-marks carol) 90)\n\c
           (= (lt-marks carol) 30)\n\c
           (= (lt-marks dave) 10)\n\c
           (= (lt-marks dave) 20)\n\c
           (= (lt-any-pass $w) (let $m (lt-marks $w) (> $m 50)))"),
    metta_answer("!(collapse (lt-any-pass carol))", [true, false]),
    metta_answer("!(not-provable (lt-any-pass carol))", false),
    metta_answer("!(not-provable (lt-any-pass dave))", true).

%A generator with no answers makes the let itself answerless, so it is not
%True. foreach/2 over an empty generator is vacuously true, which is exactly
%that.
test(a_value_with_no_answer_makes_the_let_not_provable) :-
    metta("(= (lt-known alice) 1)\n\c
           (= (lt-reachable $w) (let $s (lt-known $w) (> $s 0)))"),
    metta_answer("!(not-provable (lt-reachable nobody))", true),
    metta_answer("!(not-provable (lt-reachable alice))", false).

test(let_star_nests_and_duals) :-
    metta("(= (lt-g alice) 90)\n\c
           (= (lt-g bob) 40)\n\c
           (= (lt-both $w) (let* (($a (lt-g $w)) ($b (#+ $a 1))) (> $b 50)))"),
    metta_answer("!(not-provable (lt-both alice))", false),
    metta_answer("!(not-provable (lt-both bob))", true).

%A dual is built ONCE, at compile time, out of the recorded MeTTa body, so
%bindings that only arrive at run time are not there to expand. That used to
%be silent: the expansion unified the bindings argument with its own
%empty-list base clause and produced a dual with the bindings DROPPED, so
%this answered NOTHING where the same bindings written out answer True.
%Declining names the form instead, which is the limit case has too.
test(a_let_star_whose_bindings_have_not_arrived_has_no_dual,
     [ throws(error(type_error(dualisable_body, ['let*'|_]),
                    context(body_form_dual/5, _))) ]) :-
    metta("(= (lt-none) (empty))\n\c
           (= (lt-written) (let* (($a (lt-none))) (> 1 0)))\n\c
           (= (lt-handed $bs) (let* $bs (> 1 0)))"),
    metta_answer("!(not-provable (lt-written))", true),
    metta("!(not-provable (lt-handed (quote (($a (lt-none))))))").

%What the generator narrows a variable of the enclosing clause TO belongs in
%the answer rather than being quantified away, which is what collapse-bind
%says an answer is. So the dual answers once per distinct narrowing, and once
%more for the terms the generator narrows to nothing, where the let has no
%answer at all and so is not True.
test(a_narrowing_generator_answers_once_per_narrowing) :-
    metta("(= (lt-mark alice) 90)\n\c
           (= (lt-mark bob) 40)\n\c
           (= (lt-ok $who) (let $s (lt-mark $who) (> $s 50)))"),
    metta_answer("!(collapse (let True (not-provable (lt-ok $w)) \c
                               (let $w bob $w)))", [bob]),
    metta_answer("!(collapse (let True (not-provable (lt-ok $w)) \c
                               (let $w alice $w)))", []),
    metta_answer("!(collapse (let True (not-provable (lt-ok $w)) \c
                               (let $w carol $w)))", [carol]).

%A narrowing the dual cannot read is one the generator expressed as a
%CONSTRAINT rather than as an enumeration, because findall/3 copies out of the
%constraint store. That is the one case left that raises rather than answering
%incompletely.
test(a_generator_that_constrains_rather_than_enumerates_raises,
     [throws(error(instantiation_error,
                   context(metta_generator_forall/5, _)))]) :-
    metta("(= (lt-near $x) (let $s (#+ $x 1) (#< $s 5)))"),
    metta_answer("!(not-provable (lt-near 1))", false),
    metta("!(collapse (let True (not-provable (lt-near $w)) (let $w 9 $w)))").

%Building a dual is a side effect that happens once. It was redone on
%backtracking and asserted a second identical clause, so every call to the
%dual answered twice.
test(a_dual_is_built_exactly_once) :-
    metta("(= (lt-once bob) 40)\n\c
           (= (lt-twice $w) (let* (($a (lt-once $w)) ($b (#+ $a 1))) (> $b 50)))"),
    metta_answer("!(not-provable (lt-twice bob))", true),
    metta_self_module(Self),
    aggregate_all(count, clause(Self:'not-lt-twice'(_, _), _), Clauses),
    Clauses == 1.

:- end_tests(duals_let).

:- begin_tests(duals_partition).

%(not-provable G) answers False once per proof of G and True once per solution
%of G's dual. For a ground G exactly one holds; for a non-ground G the two
%partition it, so the pair is the whole answer and neither alone is.
test(a_ground_goal_answers_exactly_one_way) :-
    metta("(= (part-penguin polly) True)"),
    metta_answer("!(collapse (not-provable (part-penguin polly)))", [false]),
    metta_answer("!(collapse (not-provable (part-penguin tweety)))", [true]).

%The two branches partition the domain: the False one is exactly the terms
%that prove it, the True one is exactly the rest, and neither alone is the
%answer. $x has to be read outside the negation to see this, or it would be
%local to it and universally quantified instead.
test(a_non_ground_goal_partitions_its_argument) :-
    metta("(= (part-bird tweety) True)"),
    metta_answer("!(collapse (let False (not-provable (part-bird $x)) $x))",
                 Proves),
    Proves == [tweety],
    metta_answer("!(collapse (let True (not-provable (part-bird $x)) \c
                               (let $x tweety $x)))", Excluded),
    Excluded == [],
    metta_answer("!(collapse (let True (not-provable (part-bird $x)) \c
                               (let $x sparrow $x)))", Allowed),
    Allowed == [sparrow].

:- end_tests(duals_partition).

:- begin_tests(duals_domain_coverage).

%A covering solution that leaves a finite-domain residual restricts the
%variable to a DOMAIN, and the values it excluded are that domain's
%complement. clpfd computes the complement rather than this walking intervals
%by hand.
test(clpfd_computes_the_complement_of_a_residual_domain) :-
    X in 4..sup,
    domain_complement(X, Complement, Size),
    Complement == inf..3,
    Size == sup.

test(a_finite_complement_is_finite_and_enumerable) :-
    Y in inf..6 \/ 8..sup,
    domain_complement(Y, Complement, Size),
    Complement == 7..7,
    Size == 1,
    findall(V, complement_value(Complement, V), Values),
    Values == [7].

test(an_infinite_complement_still_yields_a_witness) :-
    Z in 4..sup,
    domain_complement(Z, Complement, _),
    complement_witness(Complement, Witness),
    Witness == 3.

%The shape this exists for: `(not-provable (#< $x 4))` used to raise
%`Domain error: enumerable_constraint` and is now decided False, because its
%dual `(#>= $x 4)` fails at the witness 3.
domain_decided("!(collapse (not-provable (#< $x 4)))",  [[false]]).
domain_decided("!(collapse (not-provable (#> $x 4)))",  [[false]]).

test(a_negated_bound_is_decided_rather_than_refused,
     [ forall(domain_decided(Source, Expected)),
       setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string(Source, Results),
    Results == Expected.

%One direction only, and deliberately. If the goal HOLDS at the witness
%nothing follows, because the rest of an infinite set is unchecked, so that
%case still refuses rather than guessing.
test(a_case_the_witness_cannot_settle_still_refuses,
     [ setup(( retractall(silent(_)), assertz(silent(true)),
               process_metta_string(
                   "(= (dc-impossible $n) (and (#< $n 4) (#> $n 10)))", _) )),
       cleanup(( 'remove-atom'('&self', [=, ['dc-impossible'|_], _], _),
                 retractall(silent(_)), assertz(silent(false)) )),
       throws(error(domain_error(enumerable_constraint, _), _)) ]) :-
    process_metta_string("!(collapse (not-provable (dc-impossible $y)))", _).

:- end_tests(duals_domain_coverage).

:- begin_tests(duals_refuse_before_running).

%The refusal used to fire AFTER the positive goal had run, because
%metta_negation/5 tries `call(True)` first and only reaches the dual when that
%fails. So `(not-provable (op 2))` invoked the operation and then reported that
%it has no dual, and an operation that RAISED reported its own exception
%instead, giving two different errors for one call shape
%[source: ai-metta-python-seams.md item 2].
%
%Whether a function is dualisable depends on its definition, not on its
%arguments, so asking first costs nothing and is the whole fix.

%A head that constrains an argument in place has no dual, which is the static
%property refuse_unsupported_head/2 tests.
test(a_function_with_no_dual_is_refused_before_its_argument_runs) :-
    process_metta_string("(= (np-effect (: $x Number)) True)", _),
    catch(( process_metta_string("!(not-provable (np-effect 2))", _),
            Outcome = accepted ),
          error(type_error(dualisable_function, _), _),
          Outcome = refused),
    assertion(Outcome == refused).

%The precondition is read off the DUAL BODY, so a call nested inside a
%connective is established too rather than only a bare one.
test(a_nested_call_is_established_as_well) :-
    process_metta_string("(= (np-ok) True)", _),
    process_metta_string("(= (np-bad (: $x Number)) True)", _),
    catch(( process_metta_string("!(not-provable (and (np-ok) (np-bad 2)))", _),
            Outcome = accepted ),
          error(type_error(dualisable_function, _), _),
          Outcome = refused),
    assertion(Outcome == refused).

%A dualisable negation still answers, so the guard has not made the ordinary
%case refuse.
test(an_ordinary_negation_still_answers) :-
    process_metta_string("(= (np-fine 1) True)", _),
    process_metta_string("!(not-provable (np-fine 2))", Answer),
    assertion(Answer == [true]).

:- end_tests(duals_refuse_before_running).
