% Purpose: boot the engine in THIS process on a platform where
%   library(thread), library(time) and library(process) genuinely cannot be
%   found, then print one transcript line per platform question so the parent
%   suite can assert on them. Run as a child process by
%   tests/prolog/reduced_platform.pl; never loaded by a suite directly.
% Assumes:
%   - argv carries the two farm directories built by
%     reduced_platform:build_reduced_library/3, as `-- <library farm>
%     <clib farm> [silent]`, and the engine source is two directories above
%     this file
%   - the farms mirror SWI's library and clib extension directories by
%     symlink, minus thread.pl, thread_pool.pl, time.pl and process.pl, and
%     carry a COPIED INDEX.pl rather than a symlinked one, so the autoloader
%     resolves an index entry against the farm and finds nothing
%     [measured 2026-08-27: with INDEX.pl symlinked, SWI resolved
%     call_with_time_limit/2 to the real /usr/lib/swi-prolog tree and
%     (timeout 5 (+ 1 2)) answered 3 on a platform that was supposed to
%     have no library(time)]
% Guarantees:
%   - the four file_search_path/2 clauses that reach SWI's own library tree,
%     two under the `library` alias and two under `autoload`, are replaced by
%     the farms before any engine file loads, so absence is real rather than
%     mocked: exists_source/1 is false for all three and call_with_time_limit/2
%     is undefined in this process
%   - every line it prints begins with one of `platform`, `refusal`, `answer`
%     or `unexpected`, and the parent reads only those
% Fails when:
%   - loaded outside its child process. The retracts below would take SWI's
%     own library out of the search path of whatever loaded it.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- current_prolog_flag(argv, Argv),
   member(Arg, Argv),
   atom_concat('reduced-platform=', Root, Arg),
   !,
   atom_concat(Root, '/library', Farm),
   atom_concat(Root, '/clib', Clib),
   exists_directory(Farm),
   exists_directory(Clib),
   retract((user:file_search_path(library, X)
            :- system:'$ext_library_directory'(X))),
   retract(user:file_search_path(library, swi(library))),
   retract((user:file_search_path(autoload, Y)
            :- '$autoload':'$ext_library_directory'(Y))),
   retract(user:file_search_path(autoload, swi(library))),
   forall(member(Alias, [library, autoload]),
          ( assertz(user:file_search_path(Alias, Farm)),
            assertz(user:file_search_path(Alias, Clib)),
            forall(( '$autoload':'$ext_library_directory'(Dir),
                     \+ sub_atom(Dir, _, _, 0, '/clib') ),
                   assertz(user:file_search_path(Alias, Dir))) )).

%Loaded only after the paths above are in force, which is the whole point of
%this file: an engine consulted before them would find every library it wanted.
:- ensure_loaded('../../engine/metta.pl').

:- initialization(reduced_platform_report, main).

%One transcript line per question, and the answer to each is a WORD the parent
%matches rather than prose, with the engine's own message text after it so a
%refusal that stops naming its cost is visible in the failure.
reduced_platform_report :-
    forall(petta_platform(Capability, Status, Requires, _),
           format("platform ~w ~w ~q~n", [Capability, Status, Requires])),
    answer(plain, "!(+ 1 2)"),
    refusal(timeout, "!(timeout 5 (+ 1 2))"),
    refusal(hyperpose, "!(hyperpose ((+ 1 2) (+ 3 4)))"),
    refusal('hyperpose-computed', "!(let $xs ((+ 1 2)) (hyperpose $xs))"),
    refusal(import, "!(import! &self (library lib_thread))"),
    refusal(git, "!(git-import! \"https://example.invalid/x.git\")"),
    %LAST, and it has to be: a max-time pragma is a process-wide setting, so
    %once it is refused every later form is wrapped by the same bound and
    %refuses with the pragma's message rather than its own. Setting it back is
    %not available either, because the reset form would be wrapped too.
    refusal(pragma, "!(pragma! max-time 5)\n!(+ 1 2)").

%A form that must still work. Its answers prove the engine did not merely
%stop: a census that refused everything would pass the refusal checks alone.
answer(Label, Source) :-
    (   catch(metta_host_run_source(Source, '&self', [], Groups), Error, fail_with(Label, Error))
    ->  format("answer ~w ~q~n", [Label, Groups])
    ;   format("unexpected ~w answered nothing~n", [Label])
    ).

%A form that must refuse, and the message is part of the assertion: the
%parent checks it names the capability and the platform library.
refusal(Label, Source) :-
    (   catch(metta_host_run_source(Source, '&self', [], Groups),
              Error,
              ( message_to_string(Error, Text),
                one_line(Text, Line),
                format("refusal ~w ~w~n", [Label, Line]) ))
    ->  (   var(Groups)
        ->  true
        ;   format("unexpected ~w answered ~q instead of refusing~n",
                   [Label, Groups])
        )
    ;   format("unexpected ~w failed without refusing~n", [Label])
    ).

fail_with(Label, Error) :-
    message_to_string(Error, Text),
    one_line(Text, Line),
    format("unexpected ~w raised ~w~n", [Label, Line]),
    fail.

%A message that wraps stays one transcript line, because the parent reads
%lines.
one_line(Text, Line) :-
    split_string(Text, "\n", " \t", Parts),
    exclude(==(""), Parts, Kept),
    atomic_list_concat(Kept, ' ', Line).
