% Purpose: hold the declared typing-rule registry and resolve its explicit
%   accept, refuse(Reason), and defer outcomes for every engine type checker.
% Assumes:
%   - current_metta_module/1 identifies the execution module whose user rules
%     are in scope.
% Guarantees:
%   - shipped and user rules occupy typing_rule_entry/7, and compatibility,
%     arrow arity, widening, and metatype checks all resolve through that one
%     relation [tested: test_a_user_typing_rule_participates_like_a_shipped_one;
%     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - a user refusal is decisive and keeps its rule name and reason, while
%     defer continues to the next rule [tested:
%     test_a_user_typing_rule_participates_like_a_shipped_one;
%     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
% Decides:
%   - rules are tried in registration order, user tier before shipped tier;
%     the shared overlap reporter names every ordering-sensitive intersection.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- dynamic typing_rule_entry/7.

% The shipped tier is data in exactly the relation add-typing-rule! extends.
% Actual and expected patterns are ordinary Prolog terms, so repeating Same in
% two positions declares equality without a separate hard-coded equality arm.
typing_rule_entry(shipped, '*', 'typing-ordinary-unknown-actual',
                  ordinary, '%Undefined%', _, accept).
typing_rule_entry(shipped, '*', 'typing-ordinary-unknown-expected',
                  ordinary, _, '%Undefined%', accept).
typing_rule_entry(shipped, '*', 'typing-ordinary-atom-actual',
                  ordinary, 'Atom', _, accept).
typing_rule_entry(shipped, '*', 'typing-ordinary-atom-expected',
                  ordinary, _, 'Atom', accept).
typing_rule_entry(shipped, '*', 'typing-ordinary-exact',
                  ordinary, Same, Same, accept).

% A raw type variable already fixed through a compound formal is not the Atom
% wildcard. Its family therefore omits the two Atom rules while retaining the
% gradual and exact rules.
typing_rule_entry(shipped, '*', 'typing-derived-unknown-actual',
                  derived, '%Undefined%', _, accept).
typing_rule_entry(shipped, '*', 'typing-derived-unknown-expected',
                  derived, _, '%Undefined%', accept).
typing_rule_entry(shipped, '*', 'typing-derived-exact',
                  derived, Same, Same, accept).

% Type reporting follows Hyperon's match_reducted_types relation. Unlike the
% runtime relation above, a literal Atom result is an ordinary type here; only
% the gradual unknown and exact equality are shipped matches.
typing_rule_entry(shipped, '*', 'typing-reporting-unknown-actual',
                  reporting, '%Undefined%', _, accept).
typing_rule_entry(shipped, '*', 'typing-reporting-unknown-expected',
                  reporting, _, '%Undefined%', accept).
typing_rule_entry(shipped, '*', 'typing-reporting-exact',
                  reporting, Same, Same, accept).

% Arrow arity is compared after a chain has been reduced to its declared
% input count. The rule, not type_chain_takes/2, decides equality.
typing_rule_entry(shipped, '*', 'typing-arrow-arity-exact',
                  'arrow-arity', Same, Same, accept).

% BigInt-to-Number is the implicit numeric widening. Declared :< edges use a
% separate family so their broad rule cannot turn every pair of ordinary types
% into a match.
typing_rule_entry(shipped, '*', 'typing-bigint-widens-to-number',
                  widening, 'BigInt', 'Number', accept).
typing_rule_entry(shipped, '*', 'typing-declared-widening-edge',
                  'declared-widening', _, _, accept).

% The metatype split is likewise declared: Atom is its wildcard and each
% shipped metatype is an explicit row. Keeping the four names here is what
% lets metta_argument_type_origin/3 discover the family from the registry
% instead of carrying a second closed list in metta.pl.
typing_rule_entry(shipped, '*', 'typing-metatype-atom',
                  metatype, _, 'Atom', accept).
typing_rule_entry(shipped, '*', 'typing-metatype-symbol',
                  metatype, 'Symbol', 'Symbol', accept).
typing_rule_entry(shipped, '*', 'typing-metatype-variable',
                  metatype, 'Variable', 'Variable', accept).
typing_rule_entry(shipped, '*', 'typing-metatype-grounded',
                  metatype, 'Grounded', 'Grounded', accept).
typing_rule_entry(shipped, '*', 'typing-metatype-expression',
                  metatype, 'Expression', 'Expression', accept).

typing_rule_family(ordinary).
typing_rule_family(derived).
typing_rule_family(reporting).
typing_rule_family('arrow-arity').
typing_rule_family(widening).
typing_rule_family('declared-widening').
typing_rule_family(metatype).

valid_typing_rule_outcome(accept).
valid_typing_rule_outcome(defer).
valid_typing_rule_outcome([refuse, Reason]) :- nonvar(Reason).

% add-typing-rule!(+Name, +Family, +Actual, +Expected, +Outcome, -Result).
% Patterns may contain variables; assertz/2 copies them into the declaration.
'add-typing-rule!'(Name, Family, Actual, Expected, Outcome, true) :-
    must_be(atom, Name),
    require_typing_rule_family(Family),
    require_typing_rule_outcome(Outcome),
    current_metta_module(Module),
    findall(F-A-E-O,
            typing_rule_entry(user, Module, Name, F, A, E, O),
            Existing),
    (   Existing == []
    ->  assertz(typing_rule_entry(user, Module, Name, Family, Actual,
                                  Expected, Outcome), Ref),
        record_source_assertion(Ref),
        clear_translation_cache
    ;   member(Old, Existing), Old =@= Family-Actual-Expected-Outcome
    ->  true
    ;   throw(error(petta_duplicate_typing_rule(Name, Existing),
                    context('add-typing-rule!'/6,
                            'a rule name identifies one declaration')))
    ).

% remove-typing-rule!(+Name, -Result). Only the current module's user rule is
% withdrawn; shipped rules cannot be removed through the user door.
'remove-typing-rule!'(Name, true) :-
    must_be(atom, Name),
    current_metta_module(Module),
    findall(Ref,
            clause(typing_rule_entry(user, Module, Name, _, _, _, _),
                   true, Ref),
            Refs),
    maplist(erase, Refs),
    clear_translation_cache.

require_typing_rule_family(Family) :-
    (   nonvar(Family), typing_rule_family(Family)
    ->  true
    ;   throw(error(domain_error(typing_rule_family, Family),
                    context('add-typing-rule!'/6,
                            'use ordinary, derived, reporting, arrow-arity, widening, declared-widening, or metatype')))
    ).

require_typing_rule_outcome(Outcome) :-
    (   nonvar(Outcome), valid_typing_rule_outcome(Outcome)
    ->  true
    ;   throw(error(domain_error(typing_rule_outcome, Outcome),
                    context('add-typing-rule!'/6,
                            'use accept, (refuse Reason), or defer')))
    ).

prolog:error_message(petta_duplicate_typing_rule(Name, Existing)) -->
    [ 'typing rule ~w already names ~w'-[Name, Existing] ].

% typing_rule_decision(+Module, +Family, ?Actual, ?Expected, -Outcome,
%                      -Name, -Tier).
% `defer` is an explicit decline, not a negative decision: continue through
% the remaining user entries and then the shipped tier. If none decides, the
% registry itself returns defer.
typing_rule_decision(Module, Family, Actual, Expected, Outcome, Name, Tier) :-
    (   decisive_typing_rule(user, Module, Family, Actual, Expected,
                             Outcome, Name)
    ->  Tier = user
    ;   decisive_typing_rule(shipped, '*', Family, Actual, Expected,
                             Outcome, Name)
    ->  Tier = shipped
    ;   Outcome = defer,
        Name = none,
        Tier = none
    ).

decisive_typing_rule(Tier, Module, Family, Actual, Expected, Outcome, Name) :-
    typing_rule_entry(Tier, Module, Name, Family, ActualPattern,
                      ExpectedPattern, Candidate),
    typing_pattern_openness(ActualPattern, ActualOpen),
    typing_pattern_openness(ExpectedPattern, ExpectedOpen),
    typing_rule_pattern_matches(Actual, ActualPattern, ActualOpen),
    typing_rule_pattern_matches(Expected, ExpectedPattern, ExpectedOpen),
    Candidate \== defer,
    !,
    Outcome = Candidate.

% Matching is directed from a declaration pattern to the checker's value.
% A rule variable may bind to that value, including linking two positions in
% an exact rule. A literal pattern does not bind an as-yet unknown checker
% value: `%Undefined%` means the literal gradual type, not a type variable that
% happens to be free when the rule is tried.
typing_pattern_openness(Pattern, open) :- var(Pattern), !.
typing_pattern_openness(_, closed).

typing_rule_pattern_matches(Value, Pattern, open) :- Pattern = Value.
typing_rule_pattern_matches(Value, Pattern, closed) :-
    nonvar(Value),
    Pattern = Value.

% Ordinary and derived compatibility delegate their unmatched pairs to the
% widening family. A decisive refusal never falls through.
typing_check_decision(Module, Family, Actual, Expected, Outcome, Name, Tier) :-
    typing_rule_decision(Module, Family, Actual, Expected,
                         Direct, DirectName, DirectTier),
    (   Direct == defer,
        ( Family == ordinary ; Family == derived ; Family == reporting )
    ->  typing_rule_decision(Module, widening, Actual, Expected,
                             Outcome, Name, Tier)
    ;   Outcome = Direct,
        Name = DirectName,
        Tier = DirectTier
    ).

typing_rule_accepts(Module, Family, Actual, Expected) :-
    typing_check_decision(Module, Family, Actual, Expected,
                          accept, _, _).

typing_rule_refusal(Module, Family, Actual, Expected, Name, Reason) :-
    typing_check_decision(Module, Family, Actual, Expected,
                          [refuse, Reason], Name, _).

% A checker can ask whether an expected type belongs to a declared family
% without inventing a parallel list. This is used to classify metatype
% parameters before their actual argument is known. A user rule with a broad
% expected pattern deliberately widens that family for its own module.
typing_rule_expected(Module, Family, Expected) :-
    (   typing_rule_entry(user, Module, _, Family, _, Pattern, _)
    ;   typing_rule_entry(shipped, '*', _, Family, _, Pattern, _)
    ),
    typing_pattern_openness(Pattern, Openness),
    typing_rule_pattern_matches(Expected, Pattern, Openness),
    !.

% The reporter reads this predicate, so it analyzes the exact entries the
% checker resolves rather than maintaining a second inventory.
registered_typing_rule(Tier, Module, Name, Family, Actual, Expected, Outcome) :-
    typing_rule_entry(Tier, Module, Name, Family, Actual, Expected, Outcome).
