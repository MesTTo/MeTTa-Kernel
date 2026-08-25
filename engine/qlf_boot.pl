% Purpose: decide Quick Load Format freshness for the engine tree before
%   any engine file loads: purge every engine and lib .qlf when any source
%   is newer than any of them or when the .qlf set was written by a
%   different SWI version, so the boot that follows regenerates them under
%   qcompile(auto). Exports nothing and lives in its own module for
%   user-surface hygiene; note that ANY boot-content change, however
%   inert, can move a twin's pinned inference count by a few tens
%   through SWI's clause-indexing shape (the benchmark ledger records
%   inert facts moving counts non-monotonically the same way), which is
%   why twin budgets are pinned on the exact shipping tree [measured
%   2026-08-25: examples/basics/identity.metta reads 2838 without this
%   file loaded and 2878 with it, under source and .qlf boots alike,
%   with user-predicate count, the stamp file, and .qlf presence each
%   ruled out by A/B].
% Assumes:
%   - loaded with autoload possibly OFF (tests/no_autoload_boot.pl), so
%     only true builtins appear: no member/2, no max_list/2, no
%     library(readutil).
% Guarantees:
%   - an edit to ANY engine or lib source, unit files included, defeats
%     every .qlf on the next boot: SWI's own staleness check covers a
%     .qlf's immediate source only, and the engine's units are consulted
%     by umbrellas, so a unit edit leaves the umbrella's .qlf fresh by
%     mtime and would serve the OLD code [measured 2026-08-25: a fact
%     appended to engine/translator/lowering.pl was invisible on the next
%     boot until this purge ran].
%   - a read-only tree stays correct: delete_file failures are absorbed
%     and SWI falls back to source for absent .qlf.
% Decides:
%   - freshness is transitive and coarse, the whole set against the
%     newest source: a false purge costs one ~0.25s generating boot; a
%     false keep would run stale engine code under a green-looking gate.
:- module(petta_qlf_boot, []).

qlf_glob_files(Here, Pattern, Files) :-
    atom_concat(Here, '/../', Root),
    atom_concat(Root, Pattern, Glob),
    expand_file_name(Glob, Files).

qlf_member(F, [F|_]).
qlf_member(F, [_|T]) :- qlf_member(F, T).

qlf_files(Here, Files) :-
    findall(F, ( qlf_member(Pattern,
                            ['engine/*.qlf', 'engine/*/*.qlf',
                             'lib/*.qlf', 'lib/*/*.qlf']),
                 qlf_glob_files(Here, Pattern, Fs),
                 qlf_member(F, Fs) ),
            Files).

qlf_source_newest(Here, Newest) :-
    findall(T, ( qlf_member(Pattern,
                            ['engine/*.pl', 'engine/*/*.pl',
                             'engine/*.metta', 'engine/*.c',
                             'lib/*.pl', 'lib/*/*.pl']),
                 qlf_glob_files(Here, Pattern, Fs),
                 qlf_member(F, Fs),
                 catch(time_file(F, T), _, fail) ),
            Times),
    qlf_time_max(Times, 0, Newest).

qlf_time_max([], Acc, Acc).
qlf_time_max([T|Ts], Acc, Max) :-
    ( T > Acc -> qlf_time_max(Ts, T, Max) ; qlf_time_max(Ts, Acc, Max) ).

qlf_stamp_ok(StampFile) :-
    current_prolog_flag(version, V),
    catch(setup_call_cleanup(open(StampFile, read, In),
                             read(In, qlf_stamp(V)),
                             close(In)),
          _, fail).

qlf_write_stamp(StampFile) :-
    current_prolog_flag(version, V),
    catch(setup_call_cleanup(open(StampFile, write, Out),
                             format(Out, 'qlf_stamp(~w).~n', [V]),
                             close(Out)),
          _, true).

purge_stale_qlf :-
    prolog_load_context(directory, Here),
    qlf_files(Here, QlfFiles),
    atom_concat(Here, '/.qlf-stamp', StampFile),
    (   QlfFiles == []
    ->  true
    ;   qlf_stamp_ok(StampFile),
        qlf_source_newest(Here, Newest),
        forall(qlf_member(Q, QlfFiles),
               ( catch(time_file(Q, QT), _, QT = 0 ), QT >= Newest ))
    ->  true
    ;   forall(qlf_member(Q, QlfFiles),
               catch(delete_file(Q), _, true))
    ),
    qlf_write_stamp(StampFile).

:- purge_stale_qlf.
