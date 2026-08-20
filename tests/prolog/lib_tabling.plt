% Purpose: the tabling control plane's refusals and its invalidation hook.
%   lib_tabling.pl carried three [tested ...] claims naming tests that had
%   never been written; two of them are here, and the third is the pair of
%   examples the header now names by path.
% Guarantees:
%   - a read this cannot resolve to one space predicate, and one that names a
%     foreign space, are both refused rather than tabled without the
%     incremental guarantee [tested: tabling_refuses_unresolvable_reads]
%   - changing an equation drops every table
%     [tested: tabling_equation_change_drops_tables]
%   - the change hook does not prune the handlers loaded after it, so a dual
%     built while tabling is declared is still dropped when its function
%     changes [tested: duals_survive_tabling]
%   - an effect declaration in &petta is the cache-purity claim [tested:
%     a_metta_side_effect_declaration_is_a_purity_claim; commit=WORKTREE]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).
:- initialization(consult('../../lib/lib_tabling.pl')).

% Real MeTTa functions, defined the way a program defines them, because the
% declaration resolves the name to a compiled predicate and refuses one that
% is not there yet.
tabling_definitions("
(= (plt-tab-plain $n) (+ $n 1))
(= (plt-tab-reads $k) (match &plt_tab_space (fact $k $v) $v))
(= (plt-tab-foreign $k) (match &plt_tab_foreign (fact $k $v) $v))
(= (plt-tab-computed $s) (match $s (fact $k $v) $v))
").

user:metta_foreign_space('&plt_tab_foreign').
user:metta_foreign_atoms('&plt_tab_foreign', []).

setup_tabling_suite :-
    retractall(user:silent(_)),
    assertz(user:silent(true)),
    tabling_definitions(Source),
    process_metta_string(Source, _),
    'add-atom'('&plt_tab_space', [fact, a, 1], _).

:- begin_tests(lib_tabling, [setup(setup_tabling_suite)]).

test(a_plain_function_tables) :-
    metta_tabled_decl(['plt-tab-plain', _], true),
    metta_untabled_decl(['plt-tab-plain', _], true).

% Tabling a function that reads a space is sound only when the table and the
% storage predicates it reads both carry the incremental property, which
% needs the read resolved to one dynamic predicate.
test(a_resolvable_space_read_tables) :-
    metta_tabled_decl(['plt-tab-reads', _], true),
    metta_untabled_decl(['plt-tab-reads', _], true).

test(tabling_refuses_unresolvable_reads) :-
    % A computed space: nothing here can say which storage predicate the
    % table would have to watch.
    catch(metta_tabled_decl(['plt-tab-computed', _], true), Computed, true),
    assertion(Computed = error(petta_tabling_unresolved_read(_, _), _)),
    % A foreign space: its atoms do not live in an SWI dynamic predicate at
    % all, so no write to it could ever invalidate the table.
    catch(metta_tabled_decl(['plt-tab-foreign', _], true), Foreign, true),
    assertion(Foreign = error(petta_tabling_foreign_space(_, '&plt_tab_foreign'), _)).

test(tabling_refuses_a_function_that_is_not_defined_yet,
     [throws(error(existence_error(metta_function, _), _))]) :-
    metta_tabled_decl(['plt-tab-absent', _], true).

% Deciding WHICH tables could have read a given equation needs a call graph
% over compiled clauses the engine does not keep, and answering it wrongly is
% a stale answer with no symptom, so every table goes.
test(tabling_equation_change_drops_tables,
     [ cleanup(( catch(metta_untabled_decl(['plt-tab-plain', _], true), _, true),
                 'remove-atom'('&self', [=, ['plt-tab-changed', 1], 9], _) )) ]) :-
    metta_tabled_decl(['plt-tab-plain', _], true),
    %A compiled MeTTa function lives in its space's module, so a test that
    %calls it as a Prolog predicate has to name that module.
    metta_self_module(Self),
    Self:'plt-tab-plain'(1, _),
    tabling_table_count(Before),
    assertion(Before > 0),
    % Any equation, not this function's: the invalidation is deliberately
    % coarse and the hook fires for every compiled equation.
    'add-atom'('&self', [=, ['plt-tab-changed', 1], 9], _),
    tabling_table_count(After),
    assertion(After =:= 0).

% The incremental guarantee was testable only by its EFFECT, a fresh answer,
% which a table rebuilt from scratch produces just as well. tableutil counts
% both halves per subgoal variant, so the invalidation and the re-evaluation
% are visible rather than inferred.
test(tabling_statistics_count_invalidations,
     [ cleanup(( catch(metta_untabled_decl(['plt-tab-reads', _], true), _, true),
                 'remove-atom'('&plt_tab_space', [fact, z, 26], _),
                 'remove-atom'('&plt_tab_space', [fact, a, 2], _) )) ]) :-
    metta_tabled_decl(['plt-tab-reads', _], true),
    metta_self_module(Self),
    Self:'plt-tab-reads'(a, _),
    metta_table_statistics(['plt-tab-reads', _], Before),
    assertion(memberchk([invalidated, 0], Before)),
    assertion(memberchk([reevaluated, 0], Before)),
    % A write to the same space under a key this subgoal does not read.
    % Nothing moves, and it is not the call that hides it: the counters are
    % cumulative, and this one is read BEFORE the next call.
    'add-atom'('&plt_tab_space', [fact, z, 26], _),
    metta_table_statistics(['plt-tab-reads', _], Untouched),
    assertion(memberchk([invalidated, 0], Untouched)),
    % A write under the key it does read.
    'add-atom'('&plt_tab_space', [fact, a, 2], _),
    metta_table_statistics(['plt-tab-reads', _], Invalid),
    assertion(memberchk([invalidated, 1], Invalid)),
    assertion(memberchk([reevaluated, 0], Invalid)),
    % Re-evaluation is on demand, so it takes a call.
    forall(Self:'plt-tab-reads'(a, _), true),
    metta_table_statistics(['plt-tab-reads', _], After),
    assertion(memberchk([reevaluated, 1], After)),
    % SWI's spelling on its side, MeTTa's on this one.
    assertion(memberchk(['complete-call', _], After)).

%Tables belong to the module the tabled predicate is in, which for a MeTTa
%function is its space's module.
tabling_table_count(Count) :-
    metta_self_module(Self),
    aggregate_all(count,
                  ( current_table(Self:Goal, _), Goal \== [] ),
                  Count).

:- end_tests(lib_tabling).

:- begin_tests(lib_tabling_hooks, [setup(setup_tabling_suite)]).

% The defect this guards: both hooks cut after metta_tabling_declared, a
% GLOBAL CONDITION rather than an ownership test, and every caller enumerates
% the hook with forall/2. So once anything was tabled, no handler loaded after
% lib_tabling ran. engine/duals.pl asserts its handler, which appends, so it was
% always in the pruned position: a changed function kept its stale dual and
% (not-provable (pq 2)) answered False from the recompiled path and True from
% the dual at the same time.
test(duals_survive_tabling,
     [ setup(assertz(user:plt_tab_later_handler_ran(no))),
       cleanup(( retractall(user:plt_tab_later_handler_ran(_)),
                 erase(HandlerRef),
                 catch(metta_untabled_decl(['plt-tab-plain', _], true), _, true) )) ]) :-
    % A handler in exactly the position duals.pl's occupies: asserted, so
    % ordered after every clause loaded from a file.
    assertz((user:metta_on_function_changed(_) :-
                 retractall(user:plt_tab_later_handler_ran(_)),
                 assertz(user:plt_tab_later_handler_ran(yes))),
            HandlerRef),
    metta_tabled_decl(['plt-tab-plain', _], true),
    assertion(metta_tabling_declared),
    forall(metta_on_function_changed('plt-tab-plain'), true),
    user:plt_tab_later_handler_ran(Ran),
    assertion(Ran == yes).

test(the_removal_hook_does_not_prune_either,
     [ setup(assertz(user:plt_tab_later_handler_ran(no))),
       cleanup(( retractall(user:plt_tab_later_handler_ran(_)),
                 erase(HandlerRef),
                 catch(metta_untabled_decl(['plt-tab-plain', _], true), _, true) )) ]) :-
    assertz((user:metta_on_function_removed(_) :-
                 retractall(user:plt_tab_later_handler_ran(_)),
                 assertz(user:plt_tab_later_handler_ran(yes))),
            HandlerRef),
    metta_tabled_decl(['plt-tab-plain', _], true),
    forall(metta_on_function_removed('plt-tab-plain'), true),
    user:plt_tab_later_handler_ran(Ran),
    assertion(Ran == yes).

:- end_tests(lib_tabling_hooks).

:- begin_tests(lib_tabling_purity).

%The guard used to be FAIL-OPEN: a goal it did not recognise fell through as
%inert, so tabling accepted seven kinds of impure body and cached four of them
%demonstrably wrong. A random draw answered twice from one draw, a println!
%printed once for two calls, a space write happened once for two calls, and a
%Python operation kept answering after the data it reads had changed
%[measured 2026-08-16, ai-metta-python-seams.md item 1].
%
%An unrecognised goal is UNKNOWN, and unknown in a soundness check is refusal.

%These call metta_tabled_decl/2 directly, as the suite's other tests do: this
%file consults lib_tabling.pl rather than importing the MeTTa library, so the
%`tabled` form is not in scope here and the predicate behind it is.
%Asserting WHICH goal is refused, not merely that something was. Without the
%name these passed for the wrong reason: two pure Prolog primitives were
%missing from the allow-list, so the refusal fired on `atom_string/2` before it
%ever reached the impure goal, and a test that only checks "an error happened"
%cannot tell those apart.
tabling_refuses(Definition, Call, Expected) :-
    process_metta_string(Definition, _),
    catch(( metta_tabled_decl(Call, _), Refused = none ),
          error(metta_impure_goal(Name/_), _),
          Refused = Name),
    assertion(Refused == Expected).

test(a_pure_body_still_tables) :-
    process_metta_string("(= (purity-pure $k) (+ $k 1))", _),
    metta_tabled_decl(['purity-pure', _], Answer),
    assertion(Answer == true),
    metta_untabled_decl(['purity-pure', _], true).

%Six impure expressions and every wrapper a compiled body can put between the
%guard and the goal, run as a MATRIX rather than as a list.
%
%The list was the defect. All six ran unwrapped, and the walk descended only
%arity-one wrappers, so `collapse` (a findall/3) and `forall` (a forall/2) fell
%through and accepted every one of them: `(collapse (random-int 1 1000000))`
%tabled clean and then answered one draw twice. Every body through every
%wrapper is what says a wrapper the walk does not descend cannot pass anything
%[measured 2026-08-17, ai-metta-python-seams.md item 1's review].
purity_impure_body("(+ $k (py-call (builtins.abs $k)))", 'py-call').
purity_impure_body("(+ $k (random-int 0 1000))", 'random-int').
purity_impure_body("(+ $k (get-state purity-cell))", 'get-state').
purity_impure_body("(let $i (add-atom &purity-log (saw $k)) $k)", 'add-atom').
purity_impure_body("(let $i (println! $k) $k)", 'println!').
purity_impure_body("(let $t (current-time) $k)", 'current-time').

purity_wrapper(bare,     "~s").
purity_wrapper(once,     "(once ~s)").
purity_wrapper(collapse, "(collapse ~s)").
purity_wrapper(forall,   "(forall ~s True)").
purity_wrapper(iff,      "(if (> $k 0) ~s 0)").
purity_wrapper(taking,   "(take 1 ~s)").
%The collection forms, which leaked the same way and were found by
%generalising the first fix rather than reported: they compile to maplist/3,
%foldl/4 and include/3, and `maplist` and `foldl` are ALSO MeTTa builtins
%declared pure, so the classifier judged the wrapper inert by name and never
%looked at the closure it called.
purity_wrapper(mapping,   "(map-atom (1 2) $x ~s)").
purity_wrapper(folding,   "(foldl-atom (1 2) 0 $a $x ~s)").
purity_wrapper(filtering, "(filter-atom (1 2) $x ~s)").

test(an_impure_goal_is_refused_inside_every_wrapper,
     [forall(( purity_impure_body(Body, Refused),
               purity_wrapper(Wrapper, Shape) ))]) :-
    format(atom(Name), 'purity-~w-~w', [Wrapper, Refused]),
    format(string(Wrapped), Shape, [Body]),
    format(string(Definition), "(= (~w $k) ~s)", [Name, Wrapped]),
    tabling_refuses(Definition, [Name, _], Refused).

%The other half of the same change. Descending forall exposed the engine's own
%reduce/3, its runtime dispatcher, and refusing THAT would have made every
%pure forall body uncacheable while naming an internal the program never
%wrote. The template's head is fixed at compile time, so the call it reaches
%is classified exactly as a direct call would be.
test(a_pure_body_inside_a_wrapper_still_tables,
     [forall(member(Wrapper, [bare, once, collapse, forall, iff, taking,
                             mapping, folding, filtering]))]) :-
    purity_wrapper(Wrapper, Shape),
    format(atom(Name), 'purity-ok-~w', [Wrapper]),
    format(string(Wrapped), Shape, ["(+ $k 1)"]),
    format(string(Definition), "(= (~w $k) ~s)", [Name, Wrapped]),
    process_metta_string(Definition, _),
    metta_tabled_decl([Name, _], Answer),
    assertion(Answer == true),
    metta_untabled_decl([Name, _], true).

%A template whose head is a VALUE rather than a name is a higher-order call,
%and which function it reaches is decided while the program runs. No
%declaration can answer that, so the refusal says so instead of naming
%reduce/3 and advising a declaration that could not match.
test(a_higher_order_call_is_refused_as_one) :-
    process_metta_string("(= (purity-ho $f $k) (forall (+ $k 1) ($f $k)))", _),
    catch(( metta_tabled_decl(['purity-ho', _, _], _), Refused = none ),
          error(Formal, _),
          Refused = Formal),
    assertion(Refused = metta_higher_order_goal(_)),
    message_to_codes(error(Refused, none), Codes),
    string_codes(Text, Codes),
    assertion(sub_string(Text, _, _, _, "value rather than a name")).

%The refusal names the goal and says what to do about it, rather than being an
%anonymous failure.
test(the_refusal_names_the_goal) :-
    catch(throw(error(metta_impure_goal('py-call'/3), none)),
          Error,
          message_to_codes(Error, Codes)),
    string_codes(Text, Codes),
    assertion(sub_string(Text, _, _, _, "py-call/3")),
    assertion(sub_string(Text, _, _, _, "metta_pure_operation")).

message_to_codes(error(Formal, _), Codes) :-
    phrase(prolog:error_message(Formal), Lines),
    with_output_to(codes(Codes), print_message_lines(current_output, '', Lines)).

%catch/3 is a control construct, so what is INSIDE it is judged. Waving the
%catch through would have hidden every impure goal behind one.
test(an_impure_goal_inside_a_catch_is_still_refused) :-
    tabling_refuses("(= (purity-caught $k) (catch (println! $k)))",
                    ['purity-caught', _], 'println!').

%(cache Name unchecked) in &petta is the caller's declared acceptance of
%staleness: the walk is skipped and the table is PLAIN, not incremental,
%because with reads unresolved there is nothing sound to invalidate on.
test(an_unchecked_declaration_tables_an_impure_body,
     [cleanup(( metta_untabled_decl(['purity-unchecked', _], true),
                'remove-atom'('&petta',
                              [cache, 'purity-unchecked', unchecked], _) ))]) :-
    process_metta_string("(= (purity-unchecked $k) (let $i (println! $k) $k))", _),
    process_metta_string("!(add-atom &petta (cache purity-unchecked unchecked))", _),
    metta_tabled_decl(['purity-unchecked', _], Answer),
    assertion(Answer == true).

%The effect atom register_op accepts from Python, made from inside the
%language instead: the walk reads (effect Name immutable) out of &petta's
%own storage, and removal withdraws it.
test(a_metta_side_effect_declaration_is_a_purity_claim,
     [cleanup(catch('remove-atom'('&petta',
                                  [effect, 'purity-eff', immutable], _),
                    _, true))]) :-
    assertion(\+ metta_pure_operation('purity-eff')),
    process_metta_string("!(add-atom &petta (effect purity-eff immutable))", _),
    assertion(metta_pure_operation('purity-eff')),
    'remove-atom'('&petta', [effect, 'purity-eff', immutable], _),
    assertion(\+ metta_pure_operation('purity-eff')).

:- end_tests(lib_tabling_purity).
