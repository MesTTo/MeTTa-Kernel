% Purpose: run one .metta example on one engine checkout and print the
%   inferences its load and evaluation cost, for check_upstream_parity.py.
%   The marker line is machine-read; everything the example prints stays on
%   stdout above it, symmetric for both engines.
% Assumes: the engine root's engine/metta.pl or src/metta.pl defines
%   load_metta_file/2 and the
%   file-relative working_dir/1 convention both checkouts share.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The QLF boot FIRST where the checkout has one, and the load under
%qcompile(auto), which together are what engine/main.pl does and therefore
%what the shipping configuration is. Without the flag SWI compiles the engine
%from SOURCE every run and never reads the artifacts.
%Consulting engine/metta.pl on its own compiles the engine from source every
%run: 1.69e9 instructions against 1.04e9 through the artifacts, measured
%2026-08-30, so a comparison without it prices a configuration nobody ships.
parity_prepare(EngineRoot) :-
    atom_concat(EngineRoot, '/engine/qlf_boot.pl', Boot),
    ( exists_file(Boot) -> ensure_loaded(Boot) ; true ).

parity_consult(Engine) :-
    current_prolog_flag(qcompile, Old),
    setup_call_cleanup(set_prolog_flag(qcompile, auto),
                       consult(Engine),
                       set_prolog_flag(qcompile, Old)).

%The engine module, whichever layout the checkout uses: this tree keeps it at
%engine/metta.pl and upstream at src/metta.pl. Resolving both is what lets one
%driver measure the two engines that are actually being compared.
%WITHOUT the .pl extension, which is what lets SWI prefer the compiled
%artifact: consulting `metta.pl` names the SOURCE and loads it, and the engine
%then compiled from source on every measured run, 1.71e9 instructions against
%1.04e9 [measured 2026-08-30]. engine/main.pl says `ensure_loaded(metta)` for
%the same reason.
parity_engine(EngineRoot, Engine) :-
    atom_concat(EngineRoot, '/engine/metta', Ours),
    atom_concat(EngineRoot, '/src/metta', Theirs),
    (   exists_source(Ours)
    ->  Engine = Ours
    ;   exists_source(Theirs)
    ->  Engine = Theirs
    ;   throw(error(existence_error(source_sink, EngineRoot),
                    context(parity_engine/2,
                            'no engine/metta and no src/metta there')))
    ).

%Replace the fixture's routing arguments before any engine file loads. The
%shipping launcher leaves [Example,silent,extensions] visible during the load:
%silent suppresses translator diagnostics and extensions makes this tree read
%the Python seat whose bridge implements py-call. With the fixture arguments
%left in argv, 01-python.metta ended exactly with `test/3: MeTTa test failed:
%['py-call',[getattr,['py-call',['types.SimpleNamespace']],foo]] does not match
%3.141592653589793 (MeTTa test values differ)` instead of printing the marker.
%Upstream loads Janus unconditionally, so the same argv is inert there and the
%two engines still receive one symmetric configuration [tested:
%VIRTUAL_ENV=<the checks venv> swipl parity_driver.pl ENGINE EXAMPLE,
%three consecutive processes per engine and example; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
main :-
    current_prolog_flag(argv, [EngineRoot, Example]),
    set_prolog_flag(argv, [Example, silent, extensions]),
    parity_prepare(EngineRoot),
    parity_engine(EngineRoot, Engine),
    parity_consult(Engine),
    file_directory_name(Example, Directory),
    assertz(working_dir(Directory)),
    statistics(inferences, Before),
    load_metta_file(Example, _),
    statistics(inferences, After),
    Spent is After - Before,
    format("PARITY-INFERENCES:~d~n", [Spent]).

:- initialization(main, main).
