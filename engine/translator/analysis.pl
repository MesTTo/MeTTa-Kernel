% Purpose: retain function metadata, translation caches, symbol analysis, and callable-head discovery
% Assumes: engine/translator.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
%   Deferred and eager equation metadata retain only declarations that govern
%   the equation's owning space [tested:
%   spaces_deferred_translation:a_bulk_local_shadow_retains_no_inherited_order_types,
%   translator_head_pattern_notes:bulk_and_single_ingestion_use_the_same_definition_local_mask;
%   commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c].
%   A tracked equation carries its arrival-order governing chains into body
%   translation, while an untracked translation disables every static
%   contract shortcut [tested:
%   translator_literal_type_checks:a_repeated_parameter_contract_has_a_live_static_proof,
%   translator_literal_type_checks:an_untracked_clause_retains_static_and_intrinsic_contracts;
%   commit=c00341f0ff9d83d1b9338ca86ad51708eaf07ebd].
%   A specialized clone keeps the generic call's source arity even when
%   substitution exposes a partial body, while ordinary equations retain eta
%   expansion [tested: specializer:a_specialization_keeps_the_generic_call_arity;
%   commit=1aebfc7b41e7d89893903a3a5f614e5b7c7f8eac].
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/suites/translator/translator.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

% Function source retained for higher-order specialization. Each equation is
% one independently indexed fact, so compiling a new equation does not copy
% every older equation for the same function.
%
% Keyed by MODULE as well as by name, because a space's equations are its own.
% Keyed by name alone, two spaces defining one function shared one pile of
% equations and the specializer generated a clause per equation in the pile:
% two spaces each holding (= (s-map $f $x) ($f $x)), the second compiling
% (= (s-use $z) (s-map s-inc $z)), and that space answered (s-use 1) TWICE
% [measured 2026-08-19, and the same at c7126f1, so this predates the module
% migration rather than following from it]. Under copy() it compounded: the
% clone regenerated what it had already been handed, so a space of four atoms
% cloned to six and answered three times.
:- dynamic metta_any_segment_equation/0.
:- dynamic fun_meta_clause/4.
:- dynamic fun_meta_clause_types/5.

%THE SEGMENT QUESTION IS ASKED ONCE PER EQUATION, not once per call. Every
%call used to reach metta_segment_equation_in/3, which walks a function's
%equation heads with metta_seq_present/1 looking for a sequence variable, and
%a program that uses none paid that walk for the whole search: on
%examples/tilepuzzle.metta it was 7.4% of self time in
%metta_seq_present_items/1 and metta_seq_surface_gap/3, plus the 6.5% in
%fun_meta_clause/4 the walk drives, for a feature the file never mentions
%[measured 2026-08-30, SWI profile over 181,441 states]. Upstream has no
%sequence variables at all, so this is a superset feature and it is now
%pay-per-use: one indexed lookup that fails for a program without one.
%
%Conservative on removal. Retracting the last segment equation leaves the
%flag set, so the walk comes back and the answer stays right; nothing reads
%the flag for anything but skipping work.
record_fun_meta(F, Args, Body) :-
    record_fun_meta(F, Args, Body, _).

record_fun_meta(F, Args, Body, Types) :-
    current_metta_module(Module),
    (   metta_seq_present(Args)
    ->  (   metta_any_segment_equation
        ->  true
        ;   assertz(metta_any_segment_equation)
        )
    ;   true
    ),
    asserta(fun_meta_clause(Module, F, Args, Body), Ref),
    record_source_assertion(Ref),
    (   nb_current('$metta_queued_equation_types', queued(QF, QTypes)),
        QF == F
    ->  Types = QTypes
    ;   fun_meta_types_for_new_clause(Module, F, Types)
    ),
    asserta(fun_meta_clause_types(Module, F, Args, Body, Types), TypeRef),
    record_source_assertion(TypeRef).

%The arrow association above is an ARRIVAL-ORDER property: "the declarations
%that appeared since the previous equation" is decided by when each equation
%arrived among them, and under deferred translation every equation of a name
%compiles at its first call, AFTER every declaration, so the live read handed
%the first clause the whole set and every later clause inherited it. So the
%association is CAPTURED where the equation arrives, one row per deferred
%equation of a DECLARED name, and consumed first-in-first-out as the
%store-order materialisation translates them. An undeclared name, which is
%nearly every function of a bulk load, pays one indexed probe and writes
%nothing.
%
%Limitation: removing one of a function's equations while the function is
%still deferred leaves its queued row behind, so the LATER equations of an
%interleaved-declaration function shift onto their removed sibling's group.
:- dynamic deferred_equation_types/3.

queue_deferred_equation_types(Module, F) :-
    (   catch_recover(definition_type_declaration_in(Module, F, _), fail)
    ->  findall(Chain,
                catch_recover(
                    definition_type_declaration_in(Module, F, Chain), fail),
                Current0),
        list_to_set(Current0, Current),
        exclude(deferred_seen_chain(Module, F), Current, New),
        (   New \== []
        ->  Types = New
        ;   last_queued_types_group(Module, F, Previous)
        ->  Types = Previous
        ;   Types = Current
        ),
        assertz(deferred_equation_types(F, Module, Types), Ref),
        record_source_assertion(Ref)
    ;   true
    ).

deferred_seen_chain(Module, F, Chain) :-
    (   deferred_equation_types(F, Module, Group)
    ;   fun_meta_clause_types(Module, F, _, _, Group)
    ),
    member(Seen, Group),
    Seen =@= Chain,
    !.

last_queued_types_group(Module, F, Group) :-
    (   findall(G, deferred_equation_types(F, Module, G), Groups),
        Groups \== []
    ->  last(Groups, Group)
    ;   fun_meta_clause_types(Module, F, _, _, Group)
    ->  true
    ).

%The consuming half: pop the oldest row and hold it where record_fun_meta/3
%reads, for exactly one translation. Only the materialisation path wraps with
%this, so an equation translated at ARRIVAL keeps the live read that is
%correct for it and cannot eat a deferred sibling's row.
:- meta_predicate materialize_with_queued_types(+, +, 0).
materialize_with_queued_types(Module, F, Goal) :-
    (   retract(deferred_equation_types(F, Module, Types))
    ->  setup_call_cleanup(
            b_setval('$metta_queued_equation_types', queued(F, Types)),
            call(Goal),
            nb_delete('$metta_queued_equation_types'))
    ;   call(Goal)
    ).

%Associate each equation with the arrow declarations that appeared since the
%previous equation for the same function. Source commonly writes an arrow and
%its equation as a pair; when no new arrow appeared, inherit the most recent
%group. The association is only consulted by OrderFittest, so ordinary clause
%dispatch remains the compiled Prolog path.
fun_meta_types_for_new_clause(Module, F, Types) :-
    findall(Chain,
            catch_recover(governing_type_declaration_in(Module, F, Chain),
                          fail),
            Current0),
    list_to_set(Current0, Current),
    include(fun_meta_type_is_new(Module, F), Current, New),
    (   New \== []
    ->  Types = New
    ;   fun_meta_clause_types(Module, F, _, _, Previous)
    ->  Types = Previous
    ;   Types = Current
    ).

fun_meta_type_is_new(Module, F, Chain) :-
    \+ ( fun_meta_clause_types(Module, F, _, _, Previous),
         member(Seen, Previous),
         Seen =@= Chain ).

% The NEAREST module along the chain that has equations for F, and only that
% module's, which is how Prolog resolves the clauses those equations became: a
% named space sees &self's equations because its module is below &self's, and
% stops there rather than gathering a sibling's too.
%Whether F's equations have been translated into THIS module's clauses, which
%is not what the module chain makes visible: it decides whether an arriving
%equation joins clauses that already stand, and clauses inherited from a
%parent are not this module's to join.
metta_function_translated(Module, F) :-
    fun_meta_clause(Module, F, _, _),
    !.

fun_meta_clauses(Module, F, Clauses) :-
    fun_meta_module(Module, F, Owner),
    findall(fun_meta(Args, Body),
            fun_meta_clause(Owner, F, Args, Body), Clauses),
    Clauses \== [].

fun_meta_module(Module, F, Module) :- fun_meta_clause(Module, F, _, _), !.
fun_meta_module(Module, F, Owner) :-
    super_chain(Module, Candidate),
    fun_meta_clause(Candidate, F, _, _),
    !,
    Owner = Candidate.

% Remove one variant-equivalent retained equation. Retraction must not bind the
% caller's variables, and duplicate equations are removed one at a time.
drop_fun_meta(Module, F, Args, Body) :-
    ( once(( clause(fun_meta_clause(Module, F, StoredArgs, StoredBody), true, Ref),
             (StoredArgs-StoredBody) =@= (Args-Body),
             erase(Ref) ))
    -> true
    ; true ),
    drop_fun_meta_types(Module, F, Args, Body).
drop_fun_meta_types(Module, F, Args, Body) :-
    ( once(( clause(fun_meta_clause_types(Module, F, StoredArgs, StoredBody, _),
                    true, Ref),
             (StoredArgs-StoredBody) =@= (Args-Body),
             erase(Ref) ))
    -> true
    ; true ).

% Both retractalls, so an unbound Module means every module. That is what a
% teardown wants and what the engine must never pass.
clear_fun_meta(Module, F) :-
    retractall(fun_meta_clause(Module, F, _, _)),
    retractall(fun_meta_clause_types(Module, F, _, _, _)),
    retractall(head_pattern_note(Module, F, _, _, _)).

% WHAT THE COMPILER DECIDED ABOUT A HEAD PATTERN POSITION, one row per
% position, and every decision it can take there is recorded because all of
% them are invisible in the source.
%
%   functional_pattern the position holds a CALL and compiled to a GOAL rather
%                      than to structure: (= (f (g $x)) $x) runs g and matches
%                      the caller's argument against what it answers. The
%                      retained equation no longer holds the whole head, so
%                      anything reading equations back has to know, and
%                      engine/duals.pl refuses to build a dual for such a
%                      function rather than negate a head it cannot see.
%   defined_label(R)   the label at that position HAS MEANING, through
%                      equations (R = function) or through the translator
%                      (R = translated). The position is still matched
%                      structurally, which is the ruling; what is silent is
%                      that the caller's own argument is EVALUATED on the way
%                      in, so `(= (f (g $x)) $x)` with `g` defined never
%                      matches `!(f (g 3))`, which arrives as `(f (inner 3))`
%                      [measured 2026-08-21].
%
% Naming the second one is the same lint Rust makes deny-by-default: "the
% bindings_with_variant_name lint detects pattern bindings with the same name
% as one of the matched variants... It is usually a mistake to specify an enum
% variant name as an identifier pattern", reported with the position, the name
% and the remedy [source 2026-08-21: doc.rust-lang.org/rustc/lints/listing/
% deny-by-default.html, E0170]. A name in a pattern that also means something
% elsewhere is a known silent-bug source, and naming it is the established
% answer.
%
% BOTH questions are asked about a label, fun/1 and the translator, through
% head_meaning_route/3: asking only the first cost 723 false findings when the
% linter did it [measured 2026-08-17, engine/translator.pl
% metta_translated_head/1]. Only a compound head argument reaches that
% question at all, so an ordinary head of plain variables costs nothing new.
% Module-keyed for the same reason as fun_meta_clause/4: an annotated head in
% one space must not refuse a dual in another
% [tested: translator_head_pattern_notes,
% test_the_compiler_names_a_pattern_position_it_turned_into_a_goal;
% commit=4465fc492071932eab0b2818a4ccd46f01f0d6aa].
:- dynamic head_pattern_note/5.

%The walk reports SHAPE and this decides MEANING, which is what lets
%constrain_args/3's other callers throw the positions away without ever asking
%a question about them.
%
%A head of plain variables reports no position at all, which is most of them,
%and such an equation pays NOTHING for the notes. That costs nothing rather
%than little because of two things, and both are needed. The walk hands its
%positions up a DIFFERENCE LIST, so no equation pays an append/2 over one list
%per head argument, and the label position is decided by an inline `=`/`atom`
%test inside the walk rather than by a helper call. And the only test of
%emptiness is the caller's `Positions == []`, written the way
%apply_translator_rule_dl/7 writes its declaration tests: `==/2` compiles to an
%inline instruction, so an equation with nothing to report reaches neither this
%predicate nor the module lookup under it. An early-return clause here could
%not do that job, because the cost being avoided is paid BEFORE the call.
%
%Measured 2026-08-21 with the MORK backend loaded, bench.py --counter-only,
%the harness's own minimum of three: source-load, a thousand compiled
%equations, measures 1,183,508 inferences with the append/2 shape and
%1,175,508 with this one, which is its baseline exactly. That is eight
%inferences per equation removed and none added.
%
%file-load and save-load-metta cannot be read that way, and the reason is
%worth writing down before someone reads a few inferences as a regression. Both
%load 20,001 atoms, and both move with code LAYOUT: adding N never-called
%clauses to this file, N from zero to seven, moves file-load's minimum over an
%eight-inference span and save-load-metta's over twenty, against a
%four-inference allowance. Run against the same eight layouts with this
%predicate's body neutralised, the two distributions are the same, file-load
%averaging 2.0 inferences over its baseline without the notes and 2.75 with
%them, save-load-metta 7.75 without and 7.25 with. So the notes cost nothing
%measurable on either, and where either lands relative to its pin on any one
%tree is that tree's layout rather than this machinery [measured 2026-08-21:
%bench.py file-load save-load-metta --counter-only, eight layouts each].
%The authoring notes ALONE, run where an equation ARRIVES rather than where
%it compiles, because the two separated: a deferred equation translates at
%its first call, and a note that tells the author what their head just did
%is worthless divorced from the moment they wrote it. The walk is the
%head-compiler's own, so the note text cannot drift from what translation
%will decide, and the memo inside note_head_pattern/5 keeps the
%materialisation's second walk from printing twice. The member/2 prefilter
%is the arrival path's zero-cost guard: a head of plain variables and atoms,
%which is nearly every equation of a bulk load, cannot carry a note and
%never reaches the walk.
head_pattern_notes_for(Module, [=, [F|Args], _]) :-
    (   member(Argument, Args),
        compound(Argument)
    ->  constrain_head_arguments(Args, 1, Module, F, definition_local, _, _,
                                 Positions),
        (   Positions == []
        ->  true
        ;   forall(( member(head_position(RevPath, Label, Kind), Positions),
                     head_pattern_reason(Module, definition_local, F,
                                         RevPath, Label, Kind, Reason) ),
                   note_head_pattern(Module, F, RevPath, Label, Reason))
        )
    ;   true
    ).

record_head_pattern_notes(F, Positions) :-
    current_metta_module(Module),
    forall(( member(head_position(RevPath, Label, Kind), Positions),
             head_pattern_reason(Module, governing, F, RevPath, Label, Kind,
                                 Reason) ),
           note_head_pattern(Module, F, RevPath, Label, Reason)).

%A functional pattern is the OTHER head argument that compiles to a goal, so
%it reports unconditionally for the same reason: engine/duals.pl reads these
%notes to decide which heads it cannot dualise, and a constraint it cannot
%see is one it would silently claim past
%[tested: duals_refusals:a_functional_pattern_head_has_no_dual;
%commit=c530ccb8fb7d0a5b2aa53df6e9f981ada9f81be8].
head_pattern_reason(_, _, _, _, _, functional_pattern, functional_pattern).
%THE LABEL QUESTION FIRST, and the order is what the two questions cost rather
%than taste. head_meaning_route/3 reads Prolog facts, metta_special_form/1,
%translator_rule/3 and fun/1, and fails at once for a label that means nothing,
%which is what most compound head arguments hold. unevaluated_head_argument/4
%reads a TYPE DECLARATION, and a name the prelude has not declared falls
%through to a match against &self, so asking it first paid a space query for
%every such label. Both goals are pure tests, so the order decides only what
%gets asked: 500 equations of the shape `(= (f (Cons $x $xs)) $x)` cost 62
%inferences each for their note with the type question first and 23 with the
%label question first, while the same file written with plain heads measures
%the same either way [measured 2026-08-21: 500 equations in a fresh space,
%minimum of three, 466,901 against 447,405 inferences over a 336,401-inference
%plain-head control].
head_pattern_reason(Module, DeclarationTier, F, RevPath, Label, label,
                    defined_label(Route)) :-
    head_meaning_route(Module, Label, Route),
    last(RevPath, Argument),
    \+ unevaluated_head_argument(DeclarationTier, Module, F, Argument).

%A parameter carrying the evaluation mask receives its argument AS WRITTEN, so
%a structural pattern at that position is exactly what the caller hands over
%and there is nothing to report. This is what keeps the note off the shipped
%control forms, whose whole design is `(: union (-> Atom Atom %Undefined%))`
%with `(= (union (superpose $a) (superpose $b)) ...)` under it; without it the
%engine's own prelude would emit six notes at boot, which is the shape of the
%723 false findings the linter produced by asking a narrower question
%[measured 2026-08-21]. The mask decides a whole argument, so it decides every
%subterm inside it, which is why the OUTERMOST index of the path is the one
%asked about. Bulk ingestion records the note before register_fun_in/2, so its
%arrival-time question uses the equation owner's local declarations directly;
%the compiler asks the governing selector after ownership is registered. This
%keeps the bulk and single-atom doors equivalent when an untyped local equation
%hides an inherited mask [tested:
%translator_head_pattern_notes:bulk_and_single_ingestion_use_the_same_definition_local_mask;
%commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c].
unevaluated_head_argument(definition_local, Module, F, Argument) :-
    catch_recover(definition_type_declaration_in(Module, F, [->|Xs]), fail),
    append(ArgTypes, [_], Xs),
    nth1(Argument, ArgTypes, Type),
    non_evaluated_parameter_type(Type).
unevaluated_head_argument(governing, Module, F, Argument) :-
    catch_recover(governing_type_declaration_in(Module, F, [->|Xs]), fail),
    append(ArgTypes, [_], Xs),
    nth1(Argument, ArgTypes, Type),
    non_evaluated_parameter_type(Type).

%The walk carries its path innermost-first, because prepending is what a walk
%can do without copying; the reader wants it outermost-first.
note_head_pattern(Module, F, RevPath, Label, Reason) :-
    reverse(RevPath, Path),
    (   head_pattern_note(Module, F, Path, Label, Reason)
    ->  true
    ;   assertz(head_pattern_note(Module, F, Path, Label, Reason), Ref),
        record_source_assertion(Ref),
        print_message(informational,
                      metta_head_pattern_note(F, Path, Label, Reason))
    ).

%An equation head is a PATTERN, matched, and this walk builds it. The only
%thing that is not pure structure is the in-place type annotation below, which
%is a constraint on what a position may match rather than a computation.
%
%Nothing here asks whether a label happens to have equations. It used to: a
%head argument whose label was a defined function became a CALL, Curry's
%functional pattern, so (= (f (g $x)) $x) compiled to f(A, B) :- g(B, A) and
%ran g backwards. The mechanised semantics has one matching relation and it
%does not consult that. AST.matchPat's own words are "a pattern variable
%matches any subterm (and must match consistently if it recurs); CONSTRUCTORS
%MATCH STRUCTURALLY; everything else matches only itself", four cases and no
%case reading whether a label is defined [source 2026-08-19:
%LeaTTa/MeTTaIL/Semantics/Reduce.lean:30-46, AST.matchPat], and equations are
%applied by matching the whole left-hand side, `(matchAtoms p.fst a)`
%[source 2026-08-19: LeaTTa/MettaHyperonFull/Operational/Properties.lean:48-50,
%firedReducts].
%
%The question is asked once more AFTER the walk, and only to say so:
%record_head_pattern_notes/2 reports a position whose label has meaning,
%because the caller's argument is evaluated on the way in and the position can
%then only match a term handed over unevaluated. It decides nothing about what
%compiles.
%
%Two of the arbiter's own corpus files decide it, and this engine failed both.
%`(= (outer-hold (inner-sum $x $y)) outer-held)` with `(: outer-hold (-> Atom
%Symbol))` answers `outer-held` there and RAISED here, because the head became
%`inner-sum` run backwards over syntax; and `(= (nested-atom (produce-pa3))
%nested-argument-held)` beside `(= (nested-atom pa3) ...)` answers only
%`nested-argument-evaluated` there and answered BOTH here [measured 2026-08-19:
%LeaTTa/tests/semantics/types-meta/19_atom_parameter_outer_call.metta and
%15_atom_parameter_nested_parametric.metta, through
%tests/conformance/answer_groups.pl].
%
%The relational reading is not lost, it is written where it runs: a `let` in
%the body says the same thing and answers the same answers
%[tested: examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/06-functionhead.metta,
%examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/07-functionhead2.metta,
%examples/ch05-equations-and-evaluation/05-01-an-equation-is-a-rewrite/08-functionhead3.metta].
%% constrain_args(+Pattern, -Constrained, -Goals) is det.
%The three-argument form for every caller that only wants the pattern: case
%keys, typed lets and case duals all compile a pattern and none of them is an
%equation head, so the positions the walk reports go nowhere and no question is
%ever asked about them.
constrain_args(In, Out, Goals) :-
    constrain_args(In, Out, Goals, [], _, _, structural).

%% constrain_args(+Pattern, -Constrained, -Goals, +ReversedPath, -Positions, ?PositionsTail, +Invert) is det.
%Positions is a DIFFERENCE LIST, ending in the tail the caller supplies, for
%the reason translate_expr_dl/4's goals are: a walk that appended what its
%children reported charged every compiled equation for the append, whether or
%not anything was reported.
constrain_args(X, X, [], _, Positions, Positions, _) :- (var(X); atomic(X)), !.
%QUOTE IS A SCOPE HERE, exactly as it is in a body. A body's `(quote X)` holds
%X and compiles nothing inside it
%[source 2026-08-21: engine/translator.pl,
%translate_special_dl(quote, [Expr], Goals, Goals, [quote, Expr])]. A pattern's
%did not: the walk descended and rewrote what it found, so the same two words
%meant two things depending on which side of the `=` they were written on.
%Measured 2026-08-21 on the tip before this clause: `(= (b4) (quote (cons
%1 2)))` compiled to the value `[quote, [cons, 1, 2]]` while
%`(= (h4 (quote (cons 1 2))) matched4)` compiled to the pattern
%`[quote, [1|2]]`, so the head could never match the value the body produced;
%and `(= (h3 (quote (: $x Number))) matched)` compiled to
%`h3([quote, A], matched) :- has_type(A, 'Number')`, which matched `(quote 5)`
%and refused the quoted annotation it was written to match. One arity, because
%the body's scope is one argument too: `(quote a b)` is not the scope form on
%either side [tested: translator_quote_scope,
%test_quote_is_a_scope_in_head_position_too; commit=4465fc492071932eab0b2818a4ccd46f01f0d6aa].
constrain_args([Quote, Expr], [Quote, Expr], [], _, Positions, Positions, _) :-
    nonvar(Quote), Quote == quote, !.
%A COLON FORM IN A HEAD IS ORDINARY STRUCTURE, matched like any other list.
%
%It was an IN-PLACE TYPE ANNOTATION until 2026-08-30: `(: $x T)` in a head
%parameter desugared to a plain variable plus the type premise
%`(has_type(V,T) *-> true ; get-metatype(V,T))`, which is
%hyperon-experimental issue #177's dynamic half and a feature the previous
%arbiter implemented. Upstream has no such reading, and the two disagree on
%BOTH calls rather than on an edge: with `(= (fann (: $x Number)) $x)`,
%upstream answers nothing for `(fann 5)` and `5` for `(fann (: 5 Number))`,
%and the annotation reading answered exactly the other way round
%[measured 2026-08-30 against PeTTa@ae66fa8].
%
%It is not a corner. The reading swallows every `(: A B)` head pattern, so a
%program whose SUBJECT is `(: proof theorem)` terms cannot destructure one in
%a head at all: upstream's examples/nilbc.metta compiles
%`(= (bc $kb $_ (: $proof $theorem)) (match $kb (: $proof $theorem) ...))` to
%`bc(A, B, C) :- (has_type(B, E) *-> true ; get-metatype(B, E)), match(A, [:,
%B, E], ...)`, which asks the knowledge base for the argument's TYPE instead
%of matching the query, and the file's first proof search answered nothing.
%The note that shipped the feature recorded the cost as "It needed ONE clause
%changed" in that file; a semantics the corpus has to be edited for is the
%wrong semantics.
%
%A program that wants a type where it can PRUNE writes the premise in the
%body, which is what upstream's own corpus does.
constrain_args([F, A, B], Out, Goals, Path, Positions, Rest, Invert) :-
    nonvar(F),
    F == cons,
    constrain_args(A, A1, G1, [1|Path], Positions, AfterA, Invert),
    constrain_args(B, B1, G2, [2|Path], AfterA, Rest, Invert),
    Out = [A1|B1],
    append(G1, G2, Goals), !.
%CURRY'S FUNCTIONAL PATTERN. A head argument that is a CALL to a defined
%function becomes a fresh variable plus a prefix goal that runs the function,
%so `(= (f (g $x)) $x)` compiles to `f(A, B) :- g(B, A)` and constrains the
%argument by running g BACKWARDS. It is the mechanism upstream calls
%constrain_args/3 and the whole point of its functionhead examples: `(= (cat
%(animal $X)) ...)` admits only the $X that `animal` produces, and `(= (h
%(myfunc (10) $B) $C) ($B $C))` solves $B from the value the caller passed
%[source: PeTTa@ae66fa8 src/translator.pl:9-12, `constrain_args([F|Args], Var,
%Goals) :- atom(F), fun(F), !, translate_expr([F|Args], GoalsExpr, Var)`].
%The name is Curry's: a functional pattern is a left-hand-side call solved by
%narrowing rather than matched as a constructor term.
%
%This engine dropped it on 2026-08-19 because LeaTTa's matching relation has
%no case for it, and rewrote five examples to say the same thing with a `let`
%in the body. That reasoning was sound for LeaTTa and does not survive the
%move to upstream as the only oracle: functionhead, functionhead2,
%functionhead3, patrick_test and tilepuzzle all need it and all diverged
%without it [measured 2026-08-30, tests/conformance/petta].
%
%ONLY WHERE THE ARGUMENT IS A VALUE. Invert is `structural` for a position
%carrying the evaluation mask, because such a position receives its argument
%AS WRITTEN: asking which input makes a function PRODUCE a given piece of
%syntax is not what any author meant, and this engine's own prelude depends on
%it, `(= (union (superpose $a) (superpose $b)) ...)` under `(: union (-> Atom
%Atom %Undefined%))` matching the literal call. Upstream never meets the
%collision -- `fun(union)` is false there, its lib has no such equation -- so
%gating costs nothing against upstream and keeps the prelude working
%[measured 2026-08-30: fun(superpose) is true on BOTH engines, so the fun/1
%test alone does not separate them].
constrain_args([F|Args], Var, Goals, Path,
               [head_position(Path, F, functional_pattern)|Positions],
               Positions, invert) :-
    atom(F),
    fun(F),
    !,
    translate_expr([F|Args], Goals, Var).
%Numbered from ZERO here and from one in translate_clause/3, because a nested
%sub-pattern carries its own label at the front and an equation head's argument
%list does not: `(= (f (h (g $x))) ...)` puts `(g $x)` at head argument 1,
%subterm 1, which is where a reader counting arguments looks for it.
%The LABEL of a compound sub-pattern goes on the front of what the children
%report, whether or not it means anything: whether it does is decided once,
%where the notes are recorded, so a caller that discards them never asks. The
%test is written here rather than in a helper because a helper is a CALL, and
%a call is an inference every compound head argument would pay; `=/2` and
%`atom/1` compile to inline instructions, so this costs nothing
%[measured 2026-08-21: a clause whose body is this if-then-else measures the
%same inference count as one whose body is `true`, and a clause that calls a
%helper instead measures one more].
constrain_args(In, Out, Goals, Path, Positions, Rest, Invert) :-
    (   In = [Label|_], atom(Label)
    ->  Positions = [head_position(Path, Label, label)|ChildPositions]
    ;   Positions = ChildPositions
    ),
    constrain_children(In, 0, Path, Out, NestedGoalsList, ChildPositions, Rest,
                       Invert),
    flatten(NestedGoalsList, Goals), !.

%A sub-pattern's children, numbered from one so a note can say WHICH child of
%which argument it is about. maplist/4 cannot count.
constrain_children([], _, _, [], [], Positions, Positions, _).
constrain_children([C|Cs], I, Path, [O|Os], [G|Gs], Positions, Rest, Invert) :-
    constrain_args(C, O, G, [I|Path], Positions, AfterC, Invert),
    J is I + 1,
    constrain_children(Cs, J, Path, Os, Gs, AfterC, Rest, Invert).

%The predicates the ENGINE emits into a compiled clause body, and the reason
%they have to be named somewhere.
%
%A compiled body resolves its goals in the module the clause went into, which
%is the space's. That is exactly right for a MeTTa call, because redefining a
%function in a space is what a space is for. It is exactly wrong for a goal
%the TRANSLATOR wrote: `(= (include $a $b) whatever)` would take over the
%include/3 that filter-atom compiles to, in that space's own bodies, silently
%and with a wrong answer rather than an error. Ten indicators were capturable
%that way over the shipped corpus [measured 2026-08-19].
%
%They are protected by IMPORTING them into every space's module rather than by
%a guard the write path has to remember: an explicit import is a binding SWI
%refuses to overwrite, so the assert raises permission_error and
%assert_function_clause/3 turns that into the MeTTa-level refusal it already
%turns Prolog's protected core into. No check on the hot path, no cost at run
%time, and the space still reaches the engine's own predicate through the
%import [tested: spaces_execution_modules:an_engine_emitted_name_cannot_be_taken].
%
%Engine-emitted ONLY. A Prolog goal a PROGRAM writes through
%translatePredicate is the program's own and resolves in its space
%deliberately, which is why open_string/2 and load_files/2 are absent even
%though they reach compiled bodies [measured 2026-08-19:
%lib/lib_tabling/lib_tabling.metta writes both].
%
%The list is checked rather than trusted. tests/prolog/static_checks.pl
%recompiles every equation in the corpus, reads the goals out of the bodies
%and fails if one of them is capturable and not named here, so a translation
%rule added later cannot quietly widen the hole.
%
%And it can GROW after boot, which is what makes it a seam. Two things add to
%it: an engine upgrade whose new translation rule emits a goal, and a library
%that teaches the engine to emit one of its own through seam:dispatch_call/4.
%Both are the case Logtalk's module critique names -- "any update that strictly
%adds new exported predicates has the potential to break existing applications"
%-- so the addition path is the one that has to be safe: it imports the new
%name into every space that already exists, and a space that already defines
%that name is REFUSED by protect_engine_emitted/1 (engine/spaces.pl) naming
%both parties, rather than left to be settled by which import happened first
%[tested: test_adding_an_engine_export_changes_no_spaces_answers].
:- multifile seam:engine_emitted/1.
:- dynamic seam:engine_emitted/1.
seam:engine_emitted(case_default_runtime/2).
seam:engine_emitted(case_runtime/3).
seam:engine_emitted(control_exception/1).
seam:engine_emitted(foldall/4).
seam:engine_emitted(has_type/2).
seam:engine_emitted(check_argument_type/3).
seam:engine_emitted(check_argument_type_under_policy/3).
seam:engine_emitted(check_argument_type_under_live_policy/3).
seam:engine_emitted(include/3).
seam:engine_emitted(letstar_runtime/3).
seam:engine_emitted(metta_ensure_duals/1).
%engine/duals.pl emits these two, into the dual clause it builds.
seam:engine_emitted(metta_negation/5).
%metta_dual_goal/2 was emitted and NOT declared, so protect_engine_emitted/1
%never bound it into a space's module and a MeTTa function of that name at
%arity one would have captured every dual's calls. Nothing said so while the
%engine shared one namespace and the base chain found it anyway; cutting
%engine/duals.pl into a module made a compiled body raise
%existence_error(procedure, '$metta_exec:&self':metta_dual_goal/2) instead
%[measured 2026-08-22, on examples/ch22-a-reasoner-you-can-serve/22-01-logic-programs/03-constructive_negation.metta].
seam:engine_emitted(metta_dual_goal/2).
seam:engine_emitted(metta_forall_c/2).
seam:engine_emitted(metta_generator_forall/5).
seam:engine_emitted(metta_crossed_negation/1).
seam:engine_emitted(metta_not_functor/3).
%library(dif)'s own, emitted by engine/duals.pl as the negation of an
%equality. Declared for the same reason as the rest: without it a MeTTa
%function named dif at one argument compiles to dif/2 and captures every
%generated dual's disequality.
seam:engine_emitted(dif/2).
%Four more this file emits and never declared. They reached a space's module
%through the base chain while the whole engine shared one namespace, and the
%module cut turned each into
%existence_error(procedure, '$metta_exec:&self':<name>) on the corpus.
seam:engine_emitted(agg_reduce/4).
seam:engine_emitted(hyperpose_branch/4).
seam:engine_emitted(hyperpose_runtime/2).
seam:engine_emitted(metta_condition_holds/2).
%The platform guard both hyperpose branches carry, so a build without
%library(thread) refuses (hyperpose ...) by name instead of raising
%existence_error(procedure, concurrent_and/3) from inside the compiled body.
%Declared for the same reason as the four above: it is a goal the compiler
%writes, and a MeTTa function of that name at one argument would take it.
seam:engine_emitted(metta_require_platform/2).
%engine/spaces.pl defines these two and the compiler emits them: a bounded
%match and a bounded take, both written into the clause a limited query
%compiles to.
seam:engine_emitted(match_bounded/5).
seam:engine_emitted(metta_take/2).
seam:engine_emitted(metta_take_match/5).
%Three more of engine/spaces.pl's that this file emits: the two (top k ...)
%forms and the merged match a literal (superpose (&a &b)) space compiles to.
%The corpus-recompile check above could not see these, because it reads goals
%out of equations the SHIPPED corpus compiles and no shipped equation uses
%either form; the benchmark suite does, and reported
%existence_error(procedure, '$metta_exec:&pyspace_1':metta_top/3) the moment
%engine/spaces.pl became a module. What found the third one before anything ran
%it is the source half added beside that check, which reads what this file
%CONSTRUCTS rather than what a corpus happens to reach
%[measured 2026-08-22; tested: static_checks:every_emitted_goal_is_reachable].
seam:engine_emitted(metta_top/3).
seam:engine_emitted(metta_top_match/5).
seam:engine_emitted(metta_merged_match/3).
%engine/specializer.pl's, written into a specialized call's body when
%(pragma! verify-specializations true) is set.
seam:engine_emitted(metta_verified_specialization/2).
seam:engine_emitted(metta_require_current_capability/2).
seam:engine_emitted(metta_require_safe_goal/1).
seam:engine_emitted(metta_require_space_update_capability/2).
seam:engine_emitted(metta_match_atoms/2).
seam:engine_emitted(metta_answer_terms/3).
seam:engine_emitted(metta_prune_empty/2).
seam:engine_emitted(metta_prune_empty_answers/2).
seam:engine_emitted(metta_run_named/3).
seam:engine_emitted(metta_run_with_fuel/3).
seam:engine_emitted(metta_transaction/1).
seam:engine_emitted(metta_with_seed/4).
seam:engine_emitted(switch_runtime/3).
seam:engine_emitted(metta_evaluation_fuel/1).
seam:engine_emitted(metta_fuel_exhausted/1).
seam:engine_emitted(function_overapplication/3).
seam:engine_emitted(declared_arity_refusal/3).
seam:engine_emitted(metta_bad_argument_error/3).
seam:engine_emitted(dispatch_mismatch_result/3).
seam:engine_emitted(dispatch_no_match_result/3).
seam:engine_emitted(dispatch_policy_execute/5).
seam:engine_emitted(metta_application_result/3).
seam:engine_emitted(metta_application_result/4).
seam:engine_emitted(metta_eval_step/2).
seam:engine_emitted(metta_evalc_step/3).
seam:engine_emitted(metta_evaluate_argument/2).
seam:engine_emitted(metta_evaluate_symbol/2).
seam:engine_emitted(metta_dynamic_call/3).
%The prolog-import special form emits the deferral force ahead of its direct
%goal, because the importer is itself a MeTTa equation whose clauses may not
%exist yet when the emitted goal runs.
seam:engine_emitted(metta_ensure_compiled/1).
seam:engine_emitted(metta_dynamic_head_masks/1).
seam:engine_emitted(metta_dynamic_value_call/4).
seam:engine_emitted(metta_chain_step/2).
seam:engine_emitted(collapse_runtime/2).
seam:engine_emitted(metta_segment_dispatch/4).
seam:engine_emitted(metta_segment_rule_result/6).
%The result half of the evaluation mask. engine/translator/special_forms.pl's
%masked_result_goal/3 writes it into every compiled body whose declared result
%re-enters evaluation, so a MeTTa function named metta_masked_result at two
%arguments would otherwise capture the continuation of every such call.
seam:engine_emitted(metta_masked_result/2).

%Resolving at compile time means the answer can go stale: a space that gains
%a definition of the name becomes the nearer parent, and one that loses its
%last equation stops being a parent at all. Both are function CHANGES, and the
%engine already announces those, so the recompile hangs off the announcement
%rather than off a second mechanism. It is the shape repair_stale_definitions/1
%(engine/filereader.pl) uses for the neighbouring problem, a definition compiled
%against a declaration that has since moved.
%
%Guarded by a flag rather than run always: the hook fires for every compiled
%equation, and a program that never writes `super` should pay one indexed
%probe for that rather than a walk over every recorded translation
%[tested: translator_super:a_later_definition_retargets_an_earlier_super].
%recompile_function_impl/1 rebuilds a name one MODULE at a time, which is what
%makes this safe to call on the name that just changed: the definition the
%super needs is in a different module and is not erased under it.
:- dynamic super_call_compiled/1.

note_super_call(Fun) :-
    ( super_call_compiled(Fun) -> true ; assertz(super_call_compiled(Fun)) ).

%A restricted space is fixed before its first use, so its execution module is
%known while the translator builds a body. Emit guards only into that module:
%ordinary modules keep their pre-restriction goal lists and pay no guard on a
%hot call, while a restricted body keeps the check immediately before the
%operation it protects [tested: translator_restricted_guards;
%commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
translate_in_restricted_space :-
    current_metta_module(Module),
    metta_restricted_exec_module(Module, _).

translate_restricted_guard_dl(Guard, Tail, Goals) :-
    (   translate_in_restricted_space
    ->  Goals = [Guard|Tail]
    ;   Goals = Tail
    ).

:- multifile seam:function_changed/1.
seam:function_changed(Fun) :-
    %Muted during a space release: the dying world's own super users die
    %with it and cross-world users cannot exist, so recompiling here only
    %ever resolved super inside a half-dead world
    %[source: engine/spaces/lifecycle.pl, metta_release_space/1].
    \+ nb_current('$metta_space_releasing', true),
    super_call_compiled(Fun),
    findall(User,
            ( translated_from(_, [=, [User|_], Body]),
              atom(User),
              uses_super(Fun, Body) ),
            Users0),
    sort(Users0, Users),
    forall(member(User, Users), recompile_function_impl(User)).

%The SOURCE shape, `(super (Fun ...))`, read off the recorded term rather than
%off the compiled body: the compiled body holds the module this resolved to
%last time, which is exactly the thing that may be wrong.
uses_super(Fun, Term) :-
    sub_term(Sub, Term),
    is_list(Sub),
    Sub = [super, Call],
    is_list(Call),
    Call = [Fun|_],
    !.

%A `super` form takes a CALL, and it has to name its function: `(super $f)`
%cannot be resolved without running, and saying so is better than compiling a
%call to whatever $f turns out to be.
super_call_parts(Call, Fun, Args) :-
    (   is_list(Call), Call = [Head|Rest], atom(Head)
    ->  Fun = Head, Args = Rest
    ;   throw(error(type_error(metta_super_call, Call),
                    context(super/1,
                            'super takes a call whose head is a function name')))
    ).

%The first module ABOVE this one that owns a definition of the name. Above,
%not including: a shadow calling `super` means "not me", so the walk starts at
%the parent, and a space with no shadow of its own gets the same answer it
%would have got by calling the name plainly.
%
%module_owns_function/2 for a MeTTa function, which excludes an inherited
%clause, and a plain definedness test for a predicate the engine compiled,
%because the engine's own are not equations and own no clause record.
super_target_module(Module, Fun, Arity, Parent) :-
    (   super_chain(Module, Candidate),
        super_defines(Candidate, Fun, Arity)
    ->  Parent = Candidate
    ;   metta_module_space(Module, Space),
        throw(error(existence_error(metta_super_definition, Fun/Arity),
                    context(super/1, Space)))
    ).

super_chain(Module, Parent) :- import_module(Module, Parent).
super_chain(Module, Ancestor) :-
    import_module(Module, Parent),
    Parent \== Module,
    super_chain(Parent, Ancestor).

%A CLAUSE, not merely a name. retractall/1 on a predicate that has none
%leaves it defined and empty, which is what a space that removed its last
%equation for a name leaves behind, and reading that as a definition sent
%`super` to a module with nothing in it
%[tested: translator_super:a_later_definition_retargets_an_earlier_super].
%A foreign or built-in predicate has no clause count and does answer, so the
%count is required only where it exists.
super_defines(Module, Fun, Arity) :-
    compiled_function_name(Fun, Predicate),
    functor(Head, Predicate, Arity),
    predicate_property(Module:Head, defined),
    \+ predicate_property(Module:Head, imported_from(_)),
    (   predicate_property(Module:Head, number_of_clauses(Clauses))
    ->  Clauses > 0
    ;   true
    ).

%Flatten (= Head Body) MeTTa function into Prolog Clause:

%% translate_clause(+Equation, -Clause) is semidet.
translate_clause(Input, Clause) :-
    translate_clause(Input, Clause, true).

%% translate_clause(+Equation, -Clause, +ConstrainArgs:boolean) is semidet.
translate_clause(Input, Clause, ConstrainArgs) :-
    with_static_contract_shortcuts(
        disabled,
        translate_clause_impl(Input, Clause, ConstrainArgs, eta_expand)).

%% translate_tracked_clause(+Equation, -Clause) is semidet.
translate_tracked_clause(Input, Clause) :-
    translate_tracked_clause(Input, Clause, true).

%% translate_tracked_clause(+Equation, -Clause, +ConstrainArgs:boolean) is semidet.
translate_tracked_clause(Input, Clause, ConstrainArgs) :-
    with_static_contract_shortcuts(
        enabled,
        translate_clause_impl(Input, Clause, ConstrainArgs, eta_expand)).

%% translate_specialized_clause(+Equation, -Clause, +ConstrainArgs:boolean) is semidet.
%
% A specialization clones an existing callable and its call site has already
% fixed that callable's arity. Constant substitution may turn the cloned body
% into a partial application, but that is the clone's RESULT, not permission
% to widen its ABI. Ordinary source equations still use eta_expand above.
translate_specialized_clause(Input, Clause, ConstrainArgs) :-
    with_static_contract_shortcuts(
        enabled,
        translate_clause_impl(Input, Clause, ConstrainArgs,
                              preserve_source_arity)),
    specialized_clause_arity(Input, Clause).

specialized_clause_arity([=, [_|SourceArgs], _], (Head :- _)) :-
    length(SourceArgs, InputArity),
    ExpectedArity is InputArity + 1,
    functor(Head, _, ExpectedArity).

:- meta_predicate with_static_contract_shortcuts(+, 0).
with_static_contract_shortcuts(Mode, Goal) :-
    (   nb_current('$metta_static_contract_shortcuts', Previous)
    ->  Restore = previous(Previous)
    ;   Restore = absent
    ),
    setup_call_cleanup(
        nb_setval('$metta_static_contract_shortcuts', Mode),
        call(Goal),
        restore_static_contract_shortcuts(Restore)).

restore_static_contract_shortcuts(previous(Previous)) :-
    nb_setval('$metta_static_contract_shortcuts', Previous).
restore_static_contract_shortcuts(absent) :-
    nb_delete('$metta_static_contract_shortcuts').

translate_clause_impl(Input, (Head :- BodyConj), ConstrainArgs, _) :-
    Input = [=, [F|Args0], BodyExpr],
    metta_seq_present(Args0),
    !,
    translate_equation_head(F, Args0, ConstrainArgs, Args1, GoalsPrefix),
    record_fun_meta(F, Args1, BodyExpr, ArrivalTypes),
    metta_seq_head_plan(Args1, HeadPlan),
    current_metta_module(Module),
    with_static_parameter_environment(
        Module, F, Args1, ArrivalTypes,
        translate_segment_body_plan(F, BodyExpr, GoalsPrefix, BodyPlan)),
    same_length(Args1, CallArgs),
    append(CallArgs, [Out], FinalArgs),
    compiled_function_name(F, Predicate),
    Head =.. [Predicate|FinalArgs],
    length(FinalArgs, CompiledArity),
    register_arity(F, CompiledArity),
    RawBody = metta_segment_rule_result(Module, F, HeadPlan, BodyPlan,
                                        CallArgs, RawOut),
    append(CallArgs, [RawOut], RawFinalArgs),
    RawHead =.. [Predicate|RawFinalArgs],
    merge_branch_returns(RawHead, RawBody, MergedRawBody),
    normalize_equation_result(F, CallArgs, RawOut, Out, MergedRawBody,
                              BodyConj0),
    merge_branch_returns(Head, BodyConj0, BodyConj1),
    defer_application_protocol(BodyConj1, BodyConj, HasNegation),
    (   HasNegation == found
    ->  quantify_negations(Head, BodyConj)
    ;   true
    ).
translate_clause_impl(Input, (Head :- BodyConj), ConstrainArgs, ArityPolicy) :-
                                               Input = [=, [F|Args0], BodyExpr],
                                               translate_equation_head(F, Args0, ConstrainArgs,
                                                                       Args1, GoalsPrefix),
                                               record_fun_meta(F, Args1, BodyExpr,
                                                               ArrivalTypes),
                                               current_metta_module(Module),
                                               with_static_parameter_environment(
                                                   Module, F, Args1, ArrivalTypes,
                                                   translate_equation_body_result(
                                                       F, BodyExpr, GoalsBody,
                                                       ExpOut)),
                                               (  ArityPolicy == eta_expand,
                                                  nonvar(ExpOut),
                                                  ExpOut = partial(Base,Bound)
                                               -> length(Bound, N),
                                                  MinimumArity is N + 1,
                                                  metta_ensure_compiled(Base),
                                                  setof(A, (arity(Base, A), A > MinimumArity), [Arity|_]),
                                                  M is (Arity - N) - 1,
                                                  length(ExtraArgs, M), append(Bound, ExtraArgs, CallInArgs),
                                                  resolve_dispatch(Base, CallInArgs, RawOut, Goal),
                                                  dispatch_call_goal(Base, CallInArgs, RawOut, Goal, PolicyGoal),
                                                  append(GoalsBody,[PolicyGoal],FinalGoals), append(Args1,ExtraArgs,HeadArgs),
                                                  drop_superseded_arity(F, Args1, HeadArgs)
                                               ; FinalGoals= GoalsBody , HeadArgs = Args1, RawOut = ExpOut ),
                                               append(HeadArgs, [Out], FinalArgs),
                                               compiled_function_name(F, Predicate),
                                               Head =.. [Predicate|FinalArgs],
                                               length(FinalArgs, CompiledArity),
                                               register_arity(F, CompiledArity),
                                               append(GoalsPrefix, FinalGoals, Goals),
                                               goals_list_to_conj(Goals, RawBodyConj),
                                               append(HeadArgs, [RawOut], RawFinalArgs),
                                               RawHead =.. [Predicate|RawFinalArgs],
                                               merge_branch_returns(RawHead, RawBodyConj,
                                                                    MergedRawBody),
                                               normalize_equation_result(F, HeadArgs, RawOut, Out,
                                                                         MergedRawBody, BodyConj0),
                                               merge_branch_returns(Head, BodyConj0, BodyConj1),
                                               defer_application_protocol(BodyConj1, BodyConj, HasNegation),
                                               ( HasNegation == found
                                                 -> quantify_negations(Head, BodyConj)
                                                  ; true ).

%A compiled equation owns the language boundary around its own result.  This
%is the worker-wrapper split needed by recursive functions: a callee already
%turns its bare NotReducible result into that callee's runtime call, so a body
%whose tail is another compiled equation can pass the caller's output variable
%straight through and remain a last call.  Every other tail receives the
%ordinary protocol locally.  Keeping the transform branch-aware prevents one
%post-call continuation being replayed at every recursive depth while a
%nondeterministic generator enumerates its answers.
%Result normalization needs a fresh raw result when the call runs forwards:
%a bare NotReducible must become the runtime call rather than bind the public
%result to the marker. The old clause was relational too, however, and a
%caller may supply that public result to solve the body backwards. Constrain
%the raw result before the body only in that mode. A self-tail fusion removes
%RawOut from Normalized and therefore keeps its last-call path guard-free.
%[source: MettaHyperonFull/Minimal/Interpreter.lean:7350-7361 and 7533-7564;
%tested: tests/prolog/suites/translator/translator.plt:
%a_recursive_generator_enumerates_in_time_linear_in_its_answers and
%tests/prolog/suites/seams/conformance2.plt; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
normalize_equation_result(Fun, Args, RawOut, Out, RawBody, Body) :-
    Runtime = [Fun|Args],
    normalize_equation_tail(RawBody, RawOut, Runtime, Out, Normalized),
    term_variables(Normalized, Variables),
    (   variable_member(Variables, RawOut)
    ->  Body = (( nonvar(Out) -> RawOut = Out ; true ), Normalized)
    ;   compound(RawOut)
    %A constructor-composed result seeds the same way a variable result
    %does.  The produced term for a body like `(S (nplus $x $y))` is always
    %`['S'|_]` -- an irreducible inner call is retained INSIDE the
    %structure, never in place of it -- so when the caller arrives with the
    %result bound (an inverse call through `let`), unifying the structure
    %up front peels one constructor per recursion level and the inner
    %call's own nonvar seed carries the peeled value inward.  Without this
    %the recursion generates candidates blind and `(let (plus $A (S Z))
    %(S (S (S (S Z)))) $A)` is exponential where it was structural; the
    %boundary goal it preempts is pure unification for any non-marker
    %produced value, so forward calls are unchanged.
    ->  Body = (( nonvar(Out) -> RawOut = Out ; true ), Normalized)
    ;   Body = Normalized
    ).
%[tested:
%extensions/python/tests/ch10_errors_and_refusals/test_builtin_inputs.py::test_arithmetic_inverts_past_the_linear_case_or_refuses_with_the_reason,
%translator_equations:an_inverse_call_peels_a_constructor_result_structurally;
%commit=44ea37314b24f799a2080901172db66a94cb7791].

%A directly covered self call has already crossed its own equation boundary.
%Fuse both the caller-side protocol and this equation's outer protocol into
%the callee output.  The direct generated goal is emitted only after the head
%coverage proof, so no unmatched-call marker is lost.  Calls through a policy
%wrapper and calls to another function retain both boundaries; that also keeps
%mutually recursive cycles non-tail until the engine has SCC-wide fuel.
normalize_equation_tail((Call0,
                         metta_application_result(_, _, Produced, RawResult)),
                        RawOut, [Caller|_], Out, Call) :-
    RawResult == RawOut,
    direct_self_equation_goal(Call0, Caller, Produced, Out, Call),
    !.
normalize_equation_tail((A, B), RawOut, Runtime, Out, (A, Normalized)) :- !,
    normalize_equation_tail(B, RawOut, Runtime, Out, Normalized).
normalize_equation_tail((Condition -> Then ; Else), RawOut, Runtime, Out,
                        (Condition -> ThenNormalized ; ElseNormalized)) :- !,
    normalize_equation_tail(Then, RawOut, Runtime, Out, ThenNormalized),
    normalize_equation_tail(Else, RawOut, Runtime, Out, ElseNormalized).
normalize_equation_tail((Condition *-> Then ; Else), RawOut, Runtime, Out,
                        (Condition *-> ThenNormalized ; ElseNormalized)) :- !,
    normalize_equation_tail(Then, RawOut, Runtime, Out, ThenNormalized),
    normalize_equation_tail(Else, RawOut, Runtime, Out, ElseNormalized).
normalize_equation_tail((Left ; Right), RawOut, Runtime, Out,
                        (LeftNormalized ; RightNormalized)) :- !,
    normalize_equation_tail(Left, RawOut, Runtime, Out, LeftNormalized),
    normalize_equation_tail(Right, RawOut, Runtime, Out, RightNormalized).
normalize_equation_tail((Condition -> Then), RawOut, Runtime, Out,
                        (Condition -> ThenNormalized)) :- !,
    normalize_equation_tail(Then, RawOut, Runtime, Out, ThenNormalized).
normalize_equation_tail(Goal0, RawOut, Runtime, Out, Goal) :-
    normalized_equation_tail_goal(Goal0, RawOut, Runtime, Out, Goal), !.
normalize_equation_tail(Goal, RawOut, Runtime, Out,
                        (Goal, metta_application_result(Runtime, Runtime,
                                                        RawOut, Out))).

%Direct generated predicates and the default dispatch wrapper both already
%return an equation-normalized result.  Replacing only their identical final
%output variable is a compile-time worker-tail fusion; native predicates and
%all meta calls keep the explicit protocol above.
normalized_equation_tail_goal(Goal0, RawOut, [Caller|_], Out, Goal) :-
    nonvar(Goal0),
    Goal0 =.. [Predicate|Arguments0],
    append(Inputs, [Produced], Arguments0),
    Produced == RawOut,
    compiled_function_name(Fun, Predicate),
    Fun == Caller,
    length(Inputs, Arity),
    metta_equation_call(Fun, Arity),
    append(Inputs, [Out], Arguments),
    Goal =.. [Predicate|Arguments].
normalized_equation_tail_goal(
    dispatch_policy_execute(Module, Fun, Args, Goal0, Produced), RawOut,
    [Caller|_], Out,
    dispatch_policy_execute(Module, Fun, Args, Goal, Out)) :-
    Produced == RawOut,
    Fun == Caller,
    replace_goal_output(Goal0, RawOut, Out, Goal).

replace_goal_output(Goal0, RawOut, Out, Goal) :-
    nonvar(Goal0),
    Goal0 =.. [Predicate|Arguments0],
    append(Inputs, [Produced], Arguments0),
    Produced == RawOut,
    append(Inputs, [Out], Arguments),
    Goal =.. [Predicate|Arguments].

direct_self_equation_goal(Goal0, Caller, Produced, Out, Goal) :-
    nonvar(Goal0),
    Goal0 =.. [Predicate|Arguments0],
    append(Inputs, [GoalOut], Arguments0),
    GoalOut == Produced,
    compiled_function_name(Fun, Predicate),
    Fun == Caller,
    length(Inputs, Arity),
    metta_equation_call(Fun, Arity),
    append(Inputs, [Out], Arguments),
    Goal =.. [Predicate|Arguments].

%Head annotations are constraints regardless of whether the structural pattern
%also carries a sequence variable.  Keep their lowering and the pattern-note
%side effect on one path so both equation compilers see the same head
%[tested: tests/prolog/suites/reader/segment_equations.plt and
%tests/prolog/suites/translator/translator.plt:an_in_place_annotation_is_still_a_constraint;
%commit=c530ccb8fb7d0a5b2aa53df6e9f981ada9f81be8].
%THE ONE DOOR THAT INVERTS. Every other constrain_args/3 caller compiles a
%pattern that is not an equation head -- case keys, typed lets, case duals,
%the specializer's normalized head -- and a functional pattern there would
%turn a key into a call [source: PeTTa@ae66fa8 src/specializer.pl:54, which
%passes ConstrainArgs=false for the same reason this engine does].
%Per ARGUMENT, because the evaluation mask decides a whole argument and so
%decides every subterm inside it, which is the rule head_pattern_reason/7
%already applies to the notes.
translate_equation_head(F, Args0, true, Args1, GoalsPrefix) :-
    !,
    current_metta_module(Module),
    constrain_head_arguments(Args0, 1, Module, F, governing, Args1, GoalsA,
                             Positions),
    flatten(GoalsA, GoalsPrefix),
    (   Positions == []
    ->  true
    ;   record_head_pattern_notes(F, Positions)
    ).
translate_equation_head(_, Args, false, Args, []).

%Argument by argument, so each one is asked whether its own position carries
%the mask before its pattern is walked.
%The TIER is the caller's, because the two doors ask at different moments:
%bulk ingestion records notes before register_fun_in/2 and so reads the
%equation owner's local declarations, while the compiler asks the governing
%selector after ownership is registered. Both must reach the SAME verdict on
%whether a position inverts, or the note would describe a clause the compiler
%did not write
%[tested: translator_head_pattern_notes:bulk_and_single_ingestion_use_the_same_definition_local_mask].
constrain_head_arguments([], _, _, _, _, [], [], []).
constrain_head_arguments([A0|As0], Index, Module, F, Tier, [A|As], [G|Gs],
                         Positions) :-
    (   unevaluated_head_argument(Tier, Module, F, Index)
    ->  Invert = structural
    ;   Invert = invert
    ),
    constrain_args(A0, A, G, [Index], Positions, Rest, Invert),
    Next is Index + 1,
    constrain_head_arguments(As0, Next, Module, F, Tier, As, Gs, Rest).

%An equation head containing `(:seg $x)` cannot be represented by Prolog's
%fixed-arity head unification alone.  Compile its body exactly once, retain the
%variables shared with the parsed head, and put the one-sided hedge match in
%front of those goals.  Calls at the written arity take this ordinary compiled
%clause; calls at another arity use metta_segment_dispatch/4 over the retained
%source equations [tested: tests/prolog/suites/reader/segment_equations.plt;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
translate_segment_body_plan(F, BodyExpr, GoalsPrefix, BodyPlan) :-
    (   metta_seq_present(BodyExpr)
    ->  metta_seq_body_plan(BodyExpr, ParsedBody),
        goals_list_to_conj(GoalsPrefix, PrefixConj),
        BodyPlan = spliced(PrefixConj, ParsedBody)
    ;   translate_equation_body_result(F, BodyExpr, GoalsBody, ExpOut),
        append(GoalsPrefix, GoalsBody, Goals),
        goals_list_to_conj(Goals, GoalsConj),
        BodyPlan = compiled(GoalsConj, ExpOut)
    ).

%The common result-rule compiler, shared by ordinary and segment heads.  An
%Atom-returning function answers its body as data, except for the `function`
%frame whose purpose is to execute a plan until `return`.  Every other result
%keeps the existing continuation rule [source: LeaTTa
%MettaHyperonFull/Minimal/Interpreter.lean:348-368 and :3786-3799;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
translate_equation_body_result(F, BodyExpr, GoalsBody, ExpOut) :-
    (   declared_output_type(F, 'Atom'),
        \+ function_frame_body(BodyExpr)
    ->  GoalsBody = [],
        ExpOut = BodyExpr
    ;   translate_expr(BodyExpr, GoalsBody, ExpOut)
    ).

%NO RESULT CONTINUATION, which is upstream's whole rule: the two branches
%above are `( declared_output_type(F, 'Atom') -> GoalsBody = [], ExpOut =
%BodyExpr ; translate_expr(BodyExpr, GoalsBody, ExpOut) )` there and nothing
%more [source: PeTTa@ae66fa8 src/translator.pl:25-28]. A body that compiled to
%no goals used to take equation_result_continuation/4, which re-entered
%evaluation on the arbiter's `returnsAtom` rule
%[LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:3786-3799]. It became
%observable once a masked parameter could carry something unreduced, and it
%DIVERGED: `(: wu1 (-> Number Atom %Undefined%))` with
%`(= (wu1 $a $b) (42 $a $b))` answers `(42 6 (+ 4 2))` upstream and answered
%`(42 6 6)` here, which is upstream's examples/functiontypes.metta
%[measured 2026-08-30]. Upstream compiles that equation to the FACT
%`wu1(A, B, [42, A, B])`.
%
%The chain and unify-branch sites keep masked_result_goal/3, and that is not
%an inconsistency: chain SUBSTITUTES written syntax into its template here
%where upstream binds a value, so its result genuinely holds a redex that
%upstream never built. `(chain (+ 1 2) $x (quote $x))` is 3 on both engines
%with the walk and `(+ 1 2)` here without it [measured 2026-08-30;
%fixture=ai-tmp/petta-align/chain2.metta].

%THE APPLICATION PROTOCOL, PAID ONLY WHERE IT IS READ. Every compiled call to
%a MeTTa equation ends in metta_application_result/4, whose first clause tests
%`Produced == '$metta_not_reducible'` and whose second is `Out = Produced`. The second
%is the answer for every ordinary call, and reaching it cost the two CALL
%TERMS being built first: for `(fib (- $n 1))` that is `[fib, [-, A, 1]]` and
%[fib, J]`, seven heap cells handed to a predicate that reads neither.
%
%Moving the goal inside the branch that reads it makes SWI build those terms
%only there, and leaves the common case as one comparison and one
%unification. Measured in isolation over a million calls: 3,000,003
%inferences and 0.074s CPU against 2,000,003 and 0.033s, a third of the
%inferences and 2.24x the CPU
%[measured 2026-08-30; fixture=ai-tmp/petta-align/micro.pl].
%
%The relation is unchanged in every mode, which is what makes this a rewrite
%rather than a fast path: an unbound Produced fails this `==` exactly as it
%fails the first clause's, and reaches the same `Out = Produced`.
%
%LAST, after normalize_equation_tail/5 has run, because that pass FUSES the
%protocol away entirely for a proven direct self-tail call and matches the
%bare goal to do it. Deferring earlier would hide the shape it looks for and
%trade a removal for a deferral.
%Found comes back bound when the walk met a negation, so quantify_negations/2
%runs only on the clauses that have one. It rides THIS pass because this pass
%already walks the whole body: the previous carrier was the occurs-check
%demotion, which the petta alignment deleted (nothing emits an occurs check
%any more), and asking the question in a walk of its own measured +3,935
%inferences over 49 compiled functions. A separate test is not free; a
%threaded argument is [measured 2026-08-31; command=engine/bench.py].
defer_application_protocol(Goal0, Goal) :-
    defer_application_protocol(Goal0, Goal, _).

defer_application_protocol(Goal, Goal, _) :- var(Goal), !.
defer_application_protocol((A0, B0), (A, B), F) :- !,
    defer_application_protocol(A0, A, F),
    defer_application_protocol(B0, B, F).
defer_application_protocol((C0 -> T0 ; E0), (C -> T ; E), F) :- !,
    defer_application_protocol(C0, C, F),
    defer_application_protocol(T0, T, F),
    defer_application_protocol(E0, E, F).
defer_application_protocol((C0 *-> T0 ; E0), (C *-> T ; E), F) :- !,
    defer_application_protocol(C0, C, F),
    defer_application_protocol(T0, T, F),
    defer_application_protocol(E0, E, F).
defer_application_protocol((L0 ; R0), (L ; R), F) :- !,
    defer_application_protocol(L0, L, F),
    defer_application_protocol(R0, R, F).
defer_application_protocol((C0 -> T0), (C -> T), F) :- !,
    defer_application_protocol(C0, C, F),
    defer_application_protocol(T0, T, F).
defer_application_protocol((C0 *-> T0), (C *-> T), F) :- !,
    defer_application_protocol(C0, C, F),
    defer_application_protocol(T0, T, F).
defer_application_protocol(\+ G0, \+ G, F) :- !,
    defer_application_protocol(G0, G, F).
defer_application_protocol(once(G0), once(G), F) :- !,
    defer_application_protocol(G0, G, F).
defer_application_protocol(findall(T, G0, L), findall(T, G, L), F) :- !,
    defer_application_protocol(G0, G, F).
defer_application_protocol(metta_application_result(S, R, Produced, Out),
                           (   Produced == '$metta_not_reducible'
                           ->  metta_application_result(S, R, Produced, Out)
                           ;   Out = Produced
                           ), _) :- !.
defer_application_protocol(metta_application_result(W, Produced, Out),
                           (   Produced == '$metta_not_reducible'
                           ->  metta_application_result(W, Produced, Out)
                           ;   Out = Produced
                           ), _) :- !.
%A negation is the only goal this pass reports rather than rewrites. Its own
%functor gives it an index bucket, so the goals that are not negations pay
%nothing for the question.
defer_application_protocol(metta_negation(L, S, T, D, O),
                           metta_negation(L, S, T, D, O), F) :- !,
    ( var(F) -> F = found ; true ).
defer_application_protocol(Goal, Goal, _).

%Membership by IDENTITY, not unification: two distinct fresh variables unify
%but are not the same variable, and every caller here is asking which one it
%has.
variable_member(Variables, Variable) :-
    member(Candidate, Variables),
    Candidate == Variable,
    !.

%The eta-expansion above gives the clause MORE arguments than its equation's
%head has, so the arity the loader registered from the source shape names a
%predicate that will never exist. Left in place, a call at that arity compiled
%straight to it: `(= (pcap $k) (|-> ($a) (pair $a $k)))` registered pcap/2 from
%its head, compiled `pcap(A, B, C) :- lambda_2(A, B, C)`, and `(pcap 5)` then
%raised `Unknown procedure: pcap/2` where the same function written with a
%NON-capturing lambda curried cleanly. A capturing lambda not currying was the
%whole of F9c, and this is why.
%
%Dropping the superseded arity lets build_call_or_partial_dl/6 fall through to
%its partial branch, which is what partial/2 exists for: `(pcap 5)` answers
%`(partial pcap (5))` and `((pcap 5) 1)` reaches reduce/3's closure case and
%runs. The fully applied `(pcap 5 1)` is unaffected, because the compiled
%arity is still registered [tested: translator_capturing_lambda_curries].
%
%Only when nothing DEFINES that arity, because a function may genuinely be
%overloaded and another of its equations may have supplied it. That equation
%re-registers the arity when it compiles, whichever order the two arrive in.
%Called ONLY from the eta-expansion branch above, which is the only place the
%two arities can differ, so an ordinary equation pays nothing for this. Called
%unconditionally instead it cost five inferences on every compiled clause,
%+4,994 over source-load's thousand equations [measured 2026-08-16].
drop_superseded_arity(_, SourceArgs, HeadArgs) :-
    same_length(SourceArgs, HeadArgs),
    !.
drop_superseded_arity(F, SourceArgs, _) :-
    length(SourceArgs, SourceInputArity),
    SourceArity is SourceInputArity + 1,
    compiled_function_name(F, Predicate),
    functor(Probe, Predicate, SourceArity),
    (   catch(clause(Probe, _), _, fail)
    ->  true
    ;   retractall(arity(F, SourceArity))
    ).

%get-type owns the answer-stream boundary. User equations therefore compile
%behind that boundary instead of becoming sibling clauses that could bypass
%its deduplication. Every other function keeps its source name.
compiled_function_name('get-type', get_type_rule) :- !.
compiled_function_name(F, F).

%Record atoms compiled as plain symbol heads together with where they were compiled:
%a stored definition can be recompiled when the function arrives late, an already
%executed expression cannot, so late registration repairs the former and warns on the latter.
:- dynamic symbol_head/2.
%A BACKTRACKABLE GLOBAL, not a thread_local fact. This flag is set and cleared
%around EVERY runnable translation, and `eval` translates at run time, so a
%program that evaluates in a loop paid an assertz/2 and an erase/1 per
%iteration: on a 2,800-step `(chain (eval ...))` loop the flag alone was 6.9%
%of self time, and its setup_call_cleanup/3 machinery -- sig_atomic/1,
%assertz/2, erase/1 -- another 7.7% [measured 2026-08-30, SWI profile].
%A global variable costs neither clause allocation nor the logical update
%view, and engine/metta/control.pl's fuel scope already uses the same shape
%for the same reason. Per-THREAD, which is what thread_local gave it, because
%SWI's global variables are per-thread.
:- thread_initialization(nb_setval('$metta_translating_runnable', false)).

translating_runnable :- b_getval('$metta_translating_runnable', true).
%The names an importer form in the runnable being compiled registers, so the
%check after it runs knows whether the expression is worth walking at all.
:- thread_local runnable_import/1.
%A translated runnable is a TEMPLATE, not an answer. The source, goals and
%output are stored together so their variables keep the same sharing, while a
%dynamic-clause read gives every caller a fresh copy. This is the boundary
%Python's non-direct eval paths cross this boundary. Language-level eval/2 and source
%runners stay uncached because interpreter-style programs feed them many
%one-shot terms; equations also stay uncached, so compile-once paths retain
%their prior cost.
%
%The key is the specializer's operation: copy the term and number its
%variables. The source-template variant check is still required because a
%literal `$VAR(0)` collides with numbervars/4's representation of a source
%variable. Module is the other half because the same written call can resolve
%to a different predicate in each space. The measured ground-shape alternative
%was rejected: rebuilding a typed shape on every hit consumed most of the
%translation saving while the repeated eval workloads already repeat exact
%variants.
%
%The runnable dependency index contains every atom in the written form. Like
%record_translated_supports/2's translated-form supports, it deliberately
%over-approximates: evicting an unaffected translation is safe, retaining one
%that compiled against an old function is not. Both function change events use
%the same indexed first lookup.
:- dynamic translated_form_cache/6.
:- dynamic translated_form_mention/2.
:- dynamic translation_cache_hook_ref/2.

normalize_translation_key(Term, Normalized) :-
    copy_term(Term, Normalized),
    numbervars(Normalized, 0, _, [singletons(true)]).

%THE TEMPLATE ABSTRACTS ITS LITERAL LEAVES, so one translation serves every
%call of the same SHAPE. `(eval (- $x $y))` inside a loop hands this predicate
%`(- 350000 5)`, then `(- 349995 5)`, and so on: a copy_term/2 template keys on
%the constants, so every iteration missed and re-translated. The skeleton
%`(- A B)` keys once.
%
%SOUND, and measured rather than argued. Translating with an unbound operand
%produces the GENERAL code for that position -- a runtime type check where a
%literal would have discharged one at compile time -- so an instance of the
%skeleton computes the same answer, never a different one
%[measured 2026-08-30: `(- 350000 5)` translated ground answers 349995; the
%skeleton `(- A B)` translated once and then bound answers 349995 and, bound
%again, 349990; fixture=ai-tmp/petta-align/skel.pl].
%
%NUMBERS AND STRINGS ONLY, and never in head position. A symbol decides what
%the translation IS -- whether the head names a function, a special form or
%data -- so abstracting one would key two different programs to one entry. A
%number or a string can be neither, so nothing the translator asks about a
%head can be affected by replacing one.
%
%AND NEVER INSIDE A FORM THAT CAPTURES ITS OPERAND'S VARIABLES. `sealed`
%compiles to a copy_term/4 over `term_variables(Expr)` and `|->` computes its
%closure's free variables the same way, so a literal turned into a variable
%there JOINS the set they capture: `(sealed ($x) 5)` would seal a fresh
%variable in place of the 5 and answer it unbound
%[measured 2026-08-30: translator_sealed:sealing_a_ground_atom_returns_that_atom
%and examples/ch07-control-flow/07-03-let-and-sequencing/08-sealed.metta both
%fail without this]. The property is declared beside those forms in
%engine/translator/special_forms.pl so the two cannot drift.
%
%The dependency index is unchanged by this: it records every SYMBOL of the
%written form, and the skeleton keeps all of them, so
%invalidate_translated_forms/1 still evicts exactly what it did.
translation_template(Source, Template, Key) :-
    copy_term(Source, Copy),
    translation_skeleton(Copy, Template),
    normalize_translation_key(Template, Key).

%The head stays; the arguments are walked. A bare literal at the top is left
%alone because there is nothing to reuse in it.
translation_skeleton(Term, Skeleton) :-
    (   is_list(Term),
        Term = [Head|Arguments],
        \+ ( atom(Head), literal_sensitive_form(Head) )
    ->  maplist(translation_skeleton_argument, Arguments, Abstracted),
        Skeleton = [Head|Abstracted]
    ;   Skeleton = Term
    ).

%A form whose compilation reads more than the SHAPE of its arguments, so
%abstracting a literal out of it would compile something the call did not
%write.
%
%Two kinds, and they are declared differently because they ARE different. A
%variable-capturing form decides what it compiles from the variable set a
%subterm carries, and the two that do it are named beside the clauses that do
%it (engine/translator/special_forms.pl).
%
%A TRANSLATOR RULE is the other kind, and it is a registry rather than a list
%because a program adds to it. A rule is a MACRO: apply_translator_rule_dl/7
%calls the rule's own compiled predicate at compile time and takes its answer
%as the expansion, so an expansion COMPUTED from the arguments is computed
%from whatever the skeleton put there. Abstracting a literal hands the rule an
%unbound variable, and an expansion that reaches a grounded operation then
%runs it backwards: the gallery's
%`(= (MM (T (T $l)) $r) (gallery-gemm $l $r))`, lowered through
%add-translator-rule!, called NumPy on `(Matrix (Row $_0 $_1))` and failed
%with "a Python operation runs forwards only"
%[measured 2026-08-30;
% fixture=extensions/python/examples/gallery/symbolic_tensors.py].
literal_sensitive_form(Head) :- variable_capturing_form(Head), !.
literal_sensitive_form(Head) :- translator_rule(Head, _, _).

translation_skeleton_argument(Term, Skeleton) :-
    (   var(Term)
    ->  Skeleton = Term
    ;   ( number(Term) ; string(Term) )
    ->  Skeleton = _
    ;   is_list(Term)
    ->  translation_skeleton(Term, Skeleton)
    ;   Skeleton = Term
    ).

%A one-shot giant value is cheaper to translate than to copy, normalize and
%retain. The bound is a node budget rather than a byte estimate, so it stops
%after fixed work and does not walk a 100,000-element sort input merely to
%decide not to cache it [measured 2026-08-20: sort-atom cache experiment].
translation_cacheable(Term) :-
    acyclic_term(Term),
    cache_term_budget(Term, 256, _).

cache_term_budget(_, 0, _) :- !, fail.
cache_term_budget(Term, Budget0, Budget) :-
    Budget1 is Budget0 - 1,
    (   compound(Term)
    ->  functor(Term, _, Arity),
        cache_args_budget(1, Arity, Term, Budget1, Budget)
    ;   Budget = Budget1
    ).

cache_args_budget(Index, Arity, _, Budget, Budget) :- Index > Arity, !.
cache_args_budget(Index, Arity, Term, Budget0, Budget) :-
    arg(Index, Term, Argument),
    cache_term_budget(Argument, Budget0, Budget1),
    Next is Index + 1,
    cache_args_budget(Next, Arity, Term, Budget1, Budget).

%SUBSUMPTION, not variance. The stored form is a skeleton, so it must be
%GENERAL ENOUGH for the call rather than identical to it; unifying then binds
%its variables to this call's literals, which is the template instantiation
%the cache was always doing -- a dynamic clause is copied on retrieval, so the
%goals handed back are this call's own.
translated_form_hit(Module, Key, Source, Goals, Out) :-
    translated_form_cache(Module, Key, _, StoredSource, Goals, Out),
    subsumes_term(StoredSource, Source),
    StoredSource = Source,
    !.

cache_translated_form(Module, Key, Source, Goals, Out) :-
    install_translation_cache_hooks,
    gensym(translated_form_, Id),
    assertz(translated_form_cache(Module, Key, Id, Source, Goals, Out), Ref),
    record_source_assertion(Ref),
    findall(Symbol, (sub_term(Symbol, Source), atom(Symbol)), Symbols0),
    sort(Symbols0, Symbols),
    forall(member(Symbol, Symbols),
           ( assertz(translated_form_mention(Symbol, Id), MentionRef),
             record_source_assertion(MentionRef) )).

%The lifecycle sweep for one execution module, called when its space is
%cleared or its pooled name is recycled. The cached translations are the
%load-bearing part: a cached form's goals were COMPILED against this
%module's predicates, and the sweep is about to abolish them, so the next
%life of the name would run goals linked against a destroyed procedure and
%raise "Unknown procedure" from a path the undefined-predicate hook never
%sees. The queued type groups and the head-note memos are the same hygiene:
%both memo arrival-order facts about definitions that died with the space,
%and the next life must not inherit either.
clear_module_translation_state(Module) :-
    forall(retract(translated_form_cache(Module, _, Id, _, _, _)),
           retractall(translated_form_mention(_, Id))),
    retractall(deferred_equation_types(_, Module, _)),
    retractall(head_pattern_note(Module, _, _, _, _)).

install_translation_cache_hooks :- translation_cache_hook_ref(_, _), !.
install_translation_cache_hooks :-
    assertz((seam:function_changed(Symbol) :-
                invalidate_translated_forms(Symbol)), ChangedRef),
    assertz(translation_cache_hook_ref(changed, ChangedRef)),
    assertz((seam:function_removed(Symbol) :-
                invalidate_translated_forms(Symbol)), RemovedRef),
    assertz(translation_cache_hook_ref(removed, RemovedRef)).

translate_runnable_expr_cached(Module, Key, Source, Template, Goals, Out) :-
    (   translated_form_hit(Module, Key, Source, Goals, Out)
    ->  true
    ;   translate_runnable_expr(Template, TemplateGoals, TemplateOut),
        cache_translated_form(Module, Key, Template, TemplateGoals,
                              TemplateOut),
        Source = Template,
        Goals = TemplateGoals,
        Out = TemplateOut
    ).

invalidate_translated_forms(Symbol) :-
    (   translated_form_mention(Symbol, _)
    ->  with_mutex('$metta_translation_cache',
                   invalidate_translated_forms_locked(Symbol))
    ;   true
    ).

invalidate_translated_forms_locked(Symbol) :-
    findall(Id, retract(translated_form_mention(Symbol, Id)), Ids0),
    sort(Ids0, Ids),
    forall(member(Id, Ids),
           ( retractall(translated_form_cache(_, _, Id, _, _, _)),
             retractall(translated_form_mention(_, Id)) )),
    uninstall_idle_translation_cache_hooks.

uninstall_idle_translation_cache_hooks :-
    (   translated_form_cache(_, _, _, _, _, _)
    ->  true
    ;   forall(retract(translation_cache_hook_ref(_, Ref)), erase(Ref))
    ).

clear_translation_cache :-
    with_mutex('$metta_translation_cache',
               ( retractall(translated_form_cache(_, _, _, _, _, _)),
                 retractall(translated_form_mention(_, _)),
                 uninstall_idle_translation_cache_hooks )).
note_symbol_head(HV) :- atom(HV), !,
                        ( translating_runnable -> Ctx = runnable ; Ctx = clause ),
                        ( symbol_head(HV, Ctx) -> true
                        ; assertz(symbol_head(HV, Ctx), Ref),
                          record_source_assertion(Ref) ).
note_symbol_head(_).

%Translate an expression that executes immediately, marking its data uses as unrepairable.
%once/1 closes the translation before the goals run, so nested imports triggered by the
%execution compile their definitions under the clause context again:
%A runnable has no head, so a variable of its own is local to it the same way a
%clause variable that is not in the head is: only the answer it produces is
%read from outside.
%
%A runnable has no occurs-check pass to thread the flag through, so this one
%costs a call. It is a thread_local with no clauses in the ordinary case, which
%is the cheapest cross-cutting signal Prolog has: one inference, against two
%for flag/3 [measured 2026-08-15].
