% Purpose: own native storage modules and enforce the self-describing policy and capability catalog
% Assumes: engine/spaces.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/spaces.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% Guarantees: counting and tropical are ordinary catalog algebras, and each
% ordered preset declares its best direction [tested:
% bindings/python/tests/test_under_algebra.py; commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa].
% Guarantees: deprecated is a schema-checked catalog kind whose name, since,
% and remedy fields remain ordinary queryable data [tested:
% the_shipped_catalog_is_queryable_data;
% commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0].
% [tested: tests/prolog/spaces.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

:- dynamic native_storage_module_cache/2.
:- dynamic space_parametric/1.
%The two host idle-hook seams these read are declared with every other seam,
%in engine/ext_points.pl, rather than here. Declaring a seam in the module of
%the file that happens to CALL it was the flat namespace's habit; a seam
%belongs to the seam module whichever subsystem asks it.

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
%bindings/python/metta/space.py enforces at the library's
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
%It is set from metta_check_catalog_semantics/3 rather than from the walk
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
petta_catalog_head(deprecated).

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
petta_catalog_note_added([cache, Function, _]) :-
    !,
    petta_cache_policy_changed(Function).
petta_catalog_note_added([tabled, _, Function, _]) :-
    !,
    petta_cache_policy_changed(Function).
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
    petta_dispatch_all_changed,
    petta_cache_policy_changed(_).
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
petta_catalog_note_removed([cache, Function, _]) :-
    !,
    petta_cache_policy_changed(Function).
petta_catalog_note_removed([tabled, _, Function, _]) :-
    !,
    petta_cache_policy_changed(Function).
petta_catalog_note_removed([capacity|_]) :-
    !,
    petta_capacity_counts_prune.
petta_catalog_note_removed(_).

petta_cache_policy_changed(Function) :-
    forall(seam:cache_policy_changed(Function), true).

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

%The compatibility projection lives beside the vocabulary it projects into.
%pure=true and the old immutable spelling mean pureStructural; stable means
%readOnlyLookup; volatile means oracleIO. The first clause keeps every
%canonical value data-driven from the catalog, so adding an alias cannot make
%it a sixth public EffectClass member.
%[tested:
%effects_lattice:legacy_effect_spellings_map_but_cannot_enter_the_canonical_catalog;
%commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0]
petta_effect_class_canonical(Value, Canonical) :-
    nonvar(Value),
    !,
    (   petta_vocabulary_value('effect-class', Value)
    ->  Canonical = Value
    ;   petta_legacy_effect_class(Value, Canonical)
    ).
petta_effect_class_canonical(Canonical, Canonical) :-
    petta_vocabulary_values('effect-class', Values),
    member(Canonical, Values).

petta_legacy_effect_class(immutable, pureStructural).
petta_legacy_effect_class(stable, readOnlyLookup).
petta_legacy_effect_class(volatile, oracleIO).

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
petta_check_catalog_semantics(cache, [Function, _], Term) :-
    !,
    (   petta_catalog_row([cache, Function, _])
    ->  petta_declaration_refused(
            Term, 1, 'one cache override per function; remove the old row first')
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
    % policy-inventory-exempt: mechanism-internal; reason=Combine and Extend are the algebra row's own two declared operation names rather than a closed value set; evidence=engine/spaces/catalog.pl:petta_check_algebra_laws/8
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
petta_catalog_preset([vocabulary, 'image-mode', opaque, transparent, auto]).
petta_catalog_preset([vocabulary, 'registry-image',
                      expression, symbol, handle, operations]).
petta_catalog_preset([vocabulary, 'answer-policy', depth, fair, 'best-first']).
petta_catalog_preset([vocabulary, semiring, bool, bag, counting, set, ranked,
                      tropical, prob, prov]).
petta_catalog_preset([vocabulary, 'source-kind', linear, repeated, peek]).
petta_catalog_preset([vocabulary, world, 'closed-world', 'open-world']).
petta_catalog_preset([vocabulary, atomicity,
                      transactional, 'atomic-single', 'best-effort']).
petta_catalog_preset([vocabulary, 'memo-strategy', wtinylfu, lru]).
petta_catalog_preset([vocabulary, 'memo-aggregate', none, min, max, sum, count]).
petta_catalog_preset([vocabulary, 'save-format', metta, fast]).
petta_catalog_preset([vocabulary, 'cache-mode', unchecked, force, refuse]).
petta_catalog_preset([vocabulary, 'effect-class',
                      pureStructural, readOnlyLookup,
                      nondeterministicReadOnly, writesState, oracleIO]).
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
petta_catalog_preset([kind, image, symbol, symbol, ['one-of', 'image-mode']]).
petta_catalog_preset([kind, 'type-image', symbol,
                      ['one-of', 'registry-image']]).
petta_catalog_preset([kind, effect, symbol, ['one-of', 'effect-class']]).
petta_catalog_preset([kind, inverse, symbol]).
petta_catalog_preset([kind, op, symbol, integer, ['one-of', 'op-kind']]).
petta_catalog_preset([kind, deprecated, symbol, term, term]).
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
petta_catalog_preset([policy, caching, cache, automatic]).
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
petta_catalog_preset([claim, semiring, ranked, ordered, descending]).
petta_catalog_preset([claim, semiring, tropical, ordered, ascending]).
petta_catalog_preset([claim, semiring, prob, ordered, descending]).
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
petta_catalog_preset([algebra, counting, '+', '*', 0, 1,
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
petta_catalog_preset([algebra, tropical, min, '+', infinity, 0,
                      [laws, 'combine-associative', 'combine-commutative',
                       'combine-idempotent', 'extend-associative',
                       'left-distributive', 'right-distributive',
                       'combine-zero-identity', 'extend-one-identity'],
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
