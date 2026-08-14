% Purpose: run SWI's source checks after compiling representative MeTTa code.
% Guarantees:
%   - The driver runs the four reviewed library(check) predicates and check/0
%     after a function with control flow has been compiled.
%   - Loading the engine enables var_branches warnings.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(check)).
:- initialization(main, main).

main :-
    style_check(+var_branches),
    consult('../../src/metta.pl'),
    retractall(silent(_)),
    assertz(silent(true)),
    representative_source(Source),
    process_metta_string(Source, [3]),
    list_trivial_fails,
    list_redefined,
    list_void_declarations,
    list_autoload,
    check.

representative_source("
(= (static-check-inc $x) (+ $x 1))
(= (static-check-choose $x)
   (if (> $x 0) (static-check-inc $x) 0))
!(static-check-choose 2)").
