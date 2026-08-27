% Purpose: validate foreign-provider capabilities and route foreign and native space operations
% Assumes: engine/spaces.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/spaces.pl's implementation module and original load order.
%   foreign transaction enlistment is a semidet user-context check even inside nested SWI transactions.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% Guarantees: match/4 dispatches a gap pattern by its wrapper alone, so an ordinary pattern reaches the clause it always reached [tested: tests/prolog/segments.plt:segments_costs_nothing; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb].
% Guarantees: conjunction multiplicity reads the dynamically scoped algebra,
% so under=counting cannot inherit bool's duplicate collapse [tested:
% test_counting_counts_match_bag_duplicates_without_opening_a_row_cursor;
% commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa].
% Guarantees: the deferred equation walk associates only the owning space's
% declarations with a local equation [tested:
% spaces_deferred_translation:a_bulk_local_shadow_retains_no_inherited_order_types;
% commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c].
% [tested: tests/prolog/spaces.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

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
%A space that declares NOTHING provides nothing, the safe answer P12.14
%gave events, and the declaration means exactly what it says. The retired
%default read the other way round and carried a trap its own definition
%documented: it stopped the moment the space had ANY solution, so declaring
%one capability was the act that took the other seven away. Python
%providers never think about it, because foreign.py projects the whole set
%at registration from the protocols the provider implements
%[tested: test_a_python_providers_capabilities_reach_the_engine,
%a_declaration_provides_exactly_what_it_says].
%subscribe is the one capability no registration may claim on its own, and
%that is P12.14's whole point: the other eight are questions about what a
%provider implements, and this one is a promise about what its CONTEXT can
%deliver. A remote space implements add and remove and its contents still
%change on the server. So the (events ...) declaration decides it, whatever
%a host registered, and a context that declares nothing is refused here
%[tested: test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses].
%Declaring nothing provides NOTHING, the same safe answer P12.14 gave
%events. The retired default read the other way round: a space with no
%foreign_capability/2 rows provided everything, so declaring one
%capability was the act that took the other seven away, a trap its own
%definition documented. Every in-tree provider declares (the Python tier
%derives its declarations at registration; the audit of 2026-08-25 found
%two test fixtures leaning on the default and gave them their true rows),
%and an operation a space does not declare is refused naming the
%capability, which is where an undeclared provider now finds out.
foreign_provides(Space, Capability) :-
    seam:foreign_capability(Space, Capability),
    (   Capability == subscribe
    ->  metta_event_capability(Space, _, _)
    ;   true
    ).

%A capability the space does not provide. The provider gets to say why, if it
%has words for it: seam:foreign_refuse/2 raises, and "does not implement add"
%reads differently from "declines this add request", which is a distinction the
%Python half already draws and this one could not.
%
%The hook is expected to throw. Reaching the throw below means it did not,
%which is the engine and the provider disagreeing about what is provided.
refuse_absent_capability(Space, Capability) :-
    (   foreign_provides(Space, Capability)
    ->  true
    ;   seam:foreign_refuse(Space, Capability)
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
    (   metta_in_user_transaction,
        once(current_transaction(_))
    ->  metta_writes(Space, Atomicity),
        (   Atomicity == transactional
        ->  metta_enlist_foreign(Space)
        ;   Atomicity == 'best-effort'
        ->  true
        ;   throw(error(metta_transaction_unsupported(Space, Atomicity),
                        none))
        )
    ;   true
    ),
    (   call(Goal)
    ->  true
    ;   throw(error(metta_foreign_operation_failed(Space, Capability),
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
    metta_hook_claim_idle(Space),
    atoms_store_only(Space, Terms),
    add_atoms_in_one_crossing(Space, Terms), !.
metta_add_atoms(Space, Terms) :-
    %This route may perform work for its first atom, so check the whole batch
    %before invoking any per-atom door. A duplicate later in the batch must not
    %leave the first declaration, compiled equation, or observer effect behind.
    batch_declarations_unique(Space, Terms),
    forall(member(Term, Terms), 'add-atom'(Space, Term, _)).

%A provider's own batch crossing when it has one, and the native store's
%otherwise. A provider without seam:foreign_add_many/2 fails here and gets one
%seam:foreign_add/2 per atom, which is what every provider written before this
%gets. The native path writes behind the write wrapper's back, so it is
%available only while no observer is installed; a provider's own crossing owns
%the write hooks exactly as its per-atom add does.
add_atoms_in_one_crossing(Space, Terms) :-
    seam:foreign_space(Space), !,
    refuse_absent_capability(Space, add),
    seam:foreign_add_many(Space, Terms).
add_atoms_in_one_crossing(Space, Terms) :-
    metta_add_hooks_idle(Space),
    ensure_native_storage_module(Space, Storage),
    %The bulk door checks and notes contract subjects exactly as the
    %per-atom door does, once per batch head test rather than per space
    %test per atom; the whole batch is checked before any of it lands.
    (   Space == '&metta'
    ->  forall(member(Decl, Terms),
               (   metta_declaration_check(Decl),
                   metta_note_ctx_declared(Decl)
               ))
    ;   true
    ),
    forall(member(Term, Terms),
           ( add_sexp_in(Storage, Space, Term, Ref),
             record_source_atom_assertion(Ref) )),
    (   Space == '&metta'
    ->  forall(member(Term, Terms), metta_catalog_note_added(Term))
    ;   true
    ).

%Many atoms of a PROGRAM in one crossing: the equations among them are
%registered as they arrive and translated when something reaches them, so a
%file of definitions costs storing and registering them rather than compiling
%every one. metta_add_atom/3 per equation compiles it at once, which is the
%right answer for the door one atom comes through and is 61.39us an atom over
%a hundred thousand equations, against 2.25us to read them and put them in the
%space [measured 2026-08-24]. The signature pass runs first for the reason
%filereader.pl's register_parsed_signatures/1 gives, and once for the whole
%batch because asking the predicate table costs one walk of it either way.
%
%Order is the batch's own: an atom that is not an equation goes through
%metta_add_atom/3 exactly where it stood, so a declaration between two
%equations still lands between them.
%Three passes, not one loop, because what an equation settles divides in two:
%its NAME is a function, of that arity, in this module, and whatever was
%compiled against the name's previous definition is stale -- all of it once per
%name; while the equation ITSELF has to be stored and recorded -- once per
%equation. A function of ten equations pays the first once here and ten times
%through the per-atom door.
%The 2-ary door is the 3-ary one for a caller with no use for the names.
%The names come back SORTED AND DISTINCT so a lifecycle pass that is
%per-name by its own semantics (source_definition_arrived/1 retractalls by
%name and sets a once-flag) walks two thousand names instead of twenty
%thousand equations [measured 2026-08-24: the arrived walk was 5 of the 74
%inferences each equation of the fun doorbench cost].
metta_add_program_atoms(Space, Atoms) :-
    metta_add_program_atoms(Space, Atoms, _).

metta_add_program_atoms(Space, Atoms, Names) :-
    (   seam:foreign_space(Space)
    ;   \+ metta_hook_claim_idle(Space)
    ;   \+ metta_add_hooks_idle(Space)
    ),
    !,
    forall(member(Atom, Atoms), metta_add_atom(Space, Atom, _)),
    findall(F, ( member([=, [F|_], _], Atoms), atom(F) ), Names0),
    sort(Names0, Names).
%A batch of DATA is not a program: it has nothing to register and nothing to
%defer. Both halves of this clause answer to a pinned counter. The guard is
%memberchk/2, which is C and costs five inferences over a twenty-thousand
%atom miss where member/2 in a negation costs one per atom, and the
%save-load-fast INFERENCE pin allows four total. The body is the PER-ATOM
%store loop the fast door always had, not metta_add_atoms/2: the fast
%loader's atoms fail the batch door's own store-only test, so the batch
%door scans every atom and falls back to the same loop with the scan
%wasted, +29.5e6 instructions:u on the 20,001-atom lane when first tried
%[measured 2026-08-17: 4737359333 against 4707855603], -41e6 recovered by
%the loop and +80k inferences avoided by the guard
%[measured 2026-08-24, engine-only ten-load harness, same checkout].
metta_add_program_atoms(Space, Atoms, []) :-
    \+ memberchk([=|_], Atoms),
    !,
    store_data_atoms(Atoms, Space).

metta_add_program_atoms(Space, Atoms, Names) :-
    space_module(Space, Module),
    ensure_native_storage_module(Space, Storage),
    %ONE ORDERED PASS, each atom stored where it stood, and ONE walk.
    %Partitioning the batch and storing every equation before every other
    %atom was built and reverted: a space enumerates its clauses in the
    %order they were asserted, so get-atoms and match answer in that order,
    %and MeTTa answer order is observable. The same batch through the two
    %doors then differed at `(= (a) 1) (: d Number) (= (b) 2)`, which the
    %per-atom door answers in that order and the partitioned one answered
    %with the declaration last [measured 2026-08-24]. What IS batched is the
    %work belonging to a NAME rather than to an equation, which is where the
    %saving was. The signature collection used to be its own findall over
    %the batch, so a cache of a million data atoms beside one equation paid
    %two extra classification steps per data atom, one in the findall's
    %goal and one in the store dispatch: +20.9k inferences and +23e6
    %instructions:u on the 20,001-atom save-load-fast lane against the
    %direct loop [measured 2026-08-24]. The classification is written inline
    %in one walk, so a data atom pays its recursion and its store and
    %nothing else, the direct loop's own floor. Registration and the
    %per-name notes follow the stores, which is the per-form door's own
    %order per atom.
    journal_load_now(Load),
    store_program_atoms(Atoms, Storage, Space, Module, Load, none,
                        Signatures0),
    sort(Signatures0, Signatures),
    findall(F, member(F-_, Signatures), Names0),
    sort(Names0, Names),
    register_function_signatures(Signatures),
    forall(member(F, Names), note_metta_function(Module, F)),
    %Marked LAST, after every equation is in the space: the marker says
    %"translate me from the space", and a marker standing over a space that
    %does not hold the equations yet would translate nothing and retract
    %itself. The fresh functions are marked before any already-translated one
    %is translated, so an equation translated here finds its batch siblings
    %markable rather than absent.
    %The whole batch's counts in one sorted pass, so the ownership ledger
    %costs the batch one msort and one run-length walk: counting each
    %signature's occurrences with its own member/2 walk over the batch made
    %marking N one-equation functions cost N walks of N, and the load
    %profile put 97 percent of a 12,000-equation load inside member_/3
    %[measured 2026-08-24].
    msort(Signatures0, SignatureRuns),
    counted_signature_runs(SignatureRuns, CountedSignatures),
    %The partition is taken ONCE, before either pass runs, because the first
    %pass can flip it: a fresh name whose compiled predicate an inherited
    %definition already answers translates AT ARRIVAL inside
    %defer_metta_function/5, and metta_function_translated/2 is true from
    %then on. Deciding the second pass by re-asking the flag re-translated
    %exactly those names' equations, and `plus`, which shadows SWI's own
    %plus/3, loaded four clauses from two equations and answered each let
    %inversion twice per clause copy
    %[measured 2026-08-24: examples/ch07-control-flow/07-05-recursion/07-invertpeanoplus.metta, eight
    %answers where the pin holds one].
    exclude(translated_counted_signature(Module), CountedSignatures,
            FreshSignatures),
    include(translated_counted_signature(Module), CountedSignatures,
            StandingSignatures),
    forall(member(counted(F, Arity, Count), FreshSignatures),
           ( InputArity is Arity - 1,
             defer_metta_function(Space, Module, F, InputArity, Count) )),
    forall(member(counted(F, Arity, _), StandingSignatures),
           ( InputArity is Arity - 1,
             findall(Equation,
                     ( member(Equation, Atoms),
                       Equation = [=, [F|W], _],
                       length(W, InputArity) ),
                     Arriving),
             mark_or_translate_equation(Space, Module, F, InputArity,
                                        Arriving) )),
    %Once per function rather than per equation, the same collapse the
    %note_metta_function pass above already makes: every consumer of the
    %arrival announcement is an invalidator, so a batch of a function's
    %equations is one change to them.
    forall(member(F, Names), announce_equation_arrival(Module, F)).

%A run of data atoms with every run-invariant decided ONCE: the storage
%module, the parametric-or-named clause shape, and the journal context with
%its owner-pin unwrapped. What stays per atom is the mechanical core the
%corebench harness priced at 1.09us against the 2.55us the dispatching walk
%cost around it: build the clause term, assertz it with its reference, and
%journal the reference [measured 2026-08-24: ai-tmp/wip/corebench.pl,
%100,000 atoms, min of three]. Everything with per-atom SEMANTICS keeps the
%per-atom door: a ':' declaration (duplicate warning, DontEvalType,
%user-wins eviction, the recompile announce), an '=' head (the guard above,
%defensively re-tested here), and the whole batch when the space is
%'&metta', whose catalog checks are per-atom by contract. Foreign spaces
%and busy hooks never reach this clause; the batch door's first clause
%already routed them per atom.
store_data_atoms(Atoms, Space) :-
    (   Space == '&metta'
    ->  forall(member(Atom, Atoms), metta_add_atom(Space, Atom, _))
    ;   ensure_native_storage_module(Space, Storage),
        (   Space = [_|_], space_parametric(Space)
        ->  Shape = parametric
        ;   Shape = named
        ),
        journal_load_now(Load),
        store_data_atoms_(Atoms, Storage, Space, Shape, Load)
    ).

store_data_atoms_([], _, _, _, _).
store_data_atoms_([Atom|Atoms], Storage, Space, Shape, Load) :-
    (   Atom = [Rel|Args]
    ->  (   ( Rel == (=) ; Rel == (:) )
        ->  metta_add_atom(Space, Atom, _)
        ;   (   Shape == parametric
            ->  Term =.. ['$metta_parametric_atom', Rel|Args]
            ;   Term =.. [Space, Rel|Args]
            ),
            assertz(Storage:Term, Ref),
            journal_data_ref(Load, Ref)
        )
    ;   assertz(Storage:'$metta_native_scalar'(Atom), Ref),
        journal_data_ref(Load, Ref)
    ),
    store_data_atoms_(Atoms, Storage, Space, Shape, Load).

%The fused walk: classify, store, and collect the signature multiset in one
%pass, the classification inline so it compiles to VM instructions and moves
%no counter. An equation of a DERIVED name is left to the single-atom door,
%whose first clause swallows an alpha-duplicate of a specialization the
%space already holds; deciding that needs the stored equations and is what
%makes a copied space reproduce itself rather than double.
store_program_atoms([], _, _, _, _, _, []).
store_program_atoms([Atom|Atoms], Storage, Space, Module, Load, Q0,
                    Signatures) :-
    (   Atom = [=, [F|W], _],
        atom(F)
    ->  equation_walk_class(Module, F, Q0, Q1, Class),
        (   Class == ho
        ->  metta_add_atom(Space, Atom, _),
            Signatures = Rest
        ;   add_sexp_in(Storage, Space, Atom, Ref),
            journal_data_ref(Load, Ref),
            head_pattern_notes_for(Module, Atom),
            length(W, N),
            Arity is N + 1,
            Signatures = [F-Arity|Rest]
        )
    ;   metta_add_atom(Space, Atom, _),
        (   Atom = [':'|_]
        ->  Q1 = none
        ;   Q1 = Q0
        ),
        Signatures = Rest
    ),
    store_program_atoms(Atoms, Storage, Space, Module, Load, Q1, Rest).

%What the walk's per-name probes learned about the PREVIOUS equation's
%name, the higher-order test now included: a batch
%is runs of one function's equations back to back, so remembering one name
%answers nine of every ten equations at one comparison where an AVL memo
%of every name cost more than the probes it saved (4.6 inferences per
%equation of assoc machinery against the 6 it replaced, measured on this
%walk's own profile). A TRANSLATED or UNDECLARED name skips, while a
%DECLARED name queues its one-row-per-equation FIFO exactly as the
%deferral's consumption contract requires (materialize_with_queued_types/3
%retracts one row per materialised equation). A ':' atom stored mid-walk
%resets the memo to none, because a declaration between two equations is
%precisely the visibility change the per-equation probe existed to observe
%[tested: spaces_deferred_translation, lib_conformance;
%commit=5655d2531fbeec85cbea1ec365010f338179f076].
equation_walk_class(Module, F, Q0, Q, Class) :-
    (   Q0 = q(F0, Class0), F0 == F
    ->  Q = Q0,
        Class = Class0,
        (   Class0 == declared
        ->  queue_deferred_equation_types(Module, F)
        ;   true
        )
    ;   ho_specialization(Module, _, F)
    ->  Class = ho,
        Q = q(F, ho)
    ;   metta_function_translated(Module, F)
    ->  Class = plain,
        Q = q(F, plain)
    ;   catch_recover(definition_type_declaration_in(Module, F, _), fail)
    ->  queue_deferred_equation_types(Module, F),
        Class = declared,
        Q = q(F, declared)
    ;   Class = plain,
        Q = q(F, plain)
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
%loader doors notified seam:function_changed but never
%invalidate_specializations, so an equation added by a string run or a
%compile-mode load left a prior specialization of the same name
%answering stale clauses. One door means the next such rule lands once
%[tested specializer:string_run_equation_invalidates_specializations].
compile_metta_equation(Module, Term, Clause, Ref) :-
    note_metta_equation(Module, Term),
    translate_metta_equation(Module, Term, Clause, Ref).

%What an arriving equation settles immediately: the name is a function, the
%prelude's definition of it is gone, and everything compiled against the
%PREVIOUS definition is stale. None of that needs the body translated, and
%the claim is about the definition arriving rather than about the clause.
%
%Stale specializations go FIRST, before this body compiles. They are clones
%of the PREVIOUS definition, and that is the whole content of the claim; a
%clone this compilation creates for its own recursive call belongs to the NEW
%definition and must survive. Invalidating afterwards abolished exactly those
%clones while the clause naming them stood, so (= (f $g) (... (f (+ 2)) ...))
%compiled a generic clause calling an empty predicate: the direct call
%answered through its own specialization and a call that reached the generic
%clause, (let $h (+ 1) (f $h)), silently answered NOTHING. Found by the
%verify-specializations differential over examples/
%[tested specializer:a_recursive_specialization_survives_its_compile].
note_metta_equation(Module, Term) :-
    Term = [=, [F|_], _],
    note_metta_function(Module, F).

note_metta_function(Module, F) :-
    (   metta_self_module(Module) -> evict_prelude_definition(F) ; true ),
    register_fun_in(Module, F),
    prepare_specialization_invalidation(Module, F),
    support_invalidate_function_change(Module, F).

translate_metta_equation(Module, Term, Clause, Ref) :-
    Term = [=, [F|_], _],
    assert_translated_equation(Module, Term, Clause, Ref),
    %The dependent-recompile hooks run AFTER the clause is in place, so
    %a definition that mentions F recompiles against the new one.
    announce_equation_arrival(Module, F).

%The internal half of a translation, with no announcement: the clause, its
%instrumentation, and its provenance records. Deferred materialisation calls
%this alone, because the observers heard about the equation when it ARRIVED
%and the engine catching up on its own bookkeeping is not a change. Announced
%from here too, laziness was observable: the deferred translation of
%table-stats itself, forced by the first !(table-stats ...) form, fired
%seam:function_changed AFTER the table under measurement existed, and
%lib_tabling's conservative hook abolished it, so the counters read zero
%where the eager load read one [measured 2026-08-24:
%examples/ch18-performance/18-02-memoisation-and-tabling/12-tabling_statistics.metta].
assert_translated_equation(Module, Term, Clause, Ref) :-
    Term = [=, [F|Inputs], _],
    %Mainline's shadow-repair pre-step is CLAUSE-level: under deferral the
    %assert can run in a later module life than the arrival, and the weak
    %import it removes must be removed before THIS assert, whichever life
    %runs it.
    length(Inputs, InputArity),
    PredArity is InputArity + 1,
    metta_prepare_function_predicate(Module, F, PredArity),
    without_runnable_name_context(
        once(with_metta_module(Module, translate_clause(Term, RawClause)))),
    metta_instrument_recursive_clause(Term, RawClause, Clause),
    assert_function_clause(Module, Clause, Ref),
    record_source_assertion(Ref),
    record_translated_from(Ref, Term, SourceRef),
    record_source_assertion(SourceRef),
    forall(seam:function_clauses_changed(F), true).

%Everything observers may see of "an equation of F arrived", in the order the
%eager door has always fired it. Idempotent consumers only: the support-graph
%repair drains a dirty set, seam:function_changed invalidates, and
%announce_function_call_graph_changed consumes a prepared change mark, which
%is why the bulk door may fire this once per function for a batch.
announce_equation_arrival(Module, F) :-
    forall(support_repair_invalidations, true),
    forall(seam:function_changed(F), true),
    announce_function_call_graph_changed(Module, F).

%A function whose equations have arrived and not been translated. The name
%leads, not the module, because the question asked of this table is always "is
%F waiting" with the rest along for the ride, and every space's functions
%otherwise share one module-keyed bucket.
%
%A MARKER, and one per function rather than per equation: the equations are in
%the space already, which indexes them by name, so copying each into a queue
%would be a second program to keep in step with the first and one more database
%write for every equation. Reading a whole function's equations back out of a
%space holding a hundred thousand costs 0.94us; recording one equation costs
%2.2us [measured 2026-08-24].
%
%One row per (arity, OWNING LOAD) rather than per arity alone, with the count
%of equations it stands for, because a compiled clause has to be journalled
%under the source that defined its equation and the loads can interleave on
%one arity. The count is what lets the materialisation walk, which reads the
%store in arrival order, hand each equation back to its own load: the first
%Count of an arity belong to its first row's load, the next to the next
%row's. The bulk door adds a whole batch's count in one write, so the
%per-equation cost this table was built to avoid stays avoided.
:- dynamic deferred_metta_function/6.
:- dynamic metta_function_compiling/1.

%Record the equation and translate it when something reaches it. This is
%s(CASP)'s shape: its scasp/2 collects the clauses transitively reachable from
%a query and compiles only those, leaving the rest of the program as stored
%clauses that cost nothing until a query needs them
%[source: SWI-Prolog pack scasp, prolog/scasp/dyncall.pl, scasp_query_clauses/2
%and callee_closure/4]. The closure is not walked here because the translator
%already walks it: compiling a call site to F asks for F, whose bodies compile
%their own call sites, so the reachable set falls out of the recursion that
%was going to happen anyway.
defer_metta_equation(Space, Module, Term) :-
    Term = [=, [F|W], _],
    note_metta_equation(Module, Term),
    head_pattern_notes_for(Module, Term),
    (   metta_function_translated(Module, F)
    ->  true
    ;   queue_deferred_equation_types(Module, F)
    ),
    length(W, InputArity),
    mark_or_translate_equation(Space, Module, F, InputArity, [Term]),
    announce_equation_arrival(Module, F).

%The marker means "translate every equation of F out of the space", so a
%function whose clauses ALREADY stand must not be marked: the standing ones
%would be translated a second time and the function would answer each of them
%twice. Three equations of `ord` answered `a b c`, and one more arriving after
%they were translated made it answer `a b c a b c d`
%[measured 2026-08-24]. An equation joining standing clauses is therefore
%translated where it arrives, which is what the eager door has always done
%[tested: spaces_deferred_translation:an_equation_joining_a_translated_function_answers_once].
%No announcement in either branch: the CALLER announces the arrival once,
%whichever branch stored it, so an equation joining a translated function and
%an equation deferred behind a marker cost observers the same one event.
mark_or_translate_equation(Space, Module, F, InputArity, Arriving) :-
    (   metta_function_translated(Module, F)
    ->  forall(member(Equation, Arriving),
               assert_translated_equation(Module, Equation, _, _))
    ;   defer_metta_function(Space, Module, F, InputArity)
    ).

%Deferring is sound only while a call that has not been translated yet is
%OBSERVABLE, and it stops being observable the moment the equation extends a
%predicate that already answers. Every other door forces the translation before
%it reads the function: a compiled call site through build_call_or_partial_dl/6,
%a name met as data through reduce/3, and anything else through the
%undefined-predicate hook below. That hook is the one with a precondition, and
%this is it: SWI raises the existence error only when the predicate has no
%definition at all, so an equation extending one that HAS a definition would sit
%deferred while the old definition kept answering. A program extending get-type,
%which compiles into the get_type_rule/2 the engine declares at boot, typed
%`(f 2 4)` against the builtin rule alone and answered BadArgType where its own
%rule makes 2 an EvenNumber [measured 2026-08-24:
%examples/ch09-types/12-types_dependent.metta]. The same holds for a space that shadows
%an engine builtin, where the inherited definition answers in place of the
%arriving one, which is why the test is `defined` and not `number_of_clauses`.
defer_metta_function(Space, Module, F, InputArity) :-
    defer_metta_function(Space, Module, F, InputArity, 1).

%Run-length encode a SORTED signature multiset: one counted(F, Arity, N) per
%distinct signature, in order. Linear in the batch.
translated_counted_signature(Module, counted(F, _, _)) :-
    metta_function_translated(Module, F).

counted_signature_runs([], []).
counted_signature_runs([F-Arity|Rest], [counted(F, Arity, Count)|Counted]) :-
    counted_signature_run(Rest, F-Arity, 1, Count, Remaining),
    counted_signature_runs(Remaining, Counted).

counted_signature_run([Signature|Rest], Signature, Sofar, Count, Remaining) :-
    !,
    Next is Sofar + 1,
    counted_signature_run(Rest, Signature, Next, Count, Remaining).
counted_signature_run(Rest, _, Count, Count, Rest).

defer_metta_function(Space, Module, F, InputArity, _Count) :-
    Arity is InputArity + 1,
    compiled_function_name(F, Predicate),
    visible_predicate_definition(Module, Predicate, Arity),
    !,
    translate_deferred_shape(Space, Module, F, InputArity).
defer_metta_function(Space, Module, F, InputArity, Count) :-
    current_owning_source_load(Load),
    (   retract(deferred_metta_function(F, Module, Space, InputArity,
                                        Load, Sofar))
    ->  Total is Sofar + Count,
        assertz(deferred_metta_function(F, Module, Space, InputArity,
                                        Load, Total), Ref)
    ;   assertz(deferred_metta_function(F, Module, Space, InputArity,
                                        Load, Count), Ref)
    ),
    record_source_assertion(Ref).

%current_predicate/1 per module of the inheritance chain, never
%predicate_property/2 on the asking module: predicate_property RESOLVES the
%name through the chain, and SWI caches that resolution as an import link, so
%probing a name an inherited STATIC defines poisons the module against the
%local shadow the translation is about to assert. Probing
%predicate_property(m:send(_,_,_), defined) in a fresh module and then
%asserting m:send/3 is a permission error on pce_principal's static send/3,
%where the same assert with no probe before it succeeds; current_predicate/1
%in the same experiment answers about the asked module alone, creates nothing,
%and the assert after it succeeds [measured 2026-08-24]. It sees only LOCAL
%definitions, not imports, which is the question anyway: get_type_rule/2 is
%Self's own dynamic predicate and is found, and a name like send that only
%XPCE's import chain would answer is not, so its equations defer and the call
%site's forced translation asserts the shadow exactly as the eager door did.
visible_predicate_definition(Module, Predicate, Arity) :-
    default_module(Module, Inherited),
    current_predicate(Inherited:Predicate/Arity),
    !.

%The NAME alone, not the name in a module: a call site compiles in the module
%it is written in while the function it names may be defined in another, the
%global fallback a name that is not scoped gets, and asking about the calling
%module left that function untranslated and its call site compiled against an
%empty predicate. Every module that is waiting to translate F translates it,
%which is more than the one call site needs and never less
%[tested: filereader_global_function_scope].
%
%The guard is re-entrancy, not memoisation: translating one equation's body
%compiles its call sites, and a recursive function's body names ITSELF, which
%would otherwise translate the rest of its equations from inside the first one
%and assert them out of order. Held off, the recursive body compiles against
%the clauses asserted so far, which is exactly what it saw when every equation
%was translated as it arrived.
%Translation runs under a mutex inside sig_atomic/1, which is the shape SWI's
%own loader uses against the same hazard: '$mt_load_file'/4 wraps
%with_mutex('$load_file', ...) in sig_atomic/1 so a signal delivered to a
%loading thread cannot interrupt it half way [source: SWI-Prolog boot/init.pl,
%'$mt_load_file'/4, /usr/lib/swi-prolog/boot/init.pl:2650].
%
%Both halves carry weight here. par-race stops its losing branch with
%thread_signal(Thread, abort) [source: lib/lib_thread/lib_thread.pl, race_stop_/2], and a
%branch aborted between translate_deferred_function/1 retracting the deferral
%and its clauses arriving left the function neither deferred nor defined: the
%NEXT call to it raised "Unknown procedure: slow/2" from a form that had
%nothing to do with the race [measured 2026-08-24: examples/ch17-concurrency-and-the-loop/01-thread_lib.metta].
%sig_atomic/1 defers the signal until the translation is whole
%[measured 2026-08-24: a thread signalled abort inside sig_atomic/1 still
%finished its work].
%
%The mutex is the other half. Without it a second thread reaching the same name
%while the first was inside would read the compiling marker, conclude the work
%was in hand and call a predicate whose clauses were still arriving. Serialising
%is what SWI does for a file and costs nothing after the first call, because the
%deferral is gone by then and this predicate stops at its first test.
metta_ensure_compiled(F) :-
    (   deferred_metta_function(F, _, _, _, _, _)
    ->  sig_atomic(with_mutex(metta_deferred_translation,
                              translate_when_still_deferred(F)))
    ;   true
    ).

%Re-checked inside the mutex because the thread that held it may have been
%translating this very name, in which case there is nothing left to do. The
%compiling marker is the other exit: translating one equation's body compiles
%its call sites, and a recursive function's body names ITSELF, which would
%otherwise translate the rest of its equations from inside the first one and
%assert them out of order. Held off, the recursive body compiles against the
%clauses asserted so far, which is exactly what it saw when every equation was
%translated as it arrived. A global marker is enough for a per-thread question
%because the mutex admits one thread at a time, and SWI's mutexes are recursive,
%so the nested force a body's own call sites make re-enters rather than blocks
%[measured 2026-08-24: with_mutex(m, with_mutex(m, true)) succeeds].
translate_when_still_deferred(F) :-
    (   \+ deferred_metta_function(F, _, _, _, _, _)
    ->  true
    ;   metta_function_compiling(F)
    ->  true
    ;   setup_call_cleanup(
            assertz(metta_function_compiling(F), Guard),
            translate_deferred_function(F),
            erase(Guard))
    ).

%The safety net under every OTHER door. SWI calls user:exception/3 before it
%raises "unknown procedure", and `retry` makes the call happen again once the
%definition is there, which is the same hook SWI's own autoloader hangs on
%[source: SWI-Prolog 10.1 Reference Manual, exception/3]. So a deferred
%function is translated by anything that reaches its predicate -- a compiled
%goal, a host reaching into a space's execution module, a plain Prolog call --
%and not only by the doors this engine knows to guard. It cannot loop:
%translate_deferred_function/1 retracts the marker, so a second miss on the
%same name finds nothing here and the ordinary error follows
%[tested: translator_branch_returns:a_recursive_generator_enumerates_in_time_linear_in_its_answers].
:- multifile user:exception/3.

user:exception(undefined_predicate, Module:Name/_, retry) :-
    deferred_metta_function(Name, Module, _, _, _, _),
    !,
    metta_ensure_compiled(Name).

%The equations come back out of the space in the order they went in, which is
%the order they were written, because a store read enumerates its clauses. An
%equation removed while its function was still deferred is simply not there,
%so the removal door has nothing of its own to undo.
%
%The rows are COPIED here and retracted per pair only after that pair's
%clauses stand. A resource signal can land ANYWHERE inside a materialisation:
%an inference-limited eval whose first duty is the force spends its budget on
%translation, and the limit arrives as a synchronous exception sig_atomic/1
%does not defer. The first shape of this predicate retracted the rows up
%front and re-asserted them from a catch, and that lost the function twice
%over: the limit could land between the retracting findall and the catch's
%protection, and a limit that re-arms can kill the restoring handler itself.
%Either way the next call answered "Unknown procedure" where its caller was
%owed a limit error, armed by anything that shrinks the budget the parse
%spends before the force [measured 2026-08-24: the C reader cut that parse
%from ~150 inferences to 3 and test_ladder_rungs_cross_the_async_seam raised
%exactly that]. With the rows standing until the work is whole there is
%nothing to restore: a signal at ANY point leaves the pair deferred, the
%equations that DID land are excused by their provenance rows on the retry,
%and translate_missing_equations translates the rest, exactly once each
%[tested: spaces_deferred_translation:a_limit_landing_anywhere_inside_the_force_leaves_the_function_callable].
translate_deferred_function(F) :-
    findall(deferred(Space, Module, InputArity, Load, Count),
            deferred_metta_function(F, Module, Space, InputArity,
                                    Load, Count),
            Shapes),
    translate_deferred_pairs(F, Shapes).

translate_deferred_pairs(F, Shapes) :-
    findall(Space-Module,
            member(deferred(Space, Module, _, _, _), Shapes),
            Pairs0),
    list_to_set(Pairs0, Pairs),
    forall(member(Space-Module, Pairs),
           ( findall(InputArity-budget(Load, Count),
                     member(deferred(Space, Module, InputArity, Load, Count),
                            Shapes),
                     Budgeted),
             findall(InputArity, member(InputArity-_, Budgeted),
                     InputArities0),
             sort(InputArities0, InputArities),
             translate_deferred_equations(Space, Module, F, InputArities,
                                          Budgeted),
             %Only now, with the pair's clauses standing, do its rows go: a
             %signal before this line leaves the pair deferred and resumable.
             retractall(deferred_metta_function(F, Module, Space, _, _, _)),
             %The CALL-GRAPH event belongs here and not with the arrival: the
             %graph is the calls the compiled bodies make, extracted as each
             %clause is recorded, so before materialisation there is nothing
             %to read and the take-change guard makes the arrival announcement
             %a no-op. Skipped here too, the automatic-cache reconciliation
             %never saw a deferred function become recursive, and the
             %benchmark that pins automatic tabling measured the plain
             %exponential in both modes [measured 2026-08-24:
             %benchmarks/test_benchmarks.py::test_automatic_tabling_growth,
             %automatic 90,408 inferences at n=12 against its 5,466 pin].
             announce_function_call_graph_changed(Module, F) )).

%ONE pass over the space in STORE order, all of F's waiting arities together,
%because the order equations translate in is the order their call sites
%DECIDE in. A body naming F at another arity compiles a real call when that
%arity already has a translated head and the decided no-match dispatch when it
%does not, exactly as the eager door does per arrival; materialising
%arity-by-arity re-ordered that, so lib_pln's (= (PLN.Query $kb $term)
%(PLN.Query $kb $term N)), written LAST in its file after the arities it
%forwards to, translated FIRST and baked the no-match where the eager load
%compiled the call [measured 2026-08-24]. The store enumerates in insertion
%order, which is arrival order, which is the order the eager door compiled in,
%so every such decision lands the way it always has, the unhealed forward
%reference included: an equation naming a NOT-YET-ARRIVED arity of its own
%name answers its written form under both doors, and the pinned corpus pins
%that answer.
translate_deferred_equations(Space, Module, F, InputArities, Budgeted) :-
    findall([=, [F|W], Body],
            ( get_native_atom(Space, [=, [F|W], Body]),
              is_list(W),
              length(W, InputArity),
              memberchk(InputArity, InputArities) ),
            Equations),
    budget_queues(Budgeted, InputArities, Queues),
    (   metta_function_translated(Module, F)
    ->  translated_sources_of(Module, F, Stored),
        translate_missing_equations(F, Equations, Module, Stored, Queues)
    ;   translate_owned_equations(Equations, Module, F, Queues)
    ).

%One FIFO of budget(Load, Count) per arity, in row order, which is load
%arrival order. The walk pops one unit per stored copy it passes, so each
%equation is handed back to the load that stored it: the store appends, so a
%load's copies of one arity are a contiguous run in exactly the order the
%rows were written. An empty queue answers none, which journals nowhere; the
%one way to reach it with equations still untranslated is the removal
%limitation the deferral header records.
budget_queues(Budgeted, InputArities, Queues) :-
    findall(InputArity-Queue,
            ( member(InputArity, InputArities),
              findall(Budget, member(InputArity-Budget, Budgeted), Queue) ),
            Pairs),
    list_to_assoc(Pairs, Queues).

pop_equation_load([=, [_|W], _], Queues0, Load, Queues) :-
    length(W, InputArity),
    (   get_assoc(InputArity, Queues0, [budget(Load, Count)|Rest])
    ->  (   Count =< 1
        ->  Remaining = Rest
        ;   Left is Count - 1,
            Remaining = [budget(Load, Left)|Rest]
        ),
        put_assoc(InputArity, Queues0, Remaining, Queues)
    ;   Load = none,
        Queues = Queues0
    ).

%One equation, one transaction, the same unit compile_metta_equation/4 already
%commits atomically on the eager door: the clause, its fun_meta row, its
%provenance, and the queued-type consumption land together or not at all. A
%resource signal between any two of them otherwise leaves a half that poisons
%the retry both ways: provenance without a clause is excused into "Unknown
%procedure", a clause without provenance translates again and doubles its
%answers.
translate_owned_equations([], _, _, _).
translate_owned_equations([Equation|Equations], Module, F, Queues0) :-
    pop_equation_load(Equation, Queues0, Load, Queues),
    transaction(
        with_owning_source_load(Load,
            materialize_with_queued_types(Module, F,
                assert_translated_equation(Module, Equation, _, _)))),
    translate_owned_equations(Equations, Module, F, Queues).

%The second branch exists for one interleaving: a name's first arity defers, a
%SECOND arity arrives whose compiled predicate an inherited definition already
%answers, translates on arrival, and flips metta_function_translated/2 for the
%NAME, so a later equation of the still-deferred first arity translates on
%arrival too while the row and the earlier equations wait. The materialisation
%pass then meets translated and untranslated equations together, and
%re-translating a standing one would double its answers. Everywhere else the
%name-level flag is still down, which proves NOTHING of F is translated, and
%the enumeration translates unprobed: a probe here has to compare VARIANCE
%against every provenance row, and unifying against the row table instead
%skipped 29 of lib_nars's 51 `|-` rules, each one swallowed by an earlier
%rule's open-variable row [measured 2026-08-24].
translated_sources_of(Module, F, Stored) :-
    findall(Source,
            ( translated_from(Ref, Source),
              Source = [=, [F|_], _],
              clause_property(Ref, module(Module)) ),
            Stored).

%One provenance row excuses ONE stored copy, consumed as it matches, because
%equations are a multiset: the same equation stored twice answers twice, so a
%stored copy beyond its translated rows still translates. Variance decides a
%match, never unification, for the reason above.
translate_missing_equations(_, [], _, _, _).
translate_missing_equations(F, [Equation|Equations], Module, Stored0,
                            Queues0) :-
    pop_equation_load(Equation, Queues0, Load, Queues),
    (   select_variant_source(Equation, Stored0, Stored)
    ->  true
    ;   Stored = Stored0,
        transaction(
            with_owning_source_load(Load,
                materialize_with_queued_types(Module, F,
                    assert_translated_equation(Module, Equation, _, _))))
    ),
    translate_missing_equations(F, Equations, Module, Stored, Queues).

select_variant_source(Equation, [Source|Rest], Rest) :-
    Source =@= Equation,
    !.
select_variant_source(Equation, [Source|Rest], [Source|Kept]) :-
    select_variant_source(Equation, Rest, Kept).

translate_deferred_shape(Space, Module, F, InputArity) :-
    length(Args, InputArity),
    findall([=, [F|Args], Body],
            get_native_atom(Space, [=, [F|Args], Body]),
            Equations),
    forall(member(Equation, Equations),
           assert_translated_equation(Module, Equation, _, _)).

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
metta_instrument_recursive_clause([=, [F|HeadArguments], Body],
                                  (Head :- Goal),
                                  (Head :- Charge, Goal)) :-
    length(HeadArguments, Arity),
    metta_source_calls_head(Body, F, Arity),
    \+ metta_source_has_variable_head(Body),
    Head =.. [_|Arguments],
    append(Inputs, [_Output], Arguments),
    \+ ( member(Input, Inputs), nonvar(Input), Input == quote ),
    !,
    metta_fuel_culprit(F, Inputs, Culprit),
    metta_source_reduction_count(Body, Nodes),
    Cost is max(1, (Nodes + 1) // 2),
    %Built rather than called: the charge is written into this clause, which is
    %a third of what it cost as a shared call, and the cost lands as a literal
    %because it is settled here.
    metta_fuel_step_goal(Culprit, Cost, Charge).
metta_instrument_recursive_clause(_, Clause, Clause).

metta_fuel_culprit(_, [Only], Only) :- !.
metta_fuel_culprit(F, Inputs, [F|Inputs]).

metta_source_calls_head([quote, _], _, _) :- !, fail.
metta_source_calls_head([Head|Arguments], F, Arity) :-
    (   nonvar(Head), Head == F, length(Arguments, Arity)
    ->  true
    ;   member(Argument, Arguments),
        metta_source_calls_head(Argument, F, Arity)
    ).

metta_source_has_variable_head(Term) :-
    nonvar(Term),
    Term = [Head|Arguments],
    (   var(Head)
    ->  true
    ;   member(Argument, Arguments),
        metta_source_has_variable_head(Argument)
    ).

metta_source_reduction_count(Term, 0) :- var(Term), !.
metta_source_reduction_count([quote, _], 0) :- !.
metta_source_reduction_count([_|Arguments], Count) :- !,
    maplist(metta_source_reduction_count, Arguments, Counts),
    sum_list(Counts, Nested),
    Count is Nested + 1.
metta_source_reduction_count(_, 0).

add_function_atom(Storage, Space, Module, Term, FAtom, W) :-
    %Any equation of FAtom still waiting is translated BEFORE this one is
    %stored, because the marker translates everything the space holds for
    %FAtom and this equation is about to be one of them.
    metta_ensure_compiled(FAtom),
    store_equation(Storage, Space, Term),
    length(W, N),
    Arity is N + 1,
    register_arity(FAtom, Arity),
    %Translated as it arrives, not deferred like a source's equations: this is
    %the door one equation comes through at a time, so there is no batch to
    %amortise a deferral over, and a caller that adds an equation and then
    %reads the space's module finds the clause where it has always been.
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
    metta_prepare_local_predicate(Module, Clause),
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
    (   seam:engine_emitted(Name/Arity)
    ->  throw(error(metta_engine_goal_redefinition(Name, InputArity, Space),
                    context('=', 'the engine compiles this name into function \c
                                  bodies')))
    ;   throw(error(metta_builtin_redefinition(Name, InputArity, Space),
                    context('=', 'a builtin cannot be redefined in this space')))
    ).

%The refusal that reads worst when it is unrendered, because the term names a
%capability nobody has heard of and the whole point of the refusal is to teach
%it. `rules` is a promise about what a space HOLDS rather than about which
%methods a provider has, so no protocol can derive it and the message has to
%say how to opt in [tested: test_a_space_without_rules_says_how_to_hold_one].
prolog:error_message(metta_foreign_space_holds_no_rules(Space, Term)) -->
    { swrite(Term, TermText) },
    [ '~w does not hold rules, so ~w was refused rather than stored where it \c
       could never fire'-[Space, TermText], nl,
      '  a foreign space holds DATA unless it says otherwise; declare the \c
       rules capability on the provider to hold a program' ].

prolog:error_message(metta_foreign_operation_failed(Space, Capability)) -->
    [ 'the provider for ~w did not complete the ~w operation and gave no \c
       reason. A provider that cannot serve a request should raise, so the \c
       program can see why.'-[Space, Capability] ].
prolog:error_message(metta_foreign_plan_is_not_a_partition(Space, Patterns,
                                                          Claimed, Rest)) -->
    [ '~w claimed ~w and left ~w of the conjunction ~w, which do not partition \c
       it. A claim may take any subset and leave the rest, and may not drop a \c
       conjunct: the engine plans only what you leave, so a dropped pattern \c
       stops constraining the query and the join answers rows that were never \c
       asked for.'-[Space, Claimed, Rest, Patterns] ].
prolog:error_message(metta_engine_goal_redefinition(Name, Arity, Space)) -->
    [ '~w with ~w arguments is a name the engine itself compiles into function \c
       bodies, so no space can redefine it, ~w included.'-[Name, Arity, Space], nl,
      '  an equation for it would capture the engine\'s own goal in this \c
       space\'s compiled clauses rather than shadowing a function: rename it, \c
       or write the behaviour you want as a wrapper around it' ].
prolog:error_message(metta_builtin_redefinition(Name, Arity, Space)) -->
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
    (   metta_space_name(Space)
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
%A space is a NAME that is one, and metta_space_name/1 decides which. The doors
%used to share a metta_space_argument/1 whose whole body was `atom(Space)`, on
%the reading that this engine CANNOT reproduce the arbiter's
%`(add-atom not-a-space (bad add))` diagnostic: the two model spaces
%differently, upstream's being a grounded atom wrapping a space object while
%MeTTa's is a symbol, and a write to a name that does not exist yet creates it,
%so `not-a-space` and a program's own fresh name looked like the same kind of
%thing. That reading was wrong on its own terms, and the engine already
%disagreed with it in three places: is-space/2 answers False for a name without
%`&`, evalc/3 refuses one as a type error rather than reading a silently empty
%space, and bindings/python/metta/space.py refuses one with "the prefix is
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
%metta_space_name/1 is the prefix rather than the registry: a fresh `&kb` is a
%space the moment a program writes to it, and that capability is kept whole.
%The one example that used a name without the prefix,
%examples/ch04-spaces-and-matching/04-01-a-space-is-where-a-program-lives/07-add_atom_fun_space.metta, still returns a space name from a
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
%answer nothing, is metta_space_name/1 consulted to tell a space that is empty
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
    metta_note_copied_variables(Arguments, Subject),
    Error = ['Error', [Operation|Subject], Reason].

%A runnable installs its flat reader map only while its goals execute. The
%open Generated list is copied with each answer, so an operation that must
%copy a diagnostic subject can record the copied variable's spelling without
%putting attributes on matcher variables
%[tested: test_variable_names_survive_to_the_printer; commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
:- meta_predicate metta_run_named(+, 0, -).
metta_run_named(Names, Goal, Generated) :-
    Context = '$metta_runtime_name_context'(Names, Generated, Generated),
    setup_call_cleanup(
        install_runtime_name_context(Context, SavedContext),
        call(Goal),
        restore_runtime_name_context(SavedContext)).

install_runtime_name_context(Context, saved(Previous)) :-
    nb_current('$metta_runtime_name_context', Previous), !,
    nb_linkval('$metta_runtime_name_context', Context).
install_runtime_name_context(Context, none) :-
    nb_linkval('$metta_runtime_name_context', Context).

restore_runtime_name_context(saved(Previous)) :- !,
    nb_linkval('$metta_runtime_name_context', Previous).
restore_runtime_name_context(none) :-
    nb_delete('$metta_runtime_name_context').

metta_note_copied_variables(Original, Copy) :-
    nb_current('$metta_runtime_name_context', Context), !,
    Context = '$metta_runtime_name_context'(Names, _, _),
    term_variables(Original, OriginalVars),
    term_variables(Copy, CopyVars),
    metta_note_variable_pairs(OriginalVars, CopyVars, Names, Context).
metta_note_copied_variables(_, _).

metta_note_variable_pairs([], [], _, _).
metta_note_variable_pairs([Original|Originals], [Copy|Copies], Names, Context) :-
    (   metta_reader_variable_name(Names, Original, Name)
    ->  arg(3, Context, Tail),
        Tail = [Name-Copy|Next],
        setarg(3, Context, Next)
    ;   true
    ),
    metta_note_variable_pairs(Originals, Copies, Names, Context).

metta_reader_variable_name([Name-Variable|_], Original, Name) :-
    Variable == Original, !.
metta_reader_variable_name([_|Names], Original, Name) :-
    metta_reader_variable_name(Names, Original, Name).

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
    (   metta_space_name(Space)
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
%
%eval/2 AND NOT reduce/3, because the two differ on exactly the shape this
%operation is for. reduce/3 is the runtime dispatcher: it looks up the head and
%answers the term unchanged when no function heads it, so `(total (+ 1 2))`
%came back written and `(add-reduct &s (total (+ 1 2)))` stored the call.
%eval/2 compiles the expression the way a top-level form is compiled, and that
%walk reduces a MEMBER of an expression whose head names no function, which is
%what the arbiter's own interpret-tuple does: `!(total (+ 1 2))` is `(total 3)`
%on both engines, and now so is what add-reduct stores
%[measured 2026-08-24 against LeaTTa 9ea9f9d:
%`(add-reduct $s (total (+ 1 2)))` then `(get-atoms $s)` answers `((total 3))`
%there].
%
%A form that answers nothing keeps its written shape rather than removing the
%write: `Empty` prunes a branch, and an add whose atom pruned away has nothing
%to store, so the written term is the only thing left to store.
reduced_for_space(Term, Reduced) :-
    (   is_list(Term)
    ->  current_metta_module(Module),
        (   once(( eval_metta_in_module(Module, Term, Value),
                   Value \== 'Empty' ))
        ->  Reduced = Value
        ;   Reduced = Term
        )
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
    Term = [=, Scalar, _],
    atom(Scalar),
    !,
    unstore_atom(Space, Term, Removed),
    (   Removed == true
    ->  space_module(Space, Module),
        announce_function_changed(Module, Scalar)
    ;   true
    ).
metta_remove_atom(Space, Term, Removed) :-
    Term = [':', Type, Marker],
    atom(Type),
    ( Marker == 'DontEvalType' ; var(Marker) ),
    !,
    unstore_atom(Space, Term, Removed),
    (   Removed == true
    ->  space_module(Space, DeclModule),
        ( fun(Type) -> announce_function_changed(DeclModule, Type) ; true ),
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
                                           result_finality(F, Before),
                                           unstore_atom(Space, Term, Removed),
                                           space_module(Space, DeclModule),
                                           announce_declaration_changed(DeclModule, F, Before).
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
%refusal surfaced as `swrite/2: cannot write [->|'$metta_variable'(0)]` from
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
    (   seam:foreign_space(Space)
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
%moves. Found because the contract ontology's 65 resident atoms in &metta
%turned a get-atoms walk into +149 inferences per register-and-unregister
%cycle on the register-op benchmark [measured 2026-08-18: a remove on an
%80-atom &metta cost 303 inferences against 61 on a plain space, and the
%engine-level remove path profiled flat].
metta_host_removal_probe(Space, Pattern) :-
    Space = [_|_],
    space_parametric(Space),
    is_list(Pattern),
    Pattern = [Head|Arguments],
    atom(Head),
    native_storage_module(Space, Module),
    Goal =.. ['$metta_parametric_atom', Head|Arguments],
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
    (   seam:foreign_space(Space)
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
            assertz('$metta_shadow_repair_pending'(Module, F, PredArity))
        ;   metta_repair_emptied_shadows,
            metta_abolish_local_predicate(Module, F, PredArity)
        )
    ;   true
    ),
    %fun_in/2 is part of lexical declaration lookup, so withdraw the last
    %local ownership row before recompiling callers. Repairing first compiled
    %them against the local untyped tier and then exposed an inherited arrow
    %without another invalidation [tested:
    %lib_strategy:removing_a_local_shadow_recompiles_its_callers;
    %commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c]. The process-wide fun/1 row remains until the second
    %phase below, preserving the existing call-to-data removal transition.
    ( module_owns_function(Module, F) -> true ; unregister_fun_in(Module, F) ),
    announce_function_changed(Module, F),
    ( \+ function_still_defined(F)
      -> retractall(fun(F)), unregister_fun_everywhere(F),
         %announce_function_removed/1, not the bare event: fun(F) is false only now,
         %so THIS recompile is the one that reads mentions of F as data
         %again; the function_changed above ran while F was still a function.
         announce_function_removed(F)
      ; true ),
    ( Erased == false, Stored \== true -> Removed = false ; Removed = true ).

:- dynamic '$metta_shadow_repair_pending'/3.

%The deferred half of the emptied-shadow repair above: each pending row
%names a function a committed transaction emptied. The recheck matters,
%because a reload that REDEFINES a function empties it in withdrawal and
%refills it in the load, and only a function still empty at the sweep is
%a shadow to drop. abolish refusing (a tabled shadow) leaves the old
%behaviour, an empty local predicate.
metta_repair_emptied_shadows :-
    forall(retract('$metta_shadow_repair_pending'(Module, F, PredArity)),
           (   functor(Head, F, PredArity),
               (   predicate_property(Module:Head, number_of_clauses(0))
               ->  metta_abolish_local_predicate(Module, F, PredArity)
               ;   true
               )
           )),
    metta_repair_shadow_imports.

%Where an atom comes out of, the counterpart of store_atom/2. Both answer
%whether the store actually held it.

%% unstore_atom(+Space, ?Atom, -Removed:boolean) is semidet.
unstore_atom(Space, Term, Removed) :- seam:foreign_space(Space), !,
                                      foreign_write(Space, remove,
                                                    seam:foreign_remove(Space, Term,
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
%because that rides '$metta_answer_k' BACKTRACKABLY and findall would undo it:
%reset-call-read is metta_top/3's own idiom below, and the write after member/2
%is what hands the row's k to the template that reads (annotation).
%
%A space whose semiring is bool takes the plain collection, which is three
%inferences a row cheaper and is the traffic: under bool an answer's k can
%only be 1, because a provider handing one to an undeclared context raises
%rather than setting it ("a real k is admitted exactly when its context
%declared a non-Boolean semiring", bindings/python/metta/shim.pl), and the engine's own
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
%A GAP PATTERN arrives wrapped in the plan its call site decided, and this
%clause is the whole of its dispatch. The arity a gap pattern matches is what
%the gap decides rather than what the pattern fixes, so the read below cannot
%serve it: `(A ... D)` has three children and matches stored atoms of every
%arity from two upwards. The wrapper is what keeps the question free for
%everyone else, since nonvar/1 and =/2 compile inline and a clause head that
%does not unify costs no inference either.
%
%GUARDED RATHER THAN LEFT TO THE CUT, the same reason the last clause of this
%predicate states: the derivation meta-interpreter walks these clauses through
%clause/3 and call/1, where an earlier cut cannot prune this one, so each
%clause says for itself when it applies.
match(Space, Pattern, OutPattern, Result) :-
    nonvar(Pattern),
    Pattern = '$metta_seq'(Plan, Parsed),
    !,
    metta_seq_space(Plan, Space, Parsed, OutPattern, Result).
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
                                             ;   metta_space_name(Space)
                                             ->  fail
                                             ;   space_argument_error('match',
                                                                      [Space, Pattern,
                                                                       OutPattern],
                                                                      Result)
                                             ).

%A single pattern over a foreign space: the provider answers, and the
%conjunction door above has already taken the conjunctive case.
match(Space, Pattern, OutPattern, Result) :- nonvar(Space),
                                             seam:foreign_space(Space), !,
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
    \+ metta_space_name(Space),
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
    (   metta_effective_algebra(Space, bool)
    ->  findall(Row,
                Producer,
                Rows),
        member(Row, Rows)
    ;   metta_algebra_one(Space, One),
        findall(Row-K,
                ( b_setval('$metta_answer_k', One),
                  Producer,
                  b_getval('$metta_answer_k', K) ),
                Rows),
        member(Row-K, Rows),
        b_setval('$metta_answer_k', K)
    ),
    Result = OutPattern.
