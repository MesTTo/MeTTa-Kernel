% Purpose: report translator and typing rule-family overlaps, and the
%     translator family's termination.
%     `add-translator-rule!` registers a NAME (engine/translator_rules.pl's
%     translator_rule/2 keeps the registry), and the rules themselves arrive through
%     two doors, the space's own (= Lhs Rhs) atoms and the engine's
%     prelude_equation/2 register for the shipped tier
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
%     Which side of the decidability line a rule set is on is answered PER
%     SET and printed with the report. A rule that only matches is
%     unconditional and inside the fragment Knuth and Bendix decide; a rule
%     that can refuse is not. What the
%     extraction does NOT model is the engine's strategy on top of that
%     relation: a rule whose body has no answer is skipped and the next clause
%     is tried, measured 2026-08-19 with (= (m3 a) (helper zzz)) ahead of
%     (= (m3 $x) (quote two)) and helper defined only at b, which answers two.
%     So the branch the compiler takes is the first alternative whose body
%     succeeds, not simply the first; where every body succeeds, assertion
%     order alone decides.
%
%     A rule may now also DECLINE with its own words, which is a first-class
%     refusal rather than that silent skip. A rule that may decline is a
%     CONDITIONAL rule, and confluence of terminating conditional systems is
%     undecidable in general, so this tool COUNTS the rules of the set it is
%     given that can refuse and reports the set CONDITIONAL when any can,
%     instead of going on claiming the fragment it used to sit in.
% Assumes:
%     - the working directory is tests/prolog, which is where check.sh runs
%       every Prolog lane from.
%     - the engine consults into `user`, so use_module of engine/trs.pl here
%       puts its ==> operator in `user` at priority 800. SWI's own ==> is the
%       single-sided-unification rule operator at 1200, and no Prolog file in
%       this tree writes one; the only other ==> is MeTTa data in
%       lib/lib_nars.metta, which the character-level parser in engine/parser.pl
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
%       an overlap that is not joined, and on a shipped rule that can REFUSE,
%       because the critical-pair criterion decides an unconditional set and
%       says nothing about a conditional one
%       [tested: the translator-confluence-gate lane in check.sh].
%     - translator_confluence_selftest/0 fails unless the analysis puts each of
%       five planted rule sets on the side its own shape predicts, so a report
%       of "no overlaps" cannot come from a detector that stopped detecting
%       [tested: test_the_detector_is_run_against_its_own_planted_rule_sets].
%     - termination is ESTABLISHED with the route that decided it, or the
%       failure is NAMED with the step that failed. There is no third answer
%       [tested: test_the_compile_time_rule_set_is_shown_terminating_or_the_failure_is_named].
%     - a rule that DECLARED its right-hand-only variables exempt is analysed
%       with them replaced by a constant, and the exemption is printed with
%       its reason beside the termination line, so a waived precondition is
%       stated rather than assumed
%       [tested: test_the_shipped_translator_rules_bind_their_right_hand_variables;
%       commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%     - diagnostic overlap terms use presentation text, including the
%       first-order compounds and numbered-variable carriers that are not
%       serializable MeTTa values [tested:
%       test_the_compile_time_rule_set_is_shown_terminating_or_the_failure_is_named;
%       commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%     - a rule set holding a rule that can REFUSE is reported CONDITIONAL,
%       naming how many of its rules can refuse, and its conclusion is NOT
%       DECIDED rather than a critical-pair verdict, because a guard can make
%       a peak unreachable
%       [tested: test_a_translator_rule_can_decline_with_its_own_words;
%       commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%     - a registered name that already had a meaning is printed with the kind
%       of meaning it went ahead of, read from the engine's
%       translator_rule_override/2 rather than recomputed here
%       [tested: test_overriding_a_protected_name_is_refused_with_the_name;
%       commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%     - the typing family is read from typing_rule_entry/7, the checker's own
%       registry; user/user and user/shipped overlaps are named, while a
%       refusing or deferring rule is reported CONDITIONAL rather than given
%       an unconditional confluence verdict
%       [tested: test_a_user_typing_rule_participates_like_a_shipped_one;
%       commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
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

:- use_module('../../engine/trs.pl').
:- use_module('../../engine/narrowing.pl').
:- use_module(library(lists)).
:- use_module(library(apply)).

% A descriptor gives both families the same collection-and-reporting door.
% The translator family has a first-order rewrite relation and therefore the
% termination/critical-pair analysis below. The typing family has explicit
% refusal and defer outcomes, so its descriptor routes overlaps to the
% conditional report instead of pretending the unconditional checker decides
% them. Duck, Haemmerle and Sulzmann use confluence as the correctness
% criterion for CHR-based type inference, which is the precedent for keeping
% these rules in this analyzer rather than a disconnected lint
% [source: Duck, Haemmerle, Sulzmann, "On Termination, Confluence and
% Consistent CHR-based Type Inference", arXiv:1405.3393; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
rule_family(translator, translator_family_state, print_translator_family).
rule_family(typing, typing_family_state, print_typing_family).

report_rule_family(Family, Space) :-
    rule_family(Family, Collector, Printer),
    call(Collector, Space, State),
    call(Printer, State).

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

% A rule reaches the analysis through one of two doors. The space's own
% (= ...) atoms are the user tier; the prelude's equations never become
% atoms (the loader compiles them into &self's module), so the engine's
% prelude_equation/2 register is the shipped tier's door. Reading only
% the first missed the eight prelude rules while listing their names as
% registered [tested: translator_confluence_selftest].
rule_equation(Space, Head, Rule) :-
    space_equation(Space, Head, Rule).
rule_equation(_, Head, Rule) :-
    prelude_rule_equation(Head, Rule).

prelude_rule_equation(Head, L ==> R) :-
    user:prelude_equation(Head, ['=', Lhs, Rhs]),
    nonvar(Lhs),
    Lhs = [Head|_],
    expr_term(Lhs, L),
    expr_term(Rhs, R).

% The compile-time rule set: the registered names, closed under the equations
% their right-hand sides reach. A translator rule's body runs at compile time,
% so a function it calls is part of what has to terminate for compilation to
% terminate; leaving those out would report on a rule set the compiler never
% executes.
compile_time_rules(Space, Registered, Names, SpaceRules, PreludeRules) :-
    findall(N, user:translator_rule(N), Registered0),
    sort(Registered0, Registered),
    reachable_names(Space, Registered, Registered, Names),
    findall(Rule,
            ( member(Name, Names), space_equation(Space, Name, Rule) ),
            SpaceRules),
    findall(Rule,
            ( member(Name, Names), prelude_rule_equation(Name, Rule) ),
            PreludeRules).

reachable_names(Space, Frontier, Seen, Names) :-
    findall(Called,
            ( member(Name, Frontier),
              rule_equation(Space, Name, _ ==> R),
              called_name(R, Called),
              \+ memberchk(Called, Seen),
              once(rule_equation(Space, Called, _)) ),
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

%%%% The typing-rule family %%%%

translator_family_state(Space,
                        translator_state(Space, Registered, Names,
                                         SpaceRules, PreludeRules)) :-
    compile_time_rules(Space, Registered, Names, SpaceRules, PreludeRules).

typing_family_state(Space, typing_state(Entries, Overlaps)) :-
    user:space_module(Space, Module),
    findall(typing(Name, user, Family, Actual, Expected, Outcome),
            user:registered_typing_rule(user, Module, Name, Family,
                                        Actual, Expected, Outcome),
            UserEntries),
    findall(typing(Name, shipped, Family, Actual, Expected, Outcome),
            user:registered_typing_rule(shipped, '*', Name, Family,
                                        Actual, Expected, Outcome),
            ShippedEntries),
    append(UserEntries, ShippedEntries, Entries),
    findall(Overlap, typing_overlap(Entries, Overlap), Overlaps).

% Only overlaps involving a user declaration are policy choices the program
% can affect. Shipped/shipped intersections remain visible as the shipped rule
% count, but do not drown the user report in compatible wildcard ladders.
typing_overlap(Entries,
               typing_overlap(NameA, TierA, NameB, TierB, Family,
                              Actual, Expected, Kind, OutcomeA, OutcomeB)) :-
    nth1(I, Entries,
         typing(NameA, TierA, Family, ActualA, ExpectedA, OutcomeA)),
    nth1(J, Entries,
         typing(NameB, TierB, Family, ActualB, ExpectedB, OutcomeB)),
    I < J,
    ( TierA == user ; TierB == user ),
    copy_term(ActualA-ExpectedA-ActualB-ExpectedB,
              LeftActual-LeftExpected-RightActual-RightExpected),
    LeftActual = RightActual,
    LeftExpected = RightExpected,
    Actual = LeftActual,
    Expected = LeftExpected,
    typing_overlap_kind(OutcomeA, OutcomeB, Kind).

typing_overlap_kind(Left, Right, conditional(refusal)) :-
    ( Left = [refuse, _] ; Right = [refuse, _] ),
    !.
typing_overlap_kind(Left, Right, conditional(guarded_defer)) :-
    ( Left == defer ; Right == defer ),
    !.
typing_overlap_kind(accept, accept, joined).

print_typing_family(typing_state(Entries, Overlaps)) :-
    include(typing_entry_tier(user), Entries, User),
    include(typing_entry_tier(shipped), Entries, Shipped),
    length(User, UserCount),
    length(Shipped, ShippedCount),
    format("typing rule family: ~d user rules, ~d shipped rules~n",
           [UserCount, ShippedCount]),
    forall(member(Entry, Entries), print_typing_rule(Entry)),
    length(Overlaps, OverlapCount),
    include(typing_overlap_conditional, Overlaps, Conditional),
    length(Conditional, ConditionalCount),
    format("typing overlaps: ~d involving a user rule, ~d conditional~n",
           [OverlapCount, ConditionalCount]),
    forall(member(Overlap, Overlaps), print_typing_overlap(Overlap)),
    format("typing conclusion: refusing and guarded-defer overlaps are \c
            CONDITIONAL proof obligations, not decisions of the \c
            unconditional critical-pair checker.~n").

typing_entry_tier(Tier, typing(_, Tier, _, _, _, _)).

typing_overlap_conditional(
    typing_overlap(_, _, _, _, _, _, _, conditional(_), _, _)).

print_typing_rule(typing(Name, Tier, Family, Actual, Expected, Outcome)) :-
    copy_term(Actual-Expected-Outcome, Shown),
    numbervars(Shown, 0, _),
    Shown = ShownActual-ShownExpected-ShownOutcome,
    format("  ~w rule ~w: ~w(~q, ~q) => ~q~n",
           [Tier, Name, Family, ShownActual, ShownExpected, ShownOutcome]).

print_typing_overlap(
    typing_overlap(NameA, TierA, NameB, TierB, Family,
                   Actual, Expected, Kind, OutcomeA, OutcomeB)) :-
    copy_term(Actual-Expected-OutcomeA-OutcomeB, Shown),
    numbervars(Shown, 0, _),
    Shown = ShownActual-ShownExpected-ShownA-ShownB,
    (   Kind = conditional(Reason)
    ->  format("  CONDITIONAL OVERLAP (~w): ~w rule ~w and ~w rule ~w \c
                in ~w at (~q, ~q); outcomes ~q and ~q~n",
               [Reason, TierA, NameA, TierB, NameB, Family,
                ShownActual, ShownExpected, ShownA, ShownB])
    ;   format("  OVERLAP joined: ~w rule ~w and ~w rule ~w in ~w at \c
                (~q, ~q); both accept~n",
               [TierA, NameA, TierB, NameB, Family,
                ShownActual, ShownExpected])
    ).

%%%% The analysis %%%%

% analyse(+Registered, +Rules, -Analysis). Analysis is
% analysis(Termination, Verdicts), with one verdict per critical pair worth
% reporting.
% The user's tier is the headline; the shipped tier answers beside it,
% never instead of it. The two are checked TOGETHER for cross-collisions,
% because a user rule colliding with a shipped one is exactly the silent
% ordering P2.13 exists to name.
analyse(Registered, SpaceRules, PreludeRules,
        analysis(Termination, Shipped, SpaceVs, CrossVs, Specs, ShippedVs)) :-
    include(has_rule_in(SpaceRules), Registered, SpaceEntries),
    maplist(exempted_rule, SpaceRules, SpaceForTermination),
    termination(SpaceEntries, SpaceForTermination, Termination),
    (   PreludeRules == []
    ->  Shipped = no_shipped_tier
    ;   include(has_rule_in(PreludeRules), Registered, ShippedEntries),
        maplist(exempted_rule, PreludeRules, PreludeForTermination),
        termination(ShippedEntries, PreludeForTermination, Shipped)
    ),
    append(SpaceRules, PreludeRules, Combined),
    length(SpaceRules, S),
    join_bound(Fuel),
    confluence_check(Combined, Fuel, All),
    exclude(trivial_self_overlap, All, Verdicts),
    partition(both_at_most(S), Verdicts, SpaceVs, Rest),
    partition(both_above(S), Rest, PreludeVs, CrossVs),
    partition(shipped_specialization(Combined), PreludeVs,
              Specs, ShippedVs).

% A rule whose registration DECLARED that its right-hand-only variables are
% exempt is analysed with those variables replaced by a constant, which is
% what the exemption says they are: bound by a binder of the expansion, never
% taking a value from the term being rewritten. The substitution is made for
% the termination question only; the critical-pair analysis and everything
% printed use the rule as written. '$exempt' cannot collide with a MeTTa
% symbol, for the reason engine/narrowing.pl's '$bottom' cannot: a source
% token starting with $ parses as a variable.
exempted_rule(Rule, Analysed) :-
    Rule = (L ==> _),
    functor(L, Name, _),
    user:translator_rule_extra_variables_exempt(Name, _),
    !,
    copy_term(Rule, Analysed),
    Analysed = (Left ==> Right),
    term_variables(Left, Bound),
    term_variables(Right, Occurring),
    exclude(variable_among(Bound), Occurring, RightOnly),
    maplist(=('$exempt'), RightOnly).
exempted_rule(Rule, Rule).

variable_among(Variables, V) :- member(W, Variables), W == V, !.

% Which rules of a set carry an exemption, so the termination line says which
% precondition was waived and on whose word.
rule_exemptions(Rules, Exemptions) :-
    findall(Name-Reason,
            ( member(L ==> _, Rules),
              functor(L, Name, _),
              user:translator_rule_extra_variables_exempt(Name, Reason) ),
            Pairs),
    sort(Pairs, Exemptions).

has_rule_in(Rules, Name) :-
    member(L ==> _, Rules),
    functor(L, Name, _),
    !.

both_at_most(S, verdict(I, J, _, _, _, _)) :- I =< S, J =< S.
both_above(S, verdict(I, J, _, _, _, _)) :- I > S, J > S.

% A shipped pair where one head strictly subsumes the other is the ladder
% the prelude ships on purpose: a specific optimisation rule beside its
% general form. WHICH applicable rule fires is up to the engine, whatever
% matches first, and nothing promises whether that is the general or the
% specific one; so the pair is sound only as an EQUIVALENCE: both
% expansions must answer alike, and the corpus A/B that admitted the
% specific rule is the standing evidence (user ruling, 2026-08-19).
shipped_specialization(Combined, verdict(I, J, [], _, _, _)) :-
    nth1(I, Combined, LI ==> _),
    nth1(J, Combined, LJ ==> _),
    (   subsumes_term(LI, LJ), \+ subsumes_term(LJ, LI) -> true
    ;   subsumes_term(LJ, LI), \+ subsumes_term(LI, LJ)
    ).

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

print_analysis(SpaceRules, PreludeRules,
               analysis(Termination, Shipped, SpaceVs, CrossVs, Specs,
                        ShippedVs)) :-
    append(SpaceRules, PreludeRules, Combined),
    length(Combined, RuleCount),
    defined_symbols(Combined, Ds),
    length(Ds, SymbolCount),
    format("compile-time rule set: ~d rules over ~d defined symbols~n",
           [RuleCount, SymbolCount]),
    length(SpaceRules, S),
    forall(nth1(I, SpaceRules, Rule), print_rule(I, Rule)),
    forall(( nth1(K, PreludeRules, Rule), I is S + K ),
           print_shipped_rule(I, Rule)),
    print_termination(SpaceRules, Termination),
    print_exemptions(SpaceRules),
    append(SpaceVs, CrossVs, Headline),
    include(verdict_is(joined), Headline, Joined),
    include(verdict_is(counterexample), Headline, Divergent),
    include(verdict_is(unknown), Headline, Unknown),
    length(Headline, Overlaps),
    length(Joined, JoinedCount),
    length(Divergent, DivergentCount),
    length(Unknown, UnknownCount),
    join_bound(Fuel),
    format("overlaps: ~d between distinct rules or below the root, ~d joined, \c
            ~d divergent, ~d unresolved within ~d steps~n",
           [Overlaps, JoinedCount, DivergentCount, UnknownCount, Fuel]),
    forall(( member(V, Divergent) ; member(V, Unknown) ),
           print_overlap(Combined, V)),
    print_shipped_tier(Combined, PreludeRules, Shipped, Specs, ShippedVs),
    guarded_rules(SpaceRules, PreludeRules, Guarded, _),
    print_conclusion(Termination, DivergentCount, UnknownCount, Guarded).

print_shipped_rule(I, L ==> R) :-
    term_expr(L, LE),
    term_expr(R, RE),
    user:sdisplay(['=', LE, RE], Text),
    format("  ~d. ~w (shipped)~n", [I, Text]).

% The shipped tier's own block. Its termination and its internal pairs are
% the engine's to answer for, so they never move the headline numbers the
% caller's rule set is judged by; a cross-collision does, above.
print_shipped_tier(_, [], no_shipped_tier, _, _) :- !.
print_shipped_tier(Combined, PreludeRules, Shipped, Specs, ShippedVs) :-
    length(PreludeRules, N),
    format("shipped tier: ~d prelude rules; ", [N]),
    print_shipped_termination(Shipped),
    length(Specs, SpecCount),
    (   SpecCount > 0
    ->  format("  ~d specialization pairs, a specific rule beside its \c
general form. Which fires is up to the engine, whatever matches first, \c
nothing promises whether that is the general or the specific; each pair \c
is therefore an EQUIVALENCE OBLIGATION, both expansions answering alike, \c
the corpus A/B its standing evidence~n", [SpecCount]),
        forall(member(V, Specs), print_specialization(Combined, V))
    ;   true
    ),
    (   ShippedVs == []
    ->  true
    ;   format("  SHIPPED-TIER OVERLAP, a defect in the engine's own \c
vocabulary, not in the caller's rules:~n"),
        forall(member(V, ShippedVs), print_overlap(Combined, V))
    ).

print_shipped_termination(established(_)) :-
    !,
    format("termination: ESTABLISHED~n").
print_shipped_termination(not_established(Failed, Reason)) :-
    !,
    %The reason's NAME only: no_rpo_order carries the whole rule list as
    %its argument, and eleven rules inside one summary line bury the word
    %that matters.
    functor(Reason, ReasonName, _),
    format("termination: NOT ESTABLISHED, ~w at ~w~n", [ReasonName, Failed]).
print_shipped_termination(T) :-
    format("termination: ~w~n", [T]).

print_specialization(Combined, verdict(I, J, _, _, _, _)) :-
    nth1(I, Combined, LI ==> _),
    nth1(J, Combined, LJ ==> _),
    (   subsumes_term(LJ, LI)
    ->  Spec = I, Gen = J
    ;   Spec = J, Gen = I
    ),
    format("    rules ~d and ~d: ~d is the specific form of ~d~n",
           [Spec, Gen, Spec, Gen]).

print_rule(I, L ==> R) :-
    term_expr(L, LE),
    term_expr(R, RE),
    user:sdisplay(['=', LE, RE], Text),
    format("  ~d. ~w~n", [I, Text]).

print_exemptions(Rules) :-
    rule_exemptions(Rules, Exemptions),
    forall(member(Name-Reason, Exemptions),
           format("  exempt from the extra-variables precondition: ~w, \c
                   because ~w~n", [Name, Reason])).

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
% A conditional system is not decided by the criterion at all, so its verdict
% comes first: a guard can make a peak unreachable, which turns a divergent
% pair from a refutation into an obligation.
print_conclusion(_, Divergent, Unknown, Guarded) :-
    Guarded > 0,
    !,
    format("conclusion: NOT DECIDED. ~d of these rules can refuse, so this is \c
            a conditional system and the critical-pair criterion does not \c
            decide it; the ~d divergent and ~d unresolved pairs above are \c
            proof obligations.~n", [Guarded, Divergent, Unknown]).
print_conclusion(_, Divergent, _, _) :-
    Divergent > 0,
    !,
    format("conclusion: NOT LOCALLY CONFLUENT. ~d critical pairs reach \c
            distinct normal forms, so which answer the compiler gives is \c
            decided by the order the rules were asserted in, among the \c
            alternatives whose own bodies have an answer.~n", [Divergent]).
print_conclusion(_, _, Unknown, _) :-
    Unknown > 0,
    !,
    format("conclusion: UNDECIDED. ~d critical pairs did not join within the \c
            bound, which says nothing about whether they join further out.~n",
           [Unknown]).
print_conclusion(established(_), _, _, _) :-
    !,
    format("conclusion: CONFLUENT. Every critical pair joins and the rule set \c
            terminates.~n").
print_conclusion(_, _, _, _) :-
    format("conclusion: LOCALLY CONFLUENT. Every critical pair joins, but \c
            termination is not established, and without it local confluence \c
            does not give confluence.~n").

print_overlap(Rules, verdict(I, J, Pos, L, R, Kind)) :-
    nth1(I, Rules, OuterL ==> _),
    nth1(J, Rules, InnerL ==> _),
    term_expr(OuterL, OuterE),
    term_expr(InnerL, InnerE),
    user:sdisplay(OuterE, OuterText),
    user:sdisplay(InnerE, InnerText),
    term_expr(L, LE),
    term_expr(R, RE),
    user:sdisplay(LE, LText),
    user:sdisplay(RE, RText),
    format("  OVERLAP ~w: rule ~d ~w and rule ~d ~w at position ~w~n",
           [Kind, I, OuterText, J, InnerText, Pos]),
    format("    rule ~d gives ~w~n", [I, LText]),
    format("    rule ~d gives ~w~n", [J, RText]).

%%%% Entry points %%%%

% The shipped configuration, loaded quietly: the two libraries that register a
% translator rule today.
load_engine :-
    set_prolog_flag(argv, [backends]),
    user:consult('../../engine/metta.pl'),
    retractall(user:silent(_)),
    assertz(user:silent(true)).

shipped_library('../../lib/lib_patrick.metta').
shipped_library('../../lib/lib_spaces.metta').

translator_confluence_report :-
    load_engine,
    forall(shipped_library(File), user:load_metta_file(File, _)),
    report_rule_family(translator, '&self').

% The same report over named MeTTa files instead of the shipped libraries,
% which is what a caller planting an overlap needs. Read argv BEFORE
% load_engine, which overwrites it so that engine/metta.pl globs the backends.
translator_confluence_main :-
    current_prolog_flag(argv, Argv),
    (   Argv == []
    ->  translator_confluence_report
    ;   load_engine,
        forall(member(File, Argv), user:load_metta_file(File, _)),
        report_rule_family(translator, '&self') ).

typing_confluence_report :-
    load_engine,
    report_rule_family(typing, '&self').

% The typing family over named MeTTa files. Registration runnables in those
% files populate typing_rule_entry/7, so this is the same public source a
% runtime checker consumes.
typing_confluence_main :-
    current_prolog_flag(argv, Argv),
    load_engine,
    forall(member(File, Argv), user:load_metta_file(File, _)),
    report_rule_family(typing, '&self').

translator_confluence_gate :-
    load_engine,
    forall(shipped_library(File), user:load_metta_file(File, _)),
    compile_time_rules('&self', Registered, _, SpaceRules, PreludeRules),
    (   SpaceRules == [], PreludeRules == []
    ->  true
    ;   %A conditional set is not decided by the criterion at all, so passing
        %it would be claiming something this analysis cannot say. The shipped
        %libraries hold no refusing rule today; the day one ships, this stops
        %and a person decides.
        guarded_rules(SpaceRules, PreludeRules, Guarded, _),
        (   Guarded > 0
        ->  print_translator_family(translator_state('&self', Registered, [],
                                                     SpaceRules, PreludeRules)),
            halt(1)
        ;   true
        ),
        analyse(Registered, SpaceRules, PreludeRules, Analysis),
        Analysis = analysis(_, _, SpaceVs, CrossVs, _Specs, ShippedVs),
        %A specialization pair is sanctioned by its equivalence evidence;
        %every other divergent overlap, whichever tier holds it, breaks.
        append([SpaceVs, CrossVs, ShippedVs], Gated),
        include(verdict_is(counterexample), Gated, Divergent),
        (   Divergent == []
        ->  true
        ;   print_analysis(SpaceRules, PreludeRules, Analysis),
            halt(1) ) ).

report_space(Space) :- report_rule_family(translator, Space).

print_translator_family(
    translator_state(_Space, Registered, Names, SpaceRules, PreludeRules)) :-
    print_decidable_fragment(SpaceRules, PreludeRules),
    length(Registered, EntryCount),
    length(Names, NameCount),
    format("registered translator rules: ~d, closed over what they call: ~d \c
            names~n", [EntryCount, NameCount]),
    forall(member(N, Names), print_rule_name(Registered, N)),
    (   SpaceRules == [], PreludeRules == []
    ->  format("no equations found for them, so there is nothing to \c
                analyse~n")
    ;   analyse(Registered, SpaceRules, PreludeRules, Analysis),
        print_analysis(SpaceRules, PreludeRules, Analysis) ).

% A registered name that already meant something says so here. The engine
% refuses a protected_core_head/1 outright, so a row can only ever be a head
% the program is allowed to take over, and the report is where the taking-over
% is stated instead of being left to be discovered at a call site.
print_rule_name(Registered, N) :-
    (   memberchk(N, Registered)
    ->  (   user:translator_rule_override(N, Kind)
        ->  format("  ~w (registered, ahead of the engine's own ~w of that \c
                    name)~n", [N, Kind])
        ;   format("  ~w (registered)~n", [N])
        )
    ;   format("  ~w (reached)~n", [N])
    ).

% Which fragment this report can answer in, printed with every report rather
% than left in a header, because a verdict is worth what its fragment is worth.
% The third line is about THIS rule set rather than about rule sets in
% general: a rule that can refuse takes its set out of the fragment, and the
% report has to say so instead of going on claiming the old one.
print_decidable_fragment(SpaceRules, PreludeRules) :-
    format("decidable fragment: confluence is decidable for TERMINATING \c
            rewrite systems, by Knuth and Bendix (1970), since such a system \c
            has finitely many critical pairs and each one's joinability \c
            terminates.~n"),
    format("  a rule that can REFUSE is a CONDITIONAL rule, and confluence of \c
            terminating conditional systems is undecidable in general; a set \c
            holding one has to be PROVED confluent rather than decided.~n"),
    guarded_rules(SpaceRules, PreludeRules, Guarded, Total),
    (   Guarded =:= 0
    ->  format("  this set: all ~d rules are UNCONDITIONAL, applied by \c
                matching a head alone, so it sits inside that fragment.~n",
               [Total])
    ;   format("  this set: ~d of its ~d rules can refuse, so it is \c
                CONDITIONAL and every verdict below is a proof obligation for \c
                those rules rather than a decision.~n", [Guarded, Total])
    ).

% A rule can refuse when a `(refuse Reason)` form is reachable in its
% right-hand side. Read from the rules themselves rather than from the
% registration, because the equations are what decide it and a registration
% does not say.
guarded_rules(SpaceRules, PreludeRules, Guarded, Total) :-
    append(SpaceRules, PreludeRules, Combined),
    include(rule_can_refuse, Combined, Refusing),
    length(Refusing, Guarded),
    length(Combined, Total).

rule_can_refuse(_ ==> R) :-
    sub_term(Sub, R),
    nonvar(Sub),
    compound(Sub),
    functor(Sub, refuse, 1),
    !.

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
    load_engine,
    findall(Name-Expected-Got,
            ( planted(Name, Rules, Expected),
              planted_outcome(Rules, Expected, Got),
              Got \== Expected ),
            Wrong),
    planted_collection_seen,
    planted_typing_overlap_seen,
    planted_refusing_rule_seen,
    (   Wrong == []
    ->  format("translator confluence selftest: ~d planted rule sets, each on \c
                the side its shape predicts, the collection door reads the \c
                prelude and typing registries, and a refusing rule is \c
                counted~n", [5])
    ;   forall(member(N-E-G, Wrong),
               format("planted ~w: expected ~w, got ~w~n", [N, E, G])),
        halt(1) ).

% The collection scenario goes through the DOOR the others bypass: two
% overlapping rules planted in the prelude register under fixture names
% must be collected by compile_time_rules and their overlap must be
% reported divergent. This is what stops the report's "0 overlaps" from
% meaning the shipped tier was never read.
planted_collection_seen :-
    setup_call_cleanup(
        ( assertz(user:translator_rule('$cfl_fixture', [])),
          assertz(user:prelude_equation('$cfl_fixture', ['=', ['$cfl_fixture', _], one])),
          assertz(user:prelude_equation('$cfl_fixture', ['=', ['$cfl_fixture', _], two])) ),
        ( compile_time_rules('&self', _, Names, _, PreludeRules),
          memberchk('$cfl_fixture', Names),
          include(fixture_rule, PreludeRules, Two),
          length(Two, 2),
          join_bound(Fuel),
          confluence_check(Two, Fuel, Verdicts),
          include(verdict_is(counterexample), Verdicts, [_|_]) ),
        ( retractall(user:translator_rule('$cfl_fixture', _)),
          retractall(user:prelude_equation('$cfl_fixture', _)) )),
    !.
planted_collection_seen :-
    format("planted collection: the prelude register's rules were not \c
            collected or their overlap was not reported~n", []),
    halt(1).

fixture_rule(L ==> _) :- functor(L, '$cfl_fixture', _).

% The gate refuses a conditional set rather than deciding one, so the thing it
% branches on is checked here too: a planted rule whose right-hand side can
% refuse must be COUNTED, or the gate would go on passing a set the
% critical-pair criterion says nothing about.
planted_refusing_rule_seen :-
    setup_call_cleanup(
        ( assertz(user:translator_rule('$cfl_guard', [])),
          assertz(user:prelude_equation('$cfl_guard',
                                        ['=', ['$cfl_guard', _],
                                         [refuse, "planted"]])) ),
        ( compile_time_rules('&self', _, _, _, PreludeRules),
          guarded_rules([], PreludeRules, Guarded, _),
          Guarded >= 1 ),
        ( retractall(user:translator_rule('$cfl_guard', _)),
          retractall(user:prelude_equation('$cfl_guard', _)) )),
    !.
planted_refusing_rule_seen :-
    format("planted refusing rule: a rule that can refuse was not counted, so \c
            the gate would decide a conditional set~n", []),
    halt(1).

% Both required typing intersections go through the descriptor: a refusing
% user rule overlaps a deferring user rule and the shipped gradual rule. The
% reporter must classify the refusal and defer as conditional proof
% obligations rather than passing either to confluence_check/3.
planted_typing_overlap_seen :-
    user:metta_self_module(Self),
    setup_call_cleanup(
        ( assertz(user:typing_rule_entry(user, Self, '$typing_refusal_fixture',
                                         ordinary, '%Undefined%', _,
                                         [refuse, fixture]), RefusalRef),
          assertz(user:typing_rule_entry(user, Self, '$typing_defer_fixture',
                                         ordinary, '%Undefined%', _, defer),
                  DeferRef) ),
        ( typing_family_state('&self', typing_state(_, Overlaps)),
          member(typing_overlap('$typing_refusal_fixture', user,
                                '$typing_defer_fixture', user, ordinary,
                                _, _, conditional(refusal), _, _), Overlaps),
          member(typing_overlap('$typing_refusal_fixture', user,
                                'typing-ordinary-unknown-actual', shipped,
                                ordinary, _, _, conditional(refusal), _, _),
                 Overlaps),
          member(typing_overlap('$typing_defer_fixture', user,
                                'typing-ordinary-unknown-actual', shipped,
                                ordinary, _, _, conditional(guarded_defer),
                                _, _), Overlaps) ),
        ( erase(DeferRef), erase(RefusalRef) )),
    !.
planted_typing_overlap_seen :-
    format("planted typing overlap: the rule-family descriptor missed a \c
            user/user or user/shipped conditional overlap~n", []),
    halt(1).

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
