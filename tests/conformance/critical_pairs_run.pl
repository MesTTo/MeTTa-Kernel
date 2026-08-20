% Purpose: run this repository's critical-pair enumerator over a corpus of
%   rewrite systems and print each system's pairs and verdicts in a form a
%   comparator can diff against another implementation's. The other
%   implementation is MeTTaILProofs/CPExecutable.lean, whose enumerator is
%   kernel-checked, so agreement on a corpus is what turns "our enumerator
%   runs" into "our enumerator computes the same family".
% Assumes:
%   - argv carries `--corpus <path>`, a file of `system(Name, Rules)` facts
%     with rules written L ==> R and Prolog variables for term variables.
%   - the corpus holds no rule with a right-hand-side variable its left-hand
%     side does not bind. That is the Lean side's own RhsVarsInLhs hypothesis,
%     and without it the two sides answer different questions: this side treats
%     a variable a rule invented as interchangeable and that side does not.
% Guarantees:
%   - one `=== Name` line per system, then one line per critical pair holding
%     the two sides and the verdict separated by tabs, then a `### ` line
%     carrying certified or not-certified. Lines within a system are printed in
%     enumeration order; the comparator sorts, because the two enumerators
%     visit rules and positions in a different nesting and the FAMILY is what
%     is being compared, not the order.
%   - a term is written with variables numbered by first occurrence across the
%     PAIR, an application as (f a b) and a constant as its name, which is the
%     one rendering both sides can produce.
% Fails when:
%   - never silently: an unreadable corpus raises out of consult/1.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module('../../engine/trs.pl').
:- use_module(library(lists)).
:- use_module(library(apply)).

:- initialization(main, main).

:- dynamic system/2.

main :-
    current_prolog_flag(argv, Argv),
    (   append(_, ['--corpus', Corpus|_], Argv)
    ->  true
    ;   throw(error(existence_error(argument, '--corpus'), _))
    ),
    (   append(_, ['--fuel', FuelText|_], Argv)
    ->  atom_number(FuelText, Fuel)
    ;   Fuel = 5
    ),
    consult(Corpus),
    forall(system(Name, Rules), report_system(Name, Rules, Fuel)),
    halt.

report_system(Name, Rules, Fuel) :-
    format("=== ~w~n", [Name]),
    confluence_check(Rules, Fuel, Verdicts),
    forall(member(verdict(_,_,_,L,R,Verdict), Verdicts),
           ( canonical_pair(L, R, LText, RText),
             format("~w\t~w\t~w~n", [LText, RText, Verdict]) )),
    (   forall(member(V, Verdicts), V = verdict(_,_,_,_,_,joined))
    ->  format("### certified~n")
    ;   format("### not-certified~n")
    ).

% Both sides of one pair, rendered under ONE numbering, since a variable shared
% between the two sides is the whole content of a pair like (?0, ?0).
%
% confluence_check/3 numbers the peak's variables before it searches, so a pair
% arrives holding '$VAR'(N) markers rather than variables, numbered by the
% PEAK's traversal. That numbering is not the other side's, which comes from
% its own most general unifier, so both are thrown away and the markers are
% renumbered by first occurrence across the pair.
canonical_pair(L, R, LText, RText) :-
    marker_order(L, [], Seen),
    marker_order(R, Seen, Order),
    canonical_text(L, Order, LText),
    canonical_text(R, Order, RText).

marker_order(T, Seen0, Seen) :-
    (   var(T)
    ->  throw(error(type_error(numbered_term, T), _))
    ;   T = '$VAR'(N), integer(N)
    ->  (   memberchk(N, Seen0) -> Seen = Seen0 ;   append(Seen0, [N], Seen) )
    ;   compound(T)
    ->  T =.. [_|Args], foldl(marker_order, Args, Seen0, Seen)
    ;   Seen = Seen0
    ).

canonical_text(T, Order, Text) :-
    (   T = '$VAR'(N), integer(N)
    ->  nth0(I, Order, N), format(atom(Text), "?~w", [I])
    ;   compound(T)
    ->  T =.. [F|Args],
        maplist(canonical_argument(Order), Args, Texts),
        atomic_list_concat(Texts, ' ', Inner),
        format(atom(Text), "(~w ~w)", [F, Inner])
    ;   format(atom(Text), "~w", [T])
    ).

canonical_argument(Order, T, Text) :- canonical_text(T, Order, Text).
