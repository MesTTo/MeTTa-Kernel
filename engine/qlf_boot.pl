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
%   2026-08-25: examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/01-identity.metta reads 2838 without this
%   file loaded and 2878 with it, under source and .qlf boots alike,
%   with user-predicate count, the stamp file, and .qlf presence each
%   ruled out by A/B].
% Assumes:
%   - loaded with autoload possibly OFF (tests/fixtures/no_autoload_boot.pl), so
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
%     and SWI falls back to source for absent .qlf
%     [assumed: exercised only by inspection of the catch sites below and
%     SWI's own '$qlf_file' fallback; no lane boots a read-only checkout;
%     commit=a7db7299e025b17618cf22d5fe18ad3e9b2f64b1].
%   - the engine reads its own sources and writes its own output as UTF-8
%     whatever the ambient locale says, and a .qlf set compiled under a
%     different encoding is purged rather than served
%     [tested: tests/shell/test_engine_text_encoding.sh; commit=bdb032a457597ef3b4a1e0d872f66f76bad362e4].
% Decides:
%   - freshness is transitive and coarse, the whole set against the
%     newest source: a false purge costs one ~0.25s generating boot; a
%     false keep would run stale engine code under a green-looking gate.
%   - the engine's text encoding is its own, not the operator's: sources,
%     the MeTTa corpus and the verdict marks are UTF-8 by construction, so
%     a C locale gets UTF-8 output it may render as mojibake rather than
%     an ASCII stream that escapes the marks the corpus greps for.
:- module(metta_qlf_boot, []).

%The engine's text encoding is UTF-8 by construction, not by locale. Six
%engine and lib sources carry non-ASCII content (the test verdict marks in
%metta/runtime.pl among them) and the whole MeTTa corpus is UTF-8, but SWI
%derives its default file encoding from setlocale(), so a boot with LANG
%unset reads those bytes as invalid and compiles each one to U+FFFD. The
%artifact then OUTLIVES the locale: the .qlf set is written with the
%replaced atoms, its mtime is newer than every source, and every later boot
%under a correct locale loads the poisoned compile and prints three
%replacement characters where the check mark belongs [measured 2026-08-26:
%one `LC_ALL=C swipl -s engine/main.pl` boot on a purged tree, then an
%ordinary run of examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/01-measure.metta, which read `. \357\277\275 x3`
%against the source's intact `. \342\234\205`; sixteen verdict lines and
%the whole pytest example lane failed on artifacts alone]. Three files
%already carried their own `:- encoding(utf8).`, which is the same fix
%applied one file at a time; this is that fix at the boot, where it covers
%every file including the ones a later commit adds.
:- set_prolog_flag(encoding, utf8).

%The standard streams take the same pinning, because an ASCII output stream
%does not fail, it ESCAPES: the same run under LC_ALL=C with a CORRECT .qlf
%printed the six-character escape backslash-u-2-7-0-5 where test.sh and the
%pytest example lane grep for the mark itself, so the corpus's own verdict
%scan reads every passing check as absent. A host that hands the engine a
%stream it may not reconfigure keeps its own, which is why the failure is
%absorbed rather than aborting a boot.
%
%This file stays pure ASCII on purpose: it is READ before the flag it sets
%takes effect, so a non-ASCII character here would be the one thing the fix
%cannot protect.
:- catch(( set_stream(user_output, encoding(utf8)),
           set_stream(user_error, encoding(utf8)) ), _, true).

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

%The stamp carries the ENCODING beside the version, because the two spoil a
%.qlf set the same way and neither shows up in an mtime: a set compiled
%while the flag read something other than utf8 holds replacement characters
%for every non-ASCII atom, and its files are newer than every source. Both
%are read back by unification against the live values, so a set written
%before this field existed carries a one-argument term, fails to unify, and
%is purged once - which is how a tree already poisoned repairs itself on its
%next boot rather than needing a hand purge.
qlf_stamp_ok(StampFile) :-
    current_prolog_flag(version, V),
    current_prolog_flag(encoding, Enc),
    catch(setup_call_cleanup(open(StampFile, read, In),
                             read(In, qlf_stamp(V, Enc)),
                             close(In)),
          _, fail).

%Written ONLY when absent or wrong, and atomically (a sibling of the
%boot may be reading it at any moment: the lane runs 32 engine boots at
%once). The first cut truncate-rewrote the stamp on every boot, so a
%concurrent reader could catch it mid-truncate, fail the check, and
%purge the whole .qlf set while its siblings were mid-load: one twin in
%a ten-round lane died with Unknown procedure: metta_symbol_writable/1
%out of a half-regenerated engine, and 129 twins picked up one-round
%count outliers from mixed source-and-qlf boots [measured 2026-08-25,
%tools/twin_coverage.py --observe --rounds 10]. rename/2 is atomic on
%POSIX, so a reader now sees the old stamp or the new one, never a
%partial; and an unchanged stamp is never rewritten, so the steady
%state has no write at all.
qlf_write_stamp(StampFile) :-
    (   qlf_stamp_ok(StampFile)
    ->  true
    ;   current_prolog_flag(version, V),
        current_prolog_flag(encoding, Enc),
        atom_concat(StampFile, '.tmp', TmpFile),
        catch(( setup_call_cleanup(open(TmpFile, write, Out),
                                   format(Out, 'qlf_stamp(~w, ~q).~n', [V, Enc]),
                                   close(Out)),
                rename_file(TmpFile, StampFile) ),
              _, true)
    ).

%The recovery door main.pl opens on a failed load: purge everything so
%the retry runs from source, whatever state a torn artifact left.
purge_all_qlf :-
    (   qlf_boot_directory(Here)
    ->  qlf_files(Here, QlfFiles),
        forall(qlf_member(Q, QlfFiles), catch(delete_file(Q), _, true))
    ;   true
    ).

:- dynamic qlf_boot_directory/1.

purge_stale_qlf :-
    prolog_load_context(directory, Here),
    (   qlf_boot_directory(Here) -> true
    ;   assertz(qlf_boot_directory(Here))
    ),
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
