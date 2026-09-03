% Purpose: build a real SWI installation minus the five provider sets
%   swipl-wasm omits: library(thread) with library(thread_pool), library(time),
%   library(process), library(crypto) and library(redis), and minus any EXTRA
%   libraries a test names; boot the engine in a child process on it and hand
%   the transcript back to tests/prolog/suites/seams/platform_capabilities.plt.
% Assumes:
%   - THIS platform carries the withheld libraries, so there is something to
%     take away. reduced_platform_buildable/1 answers that for a given extra
%     set, and every test that needs a child is conditional on it.
%   - swipl resolves library(Name) through user:file_search_path/2 for a
%     use_module and through the separate `autoload` alias for an autoloaded
%     call, and both have to be repointed or the second finds what the first
%     hid [measured 2026-08-27: with only the `library` alias repointed,
%     (timeout 5 (+ 1 2)) answered 3 and process_create/3 ran git;
%     commit=87d998c24278fc7f020ccb0e408ebcd9332b63eb]
% Guarantees:
%   - the farm is a symlink mirror, so building it copies one file (INDEX.pl)
%     and links the rest; cleanup unlinks the links and never follows one
%   - the child runs the SAME swipl this process runs
%     (current_prolog_flag(executable, _)) and the same engine sources
%   - stdout and stderr go to files rather than pipes, so a child that writes
%     more than a pipe buffer cannot deadlock the reader
%   - the default farm reproduces all five Node-seat absences, while SHA
%     hashing remains available from library(sha) [tested:
%     platform_capabilities_reduced:the_census_reports_all_five_absent,
%     platform_capabilities_reduced:sha_hashing_survives_without_crypto;
%     commit=59792b524568755a2fbfe1c5f7cdb571bd78a3bf]
% Fails when:
%   - loaded into a process that then loads the engine expecting a full
%     platform: nothing here changes THIS process's search paths, but the
%     child's boot file does, which is why it is a separate file.
% Owns resources:
%   - one temporary directory per run_reduced_platform/3 call, named for this
%     process, removed by that call whether the child succeeded or not
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(readutil)).
:- use_module(library(process)).
:- use_module(library(error), [must_be/2]).
%The gzip fixture the child imports, written on THIS side of the fork because
%a child without zlib could never produce one. Conditional, because a parent
%without zlib can still run every other reduced test: the fixture is then not
%written and the child skips the probe that needs it.
:- ( exists_source(library(zlib))
   -> use_module(library(zlib), [gzopen/3])
   ;  true
   ).

%The libraries a WebAssembly SWI does not carry, as library SPECS rather than
%base names. thread_pool goes with thread because lib/lib_thread/lib_thread.pl
%imports both and a build with one and not the other is not a platform anybody
%ships. This is the DEFAULT set and it stays that: a build missing one of
%these is a build somebody ships, where a build missing pcre or zlib is a
%hypothetical the tests construct one library at a time through the Extra
%argument of run_reduced_platform/3.
%
%Adding a name here is now the WHOLE change. It used to be half of one: the
%farm mirrored a hardcoded pair of directories, the main library and clib, and
%the child re-added every other real directory to the search path, so a
%withhold aimed anywhere else was silently ignored and the child resolved the
%library from the real installation. SWI keeps its libraries in several
%directories -- pcre in library/ext/pcre, zlib in library/ext/zlib, clpfd in
%library/clp -- so that filter covered four names and would have quietly
%passed a fifth [measured 2026-08-28: withholding pcre.pl changed nothing, the
%child booting clean and reading as evidence that it had]. The directories are
%derived from these libraries now, so a withhold either takes effect or the
%build refuses.
reduced_platform_withheld_library(thread).
reduced_platform_withheld_library(thread_pool).
reduced_platform_withheld_library(time).
reduced_platform_withheld_library(process).
reduced_platform_withheld_library(crypto).
reduced_platform_withheld_library(redis).

%The default set plus whatever a caller adds. A TEST names extra libraries to
%withhold; the default set stays what a WebAssembly build is missing, so the
%suite's existing child is unchanged and a new capability gets a child of its
%own rather than a wider default nobody asked for.
reduced_platform_withheld_libraries(Extra, Names) :-
    must_be(list, Extra),
    findall(Name, reduced_platform_withheld_library(Name), Default),
    append(Default, Extra, Both),
    sort(Both, Names).

%The same set by base name, which is how mirror_reduced_directory/3 skips them.
reduced_platform_withheld(Names, File) :-
    member(Name, Names),
    file_name_extension(Name, pl, File).

%Every distinct directory a withheld library lives in, paired with the farm
%subdirectory that will stand in for it. The tag is positional rather than
%meaningful: nothing outside this file and the manifest it writes needs to know
%which farm mirrors which real directory.
reduced_platform_directories(Names, Pairs) :-
    findall(Directory,
            ( member(Name, Names),
              reduced_platform_home(library(Name), Directory) ),
            Directories0),
    sort(Directories0, Directories),
    findall(farm(Tag, Real),
            ( nth1(Index, Directories, Real),
              format(atom(Tag), 'farm~d', [Index]) ),
            Pairs).

reduced_platform_home(Spec, Directory) :-
    absolute_file_name(Spec, File,
                       [file_type(prolog), access(read), file_errors(fail)]),
    file_directory_name(File, Directory).

%Whether there is a full platform here to reduce. On a build that already
%lacks the libraries every test that needs a child is skipped rather than
%passing vacuously. Every withheld library must resolve, not just one per
%directory, or a name whose file this platform does not have would be mirrored
%away from nothing and the child would read as reduced when it was not.
reduced_platform_buildable :-
    reduced_platform_buildable([]).

reduced_platform_buildable(Extra) :-
    reduced_platform_withheld_libraries(Extra, Names),
    forall(member(Name, Names),
           reduced_platform_home(library(Name), _)).

%!  run_reduced_platform(-Out:list, -Err:list) is det.
%!  run_reduced_platform(+Extra:list, -Out:list, -Err:list) is det.
%
%   Boot the engine on the reduced platform and answer its two transcripts as
%   lists of strings, one per line. Extra names libraries to withhold BESIDE
%   the default set, so one capability can be taken away at a time and the
%   engine's answer read on its own.
run_reduced_platform(Out, Err) :-
    run_reduced_platform([], Out, Err).

run_reduced_platform(Extra, Out, Err) :-
    reduced_platform_withheld_libraries(Extra, Names),
    reduced_platform_root(Root),
    setup_call_cleanup(build_reduced_platform(Root, Names),
                       boot_reduced_platform(Root, Out, Err),
                       remove_reduced_platform(Root)).

reduced_platform_root(Root) :-
    tmp_file(metta_reduced_platform, Base),
    current_prolog_flag(pid, Pid),
    format(atom(Root), '~w-~w', [Base, Pid]).

build_reduced_platform(Root, Names) :-
    make_directory_path(Root),
    reduced_platform_directories(Names, Pairs),
    forall(member(farm(Tag, Real), Pairs),
           ( directory_file_path(Root, Tag, Farm),
             make_directory_path(Farm),
             mirror_reduced_directory(Names, Real, Farm) )),
    write_reduced_manifest(Root, Pairs),
    write_reduced_fixtures(Root).

%The two source files the child imports, beside the farms it boots on. Both
%carry one equation apiece, so an import that lands answers a number and an
%import that is refused answers nothing: that is the difference between a
%capability the child lost and a load path it never had.
%
%The compressed one is written here because writing it needs the very library
%the child may be missing. A parent without zlib writes only the plain file
%and the child's compressed probe reports that it had nothing to read.
write_reduced_fixtures(Root) :-
    directory_file_path(Root, 'plain.metta', Plain),
    setup_call_cleanup(open(Plain, write, Out, [encoding(utf8)]),
                       format(Out, '(= (round-trip) 7)~n', []),
                       close(Out)),
    (   current_predicate(gzopen/3)
    ->  directory_file_path(Root, 'compressed.metta.gz', Gz),
        setup_call_cleanup(gzopen(Gz, write, GzOut),
                           ( set_stream(GzOut, encoding(utf8)),
                             format(GzOut, '(= (compressed-answer) 11)~n', []) ),
                           close(GzOut))
    ;   true
    ).

%The child cannot derive the farm list: it must not resolve library(thread) to
%find out where thread.pl lives, because the whole point is that it cannot. So
%the parent writes what it built, as terms the child reads before it touches a
%search path.
write_reduced_manifest(Root, Pairs) :-
    directory_file_path(Root, 'farms.pl', Manifest),
    setup_call_cleanup(
        open(Manifest, write, Stream, [encoding(utf8)]),
        forall(member(farm(Tag, Real), Pairs),
               ( directory_file_path(Root, Tag, Farm),
                 format(Stream, '~q.~n', [reduced_farm(Farm, Real)]) )),
        close(Stream)).

%A symlink per entry, except INDEX.pl, which is COPIED. The autoloader reads
%an index and then resolves its entries against the directory the index was
%found in, and it resolves a symlinked index against the directory the link
%POINTS AT, which is the real library and has everything.
mirror_reduced_directory(Names, Real, Farm) :-
    directory_files(Real, Entries),
    forall(( member(Entry, Entries),
             \+ memberchk(Entry, ['.', '..']),
             \+ reduced_platform_withheld(Names, Entry) ),
           mirror_reduced_entry(Real, Farm, Entry)).

mirror_reduced_entry(Real, Farm, 'INDEX.pl') :- !,
    directory_file_path(Real, 'INDEX.pl', From),
    directory_file_path(Farm, 'INDEX.pl', To),
    copy_file(From, To).
%A .qlf records the absolute path of the .pl it was compiled from, so a farm
%that mixes linked .qlf with linked .pl gives SWI two identities for one
%library and it refuses the second with "module already loaded from"
%[measured 2026-08-27: apply.qlf and apply.pl, six cascading permission
%errors]. Source only, and the reduced boot pays one uncached compile.
mirror_reduced_entry(_, _, Entry) :-
    file_name_extension(_, qlf, Entry), !.
mirror_reduced_entry(Real, Farm, Entry) :-
    directory_file_path(Real, Entry, From),
    directory_file_path(Farm, Entry, To),
    link_file(From, To, symbolic).

boot_reduced_platform(Root, Out, Err) :-
    current_prolog_flag(executable, Swipl),
    reduced_platform_boot_file(Boot),
    directory_file_path(Root, 'stdout', OutFile),
    directory_file_path(Root, 'stderr', ErrFile),
    format(atom(RootArg), 'reduced-platform=~w', [Root]),
    setup_call_cleanup(
        ( open(OutFile, write, OutStream), open(ErrFile, write, ErrStream) ),
        ( process_create(Swipl,
                         ['-q', '-g', true, '-t', halt, Boot,
                          '--', silent, RootArg],
                         [ stdout(stream(OutStream)),
                           stderr(stream(ErrStream)),
                           process(Pid) ]),
          process_wait(Pid, _) ),
        ( close(OutStream), close(ErrStream) )),
    reduced_platform_lines(OutFile, Out),
    reduced_platform_lines(ErrFile, Err).

reduced_platform_boot_file(Boot) :-
    source_file(reduced_platform_boot_file(_), Here),
    file_directory_name(Here, Directory),
    directory_file_path(Directory, 'reduced_platform_boot.pl', Boot).

reduced_platform_lines(File, Lines) :-
    read_file_to_string(File, Text, [encoding(utf8)]),
    split_string(Text, "\n", "\r", Split),
    exclude(==(""), Split, Lines).

%delete_file/1 on a symlink unlinks the LINK; nothing here follows one into
%SWI's own library, which a recursive delete would.
%
%What was BUILT rather than what was expected: this named the same hardcoded
%pair the builder did, so a farm under any other name survived and left the
%root non-empty, which delete_directory/1 then refused. Reading the root back
%also cleans up after a build that failed part way, where a derived list would
%name farms that were never created and miss ones that were.
remove_reduced_platform(Root) :-
    ( exists_directory(Root)
    ->  directory_files(Root, Entries),
        forall(( member(Entry, Entries),
                 \+ memberchk(Entry, ['.', '..']),
                 directory_file_path(Root, Entry, Farm),
                 exists_directory(Farm),
                 \+ read_link(Farm, _, _) ),
               ( empty_reduced_directory(Farm),
                 catch(delete_directory(Farm), _, true) )),
        empty_reduced_directory(Root),
        ( exists_directory(Root) -> delete_directory(Root) ; true )
    ;   true
    ).

empty_reduced_directory(Directory) :-
    directory_files(Directory, Entries),
    forall(( member(Entry, Entries), \+ memberchk(Entry, ['.', '..']) ),
           ( directory_file_path(Directory, Entry, Path),
             catch(delete_file(Path), _, true) )).
