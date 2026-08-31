% Purpose: classify compiled effects, compose the five-rank effect lattice,
%   plan reified-world admission, and manage memoization, dependencies, and
%   bridge cascades.
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees:
%   - every definition retains engine/metta.pl's implementation module and
%     original load order [tested: tests/prolog/suites/evaluation/metta.plt,
%     tests/prolog/static_checks.pl; commit=WORKTREE].
%   - metta_host_goal_repeatable/2 exposes one fail-closed host question over
%     the shared effect walk without consuming control limits, so bindings
%     never reconstruct its private queue protocol [tested:
%     metta_effects:the_host_repeatability_question_fails_closed,
%     metta_effects:the_host_repeatability_question_preserves_inference_limits;
%     commit=6917bef7ca902671999eafcae3a7a86db8f69723].
%   - deprecation declarations are reflected by exact name and appear in an
%     operation explanation with their since and remedy values [tested:
%     a_deprecation_row_drives_lookup_and_explanation;
%     commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0].
%   - a host can obtain the joined effect and named operation rows reachable
%     from one compiled goal; world coverage and saga compensation remain
%     ordinary catalog data [tested:
%     effects_lattice:a_compiled_goal_plan_follows_raw_definitions_and_joins_operations,
%     effects_lattice:world_effect_coverage_composes_catalog_rows_to_the_strongest_rank,
%     effects_lattice:compensation_declarations_require_an_effectful_operation;
%     commit=WORKTREE].
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/suites/evaluation/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

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
%[tested: lib_tabling_purity:an_impure_goal_is_refused_inside_every_wrapper;
%commit=WORKTREE].
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
%[tested: lib_tabling:a_bounded_match_reports_the_read_it_is].
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
%read the functor and refuse metta_py_dispatch_det/3, naming an internal the
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

%metta_dynamic_call/3 is the variable-head application door: the call it
%reaches is decided by a value, which is exactly the case the reduce/3 walk
%above refuses as higher-order, so it is classified by the same
%reconstruction rather than refused under the dispatcher's own name
%[tested: lib_tabling_purity:a_higher_order_call_is_refused_as_one;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_effect_classify(Module, metta_dynamic_call(Head, Args, _), Queue,
                      Next) :- !,
    metta_effect_reduced(Module, [Head|Args], Queue, Next).
%The value half of the same door: the head decides the call exactly as
%above, and the finished values stand where the written arguments stood.
metta_effect_classify(Module, metta_dynamic_value_call(Head, _, Values, _),
                      Queue, Next) :- !,
    metta_effect_reduced(Module, [Head|Values], Queue, Next).
%The branch guard reads one indexed register row and binds nothing.
metta_effect_classify(_, metta_dynamic_head_masks(_), Queue, Queue) :- !.

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
%[tested: examples/ch18-performance/18-02-memoisation-and-tabling/01-memo_multi_answer.metta and its twin].
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
metta_effect_prolog_primitive(metta_prune_empty).
%The balance the inlined fuel charge reads and writes, module-qualified in the
%emitted goal so a program may still name them. b_setval/2 is a WRITE, and
%listing it here says what listing metta_fuel_step/2 as a pure engine helper
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
       mutable state; or, if the staleness is what you want, declare the \c
       function you are caching (cache <function> unchecked), which caches it \c
       on your word and skips this walk; or do not cache it'
      -[Name, Arity, Name] ].

%%%% The five-rank operation-effect lattice %%%%
%
%Every executable operation has one canonical class, ordered from an entirely
%structural computation through reads and writes to an external oracle. A
%composition has the strongest class of any member: rank is the order, join is
%maximum, and the empty composition is pureStructural. These predicates are
%the engine-side image of the public EffectClass vocabulary rather than a
%second public value set: spaces:metta_effect_class_canonical/2 resolves both
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
%commit=d74e2e828cd9272882dcf907cfaf095d2d147ce0]
metta_effect_rank(Declared, Rank) :-
    spaces:metta_effect_class_canonical(Declared, Canonical),
    metta_effect_canonical_rank(Canonical, Rank).

metta_effect_canonical_rank(pureStructural, 0).
metta_effect_canonical_rank(readOnlyLookup, 1).
metta_effect_canonical_rank(nondeterministicReadOnly, 2).
metta_effect_canonical_rank(writesState, 3).
metta_effect_canonical_rank(oracleIO, 4).

metta_effect_join(Left, Right, Joined) :-
    spaces:metta_effect_class_canonical(Left, CanonicalLeft),
    spaces:metta_effect_class_canonical(Right, CanonicalRight),
    metta_effect_canonical_rank(CanonicalLeft, LeftRank),
    metta_effect_canonical_rank(CanonicalRight, RightRank),
    (   LeftRank >= RightRank
    ->  Joined = CanonicalLeft
    ;   Joined = CanonicalRight
    ).

metta_effect_compose(Classes, Effect) :-
    metta_effect_compose_(Classes, pureStructural, Effect).

metta_effect_compose_([], Effect, Effect).
metta_effect_compose_([Class|Classes], Acc0, Effect) :-
    metta_effect_join(Acc0, Class, Acc),
    metta_effect_compose_(Classes, Acc, Effect).

%One canonical reflection row for an operation. Registration normally owns
%one raw (effect Name Class) atom. If a re-registration briefly overlaps two
%rows, or old and new clients both declared one, their join is the safe answer
%and findall/3 still exposes one canonical row. Native and semantic profiles
%are a lower bound, not an override point: an ordinary catalog atom may make a
%built-in stricter, but cannot relabel random input or mutation as structural.
%The dynamic host pure fact is the compatibility image of Operation.pure=true
%and contributes only when no catalog or fixed profile exists.
metta_operation_effect(Name, Effect) :-
    atom(Name),
    metta_declared_effect_classes(Name, CanonicalDeclared),
    findall(Fixed, metta_fixed_operation_effect(Name, Fixed), FixedClasses),
    append(CanonicalDeclared, FixedClasses, Classes0),
    (   Classes0 == [], metta_host_pure_operation(Name)
    ->  Classes = [pureStructural]
    ;   Classes = Classes0
    ),
    Classes = [_|_],
    metta_effect_compose(Classes, Effect).

%The catalog's own rows for one operation, canonicalised. Shared by the
%reflection above and by the cache's narrower question at
%seam:pure_operation/1 below.
metta_declared_effect_classes(Name, Canonical) :-
    findall(Declared,
            metta_contract_fact([effect, Name, Declared]),
            DeclaredClasses),
    maplist(spaces:metta_effect_class_canonical,
            DeclaredClasses,
            Canonical).

%What a host or the catalog DECLARED about an operation, without the fixed
%native profile. A missing declaration fails, which is the fail-closed rule
%registration enforces.
metta_declared_operation_effect(Name, Effect) :-
    atom(Name),
    metta_declared_effect_classes(Name, Canonical),
    (   Canonical = [_|_]
    ->  metta_effect_compose(Canonical, Effect)
    ;   metta_host_pure_operation(Name),
        Effect = pureStructural
    ).

metta_fixed_operation_effect(Name, Effect) :-
    (   metta_semantic_effect(Name, Semantic)
    ->  Effect = Semantic
    ;   metta_builtin_effect(Name, Effect)
    ).

%The native vocabulary has the same closed effect boundary as registered host
%operations. A missing reviewed special case is oracleIO, never structural:
%adding a builtin can therefore make admission stricter but cannot silently
%let a world run host input or mutation. The structural floor reuses the
%engine's existing reviewed primitive families, except for operations whose
%answer cardinality is itself observable. The remaining named groups are the
%interpreter profile proved by LeaTTa's Minimal/EffectSafety.lean, extended by
%MeTTa's host bridges and operating-system doors.
%A backend's own builtin is reviewed by the backend, because the engine cannot
%review a predicate it does not ship without naming it. The classification
%arrives with the registration (seam:extension_builtin/2), so it is read here
%rather than defaulted: without it MORK's three builtins fell to the oracleIO
%floor below, which is SAFE but says "nobody looked" in the same voice as
%"reviewed and unbounded".
metta_builtin_effect(Name, Effect) :-
    builtin_fun(Name),
    (   metta_builtin_effect_override(Name, Reviewed)
    ->  Effect = Reviewed
    ;   seam:extension_builtin(Name, Declared)
    ->  Effect = Declared
    ;   metta_builtin_structural(Name)
    ->  Effect = pureStructural
    ;   Effect = oracleIO
    ).

%Interpreter operations can disappear into control goals during translation,
%and several are not builtin_fun/1 leaves at all. Keep the complete reviewed
%profile independent of that registry. The five groups are the executable
%lists in LeaTTa's MettaHyperonFull/Minimal/EffectSafety.lean; the
%embedded-operation coverage test below the planner rejects drift between this
%profile and translator:embedded_operation_head/1.
metta_semantic_effect(chain, pureStructural).
metta_semantic_effect('cons-atom', pureStructural).
metta_semantic_effect('decons-atom', pureStructural).
metta_semantic_effect(function, pureStructural).

metta_semantic_effect('context-space', readOnlyLookup).
metta_semantic_effect('get-metatype', readOnlyLookup).
metta_semantic_effect('get-state', readOnlyLookup).
metta_semantic_effect('get-atoms', readOnlyLookup).
metta_semantic_effect('get-deps', readOnlyLookup).
metta_semantic_effect('module-tree!', readOnlyLookup).
metta_semantic_effect('loaded-mods!', readOnlyLookup).
metta_semantic_effect('skel-swap-pair-native', readOnlyLookup).
metta_semantic_effect('fuzzy-match-space', readOnlyLookup).
metta_semantic_effect('fuzzy-match-context', readOnlyLookup).

metta_semantic_effect(empty, nondeterministicReadOnly).
metta_semantic_effect(hyperpose, nondeterministicReadOnly).
metta_semantic_effect('near-match', nondeterministicReadOnly).
metta_semantic_effect(superpose, nondeterministicReadOnly).
metta_semantic_effect('superpose-bind', nondeterministicReadOnly).
metta_semantic_effect(unify, nondeterministicReadOnly).
metta_semantic_effect('unify%', nondeterministicReadOnly).

metta_semantic_effect(eval, writesState).
metta_semantic_effect(evalc, writesState).
metta_semantic_effect('collapse-bind', writesState).
metta_semantic_effect(metta, writesState).
metta_semantic_effect('metta-thread', writesState).
metta_semantic_effect(capture, writesState).
metta_semantic_effect('pragma!', writesState).
metta_semantic_effect(match, writesState).
metta_semantic_effect('match%', writesState).
metta_semantic_effect('get-type', writesState).
metta_semantic_effect('get-type-space', writesState).
metta_semantic_effect('_new-state', writesState).
metta_semantic_effect('change-state!', writesState).
metta_semantic_effect('new-space', writesState).
metta_semantic_effect('fork-space', writesState).
metta_semantic_effect('add-atom', writesState).
metta_semantic_effect('remove-atom', writesState).
metta_semantic_effect('bind!', writesState).
metta_semantic_effect('module-space-no-deps', writesState).
metta_semantic_effect('print-mods!', writesState).
metta_semantic_effect('println!', writesState).
metta_semantic_effect('trace!', writesState).
metta_semantic_effect(sealed, writesState).

metta_semantic_effect('git-import!', oracleIO).
metta_semantic_effect('git-module!', oracleIO).
metta_semantic_effect('import!', oracleIO).
metta_semantic_effect('import-into!', oracleIO).
metta_semantic_effect('import-item!', oracleIO).
metta_semantic_effect(include, oracleIO).
metta_semantic_effect('mod-space!', oracleIO).

%Control forms below only choose, bind, catch, or compare already planned
%values. Their emitted helpers are not world effects of their own.
metta_semantic_effect(call, oracleIO).
metta_semantic_effect(case, pureStructural).
metta_semantic_effect(catch, pureStructural).
metta_semantic_effect(collapse, pureStructural).
metta_semantic_effect(cut, pureStructural).
metta_semantic_effect('filter-atom', pureStructural).
metta_semantic_effect(foldall, pureStructural).
metta_semantic_effect('foldl-atom', pureStructural).
metta_semantic_effect(forall, pureStructural).
metta_semantic_effect(if, pureStructural).
metta_semantic_effect(inferences, pureStructural).
metta_semantic_effect(let, pureStructural).
metta_semantic_effect('let*', pureStructural).
metta_semantic_effect('map-atom', pureStructural).
metta_semantic_effect(noeval, pureStructural).
metta_semantic_effect(nop, pureStructural).
metta_semantic_effect('not-provable', pureStructural).
metta_semantic_effect(once, pureStructural).
metta_semantic_effect(prog1, pureStructural).
metta_semantic_effect(progn, pureStructural).
metta_semantic_effect(quote, pureStructural).
metta_semantic_effect(reduce, pureStructural).
metta_semantic_effect(return, pureStructural).
metta_semantic_effect(super, pureStructural).
metta_semantic_effect(switch, pureStructural).
metta_semantic_effect(take, pureStructural).
metta_semantic_effect(test, pureStructural).
metta_semantic_effect('test-no-answer', pureStructural).
metta_semantic_effect(transaction, pureStructural).
metta_semantic_effect(translatePredicate, oracleIO).
metta_semantic_effect('with-pragma!', pureStructural).
metta_semantic_effect('with-seed', pureStructural).
metta_semantic_effect(with_mutex, pureStructural).
metta_semantic_effect('|->', pureStructural).

%These forms observe mutable execution metadata rather than only their
%written values. Annotation, explain and top read engine/catalog state;
%elapsed and timeout consult host scheduling time and therefore occupy the
%top rank even when the expression they wrap is structural.
metta_semantic_effect(annotation, readOnlyLookup).
metta_semantic_effect(explain, readOnlyLookup).
metta_semantic_effect(top, readOnlyLookup).
metta_semantic_effect(elapsed, oracleIO).
metta_semantic_effect(timeout, oracleIO).

%member/2 is safe to repeat for cache purposes but can answer more than once.
%World admission classifies observable answer cardinality, not cache safety.
metta_builtin_effect_override(member, nondeterministicReadOnly).

%The names below are the remainder of builtin_fun/1 after the established
%primitive families and the engine/host doors. Keeping every shipped name in
%a reviewed row makes a newly registered builtin fail closed through the
%fallback above while the exhaustive profile test names the drift.
metta_builtin_effect_override('Predicate', pureStructural).
metta_builtin_effect_override('atom-subst', pureStructural).
metta_builtin_effect_override('format-args', pureStructural).
metta_builtin_effect_override('noreduce-eq', pureStructural).
metta_builtin_effect_override('pretty-atom', pureStructural).
metta_builtin_effect_override('sort-strings', pureStructural).
metta_builtin_effect_override(throw, pureStructural).
metta_builtin_effect_override('and-then', pureStructural).
metta_builtin_effect_override('or-else', pureStructural).
metta_builtin_effect_override('if-equal', pureStructural).
metta_builtin_effect_override('if-equal2', pureStructural).
metta_builtin_effect_override('if-error', pureStructural).
metta_builtin_effect_override('return-on-error', pureStructural).
metta_builtin_effect_override(atomically, pureStructural).
metta_builtin_effect_override('for-each-in-atom', pureStructural).
metta_builtin_effect_override(unquote, pureStructural).

metta_builtin_effect_override('is-function', readOnlyLookup).
metta_builtin_effect_override('residual-goals', readOnlyLookup).
%A require reads the loader's own records, stats the seat directory when no
%record answers, and either succeeds with nothing changed or throws. Reading
%engine state IS readOnlyLookup, and the throw does not raise the class: a
%refusal is not an effect on the world, and every builtin that refuses an
%unbound input throws from inside whatever class it already carries. It is not
%pureStructural, because the answer depends on which seats this process loaded
%rather than on the argument alone, which is the same reason 'is-function' and
%'residual-goals' above are readOnlyLookup rather than structural.
metta_builtin_effect_override('require-extension!', readOnlyLookup).

metta_builtin_effect_override('alpha-unique', nondeterministicReadOnly).
metta_builtin_effect_override(documented, nondeterministicReadOnly).
metta_builtin_effect_override('documented-space',
                              nondeterministicReadOnly).
metta_builtin_effect_override(intersection, nondeterministicReadOnly).
metta_builtin_effect_override('match-type-or',
                              nondeterministicReadOnly).
metta_builtin_effect_override('match-types', nondeterministicReadOnly).
metta_builtin_effect_override(subtraction, nondeterministicReadOnly).
metta_builtin_effect_override(undocumented, nondeterministicReadOnly).
metta_builtin_effect_override('undocumented-space',
                              nondeterministicReadOnly).
metta_builtin_effect_override(union, nondeterministicReadOnly).
metta_builtin_effect_override(unique, nondeterministicReadOnly).

metta_builtin_effect_override(assertaPredicate, writesState).
metta_builtin_effect_override(assertzPredicate, writesState).
metta_builtin_effect_override('declare-post-add!', writesState).
metta_builtin_effect_override('declare-pre-add!', writesState).
metta_builtin_effect_override(retractPredicate, writesState).
metta_builtin_effect_override('type-cast', writesState).
metta_builtin_effect_override('type-cast-holds', writesState).
metta_builtin_effect_override('undeclare-post-add!', writesState).
metta_builtin_effect_override('undeclare-pre-add!', writesState).
metta_builtin_effect_override(interpret, writesState).

metta_builtin_effect_override(assert, oracleIO).
metta_builtin_effect_override(assertAlphaEqual, oracleIO).
metta_builtin_effect_override(assertAlphaEqualMsg, oracleIO).
metta_builtin_effect_override(assertAlphaEqualToResult, oracleIO).
metta_builtin_effect_override(assertAlphaEqualToResultMsg, oracleIO).
metta_builtin_effect_override(assertEqual, oracleIO).
metta_builtin_effect_override(assertEqualMsg, oracleIO).
metta_builtin_effect_override(assertEqualToResult, oracleIO).
metta_builtin_effect_override(assertEqualToResultMsg, oracleIO).
metta_builtin_effect_override(assertIncludes, oracleIO).
metta_builtin_effect_override(callPredicate, oracleIO).
metta_builtin_effect_override(check_prolog_function_names, oracleIO).
metta_builtin_effect_override('help!', oracleIO).
metta_builtin_effect_override(import_prolog_function, oracleIO).
metta_builtin_effect_override(import_prolog_functions, oracleIO).
metta_builtin_effect_override(register_metta_library_path, oracleIO).

metta_builtin_effect_override('context-space', readOnlyLookup).
metta_builtin_effect_override('get-atoms', readOnlyLookup).
metta_builtin_effect_override('get-metatype', readOnlyLookup).
metta_builtin_effect_override('get-state', readOnlyLookup).
metta_builtin_effect_override('has-declared-type', readOnlyLookup).
metta_builtin_effect_override('is-space', readOnlyLookup).
metta_builtin_effect_override('defined-name', readOnlyLookup).
metta_builtin_effect_override('get-doc', readOnlyLookup).
metta_builtin_effect_override('get-doc-atom', readOnlyLookup).
metta_builtin_effect_override('get-doc-function', readOnlyLookup).
metta_builtin_effect_override('get-doc-params', readOnlyLookup).
metta_builtin_effect_override('get-doc-single-atom', readOnlyLookup).
metta_builtin_effect_override('get-doc-space', readOnlyLookup).
metta_builtin_effect_override('space-admission-verdict', readOnlyLookup).
metta_builtin_effect_override('space-atom-count', readOnlyLookup).
metta_builtin_effect_override('space-contains', readOnlyLookup).

metta_builtin_effect_override('add-atom', writesState).
metta_builtin_effect_override('add-atoms', writesState).
metta_builtin_effect_override('add-reduct', writesState).
metta_builtin_effect_override('add-reducts', writesState).
metta_builtin_effect_override('add-translator-rule!', writesState).
metta_builtin_effect_override('remove-translator-rule!', writesState).
metta_builtin_effect_override('add-typing-rule!', writesState).
metta_builtin_effect_override('remove-typing-rule!', writesState).
metta_builtin_effect_override('bind!', writesState).
metta_builtin_effect_override('change-state!', writesState).
metta_builtin_effect_override('collapse-bind', writesState).
metta_builtin_effect_override(eval, writesState).
metta_builtin_effect_override(evalc, writesState).
metta_builtin_effect_override('get-type', writesState).
metta_builtin_effect_override('get-type-space', writesState).
metta_builtin_effect_override(match, writesState).
metta_builtin_effect_override(metta, writesState).
metta_builtin_effect_override('metta-thread', writesState).
metta_builtin_effect_override('new-space', writesState).
metta_builtin_effect_override('new-state', writesState).
metta_builtin_effect_override('pragma!', writesState).
metta_builtin_effect_override('println!', writesState).
metta_builtin_effect_override('trace!', writesState).
metta_builtin_effect_override('register-token!', writesState).
metta_builtin_effect_override('unregister-token!', writesState).
metta_builtin_effect_override('remove-atom', writesState).

metta_builtin_effect_override(argv, oracleIO).
metta_builtin_effect_override('current-time', oracleIO).
metta_builtin_effect_override(exists_file, oracleIO).
metta_builtin_effect_override('format-time', oracleIO).
metta_builtin_effect_override('git-import!', oracleIO).
metta_builtin_effect_override('import!', oracleIO).
metta_builtin_effect_override(include, oracleIO).
metta_builtin_effect_override(library, oracleIO).
metta_builtin_effect_override('parse-command', oracleIO).
metta_builtin_effect_override('random-float', oracleIO).
metta_builtin_effect_override('random-int', oracleIO).
metta_builtin_effect_override('read-form!', oracleIO).
metta_builtin_effect_override('readln!', oracleIO).
metta_builtin_effect_override(sleep, oracleIO).

metta_builtin_structural(Name) :- pure_arithmetic(Name), !.
metta_builtin_structural(Name) :- pure_comparison(Name), !.
metta_builtin_structural(Name) :- pure_structure(Name), !.
metta_builtin_structural(Name) :- pure_inspection(Name), !.
metta_builtin_structural('#*').
metta_builtin_structural('#+').
metta_builtin_structural('#-').
metta_builtin_structural('#//').
metta_builtin_structural('#<').
metta_builtin_structural('#=').
metta_builtin_structural('#=<').
metta_builtin_structural('#>').
metta_builtin_structural('#>=').
metta_builtin_structural('#\\=').
metta_builtin_structural('#div').
metta_builtin_structural('#max').
metta_builtin_structural('#min').
metta_builtin_structural('#mod').

%A plan is a list of operation names. maplist/3 makes an unclassified member
%fail the whole plan rather than silently treating it as pure. The empty plan
%inherits metta_effect_compose/2's pureStructural identity.
metta_operation_plan_effect(Operations, Effect) :-
    maplist(metta_operation_effect, Operations, Classes),
    metta_effect_compose(Classes, Effect).

%%%% Effect plans for reified-world admission %%%%
%
%Registration and compiled Python definitions publish an (effect Name Class)
%summary. A raw MeTTa equation has no summary, so the planner follows its
%compiled clauses until it reaches a published operation. This is the same
%compiled-body and control-construct walk used by cache admission above, while
%the join remains metta_effect_compose/2's one lattice operation. Native
%builtins and effectful semantic special forms add their canonical row even
%when translation lowers the written head away. World-local add/remove/match
%remain scratch effects, but they still require explicit coverage.
%A bridge that somehow lacks its mandatory declaration and a dynamic callable
%are conservatively oracleIO, so an unclassified grounded call cannot pass as
%structural [tested:
%effects_lattice:a_compiled_goal_plan_follows_raw_definitions_and_joins_operations,
%effects_lattice:an_unclassified_bridge_and_dynamic_call_fail_closed_at_oracle_io;
%commit=WORKTREE].
metta_host_goal_effect_plan(Module,
                            (metta_effect_source_term(Source), Body),
                            Operations, Effect) :-
    !,
    metta_effect_plan_source_complete(Module, Source, RuntimeState),
    (   RuntimeState = Roots0-_,
        member(Name/_, Roots0),
        translator_rules:translator_rule(Name, _)
    ->  metta_effect_plan_body_source_backed(
            Module, Body, RuntimeState, Roots-Direct)
    ;   Roots-Direct = RuntimeState
    ),
    metta_effect_plan_finish(Module, Roots-Direct, Operations, Effect).
metta_host_goal_effect_plan(Module, Body, Operations, Effect) :-
    metta_effect_plan_body(Module, Body, []-[], Roots-Direct),
    metta_effect_plan_finish(Module, Roots-Direct, Operations, Effect).

%A translation rule is executable Prolog. Ask the retained source for its
%lower bound before translating a world target, so an uncovered rule cannot
%perform compile-time work on the way to its own refusal.
metta_host_source_effect_plan(Module, Source, Operations, Effect) :-
    metta_effect_plan_source_complete(Module, Source, Roots-Direct),
    metta_effect_plan_finish(Module, Roots-Direct, Operations, Effect).

%Replaying a frozen program executes only its compilation positions. Publish
%that projection separately so world admission can cover translator actions
%before it allocates and populates the receiver that will run them.
metta_host_source_compile_effect_plan(Module, Source, Operations, Effect) :-
    metta_effect_plan_program_write(
        Module, 'add-atom', '<world-image>', Source,
        []-[], Roots-Direct),
    metta_effect_plan_finish(Module, Roots-Direct, Operations, Effect).

%Saga instrumentation needs the operations the target can execute, excluding
%compiler actions needed only to materialise it. Keeping this as the runtime
%projection of the same source walk prevents global predicate wrapping from
%turning compiler internals into user recovery obligations.
metta_host_source_runtime_effect_plan(Module, Source, Operations, Effect) :-
    metta_effect_plan_source_root(Module, Source, []-[], Roots-Direct),
    metta_effect_plan_finish(Module, Roots-Direct, Operations, Effect).

metta_effect_plan_finish(Module, Roots-Direct, Operations, Effect) :-
    metta_effect_plan_walk(Module, Roots, [], Direct, RawPairs),
    sort(RawPairs, Pairs),
    maplist(metta_effect_plan_row, Pairs, Operations),
    maplist(metta_effect_plan_class, Pairs, Classes),
    metta_effect_compose(Classes, Effect).

%A retained source term preserves the language's masks, static type refusals
%and staged boundaries. Its compiled goal no longer does: rejected dispatch
%still contains the operation behind a runtime type guard, and a function
%return payload still resembles an eager call. Plan runtime semantics from the
%source and add only the compiler effects that happen while materialising it.
%Generated clauses without retained source continue through the goal walker.
metta_effect_plan_source_complete(Module, Source, Roots-Direct) :-
    metta_effect_plan_source_root(Module, Source, []-[], RuntimeState),
    metta_effect_plan_compile_root(Module, Source, RuntimeState,
                                   Roots-Direct).

%Translation is itself observable when a registered translator rule runs.
%Walk the written compile positions without invoking translate_expr/3: a
%world must refuse the rule before the admission query, rather than letting
%the query execute it while discovering that it should have refused. Runtime
%operation effects stay in the source walk above; this pass contributes only
%the compiler action.
metta_effect_plan_compile_root(Module, Source, State0, State) :-
    metta_effect_plan_compile_source(Module, Source, State0, State).

metta_effect_plan_compile_source(_, Source, State, State) :-
    var(Source),
    !.
metta_effect_plan_compile_source(_, Source, State, State) :-
    \+ Source = [_|_],
    !.
metta_effect_plan_compile_source(_, Source, Queue-Effects,
                                 Queue-['<dynamic-translation>'-oracleIO|
                                       Effects]) :-
    \+ is_list(Source),
    !.
metta_effect_plan_compile_source(_, [Head|Args], Queue0-Effects,
                                 [Head/Arity|Queue0]-Effects) :-
    atom(Head),
    translator_rules:translator_rule(Head, _),
    !,
    length(Args, ArgCount),
    Arity is ArgCount + 1.
metta_effect_plan_compile_source(Module, [Head|Args], State0, State) :-
    metta_effect_plan_compile_arguments(Module, Head, Args, Compiled),
    foldl(metta_effect_plan_compile_source(Module), Compiled,
          State0, State).

%Function holds its body for the runtime instruction loop. Lambda is the
%opposite: it does not run the body now, but its constructor compiles that
%body immediately. Space updates compile only their space operand here; the
%runtime program-write pass below owns equation and declaration compilation.
metta_effect_plan_compile_arguments(_, function, [_], []).
metta_effect_plan_compile_arguments(_, '|->', [_, Body], [Body]).
metta_effect_plan_compile_arguments(_, Operation, [Space, _], [Space]) :-
% policy-inventory-exempt: mechanism-internal; reason=the five space updates whose SPACE operand compiles, a shape of the operation rather than a policy value a catalog vocabulary could own; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_program_write_compilation_is_included_in_world_admission
    memberchk(Operation,
              ['add-atom', 'remove-atom', 'add-atoms',
               'add-reduct', 'add-reducts']).
metta_effect_plan_compile_arguments(Module, Head, Args, Compiled) :-
    metta_effect_plan_source_special_arguments(
        Module, Head, Args, Compiled),
    !.
metta_effect_plan_compile_arguments(Module, Head, Args, Compiled) :-
    metta_effect_plan_source_masked_arguments(
        Module, Head, Args, Compiled).

%Adding a definition compiles it, and adding/removing a definition or type
%declaration recompiles affected callers through the support graph. Inspect
%those retained source bodies for translator rules before the write. Ordinary
%data remains a writesState operation and pays no compiler effect.
metta_effect_plan_program_write(_, _, '&metta', _, Queue-Effects,
                                Queue-['<catalog-policy-mutation>'-oracleIO|
                                      Effects]) :-
    !.
metta_effect_plan_program_write(Module, Operation, Space, Payload, State0, State) :-
% policy-inventory-exempt: mechanism-internal; reason=the two space updates whose payload is a LIST of writes rather than one, which is a shape of the operation, not a policy; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_reducing_space_writes_plan_the_expression_they_execute
    memberchk(Operation, ['add-atoms', 'add-reducts']),
    is_list(Payload),
    !,
    foldl(metta_effect_plan_program_write(Module, Operation, Space), Payload,
          State0, State).
metta_effect_plan_program_write(_, _, _, Payload, Queue-Effects,
                                Queue-['<program-compilation>'-oracleIO|
                                      Effects]) :-
    var(Payload),
    !.
metta_effect_plan_program_write(Module, Operation, _, Payload, State0, State) :-
    metta_effect_plan_program_subject(Payload, Name, Kind),
    !,
    metta_effect_plan_new_program_source(
        Module, Operation, Kind, Payload, State0, AfterNew),
    metta_effect_plan_affected_program_sources(
        Module, Name, Operation, Kind, Payload, AfterNew, State).
metta_effect_plan_program_write(_, _, _, _, State, State).

metta_effect_plan_program_subject([=, [Name|_], _], Name, equation) :-
    atom(Name).
metta_effect_plan_program_subject([':', Name, _], Name, declaration) :-
    atom(Name).

metta_effect_plan_new_program_source(Module, Operation, equation,
                                     [=, _, Body], State0, State) :-
% policy-inventory-exempt: mechanism-internal; reason=the two space updates that ADD a definition, the only ones whose payload the compiler then reads; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_program_write_compilation_is_included_in_world_admission
    memberchk(Operation, ['add-atom', 'add-atoms']),
    !,
    metta_effect_plan_compile_source(Module, Body, State0, State).
metta_effect_plan_new_program_source(_, _, _, _, State, State).

metta_effect_plan_affected_program_sources(Module, Name, Operation, Kind,
                                           Removed,
                                           State0, State) :-
    findall(AffectedModule-AffectedName,
            metta_effect_plan_affected_function(
                Module, Name, Operation, Kind,
                AffectedModule, AffectedName),
            Affected0),
    sort(Affected0, Affected),
    findall(SourceModule-Source,
            ( member(SourceModule-Function, Affected),
              translated_from(Ref, Source),
              Source = [=, [Function|_], _],
              clause_property(Ref, module(SourceModule)),
              \+ Source =@= Removed ),
            Sources0),
    sort(Sources0, Sources),
    foldl(metta_effect_plan_compile_equation, Sources, State0, State).

metta_effect_plan_compile_equation(SourceModule-[=, _, Body],
                                   State0, State) :-
    metta_effect_plan_compile_source(SourceModule, Body, State0, State).

metta_effect_plan_affected_function(Module, Name, _, declaration,
                                    Module, Name).
metta_effect_plan_affected_function(Module, Name, 'remove-atom', _,
                                    Module, Name).
metta_effect_plan_affected_function(Module, Name, _, _,
                                    AffectedModule, AffectedName) :-
    metta_effect_plan_change_root(Module, Name, Root),
    metta_effect_plan_support_reachable(Root, [], Node),
    Node = compiled_function(AffectedModule, AffectedName).

metta_effect_plan_change_root(Module, Name, function(Module, Name)) :-
    support_graph:support_function_module(Name, Module).
metta_effect_plan_change_root(_, Name, function_view(ViewModule, Name)) :-
    support_graph:support_view_module(Name, ViewModule).

metta_effect_plan_support_reachable(Node, _, Node).
metta_effect_plan_support_reachable(Node, Seen, Reachable) :-
    \+ memberchk(Node, Seen),
    support_graph:supports(Node, Next),
    metta_effect_plan_support_reachable(Next, [Node|Seen], Reachable).

metta_effect_plan_walk(_, [], _, Effects, Effects).
metta_effect_plan_walk(Module, [PI|Rest], Seen, Effects0, Effects) :-
    memberchk(PI, Seen),
    !,
    metta_effect_plan_walk(Module, Rest, Seen, Effects0, Effects).
metta_effect_plan_walk(Module, [Name/Arity|Rest], Seen, Effects0, Effects) :-
    functor(Head, Name, Arity),
    findall(effect_clause(Body, Source),
            catch_recover(
                ( clause(Module:Head, Body, Ref),
                  clause_property(Ref, module(Module)),
                  ( translated_from(Ref, [=, SourceHead, SourceBody])
                  -> Source = source(SourceHead, SourceBody)
                  ;  Source = none ) ),
                fail),
            LocalClauses),
    metta_effect_plan_inherited_source_clauses(
        Name, Arity, LocalClauses, Clauses),
    (   Clauses == []
    ->  Next = Rest,
        Effects1 = [Name-oracleIO|Effects0]
    ;   foldl(metta_effect_plan_clause(Module), Clauses,
              Rest-Effects0, Next-Effects1)
    ),
    metta_effect_plan_walk(Module, Next, [Name/Arity|Seen], Effects1, Effects).

metta_effect_plan_inherited_source_clauses(_, _, Clauses, Clauses) :-
    Clauses = [_|_],
    !.
metta_effect_plan_inherited_source_clauses(Name, Arity, [], Clauses) :-
    findall(effect_clause(true, source(SourceHead, SourceBody)),
            ( prelude_equation(Name, [=, SourceHead, SourceBody]),
              SourceHead = [_|Args],
              length(Args, InputArity),
              Arity is InputArity + 1 ),
            Clauses).

metta_effect_plan_clause(Module, effect_clause(Body, Source), State0, State) :-
    metta_effect_plan_clause_source(Module, Source, State0, Mid),
    metta_effect_plan_clause_body(Module, Source, Body, Mid, State).

metta_effect_plan_clause_body(_, source(_, _), _, State, State) :-
    !,
    true.
metta_effect_plan_clause_body(Module, none, Body, State0, State) :-
    metta_effect_plan_body(Module, Body, State0, State).

metta_effect_plan_clause_source(_, none, State, State).
metta_effect_plan_clause_source(Module, source(Head, Source), State0, State) :-
    var(Source),
    metta_effect_plan_declared_final_result(Module, Head),
    !,
    State = State0.
metta_effect_plan_clause_source(Module, source(_, Source), State0, State) :-
    metta_effect_plan_source_root(Module, Source, State0, State).

%A bare equation RHS is callable only when the selected result type asks the
%application boundary to evaluate it. Atom, Number, BigInt, String and
%Grounded are final result types in the translator itself; a variable of one
%of those types is data, while %Undefined% and polymorphic results remain a
%runtime operation uncertainty.
metta_effect_plan_declared_final_result(Module, [Name|Args]) :-
    atom(Name),
    length(Args, Arity),
    catch_recover(
        with_metta_module(
            Module,
            ( translator:call_site_type_chains(Name, Chains),
              Chains \== [],
              translator:fitting_type_chains(Chains, Arity, Selection) )),
        fail),
    Selection = [_|_],
    forall(member(Chain, Selection),
           ( translator:present_type_chain(
                 Chain, Arity, [->|Presented]),
             last(Presented, Declared),
             translator:declared_type_for_evaluation(Declared, View),
             translator:intrinsically_final_builtin_result(View) )).

metta_effect_plan_body(_, Body, Queue-Effects,
                       Queue-['<dynamic-operation>'-oracleIO|Effects]) :-
    var(Body),
    !.
metta_effect_plan_body(Module, Body, Queue0-Effects0, Queue-Effects) :-
    findall(Goal, metta_effect_goal(Body, Goal), Goals),
    foldl(metta_effect_plan_classify(Module), Goals,
          Queue0-Effects0, Queue-Effects).

%A retained equation source is the authority for a runtime value the compiled
%body carries as a bare Prolog variable. Its root walk classifies such a value
%as dynamic. Suppressing only the compiler's duplicate masked-result variable
%avoids falsely raising a statically final chain result to oracleIO. Generated
%clauses without translated_from/2 keep the ordinary fail-closed rule.
metta_effect_plan_body_source_backed(
        _, Body, Queue-Effects,
        Queue-['<dynamic-operation>'-oracleIO|Effects]) :-
    var(Body),
    !.
metta_effect_plan_body_source_backed(Module, Body,
                                     Queue0-Effects0, Queue-Effects) :-
    findall(Goal, metta_effect_goal(Body, Goal), Goals),
    foldl(metta_effect_plan_classify_source_backed(Module), Goals,
          Queue0-Effects0, Queue-Effects).

metta_effect_plan_classify_source_backed(
        _, metta_masked_result(Template, _), State, State) :-
    var(Template),
    !.
metta_effect_plan_classify_source_backed(Module, Goal, State0, State) :-
    metta_effect_plan_classify(Module, Goal, State0, State).

metta_effect_plan_classify(_, Goal, Queue-Effects,
                           Queue-['<dynamic-operation>'-oracleIO|Effects]) :-
    var(Goal),
    !.
metta_effect_plan_classify(_, Dispatch, Queue-Effects0, Queue-Effects) :-
    compound(Dispatch),
    seam:effect_operation_name(Dispatch, Name, _),
    !,
    metta_effect_plan_grounded(Name, Effects0, Effects).
%The nested-evaluator doors retain their source term as an argument. Translate
%that term under the same module and plan its resulting body, rather than
%classifying the evaluator helper itself as oracleIO or ignoring its payload.
metta_effect_plan_classify(Module, metta_eval_step(Source, _),
                           State0, State) :-
    !,
    metta_effect_plan_source_term(Module, Source, State0, State).
metta_effect_plan_classify(Module, metta_evalc_step(Source, _, _),
                           State0, State) :-
    !,
    metta_effect_plan_source_term(Module, Source, State0, State).
metta_effect_plan_classify(Module, metta(Source, _, _, _),
                           Queue-Effects0, State) :-
    !,
    metta_effect_plan_grounded(metta, Effects0, Effects1),
    metta_effect_plan_source_term(Module, Source, Queue-Effects1, State).
metta_effect_plan_classify(Module, 'metta-thread'(Source, _, _, _),
                           Queue-Effects0, State) :-
    !,
    metta_effect_plan_grounded('metta-thread', Effects0, Effects1),
    metta_effect_plan_source_term(Module, Source, Queue-Effects1, State).
metta_effect_plan_classify(Module, 'collapse-bind'(Source, _),
                           Queue-Effects0, State) :-
    !,
    metta_effect_plan_grounded('collapse-bind', Effects0, Effects1),
    metta_effect_plan_source_term(Module, Source, Queue-Effects1, State).
metta_effect_plan_classify(Module, reduce(Template, _, _), State0, State) :-
    !,
    metta_effect_plan_reduced(Module, Template, State0, State).
metta_effect_plan_classify(Module,
                           metta_dynamic_call(Head, Args, _),
                           State0, State) :-
    !,
    metta_effect_plan_reduced(Module, [Head|Args], State0, State).
metta_effect_plan_classify(Module,
                           metta_dynamic_value_call(Head, _, Values, _),
                           State0, State) :-
    !,
    metta_effect_plan_reduced(Module, [Head|Values], State0, State).
metta_effect_plan_classify(_, metta_dynamic_head_masks(_), State, State) :- !.
%The host prefixes this planner-only carrier to the translated target. It is
%consumed here and never reaches execution; the same read-only source walk is
%also applied to retained equation bodies below.
metta_effect_plan_classify(Module, metta_effect_source_term(Source),
                           State0, State) :-
    !,
    metta_effect_plan_source_root(Module, Source, State0, State).
metta_effect_plan_classify(Module, metta_masked_result(Template, _),
                           State0, State) :-
    !,
    metta_effect_plan_masked_result(Module, Template, State0, State).
%An opaque grounded callable has no symbol whose effect row can be queried.
%It is the higher-order counterpart of a variable-headed reduce.
metta_effect_plan_classify(_, grounded_apply(_, _, _),
                           Queue-Effects, Queue-Next) :-
    !,
    metta_effect_plan_dynamic(Effects, Next).
metta_effect_plan_classify(Module, Goal, State0, State) :-
    compound(Goal),
    !,
    functor(Goal, Name, Arity),
    metta_effect_plan_named_call(Module, Name, Arity, State0, State).
metta_effect_plan_classify(_, Goal, State, State) :-
% policy-inventory-exempt: mechanism-internal; reason=Prolog's three control leaves, which the language fixes; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_a_typed_structural_chain_is_not_falsely_refused
    memberchk(Goal, [true, fail, !]),
    !.
metta_effect_plan_classify(Module, Goal, State0, State) :-
    atom(Goal),
    !,
    metta_effect_plan_named_call(Module, Goal, 0, State0, State).
metta_effect_plan_classify(_, _, State, State).

metta_effect_plan_source_term(Module, Source, State0, State) :-
    metta_effect_plan_source_root(Module, Source, State0, State).

metta_effect_plan_source_root(_, Source, Queue-Effects,
                              Queue-Next) :-
    var(Source),
    !,
    metta_effect_plan_dynamic(Effects, Next).
metta_effect_plan_source_root(Module, Source, State0, State) :-
    metta_effect_plan_source(Module, Source, State0, State).

%Read a retained MeTTa term without compiling it again. Translation is not an
%observer: collection forms allocate lambda predicates and advance their
%generation while they compile. Admission may run repeatedly, so its source
%half follows the translator's declared evaluation mask as data and never
%calls translate_expr/3. A variable at a root/evaluator boundary is a runtime
%callable uncertainty; an ordinary operand variable is an already evaluated
%value, so only metta_effect_plan_source_root/4 treats that shape as dynamic.
metta_effect_plan_source(_, Source, State, State) :-
    var(Source),
    !.
%A function frame is an instruction interpreter. Its `return` instruction
%ends the frame with the payload as data, even when a preceding chain or eval
%reveals that instruction later. Keep the frame context on every executable
%child so an effect-looking return payload is not mistaken for a dispatched
%operation. The root marker retains the ordinary dynamic-call rule for a body
%that arrives only at run time; operand variables below it are finished values.
metta_effect_plan_source(Module, metta_function_instruction_root(Source),
                         State0, State) :-
    !,
    (   var(Source)
    ->  metta_effect_plan_dynamic_state(State0, State)
    ;   metta_effect_plan_function_instruction(Module, Source,
                                                State0, State)
    ).
metta_effect_plan_source(Module, metta_function_instruction(Source),
                         State0, State) :-
    !,
    metta_effect_plan_function_instruction(Module, Source, State0, State).
metta_effect_plan_source(Module,
                         metta_program_write(Operation, Space, Payload),
                         State0, State) :-
    !,
    metta_effect_plan_program_write(Module, Operation, Space, Payload,
                                    State0, State).
metta_effect_plan_source(Module, metta_evaluated_source_root(Source),
                         State0, State) :-
    !,
    metta_effect_plan_source_root(Module, Source, State0, State).
metta_effect_plan_source(Module, metta_unquoted_source(Source),
                         State0, State) :-
    !,
    metta_effect_plan_unquoted_source(Module, Source, State0, State).
metta_effect_plan_source(Module, metta_mapped_operation(Operation),
                         State0, State) :-
    !,
    metta_effect_plan_source_root(Module, [Operation, _], State0, State).
metta_effect_plan_source(_, Source, State, State) :-
    \+ Source = [_|_],
    !.
metta_effect_plan_source(_, Source, Queue-Effects,
                         Queue-['<dynamic-operation>'-oracleIO|Effects]) :-
    \+ is_list(Source),
    !.
%A typed-dispatch refusal is the complete execution plan: it constructs the
%BadArgType answer and calls neither the operation nor its operands. Decide it
%before adding the source head's declared effect, matching the translator's
%fitting_type_chains/3 gate rather than refusing a host effect that cannot run.
metta_effect_plan_source(Module, [Head|Args], State, State) :-
    atom(Head),
    \+ translator:metta_special_form(Head),
    catch_recover(
        with_metta_module(
            Module,
            metta_shallow_call_refused(Head, Args)),
        fail),
    !.
metta_effect_plan_source(Module, [Head|Args], State0, State) :-
    metta_effect_plan_source_head(Module, Head, Args, State0, AfterHead),
    metta_effect_plan_source_arguments(Module, Head, Args, Evaluated),
    foldl(metta_effect_plan_source(Module), Evaluated, AfterHead, State).

metta_effect_plan_dynamic_state(Queue-Effects, Queue-Next) :-
    metta_effect_plan_dynamic(Effects, Next).

metta_effect_plan_function_instruction(_, Source, State, State) :-
    var(Source),
    !.
metta_effect_plan_function_instruction(_, [return, _], State, State) :-
    !.
metta_effect_plan_function_instruction(_, Source, State, State) :-
    \+ Source = [_|_],
    !.
metta_effect_plan_function_instruction(_, Source, Queue-Effects,
                                       Queue-Next) :-
    \+ is_list(Source),
    !,
    metta_effect_plan_dynamic(Effects, Next).
metta_effect_plan_function_instruction(Module, [Head|Args], State0, State) :-
    metta_effect_plan_source_head(Module, Head, Args, State0, AfterHead),
    metta_effect_plan_source_arguments(Module, Head, Args, Evaluated),
    maplist(metta_effect_plan_function_child, Evaluated, Children),
    foldl(metta_effect_plan_source(Module), Children, AfterHead, State).

metta_effect_plan_function_child(metta_evaluated_source_root(Source),
                                 metta_function_instruction(Source)) :-
    !.
metta_effect_plan_function_child(Source,
                                 metta_function_instruction(Source)).

metta_effect_plan_unquoted_source(Module, [quote, Source], State0, State) :-
    !,
    metta_effect_plan_source_root(Module, Source, State0, State).
metta_effect_plan_unquoted_source(Module, Source, State0, State) :-
    metta_effect_plan_source_root(Module, Source, State0, State).

metta_effect_plan_source_head(_, Head, _, Queue-Effects,
                              Queue-Next) :-
    var(Head),
    !,
    metta_effect_plan_dynamic(Effects, Next).
%A translator rule may choose an expansion from arbitrary Prolog at compile
%time. Its compiled goals are still walked, but the retained source cannot
%prove which semantic heads the expansion erased, so the source half stays
%fail-closed instead of executing the rule again during admission.
metta_effect_plan_source_head(_, Head, Args, Queue0-Effects,
                              [Head/Arity|Queue0]-Effects) :-
    atom(Head),
    translator_rules:translator_rule(Head, _),
    !,
    length(Args, ArgCount),
    Arity is ArgCount + 1.
metta_effect_plan_source_head(Module, Head, Args, State0, State) :-
    atom(Head),
    (   metta_operation_effect(Head, _)
    ;   fun(Head)
    ),
    !,
    length(Args, ArgCount),
    Arity is ArgCount + 1,
    metta_effect_plan_named_call(Module, Head, Arity, State0, State).
metta_effect_plan_source_head(Module, Head, _, Queue-Effects0,
                              Queue-Effects) :-
    Head = [_|_],
    !,
    metta_effect_plan_source(Module, Head, Queue-Effects0, Queue-Mid),
    metta_effect_plan_dynamic(Mid, Effects).
metta_effect_plan_source_head(_, _, _, State, State).

%Special forms decide which written positions execute. This table mirrors the
%successful translator clauses: patterns, binders, write payloads and quoted
%atoms stay data; conditions, possible branches and nested evaluators are
%walked. Any shape not named here falls through to the declaration mask below.
metta_effect_plan_source_arguments(Module, Head, Args, Evaluated) :-
    metta_effect_plan_source_special_arguments(
        Module, Head, Args, Evaluated),
    !.
metta_effect_plan_source_arguments(Module, Head, Args, Evaluated) :-
    metta_effect_plan_source_masked_arguments(
        Module, Head, Args, Evaluated).

metta_effect_plan_source_special_arguments(_, annotation, [], []).
metta_effect_plan_source_special_arguments(_, cut, [], []).
metta_effect_plan_source_special_arguments(_, explain, [_], []).
metta_effect_plan_source_special_arguments(_, 'get-metatype', [_], []).
metta_effect_plan_source_special_arguments(_, noeval, [_], []).
metta_effect_plan_source_special_arguments(_, quote, [_], []).
metta_effect_plan_source_special_arguments(_, sealed, [_, _], []).
metta_effect_plan_source_special_arguments(_, 'and-then',
                                           [Condition, Then],
                                           [metta_evaluated_source_root(Condition),
                                            metta_evaluated_source_root(Then)]).
metta_effect_plan_source_special_arguments(_, 'or-else',
                                           [Condition, Else],
                                           [metta_evaluated_source_root(Condition),
                                            metta_evaluated_source_root(Else)]).
metta_effect_plan_source_special_arguments(_, Operation,
                                           [_, _, Then, Else],
                                           [metta_evaluated_source_root(Then),
                                            metta_evaluated_source_root(Else)]) :-
% policy-inventory-exempt: mechanism-internal; reason=the three builtins whose two possible branches the planner walks, mirroring the translator's own clauses rather than a catalog vocabulary; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_native_control_profiles_keep_pure_calls_and_nested_effects_distinct
    memberchk(Operation, ['if-equal', 'if-equal2', 'match-types']).
metta_effect_plan_source_special_arguments(_, 'if-error',
                                           [Expression, Then, Else],
                                           [metta_evaluated_source_root(Expression),
                                            metta_evaluated_source_root(Then),
                                            metta_evaluated_source_root(Else)]).
metta_effect_plan_source_special_arguments(_, 'return-on-error',
                                           [Expression, Then],
                                           [metta_evaluated_source_root(Expression),
                                            metta_evaluated_source_root(Then)]).
metta_effect_plan_source_special_arguments(_, atomically, [Expression],
                                           [metta_evaluated_source_root(Expression)]).
metta_effect_plan_source_special_arguments(_, 'for-each-in-atom', [_, Function],
                                           [metta_mapped_operation(Function)]).
metta_effect_plan_source_special_arguments(_, interpret,
                                           [Expression, _, Space],
                                           [metta_evaluated_source_root(Expression),
                                            Space]).
metta_effect_plan_source_special_arguments(_, unquote, [Expression],
                                           [metta_unquoted_source(Expression)]).
metta_effect_plan_source_special_arguments(_, function, [Body],
                                           [metta_function_instruction_root(Body)]).
metta_effect_plan_source_special_arguments(_, superpose, [Branches],
                                           Evaluated) :-
    is_list(Branches),
    maplist(metta_effect_plan_root_marker, Branches, Evaluated).
metta_effect_plan_source_special_arguments(_, hyperpose, [Branches],
                                           Evaluated) :-
    (   is_list(Branches)
    ->  maplist(metta_effect_plan_root_marker, Branches, Evaluated)
    ;   Evaluated = [metta_evaluated_source_root(Branches)]
    ).
metta_effect_plan_source_special_arguments(_, collapse, [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, test, [Expr, Expected],
                                           [metta_evaluated_source_root(Expr),
                                            metta_evaluated_source_root(Expected)]).
metta_effect_plan_source_special_arguments(_, 'test-no-answer', [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, once, [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, take, [Count, Expr],
                                           [metta_evaluated_source_root(Count),
                                            metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, top, [Count, Expr],
                                           [metta_evaluated_source_root(Count),
                                            metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, with_mutex, [_, Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, timeout, [Seconds, Expr],
                                           [metta_evaluated_source_root(Seconds),
                                            metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, 'with-pragma!',
                                           [Settings, Expr],
                                           [metta_evaluated_source_root(Settings),
                                            metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, inferences, [Count, Expr],
                                           [metta_evaluated_source_root(Count),
                                            metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, elapsed, [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, transaction, [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, 'with-seed', [Seed, Body],
                                           [metta_evaluated_source_root(Seed),
                                            metta_evaluated_source_root(Body)]).
metta_effect_plan_source_special_arguments(_, progn, Exprs, Evaluated) :-
    maplist(metta_effect_plan_root_marker, Exprs, Evaluated).
metta_effect_plan_source_special_arguments(_, prog1, Exprs, Evaluated) :-
    Exprs = [_|_],
    maplist(metta_effect_plan_root_marker, Exprs, Evaluated).
metta_effect_plan_source_special_arguments(_, nop, Exprs, Evaluated) :-
    maplist(metta_effect_plan_root_marker, Exprs, Evaluated).
metta_effect_plan_source_special_arguments(_, if, Exprs, Evaluated) :-
    ( Exprs = [_, _] ; Exprs = [_, _, _] ),
    maplist(metta_effect_plan_root_marker, Exprs, Evaluated).
metta_effect_plan_source_special_arguments(_, unify, [_, _, Then, Else],
                                           [metta_evaluated_source_root(Then),
                                            metta_evaluated_source_root(Else)]).
metta_effect_plan_source_special_arguments(_, case, [Key, Pairs],
                                           [metta_evaluated_source_root(Key)|
                                            Evaluated]) :-
    metta_effect_plan_case_bodies(Pairs, Bodies),
    maplist(metta_effect_plan_root_marker, Bodies, Evaluated).
metta_effect_plan_source_special_arguments(_, switch, [Key, Pairs],
                                           [metta_evaluated_source_root(Key)|
                                            Evaluated]) :-
    metta_effect_plan_case_bodies(Pairs, Bodies),
    maplist(metta_effect_plan_root_marker, Bodies, Evaluated).
metta_effect_plan_source_special_arguments(_, let, [_, Value, Body],
                                           [metta_evaluated_source_root(Value),
                                            metta_evaluated_source_root(Body)]).
metta_effect_plan_source_special_arguments(_, chain,
                                           [Nested, Binder, Template],
                                           Evaluated) :-
    (   var(Binder),
        nonvar(Nested),
        \+ translator:embedded_operation(Nested)
    ->  translator:substitute_written_variable(
            Binder, Nested, Template, Substituted),
        Evaluated = [metta_evaluated_source_root(Substituted)]
    ;   Evaluated = [metta_evaluated_source_root(Nested),
                     metta_evaluated_source_root(Template)]
    ).
metta_effect_plan_source_special_arguments(_, 'let*', [Bindings, Body],
                                           Evaluated) :-
    metta_effect_plan_binding_values(Bindings, Values),
    append(Values, [Body], Sources),
    maplist(metta_effect_plan_root_marker, Sources, Evaluated).
metta_effect_plan_source_special_arguments(_, forall, [Generator, Test],
                                           [metta_evaluated_source_root(Generator),
                                            metta_evaluated_source_root(Test)]).
metta_effect_plan_source_special_arguments(_, foldall,
                                           [Accumulator, Generator, Initial],
                                           [metta_evaluated_source_root(Accumulator),
                                            metta_evaluated_source_root(Generator),
                                            metta_evaluated_source_root(Initial)]).
%Collection operands and seeds are Atom/Expression data. Only their generated
%closure executes; the caller names a computed list or seed before this form.
metta_effect_plan_source_special_arguments(_, 'foldl-atom',
                                           [_, _, _, _, Body],
                                           [metta_evaluated_source_root(Body)]).
metta_effect_plan_source_special_arguments(_, 'map-atom', [_, _, Body],
                                           [metta_evaluated_source_root(Body)]).
metta_effect_plan_source_special_arguments(_, 'filter-atom', [_, _, Body],
                                           [metta_evaluated_source_root(Body)]).
metta_effect_plan_source_special_arguments(_, '|->', [_, _], []).
metta_effect_plan_source_special_arguments(_, Operation, [Space, Payload],
                                           [metta_evaluated_source_root(Space),
                                            metta_program_write(Operation, Space,
                                                                Payload)]) :-
% policy-inventory-exempt: mechanism-internal; reason=the three space updates whose payload is written data, mirroring the translator's argument masks rather than any policy; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_program_write_compilation_is_included_in_world_admission
    memberchk(Operation, ['add-atom', 'remove-atom', 'add-atoms']).
metta_effect_plan_source_special_arguments(_, Operation, [Space, Payload],
                                           [metta_evaluated_source_root(Space),
                                            metta_evaluated_source_root(Payload),
                                            metta_program_write(Operation, Space,
                                                                Payload)]) :-
% policy-inventory-exempt: mechanism-internal; reason=the two reducing space updates, whose payload is evaluated before it is written; evidence=extensions/python/tests/ch15_writing_transactions_and_worlds/test_worlds.py:test_reducing_space_writes_plan_the_expression_they_execute
    memberchk(Operation, ['add-reduct', 'add-reducts']).
metta_effect_plan_source_special_arguments(_, 'new-space', [Space], []) :-
    is_list(Space).
metta_effect_plan_source_special_arguments(_, match, [Space, _, Body],
                                           [metta_evaluated_source_root(Space),
                                            metta_evaluated_source_root(Body)]).
metta_effect_plan_source_special_arguments(_, translatePredicate, [Call],
                                           [metta_evaluated_source_root(Call)]) :-
    Call = [_|_].
metta_effect_plan_source_special_arguments(_, call, [Call],
                                           [metta_evaluated_source_root(Call)]) :-
    Call = [_|_].
metta_effect_plan_source_special_arguments(_, reduce, [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, eval, [Source],
                                           [metta_evaluated_source_root(Source)]).
metta_effect_plan_source_special_arguments(_, evalc, [Source, Space],
                                           [metta_evaluated_source_root(Source),
                                            metta_evaluated_source_root(Space)]).
metta_effect_plan_source_special_arguments(_, metta,
                                           [Source, _, Space],
                                           [metta_evaluated_source_root(Source),
                                            metta_evaluated_source_root(Space)]).
metta_effect_plan_source_special_arguments(_, 'metta-thread',
                                           [Source, _, Space],
                                           [metta_evaluated_source_root(Source),
                                            metta_evaluated_source_root(Space)]).
metta_effect_plan_source_special_arguments(_, 'collapse-bind', [Source],
                                           [metta_evaluated_source_root(Source)]).
metta_effect_plan_source_special_arguments(_, 'space-atom-count', [Space],
                                           [metta_evaluated_source_root(Space)]).
metta_effect_plan_source_special_arguments(_, 'space-contains', [Space, _],
                                           [metta_evaluated_source_root(Space)]).
metta_effect_plan_source_special_arguments(_, 'get-atoms', [Space],
                                           [metta_evaluated_source_root(Space)]).
metta_effect_plan_source_special_arguments(_, super, [Call],
                                           [metta_evaluated_source_root(Call)]).
metta_effect_plan_source_special_arguments(_, 'not-provable', [Expr],
                                           [metta_evaluated_source_root(Expr)]).
metta_effect_plan_source_special_arguments(_, catch, [Expr],
                                           [metta_evaluated_source_root(Expr)]).

metta_effect_plan_root_marker(Source,
                              metta_evaluated_source_root(Source)).

metta_effect_plan_case_bodies(Pairs, [Pairs]) :-
    var(Pairs),
    !.
metta_effect_plan_case_bodies(Pairs, Bodies) :-
    is_list(Pairs),
    !,
    metta_effect_plan_case_body_list(Pairs, Bodies).
metta_effect_plan_case_bodies(Pairs, [Pairs]).

metta_effect_plan_case_body_list([], []).
metta_effect_plan_case_body_list([[_, Body]|Pairs], [Body|Bodies]) :-
    !,
    metta_effect_plan_case_body_list(Pairs, Bodies).
metta_effect_plan_case_body_list([Malformed|Pairs], [Malformed|Bodies]) :-
    metta_effect_plan_case_body_list(Pairs, Bodies).

metta_effect_plan_binding_values(Bindings, [Bindings]) :-
    var(Bindings),
    !.
metta_effect_plan_binding_values(Bindings, Values) :-
    is_list(Bindings),
    !,
    metta_effect_plan_binding_value_list(Bindings, Values).
metta_effect_plan_binding_values(Bindings, [Bindings]).

metta_effect_plan_binding_value_list([], []).
metta_effect_plan_binding_value_list([[_, Value]|Bindings], [Value|Values]) :-
    !,
    metta_effect_plan_binding_value_list(Bindings, Values).
metta_effect_plan_binding_value_list([Malformed|Bindings],
                                     [Malformed|Values]) :-
    metta_effect_plan_binding_value_list(Bindings, Values).

%Ordinary calls use the same declared masks as translation. A position is
%walked if any applicable type branch evaluates it; only unanimous masking may
%hide a possible effect. A named typing refusal executes no operand. When no
%declaration decides, all arguments are evaluated, which is the translator's
%fallback and the conservative answer for an unfamiliar constructor.
metta_effect_plan_source_masked_arguments(Module, Head, Args, Evaluated) :-
    atom(Head),
    catch_recover(
        with_metta_module(
            Module,
            translator:builtin_argument_mask(Head, Args, Types, _)),
        fail),
    !,
    metta_effect_plan_arguments_by_types(Args, Types, Evaluated).
metta_effect_plan_source_masked_arguments(Module, Head, Args, Evaluated) :-
    atom(Head),
    catch_recover(
        with_metta_module(
            Module,
            ( translator:call_site_type_chains(Head, Chains),
              Chains \== [],
              length(Args, Arity),
              translator:fitting_type_chains(Chains, Arity, Selection) )),
        fail),
    !,
    metta_effect_plan_arguments_by_selection(Args, Selection, Evaluated).
metta_effect_plan_source_masked_arguments(_, _, Args, Args).

metta_effect_plan_arguments_by_types([], _, []).
metta_effect_plan_arguments_by_types([Arg|Args], [Type|Types], Evaluated) :-
    !,
    (   translator:non_evaluated_parameter_type(Type)
    ->  Evaluated = Rest
    ;   Evaluated = [Arg|Rest]
    ),
    metta_effect_plan_arguments_by_types(Args, Types, Rest).
metta_effect_plan_arguments_by_types(Args, [], Args).

metta_effect_plan_arguments_by_selection(_, refused(_, _), []) :-
    !.
metta_effect_plan_arguments_by_selection(Args, Selection, Evaluated) :-
    metta_effect_plan_arguments_by_selection_(
        Args, Selection, 1, Evaluated).

metta_effect_plan_arguments_by_selection_([], _, _, []).
metta_effect_plan_arguments_by_selection_([Arg|Args], Selection, Position,
                                          Evaluated) :-
    (   metta_effect_plan_position_evaluates(Selection, Position)
    ->  Evaluated = [Arg|Rest]
    ;   Evaluated = Rest
    ),
    Next is Position + 1,
    metta_effect_plan_arguments_by_selection_(Args, Selection, Next, Rest).

metta_effect_plan_position_evaluates(Selection, Position) :-
    member(Chain, Selection),
    (   Chain = [->|Types],
        append(Parameters, [_], Types),
        nth1(Position, Parameters, Type)
    ->  \+ translator:non_evaluated_parameter_type(Type)
    ;   true
    ),
    !.

metta_effect_plan_grounded(Name, Effects0, [Name-Effect|Effects0]) :-
    (   metta_operation_effect(Name, Declared)
    ->  Effect = Declared
    ;   Effect = oracleIO
    ).

metta_effect_plan_named_call(Module, Name, Arity,
                             Queue0-Effects0, Queue-Effects) :-
    functor(Head, Name, Arity),
    (   fun(Name),
        metta_ensure_compiled(Name),
        current_predicate(Module:Name/Arity),
        \+ predicate_property(Module:Head, imported_from(_))
    ->  Queue = [Name/Arity|Queue0],
        Effects = Effects0
    ;   metta_effect_plan_transparent(Name)
    ->  Queue = Queue0,
        Effects = Effects0
    ;   metta_operation_effect(Name, Effect)
    ->  Queue = Queue0,
        Effects = [Name-Effect|Effects0]
    ;   fun(Name),
        metta_ensure_compiled(Name),
        current_predicate(Module:Name/Arity)
    ->  Queue = [Name/Arity|Queue0],
        Effects = Effects0
    ;   metta_effect_inert(Name)
    ->  Queue = Queue0,
        Effects = Effects0
    ;   Queue = Queue0,
        Effects = [Name-oracleIO|Effects0]
    ).

%Compiler helpers whose source-facing operation has already been planned.
%They inspect terms or carry control; none observes a world independently.
metta_effect_plan_transparent(control_exception).
metta_effect_plan_transparent(metta_match_atoms).
metta_effect_plan_transparent(test_answer_value).
metta_effect_plan_transparent(throw).

metta_effect_plan_reduced(_, Template, Queue-Effects,
                          Queue-Next) :-
    var(Template),
    !,
    metta_effect_plan_dynamic(Effects, Next).
metta_effect_plan_reduced(_, Template, State, State) :-
    \+ Template = [_|_],
    !.
metta_effect_plan_reduced(Module, [Head|Args], Queue-Effects0,
                          Queue-Effects) :-
    length(Args, ArgCount),
    Arity is ArgCount + 1,
    (   atom(Head)
    ->  metta_effect_plan_named_call(Module, Head, Arity,
                                     Queue-Effects0, Queue-Effects)
    ;   var(Head)
    ->  metta_effect_plan_dynamic(Effects0, Effects)
    ;   Effects = Effects0
    ).

metta_effect_plan_masked_result(_, Template, Queue-Effects,
                                Queue-Next) :-
    var(Template),
    !,
    metta_effect_plan_dynamic(Effects, Next).
metta_effect_plan_masked_result(_, Template, State, State) :-
    \+ Template = [_|_],
    !.
metta_effect_plan_masked_result(Module, [Head|Args], State0, State) :-
    (   atom(Head),
        ( builtin_fun(Head) -> true ; fun(Head) )
    ->  length(Args, ArgCount),
        Arity is ArgCount + 1,
        metta_effect_plan_named_call(Module, Head, Arity, State0, State)
    ;   metta_effect_plan_masked_members([Head|Args], Module, State0, State)
    ).

metta_effect_plan_masked_members([], _, State, State).
metta_effect_plan_masked_members([Item|Rest], Module, State0, State) :-
    metta_effect_plan_masked_result(Module, Item, State0, Mid),
    metta_effect_plan_masked_members(Rest, Module, Mid, State).

metta_effect_plan_dynamic(Effects,
                          ['<dynamic-operation>'-oracleIO|Effects]).

metta_effect_plan_row(Name-Class, [Name, Class]).
metta_effect_plan_class(_-Class, Class).

%Coverage has the lattice identity as its declared default. Multiple ordinary
%rows compose safely, which keeps a programmatic declaration batch monotone
%even before a host replaces the older row.
metta_world_effect_coverage(Ctx, Coverage) :-
    findall(Declared,
            metta_contract_fact([covers, Ctx, Declared]),
            Declarations),
    maplist(spaces:metta_effect_class_canonical,
            Declarations, Canonical),
    metta_effect_compose(Canonical, Coverage).

metta_effect_covered(Required, Coverage) :-
    metta_effect_rank(Required, RequiredRank),
    metta_effect_rank(Coverage, CoverageRank),
    RequiredRank =< CoverageRank.

%A released space name starts a new declaration life. Removing the rows here
%prevents an anonymous pooled name, or a deliberately dropped public name,
%from inheriting the previous world's authority.
metta_forget_world_coverage(Ctx) :-
    findall([covers, Ctx, Declared],
            metta_contract_fact([covers, Ctx, Declared]),
            Rows),
    forall(member(Row, Rows), metta_remove_atom('&metta', Row, _)).

%One catalog lookup is the saga runner's only registry. The catalog checker
%admits at most one row and verifies both operation names before this read.
metta_compensation(Operation, Compensation) :-
    atom(Operation),
    metta_contract_fact([compensates, Operation, Compensation]),
    !.

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
%The cache's question is NARROWER than a reified world's. The native and
%semantic profiles above are a lower bound for admission, where an
%unclassified builtin must fail closed; they are not a licence for a cached
%result to hide a builtin's answer. Reading the full reflection here newly
%admitted every reviewed control form as cacheable, which cost lib_strategy's
%recursive traversals an order of magnitude [measured 2026-08-26: the
%phrasebook priced stratego-all at 3,935,850 engine inferences before the
%profile landed and 40,310,189 after, stratego-one 4,821,848 and 46,668,102,
%restored to 3,933,747 and 4,808,680 by this split, with every other strategy
%row inside 2%; command=python extensions/python/tools/phrasebook.py --cost with
%STRATEGY_INFERENCES raised so the runaway guard does not truncate the reading;
%fixture=this worktree with engine/reader.so; commit=173eeed021beb360b5e5f9f8461889e27190affc]. The profile
%still binds one way: a catalog row cannot talk a fixed non-structural builtin
%into the cache, which the base rule alone would have allowed [tested:
%effects_lattice:the_cache_purity_seam_reads_declarations_under_the_native_floor].
seam:pure_operation(Name) :-
    atom(Name),
    metta_declared_operation_effect(Name, pureStructural),
    \+ ( metta_fixed_operation_effect(Name, Fixed),
         Fixed \== pureStructural ).

%One contract atom, read from &metta's native storage. An expression
%[H|Args] is stored as '&metta'(H, Args...) in that space's storage module,
%the resolution the tabling walk documents; a space that has never been
%written has no storage module yet, and that absence reads as "not declared".
metta_contract_fact(Args) :-
    native_storage_module('&metta', Module),
    Goal =.. ['&metta'|Args],
    catch(call(Module:Goal), error(existence_error(procedure, _), _), fail).

%The deliberate override: (cache Name unchecked) in &metta says the CALLER
%accepts stale answers for this function. lib_tabling and lib_memo consult
%it before their purity walk; an explicit non-pureStructural declaration
%still refuses, because the author's NO outranks the caller's insistence.
metta_cache_unchecked(Name) :-
    metta_contract_fact([cache, Name, unchecked]).

%(annotations Ctx Algebra [Capabilities]) declares the value algebra a
%context's answer annotations live in; silence is the shipped bool algebra.
%Every algebra is an ordinary catalog row naming combine, extend, zero, one,
%checked laws, a finite checking carrier when one exists, and requirements.
%The old semiring names are shipped rows in that same table rather than cases
%in this predicate [tested:
%test_a_declared_semiring_quadruple_serves_annotations_like_a_builtin_one;
%commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c].
metta_annotations(Ctx, Algebra) :-
    (   metta_annotations_cache(Ctx, Cached)
    ->  Algebra = Cached
    ;   metta_annotations_fresh(Ctx, Algebra)
    ).

metta_annotations_fresh(Ctx, Algebra) :-
    findall(Declared, metta_contract_fact([annotations, Ctx, Declared]),
            PlainDeclarations),
    (   PlainDeclarations == []
    ->  findall(Declared,
                metta_contract_fact([annotations, Ctx, Declared, _]),
                Declarations)
    ;   Declarations = PlainDeclarations
    ),
    sort(Declarations, Distinct),
    metta_annotations_resolved(Distinct, Ctx, Resolved),
    assertz(metta_annotations_cache(Ctx, Resolved)),
    Algebra = Resolved.

metta_annotations_resolved([], _, bool) :- !.
metta_annotations_resolved([Algebra], _, Algebra) :- !.
metta_annotations_resolved([First, Second|Rest], Ctx, _) :-
    throw(error(metta_contract_conflict(Ctx, [annotations, Ctx, First],
                                        [annotations, Ctx, Second],
                                        [annotations, Ctx,
                                         [First, Second|Rest]]),
                none)).

%A per-ask carrier is dynamically scoped around the held engine goal. It is not
%a catalog mutation: nested evaluations inherit it, cleanup restores the
%previous value on failure, exception, exhaustion, or cursor destruction, and
%every persistent declaration remains unchanged for the next ask [tested:
%extensions/python/tests/ch06_many_answers/test_under_algebra.py;
%commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa].
:- meta_predicate metta_with_under(+, 0).

metta_with_under(Algebra, Goal) :-
    setup_call_cleanup(
        metta_under_push(Algebra, Previous),
        Goal,
        metta_under_pop(Previous)).

metta_under_push(Algebra, Previous) :-
    (   nb_current('$metta_under_algebras', Old)
    ->  Previous = some(Old)
    ;   Old = [], Previous = none
    ),
    nb_setval('$metta_under_algebras', [Algebra|Old]).

metta_under_pop(some(Previous)) :- !,
    nb_setval('$metta_under_algebras', Previous).
metta_under_pop(none) :-
    catch(nb_delete('$metta_under_algebras'), _, true).

metta_effective_algebra(_, Algebra) :-
    nb_current('$metta_under_algebras', [Algebra|_]), !.
metta_effective_algebra(Ctx, Algebra) :-
    metta_annotations(Ctx, Algebra).

metta_algebra_descriptor(Name, Combine, Extend, Zero, One, Laws,
                         Carrier, Requires) :-
    (   metta_algebra_descriptor_cache(Name, CachedCombine, CachedExtend,
                                       CachedZero, CachedOne, CachedLaws,
                                       CachedCarrier, CachedRequires)
    ->  Combine = CachedCombine,
        Extend = CachedExtend,
        Zero = CachedZero,
        One = CachedOne,
        Laws = CachedLaws,
        Carrier = CachedCarrier,
        Requires = CachedRequires
    ;   metta_algebra_descriptor_fresh(Name, Combine, Extend, Zero, One,
                                       Laws, Carrier, Requires)
    ).

metta_algebra_descriptor_fresh(Name, Combine, Extend, Zero, One, Laws,
                               Carrier, Requires) :-
    metta_contract_fact([algebra, Name, Combine, Extend, Zero, One,
                         Laws, Carrier, Requires]),
    assertz(metta_algebra_descriptor_cache(Name, Combine, Extend, Zero, One,
                                           Laws, Carrier, Requires)).

metta_algebra_one(Ctx, One) :-
    metta_effective_algebra(Ctx, Algebra),
    metta_algebra_descriptor(Algebra, _, _, _, One, _, _, _).

metta_algebra_law(Algebra, Law) :-
    metta_algebra_descriptor(Algebra, _, _, _, _, [laws|Laws], _, _),
    memberchk(Law, Laws).

%Whether the declared semiring carries an order is a CLAIM in the catalog,
%(claim semiring ranked ordered) and its prob sibling shipped as presets,
%so a third-party semiring value declared ordered serves (top k ...) with
%no engine edit, the same way Oracle's RELY constraint state is a declared
%per-constraint fact its optimizer acts on.
metta_annotations_ordered(Ctx) :-
    metta_effective_algebra(Ctx, Semiring),
    metta_vocabulary_claim(semiring, Semiring, ordered).

metta_algebra_order(Algebra, ascending) :-
    metta_vocabulary_claim(semiring, Algebra, ascending), !.
metta_algebra_order(_, descending).

metta_annotations_order(Ctx, Direction) :-
    metta_effective_algebra(Ctx, Algebra),
    metta_vocabulary_claim(semiring, Algebra, ordered),
    metta_algebra_order(Algebra, Direction).

%A declared per-value fact: (claim Vocab Value Property...) rows carry any
%number of properties, and a consumer asks for one.
metta_vocabulary_claim(Vocab, Value, Property) :-
    metta_catalog_row([claim, Vocab, Value|Properties]),
    memberchk(Property, Properties),
    !.

%(source Ctx Kind) declares a context's consumption discipline: repeated
%(the default, re-enumerable), linear (consume once; a second physical
%touch is a loud error, not a silent empty answer), and peek (reads do
%not consume, the provider's promise the conformance kit checks). The
%consumed mark is a prolog FLAG, process-global and transaction-immune,
%because a rolled-back transaction does not un-drain a generator.
metta_source(Ctx, Kind) :-
    (   metta_contract_fact([source, Ctx, Declared])
    ->  Kind = Declared
    ;   Kind = repeated
    ).

metta_source_guard(Space) :-
    \+ metta_ctx_declared(Space),
    !.
metta_source_guard(Space) :-
    (   metta_contract_storage(Module),
        Module:'&metta'(source, Space, linear)
    ->  metta_space_flag_key('$metta_consumed:', Space, Key),
        (   current_prolog_flag(Key, consumed)
        ->  throw(error(metta_source_discipline(Space, linear), none))
        ;   create_prolog_flag(Key, consumed, [keep(false)])
        )
    ;   true
    ).

metta_source_reset(Space) :-
    metta_space_flag_key('$metta_consumed:', Space, Key),
    (   current_prolog_flag(Key, _)
    ->  set_prolog_flag(Key, fresh)
    ;   true
    ).

metta_space_flag_key(Prefix, Space, Key) :-
    atom(Space), !,
    atom_concat(Prefix, Space, Key).
metta_space_flag_key(Prefix, Space, Key) :-
    space_canonical_atom(Space, Encoded),
    atom_concat(Prefix, Encoded, Key).

:- multifile prolog:error_message//1.
prolog:error_message(metta_source_discipline(Ctx, linear)) -->
    [ '~w declares (source ~w linear) and this is its second \c
       consumption: the first drained it, so answering would be a silent \c
       empty set, exactly the wrong answer the declaration exists to \c
       refuse. Re-register the provider for a fresh source, or declare \c
       repeated for one that re-enumerates'-[Ctx, Ctx] ].

%The last answer's annotation, first-class: rides '$metta_answer_k'
%backtrackably. Outside an answer it reads the current context's DECLARED one,
%not a numeric engine constant.
metta_annotation(K) :-
    (   catch(b_getval('$metta_answer_k', K0), _, fail)
    ->  K = K0
    ;   current_metta_space(Ctx),
        metta_algebra_one(Ctx, K)
    ).

metta_annotation(Ctx, K) :-
    (   catch(b_getval('$metta_answer_k', K0), _, fail)
    ->  K = K0
    ;   metta_algebra_one(Ctx, K)
    ).

%Extend two annotations along a conjunction by the operation in the catalog.
%Numeric +/*/min/max use their already-typed engine primitives directly; an
%arbitrary declared operation goes through ordinary evaluation, so a grounded
%tensor operation registered from Python is not a separate engine case.
metta_k_extend(Ctx, K1, K2, K) :-
    metta_effective_algebra(Ctx, Algebra),
    metta_algebra_descriptor(Algebra, _, Extend, _, One, _, _, _),
    (   K1 == One -> K = K2
    ;   K2 == One -> K = K1
    ;   metta_apply_algebra_operation(Algebra, Extend, K1, K2, K)
    ).

metta_apply_algebra_operation(_, '*', A, B, R) :-
    number(A), number(B), !,
    R is A * B.
metta_apply_algebra_operation(_, '+', A, B, R) :-
    number(A), number(B), !,
    R is A + B.
metta_apply_algebra_operation(_, min, A, B, R) :-
    number(A), number(B), !,
    R is min(A, B).
metta_apply_algebra_operation(_, max, A, B, R) :-
    number(A), number(B), !,
    R is max(A, B).
metta_apply_algebra_operation(Algebra, Operation, A, B, R) :-
    (   once(eval([Operation, A, B], R0))
    ->  R = R0
    ;   throw(error(metta_algebra_operation_failed(Algebra, Operation, A, B),
                    none))
    ).

prolog:error_message(metta_algebra_requirement_missing(Ctx, Algebra,
                                                        Requirement)) -->
    [ 'algebra_requirement_missing: ~w declares algebra ~w, which requires \c
       capability ~w'-[Ctx, Algebra, Requirement] ].
prolog:error_message(metta_amplitude_fragment_refused(Ctx, Requirement)) -->
    [ 'amplitude_fragment_refused: ~w lacks required finite-fragment \c
       capability ~w'-[Ctx, Requirement] ].
prolog:error_message(metta_algebra_operation_failed(Algebra, Operation, A, B)) -->
    [ 'declared algebra ~w operation ~w answered nothing for (~w, ~w)'-
      [Algebra, Operation, A, B] ].
prolog:error_message(metta_algebra_law_unknown(Algebra, Law)) -->
    [ 'algebra_law_unknown: ~w names unsupported law ~w'-[Algebra, Law] ].
prolog:error_message(metta_algebra_law_uncheckable(Algebra, Laws, Reason)) -->
    [ 'algebra_law_uncheckable: ~w names ~w but provides no ~w'-
      [Algebra, Laws, Reason] ].
prolog:error_message(metta_algebra_carrier_not_closed(Algebra, Operation,
                                                       A, B, Result)) -->
    [ 'algebra_carrier_not_closed: ~w operation ~w maps (~w, ~w) to ~w'-
      [Algebra, Operation, A, B, Result] ].
prolog:error_message(metta_algebra_law_violation(Algebra, Law, Inputs,
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
metta_explain([match, Space, Pattern, _Template], Out) :-
    metta_space_name(Space), !,
    findall(Item, metta_explain_match_item(Space, Pattern, Item), Out).
metta_explain([Op|Args], Out) :-
    atom(Op), !,
    findall(Item, metta_explain_op_item(Op, Args, Item), Out).
metta_explain(Query, _) :-
    throw(error(type_error(explainable, Query),
                context(explain/1,
                        'explain covers (match <space> <pattern> <out>) \c
                         forms and operation calls'))).

metta_explain_match_item(Space, Pattern, [handles|Route]) :-
    (   catch(metta_handles_route(Space, Pattern, Entry, Fidelity, Det),
              _, fail)
    ->  Route = [Entry, Fidelity, Det]
    ;   Route = [none]
    ).
metta_explain_match_item(Space, Pattern, [pushes, Pushes]) :-
    (   nonvar(Space), seam:foreign_space(Space),
        catch(foreign_pushdown_class(Space, Pattern, exact), _, fail)
    ->  Pushes = 'True'
    ;   Pushes = 'False'
    ).
metta_explain_match_item(Space, _, [source, Kind]) :-
    metta_source(Space, Kind).
metta_explain_match_item(Space, _, [context, World]) :-
    metta_context_world(Space, World).
metta_explain_match_item(Space, _, [annotations, Semiring]) :-
    metta_annotations(Space, Semiring).
metta_explain_match_item(Space, _, [emits, Policy]) :-
    (   metta_emits(Space, Declared) -> Policy = Declared ; Policy = none ).
metta_explain_match_item(Space, _, [events, Delivery, Order]) :-
    (   metta_event_capability(Space, Fidelity, Ordering)
    ->  Delivery = Fidelity, Order = Ordering
    ;   Delivery = none, Order = none
    ).
metta_explain_match_item(Space, _, [writes, Atomicity]) :-
    metta_writes(Space, Atomicity).
metta_explain_match_item(Space, Pattern, ['on-error', Mode]) :-
    (   catch(metta_on_error_mode(Space, Pattern, Declared), _, fail)
    ->  Mode = Declared
    ;   Mode = abort
    ).
metta_explain_match_item(_, Pattern, [merge, Policy]) :-
    (   catch(metta_merge_route(Pattern, Declared), _, fail)
    ->  Policy = Declared
    ;   Policy = depth
    ).

metta_explain_op_item(Op, _, [op, Op, Arity, Kind]) :-
    metta_contract_fact([op, Op, Arity, Kind]).
metta_explain_op_item(Op, _, [effect, Effect]) :-
    (   metta_operation_effect(Op, Declared)
    ->  Effect = Declared
    ;   Effect = none
    ).
metta_explain_op_item(Op, _, [inverse, Inverse]) :-
    (   metta_contract_fact([inverse, Op]) -> Inverse = 'True'
    ;   Inverse = 'False' ).
metta_explain_op_item(Op, _, [annotations, Semiring]) :-
    metta_annotations(Op, Semiring).
metta_explain_op_item(Op, Args, ['on-error', Mode]) :-
    (   catch(metta_on_error_mode(Op, [Op|Args], Declared), _, fail)
    ->  Mode = Declared
    ;   Mode = abort
    ).
metta_explain_op_item(Op, _, [cache, Choice, Reason]) :-
    seam:automatic_cache_explanation(Op, Choice, Reason).
metta_explain_op_item(Op, _, [deprecated, Since, Remedy]) :-
    metta_deprecation(Op, Since, Remedy).

%One declaration over one callable name. Keeping the values as terms is the
%point: a version can be a symbol or grounded text, and the remedy can be a
%call-shaped atom that both explain and a host warning render without a second
%stringly registry.
metta_deprecation(Name, Since, Remedy) :-
    metta_contract_fact([deprecated, Name, Since, Remedy]), !.

%(context Ctx closed-world|open-world) records what a context's absence
%means. The mechanically checkable part gates: negation as failure reads
%absence as falsity, which is sound only over a world the answerer
%actually holds whole, so a negated goal may consult a foreign context
%only when it declares closed-world. A native space IS the engine's own
%database and closed by construction; an undeclared foreign one refuses
%under negation loudly, because silently reading an open world's silence
%as falsity was the wrong answer.
metta_context_world(Ctx, World) :-
    (   metta_contract_fact([context, Ctx, Declared])
    ->  World = Declared
    ;   World = undeclared
    ).

metta_in_negation :-
    catch(b_getval('$metta_in_negation', true), _, fail).

metta_negation_world_guard(Space) :-
    (   metta_in_negation
    ->  (   metta_context_world(Space, 'closed-world')
        ->  true
        ;   throw(error(metta_negation_open_world(Space), none))
        )
    ;   true
    ).

:- multifile prolog:error_message//1.
prolog:error_message(metta_negation_open_world(Ctx)) -->
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
%only when metta_install_bridges/0 runs (the declaration sugar calls it),
%so an engine without bridges keeps the direct write path and its
%measured cost. A cascade is bounded: depth 32 throws naming the chain,
%because an unbounded insert loop is a bug, not a fixpoint.
metta_install_bridges :-
    (   metta_bridges_installed
    ->  true
    ;   assertz(metta_bridges_installed),
        assertz(( seam:atom_added(Space, Term) :-
                      metta_bridge_fire(Space, Term) )),
        seam:enable_atom_hook(added)
    ).

:- dynamic metta_bridges_installed/0.

%%%% The agenda: which reaction fires first (P12.17) %%%%
%
%Several reactions can match one write, and before this nothing in the tree
%said which went first, so the answer was assertion order by accident. It is
%a DECLARED policy now, (agenda <ctx> <policy> [<function>]) in '&metta',
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
metta_reaction(Space, Pattern, Op, Priority) :-
    (   metta_contract_fact([on, Space, Pattern, Op, Priority])
    ;   metta_contract_fact([on, Space, Pattern, Op]),
        Priority = 0
    ).

metta_agenda(Ctx, Policy, Chooser) :-
    (   metta_contract_fact([agenda, Ctx, Declared, Named])
    ->  Policy = Declared, Chooser = Named
    ;   metta_contract_fact([agenda, Ctx, Declared])
    ->  Policy = Declared, Chooser = none
    ;   metta_agenda_default(Policy, Chooser)
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
metta_agenda_default(declaration, none).

prolog:error_message(metta_agenda_unscored(Ctx, Chooser, Entry)) -->
    [ '~w declares (agenda ~w user ~w) and ~w answered no number for ~q. A \c
       user agenda policy scores every reaction it is asked about, because a \c
       reaction with no score has no place in the order and dropping it \c
       would be a rule that silently never fires'-[Ctx, Ctx, Chooser,
                                                    Chooser, Entry] ].

metta_bridge_fire(Space, Term) :-
    findall(Pattern-Op-Priority,
            metta_reaction(Space, Pattern, Op, Priority),
            Declared),
    (   Declared = [_, _|_]
    ->  metta_agenda(Space, Policy, Chooser),
        metta_agenda_order(Policy, Chooser, Space, Declared, Ordered)
    ;   Ordered = Declared
    ),
    forall(member(P-O-_, Ordered), metta_bridge_apply(P, Term, O)).

%One reaction is already in order, and so is a conflict set under the
%default, so neither pays for the sort.
metta_agenda_order(declaration, _, _, Reactions, Reactions) :- !.
metta_agenda_order(recency, _, _, Reactions, Ordered) :- !,
    reverse(Reactions, Ordered).
metta_agenda_order(specificity, _, _, Reactions, Ordered) :- !,
    metta_agenda_keyed(metta_pattern_specificity, Reactions, Keyed),
    metta_agenda_sorted(Keyed, Ordered).
metta_agenda_order(priority, _, _, Reactions, Ordered) :- !,
    findall(Priority-Reaction,
            ( member(Reaction, Reactions), Reaction = _-_-Priority ),
            Keyed),
    metta_agenda_sorted(Keyed, Ordered).
metta_agenda_order(user, Chooser, Space, Reactions, Ordered) :-
    metta_agenda_user_keyed(Chooser, Space, Reactions, Keyed),
    metta_agenda_sorted(Keyed, Ordered).

%sort/4 with @>= keeps duplicates AND their relative order, so equal keys
%stay in declaration order without a second sort key
%[source: SWI-Prolog manual, sort/4].
metta_agenda_sorted(Keyed, Ordered) :-
    sort(1, @>=, Keyed, Sorted),
    findall(Reaction, member(_-Reaction, Sorted), Ordered).

metta_agenda_keyed(_, [], []).
metta_agenda_keyed(Measure, [Reaction|Rest], [Key-Reaction|Keyed]) :-
    Reaction = Pattern-_-_,
    call(Measure, Pattern, Key),
    metta_agenda_keyed(Measure, Rest, Keyed).

%How specific a pattern is: OPS5 counts the tests in the left-hand side, and
%a MeTTa pattern's tests are its non-variable positions, so (alert kitchen)
%outranks (alert $where) and both outrank $anything.
metta_pattern_specificity(Pattern, 0) :- var(Pattern), !.
metta_pattern_specificity(Pattern, N) :-
    is_list(Pattern),
    !,
    metta_specificity_of(Pattern, 1, N).
metta_pattern_specificity(_, 1).

metta_specificity_of([], N, N).
metta_specificity_of([Item|Rest], Acc, N) :-
    metta_pattern_specificity(Item, Count),
    Next is Acc + Count,
    metta_specificity_of(Rest, Next, N).

%A user policy SCORES each reaction rather than reordering the list, and
%that is the safer half of the same freedom: a function that returns a
%permutation can drop a reaction, and a rule that silently never fires is
%the failure this whole item exists to remove. Scoring cannot. It is also
%what CHR-rp's dynamic priorities are, an expression evaluated per rule
%instance rather than a constant. The function is called once per reaction
%per firing write, and the call goes through the ordinary translation cache,
%so an opt-in policy costs nothing until it is declared.
metta_agenda_user_keyed(none, Space, _, _) :-
    throw(error(metta_agenda_unscored(Space, none, none), none)).
metta_agenda_user_keyed(Chooser, Space, Reactions, Keyed) :-
    Chooser \== none,
    metta_agenda_user_keys(Reactions, Chooser, Space, Keyed).

metta_agenda_user_keys([], _, _, []).
metta_agenda_user_keys([Reaction|Rest], Chooser, Space,
                       [Key-Reaction|Keyed]) :-
    Reaction = Pattern-Op-Priority,
    Entry = [on, Space, Pattern, Op, Priority],
    (   metta_agenda_score(Chooser, Entry, Key)
    ->  true
    ;   throw(error(metta_agenda_unscored(Space, Chooser, Entry), none))
    ),
    metta_agenda_user_keys(Rest, Chooser, Space, Keyed).

metta_agenda_score(Chooser, Entry, Key) :-
    space_module('&self', Module),
    with_metta_module(Module,
                      ( translate_cached_expr([Chooser, Entry], Goals, Out),
                        call_goals_in_(Module, Goals) )),
    number(Out),
    Key = Out.

metta_bridge_apply(Pattern, Term, Op) :-
    (   Pattern = Term
    ->  metta_bridge_descend(Op)
    ;   true
    ).

metta_bridge_descend(Op) :-
    (   catch(b_getval('$metta_bridge_depth', Depth0), _, fail)
    ->  true
    ;   Depth0 = 0
    ),
    Depth is Depth0 + 1,
    (   Depth > 32
    ->  throw(error(metta_bridge_cascade(Op), none))
    ;   setup_call_cleanup(
            b_setval('$metta_bridge_depth', Depth),
            metta_bridge_op(Op),
            b_setval('$metta_bridge_depth', Depth0))
    ).

metta_bridge_op([insert, Target, Template]) :- !,
    metta_add_atom(Target, Template, _).
metta_bridge_op([retract, Target, Template]) :- !,
    metta_remove_atom(Target, Template, _).
metta_bridge_op([revise, Target, Old, New]) :- !,
    metta_remove_atom(Target, Old, _),
    metta_add_atom(Target, New, _).
metta_bridge_op(Op) :-
    throw(error(metta_bridge_unknown_op(Op), none)).
