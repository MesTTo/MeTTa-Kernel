% Purpose: direct PlUnit coverage for translator control forms and branch
%   rewrites whose failures are difficult to localize through whole examples,
%   and for the translator's COST guarantees, which no correctness test can
%   see at all: dispatch goal ordering, equation-store growth and translation
%   growth each leave every answer exactly as it was.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

%Take a test function back out completely: its registration, its symbol
%records, its arities, and its compiled predicate at every arity it might have
%been compiled at. forget_symbol/2 alone leaves the PREDICATE, which is enough
%to make a second setup in the same process compile a second clause and answer
%twice.
forget_test_function(F) :-
    user:metta_self_module(SelfModule),
    catch(user:forget_symbol(SelfModule, F), _, true),
    retractall(user:symbol_head(F, _)),
    retractall(user:fun_in(_, F)),
    retractall(user:fun_scoped(F)),
    retractall(user:fun(F)),
    retractall(user:arity(F, _)),
    %current_predicate/1 first, because retractall/1 CREATES an undefined
    %predicate as dynamic rather than failing, and the next
    %ensure_fun_registered/1 then records an arity for every one of them: this
    %helper without the guard left arity(F, A) for 1 and 4 through 8.
    %abolish/1 after, so the predicate record goes too rather than staying
    %defined and empty.
    forall(( between(1, 8, A),
             current_predicate(F/A),
             functor(Head, F, A) ),
           ( catch(retractall(user:Head), _, true),
             catch(abolish(user:F/A), _, true) )).

%The repository's counter recipe, read around the operation under test and
%nothing else [source: tests/prolog/README.md, "Measure engine changes"]. File
%level because four units below need it and a plunit unit is its own module.
%call/1 costs one inference of its own; it is the same one in both arms of
%every comparison here and cancels out of all of them.
count_inferences(Goal, Inferences) :-
    garbage_collect,
    statistics(inferences, I0),
    call(Goal),
    statistics(inferences, I1),
    Inferences is I1 - I0.

%The minimum of three, the second half of that recipe. Belt and braces for an
%exact counter, and what it guards against is a stray atom collection landing
%inside one window. The goal is run three times, so it has to be repeatable:
%every caller here measures a computation that leaves nothing behind.
min_inferences(Goal, Inferences) :-
    findall(Sample,
            ( between(1, 3, _),
              count_inferences(Goal, Sample) ),
            Samples),
    min_list(Samples, Inferences).

%The per-call cost of a Runner that takes a call count, as the SLOPE over
%1,000 calls, so whatever a unit's one-off setup costs falls out of both
%sides of every comparison. File level because two units need it, and the
%runner arrives already qualified with its unit's module: a plunit unit is a
%module of its own and this predicate is not in it.
call_cost(Runner, Cost) :-
    min_inferences(call(Runner, 100), Base),
    min_inferences(call(Runner, 1100), Full),
    Cost is (Full - Base) // 1000.

%A conditional nested N deep. File level rather than inside one unit, because
%two of them need it and a plunit unit is its own module: translation depth
%compiles it, and branch returns merges what that compilation produced.
nested_conditional(0, 0) :- !.
nested_conditional(N, [if, [==, 1, 1], Inner, 0]) :-
    N1 is N - 1,
    nested_conditional(N1, Inner).

:- begin_tests(translator_hyperpose).

hyperpose_space('&plunit_hyperpose').

hyperpose_form("(= (plunit-dbl $x) (* $x 2))").
hyperpose_form("(= (plunit-viamap) (map-atom (1 2 3) plunit-dbl))").
hyperpose_form("(= (plunit-viahyper) (hyperpose ((plunit-viamap) (plunit-viamap))))").

add_hyperpose_form(Space, Text) :-
    sread(Text, Term),
    'add-atom'(Space, Term, _).

remove_hyperpose_form(Space, Text) :-
    sread(Text, Term),
    'remove-atom'(Space, Term, _).

setup_hyperpose :-
    retractall(silent(_)),
    assertz(silent(true)),
    hyperpose_space(Space),
    forall(hyperpose_form(Text), add_hyperpose_form(Space, Text)).

cleanup_hyperpose :-
    hyperpose_space(Space),
    forall(hyperpose_form(Text), remove_hyperpose_form(Space, Text)),
    retractall(silent(_)),
    assertz(silent(false)).

test(named_space_static_branches_use_calling_module,
     [setup(setup_hyperpose), cleanup(cleanup_hyperpose)]) :-
    hyperpose_space(Space),
    space_module(Space, Module),
    findall(Result,
            call_goals_in(Module, ['plunit-viahyper'(Result)]),
            Results),
    Results == [[2, 4, 6], [2, 4, 6]].

test(named_space_runtime_branches_use_calling_module,
     [setup(setup_hyperpose), cleanup(cleanup_hyperpose)]) :-
    hyperpose_space(Space),
    space_module(Space, Module),
    findall(Result,
            with_metta_module(
                Module,
                hyperpose_runtime([['plunit-viamap'], ['plunit-viamap']], Result)),
            Results),
    Results == [[2, 4, 6], [2, 4, 6]].

:- end_tests(translator_hyperpose).

:- begin_tests(translator_meta_store).

meta_store_function('$plunit_meta_store').

setup_meta_store :-
    meta_store_function(F),
    current_metta_module(Module),
    clear_fun_meta(Module, F),
    retractall(arity(F, _)).

cleanup_meta_store :-
    setup_meta_store.

test(function_store_keeps_newest_first,
     [setup(setup_meta_store), cleanup(cleanup_meta_store)]) :-
    meta_store_function(F),
    translate_clause([=, [F, X], [first, X]], _),
    translate_clause([=, [F, Y], [second, Y]], _),
    current_metta_module(Module),
    fun_meta_clauses(Module, F, [fun_meta(SecondArgs, SecondBody),
                                 fun_meta(FirstArgs, FirstBody)]),
    (SecondArgs-SecondBody) =@= ([Y]-[second, Y]),
    (FirstArgs-FirstBody) =@= ([X]-[first, X]).

test(drop_fun_meta_removes_one_variant_only,
     [setup(setup_meta_store), cleanup(cleanup_meta_store)]) :-
    meta_store_function(F),
    translate_clause([=, [F, X], [same, X]], _),
    translate_clause([=, [F, Y], [same, Y]], _),
    current_metta_module(Module),
    drop_fun_meta(Module, F, [Z], [same, Z]),
    aggregate_all(count, fun_meta_clause(Module, F, _, _), 1).

test(engine_state_does_not_use_function_names,
     [ setup((setup_meta_store,
              nb_setval(specneeded, user_spec_state),
              nb_setval(lambda_counter, user_lambda_state))),
       cleanup((cleanup_meta_store,
                nb_delete(specneeded),
                nb_delete(lambda_counter))) ]) :-
    translate_clause([=, [specneeded, X], X], _),
    translate_clause([=, [lambda_counter, Y], Y], _),
    next_lambda_name(First),
    next_lambda_name(Second),
    First \== Second,
    nb_getval(specneeded, user_spec_state),
    nb_getval(lambda_counter, user_lambda_state).

%A lambda name must be unique across the whole process, not per thread. SWI
%global variables are thread-local, so a counter kept in one gave each
%hyperpose worker its own sequence from 1: two threads generated lambda_1 and
%the second assertz added its body to the first lambda's predicate, so one
%lambda answered with both branches' results.
test(lambda_names_are_unique_across_threads) :-
    next_lambda_name(Main),
    concurrent_maplist([_,Name]>>next_lambda_name(Name), [1,2,3,4], Workers),
    msort([Main|Workers], Sorted),
    sort([Main|Workers], Unique),
    Sorted == Unique.

meta_store_size(500).
meta_store_size(1000).

%A separate name per size rather than one refilled twice, so the second
%measurement does not start against a store that is already half full. Cleared
%through the test's own cleanup, which plunit runs even when the body throws.
clear_sized_meta_stores :-
    forall(( meta_store_size(Count),
             atom_concat('$plunit_meta_store_', Count, F) ),
           ( current_metta_module(Module),
             clear_fun_meta(Module, F),
             forget_test_function(F) )).

%Measured once rather than min of three: filling the store is destructive, so
%a second run would measure a different workload.
meta_store_cost(Count, Inferences) :-
    atom_concat('$plunit_meta_store_', Count, F),
    count_inferences(forall(between(1, Count, _),
                            translate_clause([=, [F, X], X], _)),
                     Inferences),
    current_metta_module(Module),
    aggregate_all(count, fun_meta_clause(Module, F, _, _), Count).

% Each equation is one independently indexed fact, so recording a new one does
% not copy the equations already held for that function [source:
% src/translator.pl, the comment above record_fun_meta/3]. A store that copied
% would cost O(n^2) to fill, and nothing said so: the ordering and retraction
% tests above pass either way.
%
% Cost is affine in the equation count, so doubling the count cannot more than
% double the work. Measured 2026-08-18: 19,757 inferences for 250 equations,
% 39,507 for 500, 79,007 for 1,000 and 158,007 for 2,000, which is 79 per
% equation plus a fixed 7 at every size. A copying store would read 4x per
% doubling instead of 2x.
%
% The count is asserted inside the measurement so a store that stopped
% recording would fail here rather than look like a speedup.
test(recording_equations_costs_no_more_than_linear_time,
     [ setup(clear_sized_meta_stores),
       cleanup(clear_sized_meta_stores) ]) :-
    meta_store_cost(500, Small),
    meta_store_cost(1000, Large),
    Large =< 2 * Small.

:- end_tests(translator_meta_store).

:- begin_tests(translator_let).

test(a_data_self_reference_cannot_create_a_rational_tree,
     [occurs_check(false), timeout(1)]) :-
    translate_expr([let, X, [g, X], X], Goals, _),
    %call_goals/1 is gone: a compiled goal resolves in the module of the space
    %that compiled it, and there is no module-blind version left.
    metta_self_module(Self),
    \+ call_goals_in_(Self, Goals).

%[g, X] above is data and needs no goals, so the check sees the whole value
%wherever it is emitted. A value that has to be computed does not: emitted
%ahead of the goals that build it, the check ran on an unbound result, could
%not fail, and the binding became a rational tree.
test(a_computed_self_reference_cannot_create_a_rational_tree,
     [occurs_check(false), timeout(1)]) :-
    translate_expr([let, X, ['cons-atom', X, []], X], Goals, _),
    metta_self_module(Self),
    \+ call_goals_in_(Self, Goals).

%A value that shares no variable with the pattern cannot be built out of the
%pattern, so its check stays ahead of the value's goals, where it runs on two
%unbound variables and costs nothing. Moving every let's check behind its
%value measured 2.7x wall clock on a let-heavy workload.
test(an_unshared_value_keeps_its_check_ahead_of_the_value_goals) :-
    translate_expr([let, _X, ['cons-atom', a, []], done], Goals, _),
    Goals = [unify_with_occurs_check(_, _)|_].

test(a_shared_value_moves_its_check_behind_the_value_goals) :-
    translate_expr([let, X, ['cons-atom', X, []], done], Goals, _),
    last(Goals, unify_with_occurs_check(_, _)).

test(acyclic_binding_keeps_let_semantics,
     [occurs_check(false)]) :-
    translate_expr([let, X, [value, 42], X], Goals, Out),
    metta_self_module(Self),
    once(call_goals_in_(Self, Goals)),
    Out == [value, 42].

:- end_tests(translator_let).

:- begin_tests(translator_stream_rewrites).

stream_rewrite_case(['trace!', 1, 2],
                    [progn, ['println!', 1], 2]).
stream_rewrite_case([unique, [superpose, a, a]],
                    [call, [superpose,
                            ['unique-atom', [collapse, [superpose, a, a]]]]]).
stream_rewrite_case(['alpha-unique', [superpose, a, a]],
                    [call, [superpose,
                            ['alpha-unique-atom',
                             [collapse, [superpose, a, a]]]]]).
stream_rewrite_case([union, [superpose, a], [superpose, b]],
                    [call, [superpose,
                            ['union-atom', [collapse, [superpose, a]],
                                           [collapse, [superpose, b]]]]]).
stream_rewrite_case([intersection, [superpose, a], [superpose, b]],
                    [call, [superpose,
                            ['intersection-atom', [collapse, [superpose, a]],
                                                  [collapse, [superpose, b]]]]]).
stream_rewrite_case([subtraction, [superpose, a], [superpose, b]],
                    [call, [superpose,
                            ['subtraction-atom', [collapse, [superpose, a]],
                                                 [collapse, [superpose, b]]]]]).

test(each_stream_rewrite_has_exactly_one_solution,
     [ forall(stream_rewrite_case(Input, Expected)),
       true(Solutions == [Expected]) ]) :-
    findall(Out, rewrite_streamops(Input, Out), Solutions).

test(trace_form_has_one_compilation) :-
    findall(Goals-Out, translate_expr(['trace!', 1, 2], Goals, Out),
            Solutions),
    Solutions = [[Print]-2],
    Print =@= 'println!'(1, _).

:- end_tests(translator_stream_rewrites).

:- begin_tests(translator_prolog_imports).

prolog_importer(import_prolog_functions_from_file).
prolog_importer(import_prolog_functions_from_module).

test(each_prolog_import_has_one_translation,
     [ forall(prolog_importer(Importer)),
       true(Solutions = [_]) ]) :-
    findall(Goals-Out,
            translate_expr([Importer, source, [imported_function]], Goals,
                           Out),
            Solutions),
    Solutions = [[Goal]-_],
    functor(Goal, Importer, 3).

:- end_tests(translator_prolog_imports).

:- begin_tests(translator_translation_depth).

nested_add(0, 0) :- !.
nested_add(N, ['+', 1, Inner]) :-
    N1 is N - 1,
    nested_add(N1, Inner).

nested_head(0, _) :- !.
nested_head(N, [Inner]) :-
    N1 is N - 1,
    nested_head(N1, Inner).

nested_let(0, 0) :- !.
nested_let(N, [let, '$v', 1, Inner]) :-
    N1 is N - 1,
    nested_let(N1, Inner).

translation_shape(call, nested_add).
translation_shape(head, nested_head).
translation_shape(let, nested_let).
translation_shape(conditional, nested_conditional).

translation_cost(Builder, Depth, Inferences) :-
    call(Builder, Depth, Expr),
    min_inferences(translate_expr(Expr, _, _), Inferences).

test(nested_calls_emit_one_goal_per_level) :-
    nested_add(400, Expr),
    translate_expr(Expr, Goals, _),
    length(Goals, 400).

test(nested_heads_emit_one_goal_per_level) :-
    nested_head(400, Expr),
    translate_expr(Expr, Goals, _),
    length(Goals, 400).

% Two depths rather than a ceiling. `Inferences < 50000` at depth 400 was the
% assertion here until 2026-08-18, and the shallowest of these shapes costs
% 3,203 at that depth, so it had room for a fifteenfold regression and could
% not have reported one. Cost is affine in depth for every shape, so doubling
% the depth cannot more than double the work, and a per-level cost that grew
% with depth would break that with no threshold to tune.
%
% Measured 2026-08-18, min of three, at depths 200 and 400: call 11,803 and
% 23,603; head 1,603 and 3,203; let 2,603 and 5,203; conditional 15,803 and
% 31,603. Per level that is 59.02/59.01, 8.02/8.01, 13.02/13.01 and
% 79.02/79.01, a constant plus a fixed 3-inference startup.
test(every_nesting_shape_compiles_in_linear_work,
     [forall(translation_shape(_Shape, Builder))]) :-
    translation_cost(Builder, 200, Small),
    translation_cost(Builder, 400, Large),
    %The lower bound is the liveness half. Without it a translator that had
    %stopped descending would cost the same at both depths and read as
    %perfectly linear.
    Large > Small,
    Large =< 2 * Small.

:- end_tests(translator_translation_depth).

:- begin_tests(translator_reduction_status).

test(a_called_function_reports_reduced) :-
    reduce(['+', 1, 2], Out, Status),
    Out == 3,
    Status == reduced.

test(an_uncallable_head_reports_not_reducible) :-
    reduce([plunit_no_such_head, 1], Out, Status),
    Out == [plunit_no_such_head, 1],
    Status == 'not-reducible'.

test(the_empty_expression_reports_not_reducible) :-
    reduce([], Out, Status),
    Out == [],
    Status == 'not-reducible'.

test(reduce_of_arity_two_keeps_its_exact_behaviour) :-
    % Every compiled call site uses reduce/2; the status must be additive.
    reduce(['+', 1, 2], Out),
    Out == 3.

:- end_tests(translator_reduction_status).

% reduce/3 dispatches on `\+ (Arity =< 2, current_op(_, _, F))`, and the ORDER
% of those two conjuncts is the guarantee: a call of arity three or more fails
% `Arity =< 2` and never reaches the operator table. Swapping them changes no
% answer anywhere, so no correctness test can see the difference; cost is the
% only witness there is.
%
% The measurement is a single-variable differential. One compiled function is
% reduced twice at the same arity with the same argument, and the only thing
% that changes between the two runs is whether its head is a declared operator.
% Equal cost means the operator table's CONTENT did not reach the computation,
% and content is the only thing current_op/3 can report.
%
% The second test is the control, and without it the first could pass because
% the instrument is blind rather than because the guard is ordered. At arity
% two the same toggle is not merely visible, it changes the answer.
:- begin_tests(translator_operator_dispatch,
               [ setup(setup_operator_dispatch),
                 cleanup(cleanup_operator_dispatch) ]).

operator_dispatch_head(binary, 'plunit-op-binary').
operator_dispatch_head(unary, 'plunit-op-unary').

%Registered the way a source file registers one. translate_clause/2 compiles
%the predicate and records its arity but never asserts fun/1, so reduce/3's
%first condition fails and the call falls through to data dispatch without
%ever reaching the guard under test.
setup_operator_dispatch :-
    cleanup_operator_dispatch,
    process_metta_string("(= (plunit-op-binary $a $b) $a)\n\c
                          (= (plunit-op-unary $a) $a)\n", _).

cleanup_operator_dispatch :-
    forall(operator_dispatch_head(_, Head),
           ( op(0, xfx, Head),
             forget_test_function(Head) )).

%op/3 is global state, so the declaration is undone even when the goal under
%it throws. A leaked declaration would silently change how every later test in
%this file reduces that head.
with_operator(Head, Goal) :-
    setup_call_cleanup(op(700, xfx, Head), Goal, op(0, xfx, Head)).

%The repository's counter recipe: warm the path, then take the minimum of
%three runs in one process [source: tests/prolog/README.md, "Measure engine
%changes"]. The minimum is belt and braces here, because an inference count is
%exact rather than sampled, but a stray atom collection inside one window is
%exactly what it protects against.
reduce_cost(Form, Answer, Inferences) :-
    Drive = forall(between(1, 500, _), once(reduce(Form, _))),
    call(Drive),
    min_inferences(Drive, Inferences),
    once(reduce(Form, Answer)).

% Measured 2026-08-18 over 500 calls, min of three: 10,002 inferences with the
% head declared an operator and 10,002 without, delta 0. With the two conjuncts
% swapped the same measurement reads 10,502 against 10,002, delta 500, which is
% the one current_op/3 redo per call that the ordering avoids.
test(a_higher_arity_call_never_reaches_the_operator_table) :-
    operator_dispatch_head(binary, Head),
    Form = [Head, 1, 2],
    reduce_cost(Form, Plain, PlainCost),
    with_operator(Head, reduce_cost(Form, AsOperator, OperatorCost)),
    %Both answers are asserted because equal costs mean nothing unless the
    %dispatch under test actually ran. An unregistered head reduces to itself
    %down a path that never reaches the guard, and the two arms are then equal
    %because neither did anything. The first draft of this test passed that
    %way, and only the control below said so.
    Plain == 1,
    AsOperator == 1,
    OperatorCost == PlainCost.

test(an_arity_two_call_does_reach_it) :-
    operator_dispatch_head(unary, Head),
    Form = [Head, 1],
    once(reduce(Form, Plain)),
    with_operator(Head, once(reduce(Form, AsOperator))),
    Plain == 1,
    AsOperator == partial(Head, [1]).

:- end_tests(translator_operator_dispatch).

% (super (f a)): the definition of f the NEXT module up this space's chain
% holds, so a shadow can check a call and then let the original run. The
% language had the absolute form already, `evalc`, which names the space to
% evaluate in and does not compose: two guards on one name in one space each
% delegating to &self both run, and an atom one refused is stored anyway by
% the other.
:- begin_tests(translator_super).

super_source("(= (sup-base $x) (base $x))\n\c
              (= (sup-shadow $x) (base $x))").

setup_super :-
    retractall(silent(_)), assertz(silent(true)),
    super_source(Source),
    process_metta_string(Source, _),
    'add-atom'('&plunit_super', [=, ['sup-base', X],
                                    [shadow, [super, ['sup-base', X]]]], _).

cleanup_super :-
    forall(member(S, ['&self', '&plunit_super']),
           forall(member(N, ['sup-base', 'sup-shadow']),
                  remove_sexp(S, [=, [N|_], _]))),
    retractall(silent(_)), assertz(silent(false)).

test(a_shadow_reaches_the_definition_above_it,
     [setup(setup_super), cleanup(cleanup_super)]) :-
    space_module('&plunit_super', Module),
    with_metta_module(Module, reduce(['sup-base', 1], Shadowed, _)),
    assertion(Shadowed == [shadow, [base, 1]]),
    % and the space above is unaffected by the shadow
    metta_self_module(Self),
    with_metta_module(Self, reduce(['sup-base', 1], Plain, _)),
    assertion(Plain == [base, 1]).

% The engine's own predicate is a definition above too, which is what makes a
% builtin shadowable AND delegable: before Phase 11 an equation for a builtin
% name in &self was refused outright.
test(a_shadow_of_a_builtin_reaches_the_engines_own,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( remove_sexp('&self', [=, ['car-atom'|_], _]),
                 metta_self_module(M), retractall(M:'car-atom'(_, _)),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    'add-atom'('&self', [=, ['car-atom', L], [mine, [super, ['car-atom', L]]]], _),
    metta_self_module(Self),
    with_metta_module(Self, reduce(['car-atom', [1, 2, 3]], Out, _)),
    assertion(Out == [mine, 1]),
    petta_engine_module(Engine),
    assertion(Engine:'car-atom'([1, 2, 3], 1)).

% Resolved at COMPILE time, so nothing above to reach is an error where the
% equation is written rather than a silent empty answer where it runs.
test(a_super_with_nothing_above_is_refused_at_definition_time,
     [ throws(error(existence_error(metta_super_definition,
                                    'sup-absent'/2), _)),
       setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( retractall(silent(_)), assertz(silent(false)) )) ]) :-
    'add-atom'('&plunit_super_absent',
               [=, ['sup-absent', X], [super, ['sup-absent', X]]], _).

test(a_super_over_a_variable_head_is_refused,
     [ throws(error(type_error(metta_super_call, _), _)) ]) :-
    translate_expr([super, '$f'], _, _).

% Compile-time resolution can go stale: a space that gains a definition
% becomes the nearer parent. The change hook rebuilds the callers.
test(a_later_definition_retargets_an_earlier_super,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( remove_sexp('&self', [=, ['car-atom'|_], _]),
                 remove_sexp('&plunit_super_retarget', [=, ['car-atom'|_], _]),
                 metta_self_module(M), retractall(M:'car-atom'(_, _)),
                 space_module('&plunit_super_retarget', R),
                 retractall(R:'car-atom'(_, _)),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    Space = '&plunit_super_retarget',
    space_module(Space, Module),
    'add-atom'(Space, [=, ['car-atom', L], [outer, [super, ['car-atom', L]]]], _),
    with_metta_module(Module, reduce(['car-atom', [1, 2, 3]], First, _)),
    % nothing between this space and the engine yet
    assertion(First == [outer, 1]),
    'add-atom'('&self', [=, ['car-atom', L2], [middle, L2]], _),
    with_metta_module(Module, reduce(['car-atom', [1, 2, 3]], Second, _)),
    assertion(Second == [outer, [middle, [1, 2, 3]]]).

:- end_tests(translator_super).

:- begin_tests(translator_special_dispatch).

% get-metatype and noeval are here for one reason: the ATOM MASK. Their
% declarations say the argument is not reduced, and only the compiler can act
% on that, so the call site has to be built rather than the predicate called
% with an evaluated argument. Compiled here rather than by honouring the
% engine's declaration register wholesale, because several of those
% declarations describe the argument a CALLER writes rather than the value the
% predicate receives; the reasoning is at call_site_type_chains/2.
expected_special_heads([
    'add-atom', 'add-atoms', 'add-reduct', 'add-reducts', annotation,
    'and-then', 'catch', 'filter-atom', 'foldall',
    'with-pragma!',
    'foldl-atom', 'forall', 'get-metatype', 'let*', 'map-atom', 'not-provable',
    'or-else', 'remove-atom', 'test-no-answer', '|->', call, case, chain,
    collapse, cut, elapsed, eval, evalc, explain, hyperpose, if, let, match,
    inferences, noeval,
    once, prog1, progn, quote, reduce, sealed, super, superpose, take, test,
    timeout,
    top, transaction, translatePredicate, unify, with_mutex
]).

special_dispatch_expression([superpose, [1, 2]]).
special_dispatch_expression([collapse, [quote, answer]]).
special_dispatch_expression([if, true, yes, no]).
special_dispatch_expression([let, X, 1, X]).
special_dispatch_expression([quote, [a, b]]).
special_dispatch_expression(['catch', [quote, answer]]).

test(each_special_form_clause_has_an_indexable_head) :-
    findall(Head,
            clause(user:translate_special_dl(Head, _, _, _, _), _),
            Heads0),
    sort(Heads0, Heads),
    expected_special_heads(Expected0),
    sort(Expected0, Expected),
    Heads == Expected.

% metta_translated_head/1 is the "does the engine give this head meaning"
% question, and the translator answers it two ways: translate_special_dl/5
% and the stream rewrites. A head missed there is reported as a
% possibly-undefined reference in correct code, which is what asking fun/1
% alone did to `if`. Derived from the clause heads rather than a literal
% list, so adding a third compilation route without widening the predicate
% fails here.
test(every_translated_head_is_answered_for) :-
    findall(H, clause(user:translate_special_dl(H, _, _, _, _), _), Special),
    findall(H, ( clause(user:rewrite_streamops(P, _), _),
                 nonvar(P), P = [H|_] ), Stream),
    append(Special, Stream, All0),
    sort(All0, All),
    forall(member(Head, All), metta_translated_head(Head)).

% rewrite_streamops/2's last clause is the identity fallthrough, whose head
% argument is a bare variable. Reading it with clause/2 without a nonvar
% guard answers true for every symbol in the language and silently disables
% the linter check this predicate exists for.
test(an_ordinary_name_is_not_a_translated_head, [fail]) :-
    metta_translated_head('no-such-head-anywhere').

test(dispatch_uses_a_realised_first_argument_index) :-
    forall(between(1, 1000, _),
           once(translate_expr([quote, answer], _, _))),
    predicate_property(user:translate_special_dl(_, _, _, _, _),
                       indexed(Indexes)),
    once(( member(Index, Indexes),
           Index.arguments == [1],
           Index.realised == true )).

test(representative_forms_each_have_one_translation,
     [forall(special_dispatch_expression(Expr))]) :-
    findall(Goals-Out, translate_expr(Expr, Goals, Out), Solutions),
    Solutions = [_].

test(variable_heads_are_not_bound_to_a_special_form) :-
    % The emitted goal is reduce/3: a variable head is decided at runtime,
    % and that is the decision the evaluation status comes from.
    translate_expr([Head, 1], Goals, _),
    var(Head),
    Goals = [reduce([Head, 1], _, _)].

test(space_predicates_use_space_storage,
     [ setup(add_sexp('&self', [plunit_space_predicate, a, b])),
       cleanup(remove_sexp('&self',
                           [plunit_space_predicate, _, _])) ]) :-
    translate_expr(
        [translatePredicate, ['&self', plunit_space_predicate, A, B]],
        Goals,
        _),
    goals_list_to_conj(Goals, Goal),
    once(call(Goal)),
    A-B == a-b,
    'Predicate'(['&self', plunit_space_predicate, C, D], Constructed),
    once(call(Constructed)),
    C-D == a-b.

% Every other special form may fall through to data dispatch when a clause does
% not fit its arguments, which is what lets a program use a name like case or
% if as a symbol. The two Prolog seams are the exception: no program means them
% as data, so each shape below used to compile into a list named after the form
% and answer without complaint, and (translatePredicate (p $x) (p $x)) even
% evaluated both arguments before discarding them into it.
malformed_seam([translatePredicate, plunit_seam_target]).
malformed_seam([translatePredicate,
                [plunit_seam_target, _], [plunit_seam_target, _]]).
malformed_seam([translatePredicate]).
malformed_seam([call, plunit_seam_target]).
malformed_seam([call]).

test(malformed_seam_is_refused,
     [ forall(malformed_seam(Expr)),
       throws(error(petta_uncompilable_seam(_, _), _)) ]) :-
    translate_expr(Expr, _, _).

:- end_tests(translator_special_dispatch).

% (case Key Cases) reads its cases as syntax and compiles one nested
% conditional out of them, so a cases argument that is still a variable has
% none to read. That shape used to reach select/3 over an open list, which
% enumerates longer and longer instances of it forever: 7.5 Gb allocated
% before anything was answered, bare, under once, under collapse, and on
% merely LOADING the one-line definition (= (switch $v $cs) (case $v $cs))
% that a library would write to give case another name.
%
% The low ceiling is what keeps a regression here cheap, and both units below
% run under it. The runaway fills the global stack faster than a person can
% react, so a low ceiling turns a machine that swaps for minutes into a run
% that reddens in a fraction of a second, and 256 Mb is far more than any
% test in either unit needs [measured 2026-08-19 on the defect: a 64 Mb
% ceiling was exhausted in 0.141 s by !(case 1 $cases) and in 0.154 s by the
% wrapper definition].
bound_case_stack :-
    current_prolog_flag(stack_limit, Limit),
    nb_setval(plunit_case_stack_limit, Limit),
    set_prolog_flag(stack_limit, 268_435_456).

restore_case_stack :-
    nb_getval(plunit_case_stack_limit, Limit),
    set_prolog_flag(stack_limit, Limit).

% The refusing half. Nothing here defines a MeTTa function, so each test
% reaches the form on its own: with the guard reverted, the first one below
% exhausts the ceiling instead of raising, which is the shape of the defect.
:- begin_tests(translator_case_open_cases,
               [ setup(bound_case_stack),
                 cleanup(restore_case_stack) ]).

open_cases_form("!(case 1 $cases)").
open_cases_form("!(once (case 1 $cases))").
open_cases_form("!(collapse (case 1 $cases))").

test(test_case_with_an_unbound_pairs_argument_declines_instead_of_allocating,
     [ forall(open_cases_form(Form)),
       throws(error(type_error('a list of (pattern value) cases', _),
                    context(case, _))) ]) :-
    process_metta_string(Form, _).

%A cases list only partly written has the same open spine one element later,
%and select/3 ran away on it too. MeTTa has no syntax for one, so it is built
%here and evaluated the way any runtime-built term reaches the engine.
test(a_partly_written_cases_list_declines_too,
     [ throws(error(type_error('a list of (pattern value) cases', _),
                    context(case, _))) ]) :-
    eval([case, 1, [[1, one]|_]], _).

%The refusal in the program's own vocabulary: the form's MeTTa name and the
%value printed as the program would have written it, not as the Prolog term
%the engine holds and not as a predicate of the engine's.
test(the_refusal_names_the_form_and_the_argument_in_metta) :-
    catch(eval([case, 1, _Cases], _), Error, true),
    assertion(nonvar(Error)),
    message_to_string(Error, Text),
    assertion(Text == "case: a list of (pattern value) cases expected, \c
                       found $_0").

%A pair that is still a variable has not arrived either, one level in from
%the spine. That shape used to reach translate_case/5, whose own head unified
%[Pattern, Value] INTO it: the source term came back changed, and
%(= (f $p) (case 1 ($p))) compiled to f([A, B], _) instead of f($p, _), so
%an argument that was not a two-element list failed silently against a head
%the program never wrote.
test(a_pair_that_has_not_arrived_is_not_unified_with_translate_cases_own_pattern) :-
    translate_expr([case, 1, [Pair]], _, _),
    assertion(var(Pair)).

%The control, and the reason this item's original title was wrong: an unbound
%KEY was always fine, because the key is an expression the form compiles
%around rather than syntax it reads. Only the cases were ever the trigger,
%and a guard that caught both would have refused a form that works.
test(an_unbound_key_is_not_what_this_form_cannot_read) :-
    process_metta_string("!(case $key ((1 one)))", Answers),
    assertion(Answers == [one]).

%A cases argument that is no list at all is not cases that have yet to
%arrive, it is a program using the name as data, and it keeps falling through
%to data dispatch exactly as it did. unarrived_pairs/1 exists to tell those
%two apart, which is_list/1 alone cannot.
test(a_cases_argument_that_is_no_list_still_falls_through_to_data,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string("!(case 1 foo)", Answers),
    assertion(Answers == [[case, 1, foo]]).

%The symptom as first reported: merely LOADING the wrapper died, before any
%call, because a definition is compiled whole. It is its own test rather than
%the next unit's setup, because a setup that dies reads as a broken suite
%instead of as this defect.
test(loading_a_one_line_case_wrapper_no_longer_dies,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( 'remove-atom'('&self', [=, ['plunit-case-alias'|_], _], _),
                 forget_test_function('plunit-case-alias'),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string("(= (plunit-case-alias $v $cs) (case $v $cs))", _),
    process_metta_string("!(plunit-case-alias 1 ((1 one)))", Answers),
    assertion(Answers == [one]).

:- end_tests(translator_case_open_cases).

% The answering half, and the item's other acceptance: switch is the ordinary
% way to give case another name, it is how an alignment library would define
% it, and the two wrappers this unit's setup defines used to kill the process
% on the way in.
:- begin_tests(translator_case_computed_cases,
               [ setup(setup_case_computed_cases),
                 cleanup(cleanup_case_computed_cases) ]).

case_computed_head('plunit-switch').
case_computed_head('plunit-case-of-nothing').
case_computed_head('plunit-case-body').
case_computed_head('plunit-case-onepair').
case_computed_head('plunit-case-3').
case_computed_head('plunit-case-24').

setup_case_computed_cases :-
    bound_case_stack,
    retractall(silent(_)), assertz(silent(true)),
    process_metta_string("(= (plunit-switch $v $cs) (case $v $cs))\n\c
                          (= (plunit-case-of-nothing $cs) (case (empty) $cs))\n\c
                          (= (plunit-case-body $x) (* $x 10))\n\c
                          (= (plunit-case-onepair $p) (case 1 ($p)))", _),
    forall(member(N, [3, 24]),
           ( written_out_case_definition(N, Definition),
             process_metta_string(Definition, _) )).

cleanup_case_computed_cases :-
    restore_case_stack,
    forall(case_computed_head(Head),
           ( 'remove-atom'('&self', [=, [Head|_], _], _),
             forget_test_function(Head) )),
    retractall(silent(_)), assertz(silent(false)).

%N cases written out, and the same N as a value, so the cost test below
%compares the two paths on identical branches rather than on two programs.
written_out_case_definition(N, Definition) :-
    computed_cases(N, Cases),
    swrite(Cases, Text),
    format(atom(Definition), "(= (plunit-case-~w $v) (case $v ~w))", [N, Text]).

computed_cases(N, Cases) :- findall([I, hit], between(1, N, I), Cases).

test(a_switch_written_as_an_ordinary_definition_answers) :-
    process_metta_string("!(plunit-switch 2 ((1 one) (2 two)))", Answers),
    assertion(Answers == [two]).

%One pair handed over on its own is a pair, and the definition keeps the head
%it was written with, so an argument that is not a pair is refused rather
%than failing against a head the program never wrote.
test(a_pair_arriving_as_a_value_is_a_branch) :-
    process_metta_string("!(plunit-case-onepair (quote (1 hit)))", Answers),
    assertion(Answers == [hit]).

test(a_pair_that_is_not_a_pair_is_refused_rather_than_failing_silently,
     [ throws(error(type_error('a list of (pattern value) cases', _),
                    context(case, _))) ]) :-
    process_metta_string("!(plunit-case-onepair 5)", _).

%The same refusal for a value that IS a list but carries something that is
%not a (pattern value) pair, which is the shape a program is most likely to
%build by accident.
test(the_refusal_prints_a_bad_cases_value_as_metta) :-
    catch(process_metta_string("!(plunit-switch 1 (quote ((1 one 2))))", _),
          Error, true),
    assertion(nonvar(Error)),
    message_to_string(Error, Text),
    assertion(Text == "case: a list of (pattern value) cases expected, \c
                       found ((1 one 2))").

%Cases written out, and the same cases handed over as a value, must answer
%the same thing. quote is what carries the cases across an ordinary argument
%without MeTTa evaluating them on the way, which is the third column: fifteen
%of these sixteen shapes answer the same with or without it, and the one that
%does not is the functional pattern (cons $h $t), which is a call and is
%evaluated [measured 2026-08-19: unquoted it answers () where the written-out
%form answers (1)]. The unquoted comparison is asserted where it holds, so
%the quote is not quietly hiding a disagreement in the other fifteen.
computed_case_shape("2",                 "((1 one) (2 two))",             plain).
computed_case_shape("9",                 "((1 one) (2 two))",             plain).
computed_case_shape("9",                 "((1 one) (Empty none))",        plain).
computed_case_shape("3",                 "((Empty none) (3 three))",      plain).
computed_case_shape("1",                 "((1 first) (1 second))",        plain).
computed_case_shape("1",                 "((1 (+ 2 3)))",                 plain).
computed_case_shape("1",                 "((1 (plunit-case-body 4)))",    plain).
computed_case_shape("1",                 "((1 (superpose (a b))))",       plain).
computed_case_shape("1",                 "((1 (case 2 ((2 inner)))))",    plain).
computed_case_shape("(plunit-pair 1)",   "(((plunit-pair $n) $n))",       plain).
computed_case_shape("(superpose (1 2))", "((1 one) (2 two))",             plain).
computed_case_shape("True",              "((True yes) (False no))",       plain).
computed_case_shape("7",                 "()",                            plain).
computed_case_shape("7",                 "(($x $x))",                     plain).
computed_case_shape("\"s\"",             "((\"s\" str) (Empty other))",  plain).
computed_case_shape("(1 2 3)",           "(((cons $h $t) $h))",           needs_quote).

test(computed_cases_answer_what_the_same_cases_written_out_answer,
     [ forall(computed_case_shape(Key, Cases, Protection)) ]) :-
    format(atom(Written), "!(collapse (case ~w ~w))", [Key, Cases]),
    format(atom(Quoted), "!(collapse (plunit-switch ~w (quote ~w)))",
           [Key, Cases]),
    process_metta_string(Written, [WrittenAnswers]),
    process_metta_string(Quoted, [QuotedAnswers]),
    assertion(QuotedAnswers == WrittenAnswers),
    ( Protection == plain
      -> format(atom(Bare), "!(collapse (plunit-switch ~w ~w))",
                [Key, Cases]),
         process_metta_string(Bare, [BareAnswers]),
         assertion(BareAnswers == WrittenAnswers)
      ;  true ).

%Empty is what a key ANSWERING NOTHING selects, not what a key that matched
%no branch selects, and the value path decides it the same way: the key runs
%once under a soft cut and the Empty pair is the else branch. A wrapper
%cannot be asked this from outside, because MeTTa evaluates the argument
%before the call, so the key is written inside the definition.
test(a_key_with_no_answers_takes_the_computed_default) :-
    process_metta_string("!(collapse (case (empty) ((1 one) (Empty none))))",
                         [Written]),
    process_metta_string("!(collapse (plunit-case-of-nothing \c
                                       (quote ((1 one) (Empty none)))))",
                         [Computed]),
    assertion(Written == [none]),
    assertion(Computed == Written).

test(a_key_with_no_answers_and_no_computed_default_answers_nothing) :-
    process_metta_string("!(collapse (plunit-case-of-nothing \c
                                       (quote ((1 one)))))",
                         [Computed]),
    assertion(Computed == []).

%Nothing downstream can check these, so they are checked before the cases are
%compiled. A pair that is not (pattern value) would unify with
%translate_case/5's own head and compile a branch the program never wrote,
%and a bare variable element is the same hole one level down.
bad_computed_cases("foo",         foo).
bad_computed_cases("((1 one 2))", [[1, one, 2]]).
bad_computed_cases("(1)",         [1]).

test(a_value_that_is_not_cases_is_refused_by_name,
     [ forall(bad_computed_cases(Text, Culprit)),
       throws(error(type_error('a list of (pattern value) cases', Culprit),
                    context(case, _))) ]) :-
    format(atom(Form), "!(plunit-switch 1 (quote ~w))", [Text]),
    process_metta_string(Form, _).

%The trade this design makes, measured rather than asserted. Cases written
%out are compiled once into a nested conditional, so a call pays the same
%however many there are. Cases arriving as a value are compiled by the same
%translate_case/5 on every call, so a call pays for all of them, which is why
%a case on a hot path is worth writing out [measured 2026-08-19: 3 inferences
%a call at 3, 12 and 24 written-out cases; 78, 258 and 498 for the same cases
%handed over]. The slope over 100 and 1,100 calls is what is asserted, so
%one-off setup falls out of both sides.
written_out_case_calls(Module, N, Times) :-
    atom_concat('plunit-case-', N, Head),
    forall(between(1, Times, _),
           ( Goal =.. [Head, 1, _], call(Module:Goal) )).

computed_case_calls(Module, N, Times) :-
    computed_cases(N, Cases),
    forall(between(1, Times, _),
           call(Module:'plunit-switch'(1, Cases, _))).

test(written_out_cases_cost_the_same_per_call_however_many_there_are) :-
    metta_self_module(Module),
    context_module(Unit),
    call_cost(Unit:written_out_case_calls(Module, 3), WrittenSmall),
    call_cost(Unit:written_out_case_calls(Module, 24), WrittenLarge),
    assertion(WrittenSmall == WrittenLarge),
    call_cost(Unit:computed_case_calls(Module, 3), ComputedSmall),
    call_cost(Unit:computed_case_calls(Module, 24), ComputedLarge),
    assertion(ComputedLarge > ComputedSmall),
    assertion(WrittenSmall < ComputedSmall).

:- end_tests(translator_case_computed_cases).

% (let* Bindings Body) reads its bindings as syntax and rewrites them into
% nested lets, so a bindings argument that has not arrived has none to read.
% That shape used to reach the [] base clause, whose cut then committed to
% it: the argument was UNIFIED with the empty list and every binding was
% dropped without a word. (= (mylet $bs $b) (let* $bs $b)) compiled to
% mylet([], A, A), so the wrapper answered its body unbound instead of the
% body under the caller's bindings.
%
% A pair that is still a variable is the same defect one level in. There the
% rewrite unified its own [Pattern, Value] pattern INTO the source, so
% (= (letpair $b) (let* ($b) 99)) compiled to letpair([A, B], 99) and changed
% the head the program wrote.
:- begin_tests(translator_letstar_unarrived_bindings).

% Nothing here defines a MeTTa function; each test reaches the form on its
% own, so the unit reddens on the defect rather than on a broken setup.

test(an_unbound_bindings_list_is_not_unified_with_the_empty_one) :-
    translate_expr(['let*', Bindings, done], _, _),
    assertion(var(Bindings)).

test(a_pair_that_has_not_arrived_is_not_unified_with_the_rewrites_own_pattern) :-
    translate_expr(['let*', [Pair], done], _, _),
    assertion(var(Pair)).

test(an_unbound_bindings_list_declines_instead_of_dropping_the_bindings,
     [ throws(error(type_error('a list of (pattern value) bindings', _),
                    context('let*', _))) ]) :-
    eval(['let*', _Bindings, done], _).

%A bindings list only partly written has the same open spine one element
%later. MeTTa has no syntax for one, so it is built here and evaluated the
%way any runtime-built term reaches the engine.
test(a_partly_written_bindings_list_declines_too,
     [ throws(error(type_error('a list of (pattern value) bindings', _),
                    context('let*', _))) ]) :-
    eval(['let*', [[_, 1]|_], done], _).

%The refusal in the program's own vocabulary: the form's MeTTa name and the
%value printed as the program would have written it, not as the Prolog term
%the engine holds and not as a predicate of the engine's.
test(the_refusal_names_the_form_and_the_argument_in_metta) :-
    catch(eval(['let*', _Bindings, done], _), Error, true),
    assertion(nonvar(Error)),
    message_to_string(Error, Text),
    assertion(Text == "let*: a list of (pattern value) bindings expected, \c
                       found $_0").

%A bindings argument that is no list at all is not bindings that have yet to
%arrive, it is a program using the name as data, and it keeps falling through
%to the partial form exactly as it did.
test(a_bindings_argument_that_is_no_list_still_falls_through_to_data,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string("!(let* foo ok)", Answers),
    assertion(Answers == [partial('let*', [foo, ok])]).

%Writing the bindings out is untouched: the form is still exactly the nested
%lets it rewrites to, goal for goal.
test(written_out_bindings_compile_as_the_nested_lets_they_rewrite_to) :-
    translate_expr(['let*', [[A, 1], [B, 2]], [+, A, B]], StarGoals, StarOut),
    translate_expr([let, C, 1, [let, D, 2, [+, C, D]]], LetGoals, LetOut),
    assertion(StarGoals-StarOut =@= LetGoals-LetOut).

test(no_bindings_at_all_is_still_the_body) :-
    translate_expr(['let*', [], done], Goals, Out),
    assertion(Goals == []),
    assertion(Out == done).

:- end_tests(translator_letstar_unarrived_bindings).

% The answering half: `let*` under another name is an ordinary definition,
% which is how a library would give the form its own spelling.
:- begin_tests(translator_letstar_computed_bindings,
               [ setup(setup_letstar_computed),
                 cleanup(cleanup_letstar_computed) ]).

letstar_computed_head('plunit-mylet').
letstar_computed_head('plunit-mylet-atom').
letstar_computed_head('plunit-letpair').
letstar_computed_head('plunit-letstar-2').
letstar_computed_head('plunit-letstar-16').

setup_letstar_computed :-
    retractall(silent(_)), assertz(silent(true)),
    process_metta_string("(= (plunit-mylet $bs $b) (let* $bs $b))\n\c
                          (: plunit-mylet-atom (-> Atom Atom Number))\n\c
                          (= (plunit-mylet-atom $bs $b) (let* $bs $b))\n\c
                          (= (plunit-letpair $b) (let* ($b) 99))", _),
    forall(member(N, [2, 16]),
           ( written_out_letstar_definition(N, Definition),
             process_metta_string(Definition, _) )).

cleanup_letstar_computed :-
    forall(letstar_computed_head(Head),
           ( 'remove-atom'('&self', [=, [Head|_], _], _),
             forget_test_function(Head) )),
    'remove-atom'('&self', [:, 'plunit-mylet-atom', _], _),
    retractall(silent(_)), assertz(silent(false)).

%N bindings written out, and the same N as a value, so the cost test below
%compares the two paths on identical bindings rather than on two programs.
written_out_letstar_definition(N, Definition) :-
    computed_bindings(N, Bindings),
    swrite(Bindings, Text),
    format(atom(Definition),
           "(= (plunit-letstar-~w) (let* ~w done))", [N, Text]).

computed_bindings(N, Bindings) :-
    findall([_, I], between(1, N, I), Bindings).

%The whole defect, end to end: the bindings a caller writes decide the
%bindings, where before they were dropped and the body answered unbound.
test(bindings_handed_over_as_a_value_bind_the_body) :-
    process_metta_string("!(plunit-mylet (quote (($x 1))) $x)", Answers),
    assertion(Answers == [1]).

%The spec row's own probe. The body has to arrive unevaluated for the
%bindings to reach it, which is what the Atom metatype is for, and then a
%one-line definition is `let*` under another name.
test(an_atom_typed_wrapper_answers_what_the_written_out_form_answers) :-
    process_metta_string("!(plunit-mylet-atom (($x 1) ($y 2)) (+ $x $y))",
                         Answers),
    assertion(Answers == [3]),
    process_metta_string("!(let* (($x 1) ($y 2)) (+ $x $y))", Written),
    assertion(Written == Answers).

%A pair handed over is a pair, and the head keeps the shape the program
%wrote: (plunit-letpair 5) has no answer because 5 is not a binding, and
%that is a refusal rather than a silent failure.
test(a_pair_arriving_as_a_value_binds_the_body) :-
    process_metta_string("!(plunit-letpair (quote ($x 7)))", Answers),
    assertion(Answers == [99]).

test(a_value_that_is_not_bindings_is_refused_by_name,
     [ throws(error(type_error('a list of (pattern value) bindings', _),
                    context('let*', _))) ]) :-
    process_metta_string("!(plunit-mylet (quote ((1 2 3))) $x)", _).

%The trade this design makes, measured rather than asserted. Bindings
%written out are rewritten into nested lets once, so a call pays the same
%however many there are. Bindings arriving as a value are rewritten and
%compiled on every call, so a call pays for all of them.
written_out_letstar_calls(Module, N, Times) :-
    atom_concat('plunit-letstar-', N, Head),
    forall(between(1, Times, _),
           ( Goal =.. [Head, _], call(Module:Goal) )).

computed_letstar_calls(Module, N, Times) :-
    computed_bindings(N, Bindings),
    forall(between(1, Times, _),
           call(Module:'plunit-mylet'(Bindings, done, _))).

test(written_out_bindings_cost_the_same_per_call_however_many_there_are) :-
    metta_self_module(Module),
    context_module(Unit),
    call_cost(Unit:written_out_letstar_calls(Module, 2), WrittenSmall),
    call_cost(Unit:written_out_letstar_calls(Module, 16), WrittenLarge),
    assertion(WrittenSmall == WrittenLarge),
    call_cost(Unit:computed_letstar_calls(Module, 2), ComputedSmall),
    call_cost(Unit:computed_letstar_calls(Module, 16), ComputedLarge),
    assertion(ComputedLarge > ComputedSmall),
    assertion(WrittenSmall < ComputedSmall).

:- end_tests(translator_letstar_computed_bindings).

% A translator rule is called as a Prolog predicate, so a rule whose MeTTa body
% is one call to a registered predicate has its whole expansion written in
% Prolog. Together with translatePredicate that is a library deciding how its
% own forms compile: the review's X4 proposed a second mechanism for this
% before the composition was tried.
:- begin_tests(translator_prolog_authored_rules,
               [ setup(( assertz(( user:plunit_x4_add(A, B, Out, Gs) :-
                                     ( integer(A), integer(B)
                                     -> C is A + B,
                                        Gs = [translatePredicate, [=, Out, C]]
                                     ;  Gs = [translatePredicate,
                                              [plus, A, B, Out]] ) )),
                        assertz(( user:plunit_x4_quoted(Out, Gs) :-
                                     Gs = [quote, [translatePredicate,
                                                   [=, Out, 42]]] )),
                        assertz(user:translator_rule(plunit_x4_add)),
                        assertz(user:translator_rule(plunit_x4_quoted)) )),
                 cleanup(( retractall(user:translator_rule(plunit_x4_add)),
                           retractall(user:translator_rule(plunit_x4_quoted)),
                           abolish(user:plunit_x4_add/4),
                           abolish(user:plunit_x4_quoted/2) )) ]).

test(a_prolog_rule_folds_a_constant_at_compile_time) :-
    translate_expr([plunit_x4_add, 20, 22, V], Goals, _),
    % Nothing is left to run but the unification the rule chose.
    Goals = [V = 42].

test(a_prolog_rule_emits_a_goal_when_it_cannot_fold) :-
    translate_expr([plunit_x4_add, A, B, V], Goals, _),
    Goals = [plus(A, B, V)],
    A = 6, B = 7,
    once(plus(A, B, V)),
    V == 13.

test(quoted_seam_expansion_is_refused,
     [throws(error(petta_seam_expansion_as_data(plunit_x4_quoted,
                                                translatePredicate), _))]) :-
    translate_expr([plunit_x4_quoted, _], _, _).

:- end_tests(translator_prolog_authored_rules).

% A symbol may carry several type declarations at different arities. That is
% nondeterminism over declarations, not a conflict, and a declaration whose
% shape does not fit a call simply does not apply to it. Before this worked,
% the branches were built with maplist, so ONE inapplicable declaration failed
% the whole form and (plunit_multi_arity a b 1) would not translate at all.
:- begin_tests(translator_multi_arity_declarations,
               [ setup((retractall(user:fun(plunit_multi_arity)),
                        retractall(user:arity(plunit_multi_arity, _)),
                        remove_sexp('&self', [':', plunit_multi_arity, _]),
                        assertz(user:fun(plunit_multi_arity)),
                        assertz(user:arity(plunit_multi_arity, 3)),
                        assertz(user:arity(plunit_multi_arity, 4)),
                        add_sexp('&self',
                                 [':', plunit_multi_arity,
                                  [->, 'Number', 'Number', 'Number']]),
                        add_sexp('&self',
                                 [':', plunit_multi_arity,
                                  [->, 'Number', 'Number', 'Number',
                                   'Number']]))),
                 cleanup((retractall(user:fun(plunit_multi_arity)),
                          retractall(user:arity(plunit_multi_arity, _)),
                          remove_sexp('&self',
                                      [':', plunit_multi_arity, _]))) ]).

test(each_arity_translates) :-
    translate_expr([plunit_multi_arity, 1, 2], _, _),
    translate_expr([plunit_multi_arity, 1, 2, 3], _, _).

% The wider declaration must not also build a branch for the shorter call,
% which would answer the same thing twice.
test(an_exact_arity_match_excludes_the_wider_declaration) :-
    findall(Goals, translate_expr([plunit_multi_arity, 1, 2], Goals, _),
            Translations),
    length(Translations, 1).

:- end_tests(translator_multi_arity_declarations).

%An argument whose declared type is a type variable occurring nowhere else in
%the chain constrains nothing: the check cannot fail, because it falls back to
%get-metatype/2, and nothing reads the type it computes. Dropping it took a
%call from 83 inferences to 12 [measured 2026-08-15, 1000 runs of a call site
%compiled once].
:- begin_tests(translator_importer_arguments).

% An importer's second argument is a list of NAMES, and it has to stay data.
% Only two of the four spellings were kept literal, so lib_zar's pair compiled
% the list as an expression once any name in it had already become a function:
% (zar_add zar_typo) became a partial application of zar_add, the declared
% Expression check on it failed, and the whole import answered nothing with no
% error at any point.
test(an_importer_name_list_stays_data,
     [ setup(( assertz(user:plunit_tr_importable(_, _)),
               import_prolog_function(plunit_tr_importable, _) )),
       cleanup(( abolish(user:plunit_tr_importable/2),
                 unregister_fun_everywhere(plunit_tr_importable),
                 release_function_name(plunit_tr_importable),
                 retractall(fun(plunit_tr_importable)),
                 retractall(arity(plunit_tr_importable, _)) )) ]) :-
    forall(prolog_function_importer(Importer),
           ( Call = [Importer, "lib.pl", [plunit_tr_importable, other]],
             translate_expr(Call, Goals, _),
             % One goal, with the list intact: no call to the registered name.
             Goals = [Goal],
             Goal =.. [Importer, "lib.pl", Names, _],
             assertion(Names == [plunit_tr_importable, other]) )).

test(all_four_importer_spellings_are_covered) :-
    findall(I, prolog_function_importer(I), Importers),
    msort(Importers, Sorted),
    Sorted == [import_prolog_functions_from_file,
               import_prolog_functions_from_file_pred,
               import_prolog_functions_from_module,
               import_prolog_functions_from_module_pred].

:- end_tests(translator_importer_arguments).

:- begin_tests(translator_unconstraining_types).

typed_call_goal(TypeChain, Goal) :-
    setup_call_cleanup(
        ( assertz(user:fun(plunit_free_types)),
          assertz(user:arity(plunit_free_types, 3)),
          add_sexp('&self', [':', plunit_free_types, TypeChain]) ),
        ( translate_expr([plunit_free_types, 1, 2], Goals, _),
          goals_list_to_conj(Goals, Goal) ),
        ( retractall(user:fun(plunit_free_types)),
          retractall(user:arity(plunit_free_types, _)),
          remove_sexp('&self', [':', plunit_free_types, _]) )).

has_type_check(Goal) :-
    once(( sub_term(Sub, Goal), nonvar(Sub), Sub = has_type(_, _) )).

test(a_singleton_type_variable_generates_no_check) :-
    typed_call_goal([->, _A, _B, 'Bool'], Goal),
    findall(Type, ( sub_term(S, Goal), nonvar(S), S = has_type(_, Type) ),
            Checked),
    %Only the concrete output type is worth checking.
    Checked == ['Bool'].

test(a_repeated_type_variable_keeps_its_checks) :-
    typed_call_goal([->, A, A, 'Bool'], Goal),
    findall(x, ( sub_term(S, Goal), nonvar(S), S = has_type(_, T), var(T) ),
            Kept),
    length(Kept, Count),
    Count =:= 2.

test(a_concrete_type_keeps_its_check) :-
    typed_call_goal([->, 'Number', 'Number', 'Bool'], Goal),
    has_type_check(Goal).

%A variable nested inside a structured type is not a bare singleton argument
%type, so its check stays.
test(a_type_variable_inside_a_structure_keeps_its_check) :-
    typed_call_goal([->, ['List', _C], 'Number', 'Bool'], Goal),
    findall(Type, ( sub_term(S, Goal), nonvar(S), S = has_type(_, Type),
                    nonvar(Type), Type = ['List'|_] ),
            Kept),
    Kept \== [].

:- end_tests(translator_unconstraining_types).

:- begin_tests(translator_typed_currying,
               [ setup((retractall(user:fun(plunit_typed_curry)),
                        retractall(user:arity(plunit_typed_curry, _)),
                        remove_sexp('&self',
                                    [':', plunit_typed_curry, _]),
                        assertz(user:fun(plunit_typed_curry)),
                        assertz(user:arity(plunit_typed_curry, 3)),
                        add_sexp('&self',
                                 [':', plunit_typed_curry,
                                  [->, 'Number', 'Number', 'Number']]))),
                 cleanup((retractall(user:fun(plunit_typed_curry)),
                          retractall(user:arity(plunit_typed_curry, _)),
                          remove_sexp('&self',
                                      [':', plunit_typed_curry, _]))) ]).

test(output_type_check_waits_for_a_return_value) :-
    translate_expr([plunit_typed_curry, 1], Goals, Partial),
    goals_list_to_conj(Goals, Goal),
    call(Goal),
    Partial == partial(plunit_typed_curry, [1]).

:- end_tests(translator_typed_currying).

:- begin_tests(translator_typed_single_pass,
               [ setup((retractall(user:fun(plunit_typed_once)),
                        retractall(user:arity(plunit_typed_once, _)),
                        remove_sexp('&self', [':', plunit_typed_once, _]),
                        assertz(user:fun(plunit_typed_once)),
                        assertz(user:arity(plunit_typed_once, 3)),
                        add_sexp('&self',
                                 [':', plunit_typed_once,
                                  [->, '%Undefined%', 'Number', 'Number']]))),
                 cleanup((retractall(user:fun(plunit_typed_once)),
                          retractall(user:arity(plunit_typed_once, _)),
                          remove_sexp('&self',
                                      [':', plunit_typed_once, _]))) ]).

%next_lambda_name/1 counts in gensym's process-wide flag, whose key gensym/2
%builds as '$gs_' followed by the base.
lambda_counter_value(Value) :-
    flag('$gs_lambda_', Value, Value).

cleanup_generated_lambdas(First) :-
    lambda_counter_value(Last),
    Start is First + 1,
    forall(between(Start, Last, Number),
           ( format(atom(Name), 'lambda_~d', [Number]),
             metta_self_module(M), forget_symbol(M, Name) )).

test(typed_argument_is_compiled_once) :-
    lambda_counter_value(Before),
    setup_call_cleanup(
        true,
        ( translate_expr(
              [plunit_typed_once, ['|->', [X], ['+', X, 1]], 41],
              _Goals, _Out),
          lambda_counter_value(After),
          After - Before =:= 1 ),
        cleanup_generated_lambdas(Before)).

:- end_tests(translator_typed_single_pass).

:- begin_tests(translator_typed_checks,
               [ setup(setup_typed_checks),
                 cleanup(cleanup_typed_checks) ]).

typed_check_fact(plunit_typed_x, plunit_a).
typed_check_fact(plunit_typed_y, plunit_b).
typed_check_fact([plunit_typed_x, plunit_typed_y],
                 [plunit_a, plunit_b]).
typed_check_fact(plunit_multi_type, plunit_a).
typed_check_fact(plunit_multi_type, plunit_b).
typed_check_fact(plunit_only_b, plunit_b).

setup_typed_checks :-
    cleanup_typed_checks,
    forall(typed_check_fact(Term, Type),
           add_sexp('&self', [':', Term, Type])),
    add_sexp('&self',
             [':', plunit_same_type,
              [->, Shared, Shared, 'Number']]),
    assertz(user:fun(plunit_same_type)),
    assertz(user:arity(plunit_same_type, 3)),
    assertz(user:plunit_same_type(_, _, 1)).

cleanup_typed_checks :-
    forall(typed_check_fact(Term, _),
           remove_sexp('&self', [':', Term, _])),
    remove_sexp('&self', [':', plunit_same_type, _]),
    retractall(user:plunit_same_type(_, _, _)),
    retractall(user:arity(plunit_same_type, _)),
    retractall(user:fun(plunit_same_type)).

test(argument_checks_do_not_multiply_duplicate_derivations) :-
    Expr = [plunit_typed_x, plunit_typed_y],
    translate_expr([plunit_same_type, Expr, Expr], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    findall(Out, call(Goal), Answers),
    Answers == [1].

test(shared_type_variables_can_reach_a_later_consistent_type) :-
    translate_expr([plunit_same_type, plunit_multi_type, plunit_only_b],
                   Goals, Out),
    goals_list_to_conj(Goals, Goal),
    findall(Out, call(Goal), Answers),
    Answers == [1].

% Where the OUTPUT shares a type variable with an argument, as in (-> $a $a),
% committing the argument check before the call picks a witness the output
% cannot satisfy: with (: at A), (: at T), (: t T) and (= (testf at) t), the
% argument check binds $a to A and the answer t, of type T, is rejected. Both
% halves have to solve together, after the call.
test(a_shared_type_variable_is_assigned_after_the_call,
     [ setup(( add_sexp('&self', [':', plunit_at, 'PlunitA']),
               add_sexp('&self', [':', plunit_at, 'PlunitT']),
               add_sexp('&self', [':', plunit_t, 'PlunitT']),
               add_sexp('&self', [':', plunit_testf, [->, Shared, Shared]]),
               assertz(user:fun(plunit_testf)),
               assertz(user:arity(plunit_testf, 2)),
               assertz(user:plunit_testf(_, plunit_t)) )),
       cleanup(( remove_sexp('&self', [':', plunit_at, _]),
                 remove_sexp('&self', [':', plunit_t, _]),
                 remove_sexp('&self', [':', plunit_testf, _]),
                 retractall(user:plunit_testf(_, _)),
                 retractall(user:arity(plunit_testf, _)),
                 retractall(user:fun(plunit_testf)) )) ]) :-
    translate_expr([plunit_testf, plunit_at], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    findall(Out, call(Goal), Answers),
    % PlunitT is the assignment that satisfies both ends. Committing to
    % PlunitA first, which is the type the argument happens to match earliest,
    % answered nothing at all.
    assertion(Answers == [plunit_t]).

:- end_tests(translator_typed_checks).

:- begin_tests(translator_type_extensions).

test(get_type_equations_compile_behind_the_answer_boundary) :-
    Source = [=, ['get-type', plunit_extended_type], plunit_extension],
    setup_call_cleanup(
        true,
        ( translate_clause(Source, Clause),
          Clause = (Head :- _),
          functor(Head, get_type_rule, 2),
          %A get-type equation compiles into the module of the space that wrote
          %it, so the clause goes where &self's equations go.
          metta_self_module(Self),
          setup_call_cleanup(
              assertz(Self:Clause, Ref),
              ( findall(Type, 'get-type'(plunit_extended_type, Type), Types),
                Types == [plunit_extension] ),
              erase(Ref)) ),
        drop_fun_meta(_, 'get-type', [plunit_extended_type],
                      plunit_extension)).

:- end_tests(translator_type_extensions).

:- begin_tests(translator_empty_forms).

empty_form_translation([superpose, []], [fail], _).
empty_form_translation(['let*', [], 42], [], 42).
empty_form_translation([case, 1, []], [fail], _).
empty_form_translation([reduce, []], [], []).
empty_form_translation([progn], [], []).

test(each_empty_special_form_has_defined_translation,
     [forall(empty_form_translation(Expr, ExpectedGoals, ExpectedOut))]) :-
    translate_expr(Expr, Goals, Out),
    Goals =@= ExpectedGoals,
    Out =@= ExpectedOut.

test(empty_reduce_is_a_value) :-
    reduce([], Out),
    Out == [].

:- end_tests(translator_empty_forms).

:- begin_tests(translator_evaluation_errors).

dynamic_arithmetic_error :-
    reduce(['+', 1, undefined_sym], _).

compiled_arithmetic_error :-
    translate_expr(['+', 1, undefined_sym], Goals, _),
    goals_list_to_conj(Goals, Conjunction),
    call(Conjunction).

captured_error(Goal, Type) :-
    catch(call(Goal), error(Type, _), true),
    nonvar(Type).

captured_operation_error(Goal, Type, Operation) :-
    catch(call(Goal), Error, true),
    nonvar(Error),
    Error = error(Type, context(Operation, _)).

test(dynamic_and_compiled_calls_report_the_same_error) :-
    captured_error(dynamic_arithmetic_error, DynamicType),
    captured_error(compiled_arithmetic_error, CompiledType),
    DynamicType == type_error(number, undefined_sym),
    CompiledType == DynamicType.

test(dynamic_and_compiled_calls_name_the_written_operation) :-
    captured_operation_error(dynamic_arithmetic_error, DynamicType,
                             DynamicOperation),
    captured_operation_error(compiled_arithmetic_error, CompiledType,
                             CompiledOperation),
    DynamicType == type_error(number, undefined_sym),
    CompiledType == DynamicType,
    DynamicOperation == '+',
    CompiledOperation == DynamicOperation.

test(dynamic_errors_are_not_converted_to_failure,
     [throws(error(type_error(number, undefined_sym), _))]) :-
    dynamic_arithmetic_error.

test(an_unknown_head_remains_inert_data) :-
    translate_expr([plunit_inert_head, 1], Goals, Out),
    Goals == [],
    Out == [plunit_inert_head, 1].

test(quote_keeps_an_invalid_builtin_call_inert) :-
    translate_expr([quote, ['+', 1, undefined_sym]], Goals, Out),
    metta_self_module(Self),
    call_goals_in_(Self, Goals),
    Out == ['+', 1, undefined_sym].

cleanup_builtin_type_declarations(Path, ParsedForms) :-
    forall(member(parsed(expression, _, Term), ParsedForms),
           remove_sexp('&self', Term)),
    retractall(compiled_metta_source(Path)),
    retractall(imported_metta_source('&self', Path)),
    retractall(import_life('&self', Path, _)).

test(builtin_type_import_keeps_runtime_errors_loud) :-
    once(( absolute_file_name('../../lib/lib_builtin_types.metta', Path,
                              [access(read)]),
           read_metta_source(Path, Source),
           parse_metta_source(Source, ParsedForms) )),
    setup_call_cleanup(
        once(load_metta_file(Path, _)),
        once(( captured_operation_error(compiled_arithmetic_error,
                                        ArithmeticType,
                                        ArithmeticOperation),
               ArithmeticType == type_error(number, undefined_sym),
               ArithmeticOperation == '+',
               translate_expr([and, true, 5], BoolGoals, _),
               goals_list_to_conj(BoolGoals, BoolGoal),
               captured_operation_error(BoolGoal, BoolType, BoolOperation),
               BoolType == type_error(boolean, 5),
               BoolOperation == and,
               translate_expr(['min-atom', 5], MinGoals, MinOut),
               goals_list_to_conj(MinGoals, MinGoal),
               call(MinGoal),
               MinOut == [] )),
        cleanup_builtin_type_declarations(Path, ParsedForms)).

:- end_tests(translator_evaluation_errors).

:- begin_tests(translator_terminal_output).

test(nonterminal_compiler_output_has_no_ansi_escapes) :-
    with_output_to(string(Output),
                   maybe_print_compiled_clause(test_label,
                                               [=, [f, x], x],
                                               (f(X, X) :- true))),
    once(sub_string(Output, _, _, _, "-->  test_label  -->")),
    \+ sub_string(Output, _, _, _, "\e[").

:- end_tests(translator_terminal_output).

:- begin_tests(translator_test_answers).

test(one_empty_expression_answer_is_a_value) :-
    translate_expr([test, [quote, []], []], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    with_output_to(string(Output), call(Goal)),
    Out == true,
    Output == "is (), should (). ✅ \n".

test(no_answer_is_not_an_empty_expression,
     [throws(error(petta_test_no_answer, _))]) :-
    translate_expr([test, [empty], []], Goals, _),
    goals_list_to_conj(Goals, Goal),
    call(Goal).

test(explicit_no_answer_assertion_keeps_the_existing_output) :-
    translate_expr(['test-no-answer', [empty]], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    with_output_to(string(Output), call(Goal)),
    Out == true,
    Output == "is (), should (). ✅ \n".

test(explicit_no_answer_rejects_an_empty_value,
     [throws(error(petta_test_failed([[]], []), _))]) :-
    translate_expr(['test-no-answer', [quote, []]], Goals, _),
    goals_list_to_conj(Goals, Goal),
    with_output_to(string(_), call(Goal)).

:- end_tests(translator_test_answers).

:- begin_tests(translator_sealed).

% sealed had NO test and NO example anywhere in the tree, and the case it
% exists for did not work: the rename was emitted as a runtime goal over the
% already-translated body, so an outer binding had already bound the variable
% and there was nothing left to rename.

% The canonical use. Without the compile-time rename this had no answer at all,
% because the inner let ran as (let 1 2 1).
test(a_sealed_variable_shadows_an_outer_binding) :-
    findall(V, eval([let, X, 1, [sealed, [X], [let, X, 2, X]]], V), Answers),
    Answers == [2].

test(a_sealed_variable_is_local_to_its_expression) :-
    findall(V, eval([sealed, [Y], [let, Y, 5, Y]], V), Answers),
    Answers == [5].

% Only the listed variables are renamed. Everything else stays shared, which is
% what copy_term/4 gives and what makes sealed useful rather than a full copy.
test(an_unlisted_variable_stays_shared) :-
    findall(V, eval([let, Z, 7, [sealed, [_W], [Z, _]]], V), Answers),
    Answers = [[7, Fresh]],
    var(Fresh).

test(sealing_nothing_is_the_expression_itself) :-
    findall(V, eval([sealed, [], 42], V), Answers),
    Answers == [42].

% sealed and lambda are the same operation, capture-avoiding renaming, in two
% places: a lambda renames its BINDERS on every application, sealed renames
% variables you NAME in an atom that has no binders. So a sealed variable
% inside a lambda body is not free in that lambda and must not be captured.
% It was: (= (mk) (|-> ($a) (sealed ($v) (pair $a $v)))) compiled mk to arity
% 2 while every call was arity 1, which made the function uncallable.
test(a_lambda_does_not_capture_a_sealed_variable) :-
    sread("(= (plunit-seal-mk) (|-> ($a) (sealed ($v) (pair $a $v))))", Term),
    translate_clause(Term, (Head :- _)),
    functor(Head, _, Arity),
    Arity == 1.

% An ordinary free variable IS still captured, so this stays arity 3 rather
% than 2: a function whose body is a partial application is eta-expanded, and
% the captured $k, the lambda's own parameter and the output are all arguments.
% That is the difference the test above measures. Before the fix the sealed
% version was arity 3 too, and ((plunit-seal-mk) 1) raised "Unknown procedure:
% plunit-seal-mk/1"; it answers (pair 1 $_) now.
test(a_lambda_still_captures_an_ordinary_free_variable) :-
    sread("(= (plunit-seal-cap $k) (|-> ($a) (pair $a $k)))", Term),
    translate_clause(Term, (Head :- _)),
    functor(Head, _, Arity),
    Arity == 3.

% Freshness per application comes from the clause mechanism rather than from
% any copying here: "Variables are local to a clause ... ensured by renaming
% the variables appearing in a clause each time the clause is chosen to effect
% a reduction" [The Art of Prolog, section 4, The Computation Model].
test(each_application_gets_its_own_sealed_variable) :-
    findall(V, eval([let, F, ['|->', [A], [sealed, [S], [tagged, A, S]]],
                     [superpose, [[F, 1], [F, 2]]]], V), Answers),
    Answers = [[tagged, 1, One], [tagged, 2, Two]],
    var(One), var(Two), One \== Two.

:- end_tests(translator_sealed).

:- begin_tests(translator_occurs_checks).

% A let unifies under an occurs check so a binding cannot build a term
% containing itself. The check is only capable of firing when the pattern
% variable could already be inside the value, and it walks the WHOLE value, so
% where it is left standing naming a term costs time proportional to that
% term's size. These tests pin which ones are demoted to =/2 and which stay.

body_of(Source, Body) :-
    sread(Source, Term),
    translate_clause(Term, (_ :- Body)).

% The pattern variable is fresh here, so it cannot be inside the value and the
% check cannot fail. Measured 2026-08-15: a let* chain of four bindings over a
% 2000 element list, 20,000 times, went from 0.8730s to 0.0026s, and became
% flat in the list's size rather than linear in it.
test(a_fresh_pattern_variable_is_demoted) :-
    body_of("(= (plunit-uwoc-fresh $l) (let $y $l (car-atom $y)))", Body),
    Body = (Bind, _),
    Bind = (_ = _).

% The pattern variable comes from the HEAD, so the caller may already have put
% it inside the value: (f $z (g $z)) makes the binding cyclic. The check stays.
test(a_head_variable_keeps_its_check) :-
    body_of("(= (plunit-uwoc-head $y $l) (let $y $l (car-atom $y)))", Body),
    once(( sub_term(Goal, Body), nonvar(Goal),
           Goal = unify_with_occurs_check(_, _) )).

% The end to end behaviour the check exists for. This must have no answers.
test(a_self_referential_binding_is_still_refused) :-
    findall(X, eval([let, X, ['cons-atom', X, []], X], _), Answers),
    Answers == [].

test(an_ordinary_binding_still_works) :-
    findall(V, eval([let, V, 5, V], _), Answers),
    Answers == [5].

:- end_tests(translator_occurs_checks).

:- begin_tests(translator_branch_returns).

test(build_branch_without_goals_unifies_at_runtime) :-
    build_branch(true, Value, Out, Branch),
    Value \== Out,
    Branch == (Out = Value).

test(build_branch_keeps_variable_value_private_until_runtime) :-
    build_branch(produce(Value), Value, Out, Branch),
    Value \== Out,
    Branch == (produce(Value), Out = Value).

test(build_branch_moves_a_ground_value_before_its_goals) :-
    build_branch(check_value, answer, Out, Branch),
    Branch == (answer = Out, check_value).

test(private_branch_return_is_merged) :-
    Head = branch_private(Input, Out),
    Body0 = (guard -> (produce(Input, Value), Out = Value) ; Out = none),
    merge_branch_returns(Head, Body0, Body),
    Value == Out,
    Body == (guard -> produce(Input, Out) ; Out = none).

test(head_parameter_is_not_merged) :-
    Head = branch_head(Value, Out),
    Body0 = (guard -> (produce(Value), Out = Value) ; Out = none),
    merge_branch_returns(Head, Body0, Body),
    Value \== Out,
    Body == Body0.

test(value_used_outside_its_branch_is_not_merged) :-
    Head = branch_shared(Out),
    Body0 = (guard -> (produce(Value), Out = Value) ; consume(Value)),
    merge_branch_returns(Head, Body0, Body),
    Value \== Out,
    Body == Body0.

%The generator fuzzer found this third condition: a value produced before the
%conditional is not private to either arm, even when one arm returns it.
test(value_produced_before_the_branch_is_not_merged) :-
    Head = branch_prebound(Input, Out),
    Body0 = (produce(Input, Value),
             (guard -> Out = Value ; Out = none)),
    merge_branch_returns(Head, Body0, Body),
    Value \== Out,
    Body == Body0.

test(nested_alternatives_can_produce_one_private_return) :-
    Head = branch_nested(Out),
    Body0 = (guard -> ((choice -> left(Value) ; right(Value)),
                       Out = Value)
                   ; Out = none),
    merge_branch_returns(Head, Body0, Body),
    Value == Out,
    Body == (guard -> (choice -> left(Out) ; right(Out)) ; Out = none).

%The body is built outside the measurement, so this reads merge_branch_returns/3
%alone rather than the translation that produced its input.
merge_cost(Depth, Inferences) :-
    nested_conditional(Depth, Expr),
    translate_expr(Expr, Goals, Out),
    goals_list_to_conj(Goals, Body),
    %min_inferences/2 cannot serve here: merge_branch_returns/3 binds the
    %returns inside the body it walks, so each sample needs a fresh copy, and
    %the copy has to be made OUTSIDE the counter because copying costs more
    %the deeper the body is, which is the very thing being measured.
    findall(Sample,
            ( between(1, 3, _),
              copy_term(branch_depth(input, Out)-Body, Head-Copy),
              count_inferences(merge_branch_returns(Head, Copy, _), Sample) ),
            Samples),
    min_list(Samples, Inferences).

% The merge carries its candidate returns in an assoc, an AVL tree, so a body
% nested n deep costs about n log n [source 2026-08-14:
% https://www.swi-prolog.org/pldoc/doc/_SWI_/library/assoc.pl]. Held against
% quadratic rather than against linear, because linear is not what an assoc
% gives and asserting it would be a test that has to be relaxed the first time
% someone reads it. A list-backed store, which is the regression the assoc
% exists to prevent, costs 4x per doubling and fails this.
%
% Measured 2026-08-18, min of three: 14,938 inferences at depth 50, 31,909 at
% 100, 67,844 at 200 and 143,715 at 400. Each doubling costs 2.11x to 2.14x,
% against 2.26x for exact n log n at these depths and 4x for quadratic.
test(merging_stays_far_from_quadratic_in_nesting_depth) :-
    merge_cost(100, Small),
    merge_cost(200, Large),
    Large > Small,
    Large < 3 * Small.

:- end_tests(translator_branch_returns).

% A runnable is compiled whole before any of it runs, so an import written in
% the same runnable as a call to what it imports cannot affect its own
% compilation: the call compiled while the name was unregistered, fell through
% to data dispatch, and the runnable answered the expression rather than the
% value. Both C-extension examples in the tree carry a comment telling the next
% reader to split the runnable, which is the shape of a trap.
:- begin_tests(translator_own_import,
               [ cleanup(( retractall(user:runnable_import(_)),
                           retractall(user:fun('plunit-own-import')) )) ]).

own_import_runnable(Importer, Expr) :-
    prolog_function_importer(Importer),
    Expr = [progn,
            [Importer, "some.pl", ['plunit-own-import']],
            ['plunit-own-import', 1]].

test(a_call_to_a_name_this_runnable_imports_is_refused,
     [ forall(own_import_runnable(_, Expr)),
       throws(error(petta_call_to_own_import('plunit-own-import'), _)) ]) :-
    translate_runnable_expr(Expr, _, _).

test(the_import_alone_is_fine) :-
    translate_runnable_expr(
        [import_prolog_functions_from_file, "some.pl", ['plunit-own-import']],
        _, _).

test(a_call_to_an_ALREADY_registered_name_is_fine,
     [ setup(assertz(user:fun('plunit-own-import'))),
       cleanup(retractall(user:fun('plunit-own-import'))) ]) :-
    % Re-importing a name that already resolves is ordinary: the call compiles
    % to a real call, so there is nothing to warn about.
    translate_runnable_expr(
        [progn,
         [import_prolog_functions_from_file, "some.pl", ['plunit-own-import']],
         ['plunit-own-import', 1]],
        _, _).

test(an_ordinary_runnable_records_no_import) :-
    translate_runnable_expr([progn, [+, 1, 2]], _, _),
    \+ user:runnable_import(_).

:- end_tests(translator_own_import).

:- begin_tests(translator_lambda_space_scope).

%A lambda's body is compiled into a clause of its own, and that clause has to
%land where the lambda was written. A bare assertz/2 puts it in `user`, and a
%module inherits from `user` rather than the reverse, so the body could not
%see the space it was written in.
lambda_scope_space('&plunit_lambda_scope').
lambda_scope_other('&plunit_lambda_other').

lambda_scope_definition(Space, Factor, Definition) :-
    format(atom(Text), "(= (plunit-lambda-local $x) (* $x ~d))", [Factor]),
    sread(Text, Definition),
    'add-atom'(Space, Definition, _).

setup_lambda_scope :-
    retractall(silent(_)),
    assertz(silent(true)),
    lambda_scope_space(Space),
    lambda_scope_definition(Space, 2, _).

cleanup_lambda_scope :-
    lambda_scope_space(Space),
    forall(( 'get-atoms'(Space, Atom),
             Atom = [=, ['plunit-lambda-local'|_], _] ),
           'remove-atom'(Space, Atom, _)),
    retractall(silent(_)),
    assertz(silent(false)).

test(a_lambda_reaches_the_space_local_function_it_names,
     [setup(setup_lambda_scope), cleanup(cleanup_lambda_scope)]) :-
    lambda_scope_space(Space),
    process_metta_string("!(map-atom (1 2 3) $x (plunit-lambda-local $x))",
                         Results, Space),
    Results == [[2, 4, 6]].

%Every lambda form shares the one '|->' clause, so each is checked rather than
%assumed from the one above.
lambda_scope_form("!(map-atom (1 2 3) $x (plunit-lambda-local $x))", [2, 4, 6]).
lambda_scope_form("!(filter-atom (1 2 3) $x (> (plunit-lambda-local $x) 2))",
                  [2, 3]).
lambda_scope_form("!(foldl-atom (1 2 3) 0 $a $x (+ $a (plunit-lambda-local $x)))",
                  12).
lambda_scope_form("!((|-> ($y) (plunit-lambda-local $y)) 21)", 42).

test(every_lambda_form_reaches_the_space_it_was_written_in,
     [ forall(lambda_scope_form(Source, Expected)),
       setup(setup_lambda_scope), cleanup(cleanup_lambda_scope) ]) :-
    lambda_scope_space(Space),
    process_metta_string(Source, Results, Space),
    Results == [Expected].

test(the_lambda_clause_is_not_in_user,
     [setup(setup_lambda_scope), cleanup(cleanup_lambda_scope)]) :-
    lambda_scope_space(Space),
    space_module(Space, Module),
    process_metta_string("!(map-atom (1 2) $x (plunit-lambda-local $x))",
                         _, Space),
    findall(Name, ( fun_in(Module, Name),
                    sub_atom(Name, 0, 7, _, lambda_) ), Names),
    Names \== [],
    forall(member(Name, Names),
           ( arity(Name, Arity),
             functor(Head, Name, Arity),
             \+ catch(nth_clause(user:Head, 1, _), _, fail),
             catch(nth_clause(Module:Head, 1, _), _, fail) )).

%F6.2: the same lambda text, in two spaces, over two different definitions of
%the name it calls. Each has to answer its own.
test(two_spaces_compiling_the_same_lambda_do_not_share_it,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(( member(S, ['&plunit_lambda_scope',
                                     '&plunit_lambda_other']),
                          'get-atoms'(S, Atom),
                          Atom = [=, ['plunit-lambda-local'|_], _] ),
                        'remove-atom'(S, Atom, _)),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    lambda_scope_space(One),
    lambda_scope_other(Other),
    lambda_scope_definition(One, 2, _),
    lambda_scope_definition(Other, 10, _),
    Source = "!(map-atom (1 2 3) $x (plunit-lambda-local $x))",
    process_metta_string(Source, OneResults, One),
    process_metta_string(Source, OtherResults, Other),
    OneResults == [[2, 4, 6]],
    OtherResults == [[10, 20, 30]].

:- end_tests(translator_lambda_space_scope).

:- begin_tests(translator_literal_type_checks).

%A literal's type is settled while the call site is compiled, so the check
%emitted for it can only succeed. Dropping it is only sound in that direction:
%it must never decide a literal FAILS a type, because a get-type extension may
%give one a second type.
literal_check_source("
(: tlc-sq (-> Number Number))
(= (tlc-sq $x) (* $x $x))
(: tlc-tag (-> String Number Bool))
(= (tlc-tag $s $n) true)
(: tlc-flag (-> Bool Bool))
(= (tlc-flag $b) $b)
(: tlc-id (-> $t $t))
(= (tlc-id $x) $x)
(: tlc-sym Bool)").

setup_literal_checks :-
    retractall(silent(_)), assertz(silent(true)),
    literal_check_source(Source),
    process_metta_string(Source, _).

cleanup_literal_checks :-
    forall(member(F, ['tlc-sq', 'tlc-tag', 'tlc-flag', 'tlc-id']),
           ( 'remove-atom'('&self', [':', F, _], _),
             'remove-atom'('&self', [=, [F|_], _], _),
             forget_test_function(F) )),
    'remove-atom'('&self', [':', 'tlc-sym', _], _),
    retractall(silent(_)), assertz(silent(false)).

%Every literal a type is decided for, and one of each that is not.
dropped_check("(tlc-sq 4)").
dropped_check("(tlc-tag \"a\" 1)").
dropped_check("(tlc-flag true)").
dropped_check("(tlc-flag false)").

test(a_literal_argument_compiles_no_type_check,
     [ forall(dropped_check(Call)),
       setup(setup_literal_checks), cleanup(cleanup_literal_checks) ]) :-
    sread(Call, Term),
    translate_runnable_expr(Term, Goals, _),
    term_string(Goals, Text),
    \+ sub_string(Text, _, _, _, "has_type(4"),
    \+ sub_string(Text, _, _, _, "has_type(\"a\""),
    \+ sub_string(Text, _, _, _, "has_type(true"),
    \+ sub_string(Text, _, _, _, "has_type(false").

test(an_unknown_argument_keeps_its_check,
     [setup(setup_literal_checks), cleanup(cleanup_literal_checks)]) :-
    sread("(tlc-sq $x)", Term),
    translate_runnable_expr(Term, Goals, _),
    term_string(Goals, Text),
    once(sub_string(Text, _, _, _, "has_type")).

%A check that cannot be dropped is SPECIALISED instead: the declared type is a
%compile-time constant, and three of them are decided by one Prolog builtin.
%The check still has to be there, so both are asserted, and the emitted text is
%what says the fast test is in FRONT rather than merely present somewhere.
specialised_check("(tlc-sq $x)",   "number(").
specialised_check("(tlc-tag $s 1)", "string(").
specialised_check("(tlc-flag $b)", "==true").

test(an_intrinsic_type_check_is_specialised,
     [ forall(specialised_check(Call, Fast)),
       setup(setup_literal_checks), cleanup(cleanup_literal_checks) ]) :-
    sread(Call, Term),
    translate_runnable_expr(Term, Goals, _),
    term_string(Goals, Spaced),
    split_string(Spaced, " ", " ", Pieces),
    atomic_list_concat(Pieces, Text),
    once(sub_atom(Text, FastAt, _, _, Fast)),
    once(sub_atom(Text, SlowAt, _, _, has_type)),
    assertion(FastAt < SlowAt).

%The one that would break under a cut instead of a fall-through. number/1 is
%SOUND for has_type/2 and not complete: `(: tlc-sym Bool)` makes
%has_type(tlc-sym, 'Bool') true while the intrinsic test says nothing, so the
%general check behind it is what still answers. It has to run in both
%positions here, since tlc-sym is the argument AND the result.
%The refusal is checked with a symbol declared to be something ELSE, not with
%an undeclared one. An undeclared symbol has type %Undefined%, which is
%consistent with every type under the gradual rule, so both arbiters admit it:
%measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
%interpreter, byte-identical across both, `(: bflag (-> Bool Atom))` gives
%`!(bflag nope)` = `(gotb nope)` while `!(bflag 7)` is
%`(BadArgType 1 Bool Number)`. This test asserted the `nope` case as a refusal
%until then, which pinned a stricter rule than either reference has.
test(a_symbol_declared_with_an_intrinsic_type_still_passes,
     [setup(setup_literal_checks), cleanup(cleanup_literal_checks)]) :-
    process_metta_string("!(collapse (tlc-flag tlc-sym))", Results),
    assertion(Results == [['tlc-sym']]),
    process_metta_string("(: tlc-other TlcOther)", _),
    process_metta_string("!(collapse (tlc-flag tlc-other))", Refused),
    assertion(Refused == [[]]),
    'remove-atom'('&self', [':', 'tlc-other', _], _),
    process_metta_string("!(collapse (tlc-flag 7))", RefusesNumber),
    assertion(RefusesNumber == [[]]).

%A parametric declaration leaves the type an unbound VARIABLE at compile time,
%and intrinsic_type_test/3's head would bind it to 'Number' and emit a number/1
%test for a type nobody wrote. The nonvar/1 guard is what stops it, and this is
%what says so.
test(a_parametric_type_is_not_specialised,
     [setup(setup_literal_checks), cleanup(cleanup_literal_checks)]) :-
    sread("(tlc-id $x)", Term),
    translate_runnable_expr(Term, Goals, _),
    term_string(Goals, Text),
    assertion(\+ sub_string(Text, _, _, _, "number(")),
    assertion(\+ sub_string(Text, _, _, _, "string(")),
    process_metta_string("!(collapse (tlc-id foo))", Results),
    assertion(Results == [[foo]]).

%The drop is one-directional: a literal of the WRONG type keeps its check and
%is still refused at run time.
refused_call("(tlc-sq \"s\")").
refused_call("(tlc-sq true)").
refused_call("(tlc-tag 1 \"a\")").
refused_call("(tlc-flag 1)").

test(a_literal_of_the_wrong_type_is_still_refused,
     [ forall(refused_call(Call)),
       setup(setup_literal_checks), cleanup(cleanup_literal_checks) ]) :-
    format(atom(Source), "!(collapse ~w)", [Call]),
    process_metta_string(Source, Results),
    Results == [[]].

test(a_literal_of_the_right_type_still_answers,
     [setup(setup_literal_checks), cleanup(cleanup_literal_checks)]) :-
    process_metta_string("!(collapse (tlc-sq 4))", Results),
    Results == [[16]].

%The drop must not BIND what it is inspecting. Written with the literal in the
%head, `intrinsic_literal_type(true, 'Bool')` unifies with an unbound Value and
%binds it, and the thing it binds is the call site's compile-time variable: the
%clause for a caller of a Bool-typed function compiled as `f(true, A, B)` and
%`(f False ...)` then matched nothing and answered nothing. The shape needs a
%Bool, Number or String parameter reached from ANOTHER function's body with a
%variable, which no example in the corpus had.
frozen_parameter_case("(: tfp-bool (-> Bool Atom Bool))",
                      "(= (tfp-bool $b $rest) $b)",
                      "(= (tfp-via $x $y) (tfp-bool $x $y))",
                      "!(collapse (tfp-via False anything))", [[false]]).
frozen_parameter_case("(: tfp-num (-> Number Number))",
                      "(= (tfp-num $n) $n)",
                      "(= (tfp-nvia $x) (tfp-num $x))",
                      "!(collapse (tfp-nvia 7))", [[7]]).
frozen_parameter_case("(: tfp-str (-> String String))",
                      "(= (tfp-str $s) $s)",
                      "(= (tfp-svia $x) (tfp-str $x))",
                      "!(collapse (tfp-svia \"z\"))", [["z"]]).

test(a_typed_parameter_is_not_frozen_at_compile_time,
     [ forall(frozen_parameter_case(Decl, Def, Caller, Call, Expected)),
       setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(member(F, ['tfp-bool', 'tfp-num', 'tfp-str',
                                   'tfp-via', 'tfp-nvia', 'tfp-svia']),
                        ( 'remove-atom'('&self', [':', F, _], _),
                          'remove-atom'('&self', [=, [F|_], _], _),
                          forget_test_function(F) )),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    format(atom(Source), "~w~n~w~n~w~n", [Decl, Def, Caller]),
    process_metta_string(Source, _),
    process_metta_string(Call, Results),
    Results == Expected.

:- end_tests(translator_literal_type_checks).

:- begin_tests(translator_match_modifiers).

%(:= X) in a match pattern is the match-by-EQUALITY modifier. Lifted at
%compile time: the position becomes a fresh variable so the space read keeps
%its ordinary shape, and the equality is a ==/2 goal after the match.
setup_match_modifiers :-
    retractall(silent(_)), assertz(silent(true)),
    'add-atom'('&self', ['plunit-mod-fact', a], _),
    'add-atom'('&self', ['plunit-mod-fact', b], _),
    'add-atom'('&self', ['plunit-mod-holds', [':=', p, q]], _).

cleanup_match_modifiers :-
    forall(( 'get-atoms'('&self', Atom),
             ( Atom = ['plunit-mod-fact'|_] ; Atom = ['plunit-mod-holds'|_] ) ),
           'remove-atom'('&self', Atom, _)),
    retractall(silent(_)), assertz(silent(false)).

modifier_case("(match &self (plunit-mod-fact $x) $x)",        [a, b]).
modifier_case("(match &self (plunit-mod-fact (:= a)) hit)",   [hit]).
modifier_case("(match &self (plunit-mod-fact (:= c)) hit)",   []).
%A free variable does not match a := operand, which is the whole point.
modifier_case("(let $y (superpose ($z)) \c
                (match &self (plunit-mod-fact (:= $y)) hit))", []).
%THE ARITY GATE. Three elements stay data and match structurally, which
%examples/libraries/minimal_metta.metta already asserts for unify-mod.
modifier_case("(match &self (plunit-mod-holds (:= $m $n)) ($m $n))", [[p, q]]).

test(a_match_pattern_honours_the_equality_modifier,
     [ forall(modifier_case(Call, Expected)),
       setup(setup_match_modifiers), cleanup(cleanup_match_modifiers) ]) :-
    format(atom(Source), "!(collapse ~w)", [Call]),
    process_metta_string(Source, Results),
    Results == [Expected].

%A pattern with no modifier compiles to exactly what it always did, so the
%space read pays nothing for a feature it is not using.
test(a_pattern_without_a_modifier_is_unchanged) :-
    lift_pattern_modifiers([fact, X, [inner, Y]], Lifted, Guards),
    Lifted == [fact, X, [inner, Y]],
    Guards == [].

test(the_modifier_position_becomes_a_variable_and_the_equality_a_guard) :-
    lift_pattern_modifiers([fact, [':=', a]], Lifted, Guards),
    Lifted = [fact, Fresh],
    var(Fresh),
    Guards = [Fresh0 == a],
    Fresh0 == Fresh.

:- end_tests(translator_match_modifiers).

:- begin_tests(translator_capturing_lambda_curries).

%A function whose body is a CAPTURING lambda is eta-expanded, so its compiled
%clause takes more arguments than its equation's head. The arity registered
%from the source shape then named a predicate that never existed, and the
%capturing case raised `Unknown procedure` where the non-capturing one curried.
capturing_source("
(= (plunit-pfree) (|-> ($a) (solo $a)))
(= (plunit-pcap $k) (|-> ($a) (pair $a $k)))").

setup_capturing :-
    retractall(silent(_)), assertz(silent(true)),
    capturing_source(Source),
    process_metta_string(Source, _).

%The compiled clause has to go too. forget_symbol/2 removes the registration
%and not the predicate, so a second setup in the same process compiled a
%SECOND plunit-pcap/3 clause and the fully applied call then answered twice.
cleanup_capturing :-
    forall(member(F, ['plunit-pfree', 'plunit-pcap']),
           ( 'remove-atom'('&self', [=, [F|_], _], _),
             forget_test_function(F) )),
    retractall(silent(_)), assertz(silent(false)).

%The non-capturing case, which always worked, and the capturing one beside it.
curry_case("(collapse ((plunit-pfree) 1))",   [[solo, 1]]).
curry_case("(collapse ((plunit-pcap 5) 1))",  [[pair, 1, 5]]).
curry_case("(collapse (plunit-pcap 5 1))",    [[pair, 1, 5]]).

test(a_capturing_lambda_curries_like_a_free_one,
     [ forall(curry_case(Call, Expected)),
       setup(setup_capturing), cleanup(cleanup_capturing) ]) :-
    format(atom(Source), "!~w", [Call]),
    process_metta_string(Source, Results),
    Results == [Expected].

%Under-applied, it answers the residual closure that partial/2 exists for
%rather than raising.
test(an_under_applied_capturing_function_answers_a_closure,
     [setup(setup_capturing), cleanup(cleanup_capturing)]) :-
    process_metta_string("!(collapse (plunit-pcap 5))", Results),
    Results = [[partial('plunit-pcap', [5])]].

%The superseded arity is dropped, the compiled one kept.
test(only_the_compiled_arity_stays_registered,
     [setup(setup_capturing), cleanup(cleanup_capturing)]) :-
    findall(A, user:arity('plunit-pcap', A), Arities),
    sort(Arities, Sorted),
    Sorted == [3].

:- end_tests(translator_capturing_lambda_curries).

:- begin_tests(translator_inplace_annotations).

%hyperon-experimental issue #177's dynamic half: a type where it can PRUNE, in
%a head or a match query rather than only in a top-level declaration. The
%spelling is `:` and not `:`, and the corpus is what decides that: see the
%collision test at the end.
annotation_source("
(: ann-Ann Person)
(: ann-Ann Employee)
(: ann-Bob Person)
(: ann-Rex Dog)
(= (ann-only-person (: $x Person)) $x)
(= (ann-type-of (: $x $t)) $t)
(= (ann-same-kind (: $x $t) (: $y $t)) ($x $y))
(= (ann-fmap $f (: $c Symbol)) ($f $c))").

setup_annotations :-
    retractall(silent(_)), assertz(silent(true)),
    annotation_source(Source),
    process_metta_string(Source, _).

cleanup_annotations :-
    forall(member(F, ['ann-only-person', 'ann-type-of', 'ann-same-kind',
                      'ann-fmap']),
           ( 'remove-atom'('&self', [=, [F|_], _], _),
             forget_test_function(F) )),
    forall(( 'get-atoms'('&self', Atom), Atom = [':', N, _],
             atom(N), sub_atom(N, 0, 4, _, 'ann-') ),
           'remove-atom'('&self', Atom, _)),
    retractall(silent(_)), assertz(silent(false)).

%Issue #177's own fixtures, each measured before it was written here.
annotation_case("(ann-only-person ann-Ann)",           ['ann-Ann']).
annotation_case("(ann-only-person ann-Rex)",           []).
annotation_case("(ann-type-of ann-Ann)",               ['Person', 'Employee']).
annotation_case("(ann-type-of ann-Rex)",               ['Dog']).
annotation_case("(ann-same-kind ann-Ann ann-Bob)",     [['ann-Ann', 'ann-Bob']]).
annotation_case("(ann-same-kind ann-Ann ann-Rex)",     []).
annotation_case("(ann-fmap g sym)",                    [[g, sym]]).
annotation_case("(ann-fmap g 42)",                     []).

test(an_annotated_head_parameter_restricts_and_binds,
     [ forall(annotation_case(Call, Expected)),
       setup(setup_annotations), cleanup(cleanup_annotations) ]) :-
    format(atom(Source), "!(collapse ~w)", [Call]),
    process_metta_string(Source, Results),
    Results == [Expected].

%The same in a match query, issue #177's third fixture, including the
%shared-type-variable form that constrains two positions to agree.
test(a_match_pattern_restricts_by_type,
     [ setup(( setup_annotations,
               'add-atom'('&self', ['ann-knows', 'ann-Ann', 'ann-Bob'], _),
               'add-atom'('&self', ['ann-knows', 'ann-Ann', 'ann-Rex'], _) )),
       cleanup(( forall(( 'get-atoms'('&self', A), A = ['ann-knows'|_] ),
                        'remove-atom'('&self', A, _)),
                 cleanup_annotations )) ]) :-
    process_metta_string(
        "!(collapse (match &self (ann-knows (: $x Person) (: $y Person)) \c
                      ($x $y)))", Restricted),
    Restricted == [[['ann-Ann', 'ann-Bob']]],
    process_metta_string(
        "!(collapse (match &self (ann-knows (: $x $t) (: $y $t)) ($x $y $t)))",
        Shared),
    Shared == [[['ann-Ann', 'ann-Bob', 'Person']]].

%THE COLLISION, and the reason the spelling is `:`. Reinterpreting `(: ...)`
%would break a program whose subject matter IS type judgements, and this tree
%has one: examples/reasoning/nilbc.metta is a backward-chaining proof search
%using `(: $proof $theorem)` in exactly the nested head and match positions a
%position gate would reinterpret. `(: ...)` still retrieves stored type atoms.
%THE SECOND COLLISION, found by the gate catching it: an annotation annotates
%a VARIABLE, so anything else in that position stays structural.
%tests/prolog/duals.plt writes `(= (pat-starts-a (: a $rest)) True)` as an
%ordinary cons-shaped pattern, and without the var/1 gate `:` would collide
%in this repository exactly as `:` does.
test(a_non_variable_in_the_annotation_position_stays_structural,
     [ setup(( retractall(silent(_)), assertz(silent(true)),
               process_metta_string(
                   "(= (ann-shape (: a $rest)) $rest)", _) )),
       cleanup(( 'remove-atom'('&self', [=, ['ann-shape'|_], _], _),
                 forget_test_function('ann-shape'),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string("!(collapse (ann-shape (: a tail)))", Matched),
    Matched == [[tail]],
    process_metta_string("!(collapse (ann-shape (: z tail)))", Unmatched),
    Unmatched == [[]].

test(a_colon_pattern_still_matches_stored_type_atoms,
     [setup(setup_annotations), cleanup(cleanup_annotations)]) :-
    process_metta_string("!(collapse (match &self (: ann-Rex $t) $t))", Results),
    Results == [['Dog']].

%THE THIRD COLLISION, and the reason the spelling is `:` rather than `::`.
%`::` is what metta-lang.dev's tutorials use as an ordinary cons constructor,
%in (= (length (:: $x $xs)) (+ 1 (length $xs))) and every list example after
%it. While `::` was the annotation, a reader following those against PeTTa got
%$xs bound to the value's TYPE and a recursion that did not terminate: the
%annotation quietly reinterpreted their data constructor.
%
%A spelling the language's own teaching material uses for something else is
%the wrong spelling however good the argument for it was. This is the
%tutorial's program, run verbatim [source: metta-lang.dev/docs/learn, Recursion
%and control].
test(a_cons_list_is_ordinary_structure,
     [ setup(( retractall(silent(_)), assertz(silent(true)),
               process_metta_string("(= (ann-length ()) 0)", _),
               process_metta_string(
                   "(= (ann-length (:: $x $xs)) (+ 1 (ann-length $xs)))", _) )),
       cleanup(( 'remove-atom'('&self', [=, ['ann-length'|_], _], _),
                 forget_test_function('ann-length'),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    process_metta_string("!(ann-length (:: A (:: B (:: C ()))))", Length),
    assertion(Length == [3]).

:- end_tests(translator_inplace_annotations).
