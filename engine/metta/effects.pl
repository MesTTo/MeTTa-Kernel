% Purpose: classify compiled effects, compose the five-rank effect lattice, and manage memoization, dependencies, and bridge cascades
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees:
%   - every definition retains engine/metta.pl's implementation module and original load order.
%   - metta_host_goal_repeatable/2 exposes one fail-closed host question over
%     the shared effect walk without consuming control limits, so bindings
%     never reconstruct its private queue protocol [tested:
%     metta_effects:the_host_repeatability_question_fails_closed,
%     metta_effects:the_host_repeatability_question_preserves_inference_limits;
%     commit=6917bef7ca902671999eafcae3a7a86db8f69723].
%   - deprecation declarations are reflected by exact name and appear in an
%     operation explanation with their since and remedy values [tested:
%     a_deprecation_row_drives_lookup_and_explanation; commit=WORKTREE].
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%%% Walking a compiled body for the effects a cache would hide %%%%
%
%One walk, shared by everything that may hand back a CACHED answer later.
%Tabling and memoization both do, and both were written with their own idea of
%what is safe: tabling's followed calls and treated everything it did not
%recognise as inert, and memoization's had nothing at all beyond a deny-list of
%names a library could mark volatile. The same body was sound for one and
%unsound for the other with no way to compare the two judgements.
%
%What it answers is the SPACE READS reachable from a root, as read/3 terms, and
%what it refuses is any goal not known pure. The reads are reported rather than
%interpreted, because interpreting them is exactly where the two callers
%differ: tabling resolves each to a storage predicate and invalidates the table
%when that predicate changes, and memoization has no such machinery, so a read
%it cannot invalidate on is a refusal there and ordinary work here.
%
%[source: ai-metta-python-seams.md item 1, which measured the fail-open default
%accepting seven impure categories and caching four of them wrongly].
metta_effect_walk(Module, Roots, Reads) :-
    metta_effect_walk_(Module, Roots, [], [], Raw),
    sort(Raw, Reads).

%One host-neutral question over one already-compiled goal. The internal body
%classifier discovers direct reads and queues called predicates; the public
%walk follows that queue. Any unknown goal or classifier failure means the
%caller must consume its held cursor instead of evaluating a second time.
metta_host_goal_repeatable(Module, Body) :-
    catch_recover(
        ( metta_effect_body(Module, Body, []-[], Roots-_),
          metta_effect_walk(Module, Roots, _) ),
        fail).

metta_effect_walk_(_, [], _, Reads, Reads).
metta_effect_walk_(Module, [PI|Rest], Seen, Reads0, Reads) :-
    memberchk(PI, Seen), !,
    metta_effect_walk_(Module, Rest, Seen, Reads0, Reads).
metta_effect_walk_(Module, [Name/Arity|Rest], Seen, Reads0, Reads) :-
    functor(Head, Name, Arity),
    findall(Body, catch_recover(clause(Module:Head, Body), fail), Bodies),
    foldl(metta_effect_body(Module), Bodies, Rest-Reads0, Next-Reads1),
    metta_effect_walk_(Module, Next, [Name/Arity|Seen], Reads1, Reads).

metta_effect_body(Module, Body, Queue0-Reads0, Queue-Reads) :-
    findall(Goal, metta_effect_goal(Body, Goal), Goals),
    foldl(metta_effect_classify(Module), Goals, Queue0-Reads0, Queue-Reads).

%The goals of a compiled body, conjunctions and control constructs opened. A
%construct NOT opened here is judged as one goal, which under a refusing
%default means refused: catch/3 was missing and hid everything inside it.
%A control construct is inert BECAUSE its goal arguments were walked, and not
%because its name is on a list. Those are two different claims and treating
%them as one is what let `collapse` through: the walk descended wrappers only
%at arity ONE, so the findall/3 the translator emits for collapse and the
%forall/2 it emits for forall fell to the catch-all, and then a name list said
%both were inert. A body refused in the open was accepted one word inside a
%collapse, and cached a random draw
%[tested: lib_tabling_purity:an_impure_goal_is_refused_inside_every_wrapper].
%
%So the shape changed rather than the list. metta_effect_construct/2 says which
%ARGUMENTS of a construct hold goals, the walk yields those and nothing for the
%construct itself, and a construct that is not there is a leaf that gets
%refused by name. This is cut_in_clause_scope/1's closed shape, where an
%unrecognised construct cannot silently become harmless; the open shape had
%already missed catch/3 once before it missed these two.
metta_effect_goal(Body, _) :- var(Body), !, fail.
metta_effect_goal(Construct, Goal) :-
    compound(Construct),
    metta_effect_construct(Construct, Inners), !,
    member(Inner, Inners),
    metta_effect_goal(Inner, Goal).
metta_effect_goal(Goal, Goal).

%Every goal-bearing argument of each control construct a compiled body can
%contain. Written as the construct's own shape rather than as name and arity,
%so an argument that is a TEMPLATE rather than a goal cannot be walked as one:
%findall/3 holds a goal in argument two and terms in one and three.
%
%What is deliberately NOT here is as load-bearing as what is. foldall/4,
%with_mutex/2 and transaction/1 are refused today purely by being absent, and
%that stays: a refusal is loud and someone fixes it, where a wrong entry here
%is a silent wrong answer. This is the allow-list asymmetry the seam is built
%on, applied to the walk as well as to the names.
metta_effect_construct((A, B), [A, B]).
metta_effect_construct((A ; B), [A, B]).
metta_effect_construct((A -> B), [A, B]).
metta_effect_construct((A *-> B), [A, B]).
metta_effect_construct(\+ A, [A]).
metta_effect_construct(call(A), [A]).
metta_effect_construct(once(A), [A]).
metta_effect_construct(catch(A, _, Recovery), [A, Recovery]).
metta_effect_construct(findall(_, A, _), [A]).
metta_effect_construct(forall(A, B), [A, B]).
%take/2's own two forms. metta_take_match/5 is a bounded match and reports as
%the read it is, which metta_effect_classify/4 does from the shape below.
metta_effect_construct(metta_take(_, A), [A]).
%top's plain form likewise calls its goal; metta_top_match/5 is a read the
%classifier judges from its shape as it does the bounded take.
metta_effect_construct(metta_top(_, A, _), [A]).
%The six-axis dispatcher wraps the generated direct goal. Its policy reads are
%invalidated through the support graph; the wrapped goal is still where any
%effect lives, so the purity walk must descend it rather than refuse the
%engine helper or, worse, call the helper pure as a whole.
metta_effect_construct(dispatch_policy_execute(_, _, _, Goal, _), [Goal]).
%A MODULE-QUALIFIED goal holds its effect in the goal, not in the module, and
%it has to be here rather than left to the meta_predicate clause below: that
%clause reads `functor(Meta, Name, Arity)` for a `:`/2 term, SWI answers a
%meta_predicate spec belonging to an unrelated predicate of that name and
%arity, and the walk then yielded the MODULE ATOM. A body carrying
%`system:b_setval(K, V)` was refused as `system/0`, naming an operator the
%program never wrote and advising a declaration for a module. The engine writes
%a qualifier where a space-local equation of the same name must not capture the
%goal, which the inlined fuel charge relies on
%[tested: test_a_cached_definition_tables_and_answers_from_its_trie].
metta_effect_construct(_:Goal, [Goal]).
%Anything else that CALLS one of its arguments, read from SWI's own
%meta_predicate declaration rather than from a list here. This clause is last,
%so every construct above keeps its exact handling and this catches the rest.
%
%It exists because a list of meta-predicates drifts the same way the list of
%control constructs did, and had: maplist/3 and foldl/4 are what the collection
%forms compile to, `maplist` and `foldl` are ALSO MeTTa builtins declared pure,
%and the classifier judges by NAME, so the wrapper was inert and what it called
%was never looked at. `(map-atom $l $x (random-int 1 1000000))` tabled clean
%and answered one draw twice [measured 2026-08-17], which is the collapse
%defect in two more wrappers.
%
%SWI says which argument is called and how many arguments it is called WITH:
%maplist(2,?,?) is argument one applied to two more, foldl(3,+,+,-) to three.
%Reading that covers include/3, exclude/3 and whatever a library adds next,
%none of which anyone would have listed.
metta_effect_construct(Meta, [Goal]) :-
    functor(Meta, Name, Arity),
    functor(Head, Name, Arity),
    predicate_property(Head, meta_predicate(Spec)),
    arg(Position, Spec, Extra),
    integer(Extra),
    arg(Position, Meta, Closure),
    nonvar(Closure),
    metta_effect_closure(Closure, Extra, Goal).

%A closure applied to the arguments its meta-predicate will add. The already
%bound arguments are KEPT, which is what makes the two-step case work:
%include/3 holds metta_condition_holds(lambda_3), and losing that would leave
%the walk classifying metta_condition_holds/2 and never reaching the lambda.
metta_effect_closure(Closure, Extra, Goal) :-
    (   atom(Closure)
    ->  Name = Closure, Bound = []
    ;   compound(Closure), Closure =.. [Name|Bound]
    ),
    length(Added, Extra),
    append(Bound, Added, Args),
    Goal =.. [Name|Args].

%A space read is REPORTED; a call to another MeTTa function is followed; a
%known-pure operation is inert; anything else is refused.
metta_effect_classify(_, Goal, Queue-Reads, Queue-Reads) :-
    var(Goal), !.
metta_effect_classify(_, match(Space, Pattern, _, _), Queue-Reads0,
                      Queue-[read(match, Space, Pattern)|Reads0]) :- !.
%A bounded match is the SAME read, and saying so here is not a tidiness: an
%unreported read is never invalidated, so a table built from
%`(once (match &s (, ...) ...))` would have outlived the write that changed it
%[tested: lib_tabling_purity:a_bounded_match_reports_the_read_it_is].
metta_effect_classify(_, match_bounded(_, Space, Pattern, _, _), Queue-Reads0,
                      Queue-[read(match, Space, Pattern)|Reads0]) :- !.
metta_effect_classify(_, 'get-atoms'(Space, Pattern), Queue-Reads0,
                      Queue-[read('get-atoms', Space, Pattern)|Reads0]) :- !.
%A count observes the whole space: every write to any arity moves it. The
%'count' pattern is deliberately not a list, so a resolver that maps reads
%to fixed storage predicates lands on its unresolved-read refusal instead
%of tabling a number every write stales.
metta_effect_classify(_, 'space-atom-count'(Space, _), Queue-Reads0,
                      Queue-[read('space-atom-count', Space, count)|Reads0]) :- !.
%The probed atom IS the read's pattern: where it is an expression the
%tabling admission can resolve the read like a match's, and a scalar
%probe falls to the same conservative refusal a count does.
metta_effect_classify(_, 'space-contains'(Space, Atom, _), Queue-Reads0,
                      Queue-[read('space-contains', Space, Atom)|Reads0]) :- !.
%A bridge's dispatch goal is classified under the OPERATION's name, not the
%dispatcher's. Ahead of the generic compound clause because that clause would
%read the functor and refuse petta_py_dispatch_det/3, naming an internal the
%program never wrote and advising a declaration that could not be matched.
metta_effect_classify(Module, Dispatch, Queue-Reads, Next-Reads) :-
    compound(Dispatch),
    seam:effect_operation_name(Dispatch, Name, Arity), !,
    metta_effect_named_call(Module, Name, Arity,
                            Queue-Reads, Next-Reads).

%reduce/3 is the engine's RUNTIME dispatcher: it takes a MeTTa term and calls
%whatever function heads it, so refusing it by its own name says nothing about
%the program. `(forall (gen $k) True)` compiles its generator and its test to
%two reduce/3 goals, and once forall/2 was descended, a wholly pure body was
%refused as `reduce/3`.
%
%The head is fixed while COMPILING for every template a source program can
%write, so the call it reaches is known here and is classified exactly as a
%direct call to it would be. A head that is a VARIABLE is a higher-order call
%whose target is decided by a value the walk cannot see, and that is refused
%under its own description rather than the dispatcher's
%[tested: lib_tabling_purity:a_pure_body_inside_a_wrapper_still_tables,
%a_higher_order_call_is_refused_as_one].
metta_effect_classify(Module, reduce(Template, _, _), Queue, Next) :- !,
    metta_effect_reduced(Module, Template, Queue, Next).

%petta_dynamic_call/3 is the variable-head application door: the call it
%reaches is decided by a value, which is exactly the case the reduce/3 walk
%above refuses as higher-order, so it is classified by the same
%reconstruction rather than refused under the dispatcher's own name
%[tested: lib_tabling_purity:a_higher_order_call_is_refused_as_one;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_effect_classify(Module, petta_dynamic_call(Head, Args, _), Queue,
                      Next) :- !,
    metta_effect_reduced(Module, [Head|Args], Queue, Next).
%The value half of the same door: the head decides the call exactly as
%above, and the finished values stand where the written arguments stood.
metta_effect_classify(Module, petta_dynamic_value_call(Head, _, Values, _),
                      Queue, Next) :- !,
    metta_effect_reduced(Module, [Head|Values], Queue, Next).
%The branch guard reads one indexed register row and binds nothing.
metta_effect_classify(_, petta_dynamic_head_masks(_), Queue, Queue) :- !.

%The evaluation mask's result half is a CONDITIONAL reduce/3 over the value an
%equation body handed back, so it is classified by that value and not by its
%own name. Judging it by name refused `(= (past-tabled $x) $x)` as
%metta_impure_goal(metta_masked_result/2), naming an engine internal the
%program never wrote. The former diagnostic also advised the old
%seam:pure_operation/1 extension declaration, which would have been false:
%the goal DOES re-enter evaluation, it just re-enters
%evaluation of a term the walk can read
%[tested: test_a_recycled_space_name_inherits_no_clauses_from_its_past_life].
metta_effect_classify(Module, metta_masked_result(Template, _), Queue, Next) :- !,
    metta_effect_masked_result(Module, Template, Queue, Next).

%A BUILTIN is judged by declaration and a USER function by its body, and the
%order matters twice over. A builtin's implementation is engine Prolog nobody
%can declare pure, so following it reports the wrong thing: `(py-call ...)` was
%refused as `must_be/2`, `(println! ...)` as `swrite/2` and `(get-state ...)` as
%`nb_getval/2`, each naming an internal the program never wrote. And following
%it is wasted work, because the answer was already decided by whether the name
%is on the allow-list.
metta_effect_classify(Module, Goal, Queue-Reads, Next-Reads) :-
    compound(Goal), !,
    functor(Goal, Name, Arity),
    metta_effect_named_call(Module, Name, Arity,
                            Queue-Reads, Next-Reads).

metta_effect_classify(_, Goal, Queue-Reads, Queue-Reads) :-
    atom(Goal), metta_effect_inert(Goal), !.
metta_effect_classify(_, Goal, _, _) :-
    functor(Goal, Name, Arity),
    throw(error(metta_impure_goal(Name/Arity), none)).

%And it follows the SAME test the goal itself makes, which is not reduce/3's.
%metta_result_reducible/1 re-enters evaluation only for an application of a
%known function, or for a term one of whose MEMBERS is one; a head that names
%no function is data, and the term is walked member by member. Reading such a
%head as an unknown CALL, the way reduce/3's walk must, refused an equation
%whose body is a constructor: `(Pair $a $b)` is not a call and
%`(memoize! choose)` was refused as metta_impure_goal(Pair/3)
%[tested: examples/libraries/memo_multi_answer.metta and its twin].
metta_effect_masked_result(_, Template, Queue, Queue) :-
    ( var(Template) ; \+ Template = [_|_] ), !.
metta_effect_masked_result(Module, [Head|Args], Queue, Next) :-
    (   atom(Head),
        ( builtin_fun(Head) -> true ; fun(Head) )
    ->  length(Args, ArgCount),
        Arity is ArgCount + 1,
        functor(Call, Head, Arity),
        metta_effect_classify(Module, Call, Queue, Next)
    ;   metta_effect_masked_members([Head|Args], Module, Queue, Next)
    ).

metta_effect_masked_members([], _, Queue, Queue).
metta_effect_masked_members([Item|Rest], Module, Queue, Next) :-
    metta_effect_masked_result(Module, Item, Queue, Mid),
    metta_effect_masked_members(Rest, Module, Mid, Next).


%An ownership seam may identify either a registered operation or a transparent
%dispatcher around a user equation. The former is decided by its effect
%declaration; the latter must still be followed. Treating lib_memo's
%cache_call/4 as an impure leaf made the next catalogue change revoke every
%automatic decision merely because the previous decision had recompiled the
%recursive call through that wrapper.
metta_effect_named_call(Module, Name, Arity, Queue-Reads, Next-Reads) :-
    (   builtin_fun(Name)
    ->  (   metta_effect_inert(Name)
        ->  Next = Queue
        ;   throw(error(metta_impure_goal(Name/Arity), none))
        )
    ;   %A definition that has arrived without being translated has no
        %predicate to find, and the walk below reads its clauses, so the
        %question has to be asked of the translated function.
        %current_predicate/1 is not a call, so the engine's
        %undefined-predicate net does not fire for it.
        fun(Name), metta_ensure_compiled(Name),
        current_predicate(Module:Name/Arity)
    ->  Next = [Name/Arity|Queue]
    ;   metta_effect_inert(Name)
    ->  Next = Queue
    ;   throw(error(metta_impure_goal(Name/Arity), none))
    ).

%A template that is not a call reaches nothing: a number, a string, a symbol
%and the empty list are data whatever surrounds them.
metta_effect_reduced(_, Template, Queue, Queue) :-
    ( var(Template) ; \+ Template = [_|_] ), !.
metta_effect_reduced(Module, [Head|Args], Queue, Next) :-
    length(Args, ArgCount),
    Arity is ArgCount + 1,
    (   atom(Head)
    ->  functor(Call, Head, Arity),
        metta_effect_classify(Module, Call, Queue, Next)
    ;   var(Head)
    ->  throw(error(metta_higher_order_goal(Arity), none))
    ;   %A number or a string in head position is not a call: reduce/3 reaches
        %its last case and leaves the term unevaluated, so `(1 2)` is data and
        %refusing it would refuse every list literal in a cached body.
        Next = Queue
    ).

metta_effect_inert(Name) :- seam:pure_operation(Name), !.
metta_effect_inert(Name) :- metta_effect_control(Name), !.
metta_effect_inert(Name) :- metta_effect_prolog_primitive(Name).

%Only the three that are LEAVES. Every compound control construct used to be
%here too, and that list was the second half of the collapse defect: a name on
%it was inert whether or not the walk had descended it, so adding a construct
%to the walk and forgetting the name was safe while the reverse was silently
%unsound. Now the walk is the only thing that makes a construct inert, and
%these three have no goal arguments to walk.
metta_effect_control(true).  metta_effect_control(fail).  metta_effect_control(!).

%The Prolog primitives a compiled body contains that are not MeTTa operations:
%the type tests the translator emits around a typed parameter, unification and
%arithmetic. Each inspects its arguments and does nothing else.
metta_effect_prolog_primitive(integer).  metta_effect_prolog_primitive(number).
metta_effect_prolog_primitive(float).    metta_effect_prolog_primitive(atom).
metta_effect_prolog_primitive(atomic).   metta_effect_prolog_primitive(compound).
metta_effect_prolog_primitive(string).   metta_effect_prolog_primitive(is_list).
metta_effect_prolog_primitive(var).      metta_effect_prolog_primitive(nonvar).
metta_effect_prolog_primitive(ground).   metta_effect_prolog_primitive(is).
%What `let` compiles to. Found by running every impure body through every
%wrapper rather than by reading: under `take` the occurs check precedes the
%impure goal, so the refusal fired on this and named it, which is the same
%false refusal atom_string/2 gave before it was listed. Unification with an
%occurs check inspects and binds and does nothing a cache could hide.
metta_effect_prolog_primitive(unify_with_occurs_check).
%What every computed collapse compiles to beside its findall: the Empty
%prune is a read-free list transformation, and leaving it unlisted
%refused a pure body one word inside a collapse
%[tested: a_pure_body_inside_a_wrapper_still_tables].
metta_effect_prolog_primitive(petta_prune_empty).
%The balance the inlined fuel charge reads and writes, module-qualified in the
%emitted goal so a program may still name them. b_setval/2 is a WRITE, and
%listing it here says what listing petta_fuel_step/2 as a pure engine helper
%said before the charge was inlined: a cached answer replays without spending
%fuel, which is the behaviour this engine already had.
metta_effect_prolog_primitive(b_getval).
metta_effect_prolog_primitive(b_setval).
%Restricted-space translation emits these guards immediately before the
%operation it protects. They inspect the fixed execution-base declaration and
%must not hide the operation from the effect walk: classifying them as inert
%lets the next add-atom, evalc, import or raw goal supply the user-facing
%effect name [tested:
%lib_tabling_purity:an_impure_goal_is_refused_inside_every_wrapper;
%commit=f46e45074286c08c4bd8b3d7892b3d7933f11f77].
metta_effect_prolog_primitive(metta_require_current_capability).
metta_effect_prolog_primitive(metta_require_safe_goal).
metta_effect_prolog_primitive(metta_require_space_update_capability).
metta_effect_prolog_primitive('=@=').    metta_effect_prolog_primitive('\\==').
metta_effect_prolog_primitive(nth0).     metta_effect_prolog_primitive(nth1).
metta_effect_prolog_primitive(between).  metta_effect_prolog_primitive(succ).
metta_effect_prolog_primitive('=<').     metta_effect_prolog_primitive('>=').
metta_effect_prolog_primitive('=:=').    metta_effect_prolog_primitive('=\\=').
metta_effect_prolog_primitive(atom_string).   metta_effect_prolog_primitive(atom_number).
metta_effect_prolog_primitive(atom_codes).    metta_effect_prolog_primitive(atom_length).
metta_effect_prolog_primitive(number_codes).  metta_effect_prolog_primitive(string_codes).
metta_effect_prolog_primitive(string_concat).  metta_effect_prolog_primitive(sub_atom).
metta_effect_prolog_primitive(functor).        metta_effect_prolog_primitive(arg).
metta_effect_prolog_primitive(compound_name_arguments).
metta_effect_prolog_primitive(compound_name_arity).

:- multifile prolog:error_message//1.
%The higher-order case, which no declaration can answer: nothing names the
%function, so there is nothing to declare pure. Saying so is the difference
%between an author declaring the right thing and an author declaring
%reduce/3 and watching nothing change.
prolog:error_message(metta_higher_order_goal(Arity)) -->
    [ 'caching refuses a call of arity ~w whose function is a value rather \c
       than a name. Which function it reaches is decided while the program \c
       RUNS, so no declaration can say whether a cached answer would hide \c
       anything. Name the function, or do not cache this one'-[Arity] ].

prolog:error_message(metta_impure_goal(Name/Arity)) -->
    [ 'caching refuses ~w/~w: it is not classified pureStructural, and a \c
       cached answer would hide its effect. Declare (effect ~w \c
       pureStructural) only when it inspects its arguments without observing \c
       mutable state, or do not cache this function'
      -[Name, Arity, Name] ].

%%%% The five-rank operation-effect lattice %%%%
%
%Every executable operation has one canonical class, ordered from an entirely
%structural computation through reads and writes to an external oracle. A
%composition has the strongest class of any member: rank is the order, join is
%maximum, and the empty composition is pureStructural. These predicates are
%the engine-side image of the public EffectClass vocabulary rather than a
%second public value set: spaces:petta_effect_class_canonical/2 resolves both
%catalog members and the old immutable/stable/volatile input spellings.
%
%The old projections are deliberately conservative. immutable and pure=true
%mean pureStructural, stable means readOnlyLookup, and volatile means oracleIO
%because the former volatile contract admitted variation, writes and I/O.
%Only pureStructural projects back to seam:pure_operation/1.
%[tested: effects_lattice:the_five_effect_classes_are_ranked_in_catalog_order,
%effects_lattice:effect_join_and_compose_choose_the_strongest_member,
%effects_lattice:operation_effect_reflection_is_canonical_and_fail_closed,
%effects_lattice:the_legacy_host_pure_boolean_maps_to_pure_structural;
%commit=WORKTREE]
petta_effect_rank(Declared, Rank) :-
    spaces:petta_effect_class_canonical(Declared, Canonical),
    petta_effect_canonical_rank(Canonical, Rank).

petta_effect_canonical_rank(pureStructural, 0).
petta_effect_canonical_rank(readOnlyLookup, 1).
petta_effect_canonical_rank(nondeterministicReadOnly, 2).
petta_effect_canonical_rank(writesState, 3).
petta_effect_canonical_rank(oracleIO, 4).

petta_effect_join(Left, Right, Joined) :-
    spaces:petta_effect_class_canonical(Left, CanonicalLeft),
    spaces:petta_effect_class_canonical(Right, CanonicalRight),
    petta_effect_canonical_rank(CanonicalLeft, LeftRank),
    petta_effect_canonical_rank(CanonicalRight, RightRank),
    (   LeftRank >= RightRank
    ->  Joined = CanonicalLeft
    ;   Joined = CanonicalRight
    ).

petta_effect_compose(Classes, Effect) :-
    petta_effect_compose_(Classes, pureStructural, Effect).

petta_effect_compose_([], Effect, Effect).
petta_effect_compose_([Class|Classes], Acc0, Effect) :-
    petta_effect_join(Acc0, Class, Acc),
    petta_effect_compose_(Classes, Acc, Effect).

%One canonical reflection row for an operation. Registration normally owns
%one raw (effect Name Class) atom. If a re-registration briefly overlaps two
%rows, or old and new clients both declared one, their join is the safe answer
%and findall/3 still exposes one canonical row. A missing declaration fails,
%which is the same fail-closed rule registration enforces. The dynamic host
%pure fact is the compatibility image of Operation.pure=true and is consulted
%only when no catalog row exists.
petta_operation_effect(Name, Effect) :-
    atom(Name),
    findall(Declared,
            petta_contract_fact([effect, Name, Declared]),
            DeclaredClasses),
    (   DeclaredClasses = [_|_]
    ->  maplist(spaces:petta_effect_class_canonical,
                DeclaredClasses,
                CanonicalClasses),
        petta_effect_compose(CanonicalClasses, Effect)
    ;   metta_host_pure_operation(Name)
    ->  Effect = pureStructural
    ;   fail
    ).

%A plan is a list of operation names. maplist/3 makes an unclassified member
%fail the whole plan rather than silently treating it as pure. The empty plan
%inherits petta_effect_compose/2's pureStructural identity.
petta_operation_plan_effect(Operations, Effect) :-
    maplist(petta_operation_effect, Operations, Classes),
    petta_effect_compose(Classes, Effect).

%%%% Which operations a cache may hide %%%%
%
%The engine's own answer to seam:pure_operation/1: an operation with no effect
%a cached result could hide. Anything that reads or writes a space, reads or
%writes state, prints, draws at random, reads the clock, crosses to a host, or
%evaluates something else is ABSENT, and absence is a refusal rather than a
%default.
%
%The list is deliberately shorter than "everything that looks harmless". A name
%missing here produces a loud refusal that someone adds a line for; a name
%wrongly present produces a silent wrong answer, which is what the fail-open
%default it replaces was producing.
:- multifile seam:pure_operation/1.
:- dynamic metta_host_pure_operation/1.

%A HOST's own declarations, at run time. It was multifile only, so a library
%file could add a name when it loaded and a running process could add none at
%all: register_op(len, name="size") gave an operation nothing could ever
%declare pure, and the refusal's advice, "declare it with
%seam:pure_operation/1", was unreachable by any route.
%
%It is a SEPARATE predicate rather than more clauses of this one, and that is
%not tidiness. The five shipped clauses in space_hooks.pl are RULES with a
%variable head, so
%retractall(seam:pure_operation(foo)), which is how a registration withdraws
%one declaration, unifies with every one of them: five clauses to zero and
%seam:pure_operation('+') true to false, from registering any operation at
%all [measured 2026-08-17]. Retracting from here cannot reach them.
seam:pure_operation(Name) :-
    atom(Name),
    petta_operation_effect(Name, pureStructural).

%One contract atom, read from &petta's native storage. An expression
%[H|Args] is stored as '&petta'(H, Args...) in that space's storage module,
%the resolution the tabling walk documents; a space that has never been
%written has no storage module yet, and that absence reads as "not declared".
petta_contract_fact(Args) :-
    native_storage_module('&petta', Module),
    Goal =.. ['&petta'|Args],
    catch(call(Module:Goal), error(existence_error(procedure, _), _), fail).

%The deliberate override: (cache Name unchecked) in &petta says the CALLER
%accepts stale answers for this function. lib_tabling and lib_memo consult
%it before their purity walk; an explicit non-pureStructural declaration
%still refuses, because the author's NO outranks the caller's insistence.
metta_cache_unchecked(Name) :-
    petta_contract_fact([cache, Name, unchecked]).

%(annotations Ctx Algebra [Capabilities]) declares the value algebra a
%context's answer annotations live in; silence is the shipped bool algebra.
%Every algebra is an ordinary catalog row naming combine, extend, zero, one,
%checked laws, a finite checking carrier when one exists, and requirements.
%The old semiring names are shipped rows in that same table rather than cases
%in this predicate [tested:
%test_a_declared_semiring_quadruple_serves_annotations_like_a_builtin_one;
%commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c].
petta_annotations(Ctx, Algebra) :-
    (   petta_annotations_cache(Ctx, Cached)
    ->  Algebra = Cached
    ;   petta_annotations_fresh(Ctx, Algebra)
    ).

petta_annotations_fresh(Ctx, Algebra) :-
    findall(Declared, petta_contract_fact([annotations, Ctx, Declared]),
            PlainDeclarations),
    (   PlainDeclarations == []
    ->  findall(Declared,
                petta_contract_fact([annotations, Ctx, Declared, _]),
                Declarations)
    ;   Declarations = PlainDeclarations
    ),
    sort(Declarations, Distinct),
    petta_annotations_resolved(Distinct, Ctx, Resolved),
    assertz(petta_annotations_cache(Ctx, Resolved)),
    Algebra = Resolved.

petta_annotations_resolved([], _, bool) :- !.
petta_annotations_resolved([Algebra], _, Algebra) :- !.
petta_annotations_resolved([First, Second|Rest], Ctx, _) :-
    throw(error(petta_contract_conflict(Ctx, [annotations, Ctx, First],
                                        [annotations, Ctx, Second],
                                        [annotations, Ctx,
                                         [First, Second|Rest]]),
                none)).

%A per-ask carrier is dynamically scoped around the held engine goal. It is
%not a catalog mutation: nested evaluations inherit it, cleanup restores the
%previous value on failure, exception, exhaustion, or cursor destruction, and
%every persistent declaration remains unchanged for the next ask [tested:
%bindings/python/tests/test_under_algebra.py; commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa].
:- meta_predicate petta_with_under(+, 0).

petta_with_under(Algebra, Goal) :-
    setup_call_cleanup(
        petta_under_push(Algebra, Previous),
        Goal,
        petta_under_pop(Previous)).

petta_under_push(Algebra, Previous) :-
    (   nb_current('$petta_under_algebras', Old)
    ->  Previous = some(Old)
    ;   Old = [], Previous = none
    ),
    nb_setval('$petta_under_algebras', [Algebra|Old]).

petta_under_pop(some(Previous)) :- !,
    nb_setval('$petta_under_algebras', Previous).
petta_under_pop(none) :-
    catch(nb_delete('$petta_under_algebras'), _, true).

petta_effective_algebra(_, Algebra) :-
    nb_current('$petta_under_algebras', [Algebra|_]), !.
petta_effective_algebra(Ctx, Algebra) :-
    petta_annotations(Ctx, Algebra).

petta_algebra_descriptor(Name, Combine, Extend, Zero, One, Laws,
                         Carrier, Requires) :-
    (   petta_algebra_descriptor_cache(Name, CachedCombine, CachedExtend,
                                       CachedZero, CachedOne, CachedLaws,
                                       CachedCarrier, CachedRequires)
    ->  Combine = CachedCombine,
        Extend = CachedExtend,
        Zero = CachedZero,
        One = CachedOne,
        Laws = CachedLaws,
        Carrier = CachedCarrier,
        Requires = CachedRequires
    ;   petta_algebra_descriptor_fresh(Name, Combine, Extend, Zero, One,
                                       Laws, Carrier, Requires)
    ).

petta_algebra_descriptor_fresh(Name, Combine, Extend, Zero, One, Laws,
                               Carrier, Requires) :-
    petta_contract_fact([algebra, Name, Combine, Extend, Zero, One,
                         Laws, Carrier, Requires]),
    assertz(petta_algebra_descriptor_cache(Name, Combine, Extend, Zero, One,
                                           Laws, Carrier, Requires)).

petta_algebra_one(Ctx, One) :-
    petta_effective_algebra(Ctx, Algebra),
    petta_algebra_descriptor(Algebra, _, _, _, One, _, _, _).

petta_algebra_law(Algebra, Law) :-
    petta_algebra_descriptor(Algebra, _, _, _, _, [laws|Laws], _, _),
    memberchk(Law, Laws).

%Whether the declared semiring carries an order is a CLAIM in the catalog,
%(claim semiring ranked ordered) and its prob sibling shipped as presets,
%so a third-party semiring value declared ordered serves (top k ...) with
%no engine edit, the same way Oracle's RELY constraint state is a declared
%per-constraint fact its optimizer acts on.
petta_annotations_ordered(Ctx) :-
    petta_effective_algebra(Ctx, Semiring),
    petta_vocabulary_claim(semiring, Semiring, ordered).

petta_algebra_order(Algebra, ascending) :-
    petta_vocabulary_claim(semiring, Algebra, ascending), !.
petta_algebra_order(_, descending).

petta_annotations_order(Ctx, Direction) :-
    petta_effective_algebra(Ctx, Algebra),
    petta_vocabulary_claim(semiring, Algebra, ordered),
    petta_algebra_order(Algebra, Direction).

%A declared per-value fact: (claim Vocab Value Property...) rows carry any
%number of properties, and a consumer asks for one.
petta_vocabulary_claim(Vocab, Value, Property) :-
    petta_catalog_row([claim, Vocab, Value|Properties]),
    memberchk(Property, Properties),
    !.

%(source Ctx Kind) declares a context's consumption discipline: repeated
%(the default, re-enumerable), linear (consume once; a second physical
%touch is a loud error, not a silent empty answer), and peek (reads do
%not consume, the provider's promise the conformance kit checks). The
%consumed mark is a prolog FLAG, process-global and transaction-immune,
%because a rolled-back transaction does not un-drain a generator.
petta_source(Ctx, Kind) :-
    (   petta_contract_fact([source, Ctx, Declared])
    ->  Kind = Declared
    ;   Kind = repeated
    ).

petta_source_guard(Space) :-
    \+ petta_ctx_declared(Space),
    !.
petta_source_guard(Space) :-
    (   petta_contract_storage(Module),
        Module:'&petta'(source, Space, linear)
    ->  petta_space_flag_key('$petta_consumed:', Space, Key),
        (   current_prolog_flag(Key, consumed)
        ->  throw(error(petta_source_discipline(Space, linear), none))
        ;   create_prolog_flag(Key, consumed, [keep(false)])
        )
    ;   true
    ).

petta_source_reset(Space) :-
    petta_space_flag_key('$petta_consumed:', Space, Key),
    (   current_prolog_flag(Key, _)
    ->  set_prolog_flag(Key, fresh)
    ;   true
    ).

petta_space_flag_key(Prefix, Space, Key) :-
    atom(Space), !,
    atom_concat(Prefix, Space, Key).
petta_space_flag_key(Prefix, Space, Key) :-
    space_canonical_atom(Space, Encoded),
    atom_concat(Prefix, Encoded, Key).

:- multifile prolog:error_message//1.
prolog:error_message(petta_source_discipline(Ctx, linear)) -->
    [ '~w declares (source ~w linear) and this is its second \c
       consumption: the first drained it, so answering would be a silent \c
       empty set, exactly the wrong answer the declaration exists to \c
       refuse. Re-register the provider for a fresh source, or declare \c
       repeated for one that re-enumerates'-[Ctx, Ctx] ].

%The last answer's annotation, first-class: rides '$petta_answer_k'
%backtrackably. Outside an answer it reads the current context's DECLARED one,
%not a numeric engine constant.
petta_annotation(K) :-
    (   catch(b_getval('$petta_answer_k', K0), _, fail)
    ->  K = K0
    ;   current_metta_space(Ctx),
        petta_algebra_one(Ctx, K)
    ).

petta_annotation(Ctx, K) :-
    (   catch(b_getval('$petta_answer_k', K0), _, fail)
    ->  K = K0
    ;   petta_algebra_one(Ctx, K)
    ).

%Extend two annotations along a conjunction by the operation in the catalog.
%Numeric +/*/min/max use their already-typed engine primitives directly; an
%arbitrary declared operation goes through ordinary evaluation, so a grounded
%tensor operation registered from Python is not a separate engine case.
petta_k_extend(Ctx, K1, K2, K) :-
    petta_effective_algebra(Ctx, Algebra),
    petta_algebra_descriptor(Algebra, _, Extend, _, One, _, _, _),
    (   K1 == One -> K = K2
    ;   K2 == One -> K = K1
    ;   petta_apply_algebra_operation(Algebra, Extend, K1, K2, K)
    ).

petta_apply_algebra_operation(_, '*', A, B, R) :-
    number(A), number(B), !,
    R is A * B.
petta_apply_algebra_operation(_, '+', A, B, R) :-
    number(A), number(B), !,
    R is A + B.
petta_apply_algebra_operation(_, min, A, B, R) :-
    number(A), number(B), !,
    R is min(A, B).
petta_apply_algebra_operation(_, max, A, B, R) :-
    number(A), number(B), !,
    R is max(A, B).
petta_apply_algebra_operation(Algebra, Operation, A, B, R) :-
    (   once(eval([Operation, A, B], R0))
    ->  R = R0
    ;   throw(error(petta_algebra_operation_failed(Algebra, Operation, A, B),
                    none))
    ).

prolog:error_message(petta_algebra_requirement_missing(Ctx, Algebra,
                                                        Requirement)) -->
    [ 'algebra_requirement_missing: ~w declares algebra ~w, which requires \c
       capability ~w'-[Ctx, Algebra, Requirement] ].
prolog:error_message(petta_amplitude_fragment_refused(Ctx, Requirement)) -->
    [ 'amplitude_fragment_refused: ~w lacks required finite-fragment \c
       capability ~w'-[Ctx, Requirement] ].
prolog:error_message(petta_algebra_operation_failed(Algebra, Operation, A, B)) -->
    [ 'declared algebra ~w operation ~w answered nothing for (~w, ~w)'-
      [Algebra, Operation, A, B] ].
prolog:error_message(petta_algebra_law_unknown(Algebra, Law)) -->
    [ 'algebra_law_unknown: ~w names unsupported law ~w'-[Algebra, Law] ].
prolog:error_message(petta_algebra_law_uncheckable(Algebra, Laws, Reason)) -->
    [ 'algebra_law_uncheckable: ~w names ~w but provides no ~w'-
      [Algebra, Laws, Reason] ].
prolog:error_message(petta_algebra_carrier_not_closed(Algebra, Operation,
                                                       A, B, Result)) -->
    [ 'algebra_carrier_not_closed: ~w operation ~w maps (~w, ~w) to ~w'-
      [Algebra, Operation, A, B, Result] ].
prolog:error_message(petta_algebra_law_violation(Algebra, Law, Inputs,
                                                  Left, Right)) -->
    [ 'algebra_law_violation: ~w law ~w fails at ~w: ~w differs from ~w'-
      [Algebra, Law, Inputs, Left, Right] ].

%%%% explain: the route as atoms (H3) %%%%
%
%(explain (match &s P T)) and (explain (op ...)) answer the declarations
%the seam would consult for that query, as atoms: which handles entry
%routes it and with what fidelity, whether a take bound would push,
%source, context world, annotations, emission, event delivery, writes,
%error mode and merge strategy. The self-honesty law is the lane: what explain says is
%what instrumented execution then does, which answers the original
%complaint that the split was invisible.
petta_explain([match, Space, Pattern, _Template], Out) :-
    petta_space_name(Space), !,
    findall(Item, petta_explain_match_item(Space, Pattern, Item), Out).
petta_explain([Op|Args], Out) :-
    atom(Op), !,
    findall(Item, petta_explain_op_item(Op, Args, Item), Out).
petta_explain(Query, _) :-
    throw(error(type_error(explainable, Query),
                context(explain/1,
                        'explain covers (match <space> <pattern> <out>) \c
                         forms and operation calls'))).

petta_explain_match_item(Space, Pattern, [handles|Route]) :-
    (   catch(petta_handles_route(Space, Pattern, Entry, Fidelity, Det),
              _, fail)
    ->  Route = [Entry, Fidelity, Det]
    ;   Route = [none]
    ).
petta_explain_match_item(Space, Pattern, [pushes, Pushes]) :-
    (   nonvar(Space), seam:foreign_space(Space),
        catch(foreign_pushdown_class(Space, Pattern, exact), _, fail)
    ->  Pushes = 'True'
    ;   Pushes = 'False'
    ).
petta_explain_match_item(Space, _, [source, Kind]) :-
    petta_source(Space, Kind).
petta_explain_match_item(Space, _, [context, World]) :-
    petta_context_world(Space, World).
petta_explain_match_item(Space, _, [annotations, Semiring]) :-
    petta_annotations(Space, Semiring).
petta_explain_match_item(Space, _, [emits, Policy]) :-
    (   petta_emits(Space, Declared) -> Policy = Declared ; Policy = none ).
petta_explain_match_item(Space, _, [events, Delivery, Order]) :-
    (   petta_event_capability(Space, Fidelity, Ordering)
    ->  Delivery = Fidelity, Order = Ordering
    ;   Delivery = none, Order = none
    ).
petta_explain_match_item(Space, _, [writes, Atomicity]) :-
    petta_writes(Space, Atomicity).
petta_explain_match_item(Space, Pattern, ['on-error', Mode]) :-
    (   catch(petta_on_error_mode(Space, Pattern, Declared), _, fail)
    ->  Mode = Declared
    ;   Mode = abort
    ).
petta_explain_match_item(_, Pattern, [merge, Policy]) :-
    (   catch(petta_merge_route(Pattern, Declared), _, fail)
    ->  Policy = Declared
    ;   Policy = depth
    ).

petta_explain_op_item(Op, _, [op, Op, Arity, Kind]) :-
    petta_contract_fact([op, Op, Arity, Kind]).
petta_explain_op_item(Op, _, [effect, Effect]) :-
    (   petta_operation_effect(Op, Declared)
    ->  Effect = Declared
    ;   Effect = none
    ).
petta_explain_op_item(Op, _, [inverse, Inverse]) :-
    (   petta_contract_fact([inverse, Op]) -> Inverse = 'True'
    ;   Inverse = 'False' ).
petta_explain_op_item(Op, _, [annotations, Semiring]) :-
    petta_annotations(Op, Semiring).
petta_explain_op_item(Op, Args, ['on-error', Mode]) :-
    (   catch(petta_on_error_mode(Op, [Op|Args], Declared), _, fail)
    ->  Mode = Declared
    ;   Mode = abort
    ).
petta_explain_op_item(Op, _, [cache, Choice, Reason]) :-
    seam:automatic_cache_explanation(Op, Choice, Reason).
petta_explain_op_item(Op, _, [deprecated, Since, Remedy]) :-
    petta_deprecation(Op, Since, Remedy).

%One declaration over one callable name. Keeping the values as terms is the
%point: a version can be a symbol or grounded text, and the remedy can be a
%call-shaped atom that both explain and a host warning render without a second
%stringly registry.
petta_deprecation(Name, Since, Remedy) :-
    petta_contract_fact([deprecated, Name, Since, Remedy]), !.

%(context Ctx closed-world|open-world) records what a context's absence
%means. The mechanically checkable part gates: negation as failure reads
%absence as falsity, which is sound only over a world the answerer
%actually holds whole, so a negated goal may consult a foreign context
%only when it declares closed-world. A native space IS the engine's own
%database and closed by construction; an undeclared foreign one refuses
%under negation loudly, because silently reading an open world's silence
%as falsity was the wrong answer.
petta_context_world(Ctx, World) :-
    (   petta_contract_fact([context, Ctx, Declared])
    ->  World = Declared
    ;   World = undeclared
    ).

petta_in_negation :-
    catch(b_getval('$petta_in_negation', true), _, fail).

petta_negation_world_guard(Space) :-
    (   petta_in_negation
    ->  (   petta_context_world(Space, 'closed-world')
        ->  true
        ;   throw(error(petta_negation_open_world(Space), none))
        )
    ;   true
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_negation_open_world(Ctx)) -->
    [ 'a negated goal consulted ~w, which does not declare \c
       (context ~w closed-world). Negation as failure reads absence as \c
       falsity, and that is only sound over a world the answerer holds \c
       whole; declare closed-world if ~w is complete for what it \c
       serves'-[Ctx, Ctx, Ctx] ].

%%%% Declared bridges and admission (G5) %%%%
%
%(on Ctx Pattern Op) is an MCS bridge rule with a managed head: when an
%atom matching Pattern lands in Ctx, Op runs under the match's bindings.
%The subscribe callback is the special case this generalises. The heads
%are insert, retract and revise, and they route through the same write
%paths as direct writes, so a foreign target's capabilities and declared
%atomicity govern a bridged write exactly as a direct one. Bridges fire
%through the engine's own atom hooks, and the hook wrapper is installed
%only when petta_install_bridges/0 runs (the declaration sugar calls it),
%so an engine without bridges keeps the direct write path and its
%measured cost. A cascade is bounded: depth 32 throws naming the chain,
%because an unbounded insert loop is a bug, not a fixpoint.
petta_install_bridges :-
    (   petta_bridges_installed
    ->  true
    ;   assertz(petta_bridges_installed),
        assertz(( seam:atom_added(Space, Term) :-
                      petta_bridge_fire(Space, Term) )),
        seam:enable_atom_hook(added)
    ).

:- dynamic petta_bridges_installed/0.

%%%% The agenda: which reaction fires first (P12.17) %%%%
%
%Several reactions can match one write, and before this nothing in the tree
%said which went first, so the answer was assertion order by accident. It is
%a DECLARED policy now, (agenda <ctx> <policy> [<function>]) in '&petta',
%with declaration as the stated default: the order they were declared, which
%is what the accident used to produce.
%
%The vocabulary is production systems' own conflict-resolution vocabulary and
%the reasons are on the catalog row that declares it. Every policy is STABLE
%on declaration order, so the tie-break is the default rather than an
%accident of the sort: that is CLIPS's own layering, where salience picks the
%bucket and the strategy orders within it.
%
%A reaction's priority is the optional fifth argument of its (on ...) row and
%defaults to 0, so every reaction written before this keeps its meaning.
petta_reaction(Space, Pattern, Op, Priority) :-
    (   petta_contract_fact([on, Space, Pattern, Op, Priority])
    ;   petta_contract_fact([on, Space, Pattern, Op]),
        Priority = 0
    ).

petta_agenda(Ctx, Policy, Chooser) :-
    (   petta_contract_fact([agenda, Ctx, Declared, Named])
    ->  Policy = Declared, Chooser = Named
    ;   petta_contract_fact([agenda, Ctx, Declared])
    ->  Policy = Declared, Chooser = none
    ;   petta_agenda_default(Policy, Chooser)
    ).

%The stated default, as a FACT. Two reasons and both are load-bearing: the
%row's whole point is that the default is stated rather than accidental, so
%it reads better as one named thing than as two bindings buried in a branch;
%and `Policy = declaration` cannot be written there at all, because the
%development-side Ciao assertion packs declare `declaration` as a prefix
%operator at priority 1125, above the 999 an operand of ,/2 may reach, so
%that clause body stopped parsing under the ciao-grade lane's operator table
%[measured 2026-08-21: engine/metta.pl:3540:27, "Operand expected, unquoted
%comma or bar found"]. A head argument is not an operand of ,/2 and parses
%either way.
petta_agenda_default(declaration, none).

prolog:error_message(petta_agenda_unscored(Ctx, Chooser, Entry)) -->
    [ '~w declares (agenda ~w user ~w) and ~w answered no number for ~q. A \c
       user agenda policy scores every reaction it is asked about, because a \c
       reaction with no score has no place in the order and dropping it \c
       would be a rule that silently never fires'-[Ctx, Ctx, Chooser,
                                                    Chooser, Entry] ].

petta_bridge_fire(Space, Term) :-
    findall(Pattern-Op-Priority,
            petta_reaction(Space, Pattern, Op, Priority),
            Declared),
    (   Declared = [_, _|_]
    ->  petta_agenda(Space, Policy, Chooser),
        petta_agenda_order(Policy, Chooser, Space, Declared, Ordered)
    ;   Ordered = Declared
    ),
    forall(member(P-O-_, Ordered), petta_bridge_apply(P, Term, O)).

%One reaction is already in order, and so is a conflict set under the
%default, so neither pays for the sort.
petta_agenda_order(declaration, _, _, Reactions, Reactions) :- !.
petta_agenda_order(recency, _, _, Reactions, Ordered) :- !,
    reverse(Reactions, Ordered).
petta_agenda_order(specificity, _, _, Reactions, Ordered) :- !,
    petta_agenda_keyed(petta_pattern_specificity, Reactions, Keyed),
    petta_agenda_sorted(Keyed, Ordered).
petta_agenda_order(priority, _, _, Reactions, Ordered) :- !,
    findall(Priority-Reaction,
            ( member(Reaction, Reactions), Reaction = _-_-Priority ),
            Keyed),
    petta_agenda_sorted(Keyed, Ordered).
petta_agenda_order(user, Chooser, Space, Reactions, Ordered) :-
    petta_agenda_user_keyed(Chooser, Space, Reactions, Keyed),
    petta_agenda_sorted(Keyed, Ordered).

%sort/4 with @>= keeps duplicates AND their relative order, so equal keys
%stay in declaration order without a second sort key
%[source: SWI-Prolog manual, sort/4].
petta_agenda_sorted(Keyed, Ordered) :-
    sort(1, @>=, Keyed, Sorted),
    findall(Reaction, member(_-Reaction, Sorted), Ordered).

petta_agenda_keyed(_, [], []).
petta_agenda_keyed(Measure, [Reaction|Rest], [Key-Reaction|Keyed]) :-
    Reaction = Pattern-_-_,
    call(Measure, Pattern, Key),
    petta_agenda_keyed(Measure, Rest, Keyed).

%How specific a pattern is: OPS5 counts the tests in the left-hand side, and
%a MeTTa pattern's tests are its non-variable positions, so (alert kitchen)
%outranks (alert $where) and both outrank $anything.
petta_pattern_specificity(Pattern, 0) :- var(Pattern), !.
petta_pattern_specificity(Pattern, N) :-
    is_list(Pattern),
    !,
    petta_specificity_of(Pattern, 1, N).
petta_pattern_specificity(_, 1).

petta_specificity_of([], N, N).
petta_specificity_of([Item|Rest], Acc, N) :-
    petta_pattern_specificity(Item, Count),
    Next is Acc + Count,
    petta_specificity_of(Rest, Next, N).

%A user policy SCORES each reaction rather than reordering the list, and
%that is the safer half of the same freedom: a function that returns a
%permutation can drop a reaction, and a rule that silently never fires is
%the failure this whole item exists to remove. Scoring cannot. It is also
%what CHR-rp's dynamic priorities are, an expression evaluated per rule
%instance rather than a constant. The function is called once per reaction
%per firing write, and the call goes through the ordinary translation cache,
%so an opt-in policy costs nothing until it is declared.
petta_agenda_user_keyed(none, Space, _, _) :-
    throw(error(petta_agenda_unscored(Space, none, none), none)).
petta_agenda_user_keyed(Chooser, Space, Reactions, Keyed) :-
    Chooser \== none,
    petta_agenda_user_keys(Reactions, Chooser, Space, Keyed).

petta_agenda_user_keys([], _, _, []).
petta_agenda_user_keys([Reaction|Rest], Chooser, Space,
                       [Key-Reaction|Keyed]) :-
    Reaction = Pattern-Op-Priority,
    Entry = [on, Space, Pattern, Op, Priority],
    (   petta_agenda_score(Chooser, Entry, Key)
    ->  true
    ;   throw(error(petta_agenda_unscored(Space, Chooser, Entry), none))
    ),
    petta_agenda_user_keys(Rest, Chooser, Space, Keyed).

petta_agenda_score(Chooser, Entry, Key) :-
    space_module('&self', Module),
    with_metta_module(Module,
                      ( translate_cached_expr([Chooser, Entry], Goals, Out),
                        call_goals_in_(Module, Goals) )),
    number(Out),
    Key = Out.

petta_bridge_apply(Pattern, Term, Op) :-
    (   Pattern = Term
    ->  petta_bridge_descend(Op)
    ;   true
    ).

petta_bridge_descend(Op) :-
    (   catch(b_getval('$petta_bridge_depth', Depth0), _, fail)
    ->  true
    ;   Depth0 = 0
    ),
    Depth is Depth0 + 1,
    (   Depth > 32
    ->  throw(error(petta_bridge_cascade(Op), none))
    ;   setup_call_cleanup(
            b_setval('$petta_bridge_depth', Depth),
            petta_bridge_op(Op),
            b_setval('$petta_bridge_depth', Depth0))
    ).

petta_bridge_op([insert, Target, Template]) :- !,
    metta_add_atom(Target, Template, _).
petta_bridge_op([retract, Target, Template]) :- !,
    metta_remove_atom(Target, Template, _).
petta_bridge_op([revise, Target, Old, New]) :- !,
    metta_remove_atom(Target, Old, _),
    metta_add_atom(Target, New, _).
petta_bridge_op(Op) :-
    throw(error(petta_bridge_unknown_op(Op), none)).
