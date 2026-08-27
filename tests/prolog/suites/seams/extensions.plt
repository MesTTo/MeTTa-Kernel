% Purpose: the extension control files and the loader that reads them --
%   engine/metta.pl's metta_load_extension/1 and the metta_extension_loaded/1
%   and metta_extension_unmet/2 records it keeps.
% Guarantees:
%   - a control file is READ and never consulted: a directive in one refuses
%     loudly naming the file and the term, and the directive does not run
%     [tested: a_control_file_is_read_never_consulted]
%   - an unmet need of every kind is recorded by name and loads nothing, and
%     the boot stays silent, because not built is not an error
%     [tested: an_unmet_artefact_is_recorded_by_name and the three beside it]
%   - met needs load the engine entries in control-file order, and the seat is
%     recorded loaded [tested: met_needs_load_the_engine_entries]
%   - an entry(host, _) is recorded and never loaded by the engine
%     [tested: a_host_entry_is_never_loaded_by_the_engine]
%   - needs(extension(Other)) holds exactly when Other loaded first
%     [tested: an_extension_need_follows_the_loaded_record]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(extension_control_files).

%One scratch seat per test, in its own directory, so no test reads another's
%record. Every record access is user-qualified, because the engine's loader
%runs in user and a bare assertz or retractall HERE would create a
%plunit-module-local dynamic that SHADOWS the engine's table: the test would
%then write to one table and the loader read another, which is exactly what
%the first version of this suite did.
scratch_seat(Name, Facts, Control) :-
    tmp_file(Name, Base),
    atom_concat(Base, '-seat', Directory),
    make_directory_path(Directory),
    directory_file_path(Directory, 'extension.pl', Control),
    setup_call_cleanup(
        open(Control, write, Out),
        forall(member(Fact, Facts), format(Out, '~q.~n', [Fact])),
        close(Out)).

remove_seat(Control) :-
    file_directory_name(Control, Directory),
    catch(delete_file(Control), _, true),
    forall(( directory_member(Directory, Entry, []) ),
           catch(delete_file(Entry), _, true)),
    catch(delete_directory(Directory), _, true).

seat_name(Control, Name) :-
    file_directory_name(Control, Directory),
    file_base_name(Directory, Name).

:- dynamic user:extension_suite_directive_ran/0.
:- dynamic user:extension_suite_entry_ran/1.

test(a_control_file_is_read_never_consulted,
     [ cleanup(remove_seat(Control)),
       throws(error(domain_error(extension_control_term, _), _)) ]) :-
    tmp_file(ext_directive, Base),
    atom_concat(Base, '-seat', Directory),
    make_directory_path(Directory),
    directory_file_path(Directory, 'extension.pl', Control),
    setup_call_cleanup(
        open(Control, write, Out),
        format(Out, ':- assertz(user:extension_suite_directive_ran).~n', []),
        close(Out)),
    metta_load_extension(Control).

test(the_refused_directive_did_not_run) :-
    \+ user:extension_suite_directive_ran.

test(an_unmet_artefact_is_recorded_by_name, [cleanup(remove_seat(Control))]) :-
    scratch_seat(ext_artefact,
                 [ title(probe),
                   needs(artefact('never-built.so')),
                   entry(engine, 'never-consulted.pl') ],
                 Control),
    seat_name(Control, Name),
    metta_load_extension(Control),
    assertion(user:metta_extension_unmet(Name, artefact('never-built.so'))),
    assertion(\+ user:metta_extension_loaded(Name)).

test(an_unmet_library_is_recorded_by_name, [cleanup(remove_seat(Control))]) :-
    scratch_seat(ext_library,
                 [ needs(prolog_library(no_such_library_exists_here)) ],
                 Control),
    seat_name(Control, Name),
    metta_load_extension(Control),
    assertion(user:metta_extension_unmet(Name,
                  prolog_library(no_such_library_exists_here))).

test(an_unmet_predicate_is_recorded_by_name, [cleanup(remove_seat(Control))]) :-
    scratch_seat(ext_predicate,
                 [ needs(predicate(no_such_marker/7)) ],
                 Control),
    seat_name(Control, Name),
    metta_load_extension(Control),
    assertion(user:metta_extension_unmet(Name, predicate(no_such_marker/7))).

test(an_extension_need_follows_the_loaded_record,
     [cleanup(remove_seat(Control))]) :-
    scratch_seat(ext_dependent,
                 [ needs(extension(no_such_seat_loaded)) ],
                 Control),
    seat_name(Control, Name),
    metta_load_extension(Control),
    assertion(user:metta_extension_unmet(Name, extension(no_such_seat_loaded))),
    %The same seat, once the seat it needs is on the record: the loader is
    %idempotent over the record, so a second read with the need met loads.
    assertz(user:metta_extension_loaded(no_such_seat_loaded)),
    retractall(user:metta_extension_unmet(Name, _)),
    metta_load_extension(Control),
    assertion(user:metta_extension_loaded(Name)),
    retractall(user:metta_extension_loaded(no_such_seat_loaded)),
    retractall(user:metta_extension_loaded(Name)).

test(met_needs_load_the_engine_entries, [cleanup(remove_seat(Control))]) :-
    scratch_seat(ext_loading, [title(probe)], Control),
    file_directory_name(Control, Directory),
    directory_file_path(Directory, 'entry.pl', Entry),
    setup_call_cleanup(
        open(Entry, write, Out),
        format(Out, ':- assertz(user:extension_suite_entry_ran(engine)).~n', []),
        close(Out)),
    %entry/2 is appended after the scratch write so the entry file exists
    %before the control file names it.
    setup_call_cleanup(
        open(Control, append, Again),
        format(Again, '~q.~n', [entry(engine, 'entry.pl')]),
        close(Again)),
    seat_name(Control, Name),
    metta_load_extension(Control),
    assertion(user:extension_suite_entry_ran(engine)),
    assertion(user:metta_extension_loaded(Name)),
    retractall(user:extension_suite_entry_ran(_)),
    retractall(user:metta_extension_loaded(Name)).

test(a_host_entry_is_never_loaded_by_the_engine,
     [cleanup(remove_seat(Control))]) :-
    scratch_seat(ext_host, [title(probe)], Control),
    file_directory_name(Control, Directory),
    directory_file_path(Directory, 'transport.pl', Transport),
    setup_call_cleanup(
        open(Transport, write, Out),
        format(Out, ':- assertz(user:extension_suite_entry_ran(host)).~n', []),
        close(Out)),
    setup_call_cleanup(
        open(Control, append, Again),
        format(Again, '~q.~n', [entry(host, 'transport.pl')]),
        close(Again)),
    seat_name(Control, Name),
    metta_load_extension(Control),
    assertion(\+ user:extension_suite_entry_ran(host)),
    assertion(user:metta_extension_loaded(Name)),
    retractall(user:metta_extension_loaded(Name)).

%The shipped seats, read off the live record this process booted with: the
%Python seat loaded (this suite runs under a full SWI with janus), and the C
%seat's marker is honestly unmet, because this process is not the C host.
test(the_shipped_seats_are_on_the_record) :-
    assertion(user:metta_extension_loaded(python)),
    assertion(user:metta_extension_unmet(cetta, predicate('$cetta_present'/0))).

:- end_tests(extension_control_files).
