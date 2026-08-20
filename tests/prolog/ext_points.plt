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
%   - a library's own error term renders through prolog:error_message//1
%     [tested 2026-08-16: ext_points_messages]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).

:- dynamic plunit_ext_seen/2.

% Loaded at file level rather than in a test's setup: consult/1 called from
% inside a plunit unit resolves against that unit's module, and the translator
% reads the seam in user, so a clause added from a test is one nothing sees.
:- initialization(consult('seam_dispatch')).

:- begin_tests(ext_points_atom_hooks).

% The failure this guards is the seam's own installer erasing what it was
% called for. enable_metta_atom_hook/1 runs inside a prolog_listen/2 closure,
% and that channel REMOVES the clause when the hook fails on an assertz, so a
% wrap_predicate/4 that failed would take the handler with it and a library's
% subscription would never fire, with nothing said.
test(a_handler_survives_its_own_installation,
     [ cleanup(( erase(Ref),
                 retractall(plunit_ext_seen(_, _)),
                 clear_native_atoms('&plunit_ext_hooks') )) ]) :-
    assertz((user:metta_on_atom_added(Space, Term) :-
                 assertz(plunit_ext_seen(Space, Term))),
            Ref),
    % The clause is still there, which is the half prolog_listen/2 could have
    % undone.
    assertion(clause(user:metta_on_atom_added(_, _), _, Ref)),
    % And the wrapper it triggers really wraps.
    'add-atom'('&plunit_ext_hooks', [watched, 1], _),
    assertion(plunit_ext_seen('&plunit_ext_hooks', [watched, 1])).

test(the_wrapper_goes_when_the_last_handler_does,
     [ cleanup(( retractall(plunit_ext_seen(_, _)),
                 clear_native_atoms('&plunit_ext_hooks2') )) ]) :-
    assertz((user:metta_on_atom_added(Space, Term) :-
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

% The trap a vocabulary extender walks into: the "declares nothing means
% everything" default stops at the FIRST solution, so declaring one capability
% is declaring the complete set. The seam provider declares all five; a space
% declaring one provides exactly that one.
test(a_partial_declaration_declares_the_whole_set) :-
    forall(member(C, [add, remove, match, enumerate, clear]),
           assertion(foreign_provides('&plunit_seam', C))),
    % A space nothing declares for still provides everything.
    assertion(foreign_provides('&plunit_undeclared', add)),
    assertion(foreign_provides('&plunit_undeclared', clear)).

test(clear_reaches_the_provider) :-
    'add-atom'('&plunit_seam', [fact, g], _),
    metta_foreign_clear('&plunit_seam'),
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

test(a_removed_atom_reaches_its_handler,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( erase(Ref),
                 clear_native_atoms('&plunit_seam_ev') )) ]) :-
    'add-atom'('&plunit_seam_ev', [gone, 1], _),
    assertz((user:metta_on_atom_removed(_, T) :-
                 assertz(plunit_seam_reached(removed(T)))),
            Ref),
    'remove-atom'('&plunit_seam_ev', [gone, 1], _),
    assertion(plunit_seam_reached(removed([gone, 1]))).

test(a_changed_function_reaches_its_handler,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( erase(Ref),
                 retractall(user:'plunit-seam-fn'(_)),
                 retractall(user:fun('plunit-seam-fn')) )) ]) :-
    assertz((user:metta_on_function_changed(F) :-
                 assertz(plunit_seam_reached(changed(F)))),
            Ref),
    process_metta_string("(= (plunit-seam-fn) 1)", _),
    assertion(plunit_seam_reached(changed('plunit-seam-fn'))).

test(a_removed_function_reaches_its_handler,
     [ setup(retractall(plunit_seam_reached(_))),
       cleanup(( erase(Ref),
                 retractall(user:fun('plunit-seam-gone')) )) ]) :-
    assertz((user:metta_on_function_removed(F) :-
                 assertz(plunit_seam_reached(removed_fn(F)))),
            Ref),
    forall(metta_on_function_removed('plunit-seam-gone'), true),
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
