% Purpose: measure translation dispatch for ordinary data and indexed special
%   forms using SWI inference and CPU-time counters.
% Guarantees:
%   - Each workload reports the minimum inference count and CPU time from
%     three independent runs.
%   - oracle hashes the canonical translation and must match the chain-based
%     implementation.
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
    retractall(silent(_)),
    assertz(silent(true)),
    forall(workload(Label, Form), bench(Label, Form, Iterations)).

workload(data, [foo, 1, 2]).
workload(early, [superpose, [1, 2]]).
workload(late, [quote, [a, b]]).
workload(last, ['catch', [quote, x]]).

bench(Label, Form, Iterations) :-
    findall(sample(Inferences, Cpu, Oracle),
            ( between(1, 3, _),
              measure(Form, Iterations, Inferences, Cpu, Oracle) ),
            Samples),
    findall(I, member(sample(I, _, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T, _), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu),
    Samples = [sample(_, _, Oracle)|_],
    forall(member(sample(_, _, Other), Samples), Other =:= Oracle),
    format('workload=~w iterations=~d runs=3 min_inferences=~d ',
           [Label, Iterations, MinInferences]),
    format('min_cputime=~6f oracle=~d samples=~q~n',
           [MinCpu, Oracle, Samples]).

measure(Form, Iterations, Inferences, Cpu, Oracle) :-
    forall(between(1, 1000, _), once(translate_expr(Form, _, _))),
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    forall(between(1, Iterations, _), once(translate_expr(Form, _, _))),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0,
    once(translate_expr(Form, Goals, Out)),
    copy_term(Goals-Out, Canonical),
    numbervars(Canonical, 0, _),
    term_hash(Canonical, Oracle).
