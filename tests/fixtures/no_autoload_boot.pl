% Purpose: entry point for the autoload=false example-corpus lane. Sets the
%   flag before engine/main.pl, and so engine/metta.pl, ever loads.
% Guarantees:
%   - after this loads, argv processing, backend loading and
%     load_metta_file/2 all behave exactly as when engine/main.pl is the -s
%     file directly: this only adds one directive ahead of
%     ensure_loaded('../../engine/main.pl'), so main.pl's own
%     initialization(main, main) still reads current_prolog_flag(argv, _)
%     the normal way, which is what run.sh's NO_AUTOLOAD=1 branch relies on
%     [measured 2026-08-18: NO_AUTOLOAD=1 sh test.sh, 200/200 examples/].
%   - a failure to reach engine/main.pl HALTS with status 2 rather than
%     continuing. Without that, swipl finished loading a file that defines
%     nothing, exited 0 having printed nothing, and engine/check.sh's
%     no-autoload GATE reported 233 examples OK while running none of them
%     [measured 2026-09-03: with the path one `..` short, NO_AUTOLOAD=1 sh
%     test.sh exits 0 with 233 OK lines and 0 assertion lines; with the halt
%     it exits 1 and names the file].
% Fails when:
%   - this file moves. ensure_loaded resolves a relative path against the
%     directory of the file doing the loading, so a pure rename changes where
%     this points while showing no changed line in the diff. 3be9a17d moved it
%     from tests/ into tests/fixtures/ on 2026-08-27 and it pointed at
%     tests/engine/main.pl until 2026-09-03. The halt below is what makes the
%     next such move loud.
% Decides:
%   - a wrapper file rather than a -g goal on the run.sh command line,
%     because a -g goal runs only after every -s/-l file has ALREADY
%     finished loading, in EITHER order relative to -s on the command line
%     [measured 2026-08-18: `swipl -g "set_prolog_flag(autoload,false)" -s
%     FILE.pl` and the reverse order both see autoload=true inside FILE.pl's
%     own load-time directives; only a directive INSIDE the loaded file, or
%     the special initialization(_,main) goal, runs late enough or early
%     enough respectively]. engine/metta.pl has an immediate (non-initialization)
%     directive that needs the flag already set, so it has to be a directive,
%     and it has to run before engine/main.pl is reached.
%   - halt(2), not a thrown error. An exception out of a directive is caught by
%     the loader, printed as a warning, and load continues; the process then
%     reaches the toplevel with no engine and, with stdin open, blocks there
%     forever instead of exiting.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None
:- set_prolog_flag(autoload, false).
:- (   catch(ensure_loaded('../../engine/main.pl'), Error,
             ( print_message(error, Error), fail ))
   ->  true
   ;   format(user_error,
              "no_autoload_boot: engine/main.pl did not load.~n\c
               This file reaches it by a path relative to its OWN directory,~n\c
               so moving this file breaks it with no changed line to review.~n\c
               Fix the ensure_loaded path in ~w.~n",
              ['tests/fixtures/no_autoload_boot.pl']),
       halt(2)
   ).
