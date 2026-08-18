% Purpose: plunit tests for the reader and writer in src/parser.pl. Until
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
:- initialization(consult('../../src/metta.pl')).

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

:- end_tests(parser_comments).


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
    swrite([holds, Symbol], Text),
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

:- begin_tests(parser_writes_what_is_not_metta).

%The writer's last three clauses are the three ways of not being a MeTTa term,
%and each one used to be able to take the whole run down or say nothing useful.

%=../2 refuses a zero-arity compound: it raises `compound_non_zero_arity'
%rather than failing, and the writer had an empty-argument branch it could
%never reach. The raise escaped the writer and killed the program, which is how
%`!(py-atom "()")` printed nothing at all and ended the run, janus encoding
%Python's empty tuple as exactly this term.
test(an_empty_compound_prints) :-
    Empty = -(),
    assertion(compound(Empty)),
    assertion(\+ catch(Empty =.. _, _, fail)),
    swrite(Empty, Text),
    assertion(string(Text)).

%And a non-empty one still writes as it did.
test(a_compound_prints_as_a_form) :-
    swrite(foo(a, 1), Text),
    assertion(Text == "(foo a 1)").

%A term that is neither a MeTTa term nor a compound writes as its own text
%rather than failing. The writer is never the thing that fails, so a value
%whose provider is not loaded still prints something.
test(a_value_with_no_provider_still_prints) :-
    swrite("a string", Text),
    assertion(Text == "\"a string\"").

:- end_tests(parser_writes_what_is_not_metta).

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
