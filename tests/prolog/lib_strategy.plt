% Purpose: prove lib_strategy's reified plans cross the Prolog engine's normal
%   library, storage, translator, traversal, and typed-scheme seams.
% Assumes: run from tests/prolog so ../../engine/metta.pl and the repository's
%   lib/ directory resolve from this worktree.
% Guarantees:
%   - strategy-apply is admitted as a translator rule while a stored plan stays
%     queryable data [tested: lib_strategy:stored_plans_lower_through_the_translator;
%     commit=WORKTREE]
%   - left-biased choice, strict traversal, and TP/TU filtering retain their
%     observable laws at the engine door [tested:
%     lib_strategy:choice_uses_the_complete_left_result_bag,
%     lib_strategy:traversals_keep_their_strict_order,
%     lib_strategy:typed_schemes_filter_by_the_declared_arrow; commit=WORKTREE]

:- ensure_loaded('../../engine/metta.pl').

strategy_eval_string(Text, Results) :-
    sread(Text, Term),
    findall(Result, eval(Term, Result), Results).

strategy_add_form(Text) :-
    sread(Text, Form),
    'add-atom'('&self', Form, _).

load_strategy_fixture :-
    strategy_eval_string("(import! &self (library lib_strategy))", _),
    maplist(strategy_add_form,
            [ "(= (plunit-strategy-step plunit-a) plunit-b)",
              "(= (plunit-strategy-step plunit-b) plunit-c)",
              "(= (plunit-strategy-step $x) Empty)",
              "(= (plunit-strategy-many plunit-a) plunit-left-1)",
              "(= (plunit-strategy-many plunit-a) plunit-left-2)",
              "(= (plunit-strategy-right plunit-a) plunit-wrong)",
              "(= (plunit-strategy-cap plunit-a) plunit-A)",
              "(= (plunit-strategy-cap $x) Empty)",
              "(: plunit-strategy-type Type)",
              "(: plunit-strategy-other Type)",
              "(: plunit-typed-a plunit-strategy-type)",
              "(: plunit-typed-b plunit-strategy-other)",
              "(: plunit-strategy-preserve (-> plunit-strategy-type plunit-strategy-type))",
              "(= (plunit-strategy-preserve $x) (plunit-marked $x))",
              "(plunit-strategy-policy fast (seq plunit-strategy-step plunit-strategy-step))"
            ]).

:- initialization(load_strategy_fixture).

:- begin_tests(lib_strategy).

test(stored_plans_lower_through_the_translator) :-
    assertion(translator_rule('strategy-apply')),
    strategy_eval_string(
        "(match &self (plunit-strategy-policy fast $strategy) $strategy)",
        Stored),
    assertion(Stored == [[seq, 'plunit-strategy-step',
                          'plunit-strategy-step']]),
    strategy_eval_string(
        "(match &self (plunit-strategy-policy fast $strategy) (strategy-apply $strategy plunit-a))",
        Applied),
    assertion(Applied == ['plunit-c']).

test(choice_uses_the_complete_left_result_bag) :-
    strategy_eval_string(
        "(choice plunit-strategy-many plunit-strategy-right plunit-a)",
        Results),
    assertion(Results == ['plunit-left-1', 'plunit-left-2']).

test(traversals_keep_their_strict_order) :-
    strategy_eval_string(
        "(topdown (try plunit-strategy-cap) (plunit-h plunit-a))",
        Forgiving),
    assertion(Forgiving == [['plunit-h', 'plunit-A']]),
    strategy_eval_string(
        "(topdown plunit-strategy-cap (plunit-h plunit-a))",
        Strict),
    assertion(Strict == []).

test(typed_schemes_filter_by_the_declared_arrow) :-
    strategy_eval_string(
        "(◁ plunit-strategy-preserve TP plunit-typed-a)", Good),
    assertion(Good == [['plunit-marked', 'plunit-typed-a']]),
    strategy_eval_string(
        "(◁ plunit-strategy-preserve TP plunit-typed-b)", WrongType),
    assertion(WrongType == []).

:- end_tests(lib_strategy).
