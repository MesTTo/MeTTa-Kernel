% Purpose: entry point for the autoload=false example-corpus lane. Sets the
%   flag before engine/main.pl, and so engine/metta.pl, ever loads.
% Guarantees:
%   - after this loads, argv processing, backend loading and
%     load_metta_file/2 all behave exactly as when engine/main.pl is the -s
%     file directly: this only adds one directive ahead of
%     ensure_loaded('../engine/main.pl'), so main.pl's own
%     initialization(main, main) still reads current_prolog_flag(argv, _)
%     the normal way, which is what run.sh's NO_AUTOLOAD=1 branch relies on
%     [measured 2026-08-18: NO_AUTOLOAD=1 sh test.sh, 200/200 examples/].
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
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None
:- set_prolog_flag(autoload, false).
:- ensure_loaded('../engine/main.pl').
