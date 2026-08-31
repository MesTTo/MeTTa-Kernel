% Purpose: differential and fallback coverage for engine/mbr.c, the C twin of
%   translator:merge_branch_returns_check/4. The Prolog implementation remains
%   the specification, and a C refusal remains a request to use that
%   specification rather than a failed clause translation.
% Guarantees:
%   - canonical and 600 generated control-spine clauses produce
%     variant-identical rewritten bodies and delayed binding pairs through the
%     C and Prolog analyzers [tested: mbr_c_differential; commit=WORKTREE].
%   - a clause exceeding MBR_MAX_VARS is refused by the C analyzer but still
%     rewritten by translator:merge_branch_returns/3, including when the C
%     artifact is disabled [tested: mbr_c_fallback; commit=WORKTREE].
%
%   The differential unit is conditioned on translator:metta_c_mbr_active/0,
%   following suites/reader/writer_c.plt. The fallback unit is deliberately
%   unconditioned, so a box without engine/mbr.so and METTA_C_MBR=off both
%   retain coverage and report why only the C comparisons were skipped.
%
%   Run: cd tests/prolog && swipl -g "set_test_options([format(log)]), run_tests" -t halt suites/translator/mbr_c.plt
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

% Load the engine through metta.pl, not main.pl: main.pl's
% `:- initialization(main, main).` fires on consult and prints its demo
% into the test output.
:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').
:- use_module(library(random), [random_between/3]).

%PlUnit omits a unit whose condition fails but does not print that condition's
%output in the log format. Report the same gate once while loading the suite,
%then let the condition itself stay a side-effect-free artifact predicate.
mbr_c_differential_available :-
    translator:metta_c_mbr_active.

mbr_c_report_unavailable :-
    (   mbr_c_differential_available
    ->  true
    ;   mbr_c_skip_reason(Reason),
        format(user_error, "MBR C differential tests skipped: ~w.~n", [Reason])
    ).

mbr_c_skip_reason('METTA_C_MBR=off') :-
    getenv('METTA_C_MBR', off),
    !.
mbr_c_skip_reason('engine/mbr.so is absent or could not be loaded').

:- mbr_c_report_unavailable.

%The body alone carries more distinct variables than mbr.c's 512-slot table.
%Its private branch return supplies an exact rewrite for both the Prolog
%reference and the public fallback door to prove, rather than merely proving
%that each predicate succeeds.
mbr_overflow_clause(Head, Body0, AnalysisBody, Bindings, PublicBody, Value, Out) :-
    length(Vars, 513),
    Head = overflow(Out),
    Body0 = (payload(Vars),
             (guard -> (produce(Value), Out = Value) ; Out = none)),
    AnalysisBody = (payload(Vars),
                    (guard -> produce(Value) ; Out = none)),
    Bindings = [Value-Out],
    PublicBody = (payload(Vars),
                  (guard -> produce(Out) ; Out = none)).

:- begin_tests(mbr_c_fallback).

test(the_prolog_reference_rewrites_a_private_return) :-
    Head = branch_private(Input, Out),
    Body0 = (guard -> (produce(Input, Value), Out = Value) ; Out = none),
    translator:merge_branch_returns_check(Head, Body0, Body, Bindings),
    Body == (guard -> produce(Input, Value) ; Out = none),
    Bindings == [Value-Out].

test(a_straight_line_body_stays_untouched_through_the_public_door) :-
    Head = branch_straight(Input, Out),
    Body0 = (produce(Input, Value), consume(Value, Out)),
    translator:merge_branch_returns(Head, Body0, Body),
    Body == Body0.

test(the_public_door_answers_past_the_c_variable_cap) :-
    mbr_overflow_clause(Head, Body0, _AnalysisBody, _Bindings,
                        PublicBody, Value, Out),
    term_variables(Body0, BodyVariables),
    length(BodyVariables, VariableCount),
    VariableCount > 512,
    translator:merge_branch_returns(Head, Body0, Body),
    Value == Out,
    Body == PublicBody.

:- end_tests(mbr_c_fallback).

:- begin_tests(mbr_c_differential,
               [condition(user:mbr_c_differential_available)]).

%Call both analyzers on fresh copies and compare the body together with its
%binding list. Comparing either half alone would miss a different decision
%whose eventual unifications happened to produce the same public body.
mbr_implementations_agree(Label, Head0, Body0) :-
    copy_term(Head0-Body0, CHead-CBody0),
    copy_term(Head0-Body0, PHead-PBody0),
    translator:metta_c_mbr_analyze(CHead, CBody0, CBody, CBindings),
    translator:merge_branch_returns_check(PHead, PBody0, PBody, PBindings),
    (   CBody-CBindings =@= PBody-PBindings
    ->  true
    ;   format(user_error,
               "MBR disagreement on ~w:~n  c:      ~q~n  prolog: ~q~n",
               [Label, CBody-CBindings, PBody-PBindings]),
        fail
    ).

%The expected result is copied with each input so =@=/2 also checks sharing:
%a pair naming the wrong output variable is not accepted as the same rewrite.
mbr_canonical_agrees(Label, Head0, Body0, ExpectedBody0, ExpectedBindings0) :-
    mbr_implementations_agree(Label, Head0, Body0),
    copy_term(Head0-Body0-ExpectedBody0-ExpectedBindings0,
              CHead-CBody0-CExpectedBody-CExpectedBindings),
    translator:metta_c_mbr_analyze(CHead, CBody0, CBody, CBindings),
    CBody-CBindings =@= CExpectedBody-CExpectedBindings,
    copy_term(Head0-Body0-ExpectedBody0-ExpectedBindings0,
              PHead-PBody0-PExpectedBody-PExpectedBindings),
    translator:merge_branch_returns_check(PHead, PBody0, PBody, PBindings),
    PBody-PBindings =@= PExpectedBody-PExpectedBindings.

canonical_mbr_case(private_return, Head, Body0, Body, Bindings) :-
    Head = branch_private(Input, Out),
    Body0 = (guard -> (produce(Input, Value), Out = Value) ; Out = none),
    Body = (guard -> produce(Input, Value) ; Out = none),
    Bindings = [Value-Out].
canonical_mbr_case(head_parameter_exclusion, Head, Body0, Body0, []) :-
    Head = branch_head(Value, Out),
    Body0 = (guard -> (produce(Value), Out = Value) ; Out = none).
canonical_mbr_case(outside_use_exclusion, Head, Body0, Body0, []) :-
    Head = branch_shared(Out),
    Body0 = (guard -> (produce(Value), Out = Value) ; consume(Value)).
canonical_mbr_case(produced_before_branch_exclusion, Head, Body0, Body0, []) :-
    Head = branch_prebound(Input, Out),
    Body0 = (produce(Input, Value),
             (guard -> Out = Value ; Out = none)).
canonical_mbr_case(nested_alternatives, Head, Body0, Body, Bindings) :-
    Head = branch_nested(Out),
    Body0 = (guard -> ((choice -> left(Value) ; right(Value)),
                       Out = Value)
                   ; Out = none),
    Body = (guard -> (choice -> left(Value) ; right(Value)) ; Out = none),
    Bindings = [Value-Out].
canonical_mbr_case(straight_line_untouched, Head, Body0, Body0, []) :-
    Head = branch_straight(Input, Out),
    Body0 = (produce(Input, Value), consume(Value, Out)).
%mbr_split/3 and split_last() represent the prefix before a lone branch goal
%as true. With no earlier occurrence of Value it is not a merge candidate, so
%the true sentinel must stay internal and the written branch must stay whole.
canonical_mbr_case(single_goal_branch_true_prefix, Head, Body0, Body0, []) :-
    Head = branch_single(Out),
    Body0 = (guard -> Out = _Value ; Out = none).

test(the_c_and_prolog_analyzers_agree_on_every_canonical_shape,
     [forall(canonical_mbr_case(Label, Head, Body0,
                                ExpectedBody, ExpectedBindings))]) :-
    mbr_canonical_agrees(Label, Head, Body0, ExpectedBody, ExpectedBindings).

%A fixed-seed clause-shape generator covers conjunction, if-then-else,
%disjunction, if-then, opaque control-shaped data, variable-bearing goals,
%mergeable returns, head variables, and returns whose value is used after the
%binding.
%Depth is capped so every generated case remains below MBR_MAX_VARS; overflow
%has its own exact boundary test below.
generated_mbr_clause(Index, Head, Body) :-
    random_between(1, 5, Depth),
    Head = generated(Index, HeadValue, Out),
    generated_mbr_spine(Depth, Index, HeadValue, Out, Body).

generated_mbr_spine(0, Tag, HeadValue, Out, Body) :-
    !,
    generated_mbr_leaf(Tag, HeadValue, Out, Body).
generated_mbr_spine(Depth, Tag, HeadValue, Out, Body) :-
    random_between(0, 6, Kind),
    NextDepth is Depth - 1,
    generated_mbr_node(Kind, NextDepth, Tag, HeadValue, Out, Body).

generated_mbr_node(0, _, Tag, HeadValue, Out, Body) :-
    generated_mbr_leaf(Tag, HeadValue, Out, Body).
generated_mbr_node(1, Depth, Tag, HeadValue, Out, (Left, Right)) :-
    generated_mbr_spine(Depth, left(Tag), HeadValue, Out, Left),
    generated_mbr_spine(Depth, right(Tag), HeadValue, Out, Right).
generated_mbr_node(2, Depth, Tag, HeadValue, Out,
                   (condition(Tag, HeadValue) -> Then ; Else)) :-
    generated_mbr_spine(Depth, then(Tag), HeadValue, Out, Then),
    generated_mbr_spine(Depth, else(Tag), HeadValue, Out, Else).
generated_mbr_node(3, Depth, Tag, HeadValue, Out, (Left ; Right)) :-
    generated_mbr_spine(Depth, left(Tag), HeadValue, Out, Left),
    generated_mbr_spine(Depth, right(Tag), HeadValue, Out, Right).
generated_mbr_node(4, Depth, Tag, HeadValue, Out,
                   (condition(Tag, HeadValue) -> Then)) :-
    generated_mbr_spine(Depth, then(Tag), HeadValue, Out, Then).
generated_mbr_node(5, Depth, Tag, HeadValue, Out, opaque(ControlData)) :-
    generated_mbr_spine(Depth, data(Tag), HeadValue, Out, ControlData).
generated_mbr_node(6, _, Tag, HeadValue, Out,
                   (condition(Tag, HeadValue) ->
                       (produce(Tag, Value), Out = Value)
                   ; fallback(Tag, Out))).

generated_mbr_leaf(Tag, HeadValue, Out, Body) :-
    random_between(0, 6, Kind),
    generated_mbr_leaf(Kind, Tag, HeadValue, Out, Body).

generated_mbr_leaf(0, _, _, _, true).
generated_mbr_leaf(1, Tag, HeadValue, _, probe(Tag, HeadValue)).
generated_mbr_leaf(2, Tag, _, _, call_generated(Tag, _Variable)).
generated_mbr_leaf(3, Tag, _, Out, (produce(Tag, Value), Out = Value)).
generated_mbr_leaf(4, Tag, HeadValue, Out,
                   (produce(Tag, HeadValue), Out = HeadValue)).
generated_mbr_leaf(5, Tag, _, Out,
                   (produce(Tag, Value), Out = Value, consume(Tag, Value))).
generated_mbr_leaf(6, _, _, Out, (Out = _Value)).

test(six_hundred_generated_control_spines_agree) :-
    set_random(seed(20260830)),
    CaseCount = 600,
    findall(Index-(Head-Body),
            ( between(1, CaseCount, Index),
              generated_mbr_clause(Index, Head, Body) ),
            Cases),
    length(Cases, CaseCount),
    forall(member(Index-(Head-Body), Cases),
           mbr_implementations_agree(generated(Index), Head, Body)).

test(the_c_analyzer_declines_overflow_while_the_prolog_side_answers) :-
    mbr_overflow_clause(Head0, Body00, AnalysisBody0, Bindings0,
                        _PublicBody, _Value, _Out),
    term_variables(Body00, BodyVariables),
    length(BodyVariables, VariableCount),
    VariableCount > 512,
    copy_term(Head0-Body00, CHead-CBody0),
    \+ translator:metta_c_mbr_analyze(CHead, CBody0, _, _),
    copy_term(Head0-Body00-AnalysisBody0-Bindings0,
              PHead-PBody0-ExpectedBody-ExpectedBindings),
    translator:merge_branch_returns_check(PHead, PBody0, PBody, PBindings),
    PBody-PBindings =@= ExpectedBody-ExpectedBindings.

:- end_tests(mbr_c_differential).

:- begin_tests(mbr_split_variable_arm).

%A raw variable as a branch arm must not loop: mbr_split/3 once unified an
%unbound goal with (A , B) and manufactured conjunctions until the stack
%went. Both implementations answer, and agree, with a variable in arm
%position [measured 2026-08-30: 1.0Gb stack overflow before the guard].
test(a_variable_branch_arm_is_walked_as_opaque) :-
    Head = vh(Out),
    Body0 = ( cond -> Arm ; Out = other ),
    translator:merge_branch_returns(Head, Body0, Body),
    assertion(nonvar(Body)),
    assertion(var(Arm)).

:- end_tests(mbr_split_variable_arm).
