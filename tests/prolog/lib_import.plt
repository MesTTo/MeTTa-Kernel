% Purpose: static-import!, the fast path for a large data file. It converts a
%   .metta file to Prolog facts once, qcompiles them, and consults the .qlf on
%   every run after. Every one of those steps could silently produce or serve
%   the wrong data, and three of them did.
% Guarantees:
%   - the conversion goes through the engine's own reader, so a blank line, a
%     comment, a form spanning lines, an escaped quote and a run of spaces all
%     survive [tested: import_converts_through_the_reader]
%   - the facts land where the space actually reads them
%     [tested: import_facts_land_where_the_space_reads_them]
%   - a conversion that does not finish leaves NO output, so the next run
%     re-converts rather than serving half a file
%     [tested: import_removes_a_partial_conversion]
%   - a cache older than its source is not used
%     [tested: import_reconverts_a_stale_cache]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).
:- initialization(consult('../../lib/lib_import.pl')).

% One form per line, no comments, no escapes and no runs of spaces were the
% four assumptions the line-by-line converter made and the format does not
% carry. A blank line failed sub_string/5, which failed the whole conversion
% and left the partly written output CLOSED rather than removed: the next run
% qcompiled the truncated file and reported success with half the data, in
% binary, for good.
awkward_source("; a comment line, which is not a form\n\c
                (fact a 1)\n\c
                (fact b 2)\n\c
                \n\c
                (fact c 3)\n\c
                (fact\n\c
                   d 4)\n\c
                (text e \"a \\\"quoted\\\" value\")\n\c
                (spaced f \"two  spaces\")\n").

import_space('&plunit_import').

% A directory of its own per test, so a leftover cache cannot make the next
% test pass for the wrong reason. meta_predicate because the checks below are
% compiled into their unit's module, not into this file's.
:- meta_predicate with_import_dir(+, +, 2).
with_import_dir(Stem, Source, Goal) :-
    tmp_file(import, Dir),
    make_directory(Dir),
    atomic_list_concat([Dir, '/', Stem, '.metta'], MettaFile),
    setup_call_cleanup(
        ( setup_call_cleanup(open(MettaFile, write, Out),
                             write(Out, Source),
                             close(Out)),
          asserta(user:working_dir(Dir)) ),
        call(Goal, Dir, Stem),
        ( retract(user:working_dir(Dir)),
          delete_directory_and_contents(Dir) )).

clear_import_space :-
    import_space(Space),
    clear_native_atoms(Space).

:- begin_tests(lib_import_conversion, [cleanup(clear_import_space)]).

test(import_converts_through_the_reader) :-
    awkward_source(Source),
    with_import_dir(data, Source, check_awkward_conversion).

check_awkward_conversion(_, Stem) :-
    import_space(Space),
    'static-import!'(Space, Stem, true),
    findall(Atom, 'get-atoms'(Space, Atom), Atoms),
    % Six forms, one comment and one blank line, and the two-line form is one
    % atom rather than two.
    assertion(length(Atoms, 6)),
    assertion(memberchk([fact, c, 3], Atoms)),
    assertion(memberchk([fact, d, 4], Atoms)),
    assertion(memberchk([text, e, "a \"quoted\" value"], Atoms)),
    assertion(memberchk([spaced, f, "two  spaces"], Atoms)),
    clear_import_space.

% The converter wrote '&self'(fact,a,1) into USER, while native atoms live in
% the storage module '$petta_atoms:&self'. Every clause loaded, nothing could
% read them, and the import reported success.
test(import_facts_land_where_the_space_reads_them) :-
    with_import_dir(where, "(fact a 1)\n", check_facts_are_readable).

check_facts_are_readable(Dir, Stem) :-
    import_space(Space),
    'static-import!'(Space, Stem, true),
    findall(V, match(Space, [fact, a, V], V, _), Values),
    assertion(Values == [1]),
    % And in the storage module, not in user.
    native_storage_module(Space, Module),
    functor(Head, Space, 3),
    assertion(( clause(Module:Head, true) )),
    assertion(\+ clause(user:Head, true)),
    atomic_list_concat([Dir, '/', Stem, '.pl'], PlFile),
    assertion(exists_file(PlFile)),
    clear_import_space.

:- end_tests(lib_import_conversion).

:- begin_tests(lib_import_cache, [cleanup(clear_import_space)]).

% A runnable cannot become an atom. The conversion refuses it, and what it has
% written so far must not survive, because "a .pl exists" is the branch the
% next run takes.
test(import_removes_a_partial_conversion) :-
    with_import_dir(bad, "(fact a 1)\n!(println! oops)\n", check_partial_removed).

check_partial_removed(Dir, Stem) :-
    import_space(Space),
    catch('static-import!'(Space, Stem, true), Error, true),
    assertion(Error = error(petta_static_import_form(_, _), _)),
    atomic_list_concat([Dir, '/', Stem, '.pl'], PlFile),
    assertion(\+ exists_file(PlFile)),
    findall(A, 'get-atoms'(Space, A), Atoms),
    assertion(Atoms == []).

% A cache older than the source answers from data the file no longer holds.
% The old branches asked only whether the cache EXISTED.
test(import_reconverts_a_stale_cache) :-
    with_import_dir(stale, "(fact a 1)\n", check_stale_cache).

check_stale_cache(Dir, Stem) :-
    import_space(Space),
    'static-import!'(Space, Stem, true),
    clear_import_space,
    atomic_list_concat([Dir, '/', Stem, '.metta'], MettaFile),
    atomic_list_concat([Dir, '/', Stem, '.pl'], PlFile),
    atomic_list_concat([Dir, '/', Stem, '.qlf'], QlfFile),
    % Rewrite the source and date it after both caches.
    setup_call_cleanup(open(MettaFile, write, Out),
                       write(Out, "(fact a 1)\n(fact b 2)\n"),
                       close(Out)),
    time_file(MettaFile, SourceTime),
    Older is SourceTime - 10,
    set_time_file(PlFile, [], [modified(Older)]),
    set_time_file(QlfFile, [], [modified(Older)]),
    assertion(\+ static_import_cache_fresh(MettaFile, QlfFile)),
    'static-import!'(Space, Stem, true),
    findall(A, 'get-atoms'(Space, A), Atoms),
    assertion(length(Atoms, 2)),
    clear_import_space.

:- end_tests(lib_import_cache).
