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
:- consult('spaces/bounded_matching.pl').
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
