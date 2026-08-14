% Purpose: direct PlUnit coverage for translator control forms and branch
%   rewrites whose failures are difficult to localize through whole examples.
% Open Obligations:
%   To Do: Add build_branch/4, merge_branch_returns/3, and stream-rewrite
%     determinism cases from the engine review.
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(translator_hyperpose).

hyperpose_space('&plunit_hyperpose').

hyperpose_form("(= (plunit-dbl $x) (* $x 2))").
hyperpose_form("(= (plunit-viamap) (map-atom (1 2 3) plunit-dbl))").
hyperpose_form("(= (plunit-viahyper) (hyperpose ((plunit-viamap) (plunit-viamap))))").

add_hyperpose_form(Space, Text) :-
    sread(Text, Term),
    'add-atom'(Space, Term, true).

remove_hyperpose_form(Space, Text) :-
    sread(Text, Term),
    'remove-atom'(Space, Term, _).

setup_hyperpose :-
    retractall(silent(_)),
    assertz(silent(true)),
    hyperpose_space(Space),
    forall(hyperpose_form(Text), add_hyperpose_form(Space, Text)).

cleanup_hyperpose :-
    hyperpose_space(Space),
    forall(hyperpose_form(Text), remove_hyperpose_form(Space, Text)),
    retractall(silent(_)),
    assertz(silent(false)).

test(named_space_static_branches_use_calling_module,
     [setup(setup_hyperpose), cleanup(cleanup_hyperpose)]) :-
    hyperpose_space(Space),
    space_module(Space, Module),
    findall(Result,
            call_goals_in(Module, ['plunit-viahyper'(Result)]),
            Results),
    Results == [[2, 4, 6], [2, 4, 6]].

test(named_space_runtime_branches_use_calling_module,
     [setup(setup_hyperpose), cleanup(cleanup_hyperpose)]) :-
    hyperpose_space(Space),
    space_module(Space, Module),
    findall(Result,
            with_metta_module(
                Module,
                hyperpose_runtime([['plunit-viamap'], ['plunit-viamap']], Result)),
            Results),
    Results == [[2, 4, 6], [2, 4, 6]].

:- end_tests(translator_hyperpose).
