% Purpose: validate foreign-provider capabilities and route foreign and native space operations
% Assumes: engine/spaces.pl includes this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/spaces.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE]

%%%% The foreign seam's failure contract %%%%
%
%A declared provider that does not answer an operation is the registrant's
%bug, and it is reported with the space and the operation named. It is never
%read as "there is nothing there". Four of the five operations used to fail
%silently: a write vanished, a removal reported nothing removed, and a match
%answered the empty set while the space demonstrably held matching atoms.
%Only clear said what happened, and it said it from the Python bridge.
%
%The Python half of the same seam has always done this, refusing with the
%provider class and the operation named, and it is the half a library author
%is told to port INTO Prolog for speed
%[tested: spaces_foreign_contract].
%A space that declares NOTHING provides everything, which is what every
%provider written before the declaration existed assumed.
%
%THE TRAP, and it is worth knowing before you extend the vocabulary: the
%default stops the moment this space has ANY solution. Declaring one
%capability is declaring the complete set, so a provider adding a sixth to the
%five silently loses the five it did not restate. Python providers do not have
%to think about it, because foreign.py projects the whole set at registration
%from the protocols the provider implements
%[tested: test_a_python_providers_capabilities_reach_the_engine,
%a_partial_declaration_declares_the_whole_set].
%subscribe is the one capability no registration may claim on its own, and
%that is P12.14's whole point: the other eight are questions about what a
%provider implements, and this one is a promise about what its CONTEXT can
%deliver. A remote space implements add and remove and its contents still
%change on the server. So the (events ...) declaration decides it, whatever
%a host registered, and a context that declares nothing is refused here
%[tested: test_a_context_that_declares_events_serves_them_and_one_that_does_not_refuses].
foreign_provides(Space, Capability) :-
    (   seam:foreign_capability(Space, _)
    ->  seam:foreign_capability(Space, Capability)
    ;   true
    ),
    (   Capability == subscribe
    ->  petta_event_capability(Space, _, _)
    ;   true
    ).

%A capability the space does not provide. The provider gets to say why, if it
%has words for it: seam:foreign_refuse/2 raises, and "does not implement add"
%reads differently from "declines this add request", which is a distinction the
%Python half already draws and this one could not.
%
%The hook is expected to throw. Reaching the throw below means it did not,
%which is the engine and the provider disagreeing about what is provided.
refuse_absent_capability(Space, Capability) :-
    (   foreign_provides(Space, Capability)
    ->  true
    ;   seam:foreign_refuse(Space, Capability)
    ->  throw(error(permission_error(Capability, foreign_space, Space),
                    context(foreign_write/3,
                            'the provider declined this operation and did not \c
                             say why')))
    ;   throw(error(permission_error(Capability, foreign_space, Space),
                    context(foreign_write/3,
                            'the provider does not declare this operation')))
    ).

%A write either happened or it did not, so failure here is unambiguous and is
%an error. A read that finds nothing is an ordinary empty answer, so reads do
%not go through this.
:- meta_predicate foreign_write(+, +, 0).
foreign_write(Space, Capability, Goal) :-
    refuse_absent_capability(Space, Capability),
    %Inside a transaction the write's fate follows the declared
    %atomicity: a transactional provider enlists (one begin per
    %outermost transaction) and is committed or rolled back with it,
    %best-effort is the author's declared acceptance of a write that
    %survives a rollback, and anything else is refused loudly, because
    %a foreign write silently surviving a rolled-back transaction was
    %the wrong answer this replaces.
    (   current_transaction(_),
        petta_in_user_transaction
    ->  petta_writes(Space, Atomicity),
        (   Atomicity == transactional
        ->  petta_enlist_foreign(Space)
        ;   Atomicity == 'best-effort'
        ->  true
        ;   throw(error(petta_transaction_unsupported(Space, Atomicity),
                        none))
        )
    ;   true
    ),
    (   call(Goal)
    ->  true
    ;   throw(error(petta_foreign_operation_failed(Space, Capability),
                    context(foreign_write/3,
                            'the provider refused the write without saying why')))
    ).

%A batch is a TRANSPORT optimisation and never a semantic one: what the engine
%does for an atom on its own it must still do when the atoms arrive together.
%So only atoms that store and nothing more take a bulk crossing, and
%atom_stores_only/1 decides that rather than this predicate re-deriving it,
%which is how a batched type declaration came to skip its recompile.
%[prior art: a multi-row SQL INSERT still fires per-row triggers, JDBC's
%executeBatch runs the same statements, and Redis pipelining changes round
%trips and never commands.]
metta_add_atoms(_, []) :- !.
metta_add_atoms(Space, Terms) :-
    %A claimed hook gates the write itself, so a hooked space takes the
    %per-atom door below, where the wrapper consults the handler for every
    %atom; a pool's admission guard is one such claim, which is how a
    %batch beyond capacity meets the refusal its atoms meet arriving
    %alone. Both one-crossing clauses write behind the wrapper's back, the
    %foreign one through the provider's own bulk door and the native one
    %through add_sexp_in/4
    %[tested: a_batch_into_a_hooked_space_consults_the_handler_per_atom,
    %a_batch_beyond_capacity_is_refused_like_lone_adds].
    petta_hook_claim_idle(Space),
    atoms_store_only(Space, Terms),
    add_atoms_in_one_crossing(Space, Terms), !.
metta_add_atoms(Space, Terms) :-
    %This route may perform work for its first atom, so check the whole batch
    %before invoking any per-atom door. A duplicate later in the batch must not
    %leave the first declaration, compiled equation, or observer effect behind.
    batch_declarations_unique(Space, Terms),
    forall(member(Term, Terms), 'add-atom'(Space, Term, _)).

%A provider's own batch crossing when it has one, and the native store's
%otherwise. A provider without seam:foreign_add_many/2 fails here and gets one
%seam:foreign_add/2 per atom, which is what every provider written before this
%gets. The native path writes behind the write wrapper's back, so it is
%available only while no observer is installed; a provider's own crossing owns
%the write hooks exactly as its per-atom add does.
add_atoms_in_one_crossing(Space, Terms) :-
    seam:foreign_space(Space), !,
    refuse_absent_capability(Space, add),
    seam:foreign_add_many(Space, Terms).
add_atoms_in_one_crossing(Space, Terms) :-
    metta_add_hooks_idle(Space),
    ensure_native_storage_module(Space, Storage),
    %The bulk door checks and notes contract subjects exactly as the
    %per-atom door does, once per batch head test rather than per space
    %test per atom; the whole batch is checked before any of it lands.
    (   Space == '&petta'
    ->  forall(member(Decl, Terms),
               (   petta_declaration_check(Decl),
                   petta_note_ctx_declared(Decl)
               ))
    ;   true
    ),
    forall(member(Term, Terms),
           ( add_sexp_in(Storage, Space, Term, Ref),
             record_source_assertion(Ref) )),
    (   Space == '&petta'
    ->  forall(member(Term, Terms), petta_catalog_note_added(Term))
    ;   true
    ).

%Compile and register a dynamic equation as one database transaction. A
%translation or change-hook error therefore leaves no stored atom, function
%marker, arity, meta-clause, or executable clause behind.
%The one equation-compile spine: prelude eviction (user-wins), function
%registration, translation, clause assertion, provenance records, and the
%COMPLETE change notification. Three doors used to carry this separately,
%this file's add_function_atom and filereader.pl's two process_form
%clauses, so a cross-cutting rule had to be hooked one door at a time
%(the prelude eviction was the precedent), and one rule HAD drifted: the
%loader doors notified seam:function_changed but never
%invalidate_specializations, so an equation added by a string run or a
%compile-mode load left a prior specialization of the same name
%answering stale clauses. One door means the next such rule lands once
%[tested specializer:string_run_equation_invalidates_specializations].
compile_metta_equation(Module, Term, Clause, Ref) :-
    Term = [=, [F|_], _],
    (   metta_self_module(Module) -> evict_prelude_definition(F) ; true ),
    register_fun_in(Module, F),
    %Stale specializations go FIRST, before this body compiles. They are
    %clones of the PREVIOUS definition, and that is the whole content of
    %the claim; a clone this compilation creates for its own recursive
    %call belongs to the NEW definition and must survive. Invalidating
    %afterwards abolished exactly those clones while the clause naming
    %them stood, so (= (f $g) (... (f (+ 2)) ...)) compiled a generic
    %clause calling an empty predicate: the direct call answered through
    %its own specialization and a call that reached the generic clause,
    %(let $h (+ 1) (f $h)), silently answered NOTHING. Found by the
    %verify-specializations differential over examples/
    %[tested specializer:a_recursive_specialization_survives_its_compile].
    prepare_specialization_invalidation(Module, F),
    support_invalidate_function_change(Module, F),
    once(with_metta_module(Module, translate_clause(Term, RawClause))),
    petta_instrument_recursive_clause(Term, RawClause, Clause),
    assert_function_clause(Module, Clause, Ref),
    record_source_assertion(Ref),
    record_translated_from(Ref, Term, SourceRef),
    record_source_assertion(SourceRef),
    %The dependent-recompile hooks run AFTER the clause is in place, so
    %a definition that mentions F recompiles against the new one.
    forall(support_repair_invalidations, true),
    forall(seam:function_changed(F), true),
    announce_function_call_graph_changed(Module, F).

%A recursive equation spends the same branch-local budget that runnable
%limits own. The source tree supplies the cost because it is the stable unit:
%one fuel unit covers two reduction nodes, rounded up. That calibration is
%the LeaTTa runner's two exact boundary witnesses: factorial's three-node body
%costs two and stops at -3 under 20, while fuel-loop's five-node body costs
%three and stops at -33332 under the default 100000. A quote is data and
%contributes neither a recursive call nor a reduction node. A compiled input
%that is the translator's internal `quote` sentinel is likewise not a source
%argument; its higher-order specialization owns the runnable call, so the
%generic dispatch artifact is not charged as another recursive branch.
%[tested: test_a_stack_depth_pragma_bounds_evaluation_instead_of_overflowing].
petta_instrument_recursive_clause([=, [F|HeadArguments], Body],
                                  (Head :- Goal),
                                  (Head :- Charge, Goal)) :-
    length(HeadArguments, Arity),
    petta_source_calls_head(Body, F, Arity),
    \+ petta_source_has_variable_head(Body),
    Head =.. [_|Arguments],
    append(Inputs, [_Output], Arguments),
    \+ ( member(Input, Inputs), nonvar(Input), Input == quote ),
    !,
    petta_fuel_culprit(F, Inputs, Culprit),
    petta_source_reduction_count(Body, Nodes),
    Cost is max(1, (Nodes + 1) // 2),
    %Built rather than called: the charge is written into this clause, which is
    %a third of what it cost as a shared call, and the cost lands as a literal
    %because it is settled here.
    petta_fuel_step_goal(Culprit, Cost, Charge).
petta_instrument_recursive_clause(_, Clause, Clause).

petta_fuel_culprit(_, [Only], Only) :- !.
petta_fuel_culprit(F, Inputs, [F|Inputs]).

petta_source_calls_head([quote, _], _, _) :- !, fail.
petta_source_calls_head([Head|Arguments], F, Arity) :-
    (   nonvar(Head), Head == F, length(Arguments, Arity)
    ->  true
    ;   member(Argument, Arguments),
        petta_source_calls_head(Argument, F, Arity)
    ).

petta_source_has_variable_head(Term) :-
    nonvar(Term),
    Term = [Head|Arguments],
    (   var(Head)
    ->  true
    ;   member(Argument, Arguments),
        petta_source_has_variable_head(Argument)
    ).

petta_source_reduction_count(Term, 0) :- var(Term), !.
petta_source_reduction_count([quote, _], 0) :- !.
petta_source_reduction_count([_|Arguments], Count) :- !,
    maplist(petta_source_reduction_count, Arguments, Counts),
    sum_list(Counts, Nested),
    Count is Nested + 1.
petta_source_reduction_count(_, 0).

add_function_atom(Storage, Space, Module, Term, FAtom, W) :-
    store_equation(Storage, Space, Term),
    length(W, N),
    Arity is N + 1,
    register_arity(FAtom, Arity),
    compile_metta_equation(Module, Term, Clause, _Ref),
    maybe_print_compiled_clause("added function", Term, Clause).

%What is left to refuse, now that every space compiles into a module of its
%own: SWI's PROTECTED CORE. Defining a builtin's name in a space is an
%ordinary local shadow and is accepted; SWI still refuses `assertz` outright
%for a small set of system predicates, with a permission error naming
%assertz/2, the Prolog arity and the absolute path of a source file, none of
%which is language the program that wrote the equation can act on. Say it in
%MeTTa's terms instead, and say that this set is the same in every space
%rather than pointing at a named one, which is no longer the difference
%[measured 2026-08-19: of the 428 names imported into `user`, 7 at MeTTa arity
%0, 4 at arity 1, 2 at arity 2 and 1 at arity 3 are refused in a space's
%module, against 86, 217, 163 and 64 in the engine's]
%[tested: spaces_builtin_override].
:- multifile prolog:error_message//1.

assert_function_clause(Module, Clause, Ref) :-
    catch(assertz(Module:Clause, Ref),
          error(permission_error(modify, static_procedure, _), _),
          throw_builtin_redefinition(Module, Clause)).

%Two refusals, because SWI raises the same permission error for two different
%reasons and only one of them is about Prolog. A name the ENGINE emits into
%compiled bodies is bound into every space's module on purpose
%(protect_engine_emitted/1 above), and telling its author that it is one of
%Prolog's core predicates would send them looking in the wrong place.
throw_builtin_redefinition(Module, Clause) :-
    ( Clause = (Head :- _) -> true ; Head = Clause ),
    functor(Head, Name, Arity),
    InputArity is Arity - 1,
    metta_module_space(Module, Space),
    (   seam:engine_emitted(Name/Arity)
    ->  throw(error(petta_engine_goal_redefinition(Name, InputArity, Space),
                    context('=', 'the engine compiles this name into function \c
                                  bodies')))
    ;   throw(error(petta_builtin_redefinition(Name, InputArity, Space),
                    context('=', 'a builtin cannot be redefined in this space')))
    ).

%The refusal that reads worst when it is unrendered, because the term names a
%capability nobody has heard of and the whole point of the refusal is to teach
%it. `rules` is a promise about what a space HOLDS rather than about which
%methods a provider has, so no protocol can derive it and the message has to
%say how to opt in [tested: test_a_space_without_rules_says_how_to_hold_one].
prolog:error_message(petta_foreign_space_holds_no_rules(Space, Term)) -->
    { swrite(Term, TermText) },
    [ '~w does not hold rules, so ~w was refused rather than stored where it \c
       could never fire'-[Space, TermText], nl,
      '  a foreign space holds DATA unless it says otherwise; declare the \c
       rules capability on the provider to hold a program' ].

prolog:error_message(petta_foreign_operation_failed(Space, Capability)) -->
    [ 'the provider for ~w did not complete the ~w operation and gave no \c
       reason. A provider that cannot serve a request should raise, so the \c
       program can see why.'-[Space, Capability] ].
prolog:error_message(petta_foreign_plan_is_not_a_partition(Space, Patterns,
                                                          Claimed, Rest)) -->
    [ '~w claimed ~w and left ~w of the conjunction ~w, which do not partition \c
       it. A claim may take any subset and leave the rest, and may not drop a \c
       conjunct: the engine plans only what you leave, so a dropped pattern \c
       stops constraining the query and the join answers rows that were never \c
       asked for.'-[Space, Claimed, Rest, Patterns] ].
prolog:error_message(petta_engine_goal_redefinition(Name, Arity, Space)) -->
    [ '~w with ~w arguments is a name the engine itself compiles into function \c
       bodies, so no space can redefine it, ~w included.'-[Name, Arity, Space], nl,
      '  an equation for it would capture the engine\'s own goal in this \c
       space\'s compiled clauses rather than shadowing a function: rename it, \c
       or write the behaviour you want as a wrapper around it' ].
prolog:error_message(petta_builtin_redefinition(Name, Arity, Space)) -->
    [ '~w with ~w arguments is one of Prolog\'s protected core predicates, \c
       which no space can redefine, ~w included.'-[Name, Arity, Space], nl,
      '  every other builtin name is free: an equation for one compiles into \c
       this space\'s own module and shadows it there, leaving the engine\'s \c
       and every other space\'s alone' ].

%Unit for a removal that happened, an error for one that found nothing.
%
%The language's own text is what asks for this rather than what forbids it:
%"if the given atom is not in the space, remove-atom currently neither raises a
%error nor returns the empty result" is a COMPLAINT, and upstream carries the
%same question as a TODO it has not answered, `stdlib/space.rs:219`, "Is it
%necessary to distinguish whether the atom was removed or not?". The arbiter
%answers it: LeaTTa's Hyperon-Hacks-Register row 15 rules "Implement. Keep the
%distinction", records it SATISFIED in `Metta.Minimal.removeAtomStep`, and
%pins the wording this reproduces. Hyperon as shipped answers unit for both,
%so this is a deliberate divergence from the implementation towards the
%specification, which is also what this engine's own hard-error rule says
%[source: LeaTTa wiki/Hyperon-Hacks-Register.md row 15, and
%MettaHyperonFull/Minimal/Interpreter.lean removeAtomStep at 5407-5426].
%
%metta_remove_atom/3 still answers whether anything went and still answers ONLY
%that, because the engine's own callers read the boolean: the loader's
%rollback, the storage modules, and the seam's removal hooks all ask "did the
%store hold it" rather than "what does a program see".
'remove-atom'(Space, Term, Result) :-
    (   petta_space_name(Space)
    ->  metta_remove_atom(Space, Term, Removed),
        (   Removed == true
        ->  Result = []
        ;   space_operation_error('remove-atom', [Space, Term],
                                  "remove-atom: atom is not in the space",
                                  Result)
        )
    ;   space_argument_error('remove-atom', [Space, Term], Result)
    ).

%WHY THE DOORS ASK IT WHERE THEY DO, which is the decision this section makes.
%
%A space is a NAME that is one, and petta_space_name/1 decides which. The doors
%used to share a metta_space_argument/1 whose whole body was `atom(Space)`, on
%the reading that PeTTa CANNOT reproduce the arbiter's
%`(add-atom not-a-space (bad add))` diagnostic: the two model spaces
%differently, upstream's being a grounded atom wrapping a space object while
%PeTTa's is a symbol, and a write to a name that does not exist yet creates it,
%so `not-a-space` and a program's own fresh name looked like the same kind of
%thing. That reading was wrong on its own terms, and the engine already
%disagreed with it in three places: is-space/2 answers False for a name without
%`&`, evalc/3 refuses one as a type error rather than reading a silently empty
%space, and bindings/python/metta/space.py refuses one with "the prefix is
%load-bearing". Only these doors did not, so `(add-atom not-a-space (bad add))`
%made a space called `not-a-space` while `(is-space not-a-space)` answered
%False in the same program.
%
%The arbiter decides it the same way for the same reason. LeaTTa dispatches by
%name as this engine does, and its `spaceName` says "bare symbols resolve only
%through the running context's token table; an unbound symbol is not a space",
%with every space-consuming operation resolving through `resolveSpace`
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean:1565-1573,1621-1627].
%What it does not have is creation on demand, which is why the second half of
%petta_space_name/1 is the prefix rather than the registry: a fresh `&kb` is a
%space the moment a program writes to it, and that capability is kept whole.
%The one example that used a name without the prefix,
%examples/spaces/add_atom_fun_space.metta, still returns a space name from a
%function and still lands its write there, spelled `&my_space_name`.
%
%The atom is ANSWERED rather than thrown, because that is what the arbiter
%does: `(collapse (add-atom not-a-space (bad add)))` is a one-element collapse
%holding the error, and a raise would have emptied the collapse instead
%[source: LeaTTa tests/semantics/spaces/add_atom.metta]
%[tested: space_argument_refusals].
%
%NO DOOR ASKS ON THE PATH THAT SUCCEEDS. A shared test called before the
%operation cost one to three inferences on every space operation and four
%benchmarks saw it [measured 2026-08-20: direct-join +10, prepared-join +10,
%register-op +200, py-method-call +30,002], so each door asks the question it
%was already asking: a write reaches no storage module for a name that is not a
%space, a read misses the storage lookup it was already making, and a
%conjunctive match answers no rows. Only then, on a path that was going to
%answer nothing, is petta_space_name/1 consulted to tell a space that is empty
%from a name that is not one. That is why metta_space_argument/1 is gone rather
%than renamed: one shared test in front of every door is exactly the shape the
%measurements refuse.

%The shape every space operation refuses in: the arbiter's `errAtom a0`, whose
%subject is the CALL that failed rather than a generic complaint, which is
%what lets a program tell one refusal from another without reading the message.
%
%The subject is a COPY of that call, and that is load-bearing rather than tidy.
%match/4 takes the output template and the answer in the SAME term: the
%translator emits `match('&self', [foo, A], A, A)` for
%`!(match &self (foo $x) $x)`, so unifying the answer with an error whose
%subject repeats the template builds `A = (Error (match _ (foo A) A) "...")`,
%a rational tree. SWI has no occurs check here, so nothing failed; the term
%printed until the 7.5Gb stack ran out, 50,707,153 frames deep in maplist/3
%[measured 2026-08-19]. Copying makes the subject a snapshot, which is what a
%record of a call that will not run is, and it makes every caller of this safe
%whether or not its output slot aliases an input.
space_operation_error(Operation, Arguments, Reason, Error) :-
    copy_term(Arguments, Subject),
    petta_note_copied_variables(Arguments, Subject),
    Error = ['Error', [Operation|Subject], Reason].

%A runnable installs its flat reader map only while its goals execute. The
%open Generated list is copied with each answer, so an operation that must
%copy a diagnostic subject can record the copied variable's spelling without
%putting attributes on matcher variables
%[tested: test_variable_names_survive_to_the_printer; commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
:- meta_predicate petta_run_named(+, 0, -).
petta_run_named(Names, Goal, Generated) :-
    Context = '$petta_runtime_name_context'(Names, Generated, Generated),
    setup_call_cleanup(
        install_runtime_name_context(Context, SavedContext),
        call(Goal),
        restore_runtime_name_context(SavedContext)).

install_runtime_name_context(Context, saved(Previous)) :-
    nb_current('$petta_runtime_name_context', Previous), !,
    nb_linkval('$petta_runtime_name_context', Context).
install_runtime_name_context(Context, none) :-
    nb_linkval('$petta_runtime_name_context', Context).

restore_runtime_name_context(saved(Previous)) :- !,
    nb_linkval('$petta_runtime_name_context', Previous).
restore_runtime_name_context(none) :-
    nb_delete('$petta_runtime_name_context').

petta_note_copied_variables(Original, Copy) :-
    nb_current('$petta_runtime_name_context', Context), !,
    Context = '$petta_runtime_name_context'(Names, _, _),
    term_variables(Original, OriginalVars),
    term_variables(Copy, CopyVars),
    petta_note_variable_pairs(OriginalVars, CopyVars, Names, Context).
petta_note_copied_variables(_, _).

petta_note_variable_pairs([], [], _, _).
petta_note_variable_pairs([Original|Originals], [Copy|Copies], Names, Context) :-
    (   petta_reader_variable_name(Names, Original, Name)
    ->  arg(3, Context, Tail),
        Tail = [Name-Copy|Next],
        setarg(3, Context, Next)
    ;   true
    ),
    petta_note_variable_pairs(Originals, Copies, Names, Context).

petta_reader_variable_name([Name-Variable|_], Original, Name) :-
    Variable == Original, !.
petta_reader_variable_name([_|Names], Original, Name) :-
    petta_reader_variable_name(Names, Original, Name).

%get-atoms is worded differently because upstream words it differently: it
%takes ONE argument, so pinned `space.rs:143` says "its argument" where the
%two-operand operations' `:172` and `:199` say "the first argument"
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, getAtomsStep at
%5450-5452 against addAtomStep at 5386-5388].
space_argument_error(Operation, Arguments, Error) :-
    (   Operation == 'get-atoms'
    ->  Position = "its argument"
    ;   Position = "the first argument"
    ),
    format(string(Message),
           "~w expects a space as ~w", [Operation, Position]),
    space_operation_error(Operation, Arguments, Message, Error).

%%%% The three the standard library defines beside add-atom %%%%
%
%All three were reachable only through `(import! &self (library lib_he))`, and
%only one of them at that, so a program written against the standard library
%found `(add-reduct &self (+ 1000 1))` sitting in the space UNREDUCED as the
%call itself. They are stdlib operations, not extensions:
%
%  add-atoms    "adds atoms in Expression into given space without reduction"
%  add-reduct   "Reduces atom (second argument) and adds it into the space"
%  add-reducts  "evaluates atoms in it and adds them into given space"
%
%[source: LeaTTa stdlib.md:330-361, quoted in its tests/semantics/spaces].
%
%Each answers the UNIT value, like add-atom, and each takes its second argument
%unreduced: the reducing ones do their own reducing, which is the whole of what
%distinguishes them from the plain ones.
%All three DELEGATE the space check to add-atom rather than repeating it, and
%that is observable: the arbiter answers `(Error (add-atom not-a-space 7001)
%...)` for `(add-reduct not-a-space (+ 7000 1))`, naming add-atom and the
%REDUCED atom, because the refusal happens where the write does. Checking here
%would name add-reduct and the unreduced call, which is a different answer.
'add-atoms'(Space, Terms, Result) :-
    metta_space_expression('add-atoms', Terms, List),
    add_expression_to_space(Space, List, Result).

'add-reduct'(Space, _, _) :-
    var(Space),
    !,
    refuse_unbound_input('add-reduct', 1).
'add-reduct'(Space, Term, Result) :-
    reduced_for_space(Term, Reduced),
    'add-atom'(Space, Reduced, Result).


'add-reducts'(Space, Terms, Result) :-
    metta_space_expression('add-reducts', Terms, List),
    maplist(reduced_for_space, List, Reduced),
    add_expression_to_space(Space, Reduced, Result).

%The batch crossing is kept for the space that has one, so the plural forms are
%still one write rather than n. A bad space is refused before any of it, and
%the error names the first atom because that is the one add-atom would have
%refused first.
%The batch door asks BEFORE the crossing rather than reading its failure, which
%the two doors above can do: a batch has its own crossing and a per-atom
%fallback that answers the error atom instead of failing, so a failure here
%does not mean what it means there. It costs the test once per batch and not
%once per atom.
add_expression_to_space(Space, List, Result) :-
    (   petta_space_name(Space)
    ->  metta_add_atoms(Space, List), Result = []
    ;   List = [First|_]
    ->  space_argument_error('add-atom', [Space, First], Result)
    ;   Result = []
    ).

%The plural forms take ONE expression holding the atoms, which is the shape the
%standard library gives them, so anything else is a mistake worth naming rather
%than a silent no-op over a term that is not a list.
%A DEFINITION reduces its body and keeps its head, and everything else reduces
%whole. Both readings are required by the two things this has to satisfy:
%
%  (add-reduct &self (+ 1000 1))          adds 1001
%  (add-reduct &self (= (foo) (+ 3 4)))   makes (foo) answer 7
%
%[source: LeaTTa tests/semantics/spaces/add_reduct.metta for the first, the
%language's Working with spaces for the second]. Reducing the second one whole
%cannot work HERE, and the reason is local rather than general: `=` is
%overloaded in this engine, the head of a definition and also the equality
%operator, so `(= (foo) (+ 3 4))` reduces to `false` rather than staying an
%equation with its body reduced. Upstream has no such collision, which is why
%it can state the rule as one sentence and this cannot.
reduced_for_space([=, Head, Body], [=, Head, ReducedBody]) :-
    !,
    reduced_for_space(Body, ReducedBody).

%reduce/3 takes an expression, and a symbol or a number is already its own
%value, so asking it to reduce one raises rather than answering. Both callers
%above may be handed either, because their argument arrives unreduced.
reduced_for_space(Term, Reduced) :-
    (   is_list(Term)
    ->  once(reduce(Term, Reduced, _))
    ;   Reduced = Term
    ).

metta_space_expression(_, Terms, Terms) :- is_list(Terms), !.
metta_space_expression(Operation, Terms, _) :-
    throw(error(type_error(expression, Terms),
                context(Operation, 'takes one expression of atoms'))).

%The mirror of the write path, and it has to be: an atom that compiled when it
%was added has to un-compile when it is taken out, wherever it was stored. This
%dispatched on storage first for the same reason the write path did, so a
%foreign space's equation kept its compiled clause after the atom was gone.
%A pattern that is ITSELF a variable is the remove-everything reading a
%multiset space gives it, and it must be answered here: left to the next
%clause, the unbound term UNIFIED into the equation shape and took the
%equation-removal path with an unbound function symbol, whose behaviour
%then depended on whatever equations the whole process happened to hold
%(found 2026-08-18: (remove-atom &cstore $any) raised
%atomic_list_concat/2 instantiation errors only when other suites had
%run first). Enumerating and removing each atom through its own proper
%path keeps equations, their compiled clauses, and foreign providers
%all handled by the code that owns them.

%% metta_remove_atom(+Space, ?Atom, -Removed:boolean) is semidet.
metta_remove_atom(Space, _, _) :-
    metta_refuse_module_for_space(Space, metta_remove_atom/3),
    fail.
metta_remove_atom(Space, Term, Removed) :- var(Term), !,
    findall(A, metta_host_stored(Space, A), Atoms),
    (   Atoms == []
    ->  Removed = false
    ;   forall(member(A, Atoms),
               ( metta_remove_atom(Space, A, _) -> true ; true )),
        Removed = true
    ).
metta_remove_atom(Space, Term, Removed) :- Term = [=, [F|Args], Body], !,
                                           remove_equation(Space, Term, F, Args,
                                                           Body, Removed).
metta_remove_atom(Space, Term, Removed) :-
    Term = [':', Type, Marker],
    atom(Type),
    ( Marker == 'DontEvalType' ; var(Marker) ),
    !,
    unstore_atom(Space, Term, Removed),
    (   Removed == true
    ->  space_module(Space, DeclModule),
        ( fun(Type) -> announce_function_changed(DeclModule, Type) ; true ),
        type_marker_changed(DeclModule, Type)
    ;   true
    ).
metta_remove_atom(Space, Term, Removed) :-
    Term = [':', Type, Marker],
    var(Type),
    ( Marker == 'DontEvalType' ; var(Marker) ),
    !,
    findall(MarkerType,
            ( match_stored(Space,
                           [':', MarkerType, 'DontEvalType'], MarkerType, _),
              atom(MarkerType) ),
            MarkerTypes0),
    sort(MarkerTypes0, MarkerTypes),
    unstore_atom(Space, Term, Removed),
    (   Removed == true
    ->  space_module(Space, DeclModule),
        forall(member(MarkerType, MarkerTypes),
               type_marker_changed(DeclModule, MarkerType))
    ;   true
    ).
%A declaration decides how call sites compile, so taking one away leaves them
%stale exactly as adding one did, and for the same reason: the argument that
%arrived as written now arrives evaluated. The write path learned this and the
%removal path did not.
metta_remove_atom(Space, Term, Removed) :- Term = [':', F, _], atom(F), fun(F), !,
                                           unstore_atom(Space, Term, Removed),
                                           space_module(Space, DeclModule),
                                           announce_function_changed(DeclModule, F).
metta_remove_atom(Space, Term, Removed) :- unstore_atom(Space, Term, Removed).

type_marker_changed(Module, Type) :-
    findall(Function-Context,
            type_marker_dependent(Module, Type, Function, Context),
            Dependents0),
    sort(Dependents0, Dependents),
    findall(Root,
            ( member(Function-Context, Dependents),
              Root = type_marker(Module, Type),
              support_record(function_view(Context, Function), Root) ),
            Roots0),
    sort(Roots0, Roots),
    support_invalidate_many(Roots),
    forall(support_repair_invalidations, true),
    clear_translation_cache.

type_marker_dependent(MarkerModule, Type, Function, Context) :-
    type_marker_function_context(Function, Context),
    type_marker_visible_in(MarkerModule, Context),
    stored_arrow_uses_type_in(Context, Function, Type).

type_marker_function_context(Function, Context) :-
    support_view_module(Function, Context).

type_marker_visible_in(MarkerModule, Context) :-
    metta_self_module(Self),
    ( MarkerModule == Self -> true ; Context == MarkerModule ).

stored_arrow_uses_type_in(Context, Function, Type) :-
    metta_self_module(Context),
    !,
    stored_arrow_chain('&self', Function, Types),
    arrow_parameter_type(Types, Type).
stored_arrow_uses_type_in(Context, Function, Type) :-
    metta_module_space(Context, Space),
    (   stored_arrow_chain(Space, Function, Types)
    ;   stored_arrow_chain('&self', Function, Types)
    ),
    arrow_parameter_type(Types, Type).

%The arrow shape is checked AFTER the match, not asked for in the pattern,
%because a pattern crossing a space seam has to be a MeTTa TERM and a partial
%list is not one. [-> | Types] with Types unbound is fine against the native
%store, where matching is Prolog unification, and has no text at all for a
%provider that writes the pattern to send it: MORK refused this one and the
%refusal surfaced as `swrite/2: cannot write [->|'$petta_variable'(0)]` from
%an ordinary (: Name Type) declaration, reproduced by storing an equation in
%&mork, removing it, and then declaring any type marker [measured 2026-08-21].
%Asking with a plain variable and filtering here is the seam's own
%over-approximate-then-re-unify contract, and it costs the native path
%nothing: Function is bound, so the store still dispatches on it.
stored_arrow_chain(Space, Function, Types) :-
    match_stored(Space, [':', Function, Chain], Chain, _),
    nonvar(Chain),
    Chain = [->|Types].

arrow_parameter_type(Types, Type) :-
    append(ParameterTypes, [_], Types),
    member(ParameterType, ParameterTypes),
    ParameterType == Type.

%A host's reporting removal: whether anything actually went. The
%language-facing `remove-atom` answers the UNIT value, because its type is
%`(-> spaceType Atom (->))` and the specification says absence is not
%reported there; a HOST API where `space.remove(atom)` returns whether
%anything went is the useful answer, and nothing in MeTTa's contract
%governs it. Existence is asked BEFORE the mutation against a copy, so the
%removal's own bindings cannot narrow the question; a foreign space's
%provider owns its verdict outright.
metta_host_remove_reported(Space, Term, Verdict) :-
    (   seam:foreign_space(Space)
    ->  metta_remove_atom(Space, Term, Verdict)
    ;   copy_term(Term, Pattern),
        (   metta_host_removal_probe(Space, Pattern)
        ->  Existed = true
        ;   Existed = false
        ),
        metta_remove_atom(Space, Term, Removed0),
        ( Removed0 == false -> Verdict = false ; Verdict = Existed )
    ).

%Whether an atom unifying with Pattern is stored, without enumerating the
%space when the answer is reachable by index. The first branch probes the
%native storage predicate directly, which first-argument indexing makes
%O(1) for the ground common case; it may only SUCCEED, never conclude
%absence, because storage shapes this cannot express (a foreign layout, an
%atom that is not a list) still exist. Failure falls back to the
%enumeration, so the semantics are the old ones exactly and only the cost
%moves. Found because the contract ontology's 65 resident atoms in &petta
%turned a get-atoms walk into +149 inferences per register-and-unregister
%cycle on the register-op benchmark [measured 2026-08-18: a remove on an
%80-atom &petta cost 303 inferences against 61 on a plain space, and the
%engine-level remove path profiled flat].
metta_host_removal_probe(Space, Pattern) :-
    Space = [_|_],
    space_parametric(Space),
    is_list(Pattern),
    Pattern = [Head|Arguments],
    atom(Head),
    native_storage_module(Space, Module),
    Goal =.. ['$petta_parametric_atom', Head|Arguments],
    call(Module:Goal),
    !.
metta_host_removal_probe(Space, Pattern) :-
    atom(Space),
    is_list(Pattern),
    Pattern = [Head|Arguments],
    atom(Head),
    catch(( native_storage_module(Space, Module),
            Goal =.. [Space, Head|Arguments],
            call(Module:Goal) ),
          error(existence_error(procedure, _), _),
          fail),
    !.
metta_host_removal_probe(Space, Pattern) :-
    once((metta_host_stored(Space, Stored), Stored = Pattern)).

%Every stored atom unifying Pattern, live from the space: a native space
%answers through its storage module's clause indexing, a foreign one
%enumerates its provider and unifies. Pattern-directed where storage
%allows, so an indexed head pattern does not pay a whole-space walk.
metta_host_stored(Space, Pattern) :-
    (   seam:foreign_space(Space)
    ->  'get-atoms'(Space, Atom),
        Atom = Pattern
    ;   get_native_atom(Space, Pattern)
    ).

%Decode a native storage goal for proof transports without publishing the
%storage module cache or its private functor convention to the host. Module
%and functor must both identify the same registered space [tested:
%test_a_parametric_fact_leaf_names_its_space; commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
metta_host_native_fact(Module, Goal, Space, Fact) :-
    native_storage_module_cache(Space, Module),
    native_storage_functor(Space, Functor),
    functor(Goal, Functor, _),
    Goal =.. [_|Fact].

%% remove_equation(+Space, +Equation, +Function:atom, +Arguments, ?Body, -Removed:boolean) is semidet.
remove_equation(Space, Term, F, Args, Body, Removed) :-
    unstore_atom(Space, Term, Stored),
    space_module(Space, Module),
    drop_fun_meta(Module, F, Args, Body),
    %ONE compiled clause, the multiset law applied to the compiled half. The
    %retained-equation half above already worked this way and said so, "remove
    %one variant-equivalent retained equation... duplicate equations are
    %removed one at a time", so the two halves used to disagree: the same
    %equation written twice answered twice, and one removal left the function
    %undefined because this erased both clauses under the one atom that went.
    %
    %Only this space's compiled clauses die: the same equation imported into two
    %spaces compiles into two modules, and the term-keyed lookup alone would
    %erase the twin space's clause and, through the term-wide retractall, its
    %record with it.
    %
    %The probe is a COPY for drop_fun_meta/4's reason: a lookup that binds the
    %caller's Term would narrow every later use of it in this clause.
    copy_term(Term, Probe),
    (   translated_from(Ref, Probe), clause_property(Ref, module(Module))
    ->  forget_translated_from(Module, Ref, Probe), erase(Ref), Erased = true
    ;   Erased = false
    ),
    %A local predicate the erase just EMPTIED still shadows the same name
    %inherited through the module chain, &self's builtins above all: after
    %removing a car-atom shadow from &self, every &self-compiled caller of
    %car-atom failed for the rest of the process because the empty local
    %definition answered instead of the engine's. Dropping the emptied
    %entry lets the chain answer again. The arity comes from the STORED
    %equation the lookup unified into Probe, never from the caller's Args:
    %a removal by open pattern, [Head|_], leaves Args a partial list, and
    %length/2 on a partial list generates arities for ever
    %[tested: removing_a_self_shadow_restores_the_builtin].
    (   Erased == true,
        Probe = [=, [_|StoredArgs], _],
        is_list(StoredArgs),
        length(StoredArgs, NArgs),
        PredArity is NArgs + 1,
        functor(EmptyHead, F, PredArity),
        predicate_property(Module:EmptyHead, number_of_clauses(0))
    ->  (   current_transaction(_)
        ->  %abolish/1 is predicate-level, so a rollback cannot restore
            %what it dropped: a failed reload lost the definitions it
            %promised to keep when this abolished eagerly. The pending
            %fact IS clause-level, so it vanishes with a rollback and
            %survives a commit, and the owner of the outermost
            %transaction sweeps it afterwards
            %[tested: test_a_reload_that_fails_leaves_the_previous_definitions_standing].
            assertz('$petta_shadow_repair_pending'(Module, F, PredArity))
        ;   petta_repair_emptied_shadows,
            catch(abolish(Module:F/PredArity), _, true)
        )
    ;   true
    ),
    announce_function_changed(Module, F),
    ( module_owns_function(Module, F) -> true ; unregister_fun_in(Module, F) ),
    ( \+ function_still_defined(F)
      -> retractall(fun(F)), unregister_fun_everywhere(F),
         %announce_function_removed/1, not the bare event: fun(F) is false only now,
         %so THIS recompile is the one that reads mentions of F as data
         %again; the function_changed above ran while F was still a function.
         announce_function_removed(F)
      ; true ),
    ( Erased == false, Stored \== true -> Removed = false ; Removed = true ).

:- dynamic '$petta_shadow_repair_pending'/3.

%The deferred half of the emptied-shadow repair above: each pending row
%names a function a committed transaction emptied. The recheck matters,
%because a reload that REDEFINES a function empties it in withdrawal and
%refills it in the load, and only a function still empty at the sweep is
%a shadow to drop. abolish refusing (a tabled shadow) leaves the old
%behaviour, an empty local predicate.
petta_repair_emptied_shadows :-
    forall(retract('$petta_shadow_repair_pending'(Module, F, PredArity)),
           (   functor(Head, F, PredArity),
               (   predicate_property(Module:Head, number_of_clauses(0))
               ->  catch(abolish(Module:F/PredArity), _, true)
               ;   true
               )
           )).

%Where an atom comes out of, the counterpart of store_atom/2. Both answer
%whether the store actually held it.

%% unstore_atom(+Space, ?Atom, -Removed:boolean) is semidet.
unstore_atom(Space, Term, Removed) :- seam:foreign_space(Space), !,
                                      foreign_write(Space, remove,
                                                    seam:foreign_remove(Space, Term,
                                                                         Removed)).
%One atom that unifies, and whether one was there. A MeTTa space is a multiset,
%and subtracting from a multiset takes one occurrence.
unstore_atom(Space, Term, Removed) :- remove_sexp(Space, Term, Removed).

%A CONJUNCTION finds every row before any of them leaves, which is specified
%behaviour and not an implementation detail we are free to pick: "match first
%finds all the matches, and then instantiates the output pattern with them,
%which is evaluated outside match. If remove-atom and add-atom would be
%executed right away for each found matching, the condition of circular links
%would be broken after the first rewrite" [source: the language's Working with
%spaces, the graph-rewriting example]. The arbiter pins it with an experiment
%built to tell an eager snapshot from a lazy query that happens to be fully
%consumed: both implementations retain every row through a template that
%removes the other one, and only the effect ORDER is a recorded free
%divergence [source: LeaTTa tests/semantics/matching/
%nondeterministic_match_snapshot.metta and its EVIDENCE entry].
%
%A SINGLE pattern needs nothing here and still streams. It is one goal over
%one dynamic predicate, and the logical update view already fixes what it sees
%at the call, so a template that writes cannot change what the goal still has
%to answer; the arbiter's own single-pattern experiment passes on that alone.
%A conjunction is where it runs out, because each later conjunct is a fresh
%goal STARTED AFTER the previous row's template ran, and a fresh goal sees the
%new generation. Measured on the doc's own example: upstream reverses all
%three loop edges, and this reversed one, the first template's remove-atom
%breaking the cycle for every later conjunct [measured 2026-08-19,
%ai-tmp/spaces-p1/p116/linkloop.metta].
%
%What is collected is the BINDINGS, term_variables over the pattern and the
%output template together, because that is where a row lives: the translator
%compiles the template into goals reading the PATTERN's own variables,
%`'remove-atom'('&self', [link, B, C], _)` beside `match('&self', [',',
%[link,B,C], ...], A, A)`, so collecting the output slot alone would collect a
%variable the match never binds and lose every row. Taking both terms'
%variables keeps whatever they share.
%
%Cheaper than the arbiter, which collects a BindingsSet for every match; this
%pays only where a conjunction is written, and leaves
%(once (match &big (foo $x) $x)) streaming
%[tested: test_match_snapshots_rows_before_template_effects,
%spaces_match_snapshot:a_conjunction_finds_every_row_before_any_template_runs].
%An ANNOTATED space's rows carry their annotation as well as their bindings,
%because that rides '$petta_answer_k' BACKTRACKABLY and findall would undo it:
%reset-call-read is metta_top/3's own idiom below, and the write after member/2
%is what hands the row's k to the template that reads (annotation).
%
%A space whose semiring is bool takes the plain collection, which is three
%inferences a row cheaper and is the traffic: under bool an answer's k can
%only be 1, because a provider handing one to an undeclared context raises
%rather than setting it ("a real k is admitted exactly when its context
%declared a non-Boolean semiring", bindings/python/metta/shim.pl), and the engine's own
%join writes nothing when both sides read 1. Measured on direct-join
%[measured 2026-08-19: 320,322 inferences with the capture on every row
%against 289,819 without it, over 10,000 rows]
%[tested: test_a_join_multiplies_provenance,
%test_a_conjunction_carries_each_rows_annotation].
%Atomic names retain the atom/1 fast path. Registered parametric names add one
%indexed registry probe; the refusal is still reached through the SOFT CUT
%below, so a conjunction that answered rows was a space and only one that
%answered none has anything left to decide. A general space test in the guard
%cost one inference on every ordinary join [measured 2026-08-20: direct-join
%and prepared-join +10 each].
match([Family|Parameters], Pattern, OutPattern, Result) :-
    nonvar(Pattern),
    Pattern = [Comma|_],
    Comma == ',',
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    conjunctive_match(match_conjunction(Space, Pattern, OutPattern),
                      Space, Pattern, OutPattern, Result).
match(Space, Pattern, OutPattern, Result) :- nonvar(Pattern), Pattern = [Comma|_], Comma == ',',
                                             atom(Space), !,
                                             (   conjunctive_match(match_conjunction(Space,
                                                                                     Pattern,
                                                                                     OutPattern),
                                                                   Space, Pattern,
                                                                   OutPattern, Result)
                                             *-> true
                                             ;   petta_space_name(Space)
                                             ->  fail
                                             ;   space_argument_error('match',
                                                                      [Space, Pattern,
                                                                       OutPattern],
                                                                      Result)
                                             ).

%A single pattern over a foreign space: the provider answers, and the
%conjunction door above has already taken the conjunctive case.
match(Space, Pattern, OutPattern, Result) :- nonvar(Space),
                                             seam:foreign_space(Space), !,
                                             match_foreign(Space, Pattern, OutPattern, Result).
%An unbound space would make this dynamic call enumerate every space that has
%ever been written to, so a program in &self could read &kb without naming it.
%Matching is against a space you NAME, and the refusal is the write path's
%own: `(add-atom $unbound (foo 1))` already answered
%`(Error (add-atom $_ (foo 1)) "add-atom expects a space as the first
%argument")` while this raised SWI's bare `Arguments are not sufficiently
%instantiated`, which names neither the operation nor the call and reached
%Python as an EngineError with no operation field at all. Same question, same
%kind of answer [tested: test_get_atoms_on_an_unbound_space_names_the_operation,
%spaces_storage_modules:matching_requires_a_named_space].
%
%The storage lookup this clause was already making IS the space test for every
%name the engine holds, so a match against a space that exists reaches
%match_native/5 exactly as it did and the two clauses below it never run. The
%CUT is what lets them exist: without it an answered match would produce the
%refusal as a second answer.
match([Family|Parameters], Pattern, OutPattern, Result) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    native_storage_module_cache(Space, Module), !,
    match_native(Module, Space, Pattern, OutPattern, Result).
match(Space, Pattern, OutPattern, Result) :-
    atom(Space),
    native_storage_module_cache(Space, Module), !,
    (   space_parent(Space, _)
    ->  match_inherited_space(Space, Module, Pattern, OutPattern, Result)
    ;   match_native(Module, Space, Pattern, OutPattern, Result)
    ).
%Only a name the engine holds no space for reaches here, and the question left
%is which kind it is: a space nothing has written to yet answers nothing, which
%is what an empty space answers, and anything else is refused by name.
%
%GUARDED RATHER THAN LEFT TO THE CUT ABOVE, and that is load-bearing: the
%derivation meta-interpreter walks a predicate by enumerating clause/3 and
%calling each body through call/1, where a cut in an earlier body cannot prune
%this clause. Written without the guard, every match against a real space grew
%a second answer, the refusal, and `(anc-d $x $y)` recursed on it until the
%process hung [reproduced 2026-08-20: bindings/python/tests/test_derivation.py]. Every
%clause of a predicate a proof can walk has to say for itself when it applies,
%which is what the three clauses above already do.
match(Space, Pattern, OutPattern, Result) :-
    \+ petta_space_name(Space),
    space_argument_error('match', [Space, Pattern, OutPattern], Result).

%The PRODUCER is handed in rather than built here, because the caller is where
%a bound is known: match/4 hands the plain conjunction walk and
%match_bounded/5 hands the same walk under limit/2, so a bounded caller
%collects its bound's worth of rows and stops. The unbounded collection is
%therefore exactly the goal it always was and pays nothing for the choice
%[measured 2026-08-21: direct-join and prepared-join unchanged at 300,522].
%
%Both spellings keep the snapshot: every row the caller can reach is found
%before the first of them leaves, which is the whole point of the findall.
%A bound only makes the set of reachable rows smaller.
%
%No meta_predicate declaration, and that is deliberate: the producer is always
%the engine's own match_conjunction/3, which lives in `user` beside this
%clause, where a named space's module never enters. metta_take/2 and
%metta_top/3 declare one because their goal is a MeTTa BODY.
conjunctive_match(Producer, Space, Pattern, OutPattern, Result) :-
    term_variables(Pattern-OutPattern, Row),
    (   petta_annotations(Space, bool)
    ->  findall(Row,
                Producer,
                Rows),
        member(Row, Rows)
    ;   petta_algebra_one(Space, One),
        findall(Row-K,
                ( b_setval('$petta_answer_k', One),
                  Producer,
                  b_getval('$petta_answer_k', K) ),
                Rows),
        member(Row-K, Rows),
        b_setval('$petta_answer_k', K)
    ),
    Result = OutPattern.
