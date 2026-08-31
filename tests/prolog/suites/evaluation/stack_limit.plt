% Purpose: prove that the host and pragma stack ceilings are dynamically scoped.
% Assumes:
%   - SWI-Prolog exposes the current thread's combined stack ceiling as the
%     changeable `stack_limit` flag.
% Guarantees:
%   - success, failure, exception, and nesting restore the exact prior ceiling
%     [tested: scoped_stack_limit; commit=81c50d3ae4c03ddfd70ed3f1ff70e085cfee3978]
%   - `stack-limit` is a byte ceiling distinct from reduction fuel's
%     `max-stack-depth` [tested: scoped_stack_limit; commit=81c50d3ae4c03ddfd70ed3f1ff70e085cfee3978]
%   - loading this suite under the gate never runs the standalone CLI against
%     the gate's argv [tested: scoped_stack_limit with argv extensions;
%     commit=4d6e1a458de31af0c779dc051b3892a35b17df69]
% Fails when:
%   - a caller expects one thread's temporary ceiling to mutate another
%     already-running thread; SWI flags are thread-local.
% Owns resources:
%   - each scope owns one pushed Prolog flag and pops it on every exit path.

:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').
:- ensure_loaded('../../../../extensions/python/metta/shim.pl').

raised_stack_limit(Limit) :-
    current_prolog_flag(stack_limit, Current),
    Limit is Current + 1048576.

:- begin_tests(scoped_stack_limit).

test(success_restores_the_previous_limit) :-
    current_prolog_flag(stack_limit, Before),
    raised_stack_limit(Limit),
    metta_host_with_stack_limit(Limit, current_prolog_flag(stack_limit, Inside)),
    current_prolog_flag(stack_limit, After),
    Inside =:= Limit,
    After =:= Before.

test(failure_restores_the_previous_limit) :-
    current_prolog_flag(stack_limit, Before),
    raised_stack_limit(Limit),
    \+ metta_host_with_stack_limit(Limit, fail),
    current_prolog_flag(stack_limit, After),
    After =:= Before.

test(exception_restores_the_previous_limit) :-
    current_prolog_flag(stack_limit, Before),
    raised_stack_limit(Limit),
    catch(metta_host_with_stack_limit(Limit, throw(stack_probe)), stack_probe, true),
    current_prolog_flag(stack_limit, After),
    After =:= Before.

test(nested_scopes_restore_in_lifo_order) :-
    current_prolog_flag(stack_limit, Before),
    Outer is Before + 1048576,
    Inner is Outer + 1048576,
    metta_host_with_stack_limit(
        Outer,
        ( current_prolog_flag(stack_limit, OuterSeen),
          metta_host_with_stack_limit(
              Inner, current_prolog_flag(stack_limit, InnerSeen)),
          current_prolog_flag(stack_limit, OuterAgain) )),
    current_prolog_flag(stack_limit, After),
    OuterSeen =:= Outer,
    InnerSeen =:= Inner,
    OuterAgain =:= Outer,
    After =:= Before.

test(scoped_pragma_applies_bytes_and_restores) :-
    current_prolog_flag(stack_limit, Before),
    Limit is Before + 1048576,
    metta_with_pragmas(
        [['stack-limit', Limit]], current_prolog_flag(stack_limit, Seen), Seen),
    current_prolog_flag(stack_limit, After),
    Seen =:= Limit,
    After =:= Before,
    \+ metta_pragma('stack-limit', _).

test(reduction_fuel_does_not_change_the_swi_stack_ceiling) :-
    current_prolog_flag(stack_limit, Before),
    metta_with_pragmas(
        [['max-stack-depth', 200000]], current_prolog_flag(stack_limit, Seen), Seen),
    current_prolog_flag(stack_limit, After),
    Seen =:= Before,
    After =:= Before,
    \+ metta_pragma('max-stack-depth', _).

test(a_nonpositive_byte_limit_is_refused,
     [throws(error(domain_error(metta_pragma_value, ['stack-limit', 0]), _))]) :-
    metta_with_pragmas([['stack-limit', 0]], true, _).

%A scope's restore has to be TOTAL. maplist/2 over the undo list stops at the
%first key that raises or fails, and every key after it stays in force for the
%rest of the process, which is exactly the engine-wide leak the scoped form
%exists to prevent. Driven here directly, because no key's WRITE can fail
%today -- set_metta_pragma/2 accepts foo, -1 and 1.5 for max-stack-depth
%without a word -- so the only way to reach the path from a test is to hand
%the loop a pair it cannot restore.
test(a_restore_that_fails_still_restores_the_rest,
     [ setup(( set_metta_pragma('max-stack-depth', 5),
               set_metta_pragma('max-inferences', 7) )),
       cleanup(( set_metta_pragma('max-stack-depth', none),
                 set_metta_pragma('max-inferences', none) )) ]) :-
    metta_restore_pragmas([not_a_pair,
                           'max-stack-depth'-none,
                           'max-inferences'-none],
                          First),
    %Every key after the bad one came back,
    \+ metta_pragma('max-stack-depth', _),
    \+ metta_pragma('max-inferences', _),
    %and the first problem is the one reported, with the pair that caused it.
    First = error(metta_pragma_not_restored(not_a_pair), _).

:- end_tests(scoped_stack_limit).
