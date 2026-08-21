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
%   - Effective dispatch values are cached by function and axis, validated
%     against their catalog clause reference, and forgotten at every policy
%     mutation [tested: test_every_dispatch_axis_is_readable_settable_and_defaulted,
%     examples/performance/holbenchmark.metta; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - The policy catalog publishes exactly one knob and shipped default for
%     each of the seventeen engine decision axes, and the policy-inventory
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
%     metta_foreign_match/3, and unification and the caller's own bound stay
%     on this side, so an option cannot change an answer [tested 2026-08-16:
%     test_a_provider_ignoring_the_bound_is_still_bounded_by_the_engine].
%   - (top k ...) answers the k best by declared-semiring annotation,
%     stable on ties, refuses unordered contexts, and hands the provider
%     the bound only under Exact route + ordered annotations + best-first
%     merge [tested 2026-08-17: answers_annotations].
%   - A declared (handles ...) entry outranks metta_foreign_pushdown/3
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

:- dynamic native_storage_module_cache/2.
:- dynamic space_parametric/1.
%Whether a HOST's own atom hooks are idle for a space, the host's clause of
%it: the shim answers for the Python side, and with no host loaded the seam
%has no clause and the engine's own no-handlers test already answered. The
%engine hands the host the full handler CENSUS as clause references, so a
%host clause matches the census against the one reference it installed and
%never consults engine internals to answer: a host is asked about ITS hooks,
%with the facts it needs in the question.
:- multifile metta_host_add_hooks_idle/2.
ext_point_kind(metta_host_add_hooks_idle/2, ownership).
:- multifile metta_host_remove_hooks_idle/2.
ext_point_kind(metta_host_remove_hooks_idle/2, ownership).

%Only a module that actually holds something belongs to somebody else.
%current_module/1 is not that test: SWI creates a module as a side effect of
%merely naming it, including from read-only introspection, so
%predicate_property('$petta_atoms:&kb':anything, dynamic) was enough to make
%&kb throw on every write for the life of the process, with clear/1 reporting
%success and changing nothing. An empty module of that name is ours to claim
%[tested: spaces_registration:naming_the_storage_module_does_not_claim_it].
native_storage_module_occupied(Module) :-
    current_module(Module),
    predicate_property(Module:Head, defined),
    \+ predicate_property(Module:Head, imported_from(_)),
    \+ predicate_property(Module:Head, foreign), !.

native_storage_ready(Module) :-
    current_predicate(Module:'$petta_native_storage'/0),
    predicate_property(Module:'$petta_native_storage', dynamic),
    \+ predicate_property(Module:'$petta_native_storage',
                           imported_from(_)).

native_storage_module_ready(Space, Module) :-
    native_storage_module_cache(Space, Module).

%Whether a NAME is a space, which is the wider question: one this engine
%already holds, or one it would create by being written to. A space is created
%on demand here, so the second half cannot be the registry, and the rule for it
%is the engine's own: an atom beginning with `&`, which is what is-space/2
%answers, what evalc/3 has enforced at its door since it was written, and what
%bindings/python/petta/space.py enforces at the library's
%[tested: space_argument_refusals].
petta_space_name(S) :- atom(S), sub_atom(S, 0, 1, _, '&'), !.
petta_space_name(S) :- petta_space_operand(S).
%HERE rather than beside petta_space_operand/1 below, because the two
%directives that create &self's and &petta's storage modules run while this
%file loads and a directive can only call what is already defined.

ensure_native_storage_module(Space, Module) :-
    native_storage_module_cache(Space, Module), !.
%CREATION is where a name that is not a space is refused, and refusing here is
%what makes the check free: a space this engine already holds answered from the
%cache above without asking, and only a name it would have to CREATE reaches
%the question. The doors above turn this failure into the arbiter's own error
%answer [tested: space_argument_refusals]. Asking at each door instead cost one
%to three inferences on every space operation and four benchmarks saw it
%[measured 2026-08-20: direct-join +10, prepared-join +10, register-op +200,
%py-method-call +30,002].
ensure_native_storage_module(Space, Module) :-
    petta_space_name(Space),
    native_storage_module(Space, Module),
    with_mutex('$petta_native_storage',
               ensure_native_storage_module_locked(Space, Module)).

ensure_native_storage_module_locked(Space, Module) :-
    native_storage_module_cache(Space, Module), !.
ensure_native_storage_module_locked(Space, Module) :-
    native_storage_ready(Module), !,
    assertz(native_storage_module_cache(Space, Module)).
ensure_native_storage_module_locked(Space, Module) :-
    ( native_storage_module_occupied(Module)
      -> throw(error(permission_error(create, native_space_storage, Module),
                     context(ensure_native_storage_module/2,
                             'the reserved storage module name is already in use')))
    ; set_prolog_flag(Module:unknown, fail),
      dynamic(Module:'$petta_native_storage'/0),
      assertz(native_storage_module_cache(Space, Module)) ).

%The dynamic marker and module properties survive transaction rollback even
%when its cache fact does not. A later write can therefore recover the cache
%instead of finding a stranded reserved module name [tested:
%spaces_registration:rolled_back_first_write_keeps_storage_reusable].
:- ensure_native_storage_module('&self', _).
:- dynamic '$petta_atoms:&self':'&self'/3.
%&petta too, at load: the contract read path probes it on every foreign
%match, and against a module that does not exist yet each probe is a thrown
%and caught existence error, 65 inferences where the created module's
%unknown=fail flag answers the same miss in a handful [measured 2026-08-17:
%petta_handles_route 136 to 30 inferences per miss].
:- ensure_native_storage_module('&petta', _).

% Return the asserted clause reference so a source load can roll back every
% atom it added if a later form fails.
add_sexp(Space, Term) :- add_sexp(Space, Term, _).
%&self's storage module is fixed and created when this file loads, so the
%default space skips the cache lookup that every other space needs. Writes are
%the one path that pays per atom: resolving the module per write cost four
%inferences of every seven on this path [measured 2026-08-15: 7.00 to 5.00
%inferences per write over 200,000 writes].
add_sexp('&self', Term, Ref) :- !, add_sexp_in('$petta_atoms:&self', '&self', Term, Ref).
%The contract flag rides an indexed clause of its own, so an ordinary
%add never even tests for '&petta': first-argument indexing dispatches
%past this clause for every other space at zero cost, where a guard
%inside the shared funnel taxed every write (+26k on source-load's
%counter, caught by the gate).
add_sexp('&petta', Term, Ref) :- !,
    petta_declaration_check(Term),
    petta_note_ctx_declared(Term),
    ensure_native_storage_module('&petta', Module),
    add_sexp_in(Module, '&petta', Term, Ref),
    petta_catalog_note_added(Term).
add_sexp(Space, Term, Ref) :- ensure_native_storage_module(Space, Module),
                              add_sexp_in(Module, Space, Term, Ref).

%The two clause bodies below are native_atom_clause/3 written out rather than
%called, and that is measured rather than assumed: calling it cost one goal
%per write, +2001 inferences over add-batch's thousand atoms, +2 per write on
%a seven-inference path. native_atom_clause/3 stays the definition, this is
%its copy on the hot path, and native_storage_shapes_agree binds them.
:- dynamic petta_ctx_declared/1.

%Monotone-conservative contract flag, set at the one funnel every native
%'&petta' write passes: flag ABSENT proves no declaration has ever named
%the context, so the per-call guards below skip their probes outright;
%flag PRESENT only means "run the real probes", so a declaration removed
%or rolled back later costs nothing but the shortcut. The subject is
%conservatively the declaration's first argument whatever the head,
%because over-flagging a non-context symbol is harmless while missing a
%real context would silently skip a guard. This closes CA-7's open
%squeeze: the undeclared pure-Prolog foreign match paid the handles,
%source and on-error probes on every call.
petta_note_ctx_declared([Head|_]) :-
    petta_catalog_head(Head),
    !.
petta_note_ctx_declared([_, Ctx|_]) :-
    atom(Ctx),
    \+ petta_ctx_declared(Ctx),
    !,
    assertz(petta_ctx_declared(Ctx)).
petta_note_ctx_declared(_).

%The same monotone-conservative shortcut narrowed to the events head, and it
%is the one head that needs its own: a (subscription ...) atom names a SPACE
%in the same position, so every standing query flags its own space as
%ctx-declared and the general flag can no longer say "this context declared
%nothing about events". Without a flag the admission check walked the growing
%'&petta' store on every subscription: one subscribe cost 983,768
%instructions before the check existed, 1,093,524 with the check and 988,037
%with the flag, so the capability costs 0.43% rather than 11.2% [measured
%2026-08-21, instructions:u per subscribe, 1,000 standing queries against a
%0-query baseline, min of 3].
%
%It is set from petta_check_catalog_semantics/3 rather than from the walk
%above, and the difference is measured: that walk runs on EVERY '&petta'
%write and its first argument is a list, so every clause added to it is one
%inference on every write, which register-op's benchmark caught at +94 over
%its declarations. The semantics check dispatches on the head ATOM, so a
%clause for one head costs the other heads nothing.
:- dynamic petta_events_declared/1.

%The catalog's own rows never name a context in their first argument, a
%kind head or a vocabulary name being what sits there, and flagging those
%grew petta_ctx_declared from a handful of real contexts to forty rows,
%which the guards' first miss then paid as a linear walk before the JIT
%index built [measured 2026-08-20: the single-pattern snapshot probe read
%687 against 685 by warm-up order]. Skipping them keeps the flag exactly
%what it says: a context some declaration names.
petta_catalog_head(kind).
petta_catalog_head(vocabulary).
petta_catalog_head(claim).
petta_catalog_head(policy).
petta_catalog_head('routed-by-shape').
petta_catalog_head('dispatch-default').
petta_catalog_head('dispatch-policy').

add_sexp_in(Module, [Family|Parameters], [Rel|Args], Ref) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Term =.. ['$petta_parametric_atom', Rel|Args],
    assertz(Module:Term, Ref).
add_sexp_in(Module, Space, [Rel|Args], Ref) :- !,
                                               Term =.. [Space, Rel | Args],
                                               assertz(Module:Term, Ref).
%A scalar or empty expression cannot be a plain Space(Term) fact, because that
%is already the encoding of the singleton expression (Term). It gets its own
%predicate rather than a marked rule inside the space: a marked rule makes
%every clause of the space predicate a rule, so reading one back has to go
%through clause/2, which walks the clause list instead of using SWI's clause
%indexing. Measured on examples/spaces/matespace.metta, that cost 15.3x,
%99.5 billion instructions against 1,520 billion. Keeping scalars in
%the private scalar predicate leaves expressions as facts a direct indexed
%call reaches.
add_sexp_in(Module, _, Atom, Ref) :-
    assertz(Module:'$petta_native_scalar'(Atom), Ref).

%%%% The catalog describes its own kinds %%%%
%
%Three declaration heads make the catalog self-describing, themselves
%ordinary '&petta' atoms a program can match and remove:
%
%    (vocabulary Name Value...)       a named value set, every value a symbol
%    (claim Vocab Value Property...)  properties of one value, read where a
%                                     consultation site needs a per-value fact
%                                     rather than a list compiled into the
%                                     engine
%    (kind Head ArgSpec...)           the positional shape of every (Head ...)
%                                     declaration
%
%An argspec is symbol, integer, pattern, term, (one-of Vocab),
%(optional Spec) in the tail only, or (rest Spec) in final position matching
%zero or more. pattern and term both admit any term; the two names keep a
%kind's row readable, a pattern is matched against queries and a term is
%carried.
%
%The checker runs at the two doors every native '&petta' write passes, the
%per-atom funnel above and the bulk door below. A head with a declared kind
%is validated positionally, and a violation is a hard error naming the atom,
%the argument position and the argspec it missed, where the old behaviour
%was an atom that silently never matched its consultation site. A head with
%NO declared kind passes untouched, which is what keeps the data axis open:
%a third-party declaration kind is atoms here first, schema-checked only
%once its author declares a kind row for it. The shape is PostgreSQL's: enum
%values are catalog rows and a write validates against the catalog, not
%against a list compiled into the server [source: PostgreSQL documentation,
%8.7 Enumerated Types]. Removal is monotone-conservative, the
%petta_ctx_declared rule: a removed kind row means later adds of that head
%pass unchecked, and remove-then-redeclare, even WIDER than the shipped
%preset, is how a program deliberately loosens a shipped kind.
%
%Self-description bootstraps by declaration order: the presets below add the
%vocabularies first, then (kind kind ...) while no kind row exists yet, so
%it enters unchecked, and from that atom on every (kind ...) add is
%validated against it, its argspecs walked by the same checker that walks
%any other declaration.
petta_declaration_check(Term) :-
    Term = [Head|Args],
    atom(Head),
    petta_kind_spec(Head, Spec),
    !,
    petta_check_positions(Args, Spec, 1, Term),
    petta_check_catalog_semantics(Head, Args, Term).
petta_declaration_check(_).

%A landed catalog row must beat any negative cache row for its subject:
%the positive rows self-heal through their stored reference, the negative
%ones have nothing to watch, so the write funnel retracts them here. A
%kind or routing row landing also rebuilds its head's materialized route
%dispatch, which is how the shipped routes come up during the preset walk
%and how a third-party routed kind starts routing the moment its rows are
%in.
petta_catalog_note_added(['dispatch-policy', Function, Axis, _]) :-
    !,
    petta_dispatch_cache_forget(Function, Axis),
    petta_dispatch_policy_changed(Function, Axis).
petta_catalog_note_added(['dispatch-default', Axis, _]) :-
    !,
    petta_dispatch_default_cache_forget(Axis),
    petta_dispatch_default_changed(Axis).
petta_catalog_note_added([kind, Head|_]) :-
    !,
    retractall(petta_kind_cache(Head, _, _)),
    petta_materialize_route(Head).
petta_catalog_note_added([vocabulary, Vocab|_]) :-
    !,
    retractall(petta_vocab_cache(Vocab, _, _)).
petta_catalog_note_added(['routed-by-shape', Head|_]) :-
    !,
    petta_materialize_route(Head).
petta_catalog_note_added([algebra, Name|_]) :-
    !,
    retractall(petta_algebra_descriptor_cache(Name, _, _, _, _, _, _, _)).
petta_catalog_note_added([annotations, Ctx|_]) :-
    !,
    retractall(petta_annotations_cache(Ctx, _)).
petta_catalog_note_added([capacity, Pool, _]) :-
    !,
    petta_capacity_contract_added(Pool).
petta_catalog_note_added(_).

% A policy write is rare, while every equation compilation is hot. Materialize
% the typed root at mutation time over the function-view index the translated
% forms already maintain, then invalidate it. This gives stored callers the
% common forward walk without adding six edges to every compiled form.
petta_dispatch_policy_changed(Function, Axis) :-
    findall(F-Module,
            dispatch_changed_context(Function, F, Module),
            Contexts0),
    sort(Contexts0, Contexts),
    findall(Root,
            ( member(F-Module, Contexts),
              dispatch_changed_axis(Axis, ChangedAxis),
              Root = dispatch_policy(Module, F, ChangedAxis),
              support_record(function_view(Module, F), Root) ),
            Roots0),
    sort(Roots0, Roots),
    support_invalidate_many(Roots),
    forall(support_repair_invalidations, true),
    (   atom(Function)
    ->  invalidate_translated_forms(Function)
    ;   clear_translation_cache
    ).

dispatch_changed_context(Pattern, Function, Module) :-
    support_view_module(Function, Module),
    ( var(Pattern) -> true ; Function == Pattern ).

dispatch_changed_axis(Pattern, Axis) :-
    dispatch_axis_vocabulary(Axis, _),
    ( var(Pattern) -> true ; Axis == Pattern ).

% A default row applies to every function without an override, so invalidating
% all published roots for that axis is the exact conservative update. Clearing
% runnable templates avoids a second global dependency index for a rare edit.
petta_dispatch_default_changed(Axis) :-
    petta_dispatch_policy_changed(_, Axis).

petta_dispatch_all_changed :-
    forall(dispatch_axis_vocabulary(Axis, _),
           petta_dispatch_default_changed(Axis)).

%The removal twin, called by the '&petta' clause of remove_sexp below for
%a row that actually left. A variable head means the caller removed by
%pattern and anything may have gone, so everything derived is dropped and
%rebuilt, which over-invalidates and never under-invalidates.
petta_catalog_note_removed([Rel|_]) :-
    var(Rel),
    !,
    retractall(petta_kind_cache(_, _, _)),
    retractall(petta_vocab_cache(_, _, _)),
    retractall(petta_algebra_descriptor_cache(_, _, _, _, _, _, _, _)),
    retractall(petta_annotations_cache(_, _)),
    retractall(petta_dispatch_value_cache(_, _, _, _)),
    petta_materialize_routes,
    petta_capacity_counts_prune,
    petta_dispatch_all_changed.
petta_catalog_note_removed(['dispatch-policy', Function, Axis, _]) :-
    !,
    petta_dispatch_cache_forget(Function, Axis),
    petta_dispatch_policy_changed(Function, Axis).
petta_catalog_note_removed(['dispatch-default', Axis, _]) :-
    !,
    petta_dispatch_default_cache_forget(Axis),
    petta_dispatch_default_changed(Axis).
petta_catalog_note_removed([kind, Head|_]) :-
    !,
    retractall(petta_kind_cache(Head, _, _)),
    petta_materialize_route(Head).
petta_catalog_note_removed([vocabulary, Vocab|_]) :-
    !,
    retractall(petta_vocab_cache(Vocab, _, _)).
petta_catalog_note_removed(['routed-by-shape', Head|_]) :-
    !,
    petta_materialize_route(Head).
petta_catalog_note_removed([algebra, Name|_]) :-
    !,
    retractall(petta_algebra_descriptor_cache(Name, _, _, _, _, _, _, _)).
petta_catalog_note_removed([annotations, Ctx|_]) :-
    !,
    retractall(petta_annotations_cache(Ctx, _)).
petta_catalog_note_removed([capacity|_]) :-
    !,
    petta_capacity_counts_prune.
petta_catalog_note_removed(_).

%One catalog row as a list, whatever its arity: '&petta'(kind, handles,
%symbol, ...) reads back as [kind, handles, symbol, ...]. The walk over the
%arities the storage module holds runs on catalog edits and cache misses,
%never on a match path and never on the per-write fast path below.
petta_catalog_row(Row) :-
    petta_catalog_clause(Row, _).

petta_catalog_clause([Rel|Args], Ref) :-
    native_storage_module('&petta', Module),
    current_predicate(Module:'&petta'/N),
    N >= 1,
    functor(Goal, '&petta', N),
    Goal =.. ['&petta', Rel|Args],
    clause(Module:Goal, true, Ref).

%The write-path cache. The checker runs on every '&petta' write, and the
%uncached lookup walks current_predicate over the storage arities, which
%cost register-op +2,302 inferences and made its samples drift as the
%bench's own writes created new arities [measured 2026-08-20: 42,632 to
%44,934..46,707]. One first-arg-indexed row per head fixes both. A hit
%carries the catalog clause's reference and revalidates with erased/1, so
%removing a kind or vocabulary row self-heals on the next lookup with no
%hook in the removal path; a miss is cached as a negative row, which the
%write funnel retracts when a row for that head lands. Cache writes inside
%a transaction roll back with the catalog writes they mirror, so the two
%cannot part ways.
:- dynamic petta_kind_cache/3.    %Head, Spec | none, ref(Ref) | none
:- dynamic petta_vocab_cache/3.   %Vocab, Values | none, ref(Ref) | none
:- dynamic petta_annotations_cache/2. %Ctx, Algebra
:- dynamic petta_algebra_descriptor_cache/8.
%Name, Combine, Extend, Zero, One, Laws, Carrier, Requires
:- dynamic petta_dispatch_value_cache/4. %Function, Axis, Value | none, ref(Ref) | none

%A compiled call can ask four dispatch axes on every recursive step. Walking
%the variadic catalog storage for each question makes the loop proportional
%to the size of the whole catalog. This cache keeps &petta authoritative: the
%value carries the exact override or default clause reference that supplied
%it, mutation callbacks forget affected keys, and a transaction rollback or
%source withdrawal self-heals through the erased-reference check.
petta_dispatch_value(Function, Axis, Value) :-
    (   petta_dispatch_value_cache(Function, Axis, Cached, Validity)
    ->  (   Validity = ref(Ref)
        ->  (   petta_catalog_ref_erased(Ref)
            ->  retractall(petta_dispatch_value_cache(Function, Axis, _, _)),
                petta_dispatch_value_fresh(Function, Axis, Value)
            ;   Value = Cached
            )
        ;   fail
        )
    ;   petta_dispatch_value_fresh(Function, Axis, Value)
    ).

petta_dispatch_value_fresh(Function, Axis, Value) :-
    (   petta_catalog_clause(['dispatch-policy', Function, Axis, Fresh], Ref)
    ->  assertz(petta_dispatch_value_cache(Function, Axis, Fresh, ref(Ref))),
        Value = Fresh
    ;   petta_catalog_clause(['dispatch-default', Axis, Fresh], Ref)
    ->  assertz(petta_dispatch_value_cache(Function, Axis, Fresh, ref(Ref))),
        Value = Fresh
    ;   assertz(petta_dispatch_value_cache(Function, Axis, none, none)),
        fail
    ).

petta_dispatch_cache_forget(Function, Axis) :-
    retractall(petta_dispatch_value_cache(Function, Axis, _, _)).

petta_dispatch_default_cache_forget(Axis) :-
    retractall(petta_dispatch_value_cache(_, Axis, _, _)).

petta_kind_spec(Head, Spec) :-
    (   petta_kind_cache(Head, Spec0, Validity)
    ->  (   Validity = ref(Ref)
        ->  (   petta_catalog_ref_erased(Ref)
            ->  retractall(petta_kind_cache(Head, _, _)),
                petta_kind_spec_fresh(Head, Spec)
            ;   Spec = Spec0
            )
        ;   fail
        )
    ;   petta_kind_spec_fresh(Head, Spec)
    ).

%A reference whose clause is gone, by property or by the reference itself
%having been collected, either way the cached row is stale.
petta_catalog_ref_erased(Ref) :-
    catch(clause_property(Ref, erased), _, true).

petta_kind_spec_fresh(Head, Spec) :-
    (   petta_catalog_clause([kind, Head|Fresh], Ref)
    ->  assertz(petta_kind_cache(Head, Fresh, ref(Ref))),
        Spec = Fresh
    ;   assertz(petta_kind_cache(Head, none, none)),
        fail
    ).

petta_vocabulary_values(Vocab, Values) :-
    (   petta_vocab_cache(Vocab, Values0, Validity)
    ->  (   Validity = ref(Ref)
        ->  (   petta_catalog_ref_erased(Ref)
            ->  retractall(petta_vocab_cache(Vocab, _, _)),
                petta_vocabulary_values_fresh(Vocab, Values)
            ;   Values = Values0
            )
        ;   fail
        )
    ;   petta_vocabulary_values_fresh(Vocab, Values)
    ).

petta_vocabulary_values_fresh(Vocab, Values) :-
    (   petta_catalog_clause([vocabulary, Vocab|Fresh], Ref)
    ->  assertz(petta_vocab_cache(Vocab, Fresh, ref(Ref))),
        Values = Fresh
    ;   assertz(petta_vocab_cache(Vocab, none, none)),
        fail
    ).

%One value's membership, the question every consulting site asks.
petta_vocabulary_value(Vocab, Value) :-
    petta_vocabulary_values(Vocab, Values),
    memberchk(Value, Values).

%The positional walk. Position counts declaration arguments from 1, the way
%the refusal prints them; the Expected a refusal carries is the argspec as
%declared, so the message shows the row's own words.
petta_check_positions([], [], _, _) :- !.
petta_check_positions([], [Spec|Rest], Position, Term) :-
    !,
    (   forall(member(S, [Spec|Rest]), petta_spec_omittable(S))
    ->  true
    ;   petta_declaration_refused(Term, Position, Spec)
    ).
petta_check_positions([_|_], [], Position, Term) :-
    !,
    petta_declaration_refused(Term, Position, 'no further argument').
petta_check_positions(Args, [[rest, Spec]], Position, Term) :-
    !,
    petta_check_rest(Args, Spec, Position, Term).
petta_check_positions([Arg|Args], [[optional, Spec]|Rest], Position, Term) :-
    !,
    petta_check_value(Arg, Spec, Position, Term),
    Next is Position + 1,
    petta_check_positions(Args, Rest, Next, Term).
petta_check_positions([Arg|Args], [Spec|Rest], Position, Term) :-
    petta_check_value(Arg, Spec, Position, Term),
    Next is Position + 1,
    petta_check_positions(Args, Rest, Next, Term).

petta_check_rest([], _, _, _).
petta_check_rest([Arg|Args], Spec, Position, Term) :-
    petta_check_value(Arg, Spec, Position, Term),
    Next is Position + 1,
    petta_check_rest(Args, Spec, Next, Term).

petta_spec_omittable([optional, _]).
petta_spec_omittable([rest, _]).

petta_check_value(Arg, symbol, Position, Term) :-
    !,
    (   atom(Arg) -> true ; petta_declaration_refused(Term, Position, symbol) ).
petta_check_value(Arg, integer, Position, Term) :-
    !,
    (   integer(Arg) -> true ; petta_declaration_refused(Term, Position, integer) ).
petta_check_value(_, pattern, _, _) :- !.
petta_check_value(_, term, _, _) :- !.
petta_check_value(Arg, ['one-of', Vocab], Position, Term) :-
    !,
    (   atom(Arg),
        petta_vocabulary_values(Vocab, Values),
        memberchk(Arg, Values)
    ->  true
    ;   petta_declaration_refused(Term, Position, ['one-of', Vocab])
    ).
petta_check_value(_, Spec, Position, Term) :-
    petta_declaration_refused(Term, Position, Spec).

%kind and claim rows carry meaning past their shape, and the checker owns
%their language, so their adds get the deeper walk: a kind's argspecs must
%be well-formed with optional confined to the tail and rest final, and a
%claim must name a declared vocabulary and one of its values. Everything
%else was already covered by the positional walk.
petta_check_catalog_semantics(kind, [KindHead|Spec], Term) :-
    !,
    (   petta_kind_spec(KindHead, _)
    ->  petta_declaration_refused(Term, 1,
                                  'one kind row per head; remove the old row first')
    ;   true
    ),
    petta_check_argspecs(Spec, 2, Term),
    %A head already routed by shape keeps routable: redeclaring its kind
    %(remove, then add) with a spec the route cannot dispatch would leave a
    %standing routed-by-shape row over an unroutable shape, so the unfit
    %spec is refused here rather than discovered as dead routing.
    (   petta_routed_head(KindHead, Key)
    ->  petta_check_route_fit(Key, Spec, Term)
    ;   true
    ).
petta_check_catalog_semantics('routed-by-shape', [Head|KeyArgs], Term) :-
    !,
    (   KeyArgs == []
    ->  Key = context
    ;   KeyArgs = [Key]
    ),
    (   petta_kind_spec(Head, Spec)
    ->  petta_check_route_fit(Key, Spec, Term)
    ;   petta_declaration_refused(Term, 1,
                                  'a kind row for the routed head, declared first')
    ).
petta_check_catalog_semantics(vocabulary, [Name|_], Term) :-
    !,
    (   petta_vocabulary_values(Name, _)
    ->  petta_declaration_refused(Term, 1,
                                  'one vocabulary row per name; remove the old row first')
    ;   true
    ).
petta_check_catalog_semantics(policy, [Axis|_], Term) :-
    !,
    (   petta_catalog_row([policy, Axis, _, _])
    ->  petta_declaration_refused(Term, 1,
                                  'one policy row per axis; remove the old row first')
    ;   true
    ).
petta_check_catalog_semantics(claim, [Vocab, Value|_], Term) :-
    !,
    (   petta_vocabulary_values(Vocab, Values)
    ->  (   memberchk(Value, Values)
        ->  true
        ;   petta_declaration_refused(Term, 2, 'a value of the vocabulary')
        )
    ;   petta_declaration_refused(Term, 1, 'a declared vocabulary')
    ).
petta_check_catalog_semantics(algebra,
                              [Name, Combine, Extend, Zero, One,
                               Laws, Carrier, Requires],
                              Term) :-
    !,
    (   petta_catalog_row([algebra, Name|_])
    ->  petta_declaration_refused(
            Term, 1, 'one algebra row per name; remove the old row first')
    ;   true
    ),
    petta_algebra_list_field(Laws, laws, Term, 6),
    petta_algebra_carrier_field(Carrier, Term),
    petta_algebra_list_field(Requires, requires, Term, 8),
    petta_check_algebra_laws(Name, Combine, Extend, Zero, One,
                             Laws, Carrier, Term).
petta_check_catalog_semantics(annotations, [Ctx, Algebra|CapabilityArgs], Term) :-
    !,
    petta_declared_algebra_requirements(Algebra, Required, Term),
    petta_annotation_capabilities(CapabilityArgs, Capabilities, Term),
    (   member(Requirement, Required),
        \+ memberchk(Requirement, Capabilities)
    ->  petta_algebra_requirement_refusal(Ctx, Algebra, Requirement)
    ;   true
    ).
petta_check_catalog_semantics('dispatch-default', [Axis, Value], Term) :-
    !,
    petta_check_dispatch_value(Axis, Value, Term),
    (   petta_catalog_row(['dispatch-default', Axis, _])
    ->  petta_declaration_refused(Term, 1,
                                  'one default per dispatch axis; remove the old row first')
    ;   true
    ).
petta_check_catalog_semantics('dispatch-policy', [Function, Axis, Value], Term) :-
    !,
    petta_check_dispatch_value(Axis, Value, Term),
    (   petta_catalog_row(['dispatch-policy', Function, Axis, _])
    ->  petta_declaration_refused(Term, 2,
                                  'one override per function and dispatch axis; remove the old row first')
    ;   true
    ).
%A standing query is a PROMISE about the watched context, so it is checked
%against what that context declares it can deliver, here at the catalog
%door every '&petta' write already passes rather than at one host's
%subscribe method. (subscription ...) is the reflection atom every
%subscription writes before it activates and (on ...) is a declared
%reaction, and both hear a context only through its change events, so a
%context with no (events ...) capability refuses both, naming what is
%missing. One authority, one door, every host: a MeTTa program adding the
%atom by hand is refused exactly as the Python surface is
%[tested: test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses].
petta_check_catalog_semantics(events, [Ctx|_], _) :-
    !,
    (   atom(Ctx), \+ petta_events_declared(Ctx)
    ->  assertz(petta_events_declared(Ctx))
    ;   true
    ).
petta_check_catalog_semantics(subscription, [Ctx|_], _) :-
    !,
    petta_require_events(Ctx, 'be subscribed to').
petta_check_catalog_semantics(on, [Ctx|_], _) :-
    !,
    petta_require_events(Ctx, 'carry a reaction').
petta_check_catalog_semantics(_, _, _).

petta_declared_algebra_requirements(Algebra, Required, _) :-
    petta_catalog_row([algebra, Algebra, _, _, _, _, _, _,
                       [requires|Required]]),
    !.
petta_declared_algebra_requirements(_, _, Term) :-
    petta_declaration_refused(Term, 2, 'a declared algebra').

petta_algebra_list_field([Head|Values], Head, _, _) :-
    atom(Head),
    maplist(atom, Values),
    !.
petta_algebra_list_field(_, Head, Term, Position) :-
    petta_declaration_refused(Term, Position, [Head, '... symbols']).

petta_algebra_carrier_field([carrier|Values], Term) :-
    !,
    (   maplist(ground, Values)
    ->  true
    ;   petta_declaration_refused(Term, 7, [carrier, '... ground atoms'])
    ).
petta_algebra_carrier_field(_, Term) :-
    petta_declaration_refused(Term, 7, [carrier, '... atoms']).

%A public law is a certificate, not a planner hint. User rows therefore name
%only this vocabulary and supply a finite carrier for every equation; shipped
%rows are trusted data presets whose laws are proved by their source modules.
petta_algebra_equational_law('combine-associative').
petta_algebra_equational_law('combine-commutative').
petta_algebra_equational_law('extend-associative').
petta_algebra_equational_law('extend-commutative').
petta_algebra_equational_law('left-distributive').
petta_algebra_equational_law('right-distributive').
petta_algebra_equational_law('combine-idempotent').
petta_algebra_equational_law('combine-zero-identity').
petta_algebra_equational_law('extend-one-identity').
petta_algebra_equational_law('extend-zero-annihilates').

petta_algebra_known_law(contraction).
petta_algebra_known_law(Law) :- petta_algebra_equational_law(Law).

petta_check_algebra_laws(Name, Combine, Extend, Zero, One,
                         [laws|Laws], [carrier|Carrier], Term) :-
    (   member(Unknown, Laws),
        \+ petta_algebra_known_law(Unknown)
    ->  throw(error(petta_algebra_law_unknown(Name, Unknown), none))
    ;   true
    ),
    findall(Law, ( member(Law, Laws),
                   petta_algebra_equational_law(Law) ), Equational),
    (   Equational == []
    ->  true
    ;   Carrier == [],
        \+ petta_catalog_preset(Term)
    ->  throw(error(petta_algebra_law_uncheckable(Name, Equational,
                                                  finite_carrier_required),
                    none))
    ;   Carrier == []
    ->  true
    ;   petta_check_algebra_closure(Name, Combine, Extend, Carrier),
        forall(member(Law, Equational),
               petta_check_algebra_law(Name, Combine, Extend, Zero, One,
                                       Carrier, Law))
    ).

petta_check_algebra_closure(Name, Combine, Extend, Carrier) :-
    % policy-inventory-exempt: mechanism-internal; reason=Combine and Extend are the algebra row's own two declared operation names rather than a closed value set; evidence=engine/spaces.pl:petta_check_algebra_laws/8
    forall(( member(Operation, [Combine, Extend]),
             member(A, Carrier), member(B, Carrier) ),
           ( petta_apply_algebra_operation(Name, Operation, A, B, Result),
             (   memberchk(Result, Carrier)
             ->  true
             ;   throw(error(petta_algebra_carrier_not_closed(
                                 Name, Operation, A, B, Result), none))
             ) )).

petta_algebra_apply(Name, Operation, A, B, Result) :-
    petta_apply_algebra_operation(Name, Operation, A, B, Result).

petta_check_algebra_law(Name, Combine, _, _, _, Carrier,
                        'combine-associative') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( petta_algebra_apply(Name, Combine, A, B, AB),
             petta_algebra_apply(Name, Combine, AB, C, Left),
             petta_algebra_apply(Name, Combine, B, C, BC),
             petta_algebra_apply(Name, Combine, A, BC, Right),
             petta_require_algebra_equal(Name, 'combine-associative',
                                         [A,B,C], Left, Right) )).
petta_check_algebra_law(Name, Combine, _, _, _, Carrier,
                        'combine-commutative') :- !,
    forall(( member(A, Carrier), member(B, Carrier) ),
           ( petta_algebra_apply(Name, Combine, A, B, Left),
             petta_algebra_apply(Name, Combine, B, A, Right),
             petta_require_algebra_equal(Name, 'combine-commutative',
                                         [A,B], Left, Right) )).
petta_check_algebra_law(Name, _, Extend, _, _, Carrier,
                        'extend-associative') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( petta_algebra_apply(Name, Extend, A, B, AB),
             petta_algebra_apply(Name, Extend, AB, C, Left),
             petta_algebra_apply(Name, Extend, B, C, BC),
             petta_algebra_apply(Name, Extend, A, BC, Right),
             petta_require_algebra_equal(Name, 'extend-associative',
                                         [A,B,C], Left, Right) )).
petta_check_algebra_law(Name, _, Extend, _, _, Carrier,
                        'extend-commutative') :- !,
    forall(( member(A, Carrier), member(B, Carrier) ),
           ( petta_algebra_apply(Name, Extend, A, B, Left),
             petta_algebra_apply(Name, Extend, B, A, Right),
             petta_require_algebra_equal(Name, 'extend-commutative',
                                         [A,B], Left, Right) )).
petta_check_algebra_law(Name, Combine, Extend, _, _, Carrier,
                        'left-distributive') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( petta_algebra_apply(Name, Combine, B, C, BC),
             petta_algebra_apply(Name, Extend, A, BC, Left),
             petta_algebra_apply(Name, Extend, A, B, AB),
             petta_algebra_apply(Name, Extend, A, C, AC),
             petta_algebra_apply(Name, Combine, AB, AC, Right),
             petta_require_algebra_equal(Name, 'left-distributive',
                                         [A,B,C], Left, Right) )).
petta_check_algebra_law(Name, Combine, Extend, _, _, Carrier,
                        'right-distributive') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( petta_algebra_apply(Name, Combine, A, B, AB),
             petta_algebra_apply(Name, Extend, AB, C, Left),
             petta_algebra_apply(Name, Extend, A, C, AC),
             petta_algebra_apply(Name, Extend, B, C, BC),
             petta_algebra_apply(Name, Combine, AC, BC, Right),
             petta_require_algebra_equal(Name, 'right-distributive',
                                         [A,B,C], Left, Right) )).
petta_check_algebra_law(Name, Combine, _, _, _, Carrier,
                        'combine-idempotent') :- !,
    forall(member(A, Carrier),
           ( petta_algebra_apply(Name, Combine, A, A, Result),
             petta_require_algebra_equal(Name, 'combine-idempotent',
                                         [A], Result, A) )).
petta_check_algebra_law(Name, Combine, _, Zero, _, Carrier,
                        'combine-zero-identity') :- !,
    petta_check_algebra_identity(Name, Combine, Zero, Carrier,
                                 'combine-zero-identity').
petta_check_algebra_law(Name, _, Extend, _, One, Carrier,
                        'extend-one-identity') :- !,
    petta_check_algebra_identity(Name, Extend, One, Carrier,
                                 'extend-one-identity').
petta_check_algebra_law(Name, _, Extend, Zero, _, Carrier,
                        'extend-zero-annihilates') :- !,
    forall(member(A, Carrier),
           ( petta_algebra_apply(Name, Extend, Zero, A, Left),
             petta_require_algebra_equal(Name, 'extend-zero-annihilates',
                                         [Zero,A], Left, Zero),
             petta_algebra_apply(Name, Extend, A, Zero, Right),
             petta_require_algebra_equal(Name, 'extend-zero-annihilates',
                                         [A,Zero], Right, Zero) )).

petta_check_algebra_identity(Name, Operation, Identity, Carrier, Law) :-
    forall(member(A, Carrier),
           ( petta_algebra_apply(Name, Operation, Identity, A, Left),
             petta_require_algebra_equal(Name, Law, [Identity,A], Left, A),
             petta_algebra_apply(Name, Operation, A, Identity, Right),
             petta_require_algebra_equal(Name, Law, [A,Identity], Right, A) )).

petta_require_algebra_equal(_, _, _, Left, Right) :- Left == Right, !.
petta_require_algebra_equal(Name, Law, Inputs, Left, Right) :-
    throw(error(petta_algebra_law_violation(Name, Law, Inputs, Left, Right),
                none)).

petta_annotation_capabilities([], [], _) :- !.
petta_annotation_capabilities([[capabilities|Capabilities]], Capabilities, Term) :-
    !,
    (   maplist(atom, Capabilities)
    ->  true
    ;   petta_declaration_refused(Term, 3, [capabilities, '... symbols'])
    ).
petta_annotation_capabilities(_, _, Term) :-
    petta_declaration_refused(Term, 3, [capabilities, '... symbols']).

petta_algebra_requirement_refusal(Ctx, amplitude, Requirement) :-
    !,
    throw(error(petta_amplitude_fragment_refused(Ctx, Requirement), none)).
petta_algebra_requirement_refusal(Ctx, Algebra, Requirement) :-
    throw(error(petta_algebra_requirement_missing(Ctx, Algebra, Requirement),
                none)).

petta_check_dispatch_value(Axis, Value, Term) :-
    (   dispatch_axis_vocabulary(Axis, Vocabulary)
    ->  (   petta_vocabulary_value(Vocabulary, Value)
        ->  true
        ;   petta_declaration_refused(Term, 3,
                                      ['one-of', Vocabulary])
        )
    ;   petta_declaration_refused(Term, 2, 'a declared dispatch axis')
    ).

dispatch_axis_vocabulary('MismatchEnum', 'MismatchEnum').
dispatch_axis_vocabulary('NoMatchEnum', 'NoMatchEnum').
dispatch_axis_vocabulary('EvaluationOrderEnum', 'EvaluationOrderEnum').
dispatch_axis_vocabulary('FunctionResultEnum', 'FunctionResultEnum').
dispatch_axis_vocabulary('ClauseFailedEnum', 'ClauseFailedEnum').
dispatch_axis_vocabulary('OutOfClausesEnum', 'OutOfClausesEnum').

petta_check_argspecs([], _, _).
petta_check_argspecs([Spec|Rest], Position, Term) :-
    petta_check_argspec_form(Spec, Position, Term),
    (   Spec = [rest, _], Rest \== []
    ->  petta_declaration_refused(Term, Position, 'rest only in final position')
    ;   Spec = [optional, _], Rest = [NextSpec|_], \+ petta_spec_omittable(NextSpec)
    ->  petta_declaration_refused(Term, Position, 'optional only in the tail')
    ;   true
    ),
    Next is Position + 1,
    petta_check_argspecs(Rest, Next, Term).

petta_check_argspec_form(symbol, _, _) :- !.
petta_check_argspec_form(integer, _, _) :- !.
petta_check_argspec_form(pattern, _, _) :- !.
petta_check_argspec_form(term, _, _) :- !.
petta_check_argspec_form(['one-of', Vocab], Position, Term) :-
    !,
    (   atom(Vocab),
        petta_vocabulary_values(Vocab, _)
    ->  true
    ;   petta_declaration_refused(Term, Position,
                                  'a vocabulary declared before the kind that names it')
    ).
petta_check_argspec_form([optional, Spec], Position, Term) :-
    !,
    petta_check_argspec_form(Spec, Position, Term).
petta_check_argspec_form([rest, Spec], Position, Term) :-
    !,
    petta_check_argspec_form(Spec, Position, Term).
petta_check_argspec_form(_, Position, Term) :-
    petta_declaration_refused(Term, Position, 'an argspec').

petta_declaration_refused(Term, Position, Expected) :-
    throw(error(petta_declaration_malformed(Term, Position, Expected), none)).

%%%% Materialized shape-route dispatch %%%%
%
%(routed-by-shape Head [Key]) in the catalog makes (Head ...) declarations
%route by shape through metta.pl's one algorithm: specificity over adorned
%entries, coherence among the maximal ones. The materializer compiles the
%head's kind row into the exact petta_shape_fact/4 and
%petta_shape_declared/2 clauses the router dispatches on, one fact clause
%per stored arity with omitted trailing optionals padded to none, and one
%guard clause probing those arities, so consulting a route costs what the
%hand-written clauses cost, indexed clause dispatch, and the catalog pays
%at its own writes: every add or removal of a kind or routing row lands in
%the notes above and rebuilds that head's clauses from the rows then
%standing. The shipped handles, on-error and merge dispatch is built by
%this same walk from the presets below, which is what makes a third-party
%routed kind and a shipped one the same thing.
petta_materialize_routes :-
    forall(petta_routed_head(Head, _), petta_materialize_route(Head)).

petta_routed_head(Head, Key) :-
    petta_catalog_row(['routed-by-shape', Head|KeyArgs]),
    (   KeyArgs == []
    ->  Key = context
    ;   KeyArgs = [Key]
    ).

petta_materialize_route(Head) :-
    \+ atom(Head),
    !,
    petta_materialize_routes.
petta_materialize_route(Head) :-
    retractall(petta_shape_fact(Head, _, _, _)),
    retractall(petta_shape_declared(Head, _)),
    (   petta_routed_head(Head, Key),
        petta_kind_spec(Head, Spec),
        petta_route_shape(Key, Spec, PayloadSpecs)
    ->  forall(petta_payload_slice(PayloadSpecs, Stored, Payload),
               petta_assert_route_fact(Key, Head, Stored, Payload)),
        petta_assert_route_guard(Key, Head, PayloadSpecs)
    ;   true
    ).

%How a kind row reads as a route: a context-keyed route is (head ctx-symbol
%entry-pattern payload...), a global one is (head entry-pattern payload...),
%and the payload may not carry rest, whose open arity nothing could probe.
petta_route_shape(context, [symbol, pattern|PayloadSpecs], PayloadSpecs) :-
    \+ memberchk([rest, _], PayloadSpecs).
petta_route_shape(global, [pattern|PayloadSpecs], PayloadSpecs) :-
    \+ memberchk([rest, _], PayloadSpecs).

petta_check_route_fit(Key, Spec, Term) :-
    (   petta_route_shape(Key, Spec, _)
    ->  true
    ;   petta_declaration_refused(Term, 1,
            'a kind row the route can dispatch: (symbol pattern payload...) \c
             under the context key, (pattern payload...) under global, \c
             payload without rest')
    ).

%Stored and consumed payload pairs, one per legal arity: mandatory specs
%are always stored, and the first omitted trailing optional pads every
%remaining consumed position with none, which is the padding the handles
%consumers have always read for an entry that declared no determinism.
petta_payload_slice([], [], []).
petta_payload_slice([_Spec|Specs], [V|Stored], [V|Payload]) :-
    petta_payload_slice(Specs, Stored, Payload).
petta_payload_slice([[optional, _]|Specs], [], [none|Padding]) :-
    petta_payload_padding(Specs, Padding).

petta_payload_padding([], []).
petta_payload_padding([_|Specs], [none|Padding]) :-
    petta_payload_padding(Specs, Padding).

petta_assert_route_fact(context, Head, Stored, Payload) :-
    assertz((petta_shape_fact(Head, Ctx, Entry, Payload) :-
                 petta_contract_fact([Head, Ctx, Entry|Stored]))).
petta_assert_route_fact(global, Head, Stored, Payload) :-
    assertz((petta_shape_fact(Head, global, Entry, Payload) :-
                 petta_contract_fact([Head, Entry|Stored]))).

%The guard probes the smallest stored arity first, the common case (an
%entry declaring no trailing optionals), each probe deterministic the way
%the hand-written guards were.
petta_assert_route_guard(Key, Head, PayloadSpecs) :-
    findall(N,
            ( petta_payload_slice(PayloadSpecs, Stored, _),
              length(Stored, N) ),
            Ns),
    sort(0, @<, Ns, Arities),
    petta_route_probes(Key, Head, Module, Ctx, Arities, Probes),
    petta_probe_chain(Probes, Chain),
    assertz((petta_shape_declared(Head, Ctx) :-
                 petta_contract_storage(Module),
                 Chain)).

%A global route's guard leaves Ctx free on purpose: petta_shape_declared
%(merge, _) has always matched any context, the entries being keyed by
%query shape alone.
petta_route_probes(context, Head, Module, Ctx, Arities, Probes) :-
    maplist(petta_route_probe(Head, Module, Ctx), Arities, Probes).
petta_route_probes(global, Head, Module, _Ctx, Arities, Probes) :-
    maplist(petta_route_probe_global(Head, Module), Arities, Probes).

petta_route_probe(Head, Module, Ctx, N, Module:Goal) :-
    length(Vars, N),
    Goal =.. ['&petta', Head, Ctx, _Entry|Vars].
petta_route_probe_global(Head, Module, N, Module:Goal) :-
    length(Vars, N),
    Goal =.. ['&petta', Head, _Entry|Vars].

petta_probe_chain([Probe], (Probe -> true)) :- !.
petta_probe_chain([Probe|Probes], (Probe -> true ; Chain)) :-
    petta_probe_chain(Probes, Chain).

:- multifile prolog:error_message//1.
prolog:error_message(petta_declaration_malformed(Term, Position, Expected)) -->
    { Term = [Head|_],
      swrite(Term, TermText),
      (   is_list(Expected)
      ->  swrite(Expected, ExpectedText)
      ;   ExpectedText = Expected
      ) },
    [ 'the declaration ~w does not fit its declared kind: argument ~w \c
       expects ~w. Match (kind ~w $spec) in &petta to read the declared \c
       shape, or remove the kind row and redeclare it to widen the \c
       kind'-[TermText, Position, ExpectedText, Head] ].
prolog:error_message(petta_duplicate_declaration(Space, Second, First)) -->
    { swrite(Second, SecondText), swrite(First, FirstText) },
    [ 'the declaration ~w is a duplicate in ~w; the first declaration is ~w'-
      [SecondText, Space, FirstText] ].

%The shipped catalog, as data. Every row becomes an ordinary '&petta' atom
%when the directive below runs, matchable and removable like any other.
%Vocabularies come first; (kind kind ...) enters while no kind row exists
%to check it; every later row is validated by the self-description already
%in place, claims last so their kind row checks them. The value sets are
%exactly what an engine consultation site or generated binding surface acts
%on today, strict by design: a value no consumer acts on would pass the
%checker only to sit silently inert, the failure mode this catalog exists to
%make loud.
petta_catalog_preset([vocabulary, fidelity, 'Exact', 'Partial', 'Sound', 'Refuse']).
petta_catalog_preset([vocabulary, determinism, det, semidet, nondet]).
petta_catalog_preset([vocabulary, 'numeric-type', 'Number', 'BigInt']).
petta_catalog_preset([vocabulary, 'on-error-mode', keep, empty, abort]).
petta_catalog_preset([vocabulary, 'answer-policy', depth, fair, 'best-first']).
petta_catalog_preset([vocabulary, semiring, bool, bag, set, ranked, prob, prov]).
petta_catalog_preset([vocabulary, 'source-kind', linear, repeated, peek]).
petta_catalog_preset([vocabulary, world, 'closed-world', 'open-world']).
petta_catalog_preset([vocabulary, atomicity,
                      transactional, 'atomic-single', 'best-effort']).
petta_catalog_preset([vocabulary, 'memo-strategy', wtinylfu, lru]).
petta_catalog_preset([vocabulary, 'memo-aggregate', none, min, max, sum, count]).
petta_catalog_preset([vocabulary, 'save-format', metta, fast]).
petta_catalog_preset([vocabulary, 'cache-mode', unchecked]).
petta_catalog_preset([vocabulary, 'effect-class', immutable]).
petta_catalog_preset([vocabulary, 'op-kind', det, many, raw_det, raw_many]).
petta_catalog_preset([vocabulary, 'subscription-edge', add, remove, both]).
%What a context promises about the change events it emits. The three
%delivery words are messaging's own, at-most-once, at-least-once and the
%exactly-once rung, spelled per-write-exactly here because the unit is one
%write into one space rather than one message; ordering is the second axis
%because a channel may deliver every write and still deliver them out of
%order. A context that promises neither declares no (events ...) row and
%is refused a subscription instead of serving one that silently drops
%writes [source: Eugster, Felber, Guerraoui and Kermarrec, The Many Faces
%of Publish/Subscribe, ACM Computing Surveys 35(2), 2003, whose space,
%time and synchronization decoupling are the dimensions a declaration
%here is about].
petta_catalog_preset([vocabulary, delivery,
                      'at-most-once', 'at-least-once', 'per-write-exactly']).
petta_catalog_preset([vocabulary, 'event-order', ordered, unordered]).
%Which reaction fires first when several match one write. This is the
%conflict-resolution question production systems settled in 1981, and the
%words are theirs. declaration is the order they were declared, a queue,
%which is what the engine did before this was a policy at all and is now the
%stated default; recency is the most recently declared first, a stack, which
%is CLIPS's depth strategy and its own recommended default; specificity is
%the most tests in the pattern first, OPS5's specificity criterion, which
%CLIPS spells complexity; priority reads each reaction's own declared number,
%highest first, which is CLIPS salience, CHR-rp's user-definable rule
%priorities (De Koninck, Schrijvers and Demoen, PPDP 2007) and ECLiPSe's
%twelve prioritized suspension levels; and user hands each reaction to a
%MeTTa function of the author's own that scores it, which is CHR-rp's DYNAMIC
%priority, an expression evaluated per instance rather than a constant
%[source: CLIPS Basic Programming Guide, conflict resolution strategies;
%Brownston et al., Programming Expert Systems in OPS5, 1985].
%
%OPS5's other criterion, recency of the matched working-memory elements, has
%nothing to discriminate here and is deliberately absent: every reaction in
%this conflict set was triggered by the SAME write, so their time tags are
%equal by construction. What varies between them is when they were declared
%and how specific they are.
petta_catalog_preset([vocabulary, 'agenda-policy',
                      declaration, recency, specificity, priority, user]).
petta_catalog_preset([vocabulary, volatility, volatile, stable, immutable]).
petta_catalog_preset([vocabulary, 'route-key', context, global]).
petta_catalog_preset([vocabulary, 'space-capability', file, process, network]).
petta_catalog_preset([vocabulary, 'MismatchEnum',
                      'MismatchOriginal', 'MismatchError', 'MismatchFail']).
petta_catalog_preset([vocabulary, 'NoMatchEnum',
                      'NoMatchOriginal', 'NoMatchFail', 'NoMatchError']).
petta_catalog_preset([vocabulary, 'EvaluationOrderEnum',
                      'OrderClause', 'OrderFittest']).
petta_catalog_preset([vocabulary, 'FunctionResultEnum',
                      'Nondeterministic', 'Deterministic']).
petta_catalog_preset([vocabulary, 'ClauseFailedEnum',
                      'ClauseFailNonDet', 'ClauseFailDet']).
petta_catalog_preset([vocabulary, 'OutOfClausesEnum',
                      'FailureOriginal', 'FailureEmpty', 'FailureError']).
petta_catalog_preset([kind, kind, symbol, [rest, term]]).
petta_catalog_preset([kind, 'routed-by-shape', symbol,
                      [optional, ['one-of', 'route-key']]]).
petta_catalog_preset([kind, vocabulary, symbol, [rest, symbol]]).
petta_catalog_preset([kind, claim, symbol, symbol, [rest, symbol]]).
petta_catalog_preset([kind, policy, symbol, symbol, term]).
petta_catalog_preset([kind, handles, symbol, pattern, ['one-of', fidelity],
                      [optional, ['one-of', determinism]]]).
petta_catalog_preset([kind, 'on-error', symbol, pattern,
                      ['one-of', 'on-error-mode']]).
petta_catalog_preset([kind, merge, pattern, ['one-of', 'answer-policy']]).
petta_catalog_preset([kind, annotations, symbol, symbol,
                      [optional, term]]).
petta_catalog_preset([kind, algebra, symbol, symbol, symbol, term, term,
                      term, term, term]).
petta_catalog_preset([kind, source, symbol, ['one-of', 'source-kind']]).
petta_catalog_preset([kind, context, symbol, ['one-of', world]]).
petta_catalog_preset([kind, admits, symbol, term]).
petta_catalog_preset([kind, capacity, symbol, integer]).
petta_catalog_preset([kind, writes, symbol, ['one-of', atomicity]]).
petta_catalog_preset([kind, events, symbol, ['one-of', delivery],
                      [optional, ['one-of', 'event-order']]]).
petta_catalog_preset([kind, emits, symbol, ['one-of', 'answer-policy']]).
petta_catalog_preset([kind, cache, symbol, ['one-of', 'cache-mode']]).
petta_catalog_preset([kind, effect, symbol, ['one-of', 'effect-class']]).
petta_catalog_preset([kind, inverse, symbol]).
petta_catalog_preset([kind, op, symbol, integer, ['one-of', 'op-kind']]).
petta_catalog_preset([kind, on, symbol, pattern, term, [optional, integer]]).
petta_catalog_preset([kind, agenda, symbol, ['one-of', 'agenda-policy'],
                      [optional, symbol]]).
petta_catalog_preset([kind, tabled, symbol, symbol, integer]).
petta_catalog_preset([kind, defined, symbol, symbol]).
petta_catalog_preset([kind, subscription, symbol, pattern,
                      ['one-of', 'subscription-edge']]).
petta_catalog_preset([kind, inherits, term, term]).
petta_catalog_preset([kind, restricted, term]).
petta_catalog_preset([kind, grants, term,
                      ['one-of', 'space-capability']]).
petta_catalog_preset([kind, parametric, term]).
petta_catalog_preset([kind, 'dispatch-default', symbol, term]).
petta_catalog_preset([kind, 'dispatch-policy', symbol, symbol, term]).
petta_catalog_preset(['routed-by-shape', handles]).
petta_catalog_preset(['routed-by-shape', 'on-error']).
petta_catalog_preset(['routed-by-shape', merge, global]).
%One row per engine decision axis. The inventory lane joins these live rows
%to the implementation seam named for each knob; keeping the defaults here
%means a program can read the same table the gate checks.
petta_catalog_preset([policy, dispatch, 'dispatch-policy', 'MismatchOriginal']).
petta_catalog_preset([policy, order, 'dispatch-policy', 'OrderClause']).
petta_catalog_preset([policy, merge, merge, depth]).
petta_catalog_preset([policy, agenda, reduce, 'depth-first']).
petta_catalog_preset([policy, equality, '==', 'structural-identity']).
petta_catalog_preset([policy, errors, 'on-error', abort]).
petta_catalog_preset([policy, world, context, 'closed-world']).
petta_catalog_preset([policy, algebra, annotations, bool]).
petta_catalog_preset([policy, storage, 'config-memoize', wtinylfu]).
petta_catalog_preset([policy, typing, 'typing-rule', strict]).
petta_catalog_preset([policy, fidelity, handles, 'Exact']).
petta_catalog_preset([policy, 'source-kind', source, repeated]).
petta_catalog_preset([policy, 'transaction-mode', transaction, 'all-answers']).
petta_catalog_preset([policy, atomicity, writes, transactional]).
petta_catalog_preset([policy, delivery, events, 'per-write-exactly']).
petta_catalog_preset([policy, 'reaction-order', agenda, declaration]).
petta_catalog_preset([policy, 'save-format', save, metta]).
petta_catalog_preset([policy, volatility, volatility, stable]).
petta_catalog_preset([policy, determinism, determinism, nondet]).
petta_catalog_preset([claim, semiring, ranked, ordered]).
petta_catalog_preset([claim, semiring, prob, ordered]).
petta_catalog_preset([algebra, bool, max, '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, bag, '+', '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, set, max, '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'combine-idempotent', 'extend-associative',
                       'left-distributive', 'right-distributive',
                       'combine-zero-identity', 'extend-one-identity',
                       'extend-zero-annihilates', contraction],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, ranked, max, '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, prob, '+', '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, prov, plus, times, zero, one,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, budget, min, '+', infinity, 0,
                      [laws, 'combine-associative', 'combine-commutative',
                       'combine-idempotent', 'extend-associative',
                       'combine-zero-identity', 'extend-one-identity'],
                      [carrier], [requires]]).
petta_catalog_preset([algebra, amplitude, 'amplitude-add',
                      'amplitude-multiply', [complex, 0, 0], [complex, 1, 0],
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'extend-commutative',
                       'left-distributive', 'right-distributive',
                       'combine-zero-identity', 'extend-one-identity',
                       'extend-zero-annihilates', contraction],
                      [carrier], [requires, finite, contractive, staged]]).
%The requirements above are the executable amplitude fence [tested:
%an_amplitude_context_without_the_whole_fragment_is_refused_by_name;
%commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c].
petta_catalog_preset(['dispatch-default', 'MismatchEnum', 'MismatchOriginal']).
petta_catalog_preset(['dispatch-default', 'NoMatchEnum', 'NoMatchOriginal']).
petta_catalog_preset(['dispatch-default', 'EvaluationOrderEnum', 'OrderClause']).
petta_catalog_preset(['dispatch-default', 'FunctionResultEnum', 'Nondeterministic']).
petta_catalog_preset(['dispatch-default', 'ClauseFailedEnum', 'ClauseFailNonDet']).
petta_catalog_preset(['dispatch-default', 'OutOfClausesEnum', 'FailureOriginal']).

%Presets land only where their subject has no row yet, which makes the
%directive reconsult-idempotent (a re-consulted engine meets its own rows
%and the duplicate refusal must not fire) and keeps a program's own
%remove-then-redeclare widening standing across an engine reload.
petta_catalog_preset_missing([kind, Head|_]) :-
    !,
    \+ petta_kind_spec(Head, _).
petta_catalog_preset_missing([vocabulary, Name|_]) :-
    !,
    \+ petta_vocabulary_values(Name, _).
petta_catalog_preset_missing(['routed-by-shape', Head|_]) :-
    !,
    \+ petta_routed_head(Head, _).
petta_catalog_preset_missing(Atom) :-
    \+ petta_catalog_row(Atom).

:- forall(( petta_catalog_preset(Atom), petta_catalog_preset_missing(Atom) ),
          add_sexp('&petta', Atom, _)).

%The inverse of add_sexp_in/4, written here beside it for the same reason
%metta_module_space/2 is written beside space_module/2: the mapping is
%injective, so the inverse is a function rather than a search, and keeping the
%pair together is what stops one of them drifting.
%
%The caller is a RELOAD. A source load records a clause reference for
%everything it asserts, atoms and compiled clauses and registrations alike,
%and taking a file's atoms back out has to go through metta_remove_atom/3,
%which takes an atom rather than a reference. So this is how the reload tells
%an atom's reference from the rest: it FAILS on any reference that is not a
%stored atom's, and on an erased one, and it answers the SPACE as well as the
%atom because a file's !(add-atom &elsewhere ...) is recorded by the load that
%ran it and belongs back in &elsewhere rather than in the space being reloaded
%[tested: spaces_storage_modules:a_stored_atoms_reference_decodes_to_its_atom].
%
%The module comes from clause_property/2 and not from the head clause/3 hands
%back, because that head is qualified only when the clause's module differs
%from the CALLER's: read from the engine it arrives bare, so stripping it named
%the engine's own module and every atom looked like something else
%[measured 2026-08-19: the withdrawal reported 0 atoms while removing them].
stored_atom_of_ref(Ref, Space, Atom) :-
    catch(clause_property(Ref, predicate(Module:Name/_)), _, fail),
    native_storage_module(Space, Module),
    native_storage_functor(Space, Functor),
    catch(clause(Stored, true, Ref), _, fail),
    strip_module(Stored, _, Head),
    (   Name == '$petta_native_scalar'
    ->  Head = '$petta_native_scalar'(Atom)
    ;   Name == Functor,
        Head =.. [_, Rel|Args],
        Atom = [Rel|Args]
    ).

%The clause a native space stores an atom AS. This is the definition of that
%shape, and lib_import.pl's static-import! writes exactly this to a file so a
%large data file can be qcompiled once instead of parsed every run. The two
%used to disagree and it was invisible: the converter wrote '&self'(fact,a,1)
%into USER while native atoms live in the storage module '$petta_atoms:&self',
%so a static import loaded clauses nothing could read and reported success
%[tested: native_storage_shapes_agree,
%import_facts_land_where_the_space_reads_them].
native_atom_clause([Family|Parameters], [Rel|Args], Term) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Term =.. ['$petta_parametric_atom', Rel|Args].
native_atom_clause(Space, [Rel|Args], Term) :- !,
    Term =.. [Space, Rel | Args].
native_atom_clause(_, Atom, '$petta_native_scalar'(Atom)).

%Remove ONE atom that unifies with the requested value. Expressions and
%scalars live in different predicates, so neither erases the other.
:- dynamic remove_sexp/3.
remove_sexp(Space, Atom) :- remove_sexp(Space, Atom, _).

%The same removal, answering whether anything WAS there.
%
%ONE occurrence, because removal is multiset SUBTRACTION. This used to take
%every occurrence, and its stated reason was an invalid inference: "a MeTTa
%space is a multiset unless something forbids it, SO removal takes EVERY
%occurrence". The premise argues for the opposite conclusion, and the tree it
%described was a multiset on ADD and a set on REMOVE, so three adds of (dup 1)
%gave count 3 and one removal gave count 0. The arbiter reads the premise the
%other way: "remove-atom must behave as multiset subtraction on the
%reader-visible view of &self", and its own model "removes the first exact
%occurrence and returns unit"
%[source: LeaTTa MettaHyperonFullTests/Properties.lean:107,
%MettaHyperonFull/Minimal/Stdlib.lean:2223, and wiki/Mechanization-Ledger.md
%row "Represented removal consumes the first exact occurrence", which pins
%(one two one) minus (one) as (two one) executably].
%
%This engine had already decided it everywhere else. The seam declares
%metta_foreign_remove/3 as "remove one" (EXTENDING.md), and drop_fun_meta/4
%takes "one variant-equivalent retained equation" at a time
%(engine/translator.pl:115). The native store was the one holdout.
%
%retract/1 under double negation, which makes the answer and the removal one
%lookup instead of two. retractall/1 succeeds whether or not it matched, so
%the answer had to come from a separate clause/2 probe in front of it, and
%that pair was also a check-then-act race: retract/1 reports what it did, and
%SWI adjusts each thread's entry generation so "if multiple threads use
%once(retract(Term)), no two threads will retract the same clause". Exactly
%ONE clause goes because the double negation takes retract/1's first solution
%and never backtracks into it, and it has to: under the logical update view
%"retract/1 succeeds for all clauses that match Term when the predicate was
%called", so a retract left open on backtracking would drain the lot
%[source: SWI-Prolog 10.1 Reference Manual, retract/1].
%
%Double negation rather than a copy because the bindings must NOT escape.
%That is the engine's own rule for the compiled half, "retraction must not
%bind the caller's variables" (engine/translator.pl:115), and the language's:
%remove-atom answers unit, so (remove-atom &self (pair $x)) is a request, not
%a query, and $x is no more bound afterwards than before. It is also the
%cheaper of the two isolations. Measured 2026-08-19 over 20,000 removals, min
%of three: 1.0001 inferences per removal against the probe-and-retractall
%shape's 2.0001, and against 2.0001 for the copy_term spelling
%[measured 2026-08-19, ai-tmp/spaces-p1/rmcost.pl].
%
%Answering truthfully at all is worth it because the engine already disagreed
%with ITSELF. Removing an EQUATION answers false when nothing matched, forty
%lines up, and a foreign provider fills metta_foreign_remove/3's Removed
%argument honestly, so a MeTTa program branching on (remove-atom $space $atom)
%was correct against two of the three and wrong against the third, with
%nothing in its text saying which it would get
%[tested: spaces_removal_answers_unit_for_success_and_an_error_for_absence,
%test_remove_atom_removes_one_occurrence_not_all].
remove_sexp('&petta', [Rel|Args], Removed) :- !,
    (   native_storage_module_ready('&petta', Module)
    ->  Term =.. ['&petta', Rel|Args],
        native_retract_one(Module:Term, Removed),
        (   Removed == true
        ->  petta_catalog_note_removed([Rel|Args])
        ;   true
        )
    ;   Removed = false
    ).
remove_sexp([Family|Parameters], [Rel|Args], Removed) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    (   native_storage_module_ready(Space, Module)
    ->  Term =.. ['$petta_parametric_atom', Rel|Args],
        native_retract_one(Module:Term, Removed)
    ;   Removed = false
    ).
remove_sexp(Space, [Rel|Args], Removed) :- !,
    (   native_storage_module_ready(Space, Module)
    ->  Term =.. [Space, Rel | Args],
        native_retract_one(Module:Term, Removed)
    ;   Removed = false
    ).
remove_sexp(Space, Atom, Removed) :-
    (   native_storage_module_ready(Space, Module)
    ->  native_retract_one(Module:'$petta_native_scalar'(Atom), Removed)
    ;   Removed = false
    ).

native_retract_one(Head, Removed) :-
    ( \+ \+ retract(Head) -> Removed = true ; Removed = false ).

%Which module a space's compiled clauses live in. EVERY registered space gets
%one, &self included. Atomic names retain their prefix mapping; parametric
%names use the same canonical identity encoding as storage, under a distinct
%prefix. Both mappings are total over their respective name classes and
%injective.
%
%&self used to compile into the module the ENGINE itself resolves in, and an
%equation asserted there does not shadow a predicate of that name, it REPLACES
%it for the rest of the process. Two shipped examples did exactly that
%[measured 2026-08-19: examples/functions/invertpeanoplus.metta took
%user:plus/3 from imported_from(system) to a local definition, after which
%plus(1,2,X) failed instead of answering 3; examples/libraries/
%minimal_metta.metta did the same to user:rule/3]. Every gate stayed green
%through both, because nothing that ran afterwards in those processes called
%either predicate. tests/prolog/engine_integrity.pl is the check that would
%not have let it stand, and it is a GATE at zero findings.
%
%A goal unresolved in a space's module still reaches the engine, the builtins
%and the libraries through the base chain below, so nothing has to be
%published for a compiled clause to run
%[tested: spaces_execution_modules].
%DETERMINISTIC, and the if-then-else is what makes it so. Asserting the known
%spaces as facts of space_module/2 itself in front of the rule reads one
%inference cheaper, and costs far more than it saves: the rule's head unifies
%with every space too, so a known one succeeds holding a CHOICE POINT, and
%backtracking into it re-enters the rule and takes the mutex. Measured
%2026-08-19 on that shape: eval-arith 172,009 -> 237,980 inferences, op-raw
%178,011 -> 253,976, op-encoded 214,011 -> 289,969.
space_module(Space, Module) :-
    (   metta_exec_module_known(Space, Module)
    ->  true
    ;   metta_exec_module_name(Space, Module),
        with_mutex('$petta_metta_exec',
                   ensure_metta_exec_module_locked(Space, Module))
    ).

metta_exec_module_name(Space, Module) :-
    atom(Space), !,
    metta_exec_module_prefix(Prefix),
    atom_concat(Prefix, Space, Module).
metta_exec_module_name(Space, Module) :-
    space_parametric(Space),
    !,
    space_canonical_atom(Space, Encoded),
    atom_concat('$petta_param_exec:', Encoded, Module).

:- dynamic metta_exec_module_known/2.
:- dynamic space_parent/2.
:- dynamic metta_exec_module_parent/2.
:- dynamic space_restricted/2.
:- dynamic space_grant/2.
:- dynamic restricted_profile_known/2.

%The chain, and why each link is where it is.
%
%  system  ->  the ENGINE's module  ->  '$petta_exec:&self'  ->  every other
%                                                                space
%
%&self's module inherits the engine's, so every builtin, every library
%predicate and every function imported from Prolog still resolves from a
%compiled MeTTa clause. Every other space inherits &self's, which is the
%sharing rule the engine already states for functions and types ("&self is the
%shared space", fun_here_in/2) and which named spaces used to get by accident:
%&self WAS `user`, and SWI gives an implicitly created module the base `user`.
%
%The base is SET rather than left to the name. SWI gives an implicitly created
%module whose name starts with `$` the base `system` and every other name the
%base `user`, and a module created by a :- module(...) FILE gets `user`
%whatever its name; neither rule is stated in the manual, and the first one
%alone makes '$petta_exec:&self' unable to see the engine at all
%[measured 2026-08-19: '$petta_exec:&self':'add-atom'/3 raised
%existence_error on boot until the base was set explicitly]
%[tested: spaces_execution_modules:the_chain_is_engine_then_self_then_space].
metta_exec_module_base(Space, Base) :-
    (   Space == '&self'
    ->  petta_engine_module(Base)
    ;   space_restricted(Space, Grants)
    ->  ensure_restricted_profile(Grants, Base)
    ;   space_parent(Space, Parent)
    ->  space_module(Parent, Base)
    ;   space_module('&self', Base)
    ).

%set_module/1 is idempotent and works on a module that already holds clauses
%[measured 2026-08-19: import_module went [user] -> ['$petta_exec:&self'] in
%place and the module's own predicates still answered], so recovering a cache
%fact a rolled-back transaction erased costs one redundant set and no repair,
%the same shape ensure_native_storage_module_locked/2 uses above.
%asserta, so the facts stay in front of the rule above and a known space never
%reaches it. Re-entered when a rolled-back transaction erased the fact and left
%the module based: set_module/1 is idempotent, so the repair is one redundant
%set rather than a special case, which is the shape
%ensure_native_storage_module_locked/2 uses.
ensure_metta_exec_module_locked(Space, Module) :-
    metta_exec_module_known(Space, Module), !.
ensure_metta_exec_module_locked(Space, Module) :-
    metta_exec_module_base(Space, Base),
    set_module(Module:base(Base)),
    assertz(metta_exec_module_known(Space, Module)),
    protect_engine_emitted(Module).

%Bind the engine's own emitted goals into this module so a MeTTa equation
%cannot take one over. See metta_engine_emitted/1 (engine/translator.pl) for what
%that means and why an import rather than a guard.
%
%The export half is what keeps it quiet: import/1 warns when the source module
%does not export the name, and the engine's module has no export list at all.
%current_predicate/1 guards the order: this runs for &self's module at LOAD,
%before engine/duals.pl is consulted, so the one predicate that file emits is not
%there yet and the initialization below sweeps it in afterwards.
%A NAME ADDED TO THE EMITTED SET AFTER A SPACE EXISTS is the case that has to
%be safe, and it is the disease Logtalk's module critique names: "any update
%that strictly adds new exported predicates has the potential to break existing
%applications". A space that already defines the new name is a genuine
%collision, and SWI reports it -- import/1 raises permission_error(import_into,
%...) with the context `name clash` and leaves the space's own definition
%standing. Left at that, the addition is settled by which import happened
%first: the space keeps its function, the engine's emitted goal is captured in
%that space's compiled bodies, and nothing says so. So it is REFUSED here
%instead, in the vocabulary of the two parties that collided
%[tested: test_adding_an_engine_export_changes_no_spaces_answers].
protect_engine_emitted(Module) :-
    petta_engine_module(Engine),
    forall(( metta_engine_emitted(PI), current_predicate(Engine:PI) ),
           ( Engine:export(PI), Module:import(Engine:PI) )).

refuse_engine_export_collision(Engine, Module, Culprit) :-
    ( Culprit = _:Name/Arity -> true ; Culprit = Name/Arity ),
    ( metta_module_space(Module, Space) -> true ; Space = Module ),
    InputArity is Arity - 1,
    throw(error(petta_engine_export_collision(Name, InputArity, Space, Engine),
                context(protect_engine_emitted/1,
                        'a name the engine emits collides with one this space \c
                         already defines'))).

prolog:error_message(petta_engine_export_collision(Name, Arity, Space, Engine)) -->
    [ '~w with ~w arguments is a name ~w now compiles into function bodies, \c
       and ~w already defines a function of that name.'-[Name, Arity, Engine, Space], nl,
      '  the two cannot both have it: importing the engine\'s would capture \c
       every call ~w makes to its own function, and leaving ~w\'s would capture \c
       the engine\'s goal in this space\'s compiled clauses. Rename one of \c
       them.'-[Space, Space] ].

%Every module that already exists, which at boot is &self's. Called from
%engine/metta.pl's own initialization rather than from one here, and BEFORE the
%prelude compiles: an initialization/1 goal runs after the file it appears in
%finishes, so one here would run before engine/metta.pl had defined half the
%names above, and initialization goals do not reliably order against each
%other either [source: engine/metta.pl's own note on that].
%The guard lives HERE and not in protect_engine_emitted/1 above, because this
%is the only sweep that can collide. A module being BUILT is empty, and the
%re-entry that repairs a rolled-back transaction re-imports names it already
%holds, which SWI accepts; a name that a space already defines can only arrive
%by the emitted set GROWING after that space had functions, which is this
%sweep. It is also where the cost would be felt: one catch per space-module
%build moved five benchmarks, and one per re-sweep moves none
%[measured 2026-08-21: a catch per emitted name costs alpha-unique,
%annotated-relation and file-load 52 inferences each, an inlined one 26, one per
%space build 5 to 11 on file-load, handle-round-trip and save-load-metta, and
%this leaves all 34 at their pins].
%
%SWI's own error carries both parties, so nothing is lost by catching once: it
%names the predicate indicator that was refused and the module it was refused
%into.
protect_metta_exec_modules :-
    petta_engine_module(Engine),
    catch(forall(metta_exec_module_known(_, Module),
                 protect_engine_emitted(Module)),
          error(permission_error(import_into(Target), procedure, Culprit), _),
          refuse_engine_export_collision(Engine, Target, Culprit)).

%The inverse of space_module/2. It used to be written out by hand in four
%places, three of them outside this file, each as
%`Module == user -> Space = '&self' ; Space = Module`
%[source: ai-phase11-module-survey.md section 1.3]. The exact forward-map
%cache replaces all four and supports both atomic and canonical parametric
%names. It FAILS on a module that is not a space's, because every caller has
%one in hand and a silent pass-through would answer a module name where a
%space name was asked for
%[tested: spaces_execution_modules:the_module_to_space_map_is_the_inverse].
metta_module_space(Module, Space) :-
    metta_exec_module_known(Space, Module).

restricted_core_module('$petta_restricted:core').

space_capability(file).
space_capability(process).
space_capability(network).

%A capability is attached to the written operation, not to a Prolog helper it
%happens to call. Names absent from this table are part of the curated compute
%surface; raw Prolog goals take the sandbox path below.
space_operation_capability('exists_file', file).
space_operation_capability('import!', file).
space_operation_capability(library, file).
space_operation_capability('readln!', process).
space_operation_capability('read-form!', process).
space_operation_capability('sread-command', process).
space_operation_capability(argv, process).
space_operation_capability('new-space', process).
space_operation_capability(evalc, process).
space_operation_capability(metta, process).
space_operation_capability(callPredicate, process).
space_operation_capability(assertaPredicate, process).
space_operation_capability(assertzPredicate, process).
space_operation_capability(retractPredicate, process).
space_operation_capability(import_prolog_function, process).
space_operation_capability(check_prolog_function_names, process).
space_operation_capability(import_prolog_functions, process).
space_operation_capability(import_prolog_functions_from_file, file).
space_operation_capability(import_prolog_functions_from_file_pred, file).
space_operation_capability(import_prolog_functions_from_module, process).
space_operation_capability(import_prolog_functions_from_module_pred, process).
space_operation_capability(register_metta_library_path, file).
space_operation_capability('git-import!', network).

restricted_profile_name([], Core) :- !, restricted_core_module(Core).
restricted_profile_name(Grants, Module) :-
    atomic_list_concat(Grants, '+', Suffix),
    atom_concat('$petta_restricted:', Suffix, Module).

ensure_restricted_profile(Grants, Module) :-
    restricted_profile_known(Grants, Module),
    !.
ensure_restricted_profile(Grants, Module) :-
    restricted_profile_name(Grants, Module),
    ensure_restricted_core,
    (   Grants == []
    ->  true
    ;   restricted_core_module(Core),
        set_module(Module:base(Core)),
        forall(member(Capability, Grants),
               publish_restricted_capability(Module, Capability))
    ),
    assertz(restricted_profile_known(Grants, Module)).

ensure_restricted_core :-
    restricted_profile_known([], _),
    !.
ensure_restricted_core :-
    pin_restricted_dispatch_names,
    restricted_core_module(Core),
    set_module(Core:base(none)),
    forall(restricted_core_predicate(PI), publish_restricted_pi(Core, PI)),
    publish_restricted_denials(Core),
    assertz(restricted_profile_known([], Core)).

%The reducer's existing scoped-name index decides whether a call must retain
%the current execution module. Capability-bearing names are module-sensitive
%for the same reason as a user definition: a restricted profile may publish
%or withhold them. Pinning only those names preserves reduce/3's ordinary
%base-tier path while a computed restricted call reaches the curated module's
%grant or refusal [tested:
%test_a_restricted_space_cannot_reach_what_its_base_does_not_publish;
%commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
pin_restricted_dispatch_names :-
    forall(space_operation_capability(Name, _),
           (   fun_scoped(Name)
           ->  true
           ;   assertz(fun_scoped(Name))
           )).

restricted_dispatch_name(Name) :-
    restricted_profile_known([], _),
    space_operation_capability(Name, _).

%A denied operation is a local refusal in the curated core, not an import of
%the engine operation. A grant profile imports the permitted operation into
%the nearer profile module and therefore shadows this stub. The wrapper is
%built for each callable arity from the same capability table that builds the
%grant profiles, so literal and computed calls cannot disagree about the
%boundary [tested:
%test_a_restricted_space_cannot_reach_what_its_base_does_not_publish;
%commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
publish_restricted_denials(Core) :-
    forall(( space_operation_capability(Name, Capability),
             arity(Name, Arity),
             petta_engine_module(Engine),
             current_predicate(Engine:Name/Arity) ),
           publish_restricted_denial(Core, Engine, Name, Arity, Capability)).

publish_restricted_denial(Core, Engine, Name, Arity, Capability) :-
    functor(Head, Name, Arity),
    assertz(Core:(Head :-
        Engine:metta_require_current_capability(Name, Capability),
        Engine:Head)).

%Locally defined engine helpers are needed by compiled safe calls. Registered
%builtins imported from libraries are included separately. Capability-bearing
%names are withheld and published only by their grant profile.
restricted_core_predicate(Name/Arity) :-
    petta_engine_module(Engine),
    current_predicate(Engine:Name/Arity),
    functor(Head, Name, Arity),
    predicate_property(Engine:Head, defined),
    \+ predicate_property(Engine:Head, imported_from(_)),
    \+ space_operation_capability(Name, _).
restricted_core_predicate(Name/Arity) :-
    builtin_fun(Name),
    \+ space_operation_capability(Name, _),
    arity(Name, Arity),
    petta_engine_module(Engine),
    current_predicate(Engine:Name/Arity).

publish_restricted_capability(Module, Capability) :-
    forall(( space_operation_capability(Name, Capability),
             arity(Name, Arity),
             petta_engine_module(Engine),
             current_predicate(Engine:Name/Arity) ),
           publish_restricted_pi(Module, Name/Arity)).

publish_restricted_pi(Module, PI) :-
    petta_engine_module(Engine),
    PI = Name/Arity,
    functor(Head, Name, Arity),
    (   predicate_property(Engine:Head, imported_from(system))
    ->  true
    ;   Engine:export(PI),
        Module:import(Engine:PI)
    ).

%A parametric space is an entity identifier, not an expression to execute:
%one finite, ground list headed by a symbol. Validate the complete shape
%before asserting its registry fact or asking either module cache, so a bad
%name cannot reserve persistent SWI module state. Repeating the same creation
%is idempotent and never duplicates its reflected contract atom.
metta_declare_parametric_space(Space) :-
    metta_require_parametric_space_name(Space),
    with_mutex('$petta_metta_exec',
               metta_declare_parametric_space_locked(Space)).

metta_require_parametric_space_name(Space) :-
    (   acyclic_term(Space)
    ->  true
    ;   throw(error(type_error(acyclic_term, Space),
                    context('new-space',
                            'a parametric space name must be finite')))
    ),
    (   ground(Space)
    ->  true
    ;   throw(error(instantiation_error,
                    context('new-space',
                            'a parametric space name must be ground')))
    ),
    (   Space = [Family|_], atom(Family)
    ->  true
    ;   throw(error(domain_error(parametric_space_name, Space),
                    context('new-space',
                            'a parametric space name is a nonempty expression \c
                             headed by a symbol')))
    ).

metta_declare_parametric_space_locked(Space) :-
    (   space_parametric(Space)
    ->  true
    ;   transaction(( assertz(space_parametric(Space)),
                      metta_add_atom('&petta', [parametric, Space], _),
                      ensure_native_storage_module(Space, _),
                      space_module(Space, _) ))
    ).

metta_declare_restricted_space(Space, Grants0) :-
    metta_require_space_name('new-space', Space),
    must_be(list, Grants0),
    maplist(metta_require_space_capability, Grants0),
    sort(Grants0, Grants),
    with_mutex('$petta_metta_exec',
               metta_declare_restricted_space_locked(Space, Grants)).

metta_require_space_capability(Capability) :-
    (   space_capability(Capability)
    ->  true
    ;   throw(error(domain_error(space_capability, Capability),
                    context('new-space',
                            'capability must be file, process, or network')))
    ).

metta_declare_restricted_space_locked(Space, Grants) :-
    (   space_restricted(Space, Standing)
    ->  (   Standing == Grants
        ->  true
        ;   throw(error(petta_space_restriction_conflict(Space, Standing,
                                                          Grants), none))
        )
    ;   space_parent(Space, Parent)
    ->  throw(error(petta_space_model_conflict(Space, inherits(Parent),
                                                restricted(Grants)), none))
    ;   space_parent_child_used(Space)
    ->  throw(error(petta_space_restriction_after_use(Space), none))
    ;   ensure_restricted_profile(Grants, _),
        transaction(( assertz(space_restricted(Space, Grants)),
                      forall(member(Capability, Grants),
                             assertz(space_grant(Space, Capability))),
                      metta_add_atom('&petta', [restricted, Space], _),
                      forall(member(Capability, Grants),
                             metta_add_atom('&petta',
                                            [grants, Space, Capability], _)),
                      ensure_native_storage_module(Space, _),
                      space_module(Space, _) ))
    ).

metta_restricted_exec_module(Module, Space) :-
    metta_exec_module_known(Space, Module),
    space_restricted(Space, _).

metta_require_current_capability(Operation, Capability) :-
    current_metta_module(Module),
    (   metta_restricted_exec_module(Module, Space)
    ->  (   space_grant(Space, Capability)
        ->  true
        ;   throw(error(petta_space_capability_required(Space, Operation,
                                                         Capability), none))
        )
    ;   true
    ).

metta_require_space_update_capability(Operation, Target) :-
    current_metta_module(Module),
    (   metta_restricted_exec_module(Module, Space),
        Target \== Space
    ->  metta_require_current_capability(Operation, process)
    ;   true
    ).

metta_require_safe_goal(Goal) :-
    current_metta_module(Module),
    (   metta_restricted_exec_module(Module, _)
    ->  metta_require_restricted_safe_goal(Goal, Module)
    ;   true
    ).

metta_require_restricted_safe_goal(Goal, Module) :-
    callable(Goal),
    functor(Goal, Operation, _),
    (   raw_goal_capability(Operation, Capability)
    ->  metta_require_current_capability(Operation, Capability)
    ;   catch(sandbox:safe_goal(Module:Goal), _, fail)
    ->  true
    ;   metta_require_current_capability(Operation, process)
    ).

raw_goal_capability(Operation, Capability) :-
    space_operation_capability(Operation, Capability),
    !.
raw_goal_capability(open, file).
raw_goal_capability(close, file).
raw_goal_capability(read, file).
raw_goal_capability(write, file).
raw_goal_capability(delete_file, file).
raw_goal_capability(rename_file, file).
raw_goal_capability(make_directory, file).
raw_goal_capability(process_create, process).
raw_goal_capability(process_wait, process).
raw_goal_capability(shell, process).
raw_goal_capability(www_open_url, network).
raw_goal_capability(http_open, network).

restricted_callable_name(F) :- builtin_fun(F).

%Declare the one parent a space reads and executes through. The ordering is
%part of the contract: an identical declaration is idempotent, a conflicting
%one names both parents, a cycle is diagnosed before the less-specific
%already-used refusal, and only a fresh child reaches the transaction that
%lands the index, reflection atom and execution-module base together.
%[tested: test_a_child_space_reads_through_its_parent_and_writes_locally;
% commit=755330de329ece49eddcfb7d6db3061c3350a0ca]
metta_declare_space_parent(Child, Parent) :-
    metta_require_space_name('new-space', Child),
    metta_require_space_name('new-space', Parent),
    with_mutex('$petta_metta_exec',
               metta_declare_space_parent_locked(Child, Parent)).

metta_require_space_name(_, Space) :-
    petta_space_name(Space),
    !.
metta_require_space_name(Operation, Space) :-
    throw(error(type_error('SpaceType', Space),
                context(Operation, 'an inherited-space endpoint must be a space'))).

metta_declare_space_parent_locked(Child, Parent) :-
    (   space_parent(Child, Standing)
    ->  (   Standing == Parent
        ->  true
        ;   throw(error(petta_space_parent_conflict(Child, Standing, Parent),
                        none))
        )
    ;   space_restricted(Child, Grants)
    ->  throw(error(petta_space_model_conflict(Child, restricted(Grants),
                                                inherits(Parent)), none))
    ;   space_parent_cycle(Child, Parent)
    ->  throw(error(petta_space_parent_cycle(Child, Parent), none))
    ;   space_parent_child_used(Child)
    ->  throw(error(petta_space_parent_after_use(Child), none))
    ;   transaction(( assertz(space_parent(Child, Parent)),
                      metta_add_atom('&petta', [inherits, Child, Parent], _),
                      ensure_native_storage_module(Child, _),
                      space_module(Child, ChildModule),
                      space_module(Parent, ParentModule),
                      assertz(metta_exec_module_parent(ChildModule,
                                                       ParentModule)) ))
    ).

space_parent_cycle(Child, Parent) :-
    Child == Parent,
    !.
space_parent_cycle(Child, Parent) :-
    space_parent_reaches(Parent, Child, []).

space_parent_reaches(Space, Target, Seen) :-
    \+ memberchk(Space, Seen),
    space_parent(Space, Parent),
    (   Parent == Target
    ->  true
    ;   space_parent_reaches(Parent, Target, [Space|Seen])
    ).

space_parent_child_used(Child) :- metta_exec_module_known(Child, _), !.
space_parent_child_used(Child) :- native_storage_module_cache(Child, _), !.
space_parent_child_used(Child) :- metta_foreign_space(Child).

%Child first, then each ancestor. The seen list is an invariant guard against
%a corrupt or externally asserted relation; declarations refuse such cycles
%before they can enter this index.
space_read_chain(Space, Each) :-
    space_read_chain_(Space, [], Each).

space_read_chain_(Space, Seen, Each) :-
    \+ memberchk(Space, Seen),
    (   Each = Space
    ;   space_parent(Space, Parent),
        space_read_chain_(Parent, [Space|Seen], Each)
    ).

metta_assert_space_releasable(Space) :-
    (   space_parent(Child, Space)
    ->  throw(error(petta_space_parent_live_child(Space, Child), none))
    ;   true
    ).

%A released name is allowed to acquire a different parent in its next life.
%Clear while the standing base is still known, then remove the relationship
%and its reflected atom transactionally and forget the module mapping so the
%next space_module/2 call sets the persistent SWI module's new base.
metta_release_space(Space) :-
    with_mutex('$petta_metta_exec',
               ( metta_assert_space_releasable(Space),
                 metta_host_clear_space(Space),
                 transaction(( metta_forget_space_parent(Space),
                               metta_forget_space_restriction(Space),
                               metta_forget_parametric_space(Space),
                               metta_forget_exec_module_parent(Space),
                               retractall(metta_exec_module_known(Space, _)),
                               retractall(native_storage_module_cache(Space, _)) ))
               )).

metta_forget_exec_module_parent(Space) :-
    (   metta_exec_module_known(Space, Module)
    ->  retractall(metta_exec_module_parent(Module, _))
    ;   true
    ).

metta_forget_space_parent(Child) :-
    (   retract(space_parent(Child, Parent))
    ->  metta_remove_atom('&petta', [inherits, Child, Parent], _)
    ;   true
    ).

metta_forget_space_restriction(Space) :-
    (   retract(space_restricted(Space, Grants))
    ->  forall(member(Capability, Grants),
               ( retractall(space_grant(Space, Capability)),
                 metta_remove_atom('&petta',
                                   [grants, Space, Capability], _) )),
        metta_remove_atom('&petta', [restricted, Space], _)
    ;   true
    ).

metta_forget_parametric_space(Space) :-
    (   space_parametric(Space)
    ->  metta_remove_atom('&petta', [parametric, Space], _),
        retractall(space_parametric(Space))
    ;   true
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_space_parent_conflict(Child, Standing, Requested)) -->
    [ '~w already inherits from ~w, so it cannot also inherit from ~w; a \c
       space has one parent fixed before first use'-[Child, Standing,
                                                     Requested] ].
prolog:error_message(petta_space_parent_cycle(Child, Parent)) -->
    [ 'making ~w inherit from ~w would create an inheritance cycle; space \c
       reads and execution bases must form an acyclic parent chain'-[Child,
                                                                      Parent] ].
prolog:error_message(petta_space_parent_after_use(Child)) -->
    [ '~w has already been created, written, executed, or registered; declare \c
       its parent with (new-space ~w (inherits <parent>)) before first use'-[
       Child, Child] ].
prolog:error_message(petta_space_parent_live_child(Parent, Child)) -->
    [ '~w cannot be dropped while live child ~w inherits from it; drop the \c
       child first so its relationship cannot follow a recycled parent name'-[
       Parent, Child] ].
prolog:error_message(petta_space_restriction_conflict(Space, Standing,
                                                       Requested)) -->
    [ '~w is already restricted with grants ~q, so it cannot be redeclared \c
       with grants ~q; restriction is fixed at creation'-[Space, Standing,
                                                           Requested] ].
prolog:error_message(petta_space_restriction_after_use(Space)) -->
    [ '~w has already been created, written, executed, or registered; declare \c
       it restricted with new-space before first use'-[Space] ].
prolog:error_message(petta_space_model_conflict(Space, Standing, Requested)) -->
    [ '~w already has space model ~q, so it cannot also use ~q; inheritance \c
       and restriction are alternative execution bases'-[Space, Standing,
                                                           Requested] ].
prolog:error_message(petta_space_capability_required(Space, Operation,
                                                      Capability)) -->
    [ '~w cannot run ~w because its restricted base does not publish the ~w \c
       capability; grant it explicitly when the space is created'-[
       Space, Operation, Capability] ].

%&self's execution module exists from load, the way its storage module does,
%so nothing has to create it on a first write and metta_self_module/1
%(engine/metta.pl) names a module that is already based.
:- space_module('&self', _).

%Whether anything still holds a clause for a function, which decides whether
%removing an equation forgets the NAME as well. Two sources, and `user` used to
%stand for both of them at once: a space's own module, and the ENGINE's, since
%a builtin goes on meaning the builtin after a space's equation for it is
%removed.
%
%compiled_function_name/2 rather than the written name, which is the same fix
%module_owns_function/2 below already carries: `get-type` compiles to
%get_type_rule/2, so asking for a predicate called `get-type` found the
%ENGINE's get-type/2 and answered "still defined" for every space and every
%state of the rules. Removing one of two scoped get-type rules then wiped
%fun_in/2 for the name and the surviving rule stopped answering
%[tested: spaces_type_extensions:removing_one_rule_keeps_the_other_visible].
%number_of_clauses/1 before clause/3, which is the guard tracer.pl already
%carries and for the same reason: clause/3 REFUSES a predicate it cannot show,
%raising permission_error(access, private_procedure, _) rather than failing,
%and the engine's module holds plenty of those. Removing an equation for any
%system-builtin name reached one and raised out of remove-atom
%[measured 2026-08-19: with_output_to/2]. The property is true for exactly the
%predicates clause/3 accepts [source: engine/tracer.pl, metta_trace_target/1
%measured 2026-08-16].
%A BUILTIN is defined by the engine and by no equation, so no removal can
%undefine it. Without this, a space that extended an engine operation by
%writing an equation for its name took the ENGINE's operation with it when the
%equation went: the compiled-clause probe below is the only thing that was
%asked, a builtin has no compiled clause of that shape, so `fun/1` and the
%name-wide registers were retracted and `!(get-type 1)` answered
%`(get-type 1)` unreduced for the rest of the process. Removing an equation
%for `match`, `+` or any other builtin name did the same
%[tested: builtin_survives_equation_removal].
function_still_defined(F) :- builtin_fun(F), !.
function_still_defined(F) :- compiled_function_name(F, Predicate),
                             ( fun_in(Module, F) ; petta_engine_module(Module) ),
                             current_predicate(Module:Predicate/Arity),
                             functor(Head, Predicate, Arity),
                             predicate_property(Module:Head, number_of_clauses(_)),
                             clause(Module:Head, _, _),
                             !.

%Whether this module itself holds a clause for a function. Inherited clauses
%do not count: clause/3 sees user's clauses through module inheritance, and
%counting those would keep a module's claim alive on another space's strength.
module_owns_function(Module, F) :- compiled_function_name(F, Predicate),
                                   current_predicate(Module:Predicate/Arity),
                                   functor(Head, Predicate, Arity),
                                   predicate_property(Module:Head,
                                                      number_of_clauses(_)),
                                   clause(Module:Head, _, Ref),
                                   clause_property(Ref, module(Module)),
                                   !.

%The UNIT value, not true. `add-atom` is typed `(-> spaceType Atom (->))` and
%`(->)` IS the unit type, which the language also says in prose: "bind! returns
%the unit value () similar to println! or add-atom"
%[source: the language's Working with spaces].
%
%This reverses a deliberate earlier translation, recorded in
%ai-todo-fast-libraries.md F11.3 as "HE's unit result `(->)` is PeTTa's `Bool`,
%because every one of those operations answers `true`". That reasoning had the
%direction backwards: it read the type off the implementation instead of
%correcting the implementation to the type. The engine was already inconsistent
%with itself, `trace!` answering `()` beside these answering `true`, and the
%arbiter's spaces corpus disagreed on every file
%[tested: an_effectful_operation_answers_unit].
%The write itself decides whether the first argument is a space: a name that is
%not one reaches no storage module, so nothing is written and this refuses.
%Asking BEFORE the write cost an inference on every add
%[measured 2026-08-20: register-op +200], and asking after costs nothing
%because the failure branch runs only when the write did not happen. A write
%that failed for its own reasons, a foreign provider refusing one, still fails
%without an answer, which is what it did before.
'add-atom'([Family|Parameters], Term, Result) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    (   metta_add_atom(Space, Term, _)
    ->  Result = []
    ;   fail
    ).
'add-atom'(Space, Term, Result) :-
    (   atom(Space), metta_add_atom(Space, Term, _)
    ->  Result = []
    ;   petta_space_name(Space)
    ->  fail
    ;   space_argument_error('add-atom', [Space, Term], Result)
    ).

%Adding an atom is two independent decisions: WHERE it is stored, which is a
%property of the space, and WHAT the engine must do because of what the atom
%MEANS, which is a property of the atom. This predicate dispatched on storage
%first, mixing them, and three defects came out of that one shape:
%
%  - a (: f T) added to a FOREIGN space never recompiled f's call sites,
%    because the foreign clause cut before the declaration clause could run.
%    The same program answered ((+ 1 2)) in a native named space and (3) in a
%    foreign one [measured 2026-08-16].
%  - metta_add_atoms/2 had to re-derive which atoms carry work and looked only
%    for equations, so a BATCHED declaration skipped the recompile the same
%    atom performs alone: m.add(decl) answered (+ 1 2) and m.add(decl, other)
%    answered 3 [measured 2026-08-16].
%  - the Python shim re-derived it a third time and routed MORK's batch around
%    this predicate entirely, so an equation added to a space that holds rules
%    was stored inert whenever it arrived with any other atom
%    [measured 2026-08-16].
%
%So MEANING is decided first and storage second, which is the whole of the fix.
%The order is the fix: a foreign space's declaration now reaches the clause that
%recompiles, because nothing cuts in front of it any more.
%
%The tests stay in the clause HEADS rather than moving to a classifier the batch
%path could also call, and that is measured rather than tidy. This is the
%hottest write path in the engine, and routing it through
%atom_effect/2 + add_with_effect/3 cost three inferences of every twelve per
%atom, 25%, which the save-load benchmarks caught at once [measured 2026-08-16:
%12.0012 to 15.0012 inferences per add over 20,000 adds]. atoms_store_only/1
%below repeats these two tests for the batch path, and the two are held together
%by a differential rather than by sharing code: every shape is added alone and
%in a batch and the resulting state compared
%[tested: spaces_batch_is_only_a_transport].
metta_add_atom(Space, Term, true) :- Term = [=, [FAtom|W], _], !,
                                     must_be(atom, FAtom),
                                     add_equation(Space, Term, FAtom, W).
%Type declarations are a multimap because distinct arrows and distinct data
%types are meaningful. A variant-identical second row is not: every type walk
%would enumerate it again. A direct source add is idempotent and warns while
%leaving the first row in place; the public batch preflight below stays strict
%because accepting one duplicate in a batch would make that transport differ
%from its promised all-or-nothing write. Host registrations that need exclusive
%ownership use petta_py_add_strict_declaration/2 in shim.pl.
metta_add_atom(Space, Term, true) :-
    Term = [':', _, _],
    existing_duplicate_declaration(Space, Term, First),
    !,
    print_message(warning, petta_duplicate_declaration(Space, Term, First)).
% DontEvalType changes how every arrow parameter naming this type compiles,
% even when the type symbol is not itself a function. Store first so repairs
% observe the new marker, then invalidate its module-qualified support root.
metta_add_atom(Space, Term, true) :-
    Term = [':', Type, 'DontEvalType'],
    atom(Type),
    !,
    (   Space == '&self', fun(Type)
    ->  retract_prelude_declarations(Type)
    ;   true
    ),
    store_atom(Space, Term),
    space_module(Space, DeclModule),
    ( fun(Type) -> function_changed(DeclModule, Type) ; true ),
    type_marker_changed(DeclModule, Type).
%A type declaration decides how a call site compiles, most sharply for an Atom
%parameter, which is what makes a control form possible: (: f (-> Atom
%%Undefined%)) is the difference between the argument arriving evaluated and
%arriving as written. A call site compiled before the declaration landed kept
%evaluating the argument for ever, so the same call written two ways in one
%program behaved differently and nothing said why. The engine already knows how
%to recompile what a change made stale; the declaration route simply never told
%it [tested: a_late_type_declaration_repairs_its_call_sites].
metta_add_atom(Space, Term, true) :- Term = [':', FAtom, _], atom(FAtom),
                                     fun(FAtom), !,
                                     %A declaration written into &self replaces the
                                     %prelude's for the same name, the user-wins rule
                                     %evict_prelude_definition/1 documents; the
                                     %recompile below then re-reads call sites under
                                     %the user's masking.
                                     (   Space == '&self'
                                     ->  retract_prelude_declarations(FAtom)
                                     ;   true
                                     ),
                                     store_atom(Space, Term),
                                     space_module(Space, DeclModule),
                                     function_changed(DeclModule, FAtom).
metta_add_atom(Space, Term, true) :- metta_foreign_space(Space), !,
                                     foreign_write(Space, add,
                                                   metta_foreign_add(Space, Term)).
metta_add_atom(Space, Term, true) :- add_sexp(Space, Term, Ref),
                                     record_source_assertion(Ref).

existing_duplicate_declaration(Space, Term, First) :-
    \+ metta_foreign_space(Space),
    copy_term(Term, Probe),
    get_native_atom(Space, Stored),
    Stored =@= Probe,
    !,
    First = Stored.

first_variant_declaration(Term, [First|_], First) :- Term =@= First, !.
first_variant_declaration(Term, [_|Declarations], First) :-
    first_variant_declaration(Term, Declarations, First).

ensure_new_batch_declaration(Space, Term, Earlier) :-
    (   existing_duplicate_declaration(Space, Term, First)
    ->  throw(error(petta_duplicate_declaration(Space, Term, First), none))
    ;   first_variant_declaration(Term, Earlier, First)
    ->  throw(error(petta_duplicate_declaration(Space, Term, First), none))
    ;   true
    ).

batch_declarations_unique(Space, Terms) :-
    batch_declarations_unique(Space, Terms, []).

batch_declarations_unique(_, [], _).
batch_declarations_unique(Space, [Term|Terms], Earlier) :-
    (   Term = [':', _, _]
    ->  ensure_new_batch_declaration(Space, Term, Earlier),
        Next = [Term|Earlier]
    ;   Next = Earlier
    ),
    batch_declarations_unique(Space, Terms, Next).

%Whether every atom in a batch stores and does nothing else, which is the only
%kind a bulk crossing may carry. It repeats metta_add_atom/3's first two clause
%heads, and they are repeated rather than shared for the reason given there.
%The same traversal preflights otherwise-plain type declarations against both
%the space and earlier batch members. This keeps the one-crossing fast path
%without letting two declarations bypass the single-atom refusal.
%
%Written as clause heads and not as a test called per atom, which is measured:
%head unification costs no inference where a call costs one, and over a whole
%batch that is the difference between one and two per atom [measured 2026-08-16:
%8.00 back to 7.00 inferences per atom over 20,000]. Cut-then-fail so the scan
%stops at the first atom that carries work.
atoms_store_only(Space, Terms) :- atoms_store_only(Space, Terms, []).

atoms_store_only(_, [], _).
atoms_store_only(_, [[=|_]|_], _) :- !, fail.
atoms_store_only(_, [[':', _, 'DontEvalType']|_], _) :- !, fail.
atoms_store_only(_, [[':', FAtom, _]|_], _) :-
    atom(FAtom), fun(FAtom), !, fail.
atoms_store_only(Space, [Term|Terms], Earlier) :-
    Term = [':', _, _], !,
    ensure_new_batch_declaration(Space, Term, Earlier),
    atoms_store_only(Space, Terms, [Term|Earlier]).
atoms_store_only(Space, [_|Terms], Earlier) :-
    atoms_store_only(Space, Terms, Earlier).

%Where an atom goes. A foreign space's provider owns its storage entirely; a
%native space's storage is the Prolog database.
store_atom(Space, Term) :- metta_foreign_space(Space), !,
                           foreign_write(Space, add,
                                         metta_foreign_add(Space, Term)).
store_atom(Space, Term) :- add_sexp(Space, Term, Ref),
                           record_source_assertion(Ref).

%An equation is the one atom whose storage and meaning cannot be separated, so
%they are not: it compiles inside the transaction that stores it, wherever it is
%stored. Only the storage step differs between a native space and a foreign one.
%
%An equation in a foreign space used to be a silent lie: accepted, stored, and
%inert, so (only-foreign 21) answered itself where the identical shape in a
%native named space answered 42. In MeTTa a space is BOTH a data source and
%where the program lives, so accepting a rule that can never fire is the engine
%agreeing to something it will not do. A provider that holds rules declares the
%`rules` capability; one that does not is refused here, where the author can
%still act on it, rather than at the call that quietly answers itself much later
%[tested: adding_a_rule_to_a_ruleless_foreign_space_is_refused].
%
%It goes through the SAME compiler as a native equation, and the first attempt
%at this did not: it asserted one bridge clause per function that matched the
%space for (= (f Args) Body) at call time and reduced whatever came back.
%
%That is the naive reading of evaluation, and the language documents exactly why
%it falls short. Evaluating (only-a A) "can be thought of as execution of query
%(match &self (= (only-a A) $result) $result)", and then: "There is one
%difference. match produces the empty result in the second case, while the
%interpreter keeps this expression unreduced. The interpreter is performing some
%additional processing on top of such equality queries"
%[source: metta-lang.dev/docs/learn, Functions and unification].
%
%Three of those differences were live here. A body is evaluated FURTHER, so
%(= (bnest) (+ 1 (* 2 3))) raised "+: number expected, found (* 2 3)"; a
%bare-variable body must NOT be evaluated, so an Atom parameter came back
%reduced; and (if ...) evaluates only the branch it takes, so (= (loop) (loop))
%under an if would not have terminated. Every one is a rule the translator
%already implements [source: metta-lang.dev/docs/learn, Basic evaluation and
%Recursion and control].
%
%What the seam gives up by compiling at add time is an equation that appears in
%the space by some other door, MORK's own loader or an mm2-exec write: it is
%stored and inert, because nothing told the engine. That is the honest edge and
%it is narrower than a second evaluator that is wrong on every program above.
%A specialization is DERIVED: the specializer wrote it from this module's own
%equations and owns the name. An equation arriving for a derived name that is
%an ALPHA-DUPLICATE of one already stored carries nothing, and storing it a
%second time is what made a space stop reproducing itself: MeTTa.copy()
%enumerates a space and re-adds every atom into a fresh one, the clone
%re-derived the specialization while compiling the equation that triggered
%it, and the copied atom then landed on top, so a four-atom space cloned to
%five and answered its query twice [measured 2026-08-19]. The guard used to
%swallow by NAME alone, which was right while clones re-derived; with
%adoption the copied equations ARE the derived ones, and the name-only
%swallow ate every clause of a copied specialization that arrived after its
%sibling had been adopted, so a two-clause specialization cloned to one
%[measured 2026-08-20]. Only the true duplicate is swallowed now, and the
%probe runs only on derived-name adds, which are rare by construction
%[tested: a_copied_space_adopts_its_specializations_instead_of_duplicating].
add_equation(Space, Term, FAtom, _) :-
    space_module(Space, Module),
    ho_specialization(Module, _, FAtom),
    copy_term(Term, Probe),
    get_native_atom(Space, Stored),
    Stored = [=, [FAtom|_], _],
    Stored =@= Probe,
    !.
add_equation(Space, Term, FAtom, W) :-
    metta_foreign_space(Space), !,
    refuse_ruleless_equation(Space, Term),
    space_module(Space, Module),
    transaction(add_function_atom(provider, Space, Module, Term, FAtom, W)).
add_equation(Space, Term, FAtom, W) :-
    space_module(Space, Module),
    ensure_native_storage_module(Space, Storage),
    transaction(add_function_atom(Storage, Space, Module, Term, FAtom, W)).

%Where the equation itself goes. `provider` is a foreign space, whose provider
%owns its storage; anything else is a native storage module. transaction/1 wraps
%the compile either way, and rolls back only the Prolog side of it: a provider's
%write is outside the database and stays written if the translation then fails.
store_equation(provider, Space, Term) :- !, store_atom(Space, Term).
store_equation(Storage, Space, Term) :- add_sexp_in(Storage, Space, Term, Ref),
                                        record_source_assertion(Ref).

%Everything a change to FAtom leaves stale, in one place because three callers
%need exactly it: a new equation, a new declaration, and a removed equation.
%
%The MODULE is threaded rather than read, because a change hook fires outside
%the compile door's own module switch and the invalidation behind it is scoped
%to one space now: reading the ambient module here would have made a write in
%one space invalidate whichever space happened to be in force.
function_changed(Module, FAtom) :- prepare_specialization_invalidation(Module, FAtom),
                                   support_invalidate_function_change(Module, FAtom),
                                   forall(support_repair_invalidations, true),
                                   forall(metta_on_function_changed(FAtom), true).

%The removal repair is the engine's own duty, not an observer's: it used to
%ride a shim clause of the metta_on_function_removed EVENT, so an engine
%without Python in the process kept a compiled mention of a retired function
%answering as a call. Removal needs the FULL caller recompile, because a
%mention compiled as a CALL is what must flip back to data, and the
%data-direction repair (repair_stale_definitions, which registration rides
%through register_fun/1's scheduler) cannot see a call. The ARRIVAL
%direction deliberately has no twin walk here: a new function's flip is
%register_fun's scheduled repair, which defers inside an active source load
%so a rolled-back load cannot leave callers recompiled against a definition
%that never landed. Both directions and the rollback are pinned
%[tested: the_engine_recompiles_dependents_without_a_host]
%[tested: failed_late_definition_does_not_recompile_existing_callers].
function_removed(FAtom) :- support_invalidate_function(FAtom),
                           forall(support_repair_invalidations, true),
                           forall(metta_on_function_removed(FAtom), true).

%The caller has classified the atom as an equation, so the shape test that used
%to be here is gone with it.
refuse_ruleless_equation(Space, Term) :-
    (   foreign_provides(Space, rules)
    ->  true
    ;   throw(error(petta_foreign_space_holds_no_rules(Space, Term),
                    context('add-atom'/3, 'the equation would never fire')))
    ).

%A native batch containing no equations and no observer for this space can
%resolve its storage module once. Equation batches and observed writes keep
%using add-atom/3 so registration and per-atom events retain their ordinary
%behavior.
metta_add_hooks_idle(_) :-
    \+ metta_atom_hook_clause(added, _), !.
metta_add_hooks_idle(Space) :-
    findall(Ref, metta_atom_hook_clause(added, Ref), Refs),
    metta_host_add_hooks_idle(Space, Refs).

%The removal mirror, asked by the bulk clear below: nothing is listening
%when no removed-atom handler exists at all, or when a host claims the
%whole census as its own idle hooks.
metta_remove_hooks_idle(_) :-
    \+ metta_atom_hook_clause(removed, _), !.
metta_remove_hooks_idle(Space) :-
    findall(Ref, metta_atom_hook_clause(removed, Ref), Refs),
    metta_host_remove_hooks_idle(Space, Refs).

%Clear a space, whoever holds it: a Prolog foreign provider clears through
%its own seam (or refuses, loudly, when it cannot); a native space
%announces the atoms it drops through the removal funnel exactly when
%something is watching, since the two bulk doors used to disagree, add
%announcing per atom and clear announcing nothing, and then sweeps its
%storage module in one pass [tested: test_clear_announces_every_atom_it_drops].
%Tabling state dies with the space life: clause removal leaves both the
%tabled property and the answer tables standing, so a reused pooled module
%answered its NEW definition from the dead life's cache with no tabling
%declared in the new life. Untable every tabled predicate the module itself
%owns (current_predicate/1 enumeration does not cross the default-module
%chain), abolish whatever tables remain, and retract the space's
%(tabled ...) reflection facts, which describe declarations that no longer
%exist [tested: test_pool_reuse_starts_tabling_clean].
metta_host_clear_space(Space) :-
    metta_foreign_space(Space), !,
    clear_foreign_atoms(Space).
metta_host_clear_space(Space) :-
    (   metta_remove_hooks_idle(Space)
    ->  true
    ;   findall(Atom, metta_host_stored(Space, Atom), Atoms),
        forall(member(Atom, Atoms), 'remove-atom'(Space, Atom, _))
    ),
    clear_native_atoms(Space),
    space_module(Space, Module),
    metta_host_clear_tabling(Space, Module).

metta_host_clear_tabling(Space, Module) :-
    forall(( current_predicate(Module:Name/Arity),
             functor(Head, Name, Arity),
             \+ predicate_property(Module:Head, imported_from(_)),
             predicate_property(Module:Head, tabled) ),
           untable(Module:Name/Arity)),
    abolish_module_tables(Module),
    findall([tabled, Space, F, A],
            'get-atoms'('&petta', [tabled, Space, F, A]),
            Facts),
    forall(member(Fact, Facts), 'remove-atom'('&petta', Fact, _)).

%Bulk cleanup of the reflection facts describing one space: every
%(defined <Space> _) atom in &petta goes through the engine's own removal
%funnel (hooks fire per fact), in ONE host crossing; the per-fact crossing
%measured 10,000 calls and 64ms for 10,000 defines.
metta_host_clear_defined(Space) :-
    findall(F, 'get-atoms'('&petta', [defined, Space, F]), Fs),
    forall(member(F, Fs), 'remove-atom'('&petta', [defined, Space, F], _)).

%%%% The foreign seam's failure contract %%%%
%
%A declared provider that does not answer an operation is the registrant's
%bug, and it is reported with the space and the operation named. It is never
%read as "there is nothing there". Four of the five operations used to fail
%silently: a write vanished, a removal reported nothing removed, and a match
%answered the empty set while the space demonstrably held matching atoms.
%Only clear said what happened, and it said it from the Python bridge.
%
%The Python half of the same seam has always done this, refusing with the
%provider class and the operation named, and it is the half a library author
%is told to port INTO Prolog for speed
%[tested: spaces_foreign_contract].
%A space that declares NOTHING provides everything, which is what every
%provider written before the declaration existed assumed.
%
%THE TRAP, and it is worth knowing before you extend the vocabulary: the
%default stops the moment this space has ANY solution. Declaring one
%capability is declaring the complete set, so a provider adding a sixth to the
%five silently loses the five it did not restate. Python providers do not have
%to think about it, because foreign.py projects the whole set at registration
%from the protocols the provider implements
%[tested: test_a_python_providers_capabilities_reach_the_engine,
%a_partial_declaration_declares_the_whole_set].
%subscribe is the one capability no registration may claim on its own, and
%that is P12.14's whole point: the other eight are questions about what a
%provider implements, and this one is a promise about what its CONTEXT can
%deliver. A remote space implements add and remove and its contents still
%change on the server. So the (events ...) declaration decides it, whatever
%a host registered, and a context that declares nothing is refused here
%[tested: test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses].
foreign_provides(Space, Capability) :-
    (   metta_foreign_capability(Space, _)
    ->  metta_foreign_capability(Space, Capability)
    ;   true
    ),
    (   Capability == subscribe
    ->  petta_event_capability(Space, _, _)
    ;   true
    ).

%A capability the space does not provide. The provider gets to say why, if it
%has words for it: metta_foreign_refuse/2 raises, and "does not implement add"
%reads differently from "declines this add request", which is a distinction the
%Python half already draws and this one could not.
%
%The hook is expected to throw. Reaching the throw below means it did not,
%which is the engine and the provider disagreeing about what is provided.
refuse_absent_capability(Space, Capability) :-
    (   foreign_provides(Space, Capability)
    ->  true
    ;   metta_foreign_refuse(Space, Capability)
    ->  throw(error(permission_error(Capability, foreign_space, Space),
                    context(foreign_write/3,
                            'the provider declined this operation and did not \c
                             say why')))
    ;   throw(error(permission_error(Capability, foreign_space, Space),
                    context(foreign_write/3,
                            'the provider does not declare this operation')))
    ).

%A write either happened or it did not, so failure here is unambiguous and is
%an error. A read that finds nothing is an ordinary empty answer, so reads do
%not go through this.
:- meta_predicate foreign_write(+, +, 0).
foreign_write(Space, Capability, Goal) :-
    refuse_absent_capability(Space, Capability),
    %Inside a transaction the write's fate follows the declared
    %atomicity: a transactional provider enlists (one begin per
    %outermost transaction) and is committed or rolled back with it,
    %best-effort is the author's declared acceptance of a write that
    %survives a rollback, and anything else is refused loudly, because
    %a foreign write silently surviving a rolled-back transaction was
    %the wrong answer this replaces.
    (   current_transaction(_),
        petta_in_user_transaction
    ->  petta_writes(Space, Atomicity),
        (   Atomicity == transactional
        ->  petta_enlist_foreign(Space)
        ;   Atomicity == 'best-effort'
        ->  true
        ;   throw(error(petta_transaction_unsupported(Space, Atomicity),
                        none))
        )
    ;   true
    ),
    (   call(Goal)
    ->  true
    ;   throw(error(petta_foreign_operation_failed(Space, Capability),
                    context(foreign_write/3,
                            'the provider refused the write without saying why')))
    ).

%A batch is a TRANSPORT optimisation and never a semantic one: what the engine
%does for an atom on its own it must still do when the atoms arrive together.
%So only atoms that store and nothing more take a bulk crossing, and
%atom_stores_only/1 decides that rather than this predicate re-deriving it,
%which is how a batched type declaration came to skip its recompile.
%[prior art: a multi-row SQL INSERT still fires per-row triggers, JDBC's
%executeBatch runs the same statements, and Redis pipelining changes round
%trips and never commands.]
metta_add_atoms(_, []) :- !.
metta_add_atoms(Space, Terms) :-
    %A claimed hook gates the write itself, so a hooked space takes the
    %per-atom door below, where the wrapper consults the handler for every
    %atom; a pool's admission guard is one such claim, which is how a
    %batch beyond capacity meets the refusal its atoms meet arriving
    %alone. Both one-crossing clauses write behind the wrapper's back, the
    %foreign one through the provider's own bulk door and the native one
    %through add_sexp_in/4
    %[tested: a_batch_into_a_hooked_space_consults_the_handler_per_atom,
    %a_batch_beyond_capacity_is_refused_like_lone_adds].
    petta_hook_claim_idle(Space),
    atoms_store_only(Space, Terms),
    add_atoms_in_one_crossing(Space, Terms), !.
metta_add_atoms(Space, Terms) :-
    %This route may perform work for its first atom, so check the whole batch
    %before invoking any per-atom door. A duplicate later in the batch must not
    %leave the first declaration, compiled equation, or observer effect behind.
    batch_declarations_unique(Space, Terms),
    forall(member(Term, Terms), 'add-atom'(Space, Term, _)).

%A provider's own batch crossing when it has one, and the native store's
%otherwise. A provider without metta_foreign_add_many/2 fails here and gets one
%metta_foreign_add/2 per atom, which is what every provider written before this
%gets. The native path writes behind the write wrapper's back, so it is
%available only while no observer is installed; a provider's own crossing owns
%the write hooks exactly as its per-atom add does.
add_atoms_in_one_crossing(Space, Terms) :-
    metta_foreign_space(Space), !,
    refuse_absent_capability(Space, add),
    metta_foreign_add_many(Space, Terms).
add_atoms_in_one_crossing(Space, Terms) :-
    metta_add_hooks_idle(Space),
    ensure_native_storage_module(Space, Storage),
    %The bulk door checks and notes contract subjects exactly as the
    %per-atom door does, once per batch head test rather than per space
    %test per atom; the whole batch is checked before any of it lands.
    (   Space == '&petta'
    ->  forall(member(Decl, Terms),
               (   petta_declaration_check(Decl),
                   petta_note_ctx_declared(Decl)
               ))
    ;   true
    ),
    forall(member(Term, Terms),
           ( add_sexp_in(Storage, Space, Term, Ref),
             record_source_assertion(Ref) )),
    (   Space == '&petta'
    ->  forall(member(Term, Terms), petta_catalog_note_added(Term))
    ;   true
    ).

%Compile and register a dynamic equation as one database transaction. A
%translation or change-hook error therefore leaves no stored atom, function
%marker, arity, meta-clause, or executable clause behind.
%The one equation-compile spine: prelude eviction (user-wins), function
%registration, translation, clause assertion, provenance records, and the
%COMPLETE change notification. Three doors used to carry this separately,
%this file's add_function_atom and filereader.pl's two process_form
%clauses, so a cross-cutting rule had to be hooked one door at a time
%(the prelude eviction was the precedent), and one rule HAD drifted: the
%loader doors notified metta_on_function_changed but never
%invalidate_specializations, so an equation added by a string run or a
%compile-mode load left a prior specialization of the same name
%answering stale clauses. One door means the next such rule lands once
%[tested specializer:string_run_equation_invalidates_specializations].
compile_metta_equation(Module, Term, Clause, Ref) :-
    Term = [=, [F|_], _],
    (   metta_self_module(Module) -> evict_prelude_definition(F) ; true ),
    register_fun_in(Module, F),
    %Stale specializations go FIRST, before this body compiles. They are
    %clones of the PREVIOUS definition, and that is the whole content of
    %the claim; a clone this compilation creates for its own recursive
    %call belongs to the NEW definition and must survive. Invalidating
    %afterwards abolished exactly those clones while the clause naming
    %them stood, so (= (f $g) (... (f (+ 2)) ...)) compiled a generic
    %clause calling an empty predicate: the direct call answered through
    %its own specialization and a call that reached the generic clause,
    %(let $h (+ 1) (f $h)), silently answered NOTHING. Found by the
    %verify-specializations differential over examples/
    %[tested specializer:a_recursive_specialization_survives_its_compile].
    prepare_specialization_invalidation(Module, F),
    support_invalidate_function_change(Module, F),
    once(with_metta_module(Module, translate_clause(Term, RawClause))),
    petta_instrument_recursive_clause(Term, RawClause, Clause),
    assert_function_clause(Module, Clause, Ref),
    record_source_assertion(Ref),
    record_translated_from(Ref, Term, SourceRef),
    record_source_assertion(SourceRef),
    %The dependent-recompile hooks run AFTER the clause is in place, so
    %a definition that mentions F recompiles against the new one.
    forall(support_repair_invalidations, true),
    forall(metta_on_function_changed(F), true).

%A recursive equation spends the same branch-local budget that runnable
%limits own. The source tree supplies the cost because it is the stable unit:
%one fuel unit covers two reduction nodes, rounded up. That calibration is
%the LeaTTa runner's two exact boundary witnesses: factorial's three-node body
%costs two and stops at -3 under 20, while fuel-loop's five-node body costs
%three and stops at -33332 under the default 100000. A quote is data and
%contributes neither a recursive call nor a reduction node. A compiled input
%that is the translator's internal `quote` sentinel is likewise not a source
%argument; its higher-order specialization owns the runnable call, so the
%generic dispatch artifact is not charged as another recursive branch.
%[tested: test_a_stack_depth_pragma_bounds_evaluation_instead_of_overflowing].
petta_instrument_recursive_clause([=, [F|HeadArguments], Body],
                                  (Head :- Goal),
                                  (Head :- petta_fuel_step(Culprit, Cost), Goal)) :-
    length(HeadArguments, Arity),
    petta_source_calls_head(Body, F, Arity),
    \+ petta_source_has_variable_head(Body),
    Head =.. [_|Arguments],
    append(Inputs, [_Output], Arguments),
    \+ ( member(Input, Inputs), nonvar(Input), Input == quote ),
    !,
    petta_fuel_culprit(F, Inputs, Culprit),
    petta_source_reduction_count(Body, Nodes),
    Cost is max(1, (Nodes + 1) // 2).
petta_instrument_recursive_clause(_, Clause, Clause).

petta_fuel_culprit(_, [Only], Only) :- !.
petta_fuel_culprit(F, Inputs, [F|Inputs]).

petta_source_calls_head([quote, _], _, _) :- !, fail.
petta_source_calls_head([Head|Arguments], F, Arity) :-
    (   nonvar(Head), Head == F, length(Arguments, Arity)
    ->  true
    ;   member(Argument, Arguments),
        petta_source_calls_head(Argument, F, Arity)
    ).

petta_source_has_variable_head(Term) :-
    nonvar(Term),
    Term = [Head|Arguments],
    (   var(Head)
    ->  true
    ;   member(Argument, Arguments),
        petta_source_has_variable_head(Argument)
    ).

petta_source_reduction_count(Term, 0) :- var(Term), !.
petta_source_reduction_count([quote, _], 0) :- !.
petta_source_reduction_count([_|Arguments], Count) :- !,
    maplist(petta_source_reduction_count, Arguments, Counts),
    sum_list(Counts, Nested),
    Count is Nested + 1.
petta_source_reduction_count(_, 0).

add_function_atom(Storage, Space, Module, Term, FAtom, W) :-
    store_equation(Storage, Space, Term),
    length(W, N),
    Arity is N + 1,
    register_arity(FAtom, Arity),
    compile_metta_equation(Module, Term, Clause, _Ref),
    maybe_print_compiled_clause("added function", Term, Clause).

%What is left to refuse, now that every space compiles into a module of its
%own: SWI's PROTECTED CORE. Defining a builtin's name in a space is an
%ordinary local shadow and is accepted; SWI still refuses `assertz` outright
%for a small set of system predicates, with a permission error naming
%assertz/2, the Prolog arity and the absolute path of a source file, none of
%which is language the program that wrote the equation can act on. Say it in
%MeTTa's terms instead, and say that this set is the same in every space
%rather than pointing at a named one, which is no longer the difference
%[measured 2026-08-19: of the 428 names imported into `user`, 7 at MeTTa arity
%0, 4 at arity 1, 2 at arity 2 and 1 at arity 3 are refused in a space's
%module, against 86, 217, 163 and 64 in the engine's]
%[tested: spaces_builtin_override].
:- multifile prolog:error_message//1.

assert_function_clause(Module, Clause, Ref) :-
    catch(assertz(Module:Clause, Ref),
          error(permission_error(modify, static_procedure, _), _),
          throw_builtin_redefinition(Module, Clause)).

%Two refusals, because SWI raises the same permission error for two different
%reasons and only one of them is about Prolog. A name the ENGINE emits into
%compiled bodies is bound into every space's module on purpose
%(protect_engine_emitted/1 above), and telling its author that it is one of
%Prolog's core predicates would send them looking in the wrong place.
throw_builtin_redefinition(Module, Clause) :-
    ( Clause = (Head :- _) -> true ; Head = Clause ),
    functor(Head, Name, Arity),
    InputArity is Arity - 1,
    metta_module_space(Module, Space),
    (   metta_engine_emitted(Name/Arity)
    ->  throw(error(petta_engine_goal_redefinition(Name, InputArity, Space),
                    context('=', 'the engine compiles this name into function \c
                                  bodies')))
    ;   throw(error(petta_builtin_redefinition(Name, InputArity, Space),
                    context('=', 'a builtin cannot be redefined in this space')))
    ).

%The refusal that reads worst when it is unrendered, because the term names a
%capability nobody has heard of and the whole point of the refusal is to teach
%it. `rules` is a promise about what a space HOLDS rather than about which
%methods a provider has, so no protocol can derive it and the message has to
%say how to opt in [tested: test_a_space_without_rules_says_how_to_hold_one].
prolog:error_message(petta_foreign_space_holds_no_rules(Space, Term)) -->
    { swrite(Term, TermText) },
    [ '~w does not hold rules, so ~w was refused rather than stored where it \c
       could never fire'-[Space, TermText], nl,
      '  a foreign space holds DATA unless it says otherwise; declare the \c
       rules capability on the provider to hold a program' ].

prolog:error_message(petta_foreign_operation_failed(Space, Capability)) -->
    [ 'the provider for ~w did not complete the ~w operation and gave no \c
       reason. A provider that cannot serve a request should raise, so the \c
       program can see why.'-[Space, Capability] ].
prolog:error_message(petta_foreign_plan_is_not_a_partition(Space, Patterns,
                                                          Claimed, Rest)) -->
    [ '~w claimed ~w and left ~w of the conjunction ~w, which do not partition \c
       it. A claim may take any subset and leave the rest, and may not drop a \c
       conjunct: the engine plans only what you leave, so a dropped pattern \c
       stops constraining the query and the join answers rows that were never \c
       asked for.'-[Space, Claimed, Rest, Patterns] ].
prolog:error_message(petta_engine_goal_redefinition(Name, Arity, Space)) -->
    [ '~w with ~w arguments is a name the engine itself compiles into function \c
       bodies, so no space can redefine it, ~w included.'-[Name, Arity, Space], nl,
      '  an equation for it would capture the engine\'s own goal in this \c
       space\'s compiled clauses rather than shadowing a function: rename it, \c
       or write the behaviour you want as a wrapper around it' ].
prolog:error_message(petta_builtin_redefinition(Name, Arity, Space)) -->
    [ '~w with ~w arguments is one of Prolog\'s protected core predicates, \c
       which no space can redefine, ~w included.'-[Name, Arity, Space], nl,
      '  every other builtin name is free: an equation for one compiles into \c
       this space\'s own module and shadows it there, leaving the engine\'s \c
       and every other space\'s alone' ].

%Unit for a removal that happened, an error for one that found nothing.
%
%The language's own text is what asks for this rather than what forbids it:
%"if the given atom is not in the space, remove-atom currently neither raises a
%error nor returns the empty result" is a COMPLAINT, and upstream carries the
%same question as a TODO it has not answered, `stdlib/space.rs:219`, "Is it
%necessary to distinguish whether the atom was removed or not?". The arbiter
%answers it: LeaTTa's Hyperon-Hacks-Register row 15 rules "Implement. Keep the
%distinction", records it SATISFIED in `Metta.Minimal.removeAtomStep`, and
%pins the wording this reproduces. Hyperon as shipped answers unit for both,
%so this is a deliberate divergence from the implementation towards the
%specification, which is also what this engine's own hard-error rule says
%[source: LeaTTa wiki/Hyperon-Hacks-Register.md row 15, and
%MettaHyperonFull/Minimal/Interpreter.lean removeAtomStep at 5407-5426].
%
%metta_remove_atom/3 still answers whether anything went and still answers ONLY
%that, because the engine's own callers read the boolean: the loader's
%rollback, the storage modules, and the seam's removal hooks all ask "did the
%store hold it" rather than "what does a program see".
'remove-atom'(Space, Term, Result) :-
    (   petta_space_name(Space)
    ->  metta_remove_atom(Space, Term, Removed),
        (   Removed == true
        ->  Result = []
        ;   space_operation_error('remove-atom', [Space, Term],
                                  "remove-atom: atom is not in the space",
                                  Result)
        )
    ;   space_argument_error('remove-atom', [Space, Term], Result)
    ).

%WHY THE DOORS ASK IT WHERE THEY DO, which is the decision this section makes.
%
%A space is a NAME that is one, and petta_space_name/1 decides which. The doors
%used to share a metta_space_argument/1 whose whole body was `atom(Space)`, on
%the reading that PeTTa CANNOT reproduce the arbiter's
%`(add-atom not-a-space (bad add))` diagnostic: the two model spaces
%differently, upstream's being a grounded atom wrapping a space object while
%PeTTa's is a symbol, and a write to a name that does not exist yet creates it,
%so `not-a-space` and a program's own fresh name looked like the same kind of
%thing. That reading was wrong on its own terms, and the engine already
%disagreed with it in three places: is-space/2 answers False for a name without
%`&`, evalc/3 refuses one as a type error rather than reading a silently empty
%space, and bindings/python/petta/space.py refuses one with "the prefix is
%load-bearing". Only these doors did not, so `(add-atom not-a-space (bad add))`
%made a space called `not-a-space` while `(is-space not-a-space)` answered
%False in the same program.
%
%The arbiter decides it the same way for the same reason. LeaTTa dispatches by
%name as this engine does, and its `spaceName` says "bare symbols resolve only
%through the running context's token table; an unbound symbol is not a space",
%with every space-consuming operation resolving through `resolveSpace`
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:1565-1573,1621-1627].
%What it does not have is creation on demand, which is why the second half of
%petta_space_name/1 is the prefix rather than the registry: a fresh `&kb` is a
%space the moment a program writes to it, and that capability is kept whole.
%The one example that used a name without the prefix,
%examples/spaces/add_atom_fun_space.metta, still returns a space name from a
%function and still lands its write there, spelled `&my_space_name`.
%
%The atom is ANSWERED rather than thrown, because that is what the arbiter
%does: `(collapse (add-atom not-a-space (bad add)))` is a one-element collapse
%holding the error, and a raise would have emptied the collapse instead
%[source: LeaTTa tests/semantics/spaces/add_atom.metta]
%[tested: space_argument_refusals].
%
%NO DOOR ASKS ON THE PATH THAT SUCCEEDS. A shared test called before the
%operation cost one to three inferences on every space operation and four
%benchmarks saw it [measured 2026-08-20: direct-join +10, prepared-join +10,
%register-op +200, py-method-call +30,002], so each door asks the question it
%was already asking: a write reaches no storage module for a name that is not a
%space, a read misses the storage lookup it was already making, and a
%conjunctive match answers no rows. Only then, on a path that was going to
%answer nothing, is petta_space_name/1 consulted to tell a space that is empty
%from a name that is not one. That is why metta_space_argument/1 is gone rather
%than renamed: one shared test in front of every door is exactly the shape the
%measurements refuse.

%The shape every space operation refuses in: the arbiter's `errAtom a0`, whose
%subject is the CALL that failed rather than a generic complaint, which is
%what lets a program tell one refusal from another without reading the message.
%
%The subject is a COPY of that call, and that is load-bearing rather than tidy.
%match/4 takes the output template and the answer in the SAME term: the
%translator emits `match('&self', [foo, A], A, A)` for
%`!(match &self (foo $x) $x)`, so unifying the answer with an error whose
%subject repeats the template builds `A = (Error (match _ (foo A) A) "...")`,
%a rational tree. SWI has no occurs check here, so nothing failed; the term
%printed until the 7.5Gb stack ran out, 50,707,153 frames deep in maplist/3
%[measured 2026-08-19]. Copying makes the subject a snapshot, which is what a
%record of a call that will not run is, and it makes every caller of this safe
%whether or not its output slot aliases an input.
space_operation_error(Operation, Arguments, Reason, Error) :-
    copy_term(Arguments, Subject),
    petta_note_copied_variables(Arguments, Subject),
    Error = ['Error', [Operation|Subject], Reason].

%A runnable installs its flat reader map only while its goals execute. The
%open Generated list is copied with each answer, so an operation that must
%copy a diagnostic subject can record the copied variable's spelling without
%putting attributes on matcher variables
%[tested: test_variable_names_survive_to_the_printer; commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
:- meta_predicate petta_run_named(+, 0, -).
petta_run_named(Names, Goal, Generated) :-
    Context = '$petta_runtime_name_context'(Names, Generated, Generated),
    setup_call_cleanup(
        install_runtime_name_context(Context, SavedContext),
        call(Goal),
        restore_runtime_name_context(SavedContext)).

install_runtime_name_context(Context, saved(Previous)) :-
    nb_current('$petta_runtime_name_context', Previous), !,
    nb_linkval('$petta_runtime_name_context', Context).
install_runtime_name_context(Context, none) :-
    nb_linkval('$petta_runtime_name_context', Context).

restore_runtime_name_context(saved(Previous)) :- !,
    nb_linkval('$petta_runtime_name_context', Previous).
restore_runtime_name_context(none) :-
    nb_delete('$petta_runtime_name_context').

petta_note_copied_variables(Original, Copy) :-
    nb_current('$petta_runtime_name_context', Context), !,
    Context = '$petta_runtime_name_context'(Names, _, _),
    term_variables(Original, OriginalVars),
    term_variables(Copy, CopyVars),
    petta_note_variable_pairs(OriginalVars, CopyVars, Names, Context).
petta_note_copied_variables(_, _).

petta_note_variable_pairs([], [], _, _).
petta_note_variable_pairs([Original|Originals], [Copy|Copies], Names, Context) :-
    (   petta_reader_variable_name(Names, Original, Name)
    ->  arg(3, Context, Tail),
        Tail = [Name-Copy|Next],
        setarg(3, Context, Next)
    ;   true
    ),
    petta_note_variable_pairs(Originals, Copies, Names, Context).

petta_reader_variable_name([Name-Variable|_], Original, Name) :-
    Variable == Original, !.
petta_reader_variable_name([_|Names], Original, Name) :-
    petta_reader_variable_name(Names, Original, Name).

%get-atoms is worded differently because upstream words it differently: it
%takes ONE argument, so pinned `space.rs:143` says "its argument" where the
%two-operand operations' `:172` and `:199` say "the first argument"
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, getAtomsStep at
%5450-5452 against addAtomStep at 5386-5388].
space_argument_error(Operation, Arguments, Error) :-
    (   Operation == 'get-atoms'
    ->  Position = "its argument"
    ;   Position = "the first argument"
    ),
    format(string(Message),
           "~w expects a space as ~w", [Operation, Position]),
    space_operation_error(Operation, Arguments, Message, Error).

%%%% The three the standard library defines beside add-atom %%%%
%
%All three were reachable only through `(import! &self (library lib_he))`, and
%only one of them at that, so a program written against the standard library
%found `(add-reduct &self (+ 1000 1))` sitting in the space UNREDUCED as the
%call itself. They are stdlib operations, not extensions:
%
%  add-atoms    "adds atoms in Expression into given space without reduction"
%  add-reduct   "Reduces atom (second argument) and adds it into the space"
%  add-reducts  "evaluates atoms in it and adds them into given space"
%
%[source: LeaTTa stdlib.md:330-361, quoted in its tests/semantics/spaces].
%
%Each answers the UNIT value, like add-atom, and each takes its second argument
%unreduced: the reducing ones do their own reducing, which is the whole of what
%distinguishes them from the plain ones.
%All three DELEGATE the space check to add-atom rather than repeating it, and
%that is observable: the arbiter answers `(Error (add-atom not-a-space 7001)
%...)` for `(add-reduct not-a-space (+ 7000 1))`, naming add-atom and the
%REDUCED atom, because the refusal happens where the write does. Checking here
%would name add-reduct and the unreduced call, which is a different answer.
'add-atoms'(Space, Terms, Result) :-
    metta_space_expression('add-atoms', Terms, List),
    add_expression_to_space(Space, List, Result).

'add-reduct'(Space, _, _) :-
    var(Space),
    !,
    refuse_unbound_input('add-reduct', 1).
'add-reduct'(Space, Term, Result) :-
    reduced_for_space(Term, Reduced),
    'add-atom'(Space, Reduced, Result).


'add-reducts'(Space, Terms, Result) :-
    metta_space_expression('add-reducts', Terms, List),
    maplist(reduced_for_space, List, Reduced),
    add_expression_to_space(Space, Reduced, Result).

%The batch crossing is kept for the space that has one, so the plural forms are
%still one write rather than n. A bad space is refused before any of it, and
%the error names the first atom because that is the one add-atom would have
%refused first.
%The batch door asks BEFORE the crossing rather than reading its failure, which
%the two doors above can do: a batch has its own crossing and a per-atom
%fallback that answers the error atom instead of failing, so a failure here
%does not mean what it means there. It costs the test once per batch and not
%once per atom.
add_expression_to_space(Space, List, Result) :-
    (   petta_space_name(Space)
    ->  metta_add_atoms(Space, List), Result = []
    ;   List = [First|_]
    ->  space_argument_error('add-atom', [Space, First], Result)
    ;   Result = []
    ).

%The plural forms take ONE expression holding the atoms, which is the shape the
%standard library gives them, so anything else is a mistake worth naming rather
%than a silent no-op over a term that is not a list.
%A DEFINITION reduces its body and keeps its head, and everything else reduces
%whole. Both readings are required by the two things this has to satisfy:
%
%  (add-reduct &self (+ 1000 1))          adds 1001
%  (add-reduct &self (= (foo) (+ 3 4)))   makes (foo) answer 7
%
%[source: LeaTTa tests/semantics/spaces/add_reduct.metta for the first, the
%language's Working with spaces for the second]. Reducing the second one whole
%cannot work HERE, and the reason is local rather than general: `=` is
%overloaded in this engine, the head of a definition and also the equality
%operator, so `(= (foo) (+ 3 4))` reduces to `false` rather than staying an
%equation with its body reduced. Upstream has no such collision, which is why
%it can state the rule as one sentence and this cannot.
reduced_for_space([=, Head, Body], [=, Head, ReducedBody]) :-
    !,
    reduced_for_space(Body, ReducedBody).

%reduce/3 takes an expression, and a symbol or a number is already its own
%value, so asking it to reduce one raises rather than answering. Both callers
%above may be handed either, because their argument arrives unreduced.
reduced_for_space(Term, Reduced) :-
    (   is_list(Term)
    ->  once(reduce(Term, Reduced, _))
    ;   Reduced = Term
    ).

metta_space_expression(_, Terms, Terms) :- is_list(Terms), !.
metta_space_expression(Operation, Terms, _) :-
    throw(error(type_error(expression, Terms),
                context(Operation, 'takes one expression of atoms'))).

%The mirror of the write path, and it has to be: an atom that compiled when it
%was added has to un-compile when it is taken out, wherever it was stored. This
%dispatched on storage first for the same reason the write path did, so a
%foreign space's equation kept its compiled clause after the atom was gone.
%A pattern that is ITSELF a variable is the remove-everything reading a
%multiset space gives it, and it must be answered here: left to the next
%clause, the unbound term UNIFIED into the equation shape and took the
%equation-removal path with an unbound function symbol, whose behaviour
%then depended on whatever equations the whole process happened to hold
%(found 2026-08-18: (remove-atom &cstore $any) raised
%atomic_list_concat/2 instantiation errors only when other suites had
%run first). Enumerating and removing each atom through its own proper
%path keeps equations, their compiled clauses, and foreign providers
%all handled by the code that owns them.

%% metta_remove_atom(+Space, ?Atom, -Removed:boolean) is semidet.
metta_remove_atom(Space, _, _) :-
    metta_refuse_module_for_space(Space, metta_remove_atom/3),
    fail.
metta_remove_atom(Space, Term, Removed) :- var(Term), !,
    findall(A, metta_host_stored(Space, A), Atoms),
    (   Atoms == []
    ->  Removed = false
    ;   forall(member(A, Atoms),
               ( metta_remove_atom(Space, A, _) -> true ; true )),
        Removed = true
    ).
metta_remove_atom(Space, Term, Removed) :- Term = [=, [F|Args], Body], !,
                                           remove_equation(Space, Term, F, Args,
                                                           Body, Removed).
metta_remove_atom(Space, Term, Removed) :-
    Term = [':', Type, Marker],
    atom(Type),
    ( Marker == 'DontEvalType' ; var(Marker) ),
    !,
    unstore_atom(Space, Term, Removed),
    (   Removed == true
    ->  space_module(Space, DeclModule),
        ( fun(Type) -> function_changed(DeclModule, Type) ; true ),
        type_marker_changed(DeclModule, Type)
    ;   true
    ).
metta_remove_atom(Space, Term, Removed) :-
    Term = [':', Type, Marker],
    var(Type),
    ( Marker == 'DontEvalType' ; var(Marker) ),
    !,
    findall(MarkerType,
            ( match_stored(Space,
                           [':', MarkerType, 'DontEvalType'], MarkerType, _),
              atom(MarkerType) ),
            MarkerTypes0),
    sort(MarkerTypes0, MarkerTypes),
    unstore_atom(Space, Term, Removed),
    (   Removed == true
    ->  space_module(Space, DeclModule),
        forall(member(MarkerType, MarkerTypes),
               type_marker_changed(DeclModule, MarkerType))
    ;   true
    ).
%A declaration decides how call sites compile, so taking one away leaves them
%stale exactly as adding one did, and for the same reason: the argument that
%arrived as written now arrives evaluated. The write path learned this and the
%removal path did not.
metta_remove_atom(Space, Term, Removed) :- Term = [':', F, _], atom(F), fun(F), !,
                                           unstore_atom(Space, Term, Removed),
                                           space_module(Space, DeclModule),
                                           function_changed(DeclModule, F).
metta_remove_atom(Space, Term, Removed) :- unstore_atom(Space, Term, Removed).

type_marker_changed(Module, Type) :-
    findall(Function-Context,
            type_marker_dependent(Module, Type, Function, Context),
            Dependents0),
    sort(Dependents0, Dependents),
    findall(Root,
            ( member(Function-Context, Dependents),
              Root = type_marker(Module, Type),
              support_record(function_view(Context, Function), Root) ),
            Roots0),
    sort(Roots0, Roots),
    support_invalidate_many(Roots),
    forall(support_repair_invalidations, true),
    clear_translation_cache.

type_marker_dependent(MarkerModule, Type, Function, Context) :-
    type_marker_function_context(Function, Context),
    type_marker_visible_in(MarkerModule, Context),
    stored_arrow_uses_type_in(Context, Function, Type).

type_marker_function_context(Function, Context) :-
    support_view_module(Function, Context).

type_marker_visible_in(MarkerModule, Context) :-
    metta_self_module(Self),
    ( MarkerModule == Self -> true ; Context == MarkerModule ).

stored_arrow_uses_type_in(Context, Function, Type) :-
    metta_self_module(Context),
    !,
    stored_arrow_chain('&self', Function, Types),
    arrow_parameter_type(Types, Type).
stored_arrow_uses_type_in(Context, Function, Type) :-
    metta_module_space(Context, Space),
    (   stored_arrow_chain(Space, Function, Types)
    ;   stored_arrow_chain('&self', Function, Types)
    ),
    arrow_parameter_type(Types, Type).

%The arrow shape is checked AFTER the match, not asked for in the pattern,
%because a pattern crossing a space seam has to be a MeTTa TERM and a partial
%list is not one. [-> | Types] with Types unbound is fine against the native
%store, where matching is Prolog unification, and has no text at all for a
%provider that writes the pattern to send it: MORK refused this one and the
%refusal surfaced as `swrite/2: cannot write [->|'$petta_variable'(0)]` from
%an ordinary (: Name Type) declaration, reproduced by storing an equation in
%&mork, removing it, and then declaring any type marker [measured 2026-08-21].
%Asking with a plain variable and filtering here is the seam's own
%over-approximate-then-re-unify contract, and it costs the native path
%nothing: Function is bound, so the store still dispatches on it.
stored_arrow_chain(Space, Function, Types) :-
    match_stored(Space, [':', Function, Chain], Chain, _),
    nonvar(Chain),
    Chain = [->|Types].

arrow_parameter_type(Types, Type) :-
    append(ParameterTypes, [_], Types),
    member(ParameterType, ParameterTypes),
    ParameterType == Type.

%A host's reporting removal: whether anything actually went. The
%language-facing `remove-atom` answers the UNIT value, because its type is
%`(-> spaceType Atom (->))` and the specification says absence is not
%reported there; a HOST API where `space.remove(atom)` returns whether
%anything went is the useful answer, and nothing in MeTTa's contract
%governs it. Existence is asked BEFORE the mutation against a copy, so the
%removal's own bindings cannot narrow the question; a foreign space's
%provider owns its verdict outright.
metta_host_remove_reported(Space, Term, Verdict) :-
    (   metta_foreign_space(Space)
    ->  metta_remove_atom(Space, Term, Verdict)
    ;   copy_term(Term, Pattern),
        (   metta_host_removal_probe(Space, Pattern)
        ->  Existed = true
        ;   Existed = false
        ),
        metta_remove_atom(Space, Term, Removed0),
        ( Removed0 == false -> Verdict = false ; Verdict = Existed )
    ).

%Whether an atom unifying with Pattern is stored, without enumerating the
%space when the answer is reachable by index. The first branch probes the
%native storage predicate directly, which first-argument indexing makes
%O(1) for the ground common case; it may only SUCCEED, never conclude
%absence, because storage shapes this cannot express (a foreign layout, an
%atom that is not a list) still exist. Failure falls back to the
%enumeration, so the semantics are the old ones exactly and only the cost
%moves. Found because the contract ontology's 65 resident atoms in &petta
%turned a get-atoms walk into +149 inferences per register-and-unregister
%cycle on the register-op benchmark [measured 2026-08-18: a remove on an
%80-atom &petta cost 303 inferences against 61 on a plain space, and the
%engine-level remove path profiled flat].
metta_host_removal_probe(Space, Pattern) :-
    Space = [_|_],
    space_parametric(Space),
    is_list(Pattern),
    Pattern = [Head|Arguments],
    atom(Head),
    native_storage_module(Space, Module),
    Goal =.. ['$petta_parametric_atom', Head|Arguments],
    call(Module:Goal),
    !.
metta_host_removal_probe(Space, Pattern) :-
    atom(Space),
    is_list(Pattern),
    Pattern = [Head|Arguments],
    atom(Head),
    catch(( native_storage_module(Space, Module),
            Goal =.. [Space, Head|Arguments],
            call(Module:Goal) ),
          error(existence_error(procedure, _), _),
          fail),
    !.
metta_host_removal_probe(Space, Pattern) :-
    once((metta_host_stored(Space, Stored), Stored = Pattern)).

%Every stored atom unifying Pattern, live from the space: a native space
%answers through its storage module's clause indexing, a foreign one
%enumerates its provider and unifies. Pattern-directed where storage
%allows, so an indexed head pattern does not pay a whole-space walk.
metta_host_stored(Space, Pattern) :-
    (   metta_foreign_space(Space)
    ->  'get-atoms'(Space, Atom),
        Atom = Pattern
    ;   get_native_atom(Space, Pattern)
    ).

%Decode a native storage goal for proof transports without publishing the
%storage module cache or its private functor convention to the host. Module
%and functor must both identify the same registered space [tested:
%test_a_parametric_fact_leaf_names_its_space; commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
metta_host_native_fact(Module, Goal, Space, Fact) :-
    native_storage_module_cache(Space, Module),
    native_storage_functor(Space, Functor),
    functor(Goal, Functor, _),
    Goal =.. [_|Fact].

%% remove_equation(+Space, +Equation, +Function:atom, +Arguments, ?Body, -Removed:boolean) is semidet.
remove_equation(Space, Term, F, Args, Body, Removed) :-
    unstore_atom(Space, Term, Stored),
    space_module(Space, Module),
    drop_fun_meta(Module, F, Args, Body),
    %ONE compiled clause, the multiset law applied to the compiled half. The
    %retained-equation half above already worked this way and said so, "remove
    %one variant-equivalent retained equation... duplicate equations are
    %removed one at a time", so the two halves used to disagree: the same
    %equation written twice answered twice, and one removal left the function
    %undefined because this erased both clauses under the one atom that went.
    %
    %Only this space's compiled clauses die: the same equation imported into two
    %spaces compiles into two modules, and the term-keyed lookup alone would
    %erase the twin space's clause and, through the term-wide retractall, its
    %record with it.
    %
    %The probe is a COPY for drop_fun_meta/4's reason: a lookup that binds the
    %caller's Term would narrow every later use of it in this clause.
    copy_term(Term, Probe),
    (   translated_from(Ref, Probe), clause_property(Ref, module(Module))
    ->  forget_translated_from(Module, Ref, Probe), erase(Ref), Erased = true
    ;   Erased = false
    ),
    %A local predicate the erase just EMPTIED still shadows the same name
    %inherited through the module chain, &self's builtins above all: after
    %removing a car-atom shadow from &self, every &self-compiled caller of
    %car-atom failed for the rest of the process because the empty local
    %definition answered instead of the engine's. Dropping the emptied
    %entry lets the chain answer again. The arity comes from the STORED
    %equation the lookup unified into Probe, never from the caller's Args:
    %a removal by open pattern, [Head|_], leaves Args a partial list, and
    %length/2 on a partial list generates arities for ever
    %[tested: removing_a_self_shadow_restores_the_builtin].
    (   Erased == true,
        Probe = [=, [_|StoredArgs], _],
        is_list(StoredArgs),
        length(StoredArgs, NArgs),
        PredArity is NArgs + 1,
        functor(EmptyHead, F, PredArity),
        predicate_property(Module:EmptyHead, number_of_clauses(0))
    ->  (   current_transaction(_)
        ->  %abolish/1 is predicate-level, so a rollback cannot restore
            %what it dropped: a failed reload lost the definitions it
            %promised to keep when this abolished eagerly. The pending
            %fact IS clause-level, so it vanishes with a rollback and
            %survives a commit, and the owner of the outermost
            %transaction sweeps it afterwards
            %[tested: test_a_reload_that_fails_leaves_the_previous_definitions_standing].
            assertz('$petta_shadow_repair_pending'(Module, F, PredArity))
        ;   petta_repair_emptied_shadows,
            catch(abolish(Module:F/PredArity), _, true)
        )
    ;   true
    ),
    function_changed(Module, F),
    ( module_owns_function(Module, F) -> true ; unregister_fun_in(Module, F) ),
    ( \+ function_still_defined(F)
      -> retractall(fun(F)), unregister_fun_everywhere(F),
         %function_removed/1, not the bare event: fun(F) is false only now,
         %so THIS recompile is the one that reads mentions of F as data
         %again; the function_changed above ran while F was still a function.
         function_removed(F)
      ; true ),
    ( Erased == false, Stored \== true -> Removed = false ; Removed = true ).

:- dynamic '$petta_shadow_repair_pending'/3.

%The deferred half of the emptied-shadow repair above: each pending row
%names a function a committed transaction emptied. The recheck matters,
%because a reload that REDEFINES a function empties it in withdrawal and
%refills it in the load, and only a function still empty at the sweep is
%a shadow to drop. abolish refusing (a tabled shadow) leaves the old
%behaviour, an empty local predicate.
petta_repair_emptied_shadows :-
    forall(retract('$petta_shadow_repair_pending'(Module, F, PredArity)),
           (   functor(Head, F, PredArity),
               (   predicate_property(Module:Head, number_of_clauses(0))
               ->  catch(abolish(Module:F/PredArity), _, true)
               ;   true
               )
           )).

%Where an atom comes out of, the counterpart of store_atom/2. Both answer
%whether the store actually held it.

%% unstore_atom(+Space, ?Atom, -Removed:boolean) is semidet.
unstore_atom(Space, Term, Removed) :- metta_foreign_space(Space), !,
                                      foreign_write(Space, remove,
                                                    metta_foreign_remove(Space, Term,
                                                                         Removed)).
%One atom that unifies, and whether one was there. A MeTTa space is a multiset,
%and subtracting from a multiset takes one occurrence.
unstore_atom(Space, Term, Removed) :- remove_sexp(Space, Term, Removed).

%A CONJUNCTION finds every row before any of them leaves, which is specified
%behaviour and not an implementation detail we are free to pick: "match first
%finds all the matches, and then instantiates the output pattern with them,
%which is evaluated outside match. If remove-atom and add-atom would be
%executed right away for each found matching, the condition of circular links
%would be broken after the first rewrite" [source: the language's Working with
%spaces, the graph-rewriting example]. The arbiter pins it with an experiment
%built to tell an eager snapshot from a lazy query that happens to be fully
%consumed: both implementations retain every row through a template that
%removes the other one, and only the effect ORDER is a recorded free
%divergence [source: LeaTTa tests/semantics/matching/
%nondeterministic_match_snapshot.metta and its EVIDENCE entry].
%
%A SINGLE pattern needs nothing here and still streams. It is one goal over
%one dynamic predicate, and the logical update view already fixes what it sees
%at the call, so a template that writes cannot change what the goal still has
%to answer; the arbiter's own single-pattern experiment passes on that alone.
%A conjunction is where it runs out, because each later conjunct is a fresh
%goal STARTED AFTER the previous row's template ran, and a fresh goal sees the
%new generation. Measured on the doc's own example: upstream reverses all
%three loop edges, and this reversed one, the first template's remove-atom
%breaking the cycle for every later conjunct [measured 2026-08-19,
%ai-tmp/spaces-p1/p116/linkloop.metta].
%
%What is collected is the BINDINGS, term_variables over the pattern and the
%output template together, because that is where a row lives: the translator
%compiles the template into goals reading the PATTERN's own variables,
%`'remove-atom'('&self', [link, B, C], _)` beside `match('&self', [',',
%[link,B,C], ...], A, A)`, so collecting the output slot alone would collect a
%variable the match never binds and lose every row. Taking both terms'
%variables keeps whatever they share.
%
%Cheaper than the arbiter, which collects a BindingsSet for every match; this
%pays only where a conjunction is written, and leaves
%(once (match &big (foo $x) $x)) streaming
%[tested: test_match_snapshots_rows_before_template_effects,
%spaces_match_snapshot:a_conjunction_finds_every_row_before_any_template_runs].
%An ANNOTATED space's rows carry their annotation as well as their bindings,
%because that rides '$petta_answer_k' BACKTRACKABLY and findall would undo it:
%reset-call-read is metta_top/3's own idiom below, and the write after member/2
%is what hands the row's k to the template that reads (annotation).
%
%A space whose semiring is bool takes the plain collection, which is three
%inferences a row cheaper and is the traffic: under bool an answer's k can
%only be 1, because a provider handing one to an undeclared context raises
%rather than setting it ("a real k is admitted exactly when its context
%declared a non-Boolean semiring", bindings/python/petta/shim.pl), and the engine's own
%join writes nothing when both sides read 1. Measured on direct-join
%[measured 2026-08-19: 320,322 inferences with the capture on every row
%against 289,819 without it, over 10,000 rows]
%[tested: test_a_join_multiplies_provenance,
%test_a_conjunction_carries_each_rows_annotation].
%Atomic names retain the atom/1 fast path. Registered parametric names add one
%indexed registry probe; the refusal is still reached through the SOFT CUT
%below, so a conjunction that answered rows was a space and only one that
%answered none has anything left to decide. A general space test in the guard
%cost one inference on every ordinary join [measured 2026-08-20: direct-join
%and prepared-join +10 each].
match([Family|Parameters], Pattern, OutPattern, Result) :-
    nonvar(Pattern),
    Pattern = [Comma|_],
    Comma == ',',
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    conjunctive_match(match_conjunction(Space, Pattern, OutPattern),
                      Space, Pattern, OutPattern, Result).
match(Space, Pattern, OutPattern, Result) :- nonvar(Pattern), Pattern = [Comma|_], Comma == ',',
                                             atom(Space), !,
                                             (   conjunctive_match(match_conjunction(Space,
                                                                                     Pattern,
                                                                                     OutPattern),
                                                                   Space, Pattern,
                                                                   OutPattern, Result)
                                             *-> true
                                             ;   petta_space_name(Space)
                                             ->  fail
                                             ;   space_argument_error('match',
                                                                      [Space, Pattern,
                                                                       OutPattern],
                                                                      Result)
                                             ).

%A single pattern over a foreign space: the provider answers, and the
%conjunction door above has already taken the conjunctive case.
match(Space, Pattern, OutPattern, Result) :- nonvar(Space),
                                             metta_foreign_space(Space), !,
                                             match_foreign(Space, Pattern, OutPattern, Result).
%An unbound space would make this dynamic call enumerate every space that has
%ever been written to, so a program in &self could read &kb without naming it.
%Matching is against a space you NAME, and the refusal is the write path's
%own: `(add-atom $unbound (foo 1))` already answered
%`(Error (add-atom $_ (foo 1)) "add-atom expects a space as the first
%argument")` while this raised SWI's bare `Arguments are not sufficiently
%instantiated`, which names neither the operation nor the call and reached
%Python as an EngineError with no operation field at all. Same question, same
%kind of answer [tested: test_get_atoms_on_an_unbound_space_names_the_operation,
%spaces_storage_modules:matching_requires_a_named_space].
%
%The storage lookup this clause was already making IS the space test for every
%name the engine holds, so a match against a space that exists reaches
%match_native/5 exactly as it did and the two clauses below it never run. The
%CUT is what lets them exist: without it an answered match would produce the
%refusal as a second answer.
match([Family|Parameters], Pattern, OutPattern, Result) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    native_storage_module_cache(Space, Module), !,
    match_native(Module, Space, Pattern, OutPattern, Result).
match(Space, Pattern, OutPattern, Result) :-
    atom(Space),
    native_storage_module_cache(Space, Module), !,
    (   space_parent(Space, _)
    ->  match_inherited_space(Space, Module, Pattern, OutPattern, Result)
    ;   match_native(Module, Space, Pattern, OutPattern, Result)
    ).
%Only a name the engine holds no space for reaches here, and the question left
%is which kind it is: a space nothing has written to yet answers nothing, which
%is what an empty space answers, and anything else is refused by name.
%
%GUARDED RATHER THAN LEFT TO THE CUT ABOVE, and that is load-bearing: the
%derivation meta-interpreter walks a predicate by enumerating clause/3 and
%calling each body through call/1, where a cut in an earlier body cannot prune
%this clause. Written without the guard, every match against a real space grew
%a second answer, the refusal, and `(anc-d $x $y)` recursed on it until the
%process hung [reproduced 2026-08-20: bindings/python/tests/test_derivation.py]. Every
%clause of a predicate a proof can walk has to say for itself when it applies,
%which is what the three clauses above already do.
match(Space, Pattern, OutPattern, Result) :-
    \+ petta_space_name(Space),
    space_argument_error('match', [Space, Pattern, OutPattern], Result).

%The PRODUCER is handed in rather than built here, because the caller is where
%a bound is known: match/4 hands the plain conjunction walk and
%match_bounded/5 hands the same walk under limit/2, so a bounded caller
%collects its bound's worth of rows and stops. The unbounded collection is
%therefore exactly the goal it always was and pays nothing for the choice
%[measured 2026-08-21: direct-join and prepared-join unchanged at 300,522].
%
%Both spellings keep the snapshot: every row the caller can reach is found
%before the first of them leaves, which is the whole point of the findall.
%A bound only makes the set of reachable rows smaller.
%
%No meta_predicate declaration, and that is deliberate: the producer is always
%the engine's own match_conjunction/3, which lives in `user` beside this
%clause, where a named space's module never enters. metta_take/2 and
%metta_top/3 declare one because their goal is a MeTTa BODY.
conjunctive_match(Producer, Space, Pattern, OutPattern, Result) :-
    term_variables(Pattern-OutPattern, Row),
    (   petta_annotations(Space, bool)
    ->  findall(Row,
                Producer,
                Rows),
        member(Row, Rows)
    ;   petta_algebra_one(Space, One),
        findall(Row-K,
                ( b_setval('$petta_answer_k', One),
                  Producer,
                  b_getval('$petta_answer_k', K) ),
                Rows),
        member(Row-K, Rows),
        b_setval('$petta_answer_k', K)
    ),
    Result = OutPattern.

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
    nonvar(Space), metta_foreign_space(Space), !,
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
match_conjunction(Space, Pattern, OutPattern) :- metta_foreign_space(Space), !,
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
    metta_foreign_space(Space),
    !,
    match_foreign(Space, Pattern, OutPattern, Result).
match_read_link(Space, Pattern, OutPattern, Result) :-
    native_storage_module_ready(Space, Module),
    match_native(Module, Space, Pattern, OutPattern, Result).

match_routed(_, LComma, OutPattern, Result) :- LComma == [','], !,
                                               Result = OutPattern.
match_routed(Space, [','|[Head|Tail]], OutPattern, Result) :-
    match(Space, Head, conj, conj),
    match_routed(Space, [','|Tail], OutPattern, Result).

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
petta_match_atoms(L, R) :- is_list(L), is_list(R), !,
                           petta_match_all(L, R).
petta_match_atoms(L, R) :- petta_space_operand(L), !, match(L, R, [], _).
petta_match_atoms(L, R) :- petta_space_operand(R), !, match(R, L, [], _).
petta_match_atoms(L, R) :- metta_matchable_value(L), !,
                           metta_custom_match(L, R).
petta_match_atoms(L, R) :- metta_matchable_value(R), !,
                           metta_custom_match(R, L).
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
    (   metta_foreign_space(S)
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
    findall(S, metta_foreign_space(S), Foreign),
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
%to tell "no rows" from "not mine", which is the ambiguity metta_foreign_match/3
%was fixed for; once/1 here and the cut at the call site are what prevent it.
foreign_claims_plan(Space, Conjuncts, Rest, Goal) :-
    foreign_provides(Space, plan),
    once(metta_foreign_plan(Space, Conjuncts, Claimed, Rest, Goal)),
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
    metta_foreign_atoms(Space, PatternVar),
    acyclic_term(OutPattern),
    Result = OutPattern.
match_foreign_routed(Space, match, Pattern, Options, OutPattern, Result) :- !,
    licensed_options(Space, Pattern, Options, Licensed),
    petta_source_guard(Space),
    (   petta_on_error_mode(Space, Pattern, Mode),
        Mode \== abort
    ->  petta_match_erring(Mode, Space, Pattern, Licensed, OutPattern, Result)
    ;   metta_foreign_match(Space, Pattern, Licensed),
        acyclic_term(OutPattern),
        Result = OutPattern
    ).

match_foreign_routed(Space, enumerate, Pattern, _, OutPattern, Result) :-
    petta_source_guard(Space),
    metta_foreign_atoms(Space, Candidate),
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
%through the metta_foreign_erring/5 adapter hook. A provider whose host
%is Prolog throws ordinary catchable exceptions, and the fallback below
%handles those here; catch/3 keeps the goal's choice points, so streamed
%answers survive the wrapping.
petta_match_erring(Mode, Space, Pattern, Licensed, OutPattern, Result) :-
    (   metta_foreign_erring(Space, Pattern, Licensed, Mode, Item)
    *-> (   Item == answer
        ->  acyclic_term(OutPattern),
            Result = OutPattern
        ;   Item = kept(Kept),
            Result = Kept
        )
    ;   catch(( metta_foreign_match(Space, Pattern, Licensed),
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
        metta_foreign_space(Space)
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
        metta_foreign_space(Space)
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
%same guarded metta_foreign_plan call the execution commits to, the
%lossy-partition check included. Claimed and Rest come back as indexes into
%the pattern list, so a host renders its own atoms and its caller's variable
%names survive. A stored space answers explain(stored, [], [], []): the
%engine joins by unification and no provider is consulted. Origins are
%TERMS, declared(Entry, Fidelity, Det), provider, unclaimed or
%refused(Entry); prose is the host's own presentation.
metta_host_explain_match(Space, Patterns, Report) :-
    (   \+ metta_foreign_space(Space)
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
    ;   metta_foreign_pushdown(Space, Pattern, _)
    ->  Origin = provider
    ;   Origin = unclaimed
    ).

metta_host_explain_plan(Space, Patterns, ClaimedIdx, RestIdx) :-
    (   Patterns = [_, _|_],
        foreign_provides(Space, plan),
        once(metta_foreign_plan(Space, Patterns, Claimed, Rest, _Goal)),
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
    ;   metta_foreign_pushdown(Space, Pattern, Claimed)
    ->  Class = Claimed
    ;   Class = inexact
    ).

%The advisors' fold: every metta_route_cap/4 clause is a voice and the
%most conservative wins, refuse below inexact below exact, so an advisor
%can only DEMOTE what the declaration or the method proposed. refuse is
%loud and names the advisor's Why; a cap outside the vocabulary is a bug
%in the advisor and refuses as one. The common engine has no advisor
%loaded, and that costs one failed indexed call; with advisors present
%the probe's work is repeated inside findall, which is accepted, advisors
%being rare and the fold running only at route classification, never per
%answer.
petta_route_cap_apply(Space, Pattern, Class0, Class) :-
    (   \+ metta_route_cap(Space, Pattern, _, _)
    ->  Class = Class0
    ;   findall(Cap-Why, metta_route_cap(Space, Pattern, Cap, Why), Caps),
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
       metta_route_cap/4; remove the advisor''s reason or its declaration \c
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
match_native(_, _, LComma, OutPattern, Result) :- LComma == [','], !,
                                                  Result = OutPattern.
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
                               metta_foreign_space(Space), !,
                               refuse_absent_capability(Space, enumerate),
                               petta_source_guard(Space),
                               metta_foreign_atoms(Space, Pattern).

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
    metta_foreign_space(Space),
    !,
    refuse_absent_capability(Space, enumerate),
    petta_source_guard(Space),
    metta_foreign_atoms(Space, Pattern).
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
    foreign_write(Space, clear, metta_foreign_clear(Space)).

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
    (   metta_foreign_space(Space)
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
    (   metta_foreign_space(Space)
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
