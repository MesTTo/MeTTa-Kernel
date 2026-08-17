% Purpose: consult one engine checkout and exit, so the parity harness can
%   subtract each engine's fixed boot instructions from an example's run.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

main :-
    current_prolog_flag(argv, [EngineRoot]),
    atom_concat(EngineRoot, '/src/metta.pl', Engine),
    consult(Engine),
    format("BOOTED~n").

:- initialization(main, main).
