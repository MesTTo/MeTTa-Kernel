% Purpose: consult one engine checkout and exit, so the parity harness can
%   subtract each engine's fixed boot instructions from an example's run.
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

%Boot with the same silent, seated configuration as parity_driver.pl. If this
%fixture stayed seatless while the measured driver loaded Python, boot
%subtraction would charge fixed extension setup to every example. The missing
%seat was observed as `test/3: MeTTa test failed: ['py-call',[getattr,
%['py-call',['types.SimpleNamespace']],foo]] does not match
%3.141592653589793 (MeTTa test values differ)` [tested:
%VIRTUAL_ENV=<the checks venv> swipl parity_boot.pl ENGINE,
%both engines print BOOTED; commit=WORKTREE].
main :-
    current_prolog_flag(argv, [EngineRoot]),
    set_prolog_flag(argv, [silent, extensions]),
    parity_prepare(EngineRoot),
    parity_engine(EngineRoot, Engine),
    parity_consult(Engine),
    format("BOOTED~n").

:- initialization(main, main).
