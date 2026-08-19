% Purpose: report the compile-time rule set's overlaps and its termination.
%     `add-translator-rule!` registers a NAME (src/metta.pl:4499 keeps a set of
%     them), and the rules themselves are the space's own (= Lhs Rhs) atoms
%     whose left-hand side is rooted at one of those names, plus every equation
%     reachable from their right-hand sides, because a translator rule's body
%     is EVALUATED while the program is being compiled. Two libraries that
%     register overlapping rules are unchecked today and the outcome is decided
%     by assertion order: with (= (m2 a) (quote one)) before (= (m2 $x) (quote
%     two)) the program answers one, and with the two lines swapped it answers
%     two [measured 2026-08-19]. This says which pairs overlap, on which term,
%     and what each of them gives.
%
%     Confluence of a TERMINATING system is decidable, by Knuth and Bendix
%     (1970): finitely many critical pairs, each checked for joinability. That
%     is why termination is reported first and is not decoration: it is the
%     precondition. It is also why the analysis reports a bounded search that
%     missed as `unknown` and never as a negative result.
%
%     Which side of the decidability line the rule set is on TODAY: a
%     translator rule is an ordinary MeTTa equation, whether it applies is
%     decided by matching its head, and the extracted system is therefore
%     UNCONDITIONAL and inside the fragment Knuth and Bendix decide. What the
%     extraction does NOT model is the engine's strategy on top of that
%     relation: a rule whose body has no answer is skipped and the next clause
%     is tried, measured 2026-08-19 with (= (m3 a) (helper zzz)) ahead of
%     (= (m3 $x) (quote two)) and helper defined only at b, which answers two.
%     So the branch the compiler takes is the first alternative whose body
%     succeeds, not simply the first; where every body succeeds, assertion
%     order alone decides.
%
%     Nothing here survives P2.11, which makes that skip a first-class REFUSAL
%     with its own words. A rule that may decline is a CONDITIONAL rule, and
%     confluence of terminating conditional systems is undecidable in general,
%     so a guarded rule set has to be PROVED confluent rather than decided and
%     this tool has to say which rules it can still answer for. Said before
%     P2.11 lands, on purpose.
% Assumes:
%     - the working directory is tests/prolog, which is where check.sh runs
%       every Prolog lane from.
%     - the engine consults into `user`, so use_module of src/trs.pl here
%       puts its ==> operator in `user` at priority 800. SWI's own ==> is the
%       single-sided-unification rule operator at 1200, and no Prolog file in
%       this tree writes one; the only other ==> is MeTTa data in
%       lib/lib_nars.metta, which the character-level parser in src/parser.pl
%       reads without consulting Prolog's operator table [measured 2026-08-19].
%     - a MeTTa expression is a proper list, so (f a b) has a first-order term
%       reading f(a,b). expr_term/2 raises rather than guessing on anything
%       else.
% Guarantees:
%     - translator_confluence_report/0 prints every overlap it finds with the
%       two rules, the position, the overlapped term and the two results, and
%       exits 0 whatever it finds: it is a REPORT surface
%       [tested: test_overlapping_translator_rules_are_reported_with_the_overlap_named].
%     - translator_confluence_gate/0 is the same analysis and FAILS the run on
%       an overlap that is not joined, which is the promotion path once the
%       shipped rule set is known clean [assumed 2026-08-19: no lane runs it
%       yet, and the shipped rule set has no divergent overlap today].
%     - translator_confluence_selftest/0 fails unless the analysis puts each of
%       five planted rule sets on the side its own shape predicts, so a report
%       of "no overlaps" cannot come from a detector that stopped detecting
%       [tested: test_the_detector_is_run_against_its_own_planted_rule_sets].
%     - termination is ESTABLISHED with the route that decided it, or the
%       failure is NAMED with the step that failed. There is no third answer
%       [tested: test_the_compile_time_rule_set_is_shown_terminating_or_the_failure_is_named].
% Decides:
%     - the joinability search is bounded at 5 rewrite steps per branch. A
%       compile-time macro that needs more than five steps to reconverge is
%       past the point where a report would help anyone, and the bound is
%       printed with the verdict so an `unknown` is attributable.
%     - the abstract term defaults to all-v, every argument possibly a
%       variable, because a translator rule is applied by CALLING its compiled
%       clause and a MeTTa source argument may be a variable. A caller that
%       knows better passes its own.
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: None

:- use_module('../../src/trs.pl').
:- use_module('../../src/narrowing.pl').
:- use_module(library(lists)).
:- use_module(library(apply)).

% How deep the joinability search goes on each branch of a critical pair.
join_bound(5).

%%%% Reading the rule set out of a loaded engine %%%%

% A MeTTa expression as a first-order term: (f a b) becomes f(a,b), so that the
% rewriting machinery sees f as a function symbol. Left as a list it would see
% every expression as a nest of cons cells sharing one functor, which would
% make positions meaningless and give the recursive path order a single symbol
% to build a precedence out of. The empty expression and an expression whose
% head is not a symbol take the reserved '$expr' functor; a MeTTa source token
% starting with $ parses as a variable, so no symbol can collide with it.
expr_term(V, V) :- var(V), !.
expr_term([H|Args], T) :-
    atom(H), is_list(Args), Args \== [],
    !,
    maplist(expr_term, Args, As),
    T =.. [H|As].
expr_term(E, T) :-
    is_list(E),
    !,
    maplist(expr_term, E, Es),
    T =.. ['$expr'|Es].
expr_term(A, A) :- atomic(A), !.
expr_term(E, _) :- throw(error(type_error(metta_expression, E), _)).

term_expr(V, V) :- var(V), !.
term_expr('$expr', []) :- !.
term_expr(T, E) :-
    compound(T),
    !,
    T =.. [F|As],
    maplist(term_expr, As, Es),
    (   F == '$expr' -> E = Es ;   E = [F|Es] ).
term_expr(A, A).

% Every equation of the space, as head name and rule.
space_equation(Space, Head, L ==> R) :-
    user:'get-atoms'(Space, ['=', Lhs, Rhs]),
    nonvar(Lhs),
    Lhs = [Head|_],
    atom(Head),
    expr_term(Lhs, L),
    expr_term(Rhs, R).

% The compile-time rule set: the registered names, closed under the equations
% their right-hand sides reach. A translator rule's body runs at compile time,
% so a function it calls is part of what has to terminate for compilation to
% terminate; leaving those out would report on a rule set the compiler never
% executes.
compile_time_rules(Space, Registered, Names, Rules) :-
    findall(N, user:translator_rule(N), Registered0),
    sort(Registered0, Registered),
    reachable_names(Space, Registered, Registered, Names),
    findall(Rule,
            ( member(Name, Names), space_equation(Space, Name, Rule) ),
            Rules).

reachable_names(Space, Frontier, Seen, Names) :-
    findall(Called,
            ( member(Name, Frontier),
              space_equation(Space, Name, _ ==> R),
              called_name(R, Called),
              \+ memberchk(Called, Seen),
              once(space_equation(Space, Called, _)) ),
            New0),
    sort(New0, New),
    (   New == []
    ->  Names = Seen
    ;   append(Seen, New, Seen1),
        sort(Seen1, Seen2),
        reachable_names(Space, New, Seen2, Names) ).

called_name(T, F) :-
    sub_term(Sub, T),
    nonvar(Sub),
    compound(Sub),
    functor(Sub, F, _),
    F \== '$expr'.

%%%% The analysis %%%%

% analyse(+Registered, +Rules, -Analysis). Analysis is
% analysis(Termination, Verdicts), with one verdict per critical pair worth
% reporting.
analyse(Registered, Rules, analysis(Termination, Verdicts)) :-
    termination(Registered, Rules, Termination),
    join_bound(Fuel),
    confluence_check(Rules, Fuel, All),
    exclude(trivial_self_overlap, All, Verdicts).

verdict_is(Kind, verdict(_,_,_,_,_,Kind)).

% A rule always overlaps a renamed copy of ITSELF at the root, and that
% overlap's two sides are the same term twice. Huet's definition of a critical
% pair excludes it for that reason, and the enumerator keeps it only so that
% the family it enumerates is the one the Lean side enumerates.
trivial_self_overlap(verdict(I, I, [], _, _, _)).

% One termination question per REGISTERED name, because the compiler may call
% any of them and the mode declaration is about the entry. Taking the first
% rule's head instead asks about whichever name sorted first, which is a helper
% the closure pulled in as often as it is an entry.
termination(Registered, Rules, Termination) :-
    findall(Abstract-Outcome,
            ( member(Name, Registered),
              entry_abstraction(Rules, Name, Abstract),
              narrowing_terminates(Rules, Abstract, Outcome) ),
            Outcomes),
    (   Outcomes == []
    ->  Termination = no_entry
    ;   member(Failed-not_established(Reason), Outcomes)
    ->  Termination = not_established(Failed, Reason)
    ;   Termination = established(Outcomes) ).

% The honest default declaration: every argument may be a variable, since a
% translator rule is applied by unification against whatever the source wrote
% and the source may have written a variable.
entry_abstraction(Rules, Name, Abstract) :-
    member(L ==> _, Rules),
    functor(L, Name, N),
    !,
    length(Modes, N),
    maplist(=(v), Modes),
    Abstract =.. [Name|Modes].

%%%% Printing %%%%

print_analysis(Rules, analysis(Termination, Verdicts)) :-
    length(Rules, RuleCount),
    defined_symbols(Rules, Ds),
    length(Ds, SymbolCount),
    format("compile-time rule set: ~d rules over ~d defined symbols~n",
           [RuleCount, SymbolCount]),
    forall(nth1(I, Rules, Rule), print_rule(I, Rule)),
    print_termination(Rules, Termination),
    include(verdict_is(joined), Verdicts, Joined),
    include(verdict_is(counterexample), Verdicts, Divergent),
    include(verdict_is(unknown), Verdicts, Unknown),
    length(Verdicts, Overlaps),
    length(Joined, JoinedCount),
    length(Divergent, DivergentCount),
    length(Unknown, UnknownCount),
    join_bound(Fuel),
    format("overlaps: ~d between distinct rules or below the root, ~d joined, \c
            ~d divergent, ~d unresolved within ~d steps~n",
           [Overlaps, JoinedCount, DivergentCount, UnknownCount, Fuel]),
    forall(( member(V, Divergent) ; member(V, Unknown) ),
           print_overlap(Rules, V)),
    print_conclusion(Termination, DivergentCount, UnknownCount).

print_rule(I, L ==> R) :-
    term_expr(L, LE),
    term_expr(R, RE),
    user:swrite(['=', LE, RE], Text),
    format("  ~d. ~w~n", [I, Text]).

print_termination(_, no_entry) :-
    format("termination: NOT ESTABLISHED. no registered name has an \c
            equation, so there is no entry to declare a mode for~n").
print_termination(_, established(Outcomes)) :-
    length(Outcomes, N),
    format("termination: ESTABLISHED. All ~d registered entries, by safe \c
            argument filtering, then the argument filtering transformation, \c
            then a recursive path order.~n", [N]),
    forall(member(Abstract-established(route(Filtering, Filtered,
                                             rpo(Precedence, _))), Outcomes),
           ( length(Filtered, M),
             format("  entry ~w, ~d filtered rules~n", [Abstract, M]),
             format("    filtering: ~q~n", [Filtering]),
             format("    precedence, lowest first: ~q~n", [Precedence]) )).
print_termination(_, not_established(Abstract, no_rpo_order(Filtered))) :-
    !,
    format("termination: NOT ESTABLISHED. no_rpo_order at entry ~w~n",
           [Abstract]),
    format("  no precedence and status assignment orients every rule of the \c
            filtered system left to right:~n"),
    forall(member(Rule, Filtered),
           ( copy_term(Rule, Shown),
             numbervars(Shown, 0, _),
             format("    ~q~n", [Shown]) )).
print_termination(Rules, not_established(Abstract, Reason)) :-
    functor(Reason, Name, _),
    (   entry_dependent(Name)
    ->  format("termination: NOT ESTABLISHED. ~w at entry ~w~n",
               [Reason, Abstract])
    ;   format("termination: NOT ESTABLISHED. ~w, which holds of the rule set \c
                whatever the entry is~n", [Reason]) ),
    print_termination_rule(Rules, Reason).

% A precondition failure is a property of the rule SET and holds whatever the
% entry is; only the three steps after it read the mode declaration. Naming an
% entry beside a set-level reason would suggest a different entry could change
% the answer.
entry_dependent(unknown_entry).
entry_dependent(no_safe_filtering).
entry_dependent(no_rpo_order).

print_termination_rule(Rules, Reason) :-
    arg(1, Reason, I),
    integer(I),
    nth1(I, Rules, Rule),
    !,
    print_rule(I, Rule).
print_termination_rule(_, _).

% Which theorem each line is standing on. The critical pair lemma is Huet's and
% needs no termination: a critical pair whose two sides have distinct normal
% forms refutes LOCAL confluence outright. Turning local confluence into
% confluence is Newman's lemma and needs termination, which is why the positive
% conclusion is the only one that waits on the line above it
% [source: Gerard Huet, "Confluent Reductions: Abstract Properties and
% Applications to Term Rewriting Systems", JACM 27(4):797-821, 1980; M. H. A.
% Newman, "On theories with a combinatorial definition of equivalence", Annals
% of Mathematics 43(2):223-243, 1942].
print_conclusion(_, Divergent, _) :-
    Divergent > 0,
    !,
    format("conclusion: NOT LOCALLY CONFLUENT. ~d critical pairs reach \c
            distinct normal forms, so which answer the compiler gives is \c
            decided by the order the rules were asserted in, among the \c
            alternatives whose own bodies have an answer.~n", [Divergent]).
print_conclusion(_, _, Unknown) :-
    Unknown > 0,
    !,
    format("conclusion: UNDECIDED. ~d critical pairs did not join within the \c
            bound, which says nothing about whether they join further out.~n",
           [Unknown]).
print_conclusion(established(_), _, _) :-
    !,
    format("conclusion: CONFLUENT. Every critical pair joins and the rule set \c
            terminates.~n").
print_conclusion(_, _, _) :-
    format("conclusion: LOCALLY CONFLUENT. Every critical pair joins, but \c
            termination is not established, and without it local confluence \c
            does not give confluence.~n").

print_overlap(Rules, verdict(I, J, Pos, L, R, Kind)) :-
    nth1(I, Rules, OuterL ==> _),
    nth1(J, Rules, InnerL ==> _),
    term_expr(OuterL, OuterE),
    term_expr(InnerL, InnerE),
    user:swrite(OuterE, OuterText),
    user:swrite(InnerE, InnerText),
    term_expr(L, LE),
    term_expr(R, RE),
    user:swrite(LE, LText),
    user:swrite(RE, RText),
    format("  OVERLAP ~w: rule ~d ~w and rule ~d ~w at position ~w~n",
           [Kind, I, OuterText, J, InnerText, Pos]),
    format("    rule ~d gives ~w~n", [I, LText]),
    format("    rule ~d gives ~w~n", [J, RText]).

%%%% Entry points %%%%

% The shipped configuration, loaded quietly: the two libraries that register a
% translator rule today.
load_engine :-
    set_prolog_flag(argv, [backends]),
    user:consult('../../src/metta.pl'),
    retractall(user:silent(_)),
    assertz(user:silent(true)).

shipped_library('../../lib/lib_patrick.metta').
shipped_library('../../lib/lib_spaces.metta').

translator_confluence_report :-
    load_engine,
    forall(shipped_library(File), user:load_metta_file(File, _)),
    report_space('&self').

% The same report over named MeTTa files instead of the shipped libraries,
% which is what a caller planting an overlap needs. Read argv BEFORE
% load_engine, which overwrites it so that src/metta.pl globs the backends.
translator_confluence_main :-
    current_prolog_flag(argv, Argv),
    (   Argv == []
    ->  translator_confluence_report
    ;   load_engine,
        forall(member(File, Argv), user:load_metta_file(File, _)),
        report_space('&self') ).

translator_confluence_gate :-
    load_engine,
    forall(shipped_library(File), user:load_metta_file(File, _)),
    compile_time_rules('&self', Registered, _, Rules),
    (   Rules == []
    ->  true
    ;   analyse(Registered, Rules, Analysis),
        Analysis = analysis(_, Verdicts),
        include(verdict_is(counterexample), Verdicts, Divergent),
        (   Divergent == []
        ->  true
        ;   print_analysis(Rules, Analysis),
            halt(1) ) ).

report_space(Space) :-
    print_decidable_fragment,
    compile_time_rules(Space, Registered, Names, Rules),
    length(Registered, EntryCount),
    length(Names, NameCount),
    format("registered translator rules: ~d, closed over what they call: ~d \c
            names~n", [EntryCount, NameCount]),
    forall(member(N, Names),
           (   memberchk(N, Registered)
           ->  format("  ~w (registered)~n", [N])
           ;   format("  ~w (reached)~n", [N]) )),
    (   Rules == []
    ->  format("no equations found for them, so there is nothing to \c
                analyse~n")
    ;   analyse(Registered, Rules, Analysis),
        print_analysis(Rules, Analysis) ).

% Which fragment this report can answer in, printed with every report rather
% than left in a header, because a verdict is worth what its fragment is worth.
print_decidable_fragment :-
    format("decidable fragment: confluence is decidable for TERMINATING \c
            rewrite systems, by Knuth and Bendix (1970), since such a system \c
            has finitely many critical pairs and each one's joinability \c
            terminates.~n"),
    format("  today's translator rules are UNCONDITIONAL: a rule is an \c
            ordinary MeTTa equation and whether it applies is decided by \c
            matching its head, so this rule set sits inside that fragment.~n"),
    format("  a guarded rule, which P2.11 introduces, is a CONDITIONAL rule, \c
            and confluence of terminating conditional systems is undecidable \c
            in general; a guarded rule set has to be PROVED confluent rather \c
            than decided.~n").

%%%% The selftest: does the analysis still discriminate? %%%%
%
% Five planted rule sets, each on a side its own shape predicts. Without this
% a report of "no overlaps" and a detector that stopped detecting look the
% same, which is the failure mode reachability.pl's own selftest exists for.

planted(one_rule_per_head_has_no_divergence,
        [ f(a) ==> b, g(c) ==> d ],
        divergent(0)).
planted(two_rules_that_unify_diverge,
        [ f(a) ==> b, f(_) ==> c ],
        divergent(2)).
planted(an_inner_overlap_is_found_too,
        [ f(g(_)) ==> a, g(b) ==> c ],
        divergent(1)).
planted(a_joinable_overlap_is_not_divergent,
        [ f(a) ==> b, f(_) ==> b ],
        divergent(0)).
planted(a_recursive_rule_set_is_not_shown_terminating,
        [ f(s(X)) ==> g(f(h(X))) ],
        termination(not_established)).

translator_confluence_selftest :-
    findall(Name-Expected-Got,
            ( planted(Name, Rules, Expected),
              planted_outcome(Rules, Expected, Got),
              Got \== Expected ),
            Wrong),
    (   Wrong == []
    ->  format("translator confluence selftest: ~d planted rule sets, each on \c
                the side its shape predicts~n", [5])
    ;   forall(member(N-E-G, Wrong),
               format("planted ~w: expected ~w, got ~w~n", [N, E, G])),
        halt(1) ).

planted_outcome(Rules, divergent(_), divergent(Count)) :-
    !,
    join_bound(Fuel),
    confluence_check(Rules, Fuel, Verdicts),
    include(verdict_is(counterexample), Verdicts, Divergent),
    length(Divergent, Count).
planted_outcome(Rules, termination(_), termination(Kind)) :-
    Rules = [L ==> _|_],
    functor(L, Name, _),
    termination([Name], Rules, Outcome),
    functor(Outcome, Kind, _).
