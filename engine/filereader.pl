% Purpose: read MeTTa source, split it into complete top-level forms, and
% dispatch each parsed form to the evaluator.
% Guarantees:
%   - source_lifecycle.pl is a plain source unit consulted into this module, so
%     cache, digest, transactional reload, and assertion records retain their
%     filereader predicate identities and load position
%     [tested: tests/prolog/filereader.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d].
%   - A parsed form that cannot translate is not reported as a syntax error
%     [tested 2026-08-14: filereader_translation_errors].
%   - top_forms//2 ignores comment text and keeps parentheses inside escaped
%     string quotes inside their form [tested 2026-08-15:
%     filereader_form_splitter].
%   - parse_metta_source/2 consumes comments in its grammars without building a
%     stripped source copy [measured: 7,736,802 versus 8,874,582 inferences for
%     twenty parses of 48,786 codes, 2026-08-15].
%   - plain and gzip-compressed MeTTa sources are decoded as UTF-8 regardless
%     of the process locale [tested:
%     filereader_source_reload:a_source_is_utf8_independent_of_the_locale;
%     commit=18b1135167d60396c41e63e42ded2f66d0eb1900].
%   - Loader diagnostics contain ANSI escapes only on terminal streams
%     [tested 2026-08-14: filereader_terminal_output].
%   - A type declaration that cannot type a function the same source defines
%     is refused before any of that source's forms run [tested 2026-08-16:
%     filereader_untypable_declaration].
%   - A failed source load removes compiler metadata and generated predicates,
%     and does not repair existing callers against definitions that rolled back
%     [tested 2026-08-14: filereader_source_rollback].
%   - Direct source strings compile equations into their target named space
%     [tested 2026-08-14:
%     tracer:function_defined_in_named_trace_stays_in_that_space].
%   - File functions remain a global fallback when a named space defines the
%     same symbol [tested 2026-08-14: filereader_global_function_scope].
%   - prepare_parsed_forms/1 is the ONE definition of what a source does before
%     any of its own forms run, so a reader that parses for itself
%     (bindings/python/metta/shim.pl does, to keep one answer group per directive) gets
%     the same signature set registered up front, and the same refusal of a
%     declaration that cannot type what the source defines, rather than a
%     second copy of either [tested 2026-08-18:
%     test_a_source_registers_every_signature_before_any_form_runs,
%     test_load_memoizes_a_function_the_same_file_defines_lower_down,
%     test_a_declaration_that_cannot_type_what_the_source_defines_is_refused].
%   - Signature metadata is available source-wide, but a runnable call sees
%     only equations from its source prefix; a head defined later stays
%     unreduced instead of becoming an undefined host call [tested:
%     test_a_bang_before_the_definition_answers_unreduced_not_a_host_error].
%   - Compile-time automatic-cache analysis drains once per definition batch,
%     before a runnable is translated and again at successful source exit, so
%     recursive bodies and their callers compile under one settled decision
%     [tested:
%     test_a_doubly_branching_recursion_is_tabled_automatically_and_a_tail_recursion_is_not;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
%   - That pass costs 31 inferences for a one-form source, identical across
%     three different one-form sources, then 4.006 per plain form and 23.073
%     per definition beyond it [measured 2026-08-18: interleaved A/B over
%     eight benchmark lanes, bindings/python/benchmarks/baseline.json records each].
%   - print_runnable_form/2 and print_function_form/2's trace output, and
%     library(pcre)-backed regex, both work under autoload=false, not only
%     under the engine's default [measured 2026-08-18: NO_AUTOLOAD=1 sh
%     test.sh, the full examples/ corpus].
%   - source_layout//2 skips exactly the characters sread/2 treats as
%     whitespace between atoms, parser.pl's metta_token_boundary/2 layout
%     rows being the one class both read [tested 2026-08-19:
%     test_every_unicode_whitespace_separates_top_level_forms].
%   - A top-level form is ONE ATOM of any kind, so `! untouched-symbol`,
%     `! 42`, `! "text"` and `! &first` run and a bare symbol on its own
%     line is stored, which is what the arbiter does with each. `!` marks
%     the atom after it only before `(`, layout or end of input, and is an
%     ordinary symbol character everywhere else, so `bind!`, `!=`, `!42`
%     and `!$x` are names [tested 2026-08-19: filereader_form_splitter,
%     filereader_bare_top_level_atoms].
%   - Runnable answer groups carry each reader Name-Var map inside the
%     collection template, preserving source variable identity through
%     findall without attributed variables [tested:
%     test_variable_names_survive_to_the_printer; commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
%   - parse_metta_source/2 selects the reader-token registry once for the
%     complete source, so custom token classes apply uniformly without a
%     registry probe per form [tested:
%     test_a_registered_token_class_parses_like_a_shipped_one;
%     commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%   - Grouped source execution enters the same replace, rollback, support
%     repair, and contribution-recording lifecycle as ordinary file loading
%     [tested: filereader_source_reload:a_grouped_load_runs_inside_the_source_lifecycle;
%     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - data forms loaded from files enter through metta_add_atom/3, so declared
%     pre-add admission has the same accept, transform, drop, and refuse
%     behavior on file, host, and running-MeTTa routes [tested:
%     admission_route_matrix:every_verdict_fires_on_every_engine_ingress;
%     commit=ce55fe46f26484be4269d06d6b99684d5edc040f].
%   - the source-wide signature pre-pass advances the process-global function
%     generation only when it adds a fresh fun/1 name [tested:
%     function_catalogue_generation:an_import_bringing_an_equation_bumps_once;
%     commit=4c9a794750103e0a3a2e9d883adde337ffb501f0].
%   - A file that loads again REPLACES what it put in that space rather than
%     adding to it, reaches any other space its change has made stale, and
%     says what it withdrew [tested 2026-08-19:
%     test_a_reloaded_source_replaces_its_definitions_and_says_what_it_replaced,
%     test_a_reload_replaces_the_file_in_every_space_that_holds_it,
%     filereader_source_reload:a_reload_leaves_one_clause_for_a_redefined_function].
%   - The replacement reaches everything derived from the definitions it
%     withdrew, because the atoms leave through metta_remove_atom/3
%     [tested 2026-08-19: test_reloading_invalidates_a_memoized_answer,
%     test_reloading_invalidates_a_tabled_answer,
%     test_reloading_invalidates_a_specialization,
%     test_a_live_view_follows_a_reload].
%   - A reload that raises leaves the previous definitions standing
%     [tested 2026-08-19:
%     test_a_reload_that_fails_leaves_the_previous_definitions_standing].
%   - Replacement is per FILE and reaches nothing another file contributed, so
%     a function two files define still answers twice: that is a name
%     collision and not a reload [tested 2026-08-19:
%     test_a_reload_replaces_that_files_definitions_and_no_others].
%   - "Changed" is answered from the CONTENT, so an edit that keeps a file's
%     length is still an edit where a modification time might not have moved
%     [tested 2026-08-19:
%     filereader_source_reload:an_edit_that_keeps_the_length_is_still_a_change].
%   - Recording what a load contributed costs ONE inference per stored atom,
%     which is one assertz and is what a withdrawal needs to find the atom
%     again, plus about 230 for the load itself. Measured against the same
%     tree without the recording, interleaved, min of three a side, no spread:
%     a 128-equation source 95,396 against 95,165 (+0.24%), and a
%     20,001-atom file 7,381,790 against 7,361,403 through the library's door
%     and 7,322,289 against 7,302,027 through import!'s populate pass, both
%     +0.28%. Asking whether an already-loaded file has changed costs 336, a
%     read and a hash [measured 2026-08-19].
%   - Compiled definitions record their module-qualified symbol supports in
%     supports/2, and a function change queues each transitive compiled caller
%     once for repair [tested:
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: the pass walks the form list three times, once per
%     concern, and three of the 4.006 a plain form costs are those walks
%     [measured 2026-08-18: 60,024 inferences over 20,001 forms]. One merged
%     walk would collect all three, but acquire_declared_dependencies/1
%     belongs to lib/lib_gitimport.pl and takes the form list itself, so
%     merging changes a library's interface; left alone here for that reason.

%The loader's surface: what the engine core asks of it, what a write records
%with it, the host services a binding calls, and the parser doors it publishes
%on the reader's behalf. The form splitter, the fast-cache codec, the source
%layout grammar and the reload bookkeeping are its own; a caller that wants one
%says filereader: and means it
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
:- encoding(utf8).
:- module(filereader,
          [ load_imported_metta_file/3,
            load_metta_source_groups/3,
            process_metta_string/3,
            parse_metta_source/2,
            parsed_form_parts/4,
            metta_answer_term/2,
            metta_source_changed/1,
            run_with_loading_marker/2,
            record_source_assertion/1,
            record_translated_from/3,
            forget_translated_from/3,
            forget_space_source_loads/1,
            recompile_function_impl/1,
            repair_after_late_registration/1,
            support_invalidate_function/1,
            support_invalidate_function_change/2,
            support_invalidate_definition/1,
            repair_support_invalidations/0,
            %engine/main.pl's command line runs a file through this one,
            %and engine/translator.pl asks whether a source load is active
            %before it defers a runnable's definition.
            load_metta_file/2,
            active_source_program/1,
            process_metta_string/2,
            %source_pending_definition/2 is the translator's question about a
            %definition later in the file it is compiling; translated_from/2 is
            %the compiled clause's source equation, which the specializer and
            %the tracer both read; working_dir/1 is the relative-path base a
            %parity driver asserts from outside.
            source_pending_definition/2,
            translated_from/2,
            working_dir/1,
            %The engine-wide print-suppression flag. It is set from the command
            %line right below, and by a host through petta_py_set_silent/1, and
            %READ by engine/translator.pl, engine/specializer.pl and
            %engine/metta.pl as well as by the three printers here, so there has
            %to be exactly one of it. Left off this list the module cut made two:
            %a host set user:silent/1 while this file kept reading its own, and
            %the engine printed every compiled goal it was told to suppress,
            %which cost 379 inferences on every run through the Python door
            %[measured 2026-08-22: 625 per run before the cut, 1004 after, and
            %625 again with this line].
            silent/1,

            % Host services: the engine defines them, a binding calls them.
            metta_host_run_source/4,
            metta_host_run_source_status/3,
            metta_host_load_file/3,
            metta_host_read_forms/2,
            metta_host_save_fast/3,
            metta_host_load_fast/2,
            metta_host_fast_header/1,
            metta_host_digest/2,
            metta_host_substitute/3
          ]).

:- use_module(library(readutil)). % read_file_to_string/3
%eos//0, for the source-layout grammar below. It used to arrive by accident:
%engine/parser.pl imported dcg/basics into the one namespace everything shared,
%so this file saw eos//0 without asking. With the parser in a module of its
%own the accident stopped and source_comment//2 raised
%existence_error(procedure, eos/2) on the first comment it read
%[measured 2026-08-22].
:- use_module(library(dcg/basics), [eos//0, digits//1, number//1,
                                    string//1, string_without//2]).
:- use_module(library(ansi_term)). % terminal-aware diagnostic colors
:- use_module(library(pcre)). % re_replace/4
%pcre.pl declares four local :- autoload/2 lines (apply, error, dcg/basics,
%lists) but reads its own Options list with option/2 (library(option))
%without declaring THAT one, so it too resolves by global autoload today
%[measured 2026-08-18: examples/libraries/regex_lib.metta under
%NO_AUTOLOAD=1, existence_error(procedure,pcre:option/2)]. Same trap as
%ugraphs.pl and clpb.pl (lib/lib_constraints.pl has both), same fix.
:- pcre:use_module(library(option), [option/2]).
:- use_module(library(zlib)). % gzopen/3, .gz program files
:- use_module(library(fastrw), [fast_read/2, fast_write/2]). % the fast cache
:- use_module(library(memfile)). % the fast save's hashed payload buffer
:- use_module(library(ordsets)). % ord_memberchk/2
:- use_module(library(pairs)). % group_pairs_by_key/2
%Every compiled clause's source equation; asserted here and by
%add-atom/3, read by removal and the tracer, so it must exist before
%the first function ever compiles (a virgin-engine remove-atom read it
%undefined and crashed).
:- dynamic translated_from/2.

:- multifile prolog:error_message//1.

prolog:error_message(petta_translation_failed(Form)) -->
    [ 'Could not translate MeTTa form: ~p'-[Form] ].

%What a reload replaced, said rather than done quietly. It goes out at
%informational, which is where SWI puts what the loader did and is the level a
%caller silences deliberately with -q or verbose(silent) rather than by
%accident.
:- multifile prolog:message//1.
prolog:message(petta_source_replaced(CanonPath, Spaces, Atoms)) -->
    { atomic_list_concat(Spaces, ' ', Named) },
    [ 'replaced ~w: ~w atom(s) withdrawn from ~w'-[CanonPath, Atoms, Named] ].
:- current_prolog_flag(argv, Args), ( (memberchk(silent, Args) ; memberchk('--silent', Args) ; memberchk('-s', Args))
                                      -> assertz(silent(true)) ; assertz(silent(false)) ).
:- dynamic working_dir/1.
:- dynamic compiled_metta_source/1.
:- thread_local active_source_load/1.
:- dynamic source_load_assertion/2.
:- dynamic source_load_support_assertions/2.
:- dynamic source_load_repair/2.
%What a file put where, so that loading it again can REPLACE that rather than
%add to it. SWI states the rule this implements: "clauses are owned by the file
%in which they are defined. This information is used to replace the old
%definition after the file has been modified and is reloaded"
%[source: SWI-Prolog 10.1 Reference Manual, consult/1]. Here the owned things
%are whatever the load asserted, which source_load_assertion/2 already lists,
%so the file only needs the key onto that list and the digest of the text it
%was built from.
%
%The list is KEPT as the per-assertion facts the load built it up as, rather
%than collected into one clause holding a list of references. The collected
%form is the smaller of the two, one clause where this pays a clause header
%per atom of every file loaded, and it was tried and rejected on cost: it has
%to walk the accumulator at the end of every load, and that walk cost 80,410
%inferences of the save-load benchmark's 8,502,424 [measured 2026-08-19,
%interleaved A/B, min of three a side]. Keeping the facts costs the load
%NOTHING and takes a walk off it, because the success path used to retract
%them one at a time.
%
%A clause reference is a BLOB of type clause, so holding one keeps its clause
%from being reclaimed and a stale one decodes to nothing rather than to
%whatever later took its place [measured 2026-08-19: erased, then 200,000
%clauses asserted and two clause collections later, the reference still
%decoded to nothing and erase/1 on it failed].
:- dynamic metta_source_load/4. %metta_source_load(CanonPath, Space, LoadId, Digest)
:- dynamic source_load_digest/3. %source_load_digest(LoadId, Filename, Digest)

%SHA-256 of a text, from whichever library this build carries. library(crypto)
%is OpenSSL's and a build without OpenSSL does not have it: the WebAssembly
%build is the one in front of us, where it is the only reason a load could not
%take its digest [measured 2026-08-20, swipl-wasm 8.0.6]. library(sha) is
%SWI's own C implementation and ships with every build, that one included.
%
%This is a choice of PROVIDER and not of digest, which is what makes it safe:
%the two agree byte for byte on the same text, so a digest one process wrote
%is a digest the other reads, and metta_source_changed/1 cannot answer
%differently because of which library answered
%[tested: tests/prolog/filereader.plt, both_digest_providers_agree].
:- if(exists_source(library(crypto))).
:- use_module(library(crypto), [crypto_data_hash/3]).
metta_text_digest(Text, Digest) :- crypto_data_hash(Text, Digest, [algorithm(sha256)]).
metta_octets_digest(Payload, Digest) :-
    crypto_data_hash(Payload, Digest, [algorithm(sha256), encoding(octet)]).
:- else.
:- use_module(library(sha), [sha_hash/3, hash_atom/2]).
metta_text_digest(Text, Digest) :- sha_hash(Text, Bytes, [algorithm(sha256)]),
                                   hash_atom(Bytes, Digest).
metta_octets_digest(Payload, Digest) :-
    sha_hash(Payload, Bytes, [algorithm(sha256), encoding(octet)]),
    hash_atom(Bytes, Digest).
:- endif.

%The first digest of a process pays a one-off initialisation, and without this
%it lands on whichever program loads first and reads as that program's cost
%[measured 2026-08-19: 3,132 inferences on the first call, 217 on every later
%one]. Paid here instead, where it belongs.
:- metta_text_digest("", _).

push_working_dir(Filename) :- file_directory_name(Filename, Dir0),
                              ( absolute_file_name(Dir0, Dir, [file_type(directory), file_errors(fail)])
                                -> true
                                 ; Dir = Dir0 ),
                              asserta(working_dir(Dir)).

pop_working_dir :- retract(working_dir(_)), !.
pop_working_dir.

%Read Filename into string S and process it (S holds MeTTa code):
load_metta_file(Filename, Results) :- load_metta_file(Filename, Results, '&self').
load_metta_file(Filename, Results, Space) :-
    with_mutex(metta_loader,
               catch(load_entry_metta_file(Filename, Results, Space),
                     Error,
                     rethrow_metta_file_error(Filename, Error))).

load_entry_metta_file(Filename, Results, Space) :-
    absolute_file_name(Filename, CanonPath, [access(read)]),
    import_when(changed, Space, CanonPath,
                load_imported_metta_file(CanonPath, Results, Space)),
    ( var(Results) -> Results = [] ; true ).

load_metta_file_impl(Filename, Results, Space) :-
    setup_call_cleanup(push_working_dir(Filename),
                       ( read_metta_source(Filename, S),
                         process_loader_string(S, Results, Space) ),
                       pop_working_dir).

%One answer GROUP per runnable form, in source order, which the flattening
%above deliberately loses: a program wants every answer and nothing else, and
%two callers want to know which form produced which. `include` needs the LAST
%group, because the results of a module's last directive are the results of
%including it, and tests/conformance/leatta_run.pl needs every group, because
%the arbiter records one bracketed line per form and the grouping IS the
%observation. It ran its own copy of this until include needed one too.
%
%This is an explicit execution door, so it loads on every call just as the
%Python library's load() does. The public wrapper still enters the ordinary
%file lifecycle: definitions are replaceable, failed loads roll back, and
%support repair waits until the complete source has been admitted. The raw
%implementation below exists only as the lifecycle's body.
%The cut is process_metta_string/4's, for its reason: a source has ONE
%reading, and process_form/4's last clause turns a backtrack into "could not
%translate this form", so a caller that fails after a successful load is told
%the source was malformed.
load_metta_source_groups(Filename, Space, Groups) :-
    with_mutex(metta_loader,
               catch(load_entry_metta_source_groups(Filename, Space, Groups),
                     Error,
                     rethrow_metta_file_error(Filename, Error))).

load_entry_metta_source_groups(Filename, Space, Groups) :-
    absolute_file_name(Filename, CanonPath, [access(read)]),
    import_when(true, Space, CanonPath,
                load_imported_metta_source_groups(CanonPath, Groups, Space)).

load_metta_source_groups_impl(Filename, Space, Groups) :-
    setup_call_cleanup(push_working_dir(Filename),
                       read_metta_source_groups(Filename, Space, Groups),
                       pop_working_dir).

read_metta_source_groups(Filename, Space, Groups) :-
    read_metta_source(Filename, Source),
    prepare_metta_source(Source, Forms),
    with_source_program_order(
        Forms,
        with_runnable_variable_epochs(
            ( maplist(process_loader_form(Space), Forms, PerForm),
              !,
              runnable_groups(Forms, PerForm, Groups) ))).

runnable_groups([], [], []).
runnable_groups([Form|Forms], [Group|Rest], Groups) :-
    (   Form = parsed(runnable, _, _, _)
    ->  Groups = [Group|More]
    ;   Groups = More
    ),
    runnable_groups(Forms, Rest, More).

%The carrier is internal to grouped execution. Consumers that need the MeTTa
%term itself use this seam rather than depending on the carrier functor.
metta_answer_term('$petta_answer'(Term, _), Term) :- !.
metta_answer_term(Term, Term).

%%%% The host run and load surface %%%%
%
%One neutral entry per thing a language binding does with source, so the
%grouping walk, the using-substitution, the load lifecycle and the status
%vocabulary live here ONCE instead of once per binding: the Python shim
%and the Node bridge each carried a copy of the parse-prepare-process walk
%and the six-deep load nest, and the next binding would have paid it
%again. Answers cross as raw terms; the codec stays each host's own.
%
%A reader failure crosses as the engine's reserved control envelope,
%error(metta_control_signal(syntax, M), context(petta, syntax)), the same
%shape the limit guards throw, so a binding classifies the thrown term
%rather than hunting rendered text.
metta_host_tagged_parse(Source, Parsed) :-
    catch(parse_metta_source(Source, Parsed), Caught,
          (   (   Caught = error(syntax_error(M), _)
              ;   Caught = syntax_error(M)
              )
          ->  throw(error(metta_control_signal(syntax, M),
                          context(petta, syntax)))
          ;   throw(Caught)
          )).

%The CLI asserts working_dir/1 from the file it loads and import! reads it
%unconditionally, so a string run needs one too; the process's own
%directory is the honest analogue of "the file's directory" for source
%with no file.
metta_host_default_working_dir :-
    (   working_dir(_)
    ->  true
    ;   working_directory(Dir, Dir),
        assertz(working_dir(Dir))
    ).

%Run source with one answer group per runnable form, in source order.
%Bindings are Name-Value pairs substituting the bare symbol Name
%throughout the parsed forms BEFORE the prepare pass registers
%signatures: a name bound to a host value is gone from the forms that
%run, and registering a signature for a head that no longer exists would
%leave a fun/1 nothing can ever define. An empty Bindings list walks
%nothing.
metta_host_run_source(Source0, Space, Bindings, Groups) :-
    metta_host_default_working_dir,
    ( string(Source0) -> Source = Source0 ; atom_string(Source0, Source) ),
    metta_host_tagged_parse(Source, Parsed0),
    (   Bindings == []
    ->  Parsed = Parsed0
    ;   maplist(metta_host_substitute_form(Bindings), Parsed0, Parsed)
    ),
    prepare_parsed_forms(Parsed),
    with_source_program_order(
        Parsed,
        with_runnable_variable_epochs(
            metta_host_process_groups(Parsed, Space, Groups))),
    !.

%One walk, processing and grouping together: process_form/3, not /4's
%compile mode, because a host-run source compiles its equations into the
%TARGET space's module (the tracer's own guarantee,
%function_defined_in_named_trace_stays_in_that_space), where compile mode
%deliberately targets the base tier for the CLI's entry load.
metta_host_process_groups([], _, []).
metta_host_process_groups([Form|Forms], Space, Groups) :-
    process_form(Space, Form, Results),
    (   Form = parsed(runnable, _, _, _)
    ->  Groups = [Results|More]
    ;   Groups = More
    ),
    metta_host_process_groups(Forms, Space, More).

metta_host_substitute_form(Bindings, parsed(Kind, N, Term0),
                           parsed(Kind, N, Term)) :- !,
    metta_host_substitute(Bindings, Term0, Term).
metta_host_substitute_form(Bindings, parsed(runnable, N, Term0, Names),
                           parsed(runnable, N, Term, Names)) :- !,
    metta_host_substitute(Bindings, Term0, Term).
metta_host_substitute_form(Bindings, Term0, Term) :-
    metta_host_substitute(Bindings, Term0, Term).

metta_host_substitute(_, T, T) :- var(T), !.
metta_host_substitute(Bindings, T, V) :- atom(T), memberchk(T-V, Bindings), !.
metta_host_substitute(Bindings, T, Out) :-
    is_list(T), !,
    maplist(metta_host_substitute(Bindings), T, Out).
metta_host_substitute(_, T, T).

%The status vocabulary a binding shows per answer: value for a head the
%engine will try to reduce, not-reducible otherwise (the translator's own
%test, published as metta_reducible_head/2), and one [empty, none] row
%for a runnable form that answered nothing.
metta_host_run_source_status(Source0, Space, Groups) :-
    metta_host_default_working_dir,
    ( string(Source0) -> Source = Source0 ; atom_string(Source0, Source) ),
    metta_host_tagged_parse(Source, Parsed),
    prepare_parsed_forms(Parsed),
    (   space_module(Space, Module)
    ->  true
    ;   Module = user
    ),
    with_source_program_order(
        Parsed,
        metta_host_status_groups(Parsed, Space, Module, Groups)),
    !.

metta_host_status_groups([], _, _, []).
metta_host_status_groups([Form|Forms], Space, Module, Groups) :-
    process_form(Space, Form, Answers),
    (   Form = parsed(runnable, _, Term, _)
    ->  (   metta_reducible_head(Module, Term)
        ->  Status = value
        ;   Status = 'not-reducible'
        ),
        (   Answers == []
        ->  Group = [[empty, none]]
        ;   findall([Status, Answer], member(Answer, Answers), Group)
        ),
        Groups = [Group|More]
    ;   Groups = More
    ),
    metta_host_status_groups(Forms, Space, Module, More).

%Load a file the way the CLI does, the grouping kept and the caller's
%working_dir restored whatever happens. A host-initiated load REPLACES
%the process working_dir for its duration rather than stacking on it, so
%a later string run resolves relative imports from where the process
%stood; the path is canonical because that is the key the engine's own
%loader records a file under, which is what lets the two doors replace
%each other's loads and not only their own
%[tested: test_both_doors_replace_a_files_definitions].
metta_host_load_file(File, Space, Groups) :-
    ( atom(File) -> FA = File ; atom_string(FA, File) ),
    absolute_file_name(FA, CanonPath, [access(read)]),
    file_directory_name(CanonPath, Dir),
    findall(W, working_dir(W), Saved),
    setup_call_cleanup(
        ( retractall(working_dir(_)),
          assertz(working_dir(Dir)) ),
        import_when(true, Space, CanonPath,
            replacing_previous_load(CanonPath, Space,
                load_imported_metta_file_impl(CanonPath, _),
                with_source_load(CanonPath, Space,
                    ( read_metta_source(CanonPath, S),
                      metta_host_run_source(S, Space, [], Groups) )))),
        ( retractall(working_dir(_)),
          forall(member(W, Saved), assertz(working_dir(W))) )).

%Every form as a [Kind, Text] pair, none compiled, stored, or run: the
%boot-manifest door. Text is the form's own source, which keeps the
%variable names a wire encoding would renumber.
metta_host_read_forms(Source0, Pairs) :-
    ( string(Source0) -> Source = Source0 ; atom_string(Source0, Source) ),
    metta_host_tagged_parse(Source, Parsed),
    maplist(metta_host_form_pair, Parsed, Pairs).

metta_host_form_pair(parsed(Kind, Text, _), [Kind, Text]).
metta_host_form_pair(parsed(Kind, Text, _, _), [Kind, Text]).

:- consult('filereader/source_lifecycle.pl').
%Extract function definitions, call invocations, and S-expressions part of &self space:
process_metta_string(S, Results) :- process_metta_string(S, Results, '&self').
process_metta_string(S, Results, Space) :-
    with_mutex(metta_loader,
               process_direct_metta_string(S, Results, Space)).
process_direct_metta_string(S, Results, Space) :-
    prepare_metta_source(S, ParsedForms),
    with_source_program_order(
        ParsedForms,
        with_runnable_variable_epochs(
            ( maplist(process_form(Space), ParsedForms, ResultsList), !,
              append(ResultsList, Carried),
              maplist(metta_answer_term, Carried, Results) ))).
process_loader_string(S, Results, Space) :-
    prepare_metta_source(S, ParsedForms),
    with_source_program_order(
        ParsedForms,
        with_runnable_variable_epochs(
            ( maplist(process_loader_form(Space), ParsedForms, ResultsList), !,
              append(ResultsList, Carried),
              maplist(metta_answer_term, Carried, Results) ))).

prepare_metta_source(S, ParsedForms) :-
    parse_metta_source(S, ParsedForms),
    prepare_parsed_forms(ParsedForms).

%The signature pre-pass and the evaluation pass deliberately answer different
%questions. The former lets metadata operations see every name in the source;
%the latter must still know which names have no equation in the source prefix
%that has run so far. A keyed thread-local context survives every source door,
%nests safely across imports, and disappears even when a form throws.
:- thread_local active_source_program/1.
:- thread_local source_pending_definition/2.
:- thread_local source_compiled_definition/1.
:- meta_predicate with_source_program_order(+, 0).

with_source_program_order(ParsedForms, Goal) :-
    gensym(source_program_, Id),
    findall(F, source_equation_name(ParsedForms, F), Names0),
    sort(Names0, Names),
    (   Names == []
    ->  call(Goal)
    ;   with_source_definition_order(Id, Names, Goal)
    ).

with_source_definition_order(Id, Names, Goal) :-
    setup_call_cleanup(
        asserta(active_source_program(Id), ContextRef),
        ( forall(member(F, Names), assertz(source_pending_definition(Id, F))),
          call(Goal),
          flush_source_program_analysis_if_needed ),
        ( erase(ContextRef),
          retractall(source_pending_definition(Id, _)),
          retractall(source_compiled_definition(Id)) )).

source_definition_arrived(F) :-
    active_source_program(Id),
    !,
    retractall(source_pending_definition(Id, F)),
    ( source_compiled_definition(Id) -> true
    ; assertz(source_compiled_definition(Id)) ).
source_definition_arrived(_).

%A source containing only runnables cannot have changed a source-call graph,
%so it never enters the extension event door. Definitions are analyzed once
%before the next runnable, or once at source exit, rather than once per
%equation.
flush_source_program_analysis_if_needed :-
    retract(source_compiled_definition(Id)),
    !,
    active_source_program(Id),
    forall(seam:source_program_compiled, true).
flush_source_program_analysis_if_needed.

%Everything a source does BEFORE any of its own forms run, over forms already
%parsed. It is named apart from prepare_metta_source/2 because the parse is
%not the only door onto it: bindings/python/metta/shim.pl reads a source, rewrites the
%parsed forms when run() was given host values, and then processes them one by
%one to keep a group of answers per directive, so it has to prepare the forms
%that will actually RUN rather than the text they were read from. Skipping
%this is what made the library disagree with the engine on seven shipped
%examples, each `!(memoize f)` above the `(= (f ...) ...)` the same file
%defines: fun/1 was not asserted yet and memoize refused the name
%[measured 2026-08-18: 193 of 200 examples agreed, all seven the same root].
prepare_parsed_forms(ParsedForms) :-
    refuse_untypable_source_declarations(ParsedForms),
    register_parsed_signatures(ParsedForms),
    % Pinned git dependencies declared in this file are fetched before any of
    % its forms run (gitimport.pl).
    acquire_declared_dependencies(ParsedForms).

%A source text has ONE parse, so this commits to it. Without the once/1 the
%grammar left a choice point behind every successful parse, and retrying it did
%not offer a second reading, it THREW: the first solution for "(holds foo)" is
%[parsed(expression,"(holds foo)",[holds,foo])] and backtracking into it raised
%`Syntax error: expected '(' or '!('`. So the choice point was not merely
%wasted memory, it was a trap for any caller that backtracked past this point,
%turning a parsed file into a syntax error [reproduced 2026-08-15; it is what
%plunit reported as 18 choicepoint warnings in parser.plt].
parse_metta_source(S, ParsedForms) :-
    string_codes(S, Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    metta_reader_mode(Mode),
    maplist(parse_form_with_mode(Mode), Forms, ParsedForms).

%Every name this source defines by an equation, against every type this source
%declares for it. refuse_untypable_declaration/3 in metta.pl holds the rule and
%says why it refuses; this is the collector for the case that matters most,
%the declaration and the definition written in one file.
%
%The pass is here rather than at registration because a source's declarations
%do not reach the space until its forms are processed, which is AFTER
%register_parsed_signatures/1; and here rather than after the load because by
%then the file's own !(...) forms have already run and a rollback would be
%undoing effects the author already saw. Declarations for names this source
%does not define are left alone: the space has no equations to contradict them,
%and space.lint() reads the whole space, so the cross-file case is named there.
%
%The pass costs 0.05% to 0.23% of the parse it follows [measured 2026-08-16:
%376 inferences against 770,612 over greedy_chess.metta's 128 forms, 418
%against 180,156 over lib_pln.metta's 82].
refuse_untypable_source_declarations(ParsedForms) :-
    findall(F, source_equation_name(ParsedForms, F), Defined0),
    sort(Defined0, Defined),
    Defined \== [],
    findall(Name-Type, source_declaration(ParsedForms, Defined, Name, Type),
            Declarations0),
    Declarations0 \== [],
    !,
    keysort(Declarations0, Declarations),
    group_pairs_by_key(Declarations, Grouped),
    forall(member(Name-Types, Grouped),
           refuse_untypable_declaration(Name, Types)).
refuse_untypable_source_declarations(_).

source_equation_name(ParsedForms, F) :-
    member(parsed(function, _, [=, [F|_], _]), ParsedForms),
    atom(F).

source_declaration(ParsedForms, Defined, Name, Type) :-
    member(parsed(expression, _, [':', Name, Type]), ParsedForms),
    atom(Name),
    ord_memberchk(Name, Defined).

% Register the complete signature set before repairing callers.  Translating a
% caller while only the first overload is visible can otherwise leave it stale.
register_parsed_signatures(ParsedForms) :-
    findall(F-Arity,
            ( member(parsed(function, _, [=, [F|Args], _]), ParsedForms),
              length(Args, InputArity),
              Arity is InputArity + 1 ),
            Signatures),
    register_function_signatures(Signatures).

register_function_signature(F, Arity) :-
    register_function_signatures([F-Arity]).

%A source that defines nothing is now the COMMON caller, because the Python
%library's every run() prepares its forms through here, and the clause below
%runs ten list operations over empty lists to conclude that: 43 of the 73
%inferences the whole pre-pass costs `!(+ 1 2)`, more than the other two
%passes together [measured 2026-08-18].
%
%The cut is load-bearing rather than decoration. SWI recognises two clauses
%where one argument is [] and the SAME argument is [_|_] as a special case and
%selects between them deterministically; the clause below takes a VARIABLE
%there, so that case does not apply and indexing leaves a choice point
%[source: SWI-Prolog 10.1 manual, 2.17 Just-in-time clause indexing]. Writing
%it [_|_] to earn the indexing was rejected: a caller passing a non-list would
%then fail silently where sort/2 raises a type error today.
register_function_signatures([]) :- !.
register_function_signatures(Signatures0) :-
    sort(Signatures0, Signatures),
    findall(F,
            ( member(F-Arity, Signatures),
              \+ arity(F, Arity) ),
            NewArityNames0),
    forall(member(F-Arity, Signatures),
           ( arity(F, Arity) -> true
             ; assertz(arity(F, Arity), Ref),
               record_source_assertion(Ref) )),
    findall(F, member(F-_, Signatures), Names0),
    sort(Names0, Names),
    findall(F, (member(F, Names), \+ fun(F)), NewFunNames),
    forall(member(F, Names),
           ( warn_if_executed_as_symbol(F),
             ensure_fun_registered(F) )),
    append(NewArityNames0, NewFunNames, RepairNames0),
    sort(RepairNames0, RepairNames),
    forall(member(F, RepairNames), repair_after_late_registration(F)).

ensure_fun_registered(N) :- fun(N), !.
ensure_fun_registered(N) :-
    assertz(fun(N), FunRef),
    record_source_assertion(FunRef),
    forall(( current_predicate(N/Arity),
             \+ (current_op(_, _, N), Arity =< 2) ),
           ( arity(N, Arity) -> true
             ; assertz(arity(N, Arity), ArityRef),
               record_source_assertion(ArityRef) )).

%An expression that already executed compiled F as plain data; that execution cannot
%be repaired retroactively, so flag it when F now arrives through a parsed definition:
warn_if_executed_as_symbol(F) :- \+ fun(F), symbol_head(F, runnable), !,
                                 format(user_error, "Warning: ~w is defined or imported after already being used; earlier expressions treat it as a plain symbol. Move the import or definition above the first use.~n", [F]).
warn_if_executed_as_symbol(_).

%A function arriving after its name was already compiled as plain data in stored
%definitions: recompile those definitions from their source terms, so import order
%cannot change what a definition means:
repair_after_late_registration(F) :-
    ( symbol_head(F, clause) -> schedule_definition_repair(F) ; true ).

schedule_definition_repair(F) :-
    active_source_load(LoadId), !,
    ( source_load_repair(LoadId, F) -> true
    ; assertz(source_load_repair(LoadId, F)) ).
schedule_definition_repair(F) :-
    repair_stale_definitions(F).

repair_stale_definitions(F) :-
    transaction(
        ( support_invalidate_function(F),
          repair_support_invalidations )).

%Rebuild every clause of G from its stored source terms. Erasing and re-appending each
%tracked clause in assertion order keeps their relative order; clauses asserted through
%Prolog interop are not tracked and would end up before the rebuilt ones:
recompile_function(G) :-
    transaction(recompile_function_impl(G)).

%One MODULE at a time, because the erase and the re-translation are two
%phases and the second one reads the database the first one emptied. The same
%name compiled into two spaces was erased in BOTH before either was
%retranslated, so a clause whose translation consults that name's definition
%elsewhere saw it as undefined: `(super (f $x))` in a space resolved to
%whatever lay above the erased definition instead of to the definition itself
%[tested: translator_super:a_later_definition_retargets_an_earlier_super].
%Within one module the two phases stay, because that is what keeps the
%rebuilt clauses in their original order behind any the Prolog interop
%asserted untracked.
%Every retained equation of G, found through the clause INDEX rather than by
%walking all of them. translated_from/2's second argument is the whole source
%term, so a caller that binds only G inside it, `[=, [G|_], _]`, gives SWI a
%position to discriminate on: jiti_list/1 reports a deep index at 2/2/1 with
%32,768 buckets and no collisions over 20,000 clauses, where one lookup costs
%12 inferences and the walk cost 40,011, two an equation [measured 2026-08-23].
%
%The three callers below are the whole repair path for a function defined after
%the definitions calling it, so that path no longer costs anything that grows
%with the program it repairs into: repairing eight callers over a space already
%holding M unrelated equations cost 9,692 inferences above the same file with
%the callee written FIRST at M=200 and 211,336 at M=12,800, and costs 6,352 and
%6,316 [tested:
%filereader_late_definition_cost:repairing_late_callers_costs_nothing_that_grows_with_the_program].
%
%Binding G inside the pattern UNIFIES where the walk compared with ==/2, and
%the two agree here because a stored head is always an ATOM: an equation whose
%head is a variable cannot name a function and raises before it is stored
%[tested: spaces_batch:a_variable_headed_equation_raises_either_way], which is
%also why record_translated_supports/2 can require atom(G).
translated_equation_of(G, Ref, Term) :-
    Term = [=, [G|_], _],
    translated_from(Ref, Term).

recompile_function_impl(G) :-
    findall(Module,
            ( translated_equation_of(G, Ref, _),
              clause_property(Ref, module(Module)) ),
            Modules0),
    sort(Modules0, Modules),
    support_invalidate_function(G),
    %EVERY module's retained equations, which is not the same set as the
    %modules that still have clauses: a module whose clauses have all gone
    %keeps its equations otherwise, and the specializer then plans from
    %equations nothing backs. Each module below re-records its own as it
    %retranslates.
    clear_fun_meta(_, G),
    forall(member(Module, Modules), recompile_function_in_module(Module, G)),
    repair_support_invalidations.

recompile_function_in_module(Module, G) :-
    findall(compiled(Ref, Term),
            ( translated_equation_of(G, Ref, Term),
              clause_property(Ref, module(Module)) ),
            Recorded),
    %The erase is also the LIVENESS TEST, and the rebuild runs only over what
    %it took out. A recorded reference can outlive its clause, because a
    %compiled predicate can be retracted outside the engine's own door:
    %tests/prolog/translator.plt's super cleanup takes back its `car-atom`
    %equations with a raw retractall. erase/1 FAILS on such a reference rather
    %than raising, so leaving it in the erase loop failed the whole repair and,
    %through it, the load_metta_file/2 that triggered the repair; and rebuilding
    %it from its retained source would put back a clause something deliberately
    %removed
    %[tested: translator_evaluation_errors:builtin_type_import_keeps_runtime_refusals_visible].
    %
    %`clause_property(Ref, erased)` is NOT the test, however plainly it reads.
    %A clause erased and re-asserted inside the surrounding transaction/1
    %reports `erased` while erase/1 still succeeds on it, so filtering on that
    %property dropped LIVE equations and stopped `super` retargeting: the
    %retarget space's `car-atom` was never rebuilt, so it kept the module its
    %super resolved to before the definition above it arrived
    %[tested: translator_super:a_later_definition_retargets_an_earlier_super].
    %
    %The bookkeeping goes for every recorded reference either way; only the
    %rebuild is conditional.
    forall(member(compiled(Ref, Term), Recorded),
           forget_translated_from(Module, Ref, Term)),
    findall(Term,
            ( member(compiled(Ref, Term), Recorded),
              erase(Ref) ),
            Terms),
    forall(member(Term, Terms),
           ( copy_term(Term, Fresh),
             once(with_metta_module(Module,
                                    translate_clause(Fresh, RawClause))),
             %A rebuilt clause is the same equation, so it carries the same
             %recursion fuel the compile door gave it. Re-translating without
             %this left a recursive definition unbounded the moment anything
             %it mentions changed, because the support graph recompiles a
             %dependent through here rather than through compile_metta_equation
             %[measured 2026-08-21: redefining a function the recursive
             %equation mentions dropped petta_fuel_step/2 from the rebuilt
             %clause body; commit=e8270f8551083f236ce5134ca299adf5347d6898].
             petta_instrument_recursive_clause(Fresh, RawClause, Clause),
             assertz(Module:Clause, NewRef),
             record_source_assertion(NewRef),
             record_translated_from(NewRef, Term, SourceRef),
             record_source_assertion(SourceRef) )).

% Compatibility name for the former name-index walk. Every compiled form now
% records its supports at record_translated_from/3, so one indexed forward
% invalidation answers the same question and includes transitive callers.
recompile_definitions_mentioning(F) :-
    support_invalidate_function(F),
    repair_support_invalidations.

record_translated_from(Ref, Term, SourceRef) :-
    assertz(translated_from(Ref, Term), SourceRef),
    record_translated_supports(Ref, Term).

% One source-form node per executable clause keeps multiple equations for one
% function additive. Removing or retranslating one clause can retire exactly
% its edges without replacing the supports of its siblings.
record_translated_supports(Ref, [=, [G|_], Body]) :-
    atom(G),
    clause_property(Ref, module(Module)),
    !,
    findall(Support,
            ( mentioned_symbol(Body, Symbol),
              Symbol \== G,
              Support = function_view(Module, Symbol) ),
            Supports0),
    sort(Supports0, Supports),
    support_publish_compiled_form(Module, G, Ref, Supports, Body).
record_translated_supports(_, _).

forget_translated_from(Module, Ref, [=, [G|_], _]) :-
    !,
    retractall(translated_from(Ref, _)),
    support_forget(translated_form(Module, Ref)),
    (   translated_equation_of(G, OtherRef, _),
        clause_property(OtherRef, module(Module))
    ->  true
    ;   support_forget(compiled_function(Module, G))
    ).
forget_translated_from(_, Ref, _) :-
    retractall(translated_from(Ref, _)).

% All module views already present in the graph are the callers a late global
% registration can have made stale. Each support_invalidate/1 is itself
% cycle-safe; repairs are drained once after the complete batch is dirty.
support_invalidate_function(F) :-
    support_function_node(F, _),
    !,
    findall(Node, support_function_node(F, Node), Nodes0),
    sort(Nodes0, Nodes),
    support_invalidate_many(Nodes).
support_invalidate_function(_).

support_invalidate_function_change(Module, F) :-
    support_function_change_node(Module, F, _),
    !,
    findall(Node,
            support_function_change_node(Module, F, Node),
            Nodes0),
    sort(Nodes0, Nodes),
    support_invalidate_many(Nodes).
support_invalidate_function_change(_, _).

support_function_change_node(Module, F, Node) :-
    support_function_module(F, Module),
    Node = function(Module, F).
support_function_change_node(_, F, Node) :-
    support_view_module(F, ViewModule),
    Node = function_view(ViewModule, F).

support_function_node(F, Node) :-
    support_function_module(F, Module),
    Node = function(Module, F).
support_function_node(F, Node) :-
    support_view_module(F, Module),
    Node = function_view(Module, F).

%F's OWN compiled equations, which the two invalidations above deliberately
%cannot reach: the graph flows compiled_function -> function -> function_view,
%so invalidating a view reaches the CALLERS and never the definition. That is
%right for an equation change, where a sibling equation's compiled body does
%not depend on this one, and wrong for a DECLARATION, which decides how the
%declared function's own clause compiles: the result rule reads the declared
%result type, so `(: f (-> Atom Atom))` arriving after `(= (f $x) (g $x))`
%has to rebuild f's clause or its answer keeps re-entering evaluation
%[tested: spaces_late_type_declaration:a_late_type_declaration_repairs_its_call_sites].
%
%Every module holding compiled equations of F, which support_function_module/2
%enumerates exactly: the function node is published once per compiled form.
%A module with no compiled form of F costs nothing, because the recompile
%action itself is guarded by supports(translated_form(_, _), _).
support_invalidate_definition(F) :-
    findall(Module, support_function_module(F, Module), Modules0),
    sort(Modules0, Modules),
    forall(member(Module, Modules),
           support_invalidate(compiled_function(Module, F))).

:- dynamic support_recompile_pending/3.
:- multifile support_graph:support_invalidation_action/1.
support_graph:support_invalidation_action(compiled_function(Module, G)) :-
    supports(translated_form(_, _), compiled_function(Module, G)),
    ( active_source_load(LoadId) -> Context = LoadId ; Context = immediate ),
    ( support_recompile_pending(Context, Module, G) -> true
    ; assertz(support_recompile_pending(Context, Module, G)) ).

:- multifile support_graph:support_repair_invalidations/0.
support_graph:support_repair_invalidations :-
    ( support_repairs_deferred -> true ; repair_support_invalidations ).

repair_support_invalidations :-
    repair_support_invalidations(immediate).

repair_support_invalidations(Context) :-
    support_recompile_pending(Context, _, _),
    !,
    findall(Module-G,
            retract(support_recompile_pending(Context, Module, G)),
            Repairs0),
    sort(Repairs0, Repairs),
    forall(member(Module-G, Repairs),
           ( clear_fun_meta(Module, G),
             recompile_function_in_module(Module, G) )).
repair_support_invalidations(_).

mentioned_symbol(Term, _) :- var(Term), !, fail.
mentioned_symbol(Term, Term) :- atom(Term), !.
mentioned_symbol(Term, Symbol) :- is_list(Term),
                                  member(Element, Term),
                                  mentioned_symbol(Element, Symbol).

% First pass converts MeTTa to Prolog terms without mutating registration state.
parse_form(Form, Parsed) :-
    metta_reader_mode(Mode),
    parse_form_with_mode(Mode, Form, Parsed).

parse_form_with_mode(Mode, form(S), parsed(T, S, Term)) :-
    sread_mode(Mode, S, Term),
    ( Term = [=, [F|_], _], atom(F) -> T=function ; T=expression ).
parse_form_with_mode(Mode, runnable(S), parsed(runnable, S, Term, Names)) :-
    sread_with_names_mode(Mode, S, Term, Names).

parsed_form_parts(parsed(Kind, Source, Term), Kind, Source, Term).
parsed_form_parts(parsed(Kind, Source, Term, _), Kind, Source, Term).

% process_form/3 is the direct-string path used by named Python spaces. File
% loads use process_form/4 so source clauses compile once while their atoms are
% populated into each target space.
%Only the token substitution here, not the whole parsed-form rewrite: a data
%atom is not a call site, so the py-call alias rewrite has nothing to do in one
%and this path never ran it. The token lookup is one inference per atom and it
%is what makes `(bind! x 1)` reach a stored `(fact x)`.
process_form(Space, parsed(expression, _, Term0), []) :-
    substitute_bound_tokens(Term0, Term),
    %metta_add_atom/3, not the public `add-atom`: the loader has already
    %resolved this space, so the space-argument check the public one owes a
    %PROGRAM is pure cost here. It runs once per atom loaded, and save-load-metta
    %measured it at exactly two inferences on each of its 20,001
    %[measured 2026-08-17].
    metta_add_atom(Space, Term, _),
    print_expression_form(Term).
process_form(Space, parsed(runnable, FormStr, Term, Names), Result) :-
    flush_source_program_analysis_if_needed,
    rewrite_parsed_form(Space, FormStr, Term, BoundTerm),
    space_module(Space, Module),
    with_metta_module(Module,
                      translate_runnable_expr(BoundTerm, Names, Goals, Result)),
    print_runnable_form(FormStr, Goals),
    call_goals_in(Module, Goals).
process_form(Space, parsed(function, FormStr, Term), []) :-
    Term = [=, [F|Args], _],
    must_be(atom, F),
    length(Args, InputArity),
    Arity is InputArity + 1,
    register_function_signature(F, Arity),
    add_sexp(Space, Term, SpaceRef),
    record_source_assertion(SpaceRef),
    space_module(Space, Module),
    rewrite_parsed_form(Space, FormStr, Term, BoundTerm),
    %The one compile door (compile_metta_equation/4 in spaces.pl) carries
    %the eviction, registration, translation, provenance, and the complete
    %change notification this clause used to restate.
    compile_metta_equation(Module, BoundTerm, _Clause, Ref),
    print_function_form(FormStr, Ref),
    source_definition_arrived(F).
process_form(_, In, _) :-
    throw(error(petta_translation_failed(In),
                context(process_form/3, 'could not translate MeTTa form'))).

% The loader's own door: it records every asserted clause reference, so a
% later source error can erase the whole partial load and leave the file
% retryable. It used to carry a compile/populate MODE whose compile half
% targeted the BASE tier: a file imported into a named space stored its
% atoms there while its equations compiled into &self's module, so a
% top-level call reduced through a space it never imported. The arbiter
% pins the opposite (LeaTTa tests/semantics/grounded/
% 29-builtin-module-alias-import.metta, MEASURED: an alias import admits
% nothing into the caller, both probes staying unreduced data; its model
% is World.moduleReady testing the RUNNING CONTEXT's own space's import
% mark). So equations compile into the RECEIVING space's module, exactly
% as the runtime door above does, every receiving space compiles its own
% copy, and the mode distinction died with the shared-clause optimization
% it existed for [tested:
% test_an_import_into_a_named_space_registers_its_equations_there].
process_loader_form(Space, parsed(expression, _, Term), []) :-
    %File data takes the same admission door as every other ingress. That
    %door also records the asserted source reference for rollback.
    evict_prelude_declaration(Space, Term),
    metta_add_atom(Space, Term, _),
    print_expression_form(Term).
process_loader_form(Space, parsed(runnable, FormStr, Term, Names), Result) :-
    flush_source_program_analysis_if_needed,
    rewrite_parsed_form(Space, FormStr, Term, BoundTerm),
    space_module(Space, Module),
    with_metta_module(Module,
                      translate_runnable_expr(BoundTerm, Names, Goals, Result)),
    print_runnable_form(FormStr, Goals),
    call_goals_in(Module, Goals).
process_loader_form(Space, parsed(function, FormStr, Term), []) :-
    Term = [=, [F|_], _],
    add_sexp(Space, Term, SpaceRef),
    record_source_assertion(SpaceRef),
    rewrite_parsed_form(Space, FormStr, Term, BoundTerm),
    space_module(Space, Module),
    compile_metta_equation(Module, BoundTerm, _Clause, Ref),
    print_function_form(FormStr, Ref),
    source_definition_arrived(F).
process_loader_form(_, In, _) :-
    throw(error(petta_translation_failed(In),
                context(process_loader_form/3, 'could not translate MeTTa form'))).

print_expression_form(_) :- silent(true), !.
print_expression_form(Term) :-
    swrite(Term, STerm),
    ansi_format([fg(yellow)], "--> metta sexpr -->~n", []),
    ansi_format([fg(cyan)], "~w~n", [STerm]),
    ansi_format([fg(yellow)], "^^^^^^^^^^^^^^^^^^^~n", []).

print_runnable_form(_, _) :- silent(true), !.
print_runnable_form(FormStr, Goals) :-
    ansi_format([fg(yellow)], "--> metta runnable  -->~n", []),
    ansi_format([fg(cyan)], "!~w~n", [FormStr]),
    ansi_format([fg(yellow)], "-->  prolog goal  -->", []),
    ansi_format([fg(magenta)], " ~n", []),
    %Module-qualified on purpose: ansi_format/4 (library(ansi_term)) calls a
    %~@ goal argument from ITS OWN module context, not this file's, so an
    %unqualified portray_clause here resolves (or fails to) as
    %ansi_term:portray_clause/N. ansi_term.pl does not declare its own
    %dependency on library(listing), relying on autoload the same way
    %library(prolog_clause) relies on it for nth1/3 (metta.pl's Dependencies
    %section has that finding in full); with autoload=false the unqualified
    %spelling raised existence_error(procedure,ansi_term:portray_clause/1)
    %for EVERY runnable form this prints, i.e. most of the example corpus
    %[measured 2026-08-18: examples/basics/math.metta under NO_AUTOLOAD=1].
    %Naming the predicate's real home module sidesteps the gap in
    %ansi_term.pl entirely, rather than trying to patch a library this repo
    %does not ship.
    forall(member(G, Goals),
           ansi_format([fg(magenta)], "~@", [prolog_listing:portray_clause((:- G))])),
    ansi_format([fg(yellow)], "^^^^^^^^^^^^^^^^^^^^^^^~n", []).

print_function_form(_, _) :- silent(true), !.
print_function_form(FormStr, Ref) :-
    ansi_format([fg(yellow)], "--> metta function -->~n", []),
    ansi_format([fg(cyan)], "~w~n", [FormStr]),
    ansi_format([fg(yellow)], "--> prolog clause -->~n", []),
    clause(Head, Body, Ref),
    ( Body == true -> Show = Head ; Show = (Head :- Body) ),
    %Same ansi_format/module trap as print_runnable_form/2 above.
    ansi_format([fg(green)], "~@", [prolog_listing:portray_clause(current_output, Show)]),
    ansi_format([fg(yellow)], "^^^^^^^^^^^^^^^^^^^^^^~n", []).

%Top-level comments are layout too. Count their terminating newline for source
%diagnostics while consuming their text without constructing another code list.
%
%Whitespace between forms is the reader's own class, parser.pl's
%metta_token_boundary/2, not SWI's code_type/2: reading the two differently is
%what let `(= (a) 1)<IDEOGRAPHIC SPACE>(= (b) 2)` load while the same file
%written with a NO-BREAK SPACE raised `expected '(' or '!('`, SWI calling one
%of them a space and not the other [tested:
%test_every_unicode_whitespace_separates_top_level_forms]. Only "\n" counts a
%line, here and in the Python locator, which counts source.count("\n"), so
%LINE SEPARATOR and NEL are ordinary layout on both sides
%[source: bindings/python/metta/_source_forms.py:80].
source_layout(LC0, LC2) --> ";", !, source_comment(LC0, LC2).
source_layout(LC0, LC2) --> "\n", !,
                             { LC1 is LC0 + 1 },
                             source_layout(LC1, LC2).
source_layout(LC0, LC2) --> [C], { metta_token_boundary(C, layout) }, !,
                             source_layout(LC0, LC2).
source_layout(LC, LC) --> [].

source_comment(LC0, LC2) --> "\n", !,
                              { LC1 is LC0 + 1 },
                              source_layout(LC1, LC2).
source_comment(LC, LC) --> eos, !.
source_comment(LC0, LC2) --> [_], source_comment(LC0, LC2).

%Collect characters until all parentheses are balanced (depth 0), accumulating codes, and also counting newlines:
grab_until_balanced(D, Acc, Cs, LC0, LC2, State) --> [C],
    { string_state(State, C, State1),
      ( State = outside -> ( C=0'( -> D1 is D+1
                                  ; C=0') -> D1 is D-1
                                           ; D1 = D )
                        ; D1 = D ),
      Acc1=[C|Acc],
      ( C=10 -> LC1 is LC0+1 ; LC1 = LC0 ) },
    ( { D1=:=0, State1=outside } -> { reverse(Acc1,Cs), LC2 = LC1 }
                                    ; grab_until_balanced(D1,Acc1,Cs,LC1,LC2,State1) ).

%Read a balanced (...) block if available, turn into string, then continue with rest, ignoring comments:
read_balanced_form(LC, Cs, LC2) -->
    grab_until_balanced(1, [0'(], Cs, LC, LC2, outside), !.
read_balanced_form(LC, _, _) -->
    string_without("\n", Rest),
    { format(atom(Msg), "missing ')', starting at line ~w:~n~s", [LC, Rest]),
      throw(error(syntax_error(Msg), none)) }.

%One top-level ATOM, which is what a MeTTa source is a sequence of. A
%parenthesised expression is the commonest kind and was for a long time the
%only kind this splitter read, so `! untouched-symbol`, `! 42` and `! &first`
%raised `expected '(' or '!('` and took the whole file down with them
%[source: LeaTTa tests/semantics/eval-core/self-evaluating-atoms.metta,
%grounded/25-state-rendering.metta, modules/09-bind/main.metta, all three
%STATUS conforms].
read_top_atom(LC0, Cs, LC1) --> "(", !, read_balanced_form(LC0, Cs, LC1).
read_top_atom(LC0, Cs, LC1) --> read_bare_atom(outside, LC0, [], Cs, LC1).

%A symbol, a number, a string or a variable, ending at the first token
%boundary reached OUTSIDE a string literal, so `! "a b"` is one atom and not
%two. string_state/3 is the same three-state machine grab_until_balanced//6
%runs, which is why a quote, an escape or a semicolon inside the literal
%behaves here exactly as it does inside a form.
read_bare_atom(State, LC0, Acc, Cs, LC2) --> [C],
    { \+ ( State == outside, metta_token_boundary(C, _) ) }, !,
    { string_state(State, C, State1),
      ( C =:= 0'\n -> LC1 is LC0 + 1 ; LC1 = LC0 ) },
    read_bare_atom(State1, LC1, [C|Acc], Cs, LC2).
read_bare_atom(_, LC, Acc, Cs, LC) --> { Acc \== [], reverse(Acc, Cs) }.

top_forms(Forms, LC0) --> source_layout(LC0, LC1),
                          top_forms_after_layout(Forms, LC1).

top_forms_after_layout([], _) --> eos.
top_forms_after_layout(Forms, LC0) -->
    exec_marker, !,
    source_layout(LC0, LC1),
    top_atom_form(runnable, Forms, LC1).
top_forms_after_layout(Forms, LC0) -->
    top_atom_form(form, Forms, LC0).

%A marker with nothing after it contributes no form rather than raising: the
%arbiter's tokenizer emits the marker and its parser then has no atom to mark
%[measured 2026-08-19: LeaTTa --observed-file on a file ending in a bare `!`
%exits 0 and prints nothing].
top_atom_form(_, [], _) --> eos, !.
top_atom_form(Tag, [Term|Fs], LC0) -->
    read_top_atom(LC0, Cs, LC1),
    { string_codes(FormStr, Cs), Term =.. [Tag, FormStr] },
    top_forms(Fs, LC1).

%`!` marks the atom that follows only when it stands before `(`, layout or
%end of input. Everywhere else it is an ordinary symbol character, which is
%what makes `bind!`, `change-state!`, `println!` and `!=` ordinary names, and
%what makes `!42` and `!$x` symbols rather than runnables [source: LeaTTa
%MettaHyperonFull/Runtime/Parser.lean:85-88; measured 2026-08-19: each of
%those two prints nothing there].
exec_marker --> "!", exec_marker_boundary.

exec_marker_boundary, [C] --> [C], !,
    { C =:= 0'( ; metta_token_boundary(C, layout) }.
exec_marker_boundary --> [].
