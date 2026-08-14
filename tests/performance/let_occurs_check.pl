% Purpose: measure ordinary let binding and report whether a computed
%   self-referential binding can escape as a cyclic Prolog term.
% Assumes:
%   - The first argv value is a positive iteration count.
% Guarantees:
%   - Three runs report independent minimum inference and CPU-time values
%     [measured: three 6,004-inference samples at 1,000 iterations, 2026-08-15].
%   - The computed cons-atom self-reference is checked before the ordinary let
%     samples [measured: computed_cyclic_let=no_answer, 2026-08-15].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

:- prolog_load_context(directory, Here),
   directory_file_path(Here, '../../src/metta.pl', Engine),
   consult(Engine).

main :-
    current_prolog_flag(argv, [CountAtom|_]),
    atom_number(CountAtom, Count),
    integer(Count),
    Count > 0,
    computed_cyclic_let_status(CyclicStatus),
    translate_expr([let, X, [value, 42], X], Goals, Out),
    findall(sample(Inferences, Cpu),
            ( between(1, 3, _),
              measure_let(Count, Goals-Out, Inferences, Cpu) ),
            Samples),
    minima(Samples, MinInferences, MinCpu),
    format('iterations=~d runs=3 computed_cyclic_let=~w ',
           [Count, CyclicStatus]),
    format('min_inferences=~d min_cputime=~6f samples=~q~n',
           [MinInferences, MinCpu, Samples]).

computed_cyclic_let_status(Status) :-
    translate_expr([let, X, ['cons-atom', X, []], X], Goals, Out),
    ( call_goals(Goals)
      -> ( cyclic_term(Out) -> Status = cyclic ; Status = acyclic )
    ; Status = no_answer ).

measure_let(Count, Template, Inferences, Cpu) :-
    garbage_collect,
    statistics(inferences, I0),
    statistics(cputime, T0),
    forall(between(1, Count, _),
           ( copy_term(Template, Goals-Out),
             call_goals(Goals),
             Out == [value, 42] )),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0.

minima(Samples, MinInferences, MinCpu) :-
    findall(I, member(sample(I, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu).
