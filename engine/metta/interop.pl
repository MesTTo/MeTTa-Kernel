% Purpose: import Prolog predicates and MeTTa sources while preserving module and source-lifecycle boundaries
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE]

%%% Prolog interop: %%%
argv(K, _) :- var(K), !, refuse_unbound_input(argv, 1).
argv(K, Arg) :- current_prolog_flag(argv, Argv), nth0(K, Argv, A), ( atom_number(A, N) -> Arg = N ; Arg = A ).
%A name with no predicate behind it is refused where the name is written.
%A registered name with no arity recorded compiles every call to it into a
%partial application rather than failing:
%!(import_prolog_functions_from_file "mylib.pl" (no-such-predicate)) reported
%success and !(no-such-predicate 1) answered (partial no-such-predicate (1)).
%A silent wrong answer is the worst outcome available here.
%
%The Python side refuses the same name in MeTTa.register_prolog for the same
%reason; this is the engine-level gate, so every route in gets it.
%
%register_fun_in(user, N), not register_fun/1: a registration that records no
%home module resolves only while NO named space has claimed the name, because
%fun_here/1's first clause is \+ fun_scoped(F). One named space defining an
%equation of the same name therefore turned every registered predicate into
%inert data in every space, with no error: !(rp-norm 3) answered (rp-norm 3).
%user is the module the clauses really are in, so this states where they live
%rather than adding a rule, and a named space that defines the name still
%shadows it, which is the behaviour that should happen
%[tested: a_registered_predicate_survives_a_named_space_claiming_its_name].
import_prolog_function(N, _) :- var(N), !,
                                refuse_unbound_input(import_prolog_function, 1).
import_prolog_function(N, true) :-
    import_prolog_function_at(N, scan).

%The DECLARED route knows the arity and registers that one, where the scan
%registers every arity current_predicate/1 can see. That difference is a
%defect when a declaration exists: `(: rc-scale (-> Number Number))` beside an
%internal `'rc-scale'/3` published BOTH, so `(rc-scale 3 7)` answered 21
%through a predicate the library never declared [reproduced 2026-08-16].
%
%The arity is already in hand at that moment. refuse_undeclared_arity/3
%computes it to check the predicate exists, so threading it out costs nothing
%and closes discovery on the route the whole metta_export design exists to
%make the good one. The scan stays for the legacy `names=` route, where
%nothing was declared and discovery is all there is
%[tested: a_declared_export_publishes_only_its_declared_arity].
import_prolog_function_at(N, Arity) :-
    must_be(atom, N),
    refuse_reserved_registration(N),
    refuse_absent_prolog_function(N),
    prolog_function_source(N, Source),
    claim_function_name(N, prolog, Source),
    %The clauses are the HOST's, in whatever module consult_global/1 put them
    %(`user`), and every space reaches them through the base chain. What is
    %registered here is the base TIER's claim on the name, which is &self's
    %module: fun_here_in/2 reads that claim as "callable from every space
    %unless a space of its own claims the name", and it is the same claim
    %register_op/2 makes on the Python side.
    metta_self_module(Self),
    register_fun_in(Self, N),
    (   Arity == scan
    ->  register_prolog_arities(N)
    ;   register_arity(N, Arity)
    ).

%The file the clauses in the database RIGHT NOW came from, read off a clause
%rather than off the predicate. predicate_property(file(F)) is the wrong
%question here and answers the wrong thing: after a second library redefines a
%static predicate it still reports the FIRST library's file, which is exactly
%the case this has to detect. A registration made from source held in memory
%has no file, and says so.
prolog_function_source(N, Source) :-
    (   current_predicate(N/Arity),
        functor(Head, N, Arity),
        nth_clause(Head, 1, Ref),
        clause_property(Ref, file(File))
    ->  Source = File
    ;   Source = unknown
    ).

%Two names a registration must not take, both of which it used to take
%silently while reporting success.
%
%A builtin, because a consulted predicate REPLACES the engine's static one for
%the whole process: registering a predicate named + made !(+ 1 2) answer
%whatever the library said, and the only diagnostic was SWI's redefinition
%warning on stderr, which no caller sees. The equation route already refuses
%exactly this at spaces.pl through petta_builtin_redefinition/3, so this is
%the same rule reaching the other road in rather than a new one.
%
%A translated head, because translator rules and translate_special_dl/5 are
%tried BEFORE function dispatch, so the registration compiles nothing and can
%never be reached:
%registering a predicate named if left !(if True 1 2) answering 1 from the
%translator and the library's clauses dead, with nothing said at any point.
%Accepting a registration that cannot run is telling the author their code is
%installed when it is not
%metta_translated_head/1 is the translator's own registry, so a rule added at
%run time is covered without another hand-maintained list
%[tested: a_builtin_name_is_refused, a_special_form_name_is_refused,
%test_registering_any_translator_compiled_head_is_refused_by_name].
refuse_reserved_registration(N) :-
    (   builtin_fun(N)
    ->  throw(error(permission_error(register, metta_builtin, N),
                    context(import_prolog_function/2,
                            'the engine defines this name')))
    ;   metta_translated_head(N)
    ->  throw(error(permission_error(register, metta_special_form, N),
                    context(import_prolog_function/2,
                            'the translator compiles this name')))
    ;   true
    ).

%Who put a function's clauses where they are. fun/1 says a name IS a function
%and fun_in/2 says which module its clauses live in; neither says which tier
%put them there, and without that a registration from one tier silently took
%a name another tier owned. Registering a Prolog predicate over a live Python
%operation replaced it, left petta_py_op_spec/3 still claiming the name, and
%wedged it for the life of the process: the operation could not be
%unregistered, because retractall/1 on what was now a static predicate raised,
%and could not be re-registered either.
%
%Equations are deliberately not recorded here. Their origin is already
%answerable, from the space that holds the atom and from fun_in/2, and one
%assertion per compiled equation is a cost on the hot path for a fact that is
%already derivable [tested: a_name_another_tier_owns_is_refused,
%test_a_python_operation_is_not_silently_replaced].
:- dynamic metta_function_origin/3.   %metta_function_origin(Name, Tier, Detail)

refuse_other_tiers_name(Name, Tier) :-
    (   metta_function_origin(Name, Other, OtherDetail), Other \== Tier
    ->  throw(error(permission_error(register, metta_function, Name),
                    context(refuse_other_tiers_name/2,
                            owned_by(Other, OtherDetail))))
    ;   true
    ).

%The same refusal for two PROLOG sources, asked where it can still be acted
%on: before the source that would take the name has been read.
%
%claim_function_name/3 asks the same question after the consult and has to,
%because that is the only place the clobber can be DETECTED. But detection
%after the fact told the wrong author: B was refused by name and A, which did
%nothing, silently answered B's implementation from then on
%[reproduced 2026-08-16: `A before B: 20`, `B refused`, `A after: 30`]. This
%is the check moved to where refusing still prevents something, which is
%exactly why check_prolog_function_names/3 exists for builtins ten lines
%down, and it is the same error term so one diagnostic covers both positions.
refuse_other_sources_name(Name, Source) :-
    (   metta_function_origin(Name, prolog, Owner),
        Owner \== unknown, Source \== unknown, Owner \== Source
    ->  throw(error(petta_name_owned_by_source(Name, Owner),
                    context(refuse_other_sources_name/2,
                            'two Prolog sources claim one name')))
    ;   true
    ).

%unknown is not an identity, it is prolog_function_source/2 saying it could
%not tell, which is what a predicate installed by use_foreign_library/1
%answers: it has no clause with a file behind it. Two of them are not the same
%source and one is not a different source either, so comparing them decides
%nothing and refusing on one refuses a library re-registering itself
%[tested: test_a_compiled_library_registers_from_python]. A C predicate cannot
%take a name this way in silence regardless, because installing over a static
%predicate raises from SWI rather than warning.

%What a source is CALLED, for comparing one against another. A file is
%recorded under SWI's canonical absolute path, since that is what
%clause_property(file(F)) answers, and a caller passes whatever they typed; a
%load from memory has no file and is recorded under the name it loaded as, so
%it passes through unchanged.
canonical_prolog_source(Source, Canonical) :-
    (   absolute_file_name(Source, Resolved, [file_errors(fail), access(read)])
    ->  Canonical = Resolved
    ;   Canonical = Source
    ).

%Re-registering under the same tier is replacement, which is what register_op
%does on every call. Two different PROLOG SOURCES claiming one name is not
%replacement, it is two libraries destroying each other's predicate, so that
%is refused and the source that owns it is named.
%
%This fires AFTER the consult, and it has to, which is the shape of the
%problem rather than a shortcut. SWI does warn about the redefinition, on
%stderr, and it does not throw: "Redefined static procedure 'shared-norm'/2"
%is printed and the load continues, so no catch/3 can see it and the only
%reliable check is a positive one afterwards, asking whether the name still
%resolves to what its owner loaded. CPython reaches the same answer for the
%same reason and does it by name as a matter of course
%[source: CPython, PyCapsule_Import, "a high degree of certainty that the
%Capsule they load contains the correct C API"]. The clobber has happened by
%the time this raises; what it buys is that the author hears about it instead
%of shipping a library silently bound to someone else's code, and
%unregister_metta_extension/1 is how they take it back out
%[tested: two_sources_cannot_claim_one_name].
claim_function_name(Name, Tier, Detail) :-
    (   metta_function_origin(Name, Owner, OwnerDetail)
    ->  claim_over(Name, Owner, OwnerDetail, Tier, Detail)
    ;   assertz(metta_function_origin(Name, Tier, Detail))
    ).

claim_over(Name, Owner, _, Tier, Detail) :-
    Owner == Tier, Owner \== prolog, !,
    retractall(metta_function_origin(Name, _, _)),
    assertz(metta_function_origin(Name, Tier, Detail)).
claim_over(Name, prolog, Detail, prolog, Detail) :- !,
    retractall(metta_function_origin(Name, _, _)),
    assertz(metta_function_origin(Name, prolog, Detail)).
claim_over(Name, prolog, OwnerDetail, prolog, _) :- !,
    throw(error(petta_name_owned_by_source(Name, OwnerDetail),
                context(claim_function_name/3,
                        'two Prolog sources claim one name'))).
claim_over(Name, _, _, Tier, _) :-
    refuse_other_tiers_name(Name, Tier).

release_function_name(Name) :- retractall(metta_function_origin(Name, _, _)).

%%%% The host registration lifecycle, four calls instead of seven %%%%
%
%A host registering an operation performs one protocol: prove the name is
%free, assert its own dispatch clause, then make the engine treat the name
%as a function. The protocol's steps were published one bookkeeping
%predicate at a time (refuse_other_tiers_name, the probe, register_fun_in,
%arity/2, function_changed, claim_function_name, and the release trio), so
%every binding had to restate the engine's registration invariants in order.
%These four carry the whole protocol; the fine-grained predicates stay as
%the internals they always were.
%
%OPEN runs before the host mutates anything, which is the probe's whole
%value: a taken name refuses here, naming its owner, while nothing has been
%asserted yet. The tier refusal comes first because its diagnostic names the
%owning tier and what to do about it, where the probe's names a Prolog
%predicate [tested: host_registration:a_taken_name_refuses_before_any_write].
metta_host_open_function(Name, Tier, PredArity) :-
    refuse_other_tiers_name(Name, Tier),
    metta_host_probe_function(Name, PredArity).

%ADOPT runs after the host asserted its dispatch clause at the base tier:
%the name becomes a function, its dependents refresh against the clause
%that is already in place, and the tier claim lands last, after any
%unregistration of prior arities has run its releases
%[tested: host_registration:an_adopted_name_is_a_function_and_claimed].
metta_host_adopt_function(Name, Tier, Kind, PredArity) :-
    metta_self_module(Base),
    %The arity row BEFORE register_fun_in: registering a fresh name repairs
    %stale mentions through register_fun/1's scheduler, and that recompile
    %compiles the mention as a call, which needs the arity to exist. Flip
    %this order and adopt fails
    %[tested: host_registration:a_forgotten_name_reads_as_data_again].
    ( arity(Name, PredArity) -> true ; assertz(arity(Name, PredArity)) ),
    register_fun_in(Base, Name),
    announce_function_changed(Base, Name),
    claim_function_name(Name, Tier, Kind).

%DROP removes one arity: the base tier's clauses at that functor and the
%arity row. The host guards this with its own bookkeeping so it only drops
%arities it registered; equations live in their space's own modules, and
%the tier claim keeps a host operation and a base-tier equation from
%sharing a name in the first place.
metta_host_drop_function(Name, PredArity) :-
    metta_self_module(Base),
    functor(Head, Name, PredArity),
    retractall(Base:Head),
    retractall(arity(Name, PredArity)).

%FORGET runs when nothing defines the name at any arity: the engine stops
%treating it as a function everywhere, the tier claim releases, and the
%dependents that compiled mentions of it as calls recompile back to data
%[tested: host_registration:a_forgotten_name_reads_as_data_again].
metta_host_forget_function(Name) :-
    retractall(fun(Name)),
    retractall(arity(Name, _)),
    unregister_fun_everywhere(Name),
    release_function_name(Name),
    announce_function_removed(Name).

%The probe is the assert the registration will do, on a clause that can
%never run, so the engine's own permission error surfaces before any
%existing registration has been touched. predicate_property cannot stand in
%for it: autoloadable names report static yet accept clauses. The fresh-name
%clause first, because it is the case every ordinary registration takes and
%it skips the assert, the erase and the property calls [measured 2026-08-18:
%register-op 39907 -> 38830 over 100 registrations, -10.8 each, min of 3].
%
%built_in and nothing wider decides the refusal: a merely AUTOLOADABLE
%library predicate reports defined, imported_from and a home module before
%it has ever been loaded, and a library predicate really in use is a free
%MeTTa name now that operation clauses go into the base tier's own module,
%where defining one shadows it locally. Of the 428 names the engine imports,
%probing the base module refuses 7, 4, 2 and 1 at MeTTa arity 0 to 3: SWI's
%protected core, which no module may redefine, the protected core a rewrite
%system needs, obtained rather than implemented [measured 2026-08-19, one
%process per measurement and a fresh module per name].
metta_host_probe_function(Name, PredArity) :-
    metta_self_module(Base),
    \+ current_predicate(Base:Name/PredArity),
    !.
metta_host_probe_function(Name, PredArity) :-
    metta_self_module(Base),
    functor(Probe, Name, PredArity),
    catch(setup_call_cleanup(assertz((Base:Probe :- fail), Ref), true, erase(Ref)),
          error(permission_error(modify, static_procedure, _), _),
          metta_host_refuse_taken_name(Name, PredArity, Probe)).

metta_host_refuse_taken_name(Name, PredArity, Probe) :-
    metta_self_module(Base),
    (   predicate_property(Base:Probe, imported_from(Owner))
    ->  true
    ;   Owner = Base
    ),
    Arity is PredArity - 1,
    throw(error(petta_op_name_taken(Name, Arity, PredArity, Owner),
                context(metta_host_open_function/3, 'the name is not free'))).

:- multifile prolog:error_message//1.
prolog:error_message(petta_op_name_taken(Name, Arity, PredArity, Owner)) -->
    [ 'registering ~w at ~w MeTTa argument(s) would assert into Prolog\'s \c
       ~w/~w, which ~w already owns in this process'-[Name, Arity, Name,
                                                      PredArity, Owner], nl,
      '  a registered operation\'s clauses live in the base tier, so its \c
       name has to be free there: register it under another name (the \c
       binding\'s name= override), or write it as an equation in a named \c
       space, which compiles into a module of its own' ].

%%%% A library declares its own exports, in the file that implements them %%%%
%
%Registering one predicate took three statements in two languages: the name in
%a Python call, the arity discovered by scanning whatever current_predicate/1
%happened to hold, and the type in a third statement whose ordering against
%call-site compilation nothing checked. Nothing kept the three in agreement,
%and the arity was DISCOVERED rather than declared, so a library shipping a
%public 'vec-dot'/3 and an internal helper 'vec-dot'/2 published both.
%
%Every comparable runtime puts the export declaration in the file that
%implements it: PyMethodDef, R_CallMethodDef, ErlNifFunc, napi_property_
%descriptor, SWI's own module/2 export list. R had exactly this engine's
%mechanism, symbol discovery, and walked away from it, because "the use of
%registration allows R to ensure that code compiled into packages does not
%inadvertently call routines in other packages"
%[source: R Extensions manual, section 5.4].
%
%The declaration is MeTTa, in a string, rather than a new Prolog operator. The
%types are MeTTa types, the reader that parses them is the engine's own, and
%the MeTTa arity comes from the type chain, so the arity cannot disagree with
%the type it was written beside:
%
%    :- metta_extension(pettorch, [version('0.3.1')]).
%    :- metta_export("
%        (: vec-dot (-> Number Number Number))
%        (: shape-of (-> Atom Atom))
%        (export vec-helper 1)
%    ").
%
%(export Name Arity) is the form for a name whose type the author does not
%want to state; the arity is the MeTTa arity, one less than the predicate's.
%
%The directive records; the LOAD registers, once the file has finished and its
%predicates exist. consult_global/1 and its two siblings are the funnel every
%route enters through, so the MeTTa spelling, register_prolog and a bare
%consult all get this [tested: prolog_interface_exports].
:- dynamic pending_metta_export/3.     %pending_metta_export(File, Name, Type)
:- dynamic metta_extension_info/3.     %metta_extension_info(Extension, File, Options)
:- dynamic metta_extension_member/2.   %metta_extension_member(Extension, Name)

%The version of the extension SEAM a library was written against. A library
%built on today's ext_points.pl will be loaded into a later engine, and with
%nothing to check against a removed or renamed hook shows up as silence.
%
%Erlang's NIF loader is the model for the check: the major version must match
%and the minor must not be newer than the runtime's, or the load fails. The
%rule here is the same and stated the same way, because a library that
%declares nothing is the common case and must keep working: a declaration is
%checked, silence is not.
%
%The number moves when a seam a library can SEE changes: a hook removed or
%renamed, a hook's arguments changed, a refusal added where none was. Adding
%a hook moves the minor.
%1-1: seam:route_cap/4 added, and petta_shape_route/5 published as a
%service (2026-08-20).
metta_extension_api_version(1, 1).

metta_extension(Name, Options) :-
    must_be(atom, Name),
    must_be(list, Options),
    check_extension_requirements(Name, Options),
    declaring_file(File),
    retractall(metta_extension_info(Name, File, _)),
    assertz(metta_extension_info(Name, File, Options)).

check_extension_requirements(Name, Options) :-
    (   memberchk(requires(Major-Minor), Options)
    ->  refuse_incompatible_extension(Name, Major, Minor)
    ;   true
    ).

refuse_incompatible_extension(Name, Major, Minor) :-
    metta_extension_api_version(OurMajor, OurMinor),
    (   Major =:= OurMajor, Minor =< OurMinor
    ->  true
    ;   throw(error(petta_extension_api_mismatch(Name, Major-Minor,
                                                 OurMajor-OurMinor),
                    context(metta_extension/2,
                            'this engine does not offer the seam the \c
                             extension was written against')))
    ).

metta_export(Source) :-
    declaring_file(File),
    parse_metta_source(Source, ParsedForms),
    forall(member(Parsed, ParsedForms), record_metta_export(File, Parsed)).

%The file a directive is running in. prolog_load_context/2 answers it during a
%consult; outside one, which is how a test or an inline snippet reaches here,
%the exports are keyed on a name of their own so they still register.
declaring_file(File) :-
    ( prolog_load_context(source, Source) -> File = Source ; File = 'petta_inline' ).

record_metta_export(File, Parsed) :-
    parsed_form_parts(Parsed, _, Text, Term),
    (   Term = [':', Name, Type], atom(Name), is_list(Type), Type = [->|_]
    ->  assertz(pending_metta_export(File, Name, Type))
    ;   Term = [export, Name, Arity], atom(Name), integer(Arity)
    ->  assertz(pending_metta_export(File, Name, arity(Arity)))
    %The two word lists are the catalog's volatility and determinism
    %vocabularies, consulted as data: a program that widens either row in
    %'&petta' widens what this parser accepts, one authority.
    ;   Term = [volatility, Name, Level], atom(Name),
        petta_vocabulary_value(volatility, Level)
    ->  declare_function_volatility(Name, Level)
    ;   Term = [determinism, Name, Mode], atom(Name),
        petta_vocabulary_value(determinism, Mode)
    ->  declare_function_determinism(Name, Mode)
    ;   throw(error(petta_export_form(Text),
                    context(metta_export/1,
                            'an export is (: name (-> ...)), (export name arity), \c
                             (volatility name <a volatility vocabulary value>) or \c
                             (determinism name <a determinism vocabulary value>); \c
                             both vocabularies are (vocabulary ...) rows in &petta')))
    ).

%How much a caller may assume about a function's answers, and therefore what
%an optimiser or a cache is allowed to do with it. PostgreSQL's ladder,
%because purity is not a boolean and its three rungs are the ones that turn
%out to matter: VOLATILE "makes no assumptions", STABLE gives the same answer
%within one statement so repeated calls may fold to one, and IMMUTABLE gives
%the same answer forever so a call on constant arguments may be folded at
%plan time [source: PostgreSQL documentation, Function Volatility Categories].
%
%The gap this closes was demonstrated rather than imagined: lib_memo will
%happily cache a side-effecting registered predicate, because nothing records
%whether caching it is sound, and the second call then skips the effect.
%
%SILENCE STAYS PERMISSION. PostgreSQL's default is the pessimistic rung and
%this one's is not, deliberately: memoization here is already opt-in by the
%CALLER, so making an undeclared function refuse would break every existing
%(memoize f) without telling anyone anything they did not know. What was
%missing is the library's ability to say NO, and a declared `volatile` is
%that no [tested: a_volatile_function_refuses_memoization].
:- dynamic metta_function_volatility/2.

declare_function_volatility(Name, Level) :-
    retractall(metta_function_volatility(Name, _)),
    assertz(metta_function_volatility(Name, Level)).

%True when a cache may serve this function's answers.
metta_function_cacheable(Name) :- \+ metta_function_volatility(Name, volatile).

%How many answers a caller may expect. Only det is ENFORCED, by handing the
%predicate to SWI's own det/1, and it is worth having because a leaked choice
%point is invisible to the counter and expensive in reality: no-cut, cut and
%SSU dispatch all reported exactly 1,000,003 inferences while wall clock was
%0.1887, 0.0928 and 0.1128 [measured, ai-todo-fast-libraries.md B5]. Declaring
%it moves the failure to the library's own door instead of taxing every caller.
%
%Read det as EXACTLY one answer, not at most one: SWI raises "Deterministic
%procedure f/2 failed" as readily as it raises on a choice point, so a
%function whose empty answer set is a legitimate result is semidet and not det
%[measured 2026-08-16]. semidet and nondet are recorded rather than checked,
%because SWI has a directive for det alone; they are still read, by
%profile_extension, where they say whether a redo was intended.
:- dynamic metta_function_determinism/2.

declare_function_determinism(Name, Mode) :-
    retractall(metta_function_determinism(Name, _)),
    assertz(metta_function_determinism(Name, Mode)).

apply_declared_determinism(Name, Type) :-
    (   metta_function_determinism(Name, det)
    ->  declared_predicate_arity(Type, Arity),
        det(Name/Arity)
    ;   true
    ).

%The pending list is emptied BEFORE anything is checked, so a declaration
%that raises leaves no residue for the next load to pick up: without that, a
%file whose declaration named an arity it did not define left its exports
%pending and the next unrelated consult failed on them.
register_pending_exports :-
    findall(File-Name-Type, pending_metta_export(File, Name, Type), Pending),
    retractall(pending_metta_export(_, _, _)),
    ( Pending == [] -> true ; register_declared_exports(Pending) ).

%Every name is checked before any is registered, which is import_prolog_
%functions/2's rule reaching this route too: a declaration with one bad entry
%registers nothing.
register_declared_exports(Pending) :-
    catch(check_and_register_declared_exports(Pending), Error,
          ( undo_declared_exports(Pending), throw(Error) )).

check_and_register_declared_exports(Pending) :-
    forall(member(_-Name-_, Pending), refuse_reserved_registration(Name)),
    forall(member(_-Name-_, Pending), refuse_other_tiers_name(Name, prolog)),
    forall(member(File-Name-_, Pending),
           ( canonical_prolog_source(File, Source),
             refuse_other_sources_name(Name, Source) )),
    forall(member(_-Name-Type, Pending), refuse_undeclared_arity(Name, Type, _)),
    forall(member(File-Name-Type, Pending),
           ( refuse_undeclared_arity(Name, Type, Arity),
             import_prolog_function_at(Name, Arity),
             declare_export_type(Name, Type),
             apply_declared_determinism(Name, Type),
             record_extension_membership(File, Name) )).

%All or nothing, and "nothing" has to reach past the registrations to the
%SOURCE. Every refusal in here is post-load and cannot be otherwise, so every
%one of them needs the rollback: a file refused for a reserved name has
%already replaced the builtin's static predicate, and a file refused for a
%wrong arity has already brought in whatever else it defines.
%
%THE SHAPE: By the time anything here can fail the file's clauses are already in
%the database, and if one of them redefined a static predicate another library
%loaded, that library's clauses are gone: SWI prints "Redefined static
%procedure" and continues, so the damage lands before any check can speak.
%Leaving the file loaded after refusing it left the OTHER author's function
%silently answering this one's implementation.
%
%unload_file/1 is SWI's own way of taking a load back out, "Remove all clauses
%loaded from File" [source: SWI-Prolog 10.1 Reference Manual, unload_file/1],
%and it is what unregister_metta_extension/1 already uses for the same job.
%What it does NOT do is restore the incumbent's clauses, which nothing can:
%those were destroyed at compile time. What it buys is that the name is empty
%and loud rather than full and wrong, and the recovery is the documented one,
%re-registering the library that owned it
%[tested: a_computed_declaration_is_refused_and_its_source_unloaded].
%Release only what this source currently owns. A name it never reached has no
%origin to retract and a name another source owns is not this one's to release,
%so asking the registry who owns it now is both the test and the rollback list.
undo_declared_exports(Pending) :-
    forall(member(File-Name-_, Pending), undo_declared_export(File, Name)),
    findall(File, member(File-_-_, Pending), Files),
    sort(Files, Sources),
    forall(member(Source, Sources), unload_declared_source(Source)).

undo_declared_export(File, Name) :-
    canonical_prolog_source(File, Source),
    (   metta_function_origin(Name, prolog, Source)
    ->  forget_registered_function(Name)
    ;   true
    ).

%petta_inline is the name a declaration outside any load is keyed on, so there
%is no file to take back out.
unload_declared_source('petta_inline') :- !.
unload_declared_source(Source) :- catch(unload_file(Source), _, true).

%The MeTTa arity is the type chain's length less one, and the predicate's is
%one more than that: (-> Number Number Number) is two inputs and an output,
%so 'vec-dot'/3.
declared_predicate_arity([->|Types], Arity) :- !, length(Types, Arity).
declared_predicate_arity(arity(MettaArity), Arity) :- Arity is MettaArity + 1.

%Answers the arity it checked, so the caller can register THAT rather than
%rediscovering every arity the predicate happens to have.
refuse_undeclared_arity(Name, Type, Arity) :-
    declared_predicate_arity(Type, Arity),
    (   current_predicate(Name/Arity)
    ->  true
    ;   throw(error(existence_error(procedure, Name/Arity),
                    context(metta_export/1,
                            'the declaration names an arity this file does not define')))
    ).

declare_export_type(_, arity(_)) :- !.
declare_export_type(Name, Type) :-
    Declaration = [':', Name, Type],
    ( get_native_atom('&self', Declaration) -> true
    ; 'add-atom'('&self', Declaration, _) ).

%Two records, per EXTENSION and per FILE, because the two answer different
%questions and only one of them was being asked.
%
%An extension is optional here by design, which is why this clause ends in
%`; true`. The Python side then read what a registration produced by walking
%extension MEMBERSHIP, so a file carrying `metta_export` and no
%`metta_extension`, which is the natural shape for a single-file library,
%registered everything correctly and then reported failure: `is_function` true
%and the call answering 10, beside `ValueError: register_prolog needs the
%names to register` [reproduced 2026-08-16]. The state was right and the
%report was wrong, which is I15's wedged registry and I25's partial state
%inverted.
%
%The file record makes the lookup exact and leaves extensions optional, which
%is what the Prolog side already intended
%[tested: a_declared_export_without_an_extension_reports_its_names].
:- dynamic metta_file_export/2.

record_extension_membership(File, Name) :-
    (   metta_file_export(File, Name) -> true
    ;   assertz(metta_file_export(File, Name)) ),
    (   metta_extension_info(Extension, File, _)
    ->  ( metta_extension_member(Extension, Name) -> true
        ; assertz(metta_extension_member(Extension, Name)) )
    ;   true
    ).

%Everything one extension installed, gone. PostgreSQL's rule, and its reason:
%"PostgreSQL will not let you drop an individual object contained in an
%extension, except by dropping the whole extension", which is what stops a
%registry keeping a claim on a name it can no longer release. unload_file/1 is
%SWI's own mechanism for taking a consulted file's clauses back out, so the
%predicates go with the registrations rather than being left callable through
%a name nothing records [tested: an_extension_unloads_whole].
unregister_metta_extension(Extension) :-
    must_be(atom, Extension),
    loaded_extension_file(Extension, File),
    findall(Name, metta_extension_member(Extension, Name), Names),
    forall(member(Name, Names), forget_registered_function(Name)),
    retractall(metta_extension_member(Extension, _)),
    %The per-file record goes with them, or a re-registration of the same file
    %would report names that are no longer there.
    retractall(metta_file_export(File, _)),
    retractall(metta_extension_info(Extension, File, _)),
    ( File == 'petta_inline' -> true ; catch(unload_file(File), _, true) ).

%Its own predicate so the file is a head argument: read inline, the binding
%happens in one branch of an if-then-else whose other branch throws, and SWI's
%var_branches check cannot see that the other branch never returns.
loaded_extension_file(Extension, File) :-
    (   metta_extension_info(Extension, Recorded, _)
    ->  File = Recorded
    ;   throw(error(existence_error(metta_extension, Extension),
                    context(unregister_metta_extension/1,
                            'no extension of that name is loaded')))
    ).

forget_registered_function(Name) :-
    remove_sexp('&self', [':', Name, _]),
    metta_host_forget_function(Name).

%Ask whether a whole list of names may be registered from Source, BEFORE
%Source is loaded. Order is the whole point: consulting a file that defines a
%builtin's name has already replaced the engine's static predicate by the time
%any per-name refusal could fire, so refusing afterwards left !(+ 1 2)
%answering the library's answer while reporting the registration as refused
%[tested: a_reserved_name_is_refused_before_the_source_loads].
%
%The name another SOURCE owns is refused here for exactly that reason and it
%was not: claim_function_name/3 refused it after the consult, which told the
%wrong author. B heard "already registered from A" and A, which did nothing,
%answered B's implementation from then on
%[tested: a_name_another_source_owns_is_refused_before_the_load].
check_prolog_function_names(Names, Source, true) :-
    prolog_function_name_list(Names, check_prolog_function_names/3),
    canonical_prolog_source(Source, Canonical),
    forall(member(N, Names), refuse_reserved_registration(N)),
    forall(member(N, Names), refuse_other_tiers_name(N, prolog)),
    forall(member(N, Names), refuse_other_sources_name(N, Canonical)).

%Register every name, or none. Validating inside the registration loop left a
%typo in the third name with the first two registered and callable, and the
%list of what had taken died inside the exception, so the caller could not
%learn what to undo. This is the shape petta_py_register_op_set already uses
%one file over: probe every name first, touch state only after
%[tested: a_typo_in_the_list_registers_nothing].
import_prolog_functions(Names, true) :-
    prolog_function_name_list(Names, import_prolog_functions/2),
    forall(member(N, Names), refuse_reserved_registration(N)),
    forall(member(N, Names), refuse_absent_prolog_function(N)),
    forall(member(N, Names), import_prolog_function(N, _)).

prolog_function_name_list(Names, Context) :-
    (   is_list(Names)
    ->  forall(member(N, Names), must_be(atom, N))
    ;   throw(error(type_error(list, Names),
                    context(Context, 'the names to register')))
    ).

refuse_absent_prolog_function(N) :-
    (   current_predicate(N/_)
    ->  true
    ;   throw(error(existence_error(procedure, N),
                    context(import_prolog_functions/2,
                            'no Prolog predicate of that name is loaded')))
    ).

%A Prolog library loaded from MeTTa belongs to the process, not to a space. Its
%predicates are builtins once loaded, register_fun/1 reads their arity out of
%user, and every space has to be able to call them. SWI loads a file into the
%module the load runs in, and under per-space equations a runnable form runs in
%its space's module, so a library imported inside a named space would define
%itself where register_fun/1 cannot see it: the arities never register and every
%call to it compiles to a partial application instead. In &self the load module
%already is user, so this states that behaviour rather than adding a rule.
consult_global(File) :- refuse_claimed_source_exports(File),
                        loading_loudly(user:consult(File)),
                        register_pending_exports.
use_module_global(File) :- refuse_claimed_source_exports(File),
                           loading_loudly(user:use_module(File)),
                           register_pending_exports.

%%%% Read the manifest before running the payload %%%%
%
%A source declares its exports INSIDE the file that implements them, which is
%the design the review argues for and the one that makes the arity and the
%type impossible to disagree. It also means the names are not known until the
%file has run, and by then a clause of the file has already replaced a static
%predicate another library loaded: SWI prints "Redefined static procedure" and
%CONTINUES, so the incumbent's clauses are gone before any refusal can speak.
%A directive cannot stop that either, because a directive that throws is
%reported and the load carries on [measured 2026-08-16: with the refusal in
%the metta_export/1 directive itself, `A AFTER refusal` still answered B's 30].
%
%So read the manifest out of the source WITHOUT running the source. This is
%PostgreSQL's control file, which the codebase already follows for the
%extension model: the file that says what an extension is gets read before the
%script that installs it. Python reads a package's entry points out of its
%metadata rather than by importing it, for the same reason.
%
%The scan is exact for a literal declaration, which is every one written by
%hand. It stops at the first term it cannot read, and does not run :- op/3, so
%a file that defines its own operators and declares exports below them is
%scanned only as far as the operator. Whatever the scan misses,
%register_declared_exports_or_undo/1 still catches after the load, with the
%rollback that is all that is left by then
%[tested: a_second_source_claiming_a_name_never_loads].
refuse_claimed_source_exports(Spec) :-
    (   absolute_file_name(Spec, File,
                           [file_type(prolog), access(read), file_errors(fail)])
    ->  setup_call_cleanup(open(File, read, In),
                           refuse_claimed_stream_exports(In, File),
                           close(In))
    ;   true
    ).

refuse_claimed_string_exports(Name, Text) :-
    setup_call_cleanup(open_string(Text, In),
                       refuse_claimed_stream_exports(In, Name),
                       close(In)).

refuse_claimed_stream_exports(In, File) :-
    canonical_prolog_source(File, Source),
    read_declarations(In, Declarations),
    findall(Name, member(export(Name), Declarations), Names),
    forall(member(Name, Names), refuse_reserved_registration(Name)),
    forall(member(Name, Names), refuse_other_tiers_name(Name, prolog)),
    forall(member(Name, Names), refuse_other_sources_name(Name, Source)).

%Everything a source DECLARES, read without running it: export(Name) for each
%name it publishes and extension(Name) for each extension it joins. Both
%consumers of the scan filter this rather than reading the file twice.
metta_source_declarations(Spec, Declarations) :-
    (   absolute_file_name(Spec, File,
                           [file_type(prolog), access(read), file_errors(fail)])
    ->  setup_call_cleanup(open(File, read, In),
                           read_declarations(In, Declarations),
                           close(In))
    ;   Declarations = []
    ).

metta_string_declarations(Text, Declarations) :-
    setup_call_cleanup(open_string(Text, In),
                       read_declarations(In, Declarations),
                       close(In)).

read_declarations(In, Declarations) :-
    (   read_one_declaration(In, Some)
    ->  read_declarations(In, Rest),
        append(Some, Rest, Declarations)
    ;   Declarations = []
    ).

%One term. quiet rather than dec10 on purpose: a syntax error here is not this
%predicate's to report, the consult that follows reports it properly and with
%the line, so the scan goes quiet and stops rather than printing a second copy.
read_one_declaration(In, Declarations) :-
    catch(read_term(In, Term, [syntax_errors(quiet), variable_names(_)]),
          _, fail),
    Term \== end_of_file,
    declaration_of(Term, Declarations).

declaration_of((:- metta_extension(Name, _)), [extension(Name)]) :-
    atom(Name), !.
declaration_of((:- metta_export(Text)), Names) :-
    ( string(Text) ; atom(Text) ),
    !,
    catch(parse_metta_source(Text, Forms), _, fail),
    findall(export(Name), claimed_export_name(Forms, Name), Names).
declaration_of(_, []).

%The two forms that CLAIM a name. volatility and determinism state a property
%of a name claimed elsewhere, so they are not a claim to refuse.
claimed_export_name(Forms, Name) :-
    member(Parsed, Forms),
    parsed_form_parts(Parsed, _, _, Term),
    ( Term = [':', Name, [->|_]] ; Term = [export, Name, Arity], integer(Arity) ),
    atom(Name).

%The same load, importing chosen exports under chosen names. SWI's own import
%list carries the renaming, so two libraries that both export norm/2 can both
%be present: the second arrives as mylib-norm and neither is rebound. Without
%it SWI refuses the second import, prints "No permission to import
%libb:'norm'/2 into user (already imported from liba)" and CONTINUES, which
%leaves the incumbent protected and the newcomer silently bound to the
%incumbent's code. That is the one collision a name refusal cannot fix, since
%neither library is wrong and neither can be asked to change.
%
%Loaded twice on purpose: with an empty import list first, so the module
%exists and can be asked what it exports, and then with the renames built from
%those arities. A caller therefore writes two names and no arity.
use_module_global(File, Renames) :-
    %SWI reaches a plain file first and raises domain_error(module_header, _),
    %which says what is wrong and not what to do about it.
    catch(loading_loudly(user:use_module(File, [])),
          error(domain_error(module_header, _), _),
          throw(error(petta_not_a_prolog_module(File),
                      context(use_module_global/2,
                              'renaming imports needs a module')))),
    module_exports_of(File, Module, Exports),
    maplist(renamed_import(Module, Exports), Renames, Imports),
    loading_loudly(user:use_module(File, Imports)),
    register_pending_exports.

module_exports_of(File, Module, Exports) :-
    absolute_file_name(File, Resolved,
                       [file_type(prolog), access(read), file_errors(fail)]),
    (   module_property(Module, file(Resolved))
    ->  module_property(Module, exports(Exports))
    ;   throw(error(petta_not_a_prolog_module(File),
                    context(use_module_global/2,
                            'renaming imports needs a module')))
    ).

%A name the module does not export cannot be imported under any name, and
%saying so with the export list is the difference between fixing a typo and
%guessing at one.
renamed_import(Module, Exports, Rename, Name/Arity as To) :-
    rename_pair(Rename, From0, To0),
    petta_name_atom(From0, Name),
    petta_name_atom(To0, To),
    (   memberchk(Name/Arity, Exports)
    ->  true
    ;   throw(error(petta_not_exported(Module, Name, Exports),
                    context(use_module_global/2,
                            'a rename names an export')))
    ).

%A rename is written From-To in Prolog and arrives as [From, To] from Python,
%since Janus carries a list and not a pair. Clauses rather than an
%if-then-else, so the two names are bound on every branch that reaches a use.
rename_pair(From-To, From, To) :- !.
rename_pair([From, To], From, To) :- !.
rename_pair(Rename, _, _) :-
    throw(error(type_error(petta_rename, Rename),
                context(use_module_global/2,
                        'a rename is From-To or [From, To]'))).

petta_name_atom(Name0, Name) :-
    ( atom(Name0) -> Name = Name0 ; atom_string(Name, Name0) ).

%The same load for source held in memory, which is how a library ships Prolog
%inline beside its Python. Name identifies the source location of the loaded
%clauses and is also what SWI removes clauses under when the same name is
%loaded again, so it has to be derived from the CONTENT: an address, which is
%what the caller used to pass, is reused by CPython the moment the string it
%named is freed, and the second registration then erased the first library's
%clauses [source: SWI-Prolog 10.1 Reference Manual, load_files/2, stream/1].
consult_string_global(Name, Text) :-
    refuse_claimed_string_exports(Name, Text),
    setup_call_cleanup(open_string(Text, In),
                       loading_loudly(user:load_files(Name, [stream(In)])),
                       close(In)),
    register_pending_exports.

%Raise what SWI would only have printed. A syntax error inside a consulted
%file goes through print_message/2 and the load then SUCCEEDS with the
%predicate undefined, so a library author's whole diagnostic was one line on
%stderr while the API reported success:
%  ERROR: .../lib.pl:1:28: Syntax error: Operator expected
%and register_prolog then said "no predicate named 'f' was defined by that
%source", which names the symptom and not the cause. Wrapping the load in
%catch/3 does not help, because these are printed rather than thrown.
%
%thread_message_hook/3 is SWI's own answer for exactly this, "intended to
%catch messages that may be produced by calling some goal without affecting
%other threads", and being thread-local is what lets a Pool worker load a file
%without collecting another worker's messages
%[source: SWI-Prolog 10.1 Reference Manual, section 4.11, message_hook/3].
%
%Only error-kind messages are collected. A warning is not a failed load:
%singleton variables are a style note, and the redefinition warning that
%matters is caught positively instead, by asking after the load whether each
%name resolves where it should [tested: a_syntax_error_in_a_library_raises].
:- thread_local petta_load_diagnostic/1, petta_watching_load/0.
:- multifile user:thread_message_hook/3.
user:thread_message_hook(Term, error, _Lines) :-
    petta_watching_load,
    message_to_string(Term, Text),
    assertz(petta_load_diagnostic(Text)),
    %Fail deliberately: SWI still prints the message with its full context,
    %and the throw below carries the summary a caller can act on.
    fail.

:- meta_predicate loading_loudly(0).
loading_loudly(Goal) :-
    setup_call_cleanup(( retractall(petta_load_diagnostic(_)),
                         assertz(petta_watching_load) ),
                       Goal,
                       retractall(petta_watching_load)),
    findall(Text, petta_load_diagnostic(Text), Diagnostics),
    retractall(petta_load_diagnostic(_)),
    (   Diagnostics == []
    ->  true
    ;   atomic_list_concat(Diagnostics, '; ', Summary),
        throw(error(petta_load_failed(Summary),
                    context(loading_loudly/1,
                            'the Prolog source reported an error while loading')))
    ).
%A predicate term headed by a space is a provider query, not a raw Prolog
%call into the module where native atoms happen to be stored. Other heads keep
%the Prolog interop constructor's original meaning.
metta_predicate_goal([Space|Pattern],
                     match(Space, Pattern, matched, matched)) :-
    petta_space_name(Space), !.
metta_predicate_goal([F|Args], Term) :- Term =.. [F|Args].

'Predicate'(Parts, _) :- var(Parts), !, refuse_unbound_input('Predicate', 1).
'Predicate'(Parts, Term) :- metta_predicate_goal(Parts, Term).
%Resolved in the CALLING space's module, which reaches both directions of this
%seam: a host Prolog predicate through the module's base chain, and a MeTTa
%function this space compiled, which lives in that module and nowhere else.
%Called unqualified it resolved in the engine's own module, so
%`(callPredicate (Predicate (myAddMeTTa 241 $x)))` over a function the program
%had just defined raised Unknown procedure
%[tested: examples/integration/prologimport.metta].
%
%assertaPredicate/2 and its siblings deliberately do NOT follow: a clause a
%MeTTa program asserts is host Prolog, it belongs in the host tier where
%consult_global/1 puts a consulted file, and import_prolog_function/2 looks
%for it there.
callPredicate(G, true) :- current_metta_module(Module), call(Module:G).
assertzPredicate(G, true) :- assertz(G).
assertaPredicate(G, true) :- asserta(G).
retractPredicate(G, true) :- retract(G), !.
retractPredicate(_, false).

%%% Library / Import: %%%
ensure_metta_ext(Path, Path) :- file_name_extension(_, gz, Path), !.
ensure_metta_ext(Path, Path) :- file_name_extension(_, metta, Path), !.
ensure_metta_ext(Path, PathWithExt) :- file_name_extension(Path, metta, PathWithExt).

current_working_dir(Base) :- working_dir(Base), !.
current_working_dir(Base) :- absolute_file_name('.', Base, [file_type(directory)]).

import_file_string(File, SFile) :- string(File), !, SFile = File.
import_file_string(File, SFile) :- atom_string(File, SFile).


resolve_existing_import_path(Base, RequestedPath, CanonPath) :-
    ( is_absolute_file_name(RequestedPath)
      -> absolute_file_name(RequestedPath, CanonPath,
                            [access(read), file_errors(fail)])
       ; absolute_file_name(RequestedPath, CanonPath,
                            [relative_to(Base), access(read), file_errors(fail)]) ),
    !.

throw_missing_import(File) :-
    throw(error(existence_error(source_sink, File), context('import!', File))).

resolve_metta_import_path(File, CanonPath) :-
    import_file_string(File, SFile),
    metta_module_path(SFile, Base, Relative),
    ensure_metta_ext(Relative, RequestedPath),
    ( resolve_existing_import_path(Base, RequestedPath, CanonPath)
      -> true
       ; throw_missing_import(File) ).

%`include` PASTES a module's source into the space that included it and
%answers what its LAST directive answered, where import! gives the file its
%own space and answers unit. A module with no directive answers nothing, and
%facts join the including space in order, each directive evaluating against
%the state built so far
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, the include
%dispatch, whose Type line is `(-> Atom %Undefined%)`;
%tests/semantics/modules/04-include-no-directive.metta and
%05-include-directive.metta, both STATUS conforms].
%
%`self` and `top` are BASES rather than modules, so including one is refused
%in upstream's own words, and so is a name that resolves to nothing
%[measured 2026-08-19 against the arbiter: `!(include nosuchfile)` answers
%`(Error (include nosuchfile) no module named nosuchfile is available)`].
include(Module, Answer) :-
    (   metta_include_refusal(Module, Reason)
    ->  metta_error_atom(include, [Module], Reason, Answer)
    ;   current_metta_space(Space),
        resolve_metta_import_path(Module, Path),
        load_metta_source_groups(Path, Space, Groups),
        last(Groups, Last),
        member(Carried, Last),
        metta_answer_term(Carried, Answer)
    ).

metta_include_refusal(Module, "include: the running context is not a module") :-
    % policy-inventory-exempt: arbiter-owned-language-law; reason=self and top denote module path bases and cannot themselves be included; evidence=engine/metta.pl:metta_include_refusal/2
    memberchk(Module, [self, top]), !.
metta_include_refusal(Module, Reason) :-
    \+ catch(resolve_metta_import_path(Module, _), _, fail),
    format(string(Reason), "no module named ~w is available", [Module]).

%A module NAME may be a COLON PATH. `pkg:child` names pkg/child.metta beside
%the file that imports it, `top:` names the OUTERMOST module's directory and
%`self:` the importing module's own, which is also what a bare name means
%[source: LeaTTa tests/semantics/modules/22-path-colon.metta,
%23-path-top.metta and 24-path-self.metta, all STATUS conforms; the third
%imports `self:child` from inside a module the first level already reached].
%
%A name carrying a separator ALREADY is a path and is left alone, which is the
%whole guard: nothing that resolved before resolves somewhere else now
%[tested: module_colon_paths].
metta_module_path(SFile, Base, Relative) :-
    \+ sub_string(SFile, _, _, _, "/"),
    sub_string(SFile, _, _, _, ":"),
    split_string(SFile, ":", "", Segments0),
    module_path_base(Segments0, Which, Segments),
    Segments \== [],
    !,
    metta_import_base(Which, Base),
    atomic_list_concat(Segments, '/', Relative).
metta_module_path(SFile, Base, SFile) :- current_working_dir(Base).

module_path_base(["top"|Segments], top, Segments) :- !.
module_path_base(["self"|Segments], self, Segments) :- !.
module_path_base(Segments, self, Segments).

%working_dir/1 is a stack kept by asserta/1, so its FIRST solution is the file
%being loaded and its last is the module the load started from.
metta_import_base(self, Directory) :- current_working_dir(Directory).
metta_import_base(top, Directory) :-
    findall(Held, working_dir(Held), Directories),
    (   last(Directories, Directory)
    ->  true
    ;   current_working_dir(Directory)
    ).


:- dynamic imported_metta_source/2.
:- dynamic import_life/3.

%Import state cannot live as a clause of the space predicate: wildcard
%remove-atom retracts every unifying clause, including rules. Loading is
%visible while recursive imports run so cycles terminate; success changes the
%state to loaded. A full space clear owns removal of both states.
import_life_current(Space, CanonPath) :-
    petta_space_name(Space), !,
    import_life(Space, CanonPath, _).
import_life_current(_, _).

assert_import_life_marker(Space, CanonPath, Ref) :-
    petta_space_name(Space), !,
    assertz(import_life(Space, CanonPath, loading), Ref).
assert_import_life_marker(_, _, none).

erase_import_life_marker(none) :- !.
erase_import_life_marker(Ref) :-
    ( clause_property(Ref, erased) -> true ; erase(Ref) ).

finish_import_life(_, _, none, _) :- !.
finish_import_life(Space, CanonPath, Ref, exit) :- !,
    erase_import_life_marker(Ref),
    assertz(import_life(Space, CanonPath, loaded)).
finish_import_life(_, _, Ref, _) :-
    erase_import_life_marker(Ref).

run_with_import_life_marker(Space, CanonPath, Goal) :-
    setup_call_catcher_cleanup(
        assert_import_life_marker(Space, CanonPath, Ref),
        once(Goal),
        Catcher,
        finish_import_life(Space, CanonPath, Ref, Catcher)).

clear_import_life(Space, CanonPath) :-
    ( petta_space_name(Space)
    -> retractall(import_life(Space, CanonPath, _))
    ;  true
    ).

% Assert both markers before loading to break cycles. Retain them on success
% and retract them on failure. The recursive mutex serializes the loader graph.
%
%Whether an already-loaded file loads AGAIN is a condition, and the condition
%is named at the call site rather than fixed here, which is how SWI writes the
%same choice: load_files/2 takes if(Condition), and `not_loaded loads the file
%if it was not loaded before` while `changed loads the file if it was not
%loaded before or has been modified since it was loaded the last time`
%[source: SWI-Prolog 10.1 Reference Manual, load_files/2]. consult/1 is
%if(true), ensure_loaded/1 is if(not_loaded), and make/0 is what if(changed)
%is for.
%
%import! takes `changed`, so an edited file is picked up where before the
%import was skipped and the edit silently ignored. An UNCHANGED repeat is
%still skipped, which is what keeps the arbiter's measured behaviour: two
%imports of the same module with different destination tokens execute its
%source once [source: LeaTTa tests/semantics/modules/30-resolution-loaded,
%M30 conforms; its own evidence records that neither stdlib.md nor the module
%tutorial states a reload policy, so the edited case is ours to decide].
%
%A Python source takes `not_loaded`. Re-executing a module body over a live
%sys.modules entry is a different operation with different hazards, and
%importlib.reload/1 is what would implement it; nothing here pretends to.
%
%The Python library's load() takes `true`, and takes it through here rather
%than around it: that is what puts the two doors on one record, so an import!
%of a file load() already read is skipped as loaded rather than run a second
%time [tested: test_a_file_the_library_loaded_is_already_imported].
%A GOAL argument crossing a module boundary has to carry its module, and this
%one crosses two: engine/filereader.pl hands import_when/4 a goal of its own,
%and the loading and life markers pass it on. Without the declarations the goal
%travelled unqualified and was called in THIS module, where the loader's
%internals are invisible, so a grouped load raised
%existence_error(procedure, load_imported_metta_source_groups/3)
%[measured 2026-08-22, once engine/filereader.pl became a module].
:- meta_predicate import_when(+, +, +, 0),
                  run_with_import_life_marker(+, +, 0).

import_when(Condition, Space, CanonPath, Goal) :-
    (   import_load_needed(Condition, Space, CanonPath)
    ->  retractall(imported_metta_source(Space, CanonPath)),
        clear_import_life(Space, CanonPath),
        run_with_loading_marker(
            imported_metta_source(Space, CanonPath),
            run_with_import_life_marker(Space, CanonPath, Goal))
    ;   true
    ).

%SWI's three if(Condition) values, asked as a question about THIS load rather
%than about the previous one.
import_load_needed(true, _, _).
import_load_needed(not_loaded, Space, CanonPath) :-
    \+ ( imported_metta_source(Space, CanonPath),
         import_life_current(Space, CanonPath) ).
import_load_needed(changed, Space, CanonPath) :-
    (   import_load_needed(not_loaded, Space, CanonPath)
    ->  true
    ;   metta_source_changed(CanonPath)
    ).


%The UNIT value, for the reason add-atom and pragma! answer it: importing is
%an effect and `()` is what the arbiter records for every one of its module
%transcripts [source: LeaTTa tests/semantics/modules/18-direct-import-control
%and 20-cycle-control, both `[()]`].
'import!'(Space, File, []) :-
    metta_require_space_update_capability('import!', Space),
    importer_helper(Space, File).
%`(: import! (-> Atom Atom Bool))` says both arguments arrive UNREDUCED, which
%is right: a module name is a name and evaluating it would look for a function
%called `lib_constraints`. So the forms a module name can take are resolved
%here rather than by the call site.
%
%`(library Name)` is the one form that needs it, and it used to work by
%accident: the call site evaluated the argument because the Atom mask was not
%honoured for builtins, so library/2 ran before import! ever saw it. With the
%mask honoured the form arrives whole, and resolving it is import!'s job.
importer_helper(Space, File0) :-
    resolve_module_form(File0, File),
    with_mutex(metta_loader, importer_helper_impl(Space, File)).

resolve_module_form(Form, Path) :-
    nonvar(Form), Form = [library, Name], !,
    library(Name, Path).
%A BUILT-IN MODULE is one the engine ships, named directly rather than by
%path: `!(import! &self skel)` is the arbiter's own spelling and upstream
%loads six of them at startup [source: LeaTTa
%MettaHyperonFull/Minimal/Interpreter.lean, builtinModules]. Resolved BEFORE
%the filesystem, because the name is the module's identity rather than a path
%a program may happen to have a file for, which is also what makes the same
%import work from inside another module with its own working directory
%[tested: builtin_modules] [source: LeaTTa tests/semantics/grounded/
%28-builtin-module-skel.metta and modules/35-builtin-from-module].
resolve_module_form(Form, Path) :-
    atom(Form), metta_builtin_module(Form, Relative),
    metta_top_context, !,
    library(Relative, Path).
resolve_module_form(Form, Form).

%The modules this engine ships, one row each. `skel` is upstream's own
%skeleton and the only one of its six that uses every tier at once: three
%declarations, one MeTTa equation and one grounded operation. Upstream's
%`load_builtin_mods` also registers `json`, `fileio`, `catalog` and `das`, and
%those are libraries this engine does not implement; registering a name so
%that an import succeeds while every operation behind it silently fails is the
%graceful degradation this repository refuses, so they stay unresolvable and
%say so [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, the note
%above builtinModules, which makes the same decision].
metta_builtin_module(skel, 'builtin_mods/skel.metta').

%A built-in module is a child of the TOP, so its bare name means one only when
%the import is written at the top. Inside a module the same name is relative to
%that module, `skel` written in `usesskel` means `top:usesskel:skel`, which no
%built-in is, and the import fails. Comparing the written name before anything
%else gets this wrong in a way that is worse than a plain refusal: the import
%reports success and a call to the module's operation is still unreduced,
%because admission is tested against the running context and the import went
%somewhere else [source: LeaTTa tests/semantics/modules/35-builtin-from-module,
%whose PURPOSE is exactly that trap; both engines refuse there and differ only
%in the wording]
%[tested: a_module_cannot_reach_a_builtin_by_its_bare_name].
%
%working_dir/1 is the load stack, one entry per file being loaded, so the
%outermost file is depth one and anything it imports is deeper.
metta_top_context :-
    findall(Held, working_dir(Held), Directories),
    length(Directories, Depth),
    Depth =< 1.
%A HOST claims and performs an import whose source is its own kind of
%file, through the ownership seam; with no host loaded, or none claiming,
%every import is a MeTTa import. The claiming clause does the whole job,
%lifecycle included, through the same published import_when/4 the engine
%uses itself.
importer_helper_impl(Space, File) :-
    ( seam:host_import(File)
      -> true
       ; resolve_metta_import_path(File, CanonPath),
         import_when(changed, Space, CanonPath,
                     load_imported_metta_file(CanonPath, _, Space)) ).
