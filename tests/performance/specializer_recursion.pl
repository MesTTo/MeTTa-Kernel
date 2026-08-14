% Purpose: measure whether a recursive higher-order specialization stays on
%   its generated predicate after the first recursive step.
% Assumes:
%   - The first argv value is a positive recursion count.
% Guarantees:
%   - Generic and specialized calls each run three times, report independent
%     minimum inference and CPU-time values, and must return the recursion count.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

:- prolog_load_context(directory, Here),
   directory_file_path(Here, '../../src/metta.pl', Engine),
   consult(Engine).

definitions("\n
(= (review-inc $x) (+ $x 1))\n
(= (review-rep $f 0 $x) $x)\n
(= (review-rep $f $n $x)\n
   (if (> $n 0)\n
       (review-rep $f (- $n 1) ($f $x))\n
       (empty)))\n
").

main :-
    current_prolog_flag(argv, [CountAtom|_]),
    atom_number(CountAtom, Count),
    integer(Count),
    Count > 0,
    retractall(silent(_)),
    assertz(silent(true)),
    definitions(Source),
    process_metta_string(Source, _),
    process_metta_string("!(review-rep review-inc 3 0)", [3]),
    ho_specialization('review-rep', SpecName),
    goal_counts(SpecName, ReduceCalls, GenericCalls),
    measure_three(generic, 'review-rep', Count, GenericSamples),
    measure_three(specialized, SpecName, Count, SpecializedSamples),
    minima(GenericSamples, GenericInferences, GenericCpu),
    minima(SpecializedSamples, SpecializedInferences, SpecializedCpu),
    format('steps=~d runs=3 reduce_calls=~d generic_recursive_calls=~d ',
           [Count, ReduceCalls, GenericCalls]),
    format('generic_min_inferences=~d generic_min_cputime=~6f ',
           [GenericInferences, GenericCpu]),
    format('specialized_min_inferences=~d specialized_min_cputime=~6f ',
           [SpecializedInferences, SpecializedCpu]),
    format('generic_samples=~q specialized_samples=~q~n',
           [GenericSamples, SpecializedSamples]).

goal_counts(SpecName, ReduceCalls, GenericCalls) :-
    aggregate_all(count,
                  ( specialization_body(SpecName, Body),
                    sub_term(Term, Body),
                    compound(Term),
                    functor(Term, reduce, 2) ),
                  ReduceCalls),
    aggregate_all(count,
                  ( specialization_body(SpecName, Body),
                    sub_term(Term, Body),
                    compound(Term),
                    functor(Term, 'review-rep', 4) ),
                  GenericCalls).

specialization_body(SpecName, Body) :-
    functor(Head, SpecName, 4),
    clause(Head, Body).

measure_three(Kind, Name, Count, Samples) :-
    findall(Sample,
            ( between(1, 3, _),
              measure_call(Kind, Name, Count, Sample) ),
            Samples).

measure_call(Kind, Name, Count, sample(Inferences, Cpu)) :-
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    call_review(Kind, Name, Count, Out),
    Out == Count,
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0.

call_review(generic, Name, Count, Out) :-
    Goal =.. [Name, 'review-inc', Count, 0, Out],
    call(Goal).
call_review(specialized, Name, Count, Out) :-
    Goal =.. [Name, 'review-inc', Count, 0, Out],
    call(Goal).

minima(Samples, MinInferences, MinCpu) :-
    findall(I, member(sample(I, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu).
