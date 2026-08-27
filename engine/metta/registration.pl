% Purpose: register function names and arities, protect callable surface, and import host and backend builtins
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/suites/evaluation/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%% Registration: %%%
:- dynamic fun/1, arity/2.
register_fun(N) :- must_be(atom, N),
                   ( fun(N) -> true
                   ; assertz(fun(N), Ref),
                     record_source_assertion(Ref),
                     repair_after_late_registration(N) ).

%The arities a loaded predicate is callable at, which is what a registration
%from Prolog has to record: every other route knows its arity from the
%equation head it just compiled and calls register_arity/2 with it directly.
%An operator's name answers current_predicate/1 at arities 1 and 2 whether or
%not a predicate of that name exists, so those two are not registrable.
%
%This walk used to live inside register_fun/1, guarded by "the name is new".
%A library registering 'norm'/3 for a name some space already defined at MeTTa
%arity 1 therefore recorded no arity at all, and incomplete_application_kind/3
%reads a missing arity as "not applied far enough", so (norm a b) compiled to a
%partial application. Reading it here instead means the arities are recorded
%for the registration that asked for them, whatever else knows the name
%[tested: a_registration_records_arities_for_a_name_that_is_already_a_function].
%Every arity the name is CALLABLE at, and callable means defined here rather
%than merely visible. The exclusion is not defensive: library(yall) exports
%//2 through //9 into user as its free-variables lambda, so probing
%current_predicate/1 alone recorded SEVEN arities for `/` where + and * have
%one. (/ 1 2 3) then compiled to a direct '/'(1,2,3,_) call, which is yall's
%lambda, and answered `type_error(lambda_free, 1)` where every other operator
%answers the engine's own function_input_arities naming the operator
%[tested: metta_registration_arities].
%
%imported_from/1 is the exact question, and the arity =< 2 clause below is the
%older half-answer to the same thing: it excluded 1/2 the TERM and nothing
%told it about 1/2 the lambda.
register_prolog_arities(N) :-
    forall(( current_predicate(N/Arity),
             \+ (current_op(_, _, N), Arity =< 2),
             \+ (current_op(_, _, N), imported_predicate(N, Arity)) ),
           register_arity(N, Arity)).

%%% Arities a SWI system predicate lent a MeTTa name by accident %%%
%
%A SWI SYSTEM predicate that shares a MeTTa operation's name but not its shape
%is a different predicate, and registering its arity made an UNDER-APPLIED call
%compile straight into it. `!(not)` reached SWI's own not/1, which is negation,
%and aborted the runnable with `not/1: Arguments are not sufficiently
%instantiated` instead of answering anything at all; the same held for
%`(append)`, `(assert)`, `(exists_file)` and `(sleep)`. Under-applying an
%operation is an ordinary MeTTa event -- this engine answers a partial
%application, `(sqrt-math)` is `(partial sqrt-math ())` -- and no MeTTa event
%may take the host down
%[tested: test_an_underapplied_operation_answers_instead_of_aborting].
%
%The operation's OWN declarations decide which arities are its: a chain of N
%links is the Prolog predicate of arity N, one argument per link with the last
%being the result. So `(: not (-> Bool Bool))` keeps not/2 and drops not/1, and
%`(: length (-> Expression Number))` keeps length/2 even though length/2 is a
%system predicate too. Measured on this tree: exactly nine registrations go,
%append/1, assert/1, copy_term/3, copy_term/4, exists_file/1, not/1, sleep/1,
%sort/4 and term_hash/4, none of which any example, test or library calls, and
%every library or engine-defined predicate is untouched because it is not
%built_in.
%
%IT RUNS AFTER THE DECLARATIONS AND THE PRELUDE, not while the names register,
%and that ordering is the whole reason it is a separate pass:
%register_builtin_fun/1 runs at DIRECTIVE time while load_builtin_type_surface/0
%and load_engine_prelude/0 run at INITIALIZATION time, so a filter inside the
%registration sees an empty declaration table and drops the arities it exists to
%keep -- measured, it took length/2, sort/2 and msort/2 with it and turned
%`(length (1 2 3))` into a partial application. It is one pass over the registry
%rather than a test on the hot path, which is why the calls that read arity/2
%are untouched.
%
%Limitation: a host library or backend that registers a name AFTER the boot
%chain is not swept, because nothing re-runs this. Nothing in the tree does
%that today; a registration door that starts to would call this again.
retract_unrelated_system_arities :-
    findall(N-Arity,
            ( arity(N, Arity), unrelated_system_predicate(N, Arity) ),
            Unrelated),
    forall(member(N-Arity, Unrelated), retractall(arity(N, Arity))).

unrelated_system_predicate(N, Arity) :-
    functor(Head, N, Arity),
    metta_engine_module(Engine),
    predicate_property(Engine:Head, built_in),
    seam:builtin_type_declaration(N, _),
    \+ declared_metta_arity(N, Arity).

declared_metta_arity(N, Arity) :-
    seam:builtin_type_declaration(N, [->|Links]),
    length(Links, Arity).

%Only for an OPERATOR, and the first attempt got that wrong: excluding every
%imported predicate dropped length/2, which is library(lists)'s and a
%perfectly good builtin, so (length ...) compiled to partial(length, [...])
%and four gates went red. An imported predicate is normal; an imported
%predicate whose name is also an OPERATOR is the collision.
imported_predicate(N, Arity) :-
    functor(Head, N, Arity),
    metta_engine_module(Engine),
    predicate_property(Engine:Head, imported_from(_)).

%Record each callable arity once, even when a function has many equations.
register_arity(N, Arity) :- ( arity(N, Arity) -> true
                            ; assertz(arity(N, Arity), Ref),
                              record_source_assertion(Ref) ).

%The module whose equations are in scope while a term is compiled or run. The
%default is &self's, which is where a program that names no space writes.
%
%The default is a fact read rather than a constant unified, one inference
%instead of none, because the alternative is writing '$metta_exec:&self' out
%here and having two places that decide the name
%[tested: metta_module_context:the_default_context_is_selfs_own_module].
current_metta_module(Module) :-
    ( nb_current('$metta_module', M) -> Module = M ; metta_self_module(Module) ).

%Skipping the switch when Module is already in force was tried and taken back
%out. It saved 4 inferences on every Python evaluation and cost 2 on every
%annotated typed call, which is the wrong side of that trade: the crossing
%happens once and the typed call happens in a loop. Measured 2026-08-16, the
%@m.define annotated tier of extensions/python/benchmarks/extension_cost.py went 20.00 to
%22.00 with the test in place, against m.fn 68.00 to 64.00.
%The argument is a MODULE, and refusing anything else is what keeps this
%honest now that a space and its module are different atoms. They used to be
%the same atom for every space but &self, so `with_metta_module('&pool', G)`
%worked by coincidence; today it would switch the context to a module nothing
%compiles into, every lookup would miss, and the goal would answer as if the
%space were empty. One indexed cache probe turns that into a refusal at the
%call [tested: metta_module_context:a_space_name_is_refused_where_a_module_is_asked].
with_metta_module(Module, Goal) :-
    (   metta_exec_module_known(_, Module)
    ->  true
    ;   throw(error(type_error(metta_execution_module, Module),
                    context(with_metta_module/2,
                            'space_module/2 maps a space to the module its \c
                             clauses are in; pass that, not the space')))
    ),
    current_metta_module(Previous),
    setup_call_cleanup(b_setval('$metta_module', Module),
                       Goal,
                       b_setval('$metta_module', Previous)).

%Control signals pass through every recovery catch: a caught abort, limit,
%alarm, or interrupt is a stopped program pretending it succeeded. This is
%the KeyboardInterrupt-outside-Exception design; a swallowed limit signal
%also DISARMS call_with_inference_limit for the rest of the call, measured
%as six million inferences spent under a thousand-inference budget when a
%recovery catch ate the signal mid-translation.
%
%The engine's own list. It is a SEAM, so a library that introduces its own
%cancellation or budget signal adds a clause instead of being swallowed by
%the first recovery catch it meets
%[tested: a_librarys_own_control_signal_is_not_recovered_from].
%
%Its multifile declaration is HERE and not with the other seams, which is the
%one exception seam_home/2 in engine/ext_points.pl exists to answer. The name
%is also an engine_emitted/1 one: the translator writes control_exception/1
%into compiled bodies and protect_engine_emitted/1 imports every emitted name
%into a space's execution module FROM THE ENGINE'S MODULE, so a copy living
%in the seam module would leave the import with nothing to find.
:- multifile control_exception/1.
control_exception(time_limit_exceeded).
control_exception(inference_limit_exceeded).
control_exception(metta_host_interrupted).
control_exception('$aborted').
%The reserved seam envelopes for the same two signals: the shim declares
%every metta_control_signal kind control on the Python side, and these two
%are thrown by the ENGINE's own bound forms (inferences, with-pragma!),
%so the CLI must agree or a program could catch its own budget there and
%disarm the counter.
control_exception(error(metta_control_signal(time_limit, _), _)).
control_exception(error(metta_control_signal(inference_limit, _), _)).

%The reserved envelope renders its payload: a reader failure used to cross
%as a bare syntax_error and take SWI's own message with it, and wrapping
%it in the envelope must not trade "missing ')' ..." for an unknown-term
%dump on a host that shows message text.
:- multifile prolog:error_message//1.
prolog:error_message(metta_control_signal(syntax, Detail)) -->
    [ 'MeTTa syntax error: ~w'-[Detail] ].
%The two bound kinds had no rendering at all, so a program that spent its own
%(pragma! max-inferences N) printed `Unknown error term:
%metta_control_signal(inference_limit,500)` at the CLI [measured 2026-08-27 on
%!(with-pragma! ((max-inferences 500)) (spin 1000000)); commit=6da1b0dacc500fc7691a66722ba58f52ab2df081]. Every
%seat that shows message text reads these, the C binding included, so they say
%which bound stopped the work and what it was set to.
prolog:error_message(metta_control_signal(inference_limit, Limit)) -->
    [ 'the evaluation passed its ~w inference bound and was stopped'-[Limit] ].
prolog:error_message(metta_control_signal(time_limit, Seconds)) -->
    [ 'the evaluation passed its ~w second bound and was stopped'-[Seconds] ].
control_exception(error(resource_error(_), _)).

%A result past binary64 SATURATES to the IEEE value instead of raising,
%which is upstream's arithmetic (plain Rust f64: "1e400".parse and 1e308*10
%both answer inf there) and the reader's own behaviour for literals, so the
%two halves of the numeric boundary agree: 1e400 reads as inf and
%(+ 1e400 1) answers inf. SWI's error mode rejects any non-finite RESULT,
%operands included, so without this an infinity the reader legally produced
%could not even carry through (+ inf 1). The flag is borrowed for the one
%retry and given back, parser.pl's metta_saturating_parse discipline on the
%evaluation side; the happy path pays nothing because this only runs from a
%catch recovery. The same discipline covers the whole IEEE family when a
%floating expression is present, including an explicit integer promotion:
%division by a float zero answers the signed infinity and the NaN class
%(0.0/0.0, inf - inf, sqrt of a negative, asin past one) answers NaN, which
%is what isnan-math and isinf-math exist to
%observe. Every fault outside metta_ieee_retry/1, integer division by zero
%first among them, reaches the operation-recovery funnel below; the retry's
%own catch is the net for faults the flags do not govern, none known for the
%shipped operations.
metta_saturating_recover(Operation, Expression, Result, Error) :-
    metta_ieee_saturable(Expression, Error),
    !,
    current_prolog_flag(float_overflow, WasOverflow),
    current_prolog_flag(float_zero_div, WasZeroDiv),
    current_prolog_flag(float_undefined, WasUndefined),
    catch(setup_call_cleanup(
              ( set_prolog_flag(float_overflow, infinity),
                set_prolog_flag(float_zero_div, infinity),
                set_prolog_flag(float_undefined, nan) ),
              Result is Expression,
              ( set_prolog_flag(float_overflow, WasOverflow),
                set_prolog_flag(float_zero_div, WasZeroDiv),
                set_prolog_flag(float_undefined, WasUndefined) )),
          Residual,
          rethrow_metta_operation_error(Operation, Residual)).
metta_saturating_recover(Operation, _, _, Error) :-
    metta_arithmetic_rethrow(Operation, Error).

%is/2 raises a BARE instantiation error for an operand it does not have, and
%that error names neither the operation's modes nor what to write instead: it
%is SWI's, not the language's. Every backward query the engine CAN answer is
%decided before an exception exists (metta_int_solve/5 for one unknown among
%integers, metta_clp_backward/4 for the integer relations past it), so what
%reaches here is a query outside both: a float operand, or an operation with
%no relation to solve. It refuses by name
%[tested: test_arithmetic_inverts_past_the_linear_case_or_refuses_with_the_reason].
metta_arithmetic_rethrow(Operation, error(instantiation_error, _)) :- !,
    metta_refuse_unsolved_arithmetic(Operation, unbound_operand).
metta_arithmetic_rethrow(Operation, Error) :-
    rethrow_metta_operation_error(Operation, Error).

%Float zero division belongs to the IEEE retry, while integer zero division
%is a contained language result. Test the IEEE class first so `/ 1.0 0.0`
%keeps its signed infinity and only the all-integer fault reaches the shared
%operation recovery.
metta_arithmetic_saturating_recovery(Operation, Arguments, Expression,
                                     Error, Result) :-
    (   metta_ieee_saturable(Expression, Error)
    ->  metta_saturating_recover(Operation, Expression, Result, Error)
    ;   metta_operation_recovery(Operation, Arguments, Error, Result)
    ).

%An operation fault is an answer when the language gives the fault a reason.
%LeaTTa pins both integer doors byte-exactly as (Error (<op> 7 0)
%DivisionByZero), while every other host error retains the raising path
%[source: LeaTTa tests/regression/division_convention.metta:82-90;
%tested: test_integer_division_by_zero_answers_what_d1_decides;
%commit=ecd792eacbfe1810645434ce406f79be3a9e03d1].
metta_operation_recovery(Operation, Arguments,
                         error(evaluation_error(zero_divisor), _), Answer) :-
    maplist(integer, Arguments), !,
    metta_error_atom(Operation, Arguments, 'DivisionByZero', Answer).
metta_operation_recovery(Operation, _, Error, _) :-
    metta_arithmetic_rethrow(Operation, Error).

%Which evaluation faults license the retry. Overflow retries
%unconditionally, because an ALL-INTEGER division can overflow in its float
%conversion and the saturated value is this engine's committed answer
%there. Zero division and the NaN family retry only when the expression has a
%float operand or an explicit float/1 promotion: upstream's float arm is raw
%f64 (1.0/0.0 is inf,
%0.0/0.0 and inf - inf are NaN, by construction), while its INTEGER
%division by zero answers a DivisionByZero Error atom, so an integer zero
%takes the operation-recovery funnel instead of this retry. The retry runs
%under all three IEEE flags at once rather
%than only the one that fired, because a compound expression can fault
%twice: log-math with base 1 overflows in log(0.0) and then divides the
%saturated -inf by log(1) = 0.0, and one-flag-at-a-time would error where
%the arbiter's arithmetic answers -inf.
metta_ieee_retry(float_overflow).
metta_ieee_retry(zero_divisor).
metta_ieee_retry(undefined).

%Whether a fault is in the retryable family at all, factored out so the
%chained recovery above can ask without committing to the retry.
metta_ieee_saturable(Expression, error(evaluation_error(Evaluation), _)) :-
    metta_ieee_retry(Evaluation),
    (   Evaluation == float_overflow
    ->  true
    ;   sub_term(Operand, Expression),
        (   float(Operand)
        ;   compound(Operand), functor(Operand, float, 1)
        )
    ).

%Keep the ISO Formal term because callers and the MeTTa catch form inspect it.
%Only the host context is replaced, so lists:min_list/3, is/2, and nb_setval/2
%cannot leak into a language-level diagnostic. Integer fast paths avoid the
%catch cost on valid arithmetic without letting float overflow escape, except
%division, whose all-integer case converts a non-divisible pair to float and
%can overflow doing it, so it pays the catch like the float arms. Over
%100,000 calls the guarded form used
%300,002 inferences against 300,003 directly, while an unconditional catch used
%400,002 [measured: guarded -1 and caught +99,999 inferences, 2026-08-15].
rethrow_metta_operation_error(_, Error) :- control_exception(Error), !,
                                            throw(Error).
rethrow_metta_operation_error(Operation, error(Formal, _)) :- !,
    throw(error(Formal,
                context(Operation, 'while evaluating MeTTa operation'))).
rethrow_metta_operation_error(_, Error) :- throw(Error).

throw_metta_type_error(Operation, Expected, Culprit) :-
    throw(error(type_error(Expected, Culprit),
                context(Operation, 'invalid MeTTa operation argument'))).

%The classification a host reads a builtin refusal through, beside the two
%throwers that produce the shape. The engine names the written MeTTa
%operation in the context, so a host reads the name from the term rather
%than from rendered text; only a type_error carries an expected type and a
%culprit, and any other formal reports its own functor with both parts
%ABSENT. Absence is an unbound part, which is the one marker no culprit can
%collide with; a host maps var-ness to its own None.
metta_host_operation_error(error(Formal, context(Operation, Message)),
                           Operation, Kind, Expected, Culprit) :-
    atom(Operation),
    nonvar(Message),
    metta_host_operation_message(Message),
    nonvar(Formal),
    metta_host_operation_formal(Formal, Kind, Expected0, Culprit0),
    metta_host_operation_part(Expected0, Expected),
    metta_host_operation_part(Culprit0, Culprit).

metta_host_operation_message('while evaluating MeTTa operation').
metta_host_operation_message('invalid MeTTa operation argument').

%is/2 reports an unevaluable term as a predicate indicator, Name/Arity. That
%is a Prolog artifact rather than anything the user wrote, and swrite would
%read the / as MeTTa and print (/ a 0). A zero-arity indicator is exactly
%the symbol the source wrote, so it crosses as that symbol.
metta_host_operation_formal(type_error(evaluable, Name/Arity), type_error,
                            evaluable, Culprit) :- !,
    ( Arity =:= 0 -> Culprit = Name
                   ; format(atom(Culprit), '~w/~w', [Name, Arity]) ).
metta_host_operation_formal(type_error(Expected, Culprit), type_error,
                            Expected, Culprit) :- !.
metta_host_operation_formal(Formal, Kind, _, _) :- functor(Formal, Kind, _).

%A wire carries atomics and lists of them; any other compound crosses as
%its written text, from swrite/2, the engine's own printer, so it reads
%back as the MeTTa the user wrote: a generic term writer would spell a
%variable _112 and a partial application partial(g,[1]), neither of which
%is MeTTa surface syntax. An unbound part stays unbound.
metta_host_operation_part(Term, Term) :- var(Term), !.
metta_host_operation_part(Term, Value) :- metta_host_operation_value(Term, Value).

metta_host_operation_value(Term, Term) :- atomic(Term), !.
metta_host_operation_value(Term, Value) :-
    is_list(Term), !,
    maplist(metta_host_operation_value, Term, Value).
metta_host_operation_value(Term, Text) :- swrite(Term, Text).

%The culprit in the message is the value the program wrote, so it reads as
%MeTTa: (State 5), not ['State',5]. The Formal term stays ISO, because
%callers and the MeTTa catch form inspect it, and the structured Python
%surface reads it too; only the rendering changes.
%
%prolog:message//1 is consulted before the formal-only
%prolog:error_message//1, and this clause matches the context MeTTa's own
%guards attach, so every other error SWI renders is untouched
%[source: SWI-Prolog 10.1 boot/messages.pl, translate_message/1]
%[tested: metta_operation_error_message].
%The context is matched in the body, not in the head: library(error) throws
%its type errors with an unbound context, which a head pattern would unify
%with and claim, renaming every unrelated type error in the process
%[tested: metta_operation_error_message:an_unrelated_type_error_is_untouched].
%metta_error_context(+Context, -Operation, +Detail) reads a context term
%WITHOUT writing to it. Matching context(Operation, Detail) in the head looks
%equivalent and is not: SWI's own errors carry context(PI, _) with the second
%argument UNBOUND, so unifying a detail atom into it succeeds and the clause
%then renders every ordinary error of that formal. This clause was hijacking
%all of them, which is where I16's "system:(is)/2: evaluable expected, found
%(/ foo 0)" came from: a library predicate's is/2 type error was being
%reported in MeTTa's operation vocabulary, naming an engine internal and a
%culprit the program never wrote [tested: metta_operation_errors,
%an_unrelated_type_error_keeps_swi_s_own_message].
metta_error_context(Context, Operation, Detail) :-
    nonvar(Context),
    Context = context(Operation, Actual),
    nonvar(Actual),
    Actual == Detail.

prolog:message(error(type_error(Expected, Culprit), Context)) -->
    { metta_error_context(Context, Operation, 'invalid MeTTa operation argument'),
      swrite(Culprit, CulpritText) },
    [ '~w: ~w expected, found ~w'-[Operation, Expected, CulpritText] ].
%The ISO formal stays existence_error(procedure, Name), so a program can catch
%it the standard way; only the wording changes, because SWI's default renders
%it as "procedure `f' does not exist", which says nothing about why a
%registration cares. What it costs is the reason worth printing: a name with
%no predicate records no arity, and incomplete_application_kind/3 then reads
%the missing arity as "not applied far enough", so the call compiles to a
%partial application instead of failing.
prolog:message(error(existence_error(procedure, Name), Context)) -->
    { metta_error_context(Context, _, 'no Prolog predicate of that name is loaded') },
    [ 'no predicate named ~w is loaded, so registering it would compile \c
       every call to it into a partial application rather than failing'-[Name] ].

%These builtins validate their own runtime inputs and provide their own error
%context. The translator may therefore bypass reflective input filtering when
%the builtin has not been overridden. Keep this list aligned with those guards.
runtime_type_guarded('+').
runtime_type_guarded('-').
runtime_type_guarded('*').
runtime_type_guarded('/').
runtime_type_guarded('%').
runtime_type_guarded('<').
%== and != carry their own guard, comparable_operands/3, which is exactly
%what their declared type (-> $a $a Bool) states, so the typed dispatch has
%nothing left to check. Classifying them here is what makes
%lib_builtin_types.metta affordable: with the file loaded, a workload calling
%== and != went from 102402 inferences to 181602, +77%, and back to 102402
%with these two lines [measured 2026-08-16]. Their own guard is cheaper than
%either, and free on two numbers: a thousand-iteration == loop is 4487.45
%inferences with and without it [measured 2026-08-19]. A user or named-space
%equation overriding either still gets the full typed dispatch, because
%runtime_guarded_builtin_call/1 requires the unmodified builtin.
%
%The declaration was (-> $a $b Bool), two independent variables, which
%constrained nothing and is why (== 1 "S") answered False. Upstream writes
%(-> $t $t Bool) [source: pinned stdlib.md via the arbiter, and measured from
%hyperon 0.2.10's own !(get-type ==) on 2026-08-19].
runtime_type_guarded('==').
runtime_type_guarded('!=').
runtime_type_guarded('>').
runtime_type_guarded('<=').
runtime_type_guarded('>=').
runtime_type_guarded(min).
runtime_type_guarded(max).
runtime_type_guarded(exp).
runtime_type_guarded('#+').
runtime_type_guarded('#-').
runtime_type_guarded('#*').
runtime_type_guarded('#div').
runtime_type_guarded('#//').
runtime_type_guarded('#mod').
runtime_type_guarded('#min').
runtime_type_guarded('#max').
runtime_type_guarded('#<').
runtime_type_guarded('#>').
runtime_type_guarded('#=').
runtime_type_guarded('#\\=').
runtime_type_guarded('#=<').
runtime_type_guarded('#>=').
runtime_type_guarded('pow-math').
runtime_type_guarded('sqrt-math').
runtime_type_guarded('abs-math').
runtime_type_guarded('log-math').
runtime_type_guarded('exp-math').
runtime_type_guarded('trunc-math').
runtime_type_guarded('ceil-math').
runtime_type_guarded('floor-math').
runtime_type_guarded('round-math').
runtime_type_guarded('sin-math').
runtime_type_guarded('cos-math').
runtime_type_guarded('tan-math').
runtime_type_guarded('asin-math').
runtime_type_guarded('acos-math').
runtime_type_guarded('atan-math').
runtime_type_guarded('isnan-math').
runtime_type_guarded('isinf-math').
runtime_type_guarded('min-atom').
runtime_type_guarded('max-atom').
runtime_type_guarded('random-int').
runtime_type_guarded('random-float').
runtime_type_guarded(and).
runtime_type_guarded(or).
runtime_type_guarded(not).
runtime_type_guarded(xor).
runtime_type_guarded(implies).

%The evaluator's catch-all: real errors take the recovery, control
%signals keep flying.
:- meta_predicate catch_recover(0, 0).
catch_recover(Goal, Recovery) :-
    catch(Goal, E, ( control_exception(E) -> throw(E) ; call(Recovery) )).

%Whether a symbol is callable from where we are: a process-wide function that
%no named equation module claims, a function this module defines, or one &self
%defines, since &self is shared. fun_scoped/1 summarizes non-user fun_in/2
%claims. A builtin or user-only function is therefore unambiguous in every
%space and avoids a current-module read in higher-order loops.
%fun_in/2 is only ever asserted by register_fun_in/2, which registers fun/1
%first, so fun_in implies fun. A name that is not a function therefore cannot
%be one here either, and one indexed lookup settles it: the old second clause
%went on to read current_metta_module/1 and two fun_in/2 facts before failing,
%for every non-function head the translator resolves
%[measured 2026-08-15: alpha-unique 4,050,778 to 3,750,772 inferences].
fun_here(F) :- fun(F),
               ( \+ fun_scoped(F) -> true
               ; current_metta_module(Module), fun_here_in(Module, F) ).

%The builtin fallback is what keeps (+ 1 2) working in &self after some other
%named space defines (= (+ $a $b) ...). fun_scoped(N) stops fun_here/1's first
%clause applying process-wide, and without this the name resolved nowhere: one
%named space turned + into inert data in every other space and in engines
%built afterwards [tested: metta_builtin_scoping].
fun_here_in(Module, F) :-
    (   fun_in(Module, F)
    ->  true
    ;   metta_restricted_exec_module(Module, _)
    ->  restricted_callable_name(F)
    ;   metta_exec_module_parent(Module, ParentModule)
    ->  fun_here_in(ParentModule, F)
    ;   metta_self_module(Self), Module \== Self, fun_in(Self, F)
    ->  true
    ;   builtin_fun(F)
    ).

%Register a function and record which module its clauses live in. fun/1 stays
%global because the translator consults it at compile time to decide whether a
%head is a call or data, and that decision has to hold wherever the term is
%compiled; fun_in/2 says where the clauses actually are, so a caller can ask
%whether *this* space defines a symbol rather than whether any space does.
:- dynamic fun_in/2, fun_scoped/1.
%A builtin is visible from every space, and stays visible when a named space
%defines its name. fun_in/2 cannot carry that: it means "an equation or a
%registered operation defines this here", which is exactly the test
%runtime_guarded_builtin_call/1 uses to decide a builtin was overridden. One
%fact for each meaning, so neither reading breaks the other.
:- dynamic builtin_fun/1.
register_builtin_fun(N) :- register_fun(N),
                           register_prolog_arities(N),
                           ( builtin_fun(N) -> true ; assertz(builtin_fun(N)) ).

register_fun_in(Module, N) :- register_fun(N),
                              ( fun_in(Module, N) -> true
                              ; assertz(fun_in(Module, N), FunInRef),
                                record_source_assertion(FunInRef) ),
                              ( metta_self_module(Module) -> true
                              ; fun_scoped(N) -> true
                              ; assertz(fun_scoped(N), ScopedRef),
                                record_source_assertion(ScopedRef) ).

unregister_fun_in(Module, N) :- retractall(fun_in(Module, N)),
                                metta_self_module(Self),
                                ( fun_in(Other, N), Other \== Self
                                  -> true
                                ; restricted_dispatch_name(N)
                                  -> true
                                ; retractall(fun_scoped(N)) ).

unregister_fun_everywhere(N) :- retractall(fun_in(_, N)),
                                retractall(fun_scoped(N)).
:- maplist(register_builtin_fun, [superpose, empty, let, 'let*', '+','-','*','/', '%', min, max, 'new-state', 'change-state!', 'get-state', 'bind!', 'register-token!', 'unregister-token!', 'declare-pre-add!', 'undeclare-pre-add!', 'declare-post-add!', 'undeclare-post-add!', 'space-atom-count', 'has-declared-type', 'space-admission-verdict', 'space-contains',
                          '<','>','==', '!=', '=', '=?', '<=', '>=', and, or, xor, implies, not, exp,
                          'first-from-pair', 'second-from-pair', 'car-atom', 'cdr-atom', 'unique-atom', 'alpha-unique-atom',
                          repr, repra, parse, 'pretty-atom', 'println!', 'readln!', 'read-form!', 'parse-command', test, 'test-no-answer', assert, atom_concat, atom_chars, copy_term, term_hash,
                          foldl, first, last, append, length, 'size-atom', sort, msort, member, 'is-member', 'is-alpha-member', 'exclude-item', list_to_set, maplist, eval, evalc, reduce, 'import!',
                          'git-import!',
                          'add-atom', 'remove-atom', 'add-atoms', 'add-reduct', 'add-reducts', 'get-atoms', match, 'is-var', 'is-ground', 'is-expr', 'is-space',
                          decons, 'decons-atom', noeval, 'new-space',
                          'get-type', 'get-type-space', 'get-metatype', '=alpha', sread, cons, reverse,
                          'get-doc', 'get-doc-space', 'get-doc-atom',
                          'get-doc-single-atom', 'get-doc-function', 'get-doc-params',
                          'help!', documented, 'documented-space',
                          'defined-name', undocumented, 'undocumented-space',
                          '#+','#-','#*','#div','#//','#mod','#min','#max','#<','#>','#=','#\\=','#=<','#>=',
                          'union-atom', 'cons-atom', 'intersection-atom', 'subtraction-atom', 'index-atom', 'atom-subst', id,
                          function, 'collapse-bind', 'superpose-bind',
                          'pow-math', 'sqrt-math', 'sort-atom','abs-math', 'log-math', 'exp-math', 'trunc-math', 'ceil-math',
                          'floor-math', 'round-math', 'sin-math', 'cos-math', 'tan-math', 'asin-math','random-int','random-float',
                          'acos-math', 'atan-math', 'isnan-math', 'isinf-math', 'min-atom', 'max-atom',
                          'foldl-atom', 'map-atom', 'filter-atom','current-time','format-time', 'context-space', library, exists_file,
                          'format-args', 'sort-strings', include,
                          sleep, 'pragma!', metta, 'metta-thread',
                          import_prolog_function, check_prolog_function_names, import_prolog_functions,
                          'Predicate', callPredicate, assertaPredicate, assertzPredicate, retractPredicate,
                          'add-translator-rule!', 'remove-translator-rule!',
                          'add-typing-rule!', 'remove-typing-rule!', argv,
                          register_metta_library_path,
                          dif, 'residual-goals']).
%An EXTENSION's own builtins -- a host bridge's and a backend's alike --
%register here, from that extension's own seam:extension_builtin/2 declarations
%rather than from a list here that would name it. This was two directives over
%two seams, seam:host_builtin/1 and seam:backend_builtin/2, which differed only
%in whether they carried an effect class; the merged seam carries one for
%everybody. Every extension loads earlier in this file's own load order, so its
%facts exist by the time this directive runs, and an engine with none loaded
%registers nothing.
%
%The NAMES are the extension's: it declares them in the file that DEFINES them,
%so they exist exactly when the predicates behind them do. That conditionality
%used to be an argv test in this file, which meant the engine had to know both
%that MORK had builtins and what they were called.
%
%Registering a name whose predicate is absent records no arity, and
%incomplete_application_kind/3 reads "no arity" as "not applied far enough":
%every call to it then compiled to a partial application, so (mm2-exec &mork 1)
%answered (partial mm2-exec (&mork 1)) instead of running or failing. Declaring
%the names beside the predicates is what makes that unable to happen again.
:- forall(seam:extension_builtin(Name, _), register_builtin_fun(Name)).
