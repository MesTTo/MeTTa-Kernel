% Purpose: pin the two SWI facts a cumulative cursor budget rests on, and the
%   behaviour metta_host_inference_budget/3 derives from them.
% Assumes:
%   - an SWI engine has its own inference counter, separate from the counter
%     the thread that created it reads through statistics/2.
%   - call_with_inference_limit/3 bounds inferences PER SOLUTION of its goal,
%     which is what SWI's manual says, so it is re-armed at every answer.
% Guarantees:
%   - a budget spans resumes and stops the cursor on the answer that passes it
%     [tested: a_budget_is_cumulative_across_resumes]
%   - a budget also stops a resume that never yields an answer, which a check
%     placed after a solution cannot see [tested:
%     a_budget_stops_a_resume_that_never_yields]
%   - the same wrapper charges a goal driven on the calling thread for that
%     goal alone, though that thread's counter started long before it [tested:
%     a_budget_charges_a_host_thread_goal_for_its_own_work]
%   - a non-positive budget installs no wrapper, so an unbounded cursor runs
%     the goal it was given [tested: a_non_positive_budget_installs_no_wrapper]
%   - the cumulative check costs three inferences per answer plus one for the
%     base read, the same at every answer cost [tested:
%     the_cumulative_check_costs_three_inferences_per_answer]
%   - one of those three is bought by the direction the comparison is written
%     [tested: an_if_then_else_costs_more_on_the_branch_its_condition_fails_to]
% Fails when:
%   - run from anywhere but tests/prolog; the engine is loaded by relative path.
% Owns resources:
%   - one engine per bounded case, destroyed on every exit path including the
%     one the budget's own exception takes.
%
% These facts are measured nowhere else in the tree, and getting them backwards
% is what left the budget inert in two bindings at once: both metered from
% outside the engine, where the counter cannot see the work. A future author
% who moves the meter back outside, or who drops the per-solution limiter as
% redundant, fails here rather than in a host binding's timing.

:- ensure_loaded('../../../../engine/metta.pl').

% About 402 inferences per answer, so a budget buys a countable number of them.
budget_burn(0) :- !.
budget_burn(N) :- N > 0, N1 is N - 1, budget_burn(N1).

% Endless.
budget_gen(N, N).
budget_gen(N, X) :- budget_burn(200), N1 is N + 1, budget_gen(N1, X).

% Fifty-one answers and then done, so "drains" is a number rather than a mood.
budget_upto(N, Max, N) :- N =< Max.
budget_upto(N, Max, X) :-
    N < Max, budget_burn(200), N1 is N + 1, budget_upto(N1, Max, X).

% A generator whose per-answer cost is a PARAMETER, so "the metering charge is
% the same whatever an answer costs" is measured rather than asserted.
budget_cost(_, N, Max, N) :- N =< Max.
budget_cost(K, N, Max, X) :-
    N < Max, budget_burn(K), N1 is N + 1, budget_cost(K, N1, Max, X).

% Drain a finite goal on the calling thread and report what it spent. No
% engine here: the charge is a property of the wrapper, not of engines, and a
% thread-level counter reads it directly when the goal is driven by findall/3.
budget_drain(Goal, Answers, Spent) :-
    statistics(inferences, Before),
    findall(x, Goal, Rows),
    statistics(inferences, After),
    length(Rows, Answers),
    Spent is After - Before.

% What the cumulative check costs per answer, over the per-solution limiter
% alone, so the limiter's own cost is not counted against the wrapper.
budget_charge(K, Max, Charge) :-
    Bare = call_with_inference_limit(budget_cost(K, 0, Max, _), 1000000000, _),
    budget_drain(Bare, Answers, Unguarded),
    metta_host_inference_budget(budget_cost(K, 0, Max, _), 1000000000, Guarded),
    budget_drain(Guarded, Answers, Metered),
    Delta is Metered - Unguarded,
    % AFFINE, not proportional: the wrapper reads the counter once at goal
    % start to take its base, and then once per answer. Solving for the slope
    % is what makes this a per-answer constant rather than an average, and the
    % equation is asserted rather than divided so a charge that is not a fixed
    % constant fails here instead of rounding into one.
    Charge is (Delta - 1) // Answers,
    Delta =:= Charge * Answers + 1.

% Twelve cheap answers, then a resume that never yields one. Only a bound that
% acts INSIDE a solution can stop the thirteenth.
budget_cliff(N, N) :- N < 12.
budget_cliff(N, X) :-
    N < 12, budget_burn(200), N1 is N + 1, budget_cliff(N1, X).
budget_cliff(N, _) :- N >= 12, budget_burn(100000000), fail.

% Drive a bounded goal in an engine and report how many answers arrived before
% it ended and how it ended. The count lives in a non-backtrackable global
% because the budget's exception unwinds past any variable holding it.
budget_engine_rows(Goal, Budget, Ceiling, Rows, Outcome) :-
    metta_host_inference_budget(Goal, Budget, Bounded),
    engine_create(answer, Bounded, Engine),
    nb_setval(budget_rows, 0),
    catch(( budget_pull(Engine, Ceiling), Outcome = drained ),
          error(metta_control_signal(inference_limit, _), _),
          Outcome = stopped),
    catch(engine_destroy(Engine), _, true),
    nb_getval(budget_rows, Rows).

budget_pull(Engine, Ceiling) :-
    nb_getval(budget_rows, Rows),
    (   Rows >= Ceiling
    ->  true
    ;   engine_next(Engine, _)
    ->  Rows1 is Rows + 1,
        nb_setval(budget_rows, Rows1),
        budget_pull(Engine, Ceiling)
    ;   true
    ).

:- begin_tests(inference_budget).

% The fact every candidate design turns on. Nothing else in the tree records
% it, and both host bindings were written as though the opposite were true.
test(an_engine_counts_its_own_work_and_the_creating_thread_does_not) :-
    engine_create(Spent, (budget_gen(0, _), statistics(inferences, Spent)),
                  Engine),
    engine_next(Engine, First),
    statistics(inferences, HostBefore),
    forall(between(2, 200, _), engine_next(Engine, _)),
    engine_next(Engine, Last),
    statistics(inferences, HostAfter),
    engine_destroy(Engine),
    EngineGrew is Last - First,
    HostGrew is HostAfter - HostBefore,
    % 200 answers at about 402 inferences each is over 80,000; the host sees
    % about two per pull. The margins are an order of magnitude either side.
    EngineGrew > 40000,
    HostGrew * 10 < EngineGrew.

% SWI's own contract, stated as a test because the whole defect was reading it
% the other way: the limiter is re-armed at every answer, so a generator that
% answers cheaply forever never reaches it.
test(the_bare_limiter_does_not_bound_a_generator) :-
    engine_create(answer,
                  call_with_inference_limit(budget_gen(0, _), 5000, _),
                  Engine),
    forall(between(1, 400, _), engine_next(Engine, _)),
    engine_destroy(Engine).

test(a_budget_is_cumulative_across_resumes) :-
    budget_engine_rows(budget_gen(0, _), 20000, 5000, Rows, Outcome),
    Outcome == stopped,
    Rows > 5,
    Rows < 500,
    % Five times the budget buys several times the answers. A meter that
    % charges a fixed amount per pull instead of metering the engine would
    % reach the ceiling under both.
    budget_engine_rows(budget_gen(0, _), 100000, 5000, More, stopped),
    More > Rows * 3.

% A check that runs after each answer never runs at all here.
test(a_budget_stops_a_resume_that_never_yields) :-
    % The wall bound is a BACKSTOP: without the per-solution limiter this case
    % does not return, and a gate should learn that as a failure rather than
    % as a hang.
    catch(call_with_time_limit(
              20, budget_engine_rows(budget_cliff(0, _), 5000, 5000, Rows,
                                     Outcome)),
          time_limit_exceeded,
          Outcome = never_stopped),
    Outcome == stopped,
    % Twelve cheap answers cost about 4,824, inside the budget, so the
    % cumulative check passes them and the limiter stops the runaway resume.
    Rows =:= 12.

test(a_budget_above_the_whole_cost_drains) :-
    budget_engine_rows(budget_upto(0, 50, _), 1000000, 5000, Rows, Outcome),
    Outcome == drained,
    Rows =:= 51.

% The wrapper is used on a goal a host drives with findall/3 on its own thread,
% not only inside an engine. That thread's counter has been running since the
% process started, so a raw comparison against the budget would fire before the
% goal did any work at all.
test(a_budget_charges_a_host_thread_goal_for_its_own_work) :-
    budget_burn(200000),
    statistics(inferences, Started),
    % The precondition this case exists for: the counter is already past the
    % budget named below.
    Started > 100000,
    metta_host_inference_budget(budget_upto(0, 50, X), 100000, Bounded),
    findall(X, Bounded, Rows),
    length(Rows, 51).

test(a_non_positive_budget_installs_no_wrapper) :-
    Goal = budget_gen(0, _),
    metta_host_inference_budget(Goal, -1, Negative),
    metta_host_inference_budget(Goal, 0, Zero),
    strip_module(Negative, _, PlainNegative),
    strip_module(Zero, _, PlainZero),
    PlainNegative == Goal,
    PlainZero == Goal.

test(a_budget_that_is_not_an_integer_is_refused,
     [throws(error(type_error(integer, half), _))]) :-
    metta_host_inference_budget(true, half, _).

% A fixed charge per answer plus one for the base read, so its COST is a
% fraction of what an answer costs and the cheapest generator pays the most:
% about 0.7% where an answer costs 407 inferences, 9.7% at 31, and half again
% at 6. Pinned as a NUMBER because
% the shipped shape paid four here while the note describing it said two, and
% an unmeasured per-answer constant drifts in silence. Three is the floor for
% this shape: the two-inference variant drops the throw and merely fails, so a
% spent cursor would end quietly instead of reporting its bound.
test(the_cumulative_check_costs_three_inferences_per_answer) :-
    budget_charge(200, 2000, Expensive),
    budget_charge(12, 2000, Middling),
    budget_charge(0, 2000, Cheap),
    Expensive =:= 3,
    Middling =:= 3,
    Cheap =:= 3.

% The comparison's direction is worth an inference, which is not obvious and is
% the reason the clause is written the way round it is: SWI charges an
% if-then-else more when its condition FAILS, and within-budget is the common
% case. Written the other way this pair differs by exactly one per answer.
test(an_if_then_else_costs_more_on_the_branch_its_condition_fails_to) :-
    budget_drain(forall(between(1, 2000, N), (N > 3000 -> true ; true)),
                 _, ConditionFails),
    budget_drain(forall(between(1, 2000, N), (N =< 3000 -> true ; true)),
                 _, ConditionHolds),
    Difference is ConditionFails - ConditionHolds,
    Difference =:= 2000.

% The reserved envelope had no rendering, so a program that spent its own
% (pragma! max-inferences N) printed the raw term. Every seat that shows
% message text reads this, the C binding included.
test(a_spent_budget_names_the_bound_that_stopped_it) :-
    phrase(prolog:error_message(metta_control_signal(inference_limit, 500)),
           Parts),
    memberchk(Format-[500], Parts),
    once(sub_atom(Format, _, _, _, 'inference bound')).

:- end_tests(inference_budget).
