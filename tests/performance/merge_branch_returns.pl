% Purpose: measure merge_branch_returns/3 on a nested conditional body with
%   one candidate return merge per level.
% Assumes:
%   - The first argv value is a positive conditional depth.
% Guarantees:
%   - Three independent runs report minimum inference and CPU-time values.
%   - oracle is the canonical transformed clause hash and must stay unchanged.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

:- prolog_load_context(directory, Here),
   directory_file_path(Here, '../../src/metta.pl', Engine),
   consult(Engine).

main :-
    current_prolog_flag(argv, [DepthAtom|_]),
    atom_number(DepthAtom, Depth),
    integer(Depth),
    Depth > 0,
    nest_if(Depth, BodyExpr),
    translate_expr(BodyExpr, Goals, Out),
    goals_list_to_conj(Goals, Body),
    Head = merge_bench(input, Out),
    findall(sample(Inferences, Cpu, Hash),
            ( between(1, 3, _),
              copy_term(Head-Body, RunHead-RunBody),
              measure_merge(RunHead, RunBody, Inferences, Cpu, Hash) ),
            Samples),
    minima(Samples, MinInferences, MinCpu),
    same_hash(Samples, Oracle),
    format('depth=~d runs=3 min_inferences=~d min_cputime=~6f ',
           [Depth, MinInferences, MinCpu]),
    format('oracle=~d samples=~q~n', [Oracle, Samples]).

nest_if(0, 0) :- !.
nest_if(N, [if, [==, 1, 1], Inner, 0]) :-
    N1 is N - 1,
    nest_if(N1, Inner).

measure_merge(Head, Body, Inferences, Cpu, Hash) :-
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    merge_branch_returns(Head, Body, Merged),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0,
    copy_term(Head-Merged, Canonical),
    numbervars(Canonical, 0, _),
    term_hash(Canonical, Hash).

same_hash([sample(_, _, Hash)|Samples], Hash) :-
    forall(member(sample(_, _, Other), Samples), Other =:= Hash).

minima(Samples, MinInferences, MinCpu) :-
    findall(I, member(sample(I, _, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T, _), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu).
