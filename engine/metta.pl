% Purpose: provide PeTTa's Prolog runtime, builtins, type system, evaluator,
%   imports, function registration, and named-space execution context.
% Guarantees:
%   - Files below engine/metta/ are plain source units consulted into this
%     implementation module in their original order; builtin, runtime, and
%     registration predicates retain their existing ownership and clause order
%     [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE].
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
%   - petta_handles_route/5 routes a query by the most specific matching
%     (handles ...) entry in &petta, where specificity is pattern
%     subsumption first and adornment-set inclusion between renaming-equal
%     patterns, disagreeing maximal ties throw petta_contract_conflict/4
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
%   - Import lifecycle state is separate from atom storage, so wildcard atom
%     removal cannot make a loaded source run twice [tested 2026-08-15:
%     filereader_import_lifecycle].
%   - Host failures from builtins retain their ISO error class and name the
%     written MeTTa operation [tested 2026-08-15:
%     metta_operation_errors, translator_evaluation_errors]. Integer
%     arithmetic pays nothing for this and float arithmetic pays one
%     inference per call, because only the integer pair takes the guarded
%     fast path [measured 2026-08-15: 300,000 and 400,000 inferences per
%     100,000 calls, against 300,000 unguarded]; division's integer pair
%     pays the catch too, because a non-divisible pair converts its result
%     to float and can overflow doing it. Whole-corpus cost is
%     +2.1% instructions on examples/performance/scale.metta
%     [measured 2026-08-15].
%   - Python operation purity reaches the same `(effect Name immutable)` atom
%     read by seam:pure_operation/1 [tested:
%     test_pure_registration_reflects_an_effect_atom; commit=6fbd5872cc0ff7abf9c99b90f915f8a31470a861].
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
%   - petta_transaction/1 answers everything its body answers, and every
%     answer's writes commit or roll back together [tested 2026-08-19:
%     bindings/python/tests/test_atomic_forms.py::test_a_transaction_preserves_every_answer_of_its_body].
%   - Every guarded_input_position/3 refuses an unbound argument and names the
%     MeTTa operation, so no builtin binds the caller's variable, invents an
%     answer, runs away or reports a host predicate [tested 2026-08-19:
%     builtin_input_guards:every_builtin_refuses_an_unbound_input_by_name,
%     bindings/python/tests/test_builtin_inputs.py::test_a_raising_builtin_names_the_metta_operation_not_the_host_predicate].
%   - ==/3 and !=/3 refuse two operands of known and different types and
%     answer for every other pair, at no cost on two numbers [tested
%     2026-08-19:
%     bindings/python/tests/test_equality.py::test_cross_kind_equality_answers_what_the_arbiter_answers]
%     [measured 2026-08-19: 4487.45 inferences per thousand-iteration loop,
%     unchanged].
%   - %Undefined% is consistent with every type in both directions, so a call
%     site refuses only a PROVEN conflict, while has_declared_type/2 demands a
%     witness for a contract [tested 2026-08-19:
%     bindings/python/tests/test_gradual_typing.py::test_an_unknown_type_is_consistent_with_every_declared_type,
%     bindings/python/tests/test_answer_protocol.py::test_admission_types_the_pool].
%   - An expression no arrow types reads element-wise, and the tuple it reads
%     is %Undefined% as soon as one member's type is [tested 2026-08-19:
%     metta_type_answers:a_tuple_with_an_untyped_member_is_undefined].
%   - get-type/2 and get-type-space/3 answer from declarations without running
%     the inspected expression, so inspection has no effects of its own
%     [tested 2026-08-19:
%     bindings/python/tests/test_type_inspection.py::test_get_type_does_not_run_its_arguments_effects].
%   - get-type-space/3 reads only the selected space, and the upstream doc
%     family builds @doc-formal answers from that scoped type and prose
%     [tested 2026-08-20:
%     bindings/python/tests/test_doc_family.py::test_the_doc_family_answers_what_upstream_answers].
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
%     is how a DERIVED form ships. A program that defines such a name takes
%     the whole form over, so the registration is withdrawn with the clauses
%     [tested 2026-08-19: prelude_derived_forms].
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
%   - petta_assertion_failure/4 classifies the three assertion formals, so a
%     harness tells a false claim from a broken engine by TYPE rather than by
%     reading the message [tested 2026-08-19:
%     bindings/python/tests/test_assertion_failures.py::test_a_failing_assertion_is_a_different_exception_from_an_engine_fault].
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
%     bindings/python/tests/test_ops.py::test_a_declared_type_survives_the_library_being_loaded]
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
%     no backends), +0.54% with backends loaded too, +0.14% over a full
%     example run that also exercises the opt-in libraries' own fixes
%     (lib/lib_constraints.pl, lib/lib_memo.pl) [measured 2026-08-18:
%     interleaved min-of-3, perf stat -e instructions:u, spread under
%     0.003% within each side].
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
library(X, Path) :- standard_library_path(Base),
                    directory_file_path(Base, X, Path).
%A named library directory, git-fetched or registered. A library that
%pip-installs is under neither: standard_library_path/1 is one directory,
%<src>/../lib, so (library fast.pl) cannot reach a package's own files and a
%downstream library has to pass absolute paths, which is what
%lib/minimal_metta_lib.py does with os.path.dirname(os.path.abspath(__file__)).
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
    throw(error(petta_unresolved_library(Alias, File, Directories),
                context(library/3, 'no readable file of that name'))).

prolog:error_message(petta_unresolved_library(Alias, File, [])) -->
    [ '(library ~w ~w) does not resolve: nothing is registered under the \c
       alias ~w. Register the directory with register_metta_library_path, or \c
       import the file by path.'-[Alias, File, Alias] ].
prolog:error_message(petta_unresolved_library(Alias, File, Directories)) -->
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
%existence_error(procedure, '$petta_exec:&self':dif/2)
%[measured 2026-08-22, on examples/reasoning/constructive_negation.metta].
:- use_module(library(dif), [dif/2]).
%The HOST TIER's Prolog predicates. A MeTTa program reaches Prolog through
%callPredicate/2 and import_prolog_function/2, and both resolve in the space's
%module, whose base chain ends here, so what this module holds is what a
%program can call. These two arrived by accident until now: engine/filereader.pl
%loaded library(pcre) and library(readutil) into the one namespace everything
%shared, and examples/integration/prologimport.metta imports re_replace/4 and
%calls read_file_to_string/3 through that leak. Cutting the loader into a module
%of its own would have withdrawn both from every MeTTa program without saying
%so, which is a language change and not a refactoring, so they are imported
%here deliberately instead [measured 2026-08-22: the example raised "no
%predicate named re_replace is loaded" the moment the loader stopped sharing].
:- use_module(library(pcre), [re_replace/4]).
:- use_module(library(readutil), [read_file_to_string/3, read_line_to_string/2]).
%The engine's own uses of the standard libraries, which autoload used to supply
%into the one namespace every subsystem shared: alpha_list_to_set/2 buckets
%alpha-variants through an assoc, petta_shape_stricter/2 compares two shapes'
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
%[measured 2026-08-18: examples/libraries/doc_lib.metta under
%NO_AUTOLOAD=1, existence_error(procedure,distinct/2)].
:- use_module(library(solution_sequences)).
:- use_module(library(thread)).
%alarm/4 and remove_alarm/1, which metta_timeout/2 uses instead of
%call_with_time_limit/2 so a bounded goal keeps its answers.
:- use_module(library(time)).
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
:- use_module(library(process)).

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
:- dynamic petta_engine_module/1.
:- prolog_load_context(module, EngineModule),
   (   petta_engine_module(EngineModule) -> true
   ;   assertz(petta_engine_module(EngineModule))
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
metta_self_module('$petta_exec:&self').

%And the prefix atomic-name mappings are built from, written once for the same
%reason and read the same way. space_module/2 uses it for atomic spaces;
%parametric spaces use their separately prefixed canonical term encoding.
metta_exec_module_prefix('$petta_exec:').

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
goal_expansion(metta_self_module(Module), Module = '$petta_exec:&self').
goal_expansion(metta_exec_module_prefix(Prefix), Prefix = '$petta_exec:').

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
%existence_error(procedure, '$petta_exec:&self':f/2) where the language says
%the term is simply unreduced [measured 2026-08-22, on
%examples/functions/functionremoval.metta].
%
%So the four registries a subsystem writes are IMPORTED into every subsystem
%module rather than inherited, which is what makes a write land on the one
%predicate. The list is short on purpose: it is the coupling P11.7 exists to
%make visible, and the layering lane fails on any OTHER name held by two
%engine modules at once, so a fifth cannot arrive quietly
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
petta_shared_registry(fun/1).
petta_shared_registry(arity/2).
petta_shared_registry(petta_shape_fact/4).
petta_shared_registry(petta_shape_declared/2).
%engine/spaces.pl clears a space's import bookkeeping with the space, and pins
%the restricted dispatch names; both tables are the core's.
petta_shared_registry(import_life/3).
petta_shared_registry(fun_scoped/1).

:- dynamic fun/1, arity/2, petta_shape_fact/4, petta_shape_declared/2,
            import_life/3, fun_scoped/1.
:- forall(petta_shared_registry(Registry), export(Registry)).

%!  petta_import_shared_registries is det.
%
%   Import the four into the CALLING module. A subsystem that writes one calls
%   this from a directive of its own, which is where the coupling is visible;
%   the import has to happen while that file is loading, because a write
%   compiled before it would already have made the subsystem a predicate of
%   its own and import/1 then refuses with a name clash.
petta_import_shared_registries(Subsystem) :-
    petta_engine_module(Engine),
    forall(petta_shared_registry(Registry),
           Subsystem:import(Engine:Registry)).

:- ensure_loaded([parser, type_rules, translator, translator_rules,
                  support_graph, specializer, filereader,
                  '../lib/lib_gitimport', spaces, tracer, duals, kernel,
                  '../lib/lib_memo']).

%A subsystem that declares a module gets THIS module as its base, so the calls
%it makes the other way -- into the engine core, into another subsystem's
%exports, into a MeTTa builtin -- resolve without an import cycle. SWI gives a
%module file the base `user`, which is the right answer only while the engine
%happens to be consulted there; petta_engine_module/1 above exists precisely
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
   petta_engine_module(Engine),
   forall(( source_file(SubsystemFile),
            sub_atom(SubsystemFile, 0, _, _, EngineDirectory),
            module_property(Subsystem, file(SubsystemFile)),
            Subsystem \== Engine ),
          set_module(Subsystem:base(Engine))).


%A host is a seat's decider file under bindings/, the backends split one
%directory over: the
%decider file loads unconditionally and whether its bridge is usable is its
%own business, so the engine names no host and the next host is a new
%seat folder with a decider.pl. Hosts load here, before the standard library and the registry
%directive, so a bridge's declared builtins and seams exist by the time
%anything reads them.
:- prolog_load_context(directory, Src),
   directory_file_path(Src, '../bindings/*/decider.pl', Pattern),
   expand_file_name(Pattern, Found),
   msort(Found, Files),
   forall(member(File, Files), ensure_loaded(File)).

%%%% Native backends %%%%
%
%A native backend is a space provider whose implementation is a shared library
%rather than Prolog. Once loaded it is a foreign space like any other and this
%file knows nothing more about it; what it needs from the engine is somewhere
%to be loaded FROM, and that is all this does.
%
%One backend used to be named here instead, twice: `'../backends/mork/mork_ffi/morkspaces'`
%in a second copy of the whole load list, and its three builtin names in a
%second argv test further down. So a second native backend could not be added
%without editing this file, which is the one thing EXTENDING.md promises an
%extension author never has to do, and MORK was reaching the engine through a
%door no other provider had. It goes through the seam now like everyone else.
%
%A backend is an integration folder in backends/ with a decider.pl at its
%top. Loading one is consulting that decider, and
%what it pulls in, where its build artefacts are, and whether they are present
%at all is the backend's own business: a backend that is not built loads
%nothing and says nothing, and one that is built and broken raises, which is
%the split every host wants and none of them should have to implement.
%
%The engine's own position is fixed rather than the backend's: they load after
%everything, because a provider is reached through seam:foreign_space/1 and
%not through clause order. That was true before this change and is what made it
%safe [verified 2026-08-16: moved, whole gate green including the MORK tests].
:- prolog_load_context(directory, Src),
   current_prolog_flag(argv, Argv),
   (   memberchk(backends, Argv)
   ->  directory_file_path(Src, '../backends/*/decider.pl', Pattern),
       expand_file_name(Pattern, Found),
       msort(Found, Files),
       forall(member(File, Files), ensure_loaded(File))
   ;   true
   ).

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
%lib/lib_builtin_types.metta, but with nothing loading that file
%`(get-type !=)` answered %Undefined% for an operation that works. Nothing was
%missing; the type surface was simply not connected, and a reader like the
%metta-lsp port has no way to tell "this has no type" from "this has a type
%nobody loaded".
%
%FACTS RATHER THAN ATOMS IN &self, and that is the whole design decision.
%Loading the file into &self was tried first and it changes what every program
%SEES OF ITS OWN SPACE: `(match &self (: $what $type) ...)` then answers 41
%engine declarations alongside the program's own, which broke
%tests/regression/repro3_failed_specialization_self_leak.metta immediately.
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
    index_masking_data_heads.
load_builtin_type_surface :- index_masking_data_heads.

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
:- dynamic petta_engine_src_dir/1.
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
%promoted (examples/types/matchtypes.metta defines its own match-types
%and must keep meaning ITS match-types). Additive answers would be the
%non-exclusive-equations reading, but the prelude is engine vocabulary,
%not part of the program, and the house rule everywhere else on this
%boundary is that the user's word replaces the engine's: get-type reads
%a program's declaration ahead of the surface, prelude_type_declaration
%is consulted last. Eviction is one-way; removing the user's equation
%later does not resurrect the prelude's, the same as redefining any
%function. Named spaces need none of this: their clauses shadow through
%their own module already, the builtin-override rule.
evict_prelude_definition(FAtom) :-
    (   retract(prelude_owned(FAtom))
    ->  forall(retract(prelude_clause_ref(FAtom, Ref)), erase(Ref)),
        retract_prelude_declarations(FAtom),
        retractall(prelude_doc_atom(FAtom, _)),
        retractall(prelude_equation(FAtom, _)),
        (   retract(prelude_translator_rule(FAtom))
        ->  retractall(translator_rule(FAtom, _))
        ;   true
        ),
        %The prelude is the base tier's, so its eviction is &self's change.
        metta_self_module(Self),
        announce_function_changed(Self, FAtom)
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

:- prolog_load_context(directory, Dir),
   (   petta_engine_src_dir(_) -> true
   ;   assertz(petta_engine_src_dir(Dir))
   ).

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
    petta_engine_src_dir(Dir),
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
    %(the backends note beside seam:backend_builtin/1 records the same
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
    (   prelude_owned(Name)
    ->  'add-translator-rule!'(Name, _),
        (   prelude_translator_rule(Name) -> true
        ;   assertz(prelude_translator_rule(Name))
        )
    ;   throw(error(existence_error(prelude_definition, Name),
                    context(load_engine_prelude/0, Src)))
    ).
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

%fun/1 is the exact mutable input petta_py_builtins/1 reads. SWI maintains a
%dynamic predicate's last_modified_generation for cache validation, including
%transaction commit and rollback semantics, so no listener or generic
%write-door flag exists and every mutation route keeps its original cost.
%Keep this read-only host service after the loader predicates it does not call:
%its clause layout then cannot perturb the save-load-metta hot path [measured 2026-08-23:
%save-load-metta 9,223,648 inferences; command=PETTA_BENCHMARK_COUNTERS=1
%PYTHONPATH=bindings/python python -m pytest
%-q bindings/python/benchmarks/test_benchmarks.py::test_save_load_metta;
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
                   retract_unrelated_system_arities)).
