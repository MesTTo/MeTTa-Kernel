% Purpose: report every MeTTa equation in the shipped corpus whose compiled
%     head collides with a predicate the ENGINE's own module already holds,
%     because such an equation does not shadow that predicate, it replaces it
%     for the rest of the process.
% Assumes:
%     - the working directory is tests/prolog, which is where check.sh runs
%       every Prolog lane from
%     - a MeTTa equation `(= (f a b) body)` compiles to a Prolog head of arity
%       one more than the written one, the extra argument carrying the result
%       [source: src/spaces.pl, throw_builtin_redefinition/2 computes
%       InputArity is Arity - 1 to say it back in MeTTa's terms]
%     - space_module('&self', M) names the module `&self` compiles into, so
%       asking it rather than writing `user` here is what makes this report
%       follow Phase 11 instead of quietly reporting nothing afterwards
%       [source: src/spaces.pl:231]
% Guarantees:
%     - engine_integrity_report/0 parses every .metta file under examples/,
%       lib/ and tests/ with the engine's own parser and names each colliding
%       equation with its file and the module that owns the predicate it takes
%       over [measured 2026-08-19: 2 collisions over 274 files]
%     - both findings were confirmed by running the file and re-asking SWI, not
%       inferred from the scan [measured 2026-08-19: loading
%       examples/functions/invertpeanoplus.metta took user:plus/3 from
%       imported_from(system) to a local definition and plus(1,2,X) from
%       answering 3 to failing; loading examples/libraries/minimal_metta.metta
%       took user:rule/3 from imported_from('$syspreds') to local]
%     - engine_integrity_selftest/0 fails unless the detector puts four planted
%       equations on the sides it predicts, so the report cannot pass by
%       examining nothing. It caught exactly that: the first version of this
%       file swallowed an existence error and reported all 279 files clean
% Fails when:
%     - an equation is added at RUN time through add-atom rather than written
%       in a file. Nothing static sees that, and the same collision applies.
%     - a name is assembled at run time from parts. Same blind spot.
%     - a file under _fixtures/ is deliberately malformed, so it is skipped by
%       name; an unparsable file anywhere else is raised rather than hidden
% Decides: nothing. This is a report; it neither refuses nor repairs.
% Open Obligations:
%   To Do: becomes a GATE at 0 findings, which is what Phase 11 delivers by
%     compiling `&self` into a module of its own rather than into the engine's
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(filesex)).
:- initialization(consult('../../src/metta.pl')).

%The predicate the whole report turns on. A MeTTa equation for a name the
%engine's module already holds is asserted INTO that module, so the engine
%loses the original rather than shadowing it. A named space is unaffected,
%because it compiles into a module of its own where the same definition is a
%local shadow [tested: spaces_builtin_override].
engine_owned(Name, Arity, Owner) :-
    space_module('&self', Module),
    functor(Head, Name, Arity),
    predicate_property(Module:Head, built_in),
    (   predicate_property(Module:Head, imported_from(Owner))
    ->  true
    ;   Owner = Module
    ).

%MeTTa arity is the written one; the compiled head carries one more argument
%for the result. A head written as a bare atom is the nullary case.
equation_head([=, Head|_], Name, MettaArity) :-
    (   is_list(Head), Head = [Name|Args]
    ->  length(Args, MettaArity)
    ;   atom(Head), Name = Head, MettaArity = 0
    ).

%A file under _fixtures/ is deliberately malformed input for a test that checks
%the engine's own error handling, so it is skipped BY NAME rather than by
%swallowing its syntax error: examples/integration/_fixtures/imports/
%import_error_broken.metta is one.
corpus_file(Dirs, File) :-
    member(Dir, Dirs),
    exists_directory(Dir),
    directory_member(Dir, File, [recursive(true), extensions([metta])]),
    \+ sub_atom(File, _, _, _, '/_fixtures/').

%No catch around the parse. The first version of this file had one, and it
%turned an existence error for space_module/2 into "no shipped equation takes
%over an engine predicate" across all 279 files: a green report that had
%examined nothing. A shipped file that does not parse is a finding, so it is
%raised rather than counted as clean.
collision(Dirs, File, Name, MettaArity, Owner) :-
    corpus_file(Dirs, File),
    read_metta_source(File, Source),
    parse_metta_source(Source, Forms),
    member(parsed(function, _, Form), Forms),
    equation_head(Form, Name, MettaArity),
    Arity is MettaArity + 1,
    engine_owned(Name, Arity, Owner).

collisions(Dirs, Found) :-
    findall(Name/MettaArity-Owner-File,
            collision(Dirs, File, Name, MettaArity, Owner), Found0),
    sort(Found0, Found).

corpus_directories(['../../examples', '../../lib', '../../tests']).

engine_integrity_report :-
    corpus_directories(Dirs),
    collisions(Dirs, Found),
    length(Found, Count),
    (   Count =:= 0
    ->  format("engine integrity: no shipped equation replaces an engine predicate~n")
    ;   format("engine integrity: ~w shipped equation(s) replace an engine predicate~n",
               [Count]),
        forall(member(Name/MA-Owner-File, Found),
               format("  ~w with ~w arguments~t~34| replaces ~w:~w~t~58| ~w~n",
                      [Name, MA, Owner, Name, File])),
        %A REPORT signals findings through its exit status, which is what makes
        %promoting this lane to a GATE a one-word edit in check.sh rather than
        %a rewrite [source: check.sh, "A REPORT that exits nonzero has FINDINGS,
        %which is its working state"].
        fail
    ).

%The report is a claim, so it is checked the way the evidence and reachability
%gates are. Four equations are planted in a throwaway directory: two that must
%be reported and two that must not. The arity pair is the one that matters,
%because MeTTa arity and Prolog arity differ by one and a detector that got
%that wrong would report the safe name and miss the dangerous one.
planted("(= (plus $a $b) planted)",        plus/2,        report).
planted("(= (plus $a) planted)",           plus/1,        silent).
planted("(= (b_setval $a) planted)",       b_setval/1,    report).
planted("(= (petta-own-name $a) planted)", 'petta-own-name'/1, silent).

engine_integrity_selftest :-
    tmp_file(engine_integrity, Base),
    atom_concat(Base, '_dir', Dir),
    make_directory(Dir),
    setup_call_cleanup(plant_corpus(Dir),
                       selftest_in(Dir),
                       delete_directory_and_contents(Dir)).

plant_corpus(Dir) :-
    directory_file_path(Dir, 'planted.metta', File),
    findall(Text, planted(Text, _, _), Texts),
    atomic_list_concat(Texts, '\n', Source),
    setup_call_cleanup(open(File, write, Out),
                       write(Out, Source),
                       close(Out)).

selftest_in(Dir) :-
    collisions([Dir], Found),
    findall(Name/MA, member(Name/MA-_-_, Found), Reported0),
    sort(Reported0, Reported),
    findall(Indicator-Side,
            ( planted(_, Indicator, Expected),
              ( memberchk(Indicator, Reported) -> Actual = report ; Actual = silent ),
              Actual \== Expected,
              Side = expected(Expected)-got(Actual) ), Wrong),
    (   Wrong == []
    ->  length(Reported, N),
        format("engine integrity selftest: 4 planted equations, ~w reported, each on the side predicted~n",
               [N])
    ;   format("engine integrity selftest FAILED, the report does not discriminate:~n"),
        forall(member(Indicator-Detail, Wrong),
               format("  ~w  ~w~n", [Indicator, Detail])),
        fail
    ).
