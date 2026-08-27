% Purpose: PlUnit coverage for the branch-local evaluation fuel, and for the
%   two SWI global-variable behaviours its single-global design depends on.
% Assumes: engine/metta.pl is loaded, so metta_run_with_fuel/3,
%   metta_open_fuel_scope/0, metta_close_fuel_scope/0 and
%   metta_fuel_step_goal/3 are reachable; `$metta_fuel_remaining` is the one
%   global they share. The charge is BUILT by metta_fuel_step_goal/3 and
%   written into each compiled clause, so these tests call the built goal,
%   which is the thing the engine actually runs.
% Guarantees:
%   - a step charges inside a scope and is inert outside one, an exhausted
%     branch records its culprit and fails, and the limit is read from
%     max-stack-depth on the first step rather than at scope open [tested:
%     fuel:a_step_charges_inside_a_scope_and_is_inert_outside_one;
%     commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f].
%   - nb_delete/1 and an `off` sentinel both survive backtracking past a
%     trailed b_setval/2 write, which is what lets the balance be its own scope
%     marker [tested: fuel:a_deleted_global_is_not_resurrected_by_backtracking;
%     commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f].
% Fails when: read as coverage of max-stack-depth's user-facing law. That is
%   test_a_stack_depth_pragma_bounds_evaluation_instead_of_overflowing and the
%   arbiter's own boundary witnesses; this file covers the mechanism under it.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(fuel).

% ---------------------------------------------------------------- the mechanism

test(a_step_charges_inside_a_scope_and_is_inert_outside_one) :-
    metta_open_fuel_scope,
    nb_setval('$metta_fuel_remaining', 1000),
    charge(probe, 7),
    b_getval('$metta_fuel_remaining', Inside),
    metta_close_fuel_scope,
    b_getval('$metta_fuel_remaining', Closed),
    charge(probe, 7),
    b_getval('$metta_fuel_remaining', Outside),
    assertion(Inside == 993),
    assertion(Closed == off),
    assertion(Outside == off).

test(a_step_spends_from_the_balance_it_inherited_on_a_sibling_branch) :-
    metta_open_fuel_scope,
    nb_setval('$metta_fuel_remaining', 1000),
    %A branch that spends and then fails leaves the balance it started with,
    %which is the whole reason the write is backtrackable.
    (   charge(first, 100), fail
    ;   true
    ),
    b_getval('$metta_fuel_remaining', Restored),
    metta_close_fuel_scope,
    assertion(Restored == 1000).

test(an_exhausted_branch_records_its_culprit_and_fails) :-
    metta_open_fuel_scope,
    nb_setval('$metta_fuel_remaining', 10),
    (   charge(the_culprit, 9)
    ->  Charged = true
    ;   Charged = false
    ),
    nb_getval('$metta_fuel_errors', Recorded),
    metta_close_fuel_scope,
    assertion(Charged == false),
    assertion(Recorded == [the_culprit]).

test(the_limit_is_read_on_the_first_step_rather_than_at_scope_open) :-
    setup_call_cleanup(
        true,
        (   metta_open_fuel_scope,
            b_getval('$metta_fuel_remaining', AtOpen),
            'pragma!'('max-stack-depth', 500, _),
            charge(probe, 1),
            b_getval('$metta_fuel_remaining', AfterStep),
            metta_close_fuel_scope
        ),
        'pragma!'('max-stack-depth', none, _)),
    %`unstarted` at open is what lets a with-pragma! INSIDE the runnable set the
    %bound the runnable is then measured against.
    assertion(AtOpen == unstarted),
    assertion(AfterStep == 499).

%The scope belongs to the RUNNABLE, not to one answer: it stays open while the
%form can still produce answers, which is what lets the recorded overflow
%branches be replayed after the ordinary ones, and it closes when the caller
%stops asking. So an inner run inside it spends the outer balance, and only the
%cut puts the marker back to `off`.
test(a_nested_run_reuses_the_scope_the_outer_one_opened) :-
    once(metta_run_with_fuel(outer, Answer,
                             ( b_getval('$metta_fuel_remaining', Open),
                               nb_setval('$metta_plt_seen', Open),
                               metta_run_with_fuel(inner, _, true) ))),
    nb_getval('$metta_plt_seen', Seen),
    nb_delete('$metta_plt_seen'),
    b_getval('$metta_fuel_remaining', Afterwards),
    assertion(Answer == outer),
    assertion(Seen == unstarted),
    assertion(Afterwards == off).

% ------------------------------------------------- the SWI behaviour underneath

% The balance doubles as the scope marker, so a value restored by backtracking
% into an already-closed scope would silently reopen one. Neither closing form
% does that: the manual says a b_setval/2 that CREATED a variable has its
% creation undone on backtracking, and nothing says a later delete is undone
% [source: SWI-Prolog 10.1 Reference Manual section 4.33, b_setval/2].

test(a_deleted_global_is_not_resurrected_by_backtracking) :-
    (   plt_fuel_scope(nb_delete('$metta_plt_probe')),
        fail
    ;   true
    ),
    assertion(\+ nb_current('$metta_plt_probe', _)).

test(an_off_sentinel_is_not_restored_over_by_backtracking) :-
    (   plt_fuel_scope(nb_setval('$metta_plt_probe', off)),
        fail
    ;   true
    ),
    nb_getval('$metta_plt_probe', Value),
    nb_delete('$metta_plt_probe'),
    assertion(Value == off).

:- end_tests(fuel).

%A scope whose body writes the backtrackable balance three times and then
%closes, with the caller free to backtrack through every one of those writes
%after the close has run.
%The charge exactly as a compiled clause carries it.
charge(Culprit, Cost) :-
    metta_fuel_step_goal(Culprit, Cost, Goal),
    call(Goal).

plt_fuel_scope(Close) :-
    setup_call_cleanup(nb_setval('$metta_plt_probe', 100),
                       ( member(N, [1, 2, 3]),
                         b_setval('$metta_plt_probe', N) ),
                       Close).
