% Purpose: run one .metta example on one engine checkout and print the
%   inferences its load and evaluation cost, for check_upstream_parity.py.
%   The marker line is machine-read; everything the example prints stays on
%   stdout above it, symmetric for both engines.
% Assumes: the engine root's src/metta.pl defines load_metta_file/2 and the
%   file-relative working_dir/1 convention both checkouts share.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

main :-
    current_prolog_flag(argv, [EngineRoot, Example]),
    atom_concat(EngineRoot, '/src/metta.pl', Engine),
    consult(Engine),
    file_directory_name(Example, Directory),
    assertz(working_dir(Directory)),
    statistics(inferences, Before),
    load_metta_file(Example, _),
    statistics(inferences, After),
    Spent is After - Before,
    format("PARITY-INFERENCES:~d~n", [Spent]).

:- initialization(main, main).
