% Purpose: compile MeTTa expressions and equations into executable Prolog,
%   including dynamic dispatch, control forms, higher-order calls, and
%   branch-return optimization.
% Assumes:
%   - merge_branch_returns/3 does not bind variable keys until its assoc
%     lookups finish [source 2026-08-14:
%     https://www.swi-prolog.org/pldoc/doc/_SWI_/library/assoc.pl].
%   - '$skip_list'(-Length, +List, -Tail) reports the tail a list spine ends
%     in without instantiating it, which is what separates a pair list that
%     has not arrived from one that is no list at all
%     [source 2026-08-19: SWI-Prolog 10.1.13
%     /usr/lib/swi-prolog/library/error.pl:311-315, not_a_list/2].
%   - translate_clause/3's third argument is the boolean that says whether to
%     constrain the head arguments [measured 2026-08-19 by wrapping it and
%     reading every call 45 shipped examples make: `true` or `false` every
%     time]. It is a PlDoc mode line above the clause, so the development
%     build checks it at run time [tested: the_dev_build_inserts_checks_and_types_a_planted_violation].
%     Its other two arguments, and every argument of translate_expr/3,
%     translate_expr_to_conj/3 and translate_runnable_expr/3, are terms UNDER
%     CONSTRUCTION, so their mode lines record modes and no types: a check on
%     a non-ground value is a when/2 coroutine, and a term carrying one is no
%     longer a variant of the same term without one, which changes what =@=/2
%     answers about a term the engine stores.
% Guarantees:
%   - Files below engine/translator/ are plain source units consulted into this
%     implementation module in their original order; no predicate ownership or
%     call qualification changes at the source-layout boundary
%     [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE].
%   - Runnable translations are cached as fresh templates by execution module
%     and a copy_term/2 plus numbervars/4 variant key; changing or removing a
%     mentioned function evicts every dependent template
%     [tested: translation_cache; commit=d90a3c9620e56e42d3a2f5982b4353da8423e873].
%   - A runtime-type-guarded built-in, or format-args, whose written operands
%     already contradict its declared parameter types is refused before those
%     operands run, while accepted and undecided operands retain ordinary
%     translation
%     [tested: operation_answers, test_a_repeated_eval_does_not_recompile_and_the_effects_cluster_conforms; commit=8d0027a3942000c799daccb45bf0abe1b46b10aa].
%   - User get-type equations extend the deduplicating type boundary through
%     get_type_rule/2 [tested 2026-08-15: translator_type_extensions].
%   - Branch-return merging preserves shared and pre-bound variables while
%     restoring private tail returns [tested 2026-08-14:
%     translator_branch_returns].
%   - A typed function remains partially applicable until it has produced a
%     return value [tested 2026-08-14: translator_typed_currying].
%   - Every compiled user-function call consults the six declarations in its
%     effective dispatch policy, and non-default order/failure modes execute
%     from retained equation support without changing the default fast path
%     [tested: test_every_dispatch_axis_is_readable_settable_and_defaulted; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - A parameter type declared as DontEvalType receives its written argument
%     without evaluation, independent of the type's name
%     [tested: test_a_user_declared_lazy_type_receives_its_argument_unevaluated; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - Every head pattern position the compiler decides something about, a type
%     annotation compiled to a goal or a label that already has meaning
%     through either of the engine's two routes, is recorded in
%     head_pattern_note/5 and said through print_message/2, and a position
%     whose parameter carries the evaluation mask is neither
%     [tested: translator_head_pattern_notes,
%     test_the_compiler_names_a_pattern_position_it_turned_into_a_goal;
%     commit=4465fc492071932eab0b2818a4ccd46f01f0d6aa].
%   - A translator rule is applied by matching: its head shape and its body
%     goals cannot instantiate the call, and a rule that would have to falls
%     back to the next clause and then to ordinary dispatch
%     [tested: translator_rule_matching,
%     test_a_guard_that_binds_a_pattern_variable_cannot_create_a_match;
%     commit=4465fc492071932eab0b2818a4ccd46f01f0d6aa].
%   - Exact arrow arity is decided through the shared typing_rule_entry/7
%     registry rather than a compiler-local equality
%     [tested: test_a_user_typing_rule_participates_like_a_shipped_one;
%     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - The Number fast path admits both signed-i64 Number integers and wider
%     BigInt integers, matching the type boundary's directed compatibility
%     rule [tested 2026-08-20:
%     bigint_number:number_accepts_bigint_but_bigint_stays_narrow].
%   - Arity selection does not compile typed arguments before their branch
%     translation [tested 2026-08-14: translator_typed_single_pass].
%   - Empty special-form inputs have explicit identity or failure semantics
%     [tested 2026-08-14: translator_empty_forms].
%   - Dynamic and compiled calls surface the same runtime errors
%     even when builtin type declarations are loaded [tested 2026-08-15:
%     translator_evaluation_errors].
%   - Compiler diagnostics contain ANSI escapes only on terminal streams
%     [tested 2026-08-14: translator_terminal_output].
%   - A lambda's compiled clause lands in the space it was written in, so
%     every lambda form reaches that space's own functions [tested 2026-08-16:
%     translator_lambda_space_scope]. +10 inferences once per lambda
%     compiled, nothing per call [measured 2026-08-16: 1338 to 1348 for one
%     compile-and-run, 10,005 either way over 2,000 elements].
%   - Special forms dispatch through first-argument-indexed clauses
%     [tested 2026-08-14: translator_special_dispatch].
%   - The translatePredicate and call seams refuse a shape they cannot compile
%     rather than building a data list named after the form
%     [tested 2026-08-16: translator_special_dispatch:malformed_seam_is_refused].
%   - restricted calls preserve capability checks through direct, computed,
%     and raw-Prolog translation paths [tested:
%     test_a_restricted_space_cannot_reach_what_its_base_does_not_publish;
%     commit=6a08901f4125c2536f5b4032daac9937f793870f].
%   - the constructor holds a parametric identifier before it is registered,
%     and registered identifiers stay literal at space positions while every
%     unregistered expression keeps the established computed-space path [tested:
%     test_two_instances_of_a_parametric_space_answer_independently;
%     commit=3c7bcde6a0670ec5c563584b26977b41cc727580].
%   - A translator rule whose expansion is built in Prolog compiles to the
%     goals it emits, including a constant folded at compile time, and is
%     refused when a quote leaves that expansion as data
%     [tested 2026-08-16: translator_prolog_authored_rules].
%   - Higher-arity dynamic calls bypass the operator-table lookup, because
%     reduce/3's guard tests the arity before it consults current_op/3
%     [tested 2026-08-18: translator_operator_dispatch].
%   - A function's retained equations belong to the module that compiled them,
%     and reading them follows that module's own chain, so a definition in one
%     space cannot add a clause to another space's specialization
%     [tested: specializer_invalidation:
%     a_definition_in_another_space_does_not_double_an_answer].
%   - Recording an equation does not copy the equations already held for its
%     function, so filling a store is linear in the equation count
%     [tested 2026-08-18: recording_equations_costs_no_more_than_linear_time]
%     [measured 2026-08-18: 79 inferences per equation plus a fixed 7, at
%     250, 500, 1,000 and 2,000 equations].
%   - Expression translation is linear in nesting depth for the call, head,
%     let and conditional shapes [tested 2026-08-18:
%     every_nesting_shape_compiles_in_linear_work] [measured 2026-08-18:
%     59.01, 8.01, 13.01 and 79.01 inferences per level at depth 400].
%   - Branch-return merging stays far from quadratic in nesting depth, which
%     is what carrying its candidate returns in an assoc buys
%     [tested 2026-08-18: merging_stays_far_from_quadratic_in_nesting_depth]
%     [measured 2026-08-18: 2.11x to 2.14x per doubling from depth 50 to 400].
%   - Prolog import forms have exactly one translation
%     [tested 2026-08-14: translator_prolog_imports].
%   - Space-headed translatePredicate forms use the space provider instead of
%     a predicate inherited from user [tested:
%     translator_special_dispatch:space_predicates_use_space_storage].
%   - Source-load rollback removes retained metadata, generated lambdas, and
%     symbol-head notes [tested 2026-08-14: filereader_source_rollback].
%   - maybe_print_compiled_clause/3's trace output works under autoload=false
%     too [measured 2026-08-18: NO_AUTOLOAD=1 sh test.sh, the full
%     examples/ corpus].
%   - maybe_print_compiled_clause/3 uses the presentation writer because its
%     compiled Prolog terms are diagnostics rather than MeTTa serialization
%     [tested: specializer:compound_partial_key_has_stable_anonymous_variables;
%     commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%   - A cases argument that has not arrived, either because its list spine
%     ends in a variable or because a pair in it is still one, compiles to a
%     runtime path instead of running select/3 over it forever or unifying
%     translate_case/5's own pattern into the source, and a value arriving
%     there that is not a list of (pattern value) pairs is refused naming the
%     form and printing the argument as MeTTa
%     [tested 2026-08-19: translator_case_open_cases].
%   - Cases handed over as a value answer what the same cases written out
%     answer, over sixteen shapes including the Empty default, a
%     nondeterministic key, a functional pattern and a nested case, so a
%     one-line switch is an ordinary definition again
%     [tested 2026-08-19: translator_case_computed_cases]. Writing them out is
%     unaffected: byte-identical compiled goals over twelve case shapes,
%     including the two that decide where the default comes from, an Empty
%     pair anywhere in the list and a pair of two variables that is an
%     ordinary branch rather than a default, and 3 inferences a call at 3, 12
%     and 24 cases against 78, 258 and 498 for the same cases handed over
%     [measured 2026-08-19].
%   - A let* whose bindings have not arrived, either because the whole list
%     is still a variable or because a pair in it is, compiles to a runtime
%     path instead of dropping the bindings into the rewrite's empty-list
%     base clause, and a value arriving there that is not a list of
%     (pattern value) pairs is refused naming the form and printing the
%     argument as MeTTa
%     [tested 2026-08-19: translator_letstar_unarrived_bindings].
%   - Bindings handed over as a value bind the body exactly as the same
%     bindings written out do, so `let*` under another name is an ordinary
%     definition [tested 2026-08-19: translator_letstar_computed_bindings,
%     examples/control/letstarcomputed.metta]. Writing them out is
%     unaffected: the 203-example corpus answers identically, group for
%     group, and a call costs a flat 3 inferences at 2 and at 16 bindings
%     against 62 and 370 for the same bindings handed over
%     [measured 2026-08-19].
%   - A form the engine's prelude ships as a translator rule compiles to what
%     its expansion compiles to, goal for goal, and a rule that does not
%     apply leaves the call to ordinary dispatch rather than failing the
%     equation around it [tested 2026-08-19: translator_derived_forms]. Eight
%     forms moved out of translate_special_dl/5 and rewrite_streamops/2 that
%     way, for -0.2313% of the corpus's deterministic inference count and no
%     change to any answer [measured 2026-08-19; KERNEL.md carries the
%     per-head ledger].
%   - An equation head is a PATTERN at every depth, matched structurally,
%     whatever a label inside it happens to have equations for, so a head and
%     a match that reads the same shape back agree
%     [tested 2026-08-19: translator_head_is_a_pattern]. The only head
%     argument that is not pure structure is the in-place annotation
%     `(: $x T)`, which is a constraint on what the position may match.
% Fails when:
%   - a case whose cases are not written out sits on a hot path. It costs one
%     translation per call, and a case body holding a lambda generates one
%     predicate per call that nothing collects. eval/2 is the engine's other
%     runtime-translation door and behaves identically, so this is the shape
%     of runtime translation here rather than anything case adds
%     [measured 2026-08-19: 51 calls of a lambda-bearing computed case left
%     51 generated lambdas and 50 evals of the same expression left 50 more,
%     while a body with no lambda left none]. Writing the cases out compiles
%     them once and pays neither cost. A let* whose bindings are not written
%     out carries the same cost for the same reason.
%   - a program relied on an equation head EVALUATING a position, which this
%     engine used to do wherever the label had equations. `(= (h (myfunc (10)
%     $B) $C) ($B $C))` no longer constrains its argument by running myfunc
%     backwards; the constraint is written in the body, where `let` unifies
%     the argument with what the call produces and answers the same answers
%     [tested: examples/functions/functionhead.metta,
%     examples/functions/functionhead2.metta,
%     examples/functions/functionhead3.metta,
%     examples/libraries/patrick.metta,
%     examples/reasoning/tilepuzzle.metta].
%   - the DUAL of a let* whose bindings have not arrived is asked for.
%     engine/duals.pl builds duals at compile time from the recorded MeTTa body,
%     so bindings that arrive at run time have no dual, and (not-provable ...)
%     over such a form declines rather than answering [tested 2026-08-19:
%     duals_let]. The same limit applies to case and has since it gained its
%     own runtime path.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None
% Owns resources:
%   - '$petta_translation_cache' serializes first publication and dependency
%     eviction; translated_form_cache/6 and translated_form_mention/2 retain
%     templates until a mentioned function changes or the process exits.

%The compiler's surface: what compiles a form, what the compiled clause's
%metadata answers, the runtime helpers a compiled body calls, and the
%questions the loader, the spaces and the duals ask while a program is being
%built. Everything else -- the expression walk, the dispatch planner, the
%type-chain solver, the head-pattern notes, the translation cache's own
%tables -- is the compiler's own, and a caller that wants one says translator:
%and means it
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
%
%The runtime helpers on this list are also seam:engine_emitted/1 names: the
%compiler writes case_runtime/3, letstar_runtime/3, function_overapplication/3
%and the two dispatch results into clause bodies, so a space's execution module
%imports them from the engine's module and they have to reach it from here.
:- module(translator,
          [ translate_clause/2,
            translate_clause/3,
            translate_expr/3,
            translate_cached_expr/3,
            translate_runnable_expr/3,
            translate_runnable_expr/4,
            with_runnable_variable_epochs/1,
            clear_translation_cache/0,
            invalidate_translated_forms/1,
            index_masking_data_heads/0,
            maybe_print_compiled_clause/3,

            compiled_function_name/2,
            metta_special_form/1,
            metta_special_form_head/1,
            metta_translated_head/1,
            metta_reducible_head/2,
            uses_super/2,
            fun_meta_clauses/3,
            clear_fun_meta/2,
            drop_fun_meta/4,
            arrived_pairs/1,
            call_site_type_chains/2,
            fitting_type_chains/3,
            constrain_args/3,
            drop_unconstraining_types/3,
            letstar_to_rec_let/3,
            memberchk_eq/2,
            reduce/2,
            reduce/3,
            eval_metta_in_module/3,
            lift_pattern_modifiers/3,
            metta_host_dispatch_proof_step/6,
            %The head-context note engine/filereader.pl reads to decide whether a
            %symbol was executed as a runnable or as a clause head.
            symbol_head/2,

            %The head-context note engine/duals.pl reads while it builds a dual.
            head_pattern_note/5,

            % Emitted into compiled bodies. Four of these were never declared
            % in seam:engine_emitted/1 either, and are now: agg_reduce/4,
            % hyperpose_branch/4, hyperpose_runtime/2 and
            % metta_condition_holds/2 are goals this file writes into the
            % clauses it generates, so a MeTTa function of any of those names
            % at the matching arity would have captured them.
            agg_reduce/4,
            hyperpose_branch/4,
            hyperpose_runtime/2,
            metta_condition_holds/2,
            case_runtime/3,
            case_default_runtime/2,
            letstar_runtime/3,
            function_overapplication/3,
            dispatch_mismatch_result/3,
            switch_runtime/3,
            dispatch_no_match_result/3,
            dispatch_policy_execute/5
          ]).

:- use_module(library(assoc)).
:- use_module(library(ansi_term)).

:- consult('translator/analysis.pl').
:- consult('translator/lowering.pl').
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
%54,000 [measured 2026-08-22, PETTA_BENCHMARK_COUNTERS=1, min of three].
%
%An operand headed by an error-REIFYING form is left out: its value is data by
%contract. That test is paid only by an argument that did emit goals, which is
%the minority.
translate_call_args_dl([], Goals, Goals, [], []).
translate_call_args_dl([X|Xs], Goals0, Goals, [V|Vs], Computed) :-
    translate_expr_dl(X, Goals0, AfterExpr, V),
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
%alone reported 1623 findings over PeTTa/examples, 712 of them special forms
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
    translate_expr_to_conj(Expr, Conj, ExprValue),
    (   runnable_collapse_name_state(CollapseState, NameSlot)
    ->  CollapseState = '$petta_name_state'(CollapseNames, PriorNames),
        NameState = '$petta_name_state'(CollapseNames,
                                        [CollapseRuntimeNames|PriorNames]),
        NamedConj = petta_run_named(CollapseNames, Conj,
                                    CollapseRuntimeNames),
        (   ExprValue == 'Empty'
        ->  AfterHead = [(Out = [], NameSlot = [])|Goals]
        ;   nonvar(ExprValue)
        ->  AfterHead = [(findall('$petta_answer'(ExprValue, NameState),
                                  NamedConj, Carried),
                          petta_answer_terms(Carried, Out, NameSlot))|Goals]
        ;   AfterHead = [(findall('$petta_answer'(ExprValue, NameState),
                                  NamedConj, Carried0),
                          petta_prune_empty_answers(Carried0, Carried),
                          petta_answer_terms(Carried, Out, NameSlot))|Goals]
        )
    ;   ExprValue == 'Empty'
    ->  AfterHead = [Out = []|Goals]
    ;   nonvar(ExprValue)
    ->  AfterHead = [findall(ExprValue, Conj, Out)|Goals]
    ;   AfterHead = [(findall(ExprValue, Conj, All),
                      petta_prune_empty(All, Out))|Goals]
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
    AfterHead = [petta_annotation(Out)|Goals].
%(explain Query): the seam's route for Query, answered as atoms rather
%than run. The query arrives UNEVALUATED, like quote's argument, because
%the route is a fact about the expression, not about its answers.
translate_special_dl(explain, [Query], AfterHead, Goals, Out) :-
    AfterHead = [petta_explain(Query, Out)|Goals].
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
    AfterHead = [petta_transaction(Conj)|Goals].

%A SEED IS A SCOPE, not a global setting, so the sequence a program depends on
%is the one written beside it rather than whatever the process did earlier.
%`(with-seed 42 (random-int 1 6))` draws from a generator seeded with 42 and
%restores whatever state was in force when it finishes, so two runs of the same
%scope answer the same thing and nothing outside it is disturbed. That is
%Racket's `parameterize` over `current-pseudo-random-generator` and Common
%Lisp's `with-random-state`, the same shape petta/algebra.py already uses on
%the Python side with random.Random(seed) rather than the module generator
%[source: bindings/python/petta/algebra.py, "Draw a stable cumulative rate
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
    ->  AfterHead = [petta_with_seed(SeedValue, Written, BodyBranch, Out)|Goals]
    ;   AfterHead = [( SeedConj,
                       petta_with_seed(SeedValue, Written, BodyBranch,
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
%measured 2026-08-11]. Every solution of petta_match_atoms/2 is one
%binding set and instantiates its own then-branch answer; the soft cut
%runs the else-branch exactly when no binding set exists. Bindings made
%by the match flow into the branch through the shared variables, which
%is how (unify &kb (friend $who Alice) $who no-friends) answers each
%friend.
translate_special_dl(unify, [A, B, Then, Else], AfterHead, Goals, Out) :-
    translate_expr_to_conj(Then, ThenConj, ThenValue),
    translate_expr_to_conj(Else, ElseConj, ElseValue),
    build_branch(ThenConj, ThenValue, Out, ThenBranch),
    build_branch(ElseConj, ElseValue, Out, ElseBranch),
    AfterHead = [(petta_match_atoms(A, B) *-> ThenBranch ; ElseBranch)|Goals].
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
translate_special_dl(chain, Args, AfterHead, Goals, Out) :-
    translate_let_dl(Args, AfterHead, Goals, Out).
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
translate_special_dl('foldl-atom', [ListExpr, InitialExpr, AccVar, ItemVar,
                                    Body], AfterHead, Goals, Out) :-
    translate_expr_to_conj(ListExpr, ListConj, List),
    translate_expr_to_conj(InitialExpr, InitialConj, Initial),
    collection_closure([ItemVar, AccVar], Body, Closure),
    exclude(==(true), [ListConj, InitialConj], PrefixGoals),
    append(PrefixGoals, [foldl(Closure, List, Initial, Out)|Goals], AfterHead).
translate_special_dl('map-atom', [ListExpr, ItemVar, Body],
                     AfterHead, Goals, Out) :-
    translate_expr_to_conj(ListExpr, ListConj, List),
    collection_closure([ItemVar], Body, Closure),
    exclude(==(true), [ListConj], PrefixGoals),
    append(PrefixGoals, [maplist(Closure, List, Out)|Goals], AfterHead).
translate_special_dl('filter-atom', [ListExpr, ItemVar, Condition],
                     AfterHead, Goals, Out) :-
    translate_expr_to_conj(ListExpr, ListConj, List),
    collection_closure([ItemVar], Condition, Closure),
    exclude(==(true), [ListConj], PrefixGoals),
    append(PrefixGoals,
           [include(metta_condition_holds(Closure), List, Out)|Goals],
           AfterHead).

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
    append(ArgVars, SealedLocals, NotFree),
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
    %function; and since every space PyPeTTa creates is a named one, it was
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
%does: those queries route through petta_merged_match/3, where the
%declared (merge <pattern> <policy>) chooses the strategy. A computed
%space expression keeps the space-after-space path.
translate_special_dl(match, [SpaceExpr, Pattern0, Body], AfterHead, Goals,
                     Out) :-
    SpaceExpr = [superpose, SpaceList],
    is_list(SpaceList), SpaceList = [_, _|_],
    forall(member(Space, SpaceList), petta_space_name(Space)), !,
    lift_pattern_modifiers(Pattern0, Pattern, Guards),
    append([petta_merged_match(SpaceList, Pattern, Out)|Guards],
           AfterMatch, AfterHead),
    translate_expr_dl(Body, AfterMatch, Goals, Out).
translate_special_dl(match, [SpaceExpr, Pattern0, Body], AfterHead, Goals,
                     Out) :-
    translate_space_expr_dl(SpaceExpr, AfterHead, BeforeMatch, Space),
    lift_pattern_modifiers(Pattern0, Pattern, Guards),
    %The template and the result are DISTINCT variables. Fused, the
    %answer-shaped refusal of match/4's last clause could never surface: the
    %body had already bound the one variable, the Error atom failed to unify
    %with it, and the clause died silently, so !(match $u (f 1) matched)
    %answered zero rows while a direct call answered the Error
    %[tested: test_a_surface_match_on_an_unbound_space_answers_the_error].
    %On success match/4 unifies Result with OutPattern, so the compiled
    %goals and their cost are unchanged.
    append([match(Space, Pattern, Template, Out)|Guards], AfterMatch,
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
      -> Out = [],
         AfterHead = Goals
      ; var(Expr)
      -> translate_expr_dl(Expr, AfterHead, BeforeReduce, ExprValue),
         BeforeReduce = [reduce(ExprValue, Out, _)|Goals]
      ; Expr = [Function|Args],
        translate_args_dl(Args, AfterHead, BeforeReduce, ArgValues),
        ExprValue = [Function|ArgValues],
        BeforeReduce = [reduce(ExprValue, Out, _)|Goals] ).
translate_special_dl(eval, [Arg], AfterHead, Goals, Out) :-
    AfterHead = [eval(Arg, Out)|Goals].
%evalc hands its first argument over unevaluated, exactly as eval does, or the
%expression would already have been reduced in the calling space before the
%space argument could select another one. The space itself is evaluated, so a
%function that answers a space name, or (context-space), can name it.
translate_special_dl(evalc, [Arg, Space], AfterHead, Goals, Out) :-
    translate_space_expr_dl(Space, AfterHead, BeforeEval, SpaceValue),
    translate_restricted_guard_dl(
        metta_require_current_capability(evalc, process),
        [evalc(Arg, SpaceValue, Out)|Goals], BeforeEval).
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
prolog:message(petta_head_pattern_note(Fun, Path, Label, type_annotation)) -->
    { head_pattern_position_text(Path, Where) },
    [ 'the head of (= (~w ...) ...) constrains ~w with the in-place \c
       annotation on ~w, so that position compiled to a type premise GOAL \c
       rather than to structure. The equation this function stores no longer \c
       holds its whole head, which is why a dual cannot be built \c
       for it.'-[Fun, Where, Label] ].
prolog:message(petta_head_pattern_note(Fun, Path, Label, defined_label(Route)))
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
    throw(error(petta_uncompilable_seam(Form, Offender),
                context(Form/1, 'a Prolog seam compiles one goal'))).

%The same mistake reaches the translator by a second route that the clauses
%above cannot see. A rule whose expansion is built in Prolog returns the form
%itself. A malformed bare seam can therefore survive translation as data and
%is refused here. A quote around it is a valid inert quote value instead
%[tested translator.plt:quoted_seam_expansion_stays_inert].
refuse_seam_expanded_to_data(Rule, Out) :-
    (   nonvar(Out), Out = [Seam|_],
        ( Seam == translatePredicate ; Seam == call )
    ->  throw(error(petta_seam_expansion_as_data(Rule, Seam),
                    context(Rule, 'a translator rule expanded to data')))
    ;   true ).

prolog:error_message(petta_uncompilable_seam(Form, Offender)) -->
    [ '~w compiles one Prolog goal and needs it written as a list naming the \c
       predicate, as (~w (name $arg ...)), but it was given ~p. A translator \c
       rule that builds this form in Prolog returns it directly; quoting it \c
       there yields a list the translator can only read as data.'-[Form, Form,
                                                                   Offender] ].
prolog:error_message(petta_call_to_own_import(Name)) -->
    [ 'this runnable imports ~w and calls it, and a runnable is compiled \c
       whole before any of it runs, so the call compiles while ~w is still \c
       unregistered and answers the expression instead of the value. Put the \c
       import in its own runnable, before the one that calls it.'-[Name, Name] ].
prolog:error_message(petta_seam_expansion_as_data(Rule, Seam)) -->
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
translate_let_dl([[__petta_typed_binding__, Pattern], Value, In],
                 AfterHead, Goals, Out) :-
    constrain_args(Pattern, ConstrainedPattern, TypeGoals),
    TypeGoals \== [],
    translate_expr_dl(ConstrainedPattern, AfterHead, AfterPattern,
                      PatternValue),
    translate_expr_dl(Value, AfterPattern, AfterValue, ValueResult),
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
translate_let_dl([Pattern, Value, In], AfterHead, Goals, Out) :-
    ( shares_variable(Pattern, Value)
      -> translate_expr_dl(Pattern, AfterHead, AfterPattern, PatternValue),
         translate_expr_dl(Value, AfterPattern, AfterValue, ValueResult),
         AfterValue = [unify_with_occurs_check(PatternValue, ValueResult)|AfterUnify]
       ; ( var(Value)
           -> EarlyUnify = unify_with_occurs_check(PatternValue, ValueResult)
            ; EarlyUnify = (ValueResult = PatternValue) ),
         AfterHead = [EarlyUnify|BeforePattern],
         translate_expr_dl(Pattern, BeforePattern, AfterPattern, PatternValue),
         translate_expr_dl(Value, AfterPattern, AfterUnify, ValueResult) ),
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
    petta_space_operand(SpaceExpr), !,
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
    translate_restricted_guard_dl(
        metta_require_current_capability(Importer, Capability), [Goal|Goals],
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
    length(AVs, N),
    Arity is N + 1,
    ( maybe_specialize_call(Fun, AVs, Out, Goal)
      -> dispatch_call_goal(Fun, AVs, Out, Goal, PolicyGoal),
         append([PolicyGoal|Extra], Goals, Goals0)
    ; arity(Fun, Arity)
      -> resolve_dispatch(Fun, AVs, Out, Goal),
         dispatch_call_goal(Fun, AVs, Out, Goal, PolicyGoal),
         append([PolicyGoal|Extra], Goals, Goals0)
    ; incomplete_application_kind(Fun, Arity, partial)
      -> Out = partial(Fun, AVs),
         Goals0 = Goals
    ; Goals0 = [function_overapplication(Fun, AVs, Out)|Goals] ).

%Type function call generation, returns function call plus typechecks for input and output:
%Translate a call against every type declaration that fits it.
%
%A symbol may carry several declarations at different arities, which is
%ordinary nondeterminism over declarations rather than a conflict, so a
%declaration whose shape does not fit THIS call simply does not contribute a
%branch. Collecting the branches with findall is what makes that true. It was
%a maplist, which meant one inapplicable declaration failed the entire form:
%with both (: g (-> A Atom B)) and (: g (-> A Atom Number B)) declared,
%(g x y 1) did not translate at all, while the same two equations with no
%declarations worked [tested: translator_multi_arity_declarations].
%
%Failing when no branch fits is deliberate: the caller falls back to the
%untyped translation, which is what a call carrying no usable declaration
%should get.
%
%The branches are collected by recursion rather than findall/3, because
%findall COPIES its template and every branch has to keep sharing the caller's
%Out and argument variables. Collecting them with findall compiled cleanly and
%answered an unbound variable for every typed call.
typed_functioncall_dl(Fun, UniqueTypeChains, T, IsPartial, Bound, Out, AfterHead, Goals) :-
    UniqueTypeChains \== [],
    length(T, NewInputArity),
    length(Bound, BoundArity),
    InputArity is BoundArity + NewInputArity,
    Arity is InputArity + 1,
    (   incomplete_application_kind(Fun, Arity, ApplicationKind),
        ApplicationKind == overapplied
    ->  ( IsPartial -> append(Bound, T, Written) ; Written = T ),
        AfterHead = [function_overapplication(Fun, Written, Out)|Goals]
    ;   fitting_type_chains(UniqueTypeChains, InputArity, Selection),
        ( IsPartial -> append(Bound, T, Written) ; Written = T ),
        (   Selection = refused(Rule, Reason)
        ->  Refusal = ['Error', [Fun|Written],
                       ['TypingRuleRefusal', Rule, Reason]],
            AfterHead = [Out = Refusal|Goals]
        ;   applicable_typed_branches(Selection, Fun, T, IsPartial, Bound,
                                      Out, Branches),
            Branches \== [],
            disj_list(Branches, Disj),
            AfterHead = [( Disj
                         *-> true
                         ;   dispatch_mismatch_result(Fun, Written, Out)
                         )|Goals]
        )
    ).

%A declared call that no branch answered says WHY when the declaration is the
%reason: every rejection it makes, `(Error <call> (BadArgType <position>
%<expected> <actual>))`, against the arguments AS WRITTEN, which is the form
%the arbiter names and the one whose types decide
%[source: LeaTTa tests/semantics/types-basic/44-badargtype-per-actual.metta
%through 49-badargtype-widened-actuals.metta].
%
%It answers NOTHING when the declaration makes no rejection, so a call whose
%types check and whose equations do not match keeps this engine's own reading
%rather than gaining the arbiter's NotReducible: `(= (f 1) one)` then `!(f 2)`
%answers `[(f 2)]` there and nothing here, and that divergence is not this
%change's to make [measured 2026-08-19 against the arbiter]. The soft cut is
%what keeps the successful path unchanged: it commits to the branches whenever
%any of them answered.

%When some declaration has exactly this call's arity, only those apply. A
%wider declaration would otherwise also build a branch for a shorter call and
%answer the same thing twice: with (: g (-> A Atom B)) and
%(: g (-> A Atom Number B)) both declared, (g x y) answered (x y) twice.
%
%When NOTHING decides this arity the call is a partial application, and every
%declaration stays a candidate so currying keeps working. A named refusal is
%kept distinct from that absence; otherwise filtering it out would select the
%partial fallback and make an arrow-arity refusal behaviorally inert.
fitting_type_chains(Chains, InputArity, Fitting) :-
    include(type_chain_takes(InputArity), Chains, Exact),
    (   Exact \== []
    ->  Fitting = Exact
    ;   type_chain_refusal(Chains, InputArity, Rule, Reason)
    ->  Fitting = refused(Rule, Reason)
    ;   Fitting = Chains
    ).

type_chain_takes(InputArity, [->|Types]) :-
    length(Types, Count),
    DeclaredInputArity is Count - 1,
    current_metta_module(Module),
    typing_rule_accepts(Module, 'arrow-arity', InputArity,
                        DeclaredInputArity).

type_chain_refusal(Chains, InputArity, Rule, Reason) :-
    member([->|Types], Chains),
    length(Types, Count),
    DeclaredInputArity is Count - 1,
    current_metta_module(Module),
    typing_rule_refusal(Module, 'arrow-arity', InputArity,
                        DeclaredInputArity, Rule, Reason),
    !.

applicable_typed_branches([], _, _, _, _, _, []).
applicable_typed_branches([TypeChain|Rest], Fun, T, IsPartial, Bound, Out,
                          Branches) :-
    (   typed_functioncall_branch(Fun, TypeChain, T, [], IsPartial, Bound, Out,
                                  BranchGoal)
    ->  Branches = [BranchGoal|More]
    ;   Branches = More
    ),
    applicable_typed_branches(Rest, Fun, T, IsPartial, Bound, Out, More).

typed_functioncall_branch(Fun, TypeChain, T, GsH, IsPartial, Bound, Out, BranchGoal) :-
    TypeChain = [->|Xs],
    append(ArgTypes0, [OutType], Xs), !,
    drop_unconstraining_types(TypeChain, ArgTypes0, ArgTypes),
    metta_argument_type_origins(ArgTypes, ArgOrigins),
    argument_applicability_checks(T, ArgTypes, ArgOrigins, ApplicabilityChecks),
    translate_args_by_type(T, ArgTypes, GsT2, AVsTmp0, ArgChecks, Computed0),
    ( IsPartial -> append(Bound, AVsTmp0, AVsTmp) ; AVsTmp = AVsTmp0 ),
    append(GsH, ApplicabilityChecks, BeforeArgs),
    append(BeforeArgs, GsT2, InnerEval),
    %The output check asks whether the result has the declared type, and
    %nothing reads OutType afterwards, so one witness is the whole answer. A
    %soft cut here instead enumerates every derivation and succeeds once per
    %derivation, which repeats the call's answer: with (: (a b) (A B)) declared
    %alongside (: a A) and (: b B), a function returning (a b) answered twice.
    %The argument checks above keep their soft cut, because a shared type
    %variable there does have to backtrack to find a consistent assignment.
    ( (OutType == '%Undefined%' ; OutType == '_' ; OutType == 'Atom')
       -> OutCheck = []
        ; type_check_goal(Out, OutType,
                          ( has_type(Out, OutType) -> true
                          ; 'get-metatype'(Out, OutType) ),
                          OutGoal),
          OutCheck = [OutGoal] ),
    %The checks are placed against an EMPTY prefix so the guard below can sit
    %between the argument evaluations and them. An argument that produced an
    %Error fails its own declared check -- an Error is not a Number -- and a
    %failed check takes the whole branch down, which is how
    %`(needs-number (+ 1 "bad"))` answered nothing where the arbiter answers
    %the inner error atom.
    place_type_checks(ArgTypes, OutType, ArgChecks, OutCheck, [], AfterEval, Extra),
    typed_call_operands(Fun, Computed0, Guarded),
    build_call_or_partial_dl(Fun, AVsTmp, Out, CallGoals, [], Extra),
    append(AfterEval, CallGoals, Checked),
    guard_error_arguments(Guarded, Out, Checked, AfterInnerEval, []),
    append(InnerEval, AfterInnerEval, GoalsList),
    goals_list_to_conj(GoalsList, BranchGoal).

%evaluated_argument_values/3's typed twin. A parameter the evaluation mask
%holds back (Atom, and any user type declared DontEvalType) receives the
%argument AS WRITTEN, so nothing was evaluated at that position and nothing
%there can have produced an Error: `(assertEqual (Error a b) (Error a b))`
%keeps comparing two Error atoms.
%An operation whose contract is to OBSERVE an error receives it as a value, so
%none of its operands is tested and none is recovered.
typed_call_operands(Fun, _, []) :- error_transparent_operation(Fun), !.
typed_call_operands(_, Computed, Computed).

%A shared raw type variable needs the whole written call checked before any
%argument runs. Earlier formals bind it and later formals consume that exact
%binding; ordinary chains retain the existing evaluate-then-check path.
argument_applicability_checks(Args, Types, Origins, Checks) :-
    memberchk(derived_variable, Origins),
    !,
    maplist(argument_applicability_check, Args, Types, Origins, Raw),
    goals_list_to_conj(Raw, Conj),
    Checks = [once(Conj)].
argument_applicability_checks(_, _, _, []).

argument_applicability_check(Argument, Type, Origin,
                             check_argument_type(Argument, Type, Origin)).

%An argument whose declared type is a type variable occurring NOWHERE else in
%the chain constrains nothing, and its check is pure waste. The check is
%(has_type(A,T) *-> true ; get-metatype(A,T)), so with T unbound it enumerates
%the argument's types, binds T to the first, and cannot fail: get-metatype/2
%answers for every term. Nothing then reads T.
%
%(: == (-> $a $b Bool)) is the shape, and it is what the builtin type file
%declares for ==, != and =alpha. Measured 2026-08-15 over 1000 calls of a
%two-argument function: 683 inferences undeclared, 1620 declared with two free
%type variables, 1562 declared with concrete types. The free variables were
%the MOST expensive of the three, for checks that decide nothing.
%
%A variable occurring twice is a real constraint and stays: (-> $a $a Bool)
%requires both arguments to have a consistent type, and (-> $a Bool $a) ties an
%argument to the result. Only a bare singleton variable is dropped, so
%(-> (List $a) Bool) keeps its check on the list.
%A chain with no type variables at all has nothing to drop, and that is most
%of them: every arithmetic, comparison and math declaration in
%lib_builtin_types.metta is concrete. term_variables/2 answers that in one
%call, where the occurrence walk below cost 72 inferences per compiled call
%site [measured 2026-08-15].
drop_unconstraining_types(TypeChain, ArgTypes0, ArgTypes) :-
    term_variables(TypeChain, TypeVariables),
    (   TypeVariables == []
    ->  ArgTypes = ArgTypes0
    ;   type_variable_occurrences(TypeChain, Occurrences),
        maplist(drop_unconstraining_type(Occurrences), ArgTypes0, ArgTypes)
    ).

drop_unconstraining_type(Occurrences, Type, Dropped) :-
    (   var(Type),
        occurrence_count(Occurrences, Type, 1)
    ->  Dropped = '_'
    ;   Dropped = Type
    ).

%Every variable OCCURRENCE, duplicates kept, which is what term_variables/2
%cannot report.
type_variable_occurrences(Term, [Term]) :- var(Term), !.
type_variable_occurrences(Term, Occurrences) :-
    compound(Term),
    !,
    Term =.. [_|Args],
    maplist(type_variable_occurrences, Args, Lists),
    append(Lists, Occurrences).
type_variable_occurrences(_, []).

occurrence_count(Occurrences, Variable, Count) :-
    include(==(Variable), Occurrences, Same),
    length(Same, Count).

%One commit covers every check that constrains the same type variables.
%
%Where the output type shares no variable with the arguments, the argument
%checks commit as a group before the call, so an ill-typed call never runs the
%body, and the output check commits separately after it.
%
%Where the output shares one, as in (-> $a $a), committing before the call
%picks a witness the output cannot satisfy: with (: at A), (: at T), (: t T)
%and (= (testf at) t), the argument check binds $a to A and the answer t, of
%type T, is then rejected. Both halves solve together after the call instead,
%which is the only order in which a shared variable can be assigned
%consistently [tested: examples/types/types.metta,
%a_shared_type_variable_is_assigned_after_the_call].
place_type_checks(ArgTypes, OutType, ArgChecks, OutCheck, InnerEval, Inner, Extra) :-
    term_variables(ArgTypes, ArgVars),
    term_variables(OutType, OutVars),
    ( shares_a_variable(ArgVars, OutVars)
      -> Inner = InnerEval,
         append(ArgChecks, OutCheck, Both),
         commit_checks(Both, Extra)
       ; commit_checks(ArgChecks, Committed),
         append(InnerEval, Committed, Inner),
         Extra = OutCheck ).

commit_checks([], []) :- !.
commit_checks(Checks, [once(Conj)]) :- goals_list_to_conj(Checks, Conj).

shares_a_variable(As, Bs) :- member(A, As), member(B, Bs), A == B, !.

%Selectively apply translate_args for non-Expression args while Expression args stay as data input:
%The argument checks are collected and committed as ONE group, after the
%argument evaluations. Checking each argument under its own commit cannot
%satisfy a type variable the arguments share: the first witness for one
%argument binds it, and nothing backtracks to the assignment the next
%argument needs. Committing per argument loses answers, and not committing
%at all repeats them once per consistent assignment, so the group is the
%unit: find one assignment that satisfies every argument, then stop looking.
%The evaluations stay outside the commit, because a nondeterministic
%argument must keep every answer it produces
%[tested: a_parametric_expected_type_enumerates_its_witnesses,
%translator_typed_checks].
%Computed rides this walk for the same reason it rides
%translate_call_args_dl/5: asking a second time costs, and the answer is free
%here. It names the operand values this branch EVALUATED, which are the ones
%that can hold an error atom the call must hand on rather than consume.
translate_args_by_type([], _, [], [], [], []) :- !.
translate_args_by_type(Args, Types, GsOut, AVs, Checks, Computed) :-
    metta_argument_type_origins(Types, Origins),
    translate_args_by_type_dl(Args, Types, Origins,
                              GsOut, [], AVs, Checks, [], Computed).

translate_args_by_type_dl(Args, Types, Goals0, Goals, AVs) :-
    metta_argument_type_origins(Types, Origins),
    translate_args_by_type_dl(Args, Types, Origins,
                              Goals0, Tail, AVs, Checks, [], _),
    ( Checks == []
      -> Tail = Goals
       ; goals_list_to_conj(Checks, CheckConj),
         Tail = [once(CheckConj)|Goals] ).

translate_args_by_type_dl([], _, _, Goals, Goals, [], Checks, Checks, []) :- !.
translate_args_by_type_dl([A|As], [T|Ts], [Origin|Origins],
                          Goals0, Goals, [AV|AVs], Checks0, Checks, Computed) :-
    ( non_evaluated_parameter_type(T)
      -> AV = A,
         AfterArg = Goals0,
         AfterCheck = Checks0,
         Computed = More
    ; ( T == 'SpaceType'
        -> translate_space_expr_dl(A, Goals0, AfterArg, AV)
        ;  translate_expr_dl(A, Goals0, AfterArg, AV) ),
      (   Goals0 == AfterArg
      ->  Computed = More
      ;   nonvar(AV)
      ->  Computed = More
      ;   error_reifying_argument(A)
      ->  Computed = More
      ;   Computed = [AV|More]
      ),
      ( (T == '%Undefined%' ; T == '_' ; statically_typed_literal(AV, T))
        -> AfterCheck = Checks0
      ; type_check_goal(AV, T,
                        check_argument_type(AV, T, Origin),
                        ArgGoal),
        Checks0 = [ArgGoal|AfterCheck] ) ),
    translate_args_by_type_dl(As, Ts, Origins, AfterArg, Goals, AVs,
                              AfterCheck, Checks, More).

%Atom is the shipped evaluation mask. DontEvalType makes that same compiler
%decision declarative for user types; it deliberately skips the ordinary
%argument check because the written expression has not yet produced a value
%whose runtime type could satisfy the declared marker.
non_evaluated_parameter_type(Type) :- Type == 'Atom', !.
non_evaluated_parameter_type(Type) :-
    nonvar(Type),
    catch_recover(type_declaration(Type, 'DontEvalType'), fail).

%A check that cannot be DROPPED can still be SPECIALISED. Three types are
%decided by a single Prolog builtin, and when the declared type is one of them
%the compiler knows so, because the type is a compile-time constant. Putting
%that test in front turns the common case from a walk through
%current_metta_module/1, has_type_in/3, once/1 and type_candidate_in/3 into one
%builtin call [measured 2026-08-17: an output check of type Number, 8.00
%inferences per call to 1.00].
%
%The fallback is untouched and reached whenever the fast test fails, so this
%decides nothing the general check would decide differently. It only answers
%the common case sooner. That matters because the fast test is INCOMPLETE on
%purpose: `(: mysym Number)` makes has_type(mysym, 'Number') true while
%number(mysym) is false, and the second disjunct is what still says so.
%
%Soundness in the other direction is what makes the shortcut legal at all.
%Both get_type_candidate/2 and get_type_candidate_in/3 open with a CUTTING
%numeric clause. Signed-i64 integers and floats answer Number directly. Wider
%integers answer BigInt, which metta_types_match/2 admits when Number is the
%expected type. Thus number(V) implies has_type(V, 'Number') in every module,
%whatever a get-type extension adds later [source: engine/metta.pl,
%metta_numeric_type/2 and metta_types_match/2].
%
%This is the other half of what statically_typed_literal/2 below does, from the
%same compile-time fact. A compiler holding type information "remov[es] type
%and mode checks and ... call[s] specialized versions of some builtins"
%[source: Morales, Carro and Hermenegildo, Improved Compilation of Prolog to C
%Using Moded Types]; the removal is the literal case and this is the
%specialisation case.
%
%nonvar/1 first, and it is not defensive: a parametric declaration leaves the
%type a VARIABLE here, and intrinsic_type_test/3's head would bind it to
%'Number' and emit a number/1 test for a type nobody wrote. That is the same
%trap intrinsic_literal_type/2 below carries a note about, from the same shape.
%[tested: translator_literal_type_checks:an_intrinsic_type_check_is_specialised].
type_check_goal(Value, Type, General, Goal) :-
    (   nonvar(Type),
        intrinsic_type_test(Type, Value, Fast)
    ->  Goal = ( Fast -> true ; General )
    ;   Goal = General
    ).

intrinsic_type_test('Number', V, number(V)).
intrinsic_type_test('String', V, string(V)).
intrinsic_type_test('Bool',   V, (V == true ; V == false)).

%A literal argument's type is settled while the call site is being COMPILED,
%so the check emitted for it can only ever succeed and every inference it
%spends is spent on a foregone conclusion. `(: f (-> Number Number Number))`
%called as `(f 1 2)` compiled two has_type/2 goals over the constants 1 and 2,
%and they cost as much as the same call on two unknown variables: 31
%inferences per call against 6 for the same function undeclared, the whole 25
%being the checks [measured 2026-08-16, 20,000 calls of a site compiled once].
%Dropping every check leaves no once/1 wrapper either, so the fully literal
%call compiles to exactly what the untyped one does.
%
%Only four literal shapes qualify. A number is accepted by Number, including
%a BigInt integer through the directed compatibility rule. A string is String,
%and true and false are Bool, whatever a user's get-type extension adds later.
%
%This only ever DROPS a check that must pass; it never rejects. `(f "s")`
%against a Number parameter still compiles its check and still refuses at run
%time, because a get-type extension may legitimately give a literal a second
%type and deciding THAT statically would be unsound
%[tested: translator_literal_type_checks].
statically_typed_literal(Value, Type) :-
    nonvar(Type),
    nonvar(Value),
    intrinsic_literal_type(Value, Type).

%nonvar/1 above and ==/2 rather than head unification below, because BOTH are
%needed and the second is what a reader would skip. Written as
%`intrinsic_literal_type(true, 'Bool')`, a call with an unbound Value and
%Type = 'Bool' UNIFIES the head and binds Value to true. The argument being
%bound there is the call site's compile-time variable, so
%`(= (f $a $b) (g $a $b))` against `(: g (-> Bool Atom Bool))` compiled its
%head as `f(true, A, B)` and `(f False ...)` then matched no clause and
%answered nothing at all [reproduced 2026-08-16].
%
%Caught by a hand probe rather than by the gate, because the shape needs a
%Bool, Number or String parameter reached from ANOTHER function's body with a
%variable, and no example in the corpus had one
%[tested: translator_literal_type_checks:a_typed_parameter_is_not_frozen_at_compile_time].
intrinsic_literal_type(Value, 'Number') :- number(Value), !.
intrinsic_literal_type(Value, 'String') :- string(Value), !.
intrinsic_literal_type(Value, 'Bool') :- ( Value == true ; Value == false ).

%Handle data list:
eval_data_term_dl(X, Goals, Goals, X) :- (var(X); atomic(X)), !.
eval_data_term_dl([F|As], Goals0, Goals, Val) :-
    ( atom(F), fun_here(F) -> translate_expr_dl([F|As], Goals0, Goals, Val)
                           ; eval_data_list_dl([F|As], Goals0, Goals, Val) ).

%Handle data list entry:
eval_data_list_dl([], Goals, Goals, []).
eval_data_list_dl([E|Es], Goals0, Goals, [V|Vs]) :-
    ( is_list(E) -> eval_data_term_dl(E, Goals0, AfterEntry, V)
                 ; V = E, AfterEntry = Goals0 ),
    eval_data_list_dl(Es, AfterEntry, Goals, Vs).

%Convert let* to recursive let. The singleton case is the recursive one over
%an empty rest, and writing it out as a third clause made the predicate
%answer the SAME expansion twice: harmless where the compiler took the first
%solution, and two identical answers a call once letstar_runtime/3 below
%started backtracking into it.
letstar_to_rec_let([], Body, Body) :- !.
letstar_to_rec_let([[Pat,Val]|Rest],Body,[let,Pat,Val,Out]) :- letstar_to_rec_let(Rest,Body,Out).

%Pairs a form reads as syntax have ARRIVED when the list is proper and every
%element of it is a term rather than a variable. That is the shape a rewrite
%may read: below it there is a variable standing where the spine or a pair
%should be, and reading it would unify the rewrite's own pattern INTO the
%source instead of reading what is there.
arrived_pairs(Pairs) :- is_list(Pairs), maplist(nonvar, Pairs).

%The pairs have NOT arrived when such a variable is there, which is different
%from a term that is no list at all: the first can still arrive as a value,
%the second keeps falling through as it always has. is_list/1 alone cannot
%tell those two apart, and '$skip_list'/3 can, walking the spine once and
%reporting the tail without instantiating it, the way library(error) tells a
%partial list from a bad one [source 2026-08-19: SWI-Prolog 10.1.13
%/usr/lib/swi-prolog/library/error.pl:311-315, not_a_list/2, and :428-430,
%is_list_or_partial_list/1].
%'$skip_list'/3 has already settled the spine by the time the elements are
%looked at, so this walks it once more rather than through arrived_pairs/1,
%whose is_list/1 would walk it a third time to learn what Tail == [] just
%said.
unarrived_pairs(Pairs) :-
    '$skip_list'(_, Pairs, Tail),
    ( var(Tail) -> true
                 ; Tail == [], \+ maplist(nonvar, Pairs) ).

%The bindings when they were not syntax. `(= (mylet $bs $b) (let* $bs $b))`
%reaches translation with no bindings to rewrite and receives them as a VALUE
%instead, so they are rewritten when that value arrives, through the same
%letstar_to_rec_let/3 the written-out form uses. One definition therefore
%decides what let* means either way. The shape is case_runtime/3's, and so
%are the costs: one translation per call, growing with the bindings, against
%a flat cost for the same bindings written out
%[measured 2026-08-19: 3 inferences a call at both 2 and 16 written-out
%bindings; 62 and 370 for the same bindings handed over, min of 3 over a
%1,000-call slope; tested translator_letstar_computed_bindings].
%
%This reaches compiled bodies, so it is named in seam:engine_emitted/1
%above: without that, `(= (letstar_runtime $bs $b) ...)` would take the goal
%over inside its own space, silently and with a wrong answer rather than an
%error, because a space resolves a body's goals in its own module first
%[source: tests/prolog/static_checks.pl, the scan that reads the goals out of
%every equation the corpus compiles and fails on a capturable one that is not
%named].
letstar_runtime(Bindings, Body, Out) :-
    checked_pair_list('let*', 'a list of (pattern value) bindings', Bindings),
    letstar_to_rec_let(Bindings, Body, RecursiveLet),
    translate_expr_to_conj(RecursiveLet, Conj, Value),
    build_branch(Conj, Value, Out, Branch),
    current_metta_module(Module),
    call_goals_in_(Module, [Branch]).

% Constructs the goal for a single branch of an if-then-else/case.
build_branch(true, Val, Out, (Out = Val)) :- !.
%A variable-valued branch unifies with the output at RUNTIME, inside the
%branch. Unifying at translate time (Val = Out) is only sound when Val is
%private to the branch, and it is not when the branch's value is a clause
%parameter (an if arm of (let* (($c $a)) $a) collapses to the parameter $a):
%aliasing the head's output with the parameter makes the other arm's
%unification corrupt it, so the clause fails wherever that arm runs.
%merge_branch_returns/3 restores the translate-time binding afterwards,
%exactly where the whole clause proves it private.
build_branch(Con, Val, Out, (Con, Out = Val)) :- var(Val), !.
build_branch(Con, Val, Out, (Val = Out, Con)).

%Restore last-call optimization where it is safe: a branch ending with the
%runtime unification (Out = V) keeps a tail-recursive loop from running in
%constant stack, since the recursive call is no longer last. The first pass
%records each variable's total occurrences and first/last traversal positions.
%The second pass knows each branch's position interval, so two AVL lookups prove
%that V is absent from the head, confined to this branch, and produced before
%the final unification. No branch re-scans the whole clause.
%
%Unbound variables are valid assoc keys while their standard-order relation is
%unchanged. All return bindings are therefore delayed until every lookup has
%finished: https://www.swi-prolog.org/pldoc/doc/_SWI_/library/assoc.pl
merge_branch_returns(Head, Body0, Body) :-
    empty_assoc(Empty),
    mbr_collect_stats(Head, 0, _HeadEnd, Empty, HeadStats),
    mbr_collect_stats(Body0, 0, End, Empty, Stats),
    mbr_goal(Body0, HeadStats, Stats, 0, WalkEnd, Body, Bindings, []),
    WalkEnd =:= End,
    mbr_bind_returns(Bindings).

%A variable goal is opaque and can only be walked as a term, which is what the
%catch-all clause at the bottom does. It needs saying here because a variable
%unifies with every control structure below: the conjunction clause bound it to
%a fresh (A , B) whose own left branch was again a variable, the cut committed,
%and the walk recursed on manufactured conjunctions forever. Reproduced
%2026-08-15: an unbound goal exceeded a depth limit of 3000 where `true`
%finishes at depth 2, and importing a library whose body held one exhausted the
%7.5Gb stack at 24,403,140 frames.
mbr_goal(Goal, _, _, P0, P, Goal, Bs, Bs) :- var(Goal), !,
    mbr_advance_term(Goal, P0, P).
mbr_goal((A , B), H, Stats, P0, P, (A1 , B1), Bs0, Bs) :- !,
    mbr_goal(A, H, Stats, P0, P1, A1, Bs0, Bs1),
    mbr_goal(B, H, Stats, P1, P, B1, Bs1, Bs).
mbr_goal((C -> T ; E), H, Stats, P0, P, (C -> T1 ; E1), Bs0, Bs) :- !,
    mbr_advance_term(C, P0, P1),
    mbr_branch(T, H, Stats, P1, P2, T1, Bs0, Bs1),
    mbr_branch(E, H, Stats, P2, P, E1, Bs1, Bs).
mbr_goal((A ; B), H, Stats, P0, P, (A1 ; B1), Bs0, Bs) :- !,
    mbr_branch(A, H, Stats, P0, P1, A1, Bs0, Bs1),
    mbr_branch(B, H, Stats, P1, P, B1, Bs1, Bs).
mbr_goal((C -> T), H, Stats, P0, P, (C -> T1), Bs0, Bs) :- !,
    mbr_advance_term(C, P0, P1),
    mbr_branch(T, H, Stats, P1, P, T1, Bs0, Bs).
mbr_goal(G, _, _, P0, P, G, Bs, Bs) :-
    mbr_advance_term(G, P0, P).

mbr_branch(B0, H, Stats, P0, P, B, Bs0, Bs) :-
    mbr_goal(B0, H, Stats, P0, P, B1, Bs0, Bs1),
    ( mbr_merge_candidate(B0, H, Stats, P0, P, V, Out)
      -> mbr_split(B1, B, _),
         Bs1 = [V-Out|Bs]
    ; B = B1,
      Bs1 = Bs ).

mbr_merge_candidate(B0, HeadStats, Stats, P0, P, V, Out) :-
    mbr_split(B0, _Prefix, (Out = V)),
    var(V),
    var(Out),
    V \== Out,
    \+ get_assoc(V, HeadStats, _),
    get_assoc(V, Stats, var_stat(Count, First, Last)),
    Count > 1,
    First >= P0,
    Last < P.

mbr_bind_returns([]).
mbr_bind_returns([V-Out|Bindings]) :-
    V = Out,
    mbr_bind_returns(Bindings).

%Split a conjunction into everything-but-last and its last conjunct:
mbr_split((A , B), Prefix, Last) :- !,
    ( mbr_split(B, P1, Last), ( P1 == true -> Prefix = A ; Prefix = (A , P1) ) ).
mbr_split(G, true, G).

%Collect every variable's occurrence count and traversal interval in one pass.
mbr_collect_stats(T, P0, P, Stats0, Stats) :-
    ( var(T)
      -> ( get_assoc(T, Stats0, var_stat(Count0, First, _))
           -> Count is Count0 + 1,
              put_assoc(T, Stats0, var_stat(Count, First, P0), Stats)
         ; put_assoc(T, Stats0, var_stat(1, P0, P0), Stats) ),
         P is P0 + 1
    ; compound(T)
      -> functor(T, _, N),
         mbr_collect_stats_args(1, N, T, P0, P, Stats0, Stats)
    ; P = P0,
      Stats = Stats0 ).

mbr_collect_stats_args(I, N, _, P, P, Stats, Stats) :- I > N, !.
mbr_collect_stats_args(I, N, T, P0, P, Stats0, Stats) :-
    arg(I, T, Arg),
    mbr_collect_stats(Arg, P0, P1, Stats0, Stats1),
    I1 is I + 1,
    mbr_collect_stats_args(I1, N, T, P1, P, Stats1, Stats).

%Advance over the same depth-first variable positions without rebuilding the
%association. This pass also reconstructs only the control nodes it changes.
mbr_advance_term(T, P0, P) :-
    ( var(T) -> P is P0 + 1
    ; compound(T) -> functor(T, _, N), mbr_advance_args(1, N, T, P0, P)
    ; P = P0 ).

mbr_advance_args(I, N, _, P, P) :- I > N, !.
mbr_advance_args(I, N, T, P0, P) :-
    arg(I, T, Arg),
    mbr_advance_term(Arg, P0, P1),
    I1 is I + 1,
    mbr_advance_args(I1, N, T, P1, P).

%The Empty pair is the default branch, taken when the key answered nothing,
%so it is removed from the branches the key is matched against. Found stays
%unbound through the select: unifying ['Empty', _] in during the search would
%let an ordinary case pair of two variables be picked as the default.
case_default_pair(Cases, DefaultExpr, Rest) :-
    select(Found, Cases, Rest),
    subsumes_term(['Empty', _], Found),
    !,
    Found = ['Empty', DefaultExpr].

%Translate case expression recursively into nested if:
translate_case([], _, _, fail, []) :- !.
translate_case([[K,VExpr]|Rs], Kv, Out, Goal, KGo) :- translate_expr_to_conj(VExpr, ConV, VOut),
                                                      constrain_args(K, Kc, Gc),
                                                      build_branch(ConV, VOut, Out, Then),
                                                      ( Rs == [] -> Goal = ((Kv = Kc) -> Then), KGi=[]
                                                                  ; translate_case(Rs, Kv, Out, Next, KGi),
                                                                    Goal = ((Kv = Kc) -> Then ; Next) ),
                                                      append([Gc,KGi], KGo).

%The cases when they were not syntax. A case written inside a definition of
%its own, `(= (switch $v $cs) (case $v $cs))`, reaches translation with no
%branches to compile and receives them as a VALUE instead, so they compile
%when that value arrives, through the same translate_case/5 the written-out
%form uses. One definition therefore decides what a case means either way: a
%second interpreter for the same form would be a second set of answers to
%keep in step [tested: translator_case_computed_cases]. The shape is
%hyperpose_runtime/2's, and the costs are eval/2's: one translation per call,
%growing with the cases at 78, 258 and 498 inferences a call for 3, 12 and 24
%of them against a flat 3 for the same cases written out [measured
%2026-08-19, min of 3, per-call slope over 100 and 1,100 calls], plus the
%generated-lambda growth the header's Fails when records. A compiled-goal
%cache would answer both and is deliberately not here: it would need
%invalidation kept in step with the specializer's and lib_memo's, which is a
%larger problem than the one this path exists to solve, and writing the cases
%out already pays neither cost.
%
%Writing them out is otherwise untouched: byte-identical compiled output over
%twelve case shapes, with the classification paid once at COMPILE time
%[measured 2026-08-19: 71 to 78 inferences translating a three-case form,
%min of 5].
%
%This and case_default_runtime/2 reach compiled bodies, so both are named in
%seam:engine_emitted/1 above. Without that, `(= (case_runtime $k $cs) ...)`
%would take the goal over inside its own space, silently and with a wrong
%answer rather than an error, because a space resolves a body's goals in its
%own module first [source 2026-08-19: tests/prolog/static_checks.pl:685-692,
%the scan that reads the goals out of every equation the corpus compiles and
%fails on a capturable one that is not named].
case_runtime(KeyValue, Cases, Out) :-
    checked_pair_list(case, 'a list of (pattern value) cases', Cases),
    ( case_default_pair(Cases, _, NormalCases) -> true ; NormalCases = Cases ),
    translate_case(NormalCases, KeyValue, Out, CaseGoal, KeyGoals),
    append(KeyGoals, [CaseGoal], Runtime),
    current_metta_module(Module),
    call_goals_in_(Module, Runtime).

%switch's rows when they were not syntax, case_runtime/3's twin. It keeps the
%Empty pair in the list rather than lifting it out, which is the one difference
%between the two forms.
switch_runtime(KeyValue, Cases, Out) :-
    checked_pair_list(switch, 'a list of (pattern value) cases', Cases),
    translate_case(Cases, KeyValue, Out, CaseGoal, KeyGoals),
    append(KeyGoals, [CaseGoal], Runtime),
    current_metta_module(Module),
    call_goals_in_(Module, Runtime).

%The key answered nothing, so the Empty pair is the answer. Cases carrying no
%Empty answer nothing at all, which is what the compiled form says by having
%no else branch to build in that case.
case_default_runtime(Cases, Out) :-
    checked_pair_list(case, 'a list of (pattern value) cases', Cases),
    case_default_pair(Cases, DefaultExpr, _),
    translate_expr_to_conj(DefaultExpr, DefaultConj, DefaultValue),
    build_branch(DefaultConj, DefaultValue, Out, DefaultBranch),
    current_metta_module(Module),
    call_goals_in_(Module, [DefaultBranch]).

%Pairs arriving as a value are checked before they are compiled, because
%nothing downstream can. An unbound cases list is what `case` used to
%allocate 7.5 Gb on, and a pair that is not (pattern value) would unify with
%translate_case/5's or letstar_to_rec_let/3's own head and compile a branch
%or a binding the program never wrote. Said in MeTTa's vocabulary through
%throw_metta_type_error/3, so the message names the FORM and prints the value
%the way the program would have written it instead of naming a predicate of
%the engine's [tested: translator_case_open_cases,
%translator_letstar_unarrived_bindings].
%
%A type error rather than the instantiation error ISO asks for when the
%culprit is unbound [source 2026-08-19: SWI-Prolog 10.1 manual A.16,
%instantiation_error/1, "an argument is under-instantiated"]. What arrives
%here is a MeTTa VALUE, not a Prolog input argument, and MeTTa gives an
%unbound one the metatype Variable where a cases list is an Expression
%[measured 2026-08-19: !(get-metatype $x) answers Variable and
%!(get-metatype (1 one)) answers Expression], so the wrong metatype is
%exactly what happened and the message can say which. The bare ISO error
%says only that something somewhere was not instantiated, which is the
%complaint against the engine's other unbound-argument raises.
checked_pair_list(Form, Expected, Pairs) :-
    (   is_list(Pairs),
        forall(member(Pair, Pairs), subsumes_term([_, _], Pair))
    ->  true
    ;   throw_metta_type_error(Form, Expected, Pairs)
    ).

%Translate arguments recursively:
translate_args([], [], []).
translate_args([X|Xs], Goals, [V|Vs]) :-
    translate_args_dl([X|Xs], Goals, [], [V|Vs]).

translate_args_dl([], Goals, Goals, []).
translate_args_dl([X|Xs], Goals0, Goals, [V|Vs]) :-
    translate_expr_dl(X, Goals0, AfterExpr, V),
    translate_args_dl(Xs, AfterExpr, Goals, Vs).

%Build A ; B ; C ... from a list:
disj_list([], fail) :- !.
disj_list([G], G) :- !.
disj_list([G|Gs], (G ; R)) :- disj_list(Gs, R).

%Build one disjunct per branch: (Conj, Out = Val). A literal Empty member
%is the branch remover and contributes no branch at all, minimal MeTTa's
%"is not returned among other results" applied where it is free; a
%COMPUTED Empty is pruned at the collapse aggregation instead.
build_superpose_branches([], _, []).
build_superpose_branches([E|Es], Out, Bs) :- E == 'Empty', !,
                                             build_superpose_branches(Es, Out, Bs).
build_superpose_branches([E|Es], Out, [B|Bs]) :- translate_expr_to_conj(E, Conj, Val),
                                                 build_branch(Conj, Val, Out, B),
                                                 build_superpose_branches(Es, Out, Bs).

%Build hyperpose branch as a goal list for concurrent_and/3 to consume:
build_hyperpose_branches([], []).
build_hyperpose_branches([E|Es], [(Goal, Res)|Bs]) :- translate_expr_to_conj(E, Goal, Res),
                                                      build_hyperpose_branches(Es, Bs).

%Never ask for more workers than there are branches. library(thread)'s jobs/2
%defaults the pool to the cpu_count flag and concurrent_and/3 creates that many
%workers plus a generator on EVERY call, so a three-branch hyperpose was
%creating 33 OS threads on this 32-core box regardless of its width
%[measured 2026-08-15: 30 three-branch calls created 990 threads; sizing to the
%branch count made it 120 and 11.6x faster on the same answers].
hyperpose_pool_size(BranchCount, Jobs) :-
    ( current_prolog_flag(cpu_count, Cores), integer(Cores), Cores > 0
      -> Jobs is max(1, min(BranchCount, Cores))
    ; Jobs is max(1, BranchCount) ).

%Run each branch under the module the TRANSLATOR wrote into this goal. Module
%is a compile-time literal here, so the worker's space context comes from the
%BRANCH and not from the thread that spawned it: SWI's globals are per-thread,
%a worker starts with this one unset, and inheriting the caller's thread state
%is exactly what a fork cannot do. Binding it from the goal's own argument is
%the same shape Java's ScopedValue gives a StructuredTaskScope fork and Go's
%context.Context gives a goroutine, both of which exist because thread-local
%state is not inherited [source: JEP 506; golang/go#21355, which rejected
%goroutine-local storage for this reason].
%
%The binding is the whole of it: no save, because a worker's context starts
%unset and the thread ends with the branch; and no validation, because the
%module came from the compiler rather than from a caller. b_setval/2 unwinds on
%backtracking, so a worker handed a second branch from another space binds its
%own. with_metta_module/2 did all three and cost 8 inferences in every worker.
%
%FAILS WHEN called anywhere but a concurrent_and/3 worker. Without the restore
%a deterministic success leaves the calling thread's context pointing at
%Module, which is free in a worker that is about to end and wrong in a thread
%that goes on to do something else. The one caller is the goal
%translate_special_dl/5 emits above, and every shipped hyperpose shape was
%measured for the leak and has none, because concurrent_and/3 runs the goal in
%a worker even at threads(1); calling this predicate directly does leak
%[measured 2026-08-21, all four shapes and the direct call].
%
%[measured 2026-08-21, min-of-3 on the engine's own counters, and the saving is
%per branch rather than per call, so it grows with the width the construct
%exists for: 1108 -> 1097, 1570 -> 1548, 2498 -> 2457, 4380 -> 4296 and
%8240 -> 8072 inferences at 1, 2, 4, 8 and 16 branches, a flat -10.5 each; the
%same collapse over superpose is unchanged at 1471]
%[tested: translator_hyperpose:test_a_hyperpose_worker_inherits_its_space_context_structurally].
%
%WHY THE CONTEXT IS NOT DERIVED FROM THE CALL SITE, which is what the survey
%expected and what was built and measured first. SWI hands a module_transparent
%predicate the module of the CLAUSE that called it, which is Logtalk's `This`;
%what a space context means is Logtalk's `Self`, the space the program is
%running in. They differ under inheritance, and this engine inherits: the
%prelude's `(= (atomically $expr) (transaction (eval $expr)))` is compiled into
%&self's module and shared by every space, so with eval/2 reading its call site
%`!(collapse (atomically (petta-three)))` in a named space answered
%((petta-three)) instead of ((1 2 3)) [measured 2026-08-21]. Logtalk threads
%both fields through every compiled clause for this exact reason
%(core.pl:25188); SWI's module system carries only the first, so Self stays in
%the global until a compiled clause carries it, which is P11.7's argument to
%add, not this row's.
hyperpose_branch(Module, Goal, Res, Out) :-
    b_setval('$petta_module', Module),
    call(Module:Goal), Out = Res.

%Runtime hyperpose path for variable/computed list arguments.
hyperpose_runtime(Exprs, Out) :-
    is_list(Exprs),
    current_metta_module(Module),
    length(Exprs, BranchCount),
    hyperpose_pool_size(BranchCount, Jobs),
    concurrent_and(member(Expr, Exprs),
                   eval_metta_in_module(Module, Expr, Out),
                   [threads(Jobs)]).

eval_metta_in_module(Module, Expr, Out) :-
    with_metta_module(Module,
                      ( translate_expr(Expr, Goals, Out),
                        call_goals_in_(Module, Goals) )).

%Compile Params and Body into a closure predicate and give back a Prolog
%callable that takes the body's own arguments after the captured ones. This is
%'|->' itself, which already names the predicate, captures the free variables
%and registers the arity; the difference-list arguments are the same variable
%because a lambda contributes no runtime goals of its own.
collection_closure(Params, Body, Closure) :-
    translate_special_dl('|->', [Params, Body], Tail, Tail, Lambda),
    (   Lambda = partial(Function, Captured)
    ->  Closure =.. [Function|Captured]
    ;   Closure = Lambda
    ).

%include/3's test for filter-atom. The condition's VALUE decides, so unify it
%with true rather than calling it. Calling it is what the yall version did, and
%(filter-atom (1 2 3) $x 42) then died with "callable expected, found (, true
%42)" where the same filter written (filter-atom (1 2 3) notbool) answered ().
%Unifying is also what the builtin 'filter-atom'/3 in metta.pl has always done.
metta_condition_holds(Closure, Item) :- call(Closure, Item, true).
%Declared meta so the lambda survives the hop through here. include/3 qualifies
%its own closure argument, which reaches this predicate's clause in the calling
%module, but Closure inside the clause is then a bare atom and call/3 resolves
%it in `user`. maplist/3 and foldl/4 never showed this because library(apply)
%declares them meta and this predicate is the only hand-written link in the
%chain: with the lambda in the space's module, filter-atom raised
%`metta_condition_holds/2: Unknown procedure: lambda_3/2` where map-atom and
%foldl-atom over the same lambda answered
%[tested: translator_lambda_space_scope]. Free: 10,013 inferences either way
%for a compiled filter-atom over 2,000 elements [measured 2026-08-16].
:- meta_predicate metta_condition_holds(2, ?).
%(:= X) inside a match pattern is the match-by-EQUALITY modifier: the atom
%matches only where it is already identical to X, so a free variable does not
%match it. lib/minimal_metta_lib.pl has implemented it for unify-mod all along
%and the engine's own match/4 did not know it, so the same modifier meant two
%different things depending on which matcher read it.
%
%Lifted at COMPILE time rather than taught to match/4, and that is the whole
%design. The modifier position is replaced by a fresh variable, so the space
%read keeps its ordinary shape and its clause indexing, and the equality is
%emitted as a ==/2 goal after the match. A pattern with no modifier in it
%produces no guards and an unchanged pattern. Only expression lists can denote
%a modifier; trying the ownership seam on leaf atoms added a fixed preparation
%tax without making a meaningful modifier possible [measured: query-2k-rows
%minimum 561467 versus 601709 on 2026-08-21 before leaf calls and per-row
%empty modifier
%calls were removed; command=python bench.py query-2k-rows --counter-only;
%fixture=20 queries over 2000 rows;
%commit=b54ecaaa1224eabb90f808275003cd9abeef8065]. Engine-compiled match/4
%pays nothing per row because this walk happens once while its call site compiles.
%
%That also matches what the modifier means. The reference states that the
%guard "does not receive the match state, so bindings accumulated earlier in
%the same match cannot affect it", which is exactly a ==/2 over the operand as
%written [source: LeaTTa/MettaHyperonFull/Proofs/Modifiers.lean, the checked
%matcher's modifier law].
%
%THE ARITY GATE IS COPIED, NOT INVENTED. The reference recognises a modifier
%only at `Atom.expr [Atom.sym s, x]`, exactly two elements
%[source: LeaTTa/MettaHyperonFull/Core/Modifiers.lean, registeredMod?], and
%the reason is in this repository too: examples/libraries/minimal_metta.metta
%asserts that the THREE-element (:= a b) is ordinary data and matches the
%pattern (:= $x $y) structurally. Recognising := by name alone would
%reinterpret it [tested: translator_match_modifiers].
%GATE ONE: a pattern that IS a colon expression is a query for stored type
%declarations, not an annotation. `(match &self (: $x Human) $x)` retrieves the
%atoms somebody wrote, which is the reading a knowledge base needs and the one
%issue #177 names as the collision to avoid. An annotation is therefore always
%NESTED: `(match &self (knows (: $x Human) (: $y Human)) ($x $y))`
%[source: LeaTTa/ai-report-inplace-annotations.md, Design, gate 1].
lift_pattern_modifiers(Pattern, Lifted, Guards) :-
    (   colon_expression(Pattern)
    ->  Lifted = Pattern, Guards = []
    ;   lift_pattern_modifiers_(Pattern, Lifted, Guards, [])
    ).

lift_pattern_modifiers_(Pattern, Lifted, Guards0, Guards) :-
    (   nonvar(Pattern), Pattern = [_|_]
    ->  (   seam:pattern_modifier(Pattern, Lifted, Guard)
        ->  Guards0 = [Guard|Guards]
    %GATE TWO: a colon whose VALUE slot is not a variable is data, and the walk
    %does not look inside it. Without the second half a constructor that nests
    %colons inside a value, as LeaTTa's single_sided.metta does with
    %`(: (Sym (: (Sym (: $x $a)) $b)) $c)`, would have its inner colons
    %reinterpreted [source: LeaTTa/ai-report-inplace-annotations.md, Design].
        ;   colon_expression(Pattern)
        ->  Lifted = Pattern,
            Guards0 = Guards
        ;   lift_pattern_modifiers_list(Pattern, Lifted, Guards0, Guards)
        )
    ;   Lifted = Pattern,
        Guards0 = Guards
    ).

colon_expression(Pattern) :- nonvar(Pattern),
                             Pattern = [Colon, _, _],
                             nonvar(Colon),
                             Colon == ':'.

lift_pattern_modifiers_list([], [], Guards, Guards).
lift_pattern_modifiers_list([Item|Rest], [Lifted|LiftedRest], Guards0, Guards) :-
    lift_pattern_modifiers_(Item, Lifted, Guards0, Guards1),
    lift_pattern_modifiers_list(Rest, LiftedRest, Guards1, Guards).

%The two modifiers a pattern position can carry, each replaced by a fresh
%variable and a guard over it. `(:= X)` matches by EQUALITY, so a free
%variable does not match it; `(: $x T)` matches anything of type T and is the
%same acceptance a declared parameter of type T compiles, so a match query can
%restrict by type where only a top-level declaration could before.
%Every clause of this open ownership seam, the two below and a provider's own,
%takes a LIST, so SWI's first-argument index already separates it from nothing
%and the marker is what discriminates. The marker is therefore COMPARED rather
%than unified, which costs one nonvar and one == per clause tried, at
%compile time and never per match.
seam:pattern_modifier([Assign, Wanted], Fresh, Fresh == Wanted) :-
    %The marker is read the way colon_expression/1 reads its own, nonvar then
    %==, because a LITERAL in the head unifies with an unbound head instead of
    %rejecting it: a two-element pattern whose head is a variable, (match &s
    %($A $B) ...), unified $A with ':=' and compiled as the equality modifier,
    %so the query answered nothing and $A silently became ':=' in the template
    %[measured 2026-08-21: hypothesis's SpaceStateMachine drew (() ()) against
    %($A ()); every arity but two matches, and match/4 itself answers].
    nonvar(Assign), Assign == ':=',
    !.
seam:pattern_modifier([Colon, Fresh, Type], Fresh,
                 (has_type(Fresh, Type) *-> true ; 'get-metatype'(Fresh, Type))) :-
    %The same nonvar-then-== reading as the clause above and as
    %colon_expression/1: ($A $B 0) against a stored () was compiled as "of
    %type 0" because the literal ':' unified with the pattern's own head
    %variable [measured 2026-08-21, hypothesis SpaceStateMachine].
    nonvar(Colon), Colon == ':',
    %An annotation annotates a VARIABLE, so anything else in that position
    %stays structural. Not a nicety: tests/prolog/duals.plt writes
    %`(= (pat-starts-a (: a $rest)) True)` as an ordinary cons-shaped pattern,
    %and without this gate it would be read as "the atom a has type $rest".
    var(Fresh).

%Like membercheck but with direct equality rather than unification
memberchk_eq(V, [H|T]) :- ( V == H -> true ; memberchk_eq(V, T) ).

%Generate a readable lambda name. The counter has to be process-wide: SWI
%global variables are thread-local, so a counter kept in one gave every
%hyperpose worker its own sequence starting at 1, and two threads compiling a
%lambda both produced lambda_1. assertz then added the second body to the first
%lambda's predicate rather than defining a new one, and one lambda answered
%with every colliding branch's result. gensym/2 counts in a process-wide flag
%and is the same generator filereader.pl already uses for load ids.
next_lambda_name(Name) :- gensym(lambda_, Name).

declared_output_type(F, OutType) :- atom(F),
									nonvar(OutType),
									catch_recover(type_declaration(F, TypeChain), fail),
									TypeChain = [->|Types],
									append(_, [DeclaredOutType], Types),
									DeclaredOutType == OutType.
