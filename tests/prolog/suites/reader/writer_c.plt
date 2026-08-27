% Purpose: differential gate for the C writer in engine/writer.c against the
%   Prolog writer it ports, which stays the specification. Every form of every
%   shipped .metta file and an adversarial battery must write to a
%   BYTE-IDENTICAL string through both, in all three of writer.c's modes and
%   through the round-trip guard, with refusals naming the same culprit; and
%   every public door must answer what it answers with the C writer switched
%   off.
%
%   The reference is taken by retracting parser:metta_c_writer_active/0 for
%   the length of one call, which is the in-process form of METTA_C_WRITER=off
%   and is the dispatch's only gate. That is deliberate: it gives every door
%   its own reference without a second implementation in this file that could
%   drift from parser.pl.
%
%   Three properties this file keeps beyond agreement:
%
%   - A writer that DECLINED everything would agree on every case here,
%     because a decline routes the call back to the Prolog writer. So the lane
%     counts routes and declines and fails if the C path stops answering
%     (the_c_writer_answers_the_corpus_rather_than_declining_it).
%   - The comparator must be able to say no. A planted one-byte divergence
%     goes through the same predicate every corpus case uses and the lane
%     fails if that stops being caught (a_one_byte_divergence_is_caught). The
%     real plant was also done in writer.c and reverted, and is recorded in
%     CHANGELOG.md.
%   - Every shape writer.c hands back must be handed back AND answered by the
%     Prolog writer (the_shapes_outside_the_ported_fragment_route_back).
%
%   The whole suite is conditioned on parser:metta_c_writer_active: a box
%   without the built artifact runs the Prolog writer everywhere and reports
%   its tests as skipped. check.sh builds engine/writer.so before the plunit
%   lane wherever swipl-ld exists, so the gate exercises the shipping
%   configuration.
%
%   Run: cd tests/prolog && swipl -g "set_test_options([format(log)]), run_tests" -t halt suites/reader/writer_c.plt
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

% Load the engine through metta.pl, not main.pl: main.pl's
% `:- initialization(main, main).` fires on consult and prints its demo
% into the test output.
:- ensure_loaded('../../../../engine/metta.pl').

:- begin_tests(writer_c, [condition(parser:metta_c_writer_active)]).

%Outcome capture: success value, error term, or failure, so a differential
%case compares all three the same way.
writer_outcome(G, V, R) :-
    (   catch(G, E, true)
    ->  ( var(E) -> R = ok(V) ; R = err(E) )
    ;   R = fail
    ).

%The Prolog answer, from the same door with the C writer switched off. BOTH
%gates go: metta_c_writer_active/0 is the artifact's, and
%metta_c_strict_writer/0 is the token registry's derived one, and a door
%reads whichever applies to it.
without_c_writer(Goal) :-
    setup_call_cleanup(( retract(parser:metta_c_writer_active),
                         retract(parser:metta_c_strict_writer) ),
                       Goal,
                       ( assertz(parser:metta_c_writer_active),
                         assertz(parser:metta_c_strict_writer) )).

prolog_outcome(Goal, Value, Outcome) :-
    without_c_writer(writer_outcome(Goal, Value, Outcome)).

%The C answer in one of writer.c's three modes, mapped through parser.pl's own
%metta_c_string/2 so the refusal term has exactly one construction. `declined`
%is kept apart: it is the fallback firing, not a disagreement.
c_outcome(Mode, Term, Outcome) :-
    (   catch(( parser:metta_c_write(Term, Mode, Result),
                (   Result == declined
                ->  true
                ;   parser:metta_c_string(Result, S)
                ) ),
              E, true)
    ->  (   nonvar(E)
        ->  Outcome = err(E)
        ;   Result == declined
        ->  Outcome = declined
        ;   Outcome = ok(S)
        )
    ;   Outcome = fail
    ).

%A disagreement prints what both sides said. The planted self-test below runs
%the same comparator on purpose, so it silences the report rather than
%bypassing the check.
report(Format, Args) :-
    (   nb_current(writer_c_quiet, true)
    ->  true
    ;   format(user_error, Format, Args)
    ).

%One differential cell: PROLOG against C, byte for byte, with the route and
%decline counters threaded so a caller can prove the C path is answering.
agree(Label, Term, PrologOutcome, Mode, Routed0, Routed, Declined0, Declined) :-
    c_outcome(Mode, Term, COutcome),
    (   COutcome == declined
    ->  Routed = Routed0, Declined is Declined0 + 1
    ;   PrologOutcome =@= COutcome
    ->  Routed is Routed0 + 1, Declined = Declined0
    ;   report("~w disagreement on ~q:~n  prolog: ~q~n  c:      ~q~n",
               [Label, Term, PrologOutcome, COutcome]),
        fail
    ).

%Every mode writer.c serves, over one term. Strict and display start from the
%raw term through their public doors; the two numbered modes start from the
%term stable_print_term/2 already numbered, which is what swrite_with_names/3,
%swrite_pretty/2 and the answer groups hand them.
agree_all(Term, R0, R, D0, D) :-
    prolog_outcome(parser:swrite(Term, S1), S1, OStrict),
    agree(strict, Term, OStrict, strict, R0, R1, D0, D1),
    prolog_outcome(parser:sdisplay(Term, S2), S2, ODisplay),
    agree(display, Term, ODisplay, display, R1, R2, D1, D2),
    parser:stable_print_term(Term, Printable),
    prolog_outcome(parser:metta_printable_string(Printable, strict_numbered, S3),
                   S3, ONumbered),
    agree(numbered, Printable, ONumbered, strict_numbered, R2, R3, D2, D3),
    prolog_outcome(parser:metta_printable_string(Printable, display, S4),
                   S4, ODisplayN),
    agree(display_numbered, Printable, ODisplayN, display, R3, R4, D3, D4),
    agree_guard(Term, R4, R, D4, D).

%The round-trip guard is the same walk in writer.c with its bytes dropped, so
%it gets its own cell against metta_unwritable_symbol/2 with the C writer off.
agree_guard(Term, R0, R, D0, D) :-
    prolog_outcome(parser:metta_unwritable_symbol(Term, B), B, Spec0),
    ( Spec0 = ok(Bad) -> Spec = unwritable(Bad)
    ; Spec0 == fail -> Spec = writable
    ; Spec = Spec0 ),
    (   catch(parser:metta_c_unwritable(Term, Got), E, true)
    ->  ( nonvar(E) -> Answer = err(E) ; Answer = Got )
    ;   Answer = fail
    ),
    (   Answer == declined
    ->  R = R0, D is D0 + 1
    ;   Spec =@= Answer
    ->  R is R0 + 1, D = D0
    ;   report("guard disagreement on ~q:~n  prolog: ~q~n  c:      ~q~n",
               [Term, Spec, Answer]),
        fail
    ).

agree_all(Term) :- agree_all(Term, 0, _, 0, _).

%%%% The corpus %%%%

corpus_files(Fs) :-
    expand_file_name('../../examples/*/*.metta', Fs1),
    expand_file_name('../../examples/*/*/*.metta', Fs2),
    expand_file_name('../../lib/*/*.metta', Fs3),
    append([Fs1, Fs2, Fs3], Fs0),
    msort(Fs0, Fs).

corpus_terms(Terms) :-
    corpus_files(Fs),
    findall(T,
            ( member(F, Fs),
              read_file_to_string(F, S, []),
              catch(filereader:parse_metta_source(S, Forms), _, fail),
              member(Form, Forms),
              form_term(Form, T) ),
            Terms).

form_term(parsed(_, _, T), T).
form_term(parsed(_, _, T, _), T).

%%%% The adversarial battery %%%%
%
%Shapes chosen for what they can break rather than for what a program writes:
%the writability edges, the float classes, the non-ASCII names (including the
%MM2 operators, which are real symbols in lib/lib_mm2), the internal
%'$metta_seq' wrapper, and every shape writer.c hands back.
%
%'$metta_seq'(Plan, Parsed) is the engine's gap-pattern wrapper, and it CAN
%reach the writer: prolog:error_message(metta_route_capped(_, Pattern, _)) in
%engine/spaces/bounded_matching.pl calls swrite/2 on a pattern it does not
%unwrap. Both writers refuse it in strict as an ordinary compound; in display
%the C writer hands it back so swrite_mode//2's compound branch spells it.
%Both directions are in the battery.

adversarial([]).
adversarial([[]]).
adversarial([[], []]).
adversarial([[[[]]]]).
adversarial([a]).
adversarial([a, b, c]).
adversarial([a, [b, [c, [d]]]]).
adversarial(a).
adversarial('').
adversarial('True').
adversarial('False').
adversarial(true).
adversarial(false).
adversarial([true, false, 'True', 'False']).
adversarial('$').
adversarial('$x').
adversarial('$_').
adversarial('$$').
adversarial('+').
adversarial('-').
adversarial('.').
adversarial('.5').
adversarial('+.5').
adversarial('42').
adversarial('007').
adversarial('1e5').
adversarial('1abc').
adversarial('-abc').
adversarial('1r3').
adversarial('a"b').
adversarial('"').
adversarial('""').
adversarial('日本').
adversarial('＋').
adversarial('－').
adversarial('λ').
adversarial('é').
adversarial('naïve').
adversarial(['＋', '－', 1, 2]).
%Every codepoint that ends a token, in the middle of a name and at each end,
%read from the engine's own table so the battery cannot fall behind it.
adversarial(A) :- parser:metta_token_boundary(C, _), atom_codes(A, [0'a, C, 0'b]).
adversarial(A) :- parser:metta_token_boundary(C, _), atom_codes(A, [C, 0'a]).
adversarial(A) :- parser:metta_token_boundary(C, _), atom_codes(A, [0'a, C]).
adversarial(S) :- parser:metta_token_boundary(C, _), string_codes(S, [0'a, C, 0'b]).
adversarial("").
adversarial("a").
adversarial("a\"b").
adversarial("a\\b").
adversarial("a\nb").
adversarial("a\tb").
adversarial("a\rb").
adversarial("\\\"\n\t\r").
adversarial("日本＋").
adversarial(["s", 'sym', 1, 1.5]).
adversarial(0).
adversarial(1).
adversarial(-1).
adversarial(9223372036854775807).
adversarial(-9223372036854775808).
adversarial(99999999999999999999999999999999999999).
adversarial(-99999999999999999999999999999999999999).
adversarial(1.0).
adversarial(0.1).
adversarial(-0.1).
adversarial(1.0e20).
adversarial(1.0e16).
adversarial(1.0e17).
adversarial(1.0e15).
adversarial(1.0e-4).
adversarial(1.0e-5).
adversarial(1.0e-320).
adversarial(5.0e-324).
adversarial(1.7976931348623157e308).
adversarial(2.2250738585072014e-308).
adversarial(0.0).
adversarial(-0.0).
adversarial(123456789.0).
adversarial(X) :- X is inf.
adversarial(X) :- X is -inf.
adversarial(X) :- X is nan.
adversarial(X) :- X is 1 rdiv 3.
adversarial(X) :- X is -22 rdiv 7.
adversarial('$metta_variable'(0)).
adversarial('$metta_named_variable'(x)).
adversarial([a, '$metta_variable'(3), b]).
adversarial('$metta_seq'(plan, parsed)).
adversarial([match, '$metta_seq'(one_sided(left), [g]), x]).
adversarial(f(1, 2)).
adversarial([a, f(1)]).
adversarial(-(1, 2)).
adversarial([a|b]).
adversarial([a, b|c]).
adversarial(_).
adversarial([X, X]).
adversarial([X, Y, X, Y, [X, Y]]).
adversarial([a|_]).
adversarial(T) :- length(T, 64), maplist(=(_), T).    % one variable, 64 cells
adversarial(T) :- length(T, 64).                      % 64 distinct variables
adversarial(T) :- length(T, 65).                      % past writer.c's bound
adversarial(T) :- numlist(1, 200, Ns), maplist([N, A]>>atom_number(A, N), Ns, T).
adversarial(T) :- atom_codes(T, [0'a, 0, 0'b]).       % an embedded NUL
adversarial(S) :- string_codes(S, [0'a, 0, 0'b]).
adversarial(T) :- long_atom(100000, T).
adversarial(T) :- long_atom(100000, A), atom_string(A, T).
adversarial(T) :- numlist(1, 50000, T).
adversarial(T) :- deep_list(30000, T).

long_atom(N, A) :- length(Cs, N), maplist(=(0'x), Cs), atom_codes(A, Cs).

deep_list(0, x) :- !.
deep_list(N, [T]) :- N > 0, M is N - 1, deep_list(M, T).

%%%% Tests %%%%

test(every_shipped_form_writes_identically_through_both_writers) :-
    corpus_terms(Terms),
    length(Terms, N),
    N > 2000,
    foldl([T, R0-D0, R-D]>>agree_all(T, R0, R, D0, D), Terms, 0-0, Routed-_),
    Routed > 0.

test(the_adversarial_battery_agrees_through_every_door) :-
    aggregate_all(count, adversarial(_), N),
    N > 150,
    aggregate_all(count, ( adversarial(T), agree_all(T) ), N).

%parser.pl raises ONE error term from whichever culprit it is handed, so the
%two walks have to name the same subterm and not merely agree that one exists.
%Walk order is what decides which, so a term carrying TWO unwritable leaves is
%the case that separates them; a term with one agrees by construction.
test(the_refusal_names_the_same_culprit) :-
    aggregate_all(count, two_culprits(_), N),
    N >= 8,
    aggregate_all(count, ( two_culprits(T), culprit_agrees(T) ), N).

culprit_agrees(Term) :-
    prolog_outcome(parser:metta_unwritable_symbol(Term, B), B, Want),
    (   parser:metta_c_unwritable(Term, Answer)
    ->  true
    ;   Answer = fail
    ),
    (   Want = ok(Bad), Answer == unwritable(Bad)
    ->  true
    ;   report("culprit disagreement on ~q:~n  prolog: ~q~n  c:      ~q~n",
               [Term, Want, Answer]),
        fail
    ).

two_culprits(['42', 'a b']).
two_culprits(['a b', '42']).
two_culprits([a, 'True', b, 'False']).
two_culprits([[a, '1e5'], 'a;b']).
two_culprits([f(1), '42']).
two_culprits(["text", 'a"b', 'x y']).
two_culprits([[[['007']]], 'a b']).
two_culprits([X, '42']) :- X is inf.
two_culprits([X, f(1)]) :- X is nan.

%The public doors against themselves with the C writer off: this is what a
%caller actually reaches, and it covers the naming, pretty and answer-group
%paths the four modes above do not.
test(the_public_doors_answer_what_the_prolog_writer_answers) :-
    corpus_terms(Corpus),
    findall(T, adversarial(T), Extra),
    append(Corpus, Extra, Terms),
    forall(member(T, Terms), doors_agree(T)).

doors_agree(Term) :-
    door(swrite,             parser:swrite(Term, V1), V1, Term),
    door(sdisplay,           parser:sdisplay(Term, V2), V2, Term),
    door(with_names,         parser:swrite_with_names(Term, [], V3), V3, Term),
    door(display_with_names, parser:sdisplay_with_names(Term, [], V4), V4, Term),
    door(pretty,             parser:swrite_pretty(Term, V5), V5, Term),
    door(answer_group,       parser:swrite_answer_group([Term], V6), V6, Term),
    door(display_group,      parser:sdisplay_answer_group([Term], V7), V7, Term),
    door(unwritable_symbol,  parser:metta_unwritable_symbol(Term, V8), V8, Term).

%The reference goal is copied BEFORE the door runs. Copying afterwards would
%hand the Prolog door its own output argument already bound to the C answer,
%which turns a comparison into a unification check and reads as a pass for the
%wrong reason.
door(Label, Goal, Value, Term) :-
    copy_term(Goal-Value, Reference-RefValue),
    writer_outcome(Goal, Value, Got),
    prolog_outcome(Reference, RefValue, Want),
    (   Got =@= Want
    ->  true
    ;   report("door ~w disagreement on ~q:~n  prolog: ~q~n  door:   ~q~n",
               [Label, Term, Want, Got]),
        fail
    ).

%%%% Floats and big integers, in bulk %%%%

test(float_spellings_agree_across_the_binary64_range) :-
    set_random(seed(20260828)),
    Floats = 40000,
    aggregate_all(count,
                  ( between(1, Floats, _), random_float_value(F),
                    float_agrees(F) ),
                  Floats),
    %A power of two is where a shortest-round-trip selector is most likely to
    %need the FARTHER of the two bracketing decimals (CeTTa measures 46 of
    %2098 such), so every one is enumerated rather than sampled.
    aggregate_all(count,
                  ( between(-1074, 1023, E),
                    %2.0**0 evaluates to the INTEGER 1 here, so the power is
                    %forced back to a float before it reaches a float test.
                    catch(F0 is 2.0 ** E, _, fail),
                    F is float(F0),
                    float_agrees(F),
                    NF is -F,
                    float_agrees(NF) ),
                  _).

float_agrees(F) :-
    parser:metta_float_codes(F, Codes),
    string_codes(Want, Codes),
    parser:metta_c_write(F, display, written(Got)),
    (   Want == Got
    ->  true
    ;   report("float ~q: prolog ~w, c ~w~n", [F, Want, Got]),
        fail
    ).

random_float_value(F) :-
    random_between(-323, 308, E),
    X is random_float,
    catch(F is X * 10.0 ** E, _, F = 0.0).

test(big_integers_agree_beyond_int64) :-
    set_random(seed(20260828)),
    N = 4000,
    aggregate_all(count,
                  ( between(1, N, _),
                    random_between(1, 600, Bits),
                    High is 1 << Bits,
                    random_between(0, High, V0),
                    ( random_between(0, 1, 0) -> V = V0 ; V is -V0 ),
                    integer_agrees(V) ),
                  N).

integer_agrees(V) :-
    number_codes(V, Codes),
    string_codes(Want, Codes),
    parser:metta_c_write(V, strict, written(Got)),
    (   Want == Got
    ->  true
    ;   report("integer ~w: prolog ~w, c ~w~n", [V, Want, Got]),
        fail
    ).

%%%% Symbol writability, in bulk %%%%
%
%metta_symbol_writable/1 is the writer's other half and the one place a byte
%scan can disagree with a grammar, so every symbol the corpus carries is asked
%of both, and generated near-number and near-variable spellings are asked too.

test(symbol_writability_agrees_over_the_corpus_and_generated_spellings) :-
    corpus_terms(Terms),
    findall(A, ( member(T, Terms), term_symbol(T, A) ), As0),
    sort(As0, As),
    length(As, N),
    N > 400,
    forall(member(A, As), writability_agrees(A)),
    forall(generated_symbol(A2), writability_agrees(A2)).

term_symbol(T, T) :- atom(T).
term_symbol(T, A) :- is_list(T), member(E, T), term_symbol(E, A).

writability_agrees(A) :-
    (   parser:metta_symbol_writable(A) -> Want = yes ; Want = no ),
    (   parser:metta_c_unwritable(A, Result) -> true ; Result = fail ),
    (   Result == writable -> Got = yes
    ;   Result = unwritable(_) -> Got = no
    ;   Got = Want                     % declined: the Prolog answer stands
    ),
    (   Want == Got
    ->  true
    ;   report("writability ~q: prolog ~w, c ~w~n", [A, Want, Got]),
        fail
    ).

generated_symbol(A) :-
    member(Prefix, ['', '-', '+', '.', '$', '0', '9', 'e', 'E', '1e', '1.',
                    '日', '＋']),
    member(Suffix, ['', '0', '5', 'x', '.5', 'e5', 'e-5', '_', 'True',
                    '日本', '＋']),
    atom_concat(Prefix, Suffix, A).

%%%% The three properties beyond agreement %%%%

test(the_c_writer_answers_the_corpus_rather_than_declining_it) :-
    corpus_terms(Terms),
    length(Terms, N),
    foldl([T, R0-D0, R-D]>>agree_all(T, R0, R, D0, D), Terms, 0-0,
          Routed-Declined),
    %Five differential cells per form, and the shipped corpus holds no shape
    %writer.c hands back, so ONE decline here means a fragment moved.
    Cells is N * 5,
    Declined =:= 0,
    Routed =:= Cells.

test(the_shapes_outside_the_ported_fragment_route_back) :-
    forall(declined_shape(T),
           (   parser:metta_c_write(T, strict, R), R == declined
           ->  true
           ;   report("~q was not declined in strict~n", [T]),
               fail
           )),
    %And the public door still answers, which is the point of declining.
    forall(declined_shape(T2),
           ( writer_outcome(parser:swrite(T2, S), S, Door),
             copy_term(T2, T3),
             prolog_outcome(parser:swrite(T3, S3), S3, Spec),
             Door =@= Spec )).

declined_shape([a|b]).
declined_shape([a, b|c]).
declined_shape([a|_]).
declined_shape(R) :- R is 1 rdiv 3.
declined_shape(T) :- length(T, 65).

test(the_display_door_hands_back_what_only_the_seam_can_spell) :-
    forall(display_declined(T),
           (   parser:metta_c_write(T, display, R), R == declined
           ->  true
           ;   report("~q was not declined in display~n", [T]),
               fail
           )).

display_declined(f(1, 2)).
display_declined('$metta_seq'(plan, parsed)).
display_declined(-(1, 2)).
display_declined(S) :- open_null_stream(S).

%Every reference in this file comes from without_c_writer/1, and the dispatch
%in parser.pl reads exactly the two gates it retracts. If the retract stopped
%working, every differential above would compare the C writer against itself
%and pass for nothing, so the switch is checked rather than trusted.
test(the_reference_run_really_leaves_the_c_writer) :-
    without_c_writer(( \+ parser:metta_c_writer_active,
                       \+ parser:metta_c_strict_writer )),
    parser:metta_c_writer_active,
    parser:metta_c_strict_writer.

%The comparator's own discrimination. agree/8 is the predicate every corpus
%case runs through; feeding it a reference that differs by ONE byte must make
%it fail, or a real divergence could pass unseen.
test(a_one_byte_divergence_is_caught) :-
    Term = [a, b],
    prolog_outcome(parser:swrite(Term, S), S, ok(Correct)),
    string_concat(Correct, " ", Wrong),
    setup_call_cleanup(nb_setval(writer_c_quiet, true),
                       \+ agree(planted, Term, ok(Wrong), strict, 0, _, 0, _),
                       nb_setval(writer_c_quiet, false)),
    %and the honest pair still passes, so the failure above is the byte and
    %not the harness refusing everything
    agree(planted, Term, ok(Correct), strict, 0, R, 0, D),
    R =:= 1,
    D =:= 0.

%The strict gate is DERIVED from the token registry rather than probed on
%every write, so the registry's two mutators are the only things that can
%make it lie. Registering a class that changes what `abc` reads back as must
%close it, and unregistering must reopen it; without that, the C writer would
%keep answering the SHIPPED writability question under a custom reader.
test(a_registered_token_class_closes_the_strict_gate,
     [ setup(parser:'register-token!'("abc", foo, true)),
       cleanup(parser:'unregister-token!'("abc", true)) ]) :-
    \+ parser:metta_c_strict_writer,
    \+ parser:metta_symbol_writable(abc),
    catch(parser:swrite(abc, _), Raised, true),
    Raised = error(metta_unwritable_text(abc), _),
    parser:metta_c_unwritable(abc, writable).   % the C answer, now unused

test(the_strict_gate_reopens_when_the_last_token_class_goes) :-
    parser:metta_c_strict_writer,
    parser:metta_symbol_writable(abc),
    parser:swrite(abc, "abc").

%The suite retracts parser:metta_c_writer_active/0 many times to take its
%reference; this is the last test in the file and it proves every one of them
%put it back.
test(the_writer_gate_is_restored_after_every_reference_run) :-
    parser:metta_c_writer_active,
    parser:metta_c_strict_writer.

%How much this lane compares, held to a floor rather than printed: plunit
%discards a PASSING test's own output, so a log line would say nothing on the
%run that matters. Measured 2026-08-28: 275 shipped .metta files, 3518 forms,
%213 battery shapes, 1880 distinct symbols, 143 generated spellings, 18655
%differential cells, and 29848 public-door comparisons. The floors sit under
%those so an example corpus that is reorganised does not turn the lane red,
%while a glob that stops matching does.
test(the_lane_compares_the_whole_corpus_and_not_a_fragment) :-
    corpus_files(Files),
    length(Files, FileCount),
    FileCount >= 250,
    corpus_terms(Terms),
    length(Terms, Forms),
    Forms >= 3000,
    aggregate_all(count, adversarial(_), Battery),
    Battery >= 200,
    findall(A, ( member(T, Terms), term_symbol(T, A) ), As0),
    sort(As0, As),
    length(As, Symbols),
    Symbols >= 1500.

:- end_tests(writer_c).
