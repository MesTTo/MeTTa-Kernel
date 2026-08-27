% Purpose: the platform census and the refusals that read it, checked on this
%   platform and on a real one without library(thread), library(time) or
%   library(process).
% Guarantees:
%   - every declared capability's recorded status agrees with whether its
%     platform library resolves, so the census cannot claim a library the
%     build does not have [tested: the_census_agrees_with_what_resolves]
%   - a capability this build HAS refuses nothing, and a planted absence
%     refuses naming the form, the capability, the library and the cost
%     [tested: a_present_capability_refuses_nothing,
%     a_planted_absence_refuses_by_name_and_states_its_cost]
%   - the census is published as a host_service and exported, so a binding
%     reads it through the declared surface
%     [tested: the_census_is_a_published_host_service]
%   - on a build without the three libraries the engine loads without writing
%     one ERROR line, still evaluates, and every form that rests on an absent
%     capability refuses by name
%     [tested: the_engine_boots_silently_without_the_three_libraries,
%     a_reduced_build_still_evaluates,
%     a_bounded_form_refuses_by_name_when_deadlines_are_absent,
%     a_pragma_bound_refuses_by_name_when_deadlines_are_absent,
%     hyperpose_refuses_by_name_when_concurrency_is_absent,
%     a_library_that_declares_an_absent_capability_never_loads,
%     git_import_refuses_by_name_when_subprocess_is_absent;
%     commit=87d998c24278fc7f020ccb0e408ebcd9332b63eb]
% Fails when:
%   - this platform is itself missing one of the three. The reduced unit is
%     conditional on there being something to take away, and says so rather
%     than passing over a farm it could not build.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').
:- ensure_loaded(reduced_platform).

%The plant is written into the ENGINE's module by name. A bare assertz inside
%a plunit unit creates a private metta_platform_absent/1 in that unit's own
%module, where the census cannot see it, and every refusal test then passes
%vacuously by never refusing: measured here as `no_exception` on
%a_planted_absence_refuses_by_name_and_states_its_cost. This is the same trap
%engine/metta.pl records for its four shared registries.
plant_absent(Capability) :-
    metta_engine_module(Engine),
    assertz(Engine:metta_platform_absent(Capability)).

unplant_absent(Capability) :-
    metta_engine_module(Engine),
    retractall(Engine:metta_platform_absent(Capability)).

:- begin_tests(platform_capabilities).

test(the_census_agrees_with_what_resolves) :-
    findall(Capability-Status,
            metta_platform(Capability, Status, _, _),
            Rows),
    assertion(Rows \== []),
    forall(metta_platform(Capability, Status, Requires, Costs),
           ( assertion(( exists_source(Requires)
                       -> Status == present
                       ;  Status == absent )),
             assertion(( atom(Costs), Costs \== '' )) )),
    % The three the engine's own loads rest on, named so a row that
    % disappears is a decision rather than a silence.
    forall(member(Named, [concurrency, deadlines, subprocess]),
           assertion(memberchk(Named-_, Rows))).

test(a_present_capability_refuses_nothing) :-
    forall(metta_platform(Capability, present, _, _),
           metta_require_platform(plunit_probe, Capability)).

% The planted absence is the whole point: this box has all three, so without
% it the refusal path is never taken here. The reduced unit below takes it for
% real, in a child process with the libraries genuinely gone.
test(a_planted_absence_refuses_by_name_and_states_its_cost,
     [ setup(plant_absent(deadlines)),
       cleanup(unplant_absent(deadlines)),
       throws(error(metta_platform_required('(timeout N Expr)', deadlines,
                                            library(time), _), _)) ]) :-
    metta_require_platform('(timeout N Expr)', deadlines).

test(a_planted_absence_reads_back_as_absent,
     [ setup(plant_absent(deadlines)),
       cleanup(unplant_absent(deadlines)) ]) :-
    metta_platform(deadlines, Status, Requires, Costs),
    assertion(Status == absent),
    assertion(Requires == library(time)),
    assertion(sub_atom(Costs, _, _, _, 'timeout')).

test(a_planted_absence_names_its_cost_in_the_message,
     [ setup(plant_absent(subprocess)),
       cleanup(unplant_absent(subprocess)) ]) :-
    catch(metta_require_platform('git-import!', subprocess), Error, true),
    message_to_string(Error, Text),
    forall(member(Fragment, ["git-import!", "subprocess", "library(process)",
                             "starts a program"]),
           assertion(sub_string(Text, _, _, _, Fragment))).

test(metta_requires_refuses_a_capability_the_engine_does_not_declare,
     [ throws(error(existence_error(metta_platform_capability,
                                    plunit_no_such_capability), _)) ]) :-
    metta_requires(plunit_no_such_capability).

test(a_source_declaration_is_read_without_running_the_source) :-
    metta_source_declarations('../../lib/lib_thread/lib_thread.pl', Declarations),
    assertion(memberchk(requires(concurrency), Declarations)).

test(the_census_is_a_published_host_service) :-
    assertion(seam:kind(metta_platform/4, host_service)),
    metta_engine_module(Engine),
    module_property(Engine, exports(Exports)),
    assertion(memberchk(metta_platform/4, Exports)).

:- end_tests(platform_capabilities).

:- begin_tests(platform_capabilities_reduced).

:- dynamic reduced_platform_transcript/2.

%One child boot serves the whole unit. Memoized rather than run per test,
%because booting the engine on a source-only library farm costs seconds.
reduced_transcript(Out, Err) :-
    (   reduced_platform_transcript(Out0, Err0)
    ->  Out = Out0, Err = Err0
    ;   run_reduced_platform(Out0, Err0),
        assertz(reduced_platform_transcript(Out0, Err0)),
        Out = Out0, Err = Err0
    ).

%The transcript line that starts with Prefix, as a string. Fails when the
%child never printed one, which is what every test below is asserting about.
reduced_line(Prefix, Line) :-
    reduced_transcript(Out, _),
    once(( member(Line, Out), string_concat(Prefix, _, Line) )).

%A refusal names the form, the capability, the platform library and the cost.
%All four, because a refusal that names only the form is the interior
%existence error with better manners.
refusal_names(Label, Fragments) :-
    string_concat("refusal ", Label, Prefix),
    ( reduced_line(Prefix, Line) -> true
    ; reduced_transcript(Out, _),
      throw(error(plunit_no_refusal(Label, Out), _)) ),
    forall(member(Fragment, Fragments),
           assertion(sub_string(Line, _, _, _, Fragment))).

test(the_engine_boots_silently_without_the_three_libraries,
     [condition(reduced_platform_buildable)]) :-
    reduced_transcript(_, Err),
    % Not merely "no ERROR": the base engine wrote four ERROR pairs and four
    % Warnings here, and both go when the loads are guarded.
    assertion(Err == []).

test(the_census_reports_all_three_absent,
     [condition(reduced_platform_buildable)]) :-
    forall(member(Capability-Library,
                  [concurrency-'library(thread)',
                   deadlines-'library(time)',
                   subprocess-'library(process)']),
           ( format(string(Expected), "platform ~w absent ~w",
                    [Capability, Library]),
             assertion(reduced_line(Expected, _)) )).

test(a_reduced_build_still_evaluates,
     [condition(reduced_platform_buildable)]) :-
    reduced_line("answer plain ", Line),
    assertion(sub_string(Line, _, _, _, "3")),
    % and nothing the child ran answered where a refusal was due
    reduced_transcript(Out, _),
    forall(member(Reported, Out),
           assertion(\+ string_concat("unexpected", _, Reported))).

test(a_bounded_form_refuses_by_name_when_deadlines_are_absent,
     [condition(reduced_platform_buildable)]) :-
    refusal_names("timeout", ["(timeout N Expr)", "deadlines", "library(time)",
                              "wall-clock bound"]).

test(a_pragma_bound_refuses_by_name_when_deadlines_are_absent,
     [condition(reduced_platform_buildable)]) :-
    refusal_names("pragma", ["(pragma! max-time N)", "deadlines",
                             "library(time)"]).

test(hyperpose_refuses_by_name_when_concurrency_is_absent,
     [condition(reduced_platform_buildable)]) :-
    refusal_names("hyperpose ", ["(hyperpose ...)", "concurrency",
                                 "library(thread)"]),
    % the computed-list branch compiles to a different goal and carries the
    % same guard
    refusal_names("hyperpose-computed", ["(hyperpose ...)", "concurrency",
                                         "library(thread)"]).

test(a_library_that_declares_an_absent_capability_never_loads,
     [condition(reduced_platform_buildable)]) :-
    refusal_names("import", ["lib_thread.pl", "concurrency", "library(thread)",
                             "par-map"]).

test(git_import_refuses_by_name_when_subprocess_is_absent,
     [condition(reduced_platform_buildable)]) :-
    refusal_names("git", ["git-import!", "subprocess", "library(process)",
                          "starts a program"]).

:- end_tests(platform_capabilities_reduced).
