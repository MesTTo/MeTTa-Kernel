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
%     [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE].
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
%   - Removing one scoped get-type rule keeps sibling extension rules visible
%     [tested 2026-08-15: spaces_type_extensions].
%   - A second variant-identical type declaration is refused before storage,
%     including when both copies arrive in one public batch, and the diagnostic
%     names the first declaration without publishing either batched copy
%     [tested: test_a_duplicate_declaration_names_the_first_one; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - Clearing a native space clears its import life without making wildcard
%     atom removal touch that life [tested 2026-08-15:
%     filereader_import_lifecycle].
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
            announce_function_removed/1,
            assert_function_clause/3,
            clear_foreign_atoms/1,
            clear_native_atoms/1,
            compile_metta_equation/4,
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
%%%% the bound the caller wrote, reaching the matcher %%%%
%
%(once (match &s (, ...) ...)) and (take N (match &s (, ...) ...)) know a
%bound match/4 does not, and the conjunctive door is the one place knowing it
%saves work: the snapshot above finds EVERY row before the first one leaves,
%so an unbounded conjunction walks the whole join to answer one row. Taking
%one row of a two-conjunct self-join cost 1,328 inferences over 10 edges and
%6,398 over 400; with the bound reaching here it is 1,222 over both, so the
%cost stopped tracking the join at all [measured 2026-08-21].
%
%The win is ASYMPTOTIC and OUTPUT-SENSITIVE rather than a constant factor. The
%unbounded collection is O(rows in the join) in time AND in the space the
%collected list holds, whatever the caller reads; bounded it is O(bound) in
%both, so first-answer latency stops growing with the data. The decision is
%amortized to COMPILE time, one unification per translated form and nothing per
%call, which is why every unbounded lane measures unchanged. Nothing here is
%shared between calls, so a bound adds no contention: limit/2's counter is a
%term local to the goal, and the collection is per call as it was.
%
%SOUND because of the shape the translator requires before it emits this: the
%bounded expression compiles to exactly one match goal, so nothing runs
%between a row and the answer it becomes, N rows are N answers, and a producer
%stopped at N cannot under-answer. A goal after the match could fail and make
%the (N+1)th row the answer, which is why the only thing that emits this is
%engine/translator.pl's `Conj = match(Space, Pattern, Template, Result)` shape
%test, written inline at translate_special_dl/5's once, take and top clauses
%[tested: test_a_bounded_conjunctive_match_stops_at_the_bound].
%
%Only the CONJUNCTIVE door takes the bound. A single pattern already streams
%under the logical update view and has nothing to stop, and a name that is not
%a space has no rows to bound and reaches match/4's own refusal through the
%second branch, so this predicate adds a door rather than a second matcher
%[tested: test_a_bounded_match_on_an_unbound_space_answers_the_error].
match_bounded(Bound, Space, Pattern, OutPattern, Result) :-
    (   bounded_conjunction(Bound, Space, Pattern)
    ->  conjunctive_match(limit(Bound,
                                match_conjunction(Space, Pattern, OutPattern)),
                          Space, Pattern, OutPattern, Result)
    ;   match(Space, Pattern, OutPattern, Result)
    ).

%A bound is usable when it is a whole number of rows, the pattern is a
%conjunction, and the space is one the engine holds. The last conjunct is what
%keeps the refusal in one place: a name that is not a space fails here and
%match/4 answers the Error atom it has always answered.
bounded_conjunction(Bound, Space, Pattern) :-
    integer(Bound),
    Bound >= 1,
    nonvar(Pattern),
    Pattern = [Comma|_],
    Comma == ',',
    petta_space_name(Space).

%THE ENGINE'S OWN READ of a space, the counterpart of get_native_atom/2 behind
%'get-atoms'/2 and there for the same reason: its callers hold a space name the
%ENGINE gave them rather than one a program wrote, so there is nothing to
%refuse and an error atom would be read back as a stored atom. The type lookups
%are why it has to exist rather than being a tidy split: a declaration lookup
%runs on every typed call, and routing those through the door made each one pay
%the door's refusal decision whenever the space had no atoms yet
%[measured 2026-08-20: py-method-call 2,250,095 inferences against 2,220,093,
%three per call over 10,000 evaluations in a space nothing had written to].
match_stored(Space, Pattern, OutPattern, Result) :-
    nonvar(Space), seam:foreign_space(Space), !,
    match_foreign(Space, Pattern, OutPattern, Result).
match_stored([Family|Parameters], Pattern, OutPattern, Result) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    native_storage_module_cache(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).
match_stored(Space, Pattern, OutPattern, Result) :-
    atom(Space),
    native_storage_module_cache(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).

%Choose the provider once for the whole conjunction. It may enumerate millions
%of native candidates, so deciding per candidate would repeat the foreign-space
%probe every time. A native space is a Prolog predicate named after the space
%and stays on the direct helper; anything else routes each conjunct back
%through match/4, which is how a space implemented by its own clause sees it.
match_conjunction(Space, Pattern, OutPattern) :- seam:foreign_space(Space), !,
                                                 match_foreign(Space, Pattern, OutPattern, _).
match_conjunction(Space, Pattern, OutPattern) :- native_storage_module_cache(Space, Module), !,
                                                 (   space_parent(Space, _)
                                                 ->  match_routed(Space, Pattern,
                                                                  OutPattern, _)
                                                 ;   match_native(Module, Space,
                                                                  Pattern,
                                                                  OutPattern, _)
                                                 ).
match_conjunction(Space, Pattern, OutPattern) :- match_routed(Space, Pattern, OutPattern, _).

match_inherited_space(Space, OwnModule, Pattern, OutPattern, Result) :-
    space_read_chain(Space, Each),
    (   Each == Space
    ->  match_native(OwnModule, Space, Pattern, OutPattern, Result)
    ;   match_read_link(Each, Pattern, OutPattern, Result)
    ).

match_read_link(Space, Pattern, OutPattern, Result) :-
    seam:foreign_space(Space),
    !,
    match_foreign(Space, Pattern, OutPattern, Result).
match_read_link(Space, Pattern, OutPattern, Result) :-
    native_storage_module_ready(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).

match_routed(_, LComma, OutPattern, Result) :- LComma == [','], !,
                                               Result = OutPattern.
%The same reordering as match_native/5's, for a space whose reads go through a
%parent chain. The conjuncts here are matched by match/4 rather than read from
%one storage module, so the probe asks match/4 the same cheap question: has
%this conjunct at most one match under the bindings so far. An inherited space
%joins across the chain, `(new-space &child (inherits &parent))` in
%examples/spaces/inherited_spaces.metta, and pays the same quadratic under skew
%without it. A read through the chain is a child-first multiset union and each
%conjunct routes through it independently, so which conjunct is taken first
%changes neither the rows nor how many times each appears.
%
%match_foreign_routed/6's own split is deliberately NOT reordered. That one
%combines each conjunct's annotation along the join with the algebra's declared
%extend, and `extend-commutative` is optional: the shipped prob and prov
%algebras do not declare it, so the order conjuncts are visited in is part of
%the answer there [source: website/guide/contract.md:73-80]. A foreign
%provider's own join is reachable through foreign_plan/5, which is offered the
%whole conjunction before any split happens.
match_routed(Space, [Comma|Conjuncts], OutPattern, Result) :-
    Comma == ',',
    Conjuncts = [_, _|_],
    routed_cheapest_conjunct(Space, Conjuncts, Head, Rest),
    !,
    match(Space, Head, conj, conj),
    match_routed(Space, [','|Rest], OutPattern, Result).
match_routed(Space, [','|[Head|Tail]], OutPattern, Result) :-
    match(Space, Head, conj, conj),
    match_routed(Space, [','|Tail], OutPattern, Result).

routed_cheapest_conjunct(Space, [First|More], Best, Rest) :-
    (   goal_matches_at_most_one(match(Space, First, conj, conj))
    ->  Best = First,
        Rest = More
    ;   routed_selective_conjunct(Space, More, Found, Others)
    ->  Best = Found,
        Rest = [First|Others]
    ;   Best = First,
        Rest = More
    ).

routed_selective_conjunct(Space, Conjuncts, Best, Rest) :-
    select(Best, Conjuncts, Rest),
    goal_matches_at_most_one(match(Space, Best, conj, conj)),
    !.

%One matching step of Hyperon's unify: each solution is one binding set,
%bindings applied by Prolog unification itself. The clause order is the
%case order of the arbiter's matcher, LeaTTa
%MettaHyperonFull/Core/Matching.lean matchAtomsWith (209-241): variables
%bind before anything is consulted, with the occurs check the arbiter's
%variable cases carry; expressions match pointwise, consistency kept by
%the shared bindings; then a grounded operand's own matching logic runs,
%left before right, which is how a space becomes queryable inside unify
%(Hyperon: `impl CustomMatch for DynSpace` is query, hyperon-space
%engine/lib.rs); a host value with declared matching runs its hook the same
%way; numbers compare promoted, so 1 matches 1.0 [source: LeaTTa
%tests/semantics/matching/grounded_value_matching.metta, measured
%2026-08-11]; everything else is ground equality. A space is named by a
%symbol here rather than a grounded atom, so the operand test is the
%registered-space probe, and an unregistered name falls through to
%equality like any symbol. The leading identity clause is the arbiter's
%diagonal collapsed to one C comparison: two identical operands match
%with the empty binding set case for case (equal grounds trivially; a
%shared variable is the same-variable case; identical compounds decide
%pointwise to the same), and it spares the per-leaf probe cascade on the
%equal-operand traffic that dominates eval-branch tests
%[measured 2026-08-17: test_unify_eval_branches].
petta_match_atoms(L, R) :- L == R, !.
petta_match_atoms(L, R) :- ( var(L) ; var(R) ), !,
                           unify_with_occurs_check(L, R).
%A cons cell and () never match, and deciding that must not WALK the cons.
%Every route below reaches the same failure: read as lists they differ at the
%very first cell, and the clauses past the list branch all decide by equality,
%which a cons and () fail too. `(unify $l () ...)` is how a list is walked to
%its end, so is_list/1 walking the whole remaining list at every step made the
%walk quadratic [measured 2026-08-23: 114 microseconds over 200 elements and
%7,550 over 3,200, 10.1x per 4x, and one probe of a 6,400-element list against
%() cost 9.16 microseconds against 0.5 now].
%
%Confirmed rather than argued: over 26 cases spanning proper, improper,
%partial, error-shaped and mixed-type cons cells in both operand positions,
%every one already failed.
petta_match_atoms(L, R) :- L == [], nonvar(R), R = [_|_], !, fail.
petta_match_atoms(L, R) :- R == [], nonvar(L), L = [_|_], !, fail.
petta_match_atoms(L, R) :- is_list(L), is_list(R), !,
                           petta_match_all(L, R).
petta_match_atoms(L, R) :- petta_space_operand(L), !, match(L, R, [], _).
petta_match_atoms(L, R) :- petta_space_operand(R), !, match(R, L, [], _).
petta_match_atoms(L, R) :- seam:matchable_value(L), !,
                           seam:custom_match(L, R).
petta_match_atoms(L, R) :- seam:matchable_value(R), !,
                           seam:custom_match(R, L).
petta_match_atoms(L, R) :- number(L), number(R), !, L =:= R.
petta_match_atoms(L, R) :- L == R.

petta_match_all([], []).
petta_match_all([X|Xs], [Y|Ys]) :-
    petta_match_atoms(X, Y),
    petta_match_all(Xs, Ys).

%Whether an operand names a space this engine can query: a foreign
%provider or a native storage module. Both probes are indexed lookups.
petta_space_operand(S) :-
    atom(S),
    !,
    (   seam:foreign_space(S)
    ->  true
    ;   native_storage_module_cache(S, _)
    ).
petta_space_operand(S) :-
    nonvar(S),
    space_parametric(S).


%Every space name this engine registers: '&self' and '&petta' from load time,
%every atomic or parametric native space that new-space made or that has been
%written to, and every foreign provider currently bound. Naming a space never
%registers it, only creating it, writing to it or binding one does, so this is
%the same set petta_space_operand/1 accepts. sort/2 makes the answer stable and
%duplicate-free.
metta_space_names(Names) :-
    findall(S, native_storage_module_cache(S, _), Native),
    findall(S, seam:foreign_space(S), Foreign),
    append(Native, Foreign, All),
    sort(All, Names).

%The Empty prune behind every computed collapse. The gate is memberchk
%NEGATED, which makes it sound AND C-fast: when nothing in the list
%unifies with Empty (the overwhelmingly common all-ground case,
%4 inferences however long the list), the list is shared untouched; when
%something unified, the negation has already undone the binding, and the
%identity (==) walk decides whether it was a real Empty or an unbound
%answer variable. Bare memberchk once BOUND such a variable and pruned
%it, which turned `!(let $b (is-alpha-member (1 $x) ...) $x)`'s unbound
%answer into nothing
%[tested translated_success_leaves_the_query_variable_unbound].
petta_prune_empty(All, Kept) :-
    (   \+ memberchk('Empty', All)
    ->  Kept = All
    ;   petta_member_empty_(All)
    ->  petta_drop_empty_(All, Kept)
    ;   Kept = All
    ).

petta_member_empty_([X|Xs]) :-
    (   X == 'Empty'
    ->  true
    ;   petta_member_empty_(Xs)
    ).

petta_drop_empty_([], []).
petta_drop_empty_([X|Xs], Kept) :-
    (   X == 'Empty'
    ->  petta_drop_empty_(Xs, Kept)
    ;   Kept = [X|Kept1],
        petta_drop_empty_(Xs, Kept1)
    ).

%The runnable collector carries each answer beside its reader names. Prune on
%the answer slot while retaining the side map for every surviving answer.
%This mirrors petta_prune_empty/2's identity test, so a free answer variable
%is not mistaken for Empty [tested: test_variable_names_survive_to_the_printer;
%commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
petta_prune_empty_answers(All, Kept) :-
    (   \+ memberchk('$petta_answer'('Empty', _), All)
    ->  Kept = All
    ;   petta_member_empty_answer_(All)
    ->  petta_drop_empty_answers_(All, Kept)
    ;   Kept = All
    ).

petta_member_empty_answer_(['$petta_answer'(X, _)|Xs]) :-
    (   X == 'Empty'
    ->  true
    ;   petta_member_empty_answer_(Xs)
    ).

petta_drop_empty_answers_([], []).
petta_drop_empty_answers_(['$petta_answer'(X, Names)|Xs], Kept) :-
    (   X == 'Empty'
    ->  petta_drop_empty_answers_(Xs, Kept)
    ;   Kept = ['$petta_answer'(X, Names)|Kept1],
        petta_drop_empty_answers_(Xs, Kept1)
    ).

%Unwrap a nested collapse for evaluation while retaining each copied name
%state in the enclosing runnable's side map. Term and state came out of one
%findall template, so their variables still share identity here.
petta_answer_terms([], [], []).
petta_answer_terms(['$petta_answer'(Term, Names)|Answers],
                   [Term|Terms], [Names|NameStates]) :-
    petta_answer_terms(Answers, Terms, NameStates).


%A foreign provider enumerates candidates. Unification against the pattern
%stays here, so an approximate provider cannot change matching soundness.
%Which way this space answers, decided ONCE for the whole match. It depends
%only on Space, so asking per conjunct is invariant work inside a loop:
%measured at 8.00 inferences of the seam's 9.00 fixed overhead, paid once per
%OUTER ROW in a join because the inner conjunct is re-dispatched on every
%backtrack. Hoisting it took a 200-row join from 1.89x a direct match/4 clause
%to 1.10x, saving 8.01 per row.
%
%match_native/5 one clause up already does this and says why: "The recursive
%helper keeps the provider decision outside the candidate loop."
foreign_route(Space, Route) :-
    (   foreign_provides(Space, match)
    ->  Route = match
    ;   refuse_absent_capability(Space, enumerate),
        Route = enumerate
    ).

%Whether a provider takes this conjunction, decided ONCE and committed to. A
%provider that could yield a row and then decline would leave the engine unable
%to tell "no rows" from "not mine", which is the ambiguity seam:foreign_match/3
%was fixed for; once/1 here and the cut at the call site are what prevent it.
foreign_claims_plan(Space, Conjuncts, Rest, Goal) :-
    foreign_provides(Space, plan),
    once(seam:foreign_plan(Space, Conjuncts, Claimed, Rest, Goal)),
    Claimed \== [],
    refuse_lossy_plan(Space, Conjuncts, Claimed, Rest).

%Claimed and Rest have to PARTITION the conjunction. Both sides hold the
%CALLER'S OWN pattern terms (the Python seam resolves its answer back to
%them by wire identity), so this compares like with like and is a real
%check; it used to double as the mechanism that reconnected freshly
%decoded copies to the caller, which worked only while both lists
%happened to sort into the same order. A provider that drops a
%conjunct answers more rows than the query asks for, and nothing downstream
%would catch it: the engine plans Rest and never looks at the original patterns
%again, so the dropped conjunct is simply not part of the query any more. Once
%per join and never per row.
refuse_lossy_plan(Space, Patterns, Claimed, Rest) :-
    append(Claimed, Rest, Both),
    msort(Both, Sorted),
    (   msort(Patterns, Sorted)
    ->  true
    ;   throw(error(petta_foreign_plan_is_not_a_partition(Space, Patterns,
                                                          Claimed, Rest),
                    context(match/4,
                            'a claim must partition the conjunction')))
    ).

%A declared Refuse fires on ANY match of its shape, bounded or not: the
%author said this context cannot answer it, and a silent partial answer is
%the failure the declaration exists to prevent. One route consultation per
%query, never per answer. Handles entries describe MATCH shapes, so a
%conjunction is decomposed and each conjunct asked on its own; offering the
%raw [','|_] term instead let an ($f ...) entry capture the comma itself.
petta_refuse_guard(Space, _) :-
    \+ petta_ctx_declared(Space),
    !.
petta_refuse_guard(Space, Pattern) :-
    (   nonvar(Pattern), Pattern = [Comma|Conjuncts], Comma == ','
    ->  \+ \+ petta_refuse_guard_conjuncts(Conjuncts, Space)
    ;   %The route is computed with fidelity UNBOUND and tested after, so
        %the coherence check inside it runs on every consultation; asking
        %for 'Refuse' directly would fail out before two disagreeing
        %entries are compared, and the conflict would surface only under a
        %bound instead of on every match.
        petta_handles_route(Space, Pattern, Entry, Fidelity, _),
        Fidelity == 'Refuse'
    ->  throw(error(petta_refused_shape(Space, Pattern, Entry), none))
    ;   true
    ).

%Left-to-right, the way the nested loop executes: a conjunct's variables are
%bound by the time later conjuncts run, so each is checked with the earlier
%ones' variables marked bound. This is adornment-level analysis, Mercury's
%modes and the database bindability check: an (in $x) refusal fires here at
%plan time, while a refusal keyed to a literal VALUE can only fire on a
%direct query where the value is visible. The double negation above undoes
%the marker bindings; a throw passes through it.
petta_refuse_guard_conjuncts([], _).
petta_refuse_guard_conjuncts([Conjunct|Rest], Space) :-
    petta_refuse_guard(Space, Conjunct),
    term_variables(Conjunct, Vars),
    maplist(=('$petta_bound'), Vars),
    petta_refuse_guard_conjuncts(Rest, Space).

match_foreign(Space, Pattern, OutPattern, Result) :-
    petta_refuse_guard(Space, Pattern),
    petta_negation_world_guard(Space),
    foreign_route(Space, Route),
    match_foreign_routed(Space, Route, Pattern, [], OutPattern, Result).

match_foreign_routed(_, _, LComma, _, OutPattern, Result) :- LComma == [','], !,
                                                             Result = OutPattern.
%The conjunction is offered to the provider WHOLE before it is split, which is
%the only way a backend's own join is reachable: the split below is a
%nested-loop plan, and a provider that never sees more than one pattern at a
%time cannot do better than one however fast it is.
%
%Two or more conjuncts, because a single one is the ordinary match path and
%offering it here would only duplicate that.
match_foreign_routed(Space, Route, [Comma|Conjuncts], _, OutPattern, Result) :-
    Comma == ',', Conjuncts = [_, _|_],
    foreign_claims_plan(Space, Conjuncts, Rest, Goal), !,
    call(Goal),
    match_foreign_routed(Space, Route, [','|Rest], [], OutPattern, Result).
match_foreign_routed(Space, Route, [Comma|[Head|Tail]], _, OutPattern, Result) :-
    Comma == ',', !,
    match_foreign_routed(Space, Route, Head, [], conj, conj),
    petta_annotation(Space, HeadK),
    match_foreign_routed(Space, Route, [','|Tail], [], OutPattern, Result),
    %The declared extend operation threads annotations along the join. Its
    %declared one combines without a write, so an unannotated join stays cheap;
    %the LAST conjunct combines with nothing, since the base case that
    %follows it contributes no answer of its own.
    petta_algebra_one(Space, One),
    (   HeadK == One
    ->  true
    ;   Tail == []
    ->  true
    ;   petta_annotation(Space, TailK),
        petta_k_extend(Space, HeadK, TailK, RowK),
        b_setval('$petta_answer_k', RowK)
    ).
%An unbound pattern is enumeration whichever way the space answers matches, so
%it asks for that capability on its own rather than riding the route.
match_foreign_routed(Space, _, PatternVar, _, OutPattern, Result) :-
    var(PatternVar), !,
    refuse_absent_capability(Space, enumerate),
    %The source guard sits at the three clauses that PHYSICALLY touch the
    %provider, not at the conjunction entry: a join's inner conjunct is
    %its own touch per outer row, and that second touch of a drained
    %linear source is exactly what must be loud.
    petta_source_guard(Space),
    seam:foreign_atoms(Space, PatternVar),
    acyclic_term(OutPattern),
    Result = OutPattern.
match_foreign_routed(Space, match, Pattern, Options, OutPattern, Result) :- !,
    licensed_options(Space, Pattern, Options, Licensed),
    petta_source_guard(Space),
    (   petta_on_error_mode(Space, Pattern, Mode),
        Mode \== abort
    ->  petta_match_erring(Mode, Space, Pattern, Licensed, OutPattern, Result)
    ;   seam:foreign_match(Space, Pattern, Licensed),
        acyclic_term(OutPattern),
        Result = OutPattern
    ).

match_foreign_routed(Space, enumerate, Pattern, _, OutPattern, Result) :-
    petta_source_guard(Space),
    seam:foreign_atoms(Space, Candidate),
    Candidate = Pattern,
    acyclic_term(OutPattern),
    Result = OutPattern.
%A declared keep delivers the provider's own failure as one final (Error
%...) answer beside the answers that already streamed, LeaTTa's
%adjudicated reading of evaluation errors turned to the provider
%boundary; empty ends the stream by declaration. Control signals and
%transport failures pass through both, always: an interrupt is the
%caller's, and an absent backend is never a data answer.
%
%WHERE the failure is caught depends on the provider's host, and that is
%not a style choice: a Python exception raised mid-iteration TUNNELS
%through py_iter back to the outer Python interpreter and no Prolog
%catch/3 can hold it [measured 2026-08-17: a catch-all around py_iter
%still surfaced the raw ValueError in janus.query_once], so a Python
%provider's mode is enforced on the Python side of the crossing, with a
%kept failure arriving as the reserved ["x","error",...] wire item
%through the seam:foreign_erring/5 adapter hook. A provider whose host
%is Prolog throws ordinary catchable exceptions, and the fallback below
%handles those here; catch/3 keeps the goal's choice points, so streamed
%answers survive the wrapping.
petta_match_erring(Mode, Space, Pattern, Licensed, OutPattern, Result) :-
    (   seam:foreign_erring(Space, Pattern, Licensed, Mode, Item)
    *-> (   Item == answer
        ->  acyclic_term(OutPattern),
            Result = OutPattern
        ;   Item = kept(Kept),
            Result = Kept
        )
    ;   catch(( seam:foreign_match(Space, Pattern, Licensed),
                Outcome = answer ),
              Error,
              petta_match_error_outcome(Error, Mode, Outcome)),
        (   Outcome == answer
        ->  acyclic_term(OutPattern),
            Result = OutPattern
        ;   Outcome = kept(E),
            petta_error_answer(Pattern, E, Result)
        )
    ).

petta_match_error_outcome(Error, _, _) :-
    control_exception(Error), !, throw(Error).
petta_match_error_outcome(Error, _, _) :-
    petta_transport_failure(Error), !, throw(Error).
petta_match_error_outcome(Error, keep, kept(Error)).

%A bound pattern went straight to the match hook, so a provider that
%implements only enumeration answered NOTHING to every real query while the
%space demonstrably held matching atoms. bindings/python/petta/foreign.py states the
%opposite contract for the same seam, in as many words: "An Enumerable
%provider need not implement Matcher: enumeration is the correct default
%candidate set". Porting a working Python provider to Prolog for speed, which
%is exactly what EXTENDING.md recommends, turned every match into an empty
%answer set.
%
%The provider is handed a FRESH variable and the filter happens here, so a
%provider written to enumerate never sees a bound pattern it was not written
%for. Unification staying on this side is also what makes over-approximation
%sound, which is the seam's central claim.
%The same match, carrying what the caller intends to do with it. Honouring an
%option is the provider's decision and not the engine's; see engine/ext_points.pl.
%Unification and the engine's own bound stay here whatever the provider does,
%so an option cannot make an answer wrong, only cheaper.
match_foreign(Space, Pattern, Options, OutPattern, Result) :-
    petta_refuse_guard(Space, Pattern),
    petta_negation_world_guard(Space),
    foreign_route(Space, Route),
    match_foreign_routed(Space, Route, Pattern, Options, OutPattern, Result).

%The bound reaches a provider that PROMISED it can act on it, and nobody else.
%
%It used to reach everyone as advice, with the rule for using it soundly
%written in the contract: honour it only where an exact match is
%distinguishable from a candidate, because N candidates are not N answers and
%truncating without knowing which of them unify under-answers. That rule is
%correct and it is a trap, since nothing checked whether a provider that
%truncated was entitled to. This engine's own test fixture had "its match is
%exact" in a docstring and nothing testing it.
%
%So the number goes to a provider that declared exact for this pattern, and
%the trap closes by construction: a provider that never promised is never
%given a number it could truncate to. Apache DataFusion's planner does the
%same thing with the same reasoning, dropping its own FilterExec only for a
%source that answered Exact.
%
%What the engine deliberately does NOT do with the class is stop pulling
%earlier. That was the obvious use and it buys nothing, measured both ways: a
%Prolog provider is already cut by the caller's own limit/2 after the Nth
%answer, and a Python one is pulled one ahead by janus's py_iter whatever the
%engine asks for, so limit(3) produced 3 and 4 candidates respectively with
%and without the classification wired to it [measured 2026-08-16,
%ai-tmp/x7pl.pl]. Unification is not skippable either: it is not a filter here
%but the step that binds the pattern's variables. An exact claim can therefore
%make a provider cheaper and can never make an answer wrong.
licensed_options(Space, Pattern, Options, Licensed) :-
    (   selectchk(limit(_), Options, WithoutBound)
    ->  (   foreign_pushdown_class(Space, Pattern, exact)
        ->  Licensed = Options
        ;   Licensed = WithoutBound
        )
    ;   Licensed = Options
    ).

%%%% take: at most K answers, and the bound the provider gets %%%%
%
%limit/2 is applied OUTSIDE the producer in both clauses, and that is what
%makes the whole thing correct rather than merely fast: it cuts the producer
%after the Kth answer whatever the producer did, so an infinite one terminates
%and a pushdown below it cannot change an answer. The pushdown decides only
%how much work the backend does before the first one.
metta_take(Count, Goal) :-
    metta_take_count(take, Count),
    limit(Count, Goal).

%The bound reaches the PROVIDER only when the expression is exactly one match
%over one space. Across a join the bound belongs to the joined rows, and an
%outer match truncated at N loses the rows its later candidates would have
%joined to; that is the rule petta_py_query_limit_all/5 already follows for
%m.query(limit=), and this is the same rule at the MeTTa level rather than a
%second one.
%
%A provider that never claimed `exact` for this pattern is not handed the
%number at all, which licensed_options/4 enforces on the way through, so the
%one thing the contract forbids stays impossible from here too.
%
%The native side goes through match_bounded/5, which is where the count stops
%a conjunctive snapshot instead of only cutting its answers; a single pattern
%reaches match/4 from there exactly as it did.
metta_take_match(Count, Space, Pattern, OutPattern, Result) :-
    metta_take_count(take, Count),
    (   nonvar(Space),
        seam:foreign_space(Space)
    ->  limit(Count, match_foreign(Space, Pattern, [limit(Count)], OutPattern,
                                   Result))
    ;   limit(Count, match_bounded(Count, Space, Pattern, OutPattern, Result))
    ).

%A count that is not a number is a mistake rather than an empty answer, for
%the reason every refusal here is: failing into "there is nothing there" sends
%the author looking at their data. A count of zero or less answers nothing,
%which is what "at most K" means and what limit/2 already does.
metta_take_count(_, Count) :- integer(Count), !.
metta_take_count(Form, Count) :-
    throw(error(type_error(integer, Count),
                context(Form/2, 'take needs a whole number of answers'))).

%%%% top: the k BEST by annotation, where take is any k %%%%
%
%Two bounds, two specifications. take k is "at most k, no promise which",
%correct for unordered contexts. top k is the k best in the context's
%declared semiring order, the operation a vector index actually
%implements. Each answer's annotation rides '$petta_answer_k',
%backtrackably: the seam sets it per explicit answer and the default 1
%is restored on redo, so an unannotated answer between two annotated
%ones reads 1 rather than a stale neighbour.
:- meta_predicate metta_take(+, 0), metta_top(+, 0, ?).
%The same reason the block above metta_timeout/3 in metta.pl records:
%without this the bounded goal loses its module and a named space's own
%functions are unreachable inside take and top.

metta_top(Count, Goal, Out) :-
    metta_take_count(top, Count),
    current_metta_space(Ctx),
    petta_algebra_one(Ctx, One),
    findall(Annotation-Out,
            ( b_setval('$petta_answer_k', One),
              call(Goal),
              b_getval('$petta_answer_k', Annotation) ),
            Pairs),
    metta_top_best(Count, Pairs, Best),
    member(Out, Best).

%The single-match form checks the context's declared order and decides the
%push. The bound reaches the provider only when three declarations hold
%together: the route is Exact for this shape, the annotations are ordered,
%and the merge policy is best-first, since the first k of a best-first
%emission ARE the k best. Drop any one and a pushed bound can return the
%wrong k, not merely a permutation, so the bound stays here and the
%ordering happens after collection.
metta_top_match(Count, Space, Pattern, OutPattern, Result) :-
    metta_take_count(top, Count),
    (   petta_annotations_ordered(Space)
    ->  true
    ;   petta_annotations(Space, Semiring),
        throw(error(petta_top_unordered(Space, Semiring), none))
    ),
    (   nonvar(Space),
        seam:foreign_space(Space)
    ->  (   petta_top_pushable(Space, Pattern)
        ->  Options = [limit(Count)]
        ;   Options = []
        ),
        Producer = match_foreign(Space, Pattern, Options, OutPattern, Result)
    ;   %A native space that declares an ordered semiring still stores
        %plain atoms, so every annotation reads 1 and top k keeps the
        %first k by emission order, the all-ties reading.
        Producer = match(Space, Pattern, OutPattern, Result)
    ),
    petta_algebra_one(Space, One),
    findall(Annotation-Result,
            ( b_setval('$petta_answer_k', One),
              Producer,
              b_getval('$petta_answer_k', Annotation) ),
            Pairs),
    metta_top_best(Count, Pairs, Best),
    member(Result, Best).

petta_top_pushable(Space, Pattern) :-
    %A cap below exact, or a cap refusal, declines the pushdown here and
    %lets the match itself surface the loud error, so (top k) never pushes
    %a bound an advisor has withdrawn the licence for.
    catch(( petta_handles_route(Space, Pattern, 'Exact', _),
            petta_route_cap_apply(Space, Pattern, exact, exact) ),
          _, fail),
    petta_emits(Space, 'best-first').

%Best first, ties in emission order: sort/4 with @>= keeps duplicates and
%is stable, so equal annotations keep the provider's own order.
metta_top_best(Count, Pairs, Best) :-
    sort(1, @>=, Pairs, Ordered),
    length(Ordered, Total),
    Keep is min(Count, Total),
    length(Prefix, Keep),
    append(Prefix, _, Ordered),
    findall(Out, member(_-Out, Prefix), Best).

:- multifile prolog:error_message//1.
prolog:error_message(petta_top_unordered(Ctx, Semiring)) -->
    [ '(top k ...) asks for the k BEST and ~w declares the ~w semiring, \c
       which carries no order. Declare (annotations ~w ranked) if this \c
       context annotates its answers, or use (take k ...) for any \c
       k'-[Ctx, Semiring, Ctx] ].

%What the seam already decided for a query, shown to a host without running
%it: refusal preflighted through the same petta_refuse_guard that
%match_foreign consults, per-pattern classes through foreign_pushdown_class
%with each pattern asked standalone, and the conjunction claim through the
%same guarded seam:foreign_plan call the execution commits to, the
%lossy-partition check included. Claimed and Rest come back as indexes into
%the pattern list, so a host renders its own atoms and its caller's variable
%names survive. A stored space answers explain(stored, [], [], []): the
%engine joins by unification and no provider is consulted. Origins are
%TERMS, declared(Entry, Fidelity, Det), provider, unclaimed or
%refused(Entry); prose is the host's own presentation.
metta_host_explain_match(Space, Patterns, Report) :-
    (   \+ seam:foreign_space(Space)
    ->  Report = explain(stored, [], [], [])
    ;   ( Patterns = [Whole] -> true ; Whole = [','|Patterns] ),
        catch(
            ( \+ \+ petta_refuse_guard(Space, Whole),
              maplist(metta_host_explain_class(Space), Patterns, Classes),
              metta_host_explain_plan(Space, Patterns, ClaimedIdx, RestIdx),
              Report = explain(foreign, Classes, ClaimedIdx, RestIdx) ),
            error(petta_refused_shape(_, _, Entry), _),
            Report = explain(refused, [Entry], [], []))
    ).

metta_host_explain_class(Space, Pattern, class(Class, Origin)) :-
    catch(
        ( foreign_pushdown_class(Space, Pattern, Class),
          metta_host_explain_origin(Space, Pattern, Origin) ),
        error(petta_refused_shape(_, _, Refusing), _),
        ( Class = refused,
          Origin = refused(Refusing) )).

%The origin consult mirrors foreign_pushdown_class's own precedence: a
%declared (handles ...) entry outranks the provider's method, and silence
%is the closed-world inexact.
metta_host_explain_origin(Space, Pattern, Origin) :-
    (   petta_handles_route(Space, Pattern, Entry, Fidelity, Det)
    ->  Origin = declared(Entry, Fidelity, Det)
    ;   seam:foreign_pushdown(Space, Pattern, _)
    ->  Origin = provider
    ;   Origin = unclaimed
    ).

metta_host_explain_plan(Space, Patterns, ClaimedIdx, RestIdx) :-
    (   Patterns = [_, _|_],
        foreign_provides(Space, plan),
        once(seam:foreign_plan(Space, Patterns, Claimed, Rest, _Goal)),
        Claimed \== []
    ->  refuse_lossy_plan(Space, Patterns, Claimed, Rest),
        maplist(metta_host_explain_index(Patterns), Claimed, ClaimedIdx),
        maplist(metta_host_explain_index(Patterns), Rest, RestIdx)
    ;   ClaimedIdx = [],
        findall(I, nth0(I, Patterns, _), RestIdx)
    ).

metta_host_explain_index(Patterns, Term, Index) :-
    nth0(Index, Patterns, Candidate),
    Candidate == Term, !.

%What a provider claims about its own filtering for THIS pattern. Silence is
%inexact, which is Prolog's own closed-world reading of the question, "any
%conclusion that cannot be proved to follow from the facts and rules in the
%database is false" [source: Bramer, Logic Programming with Prolog, 3.1], and
%the cautious answer: an inexact provider gets no bound to truncate to and its
%candidates are re-unified.
foreign_pushdown_class(Space, Pattern, Class) :-
    foreign_pushdown_declared_class(Space, Pattern, Declared),
    petta_route_cap_apply(Space, Pattern, Declared, Class).

foreign_pushdown_declared_class(Space, Pattern, Class) :-
    (   petta_handles_route(Space, Pattern, Entry, Fidelity, _Det)
    ->  %A declared (handles ...) entry outranks the provider's own method:
        %the declaration is the author's claim, checked by its lanes, and
        %the method stays as the dynamic floor for the undeclared. Exact
        %licenses the bound; Partial and Sound are candidates needing
        %re-unification, today's inexact; Refuse is the author's NO and it
        %is loud, the same precedence volatile has over unchecked.
        (   Fidelity == 'Exact'  -> Class = exact
        ;   Fidelity == 'Refuse' -> throw(error(petta_refused_shape(Space,
                                                                    Pattern,
                                                                    Entry),
                                                none))
        ;   Class = inexact
        )
    ;   seam:foreign_pushdown(Space, Pattern, Claimed)
    ->  Class = Claimed
    ;   Class = inexact
    ).

%The advisors' fold: every seam:route_cap/4 clause is a voice and the
%most conservative wins, refuse below inexact below exact, so an advisor
%can only DEMOTE what the declaration or the method proposed. refuse is
%loud and names the advisor's Why; a cap outside the vocabulary is a bug
%in the advisor and refuses as one. The common engine has no advisor
%loaded, and that costs one failed indexed call; with advisors present
%the probe's work is repeated inside findall, which is accepted, advisors
%being rare and the fold running only at route classification, never per
%answer.
petta_route_cap_apply(Space, Pattern, Class0, Class) :-
    (   \+ seam:route_cap(Space, Pattern, _, _)
    ->  Class = Class0
    ;   findall(Cap-Why, seam:route_cap(Space, Pattern, Cap, Why), Caps),
        (   member(BadCap-BadWhy, Caps),
            % policy-inventory-exempt: mechanism-internal; reason=exact inexact and refuse are the route-advisor fold states rather than a user policy vocabulary; evidence=engine/spaces.pl:petta_route_cap_apply/4
            \+ memberchk(BadCap, [exact, inexact, refuse])
        ->  throw(error(petta_route_cap_invalid(Space, BadCap, BadWhy),
                        none))
        ;   member(refuse-Why, Caps)
        ->  throw(error(petta_route_capped(Space, Pattern, Why), none))
        ;   memberchk(inexact-_, Caps)
        ->  Class = inexact
        ;   Class = Class0
        )
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_route_capped(Space, Pattern, Why)) -->
    { swrite(Pattern, PatternText) },
    [ 'a route advisor refuses ~w for ~w: ~w. The cap rides \c
       seam:route_cap/4; remove the advisor''s reason or its declaration \c
       to route again'-[Space, PatternText, Why] ].
prolog:error_message(petta_route_cap_invalid(Space, Cap, Why)) -->
    [ 'a route advisor for ~w answered the cap ~w (why: ~w), outside \c
       exact, inexact and refuse; an unknown cap would silently advise \c
       nothing, so it is an error in the advisor'-[Space, Cap, Why] ].

%%%% Multi-context matching: one query over several spaces %%%%
%
%(match (superpose (&a &b ...)) P T), the multi-context idiom, merges
%the spaces' answer streams under the declared (merge <pattern>
%<policy>): depth is today's space-after-space order and the undeclared
%floor; fair interleaves the streams round-robin through SWI engines,
%LogicT's msplit in the engine's own machinery (the reified-backtracking
%meta-interpreter shape, threadless); best-first is a k-way ordered
%merge by annotation, sound only when every context's own emission is
%best-first, which its (emits ...) declaration promises and this
%refuses loudly without.
petta_merged_match(Spaces, Pattern, Out) :-
    (   petta_merge_route(Pattern, Policy)
    ->  petta_merged_match_(Policy, Spaces, Pattern, Out)
    ;   member(Space, Spaces),
        match(Space, Pattern, Out, Out)
    ).

petta_merged_match_(depth, Spaces, Pattern, Out) :-
    member(Space, Spaces),
    match(Space, Pattern, Out, Out).
petta_merged_match_(fair, Spaces, Pattern, Out) :-
    maplist(petta_match_engine(Pattern, Out), Spaces, Engines),
    setup_call_cleanup(true,
                       petta_round_robin(Engines, Pattern-Out),
                       maplist(petta_engine_done, Engines)).
petta_merged_match_('best-first', Spaces, Pattern, Out) :-
    forall(member(Space, Spaces),
           (   petta_emits(Space, 'best-first')
           ->  true
           ;   throw(error(petta_merge_unordered(Space, Pattern), none))
           )),
    maplist(petta_scored_engine(Pattern, Out), Spaces, Engines),
    setup_call_cleanup(true,
                       petta_best_merge(Engines, Pattern-Out),
                       maplist(petta_engine_done, Engines)).

petta_match_engine(Pattern, Out, Space, Engine) :-
    engine_create(Pattern-Out, match(Space, Pattern, Out, Out), Engine).

petta_scored_engine(Pattern, Out, Space, Engine) :-
    petta_algebra_one(Space, One),
    engine_create(K-(Pattern-Out),
                  ( b_setval('$petta_answer_k', One),
                    match(Space, Pattern, Out, Out),
                    b_getval('$petta_answer_k', K) ),
                  Engine).

petta_engine_done(Engine) :-
    catch(engine_destroy(Engine), _, true).

petta_round_robin([], _) :- fail.
petta_round_robin([Engine|Engines], Template) :-
    (   engine_next(Engine, Answer)
    ->  (   Answer = Template
        ;   append(Engines, [Engine], Rotated),
            petta_round_robin(Rotated, Template)
        )
    ;   petta_round_robin(Engines, Template)
    ).

%One lookahead per stream; deliver the best, refill that stream. Each
%stream is itself best-first by declaration, so the maximum of the
%lookaheads is the maximum of everything unseen.
petta_best_merge(Engines, Template) :-
    foldl(petta_prime_engine, Engines, [], Primed),
    petta_best_merge_(Primed, Template).

petta_prime_engine(Engine, Primed0, Primed) :-
    (   engine_next(Engine, Answer)
    ->  Primed = [Engine-Answer|Primed0]
    ;   Primed = Primed0
    ).

petta_best_merge_([], _) :- fail.
petta_best_merge_(Primed, Template) :-
    Primed = [_|_],
    foldl(petta_better_head, Primed, none, Engine-Best),
    selectchk(Engine-Best, Primed, Rest),
    Best = _-Answer0,
    (   Answer0 = Template
    ;   petta_prime_engine(Engine, Rest, Refilled),
        petta_best_merge_(Refilled, Template)
    ).

petta_better_head(Engine-(K-Answer), none, Engine-(K-Answer)) :- !.
petta_better_head(Engine-(K-Answer), _-(BestK-_), Engine-(K-Answer)) :-
    K @> BestK, !.
petta_better_head(_, Best, Best).

:- multifile prolog:error_message//1.
prolog:error_message(petta_merge_unordered(Ctx, Pattern)) -->
    [ 'a best-first merge over ~q needs every context emitting best \c
       first, and ~w declares no (emits ~w best-first): merging ordered \c
       streams is only sound when each stream is ordered'-[Pattern, Ctx,
                                                           Ctx] ].

%Native conjunctions call their space predicate directly. The recursive helper
%keeps the provider decision outside the candidate loop.
%A conjunction is a JOIN, and the engine ran it as a nested loop in SOURCE
%order: each conjunct enumerated under every binding of the ones before it.
%That is quadratic where the join's own bound is not. Measured on the triangle
%query over a graph with a hub joined to everything in both directions, where
%no triangle exists at all, instructions differenced against the same file
%whose query is one unconstrained conjunct: 13,502,606 at 100 edges rising by
%exactly 4.0x per doubling to 3,620,340,557 at 1,600, while the AGM bound for a
%triangle over N edges is N^1.5, about 64,000 there
%[measured 2026-08-23, ai-tmp/synth/join/].
%
%Enumerating the conjunct with the FEWEST matches first removes it. Binding
%`$x,$y` from the first conjunct gives N choices and `$z` from the second gives
%deg(`$y`) more, which for the hub is another N/2, and only then does the third
%conjunct fail; taking the most constrained conjunct instead binds `$z` from
%the one that offers a single value and refutes the row at once. This is the
%minimum-remaining-values heuristic of constraint solving and the reason
%leapfrog triejoin seeks in its smallest relation
%[source: Veldhuizen, Leapfrog Triejoin, ICDT 2014, arXiv:1210.0481].
%
%It is NOT worst-case optimal, and the difference is worth stating: no ordering
%of a nested loop attains the AGM bound on the instance that bound is tight
%for, which is why a worst-case-optimal join intersects a variable's candidate
%sets across every conjunct that mentions it rather than generating from one
%and testing in the rest. That needs sorted access per variable, which the
%whole-conjunction seam foreign_plan/5 exists to delegate. This removes the
%SKEW, which is where the measured quadratic came from.
%
%MULTIPLICITY is preserved exactly because the atom combinations are the same
%ones, merely visited in another order: `(, (edge $x $y) (edge $x $y))` over a
%space holding `(edge a b)` twice answers four rows here as it did before.
%Answer ORDER is not preserved, and is not specified.
match_native(_, _, LComma, OutPattern, Result) :- LComma == [','], !,
                                                  Result = OutPattern.
match_native(Module, Space, [Comma|Conjuncts], OutPattern, Result) :-
    Comma == ',',
    Conjuncts = [_, _|_],
    relational_conjuncts(Conjuncts),
    !,
    match_relational_conjuncts(Module, Space, Conjuncts, OutPattern, Result).
match_native(Module, Space, [Comma|[Head|Tail]], OutPattern, Result) :- Comma == ',',
                                                                        var(Head), !,
                                                                        get_native_atom(Module, Space, Head),
                                                                        acyclic_term(OutPattern),
                                                                        match_native(Module, Space, [','|Tail], OutPattern, Result).
match_native(Module, Space, [Comma|[Head|Tail]], OutPattern, Result) :- Comma == ',',
                                                                        ( Head == [] ; \+ is_list(Head) ), !,
                                                                        get_native_scalar_atom_in(Module, Head),
                                                                        acyclic_term(OutPattern),
                                                                        match_native(Module, Space, [','|Tail], OutPattern, Result).
match_native(Module, Space, [Comma|[[Rel|PatArgs]|Tail]], OutPattern, Result) :- Comma == ',', !,
                                                                                native_expression(Module, Space, Rel, PatArgs),
                                                                                acyclic_term(OutPattern),
                                                                                match_native(Module, Space, [','|Tail], OutPattern, Result).

%When the native pattern itself is a variable, enumerate all atoms.
match_native(Module, Space, PatternVar, OutPattern, Result) :- var(PatternVar), !,
                                                               get_native_atom(Module, Space, PatternVar),
                                                               acyclic_term(OutPattern),
                                                               Result = OutPattern.

match_native(Module, _, Pattern, OutPattern, Result) :-
    ( Pattern == [] ; \+ is_list(Pattern) ), !,
    get_native_scalar_atom_in(Module, Pattern),
    acyclic_term(OutPattern),
    Result = OutPattern.

match_native(Module, Space, [Rel|PatArgs], OutPattern, Result) :- native_expression(Module, Space, Rel, PatArgs),
                                                                  acyclic_term(OutPattern),
                                                                  Result = OutPattern.

%Every conjunct list reached below is a SUBLIST of one relational_conjuncts/1
%has already accepted, and being relational is a property of each conjunct on
%its own, so asking again at every level walked the remaining conjuncts once
%per conjunct.
match_relational_conjuncts(Module, Space, Conjuncts, OutPattern, Result) :-
    cheapest_conjunct(Module, Space, Conjuncts, Goal, Rest),
    call(Goal),
    acyclic_term(OutPattern),
    (   Rest = [_, _|_]
    ->  match_relational_conjuncts(Module, Space, Rest, OutPattern, Result)
    ;   match_native(Module, Space, [','|Rest], OutPattern, Result)
    ).

%Read one stored expression through its private module. The module's unknown
%flag is fail, so a virgin arity fails directly and this indexed path needs no
%exception handler.
%The storage call unifies raw, so first-argument indexing dispatches, and
%the occurs check runs once on the answer instead: a cyclic binding fails
%THIS candidate and enumeration continues. Without it, a repeated-variable
%pattern like (f $y $y) against a stored (f (g $x) $x) "matched" whenever
%the out template did not mention $y, while the same pattern failed when it
%did, one match with two answers. The arbiter's matcher occurs-checks its
%variable cases (LeaTTa MettaHyperonFull/Core/Matching.lean matchAtomsWith),
%so a rational-tree instantiation is never a MeTTa answer.
%Every remaining conjunct is an expression whose head is settled, which is the
%shape the reordering understands. Anything else keeps source order.
relational_conjuncts([]).
relational_conjuncts([Conjunct|Conjuncts]) :-
    nonvar(Conjunct),
    Conjunct = [Rel|_],
    nonvar(Rel),
    relational_conjuncts(Conjuncts).

%The remaining conjunct with the fewest matches under the current bindings,
%found by a DOUBLING probe that stops as soon as one conjunct is exhausted:
%counting them all would cost as much as the join. A conjunct exhausted inside
%the current limit is known to be no larger than it, so the first one that
%exhausts wins and the probe costs O(smallest) rather than O(relation). Past
%the last limit every remaining conjunct offers more matches than the probe can
%distinguish, and source order is as good a choice as any.
%The first conjunct that offers AT MOST ONE match, which is the whole of the
%win: a conjunct with one match settles its variables and refutes the row at
%once, where the loop would otherwise enumerate another conjunct's many.
%Distinguishing two matches from three is not worth a probe that every step of
%every join pays, so the question asked is the cheap one, and the leading
%conjunct's goal is built once and kept for the fallback that uses it.
cheapest_conjunct(Module, Space, [First|More], Goal, Rest) :-
    conjunct_goal(Module, Space, First, FirstGoal),
    (   goal_matches_at_most_one(FirstGoal)
    ->  Goal = FirstGoal,
        Rest = More
    ;   selective_conjunct(Module, Space, More, Found, Others)
    ->  Goal = Found,
        Rest = [First|Others]
    ;   Goal = FirstGoal,
        Rest = More
    ).

selective_conjunct(Module, Space, Conjuncts, Goal, Rest) :-
    select(Best, Conjuncts, Rest),
    conjunct_goal(Module, Space, Best, Goal),
    goal_matches_at_most_one(Goal),
    !.

%The callable form of one conjunct, built ONCE and used by both the probe and
%the enumeration that follows it. native_expression/4 rebuilds it with =../2 on
%every call, and the probe would otherwise pay for that a second and a third
%time on the hottest path a join has.
conjunct_goal(Module, [Family|Parameters], [Rel|PatArgs], Module:Goal) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Goal =.. ['$petta_parametric_atom', Rel|PatArgs].
conjunct_goal(Module, Space, [Rel|PatArgs], Module:Goal) :-
    Goal =.. [Space, Rel|PatArgs].

%Has this goal AT MOST ONE solution, asked by both join paths: the native one
%passes the storage call conjunct_goal/4 built, the routed one passes match/4
%so the read reaches through the whole chain.
%
%Counted in a mutable cell under a single negation. nb_setarg/3 is not undone by
%the failure that drives the enumeration, so the count survives while every
%binding the probe made is discarded, which is the accumulator
%has_type_derive/3 uses for the same reason; and `\+` alone suffices, since it
%keeps no bindings of its own. It costs neither the solution list findnsols/4
%builds nor a copy_term/2, which together measured +11.4% on a dense join where
%this measures +2.35%. deterministic/1 is not a cheaper substitute: inside a
%negation it always reports a choicepoint, so no conjunct is ever chosen and
%both the skewed and the dense case get slower than doing nothing.
goal_matches_at_most_one(Goal) :-
    State = seen(0),
    \+ (   call(Goal),
           arg(1, State, Before),
           After is Before + 1,
           nb_setarg(1, State, After),
           After >= 2
       ).

native_expression(Module, [Family|Parameters], Rel, PatArgs) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Term =.. ['$petta_parametric_atom', Rel|PatArgs],
    call(Module:Term),
    acyclic_term(PatArgs).
native_expression(Module, Space, Rel, PatArgs) :-
    Term =.. [Space, Rel | PatArgs],
    call(Module:Term),
    acyclic_term(PatArgs).

'get-atoms'(Space, Pattern) :- nonvar(Space),
                               seam:foreign_space(Space), !,
                               refuse_absent_capability(Space, enumerate),
                               petta_source_guard(Space),
                               seam:foreign_atoms(Space, Pattern).

%Get all atoms in space, irregard of arity. A first argument that is not a
%space is refused HERE and not in get_native_atom/2 below, for the same reason
%metta_add_atom/3 leaves the check to 'add-atom'/3: this is the door a MeTTa
%program comes through and the one that owes it a MeTTa answer, while the
%storage read below is an engine internal whose callers hold a space name
%already and would read an error atom as a stored atom
%[tested: test_get_atoms_on_an_unbound_space_names_the_operation].
%The storage lookup decides it here too, for match/4's reason: a read of a
%space the engine holds pays nothing, and only an unknown name reaches
%petta_space_name/1. get_native_atom/3 rather than /2 because the lookup /2
%would repeat has already happened in the condition.
'get-atoms'([Family|Parameters], Pattern) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    (   native_storage_module_ready(Space, Module)
    ->  get_native_atom(Module, Space, Pattern)
    ;   fail
    ).
'get-atoms'(Space, Pattern) :-
    (   atom(Space)
    ->  (   native_storage_module_ready(Space, Module)
        ->  (   space_parent(Space, _)
            ->  get_inherited_atom(Space, Module, Pattern)
            ;   get_native_atom(Module, Space, Pattern)
            )
        ;   petta_space_name(Space)
        ->  fail
        ;   space_argument_error('get-atoms', [Space], Pattern)
        )
    ;   space_argument_error('get-atoms', [Space], Pattern)
    ).

get_inherited_atom(Space, OwnModule, Pattern) :-
    space_read_chain(Space, Each),
    (   Each == Space
    ->  get_native_atom(OwnModule, Space, Pattern)
    ;   get_atom_read_link(Each, Pattern)
    ).

get_atom_read_link(Space, Pattern) :-
    seam:foreign_space(Space),
    !,
    refuse_absent_capability(Space, enumerate),
    petta_source_guard(Space),
    seam:foreign_atoms(Space, Pattern).
get_atom_read_link(Space, Pattern) :-
    native_storage_module_ready(Space, Module),
    get_native_atom(Module, Space, Pattern).

%Drop every atom a space holds. Expressions and scalars live in different
%predicates, so a caller that wipes only the space predicate would leave the
%scalars standing and a pooled name's next life would inherit them.
%Clearing a foreign space is the provider's own operation, and it lived in
%bindings/python/petta/shim.pl, so a Prolog provider that implemented clear (as
%lib/lib_redis.pl does) was reachable only when Python was in the process:
%under run.sh the engine had no path to it at all. The shim now calls this.
clear_foreign_atoms(Space) :-
    foreign_write(Space, clear, seam:foreign_clear(Space)).

%A space has two halves and this used to empty one of them. The storage sweep
%below drops every stored atom, and the atoms that also COMPILED left their
%clauses standing in the space's execution module, so a space holding nothing
%still answered its own functions: define (= (past-life) inherited), clear,
%and `!(past-life)` in that space still answered `inherited` over an empty
%space [measured 2026-08-19, ai-tmp/spaces-p1/probe_p116h.pl]. Space names
%are POOLED, so that is a previous life answering through a recycled name.
%
%It was masked rather than absent: bindings/python/petta/shim.pl's clear removes
%equations through the removal funnel before calling this, so the Python door
%was whole and the ENGINE's own door was not. Every other caller got the half
%clear, and P1.14's reload will come through this one.
%
%So the compiled half leaves first, through metta_remove_atom/3, which is the
%code that owns each shape: an equation un-compiles its clause and forgets the
%function name when nothing else defines it, a declaration recompiles the call
%sites it was shaping. Only those two shapes, because only those two have a
%compiled half, which is exactly the two clauses metta_remove_atom/3 answers
%specially; a plain atom is storage and nothing else, so the sweep is both
%correct and one retractall per arity rather than one removal per atom.
%
%The funnel is idempotent, so the shim's own pass in front of this one leaves
%nothing here to find and no removal is announced twice
%[tested: spaces_execution_modules:clearing_a_space_empties_its_execution_module,
%test_a_recycled_space_name_inherits_no_clauses_from_its_past_life].
%Only a pool whose synthesized admission guard and capacity row coexist gets
%a counter. Its dynamic fact participates in an enclosing transaction exactly
%like the stored atom clauses do, so a rollback restores both. The regular
%write door never probes it: successful claimed writes update it from the hook
%path, while an indexed removal clause exists only for counted spaces. Removing
%the capacity row drops both facts; adding the row back recounts once before
%the next decision. An equation can be a derived duplicate that stores nothing,
%so that rare shape recounts after the write instead of assuming one landed
%[tested: capacity_counter_changes_roll_back_with_the_atoms,
%capacity_redeclaration_recounts_writes_made_while_unbounded;
%commit=819b139c7cdbdaa673f854713e8beb988eb12ead].
:- dynamic petta_capacity_count/2.
:- dynamic petta_capacity_remove_hook/2.

petta_capacity_contract_added(Pool) :-
    (   petta_capacity_admission_claim(Pool)
    ->  petta_capacity_count_install(Pool)
    ;   true
    ).

petta_capacity_admission_claim(Pool) :-
    atom_concat('space-admission-guard-', Pool, Guard),
    petta_hook_claim(Pool, pre_add, Guard, _).

petta_capacity_count_claim(Pool) :-
    (   '$petta_atoms:&petta':'&petta'(capacity, Pool, _)
    ->  petta_capacity_count_install(Pool)
    ;   true
    ).

petta_capacity_count_install(Space) :-
    (   seam:foreign_space(Space)
    ->  true
    ;   with_mutex('$petta_capacity_count',
                   transaction(( (   petta_capacity_count(Space, _)
                                 ->  true
                                 ;   space_atom_count_uncached(Space, Count),
                                     assertz(petta_capacity_count(Space, Count))
                                 ),
                                 petta_capacity_remove_hook_install(Space) )))
    ).

petta_capacity_count_uninstall(Space) :-
    with_mutex('$petta_capacity_count',
               transaction(( retractall(petta_capacity_count(Space, _)),
                             forall(retract(petta_capacity_remove_hook(Space,
                                                                       Ref)),
                                    catch(erase(Ref), _, true)) ))).

%A claim-time clause specializes remove_sexp/3 on the ground pool name.
%First-argument indexing skips it for every unclaimed space, so ordinary
%removals retain their old inference count instead of paying a failed counter
%probe [measured: register-op 44334 inferences on 2026-08-21, min of 3;
%command=cd python && python bench.py --counter-only --keep-going;
%fixture=bindings/python/benchmarks/test_benchmarks.py::test_register_operation;
%commit=819b139c7cdbdaa673f854713e8beb988eb12ead]. The clause and its reference are dynamic database state,
%hence an enclosing transaction rolls their installation back with the claim.
petta_capacity_remove_hook_install(Space) :-
    (   petta_capacity_remove_hook(Space, _)
    ->  true
    ;   asserta((remove_sexp(Space, Term, Removed) :-
                    !,
                    petta_capacity_remove_sexp(Space, Term, Removed)), Ref),
        assertz(petta_capacity_remove_hook(Space, Ref))
    ).

petta_capacity_remove_sexp('&petta', [Rel|Args], Removed) :- !,
    (   native_storage_module_ready('&petta', Module)
    ->  Term =.. ['&petta', Rel|Args],
        native_retract_one(Module:Term, Removed),
        (   Removed == true
        ->  petta_catalog_note_removed([Rel|Args])
        ;   true
        )
    ;   Removed = false
    ),
    petta_capacity_count_removed_known('&petta', Removed).
petta_capacity_remove_sexp(Space, [Rel|Args], Removed) :- !,
    (   native_storage_module_ready(Space, Module)
    ->  native_storage_functor(Space, Functor),
        Term =.. [Functor, Rel|Args],
        native_retract_one(Module:Term, Removed)
    ;   Removed = false
    ),
    petta_capacity_count_removed_known(Space, Removed).
petta_capacity_remove_sexp(Space, Atom, Removed) :-
    (   native_storage_module_ready(Space, Module)
    ->  native_retract_one(Module:'$petta_native_scalar'(Atom), Removed)
    ;   Removed = false
    ),
    petta_capacity_count_removed_known(Space, Removed).

petta_capacity_counts_prune :-
    findall(Pool, petta_capacity_count(Pool, _), Pools0),
    sort(Pools0, Pools),
    forall(member(Pool, Pools),
           (   '$petta_atoms:&petta':'&petta'(capacity, Pool, _)
           ->  true
           ;   petta_capacity_count_uninstall(Pool)
           )).

petta_capacity_count_added(Space, [=, [F|_], _]) :-
    atom(F),
    !,
    petta_capacity_count_recount(Space).
petta_capacity_count_added(Space, _) :-
    petta_capacity_count_delta(Space, 1).

petta_capacity_count_added_known(Space, [=, [F|_], _]) :-
    atom(F),
    !,
    petta_capacity_count_recount(Space).
petta_capacity_count_added_known(Space, _) :-
    petta_capacity_count_delta_known(Space, 1).

petta_capacity_count_removed_known(_, false) :- !.
petta_capacity_count_removed_known(Space, true) :-
    petta_capacity_count_delta_known(Space, -1).

petta_capacity_count_delta(Space, Delta) :-
    (   petta_capacity_count(Space, _)
    ->  petta_capacity_count_delta_known(Space, Delta)
    ;   true
    ).

petta_capacity_count_delta_known(Space, Delta) :-
    with_mutex('$petta_capacity_count',
               transaction(( (   retract(petta_capacity_count(Space, Count0))
                             ->  Count1 is Count0 + Delta,
                                 (   Count1 >= 0
                                 ->  Count = Count1
                                 ;   space_atom_count_uncached(Space, Count)
                                 ),
                                 assertz(petta_capacity_count(Space, Count))
                             ;   true
                             ) ))).

petta_capacity_count_recount(Space) :-
    (   petta_capacity_count(Space, _)
    ->  with_mutex('$petta_capacity_count',
                   ( space_atom_count_uncached(Space, Count),
                     transaction(( retractall(petta_capacity_count(Space, _)),
                                   assertz(petta_capacity_count(Space, Count)) )) ))
    ;   true
    ).

petta_capacity_count_cleared('&petta') :-
    !,
    with_mutex('$petta_capacity_count',
               transaction(( retractall(petta_capacity_count(_, _)),
                             forall(retract(petta_capacity_remove_hook(_, Ref)),
                                    catch(erase(Ref), _, true)) ))).
petta_capacity_count_cleared(Space) :-
    (   petta_capacity_count(Space, _)
    ->  with_mutex('$petta_capacity_count',
                   transaction(( retractall(petta_capacity_count(Space, _)),
                                 assertz(petta_capacity_count(Space, 0)) )))
    ;   true
    ).

%How many atoms a native space OWNS. Inherited match, get-atoms and
%space-contains read the child-first chain; this count deliberately does not,
%because capacity constrains the writable front store rather than its parents.
%A capacity-claimed pool reads its
%incremental fact; every other space reads the store's own per-predicate
%clause bookkeeping, the manual's count-asserted-facts idiom
%[source: https://www.swi-prolog.org/pldoc/man?predicate=predicate_property%2F2].
%A space that has never been written has no storage module and holds nothing.
%A foreign space's atoms live with its provider, where the only general count
%is an enumeration; hiding that would promise the wrong complexity class
%[tested: spaces_atom_count:a_foreign_space_has_no_native_count].
space_atom_count(Space, Count) :-
    petta_capacity_count(Space, Count),
    !.
space_atom_count(Space, Count) :-
    (   seam:foreign_space(Space)
    ->  throw(error(petta_foreign_space_count(Space), none))
    ;   space_atom_count_uncached(Space, Count)
    ).

space_atom_count_uncached(Space, Count) :-
    (   native_storage_module_ready(Space, Module)
    ->  findall(N,
                ( current_predicate(Module:Name/Arity),
                  functor(Head, Name, Arity),
                  (   predicate_property(Module:Head, number_of_clauses(N))
                  ->  true
                  ;   N = 0
                  ) ),
                Counts),
        sum_list(Counts, Count)
    ;   Count = 0
    ).

clear_native_atoms(Space) :-
    (   native_storage_module_ready(Space, Module)
    ->  space_module(Space, SupportModule),
        findall(Atom, compiled_half_atom(Space, Module, Atom), Compiled),
        forall(member(Atom, Compiled),
               ( metta_remove_atom(Space, Atom, _) -> true ; true )),
        native_storage_functor(Space, Functor),
        forall(( current_predicate(Module:Functor/Arity),
                 functor(Head, Functor, Arity) ),
               retractall(Module:Head)),
        retractall(Module:'$petta_native_scalar'(_))
    ;   SupportModule = none
    ),
    petta_capacity_count_cleared(Space),
    retractall(import_life(Space, _, _)),
    (   SupportModule \== none
    ->  support_forget_module(SupportModule)
    ;   true
    ),
    forget_space_source_loads(Space).

%The atoms whose removal has a consequence beyond storage, which are exactly
%the two shapes metta_remove_atom/3 answers specially; a shape added there
%without being added here would go back to leaving its compiled half behind a
%clear.
%
%Asked of the storage predicate by HEAD SYMBOL rather than by filtering a walk
%of the space. The head is the first argument, so this is one indexed lookup
%per shape and a space of plain atoms pays nothing for the question; filtering
%an enumeration cost one inference per stored atom on every clear, which the
%benchmarks saw as +20,002 inferences on py-method-call and +8,000 on
%handle-round-trip [measured 2026-08-19].
compiled_half_atom(Space, Module, [=, Head, Body]) :-
    native_storage_functor(Space, Functor),
    Term =.. [Functor, =, Head, Body],
    call(Module:Term),
    Head = [F|_], atom(F).
compiled_half_atom(Space, Module, [':', F, Type]) :-
    native_storage_functor(Space, Functor),
    Term =.. [Functor, ':', F, Type],
    call(Module:Term),
    atom(F), fun(F).

%Enumeration answers the space's expressions and then its scalar atoms.
%native_storage_module_ready/2 is a dynamic lookup, so an unbound space
%enumerated every space ever written to and !(collapse (get-atoms $any))
%answered with another space's atoms without ever naming it.
%
%This raise is the ENGINE's invariant and not the language's answer: a MeTTa
%program cannot reach it, because 'get-atoms'/2 above refuses a first argument
%that is not a space before it gets here. What is left is an engine caller
%that lost its space name, and that is a bug in the engine rather than in a
%program, so it throws instead of answering an atom the caller would store
%[tested: spaces_storage_modules:reading_atoms_requires_a_named_space].
get_native_atom(Space, Pattern) :-
    ( var(Space) -> instantiation_error(Space) ; true ),
    metta_refuse_module_for_space(Space, get_native_atom/2),
    native_storage_module_ready(Space, Module),
    get_native_atom(Module, Space, Pattern).

%The mirror of with_metta_module/2's refusal, at the space-name doors: a
%space MODULE handed where a NAME is wanted read exactly like a miss, the
%store answering "not held" with no type error, so a wrong-argument call
%was indistinguishable from absence and a plt cleanup once removed nothing
%from four of five cases in silence. The two execution-module prefixes turn it
%into a refusal at the door
%[tested: test_a_module_where_a_space_name_is_wanted_refuses_by_name].
metta_refuse_module_for_space(Space, Door) :-
    (   atom(Space),
        (   metta_exec_module_prefix(Prefix),
            sub_atom(Space, 0, _, _, Prefix)
        ;   sub_atom(Space, 0, _, _, '$petta_param_exec:')
        )
    ->  throw(error(type_error(metta_space_name, Space),
                    context(Door,
                            'a space MODULE arrived where a space NAME is \c
                             wanted; space_module/2 maps the exact atomic or \c
                             expression identifier to this module, not back')))
    ;   true
    ).

%A pattern whose SHAPE is known builds the storage head FIRST, so the
%store's argument indexing dispatches the way match/4's identical read
%does, instead of enumerating every clause under an unbound head and
%filtering afterwards: a bound-pattern read through this door was
%O(space held) where the same read through match was one indexed lookup
%[measured 2026-08-21: a per-add presence probe through the old path
%cost 2,055 inferences at 2,000 held atoms and 21,055 at 10,000,
%linear, against 69.01 flat through match's spelling of the same
%question; through this clause the same probe reads 57.01 at 2,000 and
%57.00 at 10,000]. The occurs check mirrors native_expression/4's: a cyclic
%binding is never a MeTTa answer. A partial list keeps the enumerating
%clause below, and a bound SCALAR skips both, because =../2 on it threw
%where the store owed a clean miss and the scalar shelf is that atom's
%own clause anyway [tested: spaces_contains].
get_native_atom(Module, [Family|Parameters], Pattern) :-
    is_list(Pattern),
    Pattern = [_|_],
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    length(Pattern, Arity),
    functor(Head, '$petta_parametric_atom', Arity),
    Head =.. ['$petta_parametric_atom'|Pattern],
    call(Module:Head),
    acyclic_term(Pattern).
get_native_atom(Module, Space, Pattern) :-
    is_list(Pattern),
    Pattern = [_|_],
    !,
    length(Pattern, Arity),
    functor(Head, Space, Arity),
    Head =.. [Space | Pattern],
    call(Module:Head),
    acyclic_term(Pattern).
get_native_atom(Module, [Family|Parameters], Pattern) :-
    \+ atomic(Pattern),
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    current_predicate(Module:'$petta_parametric_atom'/Arity),
    functor(Head, '$petta_parametric_atom', Arity),
    clause(Module:Head, true),
    Head =.. ['$petta_parametric_atom'|Pattern].
get_native_atom(Module, Space, Pattern) :-
    \+ atomic(Pattern),
    current_predicate(Module:Space/Arity),
    functor(Head, Space, Arity),
    clause(Module:Head, true),
    Head =.. [Space | Pattern].
get_native_atom(Module, _, Pattern) :-
    get_native_scalar_atom_in(Module, Pattern).

get_native_scalar_atom_in(Module, Pattern) :-
    Module:'$petta_native_scalar'(Pattern).
