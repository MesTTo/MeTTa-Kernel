% Purpose: run the standalone PeTTa command-line entry point and display each
%   result from a requested MeTTa source file.
% Guarantees:
%   - command-line answers use sdisplay/2, so host-only values and non-finite
%     numbers remain printable presentation values without weakening
%     swrite/2's reader-inverse contract [tested:
%     test_non_finite_floats_print_the_arbiters_spellings; commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded(metta).

%Tokens the engine reads for itself, which are therefore not the file to run.
%`backends` asks engine/metta.pl to load every native backend that is built; it is
%stripped here for the same reason the silent flags are, so that a bare
%`swipl -s engine/main.pl -- backends` still means the demo rather than a file
%called "backends".
is_engine_flag(silent).
is_engine_flag('--silent').
is_engine_flag('-s').
is_engine_flag(backends).

strip_engine_flags([], []).
strip_engine_flags([Arg|Rest], Filtered) :-
        is_engine_flag(Arg),
        !,
        strip_engine_flags(Rest, Filtered).
strip_engine_flags([Arg|Rest], [Arg|Filtered]) :-
        strip_engine_flags(Rest, Filtered).

prologfunc(X,Y) :- Y is X+1.

prolog_interop_example :- import_prolog_function(prologfunc, _),
                          process_metta_string("(= (mettafunc $x) (prologfunc $x))", _),
                          listing(mettafunc),
                          mettafunc(30, R),
                          format("mettafunc(30) = ~w~n", [R]).

%The demo runs every loaded backend's own smoke test. It used to call
%mork_test/0 by name behind an `Args = [mork]` branch, which is why this file
%knew a backend existed at all; with no backend loaded the forall runs nothing
%and the demo is what it always was.
main :- current_prolog_flag(argv, RawArgs),
        strip_engine_flags(RawArgs, Args),
        ( Args = [] -> prolog_interop_example,
                       forall(metta_backend_selftest, true)
        ; Args = [File|_] -> load_metta_file(File,Results),
                             maplist(sdisplay,Results,ResultsR),
                             maplist(format("~w~n"), ResultsR)
        ),
        halt.

:- initialization(main, main).
