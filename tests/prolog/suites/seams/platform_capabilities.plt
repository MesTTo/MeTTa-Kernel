% Purpose: the platform census and the refusals that read it, checked on this
%   platform and on real ones without library(thread), library(time),
%   library(process), library(pcre), library(zlib), or library(fastrw) and
%   library(memfile) together.
% Guarantees:
%   - every declared capability's recorded status agrees with whether its
%     platform library resolves, one library or several, so the census cannot
%     claim a library the build does not have
%     [tested: the_census_agrees_with_what_resolves]
%   - a capability this build HAS refuses nothing, and a planted absence
%     refuses naming the form, the capability, the library and the cost
%     [tested: a_present_capability_refuses_nothing,
%     a_planted_absence_refuses_by_name_and_states_its_cost]
%   - the census is published as a host_service and exported, so a binding
%     reads it through the declared surface
%     [tested: the_census_is_a_published_host_service]
%   - each guard point the newer rows added refuses by name with its
%     capability planted absent, and the guards that sit inside a branch leave
%     the other branch alone [tested:
%     a_planted_absence_refuses_a_token_class_by_name,
%     a_planted_absence_refuses_a_host_token_class_by_name,
%     a_re_export_lost_with_its_capability_refuses_by_name,
%     a_name_no_capability_lost_still_refuses_the_general_way,
%     a_planted_absence_refuses_a_gz_path_by_name,
%     a_planted_absence_leaves_a_plain_path_alone,
%     a_gz_source_round_trips_where_the_capability_is_present,
%     a_planted_absence_refuses_a_fast_save_by_name,
%     a_planted_absence_refuses_a_fast_load_by_name]
%   - on a build without the three WebAssembly libraries the engine loads
%     without writing one ERROR line, still evaluates, and every form that
%     rests on an absent capability refuses by name
%     [tested: the_engine_boots_silently_without_the_three_libraries,
%     a_reduced_build_still_evaluates,
%     a_bounded_form_refuses_by_name_when_deadlines_are_absent,
%     a_pragma_bound_refuses_by_name_when_deadlines_are_absent,
%     hyperpose_refuses_by_name_when_concurrency_is_absent,
%     a_library_that_declares_an_absent_capability_never_loads,
%     git_import_refuses_by_name_when_subprocess_is_absent;
%     commit=87d998c24278fc7f020ccb0e408ebcd9332b63eb]
%   - and the same on a build with one further library taken away, one set per
%     capability: pcre, zlib, and fastrw with memfile
%     [tested: the_engine_boots_silently_without_pcre,
%     the_census_reports_regex_absent,
%     a_regex_library_import_refuses_by_name_when_regex_is_absent,
%     a_token_class_refuses_by_name_when_regex_is_absent,
%     a_lost_re_export_refuses_by_name_when_regex_is_absent,
%     the_engine_boots_silently_without_zlib,
%     the_census_reports_compressed_sources_absent,
%     a_gz_source_refuses_by_name_when_compression_is_absent,
%     a_plain_source_still_loads_when_compression_is_absent,
%     the_engine_boots_silently_without_the_fast_cache,
%     the_census_reports_the_fast_cache_absent,
%     both_fast_cache_doors_refuse_by_name_when_it_is_absent,
%     a_load_round_trips_without_the_cache]
% Fails when:
%   - this platform is itself missing one of the libraries a set withholds.
%     Every reduced test is conditional on there being something to take away,
%     and says so rather than passing over a farm it could not build.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/metta.pl').
:- ensure_loaded('../../reduced_platform').

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

%The same plant for the name index a lost re-export leaves behind, written
%into the engine's module for the same reason.
plant_absent_name(Name, Capability) :-
    metta_engine_module(Engine),
    assertz(Engine:metta_platform_absent_name(Name, Capability)).

unplant_absent_name(Name, Capability) :-
    metta_engine_module(Engine),
    retractall(Engine:metta_platform_absent_name(Name, Capability)).

:- begin_tests(platform_capabilities).

test(the_census_agrees_with_what_resolves) :-
    findall(Capability-Status,
            metta_platform(Capability, Status, _, _),
            Rows),
    assertion(Rows \== []),
    forall(metta_platform(Capability, Status, Requires, Costs),
           ( assertion(( forall(census_spec(Requires, Spec),
                                exists_source(Spec))
                       -> Status == present
                       ;  Status == absent )),
             assertion(( atom(Costs), Costs \== '' )) )),
    % The six the engine's own loads rest on, named so a row that
    % disappears is a decision rather than a silence.
    forall(member(Named, [concurrency, deadlines, subprocess, regex,
                          'compressed-sources', 'fast-cache']),
           assertion(memberchk(Named-_, Rows))).

% A row names one library or a list of them; both have to resolve for the
% capability to be present, which is what the engine's own load requires.
census_spec(Requires, Spec) :-
    (   is_list(Requires)
    ->  member(Spec, Requires)
    ;   Spec = Requires
    ).

% Nothing was lost on THIS platform, so the name index the import door reads
% is empty here. A row in it on a full build would mean a census load asked
% for a name its library does not export.
test(no_name_is_recorded_lost_on_a_full_platform) :-
    metta_engine_module(Engine),
    forall(metta_platform(Capability, present, _, _),
           assertion(\+ Engine:metta_platform_absent_name(_, Capability))).

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

test(the_regex_library_declares_what_it_rests_on) :-
    metta_source_declarations('../../lib/lib_regex/lib_regex.pl', Declarations),
    assertion(memberchk(requires(regex), Declarations)).

% The three guard points the regex row added, each with the capability
% planted absent, because this box has pcre and would otherwise take none of
% them. The reduced unit below takes the library away for real.
test(a_planted_absence_refuses_a_token_class_by_name,
     [ setup(plant_absent(regex)),
       cleanup(unplant_absent(regex)),
       throws(error(metta_platform_required('(register-token! ...)', regex,
                                            library(pcre), _), _)) ]) :-
    'register-token!'("[A-Z][0-9]+", tagged, _).

% The host door into the same funnel, so a binding's register_token/2 gets the
% refusal the MeTTa form does rather than an interior existence error.
test(a_planted_absence_refuses_a_host_token_class_by_name,
     [ setup(plant_absent(regex)),
       cleanup(unplant_absent(regex)),
       throws(error(metta_platform_required('(register-token! ...)', regex,
                                            library(pcre), _), _)) ]) :-
    metta_host_register_reader_token("[A-Z][0-9]+", tagged).

% The re-export, refused BY NAME at import time. The probe uses a name
% nothing defines, because a name this build DOES have -- re_replace here --
% takes the door's first branch and never reaches the census. Planted, the
% pair is exactly the state a build without pcre leaves re_replace in, and the
% reduced unit takes it there for real.
test(a_re_export_lost_with_its_capability_refuses_by_name,
     [ setup(( plant_absent(regex),
               plant_absent_name(plunit_lost_re_export, regex) )),
       cleanup(( unplant_absent(regex),
                 unplant_absent_name(plunit_lost_re_export, regex) )),
       throws(error(metta_platform_required(plunit_lost_re_export, regex,
                                            library(pcre), _), _)) ]) :-
    import_prolog_function(plunit_lost_re_export, _).

% and a name nothing lost still gets the general refusal, so the census
% lookup narrows the message rather than swallowing every missing predicate.
test(a_name_no_capability_lost_still_refuses_the_general_way,
     [ throws(error(existence_error(procedure,
                                    plunit_no_such_prolog_predicate), _)) ]) :-
    import_prolog_function(plunit_no_such_prolog_predicate, _).

% metta_host_fast_open/3 and read_source_text/2 are engine/filereader.pl's
% own rather than exported host services, so these name the module the way
% plant_absent/1 names the engine's.
test(a_planted_absence_refuses_a_gz_path_by_name,
     [ setup(plant_absent('compressed-sources')),
       cleanup(unplant_absent('compressed-sources')),
       throws(error(metta_platform_required('plunit_probe.metta.gz',
                                            'compressed-sources',
                                            library(zlib), _), _)) ]) :-
    filereader:metta_host_fast_open('plunit_probe.metta.gz', read, _).

% The other half of that guard: it sits INSIDE the .gz branch, so a plain
% path opens on a build the capability is absent from and pays nothing.
test(a_planted_absence_leaves_a_plain_path_alone,
     [ setup(plant_absent('compressed-sources')),
       cleanup(unplant_absent('compressed-sources')) ]) :-
    tmp_file(plunit_plain, Path),
    setup_call_cleanup(filereader:metta_host_fast_open(Path, write, Out),
                       put_byte(Out, 0'x),
                       close(Out)),
    setup_call_cleanup(filereader:metta_host_fast_open(Path, read, In),
                       get_byte(In, Byte),
                       close(In)),
    catch(delete_file(Path), _, true),
    assertion(Byte =:= 0'x).

% The .gz reader and the cache share one door, so the capability present here
% must still read a compressed program end to end: this is the only check
% that read_source_text/2 going through metta_host_fast_open/3 kept its
% contract.
test(a_gz_source_round_trips_where_the_capability_is_present,
     [ condition(metta_platform('compressed-sources', present, _, _)) ]) :-
    tmp_file(plunit_gz, Base),
    atom_concat(Base, '.metta.gz', Path),
    setup_call_cleanup(filereader:metta_host_fast_open(Path, write, Out),
                       ( set_stream(Out, encoding(utf8)),
                         format(Out, '(= (plunit-gz-answer) 11)~n', []) ),
                       close(Out)),
    filereader:read_source_text(Path, Text),
    catch(delete_file(Path), _, true),
    assertion(sub_string(Text, _, _, _, "plunit-gz-answer")).

test(a_planted_absence_refuses_a_fast_save_by_name,
     [ setup(plant_absent('fast-cache')),
       cleanup(unplant_absent('fast-cache')),
       throws(error(metta_platform_required('plunit_probe.fast', 'fast-cache',
                                            [library(fastrw),
                                             library(memfile)], _), _)) ]) :-
    metta_host_save_fast('plunit_probe.fast', '&self', _).

test(a_planted_absence_refuses_a_fast_load_by_name,
     [ setup(plant_absent('fast-cache')),
       cleanup(unplant_absent('fast-cache')),
       throws(error(metta_platform_required('plunit_probe.fast', 'fast-cache',
                                            [library(fastrw),
                                             library(memfile)], _), _)) ]) :-
    metta_host_load_fast('plunit_probe.fast', '&self').

test(the_census_is_a_published_host_service) :-
    assertion(seam:kind(metta_platform/4, host_service)),
    metta_engine_module(Engine),
    module_property(Engine, exports(Exports)),
    assertion(memberchk(metta_platform/4, Exports)).

:- end_tests(platform_capabilities).

:- begin_tests(platform_capabilities_reduced).

:- dynamic reduced_platform_transcript/3.

%One child boot per WITHHELD SET serves every test that reads it. Memoized on
%the set, because booting the engine on a source-only library farm costs
%seconds and four sets would otherwise cost that per test rather than per set.
reduced_transcript(Out, Err) :-
    reduced_transcript([], Out, Err).

reduced_transcript(Extra, Out, Err) :-
    (   reduced_platform_transcript(Extra, Out0, Err0)
    ->  Out = Out0, Err = Err0
    ;   run_reduced_platform(Extra, Out0, Err0),
        assertz(reduced_platform_transcript(Extra, Out0, Err0)),
        Out = Out0, Err = Err0
    ).

%The transcript line that starts with Prefix, as a string. Fails when the
%child never printed one, which is what every test below is asserting about.
reduced_line(Prefix, Line) :-
    reduced_line([], Prefix, Line).

reduced_line(Extra, Prefix, Line) :-
    reduced_transcript(Extra, Out, _),
    once(( member(Line, Out), string_concat(Prefix, _, Line) )).

%A refusal names the form, the capability, the platform library and the cost.
%All four, because a refusal that names only the form is the interior
%existence error with better manners.
refusal_names(Label, Fragments) :-
    refusal_names([], Label, Fragments).

refusal_names(Extra, Label, Fragments) :-
    string_concat("refusal ", Label, Prefix),
    ( reduced_line(Extra, Prefix, Line) -> true
    ; reduced_transcript(Extra, Out, _),
      throw(error(plunit_no_refusal(Label, Out), _)) ),
    forall(member(Fragment, Fragments),
           assertion(sub_string(Line, _, _, _, Fragment))).

%What every withheld set owes whatever it took away: a boot that says nothing
%on stderr, an engine that still evaluates, and no probe answering where a
%refusal was due or refusing where an answer was.
a_clean_reduced_boot(Extra) :-
    reduced_transcript(Extra, Out, Err),
    assertion(Err == []),
    ( member(Answer, Out), string_concat("answer plain ", _, Answer)
    -> assertion(sub_string(Answer, _, _, _, "3"))
    ;  throw(error(plunit_no_plain_answer(Extra, Out), _)) ),
    forall(member(Reported, Out),
           assertion(\+ string_concat("unexpected", _, Reported))).

%The census line for one capability in one child, which is the reduced half of
%the_census_agrees_with_what_resolves.
census_reports_absent(Extra, Capability, Library) :-
    format(string(Expected), "platform ~w absent ~w", [Capability, Library]),
    assertion(reduced_line(Extra, Expected, _)).

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

% A source load with no cache in it, which is what every load on a build
% without the fast cache is. It runs in every child, so the case below that
% withholds the libraries is comparing against a route proven to work here.
test(a_source_load_round_trips_in_the_reduced_build,
     [condition(reduced_platform_buildable)]) :-
    reduced_line("answer round-trip ", Line),
    assertion(sub_string(Line, _, _, _, "7")).

%%%% One library at a time, for the capabilities a shipped reduced platform
%%%% does have and a hand-built SWI can leave out. Each set is one more child
%%%% boot, memoized on the set.

test(the_engine_boots_silently_without_pcre,
     [condition(reduced_platform_buildable([pcre]))]) :-
    % Four ERROR pairs before the guards: engine/metta.pl, engine/parser.pl,
    % engine/filereader.pl and lib/lib_regex/lib_regex.pl each loaded pcre
    % unconditionally [measured 2026-08-28].
    a_clean_reduced_boot([pcre]).

test(the_census_reports_regex_absent,
     [condition(reduced_platform_buildable([pcre]))]) :-
    census_reports_absent([pcre], regex, 'library(pcre)').

test(a_regex_library_import_refuses_by_name_when_regex_is_absent,
     [condition(reduced_platform_buildable([pcre]))]) :-
    refusal_names([pcre], "regex-library",
                  ["lib_regex.pl", "regex", "library(pcre)", "(re-match ...)"]).

test(a_token_class_refuses_by_name_when_regex_is_absent,
     [condition(reduced_platform_buildable([pcre]))]) :-
    refusal_names([pcre], "regex-token",
                  ["(register-token! ...)", "regex", "library(pcre)"]).

% The re-export, refused at IMPORT time and by name. Before the census
% recorded what its own load could not import, this answered "no predicate
% named re_replace is loaded", which reads as a typo [measured 2026-08-28].
test(a_lost_re_export_refuses_by_name_when_regex_is_absent,
     [condition(reduced_platform_buildable([pcre]))]) :-
    refusal_names([pcre], "regex-import",
                  ["re_replace", "regex", "library(pcre)"]).

test(the_engine_boots_silently_without_zlib,
     [condition(reduced_platform_buildable([zlib]))]) :-
    a_clean_reduced_boot([zlib]).

test(the_census_reports_compressed_sources_absent,
     [condition(reduced_platform_buildable([zlib]))]) :-
    census_reports_absent([zlib], 'compressed-sources', 'library(zlib)').

% The refusal names the FILE, because that is the part of the request its
% caller chose. Before the guard it named a farm path inside SWI's own
% search: `source_sink '<farm>/zlib' does not exist` [measured 2026-08-28].
test(a_gz_source_refuses_by_name_when_compression_is_absent,
     [condition(reduced_platform_buildable([zlib]))]) :-
    refusal_names([zlib], "compressed",
                  ["compressed.metta.gz", "compressed-sources",
                   "library(zlib)", "uncompressed still loads"]).

% and the same child still loads a plain source, which is the whole claim
% behind calling this a lost FILE FORMAT rather than a lost engine.
test(a_plain_source_still_loads_when_compression_is_absent,
     [condition(reduced_platform_buildable([zlib]))]) :-
    reduced_line([zlib], "answer round-trip ", Line),
    assertion(sub_string(Line, _, _, _, "7")).

test(the_engine_boots_silently_without_the_fast_cache,
     [condition(reduced_platform_buildable([fastrw, memfile]))]) :-
    a_clean_reduced_boot([fastrw, memfile]).

test(the_census_reports_the_fast_cache_absent,
     [condition(reduced_platform_buildable([fastrw, memfile]))]) :-
    census_reports_absent([fastrw, memfile], 'fast-cache',
                          '[library(fastrw),library(memfile)]').

test(both_fast_cache_doors_refuse_by_name_when_it_is_absent,
     [condition(reduced_platform_buildable([fastrw, memfile]))]) :-
    forall(member(Label, ["fast-save", "fast-load"]),
           refusal_names([fastrw, memfile], Label,
                         ["probe.fast", "fast-cache", "library(fastrw)",
                          "library(memfile)", "every load reads its source"])).

% The degradation itself: with both libraries gone the engine loads a source
% and answers from it, which is the cost text's claim that a build without the
% cache reparses and nothing else changes.
test(a_load_round_trips_without_the_cache,
     [condition(reduced_platform_buildable([fastrw, memfile]))]) :-
    reduced_line([fastrw, memfile], "answer round-trip ", Line),
    assertion(sub_string(Line, _, _, _, "7")).

:- end_tests(platform_capabilities_reduced).
