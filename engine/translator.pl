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
:- consult('translator/special_forms.pl').
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
