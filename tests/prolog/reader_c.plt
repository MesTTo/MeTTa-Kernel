% Purpose: differential gate for the C reader in engine/reader.c against the
%   Prolog reader it ports, which stays the specification: every shipped
%   .metta file and an adversarial battery must parse to variant-identical
%   results through both full-source readers and both single-form readers,
%   errors and failures included, and generated number spellings must convert
%   to identical values bit for bit.
%
%   The whole suite is conditioned on parser:petta_c_reader_active: a box
%   without the built artifact runs the Prolog reader everywhere and this
%   suite reports its tests as skipped. check.sh builds engine/reader.so
%   before the plunit lane wherever swipl-ld exists, so the gate exercises
%   the shipping configuration.
%
%   Run: cd tests/prolog && swipl -g "set_test_options([format(log)]), run_tests" -t halt reader_c.plt
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

% Load the engine through metta.pl, not main.pl: main.pl's
% `:- initialization(main, main).` fires on consult and prints its demo
% into the test output.
:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(reader_c, [condition(parser:petta_c_reader_active)]).

%Outcome capture: success value, error term, or failure, so a differential
%case compares all three the same way.
reader_outcome(G, V, R) :-
    (   catch(G, E, true)
    ->  ( var(E) -> R = ok(V) ; R = err(E) )
    ;   R = fail
    ).

%The Prolog single-form reference, sread_with_names_mode/4's own fallback
%body, bypassing the C dispatch so the two readers stay comparable after
%the dispatch made the C one the default.
reader_sread_prolog(S, T, Names) :-
    string_codes(S, Cs),
    (   catch(phrase(parser:sexpr_mode(shipped, T, [], Names), Cs),
              error(syntax_error(float_overflow), _),
              parser:metta_saturating_parse(sexpr_mode(shipped, T, [], Names),
                                            Cs))
    ->  true
    ;   format(atom(Msg), 'Parse error in form: ~w', [S]),
        throw(error(syntax_error(Msg), none))
    ).

agree_full(S) :-
    reader_outcome(filereader:parse_metta_source_prolog(S, P), P, OP),
    reader_outcome(parser:petta_c_parse_source(S, C), C, OC),
    (   OP =@= OC
    ->  true
    ;   format(user_error, "full-source disagreement:~n  prolog: ~q~n  c: ~q~n",
               [OP, OC]),
        fail
    ).

agree_sread(S) :-
    reader_outcome(reader_sread_prolog(S, T1, N1), T1-N1, OP),
    reader_outcome(parser:petta_c_sread(S, T2, N2), T2-N2, OC),
    (   OP =@= OC
    ->  true
    ;   format(user_error, "sread disagreement:~n  prolog: ~q~n  c: ~q~n",
               [OP, OC]),
        fail
    ).

%The hand battery: every pathological shape the port analysis named, the
%exec-marker rules, the splitter's string-state extents, the quote-token
%fallback, number-grammar boundaries, saturation, variable identity, the
%function classification, and the Unicode boundary table.
adversarial_source("").
adversarial_source("   \n\t ").
adversarial_source("; only a comment").
adversarial_source("; unterminated ( comment").
adversarial_source("!").
adversarial_source("!(f)").
adversarial_source("! x").
adversarial_source("!42").
adversarial_source("!$x").
adversarial_source("!!(f)").
adversarial_source("!;c\n(a)").
adversarial_source("! ;c\nx").
adversarial_source("!)").
adversarial_source(")").
adversarial_source("(a) )").
adversarial_source("a)b").
adversarial_source("(a b").
adversarial_source("((a)").
adversarial_source("(a ; )\n").
adversarial_source("(\"").
adversarial_source("(\"a\\\") (x)").
adversarial_source("\"a b\"").
adversarial_source("(\"a\tb\")").
adversarial_source("(\"esc \\n \\t \\r \\\\ \\\" \\x\")").
adversarial_source("\"\"").
adversarial_source("\"\"x\"\"").
adversarial_source("(a \")").
adversarial_source("(\"ab\\\" x)").
adversarial_source("12\"3 4\"").
adversarial_source("42").
adversarial_source("-42").
adversarial_source("+42").
adversarial_source("4.5").
adversarial_source("-4.5e10").
adversarial_source("12.5E3").
adversarial_source("1e400").
adversarial_source("-1e400").
adversarial_source("1e-400").
adversarial_source("5e3").
adversarial_source("12.").
adversarial_source(".5").
adversarial_source("+.5").
adversarial_source("12.5e").
adversarial_source("1e5x").
adversarial_source("007").
adversarial_source("+").
adversarial_source("-").
adversarial_source("9223372036854775807").
adversarial_source("9223372036854775808").
adversarial_source("-9223372036854775808").
adversarial_source("-9223372036854775809").
adversarial_source("99999999999999999999999999999999999999").
adversarial_source("-99999999999999999999999999999999999999").
adversarial_source("+99999999999999999999999999999999999999").
adversarial_source("($x $x $_ $_ $x)").
adversarial_source("($)").
adversarial_source("$").
adversarial_source("($\"a\")").
adversarial_source("($x.y $x.y)").
adversarial_source("(= $x 1)").
adversarial_source("(= (f $x) $x)").
adversarial_source("(= x 1)").
adversarial_source("(= (\"s\") 1)").
adversarial_source("(= () 1)").
adversarial_source("(= (f) 1 2)").
adversarial_source("(= (True) 1)").
adversarial_source("True False (True) $True").
adversarial_source("()").
adversarial_source("(() (()))").
adversarial_source("(a . b)").
adversarial_source("(a\u00A0b)").
adversarial_source("x\u00A0y").
adversarial_source("(a\u3000b)").
adversarial_source("x\u2028y").
adversarial_source("x\u0085y").
adversarial_source("; c\u00A0still comment\nx").
adversarial_source("; cr\rstays\ncomment-done").
adversarial_source("(f \u65E5\u672C\u8A9E \"\u65E5\\\u672C\")").
adversarial_source("(a ;c\n b)").
adversarial_source("(a ;)\n)").
adversarial_source("!\t(tab-marked)").
adversarial_source("!\u00A0(nbsp-marked)").

%Generated stress: nesting bounded by the heap on both sides (the C reader
%parses iteratively, never on the native stack), one very wide form, an
%embedded NUL codepoint, and the repeated multibyte form the compiled-reader
%spike's corpus used.
stress_source(Deep) :-
    Depth = 200000,
    length(Open, Depth), maplist(=(0'(), Open),
    length(Close, Depth), maplist(=(0')), Close),
    append([Open, `x`, Close], Cs),
    string_codes(Deep, Cs).
stress_source(Wide) :-
    numlist(1, 100000, Ns),
    maplist([N, T]>>format(atom(T), "a~w", [N]), Ns, Ts),
    atomic_list_concat(Ts, ' ', Body),
    format(string(Wide), "(~w)", [Body]).
stress_source(Nul) :-
    string_codes(Nul, [0'(, 0'a, 0, 0'b, 0')]).
stress_source(Lambda) :-
    Unit = "(f $x $x \"a\\n\" \u03BB)\n",
    findall(Unit, between(1, 512, _), Units),
    atomics_to_string(Units, Lambda).

test(every_shipped_source_parses_identically_through_both_readers) :-
    expand_file_name('../../examples/*/*.metta', Fs1),
    expand_file_name('../../examples/*/*/*.metta', Fs2),
    expand_file_name('../../lib/*.metta', Fs3),
    append([Fs1, Fs2, Fs3], Fs0),
    msort(Fs0, Fs),
    length(Fs, N),
    N > 200,
    aggregate_all(count,
                  ( member(F, Fs),
                    read_file_to_string(F, S, []),
                    agree_full(S) ),
                  N).

test(the_adversarial_battery_agrees_through_the_full_source_door) :-
    aggregate_all(count, adversarial_source(_), N),
    aggregate_all(count, ( adversarial_source(S), agree_full(S) ), N).

test(the_adversarial_battery_agrees_through_the_single_form_door) :-
    aggregate_all(count, adversarial_source(_), N),
    aggregate_all(count, ( adversarial_source(S), agree_sread(S) ), N).

test(generated_stress_shapes_agree_through_both_doors) :-
    aggregate_all(count, stress_source(_), N),
    aggregate_all(count,
                  ( stress_source(S), agree_full(S), agree_sread(S) ),
                  N).

test(the_error_shapes_match_the_prolog_reader) :-
    catch(parser:petta_c_parse_source("x\n (a b", _), E1, true),
    E1 = error(syntax_error(M1), none),
    M1 == 'missing \')\', starting at line 2:\na b',
    catch(parser:petta_c_sread("(a))", _, _), E2, true),
    E2 = error(syntax_error(M2), none),
    M2 == 'Parse error in form: (a))'.

test(number_conversion_agrees_with_the_prolog_reader) :-
    set_random(seed(20260824)),
    Floats = 20000,
    aggregate_all(count,
                  ( between(1, Floats, _),
                    random_number_spelling(float, S),
                    agree_sread(S) ),
                  Floats),
    Ints = 5000,
    aggregate_all(count,
                  ( between(1, Ints, _),
                    random_number_spelling(integer, S),
                    agree_sread(S) ),
                  Ints).

test(the_dispatching_door_answers_through_the_c_reader) :-
    filereader:parse_metta_source("(= (f $x) $x) !(g $y)", ViaDispatch),
    filereader:parse_metta_source_prolog("(= (f $x) $x) !(g $y)", ViaProlog),
    ViaDispatch =@= ViaProlog.

random_number_spelling(float, S) :-
    random_between(-323, 308, E),
    X0 is random_float,
    catch(X is X0 * 10.0 ** E, _, X = 0.0),
    (   random_between(0, 1, 0)
    ->  number_codes(X, Cs)
    ;   parser:metta_float_codes(X, Cs)
    ),
    string_codes(S, Cs).
random_number_spelling(integer, S) :-
    random_between(1, 400, Bits),
    High is 1 << Bits,
    random_between(0, High, V0),
    random_between(0, 2, SignPick),
    (   SignPick =:= 0 -> format(string(S), "~w", [V0])
    ;   SignPick =:= 1 -> format(string(S), "-~w", [V0])
    ;   format(string(S), "+~w", [V0])
    ).

:- end_tests(reader_c).
