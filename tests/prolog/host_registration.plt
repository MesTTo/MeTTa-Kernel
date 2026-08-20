% Purpose: the host registration lifecycle, the four services a binding
%   registers operations through: open proves a name free before any write,
%   adopt makes an asserted dispatch clause a claimed function, drop retires
%   one arity, forget releases a name nothing defines. And the engine-side
%   repair those services ride on: a function change or removal recompiles
%   dependent definitions in the ENGINE, with no host observer installed.
% Guarantees:
%   - a taken name refuses at open, before anything has been asserted
%     [tested: a_taken_name_refuses_before_any_write and
%     the_protected_core_refuses_naming_the_owner].
%   - the recompile no longer rides a host's event clause
%     [tested: the_engine_recompiles_dependents_without_a_host].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

:- begin_tests(host_registration).

% A dispatch clause the way a binding would assert one: result is the last
% argument, the body host-free so the suite needs no host.
adopt_probe_operation(Name, Value) :-
    metta_self_module(Base),
    Head =.. [Name, Result],
    assertz(Base:(Head :- Result = Value)),
    metta_host_adopt_function(Name, python, det, 1).

drop_probe_operation(Name) :-
    metta_host_drop_function(Name, 1),
    metta_host_forget_function(Name).

test(a_taken_name_refuses_before_any_write,
     [ cleanup(drop_probe_operation('zzz-owned')),
       throws(error(permission_error(register, metta_function, 'zzz-owned'),
                    _)) ]) :-
    metta_host_open_function('zzz-owned', python, 1),
    adopt_probe_operation('zzz-owned', 1),
    % A second tier asking for the same name is refused by the claim, and
    % the refusal arrives from OPEN, while the second tier has written
    % nothing yet.
    metta_host_open_function('zzz-owned', prolog, 1).

test(the_protected_core_refuses_naming_the_owner,
     [ throws(error(petta_op_name_taken(sort, 1, 2, system), _)) ]) :-
    % sort/2 is SWI's protected core: no module may redefine it, so the
    % probe's assert raises and the refusal names the owning module.
    metta_host_open_function(sort, python, 2).

test(an_adopted_name_is_a_function_and_claimed,
     [ cleanup(drop_probe_operation('zzz-adopted')) ]) :-
    metta_host_open_function('zzz-adopted', python, 1),
    adopt_probe_operation('zzz-adopted', 7),
    fun('zzz-adopted'),
    arity('zzz-adopted', 1),
    metta_function_origin('zzz-adopted', python, det),
    metta_self_module(Base),
    Goal =.. ['zzz-adopted', Answer],
    call(Base:Goal),
    Answer == 7.

test(a_dropped_arity_leaves_other_arities_standing,
     [ cleanup(( metta_host_drop_function('zzz-arities', 1),
                 metta_host_forget_function('zzz-arities') )) ]) :-
    metta_host_open_function('zzz-arities', python, 1),
    metta_host_open_function('zzz-arities', python, 2),
    adopt_probe_operation('zzz-arities', 1),
    metta_self_module(Base),
    assertz(Base:('zzz-arities'(X, R) :- R = X)),
    metta_host_adopt_function('zzz-arities', python, det, 2),
    metta_host_drop_function('zzz-arities', 2),
    \+ arity('zzz-arities', 2),
    arity('zzz-arities', 1),
    fun('zzz-arities').

test(a_forgotten_name_reads_as_data_again,
     [ cleanup(remove_sexp('&self', [=, [_], _])) ]) :-
    % An equation whose body mentions a name that is not a function compiles
    % the mention as DATA; registering the name recompiles it into a CALL,
    % and forgetting recompiles it back. The answer under reduce/2 is the
    % witness at each stage.
    sread("(= (zzz-caller) (zzz-callee))", Equation),
    metta_add_atom('&self', Equation, true),
    metta_host_open_function('zzz-callee', python, 1),
    adopt_probe_operation('zzz-callee', 42),
    metta_self_module(Self),
    with_metta_module(Self, reduce(['zzz-caller'], Called)),
    Called == 42,
    metta_host_drop_function('zzz-callee', 1),
    metta_host_forget_function('zzz-callee'),
    with_metta_module(Self, reduce(['zzz-caller'], After)),
    After == ['zzz-callee'].

test(the_engine_recompiles_dependents_without_a_host) :-
    % The load-bearing half of the changed/removed EVENTS lived in a host
    % hook clause, so an engine alone could not repair compiled mentions.
    % This runs the whole cycle with no host in the process: the plunit
    % process has no Python, and the recompile rides function_changed/2 and
    % function_removed/1 in the engine.
    sread("(= (zzz-watcher) (zzz-moved))", Equation),
    metta_add_atom('&self', Equation, true),
    metta_host_open_function('zzz-moved', python, 1),
    adopt_probe_operation('zzz-moved', moved),
    metta_self_module(Self),
    with_metta_module(Self, reduce(['zzz-watcher'], First)),
    First == moved,
    drop_probe_operation('zzz-moved'),
    with_metta_module(Self, reduce(['zzz-watcher'], Second)),
    Second == ['zzz-moved'],
    remove_sexp('&self', [=, [['zzz-watcher']|_], _]).

:- end_tests(host_registration).
