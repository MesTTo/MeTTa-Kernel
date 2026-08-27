% Purpose: generate MeTTa terms and check the engine's own laws over them.
%     The Python side has hypothesis and the define fuzzer, and both reach the
%     engine through janus, so nothing generated at the Prolog level, where the
%     vocabulary is different: partial terms, shared variables, operator-free
%     reader forms, spellings outside ASCII, and sread/2 with swrite/2 as a
%     roundtrip law.
%
%     ADOPTED, not written. The runner, the shrinker and the arbitrary/2
%     extension point are Michael Hendricks' quickcheck 0.3.0, vendored under
%     vendor/ with its provenance and its public-domain licence. What is here
%     is the part quickcheck cannot supply: what a MeTTa term IS, what the
%     engine promises about one, and a seed so a gate does not flake.
%
%     Three laws, each one already stated somewhere in this tree over a fixed
%     corpus and re-stated here over generated values:
%
%       roundtrip     engine/parser.pl's header promises swrite/2 and sread/2 are
%                     inverse. tests/prolog/suites/reader/parser.plt checks six hand-written
%                     terms. This checks the same law over generated ones.
%       symbol text   metta_symbol_writable/1 is supposed to answer EXACTLY
%                     which spellings survive the text seam. parser.plt checks
%                     34 spellings someone wrote down; this generates them.
%       translation   tests/prolog/translation_determinism.pl rejects any form
%                     in the SHIPPED corpus with more than one translation.
%                     This asks the same question of generated forms, with the
%                     head drawn from translator:translate_special_dl/5's own clause heads
%                     so the special-form dispatch is where the generator aims.
%
%     A green property run means nothing unless the generator generates
%     something that could go red, so five PLANTS stand in for five defects,
%     each one caught only if the generator produces a particular feature:
%     a string holding a quote, a SHARED variable, a symbol outside ASCII, a
%     number, and a nested expression. property_lane_selftest/0 requires every
%     plant to be caught and the shipped pair not to be, which is the same
%     shape as translator_confluence.pl's five planted rule sets and
%     reachability.pl's eleven mutations.
% Assumes:
%     - the working directory is tests/prolog, which is where check.sh runs
%       every Prolog lane from.
%     - the engine is already consulted into `user` when a law RUNS. Nothing
%       here calls an engine predicate at load time, so the load order between
%       this file and engine/metta.pl does not matter.
%     - library(random)'s generator is process-global and set_random/1 seeds
%       it, so seeding once before a quickcheck/1 call fixes that call's whole
%       sequence [source: SWI-Prolog 10.1 Reference Manual 4.35, set_random/1].
%     - quickcheck:arbitrary/2 and quickcheck:shrink/3 are multifile, which is
%       the pack's own extension point [source: vendor/quickcheck.pl].
% Guarantees:
%     - a gate run is deterministic: the seed and the test count are fixed
%       constants unless METTA_PROPERTY_SEED or METTA_PROPERTY_TESTS override
%       them [tested: property_lane_determinism].
%     - property_lane_selftest/0 fails unless each of the five plants is caught
%       and the shipped printer and reader are not, so "100 tests OK" cannot
%       come from a generator that generates nothing
%       [tested: test_a_prolog_property_lane_catches_a_planted_roundtrip_violation].
%     - the roundtrip law's domain is the engine's own answer to "can this term
%       cross as text", metta_unwritable_symbol/2, rather than a second copy of
%       the rule kept here. A term the service passes and the round trip loses
%       is a defect in the service, and that is how the non-finite float
%       finding surfaced; the symbol law treats swrite/2's explicit refusal as
%       the negative half of that contract [tested: parser_number_text,
%       property_lane_laws; commit=c1eaa36c7a2089801fe9da3cbec3fc02833d66fe].
% Decides:
%     - the gate seed is 20260819 and the gate runs 100 cases per law, which is
%       quickcheck's own default. Widening locally is
%       `METTA_PROPERTY_TESTS=10000 swipl -g run_tests -t halt property.plt`,
%       and METTA_PROPERTY_SEED=random draws a fresh seed per run.
%     - generated terms are at most 3 deep and 4 wide. Depth is what costs, and
%       the laws here are about the reader, the writer and the special-form
%       dispatch, none of which has a rule that only fires below depth 3.
% Open Obligations:
%     To Do: None
%     Hacks: None
%     Future Enhancements: None

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/vendor', Vendor),
   asserta(user:file_search_path(library, Vendor)).

:- use_module(library(quickcheck)).
:- use_module(library(random)).
:- use_module(library(settings), [set_setting/2]).
:- use_module(library(apply), [maplist/2, maplist/3]).
:- use_module(library(solution_sequences)).   %findnsols/4

%No library(yall). Two reasons, both measured 2026-08-19 rather than assumed.
%A `>>` lambda with no Free declaration is COPIED before the call, so the
%three-variable pool the term generator threads through maplist/2 arrived
%renamed at every child and no two leaves could ever share a variable: the
%unnumbered_variable plant below went uncaught, which is precisely the failure
%that plant exists to report. And importing yall into `user` beside the engine
%warns `Local definition of user:(/)/3 overrides weak import from yall`, the
%engine's own division being that name. Every generator here takes its output
%last instead, so maplist/2 and maplist/3 partially apply it directly.

%%%%%%%%%% Seeding, which is what keeps a gate from flaking %%%%%%%%%%

% quickcheck has no seed of its own; it draws from library(random), whose
% generator is process-global. So one set_random/1 before the call fixes the
% whole call, and the wrapper is the whole mechanism.
property_seed(Seed) :-
    (   getenv('METTA_PROPERTY_SEED', Text)
    ->  (   Text == random
        ->  Seed = random
        ;   atom_number(Text, Seed)
        )
    ;   Seed = 20260819
    ).

property_test_count(Count) :-
    (   getenv('METTA_PROPERTY_TESTS', Text)
    ->  atom_number(Text, Count)
    ;   Count = 100
    ).

%Run one property under the gate's seed and count. Compiling a MeTTa form
%prints the clause it produced unless the session is silent, and a law that
%translates 100 generated forms would print 100 of them into the test log;
%asserta so the silence wins over an already-asserted silent(false), which is
%engine/metta.pl's own idiom for the prelude.
property_check(Property) :-
    property_seed(Seed),
    (   Seed == random
    ->  set_random(seed(random))
    ;   set_random(seed(Seed))
    ),
    property_test_count(Count),
    set_setting(quickcheck:test_count, Count),
    setup_call_cleanup(asserta(silent(true), Ref),
                       quickcheck(Property),
                       erase(Ref)).

%%%%%%%%%% The alphabets %%%%%%%%%%

% ascii is where a reader defect is easiest to read in a counter-example; full
% is the alphabet the reader actually accepts, which is every code that is not
% one of the 28 token boundaries. The named singletons are the near misses
% parser.plt already pins as NOT boundaries: the four ASCII information
% separators, MONGOLIAN VOWEL SEPARATOR (White_Space until Unicode 6.3.0),
% ZERO WIDTH SPACE and ZERO WIDTH NO-BREAK SPACE.
property_alphabet_ranges(ascii, [0x20-0x7e]).
property_alphabet_ranges(full,
    [0x20-0x7e,          % ASCII
     0xa1-0x2ff,         % Latin-1 supplement and Latin extended
     0x300-0x36f,        % combining diacritical marks
     0x370-0x3ff,        % Greek
     0x400-0x4ff,        % Cyrillic
     0x5d0-0x5ea,        % Hebrew
     0x600-0x6ff,        % Arabic
     0x900-0x97f,        % Devanagari
     0x4e00-0x4eff,      % CJK unified ideographs
     0x1f300-0x1f5ff,    % astral plane, above the basic multilingual plane
     0x1c-0x1f, 0x180e-0x180e, 0x200b-0x200b, 0xfeff-0xfeff]).

property_alphabet_code(Alphabet, Code) :-
    property_alphabet_ranges(Alphabet, Ranges),
    random_member(Low-High, Ranges),
    random_between(Low, High, Code).

%What a SYMBOL may hold: no token boundary, because one would split it, and no
%quote, because the top-level form scanner opens a string on one.
property_symbol_code(Alphabet, Code) :-
    property_alphabet_code(Alphabet, Code0),
    (   \+ metta_token_boundary(Code0, _), Code0 =\= 0'"
    ->  Code = Code0
    ;   property_symbol_code(Alphabet, Code)
    ).

%What a STRING may hold, which is anything at all: a literal ends at its
%closing quote and nowhere else, so every boundary character inside one is
%data. The five escapes get a third of the draws because they are where the
%writer has a rule.
property_string_code(Alphabet, Code) :-
    random_between(1, 10, Draw),
    (   Draw =< 3
    ->  random_member(Code, [0'", 0'\\, 0'\n, 0'\t, 0'\r])
    ;   Draw =< 5
    ->  findall(Boundary, metta_token_boundary(Boundary, _), Boundaries),
        random_member(Code, Boundaries)
    ;   property_alphabet_code(Alphabet, Code)
    ).

%%%%%%%%%% The generators %%%%%%%%%%

% A symbol the seam can carry. The retry is bounded rather than a loop: a
% spelling that reads back as something else gets one non-reserved character in
% front of it, and a name that is one token, holds no quote and does not start
% with $ . - + or a digit can only fail metta_symbol_writable/1 by being True
% or False, which `a` in front also fixes.
property_symbol(Alphabet, Symbol) :-
    random_between(1, 8, Length),
    length(Codes, Length),
    maplist(property_symbol_code(Alphabet), Codes),
    atom_codes(Candidate, Codes),
    (   metta_symbol_writable(Candidate)
    ->  Symbol = Candidate
    ;   atom_concat(a, Candidate, Symbol)
    ).

%A spelling, writable or not, which is what the writability law needs: a law
%that only ever saw writable names would check one half of an if-and-only-if.
%The named spellings are the classes parser.plt found by hand, drawn often
%enough that the boundary itself is generated rather than hoped for.
property_spelling(Alphabet, Spelling) :-
    random_between(1, 10, Draw),
    (   Draw =< 3
    ->  random_member(Spelling, ['', 'True', 'False', '$x', '42', '-3', '1.5',
                                 'a b', 'a(b', 'a)b', 'a;b', 'a"b', '+', '-',
                                 '.', '0x1f', '5.', '1e'])
    ;   random_between(0, 8, Length),
        length(Codes, Length),
        maplist(property_alphabet_code(Alphabet), Codes),
        atom_codes(Spelling, Codes)
    ).

% Numbers, INCLUDING the ones whose printed form does not read back. SWI writes
% a non-finite float as 1.0Inf, -1.0Inf or 1.5NaN and a rational as 1r3, and
% the reader's number grammar accepts none of the four, so each comes back as a
% symbol. MeTTa arithmetic cannot make one here (float_overflow, float_zero_div
% and float_undefined are all `error` and prefer_rationals is false), but
% `(py-atom "float('inf')")` answers 1.0Inf, so the class is reachable and the
% generator draws it rather than pretending it does not exist.
property_number(Number) :-
    random_member(Kind, [small, small, small, large, float, float, exotic]),
    (   Kind == small
    ->  random_between(-1000, 1000, Number)
    ;   Kind == large
    ->  random_between(-1000000000000000000000, 1000000000000000000000, Number)
    ;   Kind == float
    ->  random_between(-100000, 100000, Whole), random(Fraction),
        Number is Whole * Fraction
    ;   random_member(Exotic, [infinite, negative_infinite, undefined, ratio]),
        (   Exotic == infinite -> Number is inf
        ;   Exotic == negative_infinite -> Number is -inf
        ;   Exotic == undefined -> Number is nan
        ;   random_between(1, 100, Top), random_between(2, 100, Bottom),
            Number is Top rdiv Bottom
        )
    ).

property_string(Alphabet, String) :-
    random_between(0, 10, Length),
    length(Codes, Length),
    maplist(property_string_code(Alphabet), Codes),
    string_codes(String, Codes).

% A term, over a pool of three variables so the same variable can occur twice.
% Sharing is the half of the reader's variable handling a fixed corpus keeps
% missing: `(pair $x $y)` and `(pair $x $x)` are the same shape and different
% laws, and only the second one catches a writer that stopped numbering.
property_term(Alphabet, Term) :-
    length(Pool, 3),
    property_term(Alphabet, Pool, 3, Term).

property_term(Alphabet, Pool, Depth, Term) :-
    (   Depth =< 0
    ->  property_leaf(Alphabet, Pool, Term)
    ;   random_between(1, 10, Draw),
        (   Draw =< 6
        ->  property_leaf(Alphabet, Pool, Term)
        ;   random_between(0, 4, Width),
            Shallower is Depth - 1,
            length(Term, Width),
            maplist(property_term(Alphabet, Pool, Shallower), Term)
        )
    ).

property_leaf(Alphabet, Pool, Term) :-
    random_member(Kind, [symbol, symbol, number, string, variable]),
    (   Kind == symbol -> property_symbol(Alphabet, Term)
    ;   Kind == number -> property_number(Term)
    ;   Kind == string -> property_string(Alphabet, Term)
    ;   random_member(Term, Pool)
    ).

% A form for the translator laws. The head comes from translator:translate_special_dl/5's
% own clause heads half the time, because that dispatch is where a second
% translation would hide; the other half is an ordinary symbol, which is the
% data path.
property_form(Form) :-
    property_form(2, Form).

property_form(Depth, Form) :-
    (   Depth =< 0
    ->  property_form_leaf(Form)
    ;   random_between(1, 10, Draw),
        (   Draw =< 4
        ->  property_form_leaf(Form)
        ;   property_form_head(Head),
            random_between(0, 3, Width),
            Shallower is Depth - 1,
            length(Arguments, Width),
            maplist(property_form(Shallower), Arguments),
            Form = [Head|Arguments]
        )
    ).

property_form_leaf(Leaf) :-
    random_member(Kind, [symbol, number, string, variable, empty]),
    (   Kind == symbol -> random_member(Leaf, [a, b, foo, 'my-symbol'])
    ;   Kind == number -> random_between(-5, 5, Leaf)
    ;   Kind == string -> random_member(Leaf, ["", "s"])
    ;   Kind == empty -> Leaf = []
    ;   true                                    % an unbound variable
    ).

property_form_head(Head) :-
    random_between(1, 2, Draw),
    (   Draw =:= 1
    ->  property_special_forms(Specials), random_member(Head, Specials)
    ;   random_member(Head, [a, b, foo, 'my-symbol'])
    ).

property_special_forms(Specials) :-
    findall(Name,
            ( clause(translator:translate_special_dl(Name, _, _, _, _), _), atom(Name) ),
            Names),
    sort(Names, Specials).

property_equation([=, [Function|Arguments], Body]) :-
    random_member(Function, [f, g, 'my-function']),
    random_between(0, 2, Arity),
    length(Arguments, Arity),
    maplist(property_form(1), Arguments),
    property_form(2, Body).

%%%%%%%%%% The quickcheck types %%%%%%%%%%

quickcheck:arbitrary(metta_term(Alphabet), Term) :- property_term(Alphabet, Term).
quickcheck:arbitrary(metta_number, Number) :- property_number(Number).
quickcheck:arbitrary(metta_spelling(Alphabet), Spelling) :- property_spelling(Alphabet, Spelling).
quickcheck:arbitrary(metta_form, Form) :- property_form(Form).
quickcheck:arbitrary(metta_equation, Equation) :- property_equation(Equation).

% Shrinking, so a counter-example is one a reader can act on. Each clause makes
% the value strictly smaller and FAILS when it cannot, which is what the pack's
% loop needs to stop.
quickcheck:shrink(metta_term(_), Term, Smaller) :- property_smaller(Term, Smaller).
quickcheck:shrink(metta_form, Form, Smaller) :- property_smaller(Form, Smaller).
quickcheck:shrink(metta_equation, [=, Head, Body], [=, Head, Smaller]) :-
    property_smaller(Body, Smaller).
quickcheck:shrink(metta_spelling(_), Spelling, Smaller) :-
    atom(Spelling), atom_codes(Spelling, Codes), Codes \== [],
    select(_, Codes, Fewer),
    atom_codes(Smaller, Fewer).

property_smaller(Term, []) :- is_list(Term), Term \== [].
property_smaller(Term, Element) :- is_list(Term), member(Element, Term).
property_smaller(Term, Smaller) :-
    is_list(Term), select(_, Term, Smaller), Smaller \== Term.
property_smaller(Term, 0) :- number(Term), Term \== 0, Term =:= Term.
property_smaller(Term, "") :- string(Term), Term \== "".
property_smaller(Term, Smaller) :-
    atom(Term), atom_codes(Term, Codes), Codes \== [],
    select(_, Codes, Fewer), Fewer \== [],
    atom_codes(Smaller, Fewer),
    metta_symbol_writable(Smaller).

%%%%%%%%%% The plants %%%%%%%%%%

% Which printer and reader the laws use. A plant is installed around a run and
% taken out again, so the laws themselves never know they are being tested,
% which is what makes the selftest a test OF THE GENERATOR rather than of a
% second copy of the laws.
:- dynamic property_planted/1.

property_plant(Plant) :-
    ( property_planted(Installed) -> Plant = Installed ; Plant = shipped ).

property_with_plant(Plant, Goal) :-
    setup_call_cleanup(asserta(property_planted(Plant), Ref), Goal, erase(Ref)).

% Every plant, and the one generator feature each one needs in order to be
% caught. This table is the anti-vacuity claim written down: a plant that stops
% being caught names the feature the generator stopped producing.
property_plant_feature(unescaped_quote,     'a string holding a quote').
property_plant_feature(unnumbered_variable, 'a variable occurring twice').
property_plant_feature(ascii_folded,        'a symbol outside ASCII').
property_plant_feature(number_blind,        'a number').
property_plant_feature(flattened_nesting,   'a nested expression').

property_print(Term, Text) :-
    property_plant(Plant),
    swrite(Term, Shipped),
    (   property_printer_damage(Plant, Shipped, Text)
    ->  true
    ;   Text = Shipped
    ).

property_read(Text, Term) :-
    property_plant(Plant),
    sread(Text, Read),
    (   property_reader_damage(Plant, Read, Term)
    ->  true
    ;   Term = Read
    ).

%A writer that forgot one of its five escapes. `"a\"b"` goes out as `"a"b"`,
%which the reader ends at the second quote.
property_printer_damage(unescaped_quote, Shipped, Damaged) :-
    string_codes(Shipped, Codes),
    property_drop_quote_escapes(Codes, Fewer),
    string_codes(Damaged, Fewer).
%A writer that stopped numbering variables, so every one prints as $_. Two
%DISTINCT variables survive that, because $_ reads fresh each time; a variable
%that occurred twice does not.
property_printer_damage(unnumbered_variable, Shipped, Damaged) :-
    string_codes(Shipped, Codes),
    property_strip_variable_index(Codes, Stripped),
    string_codes(Damaged, Stripped).
%A writer that assumed ASCII, which is the defect the Unicode boundary table
%replaced in the reader.
property_printer_damage(ascii_folded, Shipped, Damaged) :-
    string_codes(Shipped, Codes),
    maplist(property_fold_to_ascii, Codes, Folded),
    string_codes(Damaged, Folded).

property_fold_to_ascii(Code, Folded) :-
    ( Code > 127 -> Folded = 0'? ; Folded = Code ).

%A reader that did not recognise a number token and left it a symbol. This is
%the shape of the real finding: a non-finite float printed by swrite/2 comes
%back as an atom, and that is this plant happening for real.
property_reader_damage(number_blind, Read, Damaged) :-
    property_numbers_to_symbols(Read, Damaged).
%A reader that lost a level of nesting.
property_reader_damage(flattened_nesting, Read, Damaged) :-
    property_flatten_once(Read, Damaged).

property_drop_quote_escapes([], []).
property_drop_quote_escapes([0'\\, 0'"|Rest], [0'"|Fewer]) :- !,
    property_drop_quote_escapes(Rest, Fewer).
property_drop_quote_escapes([Code|Rest], [Code|Fewer]) :-
    property_drop_quote_escapes(Rest, Fewer).

property_strip_variable_index([], []).
property_strip_variable_index([0'$, 0'_|Rest], [0'$, 0'_|Stripped]) :- !,
    property_skip_digits(Rest, Tail),
    property_strip_variable_index(Tail, Stripped).
property_strip_variable_index([Code|Rest], [Code|Stripped]) :-
    property_strip_variable_index(Rest, Stripped).

property_skip_digits([Code|Rest], Tail) :- code_type(Code, digit), !,
    property_skip_digits(Rest, Tail).
property_skip_digits(Codes, Codes).

property_numbers_to_symbols(Term, Symbol) :-
    number(Term), !, number_codes(Term, Codes), atom_codes(Symbol, Codes).
property_numbers_to_symbols(Term, Mapped) :-
    is_list(Term), !, maplist(property_numbers_to_symbols, Term, Mapped).
property_numbers_to_symbols(Term, Term).

property_flatten_once(Term, Flattened) :-
    is_list(Term),
    append(Before, [Inner|After], Term),
    is_list(Inner),
    !,
    append(Before, Inner, Front),
    append(Front, After, Flattened).
property_flatten_once(Term, Term).

%%%%%%%%%% The laws %%%%%%%%%%

% A term the text seam accepts is a term the text seam gives back. The domain
% is metta_unwritable_symbol/2, the engine's OWN published answer to "can this
% cross as text", rather than a second copy of the rule kept here: a term the
% service passes and the round trip loses is then a defect in the service,
% which is exactly how the non-finite float class surfaced.
property_roundtrip(Term) :-
    (   metta_unwritable_symbol(Term, _)
    ->  true
    ;   property_print(Term, Text),
        property_read(Text, Back),
        Back =@= Term
    ).

% metta_symbol_writable/1 says which spellings survive the seam, and the seam
% is parse_metta_source/2 rather than sread/2 alone: the top-level form scanner
% tracks a string state sread/2 never sees, and a quote inside a symbol
% swallowed the rest of the form there while sread/2 read it back intact.
%
% SOUND always, and COMPLETE except for names holding a quote. Rejecting every
% quote is a deliberate shortcut for cost, and engine/parser.pl says so where it
% makes it: the form scanner opens a string on a quote, and answering exactly
% would mean running that scanner over every symbol a save carries, which the
% one-token scan exists to avoid. So a name with an EVEN number of quotes, none
% of them first and no token boundary between a pair, does read back and is
% refused anyway: `%""`, `a""b`, `a"b"c` [measured 2026-08-19, found by this
% law at 20,000 cases]. Over-strict at a text seam is the safe direction, a
% spurious refusal rather than a value that comes back different, so the class
% is named and excluded here rather than paid for in the engine. What must not
% weaken is the other direction, and property_a_quoted_spelling_can_read_back/0
% below keeps the exclusion from quietly growing.
property_symbol_text_agrees(Spelling) :-
    (   metta_symbol_writable(Spelling)
    ->  property_symbol_reads_back(Spelling)
    ;   sub_atom(Spelling, _, _, _, '"')
    ->  true
    ;   \+ property_symbol_reads_back(Spelling)
    ).

%The excluded class is real and is exactly one class: a quote-holding spelling
%that DOES read back exists, so the exclusion above is not a blanket that would
%hide a growing hole [tested: property_lane_laws].
property_a_quoted_spelling_can_read_back :-
    property_symbol_reads_back('%""'),
    \+ metta_symbol_writable('%""').

property_symbol_reads_back(Spelling) :-
    catch(swrite([holds, Spelling], Text),
          error(metta_unwritable_text(_), _),
          fail),
    catch(parse_metta_source(Text, Forms), _, fail),
    Forms = [parsed(_, _, Back)],
    Back == [holds, Spelling].

% parser:metta_number_writable/1 answers an integer and a float without running the
% reader, because every save and every digest asks it of every number carried
% and the grammar scan cost +36.8% on a 20,000-atom digest where the two
% shortcuts cost +1.89% [measured 2026-08-19]. A shortcut is a second rule
% about spelling unless something holds it to the first one, so this is that:
% the answer the shortcut gives and the answer the grammar gives are the same
% answer, over generated numbers rather than over a list someone wrote down.
property_number_shortcut(Number) :-
    ( parser:metta_number_writable(Number) -> Shortcut = true ; Shortcut = false ),
    (   catch(( number_codes(Number, Codes),
                phrase(parser:sexpr_token(Read, [], _), Codes),
                Read == Number ), _, fail)
    ->  Grammar = true
    ;   Grammar = false
    ),
    Shortcut == Grammar.

% The translator is a function. tests/prolog/translation_determinism.pl states
% this over every shipped example and fails the gate on a second solution; this
% asks it of forms nobody wrote. The inference limit is a guard rather than a
% law: a translation that needs two million inferences is not a second
% translation, it is a different report, and it has never fired.
property_one_translation(Goal, Witness) :-
    findnsols(2, Witness,
              catch(call_with_inference_limit(Goal, 2000000, _), _, fail),
              Solutions),
    !,
    Solutions \= [_, _].

property_translate_expr_is_a_function(Form) :-
    property_one_translation(translate_expr(Form, Goals, Out), Goals-Out).

property_translate_clause_is_a_function(Equation) :-
    property_one_translation(translate_clause(Equation, Clause), Clause).

%%%%%%%%%% The properties quickcheck runs %%%%%%%%%%

prop_roundtrip_ascii(Term:metta_term(ascii)) :- property_roundtrip(Term).
prop_roundtrip_full(Term:metta_term(full)) :- property_roundtrip(Term).
prop_symbol_text_ascii(Spelling:metta_spelling(ascii)) :- property_symbol_text_agrees(Spelling).
prop_symbol_text_full(Spelling:metta_spelling(full)) :- property_symbol_text_agrees(Spelling).
prop_number_shortcut(Number:metta_number) :- property_number_shortcut(Number).
prop_translate_expr(Form:metta_form) :- property_translate_expr_is_a_function(Form).
prop_translate_clause(Equation:metta_equation) :- property_translate_clause_is_a_function(Equation).

%%%%%%%%%% The selftest %%%%%%%%%%

% Every plant caught, the shipped pair not. Run as
% `swipl -q -g property_lane_selftest -t 'halt(0)' property_lane.pl` from
% tests/prolog, which is how check.sh runs every other selftest here.
property_lane_selftest :-
    consult('../../engine/metta.pl'),
    findall(Plant-Verdict,
            ( property_plant_feature(Plant, _),
              property_plant_verdict(Plant, Verdict) ),
            Verdicts),
    property_plant_verdict(shipped, Shipped),
    forall(member(Plant-Verdict, Verdicts),
           ( property_plant_feature(Plant, Feature),
             format("plant ~w (~w): ~w~n", [Plant, Feature, Verdict]) )),
    format("shipped printer and reader: ~w~n", [Shipped]),
    findall(Plant, member(Plant-uncaught, Verdicts), Missed),
    length(Verdicts, Count),
    (   Missed == [], Shipped == uncaught
    ->  format("property lane selftest: ~d plants, each caught, and the \c
                shipped pair clean~n", [Count])
    ;   forall(member(Plant, Missed),
               ( property_plant_feature(Plant, Feature),
                 format("plant ~w was NOT caught, so the generator stopped \c
                         producing ~w~n", [Plant, Feature]) )),
        (   Shipped == caught
        ->  format("the shipped printer and reader failed the law, which is \c
                    a defect rather than a selftest result~n", [])
        ;   true ),
        halt(1) ).

% One run of the roundtrip law under one printer and reader pair. `caught` is
% quickcheck throwing its counter-example, which for a plant is the wanted
% outcome and for the shipped pair is a defect.
property_plant_verdict(Plant, Verdict) :-
    (   property_with_plant(Plant,
                            catch(property_check(prop_roundtrip_full/1), _, fail))
    ->  Verdict = uncaught
    ;   Verdict = caught
    ).
