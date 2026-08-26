% Purpose: plan and execute indexed native-space matches and relational conjunction joins
% Assumes: engine/spaces.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/spaces.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/spaces.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%Native conjunctions call their space predicate directly. The recursive helper
%keeps the provider decision outside the candidate loop.
%A conjunction is a JOIN, and the engine ran it as a nested loop in SOURCE
%order: each conjunct enumerated under every binding of the ones before it.
%That is quadratic where the join's own bound is not. Measured on the triangle
%query over a graph with a hub joined to everything in both directions, where
%no triangle exists at all, instructions differenced against the same file
%whose query is one unconstrained conjunct: 13,502,606 at 100 edges rising by
%exactly 4.0x per doubling to 3,620,340,557 at 1,600, while the AGM bound for a
%triangle over N edges is N^1.5, about 64,000 there
%[measured 2026-08-23, ai-tmp/synth/join/].
%
%Enumerating the conjunct with the FEWEST matches first removes it. Binding
%`$x,$y` from the first conjunct gives N choices and `$z` from the second gives
%deg(`$y`) more, which for the hub is another N/2, and only then does the third
%conjunct fail; taking the most constrained conjunct instead binds `$z` from
%the one that offers a single value and refutes the row at once. This is the
%minimum-remaining-values heuristic of constraint solving and the reason
%leapfrog triejoin seeks in its smallest relation
%[source: Veldhuizen, Leapfrog Triejoin, ICDT 2014, arXiv:1210.0481].
%
%It is NOT worst-case optimal, and the difference is worth stating: no ordering
%of a nested loop attains the AGM bound on the instance that bound is tight
%for, which is why a worst-case-optimal join intersects a variable's candidate
%sets across every conjunct that mentions it rather than generating from one
%and testing in the rest. That needs sorted access per variable, which the
%whole-conjunction seam foreign_plan/5 exists to delegate. This removes the
%SKEW, which is where the measured quadratic came from.
%
%MULTIPLICITY is preserved exactly because the atom combinations are the same
%ones, merely visited in another order: `(, (edge $x $y) (edge $x $y))` over a
%space holding `(edge a b)` twice answers four rows here as it did before.
%Answer ORDER is not preserved, and is not specified.
match_native(_, _, LComma, OutPattern, Result) :- LComma == [','], !,
                                                  Result = OutPattern.
match_native(Module, Space, [Comma|Conjuncts], OutPattern, Result) :-
    Comma == ',',
    Conjuncts = [_, _|_],
    relational_conjuncts(Conjuncts),
    !,
    match_relational_conjuncts(Module, Space, Conjuncts, OutPattern, Result).
match_native(Module, Space, [Comma|[Head|Tail]], OutPattern, Result) :- Comma == ',',
                                                                        var(Head), !,
                                                                        get_native_atom(Module, Space, Head),
                                                                        acyclic_term(OutPattern),
                                                                        match_native(Module, Space, [','|Tail], OutPattern, Result).
match_native(Module, Space, [Comma|[Head|Tail]], OutPattern, Result) :- Comma == ',',
                                                                        ( Head == [] ; \+ is_list(Head) ), !,
                                                                        get_native_scalar_atom_in(Module, Head),
                                                                        acyclic_term(OutPattern),
                                                                        match_native(Module, Space, [','|Tail], OutPattern, Result).
match_native(Module, Space, [Comma|[[Rel|PatArgs]|Tail]], OutPattern, Result) :- Comma == ',', !,
                                                                                native_expression(Module, Space, Rel, PatArgs),
                                                                                acyclic_term(OutPattern),
                                                                                match_native(Module, Space, [','|Tail], OutPattern, Result).

%When the native pattern itself is a variable, enumerate all atoms.
match_native(Module, Space, PatternVar, OutPattern, Result) :- var(PatternVar), !,
                                                               get_native_atom(Module, Space, PatternVar),
                                                               acyclic_term(OutPattern),
                                                               Result = OutPattern.

match_native(Module, _, Pattern, OutPattern, Result) :-
    ( Pattern == [] ; \+ is_list(Pattern) ), !,
    get_native_scalar_atom_in(Module, Pattern),
    acyclic_term(OutPattern),
    Result = OutPattern.

match_native(Module, Space, [Rel|PatArgs], OutPattern, Result) :- native_expression(Module, Space, Rel, PatArgs),
                                                                  acyclic_term(OutPattern),
                                                                  Result = OutPattern.

%Every conjunct list reached below is a SUBLIST of one relational_conjuncts/1
%has already accepted, and being relational is a property of each conjunct on
%its own, so asking again at every level walked the remaining conjuncts once
%per conjunct.
match_relational_conjuncts(Module, Space, Conjuncts, OutPattern, Result) :-
    cheapest_conjunct(Module, Space, Conjuncts, Goal, Rest),
    call(Goal),
    acyclic_term(OutPattern),
    (   Rest = [_, _|_]
    ->  match_relational_conjuncts(Module, Space, Rest, OutPattern, Result)
    ;   match_native(Module, Space, [','|Rest], OutPattern, Result)
    ).

%Read one stored expression through its private module. The module's unknown
%flag is fail, so a virgin arity fails directly and this indexed path needs no
%exception handler.
%The storage call unifies raw, so first-argument indexing dispatches, and
%the occurs check runs once on the answer instead: a cyclic binding fails
%THIS candidate and enumeration continues. Without it, a repeated-variable
%pattern like (f $y $y) against a stored (f (g $x) $x) "matched" whenever
%the out template did not mention $y, while the same pattern failed when it
%did, one match with two answers. The arbiter's matcher occurs-checks its
%variable cases (LeaTTa MettaHyperonFull/Core/Matching.lean matchAtomsWith),
%so a rational-tree instantiation is never a MeTTa answer.
%Every remaining conjunct is an expression whose head is settled, which is the
%shape the reordering understands. Anything else keeps source order.
relational_conjuncts([]).
relational_conjuncts([Conjunct|Conjuncts]) :-
    nonvar(Conjunct),
    Conjunct = [Rel|_],
    nonvar(Rel),
    relational_conjuncts(Conjuncts).

%The remaining conjunct with the fewest matches under the current bindings,
%found by a DOUBLING probe that stops as soon as one conjunct is exhausted:
%counting them all would cost as much as the join. A conjunct exhausted inside
%the current limit is known to be no larger than it, so the first one that
%exhausts wins and the probe costs O(smallest) rather than O(relation). Past
%the last limit every remaining conjunct offers more matches than the probe can
%distinguish, and source order is as good a choice as any.
%The first conjunct that offers AT MOST ONE match, which is the whole of the
%win: a conjunct with one match settles its variables and refutes the row at
%once, where the loop would otherwise enumerate another conjunct's many.
%Distinguishing two matches from three is not worth a probe that every step of
%every join pays, so the question asked is the cheap one, and the leading
%conjunct's goal is built once and kept for the fallback that uses it.
cheapest_conjunct(Module, Space, [First|More], Goal, Rest) :-
    conjunct_goal(Module, Space, First, FirstGoal),
    (   goal_matches_at_most_one(FirstGoal)
    ->  Goal = FirstGoal,
        Rest = More
    ;   selective_conjunct(Module, Space, More, Found, Others)
    ->  Goal = Found,
        Rest = [First|Others]
    ;   Goal = FirstGoal,
        Rest = More
    ).

selective_conjunct(Module, Space, Conjuncts, Goal, Rest) :-
    select(Best, Conjuncts, Rest),
    conjunct_goal(Module, Space, Best, Goal),
    goal_matches_at_most_one(Goal),
    !.

%The callable form of one conjunct, built ONCE and used by both the probe and
%the enumeration that follows it. native_expression/4 rebuilds it with =../2 on
%every call, and the probe would otherwise pay for that a second and a third
%time on the hottest path a join has.
conjunct_goal(Module, [Family|Parameters], [Rel|PatArgs], Module:Goal) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Goal =.. ['$petta_parametric_atom', Rel|PatArgs].
conjunct_goal(Module, Space, [Rel|PatArgs], Module:Goal) :-
    Goal =.. [Space, Rel|PatArgs].

%Has this goal AT MOST ONE solution, asked by both join paths: the native one
%passes the storage call conjunct_goal/4 built, the routed one passes match/4
%so the read reaches through the whole chain.
%
%Counted in a mutable cell under a single negation. nb_setarg/3 is not undone by
%the failure that drives the enumeration, so the count survives while every
%binding the probe made is discarded, which is the accumulator
%has_type_derive/3 uses for the same reason; and `\+` alone suffices, since it
%keeps no bindings of its own. It costs neither the solution list findnsols/4
%builds nor a copy_term/2, which together measured +11.4% on a dense join where
%this measures +2.35%. deterministic/1 is not a cheaper substitute: inside a
%negation it always reports a choicepoint, so no conjunct is ever chosen and
%both the skewed and the dense case get slower than doing nothing.
goal_matches_at_most_one(Goal) :-
    State = seen(0),
    \+ (   call(Goal),
           arg(1, State, Before),
           After is Before + 1,
           nb_setarg(1, State, After),
           After >= 2
       ).

native_expression(Module, [Family|Parameters], Rel, PatArgs) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Term =.. ['$petta_parametric_atom', Rel|PatArgs],
    call(Module:Term),
    acyclic_term(PatArgs).
native_expression(Module, Space, Rel, PatArgs) :-
    Term =.. [Space, Rel | PatArgs],
    call(Module:Term),
    acyclic_term(PatArgs).

'get-atoms'(Space, Pattern) :- nonvar(Space),
                               seam:foreign_space(Space), !,
                               refuse_absent_capability(Space, enumerate),
                               petta_source_guard(Space),
                               seam:foreign_atoms(Space, Pattern).

%Get all atoms in space, irregard of arity. A first argument that is not a
%space is refused HERE and not in get_native_atom/2 below, for the same reason
%metta_add_atom/3 leaves the check to 'add-atom'/3: this is the door a MeTTa
%program comes through and the one that owes it a MeTTa answer, while the
%storage read below is an engine internal whose callers hold a space name
%already and would read an error atom as a stored atom
%[tested: test_get_atoms_on_an_unbound_space_names_the_operation].
%The storage lookup decides it here too, for match/4's reason: a read of a
%space the engine holds pays nothing, and only an unknown name reaches
%petta_space_name/1. get_native_atom/3 rather than /2 because the lookup /2
%would repeat has already happened in the condition.
'get-atoms'([Family|Parameters], Pattern) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    (   native_storage_module_ready(Space, Module)
    ->  get_native_atom(Module, Space, Pattern)
    ;   fail
    ).
'get-atoms'(Space, Pattern) :-
    (   atom(Space)
    ->  (   native_storage_module_ready(Space, Module)
        ->  (   space_parent(Space, _)
            ->  get_inherited_atom(Space, Module, Pattern)
            ;   get_native_atom(Module, Space, Pattern)
            )
        ;   petta_space_name(Space)
        ->  fail
        ;   space_argument_error('get-atoms', [Space], Pattern)
        )
    ;   space_argument_error('get-atoms', [Space], Pattern)
    ).

get_inherited_atom(Space, OwnModule, Pattern) :-
    space_read_chain(Space, Each),
    (   Each == Space
    ->  get_native_atom(OwnModule, Space, Pattern)
    ;   get_atom_read_link(Each, Pattern)
    ).

get_atom_read_link(Space, Pattern) :-
    seam:foreign_space(Space),
    !,
    refuse_absent_capability(Space, enumerate),
    petta_source_guard(Space),
    seam:foreign_atoms(Space, Pattern).
get_atom_read_link(Space, Pattern) :-
    native_storage_module_ready(Space, Module),
    get_native_atom(Module, Space, Pattern).

%Drop every atom a space holds. Expressions and scalars live in different
%predicates, so a caller that wipes only the space predicate would leave the
%scalars standing and a pooled name's next life would inherit them.
%Clearing a foreign space is the provider's own operation, and it lived in
%bindings/python/metta/shim.pl, so a Prolog provider that implemented clear (as
%lib/lib_redis.pl does) was reachable only when Python was in the process:
%under run.sh the engine had no path to it at all. The shim now calls this.
clear_foreign_atoms(Space) :-
    foreign_write(Space, clear, seam:foreign_clear(Space)).

%A space has two halves and this used to empty one of them. The storage sweep
%below drops every stored atom, and the atoms that also COMPILED left their
%clauses standing in the space's execution module, so a space holding nothing
%still answered its own functions: define (= (past-life) inherited), clear,
%and `!(past-life)` in that space still answered `inherited` over an empty
%space [measured 2026-08-19, ai-tmp/spaces-p1/probe_p116h.pl]. Space names
%are POOLED, so that is a previous life answering through a recycled name.
%
%It was masked rather than absent: bindings/python/metta/shim.pl's clear removes
%equations through the removal funnel before calling this, so the Python door
%was whole and the ENGINE's own door was not. Every other caller got the half
%clear, and P1.14's reload will come through this one.
%
%So the compiled half leaves first, through metta_remove_atom/3, which is the
%code that owns each shape: an equation un-compiles its clause and forgets the
%function name when nothing else defines it, a declaration recompiles the call
%sites it was shaping. Only those two shapes, because only those two have a
%compiled half, which is exactly the two clauses metta_remove_atom/3 answers
%specially; a plain atom is storage and nothing else, so the sweep is both
%correct and one retractall per arity rather than one removal per atom.
%
%The funnel is idempotent, so the shim's own pass in front of this one leaves
%nothing here to find and no removal is announced twice
%[tested: spaces_execution_modules:clearing_a_space_empties_its_execution_module,
%test_a_recycled_space_name_inherits_no_clauses_from_its_past_life].
%Only a pool whose synthesized admission guard and capacity row coexist gets
%a counter. Its dynamic fact participates in an enclosing transaction exactly
%like the stored atom clauses do, so a rollback restores both. The regular
%write door never probes it: successful claimed writes update it from the hook
%path, while an indexed removal clause exists only for counted spaces. Removing
%the capacity row drops both facts; adding the row back recounts once before
%the next decision. An equation can be a derived duplicate that stores nothing,
%so that rare shape recounts after the write instead of assuming one landed
%[tested: capacity_counter_changes_roll_back_with_the_atoms,
%capacity_redeclaration_recounts_writes_made_while_unbounded;
%commit=819b139c7cdbdaa673f854713e8beb988eb12ead].
:- dynamic petta_capacity_count/2.
:- dynamic petta_capacity_remove_hook/2.

petta_capacity_contract_added(Pool) :-
    (   petta_capacity_admission_claim(Pool)
    ->  petta_capacity_count_install(Pool)
    ;   true
    ).

petta_capacity_admission_claim(Pool) :-
    atom_concat('space-admission-guard-', Pool, Guard),
    petta_hook_claim(Pool, pre_add, Guard, _).

petta_capacity_count_claim(Pool) :-
    (   '$petta_atoms:&petta':'&petta'(capacity, Pool, _)
    ->  petta_capacity_count_install(Pool)
    ;   true
    ).

petta_capacity_count_install(Space) :-
    (   seam:foreign_space(Space)
    ->  true
    ;   with_mutex('$petta_capacity_count',
                   transaction(( (   petta_capacity_count(Space, _)
                                 ->  true
                                 ;   space_atom_count_uncached(Space, Count),
                                     assertz(petta_capacity_count(Space, Count))
                                 ),
                                 petta_capacity_remove_hook_install(Space) )))
    ).

petta_capacity_count_uninstall(Space) :-
    with_mutex('$petta_capacity_count',
               transaction(( retractall(petta_capacity_count(Space, _)),
                             forall(retract(petta_capacity_remove_hook(Space,
                                                                       Ref)),
                                    catch(erase(Ref), _, true)) ))).

%A claim-time clause specializes remove_sexp/3 on the ground pool name.
%First-argument indexing skips it for every unclaimed space, so ordinary
%removals retain their old inference count instead of paying a failed counter
%probe [measured: register-op 44334 inferences on 2026-08-21, min of 3;
%command=cd python && python bench.py --counter-only --keep-going;
%fixture=bindings/python/benchmarks/test_benchmarks.py::test_register_operation;
%commit=819b139c7cdbdaa673f854713e8beb988eb12ead]. The clause and its reference are dynamic database state,
%hence an enclosing transaction rolls their installation back with the claim.
petta_capacity_remove_hook_install(Space) :-
    (   petta_capacity_remove_hook(Space, _)
    ->  true
    ;   asserta((remove_sexp(Space, Term, Removed) :-
                    !,
                    petta_capacity_remove_sexp(Space, Term, Removed)), Ref),
        assertz(petta_capacity_remove_hook(Space, Ref))
    ).

petta_capacity_remove_sexp('&petta', [Rel|Args], Removed) :- !,
    (   native_storage_module_ready('&petta', Module)
    ->  Term =.. ['&petta', Rel|Args],
        native_retract_one(Module:Term, Removed),
        (   Removed == true
        ->  petta_catalog_note_removed([Rel|Args])
        ;   true
        )
    ;   Removed = false
    ),
    petta_capacity_count_removed_known('&petta', Removed).
petta_capacity_remove_sexp(Space, [Rel|Args], Removed) :- !,
    (   native_storage_module_ready(Space, Module)
    ->  native_storage_functor(Space, Functor),
        Term =.. [Functor, Rel|Args],
        native_retract_one(Module:Term, Removed)
    ;   Removed = false
    ),
    petta_capacity_count_removed_known(Space, Removed).
petta_capacity_remove_sexp(Space, Atom, Removed) :-
    (   native_storage_module_ready(Space, Module)
    ->  native_retract_one(Module:'$petta_native_scalar'(Atom), Removed)
    ;   Removed = false
    ),
    petta_capacity_count_removed_known(Space, Removed).

petta_capacity_counts_prune :-
    findall(Pool, petta_capacity_count(Pool, _), Pools0),
    sort(Pools0, Pools),
    forall(member(Pool, Pools),
           (   '$petta_atoms:&petta':'&petta'(capacity, Pool, _)
           ->  true
           ;   petta_capacity_count_uninstall(Pool)
           )).

petta_capacity_count_added(Space, [=, [F|_], _]) :-
    atom(F),
    !,
    petta_capacity_count_recount(Space).
petta_capacity_count_added(Space, _) :-
    petta_capacity_count_delta(Space, 1).

petta_capacity_count_added_known(Space, [=, [F|_], _]) :-
    atom(F),
    !,
    petta_capacity_count_recount(Space).
petta_capacity_count_added_known(Space, _) :-
    petta_capacity_count_delta_known(Space, 1).

petta_capacity_count_removed_known(_, false) :- !.
petta_capacity_count_removed_known(Space, true) :-
    petta_capacity_count_delta_known(Space, -1).

petta_capacity_count_delta(Space, Delta) :-
    (   petta_capacity_count(Space, _)
    ->  petta_capacity_count_delta_known(Space, Delta)
    ;   true
    ).

petta_capacity_count_delta_known(Space, Delta) :-
    with_mutex('$petta_capacity_count',
               transaction(( (   retract(petta_capacity_count(Space, Count0))
                             ->  Count1 is Count0 + Delta,
                                 (   Count1 >= 0
                                 ->  Count = Count1
                                 ;   space_atom_count_uncached(Space, Count)
                                 ),
                                 assertz(petta_capacity_count(Space, Count))
                             ;   true
                             ) ))).

petta_capacity_count_recount(Space) :-
    (   petta_capacity_count(Space, _)
    ->  with_mutex('$petta_capacity_count',
                   ( space_atom_count_uncached(Space, Count),
                     transaction(( retractall(petta_capacity_count(Space, _)),
                                   assertz(petta_capacity_count(Space, Count)) )) ))
    ;   true
    ).

petta_capacity_count_cleared('&petta') :-
    !,
    with_mutex('$petta_capacity_count',
               transaction(( retractall(petta_capacity_count(_, _)),
                             forall(retract(petta_capacity_remove_hook(_, Ref)),
                                    catch(erase(Ref), _, true)) ))).
petta_capacity_count_cleared(Space) :-
    (   petta_capacity_count(Space, _)
    ->  with_mutex('$petta_capacity_count',
                   transaction(( retractall(petta_capacity_count(Space, _)),
                                 assertz(petta_capacity_count(Space, 0)) )))
    ;   true
    ).

%How many atoms a native space OWNS. Inherited match, get-atoms and
%space-contains read the child-first chain; this count deliberately does not,
%because capacity constrains the writable front store rather than its parents.
%A capacity-claimed pool reads its
%incremental fact; every other space reads the store's own per-predicate
%clause bookkeeping, the manual's count-asserted-facts idiom
%[source: https://www.swi-prolog.org/pldoc/man?predicate=predicate_property%2F2].
%A space that has never been written has no storage module and holds nothing.
%A foreign space's atoms live with its provider, where the only general count
%is an enumeration; hiding that would promise the wrong complexity class
%[tested: spaces_atom_count:a_foreign_space_has_no_native_count].
space_atom_count(Space, Count) :-
    petta_capacity_count(Space, Count),
    !.
space_atom_count(Space, Count) :-
    (   seam:foreign_space(Space)
    ->  throw(error(petta_foreign_space_count(Space), none))
    ;   space_atom_count_uncached(Space, Count)
    ).

space_atom_count_uncached(Space, Count) :-
    (   native_storage_module_ready(Space, Module)
    ->  findall(N,
                ( current_predicate(Module:Name/Arity),
                  functor(Head, Name, Arity),
                  (   predicate_property(Module:Head, number_of_clauses(N))
                  ->  true
                  ;   N = 0
                  ) ),
                Counts),
        sum_list(Counts, Count)
    ;   Count = 0
    ).

clear_native_atoms(Space) :-
    (   native_storage_module_ready(Space, Module)
    ->  space_module(Space, SupportModule),
        findall(Atom, compiled_half_atom(Space, Module, Atom), Compiled),
        forall(member(Atom, Compiled),
               ( metta_remove_atom(Space, Atom, _) -> true ; true )),
        native_storage_functor(Space, Functor),
        forall(( current_predicate(Module:Functor/Arity),
                 functor(Head, Functor, Arity) ),
               retractall(Module:Head)),
        retractall(Module:'$petta_native_scalar'(_))
    ;   SupportModule = none
    ),
    petta_capacity_count_cleared(Space),
    retractall(import_life(Space, _, _)),
    (   SupportModule \== none
    ->  support_forget_module(SupportModule)
    ;   true
    ),
    forget_space_source_loads(Space).

%The atoms whose removal has a consequence beyond storage, which are exactly
%the two shapes metta_remove_atom/3 answers specially; a shape added there
%without being added here would go back to leaving its compiled half behind a
%clear.
%
%Asked of the storage predicate by HEAD SYMBOL rather than by filtering a walk
%of the space. The head is the first argument, so this is one indexed lookup
%per shape and a space of plain atoms pays nothing for the question; filtering
%an enumeration cost one inference per stored atom on every clear, which the
%benchmarks saw as +20,002 inferences on py-method-call and +8,000 on
%handle-round-trip [measured 2026-08-19].
compiled_half_atom(Space, Module, [=, Head, Body]) :-
    native_storage_functor(Space, Functor),
    Term =.. [Functor, =, Head, Body],
    call(Module:Term),
    Head = [F|_], atom(F).
compiled_half_atom(Space, Module, [':', F, Type]) :-
    native_storage_functor(Space, Functor),
    Term =.. [Functor, ':', F, Type],
    call(Module:Term),
    atom(F), fun(F).

%Enumeration answers the space's expressions and then its scalar atoms.
%native_storage_module_ready/2 is a dynamic lookup, so an unbound space
%enumerated every space ever written to and !(collapse (get-atoms $any))
%answered with another space's atoms without ever naming it.
%
%This raise is the ENGINE's invariant and not the language's answer: a MeTTa
%program cannot reach it, because 'get-atoms'/2 above refuses a first argument
%that is not a space before it gets here. What is left is an engine caller
%that lost its space name, and that is a bug in the engine rather than in a
%program, so it throws instead of answering an atom the caller would store
%[tested: spaces_storage_modules:reading_atoms_requires_a_named_space].
get_native_atom(Space, Pattern) :-
    ( var(Space) -> instantiation_error(Space) ; true ),
    metta_refuse_module_for_space(Space, get_native_atom/2),
    native_storage_module_ready(Space, Module),
    get_native_atom(Module, Space, Pattern).

%The mirror of with_metta_module/2's refusal, at the space-name doors: a
%space MODULE handed where a NAME is wanted read exactly like a miss, the
%store answering "not held" with no type error, so a wrong-argument call
%was indistinguishable from absence and a plt cleanup once removed nothing
%from four of five cases in silence. The two execution-module prefixes turn it
%into a refusal at the door
%[tested: test_a_module_where_a_space_name_is_wanted_refuses_by_name].
metta_refuse_module_for_space(Space, Door) :-
    (   atom(Space),
        (   metta_exec_module_prefix(Prefix),
            sub_atom(Space, 0, _, _, Prefix)
        ;   sub_atom(Space, 0, _, _, '$petta_param_exec:')
        )
    ->  throw(error(type_error(metta_space_name, Space),
                    context(Door,
                            'a space MODULE arrived where a space NAME is \c
                             wanted; space_module/2 maps the exact atomic or \c
                             expression identifier to this module, not back')))
    ;   true
    ).

%A pattern whose SHAPE is known builds the storage head FIRST, so the
%store's argument indexing dispatches the way match/4's identical read
%does, instead of enumerating every clause under an unbound head and
%filtering afterwards: a bound-pattern read through this door was
%O(space held) where the same read through match was one indexed lookup
%[measured 2026-08-21: a per-add presence probe through the old path
%cost 2,055 inferences at 2,000 held atoms and 21,055 at 10,000,
%linear, against 69.01 flat through match's spelling of the same
%question; through this clause the same probe reads 57.01 at 2,000 and
%57.00 at 10,000]. The occurs check mirrors native_expression/4's: a cyclic
%binding is never a MeTTa answer. A partial list keeps the enumerating
%clause below, and a bound SCALAR skips both, because =../2 on it threw
%where the store owed a clean miss and the scalar shelf is that atom's
%own clause anyway [tested: spaces_contains].
get_native_atom(Module, [Family|Parameters], Pattern) :-
    is_list(Pattern),
    Pattern = [_|_],
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    length(Pattern, Arity),
    functor(Head, '$petta_parametric_atom', Arity),
    Head =.. ['$petta_parametric_atom'|Pattern],
    call(Module:Head),
    acyclic_term(Pattern).
get_native_atom(Module, Space, Pattern) :-
    is_list(Pattern),
    Pattern = [_|_],
    !,
    length(Pattern, Arity),
    functor(Head, Space, Arity),
    Head =.. [Space | Pattern],
    call(Module:Head),
    acyclic_term(Pattern).
%A PARTIAL list with a bound head keeps the head's index too: the arity is
%open, so one storage head cannot be built, but the held arities are a small
%enumerable set and within each the first argument dispatches exactly as
%above. Without this pair an open-tail probe fell to the clause/2 walk below
%and read every stored atom: lib_tabling's `'get-atoms'('&petta', [tabled|_])`
%existence check, run per compiled equation, cost the whole catalog per event,
%23.7 inferences per held row over one tabling_fib load, linear from 74,268
%inferences at +0 planted rows through 78,777 at +200 to 97,977 at +1,000
%[measured: the three totals left; command=python - with MeTTa().space then
%m.stats() around m.run(examples/libraries/tabling_fib.metta) after N
%`!(add-atom &petta (visibility dummy-N PUBLIC))` writes, fresh process per
%N; fixture=p14-integration with engine/reader.so; commit=2b2d6f3e36d259e789ad7d977eebc3623b002970]. A bound
%head that is itself compound shares one principal functor across such rows
%and degrades toward the walk only for that shape. The head decomposes into
%FRESH arguments before unifying with the pattern, because =.. on the pattern
%itself raised a raw type error for an improper tail such as [a|b] whenever
%any clause reached it, a store-content-dependent accident the walk below
%still carries for unbound heads; through this pair an improper tail is a
%deterministic miss [tested: an_open_tail_probe_reads_through_the_head_index].
get_native_atom(Module, [Family|Parameters], Pattern) :-
    nonvar(Pattern),
    Pattern = [Rel|_],
    nonvar(Rel),
    \+ is_list(Pattern),
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    current_predicate(Module:'$petta_parametric_atom'/Arity),
    Arity >= 1,
    functor(Head, '$petta_parametric_atom', Arity),
    arg(1, Head, Rel),
    call(Module:Head),
    Head =.. [_|Args],
    Args = Pattern,
    acyclic_term(Pattern).
get_native_atom(Module, Space, Pattern) :-
    nonvar(Pattern),
    Pattern = [Rel|_],
    nonvar(Rel),
    \+ is_list(Pattern),
    !,
    current_predicate(Module:Space/Arity),
    Arity >= 1,
    functor(Head, Space, Arity),
    arg(1, Head, Rel),
    call(Module:Head),
    Head =.. [_|Args],
    Args = Pattern,
    acyclic_term(Pattern).
get_native_atom(Module, [Family|Parameters], Pattern) :-
    \+ atomic(Pattern),
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    current_predicate(Module:'$petta_parametric_atom'/Arity),
    functor(Head, '$petta_parametric_atom', Arity),
    clause(Module:Head, true),
    Head =.. ['$petta_parametric_atom'|Pattern].
get_native_atom(Module, Space, Pattern) :-
    \+ atomic(Pattern),
    current_predicate(Module:Space/Arity),
    functor(Head, Space, Arity),
    clause(Module:Head, true),
    Head =.. [Space | Pattern].
get_native_atom(Module, _, Pattern) :-
    get_native_scalar_atom_in(Module, Pattern).

get_native_scalar_atom_in(Module, Pattern) :-
    Module:'$petta_native_scalar'(Pattern).
