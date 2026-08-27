% Purpose: compile error propagation, control forms, binding forms, and special-form calls
% Assumes: engine/translator.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% Guarantees: match, unify and let classify a written gap pattern ONCE while the call site compiles and hand the plan to the door in a wrapper, so a gap-free form emits the goal it always emitted [tested: tests/prolog/segments.plt, examples/data/segments.metta; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb].
% [tested: tests/prolog/translator.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%% An evaluated operand that produced an Error finishes the call %%%
%
%`(Error <atom> <message>)` means "the interpretation is finished with error",
%so an operand whose EVALUATION produced one hands that atom on unchanged
%instead of being consumed as an ordinary value: `(== 4 (+ 1 "bad"))` is the
%inner `(Error (+ 1 "bad") (BadArgType 2 Number String))` rather than `False`,
%and a typed identity passes the same atom through
%[source: LeaTTa tests/semantics/control-stdlib/07_error.metta, STATUS
%conforms, whose probes read "A BadArgType raised while preparing a nested
%call must emerge unchanged through needs-number" and "A grounded equality
%must propagate its argument's BadArgType rather than compare it as a value";
%pinned minimal-metta.md:55-73]
%[tested: test_the_error_vocabulary_answers_what_the_arbiter_answers].
%
%An operand WRITTEN as an Error atom is data and keeps the other reading, the
%one the same file pins: `(+ (Error source message) 1)` answers
%`(BadArgType 1 Number ErrorType)`, because that refusal is decided from the
%operand's STATIC type before anything runs. The two readings separate for
%free: an operand the compiler already knows is a fixed term is not in
%Computed at all, so `assertEqual`'s unevaluated Atom operands and every
%literal keep meaning exactly what they meant.
%
%THE TEST GOES IN FRONT, and the alternative was measured rather than argued.
%Recovering the error from the FAILURE side instead -- wrapping the call in
%`( Call *-> true ; <ask whether an operand was an error> )` -- reads as free
%on the inference counter, and is not: 100,000 metacalls put a soft-cut wrapper
%at 3.00 inferences per call against a bare call's 3.00, while a test in front
%costs 2. What the counter cannot see is the CHOICE POINT the soft cut leaves,
%which also stops last-call optimisation, and on a compiled million-iteration
%loop that is the whole cost: let-heavy retires 11,744,859,430 instructions:u
%with the soft cuts and 8,794,015,276 with the tests in front, against
%8,365,651,779 with no error handling at all [measured 2026-08-22, min of
%three under the controlled harness]. So the guard is a test, and it is four
%inline goals with no choice point and no inference.
%
%What is NOT guarded is the grounded family with a runtime guard, because
%those already answer for themselves: a refused operand reaches
%metta_operation_answer/3, which hands an error operand straight back. That
%keeps every arithmetic and comparison call site exactly as it compiled before.
%
%The one exception, and it is the reason the vocabulary is usable at all: a
%combinator whose whole contract is to OBSERVE an error has to receive it as a
%value. `(if-error (needs-number (+ 1 "bad")) caught missed)` answers `caught`
%because if-error is listed here; short-circuiting its operand would answer the
%error atom instead and leave the language with no way to handle one
%[tested: bindings/python/tests/test_p3_typing_cluster.py::test_an_argument_type_fault_is_a_value_a_program_can_catch].
%
%Upstream reaches the same place by declaring these operands `Atom`, which
%stops the evaluation outright; this engine evaluates them and stops only the
%short circuit, so `(if-error (p32-f "wrong") caught missed)` still sees the
%error its operand COMPUTED rather than the unreduced call.
error_transparent_operation('if-error').
error_transparent_operation('return-on-error').
error_transparent_operation('throw').

%The mirror of the same exception, on the operand side. `catch` REIFIES a host
%exception as `(Error <type> <context>)` so a program can look inside it, which
%is why `(car-atom (catch (divide 1 0)))` answers the symbol `Error` and
%`(class-of (catch (divide 1 0)))` answers `ZeroDivisionError`
%[examples/integration/py_surface.metta:151,159]. Its answer is DATA by
%contract, not an evaluation that ended in error, so a consumer reads it
%instead of handing it on.
error_reifying_form('catch').

%An undeclared head is tested unless it is one of the operations that already
%answer for a wrong operand themselves. `runtime_type_guarded/1` is exactly
%that set: every one of them routes a refused operand through
%metta_operation_answer/3, which hands an error operand back unchanged, so
%`(+ 1 <error>)` needs no test at the call site. A head with EQUATIONS can
%return anything at all -- `(= (ignore $x) 5)` answers 5 while holding the
%error -- so its operands are tested.
undeclared_call_operands(Fun, _, []) :-
    ( error_transparent_operation(Fun) ; atom(Fun), runtime_type_guarded(Fun) ),
    !.
undeclared_call_operands(_, Computed, Computed).

%Guarded holds only UNBOUND values, because the walks that build it keep no
%other kind: a value the compiler already knows cannot become an error atom at
%run time, and a WRITTEN error atom is data whose refusal is decided from its
%static type instead.
guard_error_arguments(Guarded, Out, CallGoals, Goals0, Goals) :-
    (   Guarded == []
    ->  append(CallGoals, Goals, Goals0)
    ;   goals_list_to_conj(CallGoals, Call),
        error_argument_chain(Guarded, Out, Call, Chain),
        Goals0 = [Chain|Goals]
    ).

error_argument_chain([], _, Call, Call).
error_argument_chain([V|Vs], Out, Call, Chain) :-
    error_argument_chain(Vs, Out, Call, Rest),
    error_atom_test(V, Test),
    Chain = ( Test -> Out = V ; Rest ).

%The test READS the value and unifies nothing of it, which is what the `==`
%is for. Unifying the head instead binds a variable an ordinary expression is
%holding as data: `(\= (1 2 3) ($a 3 4))` answered `(Error 3 4)`, with `$a`
%bound to the symbol Error, in examples/libraries/roman.metta. `V` itself
%may be unbound, and then `V = [Head|_]` binds it and `Head == 'Error'` fails,
%which undoes the binding, so no nonvar/1 guard is needed in front.
error_atom_test(V, ( V = [Head|_], Head == 'Error' )).

%if compiles its own condition, so the same rule is written out for it. A
%CONDITION that produced an Error decides nothing, and if answers that atom
%rather than taking the else branch: `(if (< 1 "bad") a b)` is the inner
%`(Error (< 1 "bad") (BadArgType 2 Number String))` and not `b`. The test sits
%on the NOT-TRUE arm, so a condition that holds pays nothing for it. The
%branches are NOT guarded: a branch is the call's result, not its operand, so
%an Error there is the answer already.
guard_error_condition(Cond, CondValue, Out, Then, Else, Guarded) :-
    (   var(CondValue),
        \+ error_reifying_argument(Cond)
    ->  error_atom_test(CondValue, Test),
        Guarded = ( CondValue == true -> Then
                  ; Test -> Out = CondValue
                  ; Else )
    ;   Guarded = ( CondValue == true -> Then ; Else )
    ).

%translate_args_dl/4 with one extra output: which argument VALUES this call
%computed, and so could hold an error atom.
%
%The classification rides the walk that is already happening rather than
%walking the arguments a second time, and it decides each one by comparing the
%difference-list positions the sub-translation was handed and left behind. An
%argument translate_expr_dl/4 handed back unchanged emitted NO goal and so
%produced no value of its own: it is a variable the clause head already bound,
%a literal, or an existing partial. `Goals0 == AfterExpr` is that question
%asked exactly, in one inline comparison; a second walk asking it from the
%source term instead cost source-load 14,000 inferences and handle-round-trip
%54,000 [measured 2026-08-22, METTA_BENCHMARK_COUNTERS=1, min of three].
%
%An operand headed by an error-REIFYING form is left out: its value is data by
%contract. That test is paid only by an argument that did emit goals, which is
%the minority.
%The same walk under the callee's evaluation mask. A masked position hands the
%argument over AS WRITTEN and emits no goal, so it is never a computed value
%and can hold no error this call has to pass on, which is the same reasoning
%typed_call_operands/3 records for the declared path.
%
%The mask is consulted once per COMPILED CALL SITE rather than per argument or
%per run: the engine's declaration register is static once loaded, and
%builtin_argument_mask/3 fails on one indexed lookup for every builtin that
%masks nothing, which is nearly all of them.
translate_call_args_dl(Fun, Args, Goals0, Goals, AVs, Computed, ResultType) :-
    builtin_result_type(Fun, Args, ResultType),
    %The index is asked INLINE, so a builtin that masks nothing, which is
    %nearly all of them, pays one indexed failure and no call.
    (   atom(Fun),
        builtin_call_mask(Fun, _),
        builtin_argument_mask(Fun, Args, Types, _)
    ->  translate_masked_call_args_dl(Args, Types, Goals0, Goals, AVs, Computed)
    ;   translate_call_args_dl(Args, Goals0, Goals, AVs, Computed)
    ).

translate_masked_call_args_dl([], _, Goals, Goals, [], []).
translate_masked_call_args_dl([X|Xs], [T|Ts], Goals0, Goals, [V|Vs],
                              Computed) :-
    (   non_evaluated_parameter_type(T)
    ->  V = X,
        AfterExpr = Goals0,
        Computed = Rest
    ;   translate_eager_argument_dl(X, Goals0, AfterExpr, V),
        (   Goals0 == AfterExpr
        ->  Computed = Rest
        ;   nonvar(V)
        ->  Computed = Rest
        ;   error_reifying_argument(X)
        ->  Computed = Rest
        ;   Computed = [V|Rest]
        )
    ),
    translate_masked_call_args_dl(Xs, Ts, AfterExpr, Goals, Vs, Rest).

translate_call_args_dl([], Goals, Goals, [], []).
translate_call_args_dl([X|Xs], Goals0, Goals, [V|Vs], Computed) :-
    translate_eager_argument_dl(X, Goals0, AfterExpr, V),
    (   Goals0 == AfterExpr
    ->  Computed = Rest
    ;   nonvar(V)
    ->  Computed = Rest
    ;   error_reifying_argument(X)
    ->  Computed = Rest
    ;   Computed = [V|Rest]
    ),
    translate_call_args_dl(Xs, AfterExpr, Goals, Vs, Rest).

error_reifying_argument(X) :-
    nonvar(X), X = [Head|_], nonvar(Head), error_reifying_form(Head).

%A name alone is not enough: a user or named-space equation can override a
%builtin and must retain reflective type checks. Only the unmodified runtime
%predicate owns the complete input contract.
runtime_guarded_builtin_call(Fun) :-
    runtime_type_guarded(Fun),
    metta_self_module(Self),
    \+ fun_in(Self, Fun),
    current_metta_module(Module),
    \+ fun_in(Module, Fun).

%A special form is compiled by the translator instead of being defined by
%equations, and most are not registered as functions either: of the special
%forms, case, if, collapse, quote, sealed, once, forall, foldall, chain,
%and-then and or-else all answer false to fun/1. So "no equations" does not
%mean "nothing can prove it", and reading it that way made
%(not-provable (case 1 ((1 True)))) answer True beside its correct False
%[measured 2026-08-15]. Asked of translate_special_dl/5 rather than kept as a
%list, so a form added below is covered the day it is added.
%translate_special_dl/5 is the ENGINE's own clause table, so the module is
%asked rather than written: after Phase 11 `user` no longer means "where the
%engine's clauses are" everywhere else in the tree, and a clause/2 read that
%kept saying it would silently answer for no forms at all.
metta_special_form(Name) :-
    clause(translate_special_dl(Name, _, _, _, _), _),
    !.

%The same table, ENUMERABLE, because a reflection library wants the whole set
%and metta_special_form/1 above is the bound-name question with a cut on it.
%lib/lib_reflect.pl used to read clause(translate_special_dl(...), _) itself,
%which no surface walk can see -- the table is a term inside clause/2, not a
%call -- and which answered for no forms at all the moment the compiler's
%clauses stopped being in the module the library reads. Published as a service
%so the library asks a question instead of reading a table
%[tested: lib_reflect:special_forms_are_reported].
metta_special_form_head(Name) :-
    clause(translate_special_dl(Name, _, _, _, _), _),
    atom(Name).

%Every head the translator gives meaning to, across BOTH of its compilation
%routes. metta_special_form/1 above answers for one of them and is the
%narrower question its callers want; this is the wider one, and the
%difference is the TRANSLATOR RULES, which translate_expr_dl/4 consults one
%line before any special form or function dispatch is tried. The register is
%asked directly, so a rule the engine's prelude ships and a rule a program
%adds are both covered the moment they are registered.
%
%Written for the linter, whose possibly-undefined-reference check asks "does
%anything in the engine give this head meaning". Answering that with fun/1
%alone reported 1623 findings over this repository's examples/, 712 of them special forms
%used correctly, `if` alone accounting for 378 [measured 2026-08-17]
%[tested: test_calling_a_special_form_is_not_an_undefined_reference].
metta_translated_head(Name) :- metta_special_form(Name), !.
metta_translated_head(Name) :- translator_rule(Name, _), !.

%A head the engine will try to REDUCE from Module's view: meaning through
%the translator, or a function the module can see. A variable or compound
%head is decided at runtime by reduce/3, which reports its own outcome, so
%it counts as reducible here. Published for hosts: the run- and
%eval-status vocabularies report the branch the engine actually takes
%rather than guessing from the answer, and every binding used to carry its
%own copy of this test.
metta_reducible_head(Module, [F|_]) :-
    (   atom(F)
    ->  head_meaning_route(Module, F, _)
    ;   true
    ).

%WHICH of the two routes answered, for a caller that has to say so rather than
%only act on it. The compiler's head-pattern notes name the route in their
%message, because "it has equations" and "the translator gives it meaning" are
%different facts with different remedies. One place asks both questions, so a
%route added to either is covered wherever the pair is consulted.
head_meaning_route(_, F, translated) :- metta_translated_head(F), !.
head_meaning_route(Module, F, function) :- with_metta_module(Module, fun_here(F)).

%First-argument indexing keeps each special form independent of the number of
%other forms. A clause fails on an unsupported arity so ordinary function or
%data dispatch can still handle that expression.
%A builtin a program has taken over. The engine's own compilation of a form
%must give way to a user or named-space equation of the same name, which is the
%guard runtime_guarded_builtin_call/1 uses for the same reason.
metta_builtin_overridden(Fun) :-
    (   metta_self_module(Self), fun_in(Self, Fun)
    ->  true
    ;   current_metta_module(Module), fun_in(Module, Fun)
    ).

%THE ATOM MASK, for the two forms that are entirely about it.
%
%`Atom` in a parameter position says the argument is NOT REDUCED before the
%call, and only the compiler can act on that. The engine's declarations say so
%for both of these and the call site could not read them: `(get-metatype
%(+ 1 2))` answered Grounded where the language says Expression, and
%`(noeval (+ 1 2))` answered `(noeval 3)`
%[source: metta-lang-docs/learn__tutorials__types_basics__metatypes.md, which
%uses get-metatype as its worked example of the mask and says of the other
%"this is the way noeval function is implemented"].
%
%Compiled here rather than by honouring the declaration register wholesale,
%because several of the engine's own `Atom` declarations describe the argument
%a CALLER writes rather than the value the predicate receives: `(: maplist
%(-> Atom %Undefined% %Undefined%))` needs its closure built, not masked. The
%reasoning is at call_site_type_chains/2.
%
%A user equation still wins, the same guard runtime_guarded_builtin_call/1
%uses, so redefining either name in a program or a named space keeps working.
translate_special_dl('get-metatype', [Arg], AfterHead, Goals, Out) :-
    \+ metta_builtin_overridden('get-metatype'),
    AfterHead = ['get-metatype'(Arg, Out)|Goals].
%noeval is the mask twice: the argument is not reduced going in, and the Atom
%return type stops the answer being reduced coming out. Both are this clause.
translate_special_dl(noeval, [Arg], AfterHead, Goals, Out) :-
    \+ metta_builtin_overridden(noeval),
    AfterHead = Goals,
    Out = Arg.

translate_special_dl(superpose, [Args], AfterHead, Goals, Out) :-
    is_list(Args),
    build_superpose_branches(Args, Out, Branches),
    disj_list(Branches, Disj),
    AfterHead = [Disj|Goals].
%Empty is the branch remover: a finished result that IS the symbol Empty
%"is not returned among other results when interpreting is finished", no
%operation exempt [source: LeaTTa MettaHyperonFull/Minimal/
%Interpreter.lean:3090, quoting the pinned minimal-metta.md]. Every
%runnable and every collapse aggregates here, so this is the door. A
%literal value decides at compile time and pays nothing; a computed
%value keeps the findall EXACTLY as it always compiled and prunes the
%collected list afterwards. The filter deliberately does NOT ride inside
%the findall goal: wrapping the conjunction changed the goal's compiled
%shape and cost nilbc 2.1x upstream's instructions where this form
%measures at parity [measured 2026-08-17: 24.7e9 against 12.0e9 net for
%the identical example].
translate_special_dl(collapse, [Expr], AfterHead, Goals, Out) :-
    (   var(Expr)
    ->  AfterHead = [collapse_runtime(Expr, Out)|Goals]
    ;   translate_expr_to_conj(Expr, Conj, ExprValue),
        (   runnable_collapse_name_state(CollapseState, NameSlot)
        ->  CollapseState = '$metta_name_state'(CollapseNames, PriorNames),
            NameState = '$metta_name_state'(CollapseNames,
                                            [CollapseRuntimeNames|PriorNames]),
            NamedConj = metta_run_named(CollapseNames, Conj,
                                        CollapseRuntimeNames),
            (   ExprValue == 'Empty'
            ->  AfterHead = [(Out = [], NameSlot = [])|Goals]
            ;   nonvar(ExprValue)
            ->  AfterHead = [(findall('$metta_answer'(ExprValue, NameState),
                                      NamedConj, Carried),
                              metta_answer_terms(Carried, Out, NameSlot))|Goals]
            ;   AfterHead = [(findall('$metta_answer'(ExprValue, NameState),
                                      NamedConj, Carried0),
                              metta_prune_empty_answers(Carried0, Carried),
                              metta_answer_terms(Carried, Out, NameSlot))|Goals]
            )
        ;   ExprValue == 'Empty'
        ->  AfterHead = [Out = []|Goals]
        ;   nonvar(ExprValue)
        ->  AfterHead = [findall(ExprValue, Conj, Out)|Goals]
        ;   AfterHead = [(findall(ExprValue, Conj, All),
                          metta_prune_empty(All, Out))|Goals]
        )
    ).
translate_special_dl(cut, [], AfterHead, Goals, true) :-
    AfterHead = [(!)|Goals].
translate_special_dl(test, [Expr, Expected], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Value),
    TestGoal = ( findall(Value, Conj, Results),
                 test_answer_value(Results, Actual) ),
    AfterHead = [TestGoal|AfterFindall],
    translate_expr_dl(Expected, AfterFindall, BeforeTest, ExpectedValue),
    BeforeTest = [test(Actual, ExpectedValue, Out)|Goals].
translate_special_dl('test-no-answer', [Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Value),
    AfterHead = [findall(Value, Conj, Results),
                 'test-no-answer'(Results, Out)|Goals].
%once is a bound of one, and it reaches the matcher for the same reason take's
%does: an eager conjunctive snapshot finds every row before the first one
%leaves, so `(once (match &s (, ...) ...))` walked the whole join to answer one
%row [measured 2026-08-21, engine/spaces.pl match_bounded/5 carries the
%numbers]. once/1 still wraps it, because once is deterministic and a bound is
%not.
translate_special_dl(once, [Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Out),
    (   Conj = match(Space, Pattern, Template, Result)
    ->  Bounded = match_bounded(1, Space, Pattern, Template, Result)
    ;   Bounded = Conj
    ),
    AfterHead = [once(Bounded)|Goals].
%(take K Expr): at most K answers of Expr. once took one and collapse took
%all, and nothing took k, while the space seam has had the concept one level
%down all along in BoundedMatcher's limit.
%
%The two forms differ only in whether the bound also reaches the MATCHER, and
%that is decided HERE because the shape is what decides it. A conjunction, a
%guard or a function call compiles to the plain bound; exactly one match over
%one space compiles to the pushdown. Deciding it at run time would mean
%inspecting a compiled goal, and deciding it later would mean not knowing the
%expression was a single match at all.
%
%`Conj = match(Space, Pattern, Template, Result)` is the shape test once, take
%and top share, and it is written INLINE at all three because a unification is
%an instruction where a helper predicate is a call: the same test behind a
%predicate cost two inferences per translated form, and a source recompiled per
%call pays that per call [measured 2026-08-21: the annotated-relation benchmark
%runs 500 sources through the translator and read +1,000].
%
%Only that shape may carry a bound: nothing runs between a row and the answer
%it becomes, so N rows are N answers and a producer stopped at N cannot
%under-answer. A goal after the match could fail and make the (N+1)th row the
%answer, and a variable-headed template is exactly that case, since `($x $z)`
%compiles to a reduce/3 that may be a call [measured 2026-08-21: the bound
%reaches `(pair $x $y)` and `$x` and stops at `($x $z)`]. That is the rule
%relational planners settled on for the same question: a LIMIT may be pushed
%through a PROJECTION, which turns each row into one row, and never through a
%FILTER, which may drop the row the bound stopped at [source: Apache Spark's
%LimitPushDown, sql/catalyst/.../Optimizer.scala, which pushes LocalLimit
%through Project, Union ALL and the sides of a Join and leaves Filter alone,
%read 2026-08-21]. engine/spaces.pl's licensed_options/4 already cites
%DataFusion for the other half of the same discipline, that a bound reaches a
%source only where the source promised it can act on one.
%
%Template and Result stay DISTINCT, which the fused spelling
%`Conj = match(Space, Pattern, Out, Out)` could not: that unification bound the
%expression's own result to the template at COMPILE time, and match/4's last
%clause answers an Error ATOM through the result, so it had nothing left to
%unify with. `(take 1 (match $u (f 1) matched))` answered nothing where
%`(match $u (f 1) matched)` answered the Error
%[measured 2026-08-21;
%tested: test_a_bounded_match_on_an_unbound_space_answers_the_error].
translate_special_dl(take, [CountExpr, Expr], AfterHead, Goals, Out) :-
    translate_expr_dl(CountExpr, AfterHead, AfterCount, Count),
    translate_expr_to_conj(Expr, Conj, Out),
    (   Conj = match(Space, Pattern, Template, Result)
    ->  Bounded = metta_take_match(Count, Space, Pattern, Template, Result)
    ;   Bounded = metta_take(Count, Conj)
    ),
    AfterCount = [Bounded|Goals].
%(annotation): the current answer's annotation, the k the seam carried
%with the last answer produced in this derivation, 1 outside any.
translate_special_dl(annotation, [], AfterHead, Goals, Out) :-
    AfterHead = [metta_annotation(Out)|Goals].
%(explain Query): the seam's route for Query, answered as atoms rather
%than run. The query arrives UNEVALUATED, like quote's argument, because
%the route is a fact about the expression, not about its answers.
translate_special_dl(explain, [Query], AfterHead, Goals, Out) :-
    AfterHead = [metta_explain(Query, Out)|Goals].
%(top K Expr): the K BEST of Expr by answer annotation, in the context's
%declared semiring order, where take is any K. The same shape decision:
%exactly one match over one space is the form that can check the context's
%order and push the bound under the three declarations; everything else
%collects and orders here.
translate_special_dl(top, [CountExpr, Expr], AfterHead, Goals, Out) :-
    translate_expr_dl(CountExpr, AfterHead, AfterCount, Count),
    translate_expr_to_conj(Expr, Conj, Out),
    (   Conj = match(Space, Pattern, Template, Result)
    ->  Ordered = metta_top_match(Count, Space, Pattern, Template, Result)
    ;   Ordered = metta_top(Count, Conj, Out)
    ),
    AfterCount = [Ordered|Goals].
translate_special_dl(hyperpose, [List], AfterHead, Goals, Out) :-
    ( nonvar(List), is_list(List)
      -> build_hyperpose_branches(List, Branches),
         length(Branches, BranchCount),
         hyperpose_pool_size(BranchCount, Jobs),
         current_metta_module(Module),
         AfterHead = [concurrent_and(member((Goal, Result), Branches),
                                     hyperpose_branch(Module, Goal, Result,
                                                      Out),
                                     [threads(Jobs)])|Goals]
      ; translate_expr_dl(List, AfterHead, BeforeHyperpose, ListValue),
        BeforeHyperpose = [hyperpose_runtime(ListValue, Out)|Goals] ).
translate_special_dl(with_mutex, [Mutex, Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Out),
    AfterHead = [with_mutex(Mutex, Conj)|Goals].
%timeout and elapsed are special forms for the same reason with_mutex is: the
%expression must reach them UNEVALUATED. As ordinary functions their argument
%would be evaluated first, so the bound would be applied to finished work and
%the clock would start after the work it is meant to time [measured 2026-08-15:
%(elapsed (spin 200000)) reported 12us for a 19ms call].
translate_special_dl(timeout, [Seconds, Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Out),
    translate_expr_dl(Seconds, AfterHead, BeforeTimeout, SecondsValue),
    BeforeTimeout = [metta_timeout(SecondsValue, Conj, Out)|Goals].
translate_special_dl('with-pragma!', [Settings, Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Out),
    translate_expr_dl(Settings, AfterHead, BeforeScope, SettingsValue),
    BeforeScope = [metta_with_pragmas(SettingsValue, Conj, Out)|Goals].
translate_special_dl(inferences, [CountExpr, Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Out),
    translate_expr_dl(CountExpr, AfterHead, BeforeBound, Count),
    BeforeBound = [metta_inferences(Count, Conj, Out)|Goals].
translate_special_dl(elapsed, [Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Value),
    AfterHead = [metta_elapsed(Conj, Value, Out)|Goals].
translate_special_dl(transaction, [Expr], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Expr, Conj, Out),
    AfterHead = [metta_transaction(Conj)|Goals].

%A SEED IS A SCOPE, not a global setting, so the sequence a program depends on
%is the one written beside it rather than whatever the process did earlier.
%`(with-seed 42 (random-int 1 6))` draws from a generator seeded with 42 and
%restores whatever state was in force when it finishes, so two runs of the same
%scope answer the same thing and nothing outside it is disturbed. That is
%Racket's `parameterize` over `current-pseudo-random-generator` and Common
%Lisp's `with-random-state`, the same shape metta/algebra.py already uses on
%the Python side with random.Random(seed) rather than the module generator
%[source: bindings/python/metta/algebra.py, "Draw a stable cumulative rate
%selection using isolated seeded state"]. `set_random(seed(S))` alone would be
%the global this refuses.
%
%The body is compiled IN PLACE, as transaction's is, so the scope costs one
%save and one restore rather than a term evaluation
%[tested: test_a_seed_scope_repeats_its_draws_and_leaves_the_outside_alone].
translate_special_dl('with-seed', [SeedExpr, Body], AfterHead, Goals, Out) :-
    translate_expr_to_conj(SeedExpr, SeedConj, SeedValue),
    translate_expr_to_conj(Body, BodyConj, BodyValue),
    build_branch(BodyConj, BodyValue, Out, BodyBranch),
    Written = [SeedValue, Body],
    (   SeedConj == true
    ->  AfterHead = [metta_with_seed(SeedValue, Written, BodyBranch, Out)|Goals]
    ;   AfterHead = [( SeedConj,
                       metta_with_seed(SeedValue, Written, BodyBranch,
                                       Out) )|Goals]
    ).

translate_special_dl(progn, [], Goals, Goals, []).
translate_special_dl(progn, Exprs, AfterHead, Goals, Out) :-
    Exprs = [_|_],
    translate_args_dl(Exprs, AfterHead, Goals, Outs),
    last(Outs, Out).
translate_special_dl(prog1, [First|Rest], AfterHead, Goals, Out) :-
    translate_expr_dl(First, AfterHead, AfterFirst, Out),
    translate_args_dl(Rest, AfterFirst, Goals, _).

%progn's other half: every argument is evaluated and the answer is unit, at
%whatever arity the caller wrote. `(nop)`, `(nop 1)` and `(nop 1 2 3)` all
%answer `()`.
%
%Upstream's standard library says out loud that it could not write this one,
%"; TODO: there is no way to define operation which consumes any number of
%arguments and returns unit" immediately above nop's own doc block, and answers
%it in Rust instead: `grounded_op!(NopOp, "nop")` whose execute ignores its
%whole argument list [source: hyperon-experimental@3f76dc4 stdlib.metta:608-609
%and core.rs:58,61-63,70-74]. Here a variadic special form is the way to ignore
%an argument list, which is the same reason progn above is one.
%
%Ignoring the VALUES is not ignoring the calls: translate_args_dl/4 still
%compiles each argument, so an effect inside a nop still happens, which is what
%a grounded operation's evaluated arguments do upstream. The empty case needs
%no clause of its own because translate_args_dl([], Goals, Goals, []) already
%leaves the goal list alone [tested: nop_answers_unit_at_every_arity].
translate_special_dl(nop, Exprs, AfterHead, Goals, []) :-
    translate_args_dl(Exprs, AfterHead, Goals, _).

%The condition takes guard_error_condition/6's short circuit, which is
%guard_error_arguments/6's rule written out for a special form.
translate_special_dl(if, [Cond, Then], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Cond, CondConj, CondValue),
    translate_expr_to_conj(Then, ThenConj, ThenValue),
    build_branch(ThenConj, ThenValue, Out, ThenBranch),
    ( CondConj == true
      -> AfterHead = [(CondValue == true -> ThenBranch)|Goals]
      ; guard_error_condition(Cond, CondValue, Out, ThenBranch, fail,
                              Decision),
        AfterHead = [(CondConj, Decision)|Goals] ).
translate_special_dl(if, [Cond, Then, Else], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Cond, CondConj, CondValue),
    translate_expr_to_conj(Then, ThenConj, ThenValue),
    translate_expr_to_conj(Else, ElseConj, ElseValue),
    build_branch(ThenConj, ThenValue, Out, ThenBranch),
    build_branch(ElseConj, ElseValue, Out, ElseBranch),
    ( CondConj == true
      -> AfterHead = [(CondValue == true -> ThenBranch ; ElseBranch)|Goals]
      ; guard_error_condition(Cond, CondValue, Out, ThenBranch, ElseBranch,
                              Decision),
        AfterHead = [(CondConj, Decision)|Goals] ).
%unify: the stdlib's matching conditional. All four arguments are typed
%Atom, so the two operands cross unevaluated exactly as quote's argument
%does, and only the selected branch runs [source: LeaTTa
%tests/semantics/matching/unify_branch_evaluation.metta, branch markers
%measured 2026-08-11]. Every solution of metta_match_atoms/2 is one
%binding set and instantiates its own then-branch answer; the soft cut
%runs the else-branch exactly when no binding set exists. Bindings made
%by the match flow into the branch through the shared variables, which
%is how (unify &kb (friend $who Alice) $who no-friends) answers each
%friend.
%unify is the ONE branching form whose pattern can bind a name to an unreduced
%term, because its two operands are declared `Atom` and reach it as written
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:907,
%`(: unify (-> Atom Atom Atom Atom %Undefined%))`]. A branch that is that bare
%name compiles to no goal at all, so the unreduced term walks straight out,
%and the `%Undefined%` result is what reduces it:
%`!(unify (a $x) (a (+ 1 2)) $x nope)` is `3` and was `(+ 1 2)` here
%[measured 2026-08-24 against LeaTTa 9ea9f9d].
%
%`case`, `if` and `let` need nothing: their scrutinee and value are evaluated
%before the branch runs, so no branch of theirs can hold an unreduced term.
%All three were measured on the same day through a masked binding and agree
%already.
translate_special_dl(unify, [A, B, Then, Else], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Then, ThenConj, ThenValue),
    translate_expr_to_conj(Else, ElseConj, ElseValue),
    unify_branch(Then, ThenConj, ThenValue, Out, ThenBranch),
    unify_branch(Else, ElseConj, ElseValue, Out, ElseBranch),
    metta_unify_decision(A, B, Decide),
    AfterHead = [(Decide *-> ThenBranch ; ElseBranch)|Goals].

%case reads its cases as syntax, so a cases argument that is still a variable
%has no branches to compile. That shape used to reach case_default_pair/3's
%select/3, which enumerates longer and longer instances of an open list
%forever: `!(case 1 $cases)` allocated 7.5 Gb and died, and so did merely
%LOADING the one-line wrapper `(= (switch $v $cs) (case $v $cs))`. It
%compiles to the runtime path instead, which is the answer hyperpose already
%gives a list argument that is not syntax, so the wrapper is an ordinary
%definition again and the cases a caller writes decide the branches
%[tested: translator_case_open_cases, translator_case_computed_cases].
translate_special_dl(case, [KeyExpr, PairsExpr], AfterHead, Goals, Out) :-
    ( unarrived_pairs(PairsExpr)
      -> translate_expr_to_conj(KeyExpr, KeyConj, KeyValue),
         %The same soft cut the compiled form uses below, for the same
         %reasons: the key runs once, and its absence of answers is what
         %selects the default.
         AfterHead = [( KeyConj
                      *-> case_runtime(KeyValue, PairsExpr, Out)
                      ;   case_default_runtime(PairsExpr, Out) )|Goals]
      ; case_default_pair(PairsExpr, DefaultExpr, NormalCases)
      -> translate_expr_to_conj(KeyExpr, KeyConj, KeyValue),
         translate_case(NormalCases, KeyValue, Out, CaseGoal, KeyGoals),
         translate_expr_to_conj(DefaultExpr, DefaultConj, DefaultValue),
         build_branch(DefaultConj, DefaultValue, Out, DefaultBranch),
         %The soft cut runs the key once. Writing this as
         %`(KeyConj, CaseGoal) ; \+ KeyConj, DefaultBranch` evaluates the key a
         %second time to decide the default, so a key with a side effect ran it
         %twice and an expensive key cost twice as much. A hard `->` would run
         %it once but commit to the first key value, which loses the other
         %answers of a nondeterministic key such as (superpose (1 2)).
         Combined = ( KeyConj *-> CaseGoal
                    ; DefaultBranch ),
         append(KeyGoals, [Combined|Goals], AfterHead)
      ; translate_expr_dl(KeyExpr, AfterHead, AfterKey, KeyValue),
        translate_case(PairsExpr, KeyValue, Out, CaseGoal, KeyGoals),
        append(KeyGoals, [CaseGoal|Goals], AfterKey) ).

%switch is case WITHOUT case's reading of a key that answered nothing. The two
%forms differ at exactly that point and nowhere else, which is what upstream's
%own comment says: "Difference between switch and case is a way how they
%interpret Empty result"
%[source: hyperon-experimental@3f76dc4:lib/src/metta/runner/stdlib/stdlib.metta:331-365,
%quoted in LeaTTa tests/semantics/control-stdlib/03_case_switch.metta].
%
%So the Empty ROW is ordinary here: it is matched against the key's value in
%source order like any other, and a key with no answers selects nothing at all
%rather than selecting it. Measured against the arbiter, whose transcript this
%reproduces line for line: `(switch (key) ((first wrong) (second S) ($_ C)))`
%is S, `(switch second (($_ F) (second L)))` is F because rows are tried in
%order, `(switch absent ((first wrong) (second wrong)))` is nothing,
%`(switch (empty) ((Empty E) ($_ V)))` is nothing, and
%`(switch Empty (($_ V) (Empty L)))` is V
%[source: LeaTTa tests/semantics/control-stdlib/03_case_switch.metta, whose
%STATUS records switch as conforming]
%[tested: test_switch_reads_a_key_with_no_answers_as_no_answer].
%
%The rows compile through translate_case/5, the same relation the written-out
%case uses, so one definition decides what a row means for both forms.
translate_special_dl(switch, [KeyExpr, PairsExpr], AfterHead, Goals, Out) :-
    (   unarrived_pairs(PairsExpr)
    ->  translate_expr_to_conj(KeyExpr, KeyConj, KeyValue),
        AfterHead = [( KeyConj,
                       switch_runtime(KeyValue, PairsExpr, Out) )|Goals]
    ;   translate_expr_dl(KeyExpr, AfterHead, AfterKey, KeyValue),
        translate_case(PairsExpr, KeyValue, Out, CaseGoal, KeyGoals),
        append(KeyGoals, [CaseGoal|Goals], AfterKey)
    ).

translate_special_dl(let, Args, AfterHead, Goals, Out) :-
    translate_let_dl(Args, AfterHead, Goals, Out).
%A function frame consumes the return form structurally.  Outside that frame
%it remains an ordinary polymorphically typed call, whose argument evaluates:
%with a -> b -> c, top-level `(return a)` is `(return c)`, while
%`(function (chain (eval a) $x (return $x)))` returns b.
translate_special_dl(return, [Value], AfterHead, Goals, Out) :-
    function_evaluation_active,
    !,
    Out = [return, Value],
    AfterHead = Goals.
%CHAIN'S NESTED OPERAND IS ONE MINIMAL STEP, NOT AN EVALUATION, and that is the
%whole difference between it and `let`. Its declared first parameter is `Atom`,
%so the operand reaches the instruction as written
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:906,
%`(: chain (-> Atom Variable Atom %Undefined%))`]; the instruction then steps
%it if it is one of the twelve reflected forms and leaves it as DATA if it is
%not [source: the same file's `mi-function-continue` at :1818-1843, which
%enumerates that closed list]. An operand the instruction leaves as data is
%substituted into the template unevaluated, and the template's own positions
%then decide whether it ever reduces.
%
%That is why the two spellings answer differently for a reducible operand:
%`!(chain (+ 1 2) $x (quote $x))` is `(quote (+ 1 2))` and
%`!(let $x (+ 1 2) (quote $x))` is `(quote 3)` [measured 2026-08-24 against
%LeaTTa 9ea9f9d, both doors agreeing].
%
%SUBSTITUTION IS THE WHOLE IMPLEMENTATION, and it is compile-time work rather
%than a runtime binding, which is what makes the unevaluated operand reach a
%masked position at all. It also carries the multiplicity the runtime binding
%could not: a binder used twice duplicates a nondeterministic operand, and the
%arbiter answers all four rows for
%`!(chain (superpose (1 2)) $x ($x $x))` where a bind-once route answers two
%[measured 2026-08-24].
translate_special_dl(chain, [Nested, Binder, Template], AfterHead, Goals, Out) :-
    var(Binder),
    !,
    (   nonvar(Nested), \+ embedded_operation(Nested)
    ->  substitute_written_variable(Binder, Nested, Template, Substituted),
        translate_expr_dl(Substituted, AfterHead, AfterTemplate, Value),
        %chain's declared result is `%Undefined%`, so what the template produced
        %re-enters evaluation. The substituted operand can land in a MASKED
        %position of the template and survive there unreduced, and this is the step
        %that then reduces it: `!(chain (+ 1 2) $x (cons-atom $x (b)))` builds
        %`((+ 1 2) b)` and answers `(3 b)` [measured 2026-08-24 against LeaTTa
        %9ea9f9d].
        masked_result_goal(Value, Out, Goal),
        AfterTemplate = [Goal|Goals]
    ;   %A stepped operand is the protocol observer: chain asks eval for one raw
        %machine result, so an irreducible operand reaches its continuation as the
        %bare NotReducible mark. An eval written in any ordinary expression
        %context retains its own call instead.
        AfterHead = [metta_chain_step(Nested, Binder)|AfterTemplate],
        translate_expr_dl(Template, AfterTemplate, AfterResult, Value),
        masked_result_goal(Value, Out, Goal),
        AfterResult = [Goal|Goals]
    ).
%Malformed/non-variable binders retain the ordinary let-pattern behavior so
%the existing language-level mismatch path, rather than translation, decides
%their result.
translate_special_dl(chain, Args, AfterHead, Goals, Out) :-
    translate_let_dl(Args, AfterHead, AfterTemplate, Value),
    masked_result_goal(Value, Out, Goal),
    AfterTemplate = [Goal|Goals].
%let* reads its bindings as syntax and rewrites them into nested lets, so
%bindings that have not arrived have none to read. That shape used to reach
%letstar_to_rec_let/3's [] base clause, whose cut then committed to it: the
%argument was UNIFIED with the empty list and every binding was dropped
%without a word, so `(= (mylet $bs $b) (let* $bs $b))` compiled to
%`mylet([], A, A)` and answered its body with nothing bound. A pair that is
%still a variable is the same defect one level in, where the rewrite unified
%its own [Pattern, Value] pattern INTO the source and `(= (letpair $b)
%(let* ($b) 99))` compiled to `letpair([A, B], 99)`, changing the head the
%program wrote. Both compile to the runtime path instead, which is the answer
%case and hyperpose already give an argument that is not syntax
%[tested: translator_letstar_unarrived_bindings,
%translator_letstar_computed_bindings].
translate_special_dl('let*', [Binds, Body], AfterHead, Goals, Out) :-
    ( unarrived_pairs(Binds)
      -> AfterHead = [letstar_runtime(Binds, Body, Out)|Goals]
      ;  letstar_to_rec_let(Binds, Body, RecursiveLet),
         translate_expr_dl(RecursiveLet, AfterHead, Goals, Out) ).
%sealed returns a renamed Atom. Every variable in the Atom is fresh except a
%variable present in the first argument's ignore list [tested:
%translator_sealed:the_ignore_list_preserves_only_its_variables;
%commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa]. copy_term/4 performs that selective rename before evaluation
%can bind an outer variable, and the answer remains data rather than being
%reduced [tested: translator_sealed:sealed_returns_data_instead_of_evaluating_it;
%commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
translate_special_dl(sealed, [Ignored, Expr], Goals, Goals, SealedExpr) :-
    term_variables(Expr, ExprVariables),
    term_variables(Ignored, IgnoredVariables),
    exclude({IgnoredVariables}/[Variable]>>
                memberchk_eq(Variable, IgnoredVariables),
            ExprVariables, FreshVariables),
    copy_term(FreshVariables, Expr, FreshCopies, SealedExpr),
    runnable_note_copied_variables(FreshVariables, FreshCopies).


translate_special_dl('forall', [Generator, Test], AfterHead, Goals, Out) :-
    ( is_list(Generator)
      -> Generator = [GeneratorHead|GeneratorArgs],
         translate_expr(GeneratorHead, HeadGoals, GeneratorHeadValue),
         translate_args(GeneratorArgs, ArgGoals, GeneratorArgValues),
         append(HeadGoals, ArgGoals, GeneratorGoals),
         GeneratorList = [GeneratorHeadValue|GeneratorArgValues]
      ; translate_expr(Generator, GeneratorGoals, GeneratorHeadValue),
        GeneratorList = [GeneratorHeadValue] ),
    TestList = [TestHeadValue, GeneratedValue],
    goals_list_to_conj(GeneratorGoals, GeneratorPrefix),
    GeneratorGoal = (GeneratorPrefix,
                     reduce(GeneratorList, GeneratedValue, _)),
    translate_expr_dl(Test, AfterHead, BeforeForall, TestHeadValue),
    %Stops on FALSE, not on "anything that is not true". The example's own
    %comment has always said so, "an item returning false breaks the loop", and
    %the two readings only came apart once the effectful operations started
    %answering the unit value the specification types them with: a body of
    %`(add-atom &s (num $x))` answers `()`, which is an effect that happened and
    %not a failed test, and requiring `true` stopped the loop after one item
    %[tested: examples/control/metta4_streams.metta].
    BeforeForall = [(forall(GeneratorGoal,
                            (reduce(TestList, Truth, _), Truth \== false))
                     -> Out = true
                      ; Out = false)|Goals].
translate_special_dl('foldall', [Accumulator, Generator, InitialExpr],
                     AfterHead, Goals, Out) :-
    translate_expr_to_conj(InitialExpr, InitialConj, Initial),
    translate_expr_dl(Accumulator, AfterHead, AfterAccumulator,
                      AccumulatorValue),
    ( Generator = [Mode|_],
      (Mode == match ; Mode == let ; Mode == 'let*')
      -> Lambda = ['|->', [], Generator],
         translate_expr_dl(Lambda, AfterAccumulator, AfterGenerator,
                           GeneratorHeadValue),
         GeneratorList = [GeneratorHeadValue]
      ; is_list(Generator)
      -> Generator = [GeneratorHead|GeneratorArgs],
         translate_expr_dl(GeneratorHead, AfterAccumulator,
                           AfterGeneratorHead, GeneratorHeadValue),
         translate_args_dl(GeneratorArgs, AfterGeneratorHead,
                           AfterGenerator, GeneratorArgValues),
         GeneratorList = [GeneratorHeadValue|GeneratorArgValues]
      ; translate_expr_dl(Generator, AfterAccumulator, AfterGenerator,
                          GeneratorHeadValue),
        GeneratorList = [GeneratorHeadValue] ),
    AfterGenerator = [InitialConj,
                      foldall(agg_reduce(AccumulatorValue, Value),
                              reduce(GeneratorList, Value, _), Initial, Out)|Goals].

%The three collection forms take a variable and a body, which is a lambda
%written without the word. Each compiles its body into a closure predicate
%through the '|->' clause below and then calls maplist/3, include/3 or foldl/4
%on it, so the body is an ordinary compiled call.
%
%They used to inline the body into a yall lambda instead. That was wrong twice
%over. It cost 3.6 to 4.7 times the inferences and 7 to 11 times the cpu,
%because yall copy_terms the lambda for every element and assertz/1 does not
%run the goal expansion that would have removed it [measured 2026-08-15,
%100,000 elements: maplist 1301283 -> 300004, include 1250004 -> 350004,
%foldl 1400004 -> 300004]. And it captured nothing, so (map-atom $l $x ($x $u))
%answered ((a $_0) (b $_1)) while the same map written (map-atom $l (|-> ($x)
%($x $u))) answered ((a $_0) (b $_0)). One spelling of one map, two answers.
%examples/lambda.metta settles which is right: it binds $k outside a lambda,
%reads it inside, and expects the value, so capturing is the specified
%behaviour and these forms now share the predicate that implements it.
%THE LIST AND THE SEED CROSS AS WRITTEN, which is what their declared types
%say: `(: map-atom (-> Expression Variable Atom Expression))` and
%`(: foldl-atom (-> Expression Atom Variable Variable Atom %Undefined%))` are
%the arbiter's own rows, and Expression and Atom are both on the mask
%[source: LeaTTa MettaHyperonFull/Core/Modifiers.lean:92-124,
%`declaredTypeEvaluates`]. These three clauses evaluated both operands, so a
%written call in the list position was REDUCED and its value mapped over,
%where the arbiter maps over the parts of the call itself:
%`!(map-atom (cdr-atom (a b)) $y (q $y))` is `((q cdr-atom) (q (a b)))` there
%and was `((q b))` here, and `!(foldl-atom (1) (+ 1 2) $a $b (size-atom $a))`
%is 3 there, the size of the held `(+ 1 2)`, and was a Number refusal here
%[measured 2026-08-24 against LeaTTa 9ea9f9d].
%
%A caller that wants the value of a call in either position NAMES it first,
%`(let $xs (collapse ...) (map-atom $xs ...))`, which is what the arbiter's own
%stdlib writes and what this tree's corpus was rewritten to.
%
%No goal is emitted for either operand, so this is also strictly less work than
%the evaluation it replaces.
translate_special_dl('foldl-atom', [ListExpr, InitialExpr, AccVar, ItemVar,
                                    Body], AfterHead, Goals, Out) :-
    collection_closure([ItemVar, AccVar], Body, Closure),
    AfterHead = [foldl(Closure, ListExpr, InitialExpr, Out)|Goals].
translate_special_dl('map-atom', [ListExpr, ItemVar, Body],
                     AfterHead, Goals, Out) :-
    collection_closure([ItemVar], Body, Closure),
    AfterHead = [maplist(Closure, ListExpr, Out)|Goals].
translate_special_dl('filter-atom', [ListExpr, ItemVar, Condition],
                     AfterHead, Goals, Out) :-
    collection_closure([ItemVar], Condition, Closure),
    AfterHead = [include(metta_condition_holds(Closure), ListExpr, Out)|Goals].

translate_special_dl('|->', [Args, Body0], AfterHead, Goals, Out) :-
    %Apply every nested sealed's rename BEFORE deciding which variables are
    %free. A variable that a sealed form localises is not free in the enclosing
    %lambda, and counting it as one made the lambda capture it as an extra
    %parameter: (= (mk) (|-> ($a) (sealed ($v) (pair $a $v)))) compiled mk to
    %arity 2 while every call to it was arity 1, so the function was simply
    %uncallable. Measured 2026-08-15, and it behaved the same before sealed's
    %rename moved to compile time, so it is not that change's doing.
    seal_lambda_locals(Body0, Body, SealedLocals),
    next_lambda_name(Function),
    term_variables(Body, AllVars),
    term_variables(Args, ArgVars),
    %A variable the BODY ITSELF BINDS is not free either, and for the same
    %reason a sealed one is not: captured, it becomes an extra argument of the
    %lambda predicate, and the ONE closure term is then applied to every
    %element of a map or a fold, so the first element's binding constrains the
    %next. `(map-atom $xs (|-> ($v) (let $h (filter-atom $xs (|-> ($w)
    %(< $v $w))) (q $h))))` captured `$h`, bound it to the first element's
    %filter result, and answered nothing for the second
    %[tested: tests/test_fuzz_define.py::test_collection_bridge_agrees].
    %
    %Nothing said so while a nested collection call was EVALUATED at the call
    %site, because then no source wrote a binder into a lambda body: the
    %evaluation mask reaching `Expression` list parameters is what makes a
    %caller name its intermediate.
    lambda_body_binders(Body, BodyBinders),
    append([ArgVars, SealedLocals, BodyBinders], NotFree),
    exclude({NotFree}/[Var]>>memberchk_eq(Var, NotFree), AllVars, FreeVars),
    append(FreeVars, Args, FullArgs),
    translate_clause([=, [Function|FullArgs], Body], Clause),
    %Into the space's own module, the way filereader.pl asserts every other
    %compiled equation. A bare assertz/2 puts the lambda in `user`, and a
    %module inherits from `user` rather than the other way round, so the
    %lambda could not see the space it was written in: inside a named space,
    %`(= (local-double $x) (* $x 2))` followed by
    %`!(map-atom (1 2 3) $x (local-double $x))` raised
    %`apply:maplist_/3: Unknown procedure: 'local-double'/2` while the same
    %call written directly answered 42. That is every lambda form, `|->`,
    %`map-atom`, `filter-atom` and `foldl-atom`, unusable on a space-local
    %function; and since every space pymetta creates is a named one, it was
    %the whole Python surface [tested: translator_lambda_space_scope].
    %
    %+10 inferences once per lambda COMPILED and nothing per call [measured
    %2026-08-16: 1338 to 1348 for one map-atom compile-and-run, 10,005 either
    %way for a compiled map-atom over 2,000 elements].
    current_metta_module(Module),
    register_fun_in(Module, Function),
    assert_function_clause(Module, Clause, Ref),
    record_source_assertion(Ref),
    format(atom(Label), "metta lambda (~w)", [Function]),
    maybe_print_compiled_clause(Label, ['|->', Args, Body], Clause),
    length(FullArgs, InputArity),
    Arity is InputArity + 1,
    register_arity(Function, Arity),
    ( FreeVars == [] -> Out = Function ; Out = partial(Function, FreeVars) ),
    AfterHead = Goals.

%The five write forms, by one rule rather than one clause each. Every one of
%them is `(operation Space Atom)`: the space is an expression to evaluate and
%the atom is passed as WRITTEN, which is what their shared type
%`(-> Symbol Atom (->))` says and what the standard library means by "the added
%atom is added as is without reduction".
%
%The three plural and reducing ones were compiled as ordinary calls when they
%were added, so their argument was reduced before they saw it, and
%`(add-reduct &self (= (foo) (+ 3 4)))` reached add-reduct as `false`: `=` is
%this engine's equality operator as well as a definition head, so reducing an
%equation TESTS it [tested: examples/libraries/he_atomspace.metta].
%One clause each, and NOT one clause matching a list of names, because the
%head here is the interface: metta_special_form/1 reads these clause heads to
%decide what a special form is, so a variable in that position makes EVERY name
%one. It did, and the damage was nowhere near this file: duals refused to build
%a dual for an ordinary undefined function, reporting it as "a builtin or a
%special form" [tested: a_name_no_equation_defines_is_not_provable_at_all].
translate_special_dl('add-atom', Args, AfterHead, Goals, Out) :-
    translate_space_update_dl('add-atom', Args, AfterHead, Goals, Out).
translate_special_dl('remove-atom', Args, AfterHead, Goals, Out) :-
    translate_space_update_dl('remove-atom', Args, AfterHead, Goals, Out).
translate_special_dl('add-atoms', Args, AfterHead, Goals, Out) :-
    translate_space_update_dl('add-atoms', Args, AfterHead, Goals, Out).
translate_special_dl('add-reduct', Args, AfterHead, Goals, Out) :-
    translate_space_update_dl('add-reduct', Args, AfterHead, Goals, Out).
translate_special_dl('add-reducts', Args, AfterHead, Goals, Out) :-
    translate_space_update_dl('add-reducts', Args, AfterHead, Goals, Out).
%The parametric constructor bootstraps the identity, so its expression cannot
%be recognized from the registry yet. Hold that one expression by shape even
%when its family head is already a callable function; validation below the
%door still requires it to be finite, ground and symbol-headed.
translate_special_dl('new-space', [Space], AfterHead, Goals, Out) :-
    is_list(Space), !,
    translate_restricted_guard_dl(
        metta_require_current_capability('new-space', process),
        ['new-space'(Space, Out)|Goals], AfterHead).
%A literal (superpose (&a &b ...)) space argument is the multi-context
%idiom, and the SHAPE decides it at translation exactly as take's bound
%does: those queries route through metta_merged_match/3, where the
%declared (merge <pattern> <policy>) chooses the strategy. A computed
%space expression keeps the space-after-space path.
translate_special_dl(match, [SpaceExpr, Pattern0, Body], AfterHead, Goals,
                     Out) :-
    SpaceExpr = [superpose, SpaceList],
    is_list(SpaceList), SpaceList = [_, _|_],
    forall(member(Space, SpaceList), metta_space_name(Space)), !,
    lift_pattern_modifiers(Pattern0, Pattern, Guards, Segments),
    metta_seq_query_pattern(Segments, Pattern, Asked),
    append([metta_merged_match(SpaceList, Asked, Out)|Guards], AfterMatch,
           AfterHead),
    translate_expr_dl(Body, AfterMatch, Goals, Out).
translate_special_dl(match, [SpaceExpr, Pattern0, Body], AfterHead, Goals,
                     Out) :-
    translate_space_expr_dl(SpaceExpr, AfterHead, BeforeMatch, Space),
    lift_pattern_modifiers(Pattern0, Pattern, Guards, Segments),
    metta_seq_query_pattern(Segments, Pattern, Asked),
    %The template and the result are DISTINCT variables. Fused, the
    %answer-shaped refusal of match/4's last clause could never surface: the
    %body had already bound the one variable, the Error atom failed to unify
    %with it, and the clause died silently, so !(match $u (f 1) matched)
    %answered zero rows while a direct call answered the Error
    %[tested: test_a_surface_match_on_an_unbound_space_answers_the_error].
    %On success match/4 unifies Result with OutPattern, so the compiled
    %goals and their cost are unchanged.
    append([match(Space, Asked, Template, Out)|Guards], AfterMatch,
           BeforeMatch),
    translate_expr_dl(Body, AfterMatch, Goals, Template).


translate_special_dl(translatePredicate, [[Predicate|Args]], AfterHead, Goals,
                     _Out) :-
    translate_args_dl(Args, AfterHead, BeforePredicate, ArgValues),
    metta_predicate_goal([Predicate|ArgValues], Goal),
    translate_restricted_guard_dl(metta_require_safe_goal(Goal), [Goal|Goals],
                                  BeforePredicate).
%The two Prolog seams are the exception to the fall-through documented above.
%No program means (translatePredicate ...) or (call ...) as data, so a shape
%the clause above cannot compile is a mistake worth reporting rather than a
%list worth building. Falling through instead compiled
%(translatePredicate (p $x) (p $x)) into the data list [translatePredicate,A,B]
%after evaluating both arguments, and answered it without complaint
%[tested translator.plt:malformed_seam_is_refused].
translate_special_dl(translatePredicate, Args, _, _, _) :-
    refuse_uncompilable_seam(translatePredicate, Args).
translate_special_dl(call, [[Function|Args]], AfterHead, Goals, Out) :-
    translate_args_dl(Args, AfterHead, BeforeCall, ArgValues),
    append(ArgValues, [Out], CallArgs),
    Goal =.. [Function|CallArgs],
    translate_restricted_guard_dl(metta_require_safe_goal(Goal), [Goal|Goals],
                                  BeforeCall).
translate_special_dl(call, Args, _, _, _) :-
    refuse_uncompilable_seam(call, Args).
translate_special_dl(reduce, [Expr], AfterHead, Goals, Out) :-
    ( Expr == []
      -> ExprValue = [],
         AfterHead = BeforeReduce
      ; var(Expr)
      -> translate_expr_dl(Expr, AfterHead, BeforeReduce, ExprValue)
      ; Expr = [Function|Args],
        translate_args_dl(Args, AfterHead, BeforeReduce, ArgValues),
        ExprValue = [Function|ArgValues] ),
    BeforeReduce = [reduce(ExprValue, Reduced, Status),
                    metta_reduce_result(ExprValue, Reduced, Status, Out)|Goals].
%metta_eval_step/2 exposes the raw NotReducible mark to chain and function.  As an
%ordinary expression, however, eval is itself an application boundary and an
%irreducible step retains `(eval <arg>)` as written.
translate_special_dl(eval, [Arg], AfterHead, Goals, Out) :-
    AfterHead = [metta_eval_step(Arg, Produced),
                 metta_boundary_result([eval, Arg], Produced, Out)|Goals].
%evalc hands its first argument over unevaluated, exactly as eval does, or the
%expression would already have been reduced in the calling space before the
%space argument could select another one. The space itself is evaluated, so a
%function that answers a space name, or (context-space), can name it.
translate_special_dl(evalc, [Arg, Space], AfterHead, Goals, Out) :-
    translate_space_expr_dl(Space, AfterHead, BeforeEval, SpaceValue),
    translate_restricted_guard_dl(
        metta_require_current_capability(evalc, process),
        [metta_evalc_step(Arg, SpaceValue, Produced),
         metta_boundary_result([evalc, Arg, SpaceValue], Produced, Out)|Goals],
        BeforeEval).
%Like the reference's embedded operation, metta-thread receives the atom as
%written and runs the nested full evaluator.  Compiling it as an ordinary call
%first evaluates that operand and leaves only the inert wrapper for the source
%interpreter to consume.
%[source: MettaHyperonFull/Minimal/Interpreter.lean:6747-6755,
%`symOpMettaThread`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
translate_special_dl('metta-thread', [Arg, _Type, Space], AfterHead, Goals,
                     Out) :-
    translate_space_expr_dl(Space, AfterHead, BeforeThread, SpaceValue),
    translate_restricted_guard_dl(
        metta_require_current_capability('metta-thread', process),
        ['metta-thread'(Arg, '%Undefined%', SpaceValue, Out)|Goals],
        BeforeThread).
%These kernel reads intentionally accept an unwritten atomic &name, so their
%declarations cannot use a strict SpaceType parameter. Once an expression is
%registered, however, it is an identity at this space-position just like the
%typed doors above, including when its family head is callable.
translate_special_dl('space-atom-count', [SpaceExpr], AfterHead, Goals, Out) :-
    translate_space_expr_dl(SpaceExpr, AfterHead, BeforeRead, Space),
    BeforeRead = ['space-atom-count'(Space, Out)|Goals].
translate_special_dl('space-contains', [SpaceExpr, Atom], AfterHead, Goals,
                     Out) :-
    translate_space_expr_dl(SpaceExpr, AfterHead, BeforeRead, Space),
    BeforeRead = ['space-contains'(Space, Atom, Out)|Goals].
translate_special_dl('get-atoms', [SpaceExpr], AfterHead, Goals, Out) :-
    translate_space_expr_dl(SpaceExpr, AfterHead, BeforeRead, Space),
    BeforeRead = ['get-atoms'(Space, Out)|Goals].
%(super (f a b)): the definition of f the NEXT module up this space's chain
%holds, so a shadow can check a call and then let the original run.
%
%The relative form, and the language already had the absolute one. `evalc`
%names the space to evaluate in, which works and does not COMPOSE: two guards
%on one name in one space, each delegating with `evalc` to &self, both run,
%and an atom one of them refused is stored anyway by the other, because
%neither names the next definition along its own chain, they both name the
%bottom [source: ai-phase11-module-survey.md section 3.2, measured]. That is
%Logtalk's reason for shipping (^^)/1 beside (::)/2: "Calls an imported or
%inherited predicate definition ... This control construct preserves the
%implicit execution context" [source:
%https://logtalk.org/handbook/refman/control/call_super_1.html].
%
%Resolved at COMPILE time, which is what makes it cost nothing at the call
%(a module-qualified call, a chain hop and an explicit super all measured
%2.00 inferences per loop iteration, identical to a local unqualified call
%[measured 2026-08-19]) and what makes a missing target a loud error where the
%equation is written rather than a silent empty answer where it runs.
%
%The arguments are translated the way any call's are, so `(super (f (g 1)))`
%evaluates g first. Only the HEAD is treated specially, and it has to name a
%function: `(super $f)` cannot be resolved without running, and saying so is
%better than compiling a call to whatever $f turns out to be.
translate_special_dl(super, [Call], AfterHead, Goals, Out) :-
    super_call_parts(Call, Fun, Args),
    translate_args_dl(Args, AfterHead, AfterArgs, ArgValues),
    length(ArgValues, InputArity),
    Arity is InputArity + 1,
    current_metta_module(Module),
    super_target_module(Module, Fun, Arity, Parent),
    note_super_call(Fun),
    resolve_dispatch(Fun, ArgValues, Out, Goal),
    AfterArgs = [dispatch_policy_execute(Parent, Fun, ArgValues, Goal, Out)|Goals].

%Quote is a value headed by the ordinary symbol `quote`. Its Atom argument is
%held and the wrapper survives; a consumer that wants the payload must match
%or evaluate that value explicitly.
translate_special_dl(quote, [Expr], Goals, Goals, [quote, Expr]).
%not-provable keeps its head literal and evaluates its arguments, exactly as
%an ordinary call does. Which function is being negated has to be known
%without running it, because the answer comes from that function's dual rather
%than from a failed proof of it [source: engine/duals.pl].
:- thread_local runnable_negation/0.

translate_special_dl('not-provable', [Expr], AfterHead, Goals, Out) :-
    metta_not_provable_goal(Expr, Goal, Out),
    (   translating_runnable, \+ runnable_negation
    ->  assertz(runnable_negation)
    ;   true
    ),
    AfterHead = [Goal|Goals].
translate_special_dl('catch', [Expr], AfterHead, Goals, Out) :-
    translate_expr(Expr, ExprGoals, ExprOut),
    goals_list_to_conj(ExprGoals, Conj),
    CatchGoal = catch((Conj, Out = ExprOut),
                      Exception,
                      ( control_exception(Exception)
                        -> throw(Exception)
                        ; Exception = error(Type, Context)
                        -> Out = ['Error', Type, Context]
                        ; Out = ['Error', Exception] )),
    AfterHead = [CatchGoal|Goals].

%%%% Gap patterns: what a call site hands its door %%%%
%
%A sequence variable changes a pattern's ARITY, so the door that reads a space
%cannot build a candidate head from the pattern's length, and the fragment its
%answer set lives in has to be decided before anything enumerates [source:
%LeaTTa MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?]. Both decisions
%are made HERE, while the call site compiles, which is the staging
%lift_pattern_modifiers/4 already uses and states: "Engine-compiled match/4
%pays nothing per row because this walk happens once while its call site
%compiles." The result rides in a WRAPPER the two existing doors dispatch on,
%so a gap-free pattern is handed over untouched and adds no goal name every
%space would have to import.
metta_seq_query_pattern(false, Pattern, Pattern).
metta_seq_query_pattern(true, Pattern, Asked) :-
    metta_seq_query_plan(Pattern, Asked).

%unify is the ONE door whose two operands are both syntax: they are typed Atom
%and cross unevaluated, so both sides can carry a written gap and the pair can
%land in either two-sided fragment. Every other door faces a VALUE on one side,
%which is data and therefore gap-free, so it is one_sided by construction.
metta_unify_decision(A, B, metta_match_atoms(Asked, B)) :-
    (   metta_seq_written(A)
    ->  true
    ;   metta_seq_written(B)
    ),
    !,
    metta_seq_plan(A, B, Asked).
metta_unify_decision(A, B, Decision) :-
    lift_pattern_modifiers(A, LiftedA, GuardsA, false),
    lift_pattern_modifiers(B, LiftedB, GuardsB, false),
    append(GuardsA, GuardsB, Guards),
    Guards \== [],
    !,
    goals_list_to_conj([metta_match_atoms(LiftedA, LiftedB)|Guards], Decision).
metta_unify_decision(A, B, metta_match_atoms(A, B)).

%The free half of the gap question: only a nonvar LIST can carry a gap, and
%nonvar/1 with =/2 compile inline, so an operand that is a variable, a symbol
%or a number never reaches the walk.
metta_seq_written(Operand) :-
    nonvar(Operand),
    Operand = [_|_],
    metta_seq_present(Operand).

%Both seams take exactly one argument: the goal to compile, written as a list
%whose head names the Prolog predicate. Reporting the argument rather than only
%the form matters, because the two ways to get this wrong look nothing alike.
%Writing (translatePredicate p) names a predicate without a goal around it, and
%wrapping a well-formed seam in quote, which a macro returning a term built in
%Prolog does not need, hands the translator a list it can only treat as data.
:- multifile prolog:error_message//1.

%THE COMPILER SAYING WHAT IT DECIDED ABOUT A HEAD PATTERN POSITION. Both
%decisions are correct and both are invisible in the source, which is the whole
%complaint: nothing in `(= (f (: $x Number)) $x)` says that a goal was
%compiled, and nothing in `(= (f (g $x)) $x)` says that the caller's `(g 3)`
%will have been evaluated to something else before it arrives.
:- multifile prolog:message//1.
prolog:message(metta_head_pattern_note(Fun, Path, Label, type_annotation)) -->
    { head_pattern_position_text(Path, Where) },
    [ 'the head of (= (~w ...) ...) constrains ~w with the in-place \c
       annotation on ~w, so that position compiled to a type premise GOAL \c
       rather than to structure. The equation this function stores no longer \c
       holds its whole head, which is why a dual cannot be built \c
       for it.'-[Fun, Where, Label] ].
prolog:message(metta_head_pattern_note(Fun, Path, Label, defined_label(Route)))
    -->
    { head_pattern_position_text(Path, Where),
      head_meaning_route_text(Route, Because) },
    [ 'the head of (= (~w ...) ...) matches ~w against (~w ...), and ~w ~w. \c
       That position is matched STRUCTURALLY, so it accepts only a caller \c
       that hands it the term unevaluated: an ordinary call evaluates its \c
       own argument first and arrives as something else. Write the relation \c
       in the body with let if you meant to run ~w.'-[Fun, Where, Label,
                                                      Label, Because, Label] ].

head_pattern_position_text([Argument], Text) :- !,
    format(atom(Text), 'head argument ~w', [Argument]).
head_pattern_position_text([Argument|Rest], Text) :-
    atomic_list_concat(Rest, '.', Sub),
    format(atom(Text), 'head argument ~w, subterm ~w', [Argument, Sub]).

head_meaning_route_text(function, 'has equations here').
head_meaning_route_text(translated,
                        'is a special form or a registered translator rule').

refuse_uncompilable_seam(Form, Args) :-
    ( Args = [Goal] -> Offender = Goal ; Offender = Args ),
    throw(error(metta_uncompilable_seam(Form, Offender),
                context(Form/1, 'a Prolog seam compiles one goal'))).

%The same mistake reaches the translator by a second route that the clauses
%above cannot see. A rule whose expansion is built in Prolog returns the form
%itself. A malformed bare seam can therefore survive translation as data and
%is refused here. A quote around it is a valid inert quote value instead
%[tested translator.plt:quoted_seam_expansion_stays_inert].
refuse_seam_expanded_to_data(Rule, Out) :-
    (   nonvar(Out), Out = [Seam|_],
        ( Seam == translatePredicate ; Seam == call )
    ->  throw(error(metta_seam_expansion_as_data(Rule, Seam),
                    context(Rule, 'a translator rule expanded to data')))
    ;   true ).

prolog:error_message(metta_uncompilable_seam(Form, Offender)) -->
    [ '~w compiles one Prolog goal and needs it written as a list naming the \c
       predicate, as (~w (name $arg ...)), but it was given ~p. A translator \c
       rule that builds this form in Prolog returns it directly; quoting it \c
       there yields a list the translator can only read as data.'-[Form, Form,
                                                                   Offender] ].
prolog:error_message(metta_call_to_own_import(Name)) -->
    [ 'this runnable imports ~w and calls it, and a runnable is compiled \c
       whole before any of it runs, so the call compiles while ~w is still \c
       unregistered and answers the expression instead of the value. Put the \c
       import in its own runnable, before the one that calls it.'-[Name, Name] ].
prolog:error_message(metta_seam_expansion_as_data(Rule, Seam)) -->
    [ 'the translator rule ~w expanded to a ~w form left as data, which \c
       nothing can compile. A rule written in MeTTa evaluates its own quote \c
       and expands to what quote returned; a rule that builds the form in \c
       Prolog is already holding that term, so it returns (~w ...) without \c
       the quote around it.'-[Rule, Seam, Seam] ].

%A Python-compiled typed let carries an internal marker around the same
%in-place annotation used by an equation head. Source-level colon expressions
%remain ordinary destructuring patterns, as used by reasoning/nilbc.metta;
%shape alone cannot distinguish those data from a Python annotation.
%The value must bind before its type premise runs: checking the fresh pattern
%variable first accepts everything and then forgets the constraint. Untyped
%lets retain the occurrence-sensitive fast path below [tested:
%test_an_annotated_binding_emits_its_claim,
%translator_typed_let:a_source_colon_pair_stays_a_pattern;
%commit=c3c8ea60516dc1f45620bbe4dba3b78993ee22e3].
translate_let_dl([[__metta_typed_binding__, Pattern], Value, In],
                 AfterHead, Goals, Out) :-
    constrain_args(Pattern, ConstrainedPattern, TypeGoals),
    TypeGoals \== [],
    translate_expr_dl(ConstrainedPattern, AfterHead, AfterPattern,
                      PatternValue),
    translate_eager_argument_dl(Value, AfterPattern, AfterValue, ValueResult),
    AfterValue = [unify_with_occurs_check(PatternValue, ValueResult)|AfterUnify],
    append(TypeGoals, AfterTypes, AfterUnify),
    translate_expr_dl(In, AfterTypes, Goals, Out).

%A let unifies its pattern with its value under an occurs check, so a binding
%cannot build a term that contains itself. Where that check is emitted decides
%whether it can fire at all.
%
%Emitted before the goals that compute the value, which is where it used to
%go, it runs on a result that is still an unbound variable, and two fresh
%variables cannot fail an occurs check. The cycle is then built by the goals
%that follow: (let $x (cons-atom $x ()) $x) was accepted and left $x bound to
%a rational tree. The check was live only when the value needed no goals of
%its own, which is the case tests/prolog/translator.plt covered.
%
%Emitting it after the value's goals is not free. It then walks an
%instantiated term on every let, and let is the third most called predicate in
%the engine after arithmetic: measured on a let-heavy workload at 2.7x wall
%clock, 0.0062s to 0.0169s over five runs each, with the inference count
%identical at 248706, so neither the benchmark gate nor any other
%inference-based measure sees the difference.
%
%A computed value that shares no variable with the pattern gets a FRESH output
%variable from translation. It has appeared in no earlier goal, so binding that
%fresh variable to the pattern is plain unification: it cannot create a cycle
%even when the pattern already names a large bound term. A raw value variable
%is different: two distinct variables in a clause head may alias at runtime,
%so that path retains its early occurs check [tested:
%test_let_of_a_fresh_variable_does_not_walk_the_term]. Only a value that shares
%a source variable pays for the late occurs check.
%[measured 2026-08-21: examples/reasoning/tilepuzzle.metta, fresh-process
%m.stats() min of three, 29,633,848 before and 29,633,825 after].
%A GAP PATTERN takes neither route. Both of them are unifications, and a
%sequence variable is not one: it splits the value's children and answers once
%per split, which is what makes `(let ($pre ... SEP ... $post) $row ...)` the
%parsing-by-unification idiom rather than a single binding. It also cannot use
%the early spelling, which unifies BEFORE the value's own goals have produced
%it: a gap needs the value it is splitting. Written patterns only, so a gap
%that arrived through a binding stays data [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean, parseConcreteAtom].
%
%And a gap pattern is NOT COMPILED as an expression, which the two ordinary
%routes both do. A variable-headed pattern compiles to a reduce/3 CALL, so
%`($pre ... SEP ... $post)` reached the binding as a runtime value with no
%structure left to split, and the let answered nothing at all [measured
%2026-08-24, ai-tmp/J5-let.metta]. A pattern is matched, not evaluated, and a
%gap makes that difference visible: there is nothing to evaluate in `...`.
translate_let_dl([Pattern, Value, In], AfterHead, Goals, Out) :-
    ( metta_seq_written(Pattern)
      -> translate_eager_argument_dl(Value, AfterHead, AfterValue, ValueResult),
         metta_pattern_match_goal(Pattern, ValueResult, Decide),
         AfterValue = [Decide|AfterUnify]
       ; shares_variable(Pattern, Value)
      -> translate_expr_dl(Pattern, AfterHead, AfterPattern, PatternValue),
         translate_eager_argument_dl(Value, AfterPattern, AfterValue, ValueResult),
         AfterValue = [unify_with_occurs_check(PatternValue, ValueResult)|AfterUnify]
       ; ( var(Value)
           -> EarlyUnify = unify_with_occurs_check(PatternValue, ValueResult)
            ; EarlyUnify = (ValueResult = PatternValue) ),
         AfterHead = [EarlyUnify|BeforeValue],
         translate_eager_argument_dl(Value, BeforeValue, BeforePattern,
                                     ValueResult),
         translate_expr_dl(Pattern, BeforePattern, AfterUnify,
                           PatternValue) ),
    translate_expr_dl(In, AfterUnify, Goals, Out).

%An occurs check whose left side is a variable that has appeared NOWHERE
%earlier in the clause cannot fail. That variable is unbound when the goal
%runs, and it cannot occur inside the value, because it has not yet been
%anywhere that could have put it there. Those become =/2.
%
%What this removes is not small and the inference counter cannot see it, since
%it counts both as one goal. unify_with_occurs_check/2 walks the whole value,
%so NAMING a term costs time proportional to the term's SIZE. A let* chain of
%four bindings over one list, 20,000 times, measured 2026-08-15 at 0.0081s for
%a 10 element list, 0.0931s for 200 and 0.8730s for 2000; with the safe checks
%demoted it is a flat 0.0025s at every size. O(n) becomes O(1).
%
%translate_let_dl/4 below already avoids what it can by emitting the check
%before the value's goals, where the value is still unbound. That does nothing
%when the value IS an already-bound variable, which is what (let $y $l ...)
%over an argument compiles to, and it is the common shape.
%Cost, since the counter gate measures compilation. The first version built a
%seen-SET eagerly, calling term_variables/2 per goal, and cost 12,001
%inferences of source-load. Guarding it behind a scan for the functor made that
%worse rather than better: the scan alone accounted for the whole remaining
%regression, because it walks every clause body while only a few contain a let.
%Threading the prefix as a list of goals and inspecting it only when an occurs
%check is actually found leaves source-load at its baseline and run-source
%+998 over 1000 directives, which is one inference per compiled clause and the
%floor for any post-pass [measured 2026-08-15].
%Found comes back bound when the body holds a negation, so quantify_negations/2
%walks only the clauses that have one. It is threaded through this pass rather
%than tested for separately because a separate test is not free: a predicate
%call costs one inference and flag/3 costs two, while comparing an argument
%costs none [measured 2026-08-15, 100,000 iterations: bare loop 100002
%inferences, the same loop plus X == [] 100002, plus a dynamic call 300002,
%plus flag/3 400003]. One inference per compiled clause is what the last
%post-pass here cost, and this one costs zero.
demote_safe_occurs_checks(Head, Body0, Body, Found) :-
    demote_occurs(Body0, Body, [Head], _, Found).

%Prefix is the clause head plus every goal that can run before this one,
%newest first. It is inspected ONLY when an occurs check is actually found, so
%an ordinary goal costs one cons rather than a term_variables/2 walk. Building
%the set eagerly instead cost 5,004 inferences of source-load on its own.
demote_occurs(Goal, Goal, Prefix0, [Goal|Prefix0], _) :- var(Goal), !.
demote_occurs((A0, B0), (A, B), Prefix0, Prefix, Found) :- !,
    demote_occurs(A0, A, Prefix0, Prefix1, Found),
    demote_occurs(B0, B, Prefix1, Prefix, Found).
%The else branch runs only when the condition FAILED, which undid the
%condition's bindings, so it starts from where the condition started.
demote_occurs((C0 -> T0 ; E0), (C -> T ; E), Prefix0, Prefix, Found) :- !,
    demote_occurs(C0, C, Prefix0, PrefixC, Found),
    demote_occurs(T0, T, PrefixC, _, Found),
    demote_occurs(E0, E, Prefix0, _, Found),
    Prefix = [(C0 -> T0 ; E0)|Prefix0].
demote_occurs((C0 *-> T0 ; E0), (C *-> T ; E), Prefix0, Prefix, Found) :- !,
    demote_occurs(C0, C, Prefix0, PrefixC, Found),
    demote_occurs(T0, T, PrefixC, _, Found),
    demote_occurs(E0, E, Prefix0, _, Found),
    Prefix = [(C0 *-> T0 ; E0)|Prefix0].
demote_occurs((C0 -> T0), (C -> T), Prefix0, Prefix, Found) :- !,
    demote_occurs(C0, C, Prefix0, PrefixC, Found),
    demote_occurs(T0, T, PrefixC, _, Found),
    Prefix = [(C0 -> T0)|Prefix0].
demote_occurs((A0 ; B0), (A ; B), Prefix0, Prefix, Found) :- !,
    demote_occurs(A0, A, Prefix0, _, Found),
    demote_occurs(B0, B, Prefix0, _, Found),
    Prefix = [(A0 ; B0)|Prefix0].
%Wrappers whose argument is an ordinary goal. Bindings made inside findall/3
%and \+/1 do not escape, so counting their variables as possibly bound
%afterwards is conservative: it costs an optimisation, never soundness.
demote_occurs(findall(T, G0, L), findall(T, G, L), Prefix0, Prefix, Found) :- !,
    demote_occurs(G0, G, Prefix0, _, Found),
    Prefix = [findall(T, G0, L)|Prefix0].
demote_occurs(forall(C0, A0), forall(C, A), Prefix0, Prefix, Found) :- !,
    demote_occurs(C0, C, Prefix0, PrefixC, Found),
    demote_occurs(A0, A, PrefixC, _, Found),
    Prefix = [forall(C0, A0)|Prefix0].
demote_occurs(\+ G0, \+ G, Prefix0, Prefix, Found) :- !,
    demote_occurs(G0, G, Prefix0, _, Found),
    Prefix = [\+ G0|Prefix0].
demote_occurs(once(G0), once(G), Prefix0, Prefix, Found) :- !,
    demote_occurs(G0, G, Prefix0, _, Found),
    Prefix = [once(G0)|Prefix0].
demote_occurs(unify_with_occurs_check(Pattern, Value), Out, Prefix0, Prefix, _) :- !,
    (   var(Pattern),
        \+ occurs_in(Pattern, Prefix0),
        \+ occurs_in(Pattern, Value)
    ->  Out = (Pattern = Value)
    ;   Out = unify_with_occurs_check(Pattern, Value)
    ),
    Prefix = [unify_with_occurs_check(Pattern, Value)|Prefix0].
%A negation is the only goal this pass reports rather than rewrites. Its own
%functor gives it an index bucket of its own, so recognising it costs the
%goals that are not negations nothing.
demote_occurs(metta_negation(L, S, T, D, O), metta_negation(L, S, T, D, O),
              Prefix0, [metta_negation(L, S, T, D, O)|Prefix0], Found) :- !,
    ( var(Found) -> Found = found ; true ).
%Anything else is opaque. Its own goals are left alone and every variable it
%mentions counts as possibly bound from here on.
demote_occurs(Goal, Goal, Prefix0, [Goal|Prefix0], _).

occurs_in(Var, Term) :- term_variables(Term, Vars), memberchk_eq(Var, Vars).

%Rewrite every (sealed <vars> <expr>) inside a term so its named variables are
%renamed apart, and report the variables that rename produced. Renaming the
%whole (sealed ...) form, var list included, keeps the form consistent for the
%later translation, which renames again and finds nothing left to do.
%
%The rename alone is not enough, and that was the first attempt: a renamed
%variable is still a variable of the body, so it still counted as free and the
%lambda still captured it. What the rename buys is the ability to TELL the two
%apart, so a variable used both inside a sealed form and outside it stays free
%for its outside occurrences and is excluded only for its inside ones.
seal_lambda_locals(Term, Sealed, Locals) :-
    (   nonvar(Term), Term = [Head, Ignored, Expr], Head == sealed
    ->  seal_lambda_locals(Expr, Inner, InnerLocals),
        term_variables(Inner, InnerVariables),
        term_variables(Ignored, IgnoredVariables),
        exclude({IgnoredVariables}/[Variable]>>
                    memberchk_eq(Variable, IgnoredVariables),
                InnerVariables, FreshVariables),
        copy_term(FreshVariables, [sealed, Ignored, Inner], FreshCopies,
                  Sealed),
        runnable_note_copied_variables(FreshVariables, FreshCopies),
        maplist(remap_copied_variable(FreshVariables, FreshCopies),
                InnerLocals, RemappedInnerLocals),
        append(FreshCopies, RemappedInnerLocals, Locals0),
        term_variables(Locals0, Locals)
    ;   nonvar(Term), Term = [_|_]
    ->  seal_lambda_locals_list(Term, Sealed, Locals)
    ;   Sealed = Term, Locals = []
    ).

remap_copied_variable([Original|_], [Copy|_], Variable, Copy) :-
    Original == Variable, !.
remap_copied_variable([_|Originals], [_|Copies], Variable, Remapped) :-
    remap_copied_variable(Originals, Copies, Variable, Remapped).
remap_copied_variable([], [], Variable, Variable).

seal_lambda_locals_list(Term, Sealed, Locals) :-
    (   Term == []
    ->  Sealed = [], Locals = []
    ;   nonvar(Term), Term = [Head|Tail]
    ->  seal_lambda_locals(Head, SealedHead, HeadLocals),
        seal_lambda_locals_list(Tail, SealedTail, TailLocals),
        Sealed = [SealedHead|SealedTail],
        append(HeadLocals, TailLocals, Locals)
    ;   Sealed = Term, Locals = []
    ).

%Every variable a lambda body BINDS for itself, so the free-variable analysis
%above can leave it out of the capture set. One clause per binding form, and
%the form's own head is the specification: `let` and `chain` bind their
%pattern, `let*` binds every pair's pattern, the three collection forms bind
%their binder variables, and a nested lambda binds its parameters. A form not
%listed here binds nothing, which is the safe direction: the variable stays
%captured and behaves exactly as it did.
%
%The walk is the body's whole term, because a binding form may sit anywhere in
%it, and it deliberately does NOT rename: two occurrences of one name inside
%one form are one variable, so a name used as a binder here is a local
%throughout this body. `sealed` above renames instead, because its whole
%purpose is to localise a name that IS used outside.
lambda_body_binders(Term, Binders) :-
    (   nonvar(Term), Term = [Head|_], atom(Head), lambda_binder_form(Term, Bound)
    ->  term_variables(Bound, Own)
    ;   Own = []
    ),
    (   nonvar(Term), Term = [_|_]
    ->  lambda_body_binders_list(Term, Nested)
    ;   Nested = []
    ),
    append(Own, Nested, Binders0),
    term_variables(Binders0, Binders).

lambda_body_binders_list([], []).
lambda_body_binders_list([Head|Tail], Binders) :-
    lambda_body_binders(Head, HeadBinders),
    lambda_body_binders_list(Tail, TailBinders),
    append(HeadBinders, TailBinders, Binders).

lambda_binder_form([let, Pattern, _, _], Pattern).
lambda_binder_form([chain, _, Pattern, _], Pattern).
lambda_binder_form(['let*', Pairs, _], Patterns) :-
    is_list(Pairs),
    findall(Pattern, member([Pattern, _], Pairs), Patterns).
lambda_binder_form(['map-atom', _, Binder, _], Binder).
lambda_binder_form(['filter-atom', _, Binder, _], Binder).
lambda_binder_form(['foldl-atom', _, _, Accumulator, Item, _],
                   [Accumulator, Item]).
lambda_binder_form(['|->', Parameters, _], Parameters).

%Whether two terms have a variable in common. A let pattern is ordinarily one
%variable, so settle that shape without building and walking a one-item list;
%this offsets the fresh-output decision on the same compile path.
shares_variable(A, B) :- var(A), !,
                         term_variables(B, [First|Rest]),
                         ( A == First -> true ; memberchk_eq(A, Rest) ).
shares_variable(A, B) :- term_variables(A, VarsA),
                         VarsA \== [],
                         term_variables(B, VarsB),
                         member(Var, VarsA),
                         memberchk_eq(Var, VarsB), !.

translate_space_update_dl(Operation, [SpaceExpr, Atom], AfterHead, Goals,
                          Out) :-
    translate_space_expr_dl(SpaceExpr, AfterHead, BeforeOperation, Space),
    Goal =.. [Operation, Space, Atom, Out],
    translate_restricted_guard_dl(
        metta_require_space_update_capability(Operation, Space), [Goal|Goals],
        BeforeOperation).

%A registered expression is an entity identifier in a space position. Every
%other expression is still evaluated, preserving computed spaces such as
%(add-atom (space-name) atom). The registry test is therefore the boundary,
%not list shape alone.
translate_space_expr_dl(SpaceExpr, Goals0, Goals, Space) :-
    nonvar(SpaceExpr),
    metta_space_operand(SpaceExpr), !,
    Space = SpaceExpr,
    Goals0 = Goals.
translate_space_expr_dl(SpaceExpr, Goals0, Goals, Space) :-
    translate_expr_dl(SpaceExpr, Goals0, Goals, Space).

%All four spellings of one operation, so all four keep their name list as
%data. lib_zar's two were missing, and a list holding a name that had ALREADY
%become a function then compiled to a call: (zar_add zar_typo) became a
%partial application of zar_add, the declared Expression check on it failed,
%and the whole import answered nothing at all, with no error
%[tested: an_importer_name_list_stays_data].
prolog_function_importer(import_prolog_functions_from_file).
prolog_function_importer(import_prolog_functions_from_module).
prolog_function_importer(import_prolog_functions_from_file_pred).
prolog_function_importer(import_prolog_functions_from_module_pred).

translate_prolog_import_dl(Importer, [File, FunctionNames], Goals0, Goals, Out) :-
    atom(Importer),
    prolog_function_importer(Importer),
    note_runnable_import(FunctionNames),
    translate_expr_dl(File, Goals0, BeforeImport, ResolvedFile),
    Goal =.. [Importer, ResolvedFile, FunctionNames, Out],
    space_operation_capability(Importer, Capability),
    %The FORCE travels in the emitted goals, at run time rather than compile
    %time, because the importer is itself a MeTTa equation (lib_import.metta
    %defines it) that this special form calls directly without the dispatch
    %analysis whose door would otherwise force it. Compile-time forcing is
    %not enough: the form can compile before the equation arrives, and the
    %undefined-predicate net cannot catch the miss on a POOLED space, where
    %SWI does not consult the hook again for a name that was defined and
    %abolished in an earlier life.
    translate_restricted_guard_dl(
        metta_require_current_capability(Importer, Capability),
        [metta_ensure_compiled(Importer), Goal|Goals],
        BeforeImport).

%Recorded only while a runnable is being compiled, which is the only place the
%mistake this guards against can happen: a stored equation is compiled once
%and repaired by the change hooks when a name it calls arrives later.
note_runnable_import(Names) :-
    (   translating_runnable,
        is_list(Names)
    ->  forall(( member(Name, Names), atom(Name) ),
               assertz(runnable_import(Name)))
    ;   true
    ).

%Generate actual function call or partial if arity not complete:
build_call_or_partial_dl(Fun, AVs, Out, Goals0, Goals, Extra) :-
    metta_ensure_compiled(Fun),
    length(AVs, N),
    Arity is N + 1,
    ( maybe_specialize_call(Fun, AVs, Out, Goal)
      -> dispatch_call_goal(Fun, AVs, Out, Goal, PolicyGoal),
         append([PolicyGoal|Extra], Goals, Goals0)
    ; arity(Fun, Arity)
      -> resolve_dispatch(Fun, AVs, Out, Goal),
         dispatch_call_goal(Fun, AVs, Out, Goal, PolicyGoal),
         append([PolicyGoal|Extra], Goals, Goals0)
    ; metta_segment_equation(Fun)
      -> current_metta_module(Module),
         Goal = metta_segment_dispatch(Module, Fun, AVs, Out),
         dispatch_call_goal(Fun, AVs, Out, Goal, PolicyGoal),
         append([PolicyGoal|Extra], Goals, Goals0)
    ; incomplete_application_kind(Fun, Arity, partial)
      -> Out = partial(Fun, AVs),
         Goals0 = Goals
    ; Goals0 = [function_overapplication(Fun, AVs, Out)|Goals] ).

%A branch that compiled to a goal has already been evaluated, exactly as an
%equation body has, so only the goal-free non-ground branch takes the
%continuation and every ordinary branch compiles to what it always did.
unify_branch(Written, true, Value, Out, Branch) :-
    \+ ground(Written),
    !,
    masked_result_goal(Value, Out, Branch).
unify_branch(_, Conj, Value, Out, Branch) :-
    build_branch(Conj, Value, Out, Branch).

%THE EMBEDDED-OPERATION VOCABULARY, transcribed from the reference's own list
%rather than inferred: the twelve reflected minimal forms plus the interpreter
%operations that touch the threaded world, which are stepped for the same
%reason they are not groundings there
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:331-346,
%`embeddedOpNames` and `isEmbeddedOp`, whose header says keeping the names as
%data "lets effect and coverage checks follow the same dispatch boundary as the
%interpreter"; the transcription is complete, so a name this engine has no
%operation for simply never matches].
%
%Two decisions read it. A `chain` operand it names is EXECUTED and one it does
%not is data, which is why `!(chain (+ 1 2) $x (quote $x))` keeps the sum
%unreduced while `!(chain (cons-atom a (b)) $x (quote $x))` does not. An
%Atom-returning equation whose body it names still RUNS that body, which is the
%`!isEmbeddedOp` guard the reference records
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:800-808, "guarded by
%`!isEmbeddedOp` so a bare `(chain …)` function body is still run"].
%
%Every name here and eleven names outside it were each measured on LeaTTa
%9ea9f9d on 2026-08-24, one probe per head, and the measured split is this
%list exactly: `car-atom`, `index-atom`, `union-atom`, `format-args`, `==`,
%`if-equal`, `noeval`, `quote`, `collapse`, `superpose` and arithmetic are all
%data, and `new-state` is data while `_new-state` is named here.
embedded_operation(Term) :-
    nonvar(Term),
    Term = [Head|_],
    atom(Head),
    embedded_operation_head(Head).

%THE SHAPE THE RESULT CONTINUATION IS EMITTED IN, and the inline test in front
%of it is what keeps the rule off the arithmetic path. Only a COMPOUND answer
%can hold a redex, so a scalar is handed straight back by a test the VM decides
%and no inference is raised: `car-atom` in a counting loop answers a number a
%million times and the loop stays at its shipped inference baseline
%[measured 2026-08-24: let-heavy 16,002,687 inferences with a bare call against
%13,002,567 with this guard, on a 13,002,562 baseline].
%
%THE COMMON CASE IS THE `then` BRANCH, and the order was measured rather than
%chosen: with the compound test first and the scalar in the `else`, the same
%loop retires 7,693,833,487 instructions against 7,612,826,746 this way round,
%1.05% for reversing two branches [measured 2026-08-24, min of three]. What
%remains over the 7,541,707,255 the unchanged engine retires is one extra goal
%and one extra variable in a clause the loop runs a million times, which is
%what the result rule costs where an operation's answer could be an expression.
%
%`Produced` is always bound by the goal above it, and a partial application is
%compound, so it takes the call and is handed back unchanged by it.


masked_result_goal(Produced, Out,
                   (   atomic(Produced)
                   ->  Out = Produced
                   ;   metta_masked_result(Produced, Out)
                   )).

%Compiled equations cross metta_application_result/4 at their call site.
%Native and grounded operations instead use reduce/3's status-carrying seam,
%so this result continuation can retain the old scalar-fast shape: an Atom
%result is final, and every other compound result re-enters evaluation.
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:7350-7361 and
%7533-7564; tested: translator_evaluation_errors and conformance2;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
%An Atom-result masker answers as produced AND may be handing written
%material onward, so it raises the escape flag on a compound answer; the
%flag is what a later non-masking boundary consults before walking.  A
%user function whose chain masks and returns Atom is the same shape
%through call_site_type_chains.  Both tests run at compile time; the
%emitted goal for every ordinary final result stays `Out = Produced`.
call_result_goal(Written, _, Produced, final, Out, Goal) :-
    (   nonvar(Written),
        Written = [Fun|_],
        atom(Fun),
        masked_smuggler_head(Fun)
    ->  Goal = ( Out = Produced,
                 (   compound(Produced)
                 ->  system:b_setval('$metta_masked_escape', true)
                 ;   true
                 ) )
    ;   Goal = (Out = Produced)
    ).
%A native operation that cannot compute answers its own runtime call, which
%is minimal MeTTa's NoReduce for grounded operations. That answer is
%irreducible by construction, so the continuation keeps it as data; sending it
%back through evaluation re-ran the same operation and looped: `!(< 1 a)`
%overflowed the stack re-translating `(< 1 a)` once per retained answer
%[source: vendor/hyperon/docs/minimal-metta.md:55-101, grounded operations
%returning NoReduce; tested: test_an_operation_that_cannot_compute_answers_rather_than_raising
%and conformance2; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
%The retained-answer test sits on the non-atomic branch only: arithmetic and
%string results are atomic and answer directly, so the hot all-scalar paths
%pay nothing for the guard [measured 2026-08-25: testing equality before
%atomicity cost let-heavy +4,000,162 and loop-1m +2,000,085 inferences, about
%two per evaluated native call; this shape restored both pins exactly].
%A masked operand is the one way an unreduced subterm reaches a result.  A
%callee that masks an argument itself (car-atom) can hand such a subterm
%out directly, so its boundary walks unconditionally.  Every other callee's
%answer can carry a redex only when some Atom-result masker smuggled one
%into the value flow earlier -- `(id (noeval (+ 20 22)))` is the arbiter's
%pinned case -- and the escape flag those producers raise is consulted in
%one b_getval before any walk.  With the flag down the boundary is plain
%unification, which also covers the retained-answer case, because a
%retained call IS the produced value.  Walking unconditionally priced a
%caller by the SIZE of the callee's answer, which turned a breadth-first
%search carrying its queue through SWI's foldl/4 quadratic: the fold's
%result walk visited every held state once per iteration, 3.9x call growth
%for 2x the iterations on examples/reasoning/tilepuzzle.metta.
%[tested: translator_equations:a_function_call_result_is_not_rewalked_for_redexes,
%conformance2:a_builtin_polymorphic_result_reenters_evaluation;
%commit=44ea37314b24f799a2080901172db66a94cb7791].
call_result_goal(Written, Runtime, Produced, evaluated, Out, Goal) :-
    (   nonvar(Written),
        Written = [Fun|WrittenArgs],
        atom(Fun),
        \+ builtin_call_mask(Fun, _),
        \+ written_args_carry_a_masker(WrittenArgs)
    ->  Goal = (   atomic(Produced)
               ->  Out = Produced
               ;   Produced == Runtime
               ->  Out = Produced
               ;   system:b_getval('$metta_masked_escape', true)
               ->  metta_masked_result(Produced, Out)
               ;   Out = Produced
               )
    ;   Goal = (   atomic(Produced)
               ->  Out = Produced
               ;   Produced == Runtime
               ->  Out = Produced
               ;   metta_masked_result(Produced, Out)
               )
    ).

%`(id (noeval (+ 20 22)))` resolves noeval at COMPILE time, so no runtime
%producer ever raises the escape flag for it: the smuggling is textually
%visible in the written arguments instead, and this walk finds it there.
%A bare variable stays clear -- a redex can reach a variable's runtime
%value only through a runtime masker, and those raise the flag themselves.
written_args_carry_a_masker(Args) :-
    member(Arg, Args),
    written_term_carries_a_masker(Arg),
    !.

written_term_carries_a_masker(Term) :-
    nonvar(Term),
    Term = [Head|Tail],
    (   atom(Head),
        masked_smuggler_head(Head)
    ->  true
    ;   (   written_term_carries_a_masker(Head)
        ->  true
        ;   written_term_carries_a_masker(Tail)
        )
    ).

masked_smuggler_head(Fun) :-
    (   builtin_result_smuggler(Fun)
    ->  true
    ;   call_site_type_chains(Fun, Chains),
        member(Chain, Chains),
        chain_masks_an_argument(Chain)
    ->  true
    ;   fail
    ).

%The one head that is a FRAME rather than a value, so an Atom-returning
%equation whose body is one still runs it.
function_frame_body(Term) :-
    nonvar(Term),
    Term = [function, _].

embedded_operation_head(eval).
embedded_operation_head(evalc).
embedded_operation_head(chain).
embedded_operation_head(unify).
embedded_operation_head('unify%').
embedded_operation_head('cons-atom').
embedded_operation_head('decons-atom').
embedded_operation_head(function).
embedded_operation_head('collapse-bind').
embedded_operation_head('superpose-bind').
embedded_operation_head(metta).
embedded_operation_head('metta-thread').
embedded_operation_head(capture).
embedded_operation_head('context-space').
embedded_operation_head('pragma!').
embedded_operation_head(match).
embedded_operation_head('get-metatype').
embedded_operation_head('get-type').
embedded_operation_head('get-type-space').
embedded_operation_head('_new-state').
embedded_operation_head('get-state').
embedded_operation_head('change-state!').
embedded_operation_head('new-space').
embedded_operation_head('new-mork-space').
embedded_operation_head('fork-space').
embedded_operation_head('add-atom').
embedded_operation_head('remove-atom').
embedded_operation_head('get-atoms').
embedded_operation_head('bind!').
embedded_operation_head('import!').
embedded_operation_head('import-into!').
embedded_operation_head('import-item!').
embedded_operation_head(include).
embedded_operation_head('mod-space!').
embedded_operation_head('git-import!').
embedded_operation_head('git-module!').
embedded_operation_head('module-space-no-deps').
embedded_operation_head('print-mods!').
embedded_operation_head('module-tree!').
embedded_operation_head('loaded-mods!').
embedded_operation_head('println!').
embedded_operation_head('trace!').
embedded_operation_head('skel-swap-pair-native').
embedded_operation_head('match%').
embedded_operation_head(sealed).
embedded_operation_head('fuzzy-match-space').
embedded_operation_head('fuzzy-match-context').

%Replace every occurrence of one written variable, leaving every other variable
%shared with the surrounding clause. copy_term/2 cannot do this: it renames the
%template's OTHER variables too, and those are the equation's own.
substitute_written_variable(Variable, Value, Term, Substituted) :-
    (   Term == Variable
    ->  Substituted = Value
    ;   var(Term)
    ->  Substituted = Term
    ;   is_list(Term)
    ->  maplist(substitute_written_variable(Variable, Value), Term, Substituted)
    ;   compound(Term)
    ->  Term =.. [Functor|Arguments],
        maplist(substitute_written_variable(Variable, Value), Arguments,
                Substituted0),
        Substituted =.. [Functor|Substituted0]
    ;   Substituted = Term
    ).
