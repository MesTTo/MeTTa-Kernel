% Purpose: measure dynamic reduction through operator and non-operator heads.
% Guarantees:
%   - Three independent runs report minimum inference and CPU-time values.
%   - oracle hashes the produced answer for semantic comparison.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

:- prolog_load_context(directory, Here),
   directory_file_path(Here, '../../src/metta.pl', Engine),
   consult(Engine).

main :-
    Iterations = 200000,
    forall(workload(Name, Form),
           ( findall(sample(Inferences, Cpu, Hash),
                     ( between(1, 3, _),
                       measure(Form, Iterations, Inferences, Cpu, Hash) ),
                     Samples),
             minima(Samples, MinInferences, MinCpu),
             same_hash(Samples, Oracle),
             format('workload=~w iterations=~d runs=3 ',
                    [Name, Iterations]),
             format('min_inferences=~d min_cputime=~6f oracle=~d ',
                    [MinInferences, MinCpu, Oracle]),
             format('samples=~q~n', [Samples]) )).

workload(binary_operator, ['+', 1, 2]).
workload(unary_nonoperator, [id, 1]).

measure(Form, Iterations, Inferences, Cpu, Hash) :-
    forall(between(1, 1000, _), once(reduce(Form, _))),
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    forall(between(1, Iterations, _), once(reduce(Form, _))),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0,
    once(reduce(Form, Answer)),
    term_hash(Answer, Hash).

same_hash([sample(_, _, Hash)|Samples], Hash) :-
    forall(member(sample(_, _, Other), Samples), Other =:= Hash).

minima(Samples, MinInferences, MinCpu) :-
    findall(I, member(sample(I, _, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T, _), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu).
