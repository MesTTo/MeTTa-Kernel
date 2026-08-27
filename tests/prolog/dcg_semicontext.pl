% Purpose: report every DCG rule of the Prolog files named on the command
%     line, separating a SEMICONTEXT head (`Head, PushBack --> Body`, the
%     notation that threads state implicitly) from an ordinary one, and report
%     which of the translator's hand-threaded difference-list predicates still
%     have ordinary clauses.
%
%     P2.20 asked whether engine/translator.pl's hand-threaded difference lists
%     should become DCGs with semicontext, the way Triska's lisprolog.pl threads
%     its state, and closed as REJECTED on a measurement: `listing/1` shows the
%     DCG expanding to `num_leaves(nil, [A|B], C) :- D is A+1, E=B, C=[D|E].`
%     where the hand version is `hand(nil, N0, N1) :- N1 is N0+1.`, so the
%     expansion adds head destructuring and two unification goals the hand
%     version does not have [measured 2026-08-18]. What the item owes is that
%     the measurement is not silently reversed, and this is what reads the
%     source for the test that owns that claim.
% Assumes:
%     - each named file READS with the default operator table. engine/
%       translator.pl does [measured 2026-08-21: 400 terms, no syntax error],
%       so the scan does not load the engine and cannot be affected by what a
%       load would define.
% Guarantees:
%     - the report is over TERMS rather than lines, so a `-->` inside a quoted
%       string is not counted. engine/translator.pl has two, in the tracer's
%       ansi_format templates
%       [tested: bindings/python/tests/repository/test_gate_completeness.py,
%       test_no_dcg_semicontext_threads_the_compilers_state; commit=54d6f0ddac3887cc04cdedcebdc37a53ad9625c1].
%     - one line per finding, each naming the file it came from, and nothing
%       else on standard output, so the caller parses it without a JSON
%       dependency and attributes every finding exactly.
% Fails when:
%     - a named file does not exist or does not read, which raises rather than
%       reporting an empty scan: an empty report would pass every assertion the
%       caller makes.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Paths),
    (   Paths == []
    ->  throw(error(existence_error(file, none), context(main/0, 'no file to scan')))
    ;   forall(member(Path, Paths), scan_file(Path))
    ).

scan_file(Path) :-
    setup_call_cleanup(open(Path, read, Stream),
                       read_all(Stream, Terms),
                       close(Stream)),
    length(Terms, Count),
    format("file ~w ~w~n", [Path, Count]),
    forall(( member(Term, Terms), Term = (Head --> _) ), report_dcg(Path, Head)),
    forall(( member(Term, Terms),
             clause_head(Term, Head),
             functor(Head, Name, Arity),
             threaded_name(Name) ),
           format("clause ~w ~w ~w~n", [Path, Name, Arity])).

read_all(Stream, Terms) :-
    read_term(Stream, Term, []),
    (   Term == end_of_file
    ->  Terms = []
    ;   Terms = [Term|Rest],
        read_all(Stream, Rest)
    ).

%A directive defines nothing and a DCG rule is reported by report_dcg/2
%instead, so neither is a clause head here.
clause_head(Term, _) :- nonvar(Term), ( Term = (:- _) ; Term = (_ --> _) ), !, fail.
clause_head((Head :- _), Head) :- !.
clause_head(Head, Head) :- callable(Head).

%The predicates P2.20 named as the candidates for conversion, plus the two
%entry points every other one threads through. Reported by NAME rather than by
%name and arity, so an unrelated argument change does not make this red while
%a conversion to a DCG still does: a converted predicate stops having ordinary
%clauses and starts appearing as a `-->` head.
threaded_name(translate_expr_dl).
threaded_name(translate_special_dl).
threaded_name(translate_args_dl).
threaded_name(translate_let_dl).
threaded_name(mbr_goal).

%A semicontext head is a comma term, which is what the notation compiles the
%pushback list from. Checked before the module qualification, because
%`Module:Head, PushBack` parses as the comma term too.
report_dcg(Path, Head) :-
    nonvar(Head),
    Head = (Front, _),
    !,
    dcg_name(Front, Name, Arity),
    format("dcg ~w semicontext ~w ~w~n", [Path, Name, Arity]).
report_dcg(Path, Head) :-
    dcg_name(Head, Name, Arity),
    format("dcg ~w plain ~w ~w~n", [Path, Name, Arity]).

dcg_name(Head, Name, Arity) :- nonvar(Head), Head = _:Inner, !,
                               functor(Inner, Name, Arity).
dcg_name(Head, Name, Arity) :- functor(Head, Name, Arity).
