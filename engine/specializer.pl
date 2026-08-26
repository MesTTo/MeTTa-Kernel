% Purpose: specialize higher-order MeTTa calls and invalidate generated
%   functions when their source equations change.
% Guarantees:
%   - Specializer assertions made while loading a source participate in source
%     rollback [tested 2026-08-14:
%     specializer:compound_partial_key_has_stable_anonymous_variables].
%   - Concurrent translation creates one specialization for a function and
%     normalized key [tested 2026-08-15:
%     specializer:concurrent_translation_creates_one_specialization].
%   - A recursive specialization returns to neither the generic predicate nor
%     the reducer after its first step, so the saving is per step
%     [tested 2026-08-18:
%     specializer:exact_recursive_key_folds_to_specialized_predicate,
%     specializer:the_recursive_specialization_never_re_enters_the_reducer]
%     [measured 2026-08-18: 8,004 against 24,004 inferences over 1,000 steps,
%     the same third at 100].
%   - A specialization is a derived support-graph node, so changing its source
%     function invalidates transitive specialization chains through the common
%     forward walk [tested:
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - A specialization copies only the source function's governing
%     declarations, so an inherited arrow cannot become a local declaration
%     on a specialization of an untyped shadow [tested:
%     specializer_invalidation:an_untyped_local_shadow_does_not_type_its_specialization;
%     commit=7b238053d2907cd514e3fd9a29927d43a53c5a3c].
%   - Every specialization name is one writable MeTTa symbol; existing safe
%     display names stay unchanged and unsafe structured keys receive a
%     reversible canonical encoding. Internal partial/2 closures are retained
%     as their MeTTa application syntax in the reflected equation, so the
%     generated atom itself crosses the same text boundary [tested:
%     specializer:specialization_names_are_writable_and_stable,
%     test_a_specialized_program_saves_and_digests; commit=5d93a44cf4820717163bbf8dfaf667ae14e5e4ee].
%   - Planning a specialization grafts a call argument onto the equation's
%     head pattern without metacalling anything per position, so an arriving
%     equation pays no lambda machinery [tested:
%     specializer:the_argument_walk_makes_no_metacall_per_position;
%     commit=WORKTREE] [measured 2026-08-26: 4.0 inferences per position
%     against the 17.0 the yall lambda it replaced cost; command=cd
%     tests/prolog && swipl -g "set_test_options([format(log)]), run_tests"
%     -t halt specializer.plt; commit=WORKTREE].
% Guarded by: '$petta_specializer' serializes the existence check and the
%   transaction that publishes a specialization.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%Two doors: the one engine/translator.pl takes when a higher-order call can
%specialize, and the one engine/spaces.pl takes when a changed function
%invalidates what was built over it. Everything else, the plan, the agreement
%check and the generated-clause bookkeeping, is this subsystem's own
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
:- encoding(utf8).
:- module(specializer,
          [ maybe_specialize_call/4,
            prepare_specialization_invalidation/2,
            %The generated-specialization table, read by engine/spaces.pl when a
            %function's clauses change under one.
            ho_specialization/3,
            %Emitted into a compiled body under (pragma! verify-specializations
            %true), so it has to be reachable from the space's module the way
            %every other emitted goal is. Nothing in examples/ sets that pragma,
            %so the corpus half of the emitted-goal check never compiled a body
            %holding it and the mode was simply broken from the cut until the
            %source half found it [measured 2026-08-22: !(twice inc 5) under the
            %pragma raised existence_error(procedure,
            %'$petta_exec:&self':petta_verified_specialization/2)].
            petta_verified_specialization/2
          ]).

%This subsystem WRITES core registries -- engine/metta.pl owns fun/1,
%arity/2 and the two shape tables -- and a base module makes a name
%visible without making a write land on it, so they are imported rather
%than inherited. See petta_shared_registry/1 in engine/metta.pl.
:- petta_import_shared_registries(specializer).

:- dynamic ho_specialization/3.
:- dynamic ho_specialization_failed/3.
%Verified once per specialization, under the checking mode only.
:- dynamic ho_specialization_agrees/1.
%Recorded when the generic side could not be run inside the bound.
:- dynamic ho_specialization_unverified/2.
%Held while a specialization's own check is running, so the recursive
%calls inside it do not each start another check.
:- dynamic ho_specialization_checking/1.

% Specialize HV(AVs), or fold an exact recursive specialization back to the
% predicate currently being generated. A same-function call with a different
% key stays generic, which retains the termination guard for growing keys such
% as (evolve (twice $r) ...).
maybe_specialize_call(HV, AVs, Out, Goal) :-
    specialization_plan(HV, AVs, CleanBindSet, MetaList, HasDirectBenefit),
    %A tabled function must never specialize: the clone would carry the
    %recursion without the tabling, turning SLG termination back into
    %divergence. Found 2026-08-18 as a 27,525-frame loop in
    %linkage-closure_Spec_[d]/3, reached whenever a tabled closure was
    %called with an argument that happened to NAME a defined function (a
    %graph node called d, with (= (d $x) ...) defined elsewhere). The
    %(tabled Space Name Arity) reflection facts lib_tabling keeps in
    %&petta are the module-agnostic record of what is tabled. AFTER the
    %plan on purpose: the plan is the fail-fast for the overwhelming
    %non-higher-order case, and putting this probe first taxed every
    %translated call (+364 inferences per op on handle-round-trip,
    %measured 2026-08-18); on a formed plan it is one indexed probe.
    \+ get_native_atom('&petta', [tabled, _, HV, _]),
    length(AVs, N),
    Arity is N + 1,
    \+ ho_specialization_failed(HV, Arity, CleanBindSet),
    specialization_name(HV, CleanBindSet, SpecName),
    ( nb_current('$petta_spec_stack', Stack) -> true ; Stack = [] ),
    ( active_specialization(HV, Stack, ActiveKey, ActiveSpecName)
      -> CleanBindSet =@= ActiveKey,
         specialization_goal(ActiveSpecName, AVs, Out, Goal),
         nb_setval('$petta_spec_needed', true)
    ; capture_nb_state('$petta_spec_needed', PreviousNeeded),
      setup_call_cleanup(
          ( nb_setval('$petta_spec_needed', false),
            nb_setval('$petta_spec_stack',
                      [specializing(HV, CleanBindSet, SpecName)|Stack]) ),
          specialize_call(HV, AVs, Out, Goal, CleanBindSet, MetaList,
                          HasDirectBenefit, SpecName, Arity),
          ( nb_setval('$petta_spec_stack', Stack),
            restore_nb_state('$petta_spec_needed', PreviousNeeded) )),
      nb_setval('$petta_spec_needed', true)
    ).

active_specialization(HV, [specializing(ActiveHV, Key, SpecName)|_],
                      Key, SpecName) :-
    ActiveHV == HV, !.
active_specialization(HV, [_|Stack], Key, SpecName) :-
    active_specialization(HV, Stack, Key, SpecName).

capture_nb_state(Name, present(Value)) :- nb_current(Name, Value), !.
capture_nb_state(_, absent).

restore_nb_state(Name, present(Value)) :- !, nb_setval(Name, Value).
restore_nb_state(Name, absent) :-
    ( nb_current(Name, _) -> nb_delete(Name) ; true ).

% Keep the established readable name for the injective singleton-atom case.
% The delimiter cannot occur in HV and the closing bracket cannot occur in
% Key, so two different pairs cannot produce the same display. A safe HV uses
% `_Spec_k` plus its encoded key; a hostile HV uses the disjoint `petta_Spec_h`
% prefix plus the encoded complete identity. The token-safe alphabet
% `[0-9a-fz]` uses `z` between variable-width hexadecimal code points, making
% the encoding reversible instead of relying on a collision-prone digest.
% SWI's own tests establish that write_canonical/1 numbers variables and
% quotes operator-sensitive and non-ASCII atoms independently of the active
% operator table [source:
% https://github.com/SWI-Prolog/swipl-devel/blob/f49d28558b5f1ade8348f254b5583117e773b2bb/tests/core/test_write.pl#L94-L131;
% commit=5d93a44cf4820717163bbf8dfaf667ae14e5e4ee].
specialization_name(HV, CleanBindSet, SpecName) :-
    (   legacy_specialization_name(HV, CleanBindSet, DisplayName)
    ->  SpecName = DisplayName
    ;   encoded_specialization_name(HV, CleanBindSet, SpecName),
        (   metta_symbol_writable(SpecName)
        ->  true
        ;   throw(error(
                representation_error(specialization_name),
                context(specializer:specialization_name/3, SpecName)))
        )
    ).

legacy_specialization_name(HV, [Key], DisplayName) :-
    atom(HV),
    atom(Key),
    \+ sub_atom(HV, _, _, _, '_Spec_['),
    \+ sub_atom(Key, _, _, _, ']'),
    format(atom(DisplayName), "~w_Spec_[~w]", [HV, Key]),
    metta_symbol_writable(DisplayName).

encoded_specialization_name(HV, CleanBindSet, SpecName) :-
    atom(HV),
    metta_symbol_writable(HV),
    \+ sub_atom(HV, _, _, _, '_Spec_k'), !,
    encoded_term(CleanBindSet, EncodedKey),
    atom_concat(HV, '_Spec_k', Prefix),
    atom_concat(Prefix, EncodedKey, SpecName).
encoded_specialization_name(HV, CleanBindSet, SpecName) :-
    encoded_term(specialization(HV, CleanBindSet), EncodedIdentity),
    atom_concat('petta_Spec_h', EncodedIdentity, SpecName).

encoded_term(Term, Encoded) :-
    copy_term(Term, CanonicalTerm),
    numbervars(CanonicalTerm, 0, _, [singletons(true)]),
    with_output_to(atom(Canonical), write_canonical(CanonicalTerm)),
    atom_codes(Canonical, Codes),
    maplist(hex_code, Codes, HexCodes),
    atomic_list_concat(HexCodes, z, Encoded).

hex_code(Code, Hex) :-
    format(atom(Hex), '~16r', [Code]).

% partial/2 is the evaluator's compiled closure, not a MeTTa grounded value.
% The source form that constructs it is the incomplete application itself:
% partial(+,[1]) comes from and must be reflected as `(+ 1)` in a body. A
% specialized head does not need to re-state the binding already encoded in
% its private name, and a written `(+ 1)` in head position is structural data,
% not a closure. Restore those bound head positions as fresh variables so a
% saved specialization compiles back to a clause its real callers can enter.
specialization_storage_input(
        SpecName,
        storage_meta(SourceArgs, SourceBody, SourceVariables,
                     StoredVariables),
        [=, [SpecName|StoredArgs], StoredBody]) :-
    specialization_storage_head(SourceArgs, SourceVariables,
                                StoredVariables, StoredArgs),
    bind_specialization_storage_variables(SourceVariables, StoredVariables),
    specialization_storage_term(SourceBody, StoredBody).

specialization_storage_head(Variable, SourceVariables, StoredVariables,
                            Stored) :-
    var(Variable), !,
    (   storage_variable_source(Variable, SourceVariables,
                                StoredVariables, Source),
        nonvar(Source)
    ->  true
    ;   Stored = Variable
    ).
specialization_storage_head([Head|Tail], SourceVariables, StoredVariables,
                            [StoredHead|StoredTail]) :- !,
    specialization_storage_head(Head, SourceVariables, StoredVariables,
                                StoredHead),
    specialization_storage_head(Tail, SourceVariables, StoredVariables,
                                StoredTail).
specialization_storage_head(Term, _, _, Term).

storage_variable_source(Variable, [Source|_], [Stored|_], Source) :-
    Variable == Stored, !.
storage_variable_source(Variable, [_|Sources], [_|StoredVariables], Source) :-
    storage_variable_source(Variable, Sources, StoredVariables, Source).

bind_specialization_storage_variables([], []).
bind_specialization_storage_variables([Source|Sources], [Stored|StoredVars]) :-
    ( nonvar(Source) -> Stored = Source ; true ),
    bind_specialization_storage_variables(Sources, StoredVars).

specialization_storage_term(Variable, Variable) :-
    var(Variable), !.
specialization_storage_term(partial(Base, Bound), Written) :- !,
    maplist(specialization_storage_term, [Base|Bound], Written).
specialization_storage_term([Head|Tail], [WrittenHead|WrittenTail]) :- !,
    specialization_storage_term(Head, WrittenHead),
    specialization_storage_term(Tail, WrittenTail).
specialization_storage_term(Term, Term).

% Build a stable, variant-normalized specialization key.
%
% This intentionally descends through arbitrary compound terms (including
% partial/2 closures).  A shallow list-only variable replacement leaves fresh
% Prolog variable ids inside compound terms, producing unstable specialization
% names such as app_Spec_[partial(lambda_1,[_17896])].
normalize_specialization_key(Term, Normalized) :-
    copy_term(Term, Normalized),
    numbervars(Normalized, 0, _, [singletons(true)]).

% Build one global key from all higher-order positions, while binding every
% retained clause independently. The key is ordered by call argument and path,
% so equation order cannot select a different partial reduction.
specialization_plan(HV, AVs, CleanBindSet, MetaList, HasDirectBenefit) :-
    call_may_specialize(AVs),
    current_metta_module(Module),
    metta_ensure_compiled(HV),
    fun_meta_clauses(Module, HV, InternalMetaList),
    paired_source_meta_clauses(Module, HV, InternalMetaList, SourceMetaList),
    maplist(bind_specialization_clause(AVs), SourceMetaList,
            MetaList, BindingLists),
    append(BindingLists, Bindings),
    ( member(binding(_, _, _, direct), Bindings)
      -> HasDirectBenefit = true
    ; HasDirectBenefit = false ),
    canonical_specialization_bindings(Bindings, BindSet),
    BindSet \== [],
    normalize_specialization_key(BindSet, CleanBindSet).

% fun_meta_clause/4 retains the constrained representation used by compiled
% matching. In particular, a written `(cons $x $xs)` head is represented as
% the Prolog list cell `[$x|$xs]`. translated_from/2 retains the written
% equation. Pair each retained clause with that source equation, then unify
% their variables through constrain_args/3's normalized head. Specialization
% can bind the compiled and written views together without guessing an inverse
% for every head lowering.
paired_source_meta_clauses(Module, HV, InternalMetaList, PairedMetaList) :-
    translator:fun_meta_module(Module, HV, Owner),
    findall(source_meta(SourceArgs, SourceBody),
            ( translated_from(Ref, [=, [HV|SourceArgs], SourceBody]),
              clause_property(Ref, module(Owner)) ),
            SourceMetaList),
    pair_source_meta_clauses(InternalMetaList, SourceMetaList,
                             PairedMetaList, []).

pair_source_meta_clauses([], Remaining, [], Remaining).
pair_source_meta_clauses([InternalMeta|InternalMetas], SourceMetas0,
                         [PairedMeta|PairedMetas], Remaining) :-
    select(SourceMeta, SourceMetas0, SourceMetas),
    align_source_meta_clause(InternalMeta, SourceMeta, PairedMeta), !,
    pair_source_meta_clauses(InternalMetas, SourceMetas,
                             PairedMetas, Remaining).

align_source_meta_clause(fun_meta(InternalArgs, InternalBody),
                         source_meta(SourceArgs, SourceBody),
                         paired_meta(fun_meta(InternalArgs, InternalBody),
                                     fun_meta(SourceArgs, SourceBody),
                                     StoredMeta)) :-
    term_variables(SourceArgs-SourceBody, SourceVariables),
    copy_term(SourceVariables-(SourceArgs-SourceBody),
              StoredVariables-(StoredArgs-StoredBody)),
    StoredMeta = storage_meta(StoredArgs, StoredBody, SourceVariables,
                              StoredVariables),
    maplist(source_argument_internal_shape, SourceArgs, NormalizedArgs),
    unify_with_occurs_check(NormalizedArgs-SourceBody,
                            InternalArgs-InternalBody).

source_argument_internal_shape(Source, Internal) :-
    translator:constrain_args(Source, Internal, _).

bind_specialization_clause(AVs,
                           paired_meta(fun_meta(Args, Body), SourceMeta,
                                       StoredMeta),
                           paired_meta(fun_meta(Args, Body), SourceMeta,
                                       StoredMeta),
                           Bindings) :-
    ( same_length(AVs, Args)
      -> bind_specialization_args(AVs, Args, Body, 1, Bindings)
    ; Bindings = [] ).

bind_specialization_args([], [], _, _, []).
bind_specialization_args([Value|Values], [Arg|Args], Body, Index, Bindings) :-
    ( specializable_vars(Body, Value, Arg, _, PathBindings)
      -> index_bindings(PathBindings, Index, IndexedBindings)
    ; IndexedBindings = [] ),
    NextIndex is Index + 1,
    bind_specialization_args(Values, Args, Body, NextIndex, RestBindings),
    append(IndexedBindings, RestBindings, Bindings).

index_bindings([], _, []).
index_bindings([path_binding(Path, Value, Use)|Bindings], Index,
               [binding(Index, Path, Value, Use)|Indexed]) :-
    index_bindings(Bindings, Index, Indexed).

canonical_specialization_bindings(Bindings, BindSet) :-
    maplist(binding_pair, Bindings, Pairs),
    keysort(Pairs, SortedPairs),
    unique_binding_values(SortedPairs, BindSet).

binding_pair(binding(Index, Path, Value, _), (Index-Path)-Value).

unique_binding_values([], []).
unique_binding_values([Key-Value|Pairs], [Value|Values]) :-
    skip_same_binding(Pairs, Key, Value, Rest),
    unique_binding_values(Rest, Values).

skip_same_binding([OtherKey-OtherValue|Pairs], Key, Value, Rest) :-
    OtherKey == Key, !,
    ( OtherValue =@= Value
      -> skip_same_binding(Pairs, Key, Value, Rest)
    ; throw(error(representation_error(specialization_binding),
                  context(canonical_specialization_bindings/2,
                          'one call path produced conflicting bindings'))) ).
skip_same_binding(Pairs, _, _, Pairs).

% Create a specialization once, or reuse the completed predicate for the same
% key. MetaList already carries the explicit per-clause bindings.
specialize_call(HV, AVs, Out, Goal, CleanBindSet, MetaList,
                HasDirectBenefit, SpecName, Arity) :-
    %The mutex must be acquired before transaction/1 takes its snapshot. If
    %the order is reversed, a waiting transaction can still see the database
    %from before the first worker committed and publish a duplicate.
    with_mutex('$petta_specializer',
               transaction(specialize_call_locked(
                   HV, CleanBindSet, MetaList, HasDirectBenefit,
                   SpecName, Arity, Outcome))),
    Outcome == ready, !,
    specialization_goal(SpecName, AVs, Out, Goal).

%Keyed by module as well as by call shape. Keyed by shape alone, a named
%space reused the specialization &self had already published, so the same
%program answered twice there and once in &self, and which you got depended
%on what had run earlier in the process.
specialize_call_locked(HV, _, _, _, SpecName, _, ready) :-
    current_metta_module(Module),
    ho_specialization(Module, HV, SpecName), !.
%A COPIED specialization. A space cloned from one that had specialized
%carries the generated equations as ordinary atoms, and compiling their
%bodies re-enters here with no ho_specialization/3 row behind the name:
%regenerating then stored the same equations a SECOND time beside the
%copies, so a clone held every specialization twice and the copies were
%orphans nothing would ever invalidate. The name already being a compiled
%function of this module IS the copy's signature, so it is adopted, the
%row recorded as if generated here, and invalidation sees the clone's
%specializations again
%[tested: a_copied_space_adopts_its_specializations_instead_of_duplicating].
specialize_call_locked(HV, _, _, _, SpecName, _, ready) :-
    current_metta_module(Module),
    fun_in(Module, SpecName), !,
    assertz(ho_specialization(Module, HV, SpecName), Ref),
    record_source_assertion(Ref),
    record_specialization_support(Module, HV, SpecName).
%The specialization belongs to the space whose code triggered it. This runs
%during translation, inside with_metta_module/2, so the current module is the
%one whose functions the generated body references. Registering globally and
%asserting into user left the clause calling functions that do not exist
%there: (= (twice $f $x) ($f ($f $x))) with (= (bump $n) (+ $n 1)) crashed on
%the first call in a named space with Unknown procedure: bump/2, and gave a
%duplicate answer when an earlier &self engine had compiled the same name.
%add_function_atom/5 in spaces.pl is the same job done correctly
%[tested: higher_order_code_runs_inside_a_named_space].
specialize_call_locked(HV, CleanBindSet, MetaList, HasDirectBenefit,
                       SpecName, Arity, Outcome) :-
    current_metta_module(Module),
    current_metta_space(Space),
    register_fun_in(Module, SpecName),
    assertz(ho_specialization(Module, HV, SpecName), SpecializationRef),
    record_source_assertion(SpecializationRef),
    record_specialization_support(Module, HV, SpecName),
    register_arity(SpecName, Arity),
    ( findall(TypeChain,
              catch_recover(governing_type_declaration(HV, TypeChain), fail),
              TypeChains),
      forall(member(TypeChain, TypeChains),
             add_sexp(Space, [':', SpecName, TypeChain])),
      ( HasDirectBenefit == true
        -> nb_setval('$petta_spec_needed', true)
      ; true ),
      maplist({SpecName}/[paired_meta(fun_meta(ArgsNorm,BodyExpr),
                                      _SourceMeta,StoredMeta),
                          clause_info(StoredInput,Clause)]>>
              ( CompiledInput = [=,[SpecName|ArgsNorm],BodyExpr],
                translate_clause(CompiledInput,Clause,false),
                specialization_storage_input(SpecName, StoredMeta,
                                             StoredInput) ),
              MetaList, ClauseInfos),
      nb_getval('$petta_spec_needed', true),
      forall(member(clause_info(Input, Clause), ClauseInfos),
             ( asserta(Module:Clause, Ref),
               record_source_assertion(Ref),
               record_translated_from(Ref, Input, SourceRef),
               record_source_assertion(SourceRef),
               add_sexp(Space, Input, SpaceRef),
               record_source_assertion(SpaceRef),
               format(atom(Label), "metta specialization (~w)", [SpecName]),
               maybe_print_compiled_clause(Label, Input, Clause) ))
    -> Outcome = ready
    ; ( silent(true) -> true
      ; format("Not specialized ~w~n", [SpecName/Arity]) ),
      forget_symbol(Module, SpecName),
      retractall(ho_specialization(Module, HV, SpecName)),
      ( ho_specialization_failed(HV, Arity, CleanBindSet)
        -> true
      ; assertz(ho_specialization_failed(HV, Arity, CleanBindSet), FailedRef),
        record_source_assertion(FailedRef) ),
      Outcome = failed
    ).

specialization_goal(SpecName, AVs, Out, Goal) :-
    append(AVs, [Out], CallArgs),
    Spec =.. [SpecName|CallArgs],
    (   petta_verifying_specializations
    ->  Goal = petta_verified_specialization(SpecName, Spec)
    ;   Goal = Spec
    ).

% A generated predicate exists because its specialization exists, and the
% specialization exists because the source function does. Keeping both edges
% makes a specialization of a specialization one ordinary forward chain.
record_specialization_support(Module, Source, SpecName) :-
    Specialization = specialization(Module, SpecName),
    support_publish(Specialization,
                    [function(Module, Source)],
                    [edge(Specialization, function(Module, SpecName))]).

:- multifile support_graph:support_invalidation_action/1.
support_graph:support_invalidation_action(specialization(Module, SpecName)) :-
    (   ho_specialization(Module, _, SpecName)
    ->  forget_symbol(Module, SpecName)
    ;   true
    ).

%The specializer's whole claim is that a specialized call answers exactly
%what the generic one answers. MeTTaLog makes that self-enforcing at run
%time (metta_improve.pl compares interpreter against compiler on first
%use and demotes the loser), and the shape transfers, but running both
%ways in production would run a function's EFFECTS twice, which is worse
%than the optimisation is worth. So it is a checking MODE instead: off,
%the emitted goal is byte-identical to what it always was and costs
%nothing; on, every specialization is compared against the generic call
%the first time it runs, and a disagreement THROWS rather than silently
%demoting, because a checking mode that hides the defect it found is
%worth less than no check. The mode is what turns the workspace's
%"validate every optimisation with a differential that runs it both
%ways" from a thing tests must remember into a property the whole
%example corpus asserts on every gate run.
petta_verifying_specializations :-
    (   metta_pragma('verify-specializations', V), V \== false, V \== none
    ->  true
    ;   getenv('PETTA_VERIFY_SPECIALIZATIONS', Set), Set \== '0'
    ).

%Answers exactly what the specialization answers, after establishing once
%per specialization that the generic call agrees. The comparison is over
%COMPLETE answer lists with variant equality, so a renaming is not a
%difference and a missing, extra or reordered answer is.
%The specialization goal is compiled into the module of the space that
%triggered it and is CALLED from here, which is the engine's module, so both
%of these carry it in. Without the declaration the verifying mode raised
%existence_error for every specialization in the corpus, which is what
%check.sh's spec-differential lane runs over
%[tested: specializer_invalidation:the_verifier_runs_a_clone_in_its_own_module].
:- meta_predicate petta_verified_specialization(?, 0),
                  petta_check_specialization(?, 0).
petta_verified_specialization(SpecName, Spec) :-
    (   ho_specialization_agrees(SpecName)
    ->  call(Spec)
    ;   ho_specialization_unverified(SpecName, _)
    ->  call(Spec)
    ;   ho_specialization_checking(SpecName)
    ->  %Re-entry: the clone under check calls itself, which is what a
        %recursive specialization IS. Checking again from inside its own
        %check nests a full comparison per recursive step, so the cost is
        %exponential in the recursion depth rather than paid once: with
        %the marker holbenchmark's four specializations verify in under a
        %second, without it the same file did not finish in ninety
        %[measured 2026-08-18]. The specializer's own compile-time
        %recursion guard ($petta_spec_stack) is the same pattern.
        call(Spec)
    ;   setup_call_cleanup(assertz(ho_specialization_checking(SpecName)),
                           petta_check_specialization(SpecName, Spec),
                           retractall(ho_specialization_checking(SpecName))),
        call(Spec)
    ).

%The check, run once per specialization and BOUNDED WHOLE. Both sides are
%bounded, not just the slow one: comparing answer sets means forcing all
%answers of a call the program may only have wanted one of, so the
%specialized side can blow up exactly as the generic side can, and a
%generator with infinitely many answers would never return from either.
%Exceeding the bound records the specialization as unverified and leaves
%the call to run normally, lazily, as it always did; the count is
%REPORTED so coverage is a number rather than a claim of completeness.
%This is translation validation's own shape: the check is bounded and
%says what it could not check, instead of being trusted or being
%unbounded [source: Pnueli, Siegel and Singerman, Translation Validation,
%TACAS 1998].
petta_check_specialization(SpecName, Spec) :-
    %The module the specialization was compiled into, recovered from the
    %qualification the meta_predicate declaration above put on the way in.
    %Both sides of the comparison run there: the clone lives in that module,
    %and so does the generic function it was cloned from.
    strip_module(Spec, Module, Bare),
    Bare =.. [_|Args],
    copy_term(Args, SpecArgs),
    copy_term(Args, PlainArgs),
    SpecCopy =.. [SpecName|SpecArgs],
    petta_specialization_generic(SpecName, PlainArgs, Generic),
    petta_specialization_budget(Budget),
    %Both sides run with that module IN FORCE as well as qualified. The
    %generic side reaches reduce/3 for a higher-order argument, and reduce/3
    %resolves the name against current_metta_module/1: without the switch it
    %asked &self about a function only this space defines, got no answer, and
    %handed the call back unreduced, so the check reported a disagreement that
    %was its own [tested:
    %specializer_invalidation:the_verifier_runs_a_clone_in_its_own_module].
    catch(
        (   call_with_inference_limit(
                with_metta_module(Module,
                (   findall(SpecArgs, call(Module:SpecCopy), Specialized),
                    findall(PlainArgs, call(Module:Generic), Plain)
                )), Budget, Result),
            (   Result == inference_limit_exceeded
            ->  Outcome = unbounded
            ;   Outcome = both(Specialized, Plain)
            )
        ),
        Error,
        (   control_exception(Error) -> throw(Error) ; Outcome = raised(Error) )),
    petta_specialization_verdict(SpecName, Outcome).

petta_specialization_verdict(SpecName, both(Specialized, Plain)) :-
    (   Specialized =@= Plain
    ->  assertz(ho_specialization_agrees(SpecName))
    ;   throw(error(petta_specialization_disagrees(SpecName, Specialized, Plain),
                    context(petta_verified_specialization/2,
                            'a specialization answered differently from \c
                             the generic call')))
    ).
petta_specialization_verdict(SpecName, unbounded) :-
    assertz(ho_specialization_unverified(SpecName, inference_limit)).
petta_specialization_verdict(SpecName, raised(Error)) :-
    throw(error(petta_specialization_disagrees(SpecName, raised, Error),
                context(petta_verified_specialization/2,
                        'one side raised where the other answered'))).

%The bound, in inferences, tunable for a deeper sweep.
petta_specialization_budget(Budget) :-
    (   getenv('PETTA_VERIFY_BUDGET', Text), atom_number(Text, N), N > 0
    ->  Budget = N
    ;   Budget = 200000
    ).

%The generic twin of a specialized call: the same arguments through the
%function the specialization was cloned from, which is exactly what would
%have run had the plan been refused.
petta_specialization_generic(SpecName, Args, Generic) :-
    ho_specialization(_, HV, SpecName), !,
    Generic =.. [HV|Args].

%Extracts clause-head variables and their call-site copies, producing eligible Var–Copy pairs for specialization:
specializable_vars(BodyExpr, Value, Arg, HoVars) :-
    specializable_vars(BodyExpr, Value, Arg, HoVars, _).

specializable_vars(BodyExpr, Value, Arg, HoVars, Bindings) :-
    term_variables(Arg, Vars),
    maplist(variable_first_path(Arg), Vars, Paths),
    copy_term(Arg-Vars, ArgCopy-VarsCopy),
    traverse_list(ArgCopy, Value),
    eligible_var_pairs(Vars, VarsCopy, Paths, BodyExpr, HoVars, Bindings).

variable_first_path(Term, Var, Path) :-
    variable_path(Term, Var, [], ReversePath), !,
    reverse(ReversePath, Path).

variable_path(Term, Var, Path, Path) :-
    var(Term),
    Term == Var, !.
variable_path(Term, Var, Prefix, Path) :-
    compound(Term),
    functor(Term, _, Arity),
    between(1, Arity, Index),
    arg(Index, Term, Arg),
    variable_path(Arg, Var, [Index|Prefix], Path).

%Graft the call's argument onto the fresh copy of the equation's head
%argument, position by position, stopping wherever either side stops being a
%list. A position the call leaves unbound is left alone, and a length mismatch
%fails the whole graft, which is what makes the enclosing plan skip that
%argument.
%
%First-order on purpose. This carried the binding step as a yall lambda and
%metacalled it once per position, which is the defect
%tests/prolog/static_checks.pl states as compile_time_helper('>>') -- there
%over GENERATED bodies, here in the translator's own plan path. '>>'/4
%copy_term_nats the lambda and rebuilds the call with =../2 on every metacall,
%and the first metacall in a process resolves that machinery once
%[measured 2026-08-26: 23,940 inferences for the first metacall and 14 for
%each later one, against 2 for a named predicate; command=swipl -g
%"use_module(library(yall)), P = [A,V]>>(nonvar(V) -> V = A ; true),
%statistics(inferences,I0), call(P,_,abc), statistics(inferences,I1)";
%commit=WORKTREE]. Under deferred translation that one-time resolution landed
%on whichever equation first reached a binding plan, so a user's first
%match-bearing call paid it: the first call of a body holding
%(once (match ...)) read 3,676 inferences with the lambda and 2,163 without,
%second calls 423 either way, and the arrival cost of a match-bearing equation
%stays flat as the program grows [measured 2026-08-26: 2,215 for that first
%call with 10, 40, 160 and 640 other translated equations in the space;
%commit=WORKTREE]
%[tested: specializer:the_argument_walk_makes_no_metacall_per_position;
%commit=WORKTREE].
traverse_list(From, Into) :-
    (   is_list(From), is_list(Into)
    ->  maplist(traverse_list, From, Into)
    ;   nonvar(Into)
    ->  Into = From
    ;   true
    ).

% Select and unify variables used as higher-order operands. The six-argument
% form also retains their structural paths for the global specialization key.
eligible_var_pairs(Vars, Copies, BodyExpr, HoVars) :-
    same_length(Vars, Paths),
    maplist(=([]), Paths),
    eligible_var_pairs(Vars, Copies, Paths, BodyExpr, HoVars, _).

eligible_var_pairs([], [], [], _, [], []).
eligible_var_pairs([Var|Vars], [Copy|Copies], [Path|Paths], BodyExpr,
                   HoVars, Bindings) :-
    ( specializable_arg(Copy),
      specialization_use(Var, BodyExpr, Use)
      -> Var = Copy,
         HoVars = [Var|RestHoVars],
         Bindings = [path_binding(Path, Copy, Use)|RestBindings]
    ; HoVars = RestHoVars,
      Bindings = RestBindings ),
    eligible_var_pairs(Vars, Copies, Paths, BodyExpr,
                       RestHoVars, RestBindings).

specialization_use(Var, BodyExpr, direct) :-
    var_use_check(head, Var, BodyExpr), !.
specialization_use(Var, BodyExpr, propagated) :-
    var_use_check(ho, Var, BodyExpr).

%If Var appears at list head it means function call, meaning specialization is needed, and detect when used as HOL arg
var_use_check(head, Var, [Head|_]) :- Var == Head.
var_use_check(ho, Var, [Head|Args]) :- specializable_arg(Head),
                                       member(Arg, Args),
                                       ( Var == Arg
                                       ; is_list(Arg),
                                         var_use_check(ho, Var, Arg) ).
var_use_check(Mode, Var, L) :- is_list(L),
                               member(E, L),
                               is_list(E),
                               var_use_check(Mode, Var, E).

%Tests whether an argument represents a specializable function or partial application:
specializable_arg(Arg) :- nonvar(Arg), 
                          ( fun(Arg) ; Arg = partial(_, _) ).

%Whether reading the equations can possibly be worth it, decided from the
%CALL's arguments and their outer shape alone.
%
%A binding needs specializable_arg/1 to hold of a sub-term of some argument,
%the one aligned with an equation's head variable. An ATOMIC argument has no
%sub-terms but itself, so a call whose arguments are every one atomic, and none
%of them a function name or a partial, cannot produce a binding whatever the
%equations look like. A compound argument can hide one at any depth, so it is
%admitted without being walked; walking it is what made an earlier version of
%this precondition a net loss, since a long data argument cost Theta(its size)
%where the equations cost O(1) a position.
%
%This is the only cheap discriminator there is. The equation-side twin was
%measured and is nearly useless: of the 73,642 calls that walked every equation
%and produced nothing, 72,594 were on functions that DO have a specializable
%equation, and it is the arguments that fail. This refuses 73,070 of those
%73,642, 99.2%, and every one of the 318 calls that produced a plan passes it
%[measured 2026-08-23 over the 253 shipped example programs].
%Written as its own recursion rather than member/2 plus a cut, so an argument
%that settles it costs one inference and compound/1 costs none.
call_may_specialize([Arg|Args]) :-
    (   compound(Arg)
    ->  true
    ;   specializable_arg(Arg)
    ->  true
    ;   call_may_specialize(Args)
    ).

%Forget a specialization, IN ONE MODULE. It is keyed by name and by module
%because a specialization is: ho_specialization/3 records both, and the same
%generated name exists in two modules the moment two spaces specialize the
%same call. Keyed by name alone, forgetting the clone one space no longer
%needs removed the OTHER space's clauses and, through remove_sexp/2, the
%other space's stored equation with them: dropping a space that had been
%copied from &self took atoms out of &self
%[tested: specializer_invalidation:writing_in_one_space_leaves_another_alone,
%test_adding_in_one_space_never_removes_atoms_from_another].
%
%The clauses are in the module of the space whose code triggered the
%specialization, which is what specialize_call_locked/7 registers. Asking
%current_predicate/1 and clause/3 UNQUALIFIED read the engine's own module,
%which found &self's clauses only for as long as &self WAS that module and
%never found a named space's at all. A stale specialization then outlived the
%equation it cloned and answered beside the new one: removing one of two
%equations for a higher-order function gave (2 2 42) where (2) was asked for
%[tested: examples/functions/functionremoval.metta,
%specializer:a_removed_equation_forgets_its_specialization].
%
%clause_property(module/1) is the filter that keeps this from erasing a
%PARENT's clauses: clause/3 sees inherited ones through the base chain, and a
%named space asking to forget a name &self defines must not erase &self's.
forget_symbol(Module, Name) :-
    metta_module_space(Module, Space),
    remove_sexp(Space, [=, [Name|_], _]),
    remove_sexp(Space, [':', Name, _]),
    findall(Ref,
            ( current_predicate(Module:Name/A),
              functor(H, Name, A),
              predicate_property(Module:H, number_of_clauses(_)),
              clause(Module:H, _, Ref),
              clause_property(Ref, module(Module)) ),
            Refs0),
    sort(Refs0, Refs),
    %The provenance record dies with the clause it names. Erasing without
    %retracting it left translated_from/2 pointing at a dead reference, and
    %remove_equation/6 then found that reference, called erase/1 on it and
    %FAILED, so removing the specialization's own atom failed and every caller
    %of it failed with it [tested: bindings/python/tests/test_import_reuse.py::
    %test_import_translation_leaves_variable_heads_dynamic].
    forall(member(R, Refs),
           (   translated_from(R, Term)
           ->  forget_translated_from(Module, R, Term),
               erase(R)
           ;   erase(R)
           )),
    %Withdraw the ownership rows before invalidating the generated function's
    %own dependents. A compatibility cycle can otherwise re-enter this action
    %through the opposite row before either side has retired.
    retractall(ho_specialization(Module, Name, _)),
    retractall(ho_specialization(Module, _, Name)),
    support_invalidate(function(Module, Name)),
    %announce_function_removed/1 rather than the bare event: the recompile of the
    %dependents rides in the engine now, so this path repairs compiled
    %mentions even when no host installed an observer.
    announce_function_removed(Name),
    unregister_fun_in(Module, Name),
    %The name-wide registers go only when NO module still defines it, because
    %the same generated name can belong to two spaces at once. Name-wide means
    %EVERY module here, retained equations included: this branch is reached
    %when nothing defines the name anywhere, so a module keeping its equations
    %would leave the specializer able to plan from equations no clause backs.
    (   function_still_defined(Name)
    ->  true
    ;   retractall(arity(Name, _)),
        retractall(fun(Name)),
        clear_fun_meta(_, Name)
    ),
    support_forget(function(Module, Name)),
    support_forget(specialization(Module, Name)).

% Compatibility name for callers that used to enter the specializer's bespoke
% recursive walk. The common graph now reaches specializations, memo entries
% and compiled dependents in one cycle-safe traversal, then this public entry
% lets each artifact family perform its deferred repair.
invalidate_specializations(Module, F) :-
    prepare_specialization_invalidation(Module, F),
    support_invalidate(function(Module, F)),
    forall(support_repair_invalidations, true).

prepare_specialization_invalidation(Module, F) :-
    retractall(ho_specialization_failed(_,_,_)),
    ensure_specialization_supports(Module, F).

% Existing hosts may have asserted ho_specialization/3 through its long-lived
% compatibility surface. Backfill that module once when such a row has no
% support edge; ordinary specializations record the edge at publication.
ensure_specialization_supports(Module, F) :-
    ho_specialization(Module, F, Spec),
    \+ supports(function(Module, F), specialization(Module, Spec)),
    !,
    forall(ho_specialization(Module, Source, Name),
           record_specialization_support(Module, Source, Name)).
ensure_specialization_supports(_, _).
