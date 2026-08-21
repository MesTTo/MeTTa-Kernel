% Purpose: run the standalone PeTTa command-line entry point and display each
%   result from a requested MeTTa source file.
% Guarantees:
%   - command-line answers use sdisplay/2, so host-only values and non-finite
%     numbers remain printable presentation values without weakening
%     swrite/2's reader-inverse contract [tested:
%     test_non_finite_floats_print_the_arbiters_spellings; commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%   - the no-argument demo defines a MeTTa equation, calls it from Prolog
%     through the space's module, and runs every loaded backend selftest
%     [tested: test_the_bare_demo_runs_the_interop_example_and_backend_selftests;
%     commit=86222967a4198e11103e63a60ec8637c6ac9cb27].
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

%The equation compiles into &self's space module, so both the listing and the
%direct Prolog call name that module; the bare spellings stopped resolving when
%the space model moved &self out of user, and listing/1 was the goal that threw,
%because SWI DWIMs an unqualified name against the calling module.
prolog_interop_example :- import_prolog_function(prologfunc, _),
                          process_metta_string("(= (mettafunc $x) (prologfunc $x))", _),
                          space_module('&self', Space),
                          listing(Space:mettafunc),
                          call(Space:mettafunc, 30, R),
                          format("mettafunc(30) = ~w~n", [R]).

%The demo runs every loaded backend's own smoke test. It used to call
%mork_test/0 by name behind an `Args = [mork]` branch, which is why this file
%knew a backend existed at all; with no backend loaded the forall runs nothing
%and the demo is what it always was.
main :- current_prolog_flag(argv, RawArgs),
        strip_engine_flags(RawArgs, Args),
        ( Args = [] -> prolog_interop_example,
                       %forall/2 over the predicate's solutions cannot see a
                       %failing clause, so the demo walks the loaded clauses
                       %and a selftest that fails ends the run naming itself.
                       forall(clause(metta_backend_selftest, Selftest),
                              (   call(Selftest)
                              ->  true
                              ;   format(user_error,
                                         "backend selftest failed: ~p~n",
                                         [Selftest]),
                                  halt(1)
                              ))
        ; Args = [File|_] -> load_metta_file(File,Results),
                             maplist(sdisplay,Results,ResultsR),
                             maplist(format("~w~n"), ResultsR)
        ),
        halt.

:- initialization(main, main).
