% Purpose: parse, classify and solve expression-child gap patterns (sequence variables) inside LeaTTa's three certified-finite fragments
% Assumes: engine/spaces.pl consults this plain file while its owning module is the load context; petta_match_atoms/2 decides one atom position.
% Guarantees: a pattern the program wrote without a gap never reaches any predicate here, so a gap-free ask pays nothing [tested: tests/prolog/segments.plt:a_gap_free_match_costs_what_it_did].
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% Decides: an ask outside the three proved-finite fragments REFUSES by throwing rather than searching an infinitary space.
% [tested: tests/prolog/segments.plt; commit=a3dff3abc83b9d82f3652093246e1d693d526cdb]

%%%% What a gap is, and why the fence exists %%%%
%
%A gap is a sequence variable: an expression CHILD that stands for a finite
%run of zero or more sibling children rather than for one term. Two surface
%spellings, both the law's [source: LeaTTa
%MettaHyperonFull/Core/Modifiers.lean, segment?]: the bare symbol `...` is an
%ANONYMOUS gap, and `(:seg $x)` with a VARIABLE in the second position is a
%NAMED gap. Any other shape, `(:seg foo)` included, is ordinary data.
%
%Kutsia proved general syntactic sequence unification INFINITARY [source:
%Temur Kutsia, "Solving Equations with Sequence Variables and Sequence
%Functions", Journal of Symbolic Computation 42(3), 2007, 352-388,
%doi:10.1016/j.jsc.2006.12.002, Theorem 62]: `(f (:seg $x) a)` against
%`(f a (:seg $x))` has the family `$x = a^n` for every n, so no complete
%finite answer set exists. Three restrictions of that theory ARE proved
%finite, and they are what this engine admits, in the arbiter's own
%classification order [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?]:
%
%  one_sided       one side carries no gap at all. Matching rather than
%                  unification; every gap consumes a run of the other side's
%                  closed children.
%  last_position   every gap is the LAST child of its own expression, on both
%                  sides (Kutsia Section 6.3). Deterministic and unitary: one
%                  answer or none, which is Prolog's own partial-list
%                  unification written out.
%  linear_shallow  every gap is a direct child of the ROOT, no nested
%                  expression carries one, and each NAMED gap occurs once
%                  across the pair (Kutsia Section 6.2).
%
%Outside them the ask REFUSES, naming the rule. That is not caution: the
%alternative is a search that does not terminate.
%
%ONE NAME MAY NOT PLAY BOTH ROLES in the general two-sided `unify` and space
%query doors. `(f (:seg $x) $x)` is refused there across every fragment
%[source: ai-python-conventions.md 3.3, "One name may not play both the
%ordinary and the segment role; that mix refuses too"]. An EQUATION HEAD is
%the deliberate one-sided exception below: LeaTTa's one-sided matcher gives
%the ordinary occurrence the expression projection of the finite run, and
%petta_seq_head_match/2 does the same [source: LeaTTa
%MettaHyperonFull/Core/SeqOneSided.lean:65-89, oneSidedBindRole;
%commit=WORKTREE].
%
%DISTINCT `...` OCCURRENCES ARE DISTINCT VARIABLES [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean, SeqVar.anonymous, "two `...`
%occurrences are distinct variables"]. Parsing gives each one its own fresh
%Prolog variable, which nothing else mentions, so its run is recorded and
%discarded and no two occurrences can constrain each other.

%%%% Parsing: the gap markers become one distinguished term, once %%%%
%
%The solvers never look at surface syntax. A side is PARSED first, which
%rewrites each live gap child into '$petta_seg'(Var, Kind) and leaves
%everything else alone, and the solvers then test one functor instead of
%re-deciding what a marker-shaped list means at every candidate. That is the
%arbiter's own staging [source: LeaTTa MettaHyperonFull/Core/SeqSyntax.lean,
%parseSeqAtom], and it settles two questions the raw shape cannot:
%
%  - A marker that arrived through a BINDING is data, never a gap. Only what
%    the program WROTE is parsed, so `(let $p (:seg $x) (match &s $p $t))`
%    matches the literal atom [source: LeaTTa
%    MettaHyperonFull/Core/SeqSyntax.lean, parseConcreteAtom, "no child is
%    ever a segment, at any depth"].
%  - A repeated `(:seg $x)` still reads as a gap after its first occurrence
%    bound $x, because the second occurrence is already '$petta_seg'($x, named)
%    and the parse ran before any binding.
%
%The ROOT of a side is never a gap: only expression children can be [source:
%LeaTTa MettaHyperonFull/Core/SeqSyntax.lean, parseSeqAtom, "the root itself
%is never a segment"], so `(:seg $r)` asked as a whole pattern is ordinary
%data.
petta_seq_parse(Side, Parsed) :-
    (   nonvar(Side),
        Side = [_|_]
    ->  petta_seq_parse_items(Side, Parsed)
    ;   Parsed = Side
    ).

petta_seq_parse_items(Items, Parsed) :-
    (   nonvar(Items),
        Items = [Item|Rest]
    ->  petta_seq_parse_item(Item, ParsedItem),
        petta_seq_parse_items(Rest, ParsedRest),
        Parsed = [ParsedItem|ParsedRest]
    ;   Parsed = Items
    ).

petta_seq_parse_item(Item, Parsed) :-
    (   petta_seq_surface_gap(Item, Var, Kind)
    ->  Parsed = '$petta_seg'(Var, Kind)
    ;   petta_seq_parse(Item, Parsed)
    ).

%An anonymous gap gets a FRESH variable nothing else mentions, which is what
%makes each occurrence its own existential: its run is bound and then reachable
%from nowhere. A named gap keeps the program's own variable, so the answer
%template reads the run through the same name the pattern wrote.
petta_seq_surface_gap(Item, Var, Kind) :-
    nonvar(Item),
    (   Item == '...'
    ->  Kind = anon
    ;   Item = [Marker, Named],
        nonvar(Marker),
        Marker == ':seg',
        var(Named),
        Var = Named,
        Kind = named
    ).

%Does a pattern the program WROTE carry a gap? The compile-time and door-time
%question, asked once per pattern and never per candidate.
petta_seq_present(Pattern) :-
    nonvar(Pattern),
    Pattern = [_|_],
    petta_seq_present_items(Pattern).

petta_seq_present_items(Items) :-
    nonvar(Items),
    Items = [Item|Rest],
    (   petta_seq_surface_gap(Item, _, _)
    ->  true
    ;   petta_seq_present(Item)
    ->  true
    ;   petta_seq_present_items(Rest)
    ).

%%%% Equation-head matching and RHS substitution %%%%
%
%An equation head is always the pattern side of a ONE-SIDED match.  That
%matters for a name used in both sequence and ordinary roles: general
%two-sided sequence unification refuses that shape because it can be
%infinitary, while the one-sided reference matcher binds the finite run and
%projects its ordinary occurrence to the expression containing that run.
%Prolog already has precisely that projection.  Binding the gap variable to
%the run `[a,b]` makes a later ordinary occurrence of the same variable match
%the expression `(a b)` [source: LeaTTa
%MettaHyperonFull/Core/SeqOneSided.lean:65-89 and :445-461;
%commit=WORKTREE].
%
%The plan is built while the equation is compiled, before any call can bind
%its variables.  Only the written head is parsed.  The call is concrete syntax
%at this boundary, so a marker-shaped argument remains data.
petta_seq_head_plan(Pattern, '$petta_seq'(one_sided(left), Parsed)) :-
    petta_seq_parse(Pattern, Parsed).

petta_seq_body_plan(Body, Parsed) :-
    petta_seq_parse(Body, Parsed).

petta_seq_head_match('$petta_seq'(one_sided(left), Parsed), Subject) :-
    %An equation head stores only the argument HEDGE, not an atom with its
    %function head.  Enter the child-list matcher directly so the all-segment
    %head can match the empty argument hedge; petta_seq_atoms/2 quite properly
    %requires two nonempty expressions at its atom boundary [tested:
    %tests/prolog/segment_equations.plt:top_level_segment_accepts_zero_arguments;
    %commit=WORKTREE].
    petta_seq_items(Parsed, Subject).

%A coverage or applicability probe must not bind the live call or the retained
%equation.  copy_term/2 preserves sharing inside each side, including the one
%name that may occur as both `(:seg $x)` and ordinary `$x` in an equation head
%[tested: tests/prolog/segment_equations.plt; commit=WORKTREE].
petta_seq_head_matches(Pattern, Subject) :-
    copy_term(Pattern-Subject, PatternCopy-SubjectCopy),
    petta_seq_head_plan(PatternCopy, Plan),
    once(petta_seq_head_match(Plan, SubjectCopy)).

%RHS substitution is context-sensitive.  An ordinary `$x` keeps the bound run
%as one expression; a written `(:seg $x)` child splices the run into its
%surrounding expression.  Parse before the head match and instantiate after it,
%so a marker arriving through a binding stays data and repeated written splice
%occurrences keep sharing their one authoritative run [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean:300-314 and :343-367;
%commit=WORKTREE].
petta_seq_instantiate(Template, Instantiated) :-
    (   nonvar(Template),
        Template = [_|_]
    ->  petta_seq_instantiate_items(Template, Instantiated)
    ;   Instantiated = Template
    ).

petta_seq_instantiate_items(Items, Instantiated) :-
    (   Items == []
    ->  Instantiated = []
    ;   nonvar(Items),
        Items = [Item|Rest]
    ->  petta_seq_instantiate_items(Rest, Tail),
        (   nonvar(Item),
            Item = '$petta_seg'(Run, Kind)
        ->  (   is_list(Run)
            ->  append(Run, Tail, Instantiated)
            ;   petta_seq_open_gap(Kind, Run, Surface),
                Instantiated = [Surface|Tail]
            )
        ;   petta_seq_instantiate(Item, Head),
            Instantiated = [Head|Tail]
        )
    ;   Instantiated = Items
    ).

petta_seq_open_gap(anon, _, '...') :- !.
petta_seq_open_gap(named, Var, [':seg', Var]).

%The same question about an ALREADY PARSED side, which is what one conjunct
%carries once its enclosing conjunction was parsed.
petta_seq_parsed(Parsed) :-
    nonvar(Parsed),
    Parsed = [_|_],
    petta_seq_parsed_items(Parsed).

petta_seq_parsed_items(Items) :-
    nonvar(Items),
    Items = [Item|Rest],
    (   nonvar(Item),
        Item = '$petta_seg'(_, _)
    ->  true
    ;   petta_seq_parsed(Item)
    ->  true
    ;   petta_seq_parsed_items(Rest)
    ).

%%%% Classification: which certified-finite fragment, or a refusal %%%%
%
%One deterministic walk per side, accumulating through a difference list.
%NOT findall, and that is not a preference: findall COPIES its template, so a
%collected gap's variable is a fresh one and the mixed-role rule, which decides
%by variable IDENTITY, saw no name in both roles and admitted every mixed
%pattern [measured 2026-08-24: `(f (:seg $m) $m)` classified one_sided(left)
%with the findall spelling and refuses with this one].
%
%Depth is 0 for a direct child of the root and counts one per nested
%expression; Final says the gap is the last item of its own child list.
petta_seq_gaps(Parsed, Depth, Gaps, Tail) :-
    (   nonvar(Parsed),
        Parsed = [_|_]
    ->  petta_seq_gaps_items(Parsed, Depth, Gaps, Tail)
    ;   Gaps = Tail
    ).

petta_seq_gaps_items(Items, Depth, Gaps, Tail) :-
    (   nonvar(Items),
        Items = [Item|Rest]
    ->  (   nonvar(Item),
            Item = '$petta_seg'(_, _)
        ->  ( Rest == [] -> Final = true ; Final = false ),
            Gaps = [g(Depth, Final, Item)|Mid]
        ;   Inner is Depth + 1,
            petta_seq_gaps(Item, Inner, Gaps, Mid)
        ),
        petta_seq_gaps_items(Rest, Depth, Mid, Tail)
    ;   Gaps = Tail
    ).

%Every ordinary variable, which is every variable NOT standing in a gap
%position. The two lists are what the mixed-role rule compares.
petta_seq_ordinary(Parsed, Vars, Tail) :-
    (   var(Parsed)
    ->  Vars = [Parsed|Tail]
    ;   Parsed = [_|_]
    ->  petta_seq_ordinary_items(Parsed, Vars, Tail)
    ;   Vars = Tail
    ).

petta_seq_ordinary_items(Items, Vars, Tail) :-
    (   nonvar(Items),
        Items = [Item|Rest]
    ->  (   nonvar(Item),
            Item = '$petta_seg'(_, _)
        ->  Mid = Vars
        ;   petta_seq_ordinary(Item, Vars, Mid)
        ),
        petta_seq_ordinary_items(Rest, Mid, Tail)
    ;   Vars = Tail
    ).

%The named gap variables among collected occurrences, sharing preserved.
petta_seq_named_vars([], []).
petta_seq_named_vars([g(_, _, Gap)|Gaps], Names) :-
    (   Gap = '$petta_seg'(Var, named)
    ->  Names = [Var|Rest]
    ;   Names = Rest
    ),
    petta_seq_named_vars(Gaps, Rest).

%The classifier, in the arbiter's own dispatch order [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?]: the gap-free side
%first, then last position, which is deterministic and unitary and therefore
%the more specific result, then linear-shallow. LeaTTa's numeric guard is
%deliberately NOT reproduced: that guard belongs to the raw syntactic reading,
%and the arbiter's own dispatcher classifies the free term skeleton instead,
%where numbers are theory values rather than a finiteness limit [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean header, "Numeric grounds are not a
%finiteness or completeness limit"]. This engine compares grounds through
%petta_match_atoms/2, which is that same runtime comparison.
petta_seq_classify(Left, Right, Case) :-
    petta_seq_gaps(Left, 0, LeftGaps, []),
    petta_seq_gaps(Right, 0, RightGaps, []),
    petta_seq_mixed_roles(Left, Right, LeftGaps, RightGaps, Mixed),
    (   Mixed \== []
    ->  petta_seq_refuse(Left, Right, Mixed, mixed_roles)
    ;   RightGaps == []
    ->  Case = one_sided(left)
    ;   LeftGaps == []
    ->  Case = one_sided(right)
    ;   petta_seq_all_final(LeftGaps),
        petta_seq_all_final(RightGaps)
    ->  Case = last_position
    ;   petta_seq_linear_shallow(LeftGaps, RightGaps)
    ->  Case = linear_shallow
    ;   petta_seq_refuse(Left, Right, [], no_certificate)
    ).

%A name caught in both roles across the pair [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean, noMixedSeqRoles]. Compared by
%variable IDENTITY, because a gap's name and an ordinary mention of that name
%are one Prolog variable and == is the only test that says so.
petta_seq_mixed_roles(Left, Right, LeftGaps, RightGaps, Mixed) :-
    append(LeftGaps, RightGaps, Gaps),
    petta_seq_named_vars(Gaps, GapVars),
    (   GapVars == []
    ->  Mixed = []
    ;   petta_seq_ordinary(Left, TermVars, RightTermVars),
        petta_seq_ordinary(Right, RightTermVars, []),
        petta_seq_both_roles(GapVars, TermVars, Mixed)
    ).

petta_seq_both_roles([], _, []).
petta_seq_both_roles([Var|Vars], TermVars, Mixed) :-
    (   memberchk_eq(Var, TermVars)
    ->  Mixed = [Var|Rest]
    ;   Mixed = Rest
    ),
    petta_seq_both_roles(Vars, TermVars, Rest).

petta_seq_all_final([]).
petta_seq_all_final([g(_, Final, _)|Gaps]) :-
    Final == true,
    petta_seq_all_final(Gaps).

%Kutsia Section 6.2 exactly: every gap a direct child of the root, and every
%named gap occurring once across the whole pair. Anonymous gaps are linear by
%construction, since parsing gave each one its own variable.
petta_seq_linear_shallow(LeftGaps, RightGaps) :-
    append(LeftGaps, RightGaps, Gaps),
    forall(member(g(Depth, _, _), Gaps), Depth == 0),
    petta_seq_named_vars(Gaps, Names),
    petta_seq_distinct(Names).

petta_seq_distinct([]).
petta_seq_distinct([V|Vs]) :-
    \+ memberchk_eq(V, Vs),
    petta_seq_distinct(Vs).

%%%% The refusal, and the law it names %%%%
%
%Every refusal names its ground. This one names the theorem, the three
%fragments, the sections that prove them, and the Lean classifier that decides
%them, because a reader who hits this fence needs to know that rewriting the
%pattern is the only remedy and which shapes are admissible.
petta_seq_refuse(Left, Right, Mixed, Reason) :-
    petta_seq_surface(Left, LeftSurface),
    petta_seq_surface(Right, RightSurface),
    petta_seq_surface_items(Mixed, MixedSurface),
    throw(error(petta_seq_outside_fragment(LeftSurface, RightSurface,
                                           MixedSurface, Reason),
                none)).

:- multifile prolog:error_message//1.
prolog:error_message(petta_seq_outside_fragment(Left, Right, Mixed, Reason)) -->
    { swrite(Left, LeftText),
      %A space match classifies its pattern before it has seen a candidate, so
      %the other side is genuinely open there and naming it as a variable would
      %read like a mistake in the program.
      ( var(Right) -> RightText = 'any atom' ; swrite(Right, RightText) ),
      ( Mixed == [] -> MixedText = none ; swrite(Mixed, MixedText) ) },
    [ 'gap unification of ~w against ~w is outside the proved finitary \c
       fragment (~w, mixed-roles: ~w). General sequence unification is \c
       INFINITARY (Kutsia, Journal of Symbolic Computation 42(3), 2007, \c
       Theorem 62), so the engine refuses rather than searching forever. \c
       Three fragments are proved finite and are the ones it decides: one \c
       side with no gap at all; every gap linear and a direct child of the \c
       root (Kutsia Section 6.2); every gap the last child of its own \c
       expression (Kutsia Section 6.3). One name may not be both a gap and an \c
       ordinary variable. The classifier is LeaTTa \c
       MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?'-[LeftText,
                                                              RightText,
                                                              Reason,
                                                              MixedText] ].

%Parsed syntax back to what the program wrote, for a message a reader
%recognises and for a published run that still holds an unsolved gap [source:
%LeaTTa MettaHyperonFull/Core/SeqRuntime.lean, SeqAtom.toSurface, "a named
%splice renders as its (:seg $x) marker and an anonymous one as the bare gap
%marker, so an open value prints as the pattern that would match it"].
petta_seq_surface(Parsed, Surface) :-
    (   nonvar(Parsed),
        Parsed = '$petta_seg'(Var, Kind)
    ->  ( Kind == anon -> Surface = '...' ; Surface = [':seg', Var] )
    ;   nonvar(Parsed),
        Parsed = [_|_]
    ->  petta_seq_surface_items(Parsed, Surface)
    ;   Surface = Parsed
    ).

petta_seq_surface_items(Items, Surface) :-
    (   nonvar(Items),
        Items = [Item|Rest]
    ->  petta_seq_surface(Item, Head),
        petta_seq_surface_items(Rest, Tail),
        Surface = [Head|Tail]
    ;   Surface = Items
    ).

%%%% The plan a gap pattern carries, and the two doors that read it %%%%
%
%A gap pattern reaches the engine WRAPPED, as '$petta_seq'(Plan, Parsed), and
%the wrapper is the whole reason a gap-free program pays nothing. match/4 and
%petta_match_atoms/2 each dispatch on it with one clause whose guard is nonvar/1
%and =/2, which SWI compiles inline and does not count, so no ordinary query,
%unify, let or case gains an inference; and because both doors already existed,
%a gap adds NO new goal name for protect_engine_emitted/1 to import into every
%space, which is what a new name really costs [measured 2026-08-24: three new
%seam:engine_emitted/1 names moved eval-arith from 178168 to 178177, 2,000
%evaluations, harness-identical A/B against b492d78e].
%
%The plan is decided ONCE per pattern: while the call site compiles for a
%pattern the program wrote, and at the ask for one a host built. A refusal is
%carried in the plan rather than thrown at that moment, so an arm nothing
%reaches cannot stop a file from loading and the ask that does reach it refuses
%with the message the door would have given.
petta_seq_plan(Left, Right, '$petta_seq'(Plan, Parsed)) :-
    petta_seq_parse(Left, Parsed),
    petta_seq_outcome(petta_seq_classify(Parsed, Right, Case), Case, Plan).

%The query door's plan. Its subject is a stored atom, whose own marker-shaped
%atoms are data rather than gaps, so every conjunct is one-sided by
%construction [source: LeaTTa MettaHyperonFull/Core/SeqRuntime.lean,
%residualUnderRigid]. Each CONJUNCT is classified on its own, because a
%conjunction is a join and its conjuncts are separate equations.
petta_seq_query_plan(Pattern, '$petta_seq'(Plan, Parsed)) :-
    petta_seq_parse(Pattern, Parsed),
    petta_seq_outcome(petta_seq_admit(Parsed), query, Plan).

petta_seq_outcome(Goal, Witness, Plan) :-
    catch(( call(Goal), Plan = Witness ), error(Why, _), Plan = refused(Why)).

petta_seq_admit(Parsed) :-
    (   nonvar(Parsed),
        Parsed = [Comma|Conjuncts],
        Comma == ','
    ->  petta_seq_admit_each(Conjuncts)
    ;   petta_seq_classify(Parsed, _Subject, _Case)
    ).

petta_seq_admit_each([]).
petta_seq_admit_each([Conjunct|Conjuncts]) :-
    petta_seq_classify(Conjunct, _Subject, _Case),
    petta_seq_admit_each(Conjuncts).

%Each certificate has its own procedure and the dispatcher never guesses.
petta_seq_unify(one_sided(left), Left, Right) :-
    petta_seq_atoms(Left, Right).
petta_seq_unify(one_sided(right), Left, Right) :-
    petta_seq_atoms(Right, Left).
petta_seq_unify(last_position, Left, Right) :-
    petta_seq_last_position(Left, Right).
petta_seq_unify(linear_shallow, Left, Right) :-
    petta_seq_linear(Left, Right).
petta_seq_unify(refused(Why), _, _) :-
    throw(error(Why, none)).

%%%% one_sided: the gap side is a pattern, the other side is closed %%%%
%
%The certified matcher [source: LeaTTa MettaHyperonFull/Core/SeqOneSided.lean,
%oneSidedAtoms, oneSidedItems, oneSidedSeg]: atoms decide pointwise, argument
%lists split around each gap, and a gap consumes every possible run, SHORTEST
%FIRST. Prolog's append/3 with an unbound prefix is exactly that enumeration in
%exactly that order, which is why the substrate supplies the split rather than
%a hand-written index walk.
%
%The cost is the enumeration's own and no more: matching m gaps against n
%subject children is the integer compositions of n into m parts, C(n-1, m-1),
%so it is exponential in the NUMBER OF GAPS and polynomial in the subject
%[source: Krebber, "Non-linear Associative-Commutative Many-to-One Pattern
%Matching with Sequence Variables", arXiv:1705.00907, Section 2.1, "The matches
%are analogous to integer partitions of n with m parts ... O(n^m) many"]. One
%gap is linear, which is the shape every gap pattern in the corpus has.
%
%Runs bind EAGERLY here, unlike the two-sided solvers below, and that is what
%makes a repeated `(:seg $x)` decide against the run its first occurrence took.
%It is sound because a one-sided run is always CLOSED: it is a slice of the
%gap-free side, so it can never hold an unsolved gap that a later step would
%have to splice in.
petta_seq_atoms(Pattern, Subject) :-
    (   nonvar(Pattern),
        Pattern = '$petta_seg'(_, _)
    ->  fail
    ;   nonvar(Pattern),
        Pattern = [_|_],
        nonvar(Subject),
        Subject = [_|_]
    ->  petta_seq_items(Pattern, Subject)
    ;   petta_match_atoms(Pattern, Subject)
    ).

petta_seq_items(Pattern, Subject) :-
    (   Pattern == []
    ->  Subject == []
    ;   nonvar(Pattern),
        Pattern = [Item|Rest],
        (   nonvar(Item),
            Item = '$petta_seg'(Var, _)
        ->  petta_seq_consume(Var, Rest, Subject)
        ;   nonvar(Subject),
            Subject = [Head|Tail],
            petta_seq_atoms(Item, Head),
            petta_seq_items(Rest, Tail)
        )
    ).

%Consume one run. An UNBOUND gap variable takes every split, shortest first,
%and is bound to its run before the rest of the pattern runs, so a second
%occurrence of the same name sees the run it has to repeat. A gap variable
%already carrying a run, from an earlier occurrence or an earlier conjunct,
%accepts exactly a run that MATCHES it under the engine's own comparison rather
%than under syntactic equality, so 1 and 1.0 agree there as they do everywhere
%else [source: LeaTTa MettaHyperonFull/Core/SeqOneSided.lean,
%oneSidedBindSegment, "A repeated name accepts exactly a runtime-equal run"].
petta_seq_consume(Var, After, Subject) :-
    (   var(Var)
    ->  append(Run, Rest, Subject),
        Var = Run,
        petta_seq_items(After, Rest)
    ;   petta_seq_repeat(Var, Subject, Rest),
        petta_seq_items(After, Rest)
    ).

petta_seq_repeat(Run, Subject, Rest) :-
    (   Run == []
    ->  Rest = Subject
    ;   nonvar(Run),
        Run = [Item|Items],
        nonvar(Subject),
        Subject = [Head|Tail],
        petta_match_atoms(Item, Head),
        petta_seq_repeat(Items, Tail, Rest)
    ).

%%%% The two-sided store: runs accumulate, then publish once %%%%
%
%A two-sided run can hold an UNSOLVED gap: `(f a (:seg $x))` against
%`(f a b (:seg $y))` answers `$x = (b (:seg $y))`, and if a later step then
%solves `$y` the published `$x` has to carry that run rather than the marker.
%Binding eagerly cannot do that, because Prolog cannot rewrite a term it has
%already bound, so the two-sided solvers thread an association list and bind
%the program's variables ONCE at the end, after resolving each run through the
%others. That is the arbiter's own staging [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean, SeqSolution.instantiate, and
%MettaHyperonFull/Core/SeqLastPos.lean, bindSegment].
petta_seq_lookup(Var, [Key-Run|Rest], Found) :-
    (   Key == Var
    ->  Found = Run
    ;   petta_seq_lookup(Var, Rest, Found)
    ).

%A gap whose run mentions the gap itself would build a term containing itself.
%LeaTTa keeps the one exception its calculus keeps: `X = X` is trivial rather
%than a clash [source: LeaTTa MettaHyperonFull/Core/SeqLastPos.lean, the
%hedgeEliminate rule's occursSeqVarList branch].
petta_seq_store(Var, Run, Store0, Store) :-
    (   Run = [Only],
        nonvar(Only),
        Only = '$petta_seg'(Same, _),
        Same == Var
    ->  Store = Store0
    ;   petta_seq_gap_occurs(Var, Run)
    ->  fail
    ;   Store = [Var-Run|Store0]
    ).

petta_seq_gap_occurs(Var, Run) :-
    term_variables(Run, Vars),
    memberchk_eq(Var, Vars).

%Resolve every stored run through the others, then bind. Resolving first and
%binding afterwards is not a style choice: the store is keyed by the program's
%own variables, so binding one entry would rewrite the keys of the rest.
%
%The budget is the store's own size, which bounds any acyclic dereference
%chain, and exceeding it PROVES a cycle the per-binding occurs check could not
%see because it spans two entries [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean, SeqSolution.derefBudget, "exceeding it
%proves a dependency cycle"]. A proven cycle has no answer, so the branch
%fails rather than publishing a term that contains itself.
petta_seq_publish(Store) :-
    length(Store, Budget),
    petta_seq_resolve_store(Store, Store, Budget, Values),
    petta_seq_bind_store(Store, Values).

petta_seq_resolve_store([], _, _, []).
petta_seq_resolve_store([_-Run|Rest], Store, Budget, [Value|Values]) :-
    petta_seq_resolve_items(Run, Store, Budget, Value),
    petta_seq_resolve_store(Rest, Store, Budget, Values).

petta_seq_bind_store([], []).
petta_seq_bind_store([Var-_|Rest], [Value|Values]) :-
    Var = Value,
    petta_seq_bind_store(Rest, Values).

petta_seq_resolve_items(Items, Store, Budget, Out) :-
    (   Items == []
    ->  Out = []
    ;   nonvar(Items),
        Items = [Item|Rest]
    ->  petta_seq_resolve_items(Rest, Store, Budget, Tail),
        (   nonvar(Item),
            Item = '$petta_seg'(Var, Kind)
        ->  (   petta_seq_lookup(Var, Store, Run)
            ->  Budget > 0,
                Next is Budget - 1,
                petta_seq_resolve_items(Run, Store, Next, Spliced),
                append(Spliced, Tail, Out)
            ;   ( Kind == anon -> Marker = '...' ; Marker = [':seg', Var] ),
                Out = [Marker|Tail]
            )
        ;   petta_seq_resolve_atom(Item, Store, Budget, Head),
            Out = [Head|Tail]
        )
    ;   Out = Items
    ).

petta_seq_resolve_atom(Atom, Store, Budget, Out) :-
    (   nonvar(Atom),
        Atom = [_|_]
    ->  petta_seq_resolve_items(Atom, Store, Budget, Out)
    ;   Out = Atom
    ).

%%%% last_position: Kutsia Section 6.3, deterministic and unitary %%%%
%
%Every gap is the last child of its own expression, so nothing is ever split:
%the two child lists are walked pointwise and a trailing gap takes the whole
%remainder of the other side. That is Prolog's own partial-list unification
%with the occurs check, spelled out because MeTTa expressions are PROPER lists
%and the remainder has to be handed over as data rather than aliased as a tail
%[source: LeaTTa MettaHyperonFull/Core/SeqLastPos.lean, the hedgeEliminate,
%hedgeDecompose, hedgeTrivial and hedgeDelete rules].
petta_seq_last_position(Left, Right) :-
    petta_seq_last_atoms(Left, Right, [], Store),
    petta_seq_publish(Store).

petta_seq_last_atoms(Left, Right, Store0, Store) :-
    (   nonvar(Left),
        Left = [_|_],
        nonvar(Right),
        Right = [_|_]
    ->  petta_seq_last_items(Left, Right, Store0, Store)
    ;   petta_match_atoms(Left, Right),
        Store = Store0
    ).

petta_seq_last_items(Left, Right, Store0, Store) :-
    (   Left == [],
        Right == []
    ->  Store = Store0
    ;   petta_seq_trailing_gap(Left, Var)
    ->  petta_seq_absorb(Var, Right, Store0, Store)
    ;   petta_seq_trailing_gap(Right, Var)
    ->  petta_seq_absorb(Var, Left, Store0, Store)
    ;   nonvar(Left),
        Left = [L|Ls],
        nonvar(Right),
        Right = [R|Rs],
        petta_seq_last_atoms(L, R, Store0, Between),
        petta_seq_last_items(Ls, Rs, Between, Store)
    ).

%A gap in this fragment is always the last item of its list, so seeing one at
%the head means the list is exactly that gap.
petta_seq_trailing_gap(Items, Var) :-
    nonvar(Items),
    Items = [Item|Rest],
    Rest == [],
    nonvar(Item),
    Item = '$petta_seg'(Var, _).

%Take the whole remaining run, or, for a gap that already took one, solve the
%two runs against each other. Solving rather than comparing is what applying
%the substitution to the worklist does in the calculus, and it is what lets a
%repeated name relate two open runs instead of demanding they were written the
%same way.
petta_seq_absorb(Var, Items, Store0, Store) :-
    (   petta_seq_lookup(Var, Store0, Stored)
    ->  petta_seq_last_items(Stored, Items, Store0, Store)
    ;   petta_seq_store(Var, Items, Store0, Store)
    ).

%%%% linear_shallow: Kutsia Section 6.2's widening calculus %%%%
%
%Every gap is a direct child of the root and every named gap occurs once, so
%the problem is a LINEAR WORD EQUATION over the two child lists and the finite
%successor set is small: project a gap to the empty run, or widen it by one
%item and continue with a fresh remainder in its slot [source: LeaTTa
%MettaHyperonFull/Core/SeqLinearShallow.lean, solveLinearShallow]. Projection
%comes FIRST, which keeps the shortest-first order the one-sided enumeration
%already has. Nested expressions carry no gap in this fragment, which is why
%every position below the root decides through petta_match_atoms/2.
petta_seq_linear(Left, Right) :-
    (   nonvar(Left),
        Left = [_|_],
        nonvar(Right),
        Right = [_|_]
    ->  petta_seq_linear_items(Left, Right, [], Store),
        petta_seq_publish(Store)
    ;   petta_match_atoms(Left, Right)
    ).

petta_seq_linear_items(Left, Right, Store0, Store) :-
    (   Left == [],
        Right == []
    ->  Store = Store0
    ;   Left == []
    ->  petta_seq_linear_drain(Right, Store0, Store)
    ;   Right == []
    ->  petta_seq_linear_drain(Left, Store0, Store)
    ;   nonvar(Left),
        Left = [L|Ls],
        nonvar(Right),
        Right = [R|Rs],
        petta_seq_linear_step(L, Ls, R, Rs, Store0, Store)
    ).

%One side is exhausted, so every remaining gap on the other takes the empty run
%and every remaining ordinary item refutes.
petta_seq_linear_drain(Items, Store0, Store) :-
    (   Items == []
    ->  Store = Store0
    ;   nonvar(Items),
        Items = [Item|Rest],
        nonvar(Item),
        Item = '$petta_seg'(Var, _),
        petta_seq_project(Var, Store0, Between),
        petta_seq_linear_drain(Rest, Between, Store)
    ).

petta_seq_linear_step(L, Ls, R, Rs, Store0, Store) :-
    (   nonvar(L),
        L = '$petta_seg'(_, _)
    ->  (   nonvar(R),
            R = '$petta_seg'(_, _)
        ->  petta_seq_gaps_meet(L, Ls, R, Rs, Store0, Store)
        ;   petta_seq_gap_meets_item(L, Ls, R, Rs, Store0, Store)
        )
    ;   nonvar(R),
        R = '$petta_seg'(_, _)
    ->  petta_seq_gap_meets_item(R, Rs, L, Ls, Store0, Store)
    ;   petta_match_atoms(L, R),
        petta_seq_linear_items(Ls, Rs, Store0, Store)
    ).

%A gap facing an ordinary item: project the gap to the empty run, or widen it
%by that item and face the item's own successors with a fresh remainder in the
%gap's slot.
petta_seq_gap_meets_item('$petta_seg'(Var, _), After, Item, Rest, Store0, Store) :-
    (   petta_seq_project(Var, Store0, Between),
        petta_seq_linear_items(After, [Item|Rest], Between, Store)
    ;   Fresh = '$petta_seg'(_, anon),
        petta_seq_store(Var, [Item, Fresh], Store0, Between),
        petta_seq_linear_items([Fresh|After], Rest, Between, Store)
    ).

%Two gaps facing each other: either one projects to the empty run, or the left
%adopts the right and continues with a fresh remainder. The identical pair
%cancels, which is the calculus's own first branch for a flex-flex equation.
petta_seq_gaps_meet(Left, Ls, Right, Rs, Store0, Store) :-
    Left = '$petta_seg'(LeftVar, _),
    Right = '$petta_seg'(RightVar, _),
    (   LeftVar == RightVar
    ->  petta_seq_linear_items(Ls, Rs, Store0, Store)
    ;   petta_seq_project(LeftVar, Store0, Between),
        petta_seq_linear_items(Ls, [Right|Rs], Between, Store)
    ;   petta_seq_project(RightVar, Store0, Between),
        petta_seq_linear_items([Left|Ls], Rs, Between, Store)
    ;   Fresh = '$petta_seg'(_, anon),
        petta_seq_store(LeftVar, [Right, Fresh], Store0, Between),
        petta_seq_linear_items([Fresh|Ls], Rs, Between, Store)
    ).

petta_seq_project(Var, Store0, Store) :-
    (   petta_seq_lookup(Var, Store0, Stored)
    ->  Stored == [],
        Store = Store0
    ;   Store = [Var-[]|Store0]
    ).

%%%% The space door %%%%
%
%A pattern with a gap cannot use the store's arity-keyed read: `(A ... D)` has
%three children and matches stored atoms of every arity from two upwards, so
%the arity is what the gap decides rather than what the pattern fixes. The
%candidate set is therefore enumerated per admissible arity, with the pattern's
%own leading child written into the head first so the store's first-argument
%index still dispatches: a gap query for `(edge ... $y)` over a space also
%holding a million `node` atoms reads only the `edge` clauses.
%
%The SUBJECT is stored data and its own marker-shaped atoms are data, never
%gaps, which is why nothing parses it and why every space match sits in the
%one_sided fragment by construction [source: LeaTTa
%MettaHyperonFull/Core/SeqRuntime.lean, residualUnderRigid, "the subject is
%frozen, so its segment markers are ordinary structure and not gaps to solve
%for"].
petta_seq_space(refused(Why), _, _, _, _) :-
    throw(error(Why, none)).
petta_seq_space(query, Space, Parsed, OutPattern, Result) :-
    (   nonvar(Parsed),
        Parsed = [Comma|Conjuncts],
        Comma == ','
    ->  conjunctive_match(petta_seq_conjunction(Space, Conjuncts),
                          Space, Parsed, OutPattern, Result)
    ;   petta_seq_candidate(Space, Parsed, Candidate),
        petta_seq_atoms(Parsed, Candidate),
        acyclic_term(OutPattern),
        Result = OutPattern
    ).

petta_seq_conjunction(_, []).
petta_seq_conjunction(Space, [Conjunct|Conjuncts]) :-
    (   petta_seq_parsed(Conjunct)
    ->  petta_seq_space(query, Space, Conjunct, conj, conj)
    ;   match(Space, Conjunct, conj, conj)
    ),
    petta_seq_conjunction(Space, Conjuncts).

%The candidates a gap pattern can match. A native store answers by arity, so
%only the arities a gap pattern can reach are asked for; every other provider
%answers through match/4's own enumeration, which is the seam every foreign and
%inherited space already reads through.
petta_seq_candidate(Space, Parsed, Candidate) :-
    (   atom(Space),
        \+ seam:foreign_space(Space),
        \+ space_parent(Space, _),
        native_storage_module_cache(Space, Module)
    ->  petta_seq_native_candidate(Module, Space, Parsed, Candidate)
    ;   match(Space, Candidate, Candidate, Candidate)
    ).

%The arity window a gap pattern admits: at least one stored child per ordinary
%pattern child, and no upper bound, so the window is every arity the store
%holds that is not smaller than the pattern's fixed part. current_predicate/1
%enumerates exactly the arities that exist, so an arity nothing is stored under
%is never probed.
petta_seq_native_candidate(Module, Space, Parsed, Candidate) :-
    petta_seq_fixed_length(Parsed, Fixed),
    current_predicate(Module:Space/Arity),
    Arity >= Fixed,
    Arity >= 1,
    functor(Head, Space, Arity),
    petta_seq_index_head(Parsed, Head),
    call(Module:Head),
    Head =.. [_|Candidate],
    acyclic_term(Candidate).

%How many children a candidate must have at least: every non-gap child counts
%one and every gap counts zero, since a gap may consume nothing.
petta_seq_fixed_length(Items, Fixed) :-
    petta_seq_fixed_length_(Items, 0, Fixed).

petta_seq_fixed_length_(Items, Seen, Fixed) :-
    (   nonvar(Items),
        Items = [Item|Rest]
    ->  (   nonvar(Item),
            Item = '$petta_seg'(_, _)
        ->  petta_seq_fixed_length_(Rest, Seen, Fixed)
        ;   Next is Seen + 1,
            petta_seq_fixed_length_(Rest, Next, Fixed)
        )
    ;   Fixed = Seen
    ).

%Write the pattern's leading child into the candidate head when it is a settled
%symbol, so the store's first-argument index selects the relation instead of
%the read walking every clause of that arity. A pattern whose first child is a
%variable or a gap leaves the head open, which is the enumeration it asked for.
petta_seq_index_head(Parsed, Head) :-
    (   nonvar(Parsed),
        Parsed = [First|_],
        atomic(First)
    ->  arg(1, Head, First)
    ;   true
    ).
