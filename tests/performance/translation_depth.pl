% Purpose: measure expression translation as nesting depth grows.
% Assumes:
%   - The first argv value is a positive nesting depth.
% Guarantees:
%   - Three independent runs report minimum inference and CPU-time values.
%   - oracle hashes the canonical goals and result for semantic comparison.
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
    forall(shape(Name, Builder),
           ( call(Builder, Depth, Expr),
             findall(sample(Inferences, Cpu, Hash),
                     ( between(1, 3, _),
                       copy_term(Expr, RunExpr),
                       measure_translation(RunExpr, Inferences, Cpu, Hash) ),
                     Samples),
             minima(Samples, MinInferences, MinCpu),
             same_hash(Samples, Oracle),
             format('shape=~w depth=~d runs=3 min_inferences=~d min_cputime=~6f ',
                    [Name, Depth, MinInferences, MinCpu]),
             format('oracle=~d samples=~q~n', [Oracle, Samples]) )).

shape(call, nest_call).
shape(head, nest_head).
shape(let, nest_let).
shape(if, nest_if).

nest_call(0, 0) :- !.
nest_call(N, ['+', 1, Inner]) :-
    N1 is N - 1,
    nest_call(N1, Inner).

nest_head(0, _) :- !.
nest_head(N, [Inner]) :-
    N1 is N - 1,
    nest_head(N1, Inner).

nest_let(0, 0) :- !.
nest_let(N, [let, '$v', 1, Inner]) :-
    N1 is N - 1,
    nest_let(N1, Inner).

nest_if(0, 0) :- !.
nest_if(N, [if, [==, 1, 1], Inner, 0]) :-
    N1 is N - 1,
    nest_if(N1, Inner).

measure_translation(Expr, Inferences, Cpu, Hash) :-
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    translate_expr(Expr, Goals, Out),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0,
    copy_term(Goals-Out, Canonical),
    numbervars(Canonical, 0, _),
    term_hash(Canonical, Hash).

same_hash([sample(_, _, Hash)|Samples], Hash) :-
    forall(member(sample(_, _, Other), Samples), Other =:= Hash).

minima(Samples, MinInferences, MinCpu) :-
    findall(I, member(sample(I, _, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T, _), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu).
