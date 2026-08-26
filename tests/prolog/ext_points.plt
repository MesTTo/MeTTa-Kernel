% Purpose: the extension seams' own installer and the cut rule that decides
%   whether a handler clause may prune the ones after it.
% Guarantees:
%   - a handler survives its own installation, so a subscription that installs
%     one really does receive events
%     [tested: a_handler_survives_its_own_installation]
%   - removing the last handler removes the write wrapper, so an unobserved
%     space goes back to paying nothing
%     [tested: the_wrapper_goes_when_the_last_handler_does]
%   - every foreign-space seam is reached by the engine operation that
%     consults it, driven through a provider consulted as a file, which is how
%     the seam is really used [tested 2026-08-16: ext_points_foreign_space]
%   - the removal, function-change, function-removal and compiled-call-site
%     dispatch seams each reach their handler
%     [tested 2026-08-16: ext_points_events]
%   - nested observation frames publish in write order only at outer commit
%     and discard their whole segment without callbacks
%     [tested: a_frame_publishes_only_after_commit_in_write_order,
%     an_outer_discard_drops_its_committed_inner_segment;
%     commit=3ded7552797b66d78e666141eb51f3bc14686bd2]
%   - rollback runs every deferred discard before rethrowing the first error
%     [tested: every_deferred_discard_runs_before_the_first_error_is_rethrown;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - a library's own error term renders through prolog:error_message//1
%     [tested 2026-08-16: ext_points_messages]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

:- dynamic plunit_ext_seen/2.

% Loaded at file level rather than in a test's setup: consult/1 called from
% inside a plunit unit resolves against that unit's module, and the translator
% reads the seam in user, so a clause added from a test is one nothing sees.
:- initialization(consult('seam_dispatch')).

:- begin_tests(ext_points_atom_hooks).

% The failure this guards is the seam's own installer erasing what it was
% called for. seam:enable_atom_hook/1 runs inside a prolog_listen/2 closure,
% and that channel REMOVES the clause when the hook fails on an assertz, so a
% wrap_predicate/4 that failed would take the handler with it and a library's
% subscription would never fire, with nothing said.
test(a_handler_survives_its_own_installation,
     [ cleanup(( erase(Ref),
                 retractall(plunit_ext_seen(_, _)),
                 clear_native_atoms('&plunit_ext_hooks') )) ]) :-
    assertz((seam:atom_added(Space, Term) :-
                 assertz(plunit_ext_seen(Space, Term))),
            Ref),
    % The clause is still there, which is the half prolog_listen/2 could have
    % undone.
    assertion(clause(seam:atom_added(_, _), _, Ref)),
    % And the wrapper it triggers really wraps.
    'add-atom'('&plunit_ext_hooks', [watched, 1], _),
    assertion(plunit_ext_seen('&plunit_ext_hooks', [watched, 1])).

test(the_wrapper_goes_when_the_last_handler_does,
     [ cleanup(( retractall(plunit_ext_seen(_, _)),
                 clear_native_atoms('&plunit_ext_hooks2') )) ]) :-
    assertz((seam:atom_added(Space, Term) :-
                 assertz(plunit_ext_seen(Space, Term))),
            Ref),
    'add-atom'('&plunit_ext_hooks2', [watched, 1], _),
    assertion(plunit_ext_seen(_, _)),
    erase(Ref),
    retractall(plunit_ext_seen(_, _)),
    % An unobserved space pays nothing again.
    'add-atom'('&plunit_ext_hooks2', [watched, 2], _),
    assertion(\+ plunit_ext_seen(_, _)).

:- end_tests(ext_points_atom_hooks).

% Two recording predicates, and which one a test uses is decided by WHERE its
% handler lives. A handler assertz'd from inside a unit has its body goals
% qualified to that unit's module, so it records there and an unqualified check
% reads it. A handler in a CONSULTED FILE records into user, so the dispatch
% test below reads user:plunit_dispatch_seen/1 explicitly. Conflating the two
% fails in whichever direction the qualification is wrong, and an unqualified
% retractall/1 in a unit CREATES the local one rather than reporting anything.
%
% D4.3: one registration test per seam. A seam is a promise to a library that
% is not in this repo, so an engine change that breaks one should fail here
% rather than in somebody's package. seam_provider.pl beside this file is a
% complete provider on every foreign-space hook, consulted rather than
% assertz'd because that is how the seam is really used: the hooks are
% multifile and STATIC, and a runtime assertz raises "No permission to modify
% static procedure".

install_seam_provider :-
    user:consult('seam_provider'),
    retractall(user:plunit_seam_atom(_)),
    retractall(plunit_seam_reached(_)).

remove_seam_provider :-
    retractall(user:plunit_seam_atom(_)),
    retractall(plunit_seam_reached(_)),
    absolute_file_name('seam_provider', F, [file_type(prolog), access(read)]),
    unload_file(F).

was_reached(What) :- plunit_seam_reached(What), !.

:- begin_tests(ext_points_foreign_space,
               [setup(install_seam_provider), cleanup(remove_seam_provider)]).

test(the_space_hook_takes_the_space_over) :-
    'add-atom'('&plunit_seam', [fact, a], _),
    assertion(was_reached(space)).

test(add_reaches_the_provider) :-
    'add-atom'('&plunit_seam', [fact, b], _),
    assertion(was_reached(add)),
    assertion(user:plunit_seam_atom([fact, b])).

test(match_reaches_the_provider) :-
    'add-atom'('&plunit_seam', [fact, c], _),
    findall(X, match('&plunit_seam', [fact, X], X, X), Xs),
    assertion(was_reached(match)),
    assertion(memberchk(c, Xs)).

test(enumeration_reaches_the_provider) :-
    'add-atom'('&plunit_seam', [fact, d], _),
    findall(T, 'get-atoms'('&plunit_seam', T), Ts),
    assertion(was_reached(enumerate)),
    assertion(memberchk([fact, d], Ts)).

test(remove_reaches_the_provider) :-
    'add-atom'('&plunit_seam', [fact, e], _),
    'remove-atom'('&plunit_seam', [fact, e], _),
    assertion(was_reached(remove)),
    assertion(\+ user:plunit_seam_atom([fact, e])).

test(the_capability_declaration_is_consulted) :-
    'add-atom'('&plunit_seam', [fact, f], _),
    assertion(was_reached(capability)).

% The retired trap, pinned the safe way round: a declaration provides
% exactly what it says, and declaring nothing provides NOTHING, the same
% answer P12.14 gave events. The seam provider declares all five and has
% all five; an undeclared space has none, and finds out at the operation's
% own refusal naming the capability.
test(a_declaration_provides_exactly_what_it_says) :-
    forall(member(C, [add, remove, match, enumerate, clear]),
           assertion(foreign_provides('&plunit_seam', C))),
    assertion(\+ foreign_provides('&plunit_undeclared', add)),
    assertion(\+ foreign_provides('&plunit_undeclared', clear)).

test(clear_reaches_the_provider) :-
    'add-atom'('&plunit_seam', [fact, g], _),
    seam:foreign_clear('&plunit_seam'),
    assertion(was_reached(clear)),
    assertion(\+ user:plunit_seam_atom(_)).

% The bounded form reaches a provider that HAS a /3 clause, carrying the
% caller's option list, and only when that provider claimed its filtering
% exact for THIS pattern. The seam provider is exact for a ground pattern,
% which this one is.
test(a_bounded_match_carries_its_options) :-
    'add-atom'('&plunit_seam', [fact, h], _),
    findall(X, match_foreign('&plunit_seam', [fact, h], [limit(1)], X, X), Xs),
    assertion(was_reached(pushdown)),
    assertion(was_reached(bounded([limit(1)]))),
    assertion(Xs \== []).

% The same provider, a pattern it did NOT claim exact for, and the number is
% withheld: it would truncate at whatever it is told, and nothing about an
% inexact match says N candidates are N answers. The provider is called
% exactly as it was before the option existed, and the engine's own bound
% still answers.
test(a_bound_is_withheld_from_an_unclaimed_pattern) :-
    'add-atom'('&plunit_seam', [fact, i], _),
    'add-atom'('&plunit_seam', [fact, j], _),
    %A bound of its own rather than a retractall, so the check does not
    %depend on which tests ran before it: reaching the /3 clause with THIS
    %number is what would be recorded, and nothing else records it.
    findall(X, limit(1, match_foreign('&plunit_seam', [fact, X], [limit(9)], X, X)), Xs),
    assertion(\+ was_reached(bounded([limit(9)]))),
    assertion(was_reached(match)),
    assertion(Xs = [_]).

:- end_tests(ext_points_foreign_space).

% ------------------------------------------------------------ event seams
%
% These are dynamic rather than static, because a library installs them when
% its feature is first used and removes them again: a resident handler costs
% four inferences on every compiled equation, so an always-on one is a tax on
% programs that never use the feature.
:- begin_tests(ext_points_events,
               [cleanup(retractall(plunit_seam_reached(_)))]).

test(a_frame_publishes_only_after_commit_in_write_order,
     [ cleanup(( erase(Ref),
                 catch(seam:observation_discard, _, true),
                 retractall(plunit_seam_reached(_)),
                 clear_native_atoms('&plunit_observation_commit') )) ]) :-
    assertz((seam:atom_added('&plunit_observation_commit', T) :-
                 assertz(plunit_seam_reached(added(T)))),
            Ref),
    seam:observation_begin,
    'add-atom'('&plunit_observation_commit', [seen, 1], _),
    'add-atom'('&plunit_observation_commit', [seen, 2], _),
    assertion(\+ plunit_seam_reached(_)),
    seam:observation_commit,
    findall(T, plunit_seam_reached(added(T)), Seen),
    assertion(Seen == [[seen, 1], [seen, 2]]).

test(an_outer_discard_drops_its_committed_inner_segment,
     [ cleanup(( erase(Ref),
                 catch(seam:observation_discard, _, true),
                 catch(seam:observation_discard, _, true),
                 retractall(plunit_seam_reached(_)),
                 clear_native_atoms('&plunit_observation_discard') )) ]) :-
    assertz((seam:atom_added('&plunit_observation_discard', T) :-
                 assertz(plunit_seam_reached(added(T)))),
            Ref),
    seam:observation_begin,
    'add-atom'('&plunit_observation_discard', [seen, outer], _),
    seam:observation_begin,
    'add-atom'('&plunit_observation_discard', [seen, inner], _),
    seam:observation_commit,
    assertion(\+ plunit_seam_reached(_)),
    seam:observation_discard,
    assertion(\+ plunit_seam_reached(_)).

test(every_deferred_discard_runs_before_the_first_error_is_rethrown,
     [ setup(nb_setval('$plunit_later_discard_ran', false)),
       cleanup(( catch(seam:observation_discard, _, true),
                 nb_delete('$plunit_later_discard_ran') )) ]) :-
    seam:observation_begin,
    seam:observation_defer(
        true,
        throw(error(plunit_first_discard_failed, context(discard, first)))),
    seam:observation_defer(
        true,
        nb_setval('$plunit_later_discard_ran', true)),
    catch(seam:observation_discard, Error, true),
    assertion(Error == error(plunit_first_discard_failed,
                             context(discard, first))),
    nb_getval('$plunit_later_discard_ran', LaterRan),
    assertion(LaterRan == true).

test(a_removed_atom_reaches_its_handler,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( erase(Ref),
                 clear_native_atoms('&plunit_seam_ev') )) ]) :-
    'add-atom'('&plunit_seam_ev', [gone, 1], _),
    assertz((seam:atom_removed(_, T) :-
                 assertz(plunit_seam_reached(removed(T)))),
            Ref),
    'remove-atom'('&plunit_seam_ev', [gone, 1], _),
    assertion(plunit_seam_reached(removed([gone, 1]))).

test(a_changed_function_reaches_its_handler,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( erase(Ref),
                 retractall(user:'plunit-seam-fn'(_)),
                 retractall(user:fun('plunit-seam-fn')) )) ]) :-
    assertz((seam:function_changed(F) :-
                 assertz(plunit_seam_reached(changed(F)))),
            Ref),
    process_metta_string("(= (plunit-seam-fn) 1)", _),
    assertion(plunit_seam_reached(changed('plunit-seam-fn'))).

test(a_removed_function_reaches_its_handler,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( erase(Ref),
                 retractall(user:fun('plunit-seam-gone')) )) ]) :-
    assertz((seam:function_removed(F) :-
                 assertz(plunit_seam_reached(removed_fn(F)))),
            Ref),
    forall(seam:function_removed('plunit-seam-gone'), true),
    assertion(plunit_seam_reached(removed_fn('plunit-seam-gone'))).

% A library's own cancellation or budget signal has to reach the caller, and
% the only way it can is by joining the engine's list: a signal the engine has
% never heard of is swallowed by the first recovery catch it meets and the
% program continues as though nothing happened. Asserted rather than
% consulted, because that is how a library that installs a signal for the life
% of one operation would do it.
test(a_librarys_own_control_signal_is_not_recovered_from,
     [ cleanup(unload_seam_signal) ]) :-
    % Before the library is loaded its signal is an ordinary error and the
    % recovery runs.
    assertion(catch_recover(throw(plunit_seam_cancelled), true)),
    user:consult('seam_signal'),
    catch(catch_recover(throw(plunit_seam_cancelled), true), Escaped, true),
    assertion(Escaped == plunit_seam_cancelled),
    % And an ordinary error still takes the recovery.
    assertion(catch_recover(throw(error(type_error(integer, a), _)), true)).

unload_seam_signal :-
    absolute_file_name('seam_signal', F, [file_type(prolog), access(read)]),
    unload_file(F).

% The dispatch seam is consulted at every compiled call site, which is what
% makes it the place to install a caching strategy of your own.
test(the_dispatch_seam_is_consulted_at_a_call_site,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( retractall(user:plunit_dispatch_seen(_)),
                 retractall(user:'plunit-seam-disp'(_, _)),
                 retractall(user:'plunit-seam-caller'(_)),
                 retractall(user:fun('plunit-seam-disp')),
                 retractall(user:fun('plunit-seam-caller')) )) ]) :-
    process_metta_string("(= (plunit-seam-disp $x) $x)", _),
    process_metta_string("(= (plunit-seam-caller) (plunit-seam-disp 1))", _),
    assertion(user:plunit_dispatch_seen('plunit-seam-disp')).

:- end_tests(ext_points_events).

% ------------------------------------------------- errors and host objects
:- begin_tests(ext_points_messages).

% A library gives its own error term a rendering through this seam, as against
% rethrow_metta_operation_error/2 which re-labels an error something else
% threw. Both are documented; only this one is a hook.
test(a_library_error_term_renders_through_the_seam) :-
    % The seam IS a DCG, so calling it is the precise test of it.
    phrase(prolog:error_message(
               petta_uncompilable_seam(translatePredicate, foo)),
           Parts),
    Parts = [Format-Arguments],
    format(string(Text), Format, Arguments),
    assertion(sub_string(Text, _, _, _, "compiles one Prolog goal")).

:- end_tests(ext_points_messages).

:- begin_tests(metta_published_surface).

% Declaring a seam publishes it, and publishing means EXPORTING it from the
% module that DEFINES it. Before this the declaration was a comment with a
% checker reading it back, so "published" was two copies of one list; now the
% module system holds the answer and the surface walks ask it.
%
% Which module that is stopped being one answer when the handler seams moved
% into `seam` and the engine's subsystems started declaring their own: a
% service lives in the subsystem that defines it, control_exception/1 lives in
% the engine core because the translator emits it, and every handler seam
% lives in `seam`. seam_home/2 answers that by asking SWI which module
% implements the name, so this test does not keep a second list of homes
% either.
test(every_declared_seam_that_exists_is_exported) :-
    findall(Seam-Home,
            ( seam:kind(Seam, _),
              seam:seam_home(Seam, Home),
              \+ ( module_property(Home, exports(Exports)),
                   memberchk(Seam, Exports) ) ),
            Unexported),
    assertion(Unexported == []),
    % and the list is not vacuously empty
    aggregate_all(count, seam:kind(_, _), Declared),
    assertion(Declared > 100),
    % every declared seam has a home, so none is skipped by the findall above
    findall(Seam, ( seam:kind(Seam, _), \+ seam:seam_home(Seam, _) ), Homeless),
    assertion(Homeless == []).

% A library that introduces a seam of its own is loaded long after the engine
% booted, so the boot sweep cannot be the whole mechanism. The listener on the
% multifile declaration is, and it is the same prolog_listen/2 channel the atom
% hooks use, which sees a clause arriving by consult as it sees one arriving by
% assert.
test(a_seam_declared_in_a_later_file_is_exported) :-
    petta_engine_module(Engine),
    module_property(Engine, exports(Before)),
    assertion(\+ memberchk(plunit_late_declared_service/1, Before)),
    % The fixture defines its service in the host module, so the engine's is
    % where the export has to land; a handler seam of its own would land in
    % `seam` and the same listener would put it there.
    % user: because consult from inside a plunit unit resolves against that
    % unit's module, and a library's seam belongs where the engine's is, which
    % is the same trap the file-level load at the top of this file avoids.
    user:ensure_loaded(seam_late_declaration),
    module_property(Engine, exports(After)),
    assertion(memberchk(plunit_late_declared_service/1, After)),
    % and the walks agree, since they ask the same list
    assertion(surface_published(plunit_late_declared_service/1)).

% Exporting an undefined name would hand a caller an existence error under the
% word "published", so a declaration whose predicate does not exist yet is
% skipped. engine/metta.pl's initialization sweeps again once every file has
% loaded, which is how a seam declared before its definition still ends up
% exported; every_seam_kind_matches_its_direction fails on one that never is.
test(a_declaration_without_a_definition_is_not_exported) :-
    petta_engine_module(Engine),
    assertion(\+ current_predicate(Engine:plunit_undefined_seam/3)),
    seam:publish(plunit_undefined_seam/3),
    module_property(Engine, exports(Exports)),
    assertion(\+ memberchk(plunit_undefined_seam/3, Exports)).

:- end_tests(metta_published_surface).

:- begin_tests(seam_module).

% The seams used to carry their namespace in their names: metta_on_ for the
% events, metta_foreign_ for the space-provider protocol, metta_grounded_ and
% metta_host_ for the other two. A prefix cannot refuse anything, which is why
% the long names were the SYMPTOM and the flat namespace the cause. Each of
% the four checks below is one half of "reached under its module".

% One: every declared seam has a module that holds it, and the module system
% is what answers.
test(test_every_seam_is_reached_under_its_module) :-
    findall(Seam, ( seam:kind(Seam, _), \+ seam:seam_home(Seam, _) ), Homeless),
    assertion(Homeless == []),
    aggregate_all(count, seam:kind(_, _), Declared),
    assertion(Declared > 100),
    % Two: every HANDLER seam, the kind an extension writes clauses for, is
    % held by a module that DECLARES it: `seam` for the engine's own seam
    % table, and the subsystem's own module for a seam a subsystem declares,
    % as engine/support_graph.pl does for the five a loader contributes to.
    % control_exception/1 is the single seam held by the engine core and it is
    % named rather than tolerated: the translator emits it, so a space's
    % execution module imports it from the ENGINE's module and a copy in `seam`
    % would leave that import with nothing to find.
    petta_engine_module(Engine),
    findall(Seam-Home,
            ( seam:kind(Seam, Kind),
              seam:clauses_from(Kind, extension),
              seam:seam_home(Seam, Home),
              Home == Engine ),
            InTheCore),
    assertion(InTheCore == [control_exception/1-Engine]),
    % Three: no HANDLER seam name carries a namespace any more, because the
    % module carries it. A prefix here would be the module's job done twice.
    % A service keeps its name: it is an ordinary engine predicate that an
    % extension is allowed to call, reached under whichever subsystem defines
    % it, and its prefix names the protocol it belongs to rather than a
    % namespace the module duplicates.
    findall(Name,
            ( seam:kind(Name/_, Kind),
              seam:clauses_from(Kind, extension),
              sub_atom(Name, 0, _, _, metta_) ),
            Prefixed),
    assertion(Prefixed == []),
    % Four: the old spellings are GONE rather than aliased. An alias tier
    % would be a second name for one thing, which the ladder refuses.
    forall(member(Old, [metta_on_atom_added/2, metta_on_atom_removed/2,
                        metta_on_function_changed/1, metta_on_function_removed/1,
                        metta_foreign_match/3, metta_foreign_space/1,
                        metta_grounded_apply/3, metta_host_builtin/1,
                        metta_dispatch_call/4, metta_engine_emitted/1,
                        ext_point_kind/2]),
           ( Old = OldName/OldArity,
             functor(OldHead, OldName, OldArity),
             assertion(\+ current_predicate(seam:OldName/OldArity)),
             assertion(\+ catch(predicate_property(Engine:OldHead, defined),
                                _, fail)) )).

% A service is the other direction, and it is reached under the module that
% DEFINES it rather than under `seam`: the engine core today, and a subsystem
% module as each one is cut. Asserting this apart keeps the two directions
% from being conflated the way one flat namespace conflated them.
test(a_service_is_reached_under_the_subsystem_that_defines_it) :-
    seam:seam_home(swrite/2, Home),
    assertion(Home \== seam),
    module_property(Home, exports(Exports)),
    assertion(memberchk(swrite/2, Exports)),
    % and the kernel's cut moved its four builtins out of the engine's own
    % module, which is the same mechanism one step further along
    assertion(predicate_property(kernel:'space-atom-count'(_, _),
                                 implementation_module(kernel))).

:- end_tests(seam_module).

% The surface walks live in tests/prolog/surface_walk.pl, which the two static
% lanes load; asking their question here without loading the walk keeps this
% suite standalone.
surface_published(Seam) :-
    petta_engine_module(Engine),
    module_property(Engine, exports(Exports)),
    memberchk(Seam, Exports).
