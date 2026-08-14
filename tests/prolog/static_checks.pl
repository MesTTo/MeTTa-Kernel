% Purpose: run SWI's source checks after compiling representative MeTTa code.
% Guarantees:
%   - The driver runs the four reviewed library(check) predicates and check/0
%     after a function with control flow has been compiled.
%   - var_branches warnings are fatal for repository engine sources without
%     attributing warnings from SWI's own libraries to the repository.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(check)).
:- initialization(main, main).

main :-
    consult('../../src/metta.pl'),
    check_project_var_branches,
    retractall(silent(_)),
    assertz(silent(true)),
    representative_source(Source),
    process_metta_string(Source, [3]),
    list_trivial_fails,
    list_redefined,
    list_void_declarations,
    list_autoload,
    check.

check_project_var_branches :-
    setup_call_cleanup(
        style_check(+var_branches),
        forall(engine_source(Source), load_files(Source, [if(true)])),
        style_check(-var_branches)).

engine_source('../../src/ext_points.pl').
engine_source('../../src/parser.pl').
engine_source('../../src/translator.pl').
engine_source('../../src/specializer.pl').
engine_source('../../src/filereader.pl').
engine_source('../../lib/lib_gitimport.pl').
engine_source('../../src/spaces.pl').
engine_source('../../src/tracer.pl').
engine_source('../../src/metta.pl').

representative_source("
(= (static-check-inc $x) (+ $x 1))
(= (static-check-choose $x)
   (if (> $x 0) (static-check-inc $x) 0))
!(static-check-choose 2)").
