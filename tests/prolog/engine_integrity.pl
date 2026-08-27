% Purpose: check that no MeTTa equation in the shipped corpus can REPLACE a
%     predicate the ENGINE itself resolves, rather than shadowing it for the
%     space that wrote it.
% Assumes:
%     - the working directory is tests/prolog, which is where check.sh runs
%       every Prolog lane from
%     - a MeTTa equation `(= (f a b) body)` compiles to a Prolog head of arity
%       one more than the written one, the extra argument carrying the result
%       [source: engine/spaces.pl, spaces:throw_builtin_redefinition/2 computes
%       InputArity is Arity - 1 to say it back in MeTTa's terms]
%     - space_module('&self', M) names the module `&self` compiles into and
%       metta_engine_module/1 names the module the engine's own clauses are in.
%       Both are ASKED rather than written, so this follows the topology
%       instead of pinning one [source: engine/spaces.pl, engine/metta.pl]
% Guarantees:
%     - engine_integrity_report/0 parses every .metta file under examples/,
%       lib/ and tests/ with the engine's own parser, checks every equation in
%       them, and prints the two counts, so a run that examined nothing cannot
%       read like a clean one [measured 2026-08-19: 0 findings over 1,040
%       equations in 267 files]
%     - it reports an equation exactly when the module it compiles into is one
%       the ENGINE RESOLVES THROUGH, which is what makes the difference between
%       replacing a predicate and shadowing it. Before Phase 11 that module was
%       the engine's own and two shipped equations replaced a predicate
%       [measured 2026-08-19 on c7126f1, confirmed by running the file and
%       re-asking SWI, not inferred: loading
%       examples/ch07-control-flow/07-05-recursion/07-invertpeanoplus.metta took user:plus/3 from
%       imported_from(system) to a local definition and plus(1,2,X) from
%       answering 3 to failing; loading examples/ch20-extending-the-engine/20-02-metta-written-in-metta/04-minimal_metta.metta
%       took user:rule/3 from imported_from('$syspreds') to local]
%     - engine_integrity_selftest/0 proves both halves. It plants four
%       equations and asks the detector about the ENGINE's own module, where
%       the answer is known, and requires each to land on the side predicted:
%       that is the arity discrimination, which is the part a wrong detector
%       gets wrong. It then asks the SAME planted corpus about &self's module
%       and requires silence, which is the topology half. It then runs the
%       SAME scan over the real corpus against the engine's module and requires
%       it to still see something, which is the vacuity half [measured
%       2026-08-19: 2, plus/2 and rule/2]. Any one of the three alone passes
%       for a detector that has gone blind
% Fails when:
%     - an equation is added at RUN time through add-atom rather than written
%       in a file. Nothing static sees that, and the same rule applies to it.
%     - a name is assembled at run time from parts. Same blind spot.
%     - a file under _fixtures/ is deliberately malformed, so it is skipped by
%       name; an unparsable file anywhere else is raised rather than hidden
% Decides: nothing. This neither refuses nor repairs; it reports and exits
%     nonzero on a finding.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(filesex)).
:- ensure_loaded('../../engine/metta.pl').

%The modules the ENGINE resolves its own goals in: the module its clauses are
%in, and every module up that one's import chain. A clause asserted into any of
%them changes what the engine itself calls. A clause asserted anywhere else is
%a local shadow the engine never sees, which is the whole of what Phase 11
%bought and the reason this walk is COMPUTED rather than assumed: the day
%something re-bases a space's module onto the engine's chain, this says so.
engine_resolves_through(Module) :-
    metta_engine_module(Engine),
    module_or_ancestor(Engine, [], Module).

module_or_ancestor(Module, _, Module).
module_or_ancestor(Module, Seen, Ancestor) :-
    \+ memberchk(Module, Seen),
    import_module(Module, Parent),
    Parent \== Module,
    module_or_ancestor(Parent, [Module|Seen], Ancestor).

%A name the module already holds, by whatever route. built_in and nothing
%wider, which is the same test the Python door performs before registering an
%operation [source: bindings/python/metta/shim.pl, metta_py_probe_op_name/2].
module_holds(Module, Name, Arity, Owner) :-
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
%swallowing its syntax error: examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/_fixtures/imports/
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
corpus_equation(Dirs, File, Name, MettaArity) :-
    corpus_file(Dirs, File),
    filereader:read_metta_source(File, Source),
    parse_metta_source(Source, Forms),
    member(parsed(function, _, Form), Forms),
    equation_head(Form, Name, MettaArity).

%Parameterised by the module the equations compile into, which is what lets the
%selftest ask this exact predicate about a module where the answer is known.
collision(Module, Dirs, File, Name, MettaArity, Owner) :-
    corpus_equation(Dirs, File, Name, MettaArity),
    engine_resolves_through(Module),
    Arity is MettaArity + 1,
    module_holds(Module, Name, Arity, Owner).

collisions(Module, Dirs, Found) :-
    findall(Name/MettaArity-Owner-File,
            collision(Module, Dirs, File, Name, MettaArity, Owner), Found0),
    sort(Found0, Found).

corpus_scale(Dirs, Files, Equations) :-
    findall(File, corpus_file(Dirs, File), Fs), length(Fs, Files),
    findall(F-N/A, corpus_equation(Dirs, F, N, A), Es), length(Es, Equations).

corpus_directories(['../../examples', '../../lib', '../../tests']).

engine_integrity_report :-
    corpus_directories(Dirs),
    space_module('&self', Module),
    collisions(Module, Dirs, Found),
    length(Found, Count),
    corpus_scale(Dirs, Files, Equations),
    (   Count =:= 0
    ->  metta_engine_module(Engine),
        format("engine integrity: no shipped equation replaces an engine \c
                predicate, over ~w equations in ~w files~n", [Equations, Files]),
        format("  &self compiles into ~q; the engine resolves in ~q, which \c
                that module is below rather than on~n", [Module, Engine])
    ;   format("engine integrity: ~w of ~w shipped equation(s) in ~w files \c
                replace an engine predicate~n", [Count, Equations, Files]),
        forall(member(Name/MA-Owner-File, Found),
               format("  ~w with ~w arguments~t~34| replaces ~w:~w~t~58| ~w~n",
                      [Name, MA, Owner, Name, File])),
        %A GATE signals findings through its exit status.
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
planted("(= (metta-own-name $a) planted)", 'metta-own-name'/1, silent).

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
    %Half one, the DETECTOR: asked about the engine's own module, where every
    %answer is known, each planted equation has to land on the side predicted.
    metta_engine_module(Engine),
    collisions(Engine, [Dir], InEngine),
    findall(Name/MA, member(Name/MA-_-_, InEngine), Reported0),
    sort(Reported0, Reported),
    findall(Indicator-Side,
            ( planted(_, Indicator, Expected),
              ( memberchk(Indicator, Reported) -> Actual = report ; Actual = silent ),
              Actual \== Expected,
              Side = expected(Expected)-got(Actual) ), Wrong),
    %Half two, the TOPOLOGY: the same planted corpus, asked about the module
    %&self really compiles into, has to be silent. A detector that reported
    %there would be reporting a shadow as a replacement, and one that reported
    %nowhere would pass half one only by never looking.
    space_module('&self', SelfModule),
    collisions(SelfModule, [Dir], InSelf),
    %Half three, the SCAN: the real corpus, asked about the engine's module,
    %still yields the collisions it yielded before Phase 11. A report that is
    %clean because it parsed nothing and one that is clean because the
    %topology fixed it print the same line, and this is what tells them apart
    %[measured 2026-08-19: 2 findings, plus/2 and rule/2, the two the
    %migration was measured against].
    corpus_directories(Dirs),
    collisions(Engine, Dirs, InCorpus),
    length(InCorpus, CorpusSeen),
    (   Wrong == [], InSelf == [], CorpusSeen >= 1
    ->  length(Reported, N),
        format("engine integrity selftest: 4 planted equations, ~w reported \c
                against ~q and each on the side predicted, ~w against ~q, and \c
                the corpus scan still sees ~w against ~q~n",
               [N, Engine, 0, SelfModule, CorpusSeen, Engine])
    ;   ( CorpusSeen >= 1
          -> true
          ;  format("engine integrity selftest FAILED, the corpus scan sees \c
                     nothing even against ~q, so a clean report would mean \c
                     nothing~n", [Engine]) ),
        ( Wrong == []
          -> true
          ;  format("engine integrity selftest FAILED, the report does not \c
                     discriminate:~n"),
             forall(member(Indicator-Detail, Wrong),
                    format("  ~w  ~w~n", [Indicator, Detail])) ),
        ( InSelf == []
          -> true
          ;  format("engine integrity selftest FAILED, ~q is on the engine's \c
                     resolution path, so a shadow there is being reported as \c
                     a replacement:~n", [SelfModule]),
             forall(member(Finding, InSelf), format("  ~q~n", [Finding])) ),
        fail
    ).
