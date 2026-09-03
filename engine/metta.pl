% Purpose: provide MeTTa's Prolog runtime, builtins, type system, evaluator,
%   imports, function registration, and named-space execution context.
% Guarantees:
%   - Files below engine/metta/ are plain source units consulted into this
%     implementation module in their original order; builtin, runtime, and
%     registration predicates retain their existing ownership and clause order
%     [tested: tests/prolog/suites/evaluation/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d].
%   - A built-in call covered by the effects cluster whose declared operand
%     types already conflict is refused before operand evaluation; shallow
%     compile-time checks inspect literals and declared return types without
%     binding source variables
%     [tested: operation_answers, test_a_repeated_eval_does_not_recompile_and_the_effects_cluster_conforms; commit=8d0027a3942000c799daccb45bf0abe1b46b10aa].
%   - repr/2, println!/2, format-args, test/3 and assert/2 presentation retain
%     host display text through sdisplay/2 without weakening swrite/2's
%     reader-inverse contract [tested: parser_display,
%     a_value_prints_according_to_its_default_reading,
%     a_partial_application_remains_visible_in_test_output; commit=0c1bd4c2faadc1c4fc97cc9d2caa084907d20072].
%   - import! loads a MeTTa source that is new or that has been edited, and
%     skips one that is neither, which is SWI's if(changed); a Python source
%     keeps if(not_loaded) [tested 2026-08-19:
%     test_an_unchanged_repeat_import_does_not_run_the_source_again,
%     test_an_edited_import_is_not_skipped,
%     filereader_source_reload:an_unchanged_file_is_not_loaded_again].
%   - the builtin type surface and engine prelude are decoded as UTF-8 rather
%     than through the process locale [tested:
%     filereader_source_reload:a_source_is_utf8_independent_of_the_locale;
%     commit=18b1135167d60396c41e63e42ded2f66d0eb1900].
%   - metta_handles_route/5 routes a query by the most specific matching
%     (handles ...) entry in &metta, where specificity is pattern
%     subsumption first and adornment-set inclusion between renaming-equal
%     patterns, disagreeing maximal ties throw metta_contract_conflict/4
%     naming both entries and the query, and a context with no entries
%     fails in one indexed probe [tested 2026-08-17: metta_handles_route]
%     [measured 2026-08-17: 15 inferences per undeclared-context miss].
%   - get-type/2 returns each derived type once, while has_type/2 uses one
%     witness for a fixed expected type [tested 2026-08-15:
%     metta_type_answers, translator_typed_checks].
%   - a child execution module resolves parent equations before the shared
%     &self and builtin tiers [tested:
%     test_a_child_space_reads_through_its_parent_and_writes_locally;
%     commit=755330de329ece49eddcfb7d6db3061c3350a0ca].
%   - restricted modules resolve only their local equations and curated
%     builtin surface [tested: spaces_restricted_modules;
%     commit=6a08901f4125c2536f5b4032daac9937f793870f].
%   - expression-named spaces are SpaceType values, select their own execution
%     modules, and report their exact ground identifier through context-space
%     [tested: test_two_instances_of_a_parametric_space_answer_independently;
%     commit=3c7bcde6a0670ec5c563584b26977b41cc727580].
%   - reporting observers type the empty expression as unit `(->)` while
%     internal classifier paths retain their gradual empty-expression result
%     [tested: test_the_empty_expressions_type_follows_the_arbiters_ruling; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - the include refusal's self/top pair records the arbiter-owned module
%     bases explicitly, so the inventory's exemption remains checkable
%     [tested: test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
%     commit=42b5d28232e75c32b20a1d5bf1f740fec134938d].
%   - a hook handler whose call remains unreduced has not supplied a verdict;
%     the hook door reports its existing stuck state instead of treating the
%     residual call as a malformed verdict [tested:
%     hooks:an_unclaimed_request_is_a_stuck_state_that_says_so,
%     hooks:a_post_stuck_state_undoes_the_write; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - support_graph.pl loads before the specializer and file reader that publish
%     derived artifact edges [tested:
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - lib_memo.pl is resident before user source compiles, explain reports its
%     automatic decision, and the effect walk follows its transparent cache
%     dispatcher to the underlying source function [tested:
%     test_a_doubly_branching_recursion_is_tabled_automatically_and_a_tail_recursion_is_not,
%     test_an_impure_function_is_never_cached_automatically; commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
%   - Integers inside signed i64 report Number and integers outside it report
%     BigInt; a Number parameter admits either while a BigInt parameter admits
%     only BigInt, and arithmetic may cross the boundary in either direction
%     without changing its exact SWI value [tested 2026-08-20:
%     bigint_number, test_bigint_and_number_type_the_numeric_tower,
%     test_integer_type_follows_the_signed_i64_boundary,
%     test_number_parameters_accept_bigint_without_retyping_number].
%   - A successful named-space import commits one receipt tying the source
%     path and digest to its exact load and stored-output references. Reuse
%     requires that receipt to remain current, so any public removal rebuilds
%     the missing source contribution without duplicating survivors
%     [tested: filereader_import_lifecycle,
%     test_public_import_rebuilds_when_a_receipt_dependency_disappears,
%     test_repeat_import_reuses_one_current_receipt_without_duplication;
%     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
%   - Host failures from builtins retain their ISO error class and name the
%     written MeTTa operation [tested 2026-08-15:
%     metta_operation_errors, translator_evaluation_errors]. Integer
%     arithmetic pays nothing for this and float arithmetic pays one
%     inference per call, because only the integer pair takes the guarded
%     fast path [measured 2026-08-15: 300,000 and 400,000 inferences per
%     100,000 calls, against 300,000 unguarded]; division's integer pair
%     pays the catch too, because a non-divisible pair converts its result
%     to float and can overflow doing it. Whole-corpus cost is
%     +2.1% instructions on examples/ch18-performance/18-01-larger-workloads/01-scale.metta
%     [measured 2026-08-15].
%   - Python operation registration reaches the canonical `(effect Name Class)`
%     atom consumed by operation reflection; exactly pureStructural projects
%     to seam:pure_operation/1 [tested:
%     test_structural_registration_reflects_an_effect_atom,
%     effects_lattice:only_pure_structural_projects_to_the_cache_purity_seam;
%     commit=3cfbe0d7417b1c453c2dc12d47e2e47e7de461f7].
%   - the final boot pass materializes one catalog visibility row for every
%     callable after the prelude has registered its equations [tested:
%     catalog_self_description:every_shipped_callable_has_one_visibility;
%     commit=8779452fed89853c3f77c3469f7a6ec7b12e9efa].
%   - StateMonad cells use one process-shared non-backtrackable store, so main
%     evaluation and held answer engines observe the same writes without
%     losing their parameterized held-value type [tested:
%     test_state_cells_are_shared_across_answer_engines,
%     test_state_retires_three_state_function_strings; commit=18b1135167d60396c41e63e42ded2f66d0eb1900].
%   - A result past binary64 saturates to the IEEE value on the engine's
%     operations, agreeing with the reader's saturating literals, and an
%     infinity a literal produced carries through further arithmetic; the
%     same recovery answers the whole IEEE family when a float operand is
%     present, a float zero divides to the signed infinity and the NaN
%     class answers NaN, while integer division and remainder by zero answer
%     a contained DivisionByZero Error atom; raw
%     is/2 keeps every flag's error mode [tested 2026-08-20:
%     engine_operations_saturate_where_raw_is_still_raises,
%     a_read_infinity_survives_further_arithmetic,
%     a_twice_faulting_compound_saturates_all_the_way,
%     test_integer_division_by_zero_answers_what_d1_decides,
%     test_arithmetic_overflow_agrees_with_the_literal_side,
%     test_float_zero_division_and_nan_agree_with_the_arbiter;
%     commit=ecd792eacbfe1810645434ce406f79be3a9e03d1].
%   - is-alpha-member/3 tests unifiability without retaining bindings in its
%     arguments [tested 2026-08-15: metta_alpha_membership].
%   - alpha-unique-atom/2 confirms identity inside each term-hash bucket, so a
%     hash collision cannot remove an inequivalent term [tested 2026-08-15:
%     metta_alpha_unique].
%   - get-metatype/2 classifies every Prolog term used as a MeTTa value, and
%     classifies a NAME by the arbiter's grounded-token table gated on this
%     engine holding the operation, so a token nothing here answers to reports
%     Symbol as an unknown name does [tested 2026-08-20: metta_metatypes].
%   - metta_transaction/1 answers everything its body answers, and every
%     answer's writes commit or roll back together [tested 2026-08-19:
%     extensions/python/tests/ch15_writing_transactions_and_worlds/test_atomic_forms.py::test_a_transaction_preserves_every_answer_of_its_body].
%   - Every guarded_input_position/3 refuses an unbound argument and names the
%     MeTTa operation, so no builtin binds the caller's variable, invents an
%     answer, runs away or reports a host predicate [tested 2026-08-19:
%     builtin_input_guards:every_builtin_refuses_an_unbound_input_by_name,
%     extensions/python/tests/ch10_errors_and_refusals/test_builtin_inputs.py::test_a_raising_builtin_names_the_metta_operation_not_the_host_predicate].
%   - ==/3 and !=/3 refuse two operands of known and different types and
%     answer for every other pair, at no cost on two numbers [tested
%     2026-08-19:
%     extensions/python/tests/ch03_atoms_and_expressions/test_equality.py::test_cross_kind_equality_answers_false]
%     [measured 2026-08-19: 4487.45 inferences per thousand-iteration loop,
%     unchanged].
%   - %Undefined% is consistent with every type in both directions, so a call
%     site refuses only a PROVEN conflict, while has_declared_type/2 demands a
%     witness for a contract [tested 2026-08-19:
%     extensions/python/tests/ch09_types/test_gradual_typing.py::test_an_unknown_type_is_consistent_with_every_declared_type,
%     extensions/python/tests/ch04_spaces_and_matching/test_answer_protocol.py::test_admission_types_the_pool].
%   - An expression no arrow types reads element-wise, and the tuple it reads
%     is %Undefined% as soon as one member's type is [tested 2026-08-19:
%     metta_type_answers:a_tuple_with_an_untyped_member_is_undefined].
%   - get-type/2 and get-type-space/3 answer from declarations without running
%     the inspected expression, so inspection has no effects of its own
%     [tested 2026-08-19:
%     extensions/python/tests/ch09_types/test_type_inspection.py::test_get_type_does_not_run_its_arguments_effects].
%   - get-type-space/3 reads only the selected space, and the upstream doc
%     family builds @doc-formal answers from that scoped type and prose
%     [tested 2026-08-20:
%     extensions/python/tests/repository/test_doc_family.py::test_the_doc_family_answers_what_upstream_answers].
%   - seam:builtin_type_declaration/2 rows are the union of lib_builtin_types.metta
%     and the prelude's, with each row written once and evicted only by the
%     register that wrote it [tested 2026-08-19:
%     metta_builtin_type_surface:a_shared_declaration_is_evicted_only_from_the_register_that_wrote_it].
%   - External Prolog libraries extend seam:builtin_type_declaration/2 without
%     replacing the engine's rows, and unloading retires only their own clauses
%     [tested: test_a_library_types_its_own_blob_without_destroying_the_table;
%     commit=6f06e918c8f3382e8e1c8ccd8d120c6d809999a5].
%   - The prelude loads exactly three form shapes: a declaration, an equation,
%     and `!(add-translator-rule! NAME)` for a name it defines itself, which
%     is how a DERIVED form ships. A program that defines such a name in any
%     execution module takes the whole form over, so the global registration
%     is withdrawn with the clauses
%     [tested: prelude_derived_forms; commit=d1318d20b5d89d33079c49d0e94aa29e12685664].
%   - add-translator-rule! REFUSES a protected_core_head/1 name and puts that
%     name in the error term, and records what an accepted registration took
%     over from in translator_rule_override/2, so a rule going ahead of a
%     special form or a builtin is stated rather than silent
%     [tested: test_overriding_a_protected_name_is_refused_with_the_name;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - Test assertions distinguish no answer from one empty-expression answer
%     [tested 2026-08-14: translator_test_answers].
%   - pragma! validates keys against the closed registry and values before
%     they can replace a working setting: an unknown key is refused, max-time
%     requires a positive number, max-inferences requires a positive integer,
%     none explicitly disables either bound, max-stack-depth answers the
%     arbiter's error atom for a non-count, and the HE spellings type-check
%     and interpreter stay accepted, NOT enforced
%     [tested: test_pragma_validates_values_and_refuses_only_unknown_keys,
%     interpreter_pragmas; commit=e8270f8551083f236ce5134ca299adf5347d6898].
%   - stack-limit scopes SWI's per-thread byte ceiling and restores the exact
%     previous value after success, failure, exception, and nested scopes;
%     max-stack-depth remains branch-local reduction fuel [tested:
%     scoped_stack_limit,
%     test_janus_stack_scope_restores_on_all_exits; commit=81c50d3ae4c03ddfd70ed3f1ff70e085cfee3978].
%   - metta_assertion_failure/4 classifies the three assertion formals, so a
%     harness tells a false claim from a broken engine by TYPE rather than by
%     reading the message [tested 2026-08-19:
%     extensions/python/tests/ch12_testing/test_assertion_failures.py::test_a_failing_assertion_is_a_different_exception_from_an_engine_fault].
%   - Runtime builtins reject prebound outputs that they would not produce
%     [tested 2026-08-14: metta_builtin_outputs].
%   - Function registration performed by a source load participates in that
%     load's rollback [tested 2026-08-14: filereader_source_rollback].
%   - metta_host_function_generation/1 exposes fun/1's process-global SWI
%     database generation, which advances on committed catalogue changes and
%     on no ordinary evaluation or data write
%     [tested: function_catalogue_generation; commit=4c9a794750103e0a3a2e9d883adde337ffb501f0].
%   - Prolog registration refuses every head the translator compiles before
%     function dispatch, including heads added through translator_rule/1
%     [tested: test_registering_any_translator_compiled_head_is_refused_by_name].
%   - Python source imports restore sibling modules and sys.path after setup
%     or execution errors [tested 2026-08-14:
%     metta_python_import_cleanup].
%   - Every seam:grounded_extra_type/2 clause is consulted whether or not a host
%     bridge answers seam:grounded_type_names/2, so a (py-atom f Type)
%     declaration survives the Python library being loaded [tested 2026-08-18:
%     extensions/python/tests/ch11_python_as_a_notation/test_ops.py::test_a_declared_type_survives_the_library_being_loaded]
%     [measured 2026-08-18: +2 inferences per get-type on a Python object and
%     0 on every other value].
%   - register-token! and unregister-token! are ordinary registered builtins,
%     so source programs and host APIs reach the same reader-token mapping
%     [tested: test_a_registered_token_class_parses_like_a_shipped_one;
%     commit=2c741dda928a30d0ce1c7e1fcf0b263b4d1bb97b].
%   - The engine loads and runs the full examples/ corpus with
%     set_prolog_flag(autoload, false) already in effect: the
%     directory_file_path/3 directive below needs library(filesex) before
%     the rest of this section's use_module block would otherwise supply
%     it, and next_lambda_name/1 (translator.pl) needs library(gensym) for
%     every foldl-atom/map-atom/filter-atom/'|->' compile, both silently
%     supplied by autoload before now [measured 2026-08-18: NO_AUTOLOAD=1
%     sh test.sh, 200/200 examples; run.sh's own header has the mechanism].
%     Cost: +1.50% instructions:u on a bare boot (swipl -s engine/metta.pl,
%     no seats), +0.54% with the seats loaded too, +0.14% over a full
%     example run that also exercises the opt-in libraries' own fixes
%     (lib/lib_constraints/lib_constraints.pl, lib/lib_memo/lib_memo.pl) [measured 2026-08-18:
%     interleaved min-of-3, perf stat -e instructions:u, spread under
%     0.003% within each side].
%   - library(thread), library(time), library(process), library(crypto) and
%     library(redis) are optional: a build without one records the capability
%     absent through metta_platform/4 and loads without an error. A dependent
%     operation refuses by name, except the five SHA hashes that library(sha)
%     still supplies without crypto [tested: platform_capabilities,
%     platform_capabilities_reduced;
%     commit=59792b524568755a2fbfe1c5f7cdb571bd78a3bf]. The original three-row
%     census cost between +0.25% and +0.44% instructions:u on a boot, the range
%     being the
%     measurement's own layout sensitivity, which an inert padding block that
%     neither side executes moves by about the same amount [measured
%     2026-08-27: 1,062,764,116 -> 1,067,395,694 unpadded, 1,064,396,538 ->
%     1,067,019,910 with five inert rules, 1,063,925,775 -> 1,067,710,574 with
%     ten; interleaved min-of-5, perf stat -e instructions:u, swipl -q -g halt
%     -t halt -s engine/main.pl on twelve-character paths; boot inferences
%     688,190 -> 690,780 and examples/ch07-control-flow/07-01-if-and-booleans/09-xor.metta identical at 9,289;
%     commit=87d998c24278fc7f020ccb0e408ebcd9332b63eb].
% Open Obligations:
%   To Do: check.sh does not yet gate autoload=false; the exact line is
%     `run GATE   no-autoload  sh -c "cd '$HERE' && NO_AUTOLOAD=1 sh
%     test.sh"`, reusing test.sh's own parallel runner and skip list
%     unchanged (check.sh is single-owner, so this is not wired in here).
%   Hacks: None
%   Future Enhancements: None

%%%%%%%%%% Dependencies %%%%%%%%%%
%directory_file_path/3 is library(filesex)'s, not a built-in, and the
%directive a few lines down calls it immediately at load time to compute
%standard_library_path/1, before the rest of this section's use_module
%block would otherwise supply it. Autoload papers over the ordering when
%it is on; with autoload=false the directive fails on an unknown
%procedure and standard_library_path/1 is never asserted, which then
%aborts the boot at load_builtin_type_surface's first (library ...) call.
%So this one import has to come first, ahead of even the section header's
%own first clause.
:- encoding(utf8).
:- use_module(library(filesex)).
%A shipped library lives in its own DIRECTORY under lib/, named for the
%library: lib/lib_memo/lib_memo.metta beside lib/lib_memo/lib_memo.pl and
%lib/lib_memo/lib_memo_doc.md. A library is a MeTTa surface, the Prolog it
%rides on and the prose that explains it, and a flat lib/ scattered those
%three across an alphabetical listing of nearly sixty files.
%
%So a spec with no directory component gets one: `lib_memo` resolves to
%lib/lib_memo/lib_memo and `lib_builtin_types.metta` to
%lib/lib_builtin_types/lib_builtin_types.metta. A spec that already names a
%directory is taken as written, which is what keeps builtin_mods/skel.metta,
%the engine's own shipped-module spelling, resolving unchanged.
library(X, Path) :- standard_library_path(Base),
                    library_within(X, Relative),
                    directory_file_path(Base, Relative, Path).

%A string reaches here from MeTTa source, `(library "builtin_mods/skel.pl")`,
%and an atom from Prolog, so both spellings are normalised before the test.
%file_name_extension/3 answers Stem=Name and Ext='' for a name with no
%extension, which is why the extension-bearing and bare cases are one clause.
library_within(Spec, Relative) :-
    ( atom(Spec) -> Name = Spec ; atom_string(Name, Spec) ),
    (   sub_atom(Name, _, _, _, '/')
    ->  Relative = Name
    ;   file_name_extension(Stem, _, Name),
        directory_file_path(Stem, Name, Relative)
    ).
%A named library directory, git-fetched or registered. A library that
%pip-installs is under neither: standard_library_path/1 is one directory,
%<src>/../lib, so (library fast.pl) cannot reach a package's own files and a
%downstream library has to pass absolute paths, which is what
%lib/minimal_metta_lib/minimal_metta_lib.py does with os.path.dirname(os.path.abspath(__file__)).
%
%SWI already owns the answer. file_search_path/2 is a "dynamic multifile hook
%predicate used to specify path aliases ... called by absolute_file_name/3 to
%search files specified as Alias(Name)" [source: SWI-Prolog 10.1 Reference
%Manual, section 4.36], it composes (the second argument may be another
%alias), and every SWI tool that understands an alias understands one
%registered here. So a package registers its directory once and
%(library pettorch fast.pl) resolves
%[tested: a_registered_library_path_resolves].
library(X, Y, Path) :- git_library_path(X, Base), !,
                       directory_file_path(Base, Y, Path).
library(X, Y, Path) :- Spec =.. [X, Y],
                       (   absolute_file_name(Spec, Resolved,
                                              [access(read), file_errors(fail)])
                       ->  Path = Resolved
                       ;   refuse_unresolved_library(X, Y)
                       ).

%An alias that resolves to nothing RAISES rather than failing, and the
%distinction is CPython's: returning None from find_spec means "not mine, keep
%looking" and raising means "definitively absent", because "the latter
%indicates that the meta path search should continue, while raising an
%exception terminates it immediately" [source: CPython, the import system,
%finders and loaders].
%
%Failing was the keep-looking signal with nothing left to look with, so
%(import! &self (library imp3 plain)) with the extension forgotten answered
%the empty set, imported nothing, and left every name from that file
%undefined. That surfaces much later as an expression evaluating to itself,
%which is the hardest failure in this language to trace back to its cause. A
%plain path that is absent already raised and named itself; this is the same
%rule reaching the alias form
%[tested: an_unresolvable_library_alias_raises].
refuse_unresolved_library(Alias, File) :-
    findall(Directory, file_search_path(Alias, Directory), Directories),
    throw(error(metta_unresolved_library(Alias, File, Directories),
                context(library/3, 'no readable file of that name'))).

prolog:error_message(metta_unresolved_library(Alias, File, [])) -->
    [ '(library ~w ~w) does not resolve: nothing is registered under the \c
       alias ~w. Register the directory with register_metta_library_path, or \c
       import the file by path.'-[Alias, File, Alias] ].
prolog:error_message(metta_unresolved_library(Alias, File, Directories)) -->
    [ '(library ~w ~w) does not resolve: no readable ~w under ~w. Check the \c
       spelling, and that the file carries its extension.'
      -[Alias, File, File, Directories] ].

%Register a directory under a name, so a Python package can point MeTTa at
%the Prolog and MeTTa files it ships beside itself. Idempotent, and a
%directory that is not there is refused where the caller can still act on it
%rather than at the first import that needs it.
register_metta_library_path(Alias, Directory0, true) :-
    must_be(atom, Alias),
    ( atom(Directory0) -> Directory = Directory0 ; atom_string(Directory, Directory0) ),
    (   exists_directory(Directory)
    ->  true
    ;   throw(error(existence_error(directory, Directory),
                    context(register_metta_library_path/3,
                            'a library path must be a directory that exists')))
    ),
    (   user:file_search_path(Alias, Directory)
    ->  true
    ;   assertz(user:file_search_path(Alias, Directory))
    ).
:- prolog_load_context(directory, Source),
   directory_file_path(Source, '..', Parent),
   directory_file_path(Parent, 'lib', LibPath),
   asserta(standard_library_path(LibPath)).
:- autoload(library(uuid)).
:- use_module(library(random)).
:- use_module(library(error)).
:- use_module(library(listing)).
%That import is why the guards below exist. library(listing) loads
%library(settings) (listing.pl:46, its five layout settings), which loads
%library(arithmetic) (settings.pl:54-56, env/1 and env/2), which installs an
%UNGUARDED process-global hook, `system:goal_expansion(Math, MathGoal) :-
%math_goal_expansion(Math, MathGoal)` (arithmetic.pl:319-320). system: is
%consulted while compiling EVERY module, and the expander's one raise site is
%a COMPILE-time type_error(evaluable, F) (do_expand_function/3's final clause,
%arithmetic.pl:233-234) for an expression SWI itself compiles and raises on at
%RUN time. A raising expansion does not just misreport: SWI drops the whole
%term expansion in flight, so a host clause holding
%`catch(_ is foo + 1, E, true)` vanished silently, and for a plunit test the
%dropped expansion is BOTH the registration and the body --
%tests/prolog/suites/evaluation/metta.plt:402 registered 233 tests instead of 234 in every
%configuration [measured 2026-08-26]. The repair keeps the hook and removes
%only that compile-time judgment: an unknown evaluable defers to run time,
%where SWI's own error and message answer (metta.plt's metta_operation_errors
%unit pins them). What the hook is FOR survives, arithmetic_function/1
%functions still expand and evaluate, and nothing new is folded:
%do_expand_function/3 maps function symbols and never evaluates, and an
%identity expansion is discarded by boot/expand.pl's no-change rule
%[measured 2026-08-26: with the guard, V is twice(21) answers 42 and
%expand_goal leaves `_ is foo + 1` unchanged]. The guard runs twice over:
%once now, for the chain the import above just loaded, and from a
%prolog_listen/2 watcher for every later install -- a reload under make/0, or
%a host that loaded library(arithmetic) before the engine and reloads it
%after. system:goal_expansion/2 is dynamic, the watcher fires inside the
%installing assert, and erasing the event's own clause there works
%[measured 2026-08-26 on SWI 10: repaired-in-event, one guarded clause
%standing, and the hazardous bare clause compiles]. The watcher must never
%throw: an exception from a listener blocks the assert it observes, which
%would silently strip the hook from a library legitimately installing it
%[measured 2026-08-26: an arity-mismatched listener left
%system:goal_expansion/2 with 0 clauses after loading library(arithmetic)].
%tests/prolog/static_checks.pl holds the class canary, expanding
%`_ is foo + 1` neither throws nor rewrites, proved against a planted
%throwing expander, and check.sh's plunit lane fails any suite that prints
%ERROR while loading, so a NEW compile-time refuser from any library fails
%the gate even though this watcher knows only arithmetic's clause. A host
%that wants upstream's compile-time diagnostic back can re-assert the
%original clause after boot; the engine's contract is that an expression's
%meaning is decided when it runs.
guard_arithmetic_goal_expansion :-
    forall(( clause(system:goal_expansion(A, B), Body, Ref),
             unguarded_math_expansion_body(Body, A, B) ),
           guard_arithmetic_goal_expansion_clause(Ref)).

guard_arithmetic_goal_expansion(Action, Ref) :-
    % policy-inventory-exempt: mechanism-internal; reason=the two clause-adding actions prolog_listen/2 reports are SWI's own event vocabulary rather than a knob an operator chooses between, and every other action it delivers is a retract or an erase, which cannot install the hook this watcher repairs; evidence=engine/metta.pl:guard_arithmetic_goal_expansion/2
    catch(( (   memberchk(Action, [assertz, asserta]),
                clause(system:goal_expansion(A, B), Body, Ref),
                unguarded_math_expansion_body(Body, A, B)
            ->  guard_arithmetic_goal_expansion_clause(Ref)
            ;   true
            ) ),
          _,
          true).

%The asserting context wraps a cross-module clause body, so the hook's body
%arrives as arithmetic:math_goal_expansion/2 when arithmetic.pl loads it and
%as user:arithmetic:math_goal_expansion/2 when a host's assertz re-installs
%it [measured 2026-08-26: portrayed both from one process]. The guarded
%replacement below arrives wrapped the same way, user:catch(...), and
%unwrapping stops at a goal that is not math_goal_expansion/2, so the guard
%never matches itself.
unguarded_math_expansion_body(arithmetic:math_goal_expansion(A, B), A, B) :- !.
unguarded_math_expansion_body(_:Inner, A, B) :-
    unguarded_math_expansion_body(Inner, A, B).

guard_arithmetic_goal_expansion_clause(Ref) :-
    erase(Ref),
    assertz(( system:goal_expansion(Math, MathGoal) :-
                  catch(arithmetic:math_goal_expansion(Math, MathGoal),
                        error(type_error(evaluable, _), _),
                        fail) )).

:- guard_arithmetic_goal_expansion,
   prolog_listen(system:goal_expansion/2, guard_arithmetic_goal_expansion).
:- use_module(library(aggregate)).
%sub_term/2, which the saturating recovery uses to ask whether an erroring
%arithmetic expression holds a float operand at all.
:- use_module(library(occurs)).
%dif/2 is a goal the ENGINE writes into compiled bodies: engine/duals.pl
%builds it as the negation of an equality when it generates a dual. A goal
%the engine emits has to live in the engine's own module, because that is
%where protect_engine_emitted/1 imports every space's copy from. It used to
%arrive here by accident, through engine/duals.pl's own import into the one
%namespace everything shared, and under NO_AUTOLOAD=1 with duals in a module
%of its own a compiled dual raised
%existence_error(procedure, '$metta_exec:&self':dif/2)
%[measured 2026-08-22, on examples/ch22-a-reasoner-you-can-serve/22-01-logic-programs/03-constructive_negation.metta].
:- use_module(library(dif), [dif/2]).
%The HOST TIER's Prolog predicates. A MeTTa program reaches Prolog through
%callPredicate/2 and import_prolog_function/2, and both resolve in the space's
%module, whose base chain ends here, so what this module holds is what a
%program can call. These two arrived by accident until now: engine/filereader.pl
%loaded library(pcre) and library(readutil) into the one namespace everything
%shared, and examples/ch20-extending-the-engine/20-03-prolog-underneath/02-prologimport.metta imports re_replace/4 and
%calls read_file_to_string/3 through that leak. Cutting the loader into a module
%of its own would have withdrawn both from every MeTTa program without saying
%so, which is a language change and not a refactoring, so they are imported
%here deliberately instead [measured 2026-08-22: the example raised "no
%predicate named re_replace is loaded" the moment the loader stopped sharing].
%re_replace/4 is the other one and it moved into the census block below, since
%library(pcre) is optional and the re-export has to be too.
:- use_module(library(readutil), [read_file_to_string/3, read_line_to_string/2]).
%The engine's own uses of the standard libraries, which autoload used to supply
%into the one namespace every subsystem shared: alpha_list_to_set/2 buckets
%alpha-variants through an assoc, metta_shape_stricter/2 compares two shapes'
%sorted key sets, and metta_trace_source/4 reads the values off a pairs list.
%Under NO_AUTOLOAD=1 each is an existence error at the first call rather than at
%load, so the corpus finds them one example at a time; the complete list is what
%list_undefined/0 reports with autoload off [measured 2026-08-22: six names over
%engine/metta.pl and engine/tracer.pl, zero after these three lines and
%engine/tracer.pl's own]. The import lists are narrow, so the space modules
%below this one gain exactly these names and nothing else.
:- use_module(library(assoc), [empty_assoc/1, get_assoc/3, put_assoc/4]).
:- use_module(library(ordsets), [ord_subtract/3]).
%distinct/2, which 'defined-name'/1 and 'undocumented-space'/2 call to
%dedupe function names read off a space's own equation atoms
%[measured 2026-08-18: examples/ch08-data/08-03-the-shipped-libraries/08-doc_lib.metta under
%NO_AUTOLOAD=1, existence_error(procedure,distinct/2)].
:- use_module(library(solution_sequences)).

%%%%%%%%%% What this platform carries %%%%%%%%%%
%
%Some of the loads in this block are OPTIONAL, and a build without them is a
%real build rather than a broken one: SWI compiled to WebAssembly, which is
%what the browser playground and the Node binding run on, ships no threads, no
%alarms and no subprocesses. An unconditional use_module there fails, SWI
%prints an ERROR pair, the load carries on, and the only record of what was
%lost is that text. A host then has to recover the census by parsing the
%engine's stderr, which extensions/node does, and every next host on a reduced
%platform would write its own regex for the same knowledge.
%
%The same is true of the SWI PACKAGES the engine loads, which are built
%against system libraries and can be left out of a build one at a time: pcre,
%zlib, fastrw and memfile were each unconditional here, and withholding pcre
%alone printed four ERROR pairs -- engine/metta.pl, engine/parser.pl,
%engine/filereader.pl and lib/lib_regex/lib_regex.pl, one per unguarded load
%-- while an (import! &self (library lib_regex)) came back wrapped in a
%transcript of SWI's own source_sink error [measured 2026-08-28 through
%tests/prolog/reduced_platform.pl's extra-withheld set]. They are rows here
%now, so the kernel's platform dependencies are a list a host can READ rather
%than prose in a comment. Rows, not eight of them: a capability is the thing a
%USER loses, so the two libraries the fast cache needs are one row.
%
%So the census is the rule extensions/cmetta/extension.pl and
%extensions/python/extension.pl already state for a SEAT, aimed at the platform:
%NOT PRESENT IS NOT AN ERROR, HALF PRESENT IS. A capability whose library is
%there loads exactly as before, through the same directive in the same place;
%one whose library is absent is RECORDED absent, and the forms resting on it
%refuse by name saying what the absence costs instead of raising
%existence_error(procedure, call_with_time_limit/2) from the interior.
%
%What a row costs is not always a REFUSAL. concurrency, deadlines, subprocess
%and regex each name forms a program cannot run at all without them, so those
%forms refuse. compressed-sources costs one FILE FORMAT: a .gz program refuses
%naming the file, and the same program uncompressed loads, which is CPython's
%answer for the same absence [source: CPython 3.14.4
%tarfile.TarFile.gzopen, `except ImportError: raise CompressionError("gzip
%module is not available") from None`, rather than letting the missing import
%error out of the interior]. fast-cache costs no MeTTa form at all: the
%engine's own loading never reads a cache, so a build without it boots, runs,
%and reparses every source exactly as a build with it does when no cache was
%written. Its two doors still refuse by name rather than half-working, because
%a binary payload only fastrw can read has nothing to fall back TO -- what
%degrades is the engine, not the door.
%
%The guard is a directive rather than SWI's :- if/:- endif conditional
%compilation, and the difference is load-bearing under .qlf: a conditional
%compilation block is decided while the file COMPILES and only the taken
%branch reaches the .qlf, so a .qlf built where a library exists would carry a
%bare use_module and no census at all. A directive is stored in the .qlf and
%re-run on every load, census included [measured 2026-08-27: a directive's
%assertz reappears from a .qlf whose source file has been moved away]. The
%import lands where the bare directive's did, because use_module/1 imports
%into the module its CALLER's clause belongs to and that is this file's
%[measured 2026-08-27: consulted into a module of its own, call_with_time_limit/2
%imported_from(time) there and absent from user].
%
%And the guard is the LOAD ITSELF rather than a question asked before it.
%exists_source/1 in front of use_module/1 is the shape the two seat deciders
%use, it was written that way first, and it resolves the same file name twice
%on every build that HAS the library: a resolution walks every directory on
%the library search path against four file-type extensions, and the three
%probes cost 6,271,103 instructions, 0.37% of a bare boot, for an answer the
%load was about to compute anyway [measured 2026-08-27: 64,860,419
%instructions:u for a process that runs the three probes against 58,589,316
%for the same process without them; command=perf stat -e instructions:u swipl
%-q -g true -t halt; fixture=/tmp/capprobe/cost.pl]. use_module/1 raises
%existence_error(source_sink, Spec) for exactly the missing spec and prints
%nothing when it is caught, so the recovery IS the census row and a present
%capability pays nothing at all.
%
%One row per capability: its name, the platform library it rests on, and what
%a build without it cannot do. The cost text is what a refused user reads, so
%it names MeTTa forms rather than the Prolog predicates behind them. These
%names are the PLATFORM's, and deliberately not the restricted-space grants of
%engine/spaces/lifecycle.pl (file, process, network), which answer the other
%question: whether a space is ALLOWED to do something this build can do.
metta_platform_capability(concurrency, library(thread),
                          '(hyperpose ...), and lib_thread\'s par-map, spawn, \c
                           await, channels, pools and blocking take-atom; \c
                           this build evaluates on one thread').
metta_platform_capability(deadlines, library(time),
                          '(timeout N Expr) and (pragma! max-time N); a \c
                           wall-clock bound has to come from the host \c
                           instead').
metta_platform_capability(subprocess, library(process),
                          '(git-import! ...), and anything else that starts \c
                           a program').
metta_platform_capability(regex, library(pcre),
                          'lib_regex, so (re-match ...), (re-find ...), \c
                           (re-captures ...), (re-split ...), \c
                           (re-replace ...) and (re-replace-all ...); \c
                           (register-token! ...) for a reader class of your \c
                           own; and importing re_replace as a Prolog \c
                           function. lib_text''s plain string forms still \c
                           work').
metta_platform_capability('compressed-sources', library(zlib),
                          'reading or writing a .gz program or space file; \c
                           the same content uncompressed still loads').
%One capability over two libraries, because engine/filereader.pl imports both
%and the cache is what a user loses when either goes. The row is CONSERVATIVE
%about fastrw and deliberately so: fast_read/2 and fast_write/2 are SWI core
%builtins that library(fastrw) only re-exports, so a build missing fastrw.pl
%alone would still have the machinery [measured 2026-08-28: with the engine
%loaded and autoload off, filereader:fast_read/2 reports
%imported_from(system), and /usr/lib/swi-prolog/library/fastrw.pl defines
%only the /1 wrappers and fast_write_to_string/3]. The engine's load is what
%the census speaks for, and the engine loads both.
%library(json) is SWI's ext/json pack rather than its core, so a build can be
%complete and still not have it; the Windows runner is such a build. The C
%implementation engine/build.sh produces from json_codec.c serves the same
%forms when it is present, which is why this is a capability rather than a
%hard requirement.
metta_platform_capability(json, library(json),
                          'converting between MeTTa atoms and JSON text, \c
                           unless engine/json_codec.so was built from \c
                           json_codec.c, which answers the same forms').
%library(crypto) is not part of swipl-wasm. library(sha) is, and supplies the
%five SHA algorithms byte-for-byte identically, so losing crypto costs only
%secure randomness and the algorithms the SHA library does not implement.
metta_platform_capability(crypto, library(crypto),
                          'cryptographically secure (crypto-random-hex ...), \c
                           and non-SHA algorithms of (crypto-hash ...); \c
                           SHA-1, SHA-224, SHA-256, \c
                           SHA-384 and SHA-512 still work through library(sha)').
%library(redis) is absent from swipl-wasm too. Unlike crypto there is no local
%provider for any part of this library, so its source declares the requirement
%and the import door refuses before consulting it.
metta_platform_capability(redis, library(redis),
                          'lib_redis, so (redis-attach ...), Redis-backed \c
                           shared spaces and cross-process subscriptions').
metta_platform_capability('fast-cache', [library(fastrw), library(memfile)],
                          'saving a space in the fast binary format and \c
                           loading one back; every load reads its source \c
                           and parses it, which is what a load without a \c
                           cache does anyway, so nothing else changes').

%What the boot found missing. Empty on a full platform, which is what makes
%every read below one failing call on a dynamic predicate with no clauses.
:- dynamic metta_platform_absent/1.

%A name a capability would have published and could not. Recorded from the
%import list the load asked for, so it needs no second list to fall out of
%date, and read by the one door a MeTTa program reaches a Prolog predicate
%through: import_prolog_function/2 used to answer "no predicate named
%re_replace is loaded", which is true and says nothing about why.
:- dynamic metta_platform_absent_name/2.

%The load and the census in one act, so the two cannot disagree: what is
%recorded absent is exactly what failed to import. The catch is narrow, on the
%spec it just tried, so a library that IS there and breaks while loading still
%raises and stops the boot, which is the half-present half of the rule.
%
%The import lands in the module being LOADED rather than in this file's,
%because the census now serves engine/parser.pl and engine/filereader.pl too
%and each needs the names where its own calls are [measured 2026-08-28, with
%autoload off so a resolution is an import and not the index answering: a bare
%use_module/1 inside this clause puts pcre in THIS module and the calling
%module reaches it only by inheritance, while Into:use_module/2 puts it in the
%caller's]. Outside a load there is no such module and the engine's own is the
%only sensible target; nothing calls these at run time today.
metta_platform_load(Capability) :-
    metta_platform_load(Capability, except([])).

%except([]) rather than a separate import-everything clause: SWI reads it as
%"every exported name minus none", which is what use_module/1 does [measured
%2026-08-28: re_replace/4, re_match/2 and re_compile/3 all imported]. A narrow
%list belongs to a single-library capability; a capability resting on several
%libraries takes them whole.
metta_platform_load(Capability, Imports) :-
    metta_platform_capability(Capability, Requires, _),
    (   prolog_load_context(module, Into)
    ->  true
    ;   metta_engine_module(Into)
    ),
    forall(metta_platform_spec(Requires, Spec),
           metta_platform_admit(Capability, Into, Spec, Imports)).

%An EMPTY import list asks whether the platform HAS the library, and takes no
%name from it. use_module answers that by compiling and linking the whole
%thing, which is the most expensive way to learn a yes: library(redis) costs
%26,939 inferences to load and 2,804 to look up, and the engine imports
%nothing from it. So the census probes for the presence-only case and loads
%only where a caller named something it needs.
metta_platform_admit(Capability, _, Spec, []) :- !,
    (   exists_source(Spec)
    ->  true
    ;   metta_platform_lost(Capability, [])
    ).
metta_platform_admit(Capability, Into, Spec, Imports) :-
    catch(Into:use_module(Spec, Imports),
          error(existence_error(source_sink, Spec), _),
          metta_platform_lost(Capability, Imports)).

%A row names one library or several. The walk is this file's own rather than
%member/2, because the first census directive runs above this file's
%use_module(library(lists)) and would then need autoload to supply it, which
%is the one thing the NO_AUTOLOAD=1 lane exists to catch; engine/qlf_boot.pl
%carries qlf_member/2 for the same reason.


%A row names one library or several. The walk is this file's own rather than
%member/2, because the first census directive runs above this file's
%use_module(library(lists)) and would then need autoload to supply it, which
%is the one thing the NO_AUTOLOAD=1 lane exists to catch; engine/qlf_boot.pl
%carries qlf_member/2 for the same reason.
metta_platform_spec(Requires, Spec) :-
    (   is_list(Requires)
    ->  metta_platform_member(Requires, Spec)
    ;   Spec = Requires
    ).

metta_platform_member([Spec|_], Spec).
metta_platform_member([_|Rest], Spec) :-
    metta_platform_member(Rest, Spec).

%Idempotent because a reload under make/0 runs the directives again.
metta_platform_lost(Capability) :-
    (   metta_platform_absent(Capability)
    ->  true
    ;   assertz(metta_platform_absent(Capability))
    ).

%except([]) holds no Name/Arity pairs, so a whole-library load records the
%capability and no names, which is right: nothing published them by name.
metta_platform_lost(Capability, Imports) :-
    metta_platform_lost(Capability),
    forall(metta_platform_member(Imports, Name/_),
           (   metta_platform_absent_name(Name, Capability)
           ->  true
           ;   assertz(metta_platform_absent_name(Name, Capability))
           )).

%!  metta_platform(?Capability, ?Status, ?Requires, ?Costs) is nondet.
%
%   The census a host reads: every capability, whether this build has it, the
%   platform library it rests on, and what its absence costs. Enumerable, so a
%   host asks for the whole set in one call, and unifiable, so
%   metta_platform(C, absent, R, Costs) is exactly the loss list a binding
%   used to recover from the boot transcript.
metta_platform(Capability, Status, Requires, Costs) :-
    metta_platform_capability(Capability, Requires, Costs),
    (   metta_platform_absent(Capability)
    ->  Status = absent
    ;   Status = present
    ).

%What a form that cannot work without a capability calls before it tries.
%Form is the MeTTa spelling or the source the user wrote, because that is the
%only part of the failure they can act on.
metta_require_platform(Form, Capability) :-
    (   metta_platform_absent(Capability)
    ->  metta_platform_capability(Capability, Requires, Costs),
        throw(error(metta_platform_required(Form, Capability, Requires, Costs),
                    none))
    ;   true
    ).

:- multifile prolog:error_message//1.
prolog:error_message(metta_platform_required(Form, Capability, Requires,
                                             Costs)) -->
    [ '~w is refused: this build does not have the ~w capability, because ~w \c
       is absent. What that costs: ~w.'-[Form, Capability, Requires, Costs] ].

%library(thread), for concurrent_and/3 under (hyperpose ...).
:- metta_platform_load(concurrency).
%library(time), for call_with_time_limit/2, which metta_timeout/3 wraps around
%a findall so a bounded goal keeps every answer; engine/metta/runtime.pl's own
%block records why raw alarm/4 was rejected there.
:- metta_platform_load(deadlines).
%wrap_predicate/4, for making the pragma bound free when no bound is set.
:- use_module(library(prolog_wrap)).
%library(thread) does not declare its own dependency on option/2, and nothing
%else loaded here pulls library(option) in, so jobs/2 resolved it by autoload
%on the first concurrent_and/3 call [verified 2026-08-15: swi_option is absent
%until something touches option/2]. Loading it up front keeps lazy loading off
%the concurrent path. An `Unknown procedure: thread:option/2` was reported once
%under concurrent hyperpose; a race was NOT reproduced in 12 runs of 24 workers
%entering concurrent_and/2 on a barrier, so treat this as cheap hardening and
%not as a diagnosed fix.
:- use_module(library(option)).
:- use_module(library(lists)).
:- use_module(library(yall), except([(/)/3])).
:- use_module(library(apply)).
:- use_module(library(apply_macros)).
%next_lambda_name/1 (translator.pl) calls gensym/2 to name every compiled
%closure: '|->' itself and, through collection_closure/3, every inline body
%argument of foldl-atom, map-atom and filter-atom. Nothing else loaded here
%pulls library(gensym) in, so today it resolves by autoload on the first
%such compile. With autoload=false that call raises
%existence_error(procedure,gensym/2) from inside the engine's own prelude
%(engine/prelude.metta's type-cast-holds is the one equation there that uses
%foldl-atom with an inline body), and SWI's OWN initialization-error
%reporting then masks that primary error: building a source-location
%diagnostic for it calls into library(prolog_clause)'s
%inlined_unification/7, which has its own undeclared, autoload-only
%dependency on nth1/3, so THAT is the only message that ends up printed.
%The visible symptom is "Unknown procedure: prolog_clause:nth1/3" from
%deep inside SWI's shipped library; the actual missing dependency is this
%one, in the engine's own source, and fixing it here removes the secondary
%failure too because the primary error it was papering over never occurs.
:- use_module(library(gensym)).
%library(process). Nothing in the engine calls into it; lib/lib_gitimport/lib_gitimport.pl
%does, and it loads later in this file, so the census row has to be decided
%here where the rest of the platform's is.
:- metta_platform_load(subprocess).
%library(crypto) and library(redis). Neither publishes names into the engine's
%module at boot; these empty imports only decide their census rows. Their own
%libraries import what they use into the space module that loads them.
%Redis is probed here because NOTHING else in the engine mentions it, so
%without this the census could not answer for a capability it declares until
%lib_redis happened to load. Crypto needs no probe of its own: engine/
%filereader.pl asks for crypto_data_hash/3 by name, which records the same
%status, and every reader of that status runs after it - the two digest
%providers in that file and lib_crypto on import. Probing it twice cost 697
%inferences at every boot for an answer already established
%[tested: platform_capabilities:sha_hashing_survives_without_crypto,
%platform_capabilities:crypto_only_operations_refuse_by_name_without_crypto,
%both on a genuinely reduced build; commit=96c4df52838ef5ee3a19af4bbe99a28f73445c46].
:- metta_platform_load(redis, []).
%library(pcre), the HOST TIER re-export the block above this file's imports
%describes: re_replace/4 and nothing else, so a MeTTa program's
%(import_prolog_function re_replace) finds a predicate. The import list is
%what makes the absence say so by name -- metta_platform_lost/2 records
%re_replace against the regex capability, and refuse_absent_prolog_function/1
%reads that instead of answering "no predicate named re_replace is loaded"
%[tested: platform_capabilities:a_re_export_lost_with_its_capability_refuses_by_name].
:- metta_platform_load(regex, [re_replace/4]).
%pcre.pl declares four local :- autoload/2 lines (apply, error, dcg/basics,
%lists) but reads its own Options list with option/2 (library(option))
%without declaring THAT one, so it too resolves by global autoload today
%[measured 2026-08-18: examples/ch08-data/08-03-the-shipped-libraries/04-regex_lib.metta under
%NO_AUTOLOAD=1, existence_error(procedure,pcre:option/2)]. Same trap as
%ugraphs.pl and clpb.pl (lib/lib_constraints/lib_constraints.pl has both), same
%fix. It sat in engine/filereader.pl beside a pcre import that file never
%called into; the patch belongs with the load that actually brings pcre in,
%and it is conditional because on a build without pcre there is no such module
%to patch and naming one would create an empty module of that name.
:- (   metta_platform(regex, present, _, _)
   ->  pcre:use_module(library(option), [option/2])
   ;   true
   ).

%Which module the ENGINE's own predicates live in, asked of SWI at load time
%rather than written down. Two different jobs were both spelled `user` and
%only one of them is about the engine:
%
%  - `user` is the HOST module. SWI resolves file_search_path/2 and
%    thread_message_hook/3 there, consult/1 puts a consulted file there, and
%    janus resolves goal text there [source: SWI-Prolog 10.1 Reference
%    Manual, section 6.11 and its footnote "Unfortunately some hooks are
%    traditionally defined in the user module"]. Those sites go on naming
%    `user`, because that is the name of the thing they mean.
%  - THIS is where the engine's own clauses are, which is wherever this file
%    was consulted. Every wrap_predicate/4 target and every clause/2 read of
%    the engine's own compilation tables follows it.
%
%The two answers coincide today. They stop coinciding the moment a host
%consults the engine into a module of its own, and asking rather than writing
%is what makes that a supported thing rather than a silent breakage
%[tested: metta_engine_module].
:- dynamic metta_engine_module/1.
:- prolog_load_context(module, EngineModule),
   (   metta_engine_module(EngineModule) -> true
   ;   assertz(metta_engine_module(EngineModule))
   ).

%The module the base tier compiles into, written ONCE and read everywhere:
%current_metta_module/1's default, reduce/3's dispatch, fun_here_in/2's shared
%tier and the type family's &self clause all ask for it.
%
%Declared here, before the files that read it are compiled, so the expansion
%below applies to them. spaces.pl owns the mapping this is the '&self' case of
%and asserts the same answer into its cache; the plunit test named below is
%what keeps the two from drifting
%[tested: spaces_execution_modules:the_written_self_module_is_the_mapped_one].
metta_self_module('$metta_exec:&self').

%And the prefix atomic-name mappings are built from, written once for the same
%reason and read the same way. space_module/2 uses it for atomic spaces;
%parametric spaces use their separately prefixed canonical term encoding.
metta_exec_module_prefix('$metta_exec:').

%And read for FREE. A one-clause fact still costs an inference per call, and
%these are the hottest paths in the engine: reduce/3 reads it on every
%dispatch and current_metta_module/1 on every compile and every runnable form.
%goal_expansion/2 replaces the call with the unification it performs, which
%SWI folds into the clause, so the name stays written in one place and the
%read costs nothing [measured 2026-08-19: annotated-relation 483,019 -> 479,523
%inferences, back to its pre-Phase-11 baseline; py-method-call
%1,696,849,495 -> 1,657,043,976 instructions:u].
%
%A unification rather than `true` with the argument bound at expansion time,
%because most callers use this as a TEST on a module they already hold
%(`metta_self_module(Module), !` selects the &self clause of the type family)
%and binding their variable at compile time would make every module answer
%yes.
goal_expansion(metta_self_module(Module), Module = '$metta_exec:&self').
goal_expansion(metta_exec_module_prefix(Prefix), Prefix = '$metta_exec:').

%The seam module loads FIRST and with an EMPTY import list. First because
%every file below declares or asks a seam; empty because `seam:` is the whole
%point of it. Importing the handler seams here would put atom_added/2,
%foreign_match/3 and forty-odd others back in the engine's own namespace,
%where an extension could reach them unqualified again and where each one is a
%name a MeTTa program can no longer have.
:- use_module(ext_points, []).

%%%% The core registries a subsystem WRITES %%%%
%
%A base module makes a name VISIBLE to a subsystem; it does not make a write
%land on it. assertz/1 or retractall/1 in a module that can only SEE a
%predicate creates a predicate of that name in the WRITING module and the
%write goes there, silently, where nothing reads it. Measured on this tree:
%engine/spaces.pl's retractall(fun(F)) and engine/specializer.pl's
%retractall(arity(Name, _)) each made a second, private registry the moment
%their files declared modules, and removing every clause of a function then
%left the function REGISTERED, so a call to it compiled as a call and raised
%existence_error(procedure, '$metta_exec:&self':f/2) where the language says
%the term is simply unreduced [measured 2026-08-22, on
%examples/ch05-equations-and-evaluation/05-02-changing-the-equations/02-functionremoval.metta].
%
%So the four registries a subsystem writes are IMPORTED into every subsystem
%module rather than inherited, which is what makes a write land on the one
%predicate. The list is short on purpose: it is the coupling P11.7 exists to
%make visible, and the layering lane fails on any OTHER name held by two
%engine modules at once, so a fifth cannot arrive quietly
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
metta_shared_registry(fun/1).
metta_shared_registry(arity/2).
metta_shared_registry(metta_shape_fact/4).
metta_shared_registry(metta_shape_declared/2).
%engine/spaces.pl clears a space's import bookkeeping with the space, and pins
%the restricted dispatch names; both tables are the core's.
metta_shared_registry(import_life/3).
metta_shared_registry(fun_scoped/1).

:- dynamic fun/1, arity/2, metta_shape_fact/4, metta_shape_declared/2,
            import_life/3, fun_scoped/1.
:- forall(metta_shared_registry(Registry), export(Registry)).

%!  metta_import_shared_registries is det.
%
%   Import the four into the CALLING module. A subsystem that writes one calls
%   this from a directive of its own, which is where the coupling is visible;
%   the import has to happen while that file is loading, because a write
%   compiled before it would already have made the subsystem a predicate of
%   its own and import/1 then refuses with a name clash.
metta_import_shared_registries(Subsystem) :-
    metta_engine_module(Engine),
    forall(metta_shared_registry(Registry),
           Subsystem:import(Engine:Registry)).

%WHERE THE ENGINE'S OWN SOURCE LIVES, recorded before any unit loads because
%a unit CANNOT compute it. prolog_load_context(directory, D) answers the
%directory of the file being loaded, and a unit consulted into an umbrella has
%its directives stored in the UMBRELLA's .qlf, so the same directive in
%engine/translator/runtime.pl answered engine/translator/ on a source boot and
%engine/ once translator.qlf served it. That is how the C branch-return
%analyzer came to be looked for at engine/translator/mbr.so, found missing, and
%silently replaced by the Prolog pass on every cold tree, which made its
%differential suite skip rather than fail [measured 2026-08-31: metta_c_mbr_active
%false and metta_mbr_artifact naming engine/translator/mbr.so on a purged tree,
%true and naming engine/mbr.so after one boot warmed the .qlf set;
%tested: tests/prolog/static_checks.pl, no_unit_computes_its_own_directory;
%commit=c530ccb8fb7d0a5b2aa53df6e9f981ada9f81be8]. That check refuses the shape for every unit below this
%directory and self-tests against a planted occurrence, so a clean result is
%not a vacuous one.
%
%This file is the umbrella, so ITS load context is engine/ in both modes, and
%that is the whole reason the fact is asserted here rather than beside each
%consumer. The guard keeps a host that already set it, which is what lets an
%embedded engine name its own tree.
:- dynamic metta_engine_src_dir/1.
:- prolog_load_context(directory, Dir),
   (   metta_engine_src_dir(_) -> true
   ;   assertz(metta_engine_src_dir(Dir))
   ).

:- ensure_loaded([parser, type_rules, translator, translator_rules,
                  support_graph, specializer, filereader,
                  '../lib/lib_gitimport/lib_gitimport', spaces, tracer,
                  duals, kernel, '../lib/lib_memo/lib_memo',
                  '../lib/minimal_metta_lib/minimal_metta_lib']).

%A subsystem that declares a module gets THIS module as its base, so the calls
%it makes the other way -- into the engine core, into another subsystem's
%exports, into a MeTTa builtin -- resolve without an import cycle. SWI gives a
%module file the base `user`, which is the right answer only while the engine
%happens to be consulted there; metta_engine_module/1 above exists precisely
%because a host may consult the engine into a module of its own, and the
%subsystem modules have to follow it when it does.
%
%The same set_module(M:base(B)) call engine/spaces.pl makes for a space's
%execution module, and for the same reason: a chain of bases is how a name
%written once is visible everywhere below it
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named,
%spaces_execution_modules:the_chain_is_engine_then_self_then_space].


:- prolog_load_context(directory, EngineSource),
   atom_concat(EngineSource, '/', EngineDirectory),
   metta_engine_module(Engine),
   forall(( source_file(SubsystemFile),
            sub_atom(SubsystemFile, 0, _, _, EngineDirectory),
            module_property(Subsystem, file(SubsystemFile)),
            Subsystem \== Engine ),
          set_module(Subsystem:base(Engine))).


%%%% Extensions: the control file, its vocabulary, and the loader %%%%
%
%A seat is a folder under extensions/ carrying an extension.pl, a
%control file of FACTS the engine READS and never consults -- PostgreSQL's
%control-file model, which this codebase already follows for runtime imports
%(engine/metta/interop.pl reads a source's manifest without running it and says
%so in those words). Each seat used to carry a decider.pl instead, twelve lines
%of imperative Prolog whose whole body was one hand-rolled needs check; the
%checks are the engine's now, so a refusal is named uniformly, an unmet
%prerequisite is a queryable record rather than a silent `; true` branch, and
%`metta list` can answer without loading anything.
%
%The vocabulary, validated at read time -- a fact outside it refuses loudly
%naming the file and the term, because a control file that can smuggle a
%directive is a script with extra steps:
%
%   title(Atom)              what this seat is, one line
%   needs(artefact(Rel))     a build product, relative to the seat's folder
%   needs(prolog_library(L)) exists_source(library(L))
%   needs(predicate(N/A))    current_predicate(N/A): a host marker the way the
%                            C seat registers '$cmetta_present'/0 before it
%                            consults the engine, or a platform door the way
%                            the WASM build lacks open_shared_object/3
%   needs(extension(Other))  that seat loaded first
%   entry(engine, Rel)       the engine consults it here, at boot
%   entry(host, Rel)         the seat's own runtime consults it; recorded so
%                            tooling can derive the transport list, loaded by
%                            the host and never by this glob
%
%Every need met -> every entry(engine, _) is loaded, in the control file's
%order, and the seat is recorded loaded. Any need unmet -> nothing loads,
%nothing prints, and the unmet need is recorded: not built is not an error,
%and half built still is, because a met-needs entry that raises still raises.
:- dynamic metta_extension_loaded/1.
:- dynamic metta_extension_unmet/2.

metta_extension_control_term(title(Title)) :- atom(Title).
metta_extension_control_term(needs(Need)) :- metta_extension_need_shape(Need).
metta_extension_control_term(entry(Role, File)) :-
    % policy-inventory-exempt: mechanism-internal; reason=the two entry roles are the control file's own vocabulary, validated at read time like title/1 and needs/1, and not a value an operator chooses between: which of them a file carries says who does the loading, and the loader below consults exactly the engine ones and never the host ones; evidence=engine/metta.pl:metta_load_extension/1
    memberchk(Role, [engine, host]),
    atom(File).

metta_extension_need_shape(artefact(Relative)) :- atom(Relative).
metta_extension_need_shape(prolog_library(Library)) :- atom(Library).
metta_extension_need_shape(predicate(Name/Arity)) :- atom(Name), integer(Arity).
metta_extension_need_shape(extension(Name)) :- atom(Name).

%The same read-without-running shape interop.pl's manifest scan uses, with the
%opposite policy on a bad term: the import scan goes quiet because the consult
%behind it reports properly, and there is no consult behind this one, so HERE
%the reader is the only thing that will ever speak.
metta_extension_controls(File, Controls) :-
    setup_call_cleanup(open(File, read, In),
                       metta_extension_read(In, File, Controls),
                       close(In)).

metta_extension_read(In, File, Controls) :-
    read_term(In, Term, [variable_names(_)]),
    (   Term == end_of_file
    ->  Controls = []
    ;   (   metta_extension_control_term(Term)
        ->  true
        ;   throw(error(domain_error(extension_control_term, Term),
                        context(File, 'an extension.pl holds only title/1, \c
                                       needs/1 and entry/2 facts')))
        ),
        Controls = [Term|Rest],
        metta_extension_read(In, File, Rest)
    ).

metta_extension_need_met(_, prolog_library(Library)) :-
    exists_source(library(Library)).
metta_extension_need_met(_, predicate(Name/Arity)) :-
    current_predicate(Name/Arity).
metta_extension_need_met(Directory, artefact(Relative)) :-
    directory_file_path(Directory, Relative, Artefact),
    exists_file(Artefact).
metta_extension_need_met(_, extension(Name)) :-
    metta_extension_loaded(Name).

metta_load_extension(Control) :-
    file_directory_name(Control, Directory),
    file_base_name(Directory, Name),
    metta_extension_controls(Control, Controls),
    findall(Need, ( member(needs(Need), Controls),
                    \+ metta_extension_need_met(Directory, Need) ),
            Unmet),
    (   Unmet == []
    ->  forall(member(entry(engine, Relative), Controls),
               ( directory_file_path(Directory, Relative, Entry),
                 ensure_loaded(Entry) )),
        (   metta_extension_loaded(Name) -> true
        ;   assertz(metta_extension_loaded(Name))
        )
    ;   forall(member(Need, Unmet),
               (   metta_extension_unmet(Name, Need) -> true
               ;   assertz(metta_extension_unmet(Name, Need))
               ))
    ).

metta_load_extensions(Pattern) :-
    expand_file_name(Pattern, Found),
    msort(Found, Controls),
    forall(member(Control, Controls), metta_load_extension(Control)).

%One glob and one argv token for every seat, whatever role it plays. There were
%two of each until 2026-08-28, one folder of seats loading unconditionally and
%a second folder behind a token of its own, and the split said that who DRIVES
%the engine and what the engine CONSULTS are different kinds of thing. They are
%not: they are two roles a seat holds, and entry/2 already names them, so the
%Python seat holds both while the Node seat holds only host and MORK only
%engine. One folder, one glob, one token.
%
%A tokenless boot is therefore the pure kernel: no seat is read and none is
%recorded, which is a configuration the engine ships in and the plunit lane
%runs. `extensions` is what run.sh, the packaged CLI, the Python library, the
%C host and the Node host all pass.
%
%Seats load here, before the standard library and the registry directive, so a
%seat's declared builtins and seams exist by the time anything reads them. The
%order within the glob is msort's, and a seat that needs another names it with
%needs(extension(Other)) rather than relying on it.
%
%One backend used to be named here instead, twice: MORK's morkspaces.pl by path
%in a second copy of the whole load list, and its three builtin names in a
%second argv test further down. So a second native backend could not be added
%without editing this file, which is the one thing EXTENDING.md promises an
%extension author never has to do, and MORK was reaching the engine through a
%door no other provider had. It goes through the seam now like everyone else.
%
%A seat that is not built loads nothing and says nothing, and one that is built
%and broken raises, which is the split every host wants and none of them should
%have to implement. That is the control file's business rather than this
%file's: what a seat pulls in, where its build artefacts are, and whether they
%are present at all is its own declaration, and this only reads it.
%
%A native provider's position is fixed rather than its own: seats load after
%everything else the engine defines, because a provider is reached through
%seam:foreign_space/1 and not through clause order. That was true before this
%change and is what made it safe [verified 2026-08-16: moved, whole gate green
%including the MORK tests].
%Where the seats live, recorded once at load time because a RUNTIME reader has
%no load context to compute it from and the require door below is one: the
%diagnosis has to tell "there is no seat by that name" from "this boot read no
%seat at all", and only the directory answers that. The same shape
%standard_library_path/1 uses for lib/ further up this file, and the glob below
%reads the fact rather than repeating the path.
:- dynamic metta_extensions_path/1.
:- prolog_load_context(directory, Src),
   directory_file_path(Src, '../extensions', Extensions),
   asserta(metta_extensions_path(Extensions)).

:- current_prolog_flag(argv, Argv),
   (   memberchk(extensions, Argv)
   ->  metta_extensions_path(Directory),
       directory_file_path(Directory, '*/extension.pl', Pattern),
       metta_load_extensions(Pattern)
   ;   true
   ).

%%%% require-extension!: the named refusal for the half that is missing %%%%
%
%A `lib/` module that rests on a seat states it here, and the engine answers by
%NAME when the seat is not there. lib/lib_mm2/lib_mm2.metta is the case: five
%operators over `&mork` calling MORK's own builtins, with no presence check, so
%on a tree where the FFI was never built each of them failed at call time with
%nothing naming the cause.
%
%PostgreSQL has the identical two-half split and the identical failure, and it
%answers by name: pg_stat_statements is a preloaded C module (the hooks, in
%shared_preload_libraries) plus a per-database CREATE EXTENSION (the views),
%and running the second half without the first raises
%`pg_stat_statements must be loaded via shared_preload_libraries`, SQLSTATE
%55000, object_not_in_prerequisite_state
%[source: postgresql.org/docs/current/pgstatstatements.html, "The module must
%be loaded by adding pg_stat_statements to shared_preload_libraries"; the
%message text and its SQLSTATE quoted verbatim in
%github.com/lesovsky/pgcenter/issues/104].
%
%Two things this says that Postgres's message does not, because needs/1 is
%DATA here and a preload list is not:
%
%  - the cause is TRANSITIVE. metta_extension_unmet/2 holds the seat's own
%    unmet need, and a need of kind extension(Other) is followed into Other's
%    diagnosis, so mm2 -> mork -> the absent artefact is one message rather
%    than three sessions. The walk carries a seen list, so a needs cycle
%    reports rather than loops. This is `nix why-depends` and apt's recursive
%    `Depends: X but it is not going to be installed` in the small.
%  - it ends in the REMEDY, the seat's own build.sh where the seat has one.
%
%What it deliberately does NOT do is name the requiring side in its own text.
%The file loader already composes that around any error whose context is
%`none`, and measuring it is what settled the shape: a form raising
%error(probe_reason(deep), none) inside an imported file renders as
%`'ai-tmp/probe_inner.metta': probe reason deep (while loading MeTTa file)`
%[measured 2026-08-28, engine/filereader/source_lifecycle.pl's
%rethrow_metta_file_error/2, which rethrows a CONTEXTED error unchanged and
%wraps an uncontexted one in the file]. So the inner message names what is
%missing and the frame names who asked, which is PostgreSQL's own MESSAGE and
%CONTEXT split and Node's `Cannot find module` plus `Require stack`. Naming the
%file inside the message too would print it twice, and a require typed at a
%REPL has no requiring file to name at all.
metta_require_extension(Name) :-
    (   metta_extension_loaded(Name)
    ->  true
    ;   metta_extension_cause(Name, Cause),
        throw(error(metta_extension_required(Name, Cause), none))
    ).

%Why a seat is not loaded, in one term. The records answer first, because the
%loader wrote them; the filesystem answers only what no record can, which is
%whether a seat by that name exists at all.
%
%  unmet(Needs)  the loader read the control file and these needs failed
%  unread        the control file is there and this boot never read it, which
%                is the tokenless pure kernel rather than anything missing
%  unknown       no extensions/<Name>/extension.pl exists
metta_extension_cause(Name, unmet(Needs)) :-
    findall(Need, metta_extension_unmet(Name, Need), Needs),
    Needs = [_|_], !.
metta_extension_cause(Name, Cause) :-
    metta_extension_seat_file(Name, 'extension.pl', Control, _),
    (   exists_file(Control)
    ->  Cause = unread
    ;   Cause = unknown
    ).

%A file inside a seat, both ways: the path to open, and the path to SAY. The
%said one is written from the recorded directory's own basename rather than
%from the word `extensions`, so the engine names no seat folder of its own and
%the message follows a rename of the folder
%[tested: test_the_tree_partitions_by_seam].
metta_extension_seat_file(Name, Relative, Path, Said) :-
    metta_extensions_path(Directory),
    directory_file_path(Directory, Name, Seat),
    directory_file_path(Seat, Relative, Path),
    file_base_name(Directory, Root),
    atomic_list_concat([Root, Name, Relative], '/', Said).

%The cause as text. Seen carries the seats already being explained, so the
%extension arm below can follow a need into its own cause without looping.
metta_extension_cause_text(_, Name, unread, Text) :-
    metta_extension_seat_file(Name, 'extension.pl', _, Said),
    format(atom(Text),
           '~w is there and no seat was read on this boot, because the engine \c
            reads the seats only when its argv carries the `extensions` token',
           [Said]).
metta_extension_cause_text(_, Name, unknown, Text) :-
    metta_extension_seat_file(Name, 'extension.pl', _, Said),
    format(atom(Text), 'there is no ~w', [Said]).
metta_extension_cause_text(Seen, Name, unmet(Needs), Text) :-
    findall(Reason,
            ( member(Need, Needs),
              metta_extension_need_reason(Seen, Name, Need, Reason) ),
            Reasons),
    atomic_list_concat(Reasons, ', and ', Text).

%One unmet need of Seat, said with the remedy that clears it. The paths are
%tree-relative rather than absolute because they are what the reader types.
%needs(extension(Other)) is the recursive arm and the reason this is a walk at
%all: Other's own cause is read the same way, under Seen.
metta_extension_need_reason(_, Seat, artefact(Relative), Reason) :-
    metta_extension_seat_file(Seat, Relative, _, Said),
    metta_extension_build_remedy(Seat, Remedy),
    format(atom(Reason), 'artefact ~w is absent~w', [Said, Remedy]).
metta_extension_need_reason(_, _, prolog_library(Library), Reason) :-
    format(atom(Reason),
           'the Prolog library ~w is not on this build\'s library search path',
           [Library]).
metta_extension_need_reason(_, _, predicate(Indicator), Reason) :-
    format(atom(Reason),
           'the predicate ~w is not defined in this process, so whatever \c
            registers it has not run here',
           [Indicator]).
metta_extension_need_reason(Seen, _, extension(Other), Reason) :-
    (   memberchk(Other, Seen)
    ->  format(atom(Reason),
               'extension ~w, which is already being explained above: the \c
                needs graph has a cycle',
               [Other])
    ;   metta_extension_loaded(Other)
    ->  format(atom(Reason),
               'extension ~w, which IS loaded, so the record is stale',
               [Other])
    ;   metta_extension_cause(Other, Cause),
        metta_extension_cause_text([Other|Seen], Other, Cause, Inner),
        format(atom(Reason), 'extension ~w, which is not loaded because ~w',
               [Other, Inner])
    ).

%The seat's own build script, when it ships one, so the message ends where the
%reader can act. Refinement R1 of ai-plan-component-self-containment.md pairs
%this with each build.sh verifying the artefact needs it declares, which is
%what keeps the two from naming different paths.
metta_extension_build_remedy(Seat, Remedy) :-
    metta_extension_seat_file(Seat, 'build.sh', Script, Said),
    (   exists_file(Script)
    ->  format(atom(Remedy), ' (run ~w)', [Said])
    ;   Remedy = ''
    ).

:- multifile prolog:error_message//1.
prolog:error_message(metta_extension_required(Name, Cause)) -->
    { metta_extension_cause_text([Name], Name, Cause, Text) },
    [ 'extension ~w is required and not loaded: ~w'-[Name, Text] ].

%The MeTTa spelling. It answers the unit `[]` like every other builtin whose
%point is what it lets the rest of the file assume, and its first argument is
%guarded because a declared Symbol position is [tested:
%builtin_input_guards:every_builtin_refuses_an_unbound_input_by_name].
'require-extension!'(Name, _) :- var(Name), !,
                                 refuse_unbound_input('require-extension!', 1).
'require-extension!'(Name, []) :- metta_require_extension(Name).

:- consult('metta/terms.pl').
:- consult('metta/operators.pl').
:- consult('metta/input_guards.pl').
:- consult('metta/types.pl').
:- consult('metta/effects.pl').
:- consult('metta/space_hooks.pl').
:- consult('metta/runtime.pl').
:- consult('metta/control.pl').
:- consult('metta/interop.pl').
:- consult('metta/registration.pl').
%%%%%%%%%% The engine's own type surface %%%%%%%%%%
%
%Without this, `get-type` misreported the engine to every tool that reads it.
%`!=` IS a builtin, IS registered and IS declared (: != (-> $a $b Bool)) in
%lib/lib_builtin_types/lib_builtin_types.metta, but with nothing loading that file
%`(get-type !=)` answered %Undefined% for an operation that works. Nothing was
%missing; the type surface was simply not connected, and a reader like the
%metta-lsp port has no way to tell "this has no type" from "this has a type
%nobody loaded".
%
%FACTS RATHER THAN ATOMS IN &self, and that is the whole design decision.
%Loading the file into &self was tried first and it changes what every program
%SEES OF ITS OWN SPACE: `(match &self (: $what $type) ...)` then answers 41
%engine declarations alongside the program's own, which broke
%tests/fixtures/repro3_failed_specialization_self_leak.metta immediately.
%The engine's types belong where the type system reads them and nowhere a
%program enumerating its own atoms can trip over them.
%
%LAST, so a user wins. get_type_candidate/2 tries the intrinsic types, the
%function's arrow, the element-wise reading and &self's own declarations
%before reaching here, so `(: + (-> Foo Bar))` written by a program is
%answered ahead of the engine's and this only ever fills a gap.
%
%ONE SOURCE OF TRUTH: the facts are built by parsing lib_builtin_types.metta
%at boot, so the file a program can still import explicitly and the table the
%engine answers from cannot drift apart.
:- multifile seam:builtin_type_declaration/2.
:- dynamic seam:builtin_type_declaration/2.

load_builtin_type_surface :-
    library('lib_builtin_types.metta', Path),
    exists_file(Path),
    !,
    read_file_to_string(Path, Text, [encoding(utf8)]),
    parse_metta_source(Text, Forms),
    forall(( member(parsed(expression, _, [':', Name, Type]), Forms),
             atom(Name) ),
           ( seam:builtin_type_declaration(Name, Type)
             -> true
             ;  assertz(seam:builtin_type_declaration(Name, Type)) )),
    %Derived from the surface just loaded rather than by a separate
    %initialization, because two initialization/1 goals do not reliably order
    %against each other and an empty index is a silent loss: a constructor like
    %Error would quietly evaluate the argument it exists to carry.
    index_builtin_masks.
load_builtin_type_surface :- index_builtin_masks.

%%%%%%%%%% The engine's prelude %%%%%%%%%%
%
%engine/prelude.metta holds standard vocabulary promoted from the libraries:
%forms every program may use with no import!, compiled here at startup by
%the same translator that compiles a program's own equations. The clauses
%land in the base tier and each head registers as a builtin, so the names
%are visible from every space and shadowable per named space exactly as
%builtins are; the ATOMS are stored in no space at all, so a program
%enumerating &self sees only its own writes, the same design decision
%load_builtin_type_surface records above for the type surface.
%
%Declarations go to prelude_type_declaration/2, a third register beside
%type_declaration/2 (what the program declared) and
%seam:builtin_type_declaration/2 (the engine's Prolog surface). It is consulted
%on the FUNCTION path, which seam:builtin_type_declaration deliberately is not:
%that register describes arguments a caller writes for predicates
%underneath (the maplist lesson, documented at call_site_type_chains/2),
%while a prelude declaration is an ordinary MeTTa declaration for an
%ordinary compiled equation, so honouring it at call sites is exactly
%right, and it is what makes an Atom parameter like assertEqualToResult's
%arrive unevaluated. A program's own declaration is read first, so a user
%redeclaration wins, the same order the type surface keeps.
%
%Two passes, because the file may use a name before defining it
%(type-cast calls type-cast-holds, defined below it): every equation head
%registers first, then every form compiles, so a forward reference
%compiles as the call it is. The filereader solves the same problem with
%a repair pass; the prelude is small enough to pre-register instead.
:- dynamic prelude_type_declaration/2.
:- dynamic prelude_owned/1.
:- dynamic prelude_clause_ref/2.
%Which names the prelude registered as TRANSLATOR RULES. A derived form ships
%as an equation plus that registration, and the registration is the prelude's
%to withdraw: a program that defines the name itself takes the whole form
%over, and a rule pointing at the program's equations would call them as a
%compile-time expander, which is not what an ordinary definition means.
:- dynamic prelude_translator_rule/1.
%The prelude's equations as TERMS, one row per (= ...) form, so a tool
%can enumerate the shipped tier without re-parsing prelude source: the
%loader compiles equations into &self's module rather than storing atoms
%(get-atoms on a user space must not show engine vocabulary), and this
%register is the enumerable door that compilation would otherwise close.
%The confluence reporter is the first consumer.
:- dynamic prelude_equation/2.
%Which seam:builtin_type_declaration/2 rows the prelude PUT THERE, as opposed to
%found there. The two registers overlap once a name needs its Atom mask
%honoured at call sites AND belongs to the engine's reported type surface:
%get-type is declared by lib_builtin_types.metta and again by engine/prelude.metta,
%for the two different readers. Without this ledger the prelude's eviction
%would retract a row the FILE owns, since the two rows are identical and
%retractall/1 cannot tell them apart.
:- dynamic prelude_wrote_builtin_type/2.

%A user definition WINS over the prelude, entirely. When &self compiles
%an equation for a name the prelude owns, the prelude's clauses and
%declarations for that name are evicted first, so the program's own
%definition answers alone, exactly as it did before the name was
%promoted (examples/ch09-types/14-matchtypes.metta defines its own match-types
%and must keep meaning ITS match-types). Additive answers would be the
%non-exclusive-equations reading, but the prelude is engine vocabulary,
%not part of the program, and the house rule everywhere else on this
%boundary is that the user's word replaces the engine's: get-type reads
%a program's declaration ahead of the surface, prelude_type_declaration
%is consulted last. Eviction is one-way; removing the user's equation
%later does not resurrect the prelude's, the same as redefining any
%function. An ordinary named-space function shadows through its module, but a
%translator registration is global, so register_fun_in/2 invokes this door for
%a prelude rule name from every module.
evict_prelude_definition(FAtom) :-
    (   retract(prelude_owned(FAtom))
    ->  %Read before the declarations go, for the reason the write door reads
        %it before it stores: it is the state the compiled clauses were built
        %under.
        result_finality(FAtom, Before),
        forall(retract(prelude_clause_ref(FAtom, Ref)), erase(Ref)),
        retract_prelude_declarations(FAtom),
        retractall(prelude_doc_atom(FAtom, _)),
        retractall(prelude_equation(FAtom, _)),
        (   retract(prelude_translator_rule(FAtom))
        ->  translator_rules:forget_translator_rule(FAtom)
        ;   true
        ),
        %The prelude is the base tier's, so its eviction is &self's change.
        %An eviction takes the prelude's DECLARATION away with its equations,
        %so it reaches the same two directions a declaration write does.
        metta_self_module(Self),
        announce_declaration_changed(Self, FAtom, Before)
    ;   true
    ).

%The ledger rows say exactly which seam:builtin_type_declaration entries are
%the prelude's, so eviction purges both stores and nothing else. A row the
%prelude found already written by lib_builtin_types.metta stays, because it
%was never the prelude's to remove.
retract_prelude_declarations(Name) :-
    forall(retract(prelude_type_declaration(Name, Type)),
           (   retract(prelude_wrote_builtin_type(Name, Type))
           ->  retractall(seam:builtin_type_declaration(Name, Type))
           ;   true
           )).

%The declaration half of the same rule, for the loader's door: a ':'
%atom a file writes into the base tier replaces the prelude's
%declaration for that name, so the compile-time findall over
%type chains sees ONE authority, the user's.
evict_prelude_declaration(Space, [':', Name, _]) :-
    atom(Name),
    Space == '&self',
    !,
    retract_prelude_declarations(Name).
evict_prelude_declaration(_, _).

%The prelude compiles SILENTLY whatever the session's verbosity: these
%are engine internals loading at boot, and a --verbose user asking to see
%their program's compiled clauses is not asking for the engine's own.
%asserta so the silence wins over an already-asserted silent(false), and
%the cleanup erases exactly the clause added here.
load_engine_prelude :-
    setup_call_cleanup(asserta(silent(true), Ref),
                       load_engine_prelude_forms,
                       erase(Ref)).

load_engine_prelude_forms :-
    metta_engine_src_dir(Dir),
    directory_file_path(Dir, 'prelude.metta', Path),
    (   exists_file(Path)
    ->  true
    ;   throw(error(existence_error(source_sink, Path),
                    context(load_engine_prelude/0,
                            'engine/prelude.metta is part of the engine')))
    ),
    read_file_to_string(Path, Text, [encoding(utf8)]),
    parse_metta_source(Text, Forms),
    %Re-loading restores only what eviction removed: a name still owned
    %keeps every clause it has, and its forms are skipped WHOLE (a name
    %may carry several equations, so the skip is per name, decided
    %before anything loads). First load: nothing is owned, nothing
    %skips.
    findall(Owned, prelude_owned(Owned), OwnedBefore),
    %Arity registers in pass one WITH the name: a registered name with no
    %recorded arity compiles a later call site as a partial application
    %(the backends note beside seam:extension_builtin/2 records the same
    %trap), and type-cast calls type-cast-check before pass two reaches
    %its equation.
    forall(( member(parsed(function, _, [=, [FAtom|W], _]), Forms),
             atom(FAtom) ),
           ( register_builtin_fun(FAtom),
             length(W, N),
             Arity is N + 1,
             register_arity(FAtom, Arity) )),
    forall(( member(Form, Forms),
             parsed_form_parts(Form, Kind, Src, Term) ),
           (   Term = [=, [Skip|_], _],
               memberchk(Skip, OwnedBefore)
           ->  true
           ;   load_prelude_form(Kind, Src, Term)
           )).

%A declaration lands in TWO stores: prelude_type_declaration/2 is the
%masking tier the compiler reads and the eviction ledger, and
%seam:builtin_type_declaration/2 is where get-type already looks, so the
%get-type path gains no new clause to try (measured: an extra candidate
%clause cost ~6 inferences per compiled run() call, 2026-08-18). The
%ledger is what lets eviction purge BOTH stores exactly.
load_prelude_form(expression, _, [':', Name, Type]) :-
    atom(Name), !,
    (   prelude_type_declaration(Name, Type) -> true
    ;   assertz(prelude_type_declaration(Name, Type)),
        %lib_builtin_types.metta loads FIRST and may already carry the same
        %declaration, which is the case for a builtin the prelude declares
        %only so the CALL SITE honours its Atom mask: get-type is in both
        %files for two different readers. A second identical fact would give
        %the engine's type surface a duplicate row, so the prelude writes one
        %only when it is the one putting it there, and records that it did.
        (   seam:builtin_type_declaration(Name, Type) -> true
        ;   assertz(seam:builtin_type_declaration(Name, Type)),
            assertz(prelude_wrote_builtin_type(Name, Type))
        )
    ).
%A (@doc ...) form in the prelude lands in the engine's doc register,
%where get-doc's first tier reads it; the prelude documents its own
%vocabulary the way lib_doc documented its own, because a vocabulary
%that reports undocumented names and has none of its own would be
%telling other people to do what it does not.
load_prelude_form(expression, _, Term) :-
    Term = ['@doc', Name | _], atom(Name), !,
    (   prelude_doc_atom(Name, Term) -> true
    ;   assertz(prelude_doc_atom(Name, Term))
    ).
%A DERIVED form: an equation that expands the call plus the registration
%that makes the translator consult it. The loader takes only this one
%runnable shape, so the prelude cannot smuggle arbitrary execution into
%boot, and the name has to be one the prelude itself defines, so a
%registration can never point at somebody else's equations.
load_prelude_form(runnable, Src, ['add-translator-rule!', Name]) :-
    atom(Name), !,
    load_prelude_translator_rule(Name, [], Src).
%The DECLARED registration is the same shape carrying the rule's own
%properties, which are declarations about the rule rather than execution: a
%prelude rule whose expansion introduces `let` binders says so with
%`extra-variables-exempt`, exactly as lib_spaces.metta's succeedsPredicate
%does, and the metatheory lane then reports the exemption with its reason
%instead of recording the rule as not established.
load_prelude_form(runnable, Src, ['add-translator-rule!', Name, Declarations]) :-
    atom(Name), is_list(Declarations), !,
    load_prelude_translator_rule(Name, Declarations, Src).

load_prelude_form(function, _, Term) :-
    Term = [=, [FAtom|W], _], atom(FAtom), !,
    length(W, N),
    Arity is N + 1,
    register_arity(FAtom, Arity),
    %The prelude is the base tier's own vocabulary, so it compiles into &self's
    %module: every other space inherits it from there, and a program that
    %redefines one of its names evicts it exactly as before.
    metta_self_module(Self),
    once(with_metta_module(Self, translate_clause(Term, Clause))),
    assert_function_clause(Self, Clause, Ref),
    assertz(prelude_clause_ref(FAtom, Ref)),
    assertz(prelude_equation(FAtom, Term)),
    (   prelude_owned(FAtom) -> true
    ;   assertz(prelude_owned(FAtom))
    ).
%Anything else is refused rather than skipped: a prelude form that is
%neither a declaration nor an equation is a mistake in the engine's own
%source, and silently ignoring it would ship a vocabulary hole.
load_prelude_form(Kind, Src, _) :-
    throw(error(domain_error(prelude_form, Kind),
                context(load_engine_prelude/0, Src))).

load_prelude_translator_rule(Name, Declarations, Src) :-
    (   prelude_owned(Name)
    ->  (   Declarations == []
        ->  'add-translator-rule!'(Name, _)
        ;   'add-translator-rule!'(Name, Declarations, _)
        ),
        (   prelude_translator_rule(Name) -> true
        ;   assertz(prelude_translator_rule(Name))
        )
    ;   throw(error(existence_error(prelude_definition, Name),
                    context(load_engine_prelude/0, Src)))
    ).

%fun/1 is the exact mutable input metta_py_builtins/1 reads. SWI maintains a
%dynamic predicate's last_modified_generation for cache validation, including
%transaction commit and rollback semantics, so no listener or generic
%write-door flag exists and every mutation route keeps its original cost.
%Keep this read-only host service after the loader predicates it does not call:
%its clause layout then cannot perturb the save-load-metta hot path [measured 2026-08-23:
%save-load-metta 9,223,648 inferences; command=METTA_BENCHMARK_COUNTERS=1
%PYTHONPATH=extensions/python python -m pytest
%-q extensions/python/benchmarks/test_benchmarks.py::test_save_load_metta;
%fixture=deterministic benchmark harness; commit=fc08223618651c122c7e3bfa9f269d03ff1c0932].
metta_host_function_generation(Generation) :-
    predicate_property(fun(_), last_modified_generation(Generation)).

%One initialization goal for all of them, in this order, because
%initialization/1 goals do not reliably order against each other (the note
%above) and the prelude's bodies mention constructors like Error whose Atom
%masking reads the surface loaded first. The seam sweep runs first and for the
%same reason engine/ext_points.pl's own directive cannot be the whole of it: a
%seam is declared there before the file that defines it is loaded, so the
%export the declaration promises can only be made once every engine file has
%been [tested: metta_published_surface:every_declared_seam_that_exists_is_exported].
:- initialization((seam:publish_declared, protect_metta_exec_modules,
                   load_builtin_type_surface, load_engine_prelude,
                   spaces:metta_publish_builtin_visibility,
                   retract_unrelated_system_arities,
                   snapshot_builtin_function_sources)).
