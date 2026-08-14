% Purpose: measure acyclic-result validation on broad and selective native
%   space matches using SWI inference and CPU-time counters.
% Assumes:
%   - The first argv value is a positive atom count.
% Guarantees:
%   - Each workload runs three times and returns the expected answers.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

:- prolog_load_context(directory, Here),
   directory_file_path(Here, '../../src/metta.pl', Engine),
   consult(Engine).

guard_space('&cycle_guard_bench').

main :-
    current_prolog_flag(argv, [CountAtom|_]),
    atom_number(CountAtom, Count),
    integer(Count),
    Count > 0,
    guard_space(Space),
    forall(between(1, Count, I), add_sexp(Space, [fact, I])),
    measure_three(all_answers, all_facts(Count), AllSamples),
    measure_three(selective, one_fact(Count), OneSamples),
    minima(AllSamples, AllInferences, AllCpu),
    minima(OneSamples, OneInferences, OneCpu),
    format('atoms=~d runs=3 ', [Count]),
    format('all_min_inferences=~d all_min_cputime=~6f ',
           [AllInferences, AllCpu]),
    format('selective_repetitions=2000 selective_min_inferences=~d ',
           [OneInferences]),
    format('selective_min_cputime=~6f all_samples=~q selective_samples=~q~n',
           [OneCpu, AllSamples, OneSamples]).

all_facts(ExpectedCount) :-
    guard_space(Space),
    findall(X, match(Space, [fact, X], X, _), Answers),
    length(Answers, ExpectedCount).

one_fact(Value) :-
    guard_space(Space),
    forall(between(1, 2000, _),
           once(match(Space, [fact, Value], Value, _))).

measure_three(_, Goal, Samples) :-
    findall(Sample,
            ( between(1, 3, _),
              measure_call(Goal, Sample) ),
            Samples).

measure_call(Goal, sample(Inferences, Cpu)) :-
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    call(Goal),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0.

minima(Samples, MinInferences, MinCpu) :-
    findall(I, member(sample(I, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu).
