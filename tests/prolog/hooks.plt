% Purpose: PlUnit coverage for the space-hook mechanism in src/metta.pl:
%   (declare-pre-add! <space> <handler>), the one-claimant rule, the
%   four-verdict algebra (accept, accept-transformed, refuse, drop), the
%   stuck state, the batch door's degrade to per-atom adds, the
%   claim-time compiled fire path, the admits/capacity sugar riding
%   the same registry through petta_admission_claim/2, and the design
%   board's worked instances (threadpool, CHR vocabulary, set-as-rule).
%
%   The discipline under test is the interaction-net one (Hassan, Mackie
%   and Sato, GT-VMT 2008): at most one rule per pair of agents, checked
%   when the claim is made, and a request no rule covers is locally
%   detectable rather than silently decided. The verdicts are a BEFORE
%   trigger's; the transform is one rule step, its output granted and not
%   re-asked, the bounded prefix of the CHR ω_e semantics the arbiter
%   mechanizes (LeaTTa MettaHyperonFull/Proofs/ChrOperational.lean).
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

%Run MeTTa source and answer the result groups, swallowing the engine's
%compilation printing, the duals.plt idiom.
metta(Source, Results) :-
    with_output_to(string(_), user:process_metta_string(Source, Results)).

metta(Source) :- metta(Source, _).

%The handler equations, defined once for the whole file: pure functions in
%&self, harmless across tests. Claims are per-test state and never shared.
:- dynamic hook_guards_defined/0.

ensure_hook_guards :-
    (   hook_guards_defined
    ->  true
    ;   assertz(hook_guards_defined),
        metta("
          (= (hplt-guard (secret $x)) (refuse \"no secrets in this pool\"))
          (= (hplt-guard (raw $x)) (accept (cooked $x)))
          (= (hplt-guard (dup $x)) (drop))
          (= (hplt-guard (plain $x)) (accept))
          (= (hplt-other-guard (plain $x)) (accept))
          (= (hplt-wrong $a) 42)
          (= (hplt-open $a) (accept))
        ")
    ).

%Undeclaring is idempotent, so every test space is swept whether or not the
%test that used it reached its own undeclare. The install flag and wrapper
%come off QUALIFIED, the spaces.plt lesson: a database operation resolves
%in this unit's module where a call follows the inheritance chain.
cleanup_hooks :-
    forall(member(S, ['&hplt-pool', '&hplt-two', '&hplt-open', '&hplt-bad',
                      '&hplt-batch', '&hplt-post', '&hplt-both']),
           ( metta_undeclare_hook(pre_add, S),
             metta_undeclare_hook(post_add, S),
             clear_native_atoms(S) )),
    retractall(hplt_observed(_, _)),
    petta_engine_module(Engine),
    (   unwrap_predicate(Engine:metta_add_atom/3, petta_space_hook_guard)
    ->  true
    ;   true
    ),
    retractall(Engine:petta_space_hooks_installed).

setup_hooks :-
    ensure_hook_guards,
    cleanup_hooks.

:- begin_tests(space_hooks).

% P12.1: the refusal reaches the caller carrying the handler's OWN words,
% the SpaceProvider.refusal pattern at the hook layer.
test(a_pre_add_hook_can_refuse_with_its_own_words,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    catch('add-atom'('&hplt-pool', [secret, 1], _), error(Ball, _), true),
    assertion(Ball == petta_add_refused('&hplt-pool', [secret, 1],
                                        "no secrets in this pool")),
    findall(A, 'get-atoms'('&hplt-pool', A), Atoms),
    assertion(Atoms == []).

% P12.6: one claimant per name, checked when the claim is made, never
% raced at call time; the refusal names BOTH claimants.
test(a_second_claimant_for_one_name_is_refused_with_both_named,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-two', 'hplt-guard'),
    catch(metta_declare_hook(pre_add, '&hplt-two', 'hplt-other-guard'),
          error(Ball, _), true),
    assertion(Ball == petta_hook_conflict('&hplt-two', 'pre-add',
                                          'hplt-guard', 'hplt-other-guard')),
    % the rolled-back claim left the standing one in force
    catch('add-atom'('&hplt-two', [secret, 2], _), error(Still, _), true),
    assertion(Still = petta_add_refused(_, _, _)).

% P12.7: a claimed handler whose equations do not cover the atom is a
% stuck state that says so, naming the space, the slot, the handler and
% the atom, rather than silently admitting or silently dropping.
test(an_unclaimed_request_is_a_stuck_state_that_says_so,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    catch('add-atom'('&hplt-pool', [uncovered, 9], _), error(Ball, _), true),
    assertion(Ball == petta_hook_stuck('&hplt-pool', 'pre-add',
                                       'hplt-guard', [uncovered, 9])),
    findall(A, 'get-atoms'('&hplt-pool', A), Atoms),
    assertion(Atoms == []).

% The transform verdict: the handler's output is the granted form and is
% not re-asked, so (raw 7) lands as (cooked 7) although the handler's own
% equations do not cover (cooked 7).
test(a_transforming_hook_grants_its_output_without_being_reasked,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    'add-atom'('&hplt-pool', [raw, 7], _),
    findall(A, 'get-atoms'('&hplt-pool', A), Atoms),
    assertion(Atoms == [[cooked, 7]]).

% The drop verdict: the write is skipped and the caller sees the success
% an accepted add answers, which set semantics needs.
test(a_drop_verdict_skips_the_write_and_the_caller_sees_success,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    'add-atom'('&hplt-pool', [dup, 3], Result),
    assertion(Result == []),
    findall(A, 'get-atoms'('&hplt-pool', A), Atoms),
    assertion(Atoms == []).

test(an_accepting_hook_lands_the_atom_as_offered,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    'add-atom'('&hplt-pool', [plain, 4], _),
    findall(A, 'get-atoms'('&hplt-pool', A), Atoms),
    assertion(Atoms == [[plain, 4]]).

% With the wrapper installed, a space nobody claimed keeps the direct
% path: the miss is one indexed lookup, not a policy.
test(a_hook_on_one_space_leaves_other_spaces_direct,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    'add-atom'('&hplt-open', [uncovered, 11], _),
    findall(A, 'get-atoms'('&hplt-open', A), Atoms),
    assertion(Atoms == [[uncovered, 11]]).

test(redeclaring_the_same_handler_is_idempotent,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    findall(H, 'get-atoms'('&petta', ['pre-add', '&hplt-pool', H]), Hs),
    assertion(Hs == ['hplt-guard']).

test(undeclaring_frees_the_claim_for_a_new_claimant,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    metta_undeclare_hook(pre_add, '&hplt-pool'),
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-other-guard'),
    'add-atom'('&hplt-pool', [plain, 5], _),
    findall(A, 'get-atoms'('&hplt-pool', A), Atoms),
    assertion(Atoms == [[plain, 5]]).

% A handler answering outside the verdict algebra is a named defect, not
% a silent admission and not a stuck state: the error says what came
% back and lists the four verdicts.
test(a_non_verdict_answer_is_a_named_defect,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-bad', 'hplt-wrong'),
    catch('add-atom'('&hplt-bad', [x], _), error(Ball, _), true),
    assertion(Ball == petta_hook_bad_verdict('&hplt-bad', 'hplt-wrong',
                                             [x], 42)).

% The bulk door degrades to per-atom adds for a claimed space, so the
% handler decides every atom of a batch: the transform applies to each
% and the refusal stops the batch exactly where lone adds would stop.
test(a_batch_into_a_hooked_space_consults_the_handler_per_atom,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-batch', 'hplt-guard'),
    metta_add_atoms('&hplt-batch', [[raw, 1], [dup, 2], [plain, 3]]),
    findall(A, 'get-atoms'('&hplt-batch', A), Atoms),
    assertion(Atoms == [[cooked, 1], [plain, 3]]).

% The claim's contract atom mirrors into &petta, so reflection reads the
% hook the way it reads admits and capacity.
test(the_claim_is_readable_as_a_contract_atom,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-pool', 'hplt-guard'),
    findall(H, 'get-atoms'('&petta', ['pre-add', '&hplt-pool', H]), Hs),
    assertion(Hs == ['hplt-guard']),
    metta_undeclare_hook(pre_add, '&hplt-pool'),
    findall(H2, 'get-atoms'('&petta', ['pre-add', '&hplt-pool', H2]), Hs2),
    assertion(Hs2 == []).

% The MeTTa surface: declaring from source and refusing from source are
% the same mechanism the engine door drives.
test(the_metta_surface_declares_and_the_refusal_reaches_the_program,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta("!(declare-pre-add! &hplt-pool hplt-guard)", Groups),
    %the unit answer is pruned, so the directive contributes one empty group
    assertion(Groups == [[]]),
    catch(metta("!(add-atom &hplt-pool (secret 8))"), error(Ball, _), true),
    assertion(Ball = petta_add_refused('&hplt-pool', _, _)).

:- end_tests(space_hooks).

%The post slot: the same verdicts read against a LANDED atom, beside the
%event pair that stays pure observation.
:- dynamic hplt_observed/2.

observe_hplt_post :-
    assertz(( metta_on_atom_added(Space, Term) :-
                  ( Space == '&hplt-post'
                  -> assertz(hplt_observed(Space, Term))
                  ; true ) )),
    enable_metta_atom_hook(added).

unobserve_hplt_post :-
    retract(( metta_on_atom_added(Space, Term) :-
                  ( Space == '&hplt-post'
                  -> assertz(hplt_observed(Space, Term))
                  ; true ) )),
    sync_metta_atom_hook(added).

:- begin_tests(space_hooks_post).

% P12.2: the post hook TRANSFORMS the landed atom while the event pair,
% observing the same write, moves nothing: the observer records the raw
% arrival and the store still ends where the hook put it, because an
% observer's answer is discarded and a hook's is a verdict.
test(a_post_add_hook_may_transform_while_the_event_pair_only_observes,
     [ setup(( setup_hooks, observe_hplt_post )),
       cleanup(( unobserve_hplt_post, cleanup_hooks )) ]) :-
    metta_declare_hook(post_add, '&hplt-post', 'hplt-guard'),
    'add-atom'('&hplt-post', [raw, 1], _),
    findall(A, 'get-atoms'('&hplt-post', A), Atoms),
    assertion(Atoms == [[cooked, 1]]),
    %the observer saw the raw form land; it could not keep it
    assertion(hplt_observed('&hplt-post', [raw, 1])).

test(a_post_refusal_undoes_the_write_before_it_reaches_the_caller,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(post_add, '&hplt-post', 'hplt-guard'),
    catch('add-atom'('&hplt-post', [secret, 2], _), error(Ball, _), true),
    assertion(Ball == petta_add_refused('&hplt-post', [secret, 2],
                                        "no secrets in this pool")),
    findall(A, 'get-atoms'('&hplt-post', A), Atoms),
    assertion(Atoms == []).

test(a_post_drop_removes_the_landed_atom_and_the_caller_sees_success,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(post_add, '&hplt-post', 'hplt-guard'),
    'add-atom'('&hplt-post', [dup, 3], Result),
    assertion(Result == []),
    findall(A, 'get-atoms'('&hplt-post', A), Atoms),
    assertion(Atoms == []).

test(a_post_stuck_state_undoes_the_write,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(post_add, '&hplt-post', 'hplt-guard'),
    catch('add-atom'('&hplt-post', [uncovered, 4], _), error(Ball, _), true),
    assertion(Ball == petta_hook_stuck('&hplt-post', 'post-add',
                                       'hplt-guard', [uncovered, 4])),
    findall(A, 'get-atoms'('&hplt-post', A), Atoms),
    assertion(Atoms == []).

% A pre transform's output is granted on BOTH slots: the post handler is
% not consulted about the pre handler's decision.
test(a_pre_transform_skips_the_post_slot_on_the_granted_form,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-both', 'hplt-guard'),
    metta_declare_hook(post_add, '&hplt-both', 'hplt-guard'),
    'add-atom'('&hplt-both', [raw, 5], _),
    findall(A, 'get-atoms'('&hplt-both', A), Atoms),
    assertion(Atoms == [[cooked, 5]]).

test(an_atom_the_pre_slot_drops_never_meets_the_post_slot,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-both', 'hplt-guard'),
    metta_declare_hook(post_add, '&hplt-both', 'hplt-guard'),
    'add-atom'('&hplt-both', [dup, 6], _),
    findall(A, 'get-atoms'('&hplt-both', A), Atoms),
    assertion(Atoms == []).

% An atom the pre slot accepts AS OFFERED still meets the post slot: the
% pre handler admits everything, the post handler revises what landed.
test(both_slots_compose_on_an_accepted_atom,
     [ setup(setup_hooks), cleanup(cleanup_hooks) ]) :-
    metta_declare_hook(pre_add, '&hplt-both', 'hplt-open'),
    metta_declare_hook(post_add, '&hplt-both', 'hplt-guard'),
    'add-atom'('&hplt-both', [raw, 7], _),
    findall(A, 'get-atoms'('&hplt-both', A), Atoms),
    assertion(Atoms == [[cooked, 7]]).

:- end_tests(space_hooks_post).


:- begin_tests(hooks_compiled_fire,
               [ setup(hooks_cf_setup), cleanup(hooks_cf_cleanup) ]).

hooks_cf_setup :-
    process_metta_string(
        "(= (cf-guard (secret $x)) (refuse \"cf says no\"))\n\
(= (cf-guard (raw $x)) (accept (cooked $x)))\n\
(= (cf-guard (plain $x)) (accept))", _).

hooks_cf_cleanup :-
    metta_undeclare_hook(pre_add, '&cf-pool'),
    forall(member(F, ['cf-guard', 'cf-typed', 'cf-flip', 'cf-marker']),
           remove_sexp('&self', [=, [F|_], _])),
    clear_native_atoms('&cf-pool'),
    remove_sexp('&self', [':', 'cf-typed', _]).

%The compiled fire is an implementation of the eval path over data-shaped
%offers, so on every such handler shape the two must answer the same
%verdicts in the same order. This is the equivalence obligation stated as
%a test: the algorithm may be anything while the answers hold.
cf_parity(Handler, Term) :-
    current_metta_module(Module),
    findall(V, eval_metta_in_module(Module, [Handler, Term], V), Direct),
    petta_hook_drop_compiled('&cf-parity', pre_add),
    findall(V,
            petta_hook_eval('&cf-parity', pre_add, Handler, Module, Term, V),
            Fired),
    petta_hook_drop_compiled('&cf-parity', pre_add),
    Fired == Direct.

test(a_compiled_fire_answers_what_the_eval_path_answers) :-
    cf_parity('cf-guard', [secret, 1]),
    cf_parity('cf-guard', [raw, 7]),
    cf_parity('cf-guard', [plain, 2]).

test(a_compiled_fire_fails_where_the_eval_path_is_stuck) :-
    current_metta_module(Module),
    \+ eval_metta_in_module(Module, ['cf-guard', [uncovered, 3]], _),
    petta_hook_drop_compiled('&cf-parity', pre_add),
    \+ petta_hook_eval('&cf-parity', pre_add, 'cf-guard', Module,
                       [uncovered, 3], _),
    petta_hook_drop_compiled('&cf-parity', pre_add).

test(an_equation_added_after_the_claim_decides_the_next_fire) :-
    process_metta_string("(= (cf-flip $a) (accept))", _),
    metta_declare_hook(pre_add, '&cf-pool', 'cf-flip'),
    metta_add_atom('&cf-pool', [flip, 1], _),
    %The redefinition goes through the ordinary equation door, whose
    %change hook drops every compiled fire clause; the next add must see
    %the new program, not the baked one.
    metta_remove_atom('&self', [=, ['cf-flip', _], _], _),
    process_metta_string(
        "(= (cf-flip $a) (refuse \"the new program refuses\"))", _),
    catch(metta_add_atom('&cf-pool', [flip, 2], _), Ball, true),
    nonvar(Ball),
    Ball = error(petta_add_refused('&cf-pool', [flip, 2], _), _),
    metta_undeclare_hook(pre_add, '&cf-pool').

%The offer is DATA. A stored atom whose head happens to name a function
%must reach the handler as itself: the verdict is about what lands in the
%space, and what lands is the atom, not its evaluation. The eval-per-fire
%door got this wrong by construction, judging `evaluated` while the space
%was offered (cf-marker); a BEFORE trigger sees the row, and a CHR head
%matches the constraint, never something derived from it.
test(the_offered_atom_reaches_the_handler_as_itself) :-
    process_metta_string(
        "(= (cf-marker) evaluated)\n\
(= (cf-typed $a) (accept (saw $a)))", _),
    metta_declare_hook(pre_add, '&cf-pool', 'cf-typed'),
    metta_add_atom('&cf-pool', ['cf-marker'], _),
    (   'get-atoms'('&cf-pool', [saw, ['cf-marker']])
    ->  true
    ;   throw(cf_expected_the_offer_itself)
    ),
    %A later type declaration recompiles the fire through the change
    %hooks; the offer stays data on the other side of it.
    process_metta_string("(: cf-typed (-> Atom %Undefined%))", _),
    metta_add_atom('&cf-pool', ['cf-marker'], _),
    findall(X, 'get-atoms'('&cf-pool', [saw, X]), Seen),
    Seen == [['cf-marker'], ['cf-marker']],
    metta_undeclare_hook(pre_add, '&cf-pool').

:- end_tests(hooks_compiled_fire).

% ai-p12-design.md P12.4's acceptance: admits and capacity are sugar over
% the general hook. The claim is an ordinary petta_hook_claim row visible
% through the same registry and &petta contract atom as any user handler,
% the judge is the prelude's space-admission-verdict equations, and the
% bespoke wrapper family (petta_install_admission/0, petta_admission_check/2,
% petta_admission_idle/1) is gone from the engine.
:- begin_tests(hooks_admission_sugar).

sugar_teardown(Pool) :-
    metta_undeclare_hook(pre_add, Pool),
    atom_concat('space-admission-guard-', Pool, Guard),
    findall(T, 'get-atoms'('&petta', [admits, Pool, T]), Admits),
    forall(member(T, Admits),
           ( metta_remove_atom('&petta', [admits, Pool, T], _) -> true ; true )),
    findall(N, 'get-atoms'('&petta', [capacity, Pool, N]), Caps),
    forall(member(N, Caps),
           ( metta_remove_atom('&petta', [capacity, Pool, N], _) -> true ; true )),
    (   metta_remove_atom('&self', [=, [Guard, _], _], _) -> true ; true ),
    clear_native_atoms(Pool).

test(test_capacity_and_admits_are_sugar_over_the_general_hook_or_are_gone,
     [ cleanup(sugar_teardown('&as-pool1')) ]) :-
    metta_add_atom('&petta', [admits, '&as-pool1', 'AsWidget'], _),
    petta_admission_claim('&as-pool1', '&self'),
    assertion(petta_hook_claim('&as-pool1', pre_add,
                               'space-admission-guard-&as-pool1', _)),
    assertion(\+ \+ 'get-atoms'('&petta',
                                ['pre-add', '&as-pool1',
                                 'space-admission-guard-&as-pool1'])),
    assertion(\+ current_predicate(petta_install_admission/0)),
    assertion(\+ current_predicate(petta_admission_check/2)),
    assertion(\+ current_predicate(petta_admission_idle/1)).

% One claimant per (space, slot), both directions: the sugar refuses to
% pave over a standing user claim, and a user claim refuses to pave over
% the sugar's. Undeclaring first is the documented way through.
test(a_standing_user_claim_makes_the_sugar_conflict_loudly,
     [ cleanup(( metta_undeclare_hook(pre_add, '&as-mine'),
                 (   metta_remove_atom('&self', [=, ['as-my-guard', _], _], _)
                 ->  true
                 ;   true
                 ) )),
       throws(error(petta_hook_conflict('&as-mine', 'pre-add', 'as-my-guard',
                                        'space-admission-guard-&as-mine'),
                    _)) ]) :-
    process_metta_string("(= (as-my-guard $x) (accept))", _),
    metta_declare_hook(pre_add, '&as-mine', 'as-my-guard'),
    petta_admission_claim('&as-mine', '&self').

test(the_sugar_claim_makes_a_user_claim_conflict_loudly,
     [ cleanup(( sugar_teardown('&as-pool2'),
                 (   metta_remove_atom('&self', [=, ['as-late-guard', _], _], _)
                 ->  true
                 ;   true
                 ) )),
       throws(error(petta_hook_conflict('&as-pool2', 'pre-add',
                                        'space-admission-guard-&as-pool2',
                                        'as-late-guard'), _)) ]) :-
    petta_admission_claim('&as-pool2', '&self'),
    process_metta_string("(= (as-late-guard $x) (accept))", _),
    metta_declare_hook(pre_add, '&as-pool2', 'as-late-guard').

% The guard equation lands in the DECLARING space, not &self: admission
% declared from a named space keeps its machinery out of the base, and the
% fire still reaches the prelude's judge through the module chain.
test(the_guard_equation_lives_in_the_declaring_space,
     [ cleanup(( metta_undeclare_hook(pre_add, '&as-pool3'),
                 (   metta_remove_atom('&petta',
                                       [admits, '&as-pool3', 'AsWidget'], _)
                 ->  true
                 ;   true
                 ),
                 clear_native_atoms('&as-decl'),
                 clear_native_atoms('&as-pool3') )) ]) :-
    metta_add_atom('&petta', [admits, '&as-pool3', 'AsWidget'], _),
    petta_admission_claim('&as-pool3', '&as-decl'),
    assertion(\+ 'get-atoms'('&self',
                             [=, ['space-admission-guard-&as-pool3', _], _])),
    assertion(\+ \+ 'get-atoms'('&as-decl',
                                [=, ['space-admission-guard-&as-pool3', _],
                                 _])),
    catch(metta_add_atom('&as-pool3', ['as-x'], _), E, true),
    assertion(subsumes_term(error(petta_add_refused('&as-pool3', ['as-x'],
                                                    ['does-not-carry',
                                                     'AsWidget']),
                                  _),
                            E)).

test(a_typed_atom_enters_and_the_pool_bounds,
     [ cleanup(( sugar_teardown('&as-pool4'),
                 (   metta_remove_atom('&self', [:, 'as-w1', 'AsW'], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, 'as-w2', 'AsW'], _)
                 ->  true
                 ;   true
                 ) )) ]) :-
    metta_add_atom('&petta', [admits, '&as-pool4', 'AsW'], _),
    metta_add_atom('&petta', [capacity, '&as-pool4', 1], _),
    metta_add_atom('&self', [:, 'as-w1', 'AsW'], _),
    metta_add_atom('&self', [:, 'as-w2', 'AsW'], _),
    petta_admission_claim('&as-pool4', '&self'),
    metta_add_atom('&as-pool4', 'as-w1', _),
    catch(metta_add_atom('&as-pool4', 'as-w2', _), E, true),
    assertion(subsumes_term(error(petta_add_refused('&as-pool4', 'as-w2',
                                                    ['pool-at-capacity', 1]),
                                  _),
                            E)),
    findall(A, 'get-atoms'('&as-pool4', A), Atoms),
    assertion(Atoms == ['as-w1']).

% The pool judges the offered atom AS ITSELF: (as-live) has an equation
% reducing it to as-dead, which carries no type, so acceptance here is
% only possible if the judge never reduced the offer.
test(the_sugar_judges_the_offered_atom_as_itself,
     [ cleanup(( sugar_teardown('&as-pool5'),
                 (   metta_remove_atom('&self', [=, ['as-live'], 'as-dead'],
                                       _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, ['as-live'], 'AsLiveW'],
                                       _)
                 ->  true
                 ;   true
                 ) )) ]) :-
    process_metta_string("(= (as-live) as-dead)\n(: (as-live) AsLiveW)", _),
    metta_add_atom('&petta', [admits, '&as-pool5', 'AsLiveW'], _),
    petta_admission_claim('&as-pool5', '&self'),
    metta_add_atom('&as-pool5', ['as-live'], _),
    findall(A, 'get-atoms'('&as-pool5', A), Atoms),
    assertion(Atoms == [['as-live']]).

% Idempotent per pool, including across an undeclare: one registry row,
% one guard equation, and a pool with no contract atoms accepts freely.
test(reclaiming_is_idempotent,
     [ cleanup(sugar_teardown('&as-pool6')) ]) :-
    petta_admission_claim('&as-pool6', '&self'),
    petta_admission_claim('&as-pool6', '&self'),
    findall(H, petta_hook_claim('&as-pool6', pre_add, H, _), Hs),
    assertion(Hs == ['space-admission-guard-&as-pool6']),
    findall(x, 'get-atoms'('&self',
                           [=, ['space-admission-guard-&as-pool6', _], _]),
            Ones),
    assertion(Ones == [x]),
    metta_undeclare_hook(pre_add, '&as-pool6'),
    petta_admission_claim('&as-pool6', '&self'),
    findall(x, 'get-atoms'('&self',
                           [=, ['space-admission-guard-&as-pool6', _], _]),
            Again),
    assertion(Again == [x]),
    metta_add_atom('&as-pool6', ['as-free'], _),
    assertion(\+ \+ 'get-atoms'('&as-pool6', ['as-free'])).

:- end_tests(hooks_admission_sugar).

% The design board's worked instances (P12.5, P12.8, P12.9, P12.10):
% the mechanism demonstrated as the board names them, no new machinery.
% The CHR mapping is the project's own mechanized analysis frame
% (LeaTTa's ChrOperational cluster), and the three forms are the
% completeness checklist for the verdict vocabulary.
:- begin_tests(hooks_worked_instances).

test(test_the_hook_vocabulary_matches_the_three_chr_forms,
     [ cleanup(( metta_undeclare_hook(post_add, '&chr-obs'),
                 metta_undeclare_hook(pre_add, '&chr-simp'),
                 metta_undeclare_hook(pre_add, '&chr-keep'),
                 clear_native_atoms('&chr-obs'),
                 clear_native_atoms('&chr-derived'),
                 clear_native_atoms('&chr-simp'),
                 clear_native_atoms('&chr-keep'),
                 (   metta_remove_atom('&self', [=, ['chr-prop', _], _], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [=, ['chr-simp-rule', _], _],
                                       _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [=, ['chr-keep-rule', _], _],
                                       _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, 'chr-keep-rule', _], _)
                 ->  true
                 ;   true
                 ) )) ]) :-
    % ==> propagation: a post-add handler's body writes a derived atom
    % while the landed atom stays as it landed.
    process_metta_string(
        "(= (chr-prop $x) (chain (add-atom &chr-derived (saw $x)) $t (accept)))",
        _),
    metta_declare_hook(post_add, '&chr-obs', 'chr-prop'),
    metta_add_atom('&chr-obs', [ev, 1], _),
    assertion(\+ \+ 'get-atoms'('&chr-obs', [ev, 1])),
    assertion(\+ \+ 'get-atoms'('&chr-derived', [saw, [ev, 1]])),
    % <=> simplification: the transform verdict consumes the incoming
    % atom and produces its replacement, linear consumption stated as a
    % verdict.
    process_metta_string("(= (chr-simp-rule (raw $x)) (accept (cooked $x)))",
                         _),
    metta_declare_hook(pre_add, '&chr-simp', 'chr-simp-rule'),
    metta_add_atom('&chr-simp', [raw, 7], _),
    assertion(\+ 'get-atoms'('&chr-simp', [raw, 7])),
    assertion(\+ \+ 'get-atoms'('&chr-simp', [cooked, 7])),
    % kept \ consumed simpagation: a pre-add handler reads the space's
    % kept heads to decide about the consumed incoming atom.
    process_metta_string("(: chr-keep-rule (-> Atom %Undefined%))\n\c
(= (chr-keep-rule $a)\n\c
   (if (space-contains &chr-keep (blocker))\n\c
       (refuse (kept-head-blocks $a))\n\c
       (accept)))", _),
    metta_declare_hook(pre_add, '&chr-keep', 'chr-keep-rule'),
    metta_add_atom('&chr-keep', [free, 1], _),
    assertion(\+ \+ 'get-atoms'('&chr-keep', [free, 1])),
    metta_add_atom('&chr-keep', ['blocker'], _),
    catch(metta_add_atom('&chr-keep', [free, 2], _), E, true),
    assertion(subsumes_term(error(petta_add_refused('&chr-keep', [free, 2],
                                                    ['kept-head-blocks',
                                                     [free, 2]]),
                                  _),
                            E)).

% Set semantics is a rule the space DECLARES, not a property it has:
% CHR's foo \ foo <=> true, the (drop) verdict's reason for existing.
% The presence probe rides the store's own clause indexing, so the rule
% costs the same however large the set grows [measured 2026-08-21:
% 57.01 inferences per add at 2,000 held atoms and 57.00 at 10,000
% through space-contains, 69.01 and 69.00 through the
% collapse-over-match spelling of the same question, against 27.01 for
% a plain add; a replayed duplicate drops at 46.00].
test(test_set_semantics_is_a_declared_rule_not_a_property_of_the_space,
     [ cleanup(( metta_undeclare_hook(pre_add, '&set-pool'),
                 clear_native_atoms('&set-pool'),
                 (   metta_remove_atom('&self', [=, ['set-rule', _], _], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, 'set-rule', _], _)
                 ->  true
                 ;   true
                 ) )) ]) :-
    process_metta_string("(: set-rule (-> Atom %Undefined%))\n\c
(= (set-rule $a)\n\c
   (if (space-contains &set-pool $a) (drop) (accept)))", _),
    metta_declare_hook(pre_add, '&set-pool', 'set-rule'),
    metta_add_atom('&set-pool', [item, 1], _),
    metta_add_atom('&set-pool', [item, 1], _),
    metta_add_atom('&set-pool', [item, 2], _),
    findall(A, 'get-atoms'('&set-pool', A), Atoms),
    assertion(Atoms == [[item, 1], [item, 2]]),
    % A declared rule, not a property: undeclare it and the space is the
    % multiset it always was.
    metta_undeclare_hook(pre_add, '&set-pool'),
    metta_add_atom('&set-pool', [item, 1], _),
    findall(A, 'get-atoms'('&set-pool', A), After),
    assertion(After == [[item, 1], [item, 2], [item, 1]]).

% A threadpool is a space of spaces: membership typed by the ontology,
% the bound the capacity sugar pointed at the pool, and the enforcement
% visible in the registry as an ordinary pre-add claim.
test(test_a_threadpool_is_a_space_of_spaces_with_its_bound_as_a_hook,
     [ cleanup(( metta_undeclare_hook(pre_add, '&tp-pool'),
                 (   metta_remove_atom('&petta',
                                       [admits, '&tp-pool', 'Space'], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&petta',
                                       [capacity, '&tp-pool', 2], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self',
                                       [=, ['space-admission-guard-&tp-pool',
                                            _], _], _)
                 ->  true
                 ;   true
                 ),
                 clear_native_atoms('&tp-pool'),
                 (   metta_remove_atom('&self', [:, '&tp-w1', 'Space'], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, '&tp-w2', 'Space'], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, '&tp-w3', 'Space'], _)
                 ->  true
                 ;   true
                 ) )) ]) :-
    metta_add_atom('&petta', [admits, '&tp-pool', 'Space'], _),
    metta_add_atom('&petta', [capacity, '&tp-pool', 2], _),
    metta_add_atom('&self', [:, '&tp-w1', 'Space'], _),
    metta_add_atom('&self', [:, '&tp-w2', 'Space'], _),
    metta_add_atom('&self', [:, '&tp-w3', 'Space'], _),
    petta_admission_claim('&tp-pool', '&self'),
    assertion(petta_hook_claim('&tp-pool', pre_add, _, _)),
    metta_add_atom('&tp-pool', '&tp-w1', _),
    metta_add_atom('&tp-pool', '&tp-w2', _),
    catch(metta_add_atom('&tp-pool', '&tp-w3', _), E, true),
    assertion(subsumes_term(error(petta_add_refused('&tp-pool', '&tp-w3',
                                                    ['pool-at-capacity', 2]),
                                  _),
                            E)),
    findall(S, 'get-atoms'('&tp-pool', S), Members),
    assertion(Members == ['&tp-w1', '&tp-w2']).

% The threadpool bound stated as ONE simpagation rule: the pool's
% members are the kept heads, the incoming member the consumed one, and
% the whole bound is a single handler equation whose refusal wears the
% same words the shipped judge answers with.
test(test_the_threadpool_bound_is_one_simpagation_rule,
     [ cleanup(( metta_undeclare_hook(pre_add, '&tp2-pool'),
                 clear_native_atoms('&tp2-pool'),
                 (   metta_remove_atom('&self', [=, ['tp-bound', _], _], _)
                 ->  true
                 ;   true
                 ),
                 (   metta_remove_atom('&self', [:, 'tp-bound', _], _)
                 ->  true
                 ;   true
                 ) )) ]) :-
    process_metta_string("(: tp-bound (-> Atom %Undefined%))\n\c
(= (tp-bound $s)\n\c
   (if (< (space-atom-count &tp2-pool) 2)\n\c
       (accept)\n\c
       (refuse (pool-at-capacity 2))))", _),
    metta_declare_hook(pre_add, '&tp2-pool', 'tp-bound'),
    metta_add_atom('&tp2-pool', '&tp2-w1', _),
    metta_add_atom('&tp2-pool', '&tp2-w2', _),
    catch(metta_add_atom('&tp2-pool', '&tp2-w3', _), E, true),
    assertion(subsumes_term(error(petta_add_refused('&tp2-pool', '&tp2-w3',
                                                    ['pool-at-capacity', 2]),
                                  _),
                            E)),
    findall(S, 'get-atoms'('&tp2-pool', S), Members),
    assertion(Members == ['&tp2-w1', '&tp2-w2']).

:- end_tests(hooks_worked_instances).
