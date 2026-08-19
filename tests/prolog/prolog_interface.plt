% Purpose: the Prolog interface, which is how a library author gets native
%   speed without forking the engine and without paying for Python. It had no
%   suite of its own, and the two ways it can silently do the wrong thing were
%   both live.
% Guarantees:
%   - a registered predicate is callable from MeTTa and keeps its
%     nondeterminism [tested: a_prolog_predicate_keeps_its_nondeterminism]
%   - registering a name with no predicate behind it RAISES rather than
%     recording no arity and compiling every later call into a partial
%     application [tested: an_absent_predicate_is_refused]
%   - importing a file that is not there raises and names the path
%     [tested: a_missing_file_is_named]
%   - a registration keeps answering after a named space defines an equation
%     of the same name, and that space's own equation shadows it
%     [tested: a_registered_predicate_survives_a_named_space_claiming_its_name]
%   - a registration records its arities even when the name is already a
%     function
%     [tested: a_registration_records_arities_for_a_name_that_is_already_a_function]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

user:'plunit-pi-tag'(X, Y) :- member(X, [a, b, c]), atom_concat(X, '!', Y).
user:'plunit-pi-is-b'(b).

% In user, not in the plunit unit's module, because that is where a consulted
% Prolog library lands and where register_fun/1 reads arities from. Defining
% them inside the unit made every registration raise, which is the interface
% working: src/metta.pl already warned that a library defining itself outside
% user has its arities go unregistered and every call compile to a partial
% application. The guard now turns that silent wrong answer into an error.
user:plunit_pi_double(X, Y) :- Y is X * 2.
user:plunit_pi_pick(X, Y) :- member(Y, [X, X, X]).
user:plunit_pi_scale(X, Y) :- Y is X * 10.
user:plunit_pi_known(X, Y, Z) :- Z is X + Y.
user:plunit_pi_first(X, X).
user:plunit_pi_second(X, X).

% A registration is process-wide, so a test that makes one has to undo it or
% the next test inherits it. Everything register_fun_in/2 and
% register_prolog_arities/1 assert, in one place.
forget_pi_name(Name) :-
    unregister_fun_everywhere(Name),
    retractall(fun(Name)),
    retractall(arity(Name, _)).

:- begin_tests(prolog_interface).

test(a_registered_predicate_becomes_a_metta_function) :-
    import_prolog_function(plunit_pi_double, true),
    reduce([plunit_pi_double, 21], Out, _),
    Out == 42.

% The reason the interface is worth having at all: a Prolog predicate's own
% nondeterminism becomes the MeTTa function's answer set, with nothing in
% between.
% EXTENDING.md teaches both directions of this and neither had a test. It is
% the whole reason callPredicate is not needed for either shape, so the page
% telling an author to reach for `let` first rests on it.
%
% A registered predicate BINDS a caller's unbound argument, and the binding
% escapes into the MeTTa program rather than staying inside the call.
test(a_registered_predicate_binds_a_callers_variable) :-
    import_prolog_function('plunit-pi-tag', _),
    % Through the source pipeline, because let and collapse are special forms
    % the TRANSLATOR handles; reduce/3 takes an already-compiled call.
    process_metta_string("!(collapse (let $y (plunit-pi-tag $x) ($x $y)))",
                         [Pairs]),
    assertion(Pairs == [[a, 'a!'], [b, 'b!'], [c, 'c!']]).

% And the output slot takes an input, which is how a predicate whose single
% argument is an INPUT is called at all: its MeTTa arity is zero, and a let
% unifies the value into the slot. lib/lib_import.metta relies on this.
test(the_output_slot_takes_an_input) :-
    import_prolog_function('plunit-pi-is-b', _),
    process_metta_string("!(collapse (let b (plunit-pi-is-b) matched))", [Hit]),
    assertion(Hit == [matched]),
    process_metta_string("!(collapse (let z (plunit-pi-is-b) matched))", [Miss]),
    assertion(Miss == []).

test(a_prolog_predicate_keeps_its_nondeterminism) :-
    import_prolog_function(plunit_pi_pick, true),
    findall(Y, reduce([plunit_pi_pick, 7], Y, _), Answers),
    Answers == [7, 7, 7].

% register_fun/1 reads arities out of current_predicate/1. A name with nothing
% behind it records NO arity, and every call to it then compiles to a partial
% application rather than failing, so (no-such-predicate 1) answered
% (partial no-such-predicate (1)) and reported success on the way in.
test(an_absent_predicate_is_refused,
     [throws(error(existence_error(procedure, plunit_pi_absent), _))]) :-
    import_prolog_function(plunit_pi_absent, true).

test(a_refused_name_is_not_registered) :-
    catch(import_prolog_function(plunit_pi_absent_two, true), _, true),
    \+ fun(plunit_pi_absent_two).

% consult/1 throws existence_error(source_sink, Path) and names the file. An
% exists_file/1 guard in lib_import.metta used to swallow that, leaving a
% missing file as silent failure with no answer and no error.
test(a_missing_file_is_named,
     [throws(error(existence_error(source_sink, '/nonexistent/petta/none.pl'), _))]) :-
    consult_global('/nonexistent/petta/none.pl').

test(registering_the_same_name_twice_is_idempotent) :-
    import_prolog_function(plunit_pi_double, true),
    import_prolog_function(plunit_pi_double, true),
    findall(x, fun(plunit_pi_double), Registrations),
    Registrations == [x].

test(a_non_atom_name_is_refused,
     [throws(error(type_error(atom, 42), _))]) :-
    import_prolog_function(42, true).

% A predicate defined outside user is refused, which is the hazard
% src/metta.pl documents: register_fun/1 reads arities out of user, so a
% library that defines itself elsewhere registers no arity and every call to
% it compiles to a partial application instead of failing.
test(a_predicate_outside_user_is_refused,
     [setup(assertz(plunit_pi_elsewhere:plunit_pi_hidden(1))),
      cleanup(abolish(plunit_pi_elsewhere:plunit_pi_hidden/1)),
      throws(error(existence_error(procedure, plunit_pi_hidden), _))]) :-
    import_prolog_function(plunit_pi_hidden, true).

% The whole point of the interface: a registered predicate is called directly,
% with no boundary in between. A Prolog predicate and a MeTTa function of the
% same shape cost the same per call, and both cost a fraction of a Python
% operation [measured 2026-08-15: 8.15 inferences for Prolog against 26.15 for
% a Python op, 3.2x].
test(a_registered_predicate_costs_no_more_than_a_metta_function) :-
    import_prolog_function(plunit_pi_double, true),
    statistics(inferences, I0),
    forall(between(1, 2000, _), reduce([plunit_pi_double, 21], _, _)),
    statistics(inferences, I1),
    PerCall is (I1 - I0) / 2000,
    assertion(PerCall < 30).

% A registration used to record fun/1 and nothing about where the clauses
% live, so it resolved only through fun_here/1's first clause, \+ fun_scoped.
% Any named space defining an equation of the same name set fun_scoped and the
% registered predicate became inert data in EVERY space, with no error:
% !(rp-norm 3) answered (rp-norm 3) from code that had not changed. It is
% order-dependent, so clauses compiled before the named space kept working and
% anything compiled after did not.
test(a_registered_predicate_survives_a_named_space_claiming_its_name,
     [ cleanup(forget_pi_name(plunit_pi_scale)) ]) :-
    import_prolog_function(plunit_pi_scale, true),
    sread("(= (plunit_pi_scale $x) 999)", Equation),
    'add-atom'('&plunit_pi_kb', Equation, _),
    space_module('&plunit_pi_kb', Kb),
    metta_self_module(Self),
    with_metta_module(Self, reduce([plunit_pi_scale, 3], InSelf, _)),
    with_metta_module(Kb, reduce([plunit_pi_scale, 3], InKb, _)),
    % &self answers from the registered predicate, and the space that defined
    % the equation shadows it, which is the behaviour that should happen.
    assertion(InSelf == 30),
    assertion(InKb == 999).

% The arity walk used to sit behind register_fun/1's "the name is new" guard,
% so registering a predicate for a name some space already defined recorded no
% arity at all and incomplete_application_kind/3 read that as "not applied far
% enough": the call compiled to a partial application instead of running.
test(a_registration_records_arities_for_a_name_that_is_already_a_function,
     [ cleanup(forget_pi_name(plunit_pi_known)) ]) :-
    'add-atom'('&plunit_pi_kb2', [=, [plunit_pi_known], 1], _),
    assertion(fun(plunit_pi_known)),
    import_prolog_function(plunit_pi_known, true),
    assertion(arity(plunit_pi_known, 3)),
    metta_self_module(Self),
    with_metta_module(Self, reduce([plunit_pi_known, 4, 5], Out, _)),
    assertion(Out == 9).

:- end_tests(prolog_interface).

:- begin_tests(prolog_interface_refusals).

% A consulted predicate REPLACES the engine's static one for the whole
% process, so a library registering a predicate named + made !(+ 1 2) answer
% whatever the library said. The only diagnostic was SWI's redefinition
% warning on stderr and the API reported success.
test(a_builtin_name_is_refused,
     [throws(error(permission_error(register, metta_builtin, '+'), _))]) :-
    import_prolog_function('+', true).

% Special forms are tried BEFORE function dispatch, so a registration under
% one of their names compiles nothing and can never be reached. Accepting it
% told the author their code was installed when it was dead.
test(a_special_form_name_is_refused,
     [throws(error(permission_error(register, metta_special_form, 'if'), _))]) :-
    import_prolog_function(if, true).

% Order is the whole finding. Checking per name inside the registration loop
% ran AFTER the source had loaded, and by then SWI had already replaced the
% engine's own predicate, so the refusal was true and useless.
test(a_reserved_name_is_refused_before_the_source_loads,
     [ setup(tmp_file_stream(text, Path, Stream)),
       cleanup(delete_file(Path)) ]) :-
    format(Stream, "'car-atom'(_, R) :- R = shadowed.~n", []),
    close(Stream),
    % The two goals lib_import.metta's equation compiles to, in order. The
    % check has to come first: run the other way round, the consult has
    % already replaced the engine's static car-atom/2 by the time any refusal
    % can fire, and the refusal is then true and useless.
    catch(( check_prolog_function_names(['car-atom'], 'plunit-nothing', _),
            consult_global(Path) ), Error, true),
    assertion(Error = error(permission_error(register, metta_builtin, 'car-atom'), _)),
    'car-atom'([1, 2], Head),
    assertion(Head == 1).

% fun/1 says a name is a function and fun_in/2 says where its clauses live;
% neither said which TIER put them there, so a Prolog registration over a live
% Python operation replaced the dispatch clause, left the bridge's registry
% still claiming the name, and wedged it: unregistering raised because the
% predicate had become static, and re-registering was refused for the same
% reason.
test(a_name_another_tier_owns_is_refused,
     [ setup(claim_function_name(plunit_pi_owned, python, det)),
       cleanup(release_function_name(plunit_pi_owned)),
       throws(error(permission_error(register, metta_function, plunit_pi_owned),
                    context(_, owned_by(python, det)))) ]) :-
    refuse_other_tiers_name(plunit_pi_owned, prolog).

test(the_same_tier_may_re_register) :-
    setup_call_cleanup(claim_function_name(plunit_pi_reclaim, python, det),
                       claim_function_name(plunit_pi_reclaim, python, many),
                       release_function_name(plunit_pi_reclaim)).

test(a_typo_in_the_list_registers_nothing,
     [ cleanup(( forget_pi_name(plunit_pi_first),
                 forget_pi_name(plunit_pi_second) )),
       throws(error(existence_error(procedure, plunit_pi_typo), _)) ]) :-
    import_prolog_functions([plunit_pi_first, plunit_pi_second, plunit_pi_typo],
                            true).

test(nothing_from_a_refused_list_is_registered) :-
    catch(import_prolog_functions([plunit_pi_first, plunit_pi_second,
                                   plunit_pi_typo], true), _, true),
    assertion(\+ fun(plunit_pi_first)),
    assertion(\+ fun(plunit_pi_second)).

% SWI PRINTS a syntax error inside a consulted file and the load then
% succeeds with the predicate undefined, so wrapping the load in catch/3
% caught nothing and the author's whole diagnostic was one line on stderr.
test(a_syntax_error_in_a_library_raises,
     [ setup(tmp_file_stream(text, Path, Stream)),
       cleanup(delete_file(Path)) ]) :-
    format(Stream, "plunit_pi_bad(X, Y) :- Y is X * .~n", []),
    close(Stream),
    catch(consult_global(Path), Error, true),
    assertion(Error = error(petta_load_failed(_), _)),
    Error = error(petta_load_failed(Summary), _),
    assertion(sub_string(Summary, _, _, _, "Syntax error")).

:- end_tests(prolog_interface_refusals).

:- begin_tests(prolog_interface_determinism).

% reduce/3 is the dispatch every registered predicate is reached through. A
% choice point here defeats last call optimisation in the caller, and a
% recursive walk then retains a frame per element [measured 2026-08-15: a
% 200,000 element map-atom through this path held 86,400,000 bytes of local
% stack before the dispatch was made deterministic, and 0 after].
test(the_dispatch_leaves_no_choicepoint) :-
    import_prolog_function(plunit_pi_double, true),
    call_cleanup(reduce([plunit_pi_double, 21], _, _), Flag = done),
    ( var(Flag) -> Left = true ; Left = false ),
    Left == false.

test(a_nondeterministic_predicate_still_offers_its_answers) :-
    import_prolog_function(plunit_pi_pick, true),
    findall(Y, reduce([plunit_pi_pick, 7], Y, _), Answers),
    length(Answers, 3).

:- end_tests(prolog_interface_determinism).

:- begin_tests(prolog_interface_exports).

% Registering one predicate took three statements in two languages: the name
% in a call, the arity discovered by scanning whatever current_predicate/1
% happened to hold, and the type in a third statement whose ordering against
% call-site compilation nothing checked. A library shipping a public
% 'vec-dot'/3 and an internal helper 'vec-dot'/2 published both, because the
% arity was DISCOVERED. Here it is declared, and the declaration is the type,
% so the two cannot disagree.
export_library_source(
"'plunit-ex-scale'(X, Y) :- Y is X * 10.\n\c
 'plunit-ex-scale'(X, F, Y) :- Y is X * F.\n\c
 'plunit-ex-shape'(X, [shape, X]).\n\c
 'plunit-ex-plain'(X, X).\n\c
 'plunit-ex-helper'(_, _, hidden).\n").

export_declaration(
"    (: plunit-ex-scale (-> Number Number))\n\c
     (: plunit-ex-shape (-> Atom Atom))\n\c
     (export plunit-ex-plain 1)\n").

setup_export_library :-
    export_library_source(Source),
    export_declaration(Declaration),
    tmp_file_stream(text, Path, Stream),
    format(Stream, ":- metta_extension(plunit_ex, [version('0.1.0')]).~n", []),
    format(Stream, ":- metta_export(\"~w\").~n~n", [Declaration]),
    write(Stream, Source),
    close(Stream),
    nb_setval('$plunit_export_path', Path),
    consult_global(Path).

cleanup_export_library :-
    catch(unregister_metta_extension(plunit_ex), _, true),
    ( nb_current('$plunit_export_path', Path) -> delete_file(Path) ; true ),
    nb_delete('$plunit_export_path').

test(a_declared_export_registers_with_its_type,
     [setup(setup_export_library), cleanup(cleanup_export_library)]) :-
    reduce(['plunit-ex-scale', 3], Scaled, _),
    assertion(Scaled == 30),
    % The type travelled with the name, so the Atom parameter arrives as
    % written and the ordering trap I5 describes cannot open: there is no gap
    % between registering the name and declaring its type.
    reduce(['plunit-ex-shape', ['+', 1, 2]], Shape, _),
    assertion(Shape == [shape, ['+', 1, 2]]),
    % (export Name Arity) is the form for a name with no type to state.
    reduce(['plunit-ex-plain', 7], Plain, _),
    assertion(Plain == 7).

%The declaration says one arity and the engine used to publish every arity
%current_predicate/1 could see, so an INTERNAL overload of a declared name was
%callable from MeTTa: `(: plunit-ex-scale (-> Number Number))` beside a
%'plunit-ex-scale'/3 published both. Discovery on a route that has a
%declaration is the defect; the declared arity is in hand at that moment and is
%what gets registered now.
test(a_declared_export_publishes_only_its_declared_arity,
     [setup(setup_export_library), cleanup(cleanup_export_library)]) :-
    findall(A, user:arity('plunit-ex-scale', A), Arities),
    sort(Arities, Sorted),
    assertion(Sorted == [2]),
    reduce(['plunit-ex-scale', 3], Declared, _),
    assertion(Declared == 30),
    %and the internal overload is refused by name, as an ANSWER: the exported
    %arity is declared, so the wrong one is IncorrectNumberOfArguments
    findall(Refused, reduce(['plunit-ex-scale', 3, 7], Refused, _), Answers),
    assertion(Answers == [['Error', ['plunit-ex-scale', 3, 7],
                           'IncorrectNumberOfArguments']]).

test(an_undeclared_helper_is_not_published,
     [setup(setup_export_library), cleanup(cleanup_export_library)]) :-
    assertion(\+ fun('plunit-ex-helper')).

test(a_declaration_naming_an_arity_the_file_lacks_is_refused,
     [ cleanup(( catch(unregister_metta_extension(plunit_ex_bad), _, true),
                 delete_file(Path) )),
       throws(error(existence_error(procedure, 'plunit-ex-absent'/3), _)) ]) :-
    tmp_file_stream(text, Path, Stream),
    format(Stream, ":- metta_extension(plunit_ex_bad, []).~n", []),
    format(Stream,
           ":- metta_export(\"(: plunit-ex-absent (-> Number Number Number))\").~n",
           []),
    close(Stream),
    consult_global(Path).

% PostgreSQL's rule and its reason: an individual member cannot be dropped on
% its own, only the whole extension, which is what stops a registry keeping a
% claim on a name it can no longer release.
test(an_extension_unloads_whole,
     [setup(setup_export_library), cleanup(cleanup_export_library)]) :-
    unregister_metta_extension(plunit_ex),
    assertion(\+ fun('plunit-ex-scale')),
    assertion(\+ fun('plunit-ex-plain')),
    % The type declaration goes with it.
    assertion(\+ get_native_atom('&self', [':', 'plunit-ex-scale', _])),
    % And the clauses, so the name is not left callable through a predicate
    % nothing records.
    assertion(\+ current_predicate('plunit-ex-scale'/2)).

test(unloading_an_extension_that_is_not_there_raises,
     [throws(error(existence_error(metta_extension, plunit_ex_absent), _))]) :-
    unregister_metta_extension(plunit_ex_absent).

% A library built on today's ext_points.pl will be loaded into a later engine,
% and with nothing to check against a removed or renamed hook shows up as
% silence. Erlang's NIF loader is the model: the major must match and the minor
% must not be newer, or the load fails.
test(an_extension_written_against_a_later_seam_is_refused,
     [ cleanup(delete_file(Path)),
       throws(error(petta_extension_api_mismatch(plunit_future, 99-0, _), _)) ]) :-
    tmp_file_stream(text, Path, Stream),
    format(Stream, ":- metta_extension(plunit_future, [requires(99-0)]).~n", []),
    close(Stream),
    metta_extension(plunit_future, [requires(99-0)]).

% user: on every one of these. retractall/1 on a predicate the calling module
% cannot see CREATES it there as dynamic, so an unqualified retractall in a
% cleanup gives the plunit module its own empty metta_extension_info/3 and
% every later test in the unit reads that instead of the engine's.
% An extension is OPTIONAL, and a single-file library is the shape that leaves
% it out: one `metta_export` and the predicates under it. Everything about that
% file registered correctly and the engine had no record that answered which
% names it was, because the only record kept was extension MEMBERSHIP. The
% Python side read that and reported a registration that had already succeeded
% as a failure (I28). The per-file record is what makes the question answerable
% without making an extension mandatory.
test(a_declared_export_without_an_extension_reports_its_names,
     [ setup(setup_bare_export_library), cleanup(cleanup_bare_export_library) ]) :-
    nb_getval('$plunit_bare_path', Path),
    assertion(\+ user:metta_extension_info(_, Path, _)),
    findall(Name, user:metta_file_export(Path, Name), Names),
    sort(Names, Sorted),
    assertion(Sorted == ['plunit-bare-scale']),
    reduce(['plunit-bare-scale', 4], Scaled, _),
    assertion(Scaled == 40).

setup_bare_export_library :-
    tmp_file_stream(text, Path, Stream),
    format(Stream,
           ":- metta_export(\"(: plunit-bare-scale (-> Number Number))\").~n", []),
    format(Stream, "'plunit-bare-scale'(X, Y) :- Y is X * 10.~n", []),
    close(Stream),
    nb_setval('$plunit_bare_path', Path),
    consult_global(Path).

%Nothing owns a file that joined no extension, so the release is by name.
cleanup_bare_export_library :-
    catch(forget_registered_function('plunit-bare-scale'), _, true),
    ( nb_current('$plunit_bare_path', Path)
    -> retractall(user:metta_file_export(Path, _)), delete_file(Path)
    ;  true ),
    nb_delete('$plunit_bare_path').

test(an_extension_that_declares_nothing_still_loads,
     [ cleanup(retractall(user:metta_extension_info(plunit_silent, _, _))) ]) :-
    metta_extension(plunit_silent, []),
    assertion(user:metta_extension_info(plunit_silent, _, [])).

test(an_extension_within_the_seam_loads,
     [ cleanup(retractall(user:metta_extension_info(plunit_current, _, _))) ]) :-
    metta_extension_api_version(Major, Minor),
    metta_extension(plunit_current, [requires(Major-Minor)]),
    assertion(user:metta_extension_info(plunit_current, _, _)).

:- end_tests(prolog_interface_exports).

:- begin_tests(prolog_interface_namespacing).

% Two libraries each shipping 'shared-norm'/2: the second SILENTLY replaced the
% first, because a consulted file redefines a static predicate of the same name
% and SWI only warns, on stderr, where no caller sees it. Library A's answer
% changed from 20 to 30 the moment B loaded, and register_prolog reported
% success both times.
%
% The refusal necessarily fires after the consult. SWI prints rather than
% throws, so no catch/3 can see the redefinition and a positive check
% afterwards is the only one that can: CPython's capsule discipline reaches
% the same answer for the same reason.
test(two_sources_cannot_claim_one_name,
     [ setup(( write_norm_library(20, PathA), write_norm_library(30, PathB) )),
       cleanup(( forget_pi_name('plunit-shared-norm'),
                 release_function_name('plunit-shared-norm'),
                 delete_file(PathA), delete_file(PathB) )) ]) :-
    consult_global(PathA),
    import_prolog_function('plunit-shared-norm', _),
    reduce(['plunit-shared-norm', 1], First, _),
    assertion(First == 20),
    consult_global(PathB),
    catch(import_prolog_function('plunit-shared-norm', _), Error, true),
    assertion(Error = error(petta_name_owned_by_source('plunit-shared-norm', _), _)).

test(the_same_source_may_register_again,
     [ setup(write_norm_library(20, Path)),
       cleanup(( forget_pi_name('plunit-shared-norm'),
                 release_function_name('plunit-shared-norm'),
                 delete_file(Path) )) ]) :-
    consult_global(Path),
    import_prolog_function('plunit-shared-norm', _),
    import_prolog_function('plunit-shared-norm', _),
    reduce(['plunit-shared-norm', 1], Answer, _),
    assertion(Answer == 20).

write_norm_library(Value, Path) :-
    tmp_file_stream(text, Path, Stream),
    format(Stream, "'plunit-shared-norm'(_, ~w).~n", [Value]),
    close(Stream).

% Refusing B after the consult told the WRONG author. B heard "already
% registered from A" and A, which did nothing, answered B's implementation
% from then on:
%
%     A before B      : 20
%     B refused       : petta_name_owned_by_source(...)
%     A AFTER refusal : 30      <- A was clobbered anyway
%
% The names are in hand before the load on this route, so the refusal belongs
% beside the builtin and special-form ones, where it prevents rather than
% reports.
test(a_name_another_source_owns_is_refused_before_the_load,
     [ setup(( write_norm_library(20, PathA), write_norm_library(30, PathB) )),
       cleanup(( forget_pi_name('plunit-shared-norm'),
                 release_function_name('plunit-shared-norm'),
                 delete_file(PathA), delete_file(PathB) )) ]) :-
    consult_global(PathA),
    import_prolog_function('plunit-shared-norm', _),
    catch(check_prolog_function_names(['plunit-shared-norm'], PathB, _),
          Error, true),
    assertion(Error = error(petta_name_owned_by_source('plunit-shared-norm', PathA), _)),
    % B never loaded, so A still answers its own number.
    reduce(['plunit-shared-norm', 1], Answer, _),
    assertion(Answer == 20).

test(the_same_source_passes_the_pre_load_check,
     [ setup(write_norm_library(20, Path)),
       cleanup(( forget_pi_name('plunit-shared-norm'),
                 release_function_name('plunit-shared-norm'),
                 delete_file(Path) )) ]) :-
    consult_global(Path),
    import_prolog_function('plunit-shared-norm', _),
    check_prolog_function_names(['plunit-shared-norm'], Path, _).

% The self-declaring route has no names to check until the file has run, and
% by then a clause of it has replaced the incumbent's predicate. So the
% manifest is read out of the source WITHOUT running the source, which is
% PostgreSQL's control file and Python's package metadata: the thing that says
% what a package provides is readable before the thing that installs it runs.
%
% A directive cannot do this job. One placed in metta_export/1 itself fired,
% was reported, and the load carried on to compile the clause anyway, because
% SWI reports a throwing directive and continues.
test(a_second_source_claiming_a_name_never_loads,
     [ setup(( write_declared_norm_library(20, top, PathA),
               write_declared_norm_library(30, top, PathB) )),
       cleanup(( forget_pi_name('plunit-declared-norm'),
                 release_function_name('plunit-declared-norm'),
                 delete_file(PathA), delete_file(PathB) )) ]) :-
    consult_global(PathA),
    reduce(['plunit-declared-norm', 1], First, _),
    assertion(First == 20),
    catch(consult_global(PathB), Error, true),
    assertion(Error = error(petta_name_owned_by_source('plunit-declared-norm', PathA), _)),
    reduce(['plunit-declared-norm', 1], Second, _),
    assertion(Second == 20).

% Same file, declaration UNDER the clauses. The scan reads the whole file, so
% position does not matter and the incumbent survives here too.
test(a_declaration_under_the_clauses_still_refuses,
     [ setup(( write_declared_norm_library(20, bottom, PathA),
               write_declared_norm_library(30, bottom, PathB) )),
       cleanup(( forget_pi_name('plunit-declared-norm'),
                 release_function_name('plunit-declared-norm'),
                 delete_file(PathA), delete_file(PathB) )) ]) :-
    consult_global(PathA),
    catch(consult_global(PathB), Error, true),
    assertion(Error = error(petta_name_owned_by_source('plunit-declared-norm', PathA), _)),
    reduce(['plunit-declared-norm', 1], Answer, _),
    assertion(Answer == 20).

% What the scan cannot see, the rollback catches. The declaration's text is
% BUILT here rather than written, so there is no literal for the scan to read
% and the refusal necessarily lands after the load. Then the file goes back
% out: unload_file/1 removes the clauses it brought, so the name is empty and
% loud rather than full and silently wrong.
test(a_computed_declaration_is_refused_and_its_source_unloaded,
     [ setup(( write_declared_norm_library(20, top, PathA),
               write_computed_norm_library(30, PathB) )),
       cleanup(( forget_pi_name('plunit-declared-norm'),
                 release_function_name('plunit-declared-norm'),
                 delete_file(PathA), delete_file(PathB) )) ]) :-
    consult_global(PathA),
    catch(consult_global(PathB), Error, true),
    assertion(Error = error(petta_name_owned_by_source('plunit-declared-norm', PathA), _)),
    % B's clauses went out with it, so nothing of B is left callable.
    assertion(\+ clause_from_file('plunit-declared-norm'/2, PathB)),
    % A still owns the name, and re-registering A is the documented recovery.
    assertion(metta_function_origin('plunit-declared-norm', prolog, PathA)),
    consult_global(PathA),
    reduce(['plunit-declared-norm', 1], Answer, _),
    assertion(Answer == 20).

clause_from_file(Name/Arity, File) :-
    functor(Head, Name, Arity),
    nth_clause(Head, _, Ref),
    clause_property(Ref, file(File)).

write_declared_norm_library(Value, Where, Path) :-
    Declaration = ':- metta_export("(: plunit-declared-norm (-> Number Number))").',
    format(atom(Clause), "'plunit-declared-norm'(_, ~w).", [Value]),
    ( Where == top -> Lines = [Declaration, Clause] ; Lines = [Clause, Declaration] ),
    tmp_file_stream(text, Path, Stream),
    forall(member(Line, Lines), format(Stream, "~w~n", [Line])),
    close(Stream).

%The same library with its declaration BUILT at load time, which is the one
%shape the scan cannot read: there is no literal string in the file.
write_computed_norm_library(Value, Path) :-
    format(atom(Clause), "'plunit-declared-norm'(_, ~w).", [Value]),
    Computed = ':- atom_concat(\'(: plunit-declared-norm \', \'(-> Number Number))\', T), metta_export(T).',
    tmp_file_stream(text, Path, Stream),
    forall(member(Line, [Clause, Computed]), format(Stream, "~w~n", [Line])),
    close(Stream).

% A library that pip-installs is under neither the engine's lib directory nor
% a git checkout, so (library f.pl) could not reach it and a package had to
% compute absolute paths from __file__ by hand.
test(a_registered_library_path_resolves,
     [ setup(( tmp_file(plunit_libdir, Dir), make_directory(Dir),
               directory_file_path(Dir, 'plunit_pkg.pl', File),
               setup_call_cleanup(open(File, write, S),
                                  write(S, "'plunit-pkg-op'(X, X).\n"),
                                  close(S)) )),
       cleanup(( retractall(user:file_search_path(plunit_pkg, _)),
                 delete_directory_and_contents(Dir) )) ]) :-
    register_metta_library_path(plunit_pkg, Dir, true),
    library(plunit_pkg, 'plunit_pkg.pl', Resolved),
    assertion(Resolved == File),
    % Idempotent, and a directory that is not there is refused.
    register_metta_library_path(plunit_pkg, Dir, true),
    findall(D, user:file_search_path(plunit_pkg, D), Paths),
    assertion(Paths == [Dir]).

% CPython's distinction, and the reason it matters: returning None from
% find_spec means "not mine, keep looking" and raising means "definitively
% absent", because "the latter indicates that the meta path search should
% continue, while raising an exception terminates it immediately". Failing was
% the keep-looking signal with nothing left to look with, so a forgotten
% .metta imported NOTHING and said so with an empty answer set.
test(an_unresolvable_library_alias_raises,
     [ cleanup(retractall(user:file_search_path(plunit_lib_alias, _))) ]) :-
    tmp_dir_of_this_suite(Dir),
    register_metta_library_path(plunit_lib_alias, Dir, _),
    % A registered alias, a file that is not under it.
    catch(library(plunit_lib_alias, 'nosuchfile.metta', _), Missing, true),
    assertion(Missing = error(petta_unresolved_library(plunit_lib_alias,
                                                       'nosuchfile.metta',
                                                       [_|_]), _)),
    % An alias nothing registered names itself rather than the file.
    catch(library(plunit_no_such_alias, 'thing.metta', _), Absent, true),
    assertion(Absent = error(petta_unresolved_library(plunit_no_such_alias,
                                                      'thing.metta', []), _)).

tmp_dir_of_this_suite(Dir) :-
    ( getenv('TMPDIR', Dir) -> true ; Dir = '/tmp' ).

test(a_library_path_that_is_not_a_directory_is_refused,
     [throws(error(existence_error(directory, '/nonexistent/petta/libdir'), _))]) :-
    register_metta_library_path(plunit_absent_pkg, '/nonexistent/petta/libdir', true).

:- end_tests(prolog_interface_namespacing).
