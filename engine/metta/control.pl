% Purpose: implement pragmas, limits, control forms, goal construction, and higher-order functions
% Assumes: engine/metta.pl includes this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE]

%%% Interpreter pragmas: %%%
:- dynamic metta_pragma/2.

%The keys this engine KNOWS. Both pragma doors validate against this registry;
%an unsupported setting is a hard error rather than a successful no-op.
%HE's own keys are type-check, interpreter and max-stack-depth
%[source 2026-08-15: MeTTa HE stdlib reference, pragma!]. The two bounds are
%PeTTa's, and are the ones this engine can actually enforce.
metta_pragma_key('max-time', 'bound every runnable by wall-clock seconds').
metta_pragma_key('max-inferences', 'bound every runnable by inference count').
metta_pragma_key('verify-specializations',
                 'check every specialization against the generic call once').
metta_pragma_key('max-stack-depth',
                 'branch-local reduction fuel; zero selects the default').
metta_pragma_key('stack-limit',
                 'scope SWI combined stack bytes for the current thread').
metta_pragma_key('type-check', 'HE spelling; accepted, NOT enforced').
metta_pragma_key(interpreter, 'HE spelling; accepted, NOT enforced').

'pragma!'(Key, _, _) :- var(Key), !, refuse_unbound_input('pragma!', 1).
'pragma!'(Key, _, _) :-
    \+ metta_pragma_key(Key, _),
    !,
    findall(K-D, metta_pragma_key(K, D), Known),
    throw(error(domain_error(metta_pragma_key, Key),
                context('pragma!'/2, Known))).
%max-stack-depth is the ONE key the arbiter validates, and a count is the
%whole of what it validates. The refusal is an ANSWER, not a raise, so the
%program that wrote it keeps running [measured 2026-08-19 against the
%arbiter: -1, 1.5 and abc each answer this error, while
%(pragma! type-check -1) answers (); the plan's closed engine registry
%deliberately makes a completely invented key a hard host-facing error here;
%source: LeaTTa tests/semantics/eval-core/max-stack-depth-negative.metta].
%`none` is the engine's own "unset" sentinel, which petta_restore_pragma/1
%passes back on every scope exit, so it is not a value to validate.
'pragma!'('max-stack-depth', Value, Error) :-
    Value \== none,
    \+ ( integer(Value), Value >= 0 ),
    !,
    Error = ['Error', ['pragma!', 'max-stack-depth', Value],
             'UnsignedIntegerIsExpected'].
%The UNIT value, for the reason add-atom answers it: the standard library
%types this `(-> Symbol %Undefined% (->))` and `(->)` IS the unit type.
'pragma!'(Key, Value, []) :-
    require_metta_pragma_value(Key, Value, 'pragma!'/3),
    set_metta_pragma(Key, Value).

%A bound is active only for the shapes run_under_pragmas/1 consumes. Refusing
%every other value here keeps a stored setting from looking accepted while the
%execution wrapper ignores it. `none` is the explicit disable operation and
%therefore valid for every registered key.
require_metta_pragma_value(_, none, _) :- !.
require_metta_pragma_value('max-time', Value, Door) :- !,
    (   number(Value), Value > 0
    ->  true
    ;   throw(error(domain_error(metta_pragma_value,
                                 ['max-time', Value]),
                    context(Door,
                            'max-time requires a positive number or none')))
    ).
require_metta_pragma_value('max-inferences', Value, Door) :- !,
    (   integer(Value), Value > 0
    ->  true
    ;   throw(error(domain_error(metta_pragma_value,
                                 ['max-inferences', Value]),
                    context(Door,
                            'max-inferences requires a positive integer or none')))
    ).
require_metta_pragma_value('stack-limit', Value, Door) :- !,
    (   integer(Value), Value > 0
    ->  true
    ;   throw(error(domain_error(metta_pragma_value,
                                 ['stack-limit', Value]),
                    context(Door,
                            'stack-limit requires a positive byte count or none')))
    ).
require_metta_pragma_value(_, _, _).

set_metta_pragma(Key, Value) :-
    retractall(metta_pragma(Key, _)),
    (   Value == none
    ->  true
    ;   assertz(metta_pragma(Key, Value))
    ),
    sync_metta_pragma_bounds.

%pragma! scoped to one expression, MeTTaLog's with-pragma! adopted:
%each (key value) pair validates exactly as pragma! validates it, the
%previous values come back on every exit path, reversed so a key set
%twice in one scope restores its true pre-scope value, and the whole
%answer set is computed under the scope, timeout's own rule, so a later
%answer cannot escape it.
metta_with_pragmas(Settings, Goal, Value) :-
    must_be(list, Settings),
    maplist(petta_pragma_pair, Settings, Pairs),
    setup_call_cleanup(
        maplist(petta_apply_pragma, Pairs, Restores),
        %The global bounds wrap call_goals_in, one level above this body,
        %so the scope applies them itself: whatever bounds are in force
        %here, scoped ones included, bound this findall.
        run_under_pragmas(findall(Value, Goal, Values)),
        ( reverse(Restores, Undo),
          maplist(petta_restore_pragma, Undo) )),
    member(Value, Values).

petta_pragma_pair([Key, ValueIn], Key-ValueIn) :- !,
    require_metta_pragma_key(Key, 'with-pragma!'/2),
    require_metta_pragma_value(Key, ValueIn, 'with-pragma!'/2).
petta_pragma_pair(Other, _) :-
    throw(error(domain_error(metta_pragma_setting, Other),
                context('with-pragma!'/2,
                        'each setting is a (key value) pair'))).

require_metta_pragma_key(Key, _) :- metta_pragma_key(Key, _), !.
require_metta_pragma_key(Key, Door) :-
    findall(K-D, metta_pragma_key(K, D), Known),
    throw(error(domain_error(metta_pragma_key, Key), context(Door, Known))).

petta_apply_pragma(Key-Value, Key-Previous) :-
    ( metta_pragma(Key, P) -> Previous = P ; Previous = none ),
    set_metta_pragma(Key, Value).

petta_restore_pragma(Key-Previous) :-
    set_metta_pragma(Key, Previous).

%A bound costs nothing until one is set. call_goals_in/2 runs every runnable
%form, so an unconditional wrapper there is paid by every directive: checking
%two pragmas on each one cost 5 inferences per directive against the
%run-source benchmark's 4-inference allowance [measured 2026-08-15]. Wrapping
%the predicate only while a bound is active is how ext_points.pl keeps atom
%hooks free when nobody is listening, and the same reasoning applies here.
sync_metta_pragma_bounds :-
    (   bounding_pragma_set
    ->  enable_metta_pragma_bounds
    ;   disable_metta_pragma_bounds
    ).

bounding_pragma_set :-
    (   metta_pragma('max-time', Seconds), number(Seconds), Seconds > 0
    ->  true
    ;   metta_pragma('max-inferences', Limit), integer(Limit), Limit > 0
    ->  true
    ;   metta_pragma('stack-limit', StackBytes),
        integer(StackBytes), StackBytes > 0
    ).

enable_metta_pragma_bounds :-
    petta_engine_module(Engine),
    current_predicate_wrapper(Engine:call_goals_in(_, _), metta_pragma_bounds,
                              _, _), !.
enable_metta_pragma_bounds :-
    petta_engine_module(Engine),
    wrap_predicate(Engine:call_goals_in(_Module, _Goals), metta_pragma_bounds,
                   Wrapped, Engine:run_under_pragmas(Wrapped)).

disable_metta_pragma_bounds :-
    petta_engine_module(Engine),
    ( unwrap_predicate(Engine:call_goals_in/2, metta_pragma_bounds)
      -> true ; true ).

%What a bounded runnable form is wrapped in. Reading the pragmas here, rather
%than baking them into the compiled clause, means a pragma set later applies
%to everything after it and nothing before it.
%Expiry throws the RESERVED limit envelopes, the exact shapes
%petta_py_limited throws, so a pragma bound and a per-call kwarg bound
%classify identically one level up: TimeLimitError and
%InferenceLimitError rather than a generic engine error.
run_under_pragmas(Goal) :-
    (   metta_pragma('max-time', Seconds), number(Seconds), Seconds > 0
    ->  Timed = catch(call_with_time_limit(Seconds, Goal),
                      time_limit_exceeded,
                      throw(error(metta_control_signal(time_limit, Seconds),
                                  context(petta, time_limit))))
    ;   Timed = Goal
    ),
    (   metta_pragma('max-inferences', Limit), integer(Limit), Limit > 0
    ->  Inferred = petta_call_with_inference_bound(Timed, Limit)
    ;   Inferred = call(Timed)
    ),
    (   metta_pragma('stack-limit', StackBytes),
        integer(StackBytes), StackBytes > 0
    ->  metta_host_with_stack_limit(StackBytes, Inferred)
    ;   call(Inferred)
    ).

petta_call_with_inference_bound(Goal, Limit) :-
    call_with_inference_limit(Goal, Limit, Result),
    (   Result == inference_limit_exceeded
    ->  throw(error(metta_control_signal(inference_limit, Limit),
                    context(petta, inference_limit)))
    ;   true
    ).

%SWI's stack_limit is a changeable flag local to the calling thread. Its
%push/pop pair is nestable and records absence as well as a prior value; the
%cleanup wrapper performs the pop after deterministic success, failure, cut,
%or exception [source: SWI-Prolog 10.1 Reference Manual, Environment Control,
%https://www.swi-prolog.org/pldoc/man?section=flags; commit=81c50d3ae4c03ddfd70ed3f1ff70e085cfee3978].
metta_host_with_stack_limit(StackBytes, Goal) :-
    must_be(positive_integer, StackBytes),
    setup_call_cleanup(push_prolog_flag(stack_limit, StackBytes),
                       Goal,
                       pop_prolog_flag(stack_limit)).

%Every runnable uses one limit scope. Recursive clauses spend from its
%backtrackable balance, so trying a sibling restores the balance it started
%with. Exhaustion records and fails only that branch; after ordinary answers
%have been enumerated, the recorded unfinished branches are replayed as
%(Error <current-call> StackOverflow). This keeps a completed sibling instead
%of letting an exception discard the generator's remaining choice points.
%A positive max-stack-depth caps the same balance; zero and absence use the
%LeaTTa runner's default 100000 fuel.
%[tested: test_a_stack_depth_pragma_bounds_evaluation_instead_of_overflowing].
:- meta_predicate petta_run_with_fuel(?, ?, 0).

%The test READS AND COMPARES IN ONE GOAL, b_getval/2 unifying the balance with
%`off` rather than binding it and comparing after, which is the same inference
%the nb_current/2 test cost and eight fewer over file-load's runnable forms than
%the two-goal spelling. The value is always an atom or an integer, so the
%unification cannot instantiate the variable the manual warns about.
petta_run_with_fuel(Value, Answer, Goal) :-
    (   b_getval('$petta_fuel_remaining', off)
    ->  setup_call_cleanup(
            petta_open_fuel_scope,
            petta_fuel_answer(Value, Answer, Goal),
            petta_close_fuel_scope)
    ;   call(Goal),
        Answer = Value
    ).

%ONE GLOBAL CARRIES BOTH QUESTIONS, and it always exists so that the reader is
%the deterministic b_getval/2 rather than the nondeterministic nb_current/2.
%`off` says no scope is open, `unstarted` says one is open and the first step
%has not read the pragma yet, and a number is what the scope has left. Lazy
%rather than eager because with-pragma! sets max-stack-depth INSIDE the runnable
%the scope already opened around.
%
%Two things were measured to get here rather than argued.
%  - Separate scope marker and balance cost one extra inference on every
%    reduction, because the step then reads two globals instead of one. The
%    reason it had been split was the fear that backtracking past a trailed
%    b_setval/2 write, after the cleanup removed the variable, would resurrect a
%    nearly-spent balance and starve the next runnable. It does not:
%    tests/prolog/fuel.plt runs the shape that could do it, a scope whose body
%    writes the balance three times and whose caller then backtracks through
%    every one of those writes after the close has run, and the variable reads
%    `absent` or `off` afterwards either way. The manual says the
%    same thing for the creating write: "If the variable Name did not exist
%    before calling b_setval/2, backtracking causes the variable to be deleted"
%    [source: SWI-Prolog 10.1 Reference Manual section 4.33, b_setval/2]. The
%    xdist failures that had been blamed on the merge were a leaked
%    `(pragma! max-stack-depth 20)`, which is engine-wide and outlives the MeTTa
%    object that wrote it; SWI's own non-interactive tracer named the real
%    cause, `trace(user:petta_evaluation_fuel/1, [call,exit])` printing
%    `Exit: petta_evaluation_fuel(20)` inside a freshly built space, and the
%    conftest fixture _pragmas_are_not_left_set now fails the test that leaks
%    one instead of the test that runs next
%    [tested: fuel:a_deleted_global_is_not_resurrected_by_backtracking;
%    commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f]
%    [tested: fuel:an_off_sentinel_is_not_restored_over_by_backtracking;
%    commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f].
%  - nb_current/2 is declared nondeterministic, so every step paid a foreign
%    frame that supports redo, and it consults the exception/3 hook when the
%    variable is missing [source: SWI-Prolog 10.1 Reference Manual section 4.33,
%    nb_current/2]. Keeping the variable defined lets the step use b_getval/2
%    instead at the same inference count and measurably fewer instructions:
%    let-heavy 8,645,929,651 to 8,411,938,971 (-2.71%) and typed-call
%    7,388,289,387 to 7,271,301,502 (-1.58%), every other benchmark inside
%    +/-0.13%
%    [measured 2026-08-22: min-of-3 instructions:u; command=python -m
%    benchmarks.check_instructions; fixture=bindings/python/benchmarks;
%    commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f].
%
%thread_initialization/1 rather than initialization/1 because b_getval/2 raises
%when the variable is missing and global variables are per-thread: it runs the
%goal "at the call to this predicate, after loading a saved state, on starting a
%new thread and on creating a Prolog engine through the C interface", which is
%every way a thread can reach this engine, janus included
%[source: SWI-Prolog 10.1 Reference Manual, thread_initialization/1].
:- thread_initialization(nb_setval('$petta_fuel_remaining', off)).

petta_open_fuel_scope :-
    nb_setval('$petta_fuel_remaining', unstarted),
    nb_setval('$petta_fuel_errors', []).

petta_close_fuel_scope :-
    nb_delete('$petta_fuel_errors'),
    nb_setval('$petta_fuel_remaining', off).

petta_fuel_answer(Value, Answer, Goal) :-
    call(Goal),
    Answer = Value.
petta_fuel_answer(_, ['Error', Culprit, 'StackOverflow'], _) :-
    nb_getval('$petta_fuel_errors', Reverse),
    reverse(Reverse, Errors),
    member(Culprit, Errors).

%THE CHARGE IS BUILT, NOT CALLED. petta_instrument_recursive_clause/3 writes
%this goal into the clause it compiles instead of a call to a shared predicate,
%which is worth a third of what the charge costs: a call cost six inferences per
%charged reduction and the inlined goal costs four, and the same A/B on retired
%instructions reads 8,364,337,018 against 5,495,296,785 over three million
%steps, -34.3%
%[measured 2026-08-22: 6 and 4 inferences, -34.3% instructions:u, min-of-3;
%command=swipl ai-tmp/p14e-step-ab4.pl; fixture=20000 and 3000000 iterations;
%commit=be17bf27ac3fd74b5f5c00e430e924529a54f560]. The cost is a compile-time constant per clause, so it lands
%as a literal in the subtraction.
%
%Eleven shapes of this body were raced before settling on it, and every one that
%reads a global costs the same six inferences as a call, so the `unstarted`
%sentinel and the second comparison are free; a separate scope marker costs
%seven; and a mutable cell read with b_getval/2 and written with setarg/3 is
%2.0% WORSE in instructions than the named global. Going lower means not reading
%a global at all. That is threading the balance as a clause argument, the shape
%a depth-bounded meta-interpreter uses, which changes the arity of every
%compiled recursive predicate and so is a translator decision rather than a
%local one. C does not help either, because a foreign predicate cannot write a
%backtrackable global: libswipl.so.10.1.13 exports 472 functions and none of
%them is a global-variable or trail entry point, so the C body would have to
%call b_setval/2 back through PL_call_predicate and pay a query setup on top of
%the write it was trying to avoid
%[measured 2026-08-22: v1..v5 all 6.0 inferences, cell +2.0% instructions:u,
%472 exported functions none of them a gvar or trail entry point;
%command=swipl ai-tmp/p14e-step-ab2.pl, swipl ai-tmp/p14e-step-ab3.pl, nm -D
%/usr/lib/swi-prolog/lib/x86_64-linux/libswipl.so.10.1.13; commit=be17bf27ac3fd74b5f5c00e430e924529a54f560].
%THE TWO GLOBAL OPERATIONS ARE MODULE-QUALIFIED, and that is not decoration.
%A compiled clause lives in its space's own execution module, and an equation
%for a builtin's name is a LOCAL SHADOW there rather than a refusal, which is
%what keeps `plus` and seventy-seven other ordinary names usable in MeTTa
%[tested: test_a_system_predicate_survives_an_equation_for_its_name]. Written
%bare, `(= (b_setval $a) clash)` in a space would capture the charge in every
%recursive clause that space compiles. `system:` is one percent of the charge's
%instructions and takes the name back off the engine's own path without taking
%it away from the program.
petta_fuel_step_goal(Culprit, Cost,
                     ( system:b_getval('$petta_fuel_remaining', Current),
                       (   Current == off
                       ->  true
                       ;   (   Current == unstarted
                           ->  petta_evaluation_fuel(Limit)
                           ;   Limit = Current
                           ),
                           Remaining is Limit - Cost,
                           (   Remaining =< Cost
                           ->  petta_fuel_exhausted(Culprit)
                           ;   system:b_setval('$petta_fuel_remaining', Remaining)
                           )
                       ) )).

%Off the step's own path, because a branch that ran out of fuel is recorded
%once and then fails, while the step above runs on every reduction.
petta_fuel_exhausted(Culprit) :-
    nb_getval('$petta_fuel_errors', Errors),
    nb_setval('$petta_fuel_errors', [Culprit|Errors]),
    fail.

%%% A seeded scope, the declared alternative to a global generator %%%
%
%The state in force is SAVED and restored, so the scope is dynamic rather than
%a setting: inside it the draws are the ones the seed determines, and outside
%it the generator is exactly where it was. SWI answers both halves directly,
%`random_property(state(S))` to read the generator's whole state and
%`set_random(state(S))` to put it back
%[source: SWI-Prolog 10 manual, section 4.42 Random numbers, set_random/1 and
%random_property/1]. setup_call_cleanup/3 rather than a hand-written restore,
%so an exception or a cut inside the body still restores it
%[tested: test_a_seed_scope_repeats_its_draws_and_leaves_the_outside_alone].
%
%The seed is checked here rather than trusted, and a wrong one ANSWERS in the
%error vocabulary instead of raising, which is what every other operation does
%with an argument it cannot use: `(with-seed "bad" (random-int 1 6))` is
%`(Error (with-seed "bad" (random-int 1 6)) (BadArgType 1 Number String))` and
%the form after it still runs. The written body travels beside the seed VALUE
%so the culprit names the call, which is the shape the arbiter pins for every
%other rejected operand.
:- meta_predicate petta_with_seed(?, ?, 0, ?).

petta_with_seed(Seed, Written, Goal, Out) :-
    (   integer(Seed)
    ->  random_property(state(Saved)),
        setup_call_cleanup(set_random(seed(Seed)),
                           call(Goal),
                           set_random(state(Saved)))
    ;   metta_operation_answer('with-seed', Written, Out)
    ).

petta_evaluation_fuel(Limit) :-
    (   metta_pragma('max-stack-depth', Configured),
        integer(Configured),
        Configured > 0
    ->  Limit = Configured
    ;   Limit = 100000
    ).

%%% MeTTa HE compatibility: %%%
%HE's metta/3 is (-> Atom Type SpaceType Atom), "run the MeTTa interpreter on
%an atom" in a named space. evalc/3 already is exactly that: PeTTa's eval is a
%full evaluation rather than minimal MeTTa's single rewriting step, which its
%own comment records, so this is the HE spelling over it. The Type argument is
%accepted and ignored, as it is for %Undefined% in HE.
%The space test is evalc's, repeated rather than delegated, because a refusal
%has to name the operation the PROGRAM wrote: delegating told a program that
%wrote `metta` about `evalc`
%[tested: builtin_input_guards:every_builtin_refuses_an_unbound_input_by_name].
'metta'(Atom, _Type, Space, Out) :- ( 'is-space'(Space, true)
                                      -> true
                                      ;  throw_metta_type_error(metta,
                                                                'SpaceType',
                                                                Space) ),
                                     evalc(Atom, Space, Out).


%A FRESH SPACE, which PeTTa did not have. Spaces here are named and created on
%demand, so `(new-space)` reduced to nothing and `(bind! &s (new-space))` did
%nothing at all: the program worked anyway because `&s` doubles as a name, and
%that is an accident rather than a design. It answers a fresh unique name, so
%the form means what it says and bind! has something to bind.
:- dynamic petta_space_counter/1.

%The space is REGISTERED here rather than at its first write, because a space
%that has been created exists: `(chain (new-space) $s (get-type $s))` is
%`SpaceType` on hyperon 0.2.10 with nothing written to it
%[source: LeaTTa tests/semantics/spaces/space_identity.metta, STATUS conforms]
%[tested: space_handle_type:a_fresh_space_is_one_before_anything_is_written_to_it].
%Naming a space still registers nothing, which is the property that keeps every
%symbol in a space position from becoming one.
'new-space'(Space) :- gensym('&petta-space-', Space),
                      ensure_native_storage_module(Space, _).
%The one-input form holds its Atom argument as written. A ground expression
%there is an entity identifier, registered before either canonical module is
%created; later SpaceType positions recognize that exact term and no other
%expression as a literal space operand.
'new-space'(Space, Space) :-
    metta_declare_parametric_space(Space).
'new-space'(Child, [inherits, Parent], Child) :- !,
    metta_declare_space_parent(Child, Parent).
'new-space'(Space, [restricted], Space) :- !,
    metta_declare_restricted_space(Space, []).
'new-space'(Space, [restricted, [grants|Capabilities]], Space) :- !,
    metta_declare_restricted_space(Space, Capabilities).
'new-space'(_, Relation, _) :-
    throw(error(type_error(inheritance_declaration, Relation),
                context('new-space',
                        'the second argument is (inherits <parent>)'))).

%%% States: %%%
'bind!'(Var, _, _) :- var(Var), !, refuse_unbound_input('bind!', 1).
%THE TOKEN FORM, which is what the specification says bind! is:
%"(-> Symbol %Undefined% (->)) ... Registers a new token which is replaced with
%an atom during the parsing of the rest of the program"
%[source: metta-lang-docs/corelib-stdlib-reference.md, bind!]. PeTTa had only
%the state-cell form above, so `(bind! six 6)` FAILED SILENTLY and the language's
%own idiom `(bind! abs (py-atom numpy.absolute))` then `(abs -5)` could not work.
%
%The state form has NO clause of its own any more. `(new-state V)` is an
%operation that answers a cell, so the general clause reduces it and binds the
%name to that cell, which is the same thing the specification says bind! does
%with any other value. `(bind! s (new-state 7))` then `(get-state s)` still
%answers 7, now by substituting the cell for the name rather than by using the
%name as the cell [tested: test_a_state_cell_is_a_value_typed_by_what_it_holds].
'bind!'(Var, Value, []) :-
    ( atom(Var)
      -> true
      ;  throw(error(type_error(symbol, Var),
                     context('bind!'/2, 'a token name is a symbol'))) ),
    %"Atom, which is associated with the token AFTER REDUCTION", so the value is
    %evaluated before it is bound: `(bind! &s (new-space))` binds the space, not
    %the expression that makes one.
    ( is_list(Value) , Value \== []
      -> once(reduce(Value, Reduced, _))
      ;  Reduced = Value ),
    register_metta_token(Var, Reduced).

%A token, and the substitution that makes it one. Both are guarded on anything
%being registered at all, so a program that binds no token pays one indexed
%lookup per form it parses and nothing else.
:- dynamic metta_token/2.

register_metta_token(Name, Value) :-
    retractall(metta_token(Name, _)),
    assertz(metta_token(Name, Value)).

%ONE indexed lookup when no token is bound, which is what a token table costs
%and all it costs. A program that binds none pays that per parsed form and
%nothing else; the walk below runs only once something is registered.
substitute_bound_tokens(Term, Out) :-
    metta_token(_, _), !,
    substitute_bound_tokens_(Term, Out).
substitute_bound_tokens(Term, Term).

substitute_bound_tokens_(Term, Out) :- var(Term), !, Out = Term.
substitute_bound_tokens_(Term, Out) :- atom(Term), !,
                                       ( metta_token(Term, Bound)
                                         -> Out = Bound ; Out = Term ).
substitute_bound_tokens_(Term, Out) :- atomic(Term), !, Out = Term.
substitute_bound_tokens_(Term, Out) :- is_list(Term), !,
                                       maplist(substitute_bound_tokens_, Term, Out).
substitute_bound_tokens_(Term, Term).

%&self is the reserved token for the space the code lives in, upstream's
%own reading where &self is a tokenizer substitution for the running
%space. In the CLI the program space is literally named &self, so the
%walk is skipped outright there and nothing changes; a named space (a
%python-created one, or a (new-space) binding) gets its own name wherever
%its source says &self, which is what makes `!(add-atom &self ...)` and
%`(unify &self ...)` mean "this space" in library-hosted programs too.
%It substitutes where the engine's own bind! tokens substitute, the
%parsed-form rewrite, so stored data expressions keep their literal
%atoms exactly as they do for every other token.
metta_substitute_self('&self', Term, Term) :- !.
metta_substitute_self(Space, Term, Out) :-
    substitute_self_walk_(Term, Space, Out).

substitute_self_walk_(Term, Space, Out) :- atom(Term), !,
                                           ( Term == '&self'
                                             -> Out = Space ; Out = Term ).
substitute_self_walk_(Term, _, Out) :- atomic(Term), !, Out = Term.
substitute_self_walk_(Term, Space, Out) :-
    is_list(Term), !,
    substitute_self_list_(Term, Space, Out).
substitute_self_walk_(Term, _, Term).

substitute_self_list_([], _, []).
substitute_self_list_([Term|Terms], Space, [Out|Outs]) :-
    substitute_self_walk_(Term, Space, Out),
    substitute_self_list_(Terms, Space, Outs).

%Every rewrite a freshly parsed form gets before anything else reads it.
%The guards inline rather than calls to guarded predicates: each of
%those costs its own call on top of its lookup, and this runs on every
%form a source load parses. The &self walk is gated by a C substring
%probe of the form's own source text, so a form that never says &self
%pays a flat few inferences however large its data is: the unguarded
%walk cost alpha-unique's counter +12% and every runnable +10, caught by
%the gate.
rewrite_parsed_form(Space, FormStr, Term, Rewritten) :-
    (   Space == '&self'
    ->  Term1 = Term
    ;   string(FormStr)
    ->  (   sub_string(FormStr, _, _, _, "&self")
        ->  metta_substitute_self(Space, Term, Term1)
        ;   Term1 = Term
        )
    ;   atom(FormStr)
    ->  (   sub_atom(FormStr, _, _, _, '&self')
        ->  metta_substitute_self(Space, Term, Term1)
        ;   Term1 = Term
        )
    ;   %No source text to probe: walk, correctness over the shortcut.
        metta_substitute_self(Space, Term, Term1)
    ),
    (   seam:form_rewriter(Rewriter)
    ->  call(Rewriter, Term1, Bound)
    ;   Bound = Term1
    ),
    (   metta_token(_, _)
    ->  substitute_bound_tokens_(Bound, Rewritten)
    ;   Rewritten = Bound
    ).
%%% A state cell is a VALUE, and the value is parametric in what it holds %%%
%
%`(new-state 5)` answers a cell of its own, so a cell can be passed, stored,
%held in a data structure and written through without ever being named:
%`(get-state (change-state! (new-state 1) 2))` is 2 and `(new-state (new-state
%5))` is a cell holding a cell. The upstream signature says exactly this, and
%it is where `(StateMonad $t)` comes from:
%  (: new-state (-> $t (StateMonad $t)))
%  (: get-state (-> (StateMonad $t) $t))
%  (: change-state! (-> (StateMonad $t) $t (StateMonad $t)))
%[source: LeaTTa tests/semantics/grounded/25-state-rendering.metta, STATUS
%conforms, whose transcript has `!(new-state 5)` answering a cell and
%`!(change-state! (new-state 5) 6)` answering the cell it wrote]
%[tested: test_a_state_cell_is_a_value_typed_by_what_it_holds].
%
%THE CELL IS A HANDLE ATOM, `&state-#N`, the same shape a space handle takes
%here, and the value lives under that name in a process-shared dynamic store.
%A thread-local nb_setval store made the main evaluator and a held SWI answer
%engine see different cells. Dynamic assertions are equally non-backtrackable
%and visible to both engines. This also keeps the NAMED form working unchanged:
%a plain symbol is a cell name too, so `(change-state! &openai_client V)` in
%lib/lib_llm.metta still writes a cell nothing allocated, and the two spellings
%are one implementation rather than two.
%
%DIVERGENCE, measured and recorded rather than closed: the arbiter RENDERS a
%cell as `(State <value>)` and this engine renders it as its handle, `&state-#0`,
%which is what it already does for a space handle. The rendering is presentation
%in a printer with a round-trip obligation (swrite/2 is sread/2's inverse), so
%it is a separate change from the parametric cell this row asked for
%[source: the same file's MEASURED block, `[(State 6)]` where this answers
%`[&state-#0]`].
:- dynamic petta_state_counter/1, petta_state_value/2.

'new-state'(Value, Cell) :-
    petta_next_state_cell(Cell),
    petta_set_state(Cell, Value).

petta_next_state_cell(Cell) :-
    with_mutex('$petta_state_cells',
               ( ( retract(petta_state_counter(N)) -> true ; N = 0 ),
                 Next is N + 1,
                 assertz(petta_state_counter(Next)) )),
    atom_concat('&state-#', N, Cell).

petta_state_cell(X) :- atom(X), atom_concat('&state-#', _, X).

%change-state! ANSWERS THE CELL it wrote, which is what makes a write
%composable: `(get-state (change-state! $c 2))` reads back what was just
%written. It answered True before, which no upstream signature has.
'change-state!'(Var, Value, Var) :-
    catch(( must_be(atom, Var), petta_set_state(Var, Value) ), E,
          rethrow_metta_operation_error('change-state!', E)).
'get-state'(Var, Value) :-
    ( atom(Var), petta_state_value(Var, Value)
    -> true
    ; catch(nb_getval(Var, Value), E,
            rethrow_metta_operation_error('get-state', E)) ).

petta_set_state(Var, Value) :-
    copy_term(Value, Stored),
    with_mutex('$petta_state_cells',
               ( retractall(petta_state_value(Var, _)),
                 assertz(petta_state_value(Var, Stored)) )).

%%% Eval: %%%
%eval runs its goals in the current space's module, for the same reason
%call_goals_in/2 and current_metta_space/1 exist: call/1 resolves a goal in the
%module its clause was compiled in, so a module-blind call/1 reaches only user.
%Without this, `!(eval (f 1))` on a function defined in any space other than
%&self raised `call_goals/1: Unknown procedure: f/2` while the same `!(f 1)`
%answered normally, and every named space PyPeTTa creates hit it. lib_he's
%`unify` and the ToResult asserts route their branches through eval, so they
%failed there too [tested: test_per_space.py::test_eval_uses_the_spaces_own_equations].
%There is no unset case any more: current_metta_module/1 answers &self's own
%module when nothing is in force, and a bare call/1 would resolve in the
%ENGINE's module, which is the parent and cannot see a space's clauses. The
%two-branch version and the call_goals/1 it needed are gone with it.
%Spelling the branch out here instead was measured and bought nothing
%[measured 2026-08-19: handle-round-trip 1,950,077 either way].
%eval takes its argument as written: &self resolved at the reader if the
%expression came from source, and a runtime-built term keeps its literal
%atoms, the same boundary stored data has. A substitution walk here re-ran
%the reader's work on every eval and found nothing.
eval(C0, Out) :- translate_runnable_expr(C0, Goals, Out),
                 current_metta_module(Module),
                 call_goals_in_(Module, Goals).

%evalc is eval in a space you name, the counterpart to context-space, which
%reports the space eval is already running in. Naming the space is the only
%way to reach another space's equations from MeTTa: import! loads a file into
%one, and everything else runs where it was written.
%
%The space argument selects the module the goals resolve in and nothing else.
%PeTTa's eval is a full evaluation of compiled goals rather than the single
%rewriting step of minimal MeTTa, and evalc keeps that, so the two agree
%everywhere except which space's equations answer
%[source: LeaTTa stdlib.md, evalc's SpaceType is the "Space to
%evaluate atom in its context"] [tested: metta_evalc].
%
%A space is either an atom beginning with & or a registered ground expression,
%which is what is-space/2 tests, so anything else is a type error rather than a
%silently empty space.
%Like eval, evalc takes the expression as written: &self inside it named
%the space hosting the SOURCE (the reader pinned it there), not the space
%evalc is aimed at, so there is nothing left to substitute at run time.
evalc(C0, Space, Out) :- ( 'is-space'(Space, true)
                          -> true
                          ;  throw_metta_type_error(evalc, 'SpaceType', Space) ),
                        space_module(Space, Module),
                        with_metta_module(Module, eval(C0, Out)).

%Goals run in a named module, so a form run against a space reaches that
%space's own equations. call/1 resolves in the module its clause was
%compiled in, which is why the module has to be named rather than inherited.
%The space's module is in force while the goals run, not only while they were
%compiled. Anything consulting the current space at call time needs it: get-type
%does, so without this a `(: a A)` written in a named space was invisible to
%`!(get-type a)` even though the two ran in the same space.
call_goals_in(Module, Goals) :- with_metta_module(Module, call_goals_in_(Module, Goals)).

call_goals_in_(_, []).
call_goals_in_(Module, [G|Gs]) :- call(Module:G),
                                  call_goals_in_(Module, Gs).

%%% Higher-Order Functions: %%%
'foldl-atom'(L, _, _, _) :- var(L), !, refuse_unbound_input('foldl-atom', 1).
'foldl-atom'([], Acc, _Func, Acc).
'foldl-atom'([H|T], Acc0, Func, Out) :- reduce([Func,Acc0,H], Acc1, _),
                                        'foldl-atom'(T, Acc1, Func, Out).

'map-atom'(L, _, _) :- var(L), !, refuse_unbound_input('map-atom', 1).
'map-atom'([], _Func, []).
'map-atom'([H|T], Func, [R|RT]) :- reduce([Func,H], R, _),
                                   'map-atom'(T, Func, RT).

'filter-atom'(L, _, _) :- var(L), !, refuse_unbound_input('filter-atom', 1).
'filter-atom'([], _Func, []).
'filter-atom'([H|T], Func, Out) :- ( reduce([Func,H], true, _) -> Out = [H|RT]
                                                             ; Out = RT ),
                                   'filter-atom'(T, Func, RT).
