% Purpose: gate the packaged Ciao-style assertion side file against the live
%   engine, including a clean smoke and a planted violation collected as data.
% Guarantees:
%   - all four removal and translation funnels have external pred assertions.
%   - the declared package versions are the reviewed versions.
%   - a valid engine smoke emits no assrchk/1 findings, while the planted bad
%     call emits the expected calls finding
%     [tested: test_the_ciao_grade_collects_a_planted_assertion_violation_as_data;
%     commit=dcfc20be4933c19140ccb5759291401d13058301].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').
:- consult('../../ciao_grade.pl').
:- use_module(library(prolog_pack), [pack_property/2]).

:- begin_tests(ciao_grade).

test(the_ciao_grade_uses_the_reviewed_pack_versions) :-
    pack_property(assertions, version('0.0.1')),
    pack_property(rtchecks, version('0.0.1')),
    pack_property(xlibrary, version('0.0.2')).

test(the_external_side_file_covers_every_selected_engine_funnel) :-
    findall(Spec,
            ( member(Spec,
                     [ metta_remove_atom/3,
                       unstore_atom/3,
                       remove_equation/6,
                       translate_clause/3
                     ]),
              Spec = Name/Arity,
              functor(Head, Name, Arity),
              assertions:asr_head_prop(_, user, Head, _, pred, _, _, _)
            ),
            Covered),
    assertion(Covered == [ metta_remove_atom/3,
                           unstore_atom/3,
                           remove_equation/6,
                           translate_clause/3
                         ]).

test(the_ciao_grade_smoke_has_no_runtime_check_violations) :-
    ciao_grade_collect(ciao_grade_smoke, Findings),
    assertion(Findings == []).

test(test_the_ciao_grade_collects_a_planted_assertion_violation_as_data) :-
    ciao_grade_collect(ciao_grade_planted(42), Findings),
    assertion(Findings =
              [assrchk(error(calls,
                             user:ciao_grade_planted(42),
                             [_/instan(user:atm(42))-[]],
                             _,
                             _))]).

:- end_tests(ciao_grade).
