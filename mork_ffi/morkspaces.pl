:- multifile match/4.
:- multifile 'add-atom'/3.
:- multifile 'remove-atom'/3.
:- multifile 'get-atoms'/2.
:- multifile 'mork-flush'/2.

%MORK spaces address from MeTTa as &mork (the default space) or
%&mork:<name>, each name its own store inside MORK, created on first
%use. A request to a named space rides a "#mork-space <name>" header;
%the default space sends the bare payload, which keeps the original
%wire protocol unchanged.
mork_space_name('&mork', "default") :- !.
mork_space_name(Space, Name) :- atom(Space),
                                atom_concat('&mork:', RawName, Space),
                                RawName \== '',
                                !,
                                atom_string(RawName, Name).

mork_call(Space, Command, Payload, Response) :-
    %A NUL byte truncates at the C boundary mid-form and MORK's loader
    %panics on the resulting UnexpectedEOF, killing the process. Refuse
    %it loudly here, the one choke point every command crosses.
    ( string(Payload), string_code(_, Payload, 0)
      -> throw(error(domain_error(mork_text, Payload),
                     context(mork_call/4,
                             'a NUL byte cannot cross the MORK boundary')))
    ; true ),
    mork_space_name(Space, Name),
    ( Name == "default"
      -> Request = Payload
    ; format(string(Request), "#mork-space ~w~n~w", [Name, Payload]) ),
    mork(Command, Request, Response).

%Add an atom to the space. The engine's write hooks fire like on any
%other space, so subscriptions and reflection see MORK writes too:
'add-atom'(Space, Atom, true) :- mork_space_name(Space, _), !,
                                 swrite(Atom, S),
                                 mork_call(Space, "queue-atom", S, "OK: queued"),
                                 forall(metta_on_atom_added(Space, Atom), true).

%Add a whole list of atoms in ONE crossing: the payload joins their
%text and MORK parses it as a batch, so ingestion pays one FFI call
%and one lock instead of one per atom. Hooks still fire per atom.
'mork-add-atoms'(Space, Atoms, true) :-
    mork_space_name(Space, _),
    is_list(Atoms),
    maplist(swrite, Atoms, Lines),
    atomics_to_string(Lines, "\n", Payload),
    mork_call(Space, "add-atoms", Payload, "OK: loaded"),
    forall(member(Atom, Atoms),
           forall(metta_on_atom_added(Space, Atom), true)).

%Remove all same atoms:
'remove-atom'(Space, Atom, true) :- mork_space_name(Space, _), !,
                                    swrite(Atom, S),
                                    mork_call(Space, "remove-atoms", S, _),
                                    forall(metta_on_atom_removed(Space, Atom), true).

%Match for one pattern. Conjunctions and unbound patterns fall through
%to the engine's own clauses, which split a conjunction per conjunct and
%enumerate a variable pattern through get-atoms, so joins over this
%space are the engine's joins, each conjunct answered by MORK:
match(Space, Pattern, OutPattern, Result) :- \+ var(Pattern),
                                             Pattern \= [','|_],
                                             mork_space_name(Space, _), !,
                                             Pattern_Template = [Pattern, Pattern],
                                             swrite(Pattern_Template, MorkPat),
                                             mork_call(Space, "match", MorkPat, Temp),
                                             split_string(Temp, "\n", "", Lines),
                                             member(Line, Lines),
                                             Line \== "",
                                             sread(Line, MatchedPattern),
                                             Pattern = MatchedPattern,
                                             Result = OutPattern.

%Get all atoms in space, irregard of arity:
'get-atoms'(Space, Pattern) :- mork_space_name(Space, _), !,
                               mork_call(Space, "get-atoms", "", Temp),
                               split_string(Temp, "\n", "", Lines),
                               member(Line, Lines),
                               Line \== "",
                               sread(Line, Pattern).

%Execute MM2 calculus
'mm2-exec'(Space, Steps, true) :- mork_space_name(Space, _),
                                  number_string(Steps, St),
                                  mork_call(Space, "mm2-exec", St, _).

%Make queued additions visible without performing another operation.
'mork-flush'(Space, true) :- mork_space_name(Space, _), !,
                             mork_call(Space, "flush", "", "OK: flushed").

%Init MORK. Both libraries resolve relative to THIS file, so the same
%init serves every load flow: the engine's startup branch, git-import!,
%and an embedded process without LD_PRELOAD. The Rust cdylib opens with
%global symbol visibility first, which is what lets morklib.so's
%undefined rust_mork references link when no LD_PRELOAD preceded us; a
%process that did preload merely reopens an already-mapped library.
%Failure throws: this file only loads when MORK was asked for.
:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, 'target/release/libmork_ffi.so', RustLib),
   ( exists_file(RustLib) -> true
   ; throw(error(existence_error(mork_rust_library, RustLib),
                 context(RustLib, 'build mork_ffi first: sh build.sh'))) ),
   open_shared_object(RustLib, _, [global]),
   directory_file_path(Dir, 'morklib.so', ShimLib),
   ( exists_file(ShimLib) -> true
   ; throw(error(existence_error(mork_shim_library, ShimLib),
                 context(ShimLib, 'build mork_ffi first: sh build.sh'))) ),
   use_foreign_library(ShimLib),
   %Success is silent: every embedded boot and CLI run passes here, and
   %programs comparing process output must not carry a banner. Failure
   %throws, which is where the diagnostic value lives.
   ( current_predicate(mork/3) -> true
   ; throw(error(existence_error(procedure, mork/3),
                 context(ShimLib, 'mork/3 did not register on load'))) ).

%Test MORK:
mork_test :- 'add-atom'('&mork', [friend,sam,tim], true),
             'add-atom'('&mork', [friend,sam,joe], true),
             findall(C, match('&mork',[friend,sam,X], [friend,sam,X], C), Cs),
             format(string(SC), "MORK query result: ~w ~n", [Cs]), writeln(SC).
