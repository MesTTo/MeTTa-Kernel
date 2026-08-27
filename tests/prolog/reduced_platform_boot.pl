% Purpose: boot the engine in THIS process on a platform where
%   library(thread), library(time) and library(process) genuinely cannot be
%   found, then print one transcript line per platform question so the parent
%   suite can assert on them. Run as a child process by
%   tests/prolog/reduced_platform.pl; never loaded by a suite directly.
% Assumes:
%   - argv carries `reduced-platform=<root>` for the root
%     reduced_platform:build_reduced_platform/2 built, holding one farm per
%     directory a withheld library lives in, and the engine source is two
%     directories above this file
%   - the farms mirror SWI's library and clib extension directories by
%     symlink, minus thread.pl, thread_pool.pl, time.pl and process.pl, and
%     carry a COPIED INDEX.pl rather than a symlinked one, so the autoloader
%     resolves an index entry against the farm and finds nothing
%     [measured 2026-08-27: with INDEX.pl symlinked, SWI resolved
%     call_with_time_limit/2 to the real /usr/lib/swi-prolog tree and
%     (timeout 5 (+ 1 2)) answered 3 on a platform that was supposed to
%     have no library(time); commit=87d998c24278fc7f020ccb0e408ebcd9332b63eb]
% Guarantees:
%   - the four file_search_path/2 clauses that reach SWI's own library tree,
%     two under the `library` alias and two under `autoload`, are replaced by
%     the farms before any engine file loads, so absence is real rather than
%     mocked: exists_source/1 is false for all three and call_with_time_limit/2
%     is undefined in this process
%   - every line it prints begins with one of `platform`, `refusal`, `answer`
%     or `unexpected`, and the parent reads only those
%   - a probe for a capability this child HAS must answer and one for a
%     capability it lost must refuse; either way round the other way prints
%     `unexpected`, so one report serves every withheld set
% Fails when:
%   - loaded outside its child process. The retracts below would take SWI's
%     own library out of the search path of whatever loaded it.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The farms come from the manifest the parent wrote, not from names spelled
%here. This read two, `library` and `clib`, and re-added every OTHER real
%directory to both aliases, so a library withheld from any third directory --
%pcre, zlib and clpfd each live in one -- was resolved from the real
%installation and the withhold did nothing at all. Reading what the parent
%actually mirrored is what makes the reduction match the withheld list.
%
%The child cannot compute this itself: finding where thread.pl lives means
%resolving library(thread), which is the very thing it must not be able to do.
:- dynamic reduced_platform_child_root/1.

:- current_prolog_flag(argv, Argv),
   member(Arg, Argv),
   atom_concat('reduced-platform=', Root, Arg),
   !,
   assertz(reduced_platform_child_root(Root)),
   atom_concat(Root, '/farms.pl', Manifest),
   exists_file(Manifest),
   consult(Manifest),
   findall(Farm-Real, reduced_farm(Farm, Real), Farms),
   Farms \== [],
   forall(member(Farm-_, Farms), exists_directory(Farm)),
   retract((user:file_search_path(library, X)
            :- system:'$ext_library_directory'(X))),
   retract(user:file_search_path(library, swi(library))),
   retract((user:file_search_path(autoload, Y)
            :- '$autoload':'$ext_library_directory'(Y))),
   retract(user:file_search_path(autoload, swi(library))),
   forall(member(Alias, [library, autoload]),
          ( forall(member(Farm-_, Farms), assertz(user:file_search_path(Alias, Farm))),
            %Every real directory the parent did NOT mirror stays reachable; a
            %mirrored one must not, or the farm is bypassed and the withhold is
            %undone by the very list meant to preserve the rest of the platform.
            forall(( '$autoload':'$ext_library_directory'(Dir),
                     \+ memberchk(_-Dir, Farms) ),
                   assertz(user:file_search_path(Alias, Dir))) )),
   %The autoload index is a CACHE of absolute paths, and it was already built
   %by the time the paths above changed: member/2 three lines up is itself an
   %autoloaded call, and load_library_index_p/1 reads every INDEX.pl once and
   %then answers from library_index/3 for the next sixty seconds
   %(boot/autoload.pl:250-267). So a withheld library stayed reachable at CALL
   %time through the index's absolute path even though use_module/1 could no
   %longer resolve it, and this file's own guarantee that
   %call_with_time_limit/2 is undefined here was false [measured 2026-08-28:
   %with pcre and zlib withheld and no reset, call_with_time_limit/2 and
   %concurrent_and/2 both RESOLVED and re_compile/3 ran; with the reset all
   %three raise source_sink on the farm path]. Dropping the three cached
   %facts makes the next autoload rebuild the index from the farms, which is
   %what makes the absence real rather than only visible to the loader.
   retractall('$autoload':library_index(_, _, _)),
   retractall('$autoload':autoload_directories(_)),
   retractall('$autoload':index_checked_at(_)).

%Loaded only after the paths above are in force, which is the whole point of
%this file: an engine consulted before them would find every library it wanted.
:- ensure_loaded('../../engine/metta.pl').

:- initialization(reduced_platform_report, main).

%One transcript line per question, and the answer to each is a WORD the parent
%matches rather than prose, with the engine's own message text after it so a
%refusal that stops naming its cost is visible in the failure.
reduced_platform_report :-
    forall(metta_platform(Capability, Status, Requires, _),
           format("platform ~w ~w ~q~n", [Capability, Status, Requires])),
    answer(plain, "!(+ 1 2)"),
    %These four capabilities are absent in EVERY child this harness builds,
    %because the default withheld set is what takes them away, so each of
    %these is a refusal outright rather than a capability_probe/3. The git one
    %has to stay that way: its present-branch would start a clone against the
    %network, which is not something a test may do on a build that can.
    refusal(timeout, "!(timeout 5 (+ 1 2))"),
    refusal(hyperpose, "!(hyperpose ((+ 1 2) (+ 3 4)))"),
    refusal('hyperpose-computed', "!(let $xs ((+ 1 2)) (hyperpose $xs))"),
    refusal(import, "!(import! &self (library lib_thread))"),
    refusal(git, "!(git-import! \"https://example.invalid/x.git\")"),
    %The capabilities a child may or may not have, one probe per guard point.
    %Each says what it expects from the census rather than from the caller, so
    %the same report serves the run that withholds the library and the runs
    %that do not, and a guard that stops firing shows up as an answer where a
    %refusal was due.
    capability_probe(regex, 'regex-library', "!(import! &self (library lib_regex))"),
    capability_probe(regex, 'regex-token',
                     "!(register-token! \"[A-Z][0-9]+\" tagged)\n\c
                      !(unregister-token! \"[A-Z][0-9]+\")"),
    capability_probe(regex, 'regex-import', "!(import_prolog_function re_replace)"),
    compressed_source_probe,
    fast_cache_probe,
    %A source load with no cache anywhere near it, which is what a build
    %without the fast cache does for every load it is ever asked to do.
    child_fixture('plain.metta', Plain),
    format(string(RoundTrip), "!(import! &self \"~w\")\n!(round-trip)", [Plain]),
    answer('round-trip', RoundTrip),
    %LAST, and it has to be: a max-time pragma is a process-wide setting, so
    %once it is refused every later form is wrapped by the same bound and
    %refuses with the pragma's message rather than its own. Setting it back is
    %not available either, because the reset form would be wrapped too.
    refusal(pragma, "!(pragma! max-time 5)\n!(+ 1 2)").

%A fixture the parent wrote beside the farms, as an absolute path.
child_fixture(Name, Path) :-
    reduced_platform_child_root(Root),
    atomic_list_concat([Root, '/', Name], Path).

%A .gz program, which only a build with the compression capability can read.
%The parent writes the fixture because writing it needs the library the child
%may be missing; with no parent zlib there is no fixture and the child says so
%rather than probing a file that is not there.
compressed_source_probe :-
    child_fixture('compressed.metta.gz', Path),
    (   exists_file(Path)
    ->  format(string(Source),
               "!(import! &self \"~w\")\n!(compressed-answer)", [Path]),
        capability_probe('compressed-sources', compressed, Source)
    ;   format("platform compressed-sources unprobed no-fixture~n")
    ).

%The two host doors the fast cache is reached through, probed the way a
%binding reaches them rather than as MeTTa forms, because that is the only
%surface they have.
fast_cache_probe :-
    child_fixture('probe.fast', Path),
    capability_service('fast-cache', 'fast-save',
                       metta_host_save_fast(Path, '&self', Saved), Saved),
    capability_service('fast-cache', 'fast-load',
                       metta_host_load_fast(Path, '&self'), loaded).

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

%Which of the two a form is, decided by the CENSUS rather than by the caller.
%A capability this child has must answer and one it lost must refuse, so the
%same report serves every withheld set, and a guard that stopped firing prints
%an `unexpected` line instead of passing quietly.
capability_probe(Capability, Label, Source) :-
    (   metta_platform(Capability, absent, _, _)
    ->  refusal(Label, Source)
    ;   answer(Label, Source)
    ).

%The same question asked of a host SERVICE rather than of a MeTTa form,
%because the fast cache has no MeTTa spelling: a binding calls it directly.
%Goal answers Result where the capability holds and throws where it does not.
capability_service(Capability, Label, Goal, Result) :-
    catch(( call(Goal) -> Outcome = answered(Result) ; Outcome = failed ),
          Error,
          Outcome = refused(Error)),
    service_report(Capability, Label, Outcome).

service_report(Capability, Label, answered(Result)) :-
    (   metta_platform(Capability, absent, _, _)
    ->  format("unexpected ~w answered ~q instead of refusing~n", [Label, Result])
    ;   format("answer ~w ~q~n", [Label, Result])
    ).
service_report(_, Label, failed) :-
    format("unexpected ~w failed without refusing~n", [Label]).
service_report(Capability, Label, refused(Error)) :-
    message_to_string(Error, Text),
    one_line(Text, Line),
    (   metta_platform(Capability, absent, _, _)
    ->  format("refusal ~w ~w~n", [Label, Line])
    ;   format("unexpected ~w refused with ~w~n", [Label, Line])
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
