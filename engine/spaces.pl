% Purpose: store MeTTa atoms, compile equations into per-space modules,
%   route matching to native and foreign space providers, and validate
%   '&petta' declarations against the self-describing catalog.
% Assumes:
%   - the removal funnel takes a space NAME rather than a handle, so
%     metta_remove_atom/3, unstore_atom/3 and remove_equation/6 each take a
%     space name first (an atom or a registered ground expression);
%     remove_equation/6 is reached only for a stored equation, so its function
%     symbol is an atom; and all three answer whether anything went in a
%     `true` or `false` last argument [measured 2026-08-19 by
%     wrapping the three and reading every call the 19 shipped MeTTa files
%     that remove an atom make]. Each of those is a PlDoc mode line above its
%     clause, so the development build checks it at run time rather than
%     leaving it prose [tested:
%     the_dev_build_inserts_checks_and_types_a_planted_violation]; the
%     dev-typed gate lane also runs every plunit suite under that build.
% Guarantees:
%   - Files below engine/spaces/ are plain source units consulted into this
%     implementation module in their original order; storage predicates,
%     provider seams, and lifecycle state retain their existing ownership
%     [tested: tests/prolog/spaces.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d].
%   - Every native space stores its atoms in a private data module that does
%     not inherit user predicates [tested: spaces_storage_modules].
%   - subscribe follows the (events ...) declaration rather than what a host
%     registered, and a standing query or a reaction on a context that
%     declares none is refused at the catalog door naming the missing
%     capability [tested: spaces_event_capability; commit=c05f93baf8c6ecd483487efb72d7f8eb92c97809].
%   - the type-marker probe asks a space with a writable pattern, so a
%     provider that writes the pattern to send it is never handed a partial
%     list [tested: spaces_seam_patterns; commit=c05f93baf8c6ecd483487efb72d7f8eb92c97809].
%   - the reaction agenda is a declared policy with declaration order as its
%     stated default, and two conflicting reactions fire in the order each
%     declared policy names [tested: spaces_reaction_agenda; commit=c05f93baf8c6ecd483487efb72d7f8eb92c97809].
%   - stored_atom_of_ref/3 is add_sexp_in/4's inverse over both stored shapes,
%     and answers for a stored atom's clause reference alone: not for a
%     compiled clause's, not for a registration's, not for an erased one
%     [tested 2026-08-19:
%     spaces_storage_modules:a_stored_atoms_reference_decodes_to_its_atom,
%     spaces_storage_modules:an_erased_reference_decodes_to_nothing].
%   - An equation for a name this space's module already DERIVED as a
%     specialization is not stored again, so enumerating a space and re-adding
%     its atoms answers a space that holds and answers what the first one did
%     [tested: test_a_copy_reproduces_the_space_it_copied].
%   - A native pool with a capacity admission claim keeps one rollback-safe
%     dynamic atom count across direct adds, batches, removals, clears and
%     capacity redeclaration; a pool without that claim keeps no counter
%     [tested: the_capacity_counter_tracks_direct_adds_batches_removals_and_clears,
%     capacity_counter_changes_roll_back_with_the_atoms,
%     capacity_redeclaration_recounts_writes_made_while_unbounded;
%     commit=819b139c7cdbdaa673f854713e8beb988eb12ead].
%   - Five 2,000-row native joins take 270305 direct and 270307 prepared
%     inferences [measured: 270305 and 270307 inferences on 2026-08-15].
%   - Native spaces preserve scalar atoms and expressions as distinct values
%     [tested 2026-08-14: spaces_arbitrary_atoms].
%   - A '&petta' declaration violating its declared (kind ...) row is a hard
%     error at both write doors, naming the atom, the argument position and
%     the argspec; a head with no kind row passes untouched
%     [tested 2026-08-20: catalog_self_description].
%   - The numeric-type vocabulary publishes Number and BigInt in boundary
%     order for generated binding types [tested 2026-08-20:
%     test_numeric_types_are_published_from_the_catalog].
%   - Six dispatch axes publish one documented default and accept at most one
%     validated per-function override for each axis
%     [tested: test_every_dispatch_axis_is_readable_settable_and_defaulted; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - Cache policy is declared in the catalog with one force/refuse override
%     per function; writes, removals and explicit tabling declarations notify
%     the automatic decision owner, so an explicit SWI table takes precedence
%     [tested: test_automatic_cache_force_and_refuse_overrides,
%     test_explicit_tabling_takes_precedence_over_automatic_memoization;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
%   - Effective dispatch values are cached by function and axis, validated
%     against their catalog clause reference, and forgotten at every policy
%     mutation [tested: test_every_dispatch_axis_is_readable_settable_and_defaulted,
%     examples/performance/holbenchmark.metta; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - The policy catalog publishes exactly one knob and shipped default for
%     each of the twenty engine decision axes, and the policy-inventory
%     gate rejects a closed list that has neither a catalog row nor a strict
%     adjacent exemption [tested:
%     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
%     commit=42b5d28232e75c32b20a1d5bf1f740fec134938d].
%   - A selective native match is one indexed probe rather than a scan, and
%     the acyclic guard does not change that because it runs on the answer
%     [tested 2026-08-18:
%     a_selective_match_costs_the_same_on_a_hundredfold_larger_space]
%     [measured 2026-08-18: 6,502 inferences per 500 matches on spaces of
%     100, 1,000 and 10,000 atoms].
%   - A gap pattern decides its certified-finite fragment once, at its call
%     site or at the ask, and refuses outside the three Kutsia proved; a
%     pattern with no gap reaches no predicate of the gap unit at all
%     [tested: tests/prolog/segments.plt; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb].
%   - Removing one scoped get-type rule keeps sibling extension rules visible
%     [tested 2026-08-15: spaces_type_extensions].
%   - A second variant-identical type declaration is refused before storage,
%     including when both copies arrive in one public batch, and the diagnostic
%     names the first declaration without publishing either batched copy
%     [tested: test_a_duplicate_declaration_names_the_first_one; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - Clearing a native space clears its import life without making wildcard
%     atom removal touch that life [tested 2026-08-15:
%     filereader_import_lifecycle].
%   - Removing a space-local shadow installs one targeted weak import for the
%     inherited definition, so already-compiled callers and fresh lookups
%     agree after the removal and after a pooled module is rebased [tested:
%     filereader_import_lifecycle:
%     removing_a_local_shadow_rearms_an_already_compiled_inherited_call;
%     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
%   - Dynamic function registration is atomic and failed source loads remove
%     its asserted compiler state [tested 2026-08-14:
%     change_hook_error_rolls_back_every_registration_write,
%     filereader_source_rollback].
%   - Function changes invalidate module-qualified support nodes before
%     rebuilding compiled dependents, so all mutation doors share one forward
%     propagation mechanism [tested:
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - Dispatch override/default edits and DontEvalType marker edits invalidate
%     their typed support roots after storage changes, including callers that
%     compiled before the edit [tested:
%     test_every_dispatch_axis_is_readable_settable_and_defaulted,
%     test_a_user_declared_lazy_type_receives_its_argument_unevaluated;
%     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - match_foreign/5 passes options only to a provider that declared
%     seam:foreign_match/3, and unification and the caller's own bound stay
%     on this side, so an option cannot change an answer [tested 2026-08-16:
%     test_a_provider_ignoring_the_bound_is_still_bounded_by_the_engine].
%   - (top k ...) answers the k best by declared-semiring annotation,
%     stable on ties, refuses unordered contexts, and hands the provider
%     the bound only under Exact route + ordered annotations + best-first
%     merge [tested 2026-08-17: answers_annotations].
%   - A declared (handles ...) entry outranks seam:foreign_pushdown/3
%     shape by shape, a routed Refuse throws on any match of its shape
%     with a join checked conjunct by conjunct at plan time, and an
%     undeclared context pays one indexed probe per query
%     [tested 2026-08-17: spaces_handles_guard] [measured 2026-08-17:
%     pure-Prolog foreign match 34 to 41 inferences, bounded take 41 to
%     55].
%   - a restricted execution module bases on a curated grant profile and a
%     denied operation names the space, operation, and missing capability
%     [tested:
%     test_a_restricted_space_cannot_reach_what_its_base_does_not_publish;
%     commit=6a08901f4125c2536f5b4032daac9937f793870f].
%   - a ground expression may name a native space; canonical module names and
%     a fixed per-module storage functor keep distinct instances isolated, and
%     context-space returns the exact expression to their equations [tested:
%     test_two_instances_of_a_parametric_space_answer_independently;
%     commit=3c7bcde6a0670ec5c563584b26977b41cc727580].
% Guarded by: '$petta_native_storage' serializes private module creation and
%   publication in native_storage_module_cache/2; '$petta_capacity_count'
%   serializes installation and replacement of each incremental count.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The space subsystem's surface: the MeTTa builtins that read and write a
%space, the storage doors an engine subsystem or a shipped library uses, the
%execution-module machinery every compiled clause depends on, and the runtime
%helpers the compiler writes into those clauses. Everything else -- the
%hook-claim algebra, the capacity counters' own bookkeeping, the catalog
%presets, the restriction profiles, the parametric-name codec -- is this
%subsystem's own, and a caller that wants one says spaces: and means it
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
%
%A MeTTa program can still shadow every builtin on this list. An export is
%imported into the ENGINE's module, and a space's execution module inherits
%that module, so an equation compiled into the space defines the name locally
%and the local definition wins, which is exactly what the import was before
%this file had a module of its own
%[tested: spaces_builtin_override, test_a_system_predicate_survives_an_equation_for_its_name].
:- module(spaces,
          [
            'add-atom'/3,
            'add-atoms'/3,
            'add-reduct'/3,
            'add-reducts'/3,
            add_sexp/2,
            add_sexp/3,
            announce_function_changed/2,
            announce_declaration_changed/3,
            result_finality/2,
            announce_function_removed/1,
            assert_function_clause/3,
            clear_foreign_atoms/1,
            clear_native_atoms/1,
            compile_metta_equation/4,
            defer_metta_equation/3,
            metta_add_program_atoms/2,
            metta_add_program_atoms/3,
            store_data_atoms/2,
            metta_ensure_compiled/1,
            ensure_native_storage_module/2,
            foreign_provides/2,
            foreign_pushdown_class/3,
            function_still_defined/1,
            'get-atoms'/2,
            get_native_atom/2,
            match/4,
            match_foreign/4,
            match_foreign/5,
            match_stored/4,
            metta_add_atom/3,
            metta_add_atoms/2,
            metta_add_hooks_idle/1,
            metta_assert_space_releasable/1,
            metta_declare_parametric_space/1,
            metta_declare_restricted_space/2,
            metta_declare_space_parent/2,
            metta_exec_module_known/2,
            metta_forget_space_parent/1,
            metta_host_clear_defined/1,
            metta_host_clear_space/1,
            metta_host_explain_match/3,
            metta_host_native_fact/4,
            metta_host_remove_reported/3,
            metta_host_stored/2,
            metta_module_space/2,
            metta_release_space/1,
            metta_remove_atom/3,
            metta_remove_hooks_idle/1,
            metta_require_current_capability/2,
            metta_require_safe_goal/1,
            metta_require_space_update_capability/2,
            metta_restricted_exec_module/2,
            metta_space_names/1,
            native_atom_clause/3,
            native_storage_functor/2,
            native_storage_module/2,
            native_storage_module_cache/2,
            native_storage_module_ready/2,
            petta_answer_terms/3,
            petta_capacity_count/2,
            petta_capacity_count_added/2,
            petta_capacity_count_added_known/2,
            petta_capacity_count_claim/1,
            petta_capacity_count_install/1,
            petta_capacity_count_uninstall/1,
            petta_catalog_row/1,
            petta_dispatch_value/3,
            petta_instrument_recursive_clause/3,
            petta_match_atoms/2,
            petta_prune_empty/2,
            petta_prune_empty_answers/2,
            petta_reader_variable_name/3,
            petta_repair_emptied_shadows/0,
            petta_run_named/3,
            %The gap-pattern surface. The translator asks petta_seq_present/1
            %while a call site compiles and petta_seq_plan/3 to parse and
            %classify it there; the host query door asks petta_seq_plan/3 at
            %the ask instead, because its pattern was built rather than
            %written. Both then hand match/4 and petta_match_atoms/2 the
            %wrapped pattern those two dispatch on, so a gap adds no goal name
            %the engine has to protect and no cost to a gap-free call.
            petta_seq_body_plan/2,
            petta_seq_plan/3,
            petta_seq_head_match/2,
            petta_seq_head_matches/2,
            petta_seq_head_plan/2,
            petta_seq_instantiate/2,
            petta_seq_present/1,
            petta_seq_query_plan/2,
            petta_seq_unify/3,
            petta_space_name/1,
            petta_space_operand/1,
            petta_vocabulary_value/2,
            protect_engine_emitted/1,
            protect_metta_exec_modules/0,
            %Shared tables engine/metta.pl reads and writes: the execution
            %module parent chain and four caches the contract vocabulary keeps.
            metta_exec_module_parent/2,
            petta_algebra_descriptor_cache/8,
            petta_annotations_cache/2,
            petta_ctx_declared/1,
            petta_events_declared/1,
            %Emitted into compiled bodies: a bounded match and a bounded take
            %are goals the compiler writes, and neither was declared in
            %seam:engine_emitted/1 either.
            match_bounded/5,
            metta_take/2,
            metta_take_match/5,
            %Three more the compiler writes, found by reading what
            %engine/translator.pl CONSTRUCTS rather than what it calls. The
            %corpus-recompile half of the same check could not see them,
            %because no shipped equation uses (top k ...) or a literal
            %(match (superpose (&a &b)) ...) [measured 2026-08-22: (top ...)
            %appears in examples/ once, inside a comment].
            metta_top/3,
            metta_top_match/5,
            petta_merged_match/3,
            %The two removal funnels tests/prolog/ciao_grade.pl carries an
            %EXTERNAL Ciao-style assertion for. A predicate with a written
            %contract outside its own file is surface by that fact, and the
            %assertions library records a :- pred against the module the
            %declaration is made in, so a side file can only carry one for a
            %predicate it can see.
            unstore_atom/3,
            remove_equation/6,
            'remove-atom'/3,
            remove_sexp/2,
            restricted_callable_name/1,
            restricted_dispatch_name/1,
            space_argument_error/3,
            space_atom_count/2,
            space_canonical_atom/2,
            space_module/2,
            space_operation_capability/2,
            space_parametric/1,
            space_parent/2,
            space_restricted/2,
            stored_atom_of_ref/3
          ]).

%This subsystem WRITES core registries -- engine/metta.pl owns fun/1,
%arity/2 and the two shape tables -- and a base module makes a name
%visible without making a write land on it, so they are imported rather
%than inherited. See petta_shared_registry/1 in engine/metta.pl.
:- petta_import_shared_registries(spaces).

:- use_module(library(sandbox), [safe_goal/1]).
:- use_module(library(assoc), [list_to_assoc/2, get_assoc/3, put_assoc/4]).

% Storage modules are separate from execution modules. They inherit nothing,
% so a user predicate cannot appear as a space atom, and unknown arities fail
% without a catch on the indexed read path. Atomic names retain their existing
% module and predicate names. A parametric name uses its canonical term text
% as the module suffix and one reserved functor inside that private module;
% the module already supplies the namespace, so no compound ever occupies a
% Prolog functor position.
native_storage_module(Space, Module) :-
    var(Space),
    !,
    nonvar(Module),
    native_storage_module_cache(Space, Module).
native_storage_module(Space, Module) :-
    atom(Space), !,
    atom_concat('$petta_atoms:', Space, Module).
native_storage_module(Space, Module) :-
    space_parametric(Space),
    !,
    space_canonical_atom(Space, Encoded),
    atom_concat('$petta_param_atoms:', Encoded, Module).

native_storage_functor(Space, Functor) :- atom(Space), !, Functor = Space.
native_storage_functor(Space, '$petta_parametric_atom') :-
    space_parametric(Space),
    !.

space_canonical_atom(Space, Encoded) :-
    with_output_to(atom(Encoded), write_canonical(Space)).

:- consult('spaces/catalog.pl').
:- consult('spaces/lifecycle.pl').
:- consult('spaces/foreign.pl').
:- consult('spaces/bounded_matching.pl').
:- consult('spaces/native_matching.pl').
:- consult('spaces/segment_matching.pl').
