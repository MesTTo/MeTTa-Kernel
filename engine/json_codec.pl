% Purpose: the one JSON door this repository reads and writes through, with
%   SWI's library(json) as its specification and json_codec.c as a fast path
%   beside it. Two callers use it: extensions/python/metta/shim.pl for the
%   network wire codec and lib/lib_json/lib_json.pl for the MeTTa surface, so
%   there is still exactly one JSON implementation for the whole system.
% Assumes:
%   - json_codec.so, if present, sits beside this file and registers
%     metta_c_json_read/3 and metta_c_json_write/3 into this module
%   - a caller passes shape(dicts) or shape(classic) and the three literals it
%     wants; nothing else is an option here, because every other option
%     library(json) takes would need its own parity evidence
% Guarantees:
%   - json_codec_read/3 answers what json_read_dict/3 answers for shape(dicts)
%     and what json_read/3 answers for shape(classic), and json_codec_write/3
%     answers what json_write_dict/3 and json_write/3 answer under width(0),
%     whether or not the artefact is present
%     [tested: json_codec in tests/prolog/suites/libraries/json_codec.plt]
%   - text after one JSON value is refused in BOTH shapes and BOTH paths, and a
%     non-finite number is refused before anything is written
%     [tested: json_codec:trailing_content_is_refused_in_both_shapes,
%     json_codec:a_non_finite_number_is_refused_before_writing]
%   - METTA_C_JSON=off, or a missing artefact, keeps every conversion on
%     library(json), which is what the differential suite compares against
%     [tested: json_codec_differential:every_document_reads_the_same_through_both_paths,
%     json_codec_differential:generated_documents_read_the_same_through_both_paths]
% Fails when: an option list names anything but shape/1 and the three
%   literals. That is an error rather than a silent default, because a caller
%   that wanted json_read_dict's tag/1 or value_string_as/1 would get neither
%   the option nor a warning.
% Owns resources: the foreign library, loaded once at load time and never
%   unloaded.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- module(json_codec,
          [ json_codec_read/3,          % +Text, -Value, +Options
            json_codec_write/3,         % +Value, -Text, +Options
            json_codec_c_active/0
          ]).

:- use_module(library(json),
              [ json_read/3, json_read_dict/3,
                json_write/3, json_write_dict/3 ]).
:- use_module(library(apply), [maplist/2]).
:- use_module(library(lists), [memberchk/2]).
% An embedding that cannot load shared objects at all must still boot: the
% reader seam already treats a failed foreign load as "use the Prolog
% implementation", and this is the same absence rather than an error.
:- catch(use_module(library(shlib)), _, true).

%The artefact rides beside this file as json_codec.c, compiled to
%json_codec.so by engine/build.sh. METTA_C_JSON=off keeps every conversion on
%library(json), which is what the differential suite uses to compare the two
%implementations in one process. The stub clauses keep both foreign names
%defined for the engine's undefined-predicate gate when the artefact is
%absent; the json_codec_c_active/0 guard on every dispatch means a stub is
%unreachable.
:- dynamic json_codec_c_active/0.
:- dynamic json_codec_artifact/1.
:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, 'json_codec.so', SO),
   assertz(json_codec_artifact(SO)).

json_codec_try_load :-
    (   \+ getenv('METTA_C_JSON', off),
        json_codec_artifact(SO),
        exists_file(SO),
        catch(load_foreign_library(SO), _, fail),
        current_predicate(metta_c_json_read/3),
        current_predicate(metta_c_json_write/3)
    ->  assertz(json_codec_c_active)
    ;   json_codec_stub
    ).

json_codec_stub :-
    (   current_predicate(metta_c_json_read/3)
    ->  true
    ;   assertz((metta_c_json_read(_, _, _) :- fail)),
        assertz((metta_c_json_write(_, _, _) :- fail))
    ).

:- json_codec_try_load.

% ------------------------------------------------------------------ options

%json_read_dict/3 tags every object it reads with its own default_tag, the
%atom #, rather than leaving the tag unbound the way dict_create/3 would
%[source: SWI-Prolog 10.1 library(json), default_json_dict_options/1 and the
%json_options record's default_tag field]. Naming it here is what keeps the C
%reader and the Prolog reader from drifting apart on it; they did drift, and
%the differential over nst/JSONTestSuite reported the tag on all eleven of its
%object cases.
json_codec_dict_tag('#').

%ONE pass over the option list, which both reads what this file implements and
%refuses what it does not.
%
%Both halves of that matter. Reading the list five times with memberchk/2, once
%per option plus once for the shape, was most of the seam's own cost on a path
%whose whole point is not to have any. And an option nobody reads is how
%tag(py) survived in the wire decoder for months, silently dropping every "py"
%key it met, so a caller that means something by an option finds out here that
%nothing does.
%
%The C side takes the result as ONE compound rather than a list, so it
%destructures the request once per call instead of walking a list per element.
json_codec_request(Options, Shape,
                   json_codec_options(Dicts, Tag, True, False, Null)) :-
    json_codec_scan(Options, Options, Shape, True, False, Null),
    json_codec_given(shape, Options, Shape),
    json_codec_given(true, Options, True),
    json_codec_given(false, Options, False),
    json_codec_given(null, Options, Null),
    (   Shape == dicts
    ->  Dicts = true
    ;   Shape == classic
    ->  Dicts = false
    ;   throw(error(domain_error(json_codec_shape, Options),
                    context(json_codec_read/3,
                            'pass shape(dicts) or shape(classic)')))
    ),
    json_codec_dict_tag(Tag).

%Whole is the list as the caller gave it, carried only so a refusal can show
%it. The four accumulators take the FIRST occurrence of each option, which is
%what memberchk/2 read before.
json_codec_scan(Options, Whole, _, _, _, _) :-
    var(Options),
    !,
    json_codec_refuse(Whole).
json_codec_scan([], _, _, _, _, _) :- !.
json_codec_scan([Option|Rest], Whole, Shape, True, False, Null) :-
    !,
    json_codec_take(Option, Whole, Shape, True, False, Null),
    json_codec_scan(Rest, Whole, Shape, True, False, Null).
json_codec_scan(_, Whole, _, _, _, _) :-
    json_codec_refuse(Whole).

json_codec_take(Option, Whole, _, _, _, _) :-
    var(Option),
    !,
    json_codec_refuse(Whole).
json_codec_take(shape(Value), _, Shape, _, _, _) :- !, json_codec_first(Shape, Value).
json_codec_take(true(Value), _, _, True, _, _) :- !, json_codec_first(True, Value).
json_codec_take(false(Value), _, _, _, False, _) :- !, json_codec_first(False, Value).
json_codec_take(null(Value), _, _, _, _, Null) :- !, json_codec_first(Null, Value).
json_codec_take(_, Whole, _, _, _, _) :-
    json_codec_refuse(Whole).

json_codec_first(Slot, Value) :-
    (   var(Slot)
    ->  Slot = Value
    ;   true
    ).

json_codec_given(Which, Options, Value) :-
    (   nonvar(Value)
    ->  true
    ;   throw(error(existence_error(json_codec_option, Which),
                    context(json_codec_read/3, Options)))
    ).

json_codec_refuse(Options) :-
    throw(error(domain_error(json_codec_options, Options),
                context(json_codec_read/3,
                        'only shape/1, true/1, false/1 and null/1 are implemented here'))).

%What library(json) itself is given on the fallback path. The dict door reads
%strings for values by default and the classic door reads atoms, so the
%classic one says so: one shape of answer, whichever door produced it.
json_codec_library_options(json_codec_options(_, _, True, False, Null),
                           [true(True), false(False), null(Null),
                            value_string_as(string)]).

% ------------------------------------------------------------------ reading

%One JSON value out of Text, refusing anything but layout after it. The C path
%answers or declines; a decline runs library(json), which is also where every
%JSON syntax error is raised, so error terms and stream positions are the ones
%this repository has always produced.
json_codec_read(Text, Value, Options) :-
    json_codec_request(Options, Shape, COptions),
    (   json_codec_c_active,
        metta_c_json_read(Text, Value, COptions)
    ->  true
    ;   json_codec_read_prolog(Text, Value, Shape, COptions)
    ).

json_codec_read_prolog(Text, Value, Shape, COptions) :-
    json_codec_library_options(COptions, LibraryOptions),
    open_string(Text, Stream),
    call_cleanup(json_codec_read_stream(Stream, Value, Shape, LibraryOptions),
                 close(Stream)).

json_codec_read_stream(Stream, Value, Shape, LibraryOptions) :-
    %json_read/3 and json_read_dict/3 are what atom_json_term/3 and
    %atom_json_dict/3 call once they have opened a stream over the text; going
    %straight to them saves a second copy of the document.
    (   Shape == dicts
    ->  json_read_dict(Stream, Value, LibraryOptions)
    ;   json_read(Stream, Value, LibraryOptions)
    ),
    (   json_codec_rest_is_layout(Stream)
    ->  true
    ;   throw(error(syntax_error(json(trailing_content)),
                    context(json_codec_read/3, _)))
    ).

json_codec_rest_is_layout(Stream) :-
    get_char(Stream, Char),
    (   Char == end_of_file
    ->  true
    ;   char_type(Char, space),
        json_codec_rest_is_layout(Stream)
    ).

% ------------------------------------------------------------------ writing

%The inverse, as one line of text. The finiteness walk is on the FALLBACK path
%only: the C writer declines a non-finite number rather than spelling it, so
%every value that reaches the walk is one the C path would not write anyway,
%and the fast path pays nothing for a check that has never once fired on it.
json_codec_write(Value, Text, Options) :-
    json_codec_request(Options, Shape, COptions),
    (   json_codec_c_active,
        json_codec_no_write_hook,
        metta_c_json_write(Value, Text, COptions)
    ->  true
    ;   json_codec_finite(Value),
        json_codec_write_prolog(Value, Text, Shape, COptions)
    ).

%library(json) declares two multifile hooks that change what its WRITER does:
%json_dict_pairs/2 replaces a dict's key order and json_write_hook/4 replaces
%how a term is emitted [source: SWI-Prolog 10.1 library(json), the multifile
%declaration at json.pl:63]. The C writer knows neither, so a process that
%defines one gets the Prolog writer for everything rather than two writers that
%disagree. Asking costs two lookups per call and buys the only guarantee this
%file makes.
json_codec_no_write_hook :-
    \+ json_codec_hook_defined(json:json_dict_pairs(_, _)),
    \+ json_codec_hook_defined(json:json_write_hook(_, _, _, _)).

json_codec_hook_defined(Head) :-
    predicate_property(Head, number_of_clauses(Count)),
    Count > 0.

%width(0) in both shapes, so the two callers get the SAME text for the same
%value. The alternative, library(json)'s default width(72), lays a document
%out over many lines once it passes 72 columns, which is a second output
%format for the one codec to have and is not a form the C writer implements.
json_codec_write_prolog(Value, Text, Shape, Options) :-
    json_codec_library_options(Options, LibraryOptions),
    (   Shape == dicts
    ->  with_output_to(string(Text),
                       json_write_dict(current_output, Value,
                                       [width(0)|LibraryOptions]))
    ;   with_output_to(string(Text),
                       json_write(current_output, Value,
                                  [width(0)|LibraryOptions]))
    ).

%JSON has no spelling for NaN or the infinities, and json_write_dict/3 emits
%SWI's own float syntax for them, which no JSON reader accepts back. Refusing
%is the only honest answer and it belongs here rather than in one caller,
%because it is a property of JSON and not of the Python binding.
%The var/1 rung is not decoration. Without it the json(Pairs) test below is a
%UNIFICATION against an unbound argument, so json_codec_write(X, Text, Options)
%bound X to json([]) and answered "{}" where json_write_term/4 has always
%raised instantiation_error. That is the steadfastness trap: a check that
%BINDS what it was asked to inspect [source: SWI-Prolog 10.1 Reference Manual,
%section 5.6, citing The Craft of Prolog].
json_codec_finite(Value) :-
    (   var(Value)
    ->  true
    ;   is_dict(Value)
    ->  dict_pairs(Value, _, Pairs),
        json_codec_finite_pairs(Pairs)
    ;   is_list(Value)
    ->  maplist(json_codec_finite, Value)
    ;   float(Value)
    ->  (   float_class(Value, Class),
            ( Class == nan ; Class == infinite )
        ->  throw(error(domain_error(finite_number, Value),
                        context(json_codec_write/3, _)))
        ;   true
        )
    ;   Value = json(JsonPairs)
    ->  json_codec_finite_json_pairs(JsonPairs)
    ;   true
    ).

json_codec_finite_pairs([]).
json_codec_finite_pairs([_-Value|Pairs]) :-
    json_codec_finite(Value),
    json_codec_finite_pairs(Pairs).

%Walked with tests rather than head unification, for the same reason: this
%list comes straight out of a caller's json(Pairs) and may be partial, a
%variable, or something that is not a list at all. Whatever it is,
%json_write_term/4 below is what judges it.
json_codec_finite_json_pairs(Pairs) :-
    (   var(Pairs)
    ->  true
    ;   Pairs = [Pair|Rest]
    ->  (   nonvar(Pair),
            Pair = (_=Value)
        ->  json_codec_finite(Value)
        ;   true
        ),
        json_codec_finite_json_pairs(Rest)
    ;   true
    ).
