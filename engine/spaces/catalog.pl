% Purpose: own native storage modules and enforce the self-describing policy
% and capability catalog Assumes: engine/spaces.pl consults this plain file
% while its owning module is the load context. Guarantees: every definition
% retains engine/spaces.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and
% unqualified meta-goals would acquire the wrong owner. Guarantees: counting
% and tropical are ordinary catalog algebras, and each ordered preset declares
% its best direction [tested:
% extensions/python/tests/ch06_many_answers/test_under_algebra.py;
% commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]. Guarantees: deprecated is a
% schema-checked catalog kind whose name, since, and remedy fields remain
% ordinary queryable data [tested: the_shipped_catalog_is_queryable_data;
% commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0]. Guarantees: every shipped
% callable receives one PUBLIC or INTERNAL visibility row after prelude
% registration, and internal classification does not remove the callable
% [tested: every_shipped_callable_has_one_visibility;
% commit=8779452fed89853c3f77c3469f7a6ec7b12e9efa]. Guarantees: async is a
% declared operation kind whose compiled result is a FutureSpace [tested:
% test_an_async_operation_answers_a_future_space;
% commit=39092863ae34184a9f955f185ff57c1ff177ec40]. Guarantees: world effect
% coverage and saga compensation are schema-checked catalog rows; compensation
% is admitted only for writesState-or-stronger operations and names one
% callable recovery operation [tested:
% effects_lattice:compensation_declarations_require_an_effectful_operation,
% test_a_structural_operation_cannot_declare_a_compensation;
% commit=173eeed021beb360b5e5f9f8461889e27190affc]. [tested:
% tests/prolog/suites/spaces/spaces.plt, tests/prolog/static_checks.pl;
% commit=9a116762fb4372d55675e2ef64b7657092bc136d]

:- dynamic native_storage_module_cache/2.
:- dynamic space_parametric/1.
%The two host idle-hook seams these read are declared with every other seam,
%in engine/ext_points.pl, rather than here. Declaring a seam in the module of
%the file that happens to CALL it was the flat namespace's habit; a seam
%belongs to the seam module whichever subsystem asks it.

%Only a module that actually holds something belongs to somebody else.
%current_module/1 is not that test: SWI creates a module as a side effect of
%merely naming it, including from read-only introspection, so
%predicate_property('$metta_atoms:&kb':anything, dynamic) was enough to make
%&kb throw on every write for the life of the process, with clear/1 reporting
%success and changing nothing. An empty module of that name is ours to claim
%[tested: spaces_registration:naming_the_storage_module_does_not_claim_it].
native_storage_module_occupied(Module) :-
    current_module(Module),
    predicate_property(Module:Head, defined),
    \+ predicate_property(Module:Head, imported_from(_)),
    \+ predicate_property(Module:Head, foreign), !.

native_storage_ready(Module) :-
    current_predicate(Module:'$metta_native_storage'/0),
    predicate_property(Module:'$metta_native_storage', dynamic),
    \+ predicate_property(Module:'$metta_native_storage',
                           imported_from(_)).

native_storage_module_ready(Space, Module) :-
    native_storage_module_cache(Space, Module).

%Whether a NAME is a space, which is the wider question: one this engine
%already holds, or one it would create by being written to. A space is created
%on demand here, so the second half cannot be the registry, and the rule for it
%is the engine's own: an atom beginning with `&`, which is what is-space/2
%answers, what evalc/3 has enforced at its door since it was written, and what
%extensions/python/metta/space.py enforces at the library's
%[tested: space_argument_refusals].
metta_space_name(S) :- atom(S), sub_atom(S, 0, 1, _, '&'), !.
metta_space_name(S) :- metta_space_operand(S).
%HERE rather than beside metta_space_operand/1 below, because the two
%directives that create &self's and &metta's storage modules run while this
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
    metta_space_name(Space),
    native_storage_module(Space, Module),
    with_mutex('$metta_native_storage',
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
      dynamic(Module:'$metta_native_storage'/0),
      assertz(native_storage_module_cache(Space, Module)) ).

%The dynamic marker and module properties survive transaction rollback even
%when its cache fact does not. A later write can therefore recover the cache
%instead of finding a stranded reserved module name [tested:
%spaces_registration:rolled_back_first_write_keeps_storage_reusable].
:- ensure_native_storage_module('&self', _).
:- dynamic '$metta_atoms:&self':'&self'/3.
%&metta too, at load: the contract read path probes it on every foreign
%match, and against a module that does not exist yet each probe is a thrown
%and caught existence error, 65 inferences where the created module's
%unknown=fail flag answers the same miss in a handful [measured 2026-08-17:
%metta_handles_route 136 to 30 inferences per miss].
:- ensure_native_storage_module('&metta', _).

% Return the asserted clause reference so a source load can roll back every
% atom it added if a later form fails.
add_sexp(Space, Term) :- add_sexp(Space, Term, _).
%&self's storage module is fixed and created when this file loads, so the
%default space skips the cache lookup that every other space needs. Writes are
%the one path that pays per atom: resolving the module per write cost four
%inferences of every seven on this path [measured 2026-08-15: 7.00 to 5.00
%inferences per write over 200,000 writes].
add_sexp('&self', Term, Ref) :- !, add_sexp_in('$metta_atoms:&self', '&self', Term, Ref).
%The contract flag rides an indexed clause of its own, so an ordinary
%add never even tests for '&metta': first-argument indexing dispatches
%past this clause for every other space at zero cost, where a guard
%inside the shared funnel taxed every write (+26k on source-load's
%counter, caught by the gate).
add_sexp('&metta', Term, Ref) :- !,
    metta_declaration_check(Term),
    metta_note_ctx_declared(Term),
    ensure_native_storage_module('&metta', Module),
    add_sexp_in(Module, '&metta', Term, Ref),
    metta_catalog_note_added(Term).
add_sexp(Space, Term, Ref) :- ensure_native_storage_module(Space, Module),
                              add_sexp_in(Module, Space, Term, Ref).

%The two clause bodies below are native_atom_clause/3 written out rather than
%called, and that is measured rather than assumed: calling it cost one goal
%per write, +2001 inferences over add-batch's thousand atoms, +2 per write on
%a seven-inference path. native_atom_clause/3 stays the definition, this is
%its copy on the hot path, and native_storage_shapes_agree binds them.
:- dynamic metta_ctx_declared/1.

%Monotone-conservative contract flag, set at the one funnel every native
%'&metta' write passes: flag ABSENT proves no declaration has ever named
%the context, so the per-call guards below skip their probes outright;
%flag PRESENT only means "run the real probes", so a declaration removed
%or rolled back later costs nothing but the shortcut. The subject is
%conservatively the declaration's first argument whatever the head,
%because over-flagging a non-context symbol is harmless while missing a
%real context would silently skip a guard. This closes CA-7's open
%squeeze: the undeclared pure-Prolog foreign match paid the handles,
%source and on-error probes on every call.
metta_note_ctx_declared([Head|_]) :-
    metta_catalog_head(Head),
    !.
metta_note_ctx_declared([_, Ctx|_]) :-
    atom(Ctx),
    \+ metta_ctx_declared(Ctx),
    !,
    assertz(metta_ctx_declared(Ctx)).
metta_note_ctx_declared(_).

%The same monotone-conservative shortcut narrowed to the events head, and it
%is the one head that needs its own: a (subscription ...) atom names a SPACE
%in the same position, so every standing query flags its own space as
%ctx-declared and the general flag can no longer say "this context declared
%nothing about events". Without a flag the admission check walked the growing
%'&metta' store on every subscription: one subscribe cost 983,768
%instructions before the check existed, 1,093,524 with the check and 988,037
%with the flag, so the capability costs 0.43% rather than 11.2% [measured
%2026-08-21, instructions:u per subscribe, 1,000 standing queries against a
%0-query baseline, min of 3].
%
%It is set from metta_check_catalog_semantics/3 rather than from the walk
%above, and the difference is measured: that walk runs on EVERY '&metta'
%write and its first argument is a list, so every clause added to it is one
%inference on every write, which register-op's benchmark caught at +94 over
%its declarations. The semantics check dispatches on the head ATOM, so a
%clause for one head costs the other heads nothing.
:- dynamic metta_events_declared/1.

%The catalog's own rows never name a context in their first argument, a
%kind head or a vocabulary name being what sits there, and flagging those
%grew metta_ctx_declared from a handful of real contexts to forty rows,
%which the guards' first miss then paid as a linear walk before the JIT
%index built [measured 2026-08-20: the single-pattern snapshot probe read
%687 against 685 by warm-up order]. Skipping them keeps the flag exactly
%what it says: a context some declaration names.
metta_catalog_head(kind).
metta_catalog_head(vocabulary).
metta_catalog_head(claim).
metta_catalog_head(policy).
metta_catalog_head('routed-by-shape').
metta_catalog_head('dispatch-default').
metta_catalog_head('dispatch-policy').
metta_catalog_head(deprecated).
metta_catalog_head(visibility).

add_sexp_in(Module, [Family|Parameters], [Rel|Args], Ref) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Term =.. ['$metta_parametric_atom', Rel|Args],
    assertz(Module:Term, Ref).
add_sexp_in(Module, Space, [Rel|Args], Ref) :- !,
                                               Term =.. [Space, Rel | Args],
                                               assertz(Module:Term, Ref).
%A scalar or empty expression cannot be a plain Space(Term) fact, because that
%is already the encoding of the singleton expression (Term). It gets its own
%predicate rather than a marked rule inside the space: a marked rule makes
%every clause of the space predicate a rule, so reading one back has to go
%through clause/2, which walks the clause list instead of using SWI's clause
%indexing. Measured on examples/ch22-a-reasoner-you-can-serve/22-03-search/03-matespace.metta, that cost 15.3x,
%99.5 billion instructions against 1,520 billion. Keeping scalars in
%the private scalar predicate leaves expressions as facts a direct indexed
%call reaches.
add_sexp_in(Module, _, Atom, Ref) :-
    assertz(Module:'$metta_native_scalar'(Atom), Ref).

%%%% The catalog describes its own kinds %%%%
%
%Three declaration heads make the catalog self-describing, themselves
%ordinary '&metta' atoms a program can match and remove:
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
%The checker runs at the two doors every native '&metta' write passes, the
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
%metta_ctx_declared rule: a removed kind row means later adds of that head
%pass unchecked, and remove-then-redeclare, even WIDER than the shipped
%preset, is how a program deliberately loosens a shipped kind.
%
%Self-description bootstraps by declaration order: the presets below add the
%vocabularies first, then (kind kind ...) while no kind row exists yet, so
%it enters unchecked, and from that atom on every (kind ...) add is
%validated against it, its argspecs walked by the same checker that walks
%any other declaration.
metta_declaration_check(Term) :-
    Term = [Head|Args],
    atom(Head),
    metta_kind_spec(Head, Spec),
    !,
    metta_check_positions(Args, Spec, 1, Term),
    metta_check_catalog_semantics(Head, Args, Term).
metta_declaration_check(_).

%A landed catalog row must beat any negative cache row for its subject:
%the positive rows self-heal through their stored reference, the negative
%ones have nothing to watch, so the write funnel retracts them here. A
%kind or routing row landing also rebuilds its head's materialized route
%dispatch, which is how the shipped routes come up during the preset walk
%and how a third-party routed kind starts routing the moment its rows are
%in.
metta_catalog_note_added(['dispatch-policy', Function, Axis, _]) :-
    !,
    metta_dispatch_cache_forget(Function, Axis),
    metta_dispatch_policy_changed(Function, Axis).
metta_catalog_note_added(['dispatch-default', Axis, _]) :-
    !,
    metta_dispatch_default_cache_forget(Axis),
    metta_dispatch_default_changed(Axis).
metta_catalog_note_added([kind, Head|_]) :-
    !,
    retractall(metta_kind_cache(Head, _, _)),
    metta_materialize_route(Head).
metta_catalog_note_added([vocabulary, Vocab|_]) :-
    !,
    retractall(metta_vocab_cache(Vocab, _, _)).
metta_catalog_note_added(['routed-by-shape', Head|_]) :-
    !,
    metta_materialize_route(Head).
metta_catalog_note_added([algebra, Name|_]) :-
    !,
    retractall(metta_algebra_descriptor_cache(Name, _, _, _, _, _, _, _)).
metta_catalog_note_added([annotations, Ctx|_]) :-
    !,
    retractall(metta_annotations_cache(Ctx, _)).
metta_catalog_note_added([cache, Function, _]) :-
    !,
    metta_cache_policy_changed(Function).
metta_catalog_note_added([tabled, _, Function, _]) :-
    !,
    metta_cache_policy_changed(Function).
metta_catalog_note_added([capacity, Pool, _]) :-
    !,
    metta_capacity_contract_added(Pool).
metta_catalog_note_added(_).

% A policy write is rare, while every equation compilation is hot. Materialize
% the typed root at mutation time over the function-view index the translated
% forms already maintain, then invalidate it. This gives stored callers the
% common forward walk without adding six edges to every compiled form.
metta_dispatch_policy_changed(Function, Axis) :-
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
metta_dispatch_default_changed(Axis) :-
    metta_dispatch_policy_changed(_, Axis).

metta_dispatch_all_changed :-
    forall(dispatch_axis_vocabulary(Axis, _),
           metta_dispatch_default_changed(Axis)).

%The removal twin, called by the '&metta' clause of remove_sexp below for
%a row that actually left. A variable head means the caller removed by
%pattern and anything may have gone, so everything derived is dropped and
%rebuilt, which over-invalidates and never under-invalidates.
metta_catalog_note_removed([Rel|_]) :-
    var(Rel),
    !,
    retractall(metta_kind_cache(_, _, _)),
    retractall(metta_vocab_cache(_, _, _)),
    retractall(metta_algebra_descriptor_cache(_, _, _, _, _, _, _, _)),
    retractall(metta_annotations_cache(_, _)),
    retractall(metta_dispatch_value_cache(_, _, _, _)),
    metta_materialize_routes,
    metta_capacity_counts_prune,
    metta_dispatch_all_changed,
    metta_cache_policy_changed(_).
metta_catalog_note_removed(['dispatch-policy', Function, Axis, _]) :-
    !,
    metta_dispatch_cache_forget(Function, Axis),
    metta_dispatch_policy_changed(Function, Axis).
metta_catalog_note_removed(['dispatch-default', Axis, _]) :-
    !,
    metta_dispatch_default_cache_forget(Axis),
    metta_dispatch_default_changed(Axis).
metta_catalog_note_removed([kind, Head|_]) :-
    !,
    retractall(metta_kind_cache(Head, _, _)),
    metta_materialize_route(Head).
metta_catalog_note_removed([vocabulary, Vocab|_]) :-
    !,
    retractall(metta_vocab_cache(Vocab, _, _)).
metta_catalog_note_removed(['routed-by-shape', Head|_]) :-
    !,
    metta_materialize_route(Head).
metta_catalog_note_removed([algebra, Name|_]) :-
    !,
    retractall(metta_algebra_descriptor_cache(Name, _, _, _, _, _, _, _)).
metta_catalog_note_removed([annotations, Ctx|_]) :-
    !,
    retractall(metta_annotations_cache(Ctx, _)).
metta_catalog_note_removed([cache, Function, _]) :-
    !,
    metta_cache_policy_changed(Function).
metta_catalog_note_removed([tabled, _, Function, _]) :-
    !,
    metta_cache_policy_changed(Function).
metta_catalog_note_removed([capacity|_]) :-
    !,
    metta_capacity_counts_prune.
metta_catalog_note_removed(_).

metta_cache_policy_changed(Function) :-
    forall(seam:cache_policy_changed(Function), true).

%One catalog row as a list, whatever its arity: '&metta'(kind, handles,
%symbol, ...) reads back as [kind, handles, symbol, ...]. The walk over the
%arities the storage module holds runs on catalog edits and cache misses,
%never on a match path and never on the per-write fast path below.
metta_catalog_row(Row) :-
    metta_catalog_clause(Row, _).

metta_catalog_clause([Rel|Args], Ref) :-
    native_storage_module('&metta', Module),
    current_predicate(Module:'&metta'/N),
    N >= 1,
    functor(Goal, '&metta', N),
    Goal =.. ['&metta', Rel|Args],
    clause(Module:Goal, true, Ref).

%The write-path cache. The checker runs on every '&metta' write, and the
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
:- dynamic metta_kind_cache/3.    %Head, Spec | none, ref(Ref) | none
:- dynamic metta_vocab_cache/3.   %Vocab, Values | none, ref(Ref) | none
:- dynamic metta_annotations_cache/2. %Ctx, Algebra
:- dynamic metta_algebra_descriptor_cache/8.
%Name, Combine, Extend, Zero, One, Laws, Carrier, Requires
:- dynamic metta_dispatch_value_cache/4. %Function, Axis, Value | none, ref(Ref) | none

%A compiled call can ask four dispatch axes on every recursive step. Walking
%the variadic catalog storage for each question makes the loop proportional
%to the size of the whole catalog. This cache keeps &metta authoritative: the
%value carries the exact override or default clause reference that supplied
%it, mutation callbacks forget affected keys, and a transaction rollback or
%source withdrawal self-heals through the erased-reference check.
metta_dispatch_value(Function, Axis, Value) :-
    (   metta_dispatch_value_cache(Function, Axis, Cached, Validity)
    ->  (   Validity = ref(Ref)
        ->  (   metta_catalog_ref_erased(Ref)
            ->  retractall(metta_dispatch_value_cache(Function, Axis, _, _)),
                metta_dispatch_value_fresh(Function, Axis, Value)
            ;   Value = Cached
            )
        ;   fail
        )
    ;   metta_dispatch_value_fresh(Function, Axis, Value)
    ).

metta_dispatch_value_fresh(Function, Axis, Value) :-
    (   metta_catalog_clause(['dispatch-policy', Function, Axis, Fresh], Ref)
    ->  assertz(metta_dispatch_value_cache(Function, Axis, Fresh, ref(Ref))),
        Value = Fresh
    ;   metta_catalog_clause(['dispatch-default', Axis, Fresh], Ref)
    ->  assertz(metta_dispatch_value_cache(Function, Axis, Fresh, ref(Ref))),
        Value = Fresh
    ;   assertz(metta_dispatch_value_cache(Function, Axis, none, none)),
        fail
    ).

metta_dispatch_cache_forget(Function, Axis) :-
    retractall(metta_dispatch_value_cache(Function, Axis, _, _)).

metta_dispatch_default_cache_forget(Axis) :-
    retractall(metta_dispatch_value_cache(_, Axis, _, _)).

metta_kind_spec(Head, Spec) :-
    (   metta_kind_cache(Head, Spec0, Validity)
    ->  (   Validity = ref(Ref)
        ->  (   metta_catalog_ref_erased(Ref)
            ->  retractall(metta_kind_cache(Head, _, _)),
                metta_kind_spec_fresh(Head, Spec)
            ;   Spec = Spec0
            )
        ;   fail
        )
    ;   metta_kind_spec_fresh(Head, Spec)
    ).

%A reference whose clause is gone, by property or by the reference itself
%having been collected, either way the cached row is stale.
metta_catalog_ref_erased(Ref) :-
    catch(clause_property(Ref, erased), _, true).

metta_kind_spec_fresh(Head, Spec) :-
    (   metta_catalog_clause([kind, Head|Fresh], Ref)
    ->  assertz(metta_kind_cache(Head, Fresh, ref(Ref))),
        Spec = Fresh
    ;   assertz(metta_kind_cache(Head, none, none)),
        fail
    ).

metta_vocabulary_values(Vocab, Values) :-
    (   metta_vocab_cache(Vocab, Values0, Validity)
    ->  (   Validity = ref(Ref)
        ->  (   metta_catalog_ref_erased(Ref)
            ->  retractall(metta_vocab_cache(Vocab, _, _)),
                metta_vocabulary_values_fresh(Vocab, Values)
            ;   Values = Values0
            )
        ;   fail
        )
    ;   metta_vocabulary_values_fresh(Vocab, Values)
    ).

metta_vocabulary_values_fresh(Vocab, Values) :-
    (   metta_catalog_clause([vocabulary, Vocab|Fresh], Ref)
    ->  assertz(metta_vocab_cache(Vocab, Fresh, ref(Ref))),
        Values = Fresh
    ;   assertz(metta_vocab_cache(Vocab, none, none)),
        fail
    ).

%One value's membership, the question every consulting site asks.
metta_vocabulary_value(Vocab, Value) :-
    metta_vocabulary_values(Vocab, Values),
    memberchk(Value, Values).

%The compatibility projection lives beside the vocabulary it projects into.
%pure=true and the old immutable spelling mean pureStructural; stable means
%readOnlyLookup; volatile means oracleIO. The first clause keeps every
%canonical value data-driven from the catalog, so adding an alias cannot make
%it a sixth public EffectClass member.
%[tested:
%effects_lattice:legacy_effect_spellings_map_but_cannot_enter_the_canonical_catalog;
%commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0]
metta_effect_class_canonical(Value, Canonical) :-
    nonvar(Value),
    !,
    (   metta_vocabulary_value('effect-class', Value)
    ->  Canonical = Value
    ;   metta_legacy_effect_class(Value, Canonical)
    ).
metta_effect_class_canonical(Canonical, Canonical) :-
    metta_vocabulary_values('effect-class', Values),
    member(Canonical, Values).

metta_legacy_effect_class(immutable, pureStructural).
metta_legacy_effect_class(stable, readOnlyLookup).
metta_legacy_effect_class(volatile, oracleIO).

%The positional walk. Position counts declaration arguments from 1, the way
%the refusal prints them; the Expected a refusal carries is the argspec as
%declared, so the message shows the row's own words.
metta_check_positions([], [], _, _) :- !.
metta_check_positions([], [Spec|Rest], Position, Term) :-
    !,
    (   forall(member(S, [Spec|Rest]), metta_spec_omittable(S))
    ->  true
    ;   metta_declaration_refused(Term, Position, Spec)
    ).
metta_check_positions([_|_], [], Position, Term) :-
    !,
    metta_declaration_refused(Term, Position, 'no further argument').
metta_check_positions(Args, [[rest, Spec]], Position, Term) :-
    !,
    metta_check_rest(Args, Spec, Position, Term).
metta_check_positions([Arg|Args], [[optional, Spec]|Rest], Position, Term) :-
    !,
    metta_check_value(Arg, Spec, Position, Term),
    Next is Position + 1,
    metta_check_positions(Args, Rest, Next, Term).
metta_check_positions([Arg|Args], [Spec|Rest], Position, Term) :-
    metta_check_value(Arg, Spec, Position, Term),
    Next is Position + 1,
    metta_check_positions(Args, Rest, Next, Term).

metta_check_rest([], _, _, _).
metta_check_rest([Arg|Args], Spec, Position, Term) :-
    metta_check_value(Arg, Spec, Position, Term),
    Next is Position + 1,
    metta_check_rest(Args, Spec, Next, Term).

metta_spec_omittable([optional, _]).
metta_spec_omittable([rest, _]).

metta_check_value(Arg, symbol, Position, Term) :-
    !,
    (   atom(Arg) -> true ; metta_declaration_refused(Term, Position, symbol) ).
metta_check_value(Arg, integer, Position, Term) :-
    !,
    (   integer(Arg) -> true ; metta_declaration_refused(Term, Position, integer) ).
metta_check_value(_, pattern, _, _) :- !.
metta_check_value(_, term, _, _) :- !.
metta_check_value(Arg, ['one-of', Vocab], Position, Term) :-
    !,
    (   atom(Arg),
        metta_vocabulary_values(Vocab, Values),
        memberchk(Arg, Values)
    ->  true
    ;   metta_declaration_refused(Term, Position, ['one-of', Vocab])
    ).
metta_check_value(_, Spec, Position, Term) :-
    metta_declaration_refused(Term, Position, Spec).

%kind and claim rows carry meaning past their shape, and the checker owns
%their language, so their adds get the deeper walk: a kind's argspecs must
%be well-formed with optional confined to the tail and rest final, and a
%claim must name a declared vocabulary and one of its values. Everything
%else was already covered by the positional walk.
metta_check_catalog_semantics(kind, [KindHead|Spec], Term) :-
    !,
    (   metta_kind_spec(KindHead, _)
    ->  metta_declaration_refused(Term, 1,
                                  'one kind row per head; remove the old row first')
    ;   true
    ),
    metta_check_argspecs(Spec, 2, Term),
    %A head already routed by shape keeps routable: redeclaring its kind
    %(remove, then add) with a spec the route cannot dispatch would leave a
    %standing routed-by-shape row over an unroutable shape, so the unfit
    %spec is refused here rather than discovered as dead routing.
    (   metta_routed_head(KindHead, Key)
    ->  metta_check_route_fit(Key, Spec, Term)
    ;   true
    ).
metta_check_catalog_semantics('routed-by-shape', [Head|KeyArgs], Term) :-
    !,
    (   KeyArgs == []
    ->  Key = context
    ;   KeyArgs = [Key]
    ),
    (   metta_kind_spec(Head, Spec)
    ->  metta_check_route_fit(Key, Spec, Term)
    ;   metta_declaration_refused(Term, 1,
                                  'a kind row for the routed head, declared first')
    ).
metta_check_catalog_semantics(vocabulary, [Name|_], Term) :-
    !,
    (   metta_vocabulary_values(Name, _)
    ->  metta_declaration_refused(Term, 1,
                                  'one vocabulary row per name; remove the old row first')
    ;   true
    ).
metta_check_catalog_semantics(policy, [Axis|_], Term) :-
    !,
    (   metta_catalog_row([policy, Axis, _, _])
    ->  metta_declaration_refused(Term, 1,
                                  'one policy row per axis; remove the old row first')
    ;   true
    ).
metta_check_catalog_semantics(claim, [Vocab, Value|_], Term) :-
    !,
    (   metta_vocabulary_values(Vocab, Values)
    ->  (   memberchk(Value, Values)
        ->  true
        ;   metta_declaration_refused(Term, 2, 'a value of the vocabulary')
        )
    ;   metta_declaration_refused(Term, 1, 'a declared vocabulary')
    ).
metta_check_catalog_semantics(algebra,
                              [Name, Combine, Extend, Zero, One,
                               Laws, Carrier, Requires],
                              Term) :-
    !,
    (   metta_catalog_row([algebra, Name|_])
    ->  metta_declaration_refused(
            Term, 1, 'one algebra row per name; remove the old row first')
    ;   true
    ),
    metta_algebra_list_field(Laws, laws, Term, 6),
    metta_algebra_carrier_field(Carrier, Term),
    metta_algebra_list_field(Requires, requires, Term, 8),
    metta_check_algebra_laws(Name, Combine, Extend, Zero, One,
                             Laws, Carrier, Term).
metta_check_catalog_semantics(annotations, [Ctx, Algebra|CapabilityArgs], Term) :-
    !,
    metta_declared_algebra_requirements(Algebra, Required, Term),
    metta_annotation_capabilities(CapabilityArgs, Capabilities, Term),
    (   member(Requirement, Required),
        \+ memberchk(Requirement, Capabilities)
    ->  metta_algebra_requirement_refusal(Ctx, Algebra, Requirement)
    ;   true
    ).
metta_check_catalog_semantics(cache, [Function, _], Term) :-
    !,
    (   metta_catalog_row([cache, Function, _])
    ->  metta_declaration_refused(
            Term, 1, 'one cache override per function; remove the old row first')
    ;   true
    ).
metta_check_catalog_semantics('dispatch-default', [Axis, Value], Term) :-
    !,
    metta_check_dispatch_value(Axis, Value, Term),
    (   metta_catalog_row(['dispatch-default', Axis, _])
    ->  metta_declaration_refused(Term, 1,
                                  'one default per dispatch axis; remove the old row first')
    ;   true
    ).
metta_check_catalog_semantics('dispatch-policy', [Function, Axis, Value], Term) :-
    !,
    metta_check_dispatch_value(Axis, Value, Term),
    (   metta_catalog_row(['dispatch-policy', Function, Axis, _])
    ->  metta_declaration_refused(Term, 2,
                                  'one override per function and dispatch axis; remove the old row first')
    ;   true
    ).
%A compensation is useful only for an operation whose successful answer leaves
%a saga receipt. The receipt threshold and this declaration threshold are the
%same rank comparison, so a row cannot promise recovery for work the runner
%will never journal. A recovery takes exactly the one quoted receipt the runner
%passes. Host-operation rows record that MeTTa arity directly; a compiled
%function records one more Prolog argument for its answer.
metta_check_catalog_semantics(compensates,
                              [Operation, Compensation], Term) :-
    !,
    metta_require_saga_effect(Operation, Term),
    (   metta_saga_operation_callable(Operation)
    ->  true
    ;   metta_declaration_refused(
            Term, 1,
            'a registered host operation, native operation, or compiled MeTTa function')
    ),
    (   metta_saga_compensation_callable(Compensation)
    ->  true
    ;   metta_declaration_refused(
            Term, 2,
            'a registered host operation or compiled MeTTa function taking exactly one receipt')
    ),
    (   metta_catalog_row([compensates, Operation, _])
    ->  metta_declaration_refused(
            Term, 1,
            'one compensation per operation; remove the old row first')
    ;   true
    ).

%A standing query is a PROMISE about the watched context, so it is checked
%against what that context declares it can deliver, here at the catalog
%door every '&metta' write already passes rather than at one host's
%subscribe method. (subscription ...) is the reflection atom every
%subscription writes before it activates and (on ...) is a declared
%reaction, and both hear a context only through its change events, so a
%context with no (events ...) capability refuses both, naming what is
%missing. One authority, one door, every host: a MeTTa program adding the
%atom by hand is refused exactly as the Python surface is
%[tested: test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses].
metta_check_catalog_semantics(events, [Ctx|_], _) :-
    !,
    (   atom(Ctx), \+ metta_events_declared(Ctx)
    ->  assertz(metta_events_declared(Ctx))
    ;   true
    ).
metta_check_catalog_semantics(subscription, [Ctx|_], _) :-
    !,
    metta_require_events(Ctx, 'be subscribed to').
metta_check_catalog_semantics(on, [Ctx|_], _) :-
    !,
    metta_require_events(Ctx, 'carry a reaction').
metta_check_catalog_semantics(_, _, _).

metta_require_saga_effect(Operation, Term) :-
    metta_operation_effect(Operation, Effect),
    !,
    metta_effect_rank(Effect, Rank),
    metta_effect_rank(writesState, ReceiptRank),
    (   Rank >= ReceiptRank
    ->  true
    ;   metta_declaration_refused(
            Term, 1,
            'an operation ranked writesState or oracleIO, because weaker operations leave no saga receipt')
    ).
metta_require_saga_effect(_, Term) :-
    metta_declaration_refused(
        Term, 1, 'an operation with a declared effect class'),
    fail.

metta_saga_operation_callable(Name) :-
    metta_catalog_row([op, Name, _, _]),
    !.
metta_saga_operation_callable(Name) :-
    builtin_fun(Name),
    !.
metta_saga_operation_callable(Name) :-
    fun(Name),
    metta_ensure_compiled(Name),
    arity(Name, Arity),
    Arity > 0.

metta_saga_compensation_callable(Name) :-
    metta_catalog_row([op, Name, 1, _]),
    !.
metta_saga_compensation_callable(Name) :-
    fun(Name),
    metta_ensure_compiled(Name),
    arity(Name, 2).

metta_declared_algebra_requirements(Algebra, Required, _) :-
    metta_catalog_row([algebra, Algebra, _, _, _, _, _, _,
                       [requires|Required]]),
    !.
metta_declared_algebra_requirements(_, _, Term) :-
    metta_declaration_refused(Term, 2, 'a declared algebra').

metta_algebra_list_field([Head|Values], Head, _, _) :-
    atom(Head),
    maplist(atom, Values),
    !.
metta_algebra_list_field(_, Head, Term, Position) :-
    metta_declaration_refused(Term, Position, [Head, '... symbols']).

metta_algebra_carrier_field([carrier|Values], Term) :-
    !,
    (   maplist(ground, Values)
    ->  true
    ;   metta_declaration_refused(Term, 7, [carrier, '... ground atoms'])
    ).
metta_algebra_carrier_field(_, Term) :-
    metta_declaration_refused(Term, 7, [carrier, '... atoms']).

%A public law is a certificate, not a planner hint. User rows therefore name
%only this vocabulary and supply a finite carrier for every equation; shipped
%rows are trusted data presets whose laws are proved by their source modules.
metta_algebra_equational_law('combine-associative').
metta_algebra_equational_law('combine-commutative').
metta_algebra_equational_law('extend-associative').
metta_algebra_equational_law('extend-commutative').
metta_algebra_equational_law('left-distributive').
metta_algebra_equational_law('right-distributive').
metta_algebra_equational_law('combine-idempotent').
metta_algebra_equational_law('combine-zero-identity').
metta_algebra_equational_law('extend-one-identity').
metta_algebra_equational_law('extend-zero-annihilates').

metta_algebra_known_law(contraction).
metta_algebra_known_law(Law) :- metta_algebra_equational_law(Law).

metta_check_algebra_laws(Name, Combine, Extend, Zero, One,
                         [laws|Laws], [carrier|Carrier], Term) :-
    (   member(Unknown, Laws),
        \+ metta_algebra_known_law(Unknown)
    ->  throw(error(metta_algebra_law_unknown(Name, Unknown), none))
    ;   true
    ),
    findall(Law, ( member(Law, Laws),
                   metta_algebra_equational_law(Law) ), Equational),
    (   Equational == []
    ->  true
    ;   Carrier == [],
        \+ metta_catalog_preset(Term)
    ->  throw(error(metta_algebra_law_uncheckable(Name, Equational,
                                                  finite_carrier_required),
                    none))
    ;   Carrier == []
    ->  true
    ;   metta_check_algebra_closure(Name, Combine, Extend, Carrier),
        forall(member(Law, Equational),
               metta_check_algebra_law(Name, Combine, Extend, Zero, One,
                                       Carrier, Law))
    ).

metta_check_algebra_closure(Name, Combine, Extend, Carrier) :-
    % policy-inventory-exempt: mechanism-internal; reason=Combine and Extend are the algebra row's own two declared operation names rather than a closed value set; evidence=engine/spaces/catalog.pl:metta_check_algebra_laws/8
    forall(( member(Operation, [Combine, Extend]),
             member(A, Carrier), member(B, Carrier) ),
           ( metta_apply_algebra_operation(Name, Operation, A, B, Result),
             (   memberchk(Result, Carrier)
             ->  true
             ;   throw(error(metta_algebra_carrier_not_closed(
                                 Name, Operation, A, B, Result), none))
             ) )).

metta_algebra_apply(Name, Operation, A, B, Result) :-
    metta_apply_algebra_operation(Name, Operation, A, B, Result).

metta_check_algebra_law(Name, Combine, _, _, _, Carrier,
                        'combine-associative') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( metta_algebra_apply(Name, Combine, A, B, AB),
             metta_algebra_apply(Name, Combine, AB, C, Left),
             metta_algebra_apply(Name, Combine, B, C, BC),
             metta_algebra_apply(Name, Combine, A, BC, Right),
             metta_require_algebra_equal(Name, 'combine-associative',
                                         [A,B,C], Left, Right) )).
metta_check_algebra_law(Name, Combine, _, _, _, Carrier,
                        'combine-commutative') :- !,
    forall(( member(A, Carrier), member(B, Carrier) ),
           ( metta_algebra_apply(Name, Combine, A, B, Left),
             metta_algebra_apply(Name, Combine, B, A, Right),
             metta_require_algebra_equal(Name, 'combine-commutative',
                                         [A,B], Left, Right) )).
metta_check_algebra_law(Name, _, Extend, _, _, Carrier,
                        'extend-associative') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( metta_algebra_apply(Name, Extend, A, B, AB),
             metta_algebra_apply(Name, Extend, AB, C, Left),
             metta_algebra_apply(Name, Extend, B, C, BC),
             metta_algebra_apply(Name, Extend, A, BC, Right),
             metta_require_algebra_equal(Name, 'extend-associative',
                                         [A,B,C], Left, Right) )).
metta_check_algebra_law(Name, _, Extend, _, _, Carrier,
                        'extend-commutative') :- !,
    forall(( member(A, Carrier), member(B, Carrier) ),
           ( metta_algebra_apply(Name, Extend, A, B, Left),
             metta_algebra_apply(Name, Extend, B, A, Right),
             metta_require_algebra_equal(Name, 'extend-commutative',
                                         [A,B], Left, Right) )).
metta_check_algebra_law(Name, Combine, Extend, _, _, Carrier,
                        'left-distributive') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( metta_algebra_apply(Name, Combine, B, C, BC),
             metta_algebra_apply(Name, Extend, A, BC, Left),
             metta_algebra_apply(Name, Extend, A, B, AB),
             metta_algebra_apply(Name, Extend, A, C, AC),
             metta_algebra_apply(Name, Combine, AB, AC, Right),
             metta_require_algebra_equal(Name, 'left-distributive',
                                         [A,B,C], Left, Right) )).
metta_check_algebra_law(Name, Combine, Extend, _, _, Carrier,
                        'right-distributive') :- !,
    forall(( member(A, Carrier), member(B, Carrier), member(C, Carrier) ),
           ( metta_algebra_apply(Name, Combine, A, B, AB),
             metta_algebra_apply(Name, Extend, AB, C, Left),
             metta_algebra_apply(Name, Extend, A, C, AC),
             metta_algebra_apply(Name, Extend, B, C, BC),
             metta_algebra_apply(Name, Combine, AC, BC, Right),
             metta_require_algebra_equal(Name, 'right-distributive',
                                         [A,B,C], Left, Right) )).
metta_check_algebra_law(Name, Combine, _, _, _, Carrier,
                        'combine-idempotent') :- !,
    forall(member(A, Carrier),
           ( metta_algebra_apply(Name, Combine, A, A, Result),
             metta_require_algebra_equal(Name, 'combine-idempotent',
                                         [A], Result, A) )).
metta_check_algebra_law(Name, Combine, _, Zero, _, Carrier,
                        'combine-zero-identity') :- !,
    metta_check_algebra_identity(Name, Combine, Zero, Carrier,
                                 'combine-zero-identity').
metta_check_algebra_law(Name, _, Extend, _, One, Carrier,
                        'extend-one-identity') :- !,
    metta_check_algebra_identity(Name, Extend, One, Carrier,
                                 'extend-one-identity').
metta_check_algebra_law(Name, _, Extend, Zero, _, Carrier,
                        'extend-zero-annihilates') :- !,
    forall(member(A, Carrier),
           ( metta_algebra_apply(Name, Extend, Zero, A, Left),
             metta_require_algebra_equal(Name, 'extend-zero-annihilates',
                                         [Zero,A], Left, Zero),
             metta_algebra_apply(Name, Extend, A, Zero, Right),
             metta_require_algebra_equal(Name, 'extend-zero-annihilates',
                                         [A,Zero], Right, Zero) )).

metta_check_algebra_identity(Name, Operation, Identity, Carrier, Law) :-
    forall(member(A, Carrier),
           ( metta_algebra_apply(Name, Operation, Identity, A, Left),
             metta_require_algebra_equal(Name, Law, [Identity,A], Left, A),
             metta_algebra_apply(Name, Operation, A, Identity, Right),
             metta_require_algebra_equal(Name, Law, [A,Identity], Right, A) )).

metta_require_algebra_equal(_, _, _, Left, Right) :- Left == Right, !.
metta_require_algebra_equal(Name, Law, Inputs, Left, Right) :-
    throw(error(metta_algebra_law_violation(Name, Law, Inputs, Left, Right),
                none)).

metta_annotation_capabilities([], [], _) :- !.
metta_annotation_capabilities([[capabilities|Capabilities]], Capabilities, Term) :-
    !,
    (   maplist(atom, Capabilities)
    ->  true
    ;   metta_declaration_refused(Term, 3, [capabilities, '... symbols'])
    ).
metta_annotation_capabilities(_, _, Term) :-
    metta_declaration_refused(Term, 3, [capabilities, '... symbols']).

metta_algebra_requirement_refusal(Ctx, amplitude, Requirement) :-
    !,
    throw(error(metta_amplitude_fragment_refused(Ctx, Requirement), none)).
metta_algebra_requirement_refusal(Ctx, Algebra, Requirement) :-
    throw(error(metta_algebra_requirement_missing(Ctx, Algebra, Requirement),
                none)).

metta_check_dispatch_value(Axis, Value, Term) :-
    (   dispatch_axis_vocabulary(Axis, Vocabulary)
    ->  (   metta_vocabulary_value(Vocabulary, Value)
        ->  true
        ;   metta_declaration_refused(Term, 3,
                                      ['one-of', Vocabulary])
        )
    ;   metta_declaration_refused(Term, 2, 'a declared dispatch axis')
    ).

dispatch_axis_vocabulary('MismatchEnum', 'MismatchEnum').
dispatch_axis_vocabulary('NoMatchEnum', 'NoMatchEnum').
dispatch_axis_vocabulary('EvaluationOrderEnum', 'EvaluationOrderEnum').
dispatch_axis_vocabulary('FunctionResultEnum', 'FunctionResultEnum').
dispatch_axis_vocabulary('ClauseFailedEnum', 'ClauseFailedEnum').
dispatch_axis_vocabulary('OutOfClausesEnum', 'OutOfClausesEnum').

metta_check_argspecs([], _, _).
metta_check_argspecs([Spec|Rest], Position, Term) :-
    metta_check_argspec_form(Spec, Position, Term),
    (   Spec = [rest, _], Rest \== []
    ->  metta_declaration_refused(Term, Position, 'rest only in final position')
    ;   Spec = [optional, _], Rest = [NextSpec|_], \+ metta_spec_omittable(NextSpec)
    ->  metta_declaration_refused(Term, Position, 'optional only in the tail')
    ;   true
    ),
    Next is Position + 1,
    metta_check_argspecs(Rest, Next, Term).

metta_check_argspec_form(symbol, _, _) :- !.
metta_check_argspec_form(integer, _, _) :- !.
metta_check_argspec_form(pattern, _, _) :- !.
metta_check_argspec_form(term, _, _) :- !.
metta_check_argspec_form(['one-of', Vocab], Position, Term) :-
    !,
    (   atom(Vocab),
        metta_vocabulary_values(Vocab, _)
    ->  true
    ;   metta_declaration_refused(Term, Position,
                                  'a vocabulary declared before the kind that names it')
    ).
metta_check_argspec_form([optional, Spec], Position, Term) :-
    !,
    metta_check_argspec_form(Spec, Position, Term).
metta_check_argspec_form([rest, Spec], Position, Term) :-
    !,
    metta_check_argspec_form(Spec, Position, Term).
metta_check_argspec_form(_, Position, Term) :-
    metta_declaration_refused(Term, Position, 'an argspec').

metta_declaration_refused(Term, Position, Expected) :-
    throw(error(metta_declaration_malformed(Term, Position, Expected), none)).

%%%% Materialized shape-route dispatch %%%%
%
%(routed-by-shape Head [Key]) in the catalog makes (Head ...) declarations
%route by shape through metta.pl's one algorithm: specificity over adorned
%entries, coherence among the maximal ones. The materializer compiles the
%head's kind row into the exact metta_shape_fact/4 and
%metta_shape_declared/2 clauses the router dispatches on, one fact clause
%per stored arity with omitted trailing optionals padded to none, and one
%guard clause probing those arities, so consulting a route costs what the
%hand-written clauses cost, indexed clause dispatch, and the catalog pays
%at its own writes: every add or removal of a kind or routing row lands in
%the notes above and rebuilds that head's clauses from the rows then
%standing. The shipped handles, on-error and merge dispatch is built by
%this same walk from the presets below, which is what makes a third-party
%routed kind and a shipped one the same thing.
metta_materialize_routes :-
    forall(metta_routed_head(Head, _), metta_materialize_route(Head)).

metta_routed_head(Head, Key) :-
    metta_catalog_row(['routed-by-shape', Head|KeyArgs]),
    (   KeyArgs == []
    ->  Key = context
    ;   KeyArgs = [Key]
    ).

metta_materialize_route(Head) :-
    \+ atom(Head),
    !,
    metta_materialize_routes.
metta_materialize_route(Head) :-
    retractall(metta_shape_fact(Head, _, _, _)),
    retractall(metta_shape_declared(Head, _)),
    (   metta_routed_head(Head, Key),
        metta_kind_spec(Head, Spec),
        metta_route_shape(Key, Spec, PayloadSpecs)
    ->  forall(metta_payload_slice(PayloadSpecs, Stored, Payload),
               metta_assert_route_fact(Key, Head, Stored, Payload)),
        metta_assert_route_guard(Key, Head, PayloadSpecs)
    ;   true
    ).

%How a kind row reads as a route: a context-keyed route is (head ctx-symbol
%entry-pattern payload...), a global one is (head entry-pattern payload...),
%and the payload may not carry rest, whose open arity nothing could probe.
metta_route_shape(context, [symbol, pattern|PayloadSpecs], PayloadSpecs) :-
    \+ memberchk([rest, _], PayloadSpecs).
metta_route_shape(global, [pattern|PayloadSpecs], PayloadSpecs) :-
    \+ memberchk([rest, _], PayloadSpecs).

metta_check_route_fit(Key, Spec, Term) :-
    (   metta_route_shape(Key, Spec, _)
    ->  true
    ;   metta_declaration_refused(Term, 1,
            'a kind row the route can dispatch: (symbol pattern payload...) \c
             under the context key, (pattern payload...) under global, \c
             payload without rest')
    ).

%Stored and consumed payload pairs, one per legal arity: mandatory specs
%are always stored, and the first omitted trailing optional pads every
%remaining consumed position with none, which is the padding the handles
%consumers have always read for an entry that declared no determinism.
metta_payload_slice([], [], []).
metta_payload_slice([_Spec|Specs], [V|Stored], [V|Payload]) :-
    metta_payload_slice(Specs, Stored, Payload).
metta_payload_slice([[optional, _]|Specs], [], [none|Padding]) :-
    metta_payload_padding(Specs, Padding).

metta_payload_padding([], []).
metta_payload_padding([_|Specs], [none|Padding]) :-
    metta_payload_padding(Specs, Padding).

metta_assert_route_fact(context, Head, Stored, Payload) :-
    assertz((metta_shape_fact(Head, Ctx, Entry, Payload) :-
                 metta_contract_fact([Head, Ctx, Entry|Stored]))).
metta_assert_route_fact(global, Head, Stored, Payload) :-
    assertz((metta_shape_fact(Head, global, Entry, Payload) :-
                 metta_contract_fact([Head, Entry|Stored]))).

%The guard probes the smallest stored arity first, the common case (an
%entry declaring no trailing optionals), each probe deterministic the way
%the hand-written guards were.
metta_assert_route_guard(Key, Head, PayloadSpecs) :-
    findall(N,
            ( metta_payload_slice(PayloadSpecs, Stored, _),
              length(Stored, N) ),
            Ns),
    sort(0, @<, Ns, Arities),
    metta_route_probes(Key, Head, Module, Ctx, Arities, Probes),
    metta_probe_chain(Probes, Chain),
    assertz((metta_shape_declared(Head, Ctx) :-
                 metta_contract_storage(Module),
                 Chain)).

%A global route's guard leaves Ctx free on purpose: metta_shape_declared
%(merge, _) has always matched any context, the entries being keyed by
%query shape alone.
metta_route_probes(context, Head, Module, Ctx, Arities, Probes) :-
    maplist(metta_route_probe(Head, Module, Ctx), Arities, Probes).
metta_route_probes(global, Head, Module, _Ctx, Arities, Probes) :-
    maplist(metta_route_probe_global(Head, Module), Arities, Probes).

metta_route_probe(Head, Module, Ctx, N, Module:Goal) :-
    length(Vars, N),
    Goal =.. ['&metta', Head, Ctx, _Entry|Vars].
metta_route_probe_global(Head, Module, N, Module:Goal) :-
    length(Vars, N),
    Goal =.. ['&metta', Head, _Entry|Vars].

metta_probe_chain([Probe], (Probe -> true)) :- !.
metta_probe_chain([Probe|Probes], (Probe -> true ; Chain)) :-
    metta_probe_chain(Probes, Chain).

:- multifile prolog:error_message//1.
prolog:error_message(metta_declaration_malformed(Term, Position, Expected)) -->
    { Term = [Head|_],
      swrite(Term, TermText),
      (   is_list(Expected)
      ->  swrite(Expected, ExpectedText)
      ;   ExpectedText = Expected
      ) },
    [ 'the declaration ~w does not fit its declared kind: argument ~w \c
       expects ~w. Match (kind ~w $spec) in &metta to read the declared \c
       shape, or remove the kind row and redeclare it to widen the \c
       kind'-[TermText, Position, ExpectedText, Head] ].
prolog:error_message(metta_duplicate_declaration(Space, Second, First)) -->
    { swrite(Second, SecondText), swrite(First, FirstText) },
    [ 'the declaration ~w is a duplicate in ~w; the first declaration is ~w'-
      [SecondText, Space, FirstText] ].

%The shipped catalog, as data. Every row becomes an ordinary '&metta' atom
%when the directive below runs, matchable and removable like any other.
%Vocabularies come first; (kind kind ...) enters while no kind row exists
%to check it; every later row is validated by the self-description already
%in place, claims last so their kind row checks them. The value sets are
%exactly what an engine consultation site or generated binding surface acts
%on today, strict by design: a value no consumer acts on would pass the
%checker only to sit silently inert, the failure mode this catalog exists to
%make loud.
metta_catalog_preset([vocabulary, fidelity, 'Exact', 'Partial', 'Sound', 'Refuse']).
metta_catalog_preset([vocabulary, determinism, det, semidet, nondet]).
metta_catalog_preset([vocabulary, 'numeric-type', 'Number', 'BigInt']).
metta_catalog_preset([vocabulary, 'on-error-mode', keep, empty, abort]).
metta_catalog_preset([vocabulary, 'image-mode', opaque, transparent, auto]).
metta_catalog_preset([vocabulary, 'registry-image',
                      expression, symbol, handle, operations]).
metta_catalog_preset([vocabulary, 'answer-policy', depth, fair, 'best-first']).
metta_catalog_preset([vocabulary, semiring, bool, bag, counting, set, ranked,
                      tropical, prob, prov]).
metta_catalog_preset([vocabulary, 'source-kind', linear, repeated, peek]).
metta_catalog_preset([vocabulary, world, 'closed-world', 'open-world']).
metta_catalog_preset([vocabulary, atomicity,
                      transactional, 'atomic-single', 'best-effort']).
metta_catalog_preset([vocabulary, 'memo-strategy', wtinylfu, lru]).
metta_catalog_preset([vocabulary, 'memo-aggregate', none, min, max, sum, count]).
metta_catalog_preset([vocabulary, 'save-format', metta, fast]).
metta_catalog_preset([vocabulary, 'cache-mode', unchecked, force, refuse]).
metta_catalog_preset([vocabulary, 'effect-class',
                      pureStructural, readOnlyLookup,
                      nondeterministicReadOnly, writesState, oracleIO]).
metta_catalog_preset([vocabulary, visibility, 'PUBLIC', 'INTERNAL']).
metta_catalog_preset([vocabulary, 'op-kind', det, many, async,
                      raw_det, raw_many]).
metta_catalog_preset([vocabulary, 'subscription-edge', add, remove, both]).
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
metta_catalog_preset([vocabulary, delivery,
                      'at-most-once', 'at-least-once', 'per-write-exactly']).
metta_catalog_preset([vocabulary, 'event-order', ordered, unordered]).
%The direction an ordered semiring counts in, which the claim rows
%below already speak (ranked and prob count down from the best,
%tropical counts up from the cheapest). Declared as a vocabulary so the
%host surfaces read the closed set from the engine instead of each
%spelling it as a literal pair: nine of them did, across four files.
metta_catalog_preset([vocabulary, 'semiring-order', ascending, descending]).
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
metta_catalog_preset([vocabulary, 'agenda-policy',
                      declaration, recency, specificity, priority, user]).
metta_catalog_preset([vocabulary, volatility, volatile, stable, immutable]).
metta_catalog_preset([vocabulary, 'route-key', context, global]).
metta_catalog_preset([vocabulary, 'space-capability', file, process, network]).
metta_catalog_preset([vocabulary, 'MismatchEnum',
                      'MismatchOriginal', 'MismatchError', 'MismatchFail']).
metta_catalog_preset([vocabulary, 'NoMatchEnum',
                      'NoMatchOriginal', 'NoMatchFail', 'NoMatchError']).
metta_catalog_preset([vocabulary, 'EvaluationOrderEnum',
                      'OrderClause', 'OrderFittest']).
metta_catalog_preset([vocabulary, 'FunctionResultEnum',
                      'Nondeterministic', 'Deterministic']).
metta_catalog_preset([vocabulary, 'ClauseFailedEnum',
                      'ClauseFailNonDet', 'ClauseFailDet']).
metta_catalog_preset([vocabulary, 'OutOfClausesEnum',
                      'FailureOriginal', 'FailureEmpty', 'FailureError']).
metta_catalog_preset([kind, kind, symbol, [rest, term]]).
metta_catalog_preset([kind, 'routed-by-shape', symbol,
                      [optional, ['one-of', 'route-key']]]).
metta_catalog_preset([kind, vocabulary, symbol, [rest, symbol]]).
metta_catalog_preset([kind, claim, symbol, symbol, [rest, symbol]]).
metta_catalog_preset([kind, policy, symbol, symbol, term]).
metta_catalog_preset([kind, handles, symbol, pattern, ['one-of', fidelity],
                      [optional, ['one-of', determinism]]]).
metta_catalog_preset([kind, 'on-error', symbol, pattern,
                      ['one-of', 'on-error-mode']]).
metta_catalog_preset([kind, merge, pattern, ['one-of', 'answer-policy']]).
metta_catalog_preset([kind, annotations, symbol, symbol,
                      [optional, term]]).
metta_catalog_preset([kind, algebra, symbol, symbol, symbol, term, term,
                      term, term, term]).
metta_catalog_preset([kind, source, symbol, ['one-of', 'source-kind']]).
metta_catalog_preset([kind, context, symbol, ['one-of', world]]).
metta_catalog_preset([kind, admits, symbol, term]).
metta_catalog_preset([kind, capacity, symbol, integer]).
metta_catalog_preset([kind, writes, symbol, ['one-of', atomicity]]).
metta_catalog_preset([kind, events, symbol, ['one-of', delivery],
                      [optional, ['one-of', 'event-order']]]).
metta_catalog_preset([kind, emits, symbol, ['one-of', 'answer-policy']]).
metta_catalog_preset([kind, cache, symbol, ['one-of', 'cache-mode']]).
metta_catalog_preset([kind, image, symbol, symbol, ['one-of', 'image-mode']]).
metta_catalog_preset([kind, 'type-image', symbol,
                      ['one-of', 'registry-image']]).
metta_catalog_preset([kind, effect, symbol, ['one-of', 'effect-class']]).
metta_catalog_preset([kind, covers, term, ['one-of', 'effect-class']]).
metta_catalog_preset([kind, compensates, symbol, symbol]).
metta_catalog_preset([kind, inverse, symbol]).
metta_catalog_preset([kind, op, symbol, integer, ['one-of', 'op-kind']]).
metta_catalog_preset([kind, deprecated, symbol, term, term]).
metta_catalog_preset([kind, visibility, symbol, ['one-of', visibility]]).
metta_catalog_preset([kind, on, symbol, pattern, term, [optional, integer]]).
metta_catalog_preset([kind, agenda, symbol, ['one-of', 'agenda-policy'],
                      [optional, symbol]]).
metta_catalog_preset([kind, tabled, symbol, symbol, integer]).
metta_catalog_preset([kind, defined, symbol, symbol]).
metta_catalog_preset([kind, subscription, symbol, pattern,
                      ['one-of', 'subscription-edge']]).
metta_catalog_preset([kind, inherits, term, term]).
metta_catalog_preset([kind, restricted, term]).
metta_catalog_preset([kind, grants, term,
                      ['one-of', 'space-capability']]).
metta_catalog_preset([kind, parametric, term]).
metta_catalog_preset([kind, 'dispatch-default', symbol, term]).
metta_catalog_preset([kind, 'dispatch-policy', symbol, symbol, term]).
metta_catalog_preset(['routed-by-shape', handles]).
metta_catalog_preset(['routed-by-shape', 'on-error']).
metta_catalog_preset(['routed-by-shape', merge, global]).
%One row per engine decision axis. The inventory lane joins these live rows
%to the implementation seam named for each knob; keeping the defaults here
%means a program can read the same table the gate checks.
metta_catalog_preset([policy, dispatch, 'dispatch-policy', 'MismatchOriginal']).
metta_catalog_preset([policy, order, 'dispatch-policy', 'OrderClause']).
metta_catalog_preset([policy, merge, merge, depth]).
metta_catalog_preset([policy, agenda, reduce, 'depth-first']).
metta_catalog_preset([policy, equality, '==', 'structural-identity']).
metta_catalog_preset([policy, errors, 'on-error', abort]).
metta_catalog_preset([policy, world, context, 'closed-world']).
metta_catalog_preset([policy, algebra, annotations, bool]).
metta_catalog_preset([policy, storage, 'config-memoize', wtinylfu]).
metta_catalog_preset([policy, caching, cache, automatic]).
metta_catalog_preset([policy, typing, 'typing-rule', strict]).
metta_catalog_preset([policy, fidelity, handles, 'Exact']).
metta_catalog_preset([policy, 'source-kind', source, repeated]).
metta_catalog_preset([policy, 'transaction-mode', transaction, 'all-answers']).
metta_catalog_preset([policy, atomicity, writes, transactional]).
metta_catalog_preset([policy, delivery, events, 'per-write-exactly']).
metta_catalog_preset([policy, 'reaction-order', agenda, declaration]).
metta_catalog_preset([policy, 'save-format', save, metta]).
metta_catalog_preset([policy, volatility, volatility, stable]).
metta_catalog_preset([policy, determinism, determinism, nondet]).
metta_catalog_preset([claim, semiring, ranked, ordered, descending]).
metta_catalog_preset([claim, semiring, tropical, ordered, ascending]).
metta_catalog_preset([claim, semiring, prob, ordered, descending]).
metta_catalog_preset([algebra, bool, max, '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, bag, '+', '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, counting, '+', '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, set, max, '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'combine-idempotent', 'extend-associative',
                       'left-distributive', 'right-distributive',
                       'combine-zero-identity', 'extend-one-identity',
                       'extend-zero-annihilates', contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, ranked, max, '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, tropical, min, '+', infinity, 0,
                      [laws, 'combine-associative', 'combine-commutative',
                       'combine-idempotent', 'extend-associative',
                       'left-distributive', 'right-distributive',
                       'combine-zero-identity', 'extend-one-identity'],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, prob, '+', '*', 0, 1,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, prov, plus, times, zero, one,
                      [laws, 'combine-associative', 'combine-commutative',
                       'extend-associative', 'left-distributive',
                       'right-distributive', 'combine-zero-identity',
                       'extend-one-identity', 'extend-zero-annihilates',
                       contraction],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, budget, min, '+', infinity, 0,
                      [laws, 'combine-associative', 'combine-commutative',
                       'combine-idempotent', 'extend-associative',
                       'combine-zero-identity', 'extend-one-identity'],
                      [carrier], [requires]]).
metta_catalog_preset([algebra, amplitude, 'amplitude-add',
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
metta_catalog_preset(['dispatch-default', 'MismatchEnum', 'MismatchOriginal']).
metta_catalog_preset(['dispatch-default', 'NoMatchEnum', 'NoMatchOriginal']).
metta_catalog_preset(['dispatch-default', 'EvaluationOrderEnum', 'OrderClause']).
metta_catalog_preset(['dispatch-default', 'FunctionResultEnum', 'Nondeterministic']).
metta_catalog_preset(['dispatch-default', 'ClauseFailedEnum', 'ClauseFailNonDet']).
metta_catalog_preset(['dispatch-default', 'OutOfClausesEnum', 'FailureOriginal']).

%Visibility controls generated documentation and static members, not whether a
%name can be mentioned. These are implementation steps behind public forms, or
%the language-level interpreter whose exact S/fn mention remains available.
metta_internal_catalog_name('get-doc-atom').
metta_internal_catalog_name('get-doc-function').
metta_internal_catalog_name('get-doc-params').
metta_internal_catalog_name('get-doc-single-atom').
metta_internal_catalog_name(interpret).
metta_internal_catalog_name('match-type-or').

metta_builtin_visibility(Name, 'INTERNAL') :-
    metta_internal_catalog_name(Name),
    !.
metta_builtin_visibility(_, 'PUBLIC').

%Run after the prelude has registered its equations. Materialising the rows
%makes ordinary &metta matching, generators, and reflection share one source
%rather than teaching a second private-name list in each consumer.
metta_publish_builtin_visibility :-
    findall(Name,
            ( fun(Name)
            ; metta_special_form_head(Name)
            ),
            Names0),
    sort(Names0, Names),
    forall(member(Name, Names),
           (   metta_catalog_row([visibility, Name, _])
           ->  true
           ;   metta_builtin_visibility(Name, Visibility),
               add_sexp('&metta', [visibility, Name, Visibility], _)
           )).

%Presets land only where their subject has no row yet, which makes the
%directive reconsult-idempotent (a re-consulted engine meets its own rows
%and the duplicate refusal must not fire) and keeps a program's own
%remove-then-redeclare widening standing across an engine reload.
metta_catalog_preset_missing([kind, Head|_]) :-
    !,
    \+ metta_kind_spec(Head, _).
metta_catalog_preset_missing([vocabulary, Name|_]) :-
    !,
    \+ metta_vocabulary_values(Name, _).
metta_catalog_preset_missing(['routed-by-shape', Head|_]) :-
    !,
    \+ metta_routed_head(Head, _).
metta_catalog_preset_missing(Atom) :-
    \+ metta_catalog_row(Atom).

:- forall(( metta_catalog_preset(Atom), metta_catalog_preset_missing(Atom) ),
          add_sexp('&metta', Atom, _)).
