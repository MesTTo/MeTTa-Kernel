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
%   - require-extension! passes a loaded seat silently and refuses an unloaded
%     one naming the seat, its unmet need, the artefact path and the build
%     command, following a need of kind extension(Other) into Other's own
%     cause [tested: a_require_of_a_loaded_seat_passes,
%     a_require_names_the_seat_and_its_unmet_need,
%     a_require_diagnoses_transitively_down_to_the_build_command,
%     a_require_of_an_unknown_name_says_so]
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

%%%% The require door %%%%
%
%Every record these read and write is user-qualified for the reason the header
%above gives: the loader's tables live in the engine's module, and a bare
%assertz here would make a plunit-local shadow that the door never reads.

%The refusal message, as a host would read it. message_to_string/2 rather than
%the term, because the whole point of the door is what the text says: a term
%assertion would pass on a message that had stopped naming the artefact.
require_refusal(Name, Text) :-
    catch(( 'require-extension!'(Name, _), fail ),
          Error,
          message_to_string(Error, Text)).

test(a_require_of_a_loaded_seat_passes, [cleanup(cleanup_scratch_seat)]) :-
    assertz(user:metta_extension_loaded(require_probe_seat)),
    'require-extension!'(require_probe_seat, Unit),
    assertion(Unit == []).

cleanup_scratch_seat :-
    retractall(user:metta_extension_loaded(require_probe_seat)),
    retractall(user:metta_extension_unmet(require_probe_seat, _)),
    retractall(user:metta_extension_unmet(require_probe_backing, _)).

test(a_require_names_the_seat_and_its_unmet_need,
     [cleanup(cleanup_scratch_seat)]) :-
    assertz(user:metta_extension_unmet(require_probe_seat,
                prolog_library(no_such_library_exists_here))),
    require_refusal(require_probe_seat, Text),
    assertion(sub_string(Text, _, _, _, "require_probe_seat")),
    assertion(sub_string(Text, _, _, _, "no_such_library_exists_here")),
    assertion(sub_string(Text, _, _, _, "not loaded")).

%The transitive arm, and the one the shipped case needs: a seat whose only
%unmet need is another seat reports the OTHER seat's cause, down to the
%artefact path and the command that builds it.
test(a_require_diagnoses_transitively_down_to_the_build_command,
     [cleanup(cleanup_scratch_seat)]) :-
    assertz(user:metta_extension_unmet(require_probe_seat,
                extension(require_probe_backing))),
    assertz(user:metta_extension_unmet(require_probe_backing,
                artefact('ffi/target/release/libprobe.so'))),
    require_refusal(require_probe_seat, Text),
    assertion(sub_string(Text, _, _, _, "require_probe_seat")),
    assertion(sub_string(Text, _, _, _, "require_probe_backing")),
    assertion(sub_string(Text, _, _, _,
        "artefact extensions/require_probe_backing/ffi/target/release/libprobe.so is absent")).

%The shipped seat, read off this process's own records rather than staged:
%mork carries a build.sh, so its artefact need names the command.
test(a_shipped_seats_artefact_need_names_its_build_command,
     [cleanup(( retractall(user:metta_extension_unmet(mork, _)),
                assertz(user:metta_extension_loaded(mork)) ))]) :-
    retractall(user:metta_extension_loaded(mork)),
    assertz(user:metta_extension_unmet(mork,
                artefact('mork_ffi/target/release/libmork_ffi.so'))),
    require_refusal(mork, Text),
    assertion(sub_string(Text, _, _, _,
        "artefact extensions/mork/mork_ffi/target/release/libmork_ffi.so is absent")),
    assertion(sub_string(Text, _, _, _, "run extensions/mork/build.sh")).

%A name with no control file is a different answer from a seat that failed a
%need, and it has to be: the remedy for one is a build and for the other is a
%spelling.
test(a_require_of_an_unknown_name_says_so) :-
    require_refusal(no_such_extension_anywhere, Text),
    assertion(sub_string(Text, _, _, _,
        "there is no extensions/no_such_extension_anywhere/extension.pl")).

test(a_require_refuses_an_unbound_name_by_its_own_name) :-
    catch(( 'require-extension!'(_, _), fail ), Error, true),
    assertion(Error = error(metta_unbound_input('require-extension!', 1), _)).

%The whole composition, through a real file load, which is the only place the
%requiring side is named: the door throws with an uncontexted error and the
%file loader wraps it in the file, so one message carries who asked, what is
%missing, why, and the command that clears it. Asserting it here is what stops
%a later context change from silently dropping the file half.
test(a_require_in_a_file_names_the_file_the_seat_and_the_remedy,
     [ cleanup(( catch(delete_file(Source), _, true),
                 retractall(user:metta_extension_unmet(mork, _)),
                 assertz(user:metta_extension_loaded(mork)) )) ]) :-
    tmp_file(require_in_file, Base),
    file_name_extension(Base, metta, Source),
    setup_call_cleanup(open(Source, write, Out),
                       format(Out, '!(require-extension! mork)~n', []),
                       close(Out)),
    retractall(user:metta_extension_loaded(mork)),
    assertz(user:metta_extension_unmet(mork,
                artefact('mork_ffi/target/release/libmork_ffi.so'))),
    catch(( load_imported_metta_file(Source, _, '&self'), fail ),
          Error,
          message_to_string(Error, Text)),
    assertion(sub_string(Text, _, _, _, "require_in_file")),
    assertion(sub_string(Text, _, _, _, "extension mork is required")),
    assertion(sub_string(Text, _, _, _,
        "artefact extensions/mork/mork_ffi/target/release/libmork_ffi.so is absent")),
    assertion(sub_string(Text, _, _, _, "run extensions/mork/build.sh")),
    assertion(sub_string(Text, _, _, _, "while loading MeTTa file")).

:- end_tests(extension_control_files).
