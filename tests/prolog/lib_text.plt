% Purpose: the text and file libraries, tested at the predicate level so a
%   defect points at the operation rather than at a whole MeTTa example.
%
%   Load into user BEFORE begin_tests: begin_tests/1 switches to the plunit
%   module, and loading the engine after it puts every builtin there instead.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).
:- initialization(consult('../../lib/lib_string.pl')).
:- initialization(consult('../../lib/lib_file.pl')).
:- initialization(consult('../../lib/lib_json.pl')).

:- begin_tests(lib_string).

% ------------------------------------------------------------------ basics

test(length_counts_characters) :-
    'string-length'("hello", N), N == 5.

test(length_accepts_a_symbol) :-
    'string-length'(hello, N), N == 5.

test(length_accepts_a_number) :-
    'string-length'(42, N), N == 2.

test(a_compound_is_a_loud_type_error) :-
    catch('string-length'([a, b], _), error(_, _), true).

% Half-open and clamping, so an over-long end is the rest of the string rather
% than an error, which is what every language with slicing does.
test(slice_is_half_open) :-
    'string-slice'("hello world", 0, 5, S), S == "hello".

test(slice_clamps_a_long_end) :-
    'string-slice'("hello", 3, 999, S), S == "lo".

test(slice_beyond_the_end_is_empty) :-
    'string-slice'("hello", 99, 120, S), S == "".

test(slice_with_a_reversed_range_is_empty) :-
    'string-slice'("hello", 4, 2, S), S == "".

% ------------------------------------------------------- splitting, joining

test(split_and_join_round_trip) :-
    'string-split'(",", "a,b,c", Parts),
    Parts == ["a", "b", "c"],
    'string-join'(",", Parts, Back),
    Back == "a,b,c".

test(join_of_one_part_has_no_separator) :-
    'string-join'(", ", ["only"], S), S == "only".

test(join_of_nothing_is_empty) :-
    'string-join'(", ", [], S), S == "".

test(trim_removes_both_ends) :-
    'string-trim'("  padded\t\n", S), S == "padded".

test(case_changes_are_inverses_on_ascii) :-
    'string-upper'("shout", Up), Up == "SHOUT",
    'string-lower'("QUIET", Down), Down == "quiet".

% ------------------------------------------------------------------- tests

test(prefix_and_suffix_answer_booleans) :-
    'string-starts-with'("hello", "he", A), A == true,
    'string-starts-with'("hello", "lo", B), B == false,
    'string-ends-with'("hello", "lo", C), C == true,
    'string-contains'("hello", "ell", D), D == true,
    'string-contains'("hello", "zzz", E), E == false.

test(every_string_starts_with_the_empty_string) :-
    'string-starts-with'("hello", "", A), A == true.

% -1 rather than failing: a caller asking where something is wants an answer
% either way.
test(index_of_answers_the_first_position) :-
    'string-index-of'("hello", "l", N), N == 2.

test(index_of_answers_minus_one_when_absent) :-
    'string-index-of'("hello", "z", N), N == -1.

test(replace_changes_every_occurrence) :-
    'string-replace'("banana", "a", "X", S), S == "bXnXnX".

test(replace_of_the_empty_string_is_the_original) :-
    'string-replace'("banana", "", "X", S), S == "banana".

test(replace_can_lengthen) :-
    'string-replace'("ab", "b", "bbb", S), S == "abbb".

% ------------------------------------------------------------------- chars

% One-character STRINGS rather than char symbols, so the pieces are the same
% kind of thing as the whole and feed back into these operations.
test(chars_are_strings_and_round_trip) :-
    'string-chars'("abc", Chars),
    Chars == ["a", "b", "c"],
    forall(member(C, Chars), string(C)),
    'string-from-chars'(Chars, Back),
    Back == "abc".

test(repeat_and_pad) :-
    'string-repeat'("ab", 3, R), R == "ababab",
    'string-repeat'("ab", 0, Z), Z == "",
    'string-pad-left'("7", 3, "0", L), L == "007",
    'string-pad-right'("7", 3, ".", P), P == "7..".

test(padding_shorter_than_the_string_leaves_it_alone) :-
    'string-pad-left'("hello", 2, "0", S), S == "hello".

% ----------------------------------------------------------- HE's spellings

test(format_args_matches_hyperons_own_example) :-
    'format-args'("Probability of {} is {}%", [head, 50], S),
    S == "Probability of head is 50%".

% A short argument list produces NOTHING for the placeholders it cannot fill,
% and a long one is ignored: both are the dyn_fmt formatter upstream uses
% [source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, formatArg's empty-args
% case; measured 2026-08-19 against the arbiter, which answers "only and "].
test(format_args_empties_the_placeholders_it_cannot_fill) :-
    'format-args'("{} and {}", [only], S), S == "only and ".

test(format_args_ignores_extra_arguments) :-
    'format-args'("{}", [a, b, c], S), S == "a".

test(sort_strings_is_alphabetical_and_keeps_duplicates) :-
    'sort-strings'(["pear", "apple", "fig", "apple"], Sorted),
    Sorted == ["apple", "apple", "fig", "pear"].

test(parse_number_answers_nothing_for_non_numbers) :-
    'parse-number'("42", N), N == 42,
    \+ 'parse-number'("nope", _).

test(number_to_string_inverts_parse_number) :-
    'number-to-string'(42, S), S == "42",
    'parse-number'(S, N), N == 42.

% The file's own Guarantee is that EVERY operation answers a String and never
% an atom, so results compose with each other without a conversion in between.
% It was stated and not checked: one test covered chars and nothing covered
% the rest, so an operation answering an atom would have composed wrongly
% wherever its result was fed to another.
string_returning_operation('string-length', ["abc"]).
string_returning_operation('string-slice', ["abcdef", 1, 3]).
string_returning_operation('string-join', [", ", ["a", "b"]]).
string_returning_operation('string-trim', ["  a  "]).
string_returning_operation('string-upper', ["abc"]).
string_returning_operation('string-lower', ["ABC"]).
string_returning_operation('string-replace', ["aXa", "X", "Y"]).
string_returning_operation('string-repeat', ["ab", 3]).
string_returning_operation('number-to-string', [42]).

test(every_operation_that_answers_text_answers_a_String,
     [forall(string_returning_operation(Name, Args))]) :-
    append(Args, [Out], Full),
    Goal =.. [Name|Full],
    call(Goal),
    % A number-answering operation is exempt; what must never happen is an
    % ATOM, which prints like a string and composes like a symbol.
    assertion(\+ atom(Out)).

:- end_tests(lib_string).

:- begin_tests(lib_file,
               [ setup(tmp_test_dir(_)),
                 cleanup(true) ]).

tmp_test_dir(Dir) :-
    tmp_file_stream(text, File, Stream), close(Stream), delete_file(File),
    file_directory_name(File, Dir).

test_path(Name, Path) :-
    tmp_test_dir(Dir),
    atomic_list_concat([Dir, '/', Name], Path).

test(write_then_read_round_trips) :-
    test_path('petta_text_a.txt', Path),
    'write-file!'(Path, "one\ntwo\n", true),
    'read-file!'(Path, Content),
    Content == "one\ntwo\n",
    'delete-file!'(Path, true).

test(file_lines_drops_the_trailing_empty_line) :-
    test_path('petta_text_b.txt', Path),
    'write-file!'(Path, "one\ntwo\nthree\n", true),
    'file-lines!'(Path, Lines),
    Lines == ["one", "two", "three"],
    'delete-file!'(Path, true).

test(append_adds_without_truncating) :-
    test_path('petta_text_c.txt', Path),
    'write-file!'(Path, "one\n", true),
    'append-file!'(Path, "two\n", true),
    'file-lines!'(Path, Lines),
    Lines == ["one", "two"],
    'delete-file!'(Path, true).

% A missing file is an ERROR rather than a failure, so it can never be
% mistaken for an empty file.
test(reading_a_missing_file_raises) :-
    catch('read-file!'("/nonexistent/petta/should-not-exist", _),
          error(existence_error(source_sink, _), _), true).

test(the_handle_surface_reads_and_seeks) :-
    test_path('petta_text_d.txt', Path),
    'write-file!'(Path, "abcdefgh", true),
    'file-open!'(Path, "r", Handle),
    'file-get-size!'(Handle, Size), Size == 8,
    'file-read-exact!'(Handle, 3, Head), Head == "abc",
    'file-seek!'(Handle, 0, true),
    'file-read-to-string!'(Handle, Whole), Whole == "abcdefgh",
    'file-close!'(Handle, true),
    'delete-file!'(Path, true).

test(open_for_write_creates_the_file) :-
    test_path('petta_text_e.txt', Path),
    'delete-file!'(Path, true),
    'file-open!'(Path, "wc", Handle),
    'file-write!'(Handle, "written", true),
    'file-close!'(Handle, true),
    'read-file!'(Path, Content), Content == "written",
    'delete-file!'(Path, true).

% HE's own rule: c demands w, so rc is refused rather than quietly reading.
test(create_without_write_is_refused) :-
    test_path('petta_text_f.txt', Path),
    catch('file-open!'(Path, "rc", _), error(domain_error(_, _), _), true).

test(an_unknown_option_letter_is_refused) :-
    test_path('petta_text_g.txt', Path),
    catch('file-open!'(Path, "z", _), error(domain_error(_, _), _), true).

test(using_a_closed_handle_raises) :-
    test_path('petta_text_h.txt', Path),
    'write-file!'(Path, "x", true),
    'file-open!'(Path, "r", Handle),
    'file-close!'(Handle, true),
    catch('file-read-to-string!'(Handle, _),
          error(existence_error(petta_file_handle, _), _), true),
    'delete-file!'(Path, true).

% A cleanup path should not have to check whether it already ran.
test(closing_twice_is_not_an_error) :-
    test_path('petta_text_i.txt', Path),
    'write-file!'(Path, "x", true),
    'file-open!'(Path, "r", Handle),
    'file-close!'(Handle, true),
    'file-close!'(Handle, true),
    'delete-file!'(Path, true).

test(list_dir_finds_a_file_it_just_wrote) :-
    test_path('petta_text_j.txt', Path),
    'write-file!'(Path, "x", true),
    tmp_test_dir(Dir),
    'list-dir!'(Dir, Entries),
    memberchk("petta_text_j.txt", Entries),
    'delete-file!'(Path, true).

test(listing_a_missing_directory_raises) :-
    catch('list-dir!'("/nonexistent/petta/dir", _),
          error(existence_error(directory, _), _), true).

% The mettafied reading: a file becomes queryable data rather than one string.
test(file_space_makes_the_lines_matchable) :-
    test_path('petta_text_k.txt', Path),
    'write-file!'(Path, "alpha\nbeta\ngamma\n", true),
    'file-space!'(Path, Space),
    findall(N-T, 'get-atoms'(Space, [line, N, T]), Lines),
    msort(Lines, Sorted),
    Sorted == [1-"alpha", 2-"beta", 3-"gamma"],
    'delete-file!'(Path, true).

% The line number is kept because a space is unordered; without it the space
% would be strictly less useful than the string it replaced.
test(file_space_can_be_queried_by_line_number) :-
    test_path('petta_text_l.txt', Path),
    'write-file!'(Path, "alpha\nbeta\n", true),
    'file-space!'(Path, Space),
    findall(T, 'get-atoms'(Space, [line, 2, T]), Found),
    Found == ["beta"],
    'delete-file!'(Path, true).

:- end_tests(lib_file).

:- begin_tests(lib_json).

% HE decodes an object into a SPACE of (key value) atoms rather than an opaque
% dict, so a lookup is a match and there is no new type.
% get-value/3 is deliberately nondeterministic, one answer per matching atom,
% so these tests collect the answer SET rather than taking the first. That
% says what the test means, exactly one value for the key, and leaves no
% choicepoint for plunit to warn about.
test(an_object_decodes_into_a_space) :-
    'json-decode'("{\"a\":1,\"b\":2}", Space),
    'is-space'(Space, true),
    findall(K, 'get-keys'(Space, K), Keys),
    msort(Keys, Sorted), Sorted == [a, b],
    findall(One, 'get-value'(Space, a, One), Ones), Ones == [1].

test(an_absent_key_answers_nothing) :-
    'json-decode'("{\"a\":1}", Space),
    \+ 'get-value'(Space, missing, _).

test(an_array_decodes_into_an_expression) :-
    'json-decode'("[1,2,3]", Out), Out == [1, 2, 3].

test(scalars_decode_to_themselves) :-
    'json-decode'("\"plain\"", S), S == "plain",
    'json-decode'("42", N), N == 42.

% PeTTa's booleans are lowercase, so JSON's literals map onto true/false
% rather than onto HE's capitalised spelling; the reader normalises True to
% true anyway. Null has no PeTTa equivalent and stays as written.
test(the_three_literals_decode_to_pettas_own_atoms) :-
    'json-decode'("true", T), T == true,
    'json-decode'("false", F), F == false,
    'json-decode'("null", U), U == 'Null'.

test(nesting_decodes_all_the_way_down) :-
    'json-decode'("{\"c\":{\"d\":2}}", Outer),
    findall(I, 'get-value'(Outer, c, I), [Inner]),
    'is-space'(Inner, true),
    findall(Two, 'get-value'(Inner, d, Two), Twos), Twos == [2].

test(encode_inverts_decode_for_an_object) :-
    'json-decode'("{\"a\":1}", Space),
    'json-encode'(Space, Text),
    'json-decode'(Text, Again),
    findall(One, 'get-value'(Again, a, One), Ones), Ones == [1].

test(encode_handles_arrays_and_scalars) :-
    'json-encode'([1, 2], Array), 'json-decode'(Array, [1, 2]),
    'json-encode'("text", String), 'json-decode'(String, "text"),
    'json-encode'(true, Bool), 'json-decode'(Bool, true).

test(dict_space_builds_a_space_from_pairs) :-
    'dict-space'([[name, "ann"], [age, 3]], Space),
    findall(Name, 'get-value'(Space, name, Name), Names), Names == ["ann"],
    findall(Age, 'get-value'(Space, age, Age), Ages), Ages == [3].

test(dict_space_refuses_an_entry_that_is_not_a_pair) :-
    catch('dict-space'([[only]], _), error(type_error(key_value_pair, _), _),
          true).

test(malformed_json_raises_rather_than_answering_empty) :-
    catch('json-decode'("{not json", _), _, true).

:- end_tests(lib_json).
