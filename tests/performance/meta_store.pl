% Purpose: measure the compiler cost of recording many equations for one
%   function using SWI inference and CPU-time counters.
% Assumes:
%   - The first argv value is a positive equation count.
% Guarantees:
%   - The report uses three isolated runs and prints each sample plus the
%     independent minimum inference and CPU-time values.
%   - oracle hashes the complete newest-first metadata list and must match
%     across store implementations.
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
    findall(sample(Inferences, Cpu, Hash),
            ( between(1, 3, Trial),
              measure_meta_store(Trial, Count, Inferences, Cpu, Hash) ),
            Samples),
    findall(I, member(sample(I, _, _), Samples), InferenceSamples),
    findall(T, member(sample(_, T, _), Samples), CpuSamples),
    min_list(InferenceSamples, MinInferences),
    min_list(CpuSamples, MinCpu),
    Samples = [sample(_, _, Oracle)|_],
    forall(member(sample(_, _, Other), Samples), Other =:= Oracle),
    format('equations=~d runs=3 min_inferences=~d min_cputime=~6f ',
           [Count, MinInferences, MinCpu]),
    format('oracle=~d samples=~q~n', [Oracle, Samples]).

measure_meta_store(Trial, Count, Inferences, Cpu, Hash) :-
    format(atom(Function), '$meta_store_bench_~d', [Trial]),
    cleanup_meta_store(Function),
    statistics(inferences, I0),
    statistics(cputime, T0),
    forall(between(1, Count, _),
           ( Equation = [=, [Function, X], X],
             translate_clause(Equation, _) )),
    statistics(cputime, T1),
    statistics(inferences, I1),
    Inferences is I1 - I0,
    Cpu is T1 - T0,
    meta_store_oracle(Function, Count, Hash),
    cleanup_meta_store(Function).

meta_store_oracle(Function, Count, Hash) :-
    ( current_predicate(fun_meta_clause/3)
      -> findall(fun_meta(Args, Body),
                 fun_meta_clause(Function, Args, Body),
                 Clauses)
       ; nb_getval(Function, Clauses) ),
    length(Clauses, Count),
    copy_term(Clauses, Canonical),
    numbervars(Canonical, 0, _),
    term_hash(Canonical, Hash).

cleanup_meta_store(Function) :-
    ( current_predicate(fun_meta_clause/3)
      -> retractall(fun_meta_clause(Function, _, _))
    ; nb_current(Function, _)
      -> nb_delete(Function)
    ; true ),
    retractall(arity(Function, _)).
