% Purpose: differential gate for the C JSON codec in engine/json_codec.c
%   against the library(json) implementation it accelerates, which stays the
%   specification. Every document in the corpus must read to an identical term
%   and write to an identical string through both paths, errors and refusals
%   included, in both the dict shape the Python wire codec uses and the classic
%   shape lib_json uses.
%
%   Two things this suite does that a plain "does it work" suite would not.
%   It compares the SEAM against the Prolog implementation inside one process,
%   so the comparison is of two implementations rather than of one against a
%   remembered answer. And it pins which documents the C path ANSWERS and which
%   it DECLINES: a C path that quietly declined everything would satisfy every
%   agreement test in here while measuring nothing, so the answer set is a
%   test in its own right.
%
%   Run: cd tests/prolog && swipl -g "set_test_options([format(log)]), run_tests" -t halt suites/libraries/json_codec.plt
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/json_codec').

%library(json) declares json_dict_pairs/2 multifile but STATIC, so the hook
%test below cannot assert into it. Declaring it dynamic here leaves it with no
%clauses, which is the same answer a static multifile with no clauses gives, so
%every other test in this file still runs the C writer; a clause added at LOAD
%time would instead switch the C writer off for the whole file and make the
%write half of the differential compare Prolog with Prolog.
:- dynamic json:json_dict_pairs/2.

dict_options([shape(dicts), true(@(true)), false(@(false)), null(@(none))]).
classic_options([shape(classic), true(@(true)), false(@(false)), null(@(null))]).

shape_options(dicts, Options) :- dict_options(Options).
shape_options(classic, Options) :- classic_options(Options).

%The door reads its option list ONCE, into the compound its two halves share,
%so the suite asks for that compound rather than re-deriving it per call site.
prepared(Options, COptions) :-
    json_codec:json_codec_request(Options, _, COptions).

%Success value, error term or failure, so a differential case compares all
%three the same way. Two runs open two streams and the error context holds the
%stream handle, so the handle is dropped and the line, column and character
%position it carries are kept: those are what a caller sees.
outcome(Goal, Value, Result) :-
    (   catch(Goal, Error, true)
    ->  (   var(Error)
        ->  Result = ok(Value)
        ;   without_stream_handle(Error, Named),
            Result = err(Named)
        )
    ;   Result = fail
    ).

without_stream_handle(error(What, stream(_, Line, Position, Character)),
                      error(What, at(Line, Position, Character))) :- !.
without_stream_handle(error(What, _), error(What, context)) :- !.
without_stream_handle(Error, Error).

agree_read(Text, Shape) :-
    shape_options(Shape, Options),
    prepared(Options, COptions),
    outcome(json_codec:json_codec_read_prolog(Text, Reference, Shape, COptions),
            Reference, Expected),
    outcome(json_codec_read(Text, Answer, Options), Answer, Got),
    (   Expected =@= Got
    ->  true
    ;   format(user_error,
               "read disagreement (~w) on ~q:~n  prolog: ~q~n  seam:   ~q~n",
               [Shape, Text, Expected, Got]),
        fail
    ).

%Each side gets its OWN copy, because library(json)'s writer binds what it is
%given for some partly-instantiated shapes -- json(Var) becomes json([]) and
%writes {} -- and a shared term would hand the second path a value the first
%had already filled in. The state each side leaves its copy in is compared too,
%so "the same answer" includes "the same bindings".
agree_write(Value, Shape) :-
    shape_options(Shape, Options),
    copy_term(Value, ForReference),
    copy_term(Value, ForSeam),
    prepared(Options, COptions),
    outcome(( json_codec:json_codec_finite(ForReference),
              json_codec:json_codec_write_prolog(ForReference, Reference,
                                                 Shape, COptions) ),
            Reference-ForReference, Expected),
    outcome(json_codec_write(ForSeam, Answer, Options), Answer-ForSeam, Got),
    (   Expected =@= Got
    ->  true
    ;   format(user_error,
               "write disagreement (~w) on ~q:~n  prolog: ~q~n  seam:   ~q~n",
               [Shape, Value, Expected, Got]),
        fail
    ).

%Both directions over one document, which is what a caller actually does.
agree_both(Text, Shape) :-
    agree_read(Text, Shape),
    shape_options(Shape, Options),
    prepared(Options, COptions),
    (   catch(json_codec:json_codec_read_prolog(Text, Value, Shape, COptions),
              _, fail)
    ->  agree_write(Value, Shape)
    ;   true
    ).

% ------------------------------------------------------------------ the corpus

%Structure, layout and the empty cases.
document("{}").
document("[]").
document("  {  }  ").
document("\t\n\r {\"a\"\n:\t1\r}").
document("{\"a\":1}").
document("{\"a\":1,\"b\":2,\"c\":3}").
document("[1,2,3]").
document("[[[[[]]]]]").
document("{\"a\":{\"b\":{\"c\":{\"d\":[]}}}}").
document("[{},[],{\"a\":[]},[{}]]").
document("{\"outer\":{\"inner\":[1,{\"deep\":true}]}}").

%Strings: every escape library(json) knows, the ones it refuses, and text that
%needs none.
document("\"\"").
document("\"plain\"").
document("\"a b\tc\"").
document("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"").
document("\"\\u0000\"").
document("\"\\u001f\"").
document("\"\\u00e9\"").
document("\"\\u00E9\"").
document("\"\\uD83D\\uDE00\"").
document("\"\\ud83d\\ude00\"").
document("\"é\"").
document("\"Полтора Землекопа\"").
document("\"</script>\"").
document("\"<\\/script>\"").
document("\"a<b/c\"").
document("{\"</a>\":\"</b>\"}").
document("\"\\ud800\"").
document("\"\\udc00\"").
document("\"\\ud800x\"").
%A high surrogate whose partner is an escape but NOT a low surrogate. Without
%these the C reader could combine any following \uXXXX into a wrong character
%and every agreement test still passed: the planted-divergence run of
%2026-08-28 reported exactly that gap.
document("\"\\ud800\\u0041\"").
document("\"\\ud800\\ud800\"").
document("\"\\ud83d\\u0041\"").
document("\"\\ud800\\udbff\"").
document("\"\\udbff\\udfff\"").
document("\"\\ud800\\n\"").
document("\"\\ud800\\\\\"").
document("\"\\uZZZZ\"").
document("\"\\q\"").
document("\"unterminated").

%Numbers, including the ones library(json) reads more leniently than JSON
%allows and the ones no double can hold.
document("0").
document("-0").
document("1").
document("-1").
document("42").
document("1.0").
document("-1.0").
document("0.1").
document("1e5").
document("1E5").
document("1e+5").
document("1e-5").
document("1.5e10").
document("123456789012345678901234567890").
document("-123456789012345678901234567890").
document("999999999999999999").
document("1000000000000000000").
document("9223372036854775807").
document("9223372036854775808").
document("-9223372036854775808").
document("-9223372036854775809").
document("1.7976931348623157e308").
document("5e-324").
document("1e999").
document("-1e999").
document("1e-999").
document("01").
document("1.").
document(".5").
document("+1").
document("-").
document("1-2").
document("0x10").
document("1e").
document("[1, 2.5, -3, 4e2]").

%The three literals and the shapes near them.
document("true").
document("false").
document("null").
document("[true,false,null]").
document("{\"t\":true,\"f\":false,\"n\":null}").
document("truex").
%Every constant cut short at every length. SWI's json_read_constant/3 checks
%the rest with must_see/3 and stops where it stops; the C reader has to stop in
%the same place, and one hand-picked truncation would only prove one of them.
document(Text) :-
    member(Word, ["true", "false", "null"]),
    string_length(Word, Length),
    Last is Length - 1,
    between(1, Last, Cut),
    sub_string(Word, 0, Cut, _, Text).
document("NaN").
document("Infinity").
document("-Infinity").

%The hazard set: duplicates, trailing content, trailing commas, and text that
%is not JSON at all.
document("{\"a\":1,\"a\":2}").
document("{\"a\":1,\"a\":1}").
%Two spellings of one key. The duplicate has to be found after the escapes are
%decoded, which is where a check over the raw quoted text would miss it.
document("{\"a\":1,\"\\u0061\":2}").
document("{\"\\u00e9\":1,\"é\":2}").
document("{\"a\":1} ").
document("{\"a\":1}  \n\t ").
document("{\"a\":1} {\"b\":2}").
document("{\"a\":1}x").
document("[1,2,]").
document("{\"a\":1,}").
document("[,1]").
document("{,\"a\":1}").
document("").
document("   ").
document("'single'").
document("{a:1}").
document("{\"a\" 1}").
document("{\"a\":}").
document("[1 2]").
document("{").
document("[").
document("}").
document("]").
document("{\"py\":\"x\",\"a\":1}").
document("{\"\":1}").
document("{\"#\":1}").
%Keys, not values, through every text shape an atom can be made from.
document("{\"\\u0000\":1}").
document("{\"\\ud83d\\ude00\":1}").
document("{\"é\":1}").
document("{\"a\\tb\":1}").
document("{\"</script>\":1}").

deep_document(Text) :-
    deep_nesting(400, Inner),
    format(atom(Text), "{\"deep\":~w}", [Inner]).

deep_nesting(0, "[]") :- !.
deep_nesting(N, Text) :-
    M is N - 1,
    deep_nesting(M, Inner),
    format(atom(Text), "[~w]", [Inner]).

%A document too deep for the C path, which must decline it rather than
%overflow the C stack; the Prolog reader answers it.
too_deep_document(Text) :-
    deep_nesting(1200, Inner),
    format(atom(Text), "{\"deep\":~w}", [Inner]).

%Values a document cannot spell but a caller can hand the writer.
writable(Value, dicts) :- writable_common(Value).
writable(Value, classic) :- writable_common(Value).
writable(Dict, dicts) :- dict_create(Dict, '#', [a-1, b-"two", c-[1, 2]]).
writable(Dict, dicts) :- dict_create(Dict, '#', [1-"integer key"]).
writable(Dict, dicts) :- dict_create(Dict, tagged, [a-1]).
writable(json([a= 1, b= "two"]), classic).
writable(json([a-1]), classic).
writable(json([a(1)]), classic).
writable(json([]), classic).

writable_common([]).
writable_common([1, 2, 3]).
writable_common("text").
writable_common(bare_atom).
writable_common('an atom with spaces').
writable_common("</script>").
writable_common(0).
writable_common(-0).
writable_common(1.0).
writable_common(-0.0).
writable_common(0.1).
writable_common(1.0e308).
writable_common(123456789012345678901234567890).
writable_common(@(true)).
writable_common(@(false)).
writable_common(@(none)).
writable_common(@(null)).
writable_common(@(unknown)).
writable_common(Rational) :- Rational is 1 rdiv 3.
writable_common(f(x)).
writable_common(_).
writable_common([1|_]).
writable_common([1|two]).
%Partly-instantiated shapes library(json)'s own writer answers rather than
%refuses, json(Var) as {} and json([a=1|Var]) as the invalid {"a":1,}, both
%while BINDING what it was given. The seam is required to agree with the
%specification, not to improve on it.
writable_common(json(_)).
writable_common(json([_])).
writable_common(json([a=1|_])).

non_finite(V) :- V is nan.
non_finite(V) :- V is inf.
non_finite(V) :- V is -inf.

% ------------------------------------------------------ generated documents

%Random values, rendered by the Prolog writer and read back by both paths, so
%the corpus is not limited to shapes a person thought of.
random_value(0, Value) :-
    !,
    random_between(1, 6, Which),
    random_leaf(Which, Value).
random_value(Depth, Value) :-
    random_between(1, 8, Which),
    (   Which =< 4
    ->  random_leaf(Which, Value)
    ;   Which =< 6
    ->  Next is Depth - 1,
        random_between(0, 4, Length),
        length(Value, Length),
        maplist(random_value(Next), Value)
    ;   Next is Depth - 1,
        random_between(0, 4, Length),
        %findall rather than numlist/3, which FAILS for an empty range and
        %took every generated empty object out of the corpus silently.
        findall(Index, between(1, Length, Index), Indices),
        maplist(random_pair(Next), Indices, Pairs),
        Value = json(Pairs)
    ).

%The index keeps the keys of one object DISTINCT. Duplicates are a hazard the
%fixed corpus covers on purpose; generating them here instead made the
%reference decode raise while the reference was being built, outside the
%comparison, which reads as a suite failure rather than as the agreement it
%actually is.
random_pair(Depth, Index, Key=Value) :-
    random_text(Text),
    format(atom(Key), "~w~w", [Text, Index]),
    random_value(Depth, Value).

random_leaf(1, Value) :- random_between(-1000000, 1000000, Value).
random_leaf(2, Value) :- Value is (random_float - 0.5) * 1000.
random_leaf(3, Value) :- random_text(Value).
random_leaf(4, @(true)).
random_leaf(5, @(false)).
random_leaf(6, @(null)).

random_text(Text) :-
    random_between(0, 12, Length),
    length(Codes, Length),
    maplist(random_code, Codes),
    string_codes(Text, Codes).

%Deliberately across the interesting boundaries: control characters, the two
%characters JSON escapes, ASCII, Latin-1, the basic plane and the astral plane.
random_code(Code) :-
    random_between(1, 8, Which),
    random_code(Which, Code).

random_code(1, Code) :- random_between(1, 31, Code).
random_code(2, 0'").
random_code(3, 0'\\).
random_code(4, Code) :- random_between(32, 126, Code).
random_code(5, Code) :- random_between(160, 255, Code).
random_code(6, Code) :- random_between(0x100, 0xD7FF, Code).
random_code(7, Code) :- random_between(0xE000, 0xFFFD, Code).
random_code(8, Code) :- random_between(0x10000, 0x10FFFF, Code).

%A random value is built in the classic shape and, for the dict shape, taken
%through text so the dict door is what shapes it. Both are written by the
%PROLOG implementation, so the document under test is the specification's own
%output rather than the C writer's.
generated_document(Shape, Text) :-
    shape_options(Shape, Options),
    prepared(Options, COptions),
    classic_options(ClassicOptions),
    prepared(ClassicOptions, ClassicCOptions),
    random_value(3, Classic),
    (   Shape == dicts
    ->  json_codec:json_codec_write_prolog(Classic, ClassicText, classic,
                                           ClassicCOptions),
        json_codec:json_codec_read_prolog(ClassicText, Value, dicts, COptions)
    ;   Value = Classic
    ),
    json_codec:json_codec_write_prolog(Value, Text, Shape, COptions).

% ------------------------------------------------------------------ the tests

:- begin_tests(json_codec).

%What the seam guarantees whether or not the artefact is present.

test(reading_and_writing_round_trip_in_both_shapes) :-
    forall(member(Shape, [dicts, classic]),
           ( shape_options(Shape, Options),
             json_codec_read("{\"a\":[1,2,{\"b\":null}]}", Value, Options),
             json_codec_write(Value, Text, Options),
             json_codec_read(Text, Again, Options),
             Value =@= Again )).

test(trailing_content_is_refused_in_both_shapes) :-
    forall(member(Shape, [dicts, classic]),
           ( shape_options(Shape, Options),
             catch(json_codec_read("{\"a\":1} {\"b\":2}", _, Options),
                   error(syntax_error(json(trailing_content)), _),
                   true) )).

test(trailing_layout_is_not_trailing_content) :-
    dict_options(Options),
    json_codec_read("{\"a\":1}  \n\t ", Value, Options),
    get_dict(a, Value, One),
    One == 1.

test(a_non_finite_number_is_refused_before_writing) :-
    dict_options(Options),
    forall(non_finite(Value),
           catch(json_codec_write([Value], _, Options),
                 error(domain_error(finite_number, _), _),
                 true)).

test(an_object_read_as_a_dict_carries_json_read_dicts_own_tag) :-
    dict_options(Options),
    json_codec_read("{\"a\":1}", Value, Options),
    is_dict(Value, Tag),
    json_codec:json_codec_dict_tag(Tag).

%The finiteness walk INSPECTS. A version of it that unified answered "{}" for
%an unbound value and bound that value to json([]), where json_write_term/4
%has always raised instantiation_error.
test(writing_something_unbound_raises_instead_of_inventing_it) :-
    forall(member(Shape, [dicts, classic]),
           ( shape_options(Shape, Options),
             copy_term(Value, Before),
             catch(json_codec_write(Value, _, Options),
                   error(instantiation_error, _), true),
             Value =@= Before )).

%An absent option and a wrong one are different mistakes and say so.
test(a_shape_that_is_not_named_is_refused) :-
    catch(json_codec_read("1", _, [true(@(true)), false(@(false)),
                                   null(@(none))]),
          error(existence_error(json_codec_option, shape), _),
          true),
    catch(json_codec_read("1", _, [shape(sideways), true(@(true)),
                                   false(@(false)), null(@(none))]),
          error(domain_error(json_codec_shape, _), _),
          true).

test(a_literal_that_is_not_named_is_refused) :-
    catch(json_codec_read("1", _, [shape(dicts), true(@(true))]),
          error(existence_error(json_codec_option, _), _),
          true).

%An option this door does not implement is refused rather than ignored, which
%is how tag(py) sat in the wire decoder for months doing something nobody
%wanted.
test(an_option_this_door_does_not_implement_is_refused) :-
    dict_options(Base),
    forall(member(Extra, [tag(py), default_tag(py), value_string_as(atom),
                          width(72), _]),
           forall(member(Goal, [json_codec_read("1", _, [Extra|Base]),
                                json_codec_write(1, _, [Extra|Base])]),
                  catch(Goal, error(domain_error(json_codec_options, _), _),
                        true))),
    catch(json_codec_read("1", _, not_a_list),
          error(domain_error(json_codec_options, _), _), true).

test(the_writer_answers_one_line_whatever_the_document_is) :-
    classic_options(Options),
    deep_document(Text),
    json_codec_read(Text, Value, Options),
    json_codec_write(Value, Written, Options),
    \+ sub_string(Written, _, _, _, "\n").

:- end_tests(json_codec).

:- begin_tests(json_codec_differential,
               [ condition(json_codec:json_codec_c_active) ]).

%The C path against the Prolog implementation, in one process, over the corpus.

test(every_document_reads_the_same_through_both_paths) :-
    forall(( document(Text), member(Shape, [dicts, classic]) ),
           agree_both(Text, Shape)).

test(a_deeply_nested_document_reads_the_same_through_both_paths) :-
    deep_document(Text),
    forall(member(Shape, [dicts, classic]), agree_both(Text, Shape)).

test(a_document_past_the_c_depth_limit_is_still_answered) :-
    too_deep_document(Text),
    classic_options(Options),
    prepared(Options, COptions),
    \+ json_codec:metta_c_json_read(Text, _, COptions),
    json_codec_read(Text, Value, Options),
    Value = json([deep=_]).

test(every_writable_value_writes_the_same_through_both_paths) :-
    forall(( member(Shape, [dicts, classic]), writable(Value, Shape) ),
           agree_write(Value, Shape)).

test(a_non_finite_number_is_refused_the_same_way_through_both_paths) :-
    forall(( member(Shape, [dicts, classic]), non_finite(Number),
             member(Value, [Number, [Number], json([a=Number])]) ),
           agree_write(Value, Shape)).

test(generated_documents_read_the_same_through_both_paths) :-
    set_random(seed(20260828)),
    forall(( between(1, 400, _), member(Shape, [dicts, classic]) ),
           ( generated_document(Shape, Text), agree_both(Text, Shape) )).

%Anti-vacuity. A C path that declined every document would pass every test
%above while doing nothing, so what it ANSWERS is pinned too.
test(the_c_path_answers_the_documents_it_exists_for) :-
    Answerable = [ "{}", "[]", "{\"a\":1}", "[1,2,3]", "\"text\"", "42",
                   "1.5", "true", "false", "null", "\"\\uD83D\\uDE00\"",
                   "{\"a\":{\"b\":[1,2,{\"c\":null}]}}",
                   "123456789012345678901234567890", "\"é\"",
                   "5e-324", "1.7976931348623157e308", "-0", "0.1",
                   "{\"a\":1}  \n " ],
    forall(( member(Text, Answerable), member(Shape, [dicts, classic]) ),
           ( shape_options(Shape, Options),
             prepared(Options, COptions),
             (   json_codec:metta_c_json_read(Text, _, COptions)
             ->  true
             ;   format(user_error, "the C reader declined ~q (~w)~n",
                        [Text, Shape]),
                 fail
             ) )).

test(the_c_path_writes_the_values_it_exists_for) :-
    dict_options(Options),
    prepared(Options, COptions),
    json_codec_read("{\"a\":[1,2.5,\"three\",true,null,{\"b\":[]}]}", Value,
                    Options),
    json_codec:metta_c_json_write(Value, _, COptions).

%And what it DECLINES, so a change that starts accepting one of these has to
%prove its parity rather than inherit a green lane.
test(the_c_path_declines_rather_than_guessing) :-
    %A duplicate key is declined in the DICT shape only, where the answer is an
    %error the Prolog implementation raises; the classic shape keeps both
    %pairs, so there is nothing to decline.
    %5e-324 and 1e-999 are NOT here: glibc's strtod answers the smallest
    %subnormal, and underflow to zero, without setting ERANGE, so the C reader
    %answers both and the agreement test above is what says the answers are
    %Prolog's. Overflow is the case that does set it, and 1e999 is here.
    Declined = [ "{\"a\":1} {\"b\":2}", "[1,2,]",
                 "\"\\ud800\"", "\"\\udc00\"", "01", "1.", "1e999",
                 "{\"a\":1,}" ],
    dict_options(DictOptions),
    prepared(DictOptions, DictCOptions),
    \+ catch(json_codec:metta_c_json_read("{\"a\":1,\"a\":2}", _, DictCOptions),
             _, fail),
    forall(( member(Text, Declined), member(Shape, [dicts, classic]) ),
           ( shape_options(Shape, Options),
             prepared(Options, COptions),
             (   catch(json_codec:metta_c_json_read(Text, _, COptions), _, fail)
             ->  format(user_error,
                        "the C reader answered ~q (~w), which nothing here proves it answers identically~n",
                        [Text, Shape]),
                 fail
             ;   true
             ) )).

%library(json)'s writer consults two multifile hooks that the C writer knows
%nothing about, so a process that defines one must get the Prolog writer for
%everything. Planting json_dict_pairs/2 to reverse a dict's keys makes the two
%writers disagree unless the seam steps back, which is what this measures; the
%clause is retracted whether the test passes or fails, because plunit runs a
%whole file in one process.
test(a_write_hook_takes_the_whole_write_back_to_prolog,
     [ setup(assertz((json:json_dict_pairs(Dict, Pairs) :-
                          dict_pairs(Dict, _, Ordered),
                          reverse(Ordered, Pairs)), Planted)),
       cleanup(erase(Planted)) ]) :-
    dict_options(Options),
    \+ json_codec:json_codec_no_write_hook,
    dict_create(Value, '#', [a-1, b-2, c-3]),
    agree_write(Value, dicts),
    json_codec_write(Value, Text, Options),
    Text == "{\"c\":3,\"b\":2,\"a\":1}".

test(the_c_writer_declines_rather_than_guessing) :-
    dict_options(Options),
    prepared(Options, COptions),
    Rational is 1 rdiv 3,
    NotWritable = [f(x), _, [1|_], [1|two], Rational, @(unknown)],
    forall(member(Value, NotWritable),
           \+ catch(json_codec:metta_c_json_write(Value, _, COptions), _, fail)).

:- end_tests(json_codec_differential).
