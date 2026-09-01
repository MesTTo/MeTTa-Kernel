% Purpose: compile MeTTa expressions and equations into executable Prolog,
%   including dynamic dispatch, control forms, higher-order calls, and
%   branch-return optimization.
% Assumes:
%   - merge_branch_returns/3 keeps its occurrence stats as `translator`
%     attributes on the clause's own variables, strips them before its return
%     bindings run, and relies on assertz/1 dropping attributes while
%     copy_term/2 carries them [measured 2026-08-30: a clause asserted with an
%     attributed variable reads back bare, and copy_term/2 of the same term
%     copies the attribute; both probed directly].
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
%     [tested: tests/prolog/suites/translator/translator.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d].
%   - Runnable translations are cached as fresh templates by execution module
%     and a copy_term/2 plus numbervars/4 variant key; changing or removing a
%     mentioned function evicts every dependent template
%     [tested: translation_cache; commit=d90a3c9620e56e42d3a2f5982b4353da8423e873].
%   - translate_tracked_clause/[2,3] enables contract shortcuts only for a
%     clause recorded in the support graph; translate_clause/[2,3] keeps every
%     dynamic check for untracked prelude and lambda clauses
%     [tested:
%     translator_literal_type_checks:an_untracked_clause_retains_static_and_intrinsic_contracts;
%     commit=WORKTREE].
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
%     examples/ch07-control-flow/07-03-let-and-sequencing/04-letstarcomputed.metta]. Writing them out is
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
%     [tested: examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/06-functionhead.metta,
%     examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/07-functionhead2.metta,
%     examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/08-functionhead3.metta,
%     examples/ch08-data/08-01-atoms-lists-and-folds/11-patrick.metta,
%     examples/ch22-a-reasoner-you-can-serve/22-03-search/02-tilepuzzle.metta].
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
%   - '$metta_translation_cache' serializes first publication and dependency
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
            translate_tracked_clause/2,
            translate_tracked_clause/3,
            without_runnable_name_context/1,
            translate_expr/3,
            translate_cached_expr/3,
            translate_runnable_expr/3,
            translate_runnable_expr/4,
            with_runnable_variable_epochs/1,
            clear_translation_cache/0,
            clear_module_translation_state/1,
            queue_deferred_equation_types/2,
            materialize_with_queued_types/3,
            metta_function_translated/2,
            head_pattern_notes_for/2,
            invalidate_translated_forms/1,
            index_builtin_masks/0,
            maybe_print_compiled_clause/3,

            compiled_function_name/2,
            metta_special_form/1,
            metta_special_form_head/1,
            metta_translated_head/1,
            metta_reducible_head/2,
            %The one question the SPACES ask of a name's declarations while a
            %program is being built: whether some declared arrow answers the
            %metatype `Atom`, which is what stops an answer re-entering
            %evaluation and the only part of a declaration that reaches the
            %declared function's own compiled clause. A declaration write
            %compares it either side of the store to decide whether that
            %clause needs rebuilding (result_finality/2, engine/spaces.pl).
            declared_output_type/2,
            uses_super/2,
            fun_meta_clauses/3,
            fun_meta_module/3,
            clear_fun_meta/2,
            drop_fun_meta/4,
            arrived_pairs/1,
            call_site_type_chains/2,
            fitting_type_chains/3,
            %The reified-world and saga planner in engine/metta/effects.pl
            %asks the same questions translation asks itself: which written
            %positions a declaration evaluates, which type views end an
            %evaluation rather than re-entering it, and which heads the
            %interpreter embeds. Reading the translator's own answers is what
            %keeps admission and translation from drifting apart; a planner
            %that recomputed them would BE the drift [tested:
            %engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
            builtin_argument_mask/4,
            non_evaluated_parameter_type/1,
            present_type_chain/3,
            declared_type_for_evaluation/2,
            intrinsically_final_builtin_result/1,
            embedded_operation/1,
            metta_runtime_argument_mask/3,
            metta_runtime_returns_atom/1,
            constrain_args/3,
            drop_unconstraining_types/3,
            letstar_to_rec_let/3,
            memberchk_eq/2,
            reduce/2,
            reduce/3,
            %The compiled-lambda table. engine/metta/control.pl's collection
            %forms compile a written operator through it, so one `(|-> ...)`
            %handed over by a masked parameter compiles once for every map,
            %filter and fold that applies it.
            written_lambda_closure/2,
            eval_metta_in_module/3,
            metta_application_result/3,
            metta_application_result/4,
            metta_boundary_result/3,
            metta_reduce_result/5,
            metta_eval_step_orients/2,
            metta_rule_gates_refresh/0,
            self_tier_note/2,
            self_tier_forget/1,
            metta_rule_gates_ensure/1,
            with_not_reducible_root/2,
            metta_symbol_step/2,
            metta_eval_root_result/4,
            metta_evaluate_symbol/2,
            metta_evaluate_argument/2,
            metta_dynamic_call/3,
            metta_dynamic_head_masks/1,
            metta_dynamic_value_call/4,
            metta_chain_step/2,
            metta_minimal_equation_step/3,
            collapse_runtime/2,
            metta_function_eval/2,
            metta_function_eval/3,
            metta_segment_dispatch/4,
            metta_segment_rule_result/6,
            %The result half of the evaluation mask lands in a compiled clause
            %body, so a space's execution module imports it from here exactly
            %as it imports reduce/3 and the two dispatch results.
            metta_masked_result/2,
            %atom-subst is one written-variable substitution and chain's
            %unstepped operand is another, so the walk is defined once here
            %and the operator in engine/metta/operators.pl imports it.
            substitute_written_variable/4,
            lift_pattern_modifiers/4,
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
            declared_arity_refusal/3,
            dispatch_mismatch_result/3,
            switch_runtime/3,
            dispatch_no_match_result/3,
            dispatch_policy_execute/5
          ]).

:- use_module(library(assoc)).
:- use_module(library(ansi_term)).

:- consult('translator/analysis.pl').
:- consult('translator/lowering.pl').
:- consult('translator/special_forms.pl').
:- consult('translator/typing.pl').
:- consult('translator/runtime.pl').
