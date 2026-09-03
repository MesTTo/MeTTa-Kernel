% Purpose: prove the engine-owned &self and &metta roots cannot be cleared or
%   released through the lifecycle spine shared by every host binding.
% Guarantees:
%   - clear and release refuse both base spaces before changing their catalog,
%     typing, or arithmetic state, while ordinary spaces retain both lifecycle
%     operations [tested: base_space_lifecycle; commit=6229e43cb68cc3685360810d462d992874992f6c].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(base_space_lifecycle).

engine_owned_base_space('&self').
engine_owned_base_space('&metta').

catalog_size(Size) :-
    aggregate_all(count, 'get-atoms'('&metta', _), Size).

assert_base_space_refusal(Operation, Space, Goal) :-
    catch(( call(Goal), Outcome = accepted ), Error, Outcome = raised(Error)),
    Outcome = raised(error(
        permission_error(Operation, metta_base_space, Space),
        context(metta_assert_space_destructible/2, Remedy))),
    assertion(sub_atom(Remedy, _, _, _, 'caller''s own context space')),
    assertion(sub_atom(Remedy, _, _, _, 'named space')).

assert_engine_controls(CatalogSize) :-
    catalog_size(CatalogSize),
    with_output_to(
        string(_),
        filereader:process_metta_string('!(get-type 1)\n!(+ 1 2)', Results)),
    assertion(Results == ['Number', 3]).

cleanup_ordinary_spaces :-
    forall(member(Space, ['&base-clear-control', '&base-release-control']),
           catch(metta_release_space(Space), _, true)).

test(clearing_engine_owned_base_spaces_is_refused_without_damage) :-
    catalog_size(Before),
    forall(engine_owned_base_space(Space),
           assert_base_space_refusal(
               clear, Space, metta_host_clear_space(Space))),
    assert_engine_controls(After),
    assertion(After == Before).

test(releasing_engine_owned_base_spaces_is_refused_without_damage) :-
    catalog_size(Before),
    forall(engine_owned_base_space(Space),
           assert_base_space_refusal(
               release, Space, metta_release_space(Space))),
    assert_engine_controls(After),
    assertion(After == Before).

test(ordinary_spaces_still_clear_and_release,
     [cleanup(cleanup_ordinary_spaces)]) :-
    Clear = '&base-clear-control',
    Release = '&base-release-control',
    'add-atom'(Clear, [ordinary, clear], true),
    metta_host_clear_space(Clear),
    assertion(\+ 'get-atoms'(Clear, _)),
    'add-atom'(Release, [ordinary, release], true),
    space_module(Release, _),
    assertion(metta_exec_module_known(Release, _)),
    metta_release_space(Release),
    assertion(\+ metta_exec_module_known(Release, _)),
    assert_engine_controls(_).

:- end_tests(base_space_lifecycle).
