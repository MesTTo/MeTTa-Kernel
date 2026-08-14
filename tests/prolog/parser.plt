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
%   To Do: cover sread's error paths once they raise rather than fail.
%   Hacks: None
%   Future Enhancements: None

% Load the engine through metta.pl, not main.pl. main.pl carries
% `:- initialization(main, main).`, which fires on consult and runs
% prolog_interop_example, printing into the test output; metta.pl is
% everything main.pl actually loads.
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
