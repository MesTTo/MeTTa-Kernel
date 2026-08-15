% Purpose: connect named MeTTa spaces to MORK through its text FFI protocol,
%   as a provider behind the engine's foreign-space seam.
% Assumes:
%   - the engine consults metta_foreign_space/1 before its own storage, and
%     its foreign match clause splits conjunctions per conjunct and answers
%     an unbound pattern through metta_foreign_atoms/2
%     [source: src/spaces.pl, match_foreign/4]
% Guarantees:
%   - a MORK space refuses an unbound space name the way a native one does
%     [tested: spaces_storage_modules:matching_requires_a_named_space].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The seam, not the core predicates. Declaring match/4, 'add-atom'/3,
%'remove-atom'/3 and 'get-atoms'/2 multifile put MORK's clauses ahead of the
%engine's, because this file loads before spaces.pl, so the engine's
%instantiation guards were unreachable whenever MORK was present. That is
%every shipping configuration on a machine that built the FFI, and it made
%(get-atoms $any) answer from MORK rather than refuse. lib_redis.pl and
%python/petta/shim.pl are behind this same seam.
:- multifile metta_foreign_space/1.
:- multifile metta_foreign_add/2.
:- multifile metta_foreign_remove/3.
:- multifile metta_foreign_atoms/2.
:- multifile metta_foreign_match/2.

%MORK spaces address from MeTTa as &mork (the default space) or
%&mork:<name>, each name its own store inside MORK, created on first
%use. A request to a named space rides a "#mork-space <name>" header;
%the default space sends the bare payload, which keeps the original
%wire protocol unchanged.
%
%The name is an input. Matching an unbound argument against '&mork' would
%bind it, which is how an unnamed space used to become MORK's default one.
mork_space_name(Space, "default") :- Space == '&mork', !.
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

%MORK's bridge consumes swrite text. MeTTa has no quoted-symbol syntax, so a
%symbol containing syntax characters cannot retain its identity there.
mork_unsafe_symbol(Symbol) :- atom(Symbol),
                              atom_codes(Symbol, Codes),
                              member(Code, Codes),
                              ( code_type(Code, space)
                              ; memberchk(Code, [0'(, 0'), 0'"]) ), !.
mork_bad_text_symbol(Term, Term) :- mork_unsafe_symbol(Term), !.
mork_bad_text_symbol(Term, Bad) :-
    compound(Term),
    compound_name_arguments(Term, Functor, Args),
    ( mork_bad_text_symbol(Functor, Bad)
    ; member(Arg, Args), mork_bad_text_symbol(Arg, Bad) ), !.

mork_require_text_safe(Term, Operation) :-
    ( mork_bad_text_symbol(Term, Bad)
      -> throw(error(domain_error(mork_text_symbol, Bad),
                     context(Operation,
                             'symbol names containing whitespace, parentheses, or quotes cannot cross the MORK text boundary')))
    ; true ).

%A MORK space is a foreign space: its atoms live outside the Prolog
%database and this file owns every read and write of them.
%
%Every MORK space name starts with &mork, and the engine asks this question
%on every write and every match, native spaces included. One prefix test
%rejects every other space before the name is parsed: parsing first cost 400
%inferences over register-op's registrations and 5 over a five-way join
%[measured 2026-08-15].
metta_foreign_space(Space) :- atom(Space),
                              sub_atom(Space, 0, 5, _, '&mork'),
                              mork_space_name(Space, _).

%Add an atom to the space. The engine fires the write hooks around
%metta_add_atom/3, so subscriptions and reflection see MORK writes too:
metta_foreign_add(Space, Atom) :- mork_require_text_safe(Atom, 'add-atom'/3),
                                  swrite(Atom, S),
                                  mork_call(Space, "queue-atom", S, "OK: queued").

%Add a whole list of atoms in ONE crossing: the payload joins their
%text and MORK parses it as a batch, so ingestion pays one FFI call
%and one lock instead of one per atom. Hooks still fire per atom.
'mork-add-atoms'(Space, Atoms, true) :-
    mork_space_name(Space, _),
    is_list(Atoms),
    maplist(mork_require_text_safe_for_add, Atoms),
    maplist(swrite, Atoms, Lines),
    atomics_to_string(Lines, "\n", Payload),
    mork_call(Space, "add-atoms", Payload, "OK: loaded"),
    forall(member(Atom, Atoms),
           forall(metta_on_atom_added(Space, Atom), true)).

mork_require_text_safe_for_add(Atom) :-
    mork_require_text_safe(Atom, 'mork-add-atoms'/3).

%Remove all same atoms. MORK answers every removal with "OK: loaded" and no
%count, so whether anything was there is a separate question, and it is asked
%through MORK's own matching rather than a dump of the space. Answering true
%unconditionally would report a removal that did not happen.
metta_foreign_remove(Space, Atom, Removed) :-
    ( mork_holds(Space, Atom) -> Removed = true ; Removed = false ),
    mork_require_text_safe(Atom, 'remove-atom'/3),
    swrite(Atom, S),
    mork_call(Space, "remove-atoms", S, _).

%Whether the space holds anything this atom unifies with. An unbound atom
%asks whether the space holds anything at all, which is what match/4 does
%with one [source: src/spaces.pl, match_foreign/4].
mork_holds(Space, Atom) :-
    \+ \+ ( var(Atom)
            -> metta_foreign_atoms(Space, Atom)
            ;  metta_foreign_match(Space, Atom) ).

%Match one pattern, MORK's own matching rather than a scan. The engine
%hands over one non-conjunctive, bound pattern at a time: it splits a
%conjunction per conjunct and answers an unbound pattern through
%metta_foreign_atoms/2, so joins over this space are the engine's joins,
%each conjunct answered by MORK.
metta_foreign_match(Space, Pattern) :- Pattern_Template = [Pattern, Pattern],
                                       mork_require_text_safe(Pattern_Template, match/4),
                                       swrite(Pattern_Template, MorkPat),
                                       mork_call(Space, "match", MorkPat, Temp),
                                       mork_response_term(Temp, MatchedPattern),
                                       Pattern = MatchedPattern.

%Get all atoms in space, irregard of arity:
metta_foreign_atoms(Space, Pattern) :- mork_call(Space, "get-atoms", "", Temp),
                                       mork_response_term(Temp, Pattern).

%A response is one atom per line, with a trailing newline to skip.
mork_response_term(Response, Term) :- split_string(Response, "\n", "", Lines),
                                      member(Line, Lines),
                                      Line \== "",
                                      sread(Line, Term).

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
