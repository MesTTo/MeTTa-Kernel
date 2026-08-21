% Purpose: hold the translator rule registry and everything a registration
%   DECLARES about a rule, and derive the inverse a bidirectional declaration
%   asks for instead of making its author write it twice.
%
%   WHAT IT COVERS: REWRITING for the rules it registers and NARROWING for the
%   one thing it declares to the termination analysis. A registered rule is a
%   rewrite, so its direction, its cost, the orientation those two decide and
%   the inverse derived from them are all statements about a rewrite relation,
%   and they reach the rule set because a rule's head is MATCHED against its
%   call. The `extra-variables-exempt` declaration is the exception: it is
%   written for engine/narrowing.pl, whose question is a narrowing one because
%   a rule's body is EVALUATED while the program compiles.
% Assumes:
%   - current_metta_module/1 names the module a registration is written in and
%     metta_module_space/2 turns that into the space holding its equations, so
%     an inverse is read from and written to the space that wrote the rule.
%   - a rule whose inverse is derivable WRITES its expansion, as
%     `(= Lhs (noeval Rhs))`. A body that computes its expansion cannot be
%     read backwards without inverting the computation, which is a different
%     transformation [source: Nishida, Palacios and Vidal, "Reversible Term
%     Rewriting", FSCD 2016, whose route is flatten, constructor-normalize,
%     injectivize and only then invert; the injectivization step is what
%     embeds a computation's history and is not attempted here].
% Guarantees:
%   - translator_rule/2 is the registry and translator_rule/1 is its name
%     projection, so a rule's direction has one place to live and every
%     existing reader of the name set keeps working
%     [tested: test_a_translator_rule_declares_its_direction_and_a_bidirectional_rule_is_one_declaration;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - a bidirectional declaration is ONE declaration: the inverse equation is
%     derived, added to the space as an ordinary atom, and registered, and
%     removing the rule removes it again
%     [tested: test_a_translator_rule_declares_its_direction_and_a_bidirectional_rule_is_one_declaration;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - every precondition of the inversion is CHECKED and its failure is named:
%     a computed expansion, an expansion not rooted at a symbol, an expansion
%     that would leave a left-side variable unbound, a protected inverse head,
%     and an inverse that is the rule itself
%     [tested: tests/prolog/metta.plt, translator_rule_direction;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - add-translator-rule! REFUSES a protected_core_head/1 name with that name
%     in the error term, and records what an accepted registration went ahead
%     of in translator_rule_override/2
%     [tested: test_overriding_a_protected_name_is_refused_with_the_name;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - a rule body answering (refuse Reason) DECLINES: the call carries on down
%     the dispatch chain and the words are recorded and published into &petta
%     [tested: test_a_translator_rule_can_decline_with_its_own_words;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - a declared cost prices every form headed by the rule's name and decides
%     which way a bidirectional rewrite goes, and a conjunctive left side
%     compiles to a `match` chain, so the join is the engine's own conjunctive
%     query rather than a second substitution merger
%     [tested: test_a_translator_rule_carries_a_cost_and_a_conjunctive_left_side;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - a rule may DECLARE, with a reason, that the variables it writes only on
%     its right are binders of its expansion; the reason is required
%     [tested: test_the_shipped_translator_rules_bind_their_right_hand_variables;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
%   - a rule that declared NOTHING pays nothing for any of this: the refusal
%     and orientation tests at the one call site are inline unifications, and
%     the declarations come from the registry lookup the caller already made
%     [measured 2026-08-21: reading them again here cost 6 inferences on
%     file-load and the projection translator_rule/1 cost 50,004 on
%     alpha-unique; command=bindings/python/bench.py --counter-only;
%     commit=9330b5d7ebf607e34a85be950bb226fce65f45c0].
% Decides:
%   - a rule read both ways is applied only in the direction that strictly
%     lowers the form's cost, and cost defaults to the node count. Nothing
%     else stops a bidirectional rule and its inverse rewriting each other
%     forever, and a strictly decreasing natural number is what makes the
%     rewriting terminate.
%   - a name identifies ONE declaration. Re-registering the same name with
%     different declarations is refused rather than silently taken as the new
%     truth, the way add-typing-rule!/6 refuses a redeclaration.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%%%% The protected core %%%%
%
%The heads a rewrite rule may not take over.
%
%translate_expr_dl/4 consults the translator rules one line BEFORE
%translate_special_dl/5, so registering a rule for one of the compiler's own
%forms replaces it for the whole process with nothing said at any point:
%`(= (if $c $t $e) (noeval (quote hijacked)))` followed by
%`!(add-translator-rule! if)` makes `!(if True 1 2)` answer `(quote hijacked)`
%[measured 2026-08-21, on this engine before the refusal below existed].
%
%Rw-Prolog guards exactly this. Its call_rw_/3 special-cases `!`, true, false,
%fail, `->`, `;`, `,` and catch ahead of dispatch so that they "cannot be
%overridden by rewrite rules" [source: Chris Barrick, Rw-Prolog,
%src/rewrite.pl, call_rw_/3 and the comment above call_rw/2, read 2026-08-21
%from the checkout in ai-tmp/rw-prolog]. Refusing at the DECLARATION instead
%of at every call is that guard moved to where the author can act on it.
%
%WHICH names, from the two sets this repository has already written down.
%KERNEL.md's reference point is minimal MeTTa's state-free structural
%instruction set, and its table says which of this engine's heads is a
%counterpart of which; those counterparts are the first ten rows. The last
%four are Rw-Prolog's control forms in this engine's spelling, `true`, `false`
%and `fail` being values here rather than heads.
%
%Deliberately NOT protected: the prelude's eight derived forms, `once`,
%`progn`, `prog1`, `nop`, `take`, `test` and the five space updates. A rule
%for `once` is engine work that ships, in lib/lib_derived.metta, and
%examples/libraries/derived_forms.metta runs the swap and the swap back, so a
%set wide enough to include every special form would refuse it
%[tested: examples/libraries/derived_forms.metta].
protected_core_head(eval).
protected_core_head(evalc).
protected_core_head(chain).
protected_core_head(let).
protected_core_head(unify).
protected_core_head(superpose).
protected_core_head(collapse).
protected_core_head(call).
protected_core_head('translatePredicate').
protected_core_head(reduce).
protected_core_head(if).
protected_core_head(case).
protected_core_head(catch).
protected_core_head(cut).

%The name is the whole content of the refusal, so it travels in the error
%term where a catcher can read it rather than only in rendered prose.
refuse_protected_core_rule(Name) :-
    (   protected_core_head(Name)
    ->  throw(error(permission_error(register, metta_protected_core, Name),
                    context('add-translator-rule!',
                            'a rewrite rule cannot replace the protected \c
                             core')))
    ;   true
    ).

%%%% The registry %%%%
%
%One row per registered rule, holding what the registration declared about it.
%The set used to be bare names, so a rule's direction had nowhere to live and
%an author who wanted a rewrite read both ways wrote the inverse by hand.
%
%Declarations are a canonical sorted list, so two spellings of the same
%declaration set compare equal and a re-registration that changes nothing is
%the no-op it always was.
:- dynamic translator_rule/2.

%The name set, which is what the translator and every tool that came before
%the declarations asks for.
translator_rule(Name) :- translator_rule(Name, _).

%The equations a bidirectional declaration wrote into a space, so
%that removing the rule removes them too. Recording the atom rather than
%rebuilding it means removal cannot drift from what was added.
:- dynamic translator_rule_derived/3.   %translator_rule_derived(Source, Space, Equation)

%What a registration for an UNPROTECTED name that already means something did
%to that meaning. It does not delete it: the older clause or special form is
%still there and still answers a call the rule's head does not match, which is
%what makes a guarded rule fall through at all. What it does do is go first,
%so for a call the rule DOES match the older meaning is unreachable. Saying
%which of the two happened is the obligation; a name that meant nothing before
%records no row, so an empty register reads as "nothing was taken over".
:- dynamic translator_rule_override/2.

note_translator_rule_override(Name) :-
    (   translator_rule_override(Name, _)
    ->  true
    ;   translator_rule_override_kind(Name, Kind)
    ->  assertz(translator_rule_override(Name, Kind))
    ;   true
    ).

translator_rule_override_kind(Name, special_form) :-
    metta_special_form(Name), !.
%A derived form the PRELUDE ships is its equation and its registration
%together, and the loader registers every prelude head as a builtin so a call
%site compiles before pass two reaches the equation. Reading builtin_fun/1
%alone therefore reported all eight of the prelude's own forms as taking over
%a meaning they are [measured 2026-08-21].
translator_rule_override_kind(Name, builtin) :-
    builtin_fun(Name),
    \+ prelude_owned(Name), !.

%%%% What a registration may declare %%%%

%What a registration may say. A form this relation does not name is refused
%rather than ignored, so a misspelt declaration is not silently a rule with
%default behaviour.
translator_rule_declaration([direction, Direction], direction(Direction)) :-
    translator_rule_direction(Direction).
%A form headed by this name costs this much. The measure has to be a natural
%number for the orientation below to be well founded, and it is what an
%extractor minimises when two forms are equivalent [source: egg's
%CostFunction, whose cost/2 is a node's own cost plus its children's].
translator_rule_declaration([cost, Cost], cost(Cost)) :-
    integer(Cost), Cost >= 0.
%A CONJUNCTIVE left side: the first pattern is the call and the rest are
%matched against the space, all of them joined on the variables they share.
translator_rule_declaration([left, Patterns], left(Patterns)) :-
    is_list(Patterns), Patterns = [_|_].
translator_rule_declaration([right, Expansion], right(Expansion)) :-
    nonvar(Expansion).
%A variable this rule writes only on its right is bound by a BINDER of the
%expansion rather than taken from the term being rewritten. The termination
%analysis in engine/narrowing.pl cannot see the difference, so the rule says
%which it is and why; a reason is required because an exemption without one
%is a silenced check.
translator_rule_declaration(['extra-variables-exempt', Reason],
                            extra_variables_exempt(Reason)) :-
    nonvar(Reason).

%Two directions, which is the whole split R19 names: a FORWARD rule is a
%rewrite, and a BIDIRECTIONAL one is an equation, a quotient the compiler may
%cross either way. There is no backward-only value, and the reason is
%measured rather than aesthetic: a rule's equation also defines its head as an
%ordinary function, so a rewrite INTO that head compiles to a call that runs
%the same equation and hands the original form straight back
%[measured 2026-08-21: (= (shorthand $x) (noeval (spelled out $x))) read
%backwards rewrote (spelled out 5) to (shorthand 5), which then answered
%(spelled out 5) again]. Read BOTH ways the same equation is fine, because
%the cost order stops one of the two directions.
translator_rule_direction(forward).
translator_rule_direction(bidirectional).

parse_translator_rule_declarations(Declared, Declarations) :-
    (   is_list(Declared)
    ->  true
    ;   throw(error(type_error(list, Declared),
                    context('add-translator-rule!',
                            'the declarations are a list of forms')))
    ),
    maplist(parse_translator_rule_declaration, Declared, Parsed),
    msort(Parsed, Declarations),
    refuse_repeated_declaration(Declarations),
    %A conjunctive left side has no inverse: reading it backwards would have
    %to ASSERT the conjuncts it matched, which is a different operation from
    %rewriting a form.
    (   memberchk(left(_), Declarations),
        memberchk(direction(bidirectional), Declarations)
    ->  throw(error(petta_uninvertible_rule(left, conjunctive_left_side),
                    context('add-translator-rule!',
                            'a conjunctive left side cannot be read \c
                             backwards')))
    ;   true
    ).

parse_translator_rule_declaration(Form, Parsed) :-
    (   nonvar(Form), translator_rule_declaration(Form, Parsed)
    ->  true
    ;   throw(error(domain_error(translator_rule_declaration, Form),
                    context('add-translator-rule!',
                            'use (direction ...), (cost N), \c
                             (left (Pattern ...)), (right Expansion) or \c
                             (extra-variables-exempt Reason)')))
    ).

refuse_repeated_declaration(Declarations) :-
    findall(Kind,
            ( member(A, Declarations), functor(A, Kind, _),
              member(B, Declarations), functor(B, Kind, _), A \== B ),
            Repeated),
    (   Repeated == []
    ->  true
    ;   sort(Repeated, [Kind|_]),
        throw(error(petta_repeated_translator_rule_declaration(Kind),
                    context('add-translator-rule!',
                            'a rule declares each thing once')))
    ).

translator_rule_declared_cost(Name, Cost) :-
    translator_rule(Name, Declarations),
    memberchk(cost(Cost), Declarations).

translator_rule_extra_variables_exempt(Name, Reason) :-
    translator_rule(Name, Declarations),
    memberchk(extra_variables_exempt(Reason), Declarations).

%%%% Registration %%%%

'add-translator-rule!'(HV, Result) :-
    'add-translator-rule!'(HV, [], Result).

'add-translator-rule!'(HV, _, _) :- var(HV), !,
                                    refuse_unbound_input('add-translator-rule!', 1).
'add-translator-rule!'(HV, Declared, true) :-
    must_be(atom, HV),
    refuse_protected_core_rule(HV),
    parse_translator_rule_declarations(Declared, Declarations),
    register_translator_rule(HV, Declarations),
    install_conjunctive_rule(HV, Declarations),
    derive_translator_rule_inverse(HV, Declarations).

register_translator_rule(Name, Declarations) :-
    (   translator_rule(Name, Existing)
    ->  %Variant, not identity: two spellings of one declaration differ only
        %in the variables their patterns happen to hold, and =@=/2 is the
        %comparison engine/trs.pl already uses for exactly that reason.
        (   Existing =@= Declarations
        ->  true
        ;   throw(error(petta_duplicate_translator_rule(Name, Existing),
                        context('add-translator-rule!',
                                'a rule name identifies one declaration')))
        )
    ;   note_translator_rule_override(Name),
        assertz(translator_rule(Name, Declarations))
    ).

'remove-translator-rule!'(HV, _) :- var(HV), !,
                                    refuse_unbound_input('remove-translator-rule!', 1).
'remove-translator-rule!'(HV, true) :-
    must_be(nonvar, HV),
    forall(retract(translator_rule_derived(HV, Space, Equation)),
           withdraw_derived_equation(Space, Equation)),
    forget_translator_rule(HV).

withdraw_derived_equation(Space, Equation) :-
    Equation = [=, [InvHead|_], _],
    'remove-atom'(Space, Equation, _),
    forget_translator_rule(InvHead).

forget_translator_rule(Name) :-
    retractall(translator_rule(Name, _)),
    retractall(translator_rule_override(Name, _)).

%%%% The conjunctive left side %%%%
%
%A conjunctive left side names several patterns that must ALL match: the
%first against the call being compiled and the rest against the space the
%rule was written in. That is a conjunctive query, and this engine already
%has one, `match`, so the rule compiles to the equation an author would
%otherwise write by hand, with the conjuncts as a `match` chain around the
%expansion.
%
%The JOIN across the patterns is Prolog's unification on the variables they
%share, and they share them because the whole declaration is ONE parsed form.
%egg and TenSat have to write that join out: canonicalise every pattern's
%variables to ?i_0, ?i_1 and so on, match each canonical pattern once,
%de-canonicalise the substitutions back, test them for compatibility on the
%shared variables and merge them [source: uwplse/tensat, src/rewrites.rs,
%canonicalize/1, decanonicalize/2, compatible/3 and merge_subst/3, read
%2026-08-21]. None of that is written here, and none of it is written twice.
install_conjunctive_rule(Name, Declarations) :-
    (   memberchk(left(Patterns), Declarations)
    ->  require_declaration(Name, right(Expansion), Declarations),
        Patterns = [Head|Conjuncts],
        (   nonvar(Head), Head = [Name|Arguments], is_list(Arguments)
        ->  true
        ;   throw(error(petta_conjunctive_left_side(Name, Head),
                        context('add-translator-rule!',
                                'the first pattern of a conjunctive left \c
                                 side is the call this rule rewrites, so it \c
                                 is rooted at the rule\'s own name')))
        ),
        current_metta_module(Module),
        metta_module_space(Module, Space),
        conjunctive_body(Space, Conjuncts, [noeval, Expansion], Body),
        Equation = [=, Head, Body],
        'add-atom'(Space, Equation, _),
        assertz(translator_rule_derived(Name, Space, Equation))
    ;   \+ memberchk(right(_), Declarations)
    ->  true
    ;   throw(error(petta_conjunctive_left_side(Name, missing),
                    context('add-translator-rule!',
                            'a right side needs the left side it rewrites')))
    ).

require_declaration(Name, Wanted, Declarations) :-
    (   memberchk(Wanted, Declarations)
    ->  true
    ;   functor(Wanted, Kind, _),
        throw(error(petta_conjunctive_left_side(Name, Kind),
                    context('add-translator-rule!',
                            'a left side needs the right side it rewrites \c
                             to')))
    ).

conjunctive_body(_, [], Inner, Inner).
conjunctive_body(Space, [Conjunct|Rest], Inner, [match, Space, Conjunct, Body]) :-
    conjunctive_body(Space, Rest, Inner, Body).

%%%% The derived inverse %%%%

derive_translator_rule_inverse(Name, Declarations) :-
    (   memberchk(direction(bidirectional), Declarations)
    ->  current_metta_module(Module),
        metta_module_space(Module, Space),
        rule_source_equations(Space, Name, Equations),
        (   Equations == []
        ->  throw(error(existence_error(translator_rule_equation, Name),
                        context('add-translator-rule!',
                                'a rule read backwards needs its equation to \c
                                 read')))
        ;   true
        ),
        forall(member(Equation, Equations),
               ( inverse_equation(Name, Equation, Inverse),
                 install_inverse_equation(Name, Space, Inverse) ))
    ;   true
    ).

rule_source_equations(Space, Name, Equations) :-
    findall([=, Lhs, Rhs],
            ( 'get-atoms'(Space, ['=', Lhs, Rhs]),
              nonvar(Lhs), Lhs = [Name|_] ),
            Equations).

%The inversion, with every precondition checked and named. The transformation
%itself is one line, `(= Lhs (noeval Rhs))` becomes `(= Rhs (noeval Lhs))`;
%what makes it sound is the four refusals around it.
inverse_equation(Name, Equation, Inverse) :-
    Equation = [=, Lhs, Body],
    (   nonvar(Body), Body = [noeval, Rhs]
    ->  true
    ;   throw(error(petta_uninvertible_rule(Name, computed_expansion),
                    context('add-translator-rule!',
                            'a rule read backwards writes its expansion, as \c
                             (= Lhs (noeval Rhs))')))
    ),
    (   nonvar(Rhs), Rhs = [InvHead|InvArgs], atom(InvHead), is_list(InvArgs)
    ->  true
    ;   throw(error(petta_uninvertible_rule(Name, expansion_is_not_a_form),
                    context('add-translator-rule!',
                            'the inverse rewrites the expansion, so the \c
                             expansion has to be a form with a symbol at its \c
                             head')))
    ),
    refuse_protected_core_rule(InvHead),
    %The extra-variable precondition, which is the one the termination
    %analysis in engine/narrowing.pl names by the same word: a variable the
    %inverse's left side does not bind is a variable its right side invents.
    %Twee, an equational prover built on unfailing completion, keeps an
    %unorientable equation as an equation exactly when "both sides have the
    %same set of variables", which "is unproblematic for rewriting", and a
    %bidirectional declaration is read both ways, so it needs both inclusions
    %[source: Nick Smallbone, "Twee: An Equational Theorem Prover", CADE-28
    %(2021), section 2 on splitting an equation, read 2026-08-21].
    term_variables(Lhs, LeftVariables),
    term_variables(Rhs, RightVariables),
    require_variables_covered(Name, LeftVariables, RightVariables),
    require_variables_covered(Name, RightVariables, LeftVariables),
    Inverse = [=, Rhs, [noeval, Lhs]],
    (   Inverse =@= Equation
    ->  throw(error(petta_uninvertible_rule(Name, inverse_is_the_rule_itself),
                    context('add-translator-rule!',
                            'this rule is its own inverse, and a rewrite \c
                             between two forms of equal cost never fires')))
    ;   true
    ).

require_variables_covered(Name, Needed, Available) :-
    (   forall(member(V, Needed), ( member(W, Available), W == V ))
    ->  true
    ;   throw(error(petta_uninvertible_rule(Name, extra_variables),
                    context('add-translator-rule!',
                            'a rule read backwards needs the same variables \c
                             on both sides, or one of them arrives unbound')))
    ).

%The inverse goes into the space as an ORDINARY atom, which is what makes it
%the equation the author did not have to write: it compiles through the one
%equation spine, get-atoms shows it, and the confluence report analyses it
%beside every other rule.
install_inverse_equation(Source, Space, Equation) :-
    Equation = [=, [InvHead|_], _],
    'add-atom'(Space, Equation, _),
    assertz(translator_rule_derived(Source, Space, Equation)),
    %An inverse rooted at the rule's own head is a second equation for a name
    %that is already registered, not a second registration.
    (   InvHead == Source
    ->  true
    ;   register_translator_rule(InvHead, [direction(inverse(Source))])
    ).

%%%% Refusal %%%%
%
%A rule may inspect its match and DECLINE, rather than only match or not
%match. TenSat's CheckApply::apply_one validates the nodes it is about to
%construct and returns nothing when they are invalid, so the rewrite simply
%does not happen [source: uwplse/tensat, src/rewrites.rs, the Applier
%implementation for CheckApply, read 2026-08-21]. The same shape is already
%here twice, as metta_foreign_refuse/2 for a space and as
%engine/type_rules.pl's [refuse, Reason] outcome for a typing rule; this is
%the third rule family to get it and it is spelled the same way.
%
%A declined call carries on down the dispatch chain exactly as a call whose
%head the rule did not match, and a rule with more equations tries the next
%one, because the decline is a FAILURE at the point the rule was called.
%
%The `(refuse Reason)` shape is tested inline at the one place a rule's
%expansion arrives, so a rule that does not refuse pays nothing for the
%channel.
%
%The words are not lost. They are recorded here and published into &petta as
%an ordinary atom, where a program reads them with a match; printing them
%would be noise for a rule that declines by design, and dropping them would
%leave the author with a rewrite that did not happen and no reason.
:- dynamic translator_rule_refusal/3.   %translator_rule_refusal(Name, Reason, Call)

%The published atom is deduplicated against the REGISTER, which first-argument
%indexing narrows to this rule's own rows, rather than against &petta, which
%would walk every atom in it once per decline and make a rule that declines
%often quadratic in the size of the catalog.
note_translator_rule_refusal(Name, Args, Reason) :-
    copy_term([Name|Args], Call),
    (   translator_rule_refusal(Name, Recorded, _), Recorded == Reason
    ->  true
    ;   'add-atom'('&petta', ['translator-rule-refusal', Name, Reason], _)
    ),
    assertz(translator_rule_refusal(Name, Reason, Call)).

%%%% Orientation %%%%
%
%A bidirectional rule and the inverse it derives are one equation read both
%ways, so nothing but a measure stops them rewriting each other forever. The
%rewrite has to lower the form's COST strictly, which is ordered rewriting: an
%equation that cannot be oriented once and for all is applied in whichever
%direction decreases with respect to a reduction order [source: Bachmair,
%Dershowitz and Plaisted, "Completion Without Failure", Resolution of
%Equations in Algebraic Structures, volume 2, Academic Press (1989), 1-30].
%Because the measure is a natural number and every step strictly decreases it,
%the rewriting terminates.
%
%A forward rule is not measured. It fires when it matches, exactly as it did
%before directions existed, so nothing that shipped changes cost.
%The declarations arrive from the caller, which already had them in hand from
%the registry lookup that decided this was a rule at all. Reading them again
%here is a second lookup on the compiler's hot path and was measured as one.
translator_rule_orients(Name, Declarations, Args, Expansion) :-
    (   memberchk(direction(Direction), Declarations),
        cost_ordered_direction(Direction)
    ->  translator_form_cost([Name|Args], Before),
        translator_form_cost(Expansion, After),
        After < Before
    ;   true
    ).

cost_ordered_direction(bidirectional).
cost_ordered_direction(inverse(_)).

%A form's cost, folded over its nodes the way an e-graph extractor folds a
%cost function over an e-node and its children. A head whose rule declared a
%cost costs that; everything else, the empty expression included, costs one
%node.
translator_form_cost(Form, Cost) :-
    (   var(Form) -> Cost = 1
    ;   Form == [] -> Cost = 1
    ;   is_list(Form) -> foldl(add_translator_form_cost, Form, 0, Cost)
    ;   atom(Form), translator_rule_declared_cost(Form, Declared) -> Cost = Declared
    ;   Cost = 1
    ).

add_translator_form_cost(Term, Running, Total) :-
    translator_form_cost(Term, Cost),
    Total is Running + Cost.

:- multifile prolog:error_message//1.

prolog:error_message(petta_duplicate_translator_rule(Name, Existing)) -->
    [ 'translator rule ~w already declares ~w'-[Name, Existing] ].
prolog:error_message(petta_repeated_translator_rule_declaration(Kind)) -->
    [ 'the ~w declaration is written more than once'-[Kind] ].
prolog:error_message(petta_uninvertible_rule(Name, Reason)) -->
    [ '~w cannot be read backwards: ~w'-[Name, Reason] ].
prolog:error_message(petta_conjunctive_left_side(Name, What)) -->
    [ 'the conjunctive left side of ~w is missing or misplaced its ~w'-[Name, What] ].
