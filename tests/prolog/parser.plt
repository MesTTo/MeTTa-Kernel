% Purpose: plunit tests for the reader and writer in engine/parser.pl. Until
%   these existed the Prolog side had no direct tests at all: every one of
%   the 3187 lines was exercised only through janus from Python or through
%   a whole MeTTa example, so a parser defect surfaced as a wrong example
%   output with nothing pointing at the parser.
%
%   The escape tests are the regression that matters. swrite must emit the
%   five escapes hyperon's Str Display emits (quote, backslash, newline,
%   tab, carriage return) so a written string literal stays on one line;
%   the MORK bridge splits dumps on newlines, and a raw newline inside a
%   string is what corrupted them.
%
%   Writer entry points accept only the inverse reader domain. Values that
%   would be renamed or structurally changed are refused before any text is
%   returned [tested: parser_refuses_non_metta; commit=53686aed41e7ff02de69052198afdb537536cbdb].
%
%   Run: swipl -g run_tests -t halt tests/prolog/parser.plt
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

% Load the engine through metta.pl, not main.pl. main.pl carries
% `:- initialization(main, main).`, which fires on consult and runs
% prolog_interop_example, printing into the test output; metta.pl is
% everything main.pl actually loads.
:- use_module(library(clpfd)).
:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(parser_roundtrip).

% A term written and read back is the term again. =@= is variant equality,
% so the renamed variables a reader introduces do not count as a difference.
% sread/2 unifies its second argument as it parses, so a partially bound
% term there raises `Type error: number expected` rather than failing
% cleanly. Always read into a fresh variable, then destructure.
roundtrip(Term) :-
    swrite(Term, String),
    sread(String, Back),
    Back =@= Term,
    !.

test(symbols)        :- roundtrip([foo, bar]).
test(nested)         :- roundtrip([=, [f, _X], _Y]).
test(numbers)        :- roundtrip([a, 1, 2.5, -3]).
test(empty)          :- roundtrip([]).
test(string_cell)    :- roundtrip([s, "hi"]).
test(deep, [forall(between(1, 6, Depth))]) :-
    nest(Depth, Term),
    roundtrip(Term).

nest(0, leaf) :- !.
nest(N, [node, Inner]) :- M is N - 1, nest(M, Inner).

%The language's booleans are spelled `True` and `False`. The reader maps both
%onto Prolog's own true/false so a compiled guard can call them directly, and
%the writer maps them back: without that half the round trip renamed the
%language's own constants, `!(== 1 2)` answering `false` where the arbiter
%answers `False` [source: LeaTTa tests/semantics/grounded/07-partial-core.metta
%and 04-boolean.metta, both STATUS conforms].
test(booleans_print_in_the_languages_own_spelling) :-
    swrite(true, T), swrite(false, F),
    swrite([pair, true, false], Pair),
    T == "True", F == "False", Pair == "(pair True False)".

test(booleans_round_trip) :- roundtrip([pair, true, false]).

test(shared_variable_stays_shared) :-
    sread("(= (f $x) $x)", Term),
    Term = [=, [f, A], B],
    A == B.

test(distinct_variables_stay_distinct) :-
    sread("(pair $x $y)", Term),
    Term = [pair, A, B],
    A \== B.

test(anonymous_never_shares) :-
    sread("(pair $_ $_)", Term),
    Term = [pair, A, B],
    A \== B.

:- end_tests(parser_roundtrip).

:- begin_tests(parser_stable_variables).

test(names_follow_first_occurrence) :-
    swrite([pair, X, Y, X], Written),
    Written == "(pair $_0 $_1 $_0)",
    X \== Y.

test(unrelated_allocations_do_not_change_names) :-
    length(FirstVars, 2),
    FirstVars = [A, B],
    swrite([pair, A, B, A], First),
    length(_, 10000),
    length(SecondVars, 2),
    SecondVars = [C, D],
    swrite([pair, C, D, C], Second),
    First == Second.

test(printing_does_not_bind_or_strip_source_constraints) :-
    X #> 0,
    fd_dom(X, DomainBefore),
    swrite([value, X], Written),
    fd_dom(X, DomainAfter),
    Written == "(value $_0)",
    DomainAfter == DomainBefore.

test(stable_names_roundtrip_with_sharing) :-
    swrite([pair, X, _Y, X], Written),
    sread(Written, Parsed),
    Parsed = [pair, A, B, C],
    A == C,
    A \== B.

test(writer_dcg_has_one_compilation) :-
    findall(Codes, phrase(seq([1, 2, 3]), Codes), Solutions),
    Solutions == [[0'1, 0' , 0'2, 0' , 0'3]].

:- end_tests(parser_stable_variables).

:- begin_tests(parser_named_variables).

:- dynamic stored_pattern/1.

test(reader_name_survives_to_the_writer) :-
    sread_with_names("(pair $left $right $left)", Term, Names),
    swrite_with_names(Term, Names, Written),
    Written == "(pair $left $right $left)".

test(distinct_same_named_variables_receive_first_occurrence_epochs) :-
    Term = [pair, First, Second, First, Second],
    Names = [x-First, x-Second],
    swrite_with_names(Term, Names, Written),
    Written == "(pair $x#0 $x#1 $x#0 $x#1)".

test(an_engine_variable_without_a_reader_name_keeps_the_fallback) :-
    Term = [pair, Source, _Fresh],
    swrite_with_names(Term, [source-Source], Written),
    Written == "(pair $source $_1)".

test(printing_named_variables_does_not_bind_or_strip_constraints) :-
    X #> 0,
    fd_dom(X, DomainBefore),
    swrite_with_names([value, X], [x-X], Written),
    fd_dom(X, DomainAfter),
    Written == "(value $x)",
    DomainAfter == DomainBefore.

test(answer_group_uses_each_collected_side_map) :-
    Answers = ['$petta_answer'([left, X], [x-X]),
               '$petta_answer'([right, Y], [y-Y])],
    swrite_answer_group(Answers, Written),
    Written == "((left $x) (right $y))".

test(assert_boundary_returns_a_fresh_nameless_variable,
     [ setup(retractall(stored_pattern(_))),
       cleanup(retractall(stored_pattern(_))) ]) :-
    sread_with_names("(stored $source)", Term, [source-_]),
    assertz(stored_pattern(Term)),
    stored_pattern(Stored),
    swrite_with_names(Stored, [], Written),
    Written == "(stored $_0)".

:- end_tests(parser_named_variables).

:- begin_tests(parser_comments).

test(inline_comment_ends_at_newline) :-
    sread("(a ; ignored tokens\n b)", Term),
    Term == [a, b].

test(comment_without_newline_cannot_supply_a_closing_parenthesis,
     [throws(error(syntax_error(_), _))]) :-
    sread("(a;b c)", _).

test(semicolons_inside_strings_remain_data) :-
    sread("(value \"a;b\")", Term),
    Term == [value, "a;b"].

test(comment_is_a_number_token_boundary) :-
    sread("(1; ignored ) and (!\n 2)", Term),
    Term == [1, 2].

%LeaTTa's tokenizer leaves comment state only for LF. Direct probes against
%the LeaTTa executable answer both quoted forms for LF and only the first for
%CR, NEL and U+2028 [source 2026-08-21: LeaTTa
%MettaHyperonFull/Runtime/Parser.lean:58, tokenizeAux comment branch at 66-67].
%The row originally expected a reader change based on Hyperon's CR behavior;
%the arbiter instead makes PeTTa's existing LF-only reader the conforming one.
test(test_a_comment_terminates_on_the_class_the_arbiter_rules) :-
    sread("(a ; comment\n b)", LfTerm),
    LfTerm == [a, b],
    forall(member(Code, [0x000D, 0x0085, 0x2028]),
           ( format(string(Source), "(a ; comment~cb)", [Code]),
             catch((sread(Source, _), Outcome = read),
                   error(syntax_error(_), _), Outcome = syntax_error),
             Outcome == syntax_error )).

:- end_tests(parser_comments).


:- begin_tests(parser_unicode_layout).

% Whitespace is the other half of layout, and the reader used to define it
% twice: metta_layout//0 skipped whatever SWI calls a space, while token//1
% ended at seven ASCII characters. Where the two disagreed a token swallowed
% the separator, so `(1<NBSP>2)` read as the single symbol `1<NBSP>2` and
% `(superpose (1<NBSP>2))` answered one atom instead of two, silently
% [measured 2026-08-19].
%
% The Unicode White_Space property, one member/2 pair per line of PropList's
% White_Space block. parser.pl's table lists the same 25 code by code, so
% this is a second reading of one file and a transcription slip there fails
% here [source: https://www.unicode.org/Public/UCD/latest/ucd/PropList.txt,
% PropList-17.0.0, "Total code points: 25"]. That property is the class
% because MeTTa's grammar ends a word at char::is_whitespace, which is the
% property exactly [source: hyperon-experimental v0.2.10-25-g0559a5e2,
% lib/src/metta/text.rs, parse_word].
white_space_property(Codes) :-
    findall(C,
            ( member(Lo-Hi, [0x0009-0x000D, 0x0020-0x0020, 0x0085-0x0085,
                             0x00A0-0x00A0, 0x1680-0x1680, 0x2000-0x200A,
                             0x2028-0x2029, 0x202F-0x202F, 0x205F-0x205F,
                             0x3000-0x3000]),
              between(Lo, Hi, C) ),
            Codes).

% A table of ground facts enumerates, so this closes over the whole range
% rather than sampling it.
test(the_layout_class_is_the_unicode_white_space_property) :-
    findall(C, metta_token_boundary(C, layout), Found),
    msort(Found, Sorted),
    white_space_property(Expected),
    Sorted == Expected.

% And SWI's own class stays a cross-check on the table rather than its
% source. code_type/2 answers for 21 of the 25: it follows the C library,
% where a space is a character a line may break at, so it omits the three
% NO-BREAK spaces and NEL. Containment is the part that must hold, and it
% fails the moment either side moves [measured 2026-08-19: 21 codes].
test(swi_calls_nothing_a_space_that_the_table_does_not) :-
    forall(code_type(C, space), metta_token_boundary(C, layout)).

% Nothing but the three punctuation marks ends a token without being layout,
% so a token boundary is the property plus a closed, named set.
test(the_only_other_token_boundaries_are_punctuation) :-
    findall(C, metta_token_boundary(C, punctuation), Found),
    msort(Found, Sorted),
    Sorted == [0'(, 0'), 0';].

between_atoms(Code, Text) :-
    atom_codes(Text, [0'(, 0'1, Code, 0'2, 0')]).

test(every_layout_character_separates_two_atoms,
     [forall(metta_token_boundary(Code, layout))]) :-
    between_atoms(Code, Text),
    sread(Text, Term),
    Term == [1, 2].

test(a_run_of_layout_separates_two_atoms,
     [forall(metta_token_boundary(Code, layout))]) :-
    atom_codes(Text, [0'(, 0'a, Code, 0' , Code, 0'b, 0')]),
    sread(Text, Term),
    Term == [a, b].

% The skipper outside a form reads the same class as the scanner inside one.
test(layout_around_a_form_is_skipped, [forall(metta_token_boundary(Code, layout))]) :-
    atom_codes(Text, [Code, 0'(, 0'a, 0' , 0'b, 0'), Code]),
    sread(Text, Term),
    Term == [a, b].

% Closed in the other direction too, so the fix cannot be a blanket
% widening. The first four are str.isspace() in Python, which adds the ASCII
% record separators to the property; U+180E was White_Space until Unicode
% 6.3.0 and is a format character now; the last two have zero width.
test(a_character_outside_the_class_stays_inside_a_token,
     [forall(member(Code, [0x001C, 0x001D, 0x001E, 0x001F,
                           0x180E, 0x200B, 0xFEFF]))]) :-
    atom_codes(Text, [0'(, 0'a, Code, 0'b, 0')]),
    atom_codes(Joined, [0'a, Code, 0'b]),
    sread(Text, Term),
    Term == [Joined].

% Layout inside a string literal is data: the literal ends at its closing
% quote and nowhere else, so widening what separates atoms must not reach
% inside one.
test(layout_inside_a_string_literal_is_data,
     [forall(metta_token_boundary(Code, layout))]) :-
    atom_codes(Text, [0'(, 0's, 0' , 0'", 0'a, Code, 0'b, 0'", 0')]),
    atom_codes(Body, [0'a, Code, 0'b]),
    sread(Text, Term),
    Term = [s, Read],
    atom_string(Body, Read).

% The console reads the same class, so a line holding only layout re-prompts.
% It did not, and the two definitions gave the two answers: a line holding
% one IDEOGRAPHIC SPACE answered incomplete, while the same line holding one
% NO-BREAK SPACE answered complete(C) with C that very character, so the
% console evaluated a symbol the user never typed [measured 2026-08-19,
% sread_command/2 at 3de90e9].
test(a_line_holding_only_layout_is_incomplete,
     [forall(metta_token_boundary(Code, layout))]) :-
    atom_codes(Text, [Code]),
    sread_command(Text, Result),
    Result == incomplete.

% And the round trip stays honest. A symbol holding layout no longer has a
% text spelling that reads back as itself, so swrite/2 and sread/2 remain
% inverse and the text seam refuses it rather than corrupting a dump.
test(a_symbol_holding_layout_has_no_text_form,
     [forall(metta_token_boundary(Code, layout))]) :-
    atom_codes(Symbol, [0'a, Code, 0'b]),
    \+ metta_symbol_writable(Symbol).

:- end_tests(parser_unicode_layout).


:- begin_tests(parser_escapes).

% sread/2 unifies its second argument as it parses, so a partially bound
% term there produces a confusing type error rather than a clean failure.
% Always read into a fresh variable, then destructure.
read_cell(Written, Back) :-
    sread(Written, Term),
    Term = [s, Back].

% Each of the five escapes survives the round trip as one character.
test(escape_roundtrip, [forall(member(Char, ['"', '\\', '\n', '\t', '\r']))]) :-
    atom_string(Char, S),
    string_concat("a", S, Prefixed),
    string_concat(Prefixed, "b", Payload),
    swrite([s, Payload], Written),
    read_cell(Written, Back),
    Back == Payload,
    !.

% The written form is one line whatever the string holds. This is the
% property the MORK bridge depends on.
test(written_form_has_no_raw_newline) :-
    swrite([s, "line one\nline two"], Written),
    \+ sub_string(Written, _, _, _, "\n"),
    !.

test(written_form_has_no_raw_tab) :-
    swrite([s, "a\tb"], Written),
    \+ sub_string(Written, _, _, _, "\t"),
    !.

test(quote_is_escaped_not_bare) :-
    swrite([s, "say \"hi\""], Written),
    sub_string(Written, _, _, _, "\\\""),
    read_cell(Written, Back),
    Back == "say \"hi\"",
    !.

:- end_tests(parser_escapes).


% Which symbol spellings survive a MeTTa text round trip. The rule is
% derived from the grammar rather than from a character blacklist, so this
% suite checks it against what sread/2 actually answers rather than against
% a table someone wrote down.

:- begin_tests(parser_symbol_text).

symbol_spelling(plain).          symbol_spelling('a-b').
symbol_spelling('$notvar').      symbol_spelling('$').
symbol_spelling('semi;colon').   symbol_spelling(';leading').
symbol_spelling('42').           symbol_spelling('-3').
symbol_spelling('1.5').          symbol_spelling('1e5').
symbol_spelling('1.0e10').       symbol_spelling('+5').
symbol_spelling('-0').           symbol_spelling('0x1f').
symbol_spelling('0b101').        symbol_spelling('1_000').
symbol_spelling('.5').           symbol_spelling('5.').
symbol_spelling('1e').           symbol_spelling('3x').
symbol_spelling('1-2').          symbol_spelling('-abc').
symbol_spelling('with space').   symbol_spelling('paren(here').
symbol_spelling('"lead').        symbol_spelling('trail"').
symbol_spelling('').             symbol_spelling('True').
symbol_spelling('False').        symbol_spelling(true).
symbol_spelling(-).              symbol_spelling(+).
symbol_spelling(<=).             symbol_spelling('#+').
symbol_spelling(nil).            symbol_spelling('tab\there').

%What the text form actually answers for a symbol standing inside a term,
%read the way a saved file is read: as a whole form off the top-level
%scanner, then parsed. sread/2 alone is not that test, because the scanner
%tracks a string state sread/2 never sees, and a quote inside a symbol
%swallowed the rest of the form there while sread/2 read it back intact.
reads_back_the_same(Symbol) :-
    catch(swrite([holds, Symbol], Text),
          error(metta_unwritable_text(_), _),
          fail),
    catch(parse_metta_source(Text, Forms), _, fail),
    Forms = [parsed(_, _, Back)],
    Back == [holds, Symbol].

test(writable_says_exactly_what_reads_back,
     [forall(symbol_spelling(Symbol))]) :-
    ( metta_symbol_writable(Symbol)
      -> reads_back_the_same(Symbol)
    ;  \+ reads_back_the_same(Symbol) ).

test(a_term_reports_its_first_unwritable_symbol) :-
    metta_unwritable_symbol([holds, plain, '$notvar', '42'], Bad),
    Bad == '$notvar'.

test(a_writable_term_reports_nothing) :-
    \+ metta_unwritable_symbol([holds, plain, 'a-b', <=], _).

:- end_tests(parser_symbol_text).


% Which NUMBERS survive the round trip, the same question parser_symbol_text
% asks of names and for the same reason: swrite/2 prints with number_codes/2,
% which is SWI's whole numeric syntax, while sexpr_token//3 accepts the MeTTa
% grammar's, which is narrower. SWI writes a non-finite float as 1.0Inf,
% -1.0Inf or 1.5NaN and a rational as 1r3, and each of the four comes back a
% SYMBOL of that spelling.
%
% Found by tests/prolog/property_lane.pl's roundtrip law, which shrank its
% counter-example to a bare 1.0Inf. MeTTa arithmetic cannot make one here,
% float_overflow, float_zero_div and float_undefined all being `error` and
% prefer_rationals being false, but `(py-atom "float('inf')")` answers 1.0Inf,
% so the class is reachable, and metta_unwritable_symbol/2 passed it: the text
% seam's own service exists to "refuse rather than store an atom that will come
% back different" [source: engine/ext_points.pl] and it answered only for names.

:- begin_tests(parser_number_text).

test(a_value_with_no_text_form_is_refused_by_the_writer,
     [forall(member(Expression, [inf, -inf, nan, 1 rdiv 3])),
      throws(error(metta_unwritable_text(_), _))]) :-
    Number is Expression,
    swrite(Number, _).

test(the_seam_reports_a_value_with_no_text_form,
     [forall(member(Expression, [inf, -inf, nan, 1 rdiv 3]))]) :-
    Number is Expression,
    metta_unwritable_symbol([holds, Number], Bad),
    Bad == Number.

% And closed in the other direction, so the refusal cannot be a blanket one.
% -0.0 is in the list because it is a different float from 0.0 in the standard
% order, so a round trip that lost the sign would pass an == check against 0.0.
test(every_number_that_does_survive_is_accepted,
     [forall(member(Number, [0, 42, -3, 2.5, -0.0, 1.0e10, 1.5e-10,
                             5.0e-324, 3.141592653589793,
                             123456789012345678901234567890]))]) :-
    \+ metta_unwritable_symbol([holds, Number], _),
    swrite([holds, Number], Text),
    sread(Text, Back),
    Back == [holds, Number].

% A finite float prints the arbiter's layout over SWI's shortest digits
% [source 2026-08-20: LeaTTa RyuLean4/Runtime.lean:371-396, Decimal.formatMeTTa].
% The pins are the law's own table rows, the four measured witnesses that
% diverged under number_codes/2's layout (1.0e+16, 1.0e-05, 1.5e+300, 1.0e+26),
% and the boundary at every branch: kk 16 stays positional and 17 goes
% scientific, kk -4 stays positional and -5 goes scientific, the exponent
% carries a minus sign and never a plus or a pad, and zero keeps its sign.
test(arbiter_float_layout,
     [forall(member(Float-Want,
                    [1.0e16-"1e16", 0.00001-"0.00001", 1.5e300-"1.5e300",
                     1.0e26-"1e26", 5.0-"5.0", 1230.0-"1230.0", 3.8-"3.8",
                     0.30000000000000004-"0.30000000000000004",
                     0.0-"0.0", -0.0-"-0.0",
                     1.0e15-"1000000000000000.0",
                     1234567890123456.0-"1234567890123456.0",
                     0.0001-"0.0001", 0.000001-"1e-6", 1.5e-7-"1.5e-7",
                     5.0e-324-"5e-324", -5.0e-324-"-5e-324",
                     2.2250738585072014e-308-"2.2250738585072014e-308",
                     1.7976931348623157e308-"1.7976931348623157e308",
                     -1.0e16-"-1e16", -3.8-"-3.8",
                     0.015151515151515152-"0.015151515151515152"]))]) :-
    swrite(Float, Text),
    Text == Want,
    sread(Text, Back),
    Back == Float.

% The two shortcuts inside metta_number_writable/1 are not a second rule about
% spelling: each has to agree with the grammar wherever it is asked, the way
% metta_symbol_ordinary/2 has to agree with sexpr_token//3. The float list is
% the range's edges, the two smallest denormals, the largest finite float and
% the smallest normal one among them, because the exponent is where a spelling
% changes shape.
shortcut_agrees_with_grammar(Number) :-
    ( metta_number_writable(Number) -> Shortcut = true ; Shortcut = false ),
    (   catch(( number_codes(Number, Codes),
                phrase(sexpr_token(Read, [], _), Codes),
                Read == Number ), _, fail)
    ->  Grammar = true
    ;   Grammar = false ),
    Shortcut == Grammar.

test(the_integer_shortcut_agrees_with_the_grammar,
     [forall(member(Number, [0, 1, -1, 7, -7, 1000000, -1000000,
                             123456789012345678901234567890]))]) :-
    shortcut_agrees_with_grammar(Number).

test(the_float_shortcut_agrees_with_the_grammar,
     [forall(member(Expression, [0.0, -0.0, 1.0, -1.0, 5.0e-324, -5.0e-324,
                                 2.2250738585072014e-308, 1.0e-310,
                                 1.7976931348623157e308, -1.7976931348623157e308,
                                 3.141592653589793, 1.0e100, 1.0e-100,
                                 inf, -inf, nan]))]) :-
    Number is Expression,
    shortcut_agrees_with_grammar(Number).

test(a_rational_goes_through_the_grammar) :-
    Number is 1 rdiv 3,
    \+ integer(Number),
    \+ float(Number),
    shortcut_agrees_with_grammar(Number).

:- end_tests(parser_number_text).


% A numeric literal past binary64. dcg/basics' number//1 converts what it
% scanned with number_codes/2, which RAISES rather than answering, so
% `(holds 1e400)` neither parsed nor reported a parse error: the raise went
% out through sread/2 and killed the whole run with `number_codes/2: Syntax
% error: float_overflow` naming engine/main.pl [measured 2026-08-19, found by
% the generated-spelling law in tests/prolog/property_lane.pl].
%
% Upstream saturates, its float token being a regex handed to Rust's f64
% FromStr [source: hyperon-experimental, lib/src/metta/runner/stdlib/
% arithmetics.rs and hyperon-atom/src/gnd/number.rs; measured 2026-08-19 by
% running "1e400".parse::<f64>(), which answers Ok(inf)], so the reader does
% too, through SWI's own float_overflow flag set for the retry alone.

:- begin_tests(parser_number_overflow).

test(an_overflowing_literal_reads_as_an_infinity,
     [forall(member(Text-Expression, ["1e400"-inf, "1e309"-inf,
                                      "9e999999"-inf, "1.5e400"-inf,
                                      "-1e400"- (-inf)]))]) :-
    sread(Text, Number),
    Wanted is Expression,
    Number == Wanted.

% Underflow needed no change: both sides already answer zero.
test(an_underflowing_literal_reads_as_zero) :-
    sread("1e-400", Number),
    Number == 0.0.

% And the saturation does not widen what counts as a number: a token that only
% STARTS like an overflowing literal still ends where a token ends, so
% number_ends//0 refuses it and it reads as the symbol it is.
test(a_token_that_only_starts_like_an_overflow_is_a_symbol) :-
    sread("1e400abc", Term),
    Term == '1e400abc'.

test(a_form_holding_an_overflowing_literal_parses) :-
    sread("(holds 1e400)", Term),
    Infinity is inf,
    Term = [holds, Number],
    Number == Infinity.

% metta_symbol_writable/1 runs the same grammar, so it raised where it should
% have answered, and every caller of the text seam raised with it.
test(the_writability_check_answers_instead_of_raising,
     [forall(member(Spelling, ['1e400', '9e999999',
                               '1e99999999999999999999']))]) :-
    \+ metta_symbol_writable(Spelling).

% The flag is borrowed for the retry and given back.
test(the_overflow_flag_is_restored_after_a_saturating_parse) :-
    current_prolog_flag(float_overflow, Before),
    sread("1e400", _),
    current_prolog_flag(float_overflow, After),
    After == Before.

% The engine's OPERATIONS saturate the same way the reader does, so the two
% halves of the numeric boundary agree; raw is/2 keeps the flag's error mode,
% which pins that the saturation lives in the operations' recovery rather
% than in a global flag flip.
test(engine_operations_saturate_where_raw_is_still_raises,
     [throws(error(evaluation_error(float_overflow), _))]) :-
    Infinity is inf,
    '+'(1.0e308, 1.0e308, Sum), Sum == Infinity,
    '*'(1.0e308, 10.0, Product), Product == Infinity,
    'pow-math'(10.0, 400, Power), Power == Infinity,
    'exp-math'(1000, Grown), Grown == Infinity,
    NegativeInfinity is -inf,
    '-'(-1.0e308, 1.0e308, Dropped), Dropped == NegativeInfinity,
    'log-math'(10, 0.0, Logged), Logged == NegativeInfinity,
    Big is 10^400,
    '/'(Big, 3, Converted), Converted == Infinity,
    _ is 1.0e308 * 10.

% A compound expression can fault twice: base 1 overflows in log(0.0) and
% then divides the saturated -inf by log(1) = 0.0. The retry runs under all
% the IEEE flags at once, so the answer is the arbiter's -inf rather than a
% second error.
test(a_twice_faulting_compound_saturates_all_the_way) :-
    NegativeInfinity is -inf,
    'log-math'(1, 0.0, Out),
    Out == NegativeInfinity.

% Integer division by zero is OUTSIDE the retry: the arbiter's answer there
%is the DivisionByZero Error atom, the contained shape the operation recovery
%now returns while the literal and float paths remain unchanged.
test(integer_division_by_zero_answers_its_error_atom) :-
    '/'(1, 0, Answer),
    Answer == ['Error', ['/', 1, 0], 'DivisionByZero'].

% An infinity the reader legally produced carries THROUGH arithmetic: SWI's
% error mode rejects any non-finite result, operands included, so before the
% recovery (+ inf 1) raised even though nothing overflowed.
test(a_read_infinity_survives_further_arithmetic) :-
    sread("1e400", Read),
    '+'(Read, 1, Sum),
    Sum == Read.

:- end_tests(parser_number_overflow).

% The printed spellings are the arbiter's: hyperon prints Rust f64 Display
% forms and the arbiter's pretty-printer pins infinity by sign and an
% unsigned NaN. The spelling reads back as a SYMBOL of that name on both
% sides, which is why the writability refusal below stays.
:- begin_tests(parser_nonfinite_print).

test(the_numeric_formatter_spells_inf_minus_inf_and_nan,
     [forall(member(Value-Text, [inf-"inf", (-inf)-"-inf", nan-"NaN"]))]) :-
    Float is Value,
    metta_float_codes(Float, Codes),
    string_codes(Printed, Codes),
    Printed == Text.

test(a_nonfinite_is_refused_before_it_can_read_back_as_a_symbol,
     [forall(member(Value, [inf, -inf, nan])),
      throws(error(metta_unwritable_text(_), _))]) :-
    Float is Value,
    swrite(Float, _).

test(finite_floats_keep_the_grammar_spelling,
     [forall(member(Float, [0.0, -0.0, 2.5, 1.0e10, 1.5e-10]))]) :-
    swrite(Float, Printed),
    sread(Printed, Read),
    Read == Float.

:- end_tests(parser_nonfinite_print).


:- begin_tests(parser_commands).

% CPython names this as THE hard part of a console: "determine when the user
% has entered an incomplete command that can be completed by entering more
% text (as opposed to a complete command or a syntax error)". sread/2 answers
% one way and four different situations collapsed into it.
test(parser_command_tells_incomplete_from_malformed) :-
    assertion(sread_command("(f a)", complete([f, a]))),
    % Still typing.
    assertion(sread_command("(f a", incomplete)),
    assertion(sread_command("(a (b (c", incomplete)),
    assertion(sread_command("(= (f $x)", incomplete)),
    % An empty line re-prompts; it is the commonest input in any console.
    assertion(sread_command("", incomplete)),
    assertion(sread_command("   ", incomplete)),
    assertion(sread_command("; only a comment", incomplete)),
    % A bare atom is a whole form.
    assertion(sread_command("hello", complete(hello))),
    % One bracket too many is MALFORMED: no further typing repairs it, so the
    % reader's own error is the answer.
    catch(sread_command("(f a))", _), Malformed, true),
    assertion(Malformed = error(syntax_error(_), _)).

% Not "just count parens", which is why this is worth exposing rather than
% leaving every console to re-implement it: a bracket inside a string or a
% comment must not count, and string_state/3 is what knows the difference.
test(parser_command_ignores_brackets_inside_strings_and_comments) :-
    assertion(sread_command("(f \"a)b\")", complete([f, "a)b"]))),
    % An unterminated string is incomplete, because a MeTTa string may span
    % lines: a newline inside one keeps the string state.
    assertion(sread_command("(f \"a", incomplete)),
    assertion(sread_command("(f a) ; )))", complete([f, a]))).

% The consequence the finding is really about: examples/basics/repl.metta
% could not accept a multi-line form at all, because 'readln!'/1 is one
% read_line_to_string then sread/2. 'read-form!'/1 buffers until the brackets
% balance, and the DECISION it buffers on has no I/O in it, which is CPython's
% split between InteractiveInterpreter and InteractiveConsole.
test(parser_reads_a_form_across_lines) :-
    Source = "(= (f $x)\n   (+ $x 1))\n\n(f 41)\n",
    with_console_input(Source, Forms),
    Forms = [Spanning, Next, End],
    assertion(Spanning = [=, [f, X], [+, X, 1]]),
    % A blank line between forms re-prompts rather than erroring.
    assertion(Next == [f, 41]),
    assertion(End == end_of_file).

%'read-form!'/1 reads the user_input ALIAS, the way a console does and the way
%'readln!'/1 already does, so redirecting current_input is not enough: the
%alias itself is rebound and put back.
with_console_input(Source, Forms) :-
    stream_property(Original, alias(user_input)),
    open_string(Source, In),
    setup_call_cleanup(
        set_stream(In, alias(user_input)),
        findall(Form, ( between(1, 3, _), 'read-form!'(Form) ), Forms),
        ( set_stream(Original, alias(user_input)), close(In) )).

:- end_tests(parser_commands).

:- begin_tests(parser_refuses_non_metta).

%A refusal at the writer is the only injective answer for a host value with no
%MeTTa spelling. Returning display text would silently turn it into a
%different term at the next reader.

%=../2 refuses a zero-arity compound: it raises `compound_non_zero_arity'
%rather than failing, and the writer had an empty-argument branch it could
%never reach. The raise escaped the writer and killed the program, which is how
%`!(py-atom "()")` printed nothing at all and ended the run, janus encoding
%Python's empty tuple as exactly this term.
test(an_empty_compound_is_refused,
     [throws(error(metta_unwritable_text(_), _))]) :-
    Empty = -(),
    assertion(compound(Empty)),
    assertion(\+ catch(Empty =.. _, _, fail)),
    swrite(Empty, _).

%A Janus tuple used to become Python syntax: `(1, 2)`, which the reader sees
%as the symbol `1,` beside the number 2.
test(a_janus_tuple_is_refused,
     [throws(error(metta_unwritable_text(_), _))]) :-
    swrite(1-2, _).

test(a_non_list_compound_is_refused,
     [throws(error(metta_unwritable_text(_), _))]) :-
    swrite(foo(a, 1), _).

test(an_improper_list_is_refused,
     [throws(error(metta_unwritable_text(_), _))]) :-
    swrite([a|b], _).

%A MeTTa string remains inside the inverse domain.
test(a_metta_string_still_prints) :-
    swrite("a string", Text),
    assertion(Text == "\"a string\"").

:- end_tests(parser_refuses_non_metta).

:- begin_tests(parser_display).

%Display is intentionally not a serialization claim. It is the presentation
%path for repr and consoles, so ordinary Prolog compounds keep a readable
%shape even though the strict writer refuses them.
test(a_compound_keeps_a_presentation_shape) :-
    sdisplay(foo(a, 1), Text),
    assertion(Text == "(foo a 1)").

test(a_zero_arity_compound_keeps_a_presentation_shape) :-
    Empty = -(),
    sdisplay(Empty, Text),
    assertion(Text == "()").

test(an_unsafe_symbol_can_be_shown_but_not_serialized) :-
    sdisplay('has space', Text),
    assertion(Text == "has space"),
    assertion(\+ catch(swrite('has space', _),
                         error(metta_unwritable_text(_), _),
                         fail)).

:- end_tests(parser_display).

:- begin_tests(parser_pretty_printing).

% A width-aware layout for deep terms, MeTTaLog's metta_printer answer at
% the scale this engine needs: one line while a term fits, and a break
% after the head with two-space children when it does not.

test(a_fitting_term_stays_on_one_line) :-
    sread("(f 1 2)", T),
    swrite_pretty(T, S),
    S == "(f 1 2)".

test(a_deep_term_breaks_after_its_head) :-
    sread("(alpha (beta (gamma delta epsilon) (zeta eta theta)) \c
          (iota (kappa lambda mu) (nu xi omicron)) \c
          (pi (rho sigma tau) (upsilon phi chi)))", T),
    swrite_pretty(T, S),
    split_string(S, "\n", "", Lines),
    length(Lines, 4),
    Lines = [First|Rest],
    First == "(alpha",
    forall(member(L, Rest), sub_string(L, 0, 2, _, "  ")).

test(the_width_is_the_caller_s) :-
    sread("(f (g 1) (h 2))", T),
    swrite_pretty(T, 78, Wide),
    swrite_pretty(T, 8, Narrow),
    Wide == "(f (g 1) (h 2))",
    split_string(Narrow, "\n", "", NarrowLines),
    length(NarrowLines, 3).

test(a_pretty_atom_is_the_same_layout_from_metta) :-
    sread("(f (g 1) (h 2))", T),
    swrite_pretty(T, Direct),
    'pretty-atom'(T, ViaBuiltin),
    Direct == ViaBuiltin.

:- end_tests(parser_pretty_printing).
