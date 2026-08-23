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
%%% Registration: %%%
:- dynamic fun/1, arity/2.
register_fun(N) :- must_be(atom, N),
                   ( fun(N) -> true
                   ; assertz(fun(N), Ref),
                     record_source_assertion(Ref),
                     repair_after_late_registration(N) ).

%The arities a loaded predicate is callable at, which is what a registration
%from Prolog has to record: every other route knows its arity from the
%equation head it just compiled and calls register_arity/2 with it directly.
%An operator's name answers current_predicate/1 at arities 1 and 2 whether or
%not a predicate of that name exists, so those two are not registrable.
%
%This walk used to live inside register_fun/1, guarded by "the name is new".
%A library registering 'norm'/3 for a name some space already defined at MeTTa
%arity 1 therefore recorded no arity at all, and incomplete_application_kind/3
%reads a missing arity as "not applied far enough", so (norm a b) compiled to a
%partial application. Reading it here instead means the arities are recorded
%for the registration that asked for them, whatever else knows the name
%[tested: a_registration_records_arities_for_a_name_that_is_already_a_function].
%Every arity the name is CALLABLE at, and callable means defined here rather
%than merely visible. The exclusion is not defensive: library(yall) exports
%//2 through //9 into user as its free-variables lambda, so probing
%current_predicate/1 alone recorded SEVEN arities for `/` where + and * have
%one. (/ 1 2 3) then compiled to a direct '/'(1,2,3,_) call, which is yall's
%lambda, and answered `type_error(lambda_free, 1)` where every other operator
%answers the engine's own function_input_arities naming the operator
%[tested: metta_registration_arities].
%
%imported_from/1 is the exact question, and the arity =< 2 clause below is the
%older half-answer to the same thing: it excluded 1/2 the TERM and nothing
%told it about 1/2 the lambda.
register_prolog_arities(N) :-
    forall(( current_predicate(N/Arity),
             \+ (current_op(_, _, N), Arity =< 2),
             \+ (current_op(_, _, N), imported_predicate(N, Arity)) ),
           register_arity(N, Arity)).

%%% Arities a SWI system predicate lent a MeTTa name by accident %%%
%
%A SWI SYSTEM predicate that shares a MeTTa operation's name but not its shape
%is a different predicate, and registering its arity made an UNDER-APPLIED call
%compile straight into it. `!(not)` reached SWI's own not/1, which is negation,
%and aborted the runnable with `not/1: Arguments are not sufficiently
%instantiated` instead of answering anything at all; the same held for
%`(append)`, `(assert)`, `(exists_file)` and `(sleep)`. Under-applying an
%operation is an ordinary MeTTa event -- this engine answers a partial
%application, `(sqrt-math)` is `(partial sqrt-math ())` -- and no MeTTa event
%may take the host down
%[tested: test_an_underapplied_operation_answers_instead_of_aborting].
%
%The operation's OWN declarations decide which arities are its: a chain of N
%links is the Prolog predicate of arity N, one argument per link with the last
%being the result. So `(: not (-> Bool Bool))` keeps not/2 and drops not/1, and
%`(: length (-> Expression Number))` keeps length/2 even though length/2 is a
%system predicate too. Measured on this tree: exactly nine registrations go,
%append/1, assert/1, copy_term/3, copy_term/4, exists_file/1, not/1, sleep/1,
%sort/4 and term_hash/4, none of which any example, test or library calls, and
%every library or engine-defined predicate is untouched because it is not
%built_in.
%
%IT RUNS AFTER THE DECLARATIONS AND THE PRELUDE, not while the names register,
%and that ordering is the whole reason it is a separate pass:
%register_builtin_fun/1 runs at DIRECTIVE time while load_builtin_type_surface/0
%and load_engine_prelude/0 run at INITIALIZATION time, so a filter inside the
%registration sees an empty declaration table and drops the arities it exists to
%keep -- measured, it took length/2, sort/2 and msort/2 with it and turned
%`(length (1 2 3))` into a partial application. It is one pass over the registry
%rather than a test on the hot path, which is why the calls that read arity/2
%are untouched.
%
%Limitation: a host library or backend that registers a name AFTER the boot
%chain is not swept, because nothing re-runs this. Nothing in the tree does
%that today; a registration door that starts to would call this again.
retract_unrelated_system_arities :-
    findall(N-Arity,
            ( arity(N, Arity), unrelated_system_predicate(N, Arity) ),
            Unrelated),
    forall(member(N-Arity, Unrelated), retractall(arity(N, Arity))).

unrelated_system_predicate(N, Arity) :-
    functor(Head, N, Arity),
    petta_engine_module(Engine),
    predicate_property(Engine:Head, built_in),
    seam:builtin_type_declaration(N, _),
    \+ declared_metta_arity(N, Arity).

declared_metta_arity(N, Arity) :-
    seam:builtin_type_declaration(N, [->|Links]),
    length(Links, Arity).

%Only for an OPERATOR, and the first attempt got that wrong: excluding every
%imported predicate dropped length/2, which is library(lists)'s and a
%perfectly good builtin, so (length ...) compiled to partial(length, [...])
%and four gates went red. An imported predicate is normal; an imported
%predicate whose name is also an OPERATOR is the collision.
imported_predicate(N, Arity) :-
    functor(Head, N, Arity),
    petta_engine_module(Engine),
    predicate_property(Engine:Head, imported_from(_)).

%Record each callable arity once, even when a function has many equations.
register_arity(N, Arity) :- ( arity(N, Arity) -> true
                            ; assertz(arity(N, Arity), Ref),
                              record_source_assertion(Ref) ).

%The module whose equations are in scope while a term is compiled or run. The
%default is &self's, which is where a program that names no space writes.
%
%The default is a fact read rather than a constant unified, one inference
%instead of none, because the alternative is writing '$petta_exec:&self' out
%here and having two places that decide the name
%[tested: metta_module_context:the_default_context_is_selfs_own_module].
current_metta_module(Module) :-
    ( nb_current('$petta_module', M) -> Module = M ; metta_self_module(Module) ).

%Skipping the switch when Module is already in force was tried and taken back
%out. It saved 4 inferences on every Python evaluation and cost 2 on every
%annotated typed call, which is the wrong side of that trade: the crossing
%happens once and the typed call happens in a loop. Measured 2026-08-16, the
%@m.define annotated tier of bindings/python/benchmarks/extension_cost.py went 20.00 to
%22.00 with the test in place, against m.fn 68.00 to 64.00.
%The argument is a MODULE, and refusing anything else is what keeps this
%honest now that a space and its module are different atoms. They used to be
%the same atom for every space but &self, so `with_metta_module('&pool', G)`
%worked by coincidence; today it would switch the context to a module nothing
%compiles into, every lookup would miss, and the goal would answer as if the
%space were empty. One indexed cache probe turns that into a refusal at the
%call [tested: metta_module_context:a_space_name_is_refused_where_a_module_is_asked].
with_metta_module(Module, Goal) :-
    (   metta_exec_module_known(_, Module)
    ->  true
    ;   throw(error(type_error(metta_execution_module, Module),
                    context(with_metta_module/2,
                            'space_module/2 maps a space to the module its \c
                             clauses are in; pass that, not the space')))
    ),
    current_metta_module(Previous),
    setup_call_cleanup(b_setval('$petta_module', Module),
                       Goal,
                       b_setval('$petta_module', Previous)).

%Control signals pass through every recovery catch: a caught abort, limit,
%alarm, or interrupt is a stopped program pretending it succeeded. This is
%the KeyboardInterrupt-outside-Exception design; a swallowed limit signal
%also DISARMS call_with_inference_limit for the rest of the call, measured
%as six million inferences spent under a thousand-inference budget when a
%recovery catch ate the signal mid-translation.
%
%The engine's own list. It is a SEAM, so a library that introduces its own
%cancellation or budget signal adds a clause instead of being swallowed by
%the first recovery catch it meets
%[tested: a_librarys_own_control_signal_is_not_recovered_from].
%
%Its multifile declaration is HERE and not with the other seams, which is the
%one exception seam_home/2 in engine/ext_points.pl exists to answer. The name
%is also an engine_emitted/1 one: the translator writes control_exception/1
%into compiled bodies and protect_engine_emitted/1 imports every emitted name
%into a space's execution module FROM THE ENGINE'S MODULE, so a copy living
%in the seam module would leave the import with nothing to find.
:- multifile control_exception/1.
control_exception(time_limit_exceeded).
control_exception(inference_limit_exceeded).
control_exception(metta_host_interrupted).
control_exception('$aborted').
%The reserved seam envelopes for the same two signals: the shim declares
%every metta_control_signal kind control on the Python side, and these two
%are thrown by the ENGINE's own bound forms (inferences, with-pragma!),
%so the CLI must agree or a program could catch its own budget there and
%disarm the counter.
control_exception(error(metta_control_signal(time_limit, _), _)).
control_exception(error(metta_control_signal(inference_limit, _), _)).

%The reserved envelope renders its payload: a reader failure used to cross
%as a bare syntax_error and take SWI's own message with it, and wrapping
%it in the envelope must not trade "missing ')' ..." for an unknown-term
%dump on a host that shows message text.
:- multifile prolog:error_message//1.
prolog:error_message(metta_control_signal(syntax, Detail)) -->
    [ 'MeTTa syntax error: ~w'-[Detail] ].
control_exception(error(resource_error(_), _)).

%A result past binary64 SATURATES to the IEEE value instead of raising,
%which is upstream's arithmetic (plain Rust f64: "1e400".parse and 1e308*10
%both answer inf there) and the reader's own behaviour for literals, so the
%two halves of the numeric boundary agree: 1e400 reads as inf and
%(+ 1e400 1) answers inf. SWI's error mode rejects any non-finite RESULT,
%operands included, so without this an infinity the reader legally produced
%could not even carry through (+ inf 1). The flag is borrowed for the one
%retry and given back, parser.pl's metta_saturating_parse discipline on the
%evaluation side; the happy path pays nothing because this only runs from a
%catch recovery. The same discipline covers the whole IEEE family when a
%floating expression is present, including an explicit integer promotion:
%division by a float zero answers the signed infinity and the NaN class
%(0.0/0.0, inf - inf, sqrt of a negative, asin past one) answers NaN, which
%is what isnan-math and isinf-math exist to
%observe. Every fault outside metta_ieee_retry/1, integer division by zero
%first among them, reaches the operation-recovery funnel below; the retry's
%own catch is the net for faults the flags do not govern, none known for the
%shipped operations.
metta_saturating_recover(Operation, Expression, Result, Error) :-
    metta_ieee_saturable(Expression, Error),
    !,
    current_prolog_flag(float_overflow, WasOverflow),
    current_prolog_flag(float_zero_div, WasZeroDiv),
    current_prolog_flag(float_undefined, WasUndefined),
    catch(setup_call_cleanup(
              ( set_prolog_flag(float_overflow, infinity),
                set_prolog_flag(float_zero_div, infinity),
                set_prolog_flag(float_undefined, nan) ),
              Result is Expression,
              ( set_prolog_flag(float_overflow, WasOverflow),
                set_prolog_flag(float_zero_div, WasZeroDiv),
                set_prolog_flag(float_undefined, WasUndefined) )),
          Residual,
          rethrow_metta_operation_error(Operation, Residual)).
metta_saturating_recover(Operation, _, _, Error) :-
    petta_arithmetic_rethrow(Operation, Error).

%is/2 raises a BARE instantiation error for an operand it does not have, and
%that error names neither the operation's modes nor what to write instead: it
%is SWI's, not the language's. Every backward query the engine CAN answer is
%decided before an exception exists (petta_int_solve/5 for one unknown among
%integers, petta_clp_backward/4 for the integer relations past it), so what
%reaches here is a query outside both: a float operand, or an operation with
%no relation to solve. It refuses by name
%[tested: test_arithmetic_inverts_past_the_linear_case_or_refuses_with_the_reason].
petta_arithmetic_rethrow(Operation, error(instantiation_error, _)) :- !,
    petta_refuse_unsolved_arithmetic(Operation, unbound_operand).
petta_arithmetic_rethrow(Operation, Error) :-
    rethrow_metta_operation_error(Operation, Error).

%Float zero division belongs to the IEEE retry, while integer zero division
%is a contained language result. Test the IEEE class first so `/ 1.0 0.0`
%keeps its signed infinity and only the all-integer fault reaches the shared
%operation recovery.
metta_arithmetic_saturating_recovery(Operation, Arguments, Expression,
                                     Error, Result) :-
    (   metta_ieee_saturable(Expression, Error)
    ->  metta_saturating_recover(Operation, Expression, Result, Error)
    ;   metta_operation_recovery(Operation, Arguments, Error, Result)
    ).

%An operation fault is an answer when the language gives the fault a reason.
%LeaTTa pins both integer doors byte-exactly as (Error (<op> 7 0)
%DivisionByZero), while every other host error retains the raising path
%[source: LeaTTa tests/regression/division_convention.metta:82-90;
%tested: test_integer_division_by_zero_answers_what_d1_decides;
%commit=ecd792eacbfe1810645434ce406f79be3a9e03d1].
metta_operation_recovery(Operation, Arguments,
                         error(evaluation_error(zero_divisor), _), Answer) :-
    maplist(integer, Arguments), !,
    metta_error_atom(Operation, Arguments, 'DivisionByZero', Answer).
metta_operation_recovery(Operation, _, Error, _) :-
    petta_arithmetic_rethrow(Operation, Error).

%Which evaluation faults license the retry. Overflow retries
%unconditionally, because an ALL-INTEGER division can overflow in its float
%conversion and the saturated value is this engine's committed answer
%there. Zero division and the NaN family retry only when the expression has a
%float operand or an explicit float/1 promotion: upstream's float arm is raw
%f64 (1.0/0.0 is inf,
%0.0/0.0 and inf - inf are NaN, by construction), while its INTEGER
%division by zero answers a DivisionByZero Error atom, so an integer zero
%takes the operation-recovery funnel instead of this retry. The retry runs
%under all three IEEE flags at once rather
%than only the one that fired, because a compound expression can fault
%twice: log-math with base 1 overflows in log(0.0) and then divides the
%saturated -inf by log(1) = 0.0, and one-flag-at-a-time would error where
%the arbiter's arithmetic answers -inf.
metta_ieee_retry(float_overflow).
metta_ieee_retry(zero_divisor).
metta_ieee_retry(undefined).

%Whether a fault is in the retryable family at all, factored out so the
%chained recovery above can ask without committing to the retry.
metta_ieee_saturable(Expression, error(evaluation_error(Evaluation), _)) :-
    metta_ieee_retry(Evaluation),
    (   Evaluation == float_overflow
    ->  true
    ;   sub_term(Operand, Expression),
        (   float(Operand)
        ;   compound(Operand), functor(Operand, float, 1)
        )
    ).

%Keep the ISO Formal term because callers and the MeTTa catch form inspect it.
%Only the host context is replaced, so lists:min_list/3, is/2, and nb_setval/2
%cannot leak into a language-level diagnostic. Integer fast paths avoid the
%catch cost on valid arithmetic without letting float overflow escape, except
%division, whose all-integer case converts a non-divisible pair to float and
%can overflow doing it, so it pays the catch like the float arms. Over
%100,000 calls the guarded form used
%300,002 inferences against 300,003 directly, while an unconditional catch used
%400,002 [measured: guarded -1 and caught +99,999 inferences, 2026-08-15].
rethrow_metta_operation_error(_, Error) :- control_exception(Error), !,
                                            throw(Error).
rethrow_metta_operation_error(Operation, error(Formal, _)) :- !,
    throw(error(Formal,
                context(Operation, 'while evaluating MeTTa operation'))).
rethrow_metta_operation_error(_, Error) :- throw(Error).

throw_metta_type_error(Operation, Expected, Culprit) :-
    throw(error(type_error(Expected, Culprit),
                context(Operation, 'invalid MeTTa operation argument'))).

%The classification a host reads a builtin refusal through, beside the two
%throwers that produce the shape. The engine names the written MeTTa
%operation in the context, so a host reads the name from the term rather
%than from rendered text; only a type_error carries an expected type and a
%culprit, and any other formal reports its own functor with both parts
%ABSENT. Absence is an unbound part, which is the one marker no culprit can
%collide with; a host maps var-ness to its own None.
metta_host_operation_error(error(Formal, context(Operation, Message)),
                           Operation, Kind, Expected, Culprit) :-
    atom(Operation),
    nonvar(Message),
    metta_host_operation_message(Message),
    nonvar(Formal),
    metta_host_operation_formal(Formal, Kind, Expected0, Culprit0),
    metta_host_operation_part(Expected0, Expected),
    metta_host_operation_part(Culprit0, Culprit).

metta_host_operation_message('while evaluating MeTTa operation').
metta_host_operation_message('invalid MeTTa operation argument').

%is/2 reports an unevaluable term as a predicate indicator, Name/Arity. That
%is a Prolog artifact rather than anything the user wrote, and swrite would
%read the / as MeTTa and print (/ a 0). A zero-arity indicator is exactly
%the symbol the source wrote, so it crosses as that symbol.
metta_host_operation_formal(type_error(evaluable, Name/Arity), type_error,
                            evaluable, Culprit) :- !,
    ( Arity =:= 0 -> Culprit = Name
                   ; format(atom(Culprit), '~w/~w', [Name, Arity]) ).
metta_host_operation_formal(type_error(Expected, Culprit), type_error,
                            Expected, Culprit) :- !.
metta_host_operation_formal(Formal, Kind, _, _) :- functor(Formal, Kind, _).

%A wire carries atomics and lists of them; any other compound crosses as
%its written text, from swrite/2, the engine's own printer, so it reads
%back as the MeTTa the user wrote: a generic term writer would spell a
%variable _112 and a partial application partial(g,[1]), neither of which
%is MeTTa surface syntax. An unbound part stays unbound.
metta_host_operation_part(Term, Term) :- var(Term), !.
metta_host_operation_part(Term, Value) :- metta_host_operation_value(Term, Value).

metta_host_operation_value(Term, Term) :- atomic(Term), !.
metta_host_operation_value(Term, Value) :-
    is_list(Term), !,
    maplist(metta_host_operation_value, Term, Value).
metta_host_operation_value(Term, Text) :- swrite(Term, Text).

%The culprit in the message is the value the program wrote, so it reads as
%MeTTa: (State 5), not ['State',5]. The Formal term stays ISO, because
%callers and the MeTTa catch form inspect it, and the structured Python
%surface reads it too; only the rendering changes.
%
%prolog:message//1 is consulted before the formal-only
%prolog:error_message//1, and this clause matches the context PeTTa's own
%guards attach, so every other error SWI renders is untouched
%[source: SWI-Prolog 10.1 boot/messages.pl, translate_message/1]
%[tested: metta_operation_error_message].
%The context is matched in the body, not in the head: library(error) throws
%its type errors with an unbound context, which a head pattern would unify
%with and claim, renaming every unrelated type error in the process
%[tested: metta_operation_error_message:an_unrelated_type_error_is_untouched].
%petta_error_context(+Context, -Operation, +Detail) reads a context term
%WITHOUT writing to it. Matching context(Operation, Detail) in the head looks
%equivalent and is not: SWI's own errors carry context(PI, _) with the second
%argument UNBOUND, so unifying a detail atom into it succeeds and the clause
%then renders every ordinary error of that formal. This clause was hijacking
%all of them, which is where I16's "system:(is)/2: evaluable expected, found
%(/ foo 0)" came from: a library predicate's is/2 type error was being
%reported in PeTTa's operation vocabulary, naming an engine internal and a
%culprit the program never wrote [tested: metta_operation_errors,
%an_unrelated_type_error_keeps_swi_s_own_message].
petta_error_context(Context, Operation, Detail) :-
    nonvar(Context),
    Context = context(Operation, Actual),
    nonvar(Actual),
    Actual == Detail.

prolog:message(error(type_error(Expected, Culprit), Context)) -->
    { petta_error_context(Context, Operation, 'invalid MeTTa operation argument'),
      swrite(Culprit, CulpritText) },
    [ '~w: ~w expected, found ~w'-[Operation, Expected, CulpritText] ].
%The ISO formal stays existence_error(procedure, Name), so a program can catch
%it the standard way; only the wording changes, because SWI's default renders
%it as "procedure `f' does not exist", which says nothing about why a
%registration cares. What it costs is the reason worth printing: a name with
%no predicate records no arity, and incomplete_application_kind/3 then reads
%the missing arity as "not applied far enough", so the call compiles to a
%partial application instead of failing.
prolog:message(error(existence_error(procedure, Name), Context)) -->
    { petta_error_context(Context, _, 'no Prolog predicate of that name is loaded') },
    [ 'no predicate named ~w is loaded, so registering it would compile \c
       every call to it into a partial application rather than failing'-[Name] ].

%These builtins validate their own runtime inputs and provide their own error
%context. The translator may therefore bypass reflective input filtering when
%the builtin has not been overridden. Keep this list aligned with those guards.
runtime_type_guarded('+').
runtime_type_guarded('-').
runtime_type_guarded('*').
runtime_type_guarded('/').
runtime_type_guarded('%').
runtime_type_guarded('<').
%== and != carry their own guard, comparable_operands/3, which is exactly
%what their declared type (-> $a $a Bool) states, so the typed dispatch has
%nothing left to check. Classifying them here is what makes
%lib_builtin_types.metta affordable: with the file loaded, a workload calling
%== and != went from 102402 inferences to 181602, +77%, and back to 102402
%with these two lines [measured 2026-08-16]. Their own guard is cheaper than
%either, and free on two numbers: a thousand-iteration == loop is 4487.45
%inferences with and without it [measured 2026-08-19]. A user or named-space
%equation overriding either still gets the full typed dispatch, because
%runtime_guarded_builtin_call/1 requires the unmodified builtin.
%
%The declaration was (-> $a $b Bool), two independent variables, which
%constrained nothing and is why (== 1 "S") answered False. Upstream writes
%(-> $t $t Bool) [source: pinned stdlib.md via the arbiter, and measured from
%hyperon 0.2.10's own !(get-type ==) on 2026-08-19].
runtime_type_guarded('==').
runtime_type_guarded('!=').
runtime_type_guarded('>').
runtime_type_guarded('<=').
runtime_type_guarded('>=').
runtime_type_guarded(min).
runtime_type_guarded(max).
runtime_type_guarded(exp).
runtime_type_guarded('#+').
runtime_type_guarded('#-').
runtime_type_guarded('#*').
runtime_type_guarded('#div').
runtime_type_guarded('#//').
runtime_type_guarded('#mod').
runtime_type_guarded('#min').
runtime_type_guarded('#max').
runtime_type_guarded('#<').
runtime_type_guarded('#>').
runtime_type_guarded('#=').
runtime_type_guarded('#\\=').
runtime_type_guarded('#=<').
runtime_type_guarded('#>=').
runtime_type_guarded('pow-math').
runtime_type_guarded('sqrt-math').
runtime_type_guarded('abs-math').
runtime_type_guarded('log-math').
runtime_type_guarded('exp-math').
runtime_type_guarded('trunc-math').
runtime_type_guarded('ceil-math').
runtime_type_guarded('floor-math').
runtime_type_guarded('round-math').
runtime_type_guarded('sin-math').
runtime_type_guarded('cos-math').
runtime_type_guarded('tan-math').
runtime_type_guarded('asin-math').
runtime_type_guarded('acos-math').
runtime_type_guarded('atan-math').
runtime_type_guarded('isnan-math').
runtime_type_guarded('isinf-math').
runtime_type_guarded('min-atom').
runtime_type_guarded('max-atom').
runtime_type_guarded('random-int').
runtime_type_guarded('random-float').
runtime_type_guarded(and).
runtime_type_guarded(or).
runtime_type_guarded(not).
runtime_type_guarded(xor).
runtime_type_guarded(implies).

%The evaluator's catch-all: real errors take the recovery, control
%signals keep flying.
:- meta_predicate catch_recover(0, 0).
catch_recover(Goal, Recovery) :-
    catch(Goal, E, ( control_exception(E) -> throw(E) ; call(Recovery) )).

%Whether a symbol is callable from where we are: a process-wide function that
%no named equation module claims, a function this module defines, or one &self
%defines, since &self is shared. fun_scoped/1 summarizes non-user fun_in/2
%claims. A builtin or user-only function is therefore unambiguous in every
%space and avoids a current-module read in higher-order loops.
%fun_in/2 is only ever asserted by register_fun_in/2, which registers fun/1
%first, so fun_in implies fun. A name that is not a function therefore cannot
%be one here either, and one indexed lookup settles it: the old second clause
%went on to read current_metta_module/1 and two fun_in/2 facts before failing,
%for every non-function head the translator resolves
%[measured 2026-08-15: alpha-unique 4,050,778 to 3,750,772 inferences].
fun_here(F) :- fun(F),
               ( \+ fun_scoped(F) -> true
               ; current_metta_module(Module), fun_here_in(Module, F) ).

%The builtin fallback is what keeps (+ 1 2) working in &self after some other
%named space defines (= (+ $a $b) ...). fun_scoped(N) stops fun_here/1's first
%clause applying process-wide, and without this the name resolved nowhere: one
%named space turned + into inert data in every other space and in engines
%built afterwards [tested: metta_builtin_scoping].
fun_here_in(Module, F) :-
    (   fun_in(Module, F)
    ->  true
    ;   metta_restricted_exec_module(Module, _)
    ->  restricted_callable_name(F)
    ;   metta_exec_module_parent(Module, ParentModule)
    ->  fun_here_in(ParentModule, F)
    ;   metta_self_module(Self), Module \== Self, fun_in(Self, F)
    ->  true
    ;   builtin_fun(F)
    ).

%Register a function and record which module its clauses live in. fun/1 stays
%global because the translator consults it at compile time to decide whether a
%head is a call or data, and that decision has to hold wherever the term is
%compiled; fun_in/2 says where the clauses actually are, so a caller can ask
%whether *this* space defines a symbol rather than whether any space does.
:- dynamic fun_in/2, fun_scoped/1.
%A builtin is visible from every space, and stays visible when a named space
%defines its name. fun_in/2 cannot carry that: it means "an equation or a
%registered operation defines this here", which is exactly the test
%runtime_guarded_builtin_call/1 uses to decide a builtin was overridden. One
%fact for each meaning, so neither reading breaks the other.
:- dynamic builtin_fun/1.
register_builtin_fun(N) :- register_fun(N),
                           register_prolog_arities(N),
                           ( builtin_fun(N) -> true ; assertz(builtin_fun(N)) ).

register_fun_in(Module, N) :- register_fun(N),
                              ( fun_in(Module, N) -> true
                              ; assertz(fun_in(Module, N), FunInRef),
                                record_source_assertion(FunInRef) ),
                              ( metta_self_module(Module) -> true
                              ; fun_scoped(N) -> true
                              ; assertz(fun_scoped(N), ScopedRef),
                                record_source_assertion(ScopedRef) ).

unregister_fun_in(Module, N) :- retractall(fun_in(Module, N)),
                                metta_self_module(Self),
                                ( fun_in(Other, N), Other \== Self
                                  -> true
                                ; restricted_dispatch_name(N)
                                  -> true
                                ; retractall(fun_scoped(N)) ).

unregister_fun_everywhere(N) :- retractall(fun_in(_, N)),
                                retractall(fun_scoped(N)).
:- maplist(register_builtin_fun, [superpose, empty, let, 'let*', '+','-','*','/', '%', min, max, 'new-state', 'change-state!', 'get-state', 'bind!', 'register-token!', 'unregister-token!', 'declare-pre-add!', 'undeclare-pre-add!', 'declare-post-add!', 'undeclare-post-add!', 'space-atom-count', 'has-declared-type', 'space-admission-verdict', 'space-contains',
                          '<','>','==', '!=', '=', '=?', '<=', '>=', and, or, xor, implies, not, exp,
                          'first-from-pair', 'second-from-pair', 'car-atom', 'cdr-atom', 'unique-atom', 'alpha-unique-atom',
                          repr, repra, parse, 'pretty-atom', 'println!', 'readln!', 'read-form!', 'sread-command', test, 'test-no-answer', assert, atom_concat, atom_chars, copy_term, term_hash,
                          foldl, first, last, append, length, 'size-atom', sort, msort, member, 'is-member', 'is-alpha-member', 'exclude-item', list_to_set, maplist, eval, evalc, reduce, 'import!',
                          'git-import!',
                          'add-atom', 'remove-atom', 'add-atoms', 'add-reduct', 'add-reducts', 'get-atoms', match, 'is-var', 'is-ground', 'is-expr', 'is-space',
                          decons, 'decons-atom', noeval, 'new-space',
                          'get-type', 'get-type-space', 'get-metatype', '=alpha', sread, cons, reverse,
                          'get-doc', 'get-doc-space', 'get-doc-atom',
                          'get-doc-single-atom', 'get-doc-function', 'get-doc-params',
                          'help!', documented, 'documented-space',
                          'defined-name', undocumented, 'undocumented-space',
                          '#+','#-','#*','#div','#//','#mod','#min','#max','#<','#>','#=','#\\=','#=<','#>=',
                          'union-atom', 'cons-atom', 'intersection-atom', 'subtraction-atom', 'index-atom', id,
                          'pow-math', 'sqrt-math', 'sort-atom','abs-math', 'log-math', 'exp-math', 'trunc-math', 'ceil-math',
                          'floor-math', 'round-math', 'sin-math', 'cos-math', 'tan-math', 'asin-math','random-int','random-float',
                          'acos-math', 'atan-math', 'isnan-math', 'isinf-math', 'min-atom', 'max-atom',
                          'foldl-atom', 'map-atom', 'filter-atom','current-time','format-time', 'context-space', library, exists_file,
                          'format-args', 'sort-strings', include,
                          sleep, 'pragma!', metta,
                          import_prolog_function, check_prolog_function_names, import_prolog_functions,
                          'Predicate', callPredicate, assertaPredicate, assertzPredicate, retractPredicate,
                          'add-translator-rule!', 'remove-translator-rule!',
                          'add-typing-rule!', 'remove-typing-rule!', argv,
                          register_metta_library_path,
                          dif, 'residual-goals']).
%A HOST's builtins register the same way, from the host bridge's own
%seam:host_builtin/1 declarations rather than from a list here that would
%name the host: the bridge loads earlier in this file's own load order, so
%its facts exist by the time this directive runs, and an engine with no
%host loaded registers nothing.
:- forall(seam:host_builtin(Name), register_builtin_fun(Name)).

%A backend's own builtins, registered here because this is where the engine's
%are and the order matters. The NAMES are the backend's: it declares them in
%the file that defines them, so they exist exactly when the predicates behind
%them do. That conditionality used to be an argv test in this file, which meant
%the engine had to know both that MORK had builtins and what they were called.
%
%Registering a name whose predicate is absent records no arity, and
%incomplete_application_kind/3 reads "no arity" as "not applied far enough":
%every call to it then compiled to a partial application, so (mm2-exec &mork 1)
%answered (partial mm2-exec (&mork 1)) instead of running or failing. Declaring
%the names beside the predicates is what makes that unable to happen again.
:- forall(seam:backend_builtin(Name), register_builtin_fun(Name)).


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
