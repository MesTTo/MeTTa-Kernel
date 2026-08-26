% Purpose: decode stored atoms and manage source, subscription, reaction, table, and clear lifecycles
% Assumes: engine/spaces.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/spaces.pl's implementation module and original load order.
%   A foreign space life releases tabled, generated, deferred-translation, and
%   support state before its execution-module name can be reused [tested:
%   test_a_recycled_mork_name_inherits_nothing; commit=d843bb6d17a525c36afd21cab077d63b34447535].
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/spaces.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%The inverse of add_sexp_in/4, written here beside it for the same reason
%metta_module_space/2 is written beside space_module/2: the mapping is
%injective, so the inverse is a function rather than a search, and keeping the
%pair together is what stops one of them drifting.
%
%The caller is a RELOAD. A source load records a clause reference for
%everything it asserts, atoms and compiled clauses and registrations alike,
%and taking a file's atoms back out has to go through metta_remove_atom/3,
%which takes an atom rather than a reference. So this is how the reload tells
%an atom's reference from the rest: it FAILS on any reference that is not a
%stored atom's, and on an erased one, and it answers the SPACE as well as the
%atom because a file's !(add-atom &elsewhere ...) is recorded by the load that
%ran it and belongs back in &elsewhere rather than in the space being reloaded
%[tested: spaces_storage_modules:a_stored_atoms_reference_decodes_to_its_atom].
%
%The module comes from clause_property/2 and not from the head clause/3 hands
%back, because that head is qualified only when the clause's module differs
%from the CALLER's: read from the engine it arrives bare, so stripping it named
%the engine's own module and every atom looked like something else
%[measured 2026-08-19: the withdrawal reported 0 atoms while removing them].
stored_atom_of_ref(Ref, Space, Atom) :-
    catch(clause_property(Ref, predicate(Module:Name/_)), _, fail),
    native_storage_module(Space, Module),
    native_storage_functor(Space, Functor),
    catch(clause(Stored, true, Ref), _, fail),
    strip_module(Stored, _, Head),
    (   Name == '$petta_native_scalar'
    ->  Head = '$petta_native_scalar'(Atom)
    ;   Name == Functor,
        Head =.. [_, Rel|Args],
        Atom = [Rel|Args]
    ).

%The clause a native space stores an atom AS. This is the definition of that
%shape, and lib_import.pl's static-import! writes exactly this to a file so a
%large data file can be qcompiled once instead of parsed every run. The two
%used to disagree and it was invisible: the converter wrote '&self'(fact,a,1)
%into USER while native atoms live in the storage module '$petta_atoms:&self',
%so a static import loaded clauses nothing could read and reported success
%[tested: native_storage_shapes_agree,
%import_facts_land_where_the_space_reads_them].
native_atom_clause([Family|Parameters], [Rel|Args], Term) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    Term =.. ['$petta_parametric_atom', Rel|Args].
native_atom_clause(Space, [Rel|Args], Term) :- !,
    Term =.. [Space, Rel | Args].
native_atom_clause(_, Atom, '$petta_native_scalar'(Atom)).

%Remove ONE atom that unifies with the requested value. Expressions and
%scalars live in different predicates, so neither erases the other.
:- dynamic remove_sexp/3.
remove_sexp(Space, Atom) :- remove_sexp(Space, Atom, _).

%The same removal, answering whether anything WAS there.
%
%ONE occurrence, because removal is multiset SUBTRACTION. This used to take
%every occurrence, and its stated reason was an invalid inference: "a MeTTa
%space is a multiset unless something forbids it, SO removal takes EVERY
%occurrence". The premise argues for the opposite conclusion, and the tree it
%described was a multiset on ADD and a set on REMOVE, so three adds of (dup 1)
%gave count 3 and one removal gave count 0. The arbiter reads the premise the
%other way: "remove-atom must behave as multiset subtraction on the
%reader-visible view of &self", and its own model "removes the first exact
%occurrence and returns unit"
%[source: LeaTTa MettaHyperonFullTests/Properties.lean:107,
%MettaHyperonFull/Minimal/Stdlib.lean:2223, and wiki/Mechanization-Ledger.md
%row "Represented removal consumes the first exact occurrence", which pins
%(one two one) minus (one) as (two one) executably].
%
%This engine had already decided it everywhere else. The seam declares
%seam:foreign_remove/3 as "remove one" (EXTENDING.md), and drop_fun_meta/4
%takes "one variant-equivalent retained equation" at a time
%(engine/translator.pl:115). The native store was the one holdout.
%
%retract/1 under double negation, which makes the answer and the removal one
%lookup instead of two. retractall/1 succeeds whether or not it matched, so
%the answer had to come from a separate clause/2 probe in front of it, and
%that pair was also a check-then-act race: retract/1 reports what it did, and
%SWI adjusts each thread's entry generation so "if multiple threads use
%once(retract(Term)), no two threads will retract the same clause". Exactly
%ONE clause goes because the double negation takes retract/1's first solution
%and never backtracks into it, and it has to: under the logical update view
%"retract/1 succeeds for all clauses that match Term when the predicate was
%called", so a retract left open on backtracking would drain the lot
%[source: SWI-Prolog 10.1 Reference Manual, retract/1].
%
%Double negation rather than a copy because the bindings must NOT escape.
%That is the engine's own rule for the compiled half, "retraction must not
%bind the caller's variables" (engine/translator.pl:115), and the language's:
%remove-atom answers unit, so (remove-atom &self (pair $x)) is a request, not
%a query, and $x is no more bound afterwards than before. It is also the
%cheaper of the two isolations. Measured 2026-08-19 over 20,000 removals, min
%of three: 1.0001 inferences per removal against the probe-and-retractall
%shape's 2.0001, and against 2.0001 for the copy_term spelling
%[measured 2026-08-19, ai-tmp/spaces-p1/rmcost.pl].
%
%Answering truthfully at all is worth it because the engine already disagreed
%with ITSELF. Removing an EQUATION answers false when nothing matched, forty
%lines up, and a foreign provider fills seam:foreign_remove/3's Removed
%argument honestly, so a MeTTa program branching on (remove-atom $space $atom)
%was correct against two of the three and wrong against the third, with
%nothing in its text saying which it would get
%[tested: spaces_removal_answers_unit_for_success_and_an_error_for_absence,
%test_remove_atom_removes_one_occurrence_not_all].
remove_sexp('&metta', [Rel|Args], Removed) :- !,
    (   native_storage_module_ready('&metta', Module)
    ->  Term =.. ['&metta', Rel|Args],
        native_retract_one(Module:Term, Removed),
        (   Removed == true
        ->  petta_catalog_note_removed([Rel|Args])
        ;   true
        )
    ;   Removed = false
    ).
remove_sexp([Family|Parameters], [Rel|Args], Removed) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    (   native_storage_module_ready(Space, Module)
    ->  Term =.. ['$petta_parametric_atom', Rel|Args],
        native_retract_one(Module:Term, Removed)
    ;   Removed = false
    ).
remove_sexp(Space, [Rel|Args], Removed) :- !,
    (   native_storage_module_ready(Space, Module)
    ->  Term =.. [Space, Rel | Args],
        native_retract_one(Module:Term, Removed)
    ;   Removed = false
    ).
remove_sexp(Space, Atom, Removed) :-
    (   native_storage_module_ready(Space, Module)
    ->  native_retract_one(Module:'$petta_native_scalar'(Atom), Removed)
    ;   Removed = false
    ).

native_retract_one(Head, Removed) :-
    ( \+ \+ retract(Head) -> Removed = true ; Removed = false ).

%Which module a space's compiled clauses live in. EVERY registered space gets
%one, &self included. Atomic names retain their prefix mapping; parametric
%names use the same canonical identity encoding as storage, under a distinct
%prefix. Both mappings are total over their respective name classes and
%injective.
%
%&self used to compile into the module the ENGINE itself resolves in, and an
%equation asserted there does not shadow a predicate of that name, it REPLACES
%it for the rest of the process. Two shipped examples did exactly that
%[measured 2026-08-19: examples/functions/invertpeanoplus.metta took
%user:plus/3 from imported_from(system) to a local definition, after which
%plus(1,2,X) failed instead of answering 3; examples/libraries/
%minimal_metta.metta did the same to user:rule/3]. Every gate stayed green
%through both, because nothing that ran afterwards in those processes called
%either predicate. tests/prolog/engine_integrity.pl is the check that would
%not have let it stand, and it is a GATE at zero findings.
%
%A goal unresolved in a space's module still reaches the engine, the builtins
%and the libraries through the base chain below, so nothing has to be
%published for a compiled clause to run
%[tested: spaces_execution_modules].
%DETERMINISTIC, and the if-then-else is what makes it so. Asserting the known
%spaces as facts of space_module/2 itself in front of the rule reads one
%inference cheaper, and costs far more than it saves: the rule's head unifies
%with every space too, so a known one succeeds holding a CHOICE POINT, and
%backtracking into it re-enters the rule and takes the mutex. Measured
%2026-08-19 on that shape: eval-arith 172,009 -> 237,980 inferences, op-raw
%178,011 -> 253,976, op-encoded 214,011 -> 289,969.
space_module(Space, Module) :-
    (   metta_exec_module_known(Space, Module)
    ->  true
    ;   metta_exec_module_name(Space, Module),
        with_mutex('$petta_metta_exec',
                   ensure_metta_exec_module_locked(Space, Module))
    ).

metta_exec_module_name(Space, Module) :-
    atom(Space), !,
    metta_exec_module_prefix(Prefix),
    atom_concat(Prefix, Space, Module).
metta_exec_module_name(Space, Module) :-
    space_parametric(Space),
    !,
    space_canonical_atom(Space, Encoded),
    atom_concat('$petta_param_exec:', Encoded, Module).

:- dynamic metta_exec_module_known/2.
:- dynamic space_parent/2.
:- dynamic metta_exec_module_parent/2.
:- dynamic space_restricted/2.
:- dynamic space_grant/2.
:- dynamic restricted_profile_known/2.
:- dynamic '$petta_repaired_shadow_import'/4.

%The chain, and why each link is where it is.
%
%  system  ->  the ENGINE's module  ->  '$petta_exec:&self'  ->  every other
%                                                                space
%
%&self's module inherits the engine's, so every builtin, every library
%predicate and every function imported from Prolog still resolves from a
%compiled MeTTa clause. Every other space inherits &self's, which is the
%sharing rule the engine already states for functions and types ("&self is the
%shared space", fun_here_in/2) and which named spaces used to get by accident:
%&self WAS `user`, and SWI gives an implicitly created module the base `user`.
%
%The base is SET rather than left to the name. SWI gives an implicitly created
%module whose name starts with `$` the base `system` and every other name the
%base `user`, and a module created by a :- module(...) FILE gets `user`
%whatever its name; neither rule is stated in the manual, and the first one
%alone makes '$petta_exec:&self' unable to see the engine at all
%[measured 2026-08-19: '$petta_exec:&self':'add-atom'/3 raised
%existence_error on boot until the base was set explicitly]
%[tested: spaces_execution_modules:the_chain_is_engine_then_self_then_space].
metta_exec_module_base(Space, Base) :-
    (   Space == '&self'
    ->  petta_engine_module(Base)
    ;   space_restricted(Space, Grants)
    ->  ensure_restricted_profile(Grants, Base)
    ;   space_parent(Space, Parent)
    ->  space_module(Parent, Base)
    ;   space_module('&self', Base)
    ).

%set_module/1 is idempotent and works on a module that already holds clauses
%[measured 2026-08-19: import_module went [user] -> ['$petta_exec:&self'] in
%place and the module's own predicates still answered], so recovering a cache
%fact a rolled-back transaction erased costs one redundant set and no repair,
%the same shape ensure_native_storage_module_locked/2 uses above.
%asserta, so the facts stay in front of the rule above and a known space never
%reaches it. Re-entered when a rolled-back transaction erased the fact and left
%the module based: set_module/1 is idempotent, so the repair is one redundant
%set rather than a special case, which is the shape
%ensure_native_storage_module_locked/2 uses.
ensure_metta_exec_module_locked(Space, Module) :-
    metta_exec_module_known(Space, Module), !.
ensure_metta_exec_module_locked(Space, Module) :-
    metta_exec_module_base(Space, Base),
    petta_capture_default_imports(Module),
    set_module(Module:base(Base)),
    petta_refresh_repaired_shadow_imports(Module),
    assertz(metta_exec_module_known(Space, Module)),
    protect_engine_emitted(Module).

%A compiled call keeps the procedure identity it resolved while a local
%shadow existed. SWI's default-module walk is deliberately dynamic for a
%fresh lookup, but abolish/1 does not retarget that already-compiled call: the
%old identity raises existence_error while predicate_property/2 on the same
%qualified head reports imported_from/1 and a direct call reaches the parent.
%import/1 is SWI's supported interface for dynamically created modules, and
%turns that same identity into a weak import. It is installed only for the
%one local predicate being removed, not for every function visible to a
%space. A later local definition removes the repair first, because asserting
%through an explicit import would otherwise write into its source module
%[source: SWI-Prolog Reference Manual, import/1 and abolish/1;
% commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_abolish_local_predicate(Module, Name, Arity) :-
    catch(abolish(Module:Name/Arity), _, true),
    petta_restore_inherited_predicate(Module, Name, Arity).

%A $-prefixed name is SWI or engine bookkeeping, never a written MeTTa
%function ($x is variable syntax), so the shadow repair does not manage it at
%all: materializing an import for tabling's $table_mode/3, whether its next
%resolution came from system or from the engine's own tabled predicates in
%user, blocked SWI from defining that module's local tabling state
%('No permission to redefine built-in $table_mode/3')
%[tested: test_tabling_control; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_restore_inherited_predicate(_, Name, _) :-
    sub_atom(Name, 0, 1, _, '$'),
    !.
petta_restore_inherited_predicate(Module, Name, Arity) :-
    retractall('$petta_repaired_shadow_import'(Module, Name, Arity, _)),
    functor(Head, Name, Arity),
    (   predicate_property(Module:Head, imported_from(Source)),
        Source \== system,
        \+ predicate_property(Module:Head, built_in),
        catch(Module:import(Source:Name/Arity), _, fail)
    ->  assertz('$petta_repaired_shadow_import'(Module, Name, Arity, Source))
    ;   true
    ).

%Calling an inherited predicate can materialize a weak import even when the
%space never defined that name.  A pooled execution module keeps the import
%after its space life ends, while its next life may name a different parent.
%Capture only imports whose source belongs to the standing default-module
%chain: explicit engine imports live outside that chain and protect_engine_emitted/1
%owns them.  The ordinary repair pass below then abolishes the old link after
%set_module/1 changes the base and re-imports the name from the new chain.
%[tested: test_a_recycled_child_name_may_choose_a_different_parent and
%filereader_import_lifecycle:
%a_repaired_shadow_import_follows_a_recycled_modules_new_parent;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_capture_default_imports(Module) :-
    (   current_module(Module)
    ->  findall(Name-Arity-Source,
                ( current_predicate(Module:Name/Arity),
                  %system sits on every default chain, so without these three
                  %filters the capture swept SWI's own bookkeeping ($table_mode
                  %and friends) into the repair set, and re-importing a system
                  %predicate blocked tabling from defining its local state:
                  %'No permission to redefine built-in $table_mode/3'
                  %[tested: test_tabling_control; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
                  \+ sub_atom(Name, 0, 1, _, '$'),
                  functor(Head, Name, Arity),
                  predicate_property(Module:Head, imported_from(Source)),
                  Source \== Module,
                  Source \== system,
                  \+ predicate_property(Module:Head, built_in),
                  default_module(Module, Source) ),
                Imports0),
        sort(Imports0, Imports),
        forall(member(Name-Arity-Source, Imports),
               (   '$petta_repaired_shadow_import'(Module, Name, Arity, _)
               ->  true
               ;   assertz('$petta_repaired_shadow_import'(Module, Name,
                                                           Arity, Source)) ))
    ;   true
    ).

%A pooled module may acquire a different parent in its next life. Explicit
%imports outlive set_module/1, so each repair is rebound after the new base is
%set and before any code is compiled in that life. The marker set contains
%only names whose own shadow has needed this repair. It remains dormant while
%a new local definition owns the name, so a failed transactional or source
%load can restore the inherited link after rolling that definition back. This
%keeps the repair dependency-directed rather than copying a parent's interface
%into every child [tested:
%test_a_recycled_child_name_may_choose_a_different_parent; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_refresh_repaired_shadow_imports(Module) :-
    findall(Name-Arity,
            '$petta_repaired_shadow_import'(Module, Name, Arity, _),
            PIs0),
    sort(PIs0, PIs),
    forall(member(Name-Arity, PIs),
           ( functor(Head, Name, Arity),
             (   predicate_property(Module:Head, imported_from(_))
             ->  catch(abolish(Module:Name/Arity), _, true)
             ;   true
             ),
             petta_restore_inherited_predicate(Module, Name, Arity) )).

%Called by the one ordinary equation/lambda assertion door. A repaired weak
%import must be removed before assertz/2, or SWI follows the link and appends
%the new clause to the ancestor rather than creating the requested local
%shadow. The dependency row deliberately stays: it is dormant while the local
%clause exists and is the rollback receipt that re-arms inheritance if a later
%step of this load fails [tested:
%filereader_import_lifecycle:
%a_failed_local_redefinition_restores_the_repaired_inherited_call;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_prepare_local_predicate(Module, Clause) :-
    ( Clause = (Head :- _) -> true ; Head = Clause ),
    functor(Head, Name, Arity),
    (   '$petta_repaired_shadow_import'(Module, Name, Arity, _),
        petta_existing_import(Module, Head, _)
    ->  catch(abolish(Module:Name/Arity), _, true)
    ;   true
    ).

%Before a definition registers itself as local, the registry indexes can
%distinguish an inherited name from a fresh one without asking SWI to resolve
%every fresh predicate through the module chain. Only an inherited name that
%already has a materialized import needs the weak-link repair. Public atom
%addition calls this before opening its transaction; the compiler repeats it
%so source-loader and generated-clause doors share the same rule.
petta_prepare_function_predicate(Module, Name, Arity) :-
    (   fun_in(Module, Name)
    ->  true
    ;   petta_may_inherit_function(Module, Name),
        functor(Head, Name, Arity),
        petta_existing_import(Module, Head, Source),
        \+ seam:engine_emitted(Name/Arity)
    ->  catch(abolish(Module:Name/Arity), _, true),
        (   '$petta_repaired_shadow_import'(Module, Name, Arity, _)
        ->  true
        ;   assertz('$petta_repaired_shadow_import'(Module, Name, Arity,
                                                    Source))
        )
    ;   true
    ).

%fun_scoped/1 is the process-wide summary of definitions outside &self;
%fun_in(Self, Name) is the shared tier that deliberately does not set that
%summary; and builtin_fun/1 is the engine tier. A sibling-only fun_scoped/1
%hit is harmless because petta_existing_import/3 below still requires an
%actual import in this module. Fresh source names miss these indexed facts and
%avoid the recursive fun_here_in/2 walk entirely.
petta_may_inherit_function(Module, Name) :-
    (   fun_scoped(Name)
    ->  true
    ;   metta_self_module(Self), Module \== Self, fun_in(Self, Name)
    ->  true
    ;   builtin_fun(Name)
    ).

%predicate_property/2 resolves missing predicates through the whole default
%chain and autoloader.  The assertion door needs the narrower question "does
%this module already hold an import link?".  These are the same two primitives
%SWI's own autoload registry uses before inspecting its imported attribute, so
%a fresh function name stays an indexed miss instead of paying a module walk
%for every equation in a source load [source: SWI-Prolog
%boot/autoload.pl:1061-1070; measured: source-load 1653096 to 1647100;
%command=python bench.py --counter-only source-load; fixture=1000 fresh
%equations; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_existing_import(Module, Head, Source) :-
    '$c_current_predicate'(_, Module:Head),
    '$get_predicate_attribute'(Module:Head, imported, Source).

%Repair receipts survive both kinds of rollback used by the loader: native
%transaction rollback and the first-load reference sweep. A local clause means
%the dependency is dormant; otherwise repeating import/1 revives the exact
%procedure identity even when a fresh default-module lookup already finds the
%right ancestor [tested:
%a_failed_local_redefinition_restores_the_repaired_inherited_call;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_repair_shadow_imports :-
    findall(Module-Name-Arity,
            '$petta_repaired_shadow_import'(Module, Name, Arity, _),
            Dependencies0),
    sort(Dependencies0, Dependencies),
    forall(member(Module-Name-Arity, Dependencies),
           petta_repair_shadow_import(Module, Name, Arity)).

petta_repair_shadow_import(Module, Name, Arity) :-
    functor(Head, Name, Arity),
    (   predicate_property(Module:Head, number_of_clauses(Clauses)),
        \+ predicate_property(Module:Head, imported_from(_)),
        Clauses > 0
    ->  true
    ;   catch(abolish(Module:Name/Arity), _, true),
        petta_restore_inherited_predicate(Module, Name, Arity)
    ).

%Bind the engine's own emitted goals into this module so a MeTTa equation
%cannot take one over. See seam:engine_emitted/1 (engine/translator.pl) for what
%that means and why an import rather than a guard.
%
%The export half is what keeps it quiet: import/1 warns when the source module
%does not export the name, and the engine's module has no export list at all.
%current_predicate/1 guards the order: this runs for &self's module at LOAD,
%before engine/duals.pl is consulted, so the one predicate that file emits is not
%there yet and the initialization below sweeps it in afterwards.
%A NAME ADDED TO THE EMITTED SET AFTER A SPACE EXISTS is the case that has to
%be safe, and it is the disease Logtalk's module critique names: "any update
%that strictly adds new exported predicates has the potential to break existing
%applications". A space that already defines the new name is a genuine
%collision, and SWI reports it -- import/1 raises permission_error(import_into,
%...) with the context `name clash` and leaves the space's own definition
%standing. Left at that, the addition is settled by which import happened
%first: the space keeps its function, the engine's emitted goal is captured in
%that space's compiled bodies, and nothing says so. So it is REFUSED here
%instead, in the vocabulary of the two parties that collided
%[tested: test_adding_an_engine_export_changes_no_spaces_answers].
protect_engine_emitted(Module) :-
    petta_engine_module(Engine),
    forall(( seam:engine_emitted(PI), current_predicate(Engine:PI) ),
           ( Engine:export(PI), Module:import(Engine:PI) )).

refuse_engine_export_collision(Engine, Module, Culprit) :-
    ( Culprit = _:Name/Arity -> true ; Culprit = Name/Arity ),
    ( metta_module_space(Module, Space) -> true ; Space = Module ),
    InputArity is Arity - 1,
    throw(error(petta_engine_export_collision(Name, InputArity, Space, Engine),
                context(protect_engine_emitted/1,
                        'a name the engine emits collides with one this space \c
                         already defines'))).

prolog:error_message(petta_engine_export_collision(Name, Arity, Space, Engine)) -->
    [ '~w with ~w arguments is a name ~w now compiles into function bodies, \c
       and ~w already defines a function of that name.'-[Name, Arity, Engine, Space], nl,
      '  the two cannot both have it: importing the engine\'s would capture \c
       every call ~w makes to its own function, and leaving ~w\'s would capture \c
       the engine\'s goal in this space\'s compiled clauses. Rename one of \c
       them.'-[Space, Space] ].

%Every module that already exists, which at boot is &self's. Called from
%engine/metta.pl's own initialization rather than from one here, and BEFORE the
%prelude compiles: an initialization/1 goal runs after the file it appears in
%finishes, so one here would run before engine/metta.pl had defined half the
%names above, and initialization goals do not reliably order against each
%other either [source: engine/metta.pl's own note on that].
%The guard lives HERE and not in protect_engine_emitted/1 above, because this
%is the only sweep that can collide. A module being BUILT is empty, and the
%re-entry that repairs a rolled-back transaction re-imports names it already
%holds, which SWI accepts; a name that a space already defines can only arrive
%by the emitted set GROWING after that space had functions, which is this
%sweep. It is also where the cost would be felt: one catch per space-module
%build moved five benchmarks, and one per re-sweep moves none
%[measured 2026-08-21: a catch per emitted name costs alpha-unique,
%annotated-relation and file-load 52 inferences each, an inlined one 26, one per
%space build 5 to 11 on file-load, handle-round-trip and save-load-metta, and
%this leaves all 34 at their pins].
%
%SWI's own error carries both parties, so nothing is lost by catching once: it
%names the predicate indicator that was refused and the module it was refused
%into.
protect_metta_exec_modules :-
    petta_engine_module(Engine),
    refuse_unreachable_engine_emitted(Engine),
    catch(forall(metta_exec_module_known(_, Module),
                 protect_engine_emitted(Module)),
          error(permission_error(import_into(Target), procedure, Culprit), _),
          refuse_engine_export_collision(Engine, Target, Culprit)).

%A declared name the engine module cannot SEE is the other way the protection
%can fail, and protect_engine_emitted/1 above cannot be the one to say so: its
%current_predicate/1 guard is load-order tolerance, because &self's module is
%built before engine/duals.pl is consulted and that file's emitted goals do not
%exist yet. So the completeness question belongs here, at the sweep that runs
%once everything is loaded and again whenever the set grows. Left as a silent
%skip it costs an existence_error at the first call of whatever form emits the
%goal, in whichever space happens to reach it first, with nothing connecting
%that error to the declaration [measured 2026-08-22: four such names after the
%subsystem cuts, one of which -- petta_verified_specialization/2 behind
%(pragma! verify-specializations true) -- no test in the tree reached].
%Once per sweep rather than once per space build, which is the shape the
%benchmark note above says costs nothing.
refuse_unreachable_engine_emitted(Engine) :-
    forall(seam:engine_emitted(PI),
           (   current_predicate(Engine:PI)
           ->  true
           ;   throw(error(petta_engine_emitted_unreachable(PI, Engine),
                           context(protect_metta_exec_modules/0,
                                   'a declared emitted goal is not reachable \c
                                    from the engine module')))
           )).

prolog:error_message(petta_engine_emitted_unreachable(Name/Arity, Engine)) -->
    [ '~w is declared in seam:engine_emitted/1 and ~w cannot see it, so no \c
       space module can either.'-[Name/Arity, Engine], nl,
      '  every compiled body holding that goal would raise existence_error at \c
       its first call. Export ~w from the subsystem module that defines it, or \c
       remove the declaration.'-[Name/Arity] ].

%The inverse of space_module/2. It used to be written out by hand in four
%places, three of them outside this file, each as
%`Module == user -> Space = '&self' ; Space = Module`
%[source: ai-phase11-module-survey.md section 1.3]. The exact forward-map
%cache replaces all four and supports both atomic and canonical parametric
%names. It FAILS on a module that is not a space's, because every caller has
%one in hand and a silent pass-through would answer a module name where a
%space name was asked for
%[tested: spaces_execution_modules:the_module_to_space_map_is_the_inverse].
metta_module_space(Module, Space) :-
    metta_exec_module_known(Space, Module).

restricted_core_module('$petta_restricted:core').

space_capability(file).
space_capability(process).
space_capability(network).

%A capability is attached to the written operation, not to a Prolog helper it
%happens to call. Names absent from this table are part of the curated compute
%surface; raw Prolog goals take the sandbox path below.
space_operation_capability('exists_file', file).
space_operation_capability('import!', file).
space_operation_capability(library, file).
space_operation_capability('readln!', process).
space_operation_capability('read-form!', process).
space_operation_capability('parse-command', process).
space_operation_capability(argv, process).
space_operation_capability('new-space', process).
space_operation_capability(evalc, process).
space_operation_capability(metta, process).
space_operation_capability(callPredicate, process).
space_operation_capability(assertaPredicate, process).
space_operation_capability(assertzPredicate, process).
space_operation_capability(retractPredicate, process).
space_operation_capability(import_prolog_function, process).
space_operation_capability(check_prolog_function_names, process).
space_operation_capability(import_prolog_functions, process).
space_operation_capability(import_prolog_functions_from_file, file).
space_operation_capability(import_prolog_functions_from_file_pred, file).
space_operation_capability(import_prolog_functions_from_module, process).
space_operation_capability(import_prolog_functions_from_module_pred, process).
space_operation_capability(register_metta_library_path, file).
space_operation_capability('git-import!', network).

restricted_profile_name([], Core) :- !, restricted_core_module(Core).
restricted_profile_name(Grants, Module) :-
    atomic_list_concat(Grants, '+', Suffix),
    atom_concat('$petta_restricted:', Suffix, Module).

ensure_restricted_profile(Grants, Module) :-
    restricted_profile_known(Grants, Module),
    !.
ensure_restricted_profile(Grants, Module) :-
    restricted_profile_name(Grants, Module),
    ensure_restricted_core,
    (   Grants == []
    ->  true
    ;   restricted_core_module(Core),
        set_module(Module:base(Core)),
        forall(member(Capability, Grants),
               publish_restricted_capability(Module, Capability))
    ),
    assertz(restricted_profile_known(Grants, Module)).

ensure_restricted_core :-
    restricted_profile_known([], _),
    !.
ensure_restricted_core :-
    pin_restricted_dispatch_names,
    restricted_core_module(Core),
    set_module(Core:base(none)),
    forall(restricted_core_predicate(PI), publish_restricted_pi(Core, PI)),
    publish_restricted_denials(Core),
    assertz(restricted_profile_known([], Core)).

%The reducer's existing scoped-name index decides whether a call must retain
%the current execution module. Capability-bearing names are module-sensitive
%for the same reason as a user definition: a restricted profile may publish
%or withhold them. Pinning only those names preserves reduce/3's ordinary
%base-tier path while a computed restricted call reaches the curated module's
%grant or refusal [tested:
%test_a_restricted_space_cannot_reach_what_its_base_does_not_publish;
%commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
pin_restricted_dispatch_names :-
    forall(space_operation_capability(Name, _),
           (   fun_scoped(Name)
           ->  true
           ;   assertz(fun_scoped(Name))
           )).

restricted_dispatch_name(Name) :-
    restricted_profile_known([], _),
    space_operation_capability(Name, _).

%A denied operation is a local refusal in the curated core, not an import of
%the engine operation. A grant profile imports the permitted operation into
%the nearer profile module and therefore shadows this stub. The wrapper is
%built for each callable arity from the same capability table that builds the
%grant profiles, so literal and computed calls cannot disagree about the
%boundary [tested:
%test_a_restricted_space_cannot_reach_what_its_base_does_not_publish;
%commit=9a49e2f81bb8199c0284f8456e4b48c25a804371].
publish_restricted_denials(Core) :-
    forall(( space_operation_capability(Name, Capability),
             arity(Name, Arity),
             petta_engine_module(Engine),
             current_predicate(Engine:Name/Arity) ),
           publish_restricted_denial(Core, Engine, Name, Arity, Capability)).

publish_restricted_denial(Core, Engine, Name, Arity, Capability) :-
    functor(Head, Name, Arity),
    assertz(Core:(Head :-
        Engine:metta_require_current_capability(Name, Capability),
        Engine:Head)).

%Locally defined engine helpers are needed by compiled safe calls. Registered
%builtins imported from libraries are included separately. Capability-bearing
%names are withheld and published only by their grant profile.
restricted_core_predicate(Name/Arity) :-
    petta_engine_module(Engine),
    current_predicate(Engine:Name/Arity),
    functor(Head, Name, Arity),
    predicate_property(Engine:Head, defined),
    \+ predicate_property(Engine:Head, imported_from(_)),
    \+ space_operation_capability(Name, _).
restricted_core_predicate(Name/Arity) :-
    builtin_fun(Name),
    \+ space_operation_capability(Name, _),
    arity(Name, Arity),
    petta_engine_module(Engine),
    current_predicate(Engine:Name/Arity).

publish_restricted_capability(Module, Capability) :-
    forall(( space_operation_capability(Name, Capability),
             arity(Name, Arity),
             petta_engine_module(Engine),
             current_predicate(Engine:Name/Arity) ),
           publish_restricted_pi(Module, Name/Arity)).

publish_restricted_pi(Module, PI) :-
    petta_engine_module(Engine),
    PI = Name/Arity,
    functor(Head, Name, Arity),
    (   predicate_property(Engine:Head, imported_from(system))
    ->  true
    ;   Engine:export(PI),
        Module:import(Engine:PI)
    ).

%A parametric space is an entity identifier, not an expression to execute:
%one finite, ground list headed by a symbol. Validate the complete shape
%before asserting its registry fact or asking either module cache, so a bad
%name cannot reserve persistent SWI module state. Repeating the same creation
%is idempotent and never duplicates its reflected contract atom.
metta_declare_parametric_space(Space) :-
    metta_require_parametric_space_name(Space),
    with_mutex('$petta_metta_exec',
               metta_declare_parametric_space_locked(Space)).

metta_require_parametric_space_name(Space) :-
    (   acyclic_term(Space)
    ->  true
    ;   throw(error(type_error(acyclic_term, Space),
                    context('new-space',
                            'a parametric space name must be finite')))
    ),
    (   ground(Space)
    ->  true
    ;   throw(error(instantiation_error,
                    context('new-space',
                            'a parametric space name must be ground')))
    ),
    (   Space = [Family|_], atom(Family)
    ->  true
    ;   throw(error(domain_error(parametric_space_name, Space),
                    context('new-space',
                            'a parametric space name is a nonempty expression \c
                             headed by a symbol')))
    ).

metta_declare_parametric_space_locked(Space) :-
    (   space_parametric(Space)
    ->  true
    ;   transaction(( assertz(space_parametric(Space)),
                      metta_add_atom('&metta', [parametric, Space], _),
                      ensure_native_storage_module(Space, _),
                      space_module(Space, _) ))
    ).

metta_declare_restricted_space(Space, Grants0) :-
    metta_require_space_name('new-space', Space),
    must_be(list, Grants0),
    maplist(metta_require_space_capability, Grants0),
    sort(Grants0, Grants),
    with_mutex('$petta_metta_exec',
               metta_declare_restricted_space_locked(Space, Grants)).

metta_require_space_capability(Capability) :-
    (   space_capability(Capability)
    ->  true
    ;   throw(error(domain_error(space_capability, Capability),
                    context('new-space',
                            'capability must be file, process, or network')))
    ).

metta_declare_restricted_space_locked(Space, Grants) :-
    (   space_restricted(Space, Standing)
    ->  (   Standing == Grants
        ->  true
        ;   throw(error(petta_space_restriction_conflict(Space, Standing,
                                                          Grants), none))
        )
    ;   space_parent(Space, Parent)
    ->  throw(error(petta_space_model_conflict(Space, inherits(Parent),
                                                restricted(Grants)), none))
    ;   space_parent_child_used(Space)
    ->  throw(error(petta_space_restriction_after_use(Space), none))
    ;   ensure_restricted_profile(Grants, _),
        transaction(( assertz(space_restricted(Space, Grants)),
                      forall(member(Capability, Grants),
                             assertz(space_grant(Space, Capability))),
                      metta_add_atom('&metta', [restricted, Space], _),
                      forall(member(Capability, Grants),
                             metta_add_atom('&metta',
                                            [grants, Space, Capability], _)),
                      ensure_native_storage_module(Space, _),
                      space_module(Space, _) ))
    ).

metta_restricted_exec_module(Module, Space) :-
    metta_exec_module_known(Space, Module),
    space_restricted(Space, _).

metta_require_current_capability(Operation, Capability) :-
    current_metta_module(Module),
    (   metta_restricted_exec_module(Module, Space)
    ->  (   space_grant(Space, Capability)
        ->  true
        ;   throw(error(petta_space_capability_required(Space, Operation,
                                                         Capability), none))
        )
    ;   true
    ).

metta_require_space_update_capability(Operation, Target) :-
    current_metta_module(Module),
    (   metta_restricted_exec_module(Module, Space),
        Target \== Space
    ->  metta_require_current_capability(Operation, process)
    ;   true
    ).

metta_require_safe_goal(Goal) :-
    current_metta_module(Module),
    (   metta_restricted_exec_module(Module, _)
    ->  metta_require_restricted_safe_goal(Goal, Module)
    ;   true
    ).

metta_require_restricted_safe_goal(Goal, Module) :-
    callable(Goal),
    functor(Goal, Operation, _),
    (   raw_goal_capability(Operation, Capability)
    ->  metta_require_current_capability(Operation, Capability)
    ;   catch(sandbox:safe_goal(Module:Goal), _, fail)
    ->  true
    ;   metta_require_current_capability(Operation, process)
    ).

raw_goal_capability(Operation, Capability) :-
    space_operation_capability(Operation, Capability),
    !.
raw_goal_capability(open, file).
raw_goal_capability(close, file).
raw_goal_capability(read, file).
raw_goal_capability(write, file).
raw_goal_capability(delete_file, file).
raw_goal_capability(rename_file, file).
raw_goal_capability(make_directory, file).
raw_goal_capability(process_create, process).
raw_goal_capability(process_wait, process).
raw_goal_capability(shell, process).
raw_goal_capability(www_open_url, network).
raw_goal_capability(http_open, network).

restricted_callable_name(F) :- builtin_fun(F).

%Declare the one parent a space reads and executes through. The ordering is
%part of the contract: an identical declaration is idempotent, a conflicting
%one names both parents, a cycle is diagnosed before the less-specific
%already-used refusal, and only a fresh child reaches the transaction that
%lands the index, reflection atom and execution-module base together.
%[tested: test_a_child_space_reads_through_its_parent_and_writes_locally;
% commit=755330de329ece49eddcfb7d6db3061c3350a0ca]
metta_declare_space_parent(Child, Parent) :-
    metta_require_space_name('new-space', Child),
    metta_require_space_name('new-space', Parent),
    with_mutex('$petta_metta_exec',
               metta_declare_space_parent_locked(Child, Parent)).

metta_require_space_name(_, Space) :-
    petta_space_name(Space),
    !.
metta_require_space_name(Operation, Space) :-
    throw(error(type_error('SpaceType', Space),
                context(Operation, 'an inherited-space endpoint must be a space'))).

metta_declare_space_parent_locked(Child, Parent) :-
    (   space_parent(Child, Standing)
    ->  (   Standing == Parent
        ->  true
        ;   throw(error(petta_space_parent_conflict(Child, Standing, Parent),
                        none))
        )
    ;   space_restricted(Child, Grants)
    ->  throw(error(petta_space_model_conflict(Child, restricted(Grants),
                                                inherits(Parent)), none))
    ;   space_parent_cycle(Child, Parent)
    ->  throw(error(petta_space_parent_cycle(Child, Parent), none))
    ;   space_parent_child_used(Child)
    ->  throw(error(petta_space_parent_after_use(Child), none))
    ;   transaction(( assertz(space_parent(Child, Parent)),
                      metta_add_atom('&metta', [inherits, Child, Parent], _),
                      ensure_native_storage_module(Child, _),
                      space_module(Child, ChildModule),
                      space_module(Parent, ParentModule),
                      assertz(metta_exec_module_parent(ChildModule,
                                                       ParentModule)) ))
    ).

space_parent_cycle(Child, Parent) :-
    Child == Parent,
    !.
space_parent_cycle(Child, Parent) :-
    space_parent_reaches(Parent, Child, []).

space_parent_reaches(Space, Target, Seen) :-
    \+ memberchk(Space, Seen),
    space_parent(Space, Parent),
    (   Parent == Target
    ->  true
    ;   space_parent_reaches(Parent, Target, [Space|Seen])
    ).

space_parent_child_used(Child) :- metta_exec_module_known(Child, _), !.
space_parent_child_used(Child) :- native_storage_module_cache(Child, _), !.
space_parent_child_used(Child) :- seam:foreign_space(Child).

%Child first, then each ancestor. The seen list is an invariant guard against
%a corrupt or externally asserted relation; declarations refuse such cycles
%before they can enter this index.
space_read_chain(Space, Each) :-
    space_read_chain_(Space, [], Each).

space_read_chain_(Space, Seen, Each) :-
    \+ memberchk(Space, Seen),
    (   Each = Space
    ;   space_parent(Space, Parent),
        space_read_chain_(Parent, [Space|Seen], Each)
    ).

metta_assert_space_releasable(Space) :-
    (   space_parent(Child, Space)
    ->  throw(error(petta_space_parent_live_child(Space, Child), none))
    ;   true
    ).

%A released name is allowed to acquire a different parent in its next life.
%Clear while the standing base is still known, then remove the relationship
%and its reflected atom transactionally and forget the module mapping so the
%next space_module/2 call sets the persistent SWI module's new base.
metta_release_space(Space) :-
    with_mutex('$petta_metta_exec',
               ( metta_assert_space_releasable(Space),
                 metta_host_clear_space(Space),
                 transaction(( metta_forget_space_parent(Space),
                               metta_forget_space_restriction(Space),
                               metta_forget_parametric_space(Space),
                               metta_forget_world_coverage(Space),
                               metta_forget_exec_module_parent(Space),
                               retractall(metta_exec_module_known(Space, _)),
                               retractall(native_storage_module_cache(Space, _)) ))
               )).

metta_forget_exec_module_parent(Space) :-
    (   metta_exec_module_known(Space, Module)
    ->  retractall(metta_exec_module_parent(Module, _))
    ;   true
    ).

metta_forget_space_parent(Child) :-
    (   retract(space_parent(Child, Parent))
    ->  metta_remove_atom('&metta', [inherits, Child, Parent], _)
    ;   true
    ).

metta_forget_space_restriction(Space) :-
    (   retract(space_restricted(Space, Grants))
    ->  forall(member(Capability, Grants),
               ( retractall(space_grant(Space, Capability)),
                 metta_remove_atom('&metta',
                                   [grants, Space, Capability], _) )),
        metta_remove_atom('&metta', [restricted, Space], _)
    ;   true
    ).

metta_forget_parametric_space(Space) :-
    (   space_parametric(Space)
    ->  metta_remove_atom('&metta', [parametric, Space], _),
        retractall(space_parametric(Space))
    ;   true
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_space_parent_conflict(Child, Standing, Requested)) -->
    [ '~w already inherits from ~w, so it cannot also inherit from ~w; a \c
       space has one parent fixed before first use'-[Child, Standing,
                                                     Requested] ].
prolog:error_message(petta_space_parent_cycle(Child, Parent)) -->
    [ 'making ~w inherit from ~w would create an inheritance cycle; space \c
       reads and execution bases must form an acyclic parent chain'-[Child,
                                                                      Parent] ].
prolog:error_message(petta_space_parent_after_use(Child)) -->
    [ '~w has already been created, written, executed, or registered; declare \c
       its parent with (new-space ~w (inherits <parent>)) before first use'-[
       Child, Child] ].
prolog:error_message(petta_space_parent_live_child(Parent, Child)) -->
    [ '~w cannot be dropped while live child ~w inherits from it; drop the \c
       child first so its relationship cannot follow a recycled parent name'-[
       Parent, Child] ].
prolog:error_message(petta_space_restriction_conflict(Space, Standing,
                                                       Requested)) -->
    [ '~w is already restricted with grants ~q, so it cannot be redeclared \c
       with grants ~q; restriction is fixed at creation'-[Space, Standing,
                                                           Requested] ].
prolog:error_message(petta_space_restriction_after_use(Space)) -->
    [ '~w has already been created, written, executed, or registered; declare \c
       it restricted with new-space before first use'-[Space] ].
prolog:error_message(petta_space_model_conflict(Space, Standing, Requested)) -->
    [ '~w already has space model ~q, so it cannot also use ~q; inheritance \c
       and restriction are alternative execution bases'-[Space, Standing,
                                                           Requested] ].
prolog:error_message(petta_space_capability_required(Space, Operation,
                                                      Capability)) -->
    [ '~w cannot run ~w because its restricted base does not publish the ~w \c
       capability; grant it explicitly when the space is created'-[
       Space, Operation, Capability] ].

%&self's execution module exists from load, the way its storage module does,
%so nothing has to create it on a first write and metta_self_module/1
%(engine/metta.pl) names a module that is already based.
:- space_module('&self', _).

%Whether anything still holds a clause for a function, which decides whether
%removing an equation forgets the NAME as well. Two sources, and `user` used to
%stand for both of them at once: a space's own module, and the ENGINE's, since
%a builtin goes on meaning the builtin after a space's equation for it is
%removed.
%
%compiled_function_name/2 rather than the written name, which is the same fix
%module_owns_function/2 below already carries: `get-type` compiles to
%get_type_rule/2, so asking for a predicate called `get-type` found the
%ENGINE's get-type/2 and answered "still defined" for every space and every
%state of the rules. Removing one of two scoped get-type rules then wiped
%fun_in/2 for the name and the surviving rule stopped answering
%[tested: spaces_type_extensions:removing_one_rule_keeps_the_other_visible].
%number_of_clauses/1 before clause/3, which is the guard tracer.pl already
%carries and for the same reason: clause/3 REFUSES a predicate it cannot show,
%raising permission_error(access, private_procedure, _) rather than failing,
%and the engine's module holds plenty of those. Removing an equation for any
%system-builtin name reached one and raised out of remove-atom
%[measured 2026-08-19: with_output_to/2]. The property is true for exactly the
%predicates clause/3 accepts [source: engine/tracer.pl, metta_trace_target/1
%measured 2026-08-16].
%A BUILTIN is defined by the engine and by no equation, so no removal can
%undefine it. Without this, a space that extended an engine operation by
%writing an equation for its name took the ENGINE's operation with it when the
%equation went: the compiled-clause probe below is the only thing that was
%asked, a builtin has no compiled clause of that shape, so `fun/1` and the
%name-wide registers were retracted and `!(get-type 1)` answered
%`(get-type 1)` unreduced for the rest of the process. Removing an equation
%for `match`, `+` or any other builtin name did the same
%[tested: builtin_survives_equation_removal].
function_still_defined(F) :- builtin_fun(F), !.
function_still_defined(F) :- compiled_function_name(F, Predicate),
                             ( fun_in(Module, F) ; petta_engine_module(Module) ),
                             compiled_predicate_arity(F, Module, Predicate, Arity),
                             functor(Head, Predicate, Arity),
                             predicate_property(Module:Head, number_of_clauses(_)),
                             clause(Module:Head, _, _),
                             !.

%Whether this module itself holds a clause for a function. Inherited clauses
%do not count: clause/3 sees user's clauses through module inheritance, and
%counting those would keep a module's claim alive on another space's strength.
module_owns_function(Module, F) :- compiled_function_name(F, Predicate),
                                   compiled_predicate_arity(F, Module, Predicate,
                                                            Arity),
                                   functor(Head, Predicate, Arity),
                                   predicate_property(Module:Head,
                                                      number_of_clauses(_)),
                                   clause(Module:Head, _, Ref),
                                   clause_property(Ref, module(Module)),
                                   !.

%Which arities to try for F's compiled predicate, through the arity registry
%rather than by enumeration. current_predicate/1 with an UNBOUND arity walks the
%module's whole predicate table: 14.6 microseconds over 1,000 predicates and
%410.9 over 64,000, against a flat 0.25 fully bound, and both callers above run
%once per equation REMOVED, so removing equations from a large program cost time
%that grew with the program [measured 2026-08-24].
%
%arity/2 holds the compiled arity of every name the engine registered, which is
%the same pattern publish_restricted_denials/1 above already uses, and both
%callers run before unregister_fun_everywhere/1 retracts it. A name the registry
%does not know still falls back to the enumeration, so this cannot report a
%predicate absent that the scan would have found.
compiled_predicate_arity(F, Module, Predicate, Arity) :-
    %The question is about the compiled predicate, and a definition that has
    %arrived without being translated has none yet. current_predicate/1 is not
    %a call, so the undefined-predicate net does not fire for it.
    metta_ensure_compiled(F),
    (   arity(F, _)
    ->  arity(F, Arity),
        current_predicate(Module:Predicate/Arity)
    ;   current_predicate(Module:Predicate/Arity)
    ).

%The UNIT value, not true. `add-atom` is typed `(-> spaceType Atom (->))` and
%`(->)` IS the unit type, which the language also says in prose: "bind! returns
%the unit value () similar to println! or add-atom"
%[source: the language's Working with spaces].
%
%This reverses a deliberate earlier translation, recorded in
%ai-todo-fast-libraries.md F11.3 as "HE's unit result `(->)` is PeTTa's `Bool`,
%because every one of those operations answers `true`". That reasoning had the
%direction backwards: it read the type off the implementation instead of
%correcting the implementation to the type. The engine was already inconsistent
%with itself, `trace!` answering `()` beside these answering `true`, and the
%arbiter's spaces corpus disagreed on every file
%[tested: an_effectful_operation_answers_unit].
%The write itself decides whether the first argument is a space: a name that is
%not one reaches no storage module, so nothing is written and this refuses.
%Asking BEFORE the write cost an inference on every add
%[measured 2026-08-20: register-op +200], and asking after costs nothing
%because the failure branch runs only when the write did not happen. A write
%that failed for its own reasons, a foreign provider refusing one, still fails
%without an answer, which is what it did before.
'add-atom'([Family|Parameters], Term, Result) :-
    Space = [Family|Parameters],
    space_parametric(Space),
    !,
    (   metta_add_atom(Space, Term, _)
    ->  Result = []
    ;   fail
    ).
'add-atom'(Space, Term, Result) :-
    (   atom(Space), metta_add_atom(Space, Term, _)
    ->  Result = []
    ;   petta_space_name(Space)
    ->  fail
    ;   space_argument_error('add-atom', [Space, Term], Result)
    ).

%Adding an atom is two independent decisions: WHERE it is stored, which is a
%property of the space, and WHAT the engine must do because of what the atom
%MEANS, which is a property of the atom. This predicate dispatched on storage
%first, mixing them, and three defects came out of that one shape:
%
%  - a (: f T) added to a FOREIGN space never recompiled f's call sites,
%    because the foreign clause cut before the declaration clause could run.
%    The same program answered ((+ 1 2)) in a native named space and (3) in a
%    foreign one [measured 2026-08-16].
%  - metta_add_atoms/2 had to re-derive which atoms carry work and looked only
%    for equations, so a BATCHED declaration skipped the recompile the same
%    atom performs alone: m.add(decl) answered (+ 1 2) and m.add(decl, other)
%    answered 3 [measured 2026-08-16].
%  - the Python shim re-derived it a third time and routed MORK's batch around
%    this predicate entirely, so an equation added to a space that holds rules
%    was stored inert whenever it arrived with any other atom
%    [measured 2026-08-16].
%
%So MEANING is decided first and storage second, which is the whole of the fix.
%The order is the fix: a foreign space's declaration now reaches the clause that
%recompiles, because nothing cuts in front of it any more.
%
%The tests stay in the clause HEADS rather than moving to a classifier the batch
%path could also call, and that is measured rather than tidy. This is the
%hottest write path in the engine, and routing it through
%atom_effect/2 + add_with_effect/3 cost three inferences of every twelve per
%atom, 25%, which the save-load benchmarks caught at once [measured 2026-08-16:
%12.0012 to 15.0012 inferences per add over 20,000 adds]. atoms_store_only/1
%below repeats these two tests for the batch path, and the two are held together
%by a differential rather than by sharing code: every shape is added alone and
%in a batch and the resulting state compared
%[tested: spaces_batch_is_only_a_transport].
metta_add_atom(Space, Term, true) :- Term = [=, [FAtom|W], _], !,
                                     must_be(atom, FAtom),
                                     add_equation(Space, Term, FAtom, W).
%A scalar equality changes whether an eager symbol position compiles to a
%literal or a reduction step.  Its stored callers already publish symbol
%mentions through the support graph, so the ordinary change announcement
%rebuilds precisely those callers and evicts matching runnable templates.
%[tested: conformance2:symbol_arguments_evaluate_for_declared_and_undeclared_functions;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_add_atom(Space, Term, true) :-
    Term = [=, Scalar, _],
    atom(Scalar),
    !,
    store_atom(Space, Term),
    space_module(Space, Module),
    announce_function_changed(Module, Scalar).
%Type declarations are a multimap because distinct arrows and distinct data
%types are meaningful. A variant-identical second row is not: every type walk
%would enumerate it again. A direct source add is idempotent and warns while
%leaving the first row in place; the public batch preflight below stays strict
%because accepting one duplicate in a batch would make that transport differ
%from its promised all-or-nothing write. Host registrations that need exclusive
%ownership use petta_py_add_strict_declaration/2 in shim.pl.
metta_add_atom(Space, Term, true) :-
    Term = [':', _, _],
    existing_duplicate_declaration(Space, Term, First),
    !,
    print_message(warning, petta_duplicate_declaration(Space, Term, First)).
% DontEvalType changes how every arrow parameter naming this type compiles,
% even when the type symbol is not itself a function. Store first so repairs
% observe the new marker, then invalidate its module-qualified support root.
metta_add_atom(Space, Term, true) :-
    Term = [':', Type, 'DontEvalType'],
    atom(Type),
    !,
    (   Space == '&self', fun(Type)
    ->  retract_prelude_declarations(Type)
    ;   true
    ),
    store_atom(Space, Term),
    space_module(Space, DeclModule),
    ( fun(Type) -> announce_function_changed(DeclModule, Type) ; true ),
    type_marker_changed(DeclModule, Type).
%A type declaration decides how a call site compiles, most sharply for an Atom
%parameter, which is what makes a control form possible: (: f (-> Atom
%%Undefined%)) is the difference between the argument arriving evaluated and
%arriving as written. A call site compiled before the declaration landed kept
%evaluating the argument for ever, so the same call written two ways in one
%program behaved differently and nothing said why. The engine already knows how
%to recompile what a change made stale; the declaration route simply never told
%it [tested: a_late_type_declaration_repairs_its_call_sites].
metta_add_atom(Space, Term, true) :- Term = [':', FAtom, _], atom(FAtom),
                                     fun(FAtom), !,
                                     %Read BEFORE anything is stored or evicted,
                                     %because it is the state the already-compiled
                                     %clauses were built under.
                                     result_finality(FAtom, Before),
                                     %A declaration written into &self replaces the
                                     %prelude's for the same name, the user-wins rule
                                     %evict_prelude_definition/1 documents; the
                                     %recompile below then re-reads call sites under
                                     %the user's masking.
                                     (   Space == '&self'
                                     ->  retract_prelude_declarations(FAtom)
                                     ;   true
                                     ),
                                     store_atom(Space, Term),
                                     space_module(Space, DeclModule),
                                     announce_declaration_changed(DeclModule,
                                                                  FAtom, Before).
metta_add_atom(Space, Term, true) :- seam:foreign_space(Space), !,
                                     foreign_write(Space, add,
                                                   seam:foreign_add(Space, Term)).
metta_add_atom(Space, Term, true) :- add_sexp(Space, Term, Ref),
                                     record_source_atom_assertion(Ref).

%A variant of Term must UNIFY with a fresh copy of Term, so asking the store
%for that copy decides the common case, a declaration nothing else in the space
%matches, through the indexed read. The scan below is what the answer costs
%when something does match, and it stays because the shape a variant test
%needs is not the shape a store read gives: a read unifies its pattern with
%the stored atom, so a stored (: $x Number) comes back as the probe
%(: foo Number) and reads as a variant of it, which it is not. The scan
%enumerates with an unbound pattern, where every atom arrives as written.
%Without the probe every declaration added cost a walk of the whole space, so
%a program's declarations cost time quadratic in its size: adding 200 of them
%ran 79,600 variant tests and adding 800 ran 1,278,400, sixteen times the
%tests for four times the program.
existing_duplicate_declaration(Space, Term, First) :-
    \+ seam:foreign_space(Space),
    copy_term(Term, Probe),
    once(get_native_atom(Space, Probe)),
    stored_variant_declaration(Space, Term, First).

stored_variant_declaration(Space, Term, First) :-
    get_native_atom(Space, Stored),
    Stored =@= Term,
    !,
    First = Stored.

first_variant_declaration(Term, [First|_], First) :- Term =@= First, !.
first_variant_declaration(Term, [_|Declarations], First) :-
    first_variant_declaration(Term, Declarations, First).

ensure_new_batch_declaration(Space, Term, Earlier) :-
    (   existing_duplicate_declaration(Space, Term, First)
    ->  throw(error(petta_duplicate_declaration(Space, Term, First), none))
    ;   first_variant_declaration(Term, Earlier, First)
    ->  throw(error(petta_duplicate_declaration(Space, Term, First), none))
    ;   true
    ).

batch_declarations_unique(Space, Terms) :-
    batch_declarations_unique(Space, Terms, []).

batch_declarations_unique(_, [], _).
batch_declarations_unique(Space, [Term|Terms], Earlier) :-
    (   Term = [':', _, _]
    ->  ensure_new_batch_declaration(Space, Term, Earlier),
        Next = [Term|Earlier]
    ;   Next = Earlier
    ),
    batch_declarations_unique(Space, Terms, Next).

%Whether every atom in a batch stores and does nothing else, which is the only
%kind a bulk crossing may carry. It repeats metta_add_atom/3's first two clause
%heads, and they are repeated rather than shared for the reason given there.
%The same traversal preflights otherwise-plain type declarations against both
%the space and earlier batch members. This keeps the one-crossing fast path
%without letting two declarations bypass the single-atom refusal.
%
%Written as clause heads and not as a test called per atom, which is measured:
%head unification costs no inference where a call costs one, and over a whole
%batch that is the difference between one and two per atom [measured 2026-08-16:
%8.00 back to 7.00 inferences per atom over 20,000]. Cut-then-fail so the scan
%stops at the first atom that carries work.
atoms_store_only(Space, Terms) :- atoms_store_only(Space, Terms, []).

atoms_store_only(_, [], _).
atoms_store_only(_, [[=|_]|_], _) :- !, fail.
atoms_store_only(_, [[':', _, 'DontEvalType']|_], _) :- !, fail.
atoms_store_only(_, [[':', FAtom, _]|_], _) :-
    atom(FAtom), fun(FAtom), !, fail.
atoms_store_only(Space, [Term|Terms], Earlier) :-
    Term = [':', _, _], !,
    ensure_new_batch_declaration(Space, Term, Earlier),
    atoms_store_only(Space, Terms, [Term|Earlier]).
atoms_store_only(Space, [_|Terms], Earlier) :-
    atoms_store_only(Space, Terms, Earlier).

%Where an atom goes. A foreign space's provider owns its storage entirely; a
%native space's storage is the Prolog database.
store_atom(Space, Term) :- seam:foreign_space(Space), !,
                           foreign_write(Space, add,
                                         seam:foreign_add(Space, Term)).
store_atom(Space, Term) :- add_sexp(Space, Term, Ref),
                           record_source_atom_assertion(Ref).

%An equation is the one atom whose storage and meaning cannot be separated, so
%they are not: it compiles inside the transaction that stores it, wherever it is
%stored. Only the storage step differs between a native space and a foreign one.
%
%An equation in a foreign space used to be a silent lie: accepted, stored, and
%inert, so (only-foreign 21) answered itself where the identical shape in a
%native named space answered 42. In MeTTa a space is BOTH a data source and
%where the program lives, so accepting a rule that can never fire is the engine
%agreeing to something it will not do. A provider that holds rules declares the
%`rules` capability; one that does not is refused here, where the author can
%still act on it, rather than at the call that quietly answers itself much later
%[tested: adding_a_rule_to_a_ruleless_foreign_space_is_refused].
%
%It goes through the SAME compiler as a native equation, and the first attempt
%at this did not: it asserted one bridge clause per function that matched the
%space for (= (f Args) Body) at call time and reduced whatever came back.
%
%That is the naive reading of evaluation, and the language documents exactly why
%it falls short. Evaluating (only-a A) "can be thought of as execution of query
%(match &self (= (only-a A) $result) $result)", and then: "There is one
%difference. match produces the empty result in the second case, while the
%interpreter keeps this expression unreduced. The interpreter is performing some
%additional processing on top of such equality queries"
%[source: metta-lang.dev/docs/learn, Functions and unification].
%
%Three of those differences were live here. A body is evaluated FURTHER, so
%(= (bnest) (+ 1 (* 2 3))) raised "+: number expected, found (* 2 3)"; a
%bare-variable body must NOT be evaluated, so an Atom parameter came back
%reduced; and (if ...) evaluates only the branch it takes, so (= (loop) (loop))
%under an if would not have terminated. Every one is a rule the translator
%already implements [source: metta-lang.dev/docs/learn, Basic evaluation and
%Recursion and control].
%
%What the seam gives up by compiling at add time is an equation that appears in
%the space by some other door, MORK's own loader or an mm2-exec write: it is
%stored and inert, because nothing told the engine. That is the honest edge and
%it is narrower than a second evaluator that is wrong on every program above.
%A specialization is DERIVED: the specializer wrote it from this module's own
%equations and owns the name. An equation arriving for a derived name that is
%an ALPHA-DUPLICATE of one already stored carries nothing, and storing it a
%second time is what made a space stop reproducing itself: MeTTa.copy()
%enumerates a space and re-adds every atom into a fresh one, the clone
%re-derived the specialization while compiling the equation that triggered
%it, and the copied atom then landed on top, so a four-atom space cloned to
%five and answered its query twice [measured 2026-08-19]. The guard used to
%swallow by NAME alone, which was right while clones re-derived; with
%adoption the copied equations ARE the derived ones, and the name-only
%swallow ate every clause of a copied specialization that arrived after its
%sibling had been adopted, so a two-clause specialization cloned to one
%[measured 2026-08-20]. Only the true duplicate is swallowed now, and the
%probe runs only on derived-name adds, which are rare by construction
%[tested: a_copied_space_adopts_its_specializations_instead_of_duplicating].
add_equation(Space, Term, FAtom, _) :-
    space_module(Space, Module),
    ho_specialization(Module, _, FAtom),
    copy_term(Term, Probe),
    get_native_atom(Space, Stored),
    Stored = [=, [FAtom|_], _],
    Stored =@= Probe,
    !.
add_equation(Space, Term, FAtom, W) :-
    seam:foreign_space(Space), !,
    refuse_ruleless_equation(Space, Term),
    space_module(Space, Module),
    length(W, InputArity),
    PredArity is InputArity + 1,
    petta_prepare_function_predicate(Module, FAtom, PredArity),
    petta_add_function_transaction(provider, Space, Module, Term, FAtom, W).
add_equation(Space, Term, FAtom, W) :-
    space_module(Space, Module),
    ensure_native_storage_module(Space, Storage),
    length(W, InputArity),
    PredArity is InputArity + 1,
    petta_prepare_function_predicate(Module, FAtom, PredArity),
    petta_add_function_transaction(Storage, Space, Module, Term, FAtom, W).

%Only a name that has carried a repaired weak import needs post-transaction
%validation. The overwhelmingly common equation add keeps the original one
%transaction call, while the exceptional shadow-redefinition path repairs its
%receipt on commit, failure, or exception [tested:
%a_failed_local_redefinition_restores_the_repaired_inherited_call;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
petta_add_function_transaction(Storage, Space, Module, Term, FAtom, W) :-
    length(W, InputArity),
    PredArity is InputArity + 1,
    (   '$petta_repaired_shadow_import'(Module, FAtom, PredArity, _)
    ->  call_cleanup(
            transaction(
                add_function_atom(Storage, Space, Module, Term, FAtom, W)),
            petta_repair_emptied_shadows)
    ;   transaction(
            add_function_atom(Storage, Space, Module, Term, FAtom, W))
    ).

%Where the equation itself goes. `provider` is a foreign space, whose provider
%owns its storage; anything else is a native storage module. transaction/1 wraps
%the compile either way, and rolls back only the Prolog side of it: a provider's
%write is outside the database and stays written if the translation then fails.
store_equation(provider, Space, Term) :- !, store_atom(Space, Term).
store_equation(Storage, Space, Term) :- add_sexp_in(Storage, Space, Term, Ref),
                                        record_source_atom_assertion(Ref).

%Everything a change to FAtom leaves stale, in one place because three callers
%need exactly it: a new equation, a new declaration, and a removed equation.
%
%The MODULE is threaded rather than read, because a change hook fires outside
%the compile door's own module switch and the invalidation behind it is scoped
%to one space now: reading the ambient module here would have made a write in
%one space invalidate whichever space happened to be in force.
%announce_ rather than the bare event name, because the seam is now
%seam:function_changed/1 and this is the engine's own repair-then-announce
%around it. The two used to share a name in one namespace, which was harmless
%only by arity; with the seams in a module of their own the removal pair
%matched exactly and SWI reported "Local definition of user:function_removed/1
%overrides weak import from seam" on every file that declares the seam
%multifile [measured 2026-08-22].
announce_function_changed(Module, FAtom) :- prepare_specialization_invalidation(Module, FAtom),
                                   support_invalidate_function_change(Module, FAtom),
                                   forall(support_repair_invalidations, true),
                                   forall(seam:function_changed(FAtom), true),
                                   announce_function_call_graph_changed(Module,
                                                                        FAtom).

%A DECLARATION reaches one place an equation change does not: the declared
%function's OWN compiled clause. A parameter type decides how a CALL SITE
%compiles, which is what announce_function_changed/2 covers, but the declared
%RESULT type decides whether the function's answer re-enters evaluation, and
%that goal sits in the function's own body. So `(: f (-> Atom Atom))` arriving
%after `(= (f $x) (g $x))` left f still re-entering evaluation and
%`!(f (+ 1 2))` answered `(g 3)` where writing the declaration first answers
%`(g (+ 1 2))` [tested:
%spaces_late_type_declaration:a_late_type_declaration_repairs_its_call_sites].
%
%ONLY when that result view actually MOVED, and the narrowness is the point.
%Re-translating an equation loses which declared arrow it was compiled under,
%because nothing in the equation says: `(: f (-> Number Symbol))`,
%`(= (f $x) number-branch)`, `(: f (-> String Symbol))`,
%`(= (f $x) string-branch)` compiles the first equation against the first arrow
%alone, and rebuilding it with both declared left both clauses
%indistinguishable, so the `OrderFittest` dispatch policy stopped filtering and
%`!(f 1)` answered both branches
%[tested: test_every_dispatch_axis_is_readable_settable_and_defaulted].
%Nothing else a declaration carries reaches the callee, so this test is
%sufficient as well as minimal.
%
%The extra invalidation is marked before announce_function_changed/2 drains, so
%both directions repair in one pass.
announce_declaration_changed(Module, FAtom, Before) :-
    (   result_finality(FAtom, Before)
    ->  true
    ;   support_invalidate_definition(FAtom)
    ),
    announce_function_changed(Module, FAtom).

%The one question a compiled clause asks of its own function's declarations:
%`final` when some declared arrow answers the metatype `Atom`, which is what
%stops an answer re-entering evaluation, and `evaluated` otherwise.
%translate_clause/3 gates both its data path and its result continuation on
%exactly that test [source: engine/translator/analysis.pl:642,
%`declared_output_type(F, 'Atom')`].
result_finality(FAtom, Finality) :-
    (   declared_output_type(FAtom, 'Atom')
    ->  Finality = final
    ;   Finality = evaluated
    ).

announce_function_call_graph_changed(Module, FAtom) :-
    (   support_memo_take_change(Module, FAtom)
    ->  forall(seam:function_call_graph_changed(FAtom, Module), true)
    ;   true
    ).

%The removal repair is the engine's own duty, not an observer's: it used to
%ride a shim clause of the seam:function_removed EVENT, so an engine
%without Python in the process kept a compiled mention of a retired function
%answering as a call. Removal needs the FULL caller recompile, because a
%mention compiled as a CALL is what must flip back to data, and the
%data-direction repair (repair_stale_definitions, which registration rides
%through register_fun/1's scheduler) cannot see a call. The ARRIVAL
%direction deliberately has no twin walk here: a new function's flip is
%register_fun's scheduled repair, which defers inside an active source load
%so a rolled-back load cannot leave callers recompiled against a definition
%that never landed. Both directions and the rollback are pinned
%[tested: the_engine_recompiles_dependents_without_a_host]
%[tested: failed_late_definition_does_not_recompile_existing_callers].
announce_function_removed(FAtom) :- support_invalidate_function(FAtom),
                           forall(support_repair_invalidations, true),
                           forall(seam:function_removed(FAtom), true).

%The caller has classified the atom as an equation, so the shape test that used
%to be here is gone with it.
refuse_ruleless_equation(Space, Term) :-
    (   foreign_provides(Space, rules)
    ->  true
    ;   throw(error(petta_foreign_space_holds_no_rules(Space, Term),
                    context('add-atom'/3, 'the equation would never fire')))
    ).

%A native batch containing no equations and no observer for this space can
%resolve its storage module once. Equation batches and observed writes keep
%using add-atom/3 so registration and per-atom events retain their ordinary
%behavior.
metta_add_hooks_idle(_) :-
    \+ seam:atom_hook_clause(added, _), !.
metta_add_hooks_idle(Space) :-
    findall(Ref, seam:atom_hook_clause(added, Ref), Refs),
    seam:host_add_hooks_idle(Space, Refs).

%The removal mirror, asked by the bulk clear below: nothing is listening
%when no removed-atom handler exists at all, or when a host claims the
%whole census as its own idle hooks.
metta_remove_hooks_idle(_) :-
    \+ seam:atom_hook_clause(removed, _), !.
metta_remove_hooks_idle(Space) :-
    findall(Ref, seam:atom_hook_clause(removed, Ref), Refs),
    seam:host_remove_hooks_idle(Space, Refs).

%Clear a space, whoever holds it: a Prolog foreign provider clears through
%its own seam (or refuses, loudly, when it cannot); a native space
%announces the atoms it drops through the removal funnel exactly when
%something is watching, since the two bulk doors used to disagree, add
%announcing per atom and clear announcing nothing, and then sweeps its
%storage module in one pass [tested: test_clear_announces_every_atom_it_drops].
%Tabling state dies with the space life: clause removal leaves both the
%tabled property and the answer tables standing, so a reused pooled module
%answered its NEW definition from the dead life's cache with no tabling
%declared in the new life. Untable every tabled predicate the module itself
%owns (current_predicate/1 enumeration does not cross the default-module
%chain), abolish whatever tables remain, and retract the space's
%(tabled ...) reflection facts, which describe declarations that no longer
%exist [tested: test_pool_reuse_starts_tabling_clean].
metta_host_clear_space(Space) :-
    seam:foreign_space(Space), !,
    (   metta_exec_module_known(Space, Module)
    ->  % A foreign clear removes stored equations, so untabling must precede
        % the provider's removal funnel just as it does for native storage.
        metta_host_clear_tabling(Space, Module),
        metta_host_clear_foreign_storage(Space),
        clear_generated_predicates(Module),
        retractall(deferred_metta_function(_, Module, Space, _, _, _)),
        clear_module_translation_state(Module),
        support_forget_module(Module)
    ;   metta_host_clear_foreign_storage(Space)
    ).

%UNTABLING COMES FIRST, before any path that removes a clause. Every later
%step here removes clauses of predicates this space may have TABLED: the
%hook-driven `remove-atom` loop and clear_native_atoms/1 both retract the
%compiled half of a stored `(= ...)`, and clear_generated_predicates/1
%abolishes what the compiler generated. untable/1 removes "the tables and the
%tabling instrumentation" [source: SWI-Prolog 10.1 manual, section 7.10
%tabling-preds], so running it first is what makes every one of those removals
%an ordinary clause removal against an ordinary predicate. The reverse order
%retracts the clauses of a predicate whose tables and wrapper are still live,
%which is the shape upstream reports segfaults for; the same advice explains
%why the abolish/1 in clear_generated_predicate/3 must stay behind the
%untabling too, since abolish/1 "completely wipes the predicate, including its
%properties" [source: SWI-Prolog manual, retractall/1].
%
%Measured 2026-08-22, and it is a fault rather than a wrong answer: sixty
%cycles of "table a function in a fresh space, drop it, take the recycled
%name, redefine the same function" terminated the process abnormally inside
%libswipl 3 runs of 3 with the removal ahead of the untabling, and 0 of 4 with
%this order, in 0.70s per run; tests/test_tabling_control.py went from 4 of 4
%whole-file failures to 0 of 6. The fault predates the authoring-surface wave
%that exposed it (the same file failed 1 run of 6 at 4636dd2), which is why it
%read as a flake for weeks: it needs enough accumulated tabling state in one
%process, so a single test never showed it
%[tested: test_a_drop_untables_before_it_removes_any_clause,
%spaces_drop_untables_first; commit=b33102fbd50a30ae44d58eca08abd49e447ea60d].
metta_host_clear_space(Space) :-
    space_module(Space, Module),
    metta_host_clear_tabling(Space, Module),
    (   metta_remove_hooks_idle(Space)
    ->  true
    ;   findall(Atom, metta_host_stored(Space, Atom), Atoms),
        forall(member(Atom, Atoms), 'remove-atom'(Space, Atom, _))
    ),
    clear_native_atoms(Space),
    clear_generated_predicates(Module),
    retractall(deferred_metta_function(_, Module, Space, _, _, _)),
    clear_module_translation_state(Module).

metta_host_clear_foreign_storage(Space) :-
    clear_foreign_atoms(Space),
    retractall(import_life(Space, _, _)),
    forget_space_source_loads(Space).

%The equations above come out one per stored (= ...) atom, through
%metta_remove_atom/3, so a predicate the compiler GENERATED with no stored
%equation behind it is never reached. A compiled lambda keeps its clauses and a
%specialization keeps its predicate, and space names are POOLED, so what is left
%belongs to a life that has ended and the next holder of the name inherits it
%[measured 2026-08-22: after a drop the module still held lambda_2/2 with its
%clause and twice_Spec_[inc]/3, and the recycled space answered
%!(callPredicate (Predicate (lambda_2 5 $y))) with True, running a lambda body
%belonging to a space that no longer existed. The count grows by one dead
%predicate per lambda per life, because the lambda counter is process-global].
%
%Asked of the module by what it still OWNS rather than by naming the kinds of
%generated predicate, so a kind added later is swept without being added here.
%current_predicate/1 does not cross the default-module chain, which is what
%keeps this to the space's own and away from the engine's; it is the same
%enumeration metta_host_clear_tabling/2 above uses, and it runs after that one
%because a tabled predicate cannot be abolished until it is untabled.
clear_generated_predicates(Module) :-
    forall(( current_predicate(Module:Name/Arity),
             functor(Head, Name, Arity),
             \+ predicate_property(Module:Head, imported_from(_)) ),
           clear_generated_predicate(Module, Name/Arity, Head)).

%Clauses first and predicate second, and the split is the transaction contract.
%retractall/1 is clause-level, so a rollback restores what it removed; abolish/1
%is predicate-level and a rollback cannot restore what it dropped, which is why
%the shadow repair beside it defers under a transaction rather than abolishing
%eagerly [source: the current_transaction/1 branch in metta_remove_atom/3,
%tested: test_a_reload_that_fails_leaves_the_previous_definitions_standing].
%This defers through that same pending table, and its sweep re-checks that the
%predicate is still empty, so a rolled-back clear leaves the predicate exactly
%as it was.
clear_generated_predicate(Module, Name/Arity, Head) :-
    catch(retractall(Module:Head), _, true),
    (   current_transaction(_)
    ->  assertz('$petta_shadow_repair_pending'(Module, Name, Arity))
    ;   petta_abolish_local_predicate(Module, Name, Arity)
    ).

metta_host_clear_tabling(Space, Module) :-
    forall(( current_predicate(Module:Name/Arity),
             functor(Head, Name, Arity),
             \+ predicate_property(Module:Head, imported_from(_)),
             predicate_property(Module:Head, tabled) ),
           untable(Module:Name/Arity)),
    abolish_module_tables(Module),
    findall([tabled, Space, F, A],
            'get-atoms'('&metta', [tabled, Space, F, A]),
            Facts),
    forall(member(Fact, Facts), 'remove-atom'('&metta', Fact, _)).

%Bulk cleanup of the reflection facts describing one space: every
%(defined <Space> _) atom in &metta goes through the engine's own removal
%funnel (hooks fire per fact), in ONE host crossing; the per-fact crossing
%measured 10,000 calls and 64ms for 10,000 defines.
metta_host_clear_defined(Space) :-
    findall(F, 'get-atoms'('&metta', [defined, Space, F]), Fs),
    forall(member(F, Fs), 'remove-atom'('&metta', [defined, Space, F], _)).
