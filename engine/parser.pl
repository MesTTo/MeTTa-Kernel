% Purpose: parse and print MeTTa atoms with shared variable identity, string
%   escapes, and semicolon comments outside strings.
% Guarantees:
%   - sread/2 and the file loader apply the same semicolon-comment rules
%     without a comment-stripping prepass [tested 2026-08-15:
%     parser_comments, filereader_comments].
%   - a semicolon comment ends only at LF or end of input; CR, NEL and U+2028
%     remain comment text, matching LeaTTa's tokenizeAux comment state rather
%     than Hyperon's wider CR behavior [tested:
%     test_a_comment_terminates_on_the_class_the_arbiter_rules].
%   - swrite/2 names variables by first occurrence, independent of SWI's
%     process-local variable identifiers [tested 2026-08-14:
%     parser_stable_variables].
%   - every public writer refuses a value whose text would read back as a
%     different term, including Janus tuples and zero-arity compounds
%     [tested: parser_refuses_non_metta,
%     test_every_generated_atom_survives_the_write_parse_round_trip;
%     commit=53686aed41e7ff02de69052198afdb537536cbdb].
%   - sdisplay/2 is the explicitly lossy presentation path used by repr and
%     console output; it retains host display syntax without pretending that
%     syntax is readable MeTTa [tested: parser_display,
%     test_non_finite_floats_print_the_arbiters_spellings; commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%   - swrite_with_names/3 preserves reader names without binding the source
%     term; distinct variables carrying one written name receive #N epochs in
%     first-occurrence order [tested: parser_named_variables; commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
%   - a token ends at exactly the Unicode White_Space property plus `(`, `)`
%     and `;`, and at nothing else, which is upstream MeTTa's own rule.
%     metta_token_boundary/2 is the one place that says so, and the layout
%     skipper, the reader lexeme scanner and metta_symbol_writable/1 all read
%     it, so a symbol holding whitespace has no text form and the swrite/2
%     to sread/2 round trip stays inverse [tested:
%     parser_unicode_layout,
%     test_every_unicode_whitespace_separates_atoms;
%     commit=2c741dda928a30d0ce1c7e1fcf0b263b4d1bb97b].
%   - metta_reader_token_class/3 is the reader's declared pattern-to-constructor
%     table. Shipped numbers and strings and custom classes take the same
%     full-token path; custom registrations replace an equal pattern, affect
%     only later parses, and invalidate the symbol-writability table so Python
%     operation names cannot cross the new grammar [tested:
%     test_a_registered_token_class_parses_like_a_shipped_one;
%     commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
%   - metta_unwritable_symbol/2 answers for every value the round trip loses,
%     not only for names: non-finite and rational numbers have no readable
%     numeric spelling, and non-list compounds and opaque host values are not
%     MeTTa terms [tested: parser_number_text, parser_refuses_non_metta,
%     property_roundtrip; commit=53686aed41e7ff02de69052198afdb537536cbdb].
%   - command_wants_more/1's string and escaped states are marked as parser
%     mechanism states, not silently exempted policy values [tested:
%     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
%     commit=42b5d28232e75c32b20a1d5bf1f740fec134938d].
%   - when engine/reader.so is present and no custom token class is
%     registered, sread_mode/3 and sread_with_names_mode/4 answer through the
%     C reader, whose results are variant-identical to this file's grammar
%     over the whole shipped corpus, an adversarial battery, and generated
%     number spellings, errors and failures included; PETTA_C_READER=off or
%     a missing artifact keeps every parse on the grammar below [tested:
%     reader_c in tests/prolog/reader_c.plt; commit=d1093b8bbf5d36b18a3a36fd2536eadc5d04fea3].
% Owns resources:
%   - metta_custom_reader_token/3 retains a host constructor until its pattern
%     is replaced or unregistered [tested:
%     test_a_registered_token_class_parses_like_a_shipped_one;
%     commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
% Guarded by:
%   - '$metta_reader_tokens' serializes registry replacement and removal; each
%     mutation commits atomically with its writability-table invalidation.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The reader and the writer, and nothing else. Everything on the list is
%either a MeTTa builtin, a declared seam, or a name another subsystem calls;
%the DCG nonterminals, the token tables and the layout rules are the
%implementation of those and stay inside. A caller that wants one says
%parser: and means it, which tests/prolog/parser.plt does for the token
%grammar it exercises directly
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
:- module(parser,
          [ sread/2,
            sread_command/2,
            command_balance/5,
            command_content/2,
            command_wants_more/1,
            sread_mode/3,
            sread_with_names/3,
            sread_with_names_mode/4,
            swrite/2,
            swrite_pretty/2,
            swrite_with_names/3,
            sdisplay/2,
            sdisplay_with_names/3,
            string_state/3,
            string_chars/3,
            sexpr/5,
            var_symbol/5,
            metta_reader_mode/1,
            metta_reader_token_class/3,
            metta_reader_token_source/2,
            metta_symbol_writable/1,
            metta_token_boundary/2,
            metta_unwritable_symbol/2,
            metta_host_register_reader_token/2,
            metta_host_unregister_reader_token/1,
            metta_name_pairs/2,
            metta_c_reader_active/0,
            metta_c_parse_source/2,
            metta_c_parse_source/4,
            'register-token!'/3,
            'unregister-token!'/2
          ]).

:- use_module(library(dcg/basics)). %atom//1, number//1, eos//0
:- use_module(library(pcre)).
%shlib exists to load reader.so, and an embedding that cannot load shared
%objects at all (the node binding's sandbox refuses the module itself) must
%still boot: the reader seam already treats a failed foreign load as "use
%the Prolog grammar", so a refused shlib is the same absence, not an error.
:- catch(use_module(library(shlib)), _, true).

%The C reader rides beside this file as reader.c, compiled to reader.so by
%check.sh or by hand with `swipl-ld -shared -O2 -o reader.so reader.c`. It is
%a port of the SHIPPED grammar only, so the dispatches below consult it only
%while metta_reader_mode(shipped) holds; the Prolog grammar in this file
%remains the reader's specification, the custom-token path, and the fallback
%wherever the artifact is absent, exactly the backends' artifact-presence
%pattern. PETTA_C_READER=off keeps the Prolog reader even when the artifact
%exists, which is what the differential suite and the fallback benchmarks
%use. The stub clauses keep both foreign names defined for the engine's
%undefined-predicate gate when the artifact is absent; the
%metta_c_reader_active/0 guard on every dispatch means a stub is unreachable.
:- dynamic metta_c_reader_active/0.
:- dynamic metta_reader_artifact/1.
:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, 'reader.so', SO),
   assertz(metta_reader_artifact(SO)).

metta_try_load_c_reader :-
    (   \+ getenv('PETTA_C_READER', off),
        metta_reader_artifact(SO),
        exists_file(SO),
        catch(load_foreign_library(SO), _, fail),
        %The FOREIGN arity, never the /2 wrapper below: a stale artifact
        %registering an older arity must fall back whole rather than
        %half-activate.
        current_predicate(metta_c_parse_source/4)
    ->  assertz(metta_c_reader_active)
    ;   metta_c_reader_stub
    ).

metta_c_reader_stub :-
    (   current_predicate(metta_c_parse_source/4)
    ->  true
    ;   assertz((metta_c_parse_source(_, _, _, _) :- metta_c_reader_refuse)),
        assertz((metta_c_sread(_, _, _) :- metta_c_reader_refuse))
    ).

%The 2-ary spelling for a caller with no use for the summary.
metta_c_parse_source(S, Forms) :-
    metta_c_parse_source(S, Forms, _, _).

metta_c_reader_refuse :-
    throw(error(existence_error(metta_c_reader, 'engine/reader.so'),
                context(metta_c_parse_source/4,
                        'build it: swipl-ld -shared -O2 -o engine/reader.so engine/reader.c'))).

:- metta_try_load_c_reader.

%The tokenizer is the reader seam upstream: an ordered mapping from a full
%token regex to a constructor, searched newest first. These shipped rows are
%the numeric and string literals the old DCG alternatives implemented. The
%patterns are equivalent to hyperon-experimental's rows, and full matching is
%enforced by the PCRE options rather than left to every pattern author
%[source: hyperon-experimental@0559a5e2dd23017c459da3c7b003c7f271e77ac8,
%lib/src/metta/text.rs:Tokenizer and
%lib/src/metta/runner/stdlib/{arithmetics,string}.rs; commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
metta_shipped_reader_token('[+-]?[0-9]+', number).
metta_shipped_reader_token('[+-]?[0-9]+[.][0-9]+', number).
metta_shipped_reader_token('[+-]?[0-9]+([.][0-9]+)?[eE][+-]?[0-9]+', number).
metta_shipped_reader_token('(?s)^".*"$', string).

:- dynamic metta_custom_reader_token/3.

%Choose once per source form. The shipped mode is a deterministic
%specialization of the declared rows below; custom mode performs the ordered
%regex lookup before those same shipped constructors. Keeping the decision
%outside recursive sexpr parsing avoids a registry probe and PCRE dispatch on
%every ordinary token. A registration-maintained activity flag was measured
%against this two-clause probe on the p2-io-roundtrip merge and changed no
%floor by more than layout noise, so the probe stays in its simplest form.
metta_reader_mode(custom) :- metta_custom_reader_token(_, _, _), !.
metta_reader_mode(shipped).

%Public reflection over the mapping. A host constructor remains the same live
%object so a tool inspecting its own registration can identify it.
metta_reader_token_class(Pattern, Constructor, custom) :-
    metta_custom_reader_token(Pattern, Descriptor, _),
    metta_reader_token_descriptor_constructor(Descriptor, Constructor).
metta_reader_token_class(Pattern, Constructor, shipped) :-
    metta_shipped_reader_token(Pattern, Constructor).

metta_reader_token_descriptor_constructor(metta(Constructor), Constructor).
metta_reader_token_descriptor_constructor(host(Constructor), Constructor).

%The host door stores the callable itself. Janus's object blob owns its Python
%reference, so replacement needs no second registry that could drift; normal
%Prolog clause and blob reclamation owns the retired constructor's lifetime.
metta_host_register_reader_token(Pattern, Constructor) :-
    nonvar(Constructor),
    metta_register_reader_token(Pattern, host(Constructor)).
metta_host_unregister_reader_token(Pattern) :-
    metta_unregister_reader_token(Pattern).

metta_register_reader_token(Pattern0, Descriptor) :-
    metta_reader_token_pattern(Pattern0, Pattern),
    re_compile(Pattern, Regex, [anchored(true), endanchored(true)]),
    with_mutex('$metta_reader_tokens',
               transaction(( retractall(metta_custom_reader_token(Pattern, _, _)),
                             asserta(metta_custom_reader_token(Pattern,
                                                               Descriptor,
                                                               Regex)),
                             abolish_table_subgoals(metta_symbol_writable(_)) ))).

metta_unregister_reader_token(Pattern0) :-
    metta_reader_token_pattern(Pattern0, Pattern),
    with_mutex('$metta_reader_tokens',
               (   metta_custom_reader_token(Pattern, _, _)
               ->  transaction(( retractall(metta_custom_reader_token(Pattern,
                                                                       _, _)),
                                  abolish_table_subgoals(
                                      metta_symbol_writable(_)) ))
               ;   true
               )).

metta_reader_token_pattern(Pattern, Pattern) :- string(Pattern), !.
metta_reader_token_pattern(Pattern0, Pattern) :- atom(Pattern0), !,
    atom_string(Pattern0, Pattern).
metta_reader_token_pattern(Pattern, _) :-
    throw(error(type_error(text, Pattern),
                context(metta_reader_token_class/3,
                        'a token pattern is text'))).

%The source-language door names an expression constructor. The name is
%checked before the mapping changes because an unreadable constructor could
%never appear in the expression it promises to build.
'register-token!'(Pattern, _, _) :- var(Pattern), !,
    refuse_unbound_input('register-token!', 1).
'register-token!'(_, Constructor, _) :- var(Constructor), !,
    refuse_unbound_input('register-token!', 2).
'register-token!'(Pattern, Constructor, true) :-
    metta_source_reader_token_pattern('register-token!', Pattern),
    (   atom(Constructor), metta_symbol_writable(Constructor)
    ->  metta_register_reader_token(Pattern, metta(Constructor))
    ;   throw(error(domain_error(metta_reader_constructor, Constructor),
                    context('register-token!'/3,
                            'the constructor must be a readable symbol')))
    ).

'unregister-token!'(Pattern, _) :- var(Pattern), !,
    refuse_unbound_input('unregister-token!', 1).
'unregister-token!'(Pattern, true) :-
    metta_source_reader_token_pattern('unregister-token!', Pattern),
    metta_unregister_reader_token(Pattern).

metta_source_reader_token_pattern(_, Pattern) :- string(Pattern), !.
metta_source_reader_token_pattern(_, Pattern) :- atom(Pattern), !.
metta_source_reader_token_pattern(Operation, Pattern) :-
    throw(error(type_error(text, Pattern),
                context(Operation, 'a token pattern is text'))).

%Read ONE form and answer the variable names it bound, for a caller that
%carries names across a wire: sread/2 is this without the map, and the map
%is name-to-variable pairs in first-occurrence order, exactly what the DCG
%builds while it reads.
sread_with_names(Text, Term, VarMap) :-
    metta_reader_mode(Mode),
    sread_with_names_mode(Mode, Text, Term, VarMap).

sread_with_names_mode(Mode, Text, Term, VarMap) :-
    (   Mode == shipped,
        metta_c_reader_active
    ->  metta_c_sread(Text, Term, VarMap)
    ;   ( string(Text) -> S = Text ; atom_string(Text, S) ),
        string_codes(S, Cs),
        ( catch(phrase(sexpr_mode(Mode, Term, [], VarMap), Cs),
                error(syntax_error(float_overflow), _),
                metta_saturating_parse(sexpr_mode(Mode, Term, [], VarMap), Cs))
          -> true
           ; format(atom(Msg), 'Parse error in form: ~w', [S]),
             throw(error(syntax_error(Msg), none)) )
    ).

%Generate a MeTTa S-expression string from the Prolog list (inverse parsing).
%A value outside the inverse domain is an error, never lossy display text.
swrite(Term, String) :-
    metta_text_writable(Term),
    stable_print_term(Term, Printable),
    phrase(swrite_numbered(Printable), Codes),
    string_codes(String, Codes).

%Display text is presentation, not serialization. It deliberately preserves
%the old host repr path for repr/2 and consoles while swrite/2 stays an inverse
%of sread/2 over every value it accepts.
sdisplay(Term, String) :-
    stable_print_term(Term, Printable),
    phrase(sdisplay_numbered(Printable), Codes),
    string_codes(String, Codes).

%Present one answer with the reader's Name-Var pairs, the display twin of
%swrite_with_names/3: same identity-preserving numbering, no round-trip
%gate, because an answer's text is presentation beside its wire form and
%must render host-only values and non-finite floats the way the command
%line's sdisplay/2 answers already do.
sdisplay_with_names(Term, Names, String) :-
    named_print_term(Term, Names, Printable),
    phrase(sdisplay_numbered(Printable), Codes),
    string_codes(String, Codes).

%Print one answer with the reader's Name-Var pairs. Term and Names are copied
%as one template before numbering, the same identity-preserving shape findall
%uses for runnable answers. The source term and any attributed constraints on
%it therefore remain untouched [tested: parser_named_variables;
%commit=916def0562c211143bb91cd0bd8b2c9dac7ab4fa].
swrite_with_names(Term, Names, String) :-
    metta_text_writable(Term),
    named_print_term(Term, Names, Printable),
    phrase(swrite_numbered(Printable), Codes),
    string_codes(String, Codes).

%Print a collected answer group. The carrier is internal to the runnable
%collection boundary; accepting ordinary answers too keeps diagnostic clients
%able to print a group they constructed themselves.
swrite_answer_group(Answers, String) :-
    phrase(answer_group_mode(Answers, strict), Codes),
    string_codes(String, Codes).

sdisplay_answer_group(Answers, String) :-
    phrase(answer_group_mode(Answers, display), Codes),
    string_codes(String, Codes).

answer_group_mode([], _) --> "()".
answer_group_mode([Answer|Answers], Mode) -->
    "(", answer_mode(Answer, Mode), answer_tail_mode(Answers, Mode), ")".

answer_tail_mode([], _) --> [].
answer_tail_mode([Answer|Answers], Mode) -->
    " ", answer_mode(Answer, Mode), answer_tail_mode(Answers, Mode).

answer_mode('$metta_answer'(Term, Names), Mode) --> !,
    { ( Mode == strict -> metta_text_writable(Term) ; true ),
      named_print_term(Term, Names, Printable) },
    swrite_mode(Printable, Mode).
answer_mode(Term, Mode) -->
    { ( Mode == strict -> metta_text_writable(Term) ; true ),
      stable_print_term(Term, Printable) },
    swrite_mode(Printable, Mode).

%Retain the direct DCG entry points for parser clients.
swrite_answer_group_(Answers) --> answer_group_mode(Answers, strict).
swrite_answer_(Answer) --> answer_mode(Answer, strict).
swrite_answer_tail(Answers) --> answer_tail_mode(Answers, strict).
%Keep the writer DCGs usable by direct parser clients while the internal
%forms operate on a numbered copy of the source term.
swrite_exp(Term) --> { metta_text_writable(Term),
                       stable_print_term(Term, Printable) },
                      swrite_numbered(Printable).
seq(Terms) --> { metta_text_writable(Terms),
                 stable_print_term(Terms, Printable) },
               seq_numbered(Printable).

stable_print_term(Term, Printable) :-
    copy_term_nat(Term, Printable),
    numbervars(Printable, 0, _, [functor_name('$metta_variable')]).

named_print_term(Term, Names, Printable) :-
    copy_term_nat(Term-Names, Numbered-NumberedState),
    numbervars(Numbered-NumberedState, 0, _,
               [functor_name('$metta_variable')]),
    metta_name_pairs(NumberedState, NumberedNames),
    numbered_variable_indices(Numbered, VariableIndices0),
    sort(VariableIndices0, VariableIndices),
    named_variable_spellings(NumberedNames, VariableIndices, Spellings),
    apply_named_variable_spellings(Numbered, Spellings, Printable).

%A source reader supplies a flat pair list. Nested collapse slots hold copied
%name states, one per collected answer. Unfilled slots are numbered markers
%after the copy and contribute nothing.
metta_name_pairs(State, []) :- var(State), !.
metta_name_pairs('$metta_name_state'(Base, Slots), Pairs) :- !,
    metta_name_pairs(Base, BasePairs),
    metta_name_pairs(Slots, SlotPairs),
    append(BasePairs, SlotPairs, Pairs).
metta_name_pairs([], []) :- !.
metta_name_pairs([Entry|Rest], [Written-Var|Pairs]) :-
    nonvar(Entry),
    Entry = '$metta_epoch_name'(Name, Epoch)-Var, !,
    format(atom(Written), '~w#~d', [Name, Epoch]),
    metta_name_pairs(Rest, Pairs).
metta_name_pairs([Name-Var|Rest], [Name-Var|Pairs]) :- atom(Name), !,
    metta_name_pairs(Rest, Pairs).
metta_name_pairs([State|Rest], Pairs) :- !,
    metta_name_pairs(State, StatePairs),
    metta_name_pairs(Rest, RestPairs),
    append(StatePairs, RestPairs, Pairs).
metta_name_pairs(_, []).

numbered_variable_indices('$metta_variable'(Index), [Index]) :- !.
numbered_variable_indices([Head|Tail], Indices) :- !,
    numbered_variable_indices(Head, HeadIndices),
    numbered_variable_indices(Tail, TailIndices),
    append(HeadIndices, TailIndices, Indices).
numbered_variable_indices(_, []).

%numbervars visits the answer before its side map. Sorting by its ground
%ordinal therefore recovers answer first occurrence without comparing live
%variables. Repeated identical pairs collapse before epoch assignment.
named_variable_spellings(Names, VariableIndices, Spellings) :-
    findall(Index-Name,
            ( member(Name-'$metta_variable'(Index), Names),
              atom(Name),
              memberchk(Index, VariableIndices) ),
            Raw),
    sort(Raw, Ordered),
    named_variable_spellings_(Ordered, Ordered, Spellings).

named_variable_spellings_([], _, []).
named_variable_spellings_([Index-Name|Rest], All,
                          [Index-Spelling|Spellings]) :-
    named_variable_count(Name, All, 0, Count),
    (   Count =:= 1
    ->  Spelling = Name
    ;   named_variable_ordinal(Name, Index, All, 0, Epoch),
        format(atom(Spelling), '~w#~d', [Name, Epoch])
    ),
    named_variable_spellings_(Rest, All, Spellings).

named_variable_count(_, [], Count, Count).
named_variable_count(Name, [_-OtherName|Rest], Count0, Count) :-
    ( OtherName == Name -> Count1 is Count0 + 1 ; Count1 = Count0 ),
    named_variable_count(Name, Rest, Count1, Count).

named_variable_ordinal(Name, Index, [OtherIndex-OtherName|Rest], N0, Epoch) :-
    (   OtherIndex =:= Index, OtherName == Name
    ->  Epoch = N0
    ;   ( OtherName == Name -> N1 is N0 + 1 ; N1 = N0 ),
        named_variable_ordinal(Name, Index, Rest, N1, Epoch)
    ).

apply_named_variable_spellings('$metta_variable'(Index), Spellings,
                               '$metta_named_variable'(Name)) :-
    memberchk(Index-Name, Spellings), !.
apply_named_variable_spellings([Head|Tail], Spellings, [NamedHead|NamedTail]) :-
    !,
    apply_named_variable_spellings(Head, Spellings, NamedHead),
    apply_named_variable_spellings(Tail, Spellings, NamedTail).
apply_named_variable_spellings(Term, _, Term).

%A width-aware layout for deep terms: a subterm prints inline when it
%fits the remaining width, and otherwise breaks after its head with each
%child on its own line two deeper, the classic s-expression convention.
%The head itself always inlines, heads being symbols in practice. The
%measuring pass re-renders subterms, quadratic in the worst case, which
%a printer can afford and no hot path calls
%[tested parser_pretty_printing].
swrite_pretty(Term, String) :- swrite_pretty(Term, 78, String).
swrite_pretty(Term, Width, String) :-
    metta_text_writable(Term),
    stable_print_term(Term, Printable),
    with_output_to(string(String), metta_pretty_print(Printable, 0, Width)).

metta_pretty_print(T, Indent, Width) :-
    metta_inline_text(T, Inline),
    string_length(Inline, L),
    Budget is Width - Indent,
    (   L =< Budget
    ->  write(Inline)
    ;   is_list(T), T = [H|Rest], Rest \== []
    ->  metta_inline_text(H, HeadText),
        format("(~w", [HeadText]),
        Sub is Indent + 2,
        metta_pretty_children(Rest, Sub, Width),
        write(")")
    ;   write(Inline)
    ).

metta_pretty_children([], _, _).
metta_pretty_children([C|Cs], Indent, Width) :-
    nl, tab(Indent),
    metta_pretty_print(C, Indent, Width),
    metta_pretty_children(Cs, Indent, Width).

metta_inline_text(T, S) :-
    phrase(swrite_numbered(T), Codes),
    string_codes(S, Codes).

swrite_numbered(Term) --> swrite_mode(Term, strict).
sdisplay_numbered(Term) --> swrite_mode(Term, display).

swrite_mode('$metta_named_variable'(Name), _) --> !, "$", atom(Name).
swrite_mode('$metta_variable'(Index), _) --> !, "$_", { number_codes(Index, Cs) }, Cs.
%The language spells its booleans `True` and `False`. metta_reader_default/2 maps both
%onto Prolog's own true/false so a compiled guard calls them directly, and this
%is the other half of that map: without it the round trip renamed the
%language's own constants and `!(== 1 2)` answered `false` where the arbiter
%answers `False` [source: LeaTTa tests/semantics/grounded/07-partial-core.metta,
%04-boolean.metta]. It also closes a seam: bindings/python/metta already writes `True`,
%which bindings/python/tools/example_parity.py had to compare around
%[tested: parser_roundtrip:booleans_print_in_the_languages_own_spelling].
swrite_mode(true, _)  --> !, "True".
swrite_mode(false, _) --> !, "False".
swrite_mode(Num, _)   --> { integer(Num) }, !, { number_codes(Num, Cs) }, Cs.
swrite_mode(Num, strict) --> { float(Num), metta_number_writable(Num) }, !,
                              { metta_float_codes(Num, Cs) }, Cs.
swrite_mode(Num, display) --> { float(Num) }, !,
                               { metta_float_codes(Num, Cs) }, Cs.
swrite_mode(Num, strict) --> { number(Num), metta_number_writable(Num) }, !,
                              { number_codes(Num, Cs) }, Cs.
swrite_mode(Num, display) --> { number(Num) }, !,
                               { number_codes(Num, Cs) }, Cs.
swrite_mode(Str, _)   --> { string(Str) }, !, "\"", { string_codes(Str, Cs), escape_quotes(Cs, Es) }, Es, "\"".
swrite_mode(Atom, strict) --> { atom(Atom), metta_symbol_writable(Atom) }, !,
                               atom(Atom).
swrite_mode(Atom, display) --> { atom(Atom) }, !, atom(Atom).
swrite_mode(List, Mode) --> { is_list(List), List = [_|_] }, !,
                            "(", seq_mode(List, Mode), ")".
swrite_mode([], _)    --> !, "()".
%A Janus tuple is -/N. Python-looking text belongs only to display mode because
%`(1, 2)` reads as the symbol `1,` beside the number 2, and -() reads as [].
swrite_mode(Term, display) --> { seam:grounded_text(Term, Text) }, !,
                               { string_codes(Text, Cs) }, Cs.
swrite_mode(Term, display) --> { compound(Term),
                                 compound_name_arguments(Term, F, Args) }, !,
                               "(", atom(F),
                               ( { Args == [] }
                               -> []
                               ;  " ", seq_mode(Args, display)
                               ), ")".
swrite_mode(Term, display) --> { term_string(Term, Text),
                                 string_codes(Text, Cs) }, Cs.
%Direct strict-DCG clients receive the same refusal as swrite/2.
swrite_mode(Term, strict) --> { metta_refuse_text(Term) }.

seq_numbered(Terms) --> seq_mode(Terms, strict).

seq_mode([X], Mode)    --> !, swrite_mode(X, Mode).
seq_mode([X|Xs], Mode) --> swrite_mode(X, Mode), " ", seq_mode(Xs, Mode).

%Every float class prints the arbiter's way: inf, -inf by sign, an unsigned
%NaN (the forms hyperon's Rust f64 Display prints and the arbiter's
%pretty-printer pins), and a finite float in the arbiter's LAYOUT over SWI's
%own shortest-round-trip digits. The digits were already the arbiter's, the
%layout was not: SWI writes 1.0e+16 and 1.0e-05 where the arbiter writes
%1e16 and 0.00001 [source 2026-08-20: LeaTTa RyuLean4/Runtime.lean:371-396,
%Decimal.formatMeTTa, Rust ryu's pretty layout]. The printed non-finite
%spelling reads back as a SYMBOL of that name, upstream's exactly as ours,
%which is why metta_number_writable/1 below keeps refusing the class at the
%text seam: the answer PRINTS faithfully, it still does not round-trip.
metta_float_codes(Float, Codes) :-
    float_class(Float, Class),
    (   Class == infinite
    ->  ( Float > 0.0 -> atom_codes(inf, Codes) ; atom_codes('-inf', Codes) )
    ;   Class == nan
    ->  atom_codes('NaN', Codes)
    ;   metta_finite_float_codes(Float, Codes)
    ).

%The arbiter's layout, re-laid over SWI's spelling as pure text. SWI's
%number_codes/2 already emits the shortest decimal that reads back to the
%same binary64 (the digits the arbiter selects too), so this only reshapes:
%with D the stripped significand digits and KK the exponent making the value
%0.D*10^KK, print positionally when the decimal point falls inside or just
%past the digits (KK in -4..16) and scientifically otherwise, exponent KK-1,
%minus sign only, never a plus, never zero-padded. Reshaping text cannot
%move the value, and reading is correctly rounded, so every spelling still
%reads back to the same bits [tested: parser:arbiter_float_layout].
metta_finite_float_codes(Float, Codes) :-
    number_codes(Float, Swi),
    (   Swi = [0'-|Body] -> Sign = [0'-] ; Sign = [], Body = Swi ),
    metta_float_split(Body, AllDigits, Tens),
    metta_strip_leading_zeros(AllDigits, Fore),
    metta_strip_trailing_zeros(Fore, Tens, D, E),
    (   D == [0'0]
    ->  append(Sign, `0.0`, Codes)
    ;   length(D, Len),
        KK is Len + E,
        metta_float_layout(D, Len, KK, Laid),
        append(Sign, Laid, Codes)
    ).

%Split an unsigned SWI float spelling into its digits and the power of ten
%they carry: "1.5e+300" becomes "15" times 10^299. The mantissa's dot only
%positions digits, so folding it into the exponent is exact.
metta_float_split(Body, AllDigits, Tens) :-
    (   append(Mant, [E0|ExpCs0], Body), memberchk(E0, `eE`)
    ->  ( ExpCs0 = [0'+|ExpCs] -> true ; ExpCs = ExpCs0 ),
        number_codes(Exp, ExpCs)
    ;   Mant = Body,
        Exp = 0
    ),
    (   append(IntCs, [0'.|FracCs], Mant)
    ->  true
    ;   IntCs = Mant,
        FracCs = []
    ),
    append(IntCs, FracCs, AllDigits),
    length(FracCs, FracLen),
    Tens is Exp - FracLen.

metta_strip_leading_zeros([0'0, C|Cs], D) :- !,
    metta_strip_leading_zeros([C|Cs], D).
metta_strip_leading_zeros(D, D).

%Dropping a trailing zero divides the digits by ten, so the exponent rises
%with each drop and the value stays put.
metta_strip_trailing_zeros(D0, E0, D, E) :-
    append(Fore, [0'0], D0),
    Fore \== [],
    !,
    E1 is E0 + 1,
    metta_strip_trailing_zeros(Fore, E1, D, E).
metta_strip_trailing_zeros(D, E, D, E).

%The five layout branches, in the oracle's own order.
metta_float_layout(D, Len, KK, Laid) :-
    Point is KK - Len,
    (   Point >= 0, KK =< 16
    ->  length(Zeros, Point),
        maplist(=(0'0), Zeros),
        append([D, Zeros, `.0`], Laid)
    ;   KK > 0, KK =< 16
    ->  length(Whole, KK),
        append(Whole, Frac, D),
        append([Whole, `.`, Frac], Laid)
    ;   KK > -5, KK =< 0
    ->  Pad is -KK,
        length(Zeros, Pad),
        maplist(=(0'0), Zeros),
        append([`0.`, Zeros, D], Laid)
    ;   Exponent is KK - 1,
        number_codes(Exponent, ExpCs),
        (   D = [Only]
        ->  append([[Only], `e`, ExpCs], Laid)
        ;   D = [First|Rest],
            append([[First], `.`, Rest, `e`, ExpCs], Laid)
        )
    ).
%The five escapes hyperon's Str Display emits and this reader already
%decodes (string_chars): quote, backslash, newline, tab, carriage
%return. Writing them keeps a printed string literal on one line, so
%every line-oriented consumer of swrite text (the MORK bridge splits
%dumps on newlines) re-parses it to itself.
escape_quotes([], []).
escape_quotes([0'\\|T], [0'\\,0'\\|R]) :- !, escape_quotes(T, R).
escape_quotes([0'"|T], [0'\\,0'"|R]) :- !, escape_quotes(T, R).
escape_quotes([0'\n|T], [0'\\,0'n|R]) :- !, escape_quotes(T, R).
escape_quotes([0'\t|T], [0'\\,0't|R]) :- !, escape_quotes(T, R).
escape_quotes([0'\r|T], [0'\\,0'r|R]) :- !, escape_quotes(T, R).
escape_quotes([H|T], [H|R]) :- escape_quotes(T, R).

%Read S string or atom, extract codes, and apply the parsing DCG.
%atom_codes/2 reads the text of a string directly. Going through
%atom_string/2 first interned an atom for every string parsed, and the
%library parses one per m.run(): 20000 distinct strings through
%atom_string/2 left 9953 atoms behind, through atom_codes/2 none.
sread(S, _) :- var(S), !, refuse_unbound_input(sread, 1).
sread(S, T) :-
    metta_reader_mode(Mode),
    sread_mode(Mode, S, T).

sread_mode(Mode, S, T) :-
    (   Mode == shipped,
        metta_c_reader_active
    ->  metta_c_sread(S, T, _)
    ;   atom_codes(S, Cs),
        sread_codes_mode(Mode, Cs, S, T)
    ).

sread_codes(Cs, Source, T) :-
    metta_reader_mode(Mode),
    sread_codes_mode(Mode, Cs, Source, T).

sread_codes_mode(Mode, Cs, Source, T) :-
    ( catch(phrase(sexpr_mode(Mode, T, [], _), Cs),
            error(syntax_error(float_overflow), _),
            metta_saturating_parse(sexpr_mode(Mode, T, [], _), Cs))
      -> true
       ; format(atom(Msg), 'Parse error in form: ~w', [Source]),
         throw(error(syntax_error(Msg), none)) ).

%Re-run a parse with float overflow SATURATING instead of raising.
%
%dcg/basics' number//1 converts what it scanned with number_codes/2, which
%raises syntax_error(float_overflow) on a literal past binary64 rather than
%answering. So `(holds 1e400)` did not parse and did not report a parse error
%either: the raise went straight out through sread/2 and killed the run with
%`number_codes/2: Syntax error: float_overflow` naming engine/main.pl
%[measured 2026-08-19; found by the generated-spelling law in
%tests/prolog/property_lane.pl].
%
%Upstream SATURATES. Its float token is a regex handed to Rust's f64 FromStr,
%which returns infinity for a value too large instead of an error
%[source: hyperon-experimental, lib/src/metta/runner/stdlib/arithmetics.rs,
%register_context_independent_tokens, whose three number tokens call
%Number::from_int_str and Number::from_float_str, and hyperon-atom/src/gnd/
%number.rs, where from_float_str is num.parse::<f64>(); measured 2026-08-19 by
%running that parse: "1e400" gives Ok(inf), "-1e400" gives Ok(-inf)].
%Underflow already agreed, 1e-400 giving 0.0 on both sides.
%
%SWI has the same saturation behind the float_overflow flag, so the reader
%borrows it rather than keeping a second number grammar to decide where the
%literal ends. The flag is set only for the RETRY, so an ordinary parse pays
%nothing, and it is thread-local, so a thread already running keeps raising on
%its own arithmetic [measured 2026-08-19: a worker created before the setter
%still reads `error`]. The engine's ARITHMETIC keeps raising on overflow,
%which is a different question with a different answer:
%`(pow-math 10.0 400)` still reports evaluation_error(float_overflow).
metta_saturating_parse(Grammar, Codes) :-
    current_prolog_flag(float_overflow, Was),
    setup_call_cleanup(set_prolog_flag(float_overflow, infinity),
                       phrase(Grammar, Codes),
                       set_prolog_flag(float_overflow, Was)).

%%%% Is this a whole form, or is the user still typing? %%%%
%
%sread/2 answers one way: it parses or it raises. Three different situations
%collapse into that one outcome, and a console needs them apart:
%
%  (f a)     complete           [f, a]
%  (f a      INCOMPLETE         syntax_error('Parse error in form: (f a')
%  (f a))    malformed          syntax_error('Parse error in form: (f a))')
%  ""        an empty line      syntax_error('Parse error in form: ')
%
%CPython names this as THE hard part of a console and answers it three ways:
%"The tricky part is to determine when the user has entered an incomplete
%command that can be completed by entering more text (as opposed to a complete
%command or a syntax error)", and compile_command returns a code object,
%None, or raises [source: CPython, the code and codeop modules]. This is that
%contract: complete(Term), incomplete, or a raise.
%
%Without it examples/basics/repl.metta could not accept a multi-line form at
%all, since 'readln!'/1 is one read_line_to_string then sread/2, and every
%other console has to re-implement bracket counting. Which is not "just count
%parens": a bracket inside a string or a comment must not count, and
%string_state/3 below is what knows the difference
%[tested: parser_command_tells_incomplete_from_malformed].
sread_command(Text, Result) :-
    text_to_command_codes(Text, Codes),
    (   \+ command_has_content(Codes)
    ->  Result = incomplete
    ;   command_wants_more(Codes)
    ->  Result = incomplete
    ;   sread(Text, Term)
    ->  Result = complete(Term)
    ;   sread(Text, _)          % it raises; this reaches its error
    ).

text_to_command_codes(Text, Codes) :-
    ( is_list(Text) -> Codes = Text
    ; string(Text) -> string_codes(Text, Codes)
    ; atom_codes(Text, Codes) ).

%An empty line, or one holding only layout and comments, is INCOMPLETE rather
%than an error: it is the commonest input in any console and it should
%re-prompt.
command_has_content(Codes) :- command_content(Codes, outside).

command_content([C|Rest], State0) :-
    string_state(State0, C, State1),
    (   State0 == outside, \+ metta_token_boundary(C, layout), C =\= 0';
    ->  true
    ;   State0 == string
    ->  true
    ;   command_content(Rest, State1)
    ).

%Whether more text could still complete this: an open bracket, or an
%unterminated string, which a MeTTa string may legitimately be because a
%newline inside one keeps the string state.
%
%An unterminated COMMENT is not: a comment ends at end of input as readily as
%at a newline, so `(f a) ; trailing` is a whole form and treating the comment
%state as "wants more" made it hang the console.
command_wants_more(Codes) :-
    command_balance(Codes, 0, outside, Depth, State),
    % policy-inventory-exempt: mechanism-internal; reason=string and escaped are internal states of the reader state machine; evidence=engine/parser.pl:command_wants_more/1
    ( Depth > 0 -> true ; memberchk(State, [string, escaped]) ).

%A closing bracket too many is MALFORMED, not incomplete: no amount of further
%typing repairs it, so this fails and the reader's own error is the answer.
command_balance([], Depth, State, Depth, State).
command_balance([C|Rest], Depth0, State0, Depth, State) :-
    string_state(State0, C, State1),
    (   State0 == outside
    ->  ( C =:= 0'( -> Depth1 is Depth0 + 1
        ; C =:= 0') -> Depth1 is Depth0 - 1
        ;               Depth1 = Depth0 )
    ;   Depth1 = Depth0
    ),
    Depth1 >= 0,
    command_balance(Rest, Depth1, State1, Depth, State).

%The top-level form scanner uses the same string and comment states as the
%token grammar. A backslash escapes exactly the next string character.
string_state(outside, 0'", string) :- !.
string_state(outside, 0';, comment) :- !.
string_state(string, 0'\\, escaped) :- !.
string_state(string, 0'", outside) :- !.
string_state(escaped, _, string) :- !.
string_state(comment, 0'\n, outside) :- !.
string_state(comment, _, comment) :- !.
string_state(State, _, State).

%Every code that ends a token, and which kind of boundary it is. One table
%answers both questions the reader asks of a character, because two answers
%to one of them is the defect it replaces: the layout skipper took whitespace
%from code_type/2 while the token scanner carried its own list of seven ASCII
%characters, and wherever the two disagreed the token swallowed the
%separator. 21 of the 25 whitespace characters left `(1<c>2)` a single symbol,
%and silently, which is what makes it worth fixing rather than noting.
%NO-BREAK SPACE is what HTML's `&nbsp;` renders to, so `(foo bar)` pasted out
%of a browser became one symbol, matched nothing, and reported no problem
%[tested: parser_unicode_layout].
%
%Both kinds together are upstream MeTTa's own boundary rule, not a wider
%class chosen here: its reader ends a word at `c.is_whitespace() || c ==
%'(' || c == ')' || c == ';'` and at nothing else [source:
%hyperon-experimental v0.2.10-25-g0559a5e2, lib/src/metta/text.rs,
%parse_word]. So the layout rows are the Unicode White_Space property,
%char::is_whitespace being that property exactly [source: Rust std,
%char::is_whitespace, "Returns true if this char has the White_Space
%property", specified in https://www.unicode.org/Public/UCD/latest/ucd/
%PropList.txt, PropList-17.0.0, "Total code points: 25"].
%
%Written out rather than read from code_type/2, for two reasons.
%
%SWI's class is neither the property nor fixed. code_type/2 reads the C
%library's tables, so it MOVES with the locale: 21 codes under en_AU.UTF-8
%and under C.UTF-8, and 6 under LC_ALL=C [measured 2026-08-19, enumerated
%over the whole range]. Which characters separate atoms is a property of the
%language, not of the environment a process happens to start in, and a
%container or a cron job running under LC_ALL=C is ordinary. Even at its
%widest the class is four short of White_Space: it omits NEL and the three
%NO-BREAK spaces, reporting them as cntrl and punct.
%
%And the table has to be ground facts to be indexed. A clause body is a
%call, and worse, one clause with a variable head argument costs the index
%outright: SWI does not build a hash on an argument where more than 10% of
%the clauses are unbound there, because such a clause has to be linked into
%every bucket [source: SWI-Prolog 10.1 Reference Manual 2.17, "Just-in-time
%clause indexing"]. So `metta_token_boundary(C, layout) :- code_type(C,
%space)` beside four named codes would be a five-clause linear scan, not a
%lookup. As 28 ground facts it is a 64-bucket hash [measured 2026-08-19:
%jiti_list/1 reports index 1, speedup 28.0], and reading every shipped
%example while asking metta_unwritable_symbol/2 about each form costs 22.06M
%inferences and 13.01G instructions:u against 24.30M and 18.38G for the
%string_without//2 scan this replaces [measured 2026-08-19, min of 3
%interleaved runs]. parser_unicode_layout holds the table to the property
%and to SWI's own class, so neither can drift unseen.
metta_token_boundary(0x0009, layout).  %CHARACTER TABULATION
metta_token_boundary(0x000A, layout).  %LINE FEED
metta_token_boundary(0x000B, layout).  %LINE TABULATION
metta_token_boundary(0x000C, layout).  %FORM FEED
metta_token_boundary(0x000D, layout).  %CARRIAGE RETURN
metta_token_boundary(0x0020, layout).  %SPACE
metta_token_boundary(0x0085, layout).  %NEXT LINE
metta_token_boundary(0x00A0, layout).  %NO-BREAK SPACE
metta_token_boundary(0x1680, layout).  %OGHAM SPACE MARK
metta_token_boundary(0x2000, layout).  %EN QUAD
metta_token_boundary(0x2001, layout).  %EM QUAD
metta_token_boundary(0x2002, layout).  %EN SPACE
metta_token_boundary(0x2003, layout).  %EM SPACE
metta_token_boundary(0x2004, layout).  %THREE-PER-EM SPACE
metta_token_boundary(0x2005, layout).  %FOUR-PER-EM SPACE
metta_token_boundary(0x2006, layout).  %SIX-PER-EM SPACE
metta_token_boundary(0x2007, layout).  %FIGURE SPACE
metta_token_boundary(0x2008, layout).  %PUNCTUATION SPACE
metta_token_boundary(0x2009, layout).  %THIN SPACE
metta_token_boundary(0x200A, layout).  %HAIR SPACE
metta_token_boundary(0x2028, layout).  %LINE SEPARATOR
metta_token_boundary(0x2029, layout).  %PARAGRAPH SEPARATOR
metta_token_boundary(0x202F, layout).  %NARROW NO-BREAK SPACE
metta_token_boundary(0x205F, layout).  %MEDIUM MATHEMATICAL SPACE
metta_token_boundary(0x3000, layout).  %IDEOGRAPHIC SPACE
metta_token_boundary(0x0028, punctuation).  %LEFT PARENTHESIS
metta_token_boundary(0x0029, punctuation).  %RIGHT PARENTHESIS
metta_token_boundary(0x003B, punctuation).  %SEMICOLON, which opens a comment

%Semicolon comments are inter-token layout. LeaTTa's tokenizer changes out of
%its comment state only for '\n'; CR, NEL and U+2028 remain comment text
%[source 2026-08-21: LeaTTa MettaHyperonFull/Runtime/Parser.lean:58,
%tokenizeAux comment branch at lines 66-67]. This deliberately rejects the
%row's original wider-terminator premise. Keeping comments in the DCG avoids a
%separate source-sized code list before parsing. These clauses combine blank
%and comment scanning so the ordinary no-comment path has no wrapper grammar.
metta_layout --> ";", !, metta_comment_body, metta_layout.
metta_layout --> [C], { metta_token_boundary(C, layout) }, !, metta_layout.
metta_layout --> [].

metta_comment_body --> "\n", !.
metta_comment_body --> eos, !.
metta_comment_body --> [_], metta_comment_body.

%An S-Expression is a parentheses-nesting of S-Expressions. Parentheses and
%variables remain syntax; every word or quoted lexeme then crosses the
%declared token mapping, falling back to a symbol only when no class matches.
%The public grammar chooses a reader mode once, and recursive calls retain it.
sexpr(T, E0, E, S0, S) :-
    metta_reader_mode(Mode),
    sexpr_mode(Mode, T, E0, E, S0, S).

sexpr_mode(Mode, T, E0, E) -->
    metta_layout,
    sexpr_token_mode(Mode, T, E0, E),
    metta_layout.

sexpr_token(T, E0, E, S0, S) :-
    metta_reader_mode(Mode),
    sexpr_token_mode(Mode, T, E0, E, S0, S).

sexpr_token_mode(Mode, T, E0, E) -->
    "(", metta_layout, reader_seq(Mode, T, E0, E), metta_layout, ")", !.
sexpr_token_mode(_, V, E0, E) --> var_symbol(V, E0, E), !.
sexpr_token_mode(custom, T, E, E) --> reader_token(T).
sexpr_token_mode(shipped, T, E, E) --> shipped_reader_token(T).

%Recursive processing of S-Expressions within S-Expressions. sexpr//3 has
%already consumed the whitespace after its own token, so this does not repeat it:
reader_seq(Mode, [X|Xs], E0, E2) -->
    sexpr_mode(Mode, X, E0, E1),
    reader_seq(Mode, Xs, E1, E2).
reader_seq(_, [], E, E) --> [].

%Variables start with $, and keep track of them: reusing existing Prolog variables for variables of same name:
var_symbol(V,E0,E) --> "$", token(Cs), { atom_chars(N, Cs), ( N == '_' -> V = _, E = E0 ; memberchk(N-V0, E0) -> V = V0, E = E0 ; V = _, E = [N-V|E0] ) }.

%A successful class match commits before construction. A constructor that
%fails or raises therefore cannot silently turn its literal into a symbol or
%fall through to an older class, matching the tokenizer's newest-first rule.
reader_token(Term) -->
    reader_token_text(Text),
    {   (   metta_reader_token_match(Text, Descriptor)
        ->  metta_reader_token_construct(Descriptor, Text, Term)
        ;   metta_reader_default(Text, Term)
        )
    }.

%The shipped-only hot path implements the four declared rows without a PCRE
%call or dynamic-registry lookup per token. dcg/basics' number//1 accepts the
%three public numeric patterns exactly, and string_lit//1 is the shipped
%string constructor, so this is a compiled specialization of the declared
%mapping rather than a second token policy [tested: parser_number_text;
%commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
shipped_reader_token(String) --> string_lit(String), !.
shipped_reader_token(Number) --> number(Number), number_ends, !.
shipped_reader_token(Atom) --> atom_symbol(Atom).

number_ends([], []) :- !.
number_ends([Code|Rest], [Code|Rest]) :- metta_token_boundary(Code, _).

atom_symbol(Atom) -->
    token(Codes),
    { string_codes("\"", [Quote]),
      (   Codes = [Quote|_]
      ->  append([Quote|Body], [Quote], Codes),
          string_codes(Atom, Body)
      ;   atom_codes(Read, Codes),
          ( Read == 'True' -> Atom = true
          ; Read == 'False' -> Atom = false
          ; Atom = Read
          )
      ) }.

metta_number_token_codes --> metta_optional_number_sign,
                             metta_decimal_digits,
                             metta_number_token_tail.

metta_optional_number_sign --> "+", !.
metta_optional_number_sign --> "-", !.
metta_optional_number_sign --> [].

metta_decimal_digits --> [Code],
                         { between(0'0, 0'9, Code) }, !,
                         metta_decimal_digit_tail.

metta_decimal_digit_tail --> [Code],
                             { between(0'0, 0'9, Code) }, !,
                             metta_decimal_digit_tail.
metta_decimal_digit_tail --> [].

metta_number_token_tail --> ".", metta_decimal_digits,
                            metta_optional_exponent, !.
metta_number_token_tail --> metta_exponent, !.
metta_number_token_tail --> [].

metta_optional_exponent --> metta_exponent, !.
metta_optional_exponent --> [].

metta_exponent --> [Code],
                   % policy-inventory-exempt: mechanism-internal; reason=the two exponent-marker spellings are float lexeme syntax mirroring the shipped token pattern's [eE]; evidence=engine/parser.pl:metta_shipped_reader_token/2
                   { memberchk(Code, [0'e, 0'E]) },
                   metta_optional_number_sign,
                   metta_decimal_digits.

%String syntax is one lexeme even when it contains whitespace. Consuming the
%opening quote commits to this scanner, so an unterminated string cannot fall
%back to a word that merely happens to start with a quote.
reader_token_text(Text) -->
    [0'"], !, reader_quoted_token_tail(Cs),
    { string_codes(Text, [0'"|Cs]) }.
reader_token_text(Text) -->
    token(Cs),
    { string_codes(Text, Cs) }.

reader_quoted_token_tail([0'"]) --> [0'"], !.
reader_quoted_token_tail([0'\\, Esc|Cs]) --> [0'\\, Esc], !,
    reader_quoted_token_tail(Cs).
reader_quoted_token_tail([C|Cs]) --> [C], { C =\= 0'" },
    reader_quoted_token_tail(Cs).

%Custom rows are asserted newest first and searched before the shipped table.
%The compiled custom regex already carries its full-match options. Shipped
%rows avoid PCRE entirely for ordinary symbol starts, while still matching
%through their declared patterns for every candidate literal.
metta_reader_token_match(Text, Descriptor) :-
    metta_reader_token_resolution(Text, Descriptor, _).

%Diagnostic consumers can distinguish a custom class from shipped literal
%syntax without running the constructor a second time.
metta_reader_token_source(Text, Source) :-
    metta_reader_token_resolution(Text, _, Source).

metta_reader_token_resolution(Text, Descriptor, custom) :-
    metta_custom_reader_token(_, Descriptor, Regex),
    re_match(Regex, Text, []), !.
metta_reader_token_resolution(Text, Descriptor, shipped) :-
    metta_shipped_reader_token_candidate(Text, Descriptor), !.

metta_shipped_reader_token_candidate(Text, string) :-
    string_codes(Text, Codes),
    phrase(string_lit(_), Codes).
metta_shipped_reader_token_candidate(Text, number) :-
    string_codes(Text, Codes),
    phrase(metta_number_token_codes, Codes).

metta_reader_token_construct(number, Text, Number) :-
    string_codes(Text, Codes),
    phrase(number(Number), Codes).
metta_reader_token_construct(string, Text, String) :-
    string_codes(Text, Codes),
    phrase(string_lit(String), Codes).
metta_reader_token_construct(metta(Constructor), Text, [Constructor, Text]).
metta_reader_token_construct(host(Constructor), Text, Term) :-
    seam:host_reader_token_construct(Constructor, Text, Term).

metta_reader_default("True", true) :- !.
metta_reader_default("False", false) :- !.
metta_reader_default(Text, Atom) :- atom_string(Atom, Text).

%A token is a non-empty run of characters that end no token. The shape is
%string_without//2's own, a greedy scan committed per character, with the
%membership test replaced by the boundary table, so where a token ends is
%one definition rather than a literal repeated here.
token(Cs) --> token_codes(Cs), { Cs \= [] }.

token_codes([C|Cs]) --> [C], { \+ metta_token_boundary(C, _) }, !, token_codes(Cs).
token_codes([]) --> [].

%Whether a symbol's spelling reads back as that same symbol. Both readers
%above answer, so this cannot drift from either: a name that reads as a
%number, a variable, a string, a boolean, or as more than one token has no
%text form that carries it, and neither has one that opens a string for the
%form scanner, which would swallow the rest of the form.
%
%A character blacklist stood here in three places and missed three classes,
%each a silent change of meaning wherever an atom crossed as text. $x read
%back as a variable, a;b truncated at the comment it starts, 42 read as the
%number, and True read as the boolean [tested: parser_symbol_text].
%Reading the whole grammar back costs about three times a single token
%scan, and every save and every digest asks this of every symbol it
%carries, so the ordinary name answers without it while no custom class is
%installed: once a name is one token holding no quote, only a first character
%that could begin a number, a variable or a string, or a boolean's own
%spelling, can make it read back as something else [measured 2026-08-15: the grammar alone cost
%+18.9% inferences and +16.8% instructions on space-digest].
%Writability is a pure function of the name and a save asks it once per
%OCCURRENCE, 20,001 times for one symbol on the benchmark space, so the
%grammar run is tabled; the table is small (one entry per distinct name)
%and permanent, which a name registry already is.
:- table metta_symbol_writable/1.
metta_symbol_writable(Symbol) :-
    atom(Symbol),
    atom_codes(Symbol, Codes),
    Codes = [First|_],
    phrase(writable_token(Codes), Codes),
    (   metta_symbol_ordinary(First, Symbol)
    ->  true
    ;   catch(phrase(sexpr_token(Read, [], _), Codes),
              error(syntax_error(float_overflow), _),
              metta_saturating_parse(sexpr_token(Read, [], _), Codes)),
        Read == Symbol ).

%One token, and no quote either: the form scanner opens a string on a quote
%and would swallow the rest of the form, which sread/2 alone never sees. One
%scan answers both, since every symbol carried as text pays for it.
writable_token([C|Cs]) --> [C], { C =\= 0'", \+ metta_token_boundary(C, _) }, !,
                            writable_token(Cs).
writable_token([]) --> [].

metta_symbol_ordinary(First, Symbol) :-
    \+ metta_custom_reader_token(_, _, _),
    \+ metta_symbol_reserved_start(First),
    Symbol \== 'True',
    Symbol \== 'False'.

%$ opens a variable, . - + and a digit can open a number. A name starting
%with one of them is read in full before it is believed.
metta_symbol_reserved_start(0'$).
metta_symbol_reserved_start(0'.).
metta_symbol_reserved_start(0'-).
metta_symbol_reserved_start(0'+).
metta_symbol_reserved_start(Code) :- code_type(Code, digit).

%Whether a number's spelling reads back as that same number. The writer prints
%a finite number with number_codes/2, which is SWI's numeric syntax, and the
%reader accepts sexpr_token//3's, which is narrower: a non-finite float
%writes as inf, -inf or NaN (metta_float_codes/2, the arbiter's spellings)
%and a rational as 1r3, and each of the four comes back a SYMBOL of that
%spelling, upstream's included, its float token being a regex a bare name
%never matches. MeTTa has no literal for any of them, and inventing one
%would read a name upstream reads as a symbol, so the answer is the one a
%symbol holding whitespace already gets: the value has no text form and the
%seam refuses it rather than storing something that comes back different.
%
%The two ordinary cases answer without the grammar, the way an ordinary NAME
%does above, because every space digest and every save asks this of every
%number it carries. An integer prints as an optional minus and digits, which
%the number grammar reads back for every integer. A float prints in a decimal
%or exponent form the grammar reads back unless SWI spells it outside the
%grammar entirely, which happens for exactly the two float classes that have
%no digits in them, so float_class/2 answers in one call
%[source: SWI-Prolog 10.1 Reference Manual 4.27.2.3, float_class/2, whose
%classes are infinite, nan, zero, subnormal and normal]. A rational, the one
%remaining kind, is read back before it is believed.
%
%Both shortcuts are held to the grammar rather than trusted: the whole float
%range and every integer shape are checked against sexpr_token//3 itself
%[tested: parser_number_text], and generated numbers check the same agreement
%[tested: property_number_shortcut in tests/prolog/property_lane.pl], and one
%sweep put 200,000 random floats across the whole exponent range, 20,000
%rationals and 50,000 big integers through both [measured 2026-08-19: no
%disagreement]. The shortcuts are what make the check affordable: a
%20,000-atom space digest where every atom holds one integer and one float
%costs +1.89% with them and +36.8% without [measured 2026-08-19: 3,180,384
%inferences unchecked, 3,240,388 checked, 4,350,800 asking the grammar for
%every number, min of 3 each].
metta_number_writable(Number) :-
    (   metta_custom_reader_token(_, _, _)
    ->  metta_number_roundtrips_under_current_reader(Number)
    ;   integer(Number)
    ->  true
    ;   float(Number)
    ->  float_class(Number, Class),
        Class \== infinite,
        Class \== nan
    ;   number_codes(Number, Codes),
        phrase(sexpr_token(Read, [], _), Codes),
        Read == Number
    ).

metta_number_roundtrips_under_current_reader(Number) :-
    (   float(Number)
    ->  metta_float_codes(Number, Codes)
    ;   number_codes(Number, Codes)
    ),
    catch(phrase(sexpr_token(Read, [], _), Codes),
          error(syntax_error(float_overflow), _),
          metta_saturating_parse(sexpr_token(Read, [], _), Codes)),
    Read == Number.

metta_string_writable(String) :-
    (   \+ metta_custom_reader_token(_, _, _)
    ->  true
    ;   phrase(swrite_mode(String, display), Codes),
        phrase(sexpr_token(Read, [], _), Codes),
        Read == String
    ).

%The first value in a term that has no round-trip text spelling. A dedicated
%walk visits every proper-list element. Non-list compounds, improper lists and
%opaque host values are themselves unwritable because none is a MeTTa term. It
%replaced a sub_term/2 walk whose generic enumeration cost ~120 inferences per
%three-element atom across a save's whole-space scan and a load's add guard;
%the type-switched walk measures ~6x cheaper on the same 20,001-atom
%round-trip, byte-identical verdicts [measured 2026-08-19: the save-load A/B
%in the benchmarks lane, reverted-guard worktree against this one].
%
%The name says symbol because names were the only class known to fail when the
%text seam was declared. A number is the second, and it is the same failure
%with the same consequence at the same four call sites, so it is answered here
%rather than left for each of them to discover
%[source: engine/ext_points.pl, the swrite/sread service contract].
metta_unwritable_symbol(Term, Bad) :-
    metta_unwritable_walk(Term, Bad), !.

metta_unwritable_walk(Term, Bad) :-
    (   var(Term)
    ->  fail
    ;   Term == []
    ->  fail
    ;   string(Term)
    ->  \+ metta_string_writable(Term), Bad = Term
    ;   atom(Term)
    ->  \+ metta_symbol_writable(Term), Bad = Term
    ;   number(Term)
    ->  \+ metta_number_writable(Term), Bad = Term
    ;   Term = [Head|Tail]
    ->  (   metta_unwritable_walk(Head, Bad)
        ->  true
        ;   metta_unwritable_list_tail(Tail, Bad)
        )
    ;   Bad = Term
    ).

metta_unwritable_list_tail([], _) :- !, fail.
metta_unwritable_list_tail([Head|Tail], Bad) :- !,
    (   metta_unwritable_walk(Head, Bad)
    ->  true
    ;   metta_unwritable_list_tail(Tail, Bad)
    ).
metta_unwritable_list_tail(Bad, Bad).

metta_text_writable(Term) :-
    (   metta_unwritable_symbol(Term, Bad)
    ->  metta_refuse_text(Bad)
    ;   true
    ).

metta_refuse_text(Bad) :-
    throw(error(metta_unwritable_text(Bad),
                context(swrite/2,
                        'printed form would read back as a different value'))).

prolog:error_message(metta_unwritable_text(Bad)) -->
    [ 'cannot write ~p as MeTTa text because its printed form would read back as a different value'-[Bad] ].

%Just string literal handling from here-on:
string_lit(S) --> "\"", string_chars(Cs), "\"", { string_codes(S, Cs) }.
string_chars([]) --> [].
string_chars([C|Cs]) --> [C], { C =\= 0'", C =\= 0'\\ }, !, string_chars(Cs).
string_chars([C|Cs]) --> "\\", [X], { (X=0'n->C=10; X=0't->C=9; X=0'r->C=13; C=X) }, string_chars(Cs).
