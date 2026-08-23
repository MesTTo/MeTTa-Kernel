% Purpose: implement pre-add hooks, transforms, watchers, views, digests, and purity inventories
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE]

%%%% Space hooks: the general pre-add mechanism (P12) %%%%
%
%(declare-pre-add! <space> <handler>) claims the pre-add hook on a space
%for one MeTTa function of one argument, the incoming atom. Every write
%into a claimed space consults the handler first, equations and type
%declarations included, and the handler answers exactly one of
%
%    (accept)           the write proceeds with the atom as offered
%    (accept <atom'>)   the write proceeds with the TRANSFORMED atom.
%                       The handler's output is the GRANTED form and is
%                       not re-asked, exactly as a BEFORE trigger's
%                       modified row does not re-fire the trigger: the
%                       claimant has decided this request, and a handler
%                       wanting chained rewriting composes its own
%                       equations in the body
%    (refuse <words>)   the write throws, carrying the handler's words
%    (drop)             the write is silently skipped and the caller
%                       sees success, which set semantics needs
%
%The verdict algebra is a PostgreSQL row-level BEFORE trigger's (return
%NEW, return a modified row, raise, return NULL) and netfilter's
%(ACCEPT, mangle, REJECT, DROP); both draw the same silent-drop versus
%loud-refuse distinction. The refusal carries the handler's OWN
%sentence, the SpaceProvider.refusal pattern at the hook layer. In
%CHR's terms the hook fires at most ONE rule step per request, the
%bounded prefix of the ω_e semantics the arbiter mechanizes over this
%very atom fragment; ω_e itself has no refusal and no stuck state, so
%those belong to this admission door alone
%[source: LeaTTa MettaHyperonFull/Proofs/ChrOperational.lean].
%
%ONE claimant per (space, slot), checked when the claim is made, is the
%interaction-net discipline (Hassan, Mackie and Sato, GT-VMT 2008: at
%most one rule per pair of agents obtains confluence by construction):
%a second claimant is refused at declaration naming both, never raced
%at call time. Pattern-level dispatch belongs to the handler's own
%equations, which is where the critical-pair reporter already names
%overlaps. A claimed handler whose equations do not cover the incoming
%atom is a STUCK STATE and throws saying so, because an active pair
%with no rule is locally detectable; a handler that wants a default
%writes its own catch-all equation, one visible line.
%
%The handler runs in the module CURRENT AT DECLARATION, captured in the
%claim, because everything runs where it was written (evalc/3's own
%principle); its body reaches the hooked space by naming it. A handler
%error propagates to the add site unchanged. The wrapper installs on
%the first claim and an engine that never claims keeps the direct
%write path [tested: a_pre_add_hook_can_refuse_with_its_own_words,
%a_second_claimant_for_one_name_is_refused_with_both_named,
%an_unclaimed_request_is_a_stuck_state_that_says_so].
%The post-add slot mirrors the pre-add slot with the verdicts read
%against a LANDED atom: (accept) keeps it, (accept <atom'>) replaces it
%through the same write path with the replacement granted, (refuse
%<words>) undoes the write and throws, (drop) removes it silently. A
%post handler that errs or sticks also undoes the write first, so an
%errored hook leaves no atom behind. The event pair stays pure
%observation beside it: an observer's answer is discarded and the store
%does not move, which is the difference P12.2 names
%[tested: a_post_add_hook_may_transform_while_the_event_pair_only_observes].
:- dynamic petta_hook_claim/4.
:- dynamic petta_space_hooks_installed/0.

hook_slot_surface(pre_add, 'pre-add').
hook_slot_surface(post_add, 'post-add').

hook_slot_declare_form(pre_add, 'declare-pre-add!').
hook_slot_declare_form(post_add, 'declare-post-add!').

metta_declare_hook(Slot, Space, Handler) :-
    hook_slot_declare_form(Slot, Form),
    (   'is-space'(Space, true)
    ->  true
    ;   throw_metta_type_error(Form, 'SpaceType', Space)
    ),
    (   atom(Handler)
    ->  true
    ;   throw_metta_type_error(Form, 'Symbol', Handler)
    ),
    current_metta_module(Module),
    hook_slot_surface(Slot, SlotAtom),
    %The claim and its contract atom land together or not at all, the
    %declare_handles shape: a conflict thrown inside the transaction
    %rolls both back.
    transaction(( (   petta_hook_claim(Space, Slot, Prior, _)
                  ->  (   Prior == Handler
                      ->  true
                      ;   throw(error(petta_hook_conflict(Space, SlotAtom,
                                                          Prior, Handler),
                                      none))
                      )
                  ;   assertz(petta_hook_claim(Space, Slot, Handler, Module)),
                      metta_add_atom('&petta', [SlotAtom, Space, Handler], _),
                      %Compiled inside the same transaction, so a handler
                      %whose call site does not translate refuses the whole
                      %claim loudly at declaration instead of at the first
                      %write.
                      petta_hook_compile(Space, Slot, Handler, Module)
                  ) )),
    petta_install_space_hooks.

metta_undeclare_hook(Slot, Space) :-
    hook_slot_surface(Slot, SlotAtom),
    transaction(( (   retract(petta_hook_claim(Space, Slot, Handler, _))
                  ->  metta_remove_atom('&petta', [SlotAtom, Space, Handler], _),
                      petta_hook_drop_compiled(Space, Slot)
                  ;   true
                  ),
                  (   Slot == pre_add
                  ->  petta_capacity_count_uninstall(Space)
                  ;   true
                  ) )).

%(admits Pool Type) and (capacity Pool N) in &petta are data until a pool
%is equipped: this writes the guard equation
%  (= (space-admission-guard-<pool> $x) (space-admission-verdict <pool> $x))
%into DECLARER's space and claims POOL's pre-add hook with it, so the
%shipped judge, the space-admission-verdict builtin above, runs behind the
%same one-claimant registry as any user handler and a pool the sugar never
%touched keeps the direct write path. Idempotent per pool; a standing
%foreign claim on the slot conflicts loudly, which is the one-claimant
%rule doing its job [tested: hooks_admission_sugar].
petta_admission_claim(Pool0, Declarer0) :-
    (   atom(Pool0) -> Pool = Pool0 ; atom_string(Pool, Pool0) ),
    (   atom(Declarer0) -> Declarer = Declarer0 ; atom_string(Declarer, Declarer0) ),
    atom_concat('space-admission-guard-', Pool, Guard),
    (   petta_hook_claim(Pool, pre_add, Guard, _)
    ->  true
    ;   space_module(Declarer, Module),
        with_metta_module(Module,
            transaction(( (   \+ \+ 'get-atoms'(Declarer, [=, [Guard, _], _])
                          ->  true
                          ;   metta_add_atom(Declarer,
                                             [=, [Guard, X],
                                              ['space-admission-verdict',
                                               Pool, X]],
                                             _)
                          ),
                          metta_declare_hook(pre_add, Pool, Guard) )))
    ),
    petta_capacity_count_claim(Pool).

petta_install_space_hooks :-
    (   petta_space_hooks_installed
    ->  true
    ;   assertz(petta_space_hooks_installed),
        %The module the WRITE DOOR lives in, asked of SWI rather than assumed
        %to be this one: engine/spaces.pl has a module of its own since P11.7,
        %and wrap_predicate/4 on a name this module merely IMPORTS wraps the
        %import and leaves the definition alone, so every claimed write would
        %have gone straight past its guard [measured 2026-08-22: SWI reported
        %"Local definition of user:metta_add_atom/3 overrides weak import from
        %spaces" and examples/spaces/pre_add_hooks.metta stored the raw atom].
        seam:write_door_module(metta_add_atom/3, Engine),
        %Unqualified body for the reason ext_points.pl's two wrappers give:
        %wrap_predicate/4 declares it `0` and SWI qualifies it with this
        %file's module, which is the engine's.
        (   wrap_predicate(Engine:metta_add_atom(Space, Term, R),
                           petta_space_hook_guard, Wrapped,
                           petta_space_hooked_add(Space, Term, R, Wrapped))
        ->  true
        ;   throw(error(petta_atom_hook_install_failed(space_hooks), none))
        ),
        %The compiled fire clauses below bake each handler's translated call
        %site, and a changed equation or declaration re-shapes what that
        %translation would be, so any function change drops them all and the
        %next fire recompiles against the new program. Conservative on
        %purpose: claims are few, one stale template is a wrong verdict with
        %no symptom, and a flush costs one indexed lookup on a table that is
        %empty until something claims. Installed here, not at load, for the
        %reason the seam's header gives: a resident handler clause costs
        %four inferences on every compiled equation. If-then-else rather
        %than a cut, which is the event-seam law.
        assertz((seam:function_changed(_) :-
                    (   petta_hook_compiled(_, _, _)
                    ->  petta_hook_flush_compiled
                    ;   true
                    ))),
        assertz((seam:function_removed(_) :-
                    (   petta_hook_compiled(_, _, _)
                    ->  petta_hook_flush_compiled
                    ;   true
                    )))
    ).

%The claim-time compilation of a handler's call site, the specializer's
%own move applied to the hook door: eval_metta_in_module/3 per fire spent
%its cost re-translating [Handler, Atom] on EVERY write into a claimed
%space, measured at 234.03 inferences per add against 49.01 for a plain
%add, and the translation is the same every time until the program
%changes. The call site is translated once, here, and asserted as one
%clause in the DECLARING module:
%
%    '$petta_hook_fire'(Space, Slot, Atom, Verdict) :- call_goals_in_(M, Goals)
%
%The body is call_goals_in_/2 over the translated goal list, not a
%flattened conjunction, so a translated cut stays exactly as opaque as
%the eval path has it. The fire site below keeps the declaring module in
%force, switching only when the caller is not already there, so a handler
%body reading (context-space) or compiling against the current module sees
%what it saw before. Everything observable is the eval
%path's: same first-verdict law at the callers, same failure-is-stuck,
%same nondeterminism underneath
%[tested: hooks:a_compiled_fire_answers_what_the_eval_path_answers].
:- dynamic petta_hook_compiled/3.

petta_hook_compile(Space, Slot, Handler, Module) :-
    with_metta_module(Module,
                      translate_expr([Handler, Atom], Goals, Verdict)),
    assertz(Module:('$petta_hook_fire'(Space, Slot, Atom, Verdict) :-
                        call_goals_in_(Module, Goals)),
            Ref),
    assertz(petta_hook_compiled(Space, Slot, Ref)).

%Fire through the compiled clause, healing lazily after a flush: the
%mutex closes the race where two threads heal the same claim and the
%second assert would double the clause.
petta_hook_eval(Space, Slot, Handler, Module, Term, Verdict) :-
    (   petta_hook_compiled(Space, Slot, _)
    ->  true
    ;   with_mutex('$petta_hook_compile',
                   (   petta_hook_compiled(Space, Slot, _)
                   ->  true
                   ;   petta_hook_compile(Space, Slot, Handler, Module)
                   ))
    ),
    current_metta_module(Current),
    (   Current == Module
    ->  call(Module:'$petta_hook_fire'(Space, Slot, Term, Verdict))
    ;   with_metta_module(Module,
                          call(Module:'$petta_hook_fire'(Space, Slot, Term,
                                                         Verdict)))
    ).

petta_hook_drop_compiled(Space, Slot) :-
    forall(retract(petta_hook_compiled(Space, Slot, Ref)),
           catch(erase(Ref), _, true)).

petta_hook_flush_compiled :-
    forall(retract(petta_hook_compiled(_, _, Ref)),
           catch(erase(Ref), _, true)).

petta_space_hooked_add(Space, Term, R, Wrapped) :-
    (   petta_hook_granted_form(Space, Term)
    ->  %The handler's own transformed output arriving through the
        %inner add below: decided on BOTH slots, not re-asked. The
        %marker names the space AND the term, so a bridge or event
        %firing a DIFFERENT hooked space mid-write still consults that
        %space's own handlers.
        call(Wrapped)
    ;   petta_hook_pre_phase(Space, Term, R, Wrapped),
        petta_hook_post_phase(Space, Term)
    ).

petta_hook_pre_phase(Space, Term, R, Wrapped) :-
    (   petta_hook_claim(Space, pre_add, Handler, Module)
    ->  (   petta_hook_eval(Space, pre_add, Handler, Module, Term, Verdict)
        ->  (   petta_capacity_count(Space, _)
            ->  petta_hook_apply_counted(Verdict, Space, Handler, Term, R,
                                         Wrapped)
            ;   petta_hook_apply(Verdict, Space, Handler, Term, R, Wrapped)
            )
        ;   throw(error(petta_hook_stuck(Space, 'pre-add', Handler, Term),
                        none))
        )
    ;   call(Wrapped)
    ).

%The post phase runs only when the pre phase actually wrote Term as
%offered: a pre transform re-entered the wrapper under the granted
%marker (its inner add skipped both phases), a refusal threw, and a
%drop wrote nothing, so in each of those cases there is no landed Term
%to revise. A post error or stuck state undoes the write before it
%propagates, so a failed hook leaves no atom behind.
petta_hook_post_phase(Space, Term) :-
    (   petta_hook_claim(Space, post_add, Handler, Module),
        petta_hook_wrote_as_offered(Space, Term)
    ->  catch(( (   petta_hook_eval(Space, post_add, Handler, Module, Term,
                                    Verdict)
                ->  petta_hook_post_apply(Verdict, Space, Handler, Term)
                ;   throw(error(petta_hook_stuck(Space, 'post-add', Handler,
                                                 Term),
                                none))
                ) ),
              Ball,
              %The undo must not mask the error: a removal that finds
              %nothing (a concurrent taker, a transform that already
              %moved it) still rethrows the hook's own ball.
              ( ( metta_remove_atom(Space, Term, _) -> true ; true ),
                throw(Ball) ))
    ;   true
    ).

%Whether the pre phase left Term itself in the space: a claimed pre
%hook may have transformed or dropped it, and then the post phase has
%nothing to revise. Asked only on the doubly-hooked path, one membership
%probe against the store.
petta_hook_wrote_as_offered(Space, Term) :-
    (   petta_hook_claim(Space, pre_add, _, _)
    ->  \+ \+ 'get-atoms'(Space, Term)
    ;   true
    ).

petta_hook_post_apply([accept], _, _, _) :- !.
petta_hook_post_apply([accept, Term1], Space, _, Term) :- !,
    (   Term1 == Term
    ->  true
    ;   metta_remove_atom(Space, Term, _),
        setup_call_cleanup(
            b_setval('$petta_hook_granted', granted(Space, Term1)),
            metta_add_atom(Space, Term1, _),
            b_setval('$petta_hook_granted', [])),
        petta_capacity_count_added(Space, Term1)
    ).
%The refusal's undo is the catch handler's, once for every error path.
petta_hook_post_apply([refuse, Words], Space, _, Term) :- !,
    throw(error(petta_add_refused(Space, Term, Words), none)).
petta_hook_post_apply([drop], Space, _, Term) :- !,
    metta_remove_atom(Space, Term, _).
petta_hook_post_apply(Got, Space, Handler, Term) :-
    petta_hook_invalid_verdict('post-add', Got, Space, Handler, Term).

petta_hook_granted_form(Space, Term) :-
    catch(b_getval('$petta_hook_granted', granted(GSpace, GTerm)), _, fail),
    GSpace == Space,
    GTerm == Term.

%The counter fact is tested in the claimed pre phase, never on the direct
%write path. A counted accept therefore knows it owns the fact and can update
%without a second presence probe; the ordinary verdict algebra stays the
%shared fallback for refusal, drop and malformed answers.
petta_hook_apply_counted([accept], Space, _, Term, _, Wrapped) :- !,
    call(Wrapped),
    petta_capacity_count_added_known(Space, Term).
petta_hook_apply_counted([accept, Term1], Space, _, Term, R, Wrapped) :- !,
    (   Term1 == Term
    ->  call(Wrapped)
    ;   setup_call_cleanup(
            b_setval('$petta_hook_granted', granted(Space, Term1)),
            metta_add_atom(Space, Term1, R),
            b_setval('$petta_hook_granted', []))
    ),
    petta_capacity_count_added_known(Space, Term1).
petta_hook_apply_counted(Verdict, Space, Handler, Term, R, Wrapped) :-
    petta_hook_apply(Verdict, Space, Handler, Term, R, Wrapped).

petta_hook_apply([accept], _, _, _, _, Wrapped) :- !, call(Wrapped).
petta_hook_apply([accept, Term1], Space, _, Term, R, Wrapped) :- !,
    (   Term1 == Term
    ->  call(Wrapped)
    ;   setup_call_cleanup(
            b_setval('$petta_hook_granted', granted(Space, Term1)),
            metta_add_atom(Space, Term1, R),
            b_setval('$petta_hook_granted', []))
    ).
petta_hook_apply([refuse, Words], Space, _, Term, _, _) :- !,
    throw(error(petta_add_refused(Space, Term, Words), none)).
petta_hook_apply([drop], _, _, _, true, _) :- !.
petta_hook_apply(Got, Space, Handler, Term, _, _) :-
    petta_hook_invalid_verdict('pre-add', Got, Space, Handler, Term).

%A residual handler call is the hook's existing stuck state, not a malformed
%verdict. The fire remains an observer of evaluation; classification happens
%only after every verdict-algebra clause has missed. Doing the variant
%comparison after every successful fire added two inferences to each claimed
%write, while this cold route leaves accepted writes unchanged.
%[tested: hooks:an_unclaimed_request_is_a_stuck_state_that_says_so,
%hooks:a_post_stuck_state_undoes_the_write; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
petta_hook_invalid_verdict(Slot, Got, Space, Handler, Term) :-
    (   Got =@= [Handler, Term]
    ->  throw(error(petta_hook_stuck(Space, Slot, Handler, Term), none))
    ;   throw(error(petta_hook_bad_verdict(Space, Handler, Term, Got), none))
    ).

%The bulk door's question: a space with a claimed hook on either slot
%routes its batches through the per-atom door, where the wrapper consults
%the handler for every atom, and a pool's admission guard is one such
%claim [tested: a_batch_into_a_hooked_space_consults_the_handler_per_atom,
%a_batch_beyond_capacity_is_refused_like_lone_adds].
petta_hook_claim_idle(Space) :-
    \+ petta_hook_claim(Space, _, _, _).

%The MeTTa surface. Undeclaring is explicit and idempotent: the
%one-claimant rule would otherwise leave no way to change a handler,
%and an implicit replace would hide exactly the collision the rule
%exists to name.
'declare-pre-add!'(Space, Handler, []) :-
    metta_declare_hook(pre_add, Space, Handler).
'undeclare-pre-add!'(Space, []) :-
    metta_undeclare_hook(pre_add, Space).
'declare-post-add!'(Space, Handler, []) :-
    metta_declare_hook(post_add, Space, Handler).
'undeclare-post-add!'(Space, []) :-
    metta_undeclare_hook(post_add, Space).

:- multifile prolog:error_message//1.
prolog:error_message(petta_bridge_cascade(Op)) -->
    [ 'a bridge cascade passed depth 32 at ~q: bridges firing bridges \c
       must reach a fixed point, and this chain does not'-[Op] ].
prolog:error_message(petta_bridge_unknown_op(Op)) -->
    [ 'the bridge operation ~q is not a managed head; the heads are \c
       (insert Ctx Atom), (retract Ctx Atom) and (revise Ctx Old \c
       New)'-[Op] ].
prolog:error_message(petta_hook_conflict(Space, Slot, Prior, Claimant)) -->
    [ '~w already claims the ~w hook on ~w and ~w tried to claim it \c
       too; one claimant per name, checked when the claim is made, so \c
       undeclare the standing one first'-[Prior, Slot, Space, Claimant] ].
prolog:error_message(petta_hook_stuck(Space, Slot, Handler, Term)) -->
    [ 'the ~w hook on ~w is claimed by ~w, whose equations do not \c
       cover ~q; a request no rule covers is a stuck state that says \c
       so, so cover the shape or give the handler its own \c
       catch-all'-[Slot, Space, Handler, Term] ].
prolog:error_message(petta_add_refused(Space, Term, Words)) -->
    [ '~w refused ~q: ~w'-[Space, Term, Words] ].
prolog:error_message(petta_foreign_space_count(Space)) -->
    [ '~w is a foreign space, so its atoms live with its provider and \c
       counting them is an enumeration there, not a native property read; \c
       ask the provider, or count what a match answers'-[Space] ].
prolog:error_message(petta_hook_bad_verdict(Space, Handler, Term, Got)) -->
    [ '~w answered ~q for ~q into ~w, which is none of (accept), \c
       (accept <atom>), (refuse <words>) or (drop)'-[Handler, Got,
                                                     Term, Space] ].
prolog:error_message(petta_hook_cascade(Space, Handler)) -->
    [ 'the pre-add hook ~w on ~w transformed through depth 32: a \c
       transforming hook must reach a fixed point, and this chain does \c
       not'-[Handler, Space] ].

%(writes Ctx Atomicity) declares what a context's writes promise:
%transactional providers participate in the engine's transactions through
%the begin/commit/rollback hooks, best-effort is the author's declared
%acceptance of partial application, and atomic-single promises single
%writes only. Silence refuses a write inside a transaction loudly,
%because the old behaviour, a foreign write surviving a rolled-back
%transaction, was silent wrongness, not a floor worth keeping.
petta_writes(Ctx, Atomicity) :-
    (   petta_contract_fact([writes, Ctx, Declared])
    ->  Atomicity = Declared
    ;   Atomicity = undeclared
    ).

%The transaction form's runtime: SWI's transaction/1 for the engine's own
%database, with foreign participation coordinated around it. Providers
%enlist at their first write (petta_enlist_foreign/1, from
%foreign_write/3), and the registry is finished HERE: commit on success,
%rollback on failure or throw. A nested transaction runs inside the
%outer's registry, so providers see one begin and one finish per
%outermost transaction. Commit is single-coordinator: a provider whose
%commit throws leaves earlier commits standing, and the throw says so;
%two-phase commit is deliberately out of scope.
%The meta declaration stays in the same source unit as the clause. When it
%lived in runtime.pl after this extraction, reconsulting that later unit
%abolished the earlier static predicate before the umbrella's publication
%check ran [tested: `swipl -q -g "consult('engine/metta.pl'),
%load_files('engine/metta.pl',[if(true)]),
%current_predicate(user:petta_transaction/1),halt" -t halt`; commit=WORKTREE].
:- meta_predicate petta_transaction(0).
petta_transaction(Goal) :-
    term_variables(Goal, Vars),
    (   current_transaction(_)
    ->  transaction(petta_transaction_answers(Goal, Vars, Answers))
    ;   nb_setval('$petta_tx_enlisted', []),
        catch(( setup_call_cleanup(
                    b_setval('$petta_user_tx', true),
                    transaction(petta_transaction_answers(Goal, Vars, Answers)),
                    b_setval('$petta_user_tx', false))
            ->  Outcome = committed ; Outcome = failed ),
              Error,
              Outcome = threw(Error)),
        nb_getval('$petta_tx_enlisted', Enlisted),
        nb_setval('$petta_tx_enlisted', []),
        (   Outcome == committed
        ->  forall(member(Space, Enlisted), seam:foreign_commit(Space)),
            %The committed body may have emptied a function that shadows
            %an inherited definition; remove_equation/6 deferred the
            %predicate-level drop to the transaction's owner, which is
            %here for the user's (transaction ...) form.
            petta_repair_emptied_shadows
        ;   forall(member(Space, Enlisted),
                   catch(seam:foreign_rollback(Space), RollbackError,
                         print_message(error, RollbackError)))
        ),
        (   Outcome == committed -> true
        ;   Outcome == failed -> fail
        ;   Outcome = threw(E), throw(E)
        )
    ),
    member(Vars, Answers).

%COLLECT, COMMIT, THEN REPLAY, which is what preserving a body's answers
%costs. SWI's transaction/1 runs its goal as once/1 and cannot be made
%nondeterministic in place, so `(collapse (transaction (superpose (1 2 3))))`
%answered `(1)`: two of three answers gone and nothing said so
%[reproduced 2026-08-19]. Dropping answers is an OPACITY violation in the
%transactional-memory sense (Guerraoui and Kapalka, PPoPP 2008), since a
%reader of the transaction's result sees a state no serial execution of the
%body produces.
%
%Refusing a nondeterministic body was the other branch offered, and it is not
%implementable at a lower cost: knowing a Prolog goal is nondeterministic
%means running it to a second answer, at which point the answers are already
%in hand and refusing them throws away work already done. So the branch that
%CAN be built is the one that is also correct.
%
%The whole body runs inside the transaction, so every answer's writes commit
%or roll back together, and the replay happens after the commit, so a consumer
%that stops after the first answer cannot leave a transaction open. An
%answerless body fails the guard, which rolls the transaction back and fails
%petta_transaction/1 exactly as it did before.
%
%The cost is that the answers are materialized: a body with an unbounded
%answer set exhausts the stack here where it used to yield once. That is the
%honest price of atomicity over a whole answer set, and it raises a resource
%error rather than silently answering a prefix.
petta_transaction_answers(Goal, Vars, Answers) :-
    findall(Vars, Goal, Answers),
    Answers \== [].

%Only the USER's (transaction ...) form guards foreign writes: the
%engine's own internal transactions (a rule registration compiles inside
%one for atomic rollback of compiler state) keep their long-standing
%behaviour, which the foreign-rules suite pins. The flag is
%backtrackable and thread-local; the outermost user transaction sets it,
%a nested one runs inside it untouched.
petta_in_user_transaction :-
    catch(b_getval('$petta_user_tx', true), _, fail).

petta_enlist_foreign(Space) :-
    nb_getval('$petta_tx_enlisted', Enlisted),
    (   memberchk(Space, Enlisted)
    ->  true
    ;   seam:foreign_begin(Space),
        nb_setval('$petta_tx_enlisted', [Space|Enlisted])
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_transaction_unsupported(Ctx, undeclared)) -->
    [ 'a transaction wrote to ~w, which declares nothing about its \c
       writes. The write cannot be rolled back with the transaction, and \c
       silently keeping it is the wrong answer this error replaces. \c
       Declare (writes ~w transactional) for a provider with \c
       begin/commit/rollback, or (writes ~w best-effort) to accept \c
       partial application deliberately'-[Ctx, Ctx, Ctx] ].
prolog:error_message(petta_transaction_unsupported(Ctx, 'atomic-single')) -->
    [ '~w declares (writes ~w atomic-single): single writes are atomic \c
       and transactions are not offered, so this transactional write is \c
       refused'-[Ctx, Ctx] ].

%(emits Ctx Policy) declares the order a context emits its own answers
%in; best-first is the promise (top k) needs before its bound may reach
%the provider, since the first k of a best-first emission ARE the k
%best. Distinct from (merge <pattern> <policy>), which is the ENGINE's
%strategy for merging answers across several contexts.
petta_emits(Ctx, Policy) :-
    petta_contract_fact([emits, Ctx, Policy]).

%%%% Subscribability as a declared capability (P12.14) %%%%
%
%(events Ctx Delivery [Order]) declares that a context can emit change
%events at all, and at what fidelity. Delivery is at-most-once,
%at-least-once or per-write-exactly and Order is ordered or unordered,
%defaulting to unordered because an omitted promise is the weaker one.
%
%The point is that subscribability is a promise about a CONTEXT, not a
%property the engine may infer. A native space is the engine's own store
%and every write into it runs seam:atom_added/2, so it delivers
%per-write-exactly and ordered by construction and needs no declaration:
%that is a fact about this engine, not an assumption about a provider. A
%FOREIGN context is the other case, and inference there is wrong in the
%direction that loses events. A remote space implements add and remove
%and its contents still change on the server, so deriving "it can emit
%events" from "it can be written" made a watcher hear this process's own
%writes and silently miss every other one [source:
%bindings/python/metta/remote.py, RemoteSpace.can_run; measured
%2026-08-19]. So a foreign context serves subscriptions when it declares
%(events ...) and is refused when it does not, naming what is missing.
%
%The worked foreign instances are in this tree's own dependencies: redis
%pub/sub is fire-and-forget, so a redis-attached space promises
%at-most-once, and PostgreSQL LISTEN/NOTIFY is the same shape. The
%decoupling dimensions a declaration here is about are the pub/sub
%survey's own [source: Eugster, Felber, Guerraoui and Kermarrec, The Many
%Faces of Publish/Subscribe, ACM Computing Surveys 35(2), 2003, section
%2.2: space, time and synchronization decoupling]
%[tested: test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses].
%petta_events_declared/1 is the shortcut and it comes first: a context no
%(events ...) atom has ever named cannot have one, so the store probes are
%skipped outright. Every standing query writes a (subscription <ctx> ...)
%atom whose second argument is the space, so the general petta_ctx_declared
%flag says yes for every watched space and could not do this job.
petta_events(Ctx, Delivery, Order) :-
    (   petta_events_declared(Ctx),
        (   petta_contract_fact([events, Ctx, Delivery, Declared])
        ->  Order = Declared
        ;   petta_contract_fact([events, Ctx, Delivery]),
            Order = unordered
        )
    ->  true
    ;   seam:context_events(Ctx, Delivery, Order)
    ).

%What a space can deliver, whoever holds it. Native spaces answer the
%engine's own guarantee; a foreign one answers its declaration, and a
%foreign one without a declaration answers nothing, which is what the
%refusal below reads.
petta_event_capability(Space, Delivery, Order) :-
    (   seam:foreign_space(Space)
    ->  once(petta_events(Space, Delivery, Order))
    ;   petta_events(Space, Delivery, Order)
    ->  true
    ;   Delivery = 'per-write-exactly',
        Order = ordered
    ).

%Refuse an operation that needs change events on a context that promises
%none. Operation is the caller's own word, so a blocking take and a
%standing query each name themselves.
petta_require_events(Space, Operation) :-
    (   petta_event_capability(Space, _, _)
    ->  true
    ;   throw(error(petta_events_undeclared(Space, Operation), none))
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_events_undeclared(Space, Operation)) -->
    [ '~w cannot ~w: it declares no (events ~w <delivery>) capability, \c
       so nothing promises its changes reach a watcher. A context whose \c
       every write goes through this engine declares (events ~w \c
       per-write-exactly ordered); one with its own channel declares \c
       what that channel promises, at-most-once or at-least-once; and \c
       one whose contents change where no channel reports it declares \c
       nothing and is refused here rather than serving a subscription \c
       that silently misses writes'-[Space, Operation, Space, Space] ].

%%%% The handles route: declared fidelity per context and shape %%%%
%
%(handles Ctx Pattern Fidelity [Det]) atoms in &petta declare, per shape and
%instantiation, how faithful a context's own filtering is. Entries are
%patterns; a query is routed by the most specific entry that matches it,
%where (in $x) in an entry position matches only a bound argument. Two
%matching entries neither of which is more specific must agree on their
%claim, the critical-pair reading of MeTTa's own non-exclusive equations;
%disagreement is a loud conflict naming both. Consulted where the provider's
%own pushdown method used to be the only voice, and only at query time,
%never per answer.

%One entry of a shape-routed declaration head that matches Query: the
%stripped pattern and the adorned position paths feed the specificity
%comparison, and the entry as declared is what an error names, since that
%is the atom its author can find. The payload is whatever follows the
%shape in the declaration, [Fidelity, Det] for handles, [Mode] for
%on-error; one algorithm routes every per-shape declaration head.
petta_shape_entry(Head, Ctx, Query, entry(Stripped, Paths, Entry, Payload)) :-
    petta_shape_fact(Head, Ctx, Entry, Payload),
    petta_adorn_strip(Entry, Stripped, Requirements, Paths),
    subsumes_term(Stripped, Query),
    \+ \+ ( Stripped = Query,
            forall(member(Position, Requirements), nonvar(Position)) ).

%WHICH heads route by shape is catalog data, not a clause list here: a
%(routed-by-shape Head [Key]) row in '&petta' plus the head's (kind ...)
%row make spaces.pl's materializer compile these two predicates' clauses
%for that head, the shipped handles, on-error and merge dispatch built by
%the same walk from the presets as any third-party routed kind. (merge
%<pattern> <policy>) is the ENGINE's strategy for merging answers across
%several contexts, keyed by the query shape alone, which is what its
%global route key means. The materialized fact clauses read through
%petta_contract_fact/1 exactly as the hand-written ones did, one clause
%per stored arity with omitted trailing optionals padded to none.
:- dynamic petta_shape_fact/4.
:- dynamic petta_shape_declared/2.

%Strip (in $x) wrappers, collecting the subterms that must arrive bound and
%the position path of each, root-to-leaf indices reversed. Requirements are
%checked against the query; paths are renaming-invariant, which is what the
%specificity order needs to compare two entries' adornments.
%The wrapper is recognised at expression POSITIONS only, by the literal atom
%in its head: the spine walk below never offers a list tail to this test.
%Offering tails was the bug this shape replaces, since a tail [X, Y] whose
%head is an entry variable unifies with the marker pattern, binds X to in,
%and mangles the entry into an open list that matches everything.
petta_adorn_strip(Term, Stripped, Requirements) :-
    petta_adorn_strip(Term, Stripped, Requirements, _).
petta_adorn_strip(Term, Stripped, Requirements, Paths) :-
    petta_adorn_strip(Term, [], Stripped, Requirements, Paths).

petta_adorn_strip(Var, _, Var, [], []) :- var(Var), !.
petta_adorn_strip(Term, Here, Inner, [Inner|Requirements], [Here|Paths]) :-
    Term = [Marker, Inner0], Marker == in, !,
    petta_adorn_strip(Inner0, Here, Inner, Requirements, Paths).
petta_adorn_strip(List, Here, Stripped, Requirements, Paths) :-
    List = [_|_], !,
    petta_adorn_strip_spine(List, 0, Here, Stripped, Requirements, Paths).
petta_adorn_strip(Atom, _, Atom, [], []).

petta_adorn_strip_spine(Var, _, _, Var, [], []) :- var(Var), !.
petta_adorn_strip_spine([], _, _, [], [], []).
petta_adorn_strip_spine([Head0|Tail0], Index, Here,
                        [Head|Tail], Requirements, Paths) :-
    petta_adorn_strip(Head0, [Index|Here], Head, HeadReqs, HeadPaths),
    Next is Index + 1,
    petta_adorn_strip_spine(Tail0, Next, Here, Tail, TailReqs, TailPaths),
    append(HeadReqs, TailReqs, Requirements),
    append(HeadPaths, TailPaths, Paths).

%The route: most specific matching entry, coherence-checked among the
%maximal ones. No entry means no claim, which is today's behaviour exactly.
petta_handles_route(Ctx, Query, Fidelity, Det) :-
    petta_handles_route(Ctx, Query, _, Fidelity, Det).

%The overwhelmingly common context has no such declarations and pays for
%this on every foreign match, so the emptiness answer must be nearly free:
%one indexed call per stored arity, against the storage module spaces.pl
%pre-creates with unknown set to fail, so a missing arity FAILS here in a
%handful of inferences instead of costing a thrown and caught existence
%error [measured 2026-08-17: the guard at 15 inferences per miss against
%137 through the catch-per-probe path]. The module name is computed once at
%load through native_storage_module/2, the single source of that mapping.
:- dynamic petta_contract_storage/1.
:- native_storage_module('&petta', Module),
   assertz(petta_contract_storage(Module)).

petta_handles_route(Ctx, Query, Entry, Fidelity, Det) :-
    petta_shape_route(handles, Ctx, Query, Entry, [Fidelity, Det]).

%Route one query through one declaration head: the most specific matching
%entry, coherence-checked among the maximal ones, exactly evaluation's own
%dispatch of a call against equation heads.
petta_shape_route(Head, Ctx, Query, Entry, Payload) :-
    petta_shape_declared(Head, Ctx),
    findall(E, petta_shape_entry(Head, Ctx, Query, E), Entries),
    Entries \== [],
    petta_shape_maximal(Entries, Maximal),
    Maximal = [entry(_, _, Entry, Payload)|Rest],
    forall(member(entry(_, _, E2, P2), Rest),
           (   P2 == Payload
           ->  true
           ;   throw(error(petta_contract_conflict(Ctx, Entry, E2, Query),
                           none))
           )).

%The entries no other entry is strictly more specific than.
petta_shape_maximal(Entries, Maximal) :-
    findall(E,
            ( member(E, Entries),
              \+ ( member(Q, Entries),
                   petta_shape_stricter(Q, E) ) ),
            Maximal).

%Q strictly more specific than P: a strictly narrower pattern, or the same
%pattern up to renaming with strictly more positions required bound. The
%second clause is what makes the scan-only idiom coherent, (edge (in $a)
%$b) Refuse beside (edge $x $y) Exact: the adorned entry matches strictly
%fewer queries, so it wins the bound-subject overlap the way Mercury's
%mode-indexed determinism declarations discriminate on modes. A narrower
%pattern outranks any adornment difference, so requirements are compared
%only between renaming-equal patterns, where paths line up positionally.
petta_shape_stricter(entry(QP, _, _, _), entry(PP, _, _, _)) :-
    \+ QP =@= PP,
    subsumes_term(PP, QP),
    \+ subsumes_term(QP, PP), !.
petta_shape_stricter(entry(QP, QPaths, _, _), entry(PP, PPaths, _, _)) :-
    QP =@= PP,
    sort(QPaths, QSorted),
    sort(PPaths, PSorted),
    ord_subtract(PSorted, QSorted, []),
    QSorted \== PSorted.

%The declared error mode for one context and query shape; silence is
%abort, which is exactly today's behaviour.
petta_on_error_mode(Ctx, Query, Mode) :-
    petta_ctx_declared(Ctx),
    petta_shape_route('on-error', Ctx, Query, _, [Mode]).

%The declared cross-context merge strategy for one query shape; silence
%is depth, which is exactly today's behaviour.
petta_merge_route(Query, Policy) :-
    petta_shape_route(merge, global, Query, _, [Policy]).

%Transport failure is never any declared mode's to keep or empty: the
%backend is ABSENT rather than wrong, retrying is the caller's decision,
%and an absent backend has said nothing about the data. The Python side
%classifies at the crossing with isinstance, where subclassing is still
%visible, and re-raises under this one name.
%What counts as a transport failure is the host's to say: the term shape
%of a connection dying under a provider is host machinery, so the bridge
%declares it and the engine only forwards the question.
petta_transport_failure(Error) :- metta_host_transport_failure(Error).

%A kept error as the answer it becomes: MeTTa's own (Error <culprit>
%<reason>) shape, the culprit being the query pattern as asked, since the
%failed attempt's bindings were undone with the throw. An error a HOST
%threw renders through the bridge's own reason hook, which knows its
%exception shapes; everything else renders through the message system.
petta_error_answer(Pattern, Error, ['Error', Pattern, Reason]) :-
    (   metta_host_error_reason(Error, Reason0)
    ->  Reason = Reason0
    ;   message_to_string(Error, Reason)
    ).

%Critical-pair coherence over a context's entries, for checking a
%declaration EAGERLY instead of on the first query that falls into an
%overlap. Knuth-Bendix's move: for every pair of entries the pair's most
%general common instance is itself routed, with the adorned positions
%marked bound so the most demanding instance is the one examined, and the
%route throws its own conflict if the pair is a disagreeing tie. An overlap
%one entry is strictly more specific over is not a conflict, which is why
%routing decides rather than a bare overlap test.
petta_handles_coherent(Ctx) :-
    findall(Pattern-Requirements,
            ( (   petta_contract_fact([handles, Ctx, Entry, _, _])
              ;   petta_contract_fact([handles, Ctx, Entry, _])
              ),
              petta_adorn_strip(Entry, Pattern, Requirements) ),
            Entries),
    forall(( append(_, [First|Rest], Entries), member(Second, Rest) ),
           petta_handles_pair_coherent(Ctx, First, Second)).

petta_handles_pair_coherent(Ctx, P1-R1, P2-R2) :-
    \+ \+ (   P1 = P2
          ->  term_variables(R1-R2, Unbound),
              maplist(=('$petta_bound'), Unbound),
              petta_handles_route(Ctx, P1, _, _)
          ;   true
          ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_contract_conflict(Ctx, E1, E2, Witness)) -->
    [ 'two (handles ~w ...) entries match ~q and disagree: ~q and ~q. \c
       Make one more specific, or declare the overlap itself with its \c
       own entry'-[Ctx, Witness, E1, E2] ].
prolog:error_message(petta_refused_shape(Ctx, Pattern, Entry)) -->
    [ '~w declares (handles ... ~q Refuse) and this query is that shape: \c
       ~q. The context cannot answer it, and the declaration makes that \c
       loud here rather than a silent partial answer later'-[Ctx, Entry,
                                                             Pattern] ].

seam:pure_operation(Name) :- pure_arithmetic(Name).
seam:pure_operation(Name) :- pure_comparison(Name).
seam:pure_operation(Name) :- pure_structure(Name).
seam:pure_operation(Name) :- pure_inspection(Name).
seam:pure_operation(Name) :- pure_engine_helper(Name).

%The engine's own helpers that a compiled body calls. They inspect and raise;
%none of them writes anything a cache could hide. The two refusal helpers read
%the DECLARATION register and nothing else, and a declaration reaching a space
%already recompiles what mentions the name, so a cached answer cannot outlive
%the declarations it was computed from.
pure_engine_helper(metta_arith_operands).
pure_engine_helper(metta_bad_argument_error).
pure_engine_helper(check_argument_type).
pure_engine_helper(function_overapplication).
pure_engine_helper(throw_metta_type_error).
pure_engine_helper(rethrow_metta_operation_error).
pure_engine_helper(non_list).
pure_engine_helper(list_shaped).
%The two halves of the charge petta_fuel_step_goal/3 writes into every
%compiled recursive clause. They stand where petta_fuel_step/2 stood before
%the charge was inlined, and classifying them the same way is what keeps a
%tabled recursive body cacheable across that change.
pure_engine_helper(petta_evaluation_fuel).
pure_engine_helper(petta_fuel_exhausted).
pure_engine_helper(type_answers).
pure_engine_helper(satisfies_metatype).
%These two only choose the language-level residual, failure or Error value.
%Policy and type changes recompile dependants through the support graph, so
%neither hides a lasting effect from a cached caller.
pure_engine_helper(dispatch_mismatch_result).
pure_engine_helper(dispatch_no_match_result).

pure_arithmetic('+').  pure_arithmetic('-').  pure_arithmetic('*').
pure_arithmetic('/').  pure_arithmetic('%').  pure_arithmetic(min).
pure_arithmetic(max).  pure_arithmetic(exp).
pure_arithmetic('abs-math').   pure_arithmetic('acos-math').
pure_arithmetic('asin-math').  pure_arithmetic('atan-math').
pure_arithmetic('ceil-math').  pure_arithmetic('cos-math').
pure_arithmetic('exp-math').   pure_arithmetic('floor-math').
pure_arithmetic('isinf-math'). pure_arithmetic('isnan-math').
pure_arithmetic('log-math').   pure_arithmetic('pow-math').
pure_arithmetic('round-math'). pure_arithmetic('sin-math').
pure_arithmetic('sqrt-math').  pure_arithmetic('tan-math').
pure_arithmetic('trunc-math').

pure_comparison('<').  pure_comparison('>').  pure_comparison('<=').
pure_comparison('>=').  pure_comparison('==').  pure_comparison('!=').
pure_comparison('=').  pure_comparison('=?').  pure_comparison('=alpha').
pure_comparison(dif).  pure_comparison(and).   pure_comparison(or).
pure_comparison(not).  pure_comparison(xor).   pure_comparison(implies).

pure_structure('car-atom').    pure_structure('cdr-atom').
pure_structure('cons-atom').   pure_structure('decons-atom').
pure_structure(cons).          pure_structure(decons).
pure_structure('size-atom').   pure_structure('index-atom').
pure_structure('sort-atom').   pure_structure('union-atom').
pure_structure('intersection-atom'). pure_structure('subtraction-atom').
pure_structure('unique-atom'). pure_structure('alpha-unique-atom').
pure_structure('map-atom').    pure_structure('filter-atom').
pure_structure('foldl-atom').  pure_structure('max-atom').
pure_structure('min-atom').    pure_structure('exclude-item').
pure_structure('first-from-pair'). pure_structure('second-from-pair').
pure_structure(first).  pure_structure(last).  pure_structure(append).
pure_structure(length). pure_structure(member). pure_structure('is-member').
pure_structure('is-alpha-member'). pure_structure(reverse).
pure_structure(sort).   pure_structure(msort).  pure_structure(list_to_set).
pure_structure(foldl).  pure_structure(maplist). pure_structure(superpose).
pure_structure(empty).  pure_structure(id).      pure_structure(noeval).
pure_structure(copy_term). pure_structure(term_hash).

pure_inspection('get-type').     pure_inspection('get-metatype').
pure_inspection('has-declared-type').
pure_inspection('is-var').       pure_inspection('is-ground').
pure_inspection('is-expr').      pure_inspection('is-space').
pure_inspection(repr).           pure_inspection(repra).
pure_inspection(parse).          pure_inspection(sread).
pure_inspection(atom_chars).     pure_inspection(atom_concat).
pure_inspection(has_type).       pure_inspection(metatype_of).

'is-var'(A,R) :- var(A) -> R=true ; R=false.
'is-ground'(A,R) :- ground(A) -> R=true ; R=false.
'is-expr'(A,R) :- list_shaped(A) -> R=true ; R=false.
'is-space'(A,R) :- petta_space_name(A) -> R=true ; R=false.
