% Purpose: compile declared input and output types while preserving shared branch variables
% Assumes: engine/translator.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/translator.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/translator.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%Type function call generation, returns function call plus typechecks for input and output:
%Translate a call against every type declaration that fits it.
%
%A symbol may carry several declarations at different arities, which is
%ordinary nondeterminism over declarations rather than a conflict, so a
%declaration whose shape does not fit THIS call simply does not contribute a
%branch. Collecting the branches with findall is what makes that true. It was
%a maplist, which meant one inapplicable declaration failed the entire form:
%with both (: g (-> A Atom B)) and (: g (-> A Atom Number B)) declared,
%(g x y 1) did not translate at all, while the same two equations with no
%declarations worked [tested: translator_multi_arity_declarations].
%
%Failing when no branch fits is deliberate: the caller falls back to the
%untyped translation, which is what a call carrying no usable declaration
%should get.
%
%The branches are collected by recursion rather than findall/3, because
%findall COPIES its template and every branch has to keep sharing the caller's
%Out and argument variables. Collecting them with findall compiled cleanly and
%answered an unbound variable for every typed call.
typed_functioncall_dl(Fun, UniqueTypeChains, T, IsPartial, Bound, Out,
                      RuntimeArgs, BeforeCall, AfterHead, Goals) :-
    UniqueTypeChains \== [],
    %The arity guard below reads fun_meta rows, and a deferred function has
    %none until its equations translate: unforced, a declared 2-in name with
    %a 1-in equation compiled the ordinary typed branch instead of the
    %IncorrectNumberOfArguments refusal the arbiter pins. The dispatch
    %stage's own force runs too late for this decision.
    metta_ensure_compiled(Fun),
    length(T, NewInputArity),
    length(Bound, BoundArity),
    InputArity is BoundArity + NewInputArity,
    Arity is InputArity + 1,
    (   declared_arity_misses_existing_equation(Fun, UniqueTypeChains,
                                                 InputArity)
    ->  ( IsPartial -> append(Bound, T, Written) ; Written = T ),
        RuntimeArgs = T,
        AfterHead = [function_overapplication(Fun, Written, Out)|Goals]
    ;   incomplete_application_kind(Fun, Arity, ApplicationKind),
        ApplicationKind == overapplied,
        \+ metta_segment_equation(Fun)
    ->  ( IsPartial -> append(Bound, T, Written) ; Written = T ),
        RuntimeArgs = T,
        AfterHead = [function_overapplication(Fun, Written, Out)|Goals]
    ;   fitting_type_chains(UniqueTypeChains, InputArity, Selection),
        ( IsPartial -> append(Bound, T, Written) ; Written = T ),
        (   Selection = refused(Rule, Reason)
        ->  Refusal = ['Error', [Fun|Written],
                       ['TypingRuleRefusal', Rule, Reason]],
            RuntimeArgs = T,
            AfterHead = [Out = Refusal|Goals]
        ;   applicable_typed_branches(Selection, Fun, T, IsPartial, Bound,
                                      Out, RuntimeArgs, BeforeCall, Branches),
            Branches \== [],
            first_applicable_branch(Branches,
                                    dispatch_mismatch_result(Fun, Written, Out),
                                    Dispatch),
            AfterHead = [Dispatch|Goals]
        )
    ).

declared_arity_misses_existing_equation(Fun, Chains, InputArity) :-
    presented_type_chains(Chains, InputArity, []),
    %A refusal rule that declined this arity owns the answer: a user
    %arrow-arity rule's (TypingRuleRefusal Name Reason) must not be
    %overwritten by the generic count mismatch
    %[tested: test_a_user_typing_rule_participates_like_a_shipped_one].
    \+ type_chain_refusal(Chains, InputArity, _, _),
    current_metta_module(Module),
    fun_meta_module(Module, Fun, Owner),
    fun_meta_clause(Owner, Fun, Head, _),
    length(Head, InputArity),
    !.

%THE FIRST ARROW THAT ANSWERS IS THE ONE THAT ANSWERS, and the soft cut has to
%sit on each branch rather than around all of them. A flat disjunction under
%one `*->` commits to the GROUP, so a name carrying two declarations at the
%same arity ran both and answered the call once per declaration.
%
%That is a multiplicity divergence and multiplicity is specified: with
%`(: df (-> Atom %Undefined%))` and `(: df (-> Number %Undefined%))` declared
%over one equation, the arbiter answers `(quote (+ 1 2))` once, reading the
%FIRST declaration's mask, where this engine answered `(quote (+ 1 2))` and
%`(quote 3)` [measured 2026-08-24 against LeaTTa 9ea9f9d]. It is not a corner:
%loading the reference's own prelude beside minimal_metta_lib gives `function`
%two declarations, and `!(function (return 7))` answered `7, 7`, which is what
%made every strategy suite answer nothing once the duplicates compounded
%through recursion.
%
%The arity filter above already removed the WIDER-declaration case; this
%removes the same-arity one, and the two together are what
%`(ctxSigs env w op).head?` does in one step
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:3775].
%
%Each branch keeps its own soft cut, so a branch that answers keeps EVERY
%answer it has: a MeTTa function is nondeterministic and this must not become
%once/1.
first_applicable_branch([], Fallback, Fallback).
first_applicable_branch([Branch|Branches], Fallback, ( Branch *-> true ; Rest )) :-
    first_applicable_branch(Branches, Fallback, Rest).

%A declared call that no branch answered says WHY when the declaration is the
%reason: every rejection it makes, `(Error <call> (BadArgType <position>
%<expected> <actual>))`, against the arguments AS WRITTEN, which is the form
%the arbiter names and the one whose types decide
%[source: LeaTTa tests/semantics/types-basic/44-badargtype-per-actual.metta
%through 49-badargtype-widened-actuals.metta].
%
%It answers NOTHING when the declaration makes no rejection, so a call whose
%types check and whose equations do not match keeps this engine's own reading
%rather than gaining the arbiter's NotReducible: `(= (f 1) one)` then `!(f 2)`
%answers `[(f 2)]` there and nothing here, and that divergence is not this
%change's to make [measured 2026-08-19 against the arbiter]. The soft cut is
%what keeps the successful path unchanged: it commits to the branches whenever
%any of them answered.

%When some declaration has exactly this call's arity, only those apply. A
%wider declaration would otherwise also build a branch for a shorter call and
%answer the same thing twice: with (: g (-> A Atom B)) and
%(: g (-> A Atom Number B)) both declared, (g x y) answered (x y) twice.
%
%When NOTHING decides this arity the call is a partial application, and every
%declaration stays a candidate so currying keeps working. A named refusal is
%kept distinct from that absence; otherwise filtering it out would select the
%partial fallback and make an arrow-arity refusal behaviorally inert.
fitting_type_chains(Chains, InputArity, Fitting) :-
    presented_type_chains(Chains, InputArity, Exact),
    (   Exact \== []
    ->  Fitting = Exact
    ;   type_chain_refusal(Chains, InputArity, Rule, Reason)
    ->  Fitting = refused(Rule, Reason)
    ;   Fitting = Chains
    ).

%The full evaluator needs the same argument view as a compiled call, but it
%applies that view at run time before asking reduce/3 for one minimal step.
%The first signature decides, including the reference's raw-tail fallback for
%an arity that the arrow does not present.  With no signature every position
%evaluates.  Returning booleans keeps this boundary about evaluation only;
%the ordinary typed dispatcher still owns every argument check and rejection.
%[source: MettaHyperonFull/Minimal/Interpreter.lean:3760-3784 and 7394-7440,
%`argMask` and the argument fold in `mettaEval`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
metta_runtime_argument_mask(Fun, Arity, Mask) :-
    metta_runtime_first_signature(Fun, Signature),
    !,
    metta_runtime_parameter_types(Signature, Arity, Types),
    maplist(metta_runtime_parameter_evaluates, Types, Mask).
metta_runtime_argument_mask(_, Arity, Mask) :-
    length(Mask, Arity),
    maplist(=(true), Mask).

metta_runtime_first_signature(Fun, Signature) :-
    call_site_type_chains(Fun, [Signature|_]), !.
metta_runtime_first_signature(Fun, Signature) :-
    catch_recover(seam:builtin_type_declaration(Fun, Signature), fail),
    !.

metta_runtime_parameter_types([->|Types], Arity, Parameters) :-
    (   once(present_type_chain([->|Types], Arity, [->|Presented]))
    ->  append(Parameters, [_], Presented)
    ;   mask_prefix(Types, Arity, Parameters)
    ).

metta_runtime_parameter_evaluates(Type, false) :-
    non_evaluated_parameter_type(Type), !.
metta_runtime_parameter_evaluates(_, true).

%Result finality is the other half of the same first-signature convention.
%An Atom result is data even when its shape names another operation; every
%other result re-enters the full evaluator.
%[source: MettaHyperonFull/Minimal/Interpreter.lean:3786-3799 and 7451-7460,
%`returnsAtom` and its use in `mettaEval`; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
metta_runtime_returns_atom(Fun) :-
    metta_runtime_first_signature(Fun, [->|Types]),
    append(_, [Declared], Types),
    declared_type_for_evaluation(Declared, View),
    View == 'Atom'.

type_chain_takes(InputArity, [->|Types]) :-
    present_type_chain([->|Types], InputArity, _).

presented_type_chains([], _, []).
presented_type_chains([Chain|Chains], Arity, Presented) :-
    (   present_type_chain(Chain, Arity, Expanded)
    ->  Presented = [Expanded|Rest]
    ;   Presented = Rest
    ),
    presented_type_chains(Chains, Arity, Rest).

%A final `(%Rest% T)` formal absorbs every remaining argument and presents one
%copy of T per position.  Fixed arrows retain the existing arity typing rule,
%including provider refusals.
present_type_chain([->|Types], InputArity, [->|Presented]) :-
    append(Parameters, [Out], Types),
    (   append(Fixed, [Rest], Parameters),
        rest_parameter(Rest, Element)
    ->  length(Fixed, FixedArity),
        InputArity >= FixedArity,
        RestArity is InputArity - FixedArity,
        length(RestTypes, RestArity),
        maplist(=(Element), RestTypes),
        append(Fixed, RestTypes, PresentedParameters),
        append(PresentedParameters, [Out], Presented)
    ;   length(Parameters, DeclaredInputArity),
        current_metta_module(Module),
        typing_rule_accepts(Module, 'arrow-arity', InputArity,
                            DeclaredInputArity),
        Presented = Types
    ).

rest_parameter(Rest, Element) :-
    nonvar(Rest),
    Rest = [Marker, Element],
    nonvar(Marker),
    Marker == '%Rest%'.

type_chain_refusal(Chains, InputArity, Rule, Reason) :-
    member([->|Types], Chains),
    length(Types, Count),
    DeclaredInputArity is Count - 1,
    current_metta_module(Module),
    typing_rule_refusal(Module, 'arrow-arity', InputArity,
                        DeclaredInputArity, Rule, Reason),
    !.

applicable_typed_branches([], _, _, _, _, _, _, _, []).
applicable_typed_branches([TypeChain|Rest], Fun, T, IsPartial, Bound, Out,
                          RuntimeArgs, BeforeCall, Branches) :-
    (   typed_functioncall_branch(Fun, TypeChain, T, [], IsPartial, Bound, Out,
                                  RuntimeArgs, BeforeCall, BranchGoal)
    ->  Branches = [BranchGoal|More]
    ;   Branches = More
    ),
    applicable_typed_branches(Rest, Fun, T, IsPartial, Bound, Out,
                              RuntimeArgs, BeforeCall, More).

typed_functioncall_branch(Fun, TypeChain, T, GsH, IsPartial, Bound, Out,
                          RuntimeArgs, BeforeCall, BranchGoal) :-
    TypeChain = [->|Xs],
    append(ArgTypes0, [_OutType], Xs), !,
    drop_unconstraining_types(TypeChain, ArgTypes0, ArgTypes),
    metta_argument_type_origins(ArgTypes, ArgOrigins),
    argument_applicability_checks(T, ArgTypes, ArgOrigins, ApplicabilityChecks),
    translate_args_by_type(T, ArgTypes, GsT2, AVsTmp0, ArgChecks, Computed0),
    ( IsPartial -> append(Bound, AVsTmp0, AVsTmp) ; AVsTmp = AVsTmp0 ),
    append(GsH, ApplicabilityChecks, BeforeArgs),
    append(BeforeArgs, GsT2, InnerEval),
    %A declared result controls whether the produced atom re-enters evaluation;
    %it is not a dynamic filter on the produced value.  The requested result
    %type is checked by `metta`/`interpret` before dispatch.  Applying it here
    %made every mismatching user result disappear, including the reference's
    %`(-> Atom Variable)` function that deliberately returns 3.
    OutCheck = [],
    %NO RESULT CONTINUATION IS EMITTED HERE, and the reason is that this engine
    %compiles where the arbiter steps. The arbiter's `eval` applies one equation
    %and hands the instantiated right-hand side to `returnsAtom`, which sends it
    %back through evaluation; compiling that right-hand side has ALREADY done
    %exactly that one round. Adding a second is a double evaluation, measured:
    %`(: uf2 (-> Atom %Undefined%))` with `(= (uf2 $x) (cons-atom (+ 1 2) (b)))`
    %answers `((+ 1 2) b)` on the arbiter, because cons-atom's own `Atom` result
    %stops there, and a continuation at this call site answered `(3 b)`
    %[measured 2026-08-24 against LeaTTa 9ea9f9d].
    %
    %The one shape compilation does NOT cover is a body that emits no goals,
    %where nothing was evaluated at all; that is handled once, at the equation,
    %in translate_clause/3.
    %The checks are placed against an EMPTY prefix so the guard below can sit
    %between the argument evaluations and them. An argument that produced an
    %Error fails its own declared check -- an Error is not a Number -- and a
    %failed check takes the whole branch down, which is how
    %`(needs-number (+ 1 "bad"))` answered nothing where the arbiter answers
    %the inner error atom.
    place_type_checks(ArgTypes, '_', ArgChecks, OutCheck, [], AfterEval, Extra),
    typed_call_operands(Fun, Computed0, Guarded),
    build_call_or_partial_dl(Fun, AVsTmp, Out, CallGoals, [], Extra),
    append([AfterEval, BeforeCall, CallGoals], Checked),
    guard_error_arguments(Guarded, Out, Checked, AfterInnerEval, []),
    append(InnerEval, AfterInnerEval, CallGoalsList),
    GoalsList = [(RuntimeArgs = AVsTmp0)|CallGoalsList],
    goals_list_to_conj(GoalsList, BranchGoal).

%evaluated_argument_values/3's typed twin. A parameter the evaluation mask
%holds back (Atom, and any user type declared DontEvalType) receives the
%argument AS WRITTEN, so nothing was evaluated at that position and nothing
%there can have produced an Error: `(assertEqual (Error a b) (Error a b))`
%keeps comparing two Error atoms.
%An operation whose contract is to OBSERVE an error receives it as a value, so
%none of its operands is tested and none is recovered.
typed_call_operands(Fun, _, []) :- error_transparent_operation(Fun), !.
typed_call_operands(_, Computed, Computed).

%A shared raw type variable needs the whole written call checked before any
%argument runs. Earlier formals bind it and later formals consume that exact
%binding; ordinary chains retain the existing evaluate-then-check path.
argument_applicability_checks(Args, Types, Origins, Checks) :-
    memberchk(derived_variable, Origins),
    !,
    maplist(argument_applicability_check, Args, Types, Origins, Raw),
    goals_list_to_conj(Raw, Conj),
    Checks = [once(Conj)].
argument_applicability_checks(Args, Types, Origins, Checks) :-
    metatype_applicability_checks(Args, Types, Origins, Raw),
    commit_checks(Raw, Checks).

metatype_applicability_checks([], _, _, []).
metatype_applicability_checks([Argument|Arguments], [Type|Types],
                              [Origin|Origins], Checks) :-
    (   Origin == metatype,
        \+ unchecked_parameter_type(Type)
    ->  Checks = [check_argument_type(Argument, Type, Origin)|Rest]
    ;   Checks = Rest
    ),
    metatype_applicability_checks(Arguments, Types, Origins, Rest).

argument_applicability_check(Argument, Type, Origin,
                             check_argument_type(Argument, Type, Origin)).

%An argument whose declared type is a type variable occurring NOWHERE else in
%the chain constrains nothing, and its check is pure waste. The check is
%(has_type(A,T) *-> true ; get-metatype(A,T)), so with T unbound it enumerates
%the argument's types, binds T to the first, and cannot fail: get-metatype/2
%answers for every term. Nothing then reads T.
%
%(: == (-> $a $b Bool)) is the shape, and it is what the builtin type file
%declares for ==, != and =alpha. Measured 2026-08-15 over 1000 calls of a
%two-argument function: 683 inferences undeclared, 1620 declared with two free
%type variables, 1562 declared with concrete types. The free variables were
%the MOST expensive of the three, for checks that decide nothing.
%
%A variable occurring twice is a real constraint and stays: (-> $a $a Bool)
%requires both arguments to have a consistent type, and (-> $a Bool $a) ties an
%argument to the result. Only a bare singleton variable is dropped, so
%(-> (List $a) Bool) keeps its check on the list.
%A chain with no type variables at all has nothing to drop, and that is most
%of them: every arithmetic, comparison and math declaration in
%lib_builtin_types.metta is concrete. term_variables/2 answers that in one
%call, where the occurrence walk below cost 72 inferences per compiled call
%site [measured 2026-08-15].
drop_unconstraining_types(TypeChain, ArgTypes0, ArgTypes) :-
    term_variables(TypeChain, TypeVariables),
    (   TypeVariables == []
    ->  ArgTypes = ArgTypes0
    ;   type_variable_occurrences(TypeChain, Occurrences),
        maplist(drop_unconstraining_type(Occurrences), ArgTypes0, ArgTypes)
    ).

drop_unconstraining_type(Occurrences, Type, Dropped) :-
    (   var(Type),
        occurrence_count(Occurrences, Type, 1)
    ->  Dropped = '_'
    ;   Dropped = Type
    ).

%Every variable OCCURRENCE, duplicates kept, which is what term_variables/2
%cannot report.
type_variable_occurrences(Term, [Term]) :- var(Term), !.
type_variable_occurrences(Term, Occurrences) :-
    compound(Term),
    !,
    Term =.. [_|Args],
    maplist(type_variable_occurrences, Args, Lists),
    append(Lists, Occurrences).
type_variable_occurrences(_, []).

occurrence_count(Occurrences, Variable, Count) :-
    include(==(Variable), Occurrences, Same),
    length(Same, Count).

%One commit covers every check that constrains the same type variables.
%
%Where the output type shares no variable with the arguments, the argument
%checks commit as a group before the call, so an ill-typed call never runs the
%body, and the output check commits separately after it.
%
%Where the output shares one, as in (-> $a $a), committing before the call
%picks a witness the output cannot satisfy: with (: at A), (: at T), (: t T)
%and (= (testf at) t), the argument check binds $a to A and the answer t, of
%type T, is then rejected. Both halves solve together after the call instead,
%which is the only order in which a shared variable can be assigned
%consistently [tested: examples/types/types.metta,
%a_shared_type_variable_is_assigned_after_the_call].
place_type_checks(ArgTypes, OutType, ArgChecks, OutCheck, InnerEval, Inner, Extra) :-
    term_variables(ArgTypes, ArgVars),
    term_variables(OutType, OutVars),
    ( shares_a_variable(ArgVars, OutVars)
      -> Inner = InnerEval,
         append(ArgChecks, OutCheck, Both),
         commit_checks(Both, Extra)
       ; commit_checks(ArgChecks, Committed),
         append(InnerEval, Committed, Inner),
         Extra = OutCheck ).

commit_checks([], []) :- !.
commit_checks(Checks, [once(Conj)]) :- goals_list_to_conj(Checks, Conj).

shares_a_variable(As, Bs) :- member(A, As), member(B, Bs), A == B, !.

%Selectively apply translate_args for non-Expression args while Expression args stay as data input:
%The argument checks are collected and committed as ONE group, after the
%argument evaluations. Checking each argument under its own commit cannot
%satisfy a type variable the arguments share: the first witness for one
%argument binds it, and nothing backtracks to the assignment the next
%argument needs. Committing per argument loses answers, and not committing
%at all repeats them once per consistent assignment, so the group is the
%unit: find one assignment that satisfies every argument, then stop looking.
%The evaluations stay outside the commit, because a nondeterministic
%argument must keep every answer it produces
%[tested: a_parametric_expected_type_enumerates_its_witnesses,
%translator_typed_checks].
%Computed rides this walk for the same reason it rides
%translate_call_args_dl/5: asking a second time costs, and the answer is free
%here. It names the operand values this branch EVALUATED, which are the ones
%that can hold an error atom the call must hand on rather than consume.
translate_args_by_type([], _, [], [], [], []) :- !.
translate_args_by_type(Args, Types, GsOut, AVs, Checks, Computed) :-
    metta_argument_type_origins(Types, Origins),
    translate_args_by_type_dl(Args, Types, Origins,
                              GsOut, [], AVs, Checks, [], Computed).

translate_args_by_type_dl(Args, Types, Goals0, Goals, AVs) :-
    metta_argument_type_origins(Types, Origins),
    translate_args_by_type_dl(Args, Types, Origins,
                              Goals0, Tail, AVs, Checks, [], _),
    ( Checks == []
      -> Tail = Goals
       ; goals_list_to_conj(Checks, CheckConj),
         Tail = [once(CheckConj)|Goals] ).

translate_args_by_type_dl([], _, _, Goals, Goals, [], Checks, Checks, []) :- !.
translate_args_by_type_dl([A|As], [T|Ts], [Origin|Origins],
                          Goals0, Goals, [AV|AVs], Checks0, Checks, Computed) :-
    ( non_evaluated_parameter_type(T)
      -> AV = A,
         AfterArg = Goals0,
         %The argument was not evaluated, so nothing at this position can hold
         %an error this call has to hand on: Computed skips it either way.
         Computed = More,
         ( ( Origin == metatype ; unchecked_parameter_type(T) )
           -> AfterCheck = Checks0
           ;  declared_type_for_check(T, CheckType),
              metta_argument_type_origins([CheckType], [CheckOrigin]),
              type_check_goal(A, CheckType,
                              check_argument_type(A, CheckType, CheckOrigin),
                              MaskedGoal),
              Checks0 = [MaskedGoal|AfterCheck] )
    ; ( T == 'SpaceType'
        -> translate_space_expr_dl(A, Goals0, AfterArg, AV)
        ;  translate_eager_argument_dl(A, Goals0, AfterArg, AV) ),
      (   Goals0 == AfterArg
      ->  Computed = More
      ;   nonvar(AV)
      ->  Computed = More
      ;   error_reifying_argument(A)
      ->  Computed = More
      ;   Computed = [AV|More]
      ),
      ( ( Origin == metatype
        ; T == '%Undefined%' ; T == '_' ; statically_typed_literal(AV, T))
        -> AfterCheck = Checks0
      ; type_check_goal(AV, T,
                        check_argument_type(AV, T, Origin),
                        ArgGoal),
        Checks0 = [ArgGoal|AfterCheck] ) ),
    translate_args_by_type_dl(As, Ts, Origins, AfterArg, Goals, AVs,
                              AfterCheck, Checks, More).

%THE EVALUATION MASK, and its membership is the arbiter's own, read off the
%interpreter rather than inferred from probes. LeaTTa's `declaredTypeEvaluates`
%is one line and it names all three members:
%
%    metatype != Atom && metatype != Variable && metatype != Expression
%
%[source: LeaTTa MettaHyperonFull/Core/Modifiers.lean:118-124, consumed by
%`argMask` at MettaHyperonFull/Minimal/Interpreter.lean:3760-3784, whose own
%docstring reads "An argument is evaluated unless its declared evaluation view
%is `Atom`, `Variable`, or `Expression`"]. Symbol and Grounded are NOT members,
%which is the one boundary a probe alone could have got wrong: measured
%2026-08-24 against LeaTTa 9ea9f9d, `(: sf (-> Symbol %Undefined%))` with
%`(= (sf $x) (quote $x))` and `(= foo bar)` answers `(quote bar)`, so a Symbol
%parameter EVALUATES its argument.
%
%DontEvalType makes the same compiler decision declarative for user types.
%
%The mask decides EVALUATION only. Whether the position is also type-checked is
%unchecked_parameter_type/1 below, and the two are separate in the arbiter too:
%`argMask` chooses the operands to evaluate and `interpret-function-check-arg`
%checks each one against its formal
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:4760-4793].
non_evaluated_parameter_type(Type) :- Type == 'Atom', !.
non_evaluated_parameter_type(Type) :- Type == 'Variable', !.
non_evaluated_parameter_type(Type) :- Type == 'Expression', !.
non_evaluated_parameter_type(Type) :- type_position_modifier(Type, _, _), !.
non_evaluated_parameter_type(Type) :-
    nonvar(Type),
    catch_recover(type_declaration(Type, 'DontEvalType'), fail).

%A masked position whose declared type still DECIDES something keeps its check,
%and the check reads the argument AS WRITTEN, which is the term whose type the
%arbiter reports. Dropping it would turn two conforming answers into
%non-conforming ones: `(: ef (-> Expression %Undefined%))` answers
%`(Error (ef 5) (BadArgType 1 Expression Number))` and
%`(Error (ef "s") (BadArgType 1 Expression String))` on the arbiter
%[measured 2026-08-24 against LeaTTa 9ea9f9d].
%
%Atom decides nothing: it is the gradual top metatype, admitted against every
%actual type, so its check can only ever succeed and is the same foregone
%conclusion statically_typed_literal/2 removes elsewhere. A DontEvalType marker
%is a compiler instruction rather than a value type, so no runtime type could
%satisfy it.
unchecked_parameter_type(Type) :- Type == 'Atom', !.
unchecked_parameter_type(Type) :-
    nonvar(Type),
    catch_recover(type_declaration(Type, 'DontEvalType'), fail).

%A check that cannot be DROPPED can still be SPECIALISED. Three types are
%decided by a single Prolog builtin, and when the declared type is one of them
%the compiler knows so, because the type is a compile-time constant. Putting
%that test in front turns the common case from a walk through
%current_metta_module/1, has_type_in/3, once/1 and type_candidate_in/3 into one
%builtin call [measured 2026-08-17: an output check of type Number, 8.00
%inferences per call to 1.00].
%
%The fallback is untouched and reached whenever the fast test fails, so this
%decides nothing the general check would decide differently. It only answers
%the common case sooner. That matters because the fast test is INCOMPLETE on
%purpose: `(: mysym Number)` makes has_type(mysym, 'Number') true while
%number(mysym) is false, and the second disjunct is what still says so.
%
%Soundness in the other direction is what makes the shortcut legal at all.
%Both get_type_candidate/2 and get_type_candidate_in/3 open with a CUTTING
%numeric clause. Signed-i64 integers and floats answer Number directly. Wider
%integers answer BigInt, which metta_types_match/2 admits when Number is the
%expected type. Thus number(V) implies has_type(V, 'Number') in every module,
%whatever a get-type extension adds later [source: engine/metta.pl,
%metta_numeric_type/2 and metta_types_match/2].
%
%This is the other half of what statically_typed_literal/2 below does, from the
%same compile-time fact. A compiler holding type information "remov[es] type
%and mode checks and ... call[s] specialized versions of some builtins"
%[source: Morales, Carro and Hermenegildo, Improved Compilation of Prolog to C
%Using Moded Types]; the removal is the literal case and this is the
%specialisation case.
%
%nonvar/1 first, and it is not defensive: a parametric declaration leaves the
%type a VARIABLE here, and intrinsic_type_test/3's head would bind it to
%'Number' and emit a number/1 test for a type nobody wrote. That is the same
%trap intrinsic_literal_type/2 below carries a note about, from the same shape.
%[tested: translator_literal_type_checks:an_intrinsic_type_check_is_specialised].
type_check_goal(Value, Type, General, Goal) :-
    (   nonvar(Type),
        intrinsic_type_test(Type, Value, Fast)
    ->  Goal = ( Fast -> true ; General )
    ;   Goal = General
    ).

intrinsic_type_test('Number', V, number(V)).
intrinsic_type_test('String', V, string(V)).
intrinsic_type_test('Bool',   V, (V == true ; V == false)).

%A literal argument's type is settled while the call site is being COMPILED,
%so the check emitted for it can only ever succeed and every inference it
%spends is spent on a foregone conclusion. `(: f (-> Number Number Number))`
%called as `(f 1 2)` compiled two has_type/2 goals over the constants 1 and 2,
%and they cost as much as the same call on two unknown variables: 31
%inferences per call against 6 for the same function undeclared, the whole 25
%being the checks [measured 2026-08-16, 20,000 calls of a site compiled once].
%Dropping every check leaves no once/1 wrapper either, so the fully literal
%call compiles to exactly what the untyped one does.
%
%Only four literal shapes qualify. A number is accepted by Number, including
%a BigInt integer through the directed compatibility rule. A string is String,
%and true and false are Bool, whatever a user's get-type extension adds later.
%
%This only ever DROPS a check that must pass; it never rejects. `(f "s")`
%against a Number parameter still compiles its check and still refuses at run
%time, because a get-type extension may legitimately give a literal a second
%type and deciding THAT statically would be unsound
%[tested: translator_literal_type_checks].
statically_typed_literal(Value, Type) :-
    nonvar(Type),
    nonvar(Value),
    intrinsic_literal_type(Value, Type).

%nonvar/1 above and ==/2 rather than head unification below, because BOTH are
%needed and the second is what a reader would skip. Written as
%`intrinsic_literal_type(true, 'Bool')`, a call with an unbound Value and
%Type = 'Bool' UNIFIES the head and binds Value to true. The argument being
%bound there is the call site's compile-time variable, so
%`(= (f $a $b) (g $a $b))` against `(: g (-> Bool Atom Bool))` compiled its
%head as `f(true, A, B)` and `(f False ...)` then matched no clause and
%answered nothing at all [reproduced 2026-08-16].
%
%Caught by a hand probe rather than by the gate, because the shape needs a
%Bool, Number or String parameter reached from ANOTHER function's body with a
%variable, and no example in the corpus had one
%[tested: translator_literal_type_checks:a_typed_parameter_is_not_frozen_at_compile_time].
intrinsic_literal_type(Value, 'Number') :- number(Value), !.
intrinsic_literal_type(Value, 'String') :- string(Value), !.
intrinsic_literal_type(Value, 'Bool') :- ( Value == true ; Value == false ).
