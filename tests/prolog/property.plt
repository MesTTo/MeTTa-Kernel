% Purpose: the Prolog-native property lane, run under plunit so check.sh's
%   `plunit` gate picks it up with every other suite and runs it in both
%   configurations the engine ships in.
%
%   Everything it needs is in property_lane.pl beside it: the generators, the
%   laws, the five plants and the seed. This file is the plunit surface, one
%   test per law plus the anti-vacuity block, so a failure names the law rather
%   than naming "the property lane".
%
%   Run one suite on its own:
%     swipl -g run_tests -t halt property.plt
%   Widen locally, which the gate deliberately does not do:
%     METTA_PROPERTY_TESTS=10000 swipl -g run_tests -t halt property.plt
%     METTA_PROPERTY_SEED=random swipl -g run_tests -t halt property.plt
% Guarantees:
%   - a failing law throws quickcheck's counter_example carrying the shrunken
%     value, so the test output names the term that broke it rather than only
%     the law that broke.
%   - the run is the same run every time under the gate's own environment
%     [tested: property_lane_determinism].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

% property_lane.pl is loaded as a directive rather than through
% initialization/1, so its path resolves against THIS file's directory instead
% of against whatever the working directory happens to be at run time. Nothing
% in it calls an engine predicate at load time, so it can go first.
:- ensure_loaded(property_lane).

% The engine through metta.pl, not main.pl, whose initialization(main, main)
% fires on consult and prints its demo into the test output.
:- ensure_loaded('../../engine/metta.pl').

:- begin_tests(property_lane_laws).

% engine/parser.pl's header promises swrite/2 and sread/2 are inverse.
% tests/prolog/parser.plt checks six terms someone wrote down.
test(the_text_round_trip_is_inverse_over_generated_ascii_terms) :-
    property_check(prop_roundtrip_ascii/1).

% And over the alphabet the reader actually accepts, which is every code that
% is not one of the 28 token boundaries: Greek, Cyrillic, Hebrew, Arabic,
% Devanagari, CJK, combining marks, the astral plane, and the four near misses
% parser.plt pins as NOT boundaries.
test(the_text_round_trip_is_inverse_over_the_readers_whole_alphabet) :-
    property_check(prop_roundtrip_full/1).

% metta_symbol_writable/1 is supposed to answer EXACTLY which spellings survive
% the seam, so both halves of the if-and-only-if are checked: a spelling it
% accepts reads back, and a spelling it rejects does not.
test(writability_says_exactly_what_reads_back_over_generated_ascii_spellings) :-
    property_check(prop_symbol_text_ascii/1).

test(writability_says_exactly_what_reads_back_over_the_whole_alphabet) :-
    property_check(prop_symbol_text_full/1).

% parser:metta_number_writable/1 answers an integer and a float without running the
% reader, because a save asks it of every number it carries. The shortcut has
% to give the grammar's own answer.
test(the_number_shortcuts_give_the_grammars_answer) :-
    property_check(prop_number_shortcut/1).

% tests/prolog/translation_determinism.pl rejects any form in the SHIPPED
% corpus with more than one Prolog translation. These ask it of forms nobody
% wrote, with the head drawn from translator:translate_special_dl/5's own clause heads.
test(a_generated_expression_has_at_most_one_translation) :-
    property_check(prop_translate_expr/1).

test(a_generated_equation_has_at_most_one_translation) :-
    property_check(prop_translate_clause/1).

:- end_tests(property_lane_laws).


% "100 tests OK" means nothing unless the generator generates something that
% could have gone red, so five planted defects stand in for five real ones and
% each is caught only if the generator produces one particular feature. A plant
% that stops being caught names the feature that stopped being generated, which
% is the same shape as translator_confluence.pl's five planted rule sets and
% reachability.pl's eleven mutations.

:- begin_tests(property_lane_plants).

test(every_plant_is_caught, [forall(property_plant_feature(Plant, _))]) :-
    property_plant_verdict(Plant, caught).

test(the_shipped_printer_and_reader_pass_the_law) :-
    property_plant_verdict(shipped, uncaught).

:- end_tests(property_lane_plants).


:- begin_tests(property_lane_determinism).

% quickcheck draws from library(random), whose generator is process-global and
% unseeded by the pack, so a gate running it would flake. One set_random/1
% before the call is the whole mechanism, and this is the check that it works.
generated_terms(Terms) :-
    set_random(seed(20260819)),
    findall(Term, ( between(1, 50, _), property_term(full, Term) ), Terms).

test(the_same_seed_generates_the_same_terms) :-
    generated_terms(First),
    generated_terms(Second),
    First =@= Second.

test(a_different_seed_generates_different_terms) :-
    generated_terms(First),
    set_random(seed(20260820)),
    findall(Term, ( between(1, 50, _), property_term(full, Term) ), Second),
    First \=@= Second.

% The gate's own numbers, unless the environment overrides them, in which case
% the override is the thing under test and the default is not.
test(the_gate_runs_a_fixed_seed_and_a_fixed_count) :-
    ( getenv('METTA_PROPERTY_SEED', _) -> true ; property_seed(20260819) ),
    ( getenv('METTA_PROPERTY_TESTS', _) -> true ; property_test_count(100) ).

test(the_environment_widens_the_run) :-
    setup_call_cleanup(
        ( ( getenv('METTA_PROPERTY_TESTS', Saved) -> true ; Saved = none ),
          setenv('METTA_PROPERTY_TESTS', '7') ),
        property_test_count(Count),
        ( Saved == none
          -> unsetenv('METTA_PROPERTY_TESTS')
          ;  setenv('METTA_PROPERTY_TESTS', Saved) )),
    Count == 7.

:- end_tests(property_lane_determinism).
