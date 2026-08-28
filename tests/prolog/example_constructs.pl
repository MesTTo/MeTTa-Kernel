% Purpose: print the language constructs each MeTTa file uses, read through the
%   engine's own parser and filtered against the engine's own vocabulary, so
%   the cumulative-introduction lane and the engine agree on what a construct
%   is. Run by tests/checks/check_cumulative_syntax.py.
% Assumes:
%   - argv holds one or more .metta paths, or the single flag --vocabulary,
%     and the working directory is tests/prolog/ (check.sh's convention for
%     every Prolog gate script), so a path is written relative to it
% Guarantees:
%   - one `FILE<TAB>CONSTRUCT` line per distinct construct in each file,
%     sorted, so the reader gets a set rather than a bag
%   - a construct is a name the ENGINE publishes, builtin_fun/1 or
%     metta_special_form_head/1, plus `!`; a program's own function names are
%     not constructs and are not printed
%   - --vocabulary prints `?VOCABULARY<TAB>NAME` for every such name, so the
%     lane can refuse a table row naming something the language does not have
%   - a file that cannot be parsed prints `FILE<TAB>?PARSE-ERROR` rather than
%     nothing, because silence would read as "uses no constructs" and let the
%     lane pass a file it never inspected
%   - the engine is loaded but nothing in the file RUNS: only
%     parse_metta_source/2 is called, so a scan costs a parse and cannot
%     mutate a space
%     [tested: test_the_scanner_reports_a_parse_error_rather_than_silence]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(readutil)).
:- initialization(main, main).

main :-
    %The arguments are read BEFORE argv is replaced, because the engine reads
    %argv while it LOADS to decide whether to read the seats' control files
    %and the vocabulary below has to include the builtins a seat registers.
    %Without the token this scanner boots the pure kernel and reports py-atom
    %and its six siblings as rows in tests/data/syntax_introductions.txt that
    %the engine does not publish, which is a fact about the boot rather than
    %about the table.
    current_prolog_flag(argv, Argv),
    set_prolog_flag(argv, [extensions]),
    consult('../../engine/qlf_boot.pl'),
    consult('../../engine/metta.pl'),
    metta_host_set_silent(true),
    (   Argv == ['--vocabulary']
    ->  forall(vocabulary(Name), format("?VOCABULARY\t~w~n", [Name]))
    ;   forall(member(File, Argv), scan(File))
    ),
    halt(0).

%The two halves of the language's head vocabulary, asked SEPARATELY because
%neither answers for the other: builtin_fun/1 does not know `if`, `case`,
%`collapse` or `quote`, which the translator owns, and the special-form
%service does not know `+`, `<` or the `#`-prefixed arithmetic family. Asking
%only fun/1 for a head's meaning has produced 723 false findings in this tree
%before [source: engine/ext_points.pl kind(metta_special_form_head/1, service)].
%
%`!` is the third case and is not a head at all: the parser records the
%runnable prefix as the form's KIND, so it is emitted from there. It is a
%construct a reader has to be taught like any other, which is why it is in the
%vocabulary rather than filtered out of it.
vocabulary(Name) :-
    findall(N, ( builtin_fun(N) ; metta_special_form_head(N) ), Names0),
    sort(['!'|Names0], Names),
    member(Name, Names).

scan(File) :-
    (   catch(constructs(File, Names), _, fail)
    ->  forall(member(Name, Names), format("~w\t~w~n", [File, Name]))
    ;   format("~w\t?PARSE-ERROR~n", [File])
    ).

constructs(File, Sorted) :-
    read_file_to_string(File, Source, [encoding(utf8)]),
    parse_metta_source(Source, Forms),
    findall(N, vocabulary(N), Vocabulary),
    findall(Name,
            ( form_head(Forms, Name), memberchk(Name, Vocabulary) ),
            Names),
    sort(Names, Sorted).

form_head(Forms, Name) :-
    member(Form, Forms),
    parsed_form_parts(Form, Kind, _, Term),
    (   Kind == runnable, Name = '!'
    ;   head(Term, Name)
    ).

% Every head position anywhere in the term, including nested ones: a reader
% meets `(if (== $x 1) ...)` and has to know both `if` and `==`.
%
% The nonvar/1 guard is load-bearing rather than defensive. A parsed form
% holds real Prolog variables for the source's `$x`, and an unbound one
% UNIFIES with [H|T]: without the guard the walk bound each variable to an
% ever-growing partial list and every file holding a variable ended in a
% resource error the caller could only report as a parse failure.
head(Term, Name) :-
    nonvar(Term),
    Term = [H|T],
    (   atom(H), Name = H
    ;   head(H, Name)
    ;   member(Arg, T), head(Arg, Name)
    ).
