% Purpose: build a real SWI installation minus library(thread),
%   library(time) and library(process), boot the engine in a child process on
%   it, and hand the transcript back to tests/prolog/suites/seams/platform_capabilities.plt.
% Assumes:
%   - THIS platform carries the three libraries, so there is something to take
%     away. reduced_platform_buildable/0 answers that, and every test that
%     needs a child is conditional on it.
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
% Fails when:
%   - loaded into a process that then loads the engine expecting a full
%     platform: nothing here changes THIS process's search paths, but the
%     child's boot file does, which is why it is a separate file.
% Owns resources:
%   - one temporary directory per run_reduced_platform/2 call, named for this
%     process, removed by that call whether the child succeeded or not
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(readutil)).
:- use_module(library(process)).

%The four files a WebAssembly SWI does not carry, by base name. thread_pool
%goes with thread because lib/lib_thread/lib_thread.pl imports both and a build with one
%and not the other is not a platform anybody ships.
reduced_platform_withheld('thread.pl').
reduced_platform_withheld('thread_pool.pl').
reduced_platform_withheld('time.pl').
reduced_platform_withheld('process.pl').

%Where SWI keeps the two directories the withheld files live in: library(lists)
%is in the main library directory and library(time) in the clib extension's.
reduced_platform_directory(library, Directory) :-
    reduced_platform_home(library(lists), Directory).
reduced_platform_directory(clib, Directory) :-
    reduced_platform_home(library(time), Directory).

reduced_platform_home(Spec, Directory) :-
    absolute_file_name(Spec, File,
                       [file_type(prolog), access(read), file_errors(fail)]),
    file_directory_name(File, Directory).

%Whether there is a full platform here to reduce. On a build that already
%lacks the libraries every test that needs a child is skipped rather than
%passing vacuously.
reduced_platform_buildable :-
    forall(member(Which, [library, clib]),
           reduced_platform_directory(Which, _)).

%!  run_reduced_platform(-Out:list, -Err:list) is det.
%
%   Boot the engine on the reduced platform and answer its two transcripts as
%   lists of strings, one per line.
run_reduced_platform(Out, Err) :-
    reduced_platform_root(Root),
    setup_call_cleanup(build_reduced_platform(Root),
                       boot_reduced_platform(Root, Out, Err),
                       remove_reduced_platform(Root)).

reduced_platform_root(Root) :-
    tmp_file(metta_reduced_platform, Base),
    current_prolog_flag(pid, Pid),
    format(atom(Root), '~w-~w', [Base, Pid]).

build_reduced_platform(Root) :-
    make_directory_path(Root),
    forall(member(Which, [library, clib]),
           ( reduced_platform_directory(Which, Real),
             directory_file_path(Root, Which, Farm),
             make_directory_path(Farm),
             mirror_reduced_directory(Real, Farm) )).

%A symlink per entry, except INDEX.pl, which is COPIED. The autoloader reads
%an index and then resolves its entries against the directory the index was
%found in, and it resolves a symlinked index against the directory the link
%POINTS AT, which is the real library and has everything.
mirror_reduced_directory(Real, Farm) :-
    directory_files(Real, Entries),
    forall(( member(Entry, Entries),
             \+ memberchk(Entry, ['.', '..']),
             \+ reduced_platform_withheld(Entry) ),
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
remove_reduced_platform(Root) :-
    forall(member(Which, [library, clib]),
           ( directory_file_path(Root, Which, Farm),
             ( exists_directory(Farm) -> empty_reduced_directory(Farm) ; true ),
             ( exists_directory(Farm) -> delete_directory(Farm) ; true ) )),
    empty_reduced_directory(Root),
    ( exists_directory(Root) -> delete_directory(Root) ; true ).

empty_reduced_directory(Directory) :-
    directory_files(Directory, Entries),
    forall(( member(Entry, Entries), \+ memberchk(Entry, ['.', '..']) ),
           ( directory_file_path(Directory, Entry, Path),
             catch(delete_file(Path), _, true) )).
