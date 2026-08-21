% Purpose: verify higher-order specialization keys, per-clause bindings, and
%   recursive folding directly against generated Prolog clauses.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).

:- begin_tests(specializer).

set_specializer_test_mode :-
    retractall(silent(_)),
    assertz(silent(true)).

cleanup_specializer_symbols(Names) :-
    metta_self_module(Module),
    forall(member(Name, Names),
           ( invalidate_specializations(Module, Name),
             forget_symbol(Module, Name) )),
    retractall(silent(_)),
    assertz(silent(false)).

load_specializer_regression(File, Results) :-
    directory_file_path('../regression', File, Path),
    load_metta_file(Path, Results).

setup_concurrent_specialization :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-race-inc $x) (+ $x 1))\n
(= (plunit-spec-race $f $x) ($f $x))\n
", _).

cleanup_concurrent_specialization :-
    cleanup_specializer_symbols(
        ['plunit-spec-race', 'plunit-spec-race-inc']).

run_concurrent_specialization(_) :-
    translate_expr(
        ['plunit-spec-race', 'plunit-spec-race-inc', 1], Goals, Out),
    goals_list_to_conj(Goals, Goal),
    %A specialization is compiled into the module of the space whose code
    %triggered it, so a test that calls or reads it has to name that module.
    metta_self_module(Self),
    once(call(Self:Goal)),
    Out == 2.

test(concurrent_translation_creates_one_specialization,
     [ setup(setup_concurrent_specialization),
       cleanup(cleanup_concurrent_specialization) ]) :-
    concurrent_forall(between(1, 64, Worker),
                      run_concurrent_specialization(Worker),
                      [threads(64)]),
    findall(SpecName,
            ho_specialization(_, 'plunit-spec-race', SpecName),
            Specializations),
    Specializations = [SpecName],
    functor(Head, SpecName, 3),
    metta_self_module(Self),
    aggregate_all(count, clause(Self:Head, _), 1),
    aggregate_all(count,
                  get_native_atom('&self', [=, [SpecName|_], _]),
                  1).

setup_multiclause :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-inc $x) (+ $x 1))\n
(= (plunit-spec-t2 $f 0) ($f 100))\n
(= (plunit-spec-t2 $f $x) ($f ($f $x)))\n
", _),
    process_metta_string("!(plunit-spec-t2 plunit-spec-inc 5)", [7]).

cleanup_multiclause :-
    cleanup_specializer_symbols(['plunit-spec-t2', 'plunit-spec-inc']).

test(all_clauses_are_bound_independently,
     [setup(setup_multiclause), cleanup(cleanup_multiclause)]) :-
    ho_specialization(_, 'plunit-spec-t2', SpecName),
    SpecName == 'plunit-spec-t2_Spec_[plunit-spec-inc]',
    functor(Head, SpecName, 3),
    metta_self_module(Self),
    findall(Head-Body, clause(Self:Head, Body), Clauses),
    length(Clauses, 2),
    forall(member(ClauseHead-_, Clauses),
           arg(1, ClauseHead, 'plunit-spec-inc')),
    \+ ( member(_-ClauseBody, Clauses),
         sub_term(Reduce, ClauseBody),
         compound(Reduce),
         functor(Reduce, reduce, 2) ),
    process_metta_string("!(plunit-spec-t2 plunit-spec-inc 0)", [101, 2]).

setup_two_bindings :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-inc2 $x) (+ $x 1))\n
(= (plunit-spec-dbl2 $x) (* $x 2))\n
(= (plunit-spec-p2 $f $g 1) ($f 1))\n
(= (plunit-spec-p2 $f $g 2) ($g 2))\n
", _),
    process_metta_string(
        "!(plunit-spec-p2 plunit-spec-inc2 plunit-spec-dbl2 1)", [2]).

cleanup_two_bindings :-
    cleanup_specializer_symbols(
        ['plunit-spec-p2', 'plunit-spec-dbl2', 'plunit-spec-inc2']).

test(global_key_covers_every_specialized_argument_position,
     [setup(setup_two_bindings), cleanup(cleanup_two_bindings)]) :-
    ho_specialization(_, 'plunit-spec-p2', SpecName),
    SpecName ==
        'plunit-spec-p2_Spec_[plunit-spec-inc2,plunit-spec-dbl2]',
    functor(Head, SpecName, 4),
    metta_self_module(Self),
    findall(Body, clause(Self:Head, Body), Bodies),
    length(Bodies, 2),
    \+ ( member(Body, Bodies),
         sub_term(Reduce, Body),
         compound(Reduce),
         functor(Reduce, reduce, 2) ).

setup_recursive :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-step $x) (+ $x 1))\n
(= (plunit-spec-rep $f 0 $x) $x)\n
(= (plunit-spec-rep $f $n $x)\n
   (if (> $n 0)\n
       (plunit-spec-rep $f (- $n 1) ($f $x))\n
       (empty)))\n
", _),
    process_metta_string("!(plunit-spec-rep plunit-spec-step 3 0)", [3]).

cleanup_recursive :-
    cleanup_specializer_symbols(['plunit-spec-rep', 'plunit-spec-step']).

test(exact_recursive_key_folds_to_specialized_predicate,
     [setup(setup_recursive), cleanup(cleanup_recursive)]) :-
    ho_specialization(_, 'plunit-spec-rep', SpecName),
    functor(Head, SpecName, 4),
    metta_self_module(Self),
    forall(clause(Self:Head, Body),
           \+ ( sub_term(GenericCall, Body),
                compound(GenericCall),
                functor(GenericCall, 'plunit-spec-rep', 4) )),
    Goal =.. [SpecName, 'plunit-spec-step', 1000, 0, Result],
    once(call(Self:Goal)),
    Result == 1000.

% The test above checks that the recursive step does not name the generic
% predicate. reduce/2 is the OTHER way back to it, at run time and under a
% functor the clause body never mentions, so the absence of one is a separate
% question. It is asked of the two-binding specialization at
% global_key_covers_every_specialized_argument_position and was asked of the
% recursive one nowhere.
%
% Measured 2026-08-18, min of three: the specialized predicate costs 8,004
% inferences over 1,000 steps against the generic path's 24,004, and 804
% against 2,404 over 100, so the saving is per step rather than one-off.
test(the_recursive_specialization_never_re_enters_the_reducer,
     [setup(setup_recursive), cleanup(cleanup_recursive)]) :-
    ho_specialization(_, 'plunit-spec-rep', SpecName),
    functor(Head, SpecName, 4),
    metta_self_module(Self),
    findall(Body, clause(Self:Head, Body), Bodies),
    %The base case and the recursive one. Counted rather than left open,
    %because "no clause holds a reduce/2" is vacuously true of a predicate
    %with no clauses, which is what a specialization that failed to publish
    %would leave behind.
    length(Bodies, 2),
    \+ ( member(Body, Bodies),
         sub_term(Reduce, Body),
         compound(Reduce),
         functor(Reduce, reduce, 2) ).

setup_failed_specialization_memo :-
    set_specializer_test_mode,
    load_specializer_regression(
        'repro1_failed_specialization_memo.metta', [1, 2, 3, 4, 5]).

cleanup_failed_specialization_memo :-
    cleanup_specializer_symbols([wrap, pass, wrap2, myfun]).

test(repeated_failed_specialization_is_recorded_once_per_function,
     [ setup(setup_failed_specialization_memo),
       cleanup(cleanup_failed_specialization_memo) ]) :-
    findall(F-Arity-Key,
            ho_specialization_failed(F, Arity, Key),
            Failures),
    Failures == [pass-3-[myfun], wrap-3-[myfun]].

setup_failed_specialization_chain :-
    set_specializer_test_mode,
    load_specializer_regression(
        'repro2_exponential_failed_specialization.metta', [1]).

cleanup_failed_specialization_chain :-
    findall(Name,
            ( between(1, 12, Index),
              atom_concat(f, Index, Name) ),
            Functions),
    append(Functions, [g, myfun], Names),
    cleanup_specializer_symbols(Names).

test(branching_failed_specialization_is_linear_in_chain_depth,
     [ setup(setup_failed_specialization_chain),
       cleanup(cleanup_failed_specialization_chain) ]) :-
    aggregate_all(count, ho_specialization_failed(_, _, _), 11),
    forall(between(1, 11, Index),
           ( atom_concat(f, Index, Function),
             ho_specialization_failed(Function, 3, [myfun]) )).

setup_failed_specialization_type :-
    set_specializer_test_mode,
    load_specializer_regression(
        'repro3_failed_specialization_self_leak.metta', _).

cleanup_failed_specialization_type :-
    cleanup_specializer_symbols([wrap, wrap2, myfun]).

test(failed_specialization_does_not_leak_generated_type,
     [ setup(setup_failed_specialization_type),
       cleanup(cleanup_failed_specialization_type) ]) :-
    once(get_native_atom(
        '&self', [':', wrap, ['->', 'Number', 'Number', 'Number']])),
    ho_specialization_failed(wrap, 3, [myfun]),
    \+ ( get_native_atom('&self', [':', Name, _]),
         atom(Name),
         sub_atom(Name, 0, _, _, 'wrap_Spec_') ).

:- dynamic variant_normalization_preexisting_lambda/1.

setup_variant_normalization :-
    retractall(silent(_)),
    assertz(silent(false)),
    %Snapshot the lambdas that exist BEFORE the repro runs: the engine
    %prelude compiles a foldl lambda of its own at boot, and sweeping
    %every lambda_ name in cleanup would unregister the prelude's.
    retractall(variant_normalization_preexisting_lambda(_)),
    forall(( fun(Name), atom(Name), sub_atom(Name, 0, _, _, lambda_) ),
           assertz(variant_normalization_preexisting_lambda(Name))).

cleanup_variant_normalization :-
    findall(Name,
            ( fun(Name),
              atom(Name),
              sub_atom(Name, 0, _, _, lambda_),
              \+ variant_normalization_preexisting_lambda(Name) ),
            LambdaNames),
    retractall(variant_normalization_preexisting_lambda(_)),
    cleanup_specializer_symbols([app|LambdaNames]).

test(compound_partial_key_has_stable_anonymous_variables,
     [ setup(setup_variant_normalization),
       cleanup(cleanup_variant_normalization) ]) :-
    with_output_to(
        string(Output),
        catch(load_specializer_regression(
                  'repro4_variant_normalization.metta', _),
              Error,
              true)),
    %The fixture's (+ $y $z) leaves the addend and the result both unbound,
    %which the arithmetic refusal names: two unknowns, no finite domain.
    Error = error(petta_unsolved_arithmetic('+', unbounded_domain), _),
    %The subject here is the STABLE `_` in the variant key, not the
    %lambda's index: boot-time compiles (the engine prelude's own foldl
    %lambda among them) advance the shared sequence before this file
    %loads, so the index is whatever the boot left. Match the key by its
    %stable frame and recover the actual name from the output.
    re_matchsub("app_Spec_\\[partial\\(lambda_\\d+,\\[_\\]\\)\\]",
                Output, Sub, []),
    get_dict(0, Sub, SpecStr),
    atom_string(SpecName, SpecStr),
    \+ ho_specialization(_, app, _),
    \+ fun(SpecName),
    \+ arity(SpecName, _),
    \+ fun_meta_clause(_, SpecName, _, _),
    functor(SpecHead, SpecName, 3),
    \+ clause(SpecHead, _),
    \+ get_native_atom('&self', [=, [SpecName|_], _]).

setup_named_space_specialization :-
    set_specializer_test_mode,
    process_metta_string("\n
(= (plunit-spec-ns-bump $n) (+ $n 1))\n
(= (plunit-spec-ns-twice $f $x) ($f ($f $x)))\n
", _, '&plunit_spec_ns').

cleanup_named_space_specialization :-
    cleanup_specializer_symbols(['plunit-spec-ns-twice', 'plunit-spec-ns-bump']),
    clear_native_atoms('&plunit_spec_ns').

test(higher_order_code_runs_inside_a_named_space,
     [ setup(setup_named_space_specialization),
       cleanup(cleanup_named_space_specialization) ]) :-
    % The generated clause used to be asserted into user, where the space's
    % own functions do not exist, so this crashed on its first call with
    % Unknown procedure: plunit-spec-ns-bump/2.
    process_metta_string("!(plunit-spec-ns-twice plunit-spec-ns-bump 0)",
                         [2], '&plunit_spec_ns').

:- end_tests(specializer).

:- begin_tests(specializer_invalidation).

% invalidate_specializations/2 recurses through ho_specialization/3 and
% retracts only AFTER descending, so a cycle among those facts would not
% terminate. It is called unguarded from three engine write sites and, since
% the register-an-operation path stopped swallowing its failures, from there
% too, where a hang is worse than the swallowed failure it replaced.
%
% No cycle is reachable today, because the recursive-specialization fold
% reuses the active name rather than recording a new fact. This constructs one
% directly, which is the only way to exercise the guard at all: without the
% visited set the goal below does not return.
% Both facts are planted in ONE module, which is the only shape the cycle can
% take now that the walk is scoped to the writing space's module.
test(an_invalidation_cycle_terminates,
     [ setup(( metta_self_module(M),
               assertz(user:ho_specialization(M, plunit_cycle_a,
                                              plunit_cycle_b)),
               assertz(user:ho_specialization(M, plunit_cycle_b,
                                              plunit_cycle_a)) )),
       cleanup(( retractall(user:ho_specialization(_, plunit_cycle_a, _)),
                 retractall(user:ho_specialization(_, plunit_cycle_b, _)) )) ]) :-
    metta_self_module(Self),
    call_with_inference_limit(invalidate_specializations(Self, plunit_cycle_a),
                              100000, Outcome),
    assertion(Outcome \== inference_limit_exceeded),
    assertion(\+ user:ho_specialization(_, plunit_cycle_a, _)),
    assertion(\+ user:ho_specialization(_, plunit_cycle_b, _)).

test(a_tabled_function_never_specializes,
     [ setup(( sread("(= (spt-loop $x $y) (spt-loop $y $x))", Eq),
               add_sexp('&self', Eq),
               translate_clause(Eq, Clause),
               assertz(Clause),
               assertz(fun('spt-loop')),
               assertz(arity('spt-loop', 3)),
               add_sexp('&petta', [tabled, '&self', 'spt-loop', 2]) )),
       cleanup(( remove_sexp('&petta', [tabled, '&self', 'spt-loop', 2]),
                 remove_sexp('&self', [=, ['spt-loop'|_], _]),
                 retractall(fun('spt-loop')),
                 retractall(arity('spt-loop', _)) )) ]) :-
    % The reflection fact says spt-loop is tabled, so a call whose
    % argument names a defined function must NOT plan a specialization:
    % the clone would carry the recursion without the tabling. The
    % 27,525-frame precedent is recorded at maybe_specialize_call.
    \+ maybe_specialize_call('spt-loop', [d, x], _, _).

test(string_run_equation_invalidates_specializations,
     [ setup(( metta_self_module(M),
                assertz(user:ho_specialization(M, 'plunit-door-fn',
                                               plunit_door_spec)) )),
       cleanup(( retractall(user:ho_specialization(_, 'plunit-door-fn', _)),
                 remove_sexp('&self', [=, ['plunit-door-fn'|_], _]),
                 retractall(fun('plunit-door-fn')),
                 retractall(arity('plunit-door-fn', _)) )) ]) :-
    % The string-run door (process_form/3) used to notify
    % metta_on_function_changed and skip invalidate_specializations, so a
    % specialization of a name survived new equations for it. The one
    % compile door notifies completely; this pins that a run-defined
    % equation retracts the stale specialization record.
    process_metta_string("(= (plunit-door-fn $x) $x)", _),
    \+ user:ho_specialization(_, 'plunit-door-fn', _).

test(a_recursive_specialization_survives_its_compile,
     [ cleanup(( remove_sexp('&self', [=, ['plunit-tricky'|_], _]),
                 retractall(fun('plunit-tricky')),
                 retractall(arity('plunit-tricky', _)),
                 metta_self_module(M),
                 invalidate_specializations(M, 'plunit-tricky') )) ]) :-
    % A definition whose body calls ITSELF with a ground higher-order
    % argument compiles a clone for that call and a generic clause that
    % names it. Invalidating after the compile abolished that clone while
    % the clause naming it stood, so the generic path called an empty
    % predicate: the direct call still answered through its own
    % specialization, and a call arriving through a variable answered
    % NOTHING. Stale clones are dropped BEFORE the body compiles now.
    process_metta_string(
        "(= (plunit-tricky $f) (if (= ($f 1) 2) (plunit-tricky (+ 2)) ($f 1)))",
        _),
    process_metta_string("!(plunit-tricky (+ 1))", [Direct]),
    assertion(Direct == 3),
    process_metta_string("!(let $g (+ 1) (plunit-tricky $g))", [ViaVariable]),
    assertion(ViaVariable == 3).

% Forgetting a specialization has to take its PROVENANCE with its clauses and
% its source atoms out of the space that holds them. It erased the clauses and
% left translated_from/2 naming the dead references, so removing the
% specialization's own atom found one, called erase/1 on it, and FAILED: every
% caller of the removal failed with it, and dropping a Python space that had
% specialized a higher-order function raised
% "the engine refused petta_py_clear". And it removed the source atoms from
% '&self' by name while the specializer writes them into the space that
% triggered it, so a named space kept the atoms of a specialization whose
% clauses were gone.
test(a_removed_equation_forgets_its_specialization,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(member(E, [['plunit-forget'|_], ['plunit-forget-inc'|_],
                                   ['plunit-forget-use'|_]]),
                        remove_sexp('&plunit_spec_forget', [=, E, _])),
                 space_module('&plunit_spec_forget', M),
                 forall(member(N, ['plunit-forget', 'plunit-forget-inc',
                                   'plunit-forget-use']),
                        ( invalidate_specializations(M, N),
                          forget_symbol(M, N) )),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    Space = '&plunit_spec_forget',
    space_module(Space, Module),
    'add-atom'(Space, [=, ['plunit-forget-inc', X], ['+', X, 1]], _),
    'add-atom'(Space, [=, ['plunit-forget', F, Y], [F, Y]], _),
    % The call site with a ground higher-order argument is what makes the
    % specializer clone plunit-forget, and it is compiled into THIS space's
    % module, not the engine's.
    'add-atom'(Space, [=, ['plunit-forget-use', Z],
                          ['plunit-forget', 'plunit-forget-inc', Z]], _),
    with_metta_module(Module, reduce(['plunit-forget-use', 1], Answer, _)),
    assertion(Answer == 2),
    ho_specialization(Module, 'plunit-forget', SpecName),
    % The clone, its provenance and its source atom all exist first, so the
    % check below is about them going rather than about them never arriving.
    functor(SpecHead, SpecName, 3),
    assertion(( clause(Module:SpecHead, _, SpecRef),
                clause_property(SpecRef, module(Module)) )),
    assertion(get_native_atom(Space, [=, [SpecName|_], _])),
    % Removing the equation the clone came from forgets it.
    'remove-atom'(Space, [=, ['plunit-forget', F2, Y2], [F2, Y2]], _),
    assertion(\+ ho_specialization(Module, 'plunit-forget', _)),
    assertion(\+ ( clause(Module:SpecHead, _, R2),
                   clause_property(R2, module(Module)) )),
    % No dangling provenance is left behind, which is the half that made the
    % next removal fail.
    assertion(\+ ( translated_from(Ref, [=, [SpecName|_], _]),
                   \+ catch(clause_property(Ref, module(_)), _, fail) )),
    % And the source atom went out of the space that held it, not out of &self.
    assertion(\+ get_native_atom(Space, [=, [SpecName|_], _])).

% The verifying mode runs the clone and the generic function it was cloned
% from and compares their whole answer sets. Both live in the module of the
% space that triggered the specialization, and both used to be called from
% the engine's module, so with &self no longer being that module every
% specialization in the corpus raised existence_error under the mode that
% exists to prove they agree.
test(the_verifier_runs_a_clone_in_its_own_module,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(member(E, [['plunit-verify'|_], ['plunit-verify-inc'|_],
                                   ['plunit-verify-use'|_]]),
                        remove_sexp('&plunit_spec_verify', [=, E, _])),
                 space_module('&plunit_spec_verify', M),
                 forall(member(N, ['plunit-verify', 'plunit-verify-inc',
                                   'plunit-verify-use']),
                        ( invalidate_specializations(M, N),
                          forget_symbol(M, N) )),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    Space = '&plunit_spec_verify',
    space_module(Space, Module),
    'add-atom'(Space, [=, ['plunit-verify-inc', X], ['+', X, 1]], _),
    'add-atom'(Space, [=, ['plunit-verify', F, Y], [F, Y]], _),
    'add-atom'(Space, [=, ['plunit-verify-use', Z],
                          ['plunit-verify', 'plunit-verify-inc', Z]], _),
    with_metta_module(Module, reduce(['plunit-verify-use', 1], _, _)),
    ho_specialization(Module, 'plunit-verify', SpecName),
    SpecGoal =.. [SpecName, 'plunit-verify-inc', 1, Out],
    % Qualified the way a compiled clause in that module qualifies it, which
    % is what the meta_predicate declaration on the verifier produces.
    petta_verified_specialization(SpecName, Module:SpecGoal),
    assertion(Out == 2),
    assertion(ho_specialization_agrees(SpecName)).

% A specialization belongs to the space whose code triggered it, and
% ho_specialization/3 has said so in its first argument since it was written.
% invalidate_specializations/2's predecessor read that argument with a WILDCARD, so adding an
% equation for a name in ANY space invalidated that name's specializations in
% EVERY space: their compiled clauses went, and so did the equations
% specialize_call_locked/7 stores into each space, which is a write in one
% space changing another space's atom count.
%
% Reproduced through MeTTa.copy(), which enumerates &self and re-adds every
% atom into a fresh space: re-adding the base equation there stripped four spec
% atoms from &self, so the SOURCE of a copy lost atoms to the copy. It was the
% suite's one known flake, 1 firing in 12 parallel runs, and no concurrency was
% involved.
%The copy door: MeTTa.copy() enumerates a space and re-adds every atom into
%a fresh one, generated specializations included. Compiling a copied
%specialization's body re-enters the specializer with no ho_specialization/3
%row behind the name, and regenerating there stored every specialization
%TWICE, the copies orphans nothing would invalidate. Adoption records the
%row instead: same atom count, one answer, and the clone's specializations
%are tracked again.
test(a_copied_space_adopts_its_specializations_instead_of_duplicating,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(member(S, ['&self', '&plunit_spec_clone']),
                        forall(member(N, ['plunit-copy-hof', 'plunit-copy-inc',
                                          'plunit-copy-use']),
                               remove_sexp(S, [=, [N|_], _]))),
                 forall(member(S, ['&self', '&plunit_spec_clone']),
                        ( space_module(S, M),
                          forall(member(N, ['plunit-copy-hof', 'plunit-copy-inc',
                                            'plunit-copy-use']),
                                 invalidate_specializations(M, N)) )),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    Clone = '&plunit_spec_clone',
    space_module('&self', SelfModule),
    space_module(Clone, CloneModule),
    'add-atom'('&self', [=, ['plunit-copy-inc', X], ['+', X, 1]], _),
    'add-atom'('&self', [=, ['plunit-copy-hof', F, Y], [F, Y]], _),
    'add-atom'('&self', [=, ['plunit-copy-use', Z],
                            ['plunit-copy-hof', 'plunit-copy-inc', Z]], _),
    with_metta_module(SelfModule, reduce(['plunit-copy-use', 1], Answer, _)),
    assertion(Answer == 2),
    spec_equation_count('&self', SelfSpecs),
    assertion(SelfSpecs > 0),
    findall(A, 'get-atoms'('&self', A), Atoms),
    forall(member(A, Atoms), 'add-atom'(Clone, A, _)),
    spec_equation_count(Clone, CloneSpecs),
    assertion(CloneSpecs == SelfSpecs),
    assertion(ho_specialization(CloneModule, 'plunit-copy-hof', _)),
    with_metta_module(CloneModule,
                      findall(Out, reduce(['plunit-copy-use', 5], Out, _),
                              CloneAnswers)),
    assertion(CloneAnswers == [6]),
    spec_equation_count(Clone, CloneSpecsAfter),
    assertion(CloneSpecsAfter == SelfSpecs).

spec_equation_count(Space, Count) :-
    findall(Name,
            ( 'get-atoms'(Space, [=, [Name|_], _]),
              atom(Name), sub_atom(Name, _, _, _, '_Spec_') ),
            Names),
    length(Names, Count).

test(writing_in_one_space_leaves_another_alone,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(member(S, ['&self', '&plunit_spec_other']),
                        forall(member(N, ['plunit-cross', 'plunit-cross-inc',
                                          'plunit-cross-use']),
                               remove_sexp(S, [=, [N|_], _]))),
                 forall(member(S, ['&self', '&plunit_spec_other']),
                        ( space_module(S, M),
                          forall(member(N, ['plunit-cross', 'plunit-cross-inc',
                                            'plunit-cross-use']),
                                 invalidate_specializations(M, N)) )),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    Other = '&plunit_spec_other',
    space_module('&self', SelfModule),
    'add-atom'('&self', [=, ['plunit-cross-inc', X], ['+', X, 1]], _),
    'add-atom'('&self', [=, ['plunit-cross', F, Y], [F, Y]], _),
    'add-atom'('&self', [=, ['plunit-cross-use', Z],
                            ['plunit-cross', 'plunit-cross-inc', Z]], _),
    with_metta_module(SelfModule, reduce(['plunit-cross-use', 1], Answer, _)),
    assertion(Answer == 2),
    % &self now holds the specialization and its stored equation.
    assertion(ho_specialization(SelfModule, 'plunit-cross', _)),
    atom_multiset('&self', Before),
    % The SAME equation written into another space, which is exactly what
    % MeTTa.copy() does when it re-adds an enumerated atom into a fresh space.
    'add-atom'(Other, [=, ['plunit-cross', F2, Y2], [F2, Y2]], _),
    atom_multiset('&self', After),
    assertion(After == Before),
    assertion(ho_specialization(SelfModule, 'plunit-cross', _)),
    % and the other direction: &self writing does not strip the other space
    'add-atom'(Other, [=, ['plunit-cross-inc', X2], ['+', X2, 2]], _),
    atom_multiset(Other, OtherBefore),
    'add-atom'('&self', [=, ['plunit-cross-inc', X3], ['+', X3, 1]], _),
    atom_multiset(Other, OtherAfter),
    assertion(OtherAfter == OtherBefore).

% A space's atoms as a comparable multiset. The store hands back a fresh copy
% each time, so the variables differ between two reads of the same atom and
% ==/2 on the raw terms compares nothing useful; numbervars over a copy makes
% two reads of one atom the same term and keeps two atoms that differ apart.
atom_multiset(Space, Sorted) :-
    findall(Ground,
            ( get_native_atom(Space, Atom),
              copy_term(Atom, Ground),
              numbervars(Ground, 0, _) ),
            Atoms),
    msort(Atoms, Sorted).

% The other direction of the same root, and the one that changes ANSWERS
% rather than atom counts. The specializer reads a function's retained
% equations to build the specialized clause, one clause per equation, and
% fun_meta_clause/4 was keyed by NAME alone: two spaces each defining
% plunit-two-map put two equations under that one key, so the space that
% specialized generated TWO identical clauses and answered its query twice.
% Measured at c7126f1 as well, so it is older than the module migration.
test(a_definition_in_another_space_does_not_double_an_answer,
     [ setup(( retractall(silent(_)), assertz(silent(true)) )),
       cleanup(( forall(member(S, ['&plunit_spec_two_a', '&plunit_spec_two_b']),
                        ( forall(member(N, ['plunit-two-map', 'plunit-two-inc',
                                            'plunit-two-use']),
                                 remove_sexp(S, [=, [N|_], _])),
                          space_module(S, M),
                          forall(member(N, ['plunit-two-map', 'plunit-two-inc',
                                            'plunit-two-use']),
                                 ( invalidate_specializations(M, N),
                                   clear_fun_meta(M, N) )) )),
                 retractall(silent(_)), assertz(silent(false)) )) ]) :-
    A = '&plunit_spec_two_a',
    B = '&plunit_spec_two_b',
    forall(member(S, [A, B]),
           ( 'add-atom'(S, [=, ['plunit-two-map', _F, _Y], [_F, _Y]], _),
             'add-atom'(S, [=, ['plunit-two-inc', _X], ['+', _X, 1]], _) )),
    'add-atom'(B, [=, ['plunit-two-use', Z],
                      ['plunit-two-map', 'plunit-two-inc', Z]], _),
    space_module(B, BModule),
    findall(Answer,
            with_metta_module(BModule, reduce(['plunit-two-use', 1], Answer, _)),
            Answers),
    assertion(Answers == [2]),
    %One specialized clause, not one per space that happens to share the name.
    ho_specialization(BModule, 'plunit-two-map', SpecName),
    functor(SpecHead, SpecName, 3),
    aggregate_all(count, clause(BModule:SpecHead, _), 1).

:- end_tests(specializer_invalidation).
