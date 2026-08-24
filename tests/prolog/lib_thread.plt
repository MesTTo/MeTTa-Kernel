% Purpose: the concurrency library's Prolog surface, tested directly rather
%   than through a whole MeTTa example, so a defect points at the predicate.
%   Every parallel form is checked against its sequential twin: same answers,
%   or the test says why the difference is intended.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

% Load into user, BEFORE begin_tests. begin_tests/1 switches to the plunit
% module, so loading the engine after it puts every builtin there instead:
% the main thread still resolves them, and a worker thread calling
% user:'t-inc'/2 dies on `Unknown procedure: (+)/3`. Eighteen of these tests
% failed that way before the order was fixed. The same reason parser.plt uses
% initialization/1 here rather than a bare ensure_loaded.
:- ensure_loaded('../../engine/metta.pl').
:- initialization(consult('../../lib/lib_thread.pl')).
:- initialization(
       process_metta_string("(= (t-inc $x) (+ $x 1))
                             (= (t-big $x) (> $x 2))
                             (= (t-spin $n) (if (> $n 0) (t-spin (- $n 1)) done))
                             (= (t-slow $x) (let $_ (t-spin 2000000) $x))", _)).

% A foreign space that declares no event delivery, at FILE level: a
% begin_tests unit is a module of its own, so a multifile clause written
% inside it would define that module's predicate and the engine would never
% see it.
:- multifile seam:foreign_space/1.
:- multifile seam:foreign_capability/2.
:- multifile seam:foreign_match/3.
seam:foreign_space('&lt-silent-foreign').
seam:foreign_capability('&lt-silent-foreign', Capability) :-
    member(Capability, [add, remove, match, enumerate]).
seam:foreign_match('&lt-silent-foreign', [job, X]) :- X = quiet.

:- begin_tests(lib_thread).

% ------------------------------------------------------- parallel over data

test(par_map_answers_one_result_per_element_in_order) :-
    par_map('t-inc', [1, 2, 3, 4], Out),
    Out == [2, 3, 4, 5].

test(par_map_of_the_empty_list_is_empty) :-
    par_map('t-inc', [], Out),
    Out == [].

test(par_map_agrees_with_sequential_maplist) :-
    numlist(1, 25, Input),
    par_map('t-inc', Input, Parallel),
    metta_self_module(Self),
    findall(V, (member(E, Input), eval_metta_in_module(Self, ['t-inc', E], V)),
            Sequential),
    Parallel == Sequential.

test(par_map_rejects_a_non_list) :-
    catch(par_map('t-inc', notalist, _), error(type_error(list, _), _), true).

test(par_filter_keeps_the_matching_elements) :-
    par_filter('t-big', [1, 2, 3, 4, 5], Out),
    Out == [3, 4, 5].

test(par_filter_can_keep_nothing) :-
    par_filter('t-big', [1, 2], Out),
    Out == [].

test(par_forall_is_true_when_every_element_holds) :-
    par_forall('t-big', [3, 4, 5], Answer),
    Answer == true.

test(par_forall_is_false_when_one_element_fails) :-
    par_forall('t-big', [1, 4, 5], Answer),
    Answer == false.

test(par_forall_of_the_empty_list_is_true) :-
    par_forall('t-big', [], Answer),
    Answer == true.

% first_solution/3 answers the first goal to COMPLETE, so a branch that
% finishes by failing would make par_any answer false. This is the regression
% test for that: every element before the true one fails.
test(par_any_is_true_even_when_earlier_elements_fail) :-
    par_any('t-big', [1, 2, 9], Answer),
    Answer == true.

test(par_any_is_false_when_no_element_holds) :-
    par_any('t-big', [1, 2], Answer),
    Answer == false.

test(par_any_of_the_empty_list_is_false) :-
    par_any('t-big', [], Answer),
    Answer == false.

% ------------------------------------------------------------------ racing

test(race_answers_the_branch_that_finishes_first) :-
    par_race([['t-slow', 1], ['t-inc', 41]], Out),
    Out == 42.

test(race_is_not_sensitive_to_branch_order) :-
    par_race([['t-inc', 41], ['t-slow', 1]], Out),
    Out == 42.

% A losing branch must drop out rather than end the race, which is exactly
% what first_solution/3 would have got wrong.
test(race_survives_a_failing_branch) :-
    par_race([[superpose, []], ['t-inc', 41]], Out),
    Out == 42.

test(race_fails_when_every_branch_fails) :-
    \+ par_race([[superpose, []], [superpose, []]], _).

test(race_rejects_an_empty_branch_list) :-
    \+ par_race([], _).

% ----------------------------------------------------------------- futures

test(spawn_and_await_answer_the_value) :-
    thread_spawn(['t-inc', 41], Handle),
    thread_await(Handle, Out),
    Out == 42.

test(awaiting_twice_answers_the_same_value) :-
    thread_spawn(['t-inc', 1], Handle),
    thread_await(Handle, First),
    thread_await(Handle, Second),
    First == 2, Second == 2.

test(a_settled_future_reports_settled) :-
    thread_spawn(['t-inc', 1], Handle),
    thread_await(Handle, _),
    thread_settled(Handle, Answer),
    Answer == true.

test(awaiting_an_unknown_future_is_an_existence_error) :-
    catch(thread_await(999999, _), error(existence_error(petta_future, _), _),
          true).

%Two unbound arithmetic operands raise a HOST instantiation error. Integer
%division by zero and wrongly typed operands answer `(Error ...)` now and
%would come back as data, while a bare (throw x) is an unknown function.
test(a_future_that_raises_re_raises_on_await) :-
    thread_spawn([+, _Left, _Right], Handle),
    catch(thread_await(Handle, _), Ball, true),
    nonvar(Ball).

% The reason a future is a space: a MeTTa expression has an answer SET, and a
% future that answered only the first would discard that at the concurrency
% boundary.
test(a_future_holds_the_whole_answer_set) :-
    thread_spawn([superpose, [1, 2, 3]], Space),
    findall(V, thread_await(Space, V), Answers),
    msort(Answers, Sorted),
    Sorted == [1, 2, 3].

test(a_future_handle_is_a_space) :-
    thread_spawn(['t-inc', 1], Space),
    thread_await(Space, _),
    'is-space'(Space, true).

test(a_future_space_can_be_read_with_get_atoms) :-
    thread_spawn(['t-inc', 41], Space),
    thread_await(Space, _),
    findall(A, 'get-atoms'(Space, A), Atoms),
    Atoms == [42].

test(a_future_with_no_answers_is_empty) :-
    thread_spawn([superpose, []], Space),
    findall(V, thread_await(Space, V), Answers),
    Answers == [].

% ------------------------------------------------------------------- timers

test(after_produces_its_answer_when_it_fires) :-
    timer_after(0.05, ['t-inc', 41], Space),
    findall(V, thread_await(Space, V), Answers),
    Answers == [42].

test(a_pending_timer_is_not_settled_and_does_not_raise) :-
    timer_after(30, ['t-inc', 41], Space),
    thread_settled(Space, Answer),
    Answer == false,
    thread_cancel(Space, _).

test(cancelling_a_pending_timer_stops_it_firing) :-
    timer_after(0.05, ['t-inc', 41], Space),
    thread_cancel(Space, _),
    sleep(0.25),
    findall(A, 'get-atoms'(Space, A), Atoms),
    Atoms == [].

test(every_fires_more_than_once_and_cancel_stops_it) :-
    timer_every(0.05, ['t-inc', 1], Space),
    sleep(0.28),
    thread_cancel(Space, _),
    findall(A, 'get-atoms'(Space, A), During),
    length(During, Ticks),
    Ticks >= 2,
    sleep(0.3),
    findall(A2, 'get-atoms'(Space, A2), After),
    length(After, Same),
    Same == Ticks.

test(every_rejects_a_non_positive_period) :-
    \+ timer_every(0, [true], _).

% ---------------------------------------------------------------- channels

test(a_channel_round_trips_a_term) :-
    channel_new(Channel),
    channel_send(Channel, hello, true),
    channel_recv(Channel, Got),
    Got == hello,
    channel_close(Channel, true).

test(channel_size_counts_what_is_waiting) :-
    channel_new(Channel),
    channel_send(Channel, one, true),
    channel_send(Channel, two, true),
    channel_size(Channel, Size),
    Size == 2,
    channel_close(Channel, true).

test(try_recv_does_not_block_on_an_empty_channel) :-
    channel_new(Channel),
    \+ channel_try_recv(Channel, _),
    channel_close(Channel, true).

test(recv_with_a_deadline_gives_up) :-
    channel_new(Channel),
    \+ channel_recv(Channel, 0.05, _),
    channel_close(Channel, true).

test(a_channel_carries_a_term_between_threads) :-
    channel_new(Channel),
    thread_create(( sleep(0.02), channel_send(Channel, from_worker, true) ),
                  Thread, []),
    channel_recv(Channel, Got),
    thread_join(Thread, _),
    Got == from_worker,
    channel_close(Channel, true).

test(using_an_unknown_channel_is_an_existence_error) :-
    catch(channel_recv(999999, _), error(existence_error(petta_channel, _), _),
          true).

% ------------------------------------------------------------------- pools

test(a_pool_runs_submitted_work) :-
    pool_create('$test_pool', 2, true),
    pool_submit('$test_pool', ['t-inc', 9], Handle),
    thread_await(Handle, Out),
    Out == 10,
    pool_destroy('$test_pool', true).

test(submitting_to_an_unknown_pool_is_an_existence_error) :-
    catch(pool_submit('$no_such_pool', [true], _),
          error(existence_error(petta_thread_pool, _), _), true).

% --------------------------------------------------------- synchronisation

% The reason with_lock/3 exists: SWI's with_mutex/2 is once/1, so the obvious
% spelling turns three answers into one.
test(with_lock_keeps_every_answer) :-
    findall(V, with_lock('$test_lock', [superpose, [1, 2, 3]], V), Answers),
    msort(Answers, Sorted),
    Sorted == [1, 2, 3].

test(the_builtin_with_mutex_collapses_to_one_answer) :-
    findall(V, with_mutex('$test_lock2', member(V, [1, 2, 3])), Answers),
    Answers == [1].

% (superpose ()) is how a MeTTa expression yields nothing; a bare (fail) is an
% unknown function and comes back as data, which is what this test asserted
% first and why it did not test what it claimed.
test(with_lock_releases_the_lock_after_a_failure) :-
    \+ with_lock('$test_lock3', [superpose, []], _),
    findall(V, with_lock('$test_lock3', [superpose, [7]], V), Answers),
    Answers == [7].

% ---------------------------------------------------- blocking on a space

% Deliberately the BOUNDED form even though the unbounded one is what this
% exercises: a test that can block forever can hang the whole gate, and this
% suite runs twice, once with mork, where atom writes route differently.
test(await_atom_wakes_on_a_matching_write) :-
    thread_create(( sleep(0.05),
                    'add-atom'('&self', [awaited, marker], _) ), Thread, []),
    space_await('&self', [awaited, X], 10, Out),
    thread_join(Thread, _),
    X == marker,
    Out == [awaited, marker].

test(await_atom_gives_up_after_its_deadline) :-
    \+ space_await('&self', [never, appears, here], 0.05, _).

% --------------------------------------------------- the Linda blocking pair

% P12.16. Three claims in one test, because they are one contract: a take
% PARKS until something matches, it REMOVES exactly one, and under contention
% two takers never get the same atom. The contention half is what needs real
% threads: eight takers wait on one pattern, four atoms are written, and the
% four winners must hold four distinct atoms with the space left empty
% [source: JavaSpaces Service Specification JS.2.5, "two take operations will
% never return copies of the same entry"].
test(test_a_blocking_take_waits_for_a_matching_atom_and_removes_exactly_one,
     [ setup(( 'remove-all-atoms-of'('&lt-pool', [job, _]) )),
       cleanup(( 'remove-all-atoms-of'('&lt-pool', [job, _]) )) ]) :-
    % It PARKS: the take starts before the atom exists and answers when it
    % lands, which is what makes it a wait rather than a poll.
    thread_create(( sleep(0.05),
                    'add-atom'('&lt-pool', [job, first], _) ), Writer, []),
    space_take('&lt-pool', [job, X], 10, Taken),
    thread_join(Writer, _),
    assertion(X == first),
    assertion(Taken == [job, first]),
    % And it REMOVED it: a peek on the same pattern now finds nothing, where
    % before the take it would have answered at once.
    assertion(\+ space_await('&lt-pool', [job, _], 0.05, _)),

    % Under contention: eight takers, four atoms, four winners, no atom
    % taken twice and none left behind.
    message_queue_create(Won),
    findall(Id,
            ( between(1, 8, _),
              thread_create(lt_take_into(Won), Id, []) ),
            Takers),
    forall(between(1, 4, N), 'add-atom'('&lt-pool', [job, N], _)),
    forall(member(Taker, Takers), thread_join(Taker, _)),
    findall(Result,
            ( repeat,
              (   thread_get_message(Won, Result, [timeout(0)])
              ->  true
              ;   !, fail
              ) ),
            Results),
    catch(message_queue_destroy(Won), _, true),
    include(=(none), Results, Missed),
    exclude(=(none), Results, Claimed),
    assertion(length(Results, 8)),
    assertion(length(Claimed, 4)),
    assertion(length(Missed, 4)),
    msort(Claimed, Sorted),
    assertion(Sorted == [[job, 1], [job, 2], [job, 3], [job, 4]]),
    findall(A, 'get-atoms'('&lt-pool', A), Left),
    assertion(Left == []).

lt_take_into(Won) :-
    (   space_take('&lt-pool', [job, _], 2, Taken)
    ->  thread_send_message(Won, Taken)
    ;   thread_send_message(Won, none)
    ).

% The peek half of the pair, stated on its own: rd reads and leaves, so two
% peeks answer the same atom where two takes could not.
test(a_blocking_peek_parks_without_removing,
     [ setup(( 'remove-all-atoms-of'('&lt-peek', [tuple, _]) )),
       cleanup(( 'remove-all-atoms-of'('&lt-peek', [tuple, _]) )) ]) :-
    thread_create(( sleep(0.05),
                    'add-atom'('&lt-peek', [tuple, one], _) ), Writer, []),
    space_await('&lt-peek', [tuple, A], 10, First),
    thread_join(Writer, _),
    assertion(A == one),
    space_await('&lt-peek', [tuple, B], 1, Second),
    assertion(B == one),
    assertion(First == Second),
    findall(Atom, 'get-atoms'('&lt-peek', Atom), Left),
    assertion(Left == [[tuple, one]]).

% A wake-up sent to a waiter that already gave up must be dropped, not an
% error in the WRITER: erase/1 does not stop an execution already inside the
% wait hook (logical update view), so a write can be mid-hook when a
% timed-out waiter erases it and destroys its queue. The store is the truth
% and the hint has no recipient; under gate load this raced once as
% thread_send_message existence_error inside add-atom. Deterministic here:
% run the hook's own installed clause against a queue destroyed first.
test(a_wakeup_to_a_departed_waiter_is_dropped,
     [ setup(( 'remove-all-atoms-of'('&lt-departed', [job, _]) )),
       cleanup(( 'remove-all-atoms-of'('&lt-departed', [job, _]) )) ]) :-
    % Half one, the real sequence: a waiter times out and leaves, then the
    % write lands. The in-flight window itself needs a writer INSIDE the hook
    % at teardown and cannot be scheduled deterministically, so this half
    % guards the teardown ordering and half two pins the tolerated shape.
    thread_create(\+ space_take('&lt-departed', [job, _], 0.05, _),
                  Waiter, []),
    thread_join(Waiter, WaiterStatus),
    assertion(WaiterStatus == true),
    catch(( 'add-atom'('&lt-departed', [job, late], _), AfterTimeout = wrote ),
          LateError,
          AfterTimeout = error(LateError)),
    assertion(AfterTimeout == wrote),
    'remove-all-atoms-of'('&lt-departed', [job, _]),
    % Half two, the shape the library installs: the SAME clause body the wait
    % hook asserts, run against a queue destroyed first, writes rather than
    % raising. Without the catch in lib_thread.pl's hook this shape is what
    % raced once under gate load as existence_error inside add-atom.
    message_queue_create(Queue),
    copy_term([job, _], HookPattern),
    assertz((seam:atom_added('&lt-departed', Candidate) :-
                (   \+ HookPattern \= Candidate
                ->  catch(thread_send_message(Queue, Candidate),
                          error(existence_error(message_queue, _), _),
                          true)
                ;   true
                )), HookRef),
    message_queue_destroy(Queue),
    catch(( 'add-atom'('&lt-departed', [job, orphan], _), Outcome = wrote ),
          Error,
          Outcome = error(Error)),
    erase(HookRef),
    assertion(Outcome == wrote).

% A context that promises no change events cannot be parked on: waiting for
% something nothing will ever report is a hang, and P12.14's declaration is
% what turns it into a refusal.
test(a_wait_on_a_context_with_no_events_is_refused_rather_than_parked) :-
    catch(space_take('&lt-silent-foreign', [job, _], 1, _),
          error(Ball, _), true),
    assertion(Ball == petta_events_undeclared('&lt-silent-foreign',
                                              'be waited on')).

'remove-all-atoms-of'(Space, Pattern) :-
    forall(( 'get-atoms'(Space, Atom), \+ Pattern \= Atom ),
           'remove-atom'(Space, Atom, _)).

% ------------------------------------------------------------ introspection

test(cpu_count_is_a_positive_integer) :-
    cpu_count(Count),
    integer(Count), Count >= 1.

test(thread_count_is_a_positive_integer) :-
    thread_count(Count),
    integer(Count), Count >= 1.

:- end_tests(lib_thread).
