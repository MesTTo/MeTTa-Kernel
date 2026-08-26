% Purpose: compare cheap spawn latency and parked-wait thread cost between the
%   dedicated-thread future face and the suspended-engine M:N scheduler.
% Assumes:
%   - run from a PeTTa checkout root so engine/metta.pl and lib/lib_thread.pl
%     select that checkout's implementation.
% Guarantees:
%   - every parked worker announces readiness through a channel before thread
%     count is sampled; no timing sleep decides whether a worker is counted
%     [tested: swipl -q -f tests/prolog/async_scheduler_bench.pl -g bench -t halt;
%     commit=WORKTREE].
% Decides:
%   - 200 cheap spawns expose fixed scheduler overhead, while 128 simultaneous
%     waits make the dedicated-thread and M:N resource shapes distinguishable.

:- ensure_loaded('engine/metta.pl').
:- initialization(consult('lib/lib_thread.pl')).
:- initialization(
       process_metta_string("!(import! &self (library lib_thread))
                             (= (bench-wait $ready $n)
                                (let $_ (send $ready $n)
                                  (peek-atom &self (bench_release $x) 30)))", _)).

bench_spawn_add(_, Space) :-
    thread_spawn([+, 1, 1], Space).

bench_await_add(Space) :-
    once(thread_await(Space, 2)).

bench_spawn_wait(Ready, Number, Space) :-
    thread_spawn(['bench-wait', Ready, Number], Space).

bench_await_wait(Space) :-
    once(thread_await(Space, [bench_release, ready])).

bench_os_thread_count(Count) :-
    directory_files('/proc/self/task', Entries),
    exclude(=('.'), Entries, WithoutDot),
    exclude(=('..'), WithoutDot, Threads),
    length(Threads, Count).

bench_receive_ready(Ready, _) :-
    channel_recv(Ready, _).

bench :-
    numlist(1, 200, CheapJobs),
    get_time(CheapStart),
    maplist(bench_spawn_add, CheapJobs, CheapSpaces),
    maplist(bench_await_add, CheapSpaces),
    get_time(CheapEnd),
    CheapMs is (CheapEnd - CheapStart) * 1000,
    bench_os_thread_count(Before),
    channel_new(Ready),
    numlist(1, 128, WaitingJobs),
    get_time(WaitingStart),
    maplist(bench_spawn_wait(Ready), WaitingJobs, WaitingSpaces),
    maplist(bench_receive_ready(Ready), WaitingJobs),
    bench_os_thread_count(Blocked),
    'add-atom'('&self', [bench_release, ready], _),
    maplist(bench_await_wait, WaitingSpaces),
    get_time(WaitingEnd),
    WaitingMs is (WaitingEnd - WaitingStart) * 1000,
    'remove-atom'('&self', [bench_release, ready], _),
    channel_close(Ready, true),
    format('cheap_ms=~3f threads_before=~d threads_waiting=~d wait_cycle_ms=~3f~n',
           [CheapMs, Before, Blocked, WaitingMs]).
