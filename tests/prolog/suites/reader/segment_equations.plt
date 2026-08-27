% Purpose: pin sequence variables in equation heads through compiled and
%   variable-headed dynamic calls.
% Assumes: run from tests/prolog, which is what check.sh does; the relative
%   engine path resolves against that directory.
% Guarantees:
%   - nested and empty captures project as expressions
%   - `(:seg $x)` in a body splices while ordinary `$x` projects one expression
%   - a top-level segment changes call arity, and every split is shortest-first
%   - ordinary overlapping rules remain additive
%   - one name can occur in segment and ordinary roles in an equation head
%   - the compiled and variable-headed dynamic doors answer alike
%   [source: LeaTTa MettaHyperonFull/Core/SeqOneSided.lean:65-89 and
%   MettaHyperonFull/Core/SeqSyntax.lean:300-314; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../../../engine/metta.pl').

segment_source(Source, Answers) :-
    with_output_to(string(_), process_metta_string(Source, Answers)).

segment_equation_term(Name, Term) :-
    metta_host_stored('&self', Term),
    Term = [=, [Head|_], _],
    nonvar(Head),
    Head == Name.

forget_segment_function(Name) :-
    findall(Term, segment_equation_term(Name, Term), Terms),
    forall(member(Term, Terms), metta_remove_atom('&self', Term, _)),
    findall(Declaration,
            ( metta_host_stored('&self', Declaration),
              Declaration = [':', Head, _],
              nonvar(Head),
              Head == Name ),
            Declarations),
    forall(member(Declaration, Declarations),
           metta_remove_atom('&self', Declaration, _)).

:- begin_tests(segment_equations).

test(nested_and_zero_length_segments_project_as_expressions,
     [ cleanup(( forget_segment_function('pl-seg-nested'),
                 forget_segment_function('pl-seg-zero') )) ]) :-
    segment_source(
        "(: pl-seg-nested (-> Atom Atom))\n\c
         (= (pl-seg-nested (outer (inner left (:seg $xs) right) tail)) $xs)\n\c
         (: pl-seg-zero (-> Atom Atom))\n\c
         (= (pl-seg-zero (head (:seg $xs) tail)) $xs)", _),
    segment_source("!(pl-seg-nested (outer (inner left a b right) tail))",
                   [[a, b]]),
    segment_source("!(pl-seg-zero (head tail))", [[]]).

test(a_written_rhs_segment_splices_its_bound_run,
     [ cleanup(forget_segment_function('pl-seg-splice')) ]) :-
    segment_source(
        "(: pl-seg-splice (-> Atom Atom))\n\c
         (= (pl-seg-splice (head (:seg $xs) tail))\n\c
            (rebuilt before (:seg $xs) after))", _),
    segment_source("!(pl-seg-splice (head a b tail))",
                   [[rebuilt, before, a, b, after]]).

test(top_level_segment_accepts_zero_arguments_and_wider_arities,
     [ cleanup(forget_segment_function('pl-seg-all')) ]) :-
    segment_source(
        "(: pl-seg-all (-> (%Rest% Atom) Atom))\n\c
         (= (pl-seg-all (:seg $xs)) (quote $xs))", _),
    segment_source("!(pl-seg-all)", [[quote, []]]),
    segment_source("!(pl-seg-all a)", [[quote, [a]]]),
    segment_source("!(pl-seg-all a b)", [[quote, [a, b]]]).

test(two_segments_enumerate_splits_shortest_first,
     [ cleanup(forget_segment_function('pl-seg-split')) ]) :-
    segment_source(
        "(: pl-seg-split (-> Atom Atom))\n\c
         (= (pl-seg-split (row (:seg $before) SEP (:seg $after)))\n\c
            (quote (pair $before $after)))", _),
    segment_source("!(pl-seg-split (row a SEP b SEP c))", Answers),
    assertion(Answers == [[quote, [pair, [a], [b, 'SEP', c]]],
                          [quote, [pair, [a, 'SEP', b], [c]]]]).

test(segment_and_ordinary_rules_remain_additive_in_source_order,
     [ cleanup(forget_segment_function('pl-seg-overlap')) ]) :-
    segment_source(
        "(: pl-seg-overlap (-> Atom Atom))\n\c
         (= (pl-seg-overlap (row (:seg $xs))) segment-branch)\n\c
         (= (pl-seg-overlap $leaf) ordinary-branch)", _),
    segment_source("!(collapse (pl-seg-overlap (row a b)))",
                   [['segment-branch', 'ordinary-branch']]).

test(a_segment_name_projects_in_an_ordinary_head_position,
     [ cleanup(forget_segment_function('pl-seg-mixed')) ]) :-
    segment_source(
        "(: pl-seg-mixed (-> Atom Atom))\n\c
         (= (pl-seg-mixed ((:seg $xs) tag $xs)) yes)", _),
    segment_source("!(pl-seg-mixed (a b tag (a b)))", [yes]),
    segment_source("!(pl-seg-mixed (tag ()))", [yes]),
    segment_source("!(pl-seg-mixed (a b tag (a c)))",
                   [['pl-seg-mixed', [a, b, tag, [a, c]]]]).

test(the_compiled_and_variable_headed_doors_answer_alike,
     [ cleanup(forget_segment_function('pl-seg-doors')) ]) :-
    segment_source(
        "(: pl-seg-doors (-> Atom Atom))\n\c
         (= (pl-seg-doors (row (:seg $before) SEP (:seg $after)))\n\c
            (quote (pair $before $after)))", _),
    segment_source("!(pl-seg-doors (row a SEP b SEP c))", Compiled),
    segment_source("!(let $f pl-seg-doors ($f (row a SEP b SEP c)))",
                   Dynamic),
    assertion(Dynamic == Compiled).

test(the_reference_stratego_one_rule_rebuilds_the_successful_child,
     [ cleanup(( forget_segment_function('pl-seg-child'),
                 forget_segment_function('pl-seg-one') )) ]) :-
    segment_source(
        "(: pl-seg-child (-> Atom Atom))\n\c
         (= (pl-seg-child b) B)\n\c
         (= (pl-seg-child $x) Empty)\n\c
         (: pl-seg-one (-> Atom Atom Atom))\n\c
         (= (pl-seg-one $strategy ((:seg $before) $child (:seg $after)))\n\c
            (function\n\c
              (chain (metta ($strategy $child) %Undefined% &self) $child-result\n\c
                (return ((:seg $before) $child-result (:seg $after))))))\n\c
         (= (pl-seg-one $strategy $leaf) Empty)", _),
    segment_source("!(collapse (pl-seg-one pl-seg-child (a b c)))",
                   [[[a, 'B', c]]]).

:- end_tests(segment_equations).
