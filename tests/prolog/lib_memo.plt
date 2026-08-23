% Purpose: direct PlUnit coverage for memoization storage, eviction, and the
%   per-space keying that keeps one space's cache out of another's answers.
% Guarantees:
%   - A changed callee invalidates transitive caller caches through supports/2
%     while an unrelated cache survives [tested:
%     memo_support_graph:a_leaf_change_invalidates_transitive_callers_only;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').
:- initialization(consult('../../lib/lib_memo.pl')).

% The eviction test drives the store against a tiny budget, so it has to move
% the limits. Both are dynamic predicates carrying a default fact, and a
% cleanup that only retracts leaves them with no clause at all: every later
% cache write then fails on the missing limit and the function answers
% nothing. Save the value and put it back.

memo_setting(memo_size_limit).
memo_setting(metta_memo_total_bytes).

memo_setting_save :-
    forall(memo_setting(Name),
           ( Fact =.. [Name, Value],
             user:Fact,
             atom_concat('$memo_plt_', Name, Key),
             nb_setval(Key, Value) )).

memo_setting_restore :-
    forall(memo_setting(Name),
           ( atom_concat('$memo_plt_', Name, Key),
             nb_getval(Key, Value),
             Wild =.. [Name, _],
             retractall(user:Wild),
             Fact =.. [Name, Value],
             assertz(user:Fact) )).

memo_setting_override(Name, Value) :-
    Wild =.. [Name, _],
    retractall(user:Wild),
    Fact =.. [Name, Value],
    assertz(user:Fact).

:- begin_tests(memo_eviction_output,
               [ setup((memo_setting_save,
                        memo_setting_override(memo_size_limit, 100),
                        memo_setting_override(metta_memo_total_bytes, 100),
                        assertz(user:metta_memo_head(test_fun, user, 1, 0)),
                        assertz(user:metta_memo_tail(test_fun, user, 1, 1)),
                        assertz(user:metta_memo_count(test_fun, user, 1, 1)),
                        assertz(user:metta_memo_q(test_fun, user, 1, 1, [key])),
                        assertz(user:metta_memo_entry(test_fun, user, 1, 0,
                                                      [key], [value])))),
                 cleanup((memo_setting_restore,
                          retractall(user:metta_memo_head(test_fun, user, 1, _)),
                          retractall(user:metta_memo_tail(test_fun, user, 1, _)),
                          retractall(user:metta_memo_count(test_fun, user, 1, _)),
                          retractall(user:metta_memo_q(test_fun, user, 1, _, _)),
                          retractall(user:metta_memo_entry(test_fun, user, 1, _, _, _))))
               ]).

capture_user_error(Goal, Text) :-
    new_memory_file(Memory),
    setup_call_cleanup(
        open_memory_file(Memory, write, ErrorStream),
        ( current_input(Input),
          current_output(Output),
          stream_property(OriginalError, alias(user_error)),
          setup_call_cleanup(
              set_prolog_IO(Input, Output, ErrorStream),
              call(Goal),
              set_prolog_IO(Input, Output, OriginalError)) ),
        close(ErrorStream)),
    memory_file_to_string(Memory, Text),
    free_memory_file(Memory).

test(routine_eviction_is_silent) :-
    capture_user_error(user:evict_global_space(1), Output),
    Output == "",
    \+ user:metta_memo_entry(test_fun, user, 1, _, [key], _).

:- end_tests(memo_eviction_output).

% Two spaces defining one name hold two functions. Before the cache carried
% the module, enabling memoization in either space enabled it in both, one
% cache served both, and each space answered with the other's equation too.

:- begin_tests(memo_space_isolation,
               [ setup(memo_iso_define),
                 cleanup(memo_iso_forget) ]).

memo_iso_equation('&self', "(= (isocalc $x) (+ $x 100))").
memo_iso_equation('&memo_iso', "(= (isocalc $x) (+ $x 900))").

memo_iso_shared("(= (isoshared $x) (+ $x 7))").

memo_iso_define :-
    forall(memo_iso_equation(Space, Text),
           ( sread(Text, Term), 'add-atom'(Space, Term, _) )).

memo_iso_forget :-
    memo_iso_reset,
    forall(memo_iso_equation(Space, Text),
           ( sread(Text, Term), 'remove-atom'(Space, Term, _) )).

memo_iso_reset :-
    user:disable_memoization(isocalc),
    user:cache_clear.

%Every answer the space gives for (isocalc 2), read through the module its
%equations were compiled into.
memo_iso_answers(Space, Answers) :-
    space_module(Space, Module),
    findall(R, with_metta_module(Module, reduce([isocalc, 2], R)), Answers).

memo_iso_memoize(Space) :-
    space_module(Space, Module),
    with_metta_module(Module, user:'memoize'(isocalc, true)).

memo_iso_reports(Space, Reported) :-
    space_module(Space, Module),
    with_metta_module(Module, user:'is-memoized'(isocalc, Reported)).

test(each_space_answers_with_its_own_equation,
     [ cleanup(memo_iso_reset) ]) :-
    memo_iso_answers('&self', [102]),
    memo_iso_answers('&memo_iso', [902]).

test(memoizing_one_space_leaves_the_other_unchanged,
     [ cleanup(memo_iso_reset) ]) :-
    memo_iso_memoize('&self'),
    memo_iso_answers('&self', [102]),
    memo_iso_answers('&memo_iso', [902]),
    memo_iso_answers('&self', [102]),
    memo_iso_answers('&memo_iso', [902]).

test(memoizing_both_spaces_keeps_two_caches,
     [ cleanup(memo_iso_reset) ]) :-
    memo_iso_memoize('&self'),
    memo_iso_memoize('&memo_iso'),
    memo_iso_answers('&self', [102]),
    memo_iso_answers('&memo_iso', [902]),
    memo_iso_answers('&self', [102]),
    memo_iso_answers('&memo_iso', [902]).

test(is_memoized_answers_for_the_asking_space,
     [ cleanup(memo_iso_reset) ]) :-
    memo_iso_memoize('&self'),
    memo_iso_reports('&self', true),
    memo_iso_reports('&memo_iso', false).

%A shared function is one function: a space that only inherits &self's
%equations caches under &self, so it neither duplicates the cache nor
%reports itself separately memoized.
test(an_inheriting_space_shares_the_one_cache,
     [ setup(( memo_iso_shared(SetupText),
               sread(SetupText, SetupTerm),
               'add-atom'('&self', SetupTerm, _) )),
       cleanup(( memo_iso_reset,
                 user:disable_memoization(isoshared),
                 memo_iso_shared(CleanupText),
                 sread(CleanupText, CleanupTerm),
                 'remove-atom'('&self', CleanupTerm, _) )) ]) :-
    space_module('&memo_iso', Module),
    with_metta_module(Module, user:'memoize'(isoshared, true)),
    with_metta_module(Module, user:'is-memoized'(isoshared, true)),
    metta_self_module(Self),
    with_metta_module(Self, user:'is-memoized'(isoshared, true)),
    findall(R, with_metta_module(Module, reduce([isoshared, 1], R)), [8]),
    findall(R, with_metta_module(Self, reduce([isoshared, 1], R)), [8]).

:- end_tests(memo_space_isolation).


% Function-level memo nodes retain the safe over-approximation the old
% metta_memo_dep/6 table provided, but their edges now live in the common
% support graph and need no reverse-graph construction at invalidation time.
:- begin_tests(memo_support_graph,
               [ setup(memo_support_setup),
                 cleanup(memo_support_cleanup) ]).

memo_support_equation(
    "(= (plunit-memo-support-base $x) (+ $x 1))").
memo_support_equation(
    "(= (plunit-memo-support-middle $x) (plunit-memo-support-base $x))").
memo_support_equation(
    "(= (plunit-memo-support-derived $x) (plunit-memo-support-middle $x))").
memo_support_equation(
    "(= (plunit-memo-support-other $x) (+ $x 10))").

memo_support_name('plunit-memo-support-base').
memo_support_name('plunit-memo-support-middle').
memo_support_name('plunit-memo-support-derived').
memo_support_name('plunit-memo-support-other').

memo_support_setup :-
    retractall(silent(_)),
    assertz(silent(true)),
    forall(memo_support_equation(Text), process_metta_string(Text, _)),
    metta_self_module(Module),
    % Memoize callers before callees. Recompiling a callee then repairs its
    % callers through the graph, so every nested call reaches the memo door.
    forall(member(Name,
                  ['plunit-memo-support-derived',
                   'plunit-memo-support-middle',
                   'plunit-memo-support-base',
                   'plunit-memo-support-other']),
           with_metta_module(Module, 'memoize'(Name, true))).

memo_support_cleanup :-
    cache_clear,
    forall(memo_support_name(Name), disable_memoization(Name)),
    forall(memo_support_equation(Text),
           ( sread(Text, Term),
             ( metta_remove_atom('&self', Term, _) -> true ; true ) )),
    retractall(silent(_)),
    assertz(silent(false)).

test(a_leaf_change_invalidates_transitive_callers_only) :-
    metta_self_module(Module),
    findall(R,
            with_metta_module(Module,
                              reduce(['plunit-memo-support-derived', 1], R)),
            [2]),
    findall(R,
            with_metta_module(Module,
                              reduce(['plunit-memo-support-other', 1], R)),
            [11]),
    assertion(metta_memo_entry('plunit-memo-support-derived', Module,
                               _, _, _, _)),
    assertion(metta_memo_entry('plunit-memo-support-other', Module,
                               _, _, _, _)),
    sread("(= (plunit-memo-support-base $x) (+ $x 1))", Base),
    metta_remove_atom('&self', Base, true),
    assertion(\+ metta_memo_entry('plunit-memo-support-base', Module,
                                  _, _, _, _)),
    assertion(\+ metta_memo_entry('plunit-memo-support-middle', Module,
                                  _, _, _, _)),
    assertion(\+ metta_memo_entry('plunit-memo-support-derived', Module,
                                  _, _, _, _)),
    assertion(metta_memo_entry('plunit-memo-support-other', Module,
                               _, _, _, _)).

:- end_tests(memo_support_graph).


% The gap this closes was demonstrated rather than imagined: lib_memo will
% happily cache a side-effecting registered predicate, because nothing recorded
% whether caching it was sound, and the second call then skips the effect.
% PostgreSQL's ladder is the shape, with one deliberate difference: its default
% is the pessimistic rung and this one's is not, because memoization here is
% already opt-in by the CALLER and making silence a refusal would break every
% existing (memoize f) without telling anyone anything they did not know.
:- begin_tests(lib_memo_volatility).

user:plunit_memo_volatile(X, X).
user:plunit_memo_pure(X, X).

test(a_volatile_function_refuses_memoization,
     [ setup(( import_prolog_function(plunit_memo_volatile, _),
               declare_function_volatility(plunit_memo_volatile, volatile) )),
       cleanup(( retractall(user:metta_function_volatility(plunit_memo_volatile, _)),
                 release_function_name(plunit_memo_volatile),
                 unregister_fun_everywhere(plunit_memo_volatile),
                 retractall(user:fun(plunit_memo_volatile)),
                 retractall(user:arity(plunit_memo_volatile, _)) )),
       throws(error(permission_error(memoize, volatile_function,
                                     plunit_memo_volatile), _)) ]) :-
    'memoize'(plunit_memo_volatile, true).

test(an_undeclared_function_still_memoizes,
     [ setup(import_prolog_function(plunit_memo_pure, _)),
       cleanup(( catch('clear-memoize'(plunit_memo_pure, _), _, true),
                 release_function_name(plunit_memo_pure),
                 unregister_fun_everywhere(plunit_memo_pure),
                 retractall(user:fun(plunit_memo_pure)),
                 retractall(user:arity(plunit_memo_pure, _)) )) ]) :-
    assertion(metta_function_cacheable(plunit_memo_pure)),
    'memoize'(plunit_memo_pure, true).

%(cache Name unchecked) in &petta is the caller's declared acceptance of
%staleness: the purity walk is skipped for that function, so an impure body
%memoizes. The declaration is loud and queryable, which is what separates it
%from the silent fail-open default this library used to have.
test(an_unchecked_declaration_memoizes_an_impure_body,
     [ setup(process_metta_string(
                 "(= (plunit-memo-unchecked $k) (let $i (println! $k) $k))", _)),
       cleanup(( catch('clear-memoize'('plunit-memo-unchecked', _), _, true),
                 catch('remove-atom'('&petta',
                                     [cache, 'plunit-memo-unchecked', unchecked],
                                     _), _, true) )) ]) :-
    catch(( 'memoize'('plunit-memo-unchecked', _), Refused = none ),
          error(permission_error(memoize, impure_function, _), _),
          Refused = impure),
    assertion(Refused == impure),
    process_metta_string(
        "!(add-atom &petta (cache plunit-memo-unchecked unchecked))", _),
    'memoize'('plunit-memo-unchecked', true).

%The precedence, pinned: a library's explicit volatile outranks the caller's
%unchecked, because the author said the answers are not reproducible and the
%caller cannot know better.
test(a_volatile_declaration_outranks_unchecked,
     [ setup(( import_prolog_function(plunit_memo_volatile, _),
               declare_function_volatility(plunit_memo_volatile, volatile),
               process_metta_string(
                   "!(add-atom &petta (cache plunit_memo_volatile unchecked))", _) )),
       cleanup(( retractall(user:metta_function_volatility(plunit_memo_volatile, _)),
                 catch('remove-atom'('&petta',
                                     [cache, plunit_memo_volatile, unchecked],
                                     _), _, true),
                 release_function_name(plunit_memo_volatile),
                 unregister_fun_everywhere(plunit_memo_volatile),
                 retractall(user:fun(plunit_memo_volatile)),
                 retractall(user:arity(plunit_memo_volatile, _)) )),
       throws(error(permission_error(memoize, volatile_function,
                                     plunit_memo_volatile), _)) ]) :-
    'memoize'(plunit_memo_volatile, true).

test(an_immutable_function_memoizes,
     [ setup(( import_prolog_function(plunit_memo_pure, _),
               declare_function_volatility(plunit_memo_pure, immutable) )),
       cleanup(( retractall(user:metta_function_volatility(plunit_memo_pure, _)),
                 catch('clear-memoize'(plunit_memo_pure, _), _, true),
                 release_function_name(plunit_memo_pure),
                 unregister_fun_everywhere(plunit_memo_pure),
                 retractall(user:fun(plunit_memo_pure)),
                 retractall(user:arity(plunit_memo_pure, _)) )) ]) :-
    'memoize'(plunit_memo_pure, true).

:- end_tests(lib_memo_volatility).

%The catalog's two profitability overrides are covered from Python, but every
%function they are declared on there is recursive
%[source: bindings/python/tests/test_automatic_tabling.py
%test_automatic_cache_force_and_refuse_overrides, and the same in
%test_an_impure_function_is_never_cached_automatically,
%test_automatic_caching_preserves_multiplicity_and_answer_limit and
%test_cache_decorator]. A recursive name is already a component of the
%source-call graph and arrives through those, so the branch that collects a
%declaration on a name the graph does NOT hold, OverrideFuns in
%memo_automatic_module_plan/2, runs empty in all of them. It is the branch this
%unit is for.
:- begin_tests(memo_cache_override).

forget_cache_override(Fun, Mode) :-
    catch('remove-atom'('&petta', [cache, Fun, Mode], _), _, true).

cache_explanation(Fun, Choice-Reason) :-
    (   seam:automatic_cache_explanation(Fun, Choice, Reason)
    ->  true
    ;   Choice-Reason = none-none
    ).

%Both directions, because a decision that cannot be taken back is a leak
%rather than an override.
test(a_force_declaration_memoizes_a_function_that_calls_nothing,
     [ setup(process_metta_string(
                 "(= (plunit-memo-forced $x) (+ $x 1))", _)),
       cleanup(forget_cache_override('plunit-memo-forced', force)) ]) :-
    cache_explanation('plunit-memo-forced', Before),
    assertion(Before == declined-'not-recursive'),
    process_metta_string(
        "!(add-atom &petta (cache plunit-memo-forced force))", _),
    cache_explanation('plunit-memo-forced', Forced),
    assertion(Forced == forced-declaration),
    assertion(lib_memo:memo_automatic_enabled('plunit-memo-forced', _)),
    forget_cache_override('plunit-memo-forced', force),
    cache_explanation('plunit-memo-forced', After),
    assertion(After == declined-'not-recursive'),
    assertion(\+ lib_memo:memo_automatic_enabled('plunit-memo-forced', _)).

%Reconciliation runs once per source whose call graph changed, and finding the
%declarations used to enumerate every equation in the module and ask each name
%whether it carried one. Declarations are rare and equations are not, so the
%declarations drive now and one indexed probe confirms the name has an
%equation here. Cost of compiling a two-form source containing one source
%call, into a space already holding M unrelated equations [measured
%2026-08-23: 4,831 inferences at M=200 and 37,831 at M=3,200, exactly 11.0 an
%equation, and 2,615 at both after].
plunit_bulk_equations(M, Text) :-
    findall(Line,
            ( between(1, M, I),
              format(atom(Line), "(= (plunit_memo_bulk_b~w) ~w)~n", [I, I]) ),
            Lines),
    atomics_to_string(Lines, Text).

reconcile_cost(M, Cost) :-
    Space = '&plunit_memo_reconcile',
    plunit_bulk_equations(M, Bulk),
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            filereader:process_metta_string(Bulk, _, Space),
            ( statistics(inferences, Before),
              filereader:process_metta_string(
                  "(= (plunit_memo_gee $x) (quote $x))\n(= (plunit_memo_use) (plunit_memo_gee k0))\n",
                  _, Space),
              statistics(inferences, After),
              Cost is After - Before ),
            ( user:clear_native_atoms(Space),
              user:metta_release_space(Space) )),
        erase(SilentRef)).

test(reconciling_a_source_costs_nothing_that_grows_with_the_module) :-
    reconcile_cost(100, Narrow),
    reconcile_cost(1600, Wide),
    assertion(Wide < Narrow * 2).

:- end_tests(memo_cache_override).

%The one TIMED test in the tree, and it has to be. Every caller of
%memo_equation/4 binds the function name, and the store it reads keys on the
%whole source term, so the lookup either takes the deep index or walks every
%equation in the engine. The inference counter cannot tell those apart: a
%candidate rejected by head unification sends the VM to shallow_backtrack,
%which asks for the next clause and resumes without raising the counter
%[source: SWI-Prolog src/pl-vmi.c, VMH(shallow_backtrack) against
%VMH(depart_or_retry_continue); V10.1.13, upstream commit
%fc7ef84b949378b729052c3ade79c90ce5416abb], so the walk reads THREE inferences
%at 20 clauses and three at 20,000. prolog_trace_interception/4 does see it,
%one call of translated_from/2 with 19 redos against one with none at 20
%clauses, but plunit meta-calls its test bodies and cannot trace them.
%
%CPU time is the instrument that is left, and it is safe at this margin:
%process CPU time does not move with machine load, both readings come from one
%process, and the walk measures 17.4x for a 16x module where the index
%measures 1.2 [measured 2026-08-23: 20,000 lookups cost 0.145s at M=200 and
%2.523s at M=3,200 before, 0.009s and 0.012s after].
:- begin_tests(memo_equation_lookup).

plunit_lookup_equations(M, Text) :-
    findall(Line,
            ( between(1, M, I),
              format(atom(Line), "(= (plunit_lookup_b~w) ~w)~n", [I, I]) ),
            Lines),
    atomics_to_string(Lines, Text).

%The first lookup builds the index, so it is spent before the clock starts.
lookup_cputime(M, Reps, Seconds) :-
    atom_concat('&plunit_memo_lookup_', M, Space),
    plunit_lookup_equations(M, Bulk),
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            ( filereader:process_metta_string(Bulk, _, Space),
              filereader:process_metta_string(
                  "(= (plunit_lookup_target $x) 7)\n", _, Space) ),
            ( user:metta_module_space(Module, Space),
              !,
              ( lib_memo:memo_equation(plunit_lookup_target, Module, any, _)
                -> true ; true ),
              statistics(cputime, T0),
              forall(between(1, Reps, _),
                     ( lib_memo:memo_equation(plunit_lookup_target, Module,
                                              any, _)
                       -> true ; true )),
              statistics(cputime, T1),
              Seconds is T1 - T0 ),
            ( user:clear_native_atoms(Space),
              user:metta_release_space(Space) )),
        erase(SilentRef)).

test(one_head_is_found_without_walking_the_other_equations) :-
    lookup_cputime(200, 20000, Narrow),
    lookup_cputime(3200, 20000, Wide),
    assertion(Wide < Narrow * 4).

:- end_tests(memo_equation_lookup).
