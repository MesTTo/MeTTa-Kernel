% Purpose: the engine's self-description. These tests are what stop the
%   surface export from drifting away from the engine it describes, which is
%   the whole reason it exists: a list maintained in two places drifts, a list
%   the engine answers cannot.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).
:- initialization(consult('../../lib/lib_reflect.pl')).

:- begin_tests(lib_reflect).

test(every_registered_builtin_is_reported) :-
    forall(member(Name, ['car-atom', 'add-atom', match, superpose, '+']),
           'engine-builtin'(Name)).

test(a_name_that_is_not_a_builtin_is_not_reported) :-
    \+ 'engine-builtin'('no-such-builtin-anywhere').

% Special forms are the reason this library exists. They are COMPILED by the
% translator rather than called.
test(special_forms_are_reported) :-
    forall(member(Name, [hyperpose, timeout, elapsed, 'let*', case, collapse]),
           'engine-special-form'(Name)).

% The two sets OVERLAP, which is the fact a tool has to know and cannot get
% from either registry alone. 14 names are both, and 23 are special forms with
% no registry entry whatsoever [measured 2026-08-15].
test(some_special_forms_are_also_registered_builtins) :-
    forall(member(Name, [let, 'let*', superpose, match, 'add-atom']),
           ( 'engine-special-form'(Name), 'engine-builtin'(Name) )).

% And these are the ones that make the export necessary: the language's basic
% control forms are in NO registry, so a tool reading only the builtin list
% does not know that if, case, quote or collapse exist.
test(the_control_forms_are_in_no_registry) :-
    forall(member(Name, [if, case, collapse, quote, catch, once, forall,
                         hyperpose, timeout]),
           ( 'engine-special-form'(Name), \+ 'engine-builtin'(Name) )).

test(the_special_form_enumeration_has_no_duplicates) :-
    findall(Name, 'engine-special-form'(Name), Names),
    sort(Names, Unique),
    length(Names, Count), length(Unique, Count).

% Asking about one name must be a lookup rather than a scan.
test(asking_about_one_special_form_is_semidet) :-
    findall(x, 'engine-special-form'(hyperpose), Solutions),
    Solutions == [x].

test(arity_is_reported_for_a_known_builtin) :-
    'engine-arity'('car-atom', Arity),
    integer(Arity), Arity >= 1.

test(knows_answers_a_boolean_for_all_three_kinds) :-
    'engine-knows'('car-atom', Builtin), Builtin == true,
    'engine-knows'(hyperpose, Special), Special == true,
    'engine-knows'('definitely-not-a-thing', Unknown), Unknown == false.

test(counts_are_positive_and_consistent) :-
    'engine-surface-counts'(Counts),
    memberchk([builtins, Builtins], Counts),
    memberchk(['special-forms', Forms], Counts),
    memberchk([functions, Functions], Counts),
    memberchk(['user-functions', UserFunctions], Counts),
    Builtins > 0, Forms > 0,
    Functions >= Builtins,
    UserFunctions =:= Functions - Builtins.

% The registry and the enumeration must agree, or the export is lying.
test(the_builtin_count_matches_the_enumeration) :-
    'engine-surface-counts'(Counts),
    memberchk([builtins, Reported], Counts),
    findall(Name, 'engine-builtin'(Name), Names),
    length(Names, Actual),
    Reported =:= Actual.

test(the_special_form_count_matches_the_enumeration) :-
    'engine-surface-counts'(Counts),
    memberchk(['special-forms', Reported], Counts),
    findall(Name, 'engine-special-form'(Name), Names),
    length(Names, Actual),
    Reported =:= Actual.

test(every_user_function_is_a_function_and_not_a_builtin) :-
    forall('engine-user-function'(Name),
           ( 'engine-function'(Name), \+ 'engine-builtin'(Name) )).

% A seam's kind decides whether a cut in a handler is an optimisation or a
% soundness bug, so a wrong one is not cosmetic. The two named here are the
% ones that were wrong while the taxonomy was prose in a comment:
% metta_backend_selftest/0 is enumerated with forall/2 [source: src/main.pl:36]
% and was outside the check that enforces the rule, and metta_dispatch_call/4
% is taken with ->/2 [source: src/translator.pl:364] and was wrongly inside it.
test(extension_points_are_reported) :-
    findall(Point, 'engine-extension-point'(Point), Points),
    forall(member([Name, Arity, Kind], Points),
           ( assertion(atom(Name)),
             assertion(integer(Arity)),
             assertion(memberchk(Kind, [event, ownership, declaration,
                                        service])) )),
    forall(member(Expected, [[metta_backend_selftest, 0, event],
                             [metta_dispatch_call, 4, ownership],
                             [metta_on_atom_added, 2, event],
                             [metta_foreign_match, 3, ownership],
                             [metta_pure_operation, 1, declaration],
                             [swrite, 2, service]]),
           assertion(memberchk(Expected, Points))).

% A reflecting tool is asking what the contract IS, and the contract runs both
% ways: the handler seams it may fill, and the services it may call. Reporting
% only the first would describe half of it, so a service is a point here like
% any other and the kind says which direction it runs.
test(both_directions_of_the_contract_are_reported) :-
    findall(K-N/A, 'engine-extension-point'([N, A, K]), Points),
    forall(member(Direction, [extension, engine]),
           assertion(( member(Kind-_, Points),
                       ext_point_clauses_from(Kind, Direction) ))),
    assertion(memberchk(service-swrite/2, Points)),
    assertion(memberchk(ownership-metta_foreign_match/3, Points)).

% The cut check reads the derivation rather than the kinds, so the derivation
% is what has to hold. It is not "every kind but ownership": that rule is about
% a handler an extension contributed staying reachable, so it can only apply
% where an extension writes the clauses. A service's clauses are the engine's
% own and cut freely, swrite/2 among them, and reading the rule off the kind
% list alone would call every one of them an offender.
test(every_extension_kind_but_ownership_has_every_clause_run) :-
    forall(ext_point_kind(Seam, Kind),
           (   ext_point_clauses_from(Kind, extension), Kind \== ownership
           ->  assertion(ext_point_every_clause_runs(Seam))
           ;   assertion(\+ ext_point_every_clause_runs(Seam))
           )).

% Every kind carries a direction, checked rather than assumed: a kind added
% without one is exempt from the cut rule by silence, which is the drift
% ext_point_kind/2 was made data to stop.
test(every_kind_declares_its_direction) :-
    forall(ext_point_kind(_, Kind),
           assertion(( ext_point_clauses_from(Kind, Direction),
                       memberchk(Direction, [extension, engine]) ))).

:- end_tests(lib_reflect).

% fun/1 is a flat list in which an equation, a registered Prolog predicate and
% a Python operation are indistinguishable, so reflection could not answer the
% question a name collision raises. Every tier answers, and every tier answers
% DIFFERENTLY, which is the whole content of the claim.
:- begin_tests(lib_reflect_origin).

user:plunit_reflect_pred(X, X).

test(every_tier_names_itself,
     [ setup(import_prolog_function(plunit_reflect_pred, _)),
       cleanup(( unregister_fun_everywhere(plunit_reflect_pred),
                 release_function_name(plunit_reflect_pred),
                 retractall(fun(plunit_reflect_pred)),
                 retractall(arity(plunit_reflect_pred, _)),
                 'remove-atom'('&self', [=, ['plunit-reflect-eq', A], A], _),
                 retractall(fun('plunit-reflect-eq')),
                 retractall(arity('plunit-reflect-eq', _)),
                 unregister_fun_everywhere('plunit-reflect-eq') )) ]) :-
    'add-atom'('&self', [=, ['plunit-reflect-eq', X], X], _),
    'engine-origin'('+', Builtin),
    assertion(Builtin == [builtin]),
    'engine-origin'(if, SpecialForm),
    assertion(SpecialForm == ['special-form']),
    'engine-origin'(plunit_reflect_pred, Prolog),
    assertion(Prolog = [prolog, _]),
    'engine-origin'('plunit-reflect-eq', Equation),
    assertion(Equation = [equation, user]).

test(a_name_the_engine_does_not_know_has_no_origin) :-
    \+ 'engine-origin'(plunit_reflect_absent, _).

:- end_tests(lib_reflect_origin).
