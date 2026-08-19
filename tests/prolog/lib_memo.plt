% Purpose: direct PlUnit coverage for memoization storage, eviction, and the
%   per-space keying that keeps one space's cache out of another's answers.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).
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