% Purpose: implement fast caches, source digests, transactional reload, and source assertion ownership.
% Assumes: engine/filereader.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/filereader.pl's implementation module and original load order;
%   each source load is atomic with every dependent recompile it triggers;
%   source_load_receipt_current/4 accepts a receipt only while its source row, digest, and every tagged stored output remain current.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/suites/reader/filereader.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]

%%%% The fast cache and the content digest %%%%
%
%The binary save format, its integrity-checked loader, and the space
%digest are engine machinery: SWI streams, fastrw, zlib and the crypto
%hash, with exactly one host question in them, whether a term holds a
%live host object, which is the published seam:host_object/1 ownership
%seam each bridge answers for its own kind of object. They lived in the
%Python shim and the walk that found a live object asked py_is_object
%directly, which is how a second binding would have re-paid the whole
%section.
%
%Results cross as terms, the codec staying each host's own: a save or
%digest that refuses answers object(Atom) or symbol(Atom) naming the
%offender, a save that lands answers saved(Count), a digest answers
%digest(Hash).

%The version prefix of the header; the file appends a tab, the sha256 of
%the payload bytes, and a newline, so integrity refuses before fast_read
%sees a single payload byte.
metta_host_fast_header(Header) :-
    current_prolog_flag(version_data, swi(Major, Minor, Patch, _)),
    format(string(Header), 'METTA-CACHE\tMETTA-FAST\t2\t~d.~d.~d',
           [Major, Minor, Patch]).

%A cache whose path ends .gz reads and writes through zlib's stream;
%Python's gzip module accepts the same files and vice versa.
metta_host_fast_open(File, Mode, Stream) :-
    (   file_name_extension(_, gz, File)
    ->  gzopen(File, Mode, Stream, [type(binary)])
    ;   open(File, Mode, Stream, [type(binary)])
    ).

%Whether any subterm is a live host object, the one question only a host
%can answer, asked through its published seam. The seam is consulted only
%behind blob/2, because every host's live object crosses as a non-text
%blob (janus wraps Python objects so, and swipl-wasm renders its objects
%as opaque blobs), and asking the multifile seam at every subterm instead
%cost the fast save +320,062 inferences over its corpus
%[measured 2026-08-20: 2,322,901 against 2,002,839 on save-load-fast].
metta_host_atom_carries_object(Term) :-
    compound(Term),
    !,
    compound_name_arity(Term, _, Arity),
    between(1, Arity, Index),
    arg(Index, Term, Argument),
    metta_host_atom_carries_object(Argument),
    !.
metta_host_atom_carries_object(Term) :-
    blob(Term, Type),
    Type \== text,
    seam:host_object(Term).

%A fast save is a binary file, so it refuses before it writes rather than
%after: an object has no spelling at all, and a symbol whose name splits a
%token or carries a quote has one that reads back as something else.
%metta_unwritable_symbol/2 is the grammar's own answer to the second, so
%asking it is what keeps this from holding a second copy of the delimiter
%rules; the copy it replaced missed three classes.
metta_host_save_fast(File, Space, Result) :-
    ( atom(File) -> FA = File ; atom_string(FA, File) ),
    findall(Atom, 'get-atoms'(Space, Atom), Atoms),
    (   member(ObjectAtom, Atoms),
        metta_host_atom_carries_object(ObjectAtom)
    ->  Result = object(ObjectAtom)
    ;   member(SymbolAtom, Atoms),
        metta_unwritable_symbol(SymbolAtom, BadSymbol)
    ->  Result = symbol(BadSymbol)
    ;   setup_call_cleanup(
            new_memory_file(MF),
            ( setup_call_cleanup(
                  open_memory_file(MF, write, PW, [encoding(octet)]),
                  fast_write(PW, Atoms),
                  close(PW)),
              metta_host_hash_memory_file(MF, Hash),
              metta_host_fast_header(Prefix),
              format(string(Header), '~w\t~w\n', [Prefix, Hash]),
              string_codes(Header, HeaderCodes),
              setup_call_cleanup(
                  metta_host_fast_open(FA, write, Out),
                  ( maplist(put_byte(Out), HeaderCodes),
                    setup_call_cleanup(
                        open_memory_file(MF, read, PR, [encoding(octet)]),
                        copy_stream_data(PR, Out),
                        close(PR)) ),
                  close(Out)) ),
            free_memory_file(MF)),
        length(Atoms, Count),
        Result = saved(Count)
    ).

%One compact octet string, one C hash. Measured against the crypto
%filter-stream route (copy through the filter into a null sink), which
%charged ~9ms per 700KB pass; this stays ~1ms.
metta_host_hash_memory_file(MF, Hash) :-
    memory_file_to_string(MF, Payload, octet),
    metta_octets_digest(Payload, Hash).

metta_host_hash_stream(In, Hash) :-
    read_string(In, _, Payload),
    metta_octets_digest(Payload, Hash).

metta_host_fast_expect_header([], _).
metta_host_fast_expect_header([Expected|Rest], In) :-
    get_byte(In, Actual),
    (   Actual =:= Expected
    ->  metta_host_fast_expect_header(Rest, In)
    ;   throw(error(metta_fast_header_mismatch(Expected, Actual), none))
    ).

metta_host_fast_read(In, File, Atoms) :-
    catch(fast_read(In, Read), Caught,
          throw(error(metta_fast_read_failed(File, Caught), none))),
    (   is_list(Read)
    ->  Atoms = Read
    ;   throw(error(metta_fast_payload_not_atom_list(File), none))
    ).

%After the version prefix: one tab, sixty-four hex digits, one newline.
metta_host_fast_expect_hash(In, File, Hash) :-
    read_string(In, "\n", "", _, Line),
    (   string_concat("\t", Hash, Line),
        string_length(Hash, 64),
        forall(string_code(_, Hash, C),
               ( C >= 0'0, C =< 0'9 ; C >= 0'a, C =< 0'f ))
    ->  true
    ;   throw(error(metta_fast_integrity_header(File), none))
    ).

%A cache is a file this door loaded, so it is replaced on a second load
%the same way a text program is. It needs neither a reader nor a digest of
%its own for that: the format already carries the sha256 of its payload,
%the same question metta_source_digest/2 asks of a source's text
%[tested test_loading_a_fast_cache_twice_leaves_one_copy].
metta_host_load_fast(File, Space) :-
    ( atom(File) -> FA = File ; atom_string(FA, File) ),
    absolute_file_name(FA, CanonPath, [access(read)]),
    import_when(true, Space, CanonPath,
                replacing_previous_load(CanonPath, Space,
                                        metta_host_fast_load_into(CanonPath),
                                        metta_host_fast_load_into(CanonPath,
                                                                  Space))).

metta_host_fast_load_into(CanonPath, Space) :-
    with_source_load(CanonPath, Space,
                     metta_host_fast_add_atoms(CanonPath, Space)).

%Two passes: the first proves the payload hash, the second lets fast_read
%consume the now-proven bytes straight off the file. fastrw is unsafe on
%untrusted bytes, so no payload byte reaches it before the digest agrees.
metta_host_fast_add_atoms(FA, Space) :-
    metta_host_fast_header(Prefix),
    string_codes(Prefix, PrefixCodes),
    setup_call_cleanup(
        metta_host_fast_open(FA, read, HIn),
        ( metta_host_fast_expect_header(PrefixCodes, HIn),
          metta_host_fast_expect_hash(HIn, FA, ExpectedHash),
          metta_host_hash_stream(HIn, ActualHash) ),
        close(HIn)),
    atom_string(ActualHash, ActualHashText),
    (   ActualHashText == ExpectedHash
    ->  true
    ;   throw(error(metta_fast_integrity_mismatch(FA), none))
    ),
    %Unconditional, because the only caller wraps this in a load context. A
    %fast load that reached here without one would be recorded under
    %nothing and so could never be replaced, and failing outright is the
    %right way to find that out. Ownership pins are skipped so the digest
    %keys the load that is actually running, never a pinned owner.
    active_source_load(LoadId),
    LoadId \= '$metta_owner_pin'(_),
    assertz(source_load_digest(LoadId, FA, ActualHash)),
    setup_call_cleanup(
        metta_host_fast_open(FA, read, In),
        ( metta_host_fast_expect_header(PrefixCodes, In),
          metta_host_fast_expect_hash(In, FA, _),
          metta_host_fast_read(In, FA, Atoms),
          %metta_add_atom/3 rather than the public `add-atom`: the space was
          %resolved before the file was opened, so the space-argument check
          %the public one owes a PROGRAM is pure cost on every atom in the
          %file. metta_add_atoms/2 was tried here and is SLOWER, because a
          %fast-format file is not store-only and its batch test scans every
          %atom before falling back to this same loop [measured 2026-08-17:
          %4737359333 against 4707855603].
          forall(member(Atom, Atoms), metta_add_atom(Space, Atom, _)) ),
        close(In)).

%A space's content as one sha256: each atom canonicalized (fresh copy,
%numbered variables, quoted write) so alpha-equivalent equations print
%identically in every process, the lines multiset-sorted so insertion
%order cannot matter, then hashed as one utf8 document. Live objects
%print by address and are refused, the save contract.
metta_host_digest(Space, Result) :-
    findall(Atom, 'get-atoms'(Space, Atom), Atoms),
    (   member(ObjectAtom, Atoms),
        metta_host_atom_carries_object(ObjectAtom)
    ->  Result = object(ObjectAtom)
    ;   member(SymbolAtom, Atoms),
        metta_unwritable_symbol(SymbolAtom, BadSymbol)
    ->  Result = symbol(BadSymbol)
    ;   findall(Line,
                ( member(Atom, Atoms),
                  metta_host_digest_line(Atom, Line) ),
                Lines),
        msort(Lines, Sorted),
        atomic_list_concat(Sorted, '\n', Joined),
        metta_text_digest(Joined, Hash),
        Result = digest(Hash)
    ).

metta_host_digest_line(Atom, Line) :-
    copy_term(Atom, Copy),
    numbervars(Copy, 0, _),
    with_output_to(string(Line),
                   write_term(Copy, [quoted(true), numbervars(true)])).


% A .gz program reads through the engine's own zlib stream. Any other path
% reads plain text, so imports and the CLI share the same source reader.
%
%A load's own read is where its digest is taken, because that is where the text
%already is. Computing it again when the load finished read the file a second
%time, and only the digest belongs to the load: metta_source_digest/2 below asks
%the same question of a file that is NOT loading, and going through here would
%have filed its answer under whatever load happened to be running, which for a
%nested import is the importing file's [measured 2026-08-19: the second read
%cost 113 inferences of every load].
read_metta_source(Filename, S) :-
    read_source_text(Filename, S),
    (   active_source_load(LoadId),
        LoadId \= '$metta_owner_pin'(_)
    ->  metta_text_digest(S, Digest),
        assertz(source_load_digest(LoadId, Filename, Digest))
    ;   true
    ).

read_source_text(Filename, S) :-
    ( file_name_extension(_, gz, Filename)
      -> catch(setup_call_cleanup(gzopen(Filename, read, In),
                                  ( set_stream(In, encoding(utf8)),
                                    read_string(In, _, S) ),
                                  close(In)),
               error(Type, _),
               throw(error(Type, context(Filename,
                                         'while reading gzip-compressed MeTTa source'))))
    ; read_file_to_string(Filename, S, [encoding(utf8)]) ).

% Every space that receives a file compiles its own copy of the file's
% equations, into its own execution module, exactly as the runtime door
% does: the arbiter's import law admits a module's contents into the
% importing space and nowhere else, so a clause cannot be shared across
% spaces without making the name callable where it was never imported.
%The re-population closure is load_imported_metta_file_impl/3 with its first
%two arguments filled: the file, and a fresh Results slot per space, since a
%space that is only being brought back up to date has no answers to report.
load_imported_metta_file(Filename, Results, Space) :-
    catch(replacing_previous_load(Filename, Space,
                                  load_imported_metta_file_impl(Filename, _),
                                  load_imported_metta_file_impl(Filename, Results,
                                                                Space)),
          Error,
          rethrow_metta_file_error(Filename, Error)).

%The grouped door differs only in its result shape. Re-population of other
%spaces deliberately uses the ordinary loader because no caller observes
%those spaces' directive groups.
load_imported_metta_source_groups(Filename, Groups, Space) :-
    catch(replacing_previous_load(
              Filename, Space,
              load_imported_metta_file_impl(Filename, _),
              load_imported_metta_source_groups_impl(Filename, Groups, Space)),
          Error,
          rethrow_metta_file_error(Filename, Error)).

%Each pass gets a load context of its own: a file's equations compile into
%EVERY receiving space's module and its atoms are stored once per space, so
%the second space's copy is a contribution the file made and has to be
%recorded as one; without this a reload replaced the first space's copy and
%left the second's standing. The loading marker still guards the FIRST load
%of a path, so a recursive import of the file being loaded is caught.
load_imported_metta_file_impl(Filename, Results, Space) :-
    ( compiled_metta_source(Filename)
      -> with_source_load(Filename, Space,
                          load_metta_file_impl(Filename, Results, Space))
       ; run_with_loading_marker(
             compiled_metta_source(Filename),
             run_new_source_load(Filename, Results, Space)) ).

run_new_source_load(Filename, Results, Space) :-
    with_source_load(Filename, Space,
                     load_metta_file_impl(Filename, Results, Space)).

load_imported_metta_source_groups_impl(Filename, Groups, Space) :-
    ( compiled_metta_source(Filename)
      -> with_source_load(
             Filename, Space,
             load_metta_source_groups_impl(Filename, Space, Groups))
       ; run_with_loading_marker(
             compiled_metta_source(Filename),
             with_source_load(
                 Filename, Space,
                 load_metta_source_groups_impl(Filename, Space, Groups))) ).

%One source load: the context every assertion is filed under while it runs, the
%repair pass at the end, and the two ways it can finish. A failure rolls the
%whole partial load back, which is what this always did. A SUCCESS now keeps
%the list instead of dropping it, because that list is precisely what a later
%load of the same file has to take back out, and metta_source_load/4 is the key
%onto it.
%
%It is a wrapper rather than a fixed body because the Python library's load()
%runs the same file through a reader of its own, to keep one answer group per
%directive (metta_py_load/3 in extensions/python/metta/shim.pl), and a load that is not
%recorded here cannot be replaced later. Both doors, one lifecycle
%[tested: test_both_doors_replace_a_files_definitions].
%
%Publishing is part of the GOAL and not of the cleanup, because it only happens
%on success and because it can raise: a cleanup handler is the wrong place for
%either.
:- meta_predicate with_source_load(+, +, 0).
with_source_load(CanonPath, Space, Goal) :-
    gensym(source_load_, LoadId),
    setup_call_catcher_cleanup(
        asserta(active_source_load(LoadId), ContextRef),
        once(( call(Goal),
               run_source_repairs(LoadId),
               publish_source_load(CanonPath, Space, LoadId) )),
        Catcher,
        ( erase(ContextRef),
          retractall(source_load_repair(LoadId, _)),
          retractall(support_recompile_pending(LoadId, _, _)),
          retractall(source_load_digest(LoadId, _, _)),
          ( Catcher == exit -> true ; rollback_source_load(LoadId) ),
          (   current_transaction(_)
          ->  true
          ;   metta_repair_emptied_shadows
          ) )).

publish_source_load(CanonPath, Space, LoadId) :-
    (   source_load_digest(LoadId, CanonPath, Digest)
    ->  assertz(metta_source_load(CanonPath, Space, LoadId, Digest))
    ;   throw(error(existence_error(metta_source_digest, CanonPath),
                    context(publish_source_load/3,
                            'a source load finished without reading its own \c
                             source, so nothing records what a reload replaces')))
    ).

%Whether the file on disk still holds the text a load was built from, which is
%SWI's if(changed) condition, "the file ... has been modified since it was
%loaded the last time" [source: SWI-Prolog 10.1 Reference Manual, load_files/2].
%
%SWI answers it from the modification time. This hashes the CONTENT instead,
%because a timestamp cannot answer it soundly here: Linux stamps a file from
%the coarse clock, so two writes inside one tick carry the same time, and an
%edit that keeps the length then reads as unmodified. That is exactly the edit
%this item exists for, `(= (answer) 1)` to `(= (answer) 2)`, and a reload that
%misses it is the silent staleness the second door already had.
%
%The text is read either way when the file does load, so what being sure costs
%is one read of a file that turns out not to need loading: 333 inferences over
%a 128-form 3,236-byte source, where loading it costs 95,165
%[measured 2026-08-19, five runs each, no spread].
metta_source_digest(CanonPath, Digest) :-
    read_source_text(CanonPath, Text),
    metta_text_digest(Text, Digest).

metta_source_changed(CanonPath) :-
    metta_source_load(CanonPath, _, _, Loaded), !,
    metta_source_digest(CanonPath, Digest),
    Digest \== Loaded.

%Reloading is what makes the trace-edit-verify cycle possible, and the manual
%describes that cycle as the reason it exists: trace a goal, find unexpected
%behaviour, "Fix the sources and reload them using make/0", retry
%[source: SWI-Prolog 10.1 Reference Manual, section 4.3.2]. Two things were
%missing here and they failed in opposite directions. The Python door had no
%file identity at all, so a second load ADDED the file's definitions on top of
%the first and `(answer)` answered 1 and 2; import! had identity but no change
%detection, so a second import was skipped and the edit was ignored. Neither
%said anything [measured 2026-08-19, both doors].
%
%So this is the other half of the lifecycle P11.6 gave a space: clearing a
%space empties its execution module, and loading a file again replaces what
%that file put there. It is not retract-and-assert. The atoms leave through
%metta_remove_atom/3, the funnel that owns every consequence of an atom
%leaving: an equation un-compiles and forgets its name, a declaration
%recompiles the call sites it was shaping, invalidate_specializations/2 drops
%the specializer's clones, seam:function_removed/1 drops lib_memo's
%generations and lib_tabling's tables and duals.pl's duals, and
%seam:atom_removed/2 tells every LiveView and Python subscription. What no
%atom owns leaves through rollback_source_load/1, the same erase a failed load
%uses, and there is one such thing: a file imported into a NAMED space compiles
%into &self's module while its atoms are stored in that space, so its clauses
%are global where its atoms are not
%[tested: test_a_reloaded_source_replaces_its_definitions_and_says_what_it_replaced,
%test_reloading_invalidates_a_memoized_answer].
%
%Replacement reaches the asking space, and any OTHER space the change has made
%stale. The compiled half is shared for the reason just given, so a file whose
%text has changed cannot be replaced in one space alone: another space still
%holding the old atoms would list definitions the rebuilt module no longer
%answers. A space holding the SAME text is not stale and is left alone, which
%is what keeps loading one file into many spaces linear. The asking space loads
%first, so its pass is the one that compiles; the stale ones are populated
%again after, through LoadInto, called as call(LoadInto, Space).
%
%LoadInto is a parameter because how a file goes into a space is a property of
%the FILE, and the engine is not the only thing that reads one: the Python
%library's trusted fast cache is a serialised space with a format of its own,
%and re-populating one through the MeTTa reader would try to parse its binary
%header. Each door hands in the loader its own format needs.
%
%The withdrawal and the load that follows it are ONE transaction, so a reload
%that raises leaves the previous definitions standing rather than taking them
%with it. This is the difference between a reload being safe to attempt and a
%typo in the source costing the session its program, and the manual makes the
%same point about make/0: "Reloading a previously loaded file is safe, both in
%the debug scenario above and when the code is being executed by another
%thread", where the debug scenario is the fix-and-reload cycle this item is for
%[source: SWI-Prolog 10.1 Reference Manual, section 4.3.2]. transaction/1
%restores an erased clause the same way it discards an asserted one
%[measured 2026-08-19: an erase inside a transaction that then throws left the
%clause answering]. The reload path owns the outer transaction so withdrawal
%and replacement commit together; with_source_load/3 supplies the same atomic
%boundary for a first load, whose dependent repairs can replace older clauses
%[tested: test_a_reload_that_fails_leaves_the_previous_definitions_standing].
:- meta_predicate replacing_previous_load(+, +, 1, 0).
replacing_previous_load(CanonPath, Space, LoadInto, Goal) :-
    (   metta_source_load(CanonPath, _, _, _)
    ->  replaced_source_spaces(CanonPath, Space, Replaced),
        (   Replaced == []
        ->  call(Goal)
        ;   call_cleanup(
                transaction(replace_source_load(CanonPath, Space, Replaced,
                                                LoadInto, Goal)),
                metta_repair_emptied_shadows),
            %After the commit, because the repair drops predicate entries
            %and abolish/1 is not clause-level: remove_equation/6 records
            %what the withdrawal emptied, and only a function the load
            %did not refill is still a shadow to drop.
            metta_repair_emptied_shadows
        )
    ;   call(Goal)
    ).

%Which spaces this load replaces. Its own, whenever it holds a copy, because
%that is what a consult means. And any OTHER space whose copy this load is
%about to invalidate, which is one holding text this file no longer has: the
%compile that follows rebuilds the shared half from the NEW source, so a space
%still holding the old atoms would list definitions the module no longer
%answers.
%
%A space holding a copy of the SAME text is left alone, and that is what keeps
%the common shape cheap: loading one unchanged file into ten spaces is ten
%loads and not fifty-five, and it says nothing, because nothing was replaced
%[tested test_loading_one_file_into_many_spaces_replaces_none_of_them].
%
%import! asked the same question a moment ago, to decide whether to load at
%all, and this reads the file again rather than being handed that answer.
%Threading it down would save 336 inferences on a path that is about to spend
%tens of thousands loading, and it would be answering from a digest of what
%the file held BEFORE the decision rather than of what is about to be read.
replaced_source_spaces(CanonPath, Space, Replaced) :-
    metta_source_digest(CanonPath, Now),
    findall(S,
            ( metta_source_load(CanonPath, S, _, Loaded),
              ( S == Space -> true ; Loaded \== Now ) ),
            Replaced).

:- meta_predicate replace_source_load(+, +, +, 1, 0).
replace_source_load(CanonPath, Space, Replaced, LoadInto, Goal) :-
    findall(N, ( member(S, Replaced), withdraw_source_load(CanonPath, S, N) ),
            Counts),
    sum_list(Counts, Withdrawn),
    retractall(compiled_metta_source(CanonPath)),
    print_message(informational,
                  metta_source_replaced(CanonPath, Replaced, Withdrawn)),
    call(Goal),
    forall(( member(S, Replaced), S \== Space ), call(LoadInto, S)).

%One space's copy of one file, taken back out. The atoms go first so that the
%funnel sees the state the program was actually running with; the references
%then go the way a rolled-back load's do, and erase/1 on a reference the funnel
%already erased is why rollback_source_load/1 guards it.
withdraw_source_load(CanonPath, Space, Count) :-
    retract(metta_source_load(CanonPath, Space, LoadId, _)),
    findall(Ref, source_load_assertion(LoadId, _, Ref), Asserted),
    reverse(Asserted, Refs),
    findall(AtomSpace-Atom,
            ( member(Ref, Refs), stored_atom_of_ref(Ref, AtomSpace, Atom) ),
            Atoms),
    forall(member(AtomSpace-Atom, Atoms),
           ( metta_remove_atom(AtomSpace, Atom, _) -> true ; true )),
    rollback_source_load(LoadId),
    length(Atoms, Count).

%A cleared space keeps no record of what a file put in it, because nothing of
%it is left to replace and the name is POOLED: a later life reusing the name
%would otherwise be told it already holds a file's atoms and have them
%withdrawn from under it. This is the storage half of the same lifecycle
%clear_native_atoms/1 owns for the execution module
%[tested: test_a_cleared_space_forgets_what_a_file_put_in_it,
%test_a_recycled_space_name_inherits_no_clauses_from_its_past_life].
forget_space_source_loads(Space) :-
    forall(retract(metta_source_load(_, Space, LoadId, _)),
           ( retractall(source_load_assertion(LoadId, _, _)),
             retractall(source_load_support_assertions(LoadId, _)),
             retractall(source_load_digest(LoadId, _, _)) )).

%The marker is the CALLER's fact, so the caller's module has to travel with
%it. `:` on the first argument is what makes SWI qualify the term at the call
%site; without it the assert landed in whichever module this predicate happens
%to live in, and the marker the caller reads back is a different predicate of
%the same name. That is exactly what happened when this file became a module:
%engine/metta.pl's import_when/4 marks imported_metta_source/2 for the
%duration of a load, and this asserted filereader:imported_metta_source/2, so
%the re-entry guard saw nothing, a mutually importing pair recursed 78,000
%frames deep and SWI segfaulted on
%examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/03-import_duplicate_cycle.metta [measured 2026-08-22].
:- meta_predicate run_with_loading_marker(:, 0).

run_with_loading_marker(Marker, Goal) :-
    setup_call_catcher_cleanup(
        assertz(Marker, Ref),
        once(Goal),
        Catcher,
        ( Catcher == exit -> true ; erase(Ref) )).

record_recompiled_source_assertion(Owners, Ref) :-
    forall(member(LoadId, Owners),
           assertz(source_load_assertion(LoadId, artifact, Ref))).
%Both recorders unwrap the deferral door's ownership pin: a clause a force
%materialises belongs to the source that DEFINED it, so the pin names that
%closed load and the journal row lands there; a none owner journals
%nowhere, exactly as its arrival did. The row keeps this tree's KIND
%column either way.
record_source_assertion(Ref) :-
    active_source_load(Load0), !,
    (   Load0 = '$metta_owner_pin'(Load)
    ->  (   Load == none
        ->  true
        ;   assertz(source_load_assertion(Load, artifact, Ref))
        )
    ;   assertz(source_load_assertion(Load0, artifact, Ref))
    ).
record_source_assertion(_).

record_source_atom_assertion(Ref) :-
    active_source_load(Load0), !,
    (   Load0 = '$metta_owner_pin'(Load)
    ->  (   Load == none
        ->  true
        ;   assertz(source_load_assertion(Load, stored, Ref))
        )
    ;   assertz(source_load_assertion(Load0, stored, Ref))
    ).
record_source_atom_assertion(_).

%The same journal decision hoisted out of a run: the context lookup and the
%owner-pin unwrap happen once, and the run's store loop journals each
%reference against the answer with one indexed assert, or skips outright.
%The two must stay one policy: journal_data_ref(L, R) for the L this
%answers writes exactly the row record_source_atom_assertion(R) writes.
journal_load_now(Load) :-
    (   active_source_load(Load0)
    ->  ( Load0 = '$metta_owner_pin'(L) -> Load = L ; Load = Load0 )
    ;   Load = none
    ).

journal_data_ref(none, _) :- !.
journal_data_ref(Load, Ref) :-
    assertz(source_load_assertion(Load, stored, Ref)).

%The load an assertion made RIGHT NOW would be charged to, or none. The
%deferral door records this beside each waiting definition, because the
%definition's clauses are only asserted when something first calls it, and
%that can be inside a DIFFERENT load, on another thread, or nowhere at all.
current_owning_source_load(Load) :-
    (   active_source_load(Load0),
        Load0 \= '$metta_owner_pin'(_)
    ->  Load = Load0
    ;   Load = none
    ).

%Run Goal with the source-load JOURNAL charging LOAD, whatever load is
%active here and now. A deferred equation's compiled clause belongs to the
%source that DEFINED it: journalled under the load that happened to force
%it, a reload of that unrelated file withdrew the clause. Pinning the
%CLOSED owning load is the point: its journal rows are exactly what
%withdrawal walks when the OWNING file is reloaded, so the materialised
%clauses leave with their definitions. A rollback for a closed load never
%runs, so the pin cannot widen any failure. The pin is a MARKED term
%asserted on top of the stack and erased by ITS OWN clause reference, the
%discipline with_source_load keeps for its own marker; the journal writers
%UNWRAP it with inline unification while the repair schedulers and the
%recompile-pending context SKIP pins to the topmost real load.
:- meta_predicate with_owning_source_load(+, 0).
with_owning_source_load(Load, Goal) :-
    setup_call_cleanup(
        asserta(active_source_load('$metta_owner_pin'(Load)), Ref),
        call(Goal),
        erase(Ref)).

%A receipt consults the source journal rather than the support graph because
%its dependencies are physical source-load and clause-reference identities,
%not derived logical nodes. An erased storage reference remains in the journal
%and therefore makes the receipt stale after commit; a transaction rollback
%preserves the reference and therefore preserves the receipt.
source_load_receipt_current(CanonPath, Space, LoadId, Digest) :-
    metta_source_load(CanonPath, Space, LoadId, Digest),
    metta_source_digest(CanonPath, CurrentDigest),
    CurrentDigest == Digest,
    forall(source_load_assertion(LoadId, stored, Ref),
           stored_atom_of_ref(Ref, _, _)).

% Support edges created while a source is loading belong to that load just as
% its executable and provenance clauses do. A failed load therefore erases
% the graph rows it added instead of leaving stale dependencies behind.
:- multifile support_graph:support_assertions_tracked/0.
support_graph:support_assertions_tracked :-
    source_recompile_owners(_).
support_graph:support_assertions_tracked :-
    active_source_load(_).

:- multifile support_graph:support_assertion_record/1.
support_graph:support_assertion_record(Ref) :-
    record_source_assertion(Ref).

% The compiled-form publisher creates several adjacent graph clauses. One
% ownership row retains their references as a group, cutting per-edge loader
% bookkeeping while rollback still erases every clause precisely.
:- multifile support_graph:support_assertion_records/1.
support_graph:support_assertion_records(Refs) :-
    (   source_recompile_owners(Owners)
    ->  forall(member(LoadId, Owners),
               assertz(source_load_support_assertions(LoadId, Refs)))
    ;   active_source_load(Load0)
    ->  (   Load0 = '$metta_owner_pin'(Load)
        ->  (   Load == none
            ->  true
            ;   assertz(source_load_support_assertions(Load, Refs))
            )
        ;   assertz(source_load_support_assertions(Load0, Refs))
        )
    ;   true
    ).

%One pass over the stored equations answers the whole batch. Repairing each
%function separately walked every equation in the system once per function, so
%a load that repaired several paid that scan several times. The recompiled set
%is the union either way, and recompiling rebuilds clauses from stored source
%without changing translated_from, so a single snapshot answers the same set.
run_source_repairs(LoadId) :-
    findall(F, source_load_repair(LoadId, F), Functions0),
    sort(Functions0, Functions),
    transaction(
        ( repair_stale_definitions_batch(Functions),
          repair_support_invalidations(LoadId) )).

repair_stale_definitions_batch([]) :- !.
repair_stale_definitions_batch(Functions) :-
    findall(Node,
            ( member(F, Functions), support_function_node(F, Node) ),
            Nodes0),
    sort(Nodes0, Nodes),
    support_invalidate_many(Nodes).

%Newest first, so an assertion is undone before whatever it was built on.
%
%A reference that is already gone is not an error here, and it arrives two
%ways: erase/1 THROWS on one kind and FAILS on another. The catch alone was
%enough while the only caller was a failed load, whose references are all still
%live. A withdrawal reaches this after metta_remove_atom/3 has already taken
%the equations out, so several references are erased before the sweep starts,
%and a failing erase/1 made forall/2 fail and took the whole withdrawal down
%with it [measured 2026-08-19: it reported one atom and then failed].
rollback_source_load(LoadId) :-
    findall(F,
            ( source_load_assertion(LoadId, stored, Ref),
              stored_atom_of_ref(Ref, _, [=, [F|_], _]),
              atom(F) ),
            Functions0),
    sort(Functions0, Functions),
    findall(Refs,
            retract(source_load_support_assertions(LoadId, Refs)),
            SupportGroups),
    forall(( member(Refs, SupportGroups), member(Ref, Refs) ),
           ( catch(erase(Ref), _, true) -> true ; true )),
    findall(Ref, retract(source_load_assertion(LoadId, _, Ref)), Asserted),
    reverse(Asserted, Refs),
    forall(member(Ref, Refs),
           ( catch(erase(Ref), _, true) -> true ; true )),
    support_prune_orphans,
    repair_after_source_rollback(Functions).

%A failed first load has no enclosing database transaction, yet one of its
%definitions may already have made an older caller recompile.  Once the failed
%definition is erased, invalidate its live function views again so those
%callers rebuild against the restored registry.  A replacement load already
%runs inside replacing_previous_load/4's transaction; its rollback restores
%the old callers itself, and an inner repair would only be discarded with it.
%Keeping this transaction around the dependency repair, instead of around the
%whole source load, also keeps definitions visible to hyperpose worker threads
%while a file's runnable forms execute [tested:
%filereader_source_rollback:failed_late_definition_does_not_recompile_existing_callers;
%examples/ch17-concurrency-and-the-loop/04-thin_forms.metta; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
repair_after_source_rollback([]) :- !.
repair_after_source_rollback(_) :-
    current_transaction(_),
    !.
repair_after_source_rollback(Functions) :-
    transaction(
        ( repair_stale_definitions_batch(Functions),
          repair_support_invalidations )).

rethrow_metta_file_error(_, Error) :- control_exception(Error), !,
                                      throw(Error).
rethrow_metta_file_error(_, Error) :- Error = error(_, context(_, _)), !,
                                      throw(Error).
rethrow_metta_file_error(Filename, error(Type, _)) :- !,
                                                      throw(error(Type, context(Filename, 'while loading MeTTa file'))).
rethrow_metta_file_error(_, Error) :- throw(Error).
