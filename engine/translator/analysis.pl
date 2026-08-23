% Purpose: retain function metadata, translation caches, symbol analysis, and callable-head discovery
% Assumes: engine/translator.pl includes this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE]

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
:- dynamic fun_meta_clause/4.
:- dynamic fun_meta_clause_types/5.

record_fun_meta(F, Args, Body) :-
    current_metta_module(Module),
    asserta(fun_meta_clause(Module, F, Args, Body), Ref),
    record_source_assertion(Ref),
    fun_meta_types_for_new_clause(Module, F, Types),
    asserta(fun_meta_clause_types(Module, F, Args, Body, Types), TypeRef),
    record_source_assertion(TypeRef).

%Associate each equation with the arrow declarations that appeared since the
%previous equation for the same function. Source commonly writes an arrow and
%its equation as a pair; when no new arrow appeared, inherit the most recent
%group. The association is only consulted by OrderFittest, so ordinary clause
%dispatch remains the compiled Prolog path.
fun_meta_types_for_new_clause(Module, F, Types) :-
    findall(Chain,
            catch_recover(type_declaration_in(Module, F, Chain), fail),
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
% position, and both decisions it can take there are recorded because both are
% invisible in the source.
%
%   type_annotation    the position compiled to a GOAL rather than to
%                      structure: (= (f (: $x Number)) $x) compiles to
%                      f(A, A) :- has_type(A, 'Number'). The retained equation
%                      no longer holds the whole head, so anything reading
%                      equations back has to know, and engine/duals.pl refuses
%                      to build a dual for such a function rather than negate a
%                      head it cannot see.
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
%apply_translator_rule_dl/6 writes its declaration tests: `==/2` compiles to an
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
record_head_pattern_notes(F, Positions) :-
    current_metta_module(Module),
    forall(( member(head_position(RevPath, Label, Kind), Positions),
             head_pattern_reason(Module, F, RevPath, Label, Kind, Reason) ),
           note_head_pattern(Module, F, RevPath, Label, Reason)).

head_pattern_reason(_, _, _, _, type_annotation, type_annotation).
%THE LABEL QUESTION FIRST, and the order is what the two questions cost rather
%than taste. head_meaning_route/3 reads Prolog facts, metta_special_form/1,
%translator_rule/2 and fun/1, and fails at once for a label that means nothing,
%which is what most compound head arguments hold. unevaluated_head_argument/2
%reads a TYPE DECLARATION, and a name the prelude has not declared falls
%through to a match against &self, so asking it first paid a space query for
%every such label. Both goals are pure tests, so the order decides only what
%gets asked: 500 equations of the shape `(= (f (Cons $x $xs)) $x)` cost 62
%inferences each for their note with the type question first and 23 with the
%label question first, while the same file written with plain heads measures
%the same either way [measured 2026-08-21: 500 equations in a fresh space,
%minimum of three, 466,901 against 447,405 inferences over a 336,401-inference
%plain-head control].
head_pattern_reason(Module, F, RevPath, Label, label, defined_label(Route)) :-
    head_meaning_route(Module, Label, Route),
    last(RevPath, Argument),
    \+ unevaluated_head_argument(F, Argument).

%A parameter carrying the evaluation mask receives its argument AS WRITTEN, so
%a structural pattern at that position is exactly what the caller hands over
%and there is nothing to report. This is what keeps the note off the shipped
%control forms, whose whole design is `(: union (-> Atom Atom %Undefined%))`
%with `(= (union (superpose $a) (superpose $b)) ...)` under it; without it the
%engine's own prelude would emit six notes at boot, which is the shape of the
%723 false findings the linter produced by asking a narrower question
%[measured 2026-08-21]. The mask decides a whole argument, so it decides every
%subterm inside it, which is why the OUTERMOST index of the path is the one
%asked about.
unevaluated_head_argument(F, Argument) :-
    catch_recover(type_declaration(F, [->|Xs]), fail),
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
                      petta_head_pattern_note(F, Path, Label, Reason))
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
%tests/conformance/leatta_run.pl].
%
%The relational reading is not lost, it is written where it runs: a `let` in
%the body says the same thing and answers the same answers
%[tested: examples/functions/functionhead.metta,
%examples/functions/functionhead2.metta,
%examples/functions/functionhead3.metta].
%% constrain_args(+Pattern, -Constrained, -Goals) is det.
%The three-argument form for every caller that only wants the pattern: case
%keys, typed lets and case duals all compile a pattern and none of them is an
%equation head, so the positions the walk reports go nowhere and no question is
%ever asked about them.
constrain_args(In, Out, Goals) :- constrain_args(In, Out, Goals, [], _, _).

%% constrain_args(+Pattern, -Constrained, -Goals, +ReversedPath, -Positions, ?PositionsTail) is det.
%Positions is a DIFFERENCE LIST, ending in the tail the caller supplies, for
%the reason translate_expr_dl/4's goals are: a walk that appended what its
%children reported charged every compiled equation for the append, whether or
%not anything was reported.
constrain_args(X, X, [], _, Positions, Positions) :- (var(X); atomic(X)), !.
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
constrain_args([Quote, Expr], [Quote, Expr], [], _, Positions, Positions) :-
    nonvar(Quote), Quote == quote, !.
%An IN-PLACE TYPE ANNOTATION in a head parameter position: `(: $x T)` matches
%anything whose type includes T and binds $x to it, and `(: $x $t)` binds $t to
%each applicable type, one branch each. hyperon-experimental issue #177's
%dynamic half, the point being to put a type where it can PRUNE rather than
%only in a top-level declaration.
%
%It desugars to a plain variable plus a type premise, and the premise is not a
%new relation: it is the SAME acceptance the engine already compiles for a
%typed argument position, `(has_type(V,T) *-> true ; get-metatype(V,T))`. So
%`(: $x T)` means exactly what a declared parameter of type T means, and anyone
%who knows one knows the other.
%
%That shape is also what makes the two fixtures work for the same reason. A
%declared type wins where there is one, `(: $x Person)` accepting Ann and
%refusing Rex; and a METATYPE restriction works because has_type/2 fails on a
%symbol with no declaration, so `(: $c Symbol)` falls through to get-metatype/2
%and accepts any symbol. Symbol, Variable, Grounded and Expression are subtypes
%of Atom, so that fallback is what makes the annotation reach all four atom
%kinds and not only declared types. Nondeterminism is native and free: with the
%type a VARIABLE, has_type/2 enumerates, so `(: $x $t)` gives one branch per
%declared type and the shared form `(: $x $t) (: $y $t)` constrains the two
%parameters to agree.
%
%`:` AND NOT A NEW SPELLING, which is the whole difficulty and was got wrong
%here twice before it was got right. Issue #177 raises the collision and
%proposes `::` "when position cannot distinguish the two uses"; this tree tried
%`::` and then `:>`, and both are worse than the collision they avoid. `::` is
%what metta-lang.dev's tutorials use as an ordinary cons constructor, in
%`(= (length (:: $x $xs)) (+ 1 (length $xs)))` and 63 places after it, so it
%silently reinterpreted anyone's list code into a non-terminating recursion.
%`:>` collides with nothing and reads as a SUBTYPE bound to anyone who has met
%Scala's `<:` and `>:`, which is a different lie.
%
%Position CAN distinguish the two uses, and LeaTTa proved it by implementing
%exactly this against a mechanised Hyperon semantics. Two gates:
%
%  1. a pattern that IS a colon expression stays structural, so
%     `(match &self (: $x Human) $x)` still retrieves stored declarations;
%  2. below that, only `(: $variable expected)` is an annotation, and a colon
%     whose value slot is not a variable is data the walk does not look inside.
%
%[source: LeaTTa/ai-report-inplace-annotations.md, Design]. That is enough for
%this corpus. examples/reasoning/nilbc.metta is a backward-chaining proof
%search whose subject matter IS `(: proof theorem)` terms, 134 of them, and
%gate 2 covers every one whose value slot is an expression while gate 1 covers
%its knowledge-base queries. It needed ONE clause changed, a base case that
%destructures its query in the body instead of the head
%[tested: translator_inplace_annotations, a_cons_list_is_ordinary_structure,
%examples/reasoning/nilbc.metta].
constrain_args([Colon, Var, Type], Var,
               [(has_type(Var, Type) *-> true ; 'get-metatype'(Var, Type))],
               Path, [head_position(Path, ':', type_annotation)|Positions],
               Positions) :-
    nonvar(Colon), Colon == ':', var(Var), !.
%GATE TWO: a colon form whose VALUE slot is not a variable is ordinary data,
%and the walk does not descend into it either. Both halves are load-bearing.
%LeaTTa needed the second for single_sided.metta's binary-tree constructor
%`(: (Sym (: (Sym (: $x $a)) $b)) $c)`, whose inner colons are structure inside
%a value slot: a recognizer that kept descending changed the constructor
%[source: LeaTTa/ai-report-inplace-annotations.md, Design]. It earns its keep
%here too: nilbc.metta's `(bc $kb (S $d) (: ($rule $premise) $theorem))` has an
%expression in the value slot and stays the proof term it is.
constrain_args([Colon, Value, Type], [Colon, Value, Type], [], _,
               Positions, Positions) :-
    nonvar(Colon), Colon == ':', nonvar(Value), !.
constrain_args([F, A, B], Out, Goals, Path, Positions, Rest) :-
    nonvar(F),
    F == cons,
    constrain_args(A, A1, G1, [1|Path], Positions, AfterA),
    constrain_args(B, B1, G2, [2|Path], AfterA, Rest),
    Out = [A1|B1],
    append(G1, G2, Goals), !.
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
constrain_args(In, Out, Goals, Path, Positions, Rest) :-
    (   In = [Label|_], atom(Label)
    ->  Positions = [head_position(Path, Label, label)|ChildPositions]
    ;   Positions = ChildPositions
    ),
    constrain_children(In, 0, Path, Out, NestedGoalsList, ChildPositions, Rest),
    flatten(NestedGoalsList, Goals), !.

%A sub-pattern's children, numbered from one so a note can say WHICH child of
%which argument it is about. maplist/4 cannot count.
constrain_children([], _, _, [], [], Positions, Positions).
constrain_children([C|Cs], I, Path, [O|Os], [G|Gs], Positions, Rest) :-
    constrain_args(C, O, G, [I|Path], Positions, AfterC),
    J is I + 1,
    constrain_children(Cs, J, Path, Os, Gs, AfterC, Rest).

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
%lib/lib_tabling.metta writes both].
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
%existence_error(procedure, '$petta_exec:&self':metta_dual_goal/2) instead
%[measured 2026-08-22, on examples/reasoning/constructive_negation.metta].
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
%existence_error(procedure, '$petta_exec:&self':<name>) on the corpus.
seam:engine_emitted(agg_reduce/4).
seam:engine_emitted(hyperpose_branch/4).
seam:engine_emitted(hyperpose_runtime/2).
seam:engine_emitted(metta_condition_holds/2).
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
%existence_error(procedure, '$petta_exec:&pyspace_1':metta_top/3) the moment
%engine/spaces.pl became a module. What found the third one before anything ran
%it is the source half added beside that check, which reads what this file
%CONSTRUCTS rather than what a corpus happens to reach
%[measured 2026-08-22; tested: static_checks:every_emitted_goal_is_reachable].
seam:engine_emitted(metta_top/3).
seam:engine_emitted(metta_top_match/5).
seam:engine_emitted(petta_merged_match/3).
%engine/specializer.pl's, written into a specialized call's body when
%(pragma! verify-specializations true) is set.
seam:engine_emitted(petta_verified_specialization/2).
seam:engine_emitted(metta_require_current_capability/2).
seam:engine_emitted(metta_require_safe_goal/1).
seam:engine_emitted(metta_require_space_update_capability/2).
seam:engine_emitted(petta_match_atoms/2).
seam:engine_emitted(petta_answer_terms/3).
seam:engine_emitted(petta_prune_empty/2).
seam:engine_emitted(petta_prune_empty_answers/2).
seam:engine_emitted(petta_run_named/3).
seam:engine_emitted(petta_run_with_fuel/3).
seam:engine_emitted(petta_transaction/1).
seam:engine_emitted(petta_with_seed/4).
seam:engine_emitted(switch_runtime/3).
seam:engine_emitted(petta_evaluation_fuel/1).
seam:engine_emitted(petta_fuel_exhausted/1).
seam:engine_emitted(function_overapplication/3).
seam:engine_emitted(metta_bad_argument_error/3).
seam:engine_emitted(dispatch_mismatch_result/3).
seam:engine_emitted(dispatch_no_match_result/3).
seam:engine_emitted(dispatch_policy_execute/5).

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
translate_clause(Input, (Head :- BodyConj)) :- translate_clause(Input, (Head :- BodyConj), true).

%% translate_clause(+Equation, -Clause, +ConstrainArgs:boolean) is semidet.
translate_clause(Input, (Head :- BodyConj), ConstrainArgs) :-
                                               Input = [=, [F|Args0], BodyExpr],
                                               ( ConstrainArgs -> constrain_children(Args0, 1, [], Args1, GoalsA, Positions, []),
                                                                  flatten(GoalsA,GoalsPrefix),
                                                                  ( Positions == []
                                                                    -> true
                                                                     ; record_head_pattern_notes(F, Positions) )
                                                                ; Args1 = Args0, GoalsPrefix = [] ),
                                               record_fun_meta(F, Args1, BodyExpr),
                                               ( declared_output_type(F, 'Atom')
                                                 -> GoalsBody = [],
                                                    ExpOut = BodyExpr
                                                  ; translate_expr(BodyExpr, GoalsBody, ExpOut) ),
                                               (  nonvar(ExpOut) , ExpOut = partial(Base,Bound)
                                               -> length(Bound, N),
                                                  MinimumArity is N + 1,
                                                  setof(A, (arity(Base, A), A > MinimumArity), [Arity|_]),
                                                  M is (Arity - N) - 1,
                                                  length(ExtraArgs, M), append(Bound, ExtraArgs, CallInArgs),
                                                  resolve_dispatch(Base, CallInArgs, Out, Goal),
                                                  dispatch_call_goal(Base, CallInArgs, Out, Goal, PolicyGoal),
                                                  append(GoalsBody,[PolicyGoal],FinalGoals), append(Args1,ExtraArgs,HeadArgs),
                                                  drop_superseded_arity(F, Args1, HeadArgs)
                                               ; FinalGoals= GoalsBody , HeadArgs = Args1, Out = ExpOut ),
                                               append(HeadArgs, [Out], FinalArgs),
                                               compiled_function_name(F, Predicate),
                                               Head =.. [Predicate|FinalArgs],
                                               length(FinalArgs, CompiledArity),
                                               register_arity(F, CompiledArity),
                                               append(GoalsPrefix, FinalGoals, Goals),
                                               goals_list_to_conj(Goals, BodyConj0),
                                               merge_branch_returns(Head, BodyConj0, BodyConj1),
                                               demote_safe_occurs_checks(Head, BodyConj1, BodyConj, HasNegation),
                                               ( HasNegation == found
                                                 -> quantify_negations(Head, BodyConj)
                                                  ; true ).

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
:- thread_local translating_runnable/0.
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

translation_template(Source, Template, Key) :-
    copy_term(Source, Template),
    normalize_translation_key(Template, Key).

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

translated_form_hit(Module, Key, Source, Goals, Out) :-
    translated_form_cache(Module, Key, _, StoredSource, Goals, Out),
    Source =@= StoredSource,
    Source = StoredSource,
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
    ->  with_mutex('$petta_translation_cache',
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
    with_mutex('$petta_translation_cache',
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
