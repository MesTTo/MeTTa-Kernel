% Purpose: PlUnit coverage for the space-hook mechanism in src/metta.pl:
%   (declare-pre-add! <space> <handler>), the one-claimant rule, the
%   four-verdict algebra (accept, accept-transformed, refuse, drop), the
%   stuck state, and the batch door's degrade to per-atom adds.
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
                      '&hplt-batch']),
           ( metta_undeclare_hook(pre_add, S),
             clear_native_atoms(S) )),
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
