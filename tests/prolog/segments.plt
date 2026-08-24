% Purpose: verify sequence-variable (gap) parsing, fragment classification,
%   the three certified-finite solvers, the refusal fence, and the space door,
%   against LeaTTa's own statements of the law.
% Guarantees:
%   - `...` and `(:seg $x)` parse to gaps and every other marker-shaped term
%     stays data, root included [tested: segments_parsing].
%   - the classifier answers the arbiter's own case for each fragment and
%     refuses outside them, naming the rule [tested: segments_fragments].
%   - each solver answers what the arbiter's procedure answers, including the
%     shortest-first split order and the open remainder a two-sided answer
%     keeps [tested: segments_one_sided, segments_last_position,
%     segments_linear_shallow].
%   - distinct `...` occurrences never constrain each other, a repeated named
%     gap has to take a runtime-equal run, and a repeated named gap is admitted
%     where the fragment permits one and refused where it does not
%     [tested: segments_identity, segments_last_position].
%   - a gap query reads a native store through its own arity window and its
%     head index, and a stored marker is data rather than a gap
%     [tested: segments_space_door].
%   - a gap-free pattern reaches no predicate of the gap unit at all, which is
%     what makes the feature free [tested: segments_costs_nothing].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- ensure_loaded('../../engine/metta.pl').

%Read one MeTTa term and parse it as a pattern side. Both halves matter: sread
%gives the surface the program wrote, and petta_seq_parse/2 is what decides
%which markers in it are live gaps.
parsed(Text, Parsed) :-
    sread(Text, Term),
    spaces:petta_seq_parse(Term, Parsed).

%Two sides of ONE read, so a name written on both shares its variable. Reading
%them separately is the trap: `$x` in two sreads is two variables, and the
%linearity and mixed-role rules both decide by identity.
pair(Text, Left, Right) :-
    sread(Text, [_, LeftTerm, RightTerm]),
    spaces:petta_seq_parse(LeftTerm, Left),
    spaces:petta_seq_parse(RightTerm, Right).

%Every answer of one solver, as the runs its gaps took.
runs(Case, Left, Right, Runs) :-
    findall(Left, spaces:petta_seq_unify(Case, Left, Right), Runs).

refusal(Left, Right, Message) :-
    catch(( spaces:petta_seq_classify(Left, Right, Case),
            Message = admitted(Case) ),
          error(Error, _),
          message_text(Error, Message)).

message_text(Error, Message) :-
    (   phrase(prolog:error_message(Error), Parts),
        with_output_to(string(Text),
                       print_message_lines(current_output, '', Parts))
    ->  Message = Text
    ;   Message = Error
    ).

%sub_string/5 with every position open can match at several offsets, so a bare
%call leaves a choicepoint the plunit gate fails a test for.
mentions(Message, Text) :-
    string(Message),
    once(sub_string(Message, _, _, _, Text)).

:- begin_tests(segments_parsing).

%The two spellings the law recognises, and nothing else [source: LeaTTa
%MettaHyperonFull/Core/Modifiers.lean, segment?].
test(both_spellings_parse_to_gaps) :-
    parsed('(A ... D)', Anonymous),
    parsed('(A (:seg $x) D)', Named),
    Anonymous = ['A', AnonymousGap, 'D'],
    Named = ['A', NamedGap, 'D'],
    AnonymousGap = '$petta_seg'(_, anon),
    NamedGap = '$petta_seg'(_, named).

%A colon-seg expression whose second position is not a variable is ordinary
%data, which is the recogniser's own condition.
test(a_bound_second_position_is_data) :-
    parsed('(A (:seg foo) D)', Parsed),
    Parsed == ['A', [':seg', foo], 'D'].

%The root of a side is never a gap [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean, parseSeqAtom].
test(the_root_is_never_a_gap) :-
    sread('(:seg $r)', Term),
    spaces:petta_seq_parse(Term, Parsed),
    Parsed = [':seg', Variable],
    var(Variable).

%A gap arriving through a BINDING is data, and the mechanism that makes it so
%is WHEN the question is asked: a pattern whose marker sits behind a variable
%is gap-free at the moment its call site compiles, so it keeps the ordinary
%door and the marker the variable later carries is matched as the atom it is
%[source: LeaTTa MettaHyperonFull/Core/SeqSyntax.lean, parseConcreteAtom].
test(a_marker_behind_a_variable_is_not_a_gap) :-
    sread('(A $p D)', Term),
    \+ spaces:petta_seq_present(Term),
    %And the door that answer selects still matches the marker as the atom it
    %is, which is what a program relying on the data reading needs.
    metta_add_atom('&j5late', ['A', '...', 'D'], _),
    Term = ['A', Slot, 'D'],
    Slot = '...',
    findall(x, match('&j5late', Term, x, x), Answers),
    Answers == [x],
    metta_remove_atom('&j5late', ['A', '...', 'D'], _).

test(a_gap_free_pattern_reports_no_gap) :-
    sread('(A $x (inner b))', Term),
    \+ spaces:petta_seq_present(Term).

test(a_nested_gap_is_reported) :-
    sread('(A (inner ...))', Term),
    spaces:petta_seq_present(Term).

:- end_tests(segments_parsing).

:- begin_tests(segments_fragments).

%The classifier's own dispatch order [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean, seqFinitary?]: a gap-free side first,
%then last position, then linear-shallow.
test(a_gap_free_side_is_one_sided) :-
    parsed('(A ... D)', Left),
    sread('(A b c D)', Right),
    spaces:petta_seq_classify(Left, Right, Case),
    Case == one_sided(left).

test(the_gap_free_side_may_be_either) :-
    pair('(pair (a b c) (a ... c))', Left, Right),
    spaces:petta_seq_classify(Left, Right, Case),
    Case == one_sided(right).

%Kutsia Section 6.3: every gap the last child of its own expression.
test(trailing_gaps_are_last_position) :-
    pair('(pair (f a (:seg $u)) (f a b (:seg $v)))', Left, Right),
    spaces:petta_seq_classify(Left, Right, Case),
    Case == last_position.

%Kutsia Section 6.2: every gap a direct child of the root, every named gap
%linear across the pair.
test(root_level_linear_gaps_are_linear_shallow) :-
    pair('(pair (f (:seg $u) b) (f a (:seg $v)))', Left, Right),
    spaces:petta_seq_classify(Left, Right, Case),
    Case == linear_shallow.

%The commuting equation Kutsia's Theorem 62 refutes: `X u = u X` has the family
%X = u^n for every n, so no complete finite answer set exists and the engine
%refuses rather than searching.
test(the_commuting_equation_refuses) :-
    pair('(pair (f (:seg $x) a) (f a (:seg $x)))', Left, Right),
    refusal(Left, Right, Message),
    mentions(Message, "outside the proved finitary fragment"),
    mentions(Message, "Theorem 62"),
    mentions(Message, "SeqFragment.lean").

%A two-sided pair whose gaps are neither all final nor all shallow.
test(a_nested_two_sided_gap_refuses) :-
    pair('(pair (f (g (:seg $u) b)) (f (g a (:seg $v))))', Left, Right),
    refusal(Left, Right, Message),
    mentions(Message, "outside the proved finitary fragment").

%One name may not play both roles [source: LeaTTa
%MettaHyperonFull/Core/SeqFragment.lean, noMixedSeqRoles].
test(a_mixed_role_name_refuses) :-
    parsed('(f (:seg $m) $m)', Left),
    sread('(f a b)', Right),
    refusal(Left, Right, Message),
    mentions(Message, "mixed_roles").

%A name in both roles on OPPOSITE sides is the same mix.
test(a_mixed_role_across_sides_refuses) :-
    pair('(pair (f (:seg $m)) (f $m))', Left, Right),
    refusal(Left, Right, Message),
    mentions(Message, "mixed_roles").

:- end_tests(segments_fragments).

:- begin_tests(segments_one_sided).

%A gap consumes every possible run, SHORTEST FIRST [source: LeaTTa
%MettaHyperonFull/Core/SeqOneSided.lean, oneSidedSeg]. Two gaps around a
%separator therefore enumerate the splits in increasing prefix length.
test(splits_enumerate_shortest_first) :-
    parsed('($pre ... SEP ... $post)', Left),
    sread('(a b SEP c SEP d)', Right),
    findall(Run,
            (   spaces:petta_seq_unify(one_sided(left), Left, Right),
                Left = [_, '$petta_seg'(Run, _)|_]
            ),
            Runs),
    Runs == [[b], [b, 'SEP', c]].

test(a_gap_takes_the_empty_run) :-
    parsed('(A ... D)', Left),
    sread('(A D)', Right),
    runs(one_sided(left), Left, Right, Answers),
    Answers == [['A', '$petta_seg'([], anon), 'D']].

test(a_named_gap_answers_its_run_as_an_expression) :-
    parsed('(A (:seg $mid) D)', Left),
    sread('(A b c D)', Right),
    Left = [_, '$petta_seg'(Run, _), _],
    once(spaces:petta_seq_unify(one_sided(left), Left, Right)),
    Run == [b, c].

test(a_nested_gap_matches_below_the_root) :-
    parsed('(f (g ...) b)', Left),
    sread('(f (g 1 2) b)', Right),
    runs(one_sided(left), Left, Right, Answers),
    Answers == [[f, [g, '$petta_seg'([1, 2], anon)], b]].

%A ground clash refutes wherever the split puts it.
test(a_clash_refutes_every_split) :-
    parsed('(A ... D)', Left),
    sread('(A b c E)', Right),
    runs(one_sided(left), Left, Right, Answers),
    Answers == [].

:- end_tests(segments_one_sided).

:- begin_tests(segments_identity).

%Distinct `...` occurrences are distinct variables, so one taking a run says
%nothing about the other [source: LeaTTa
%MettaHyperonFull/Core/SeqSyntax.lean, SeqVar.anonymous].
test(distinct_anonymous_gaps_do_not_constrain_each_other) :-
    parsed('(f ... g ...)', Left),
    sread('(f a g b c)', Right),
    findall(First-Second,
            (   spaces:petta_seq_unify(one_sided(left), Left, Right),
                Left = [_, '$petta_seg'(First, _), _, '$petta_seg'(Second, _)]
            ),
            Answers),
    Answers == [[a]-[b, c]].

%A repeated NAMED gap accepts exactly a runtime-equal run [source: LeaTTa
%MettaHyperonFull/Core/SeqOneSided.lean, oneSidedBindSegment].
test(a_repeated_named_gap_takes_the_same_run) :-
    parsed('(f (:seg $x) g (:seg $x))', Left),
    sread('(f a b g a b)', Right),
    Left = [_, '$petta_seg'(Run, _)|_],
    once(spaces:petta_seq_unify(one_sided(left), Left, Right)),
    Run == [a, b].

test(a_repeated_named_gap_refutes_a_different_run) :-
    parsed('(f (:seg $x) g (:seg $x))', Left),
    sread('(f a b g c)', Right),
    runs(one_sided(left), Left, Right, Answers),
    Answers == [].

%The runtime comparison, not syntactic equality: 1 and 1.0 agree here as they
%do at every other atom position.
test(a_repeated_run_compares_the_engines_way) :-
    parsed('(f (:seg $x) g (:seg $x))', Left),
    sread('(f 1 g 1.0)', Right),
    runs(one_sided(left), Left, Right, Answers),
    Answers \== [].

:- end_tests(segments_identity).

:- begin_tests(segments_last_position).

%Kutsia Section 6.3 is deterministic and unitary: one answer or none. A gap
%facing a longer side takes the whole remainder, and a remainder that still
%holds a gap keeps it as the marker that would match it [source: LeaTTa
%MettaHyperonFull/Core/SeqRuntime.lean, SeqAtom.toSurface].
test(a_trailing_gap_absorbs_the_remainder) :-
    pair('(pair (f a (:seg $u)) (f a b (:seg $v)))', Left, Right),
    Left = [_, _, '$petta_seg'(Run, _)],
    Right = [_, _, _, '$petta_seg'(Open, _)],
    %once/1 rather than findall/3, because the open remainder in the answer IS
    %the other gap's own variable and findall would copy that sharing away.
    once(spaces:petta_seq_unify(last_position, Left, Right)),
    Run = [b, [':seg', Same]],
    Same == Open.

%Deterministic and unitary: Kutsia Section 6.3 answers once or not at all.
test(the_last_position_procedure_answers_once) :-
    pair('(pair (f a (:seg $u)) (f a b (:seg $v)))', Left, Right),
    findall(x, spaces:petta_seq_unify(last_position, Left, Right), Answers),
    Answers == [x].

test(a_trailing_gap_takes_the_empty_run) :-
    pair('(pair (f a b) (f a b (:seg $v)))', Left, Right),
    Right = [_, _, _, '$petta_seg'(Run, _)],
    findall(Run, spaces:petta_seq_unify(last_position, Left, Right), Answers),
    Answers == [[]].

test(a_shorter_fixed_side_refutes) :-
    pair('(pair (f a b) (f a c (:seg $v)))', Left, Right),
    findall(x, spaces:petta_seq_unify(last_position, Left, Right), Answers),
    Answers == [].

%LINEARITY IS NOT REQUIRED HERE. Kutsia Section 6.3 asks only that every gap be
%the last child of its own expression, so a NAMED gap may occur twice, and the
%second occurrence then solves its stored run against what it faces rather than
%demanding the two were written the same way. That is what applying the
%substitution to the worklist does in the calculus [source: LeaTTa
%MettaHyperonFull/Core/SeqLastPos.lean, bindSegment].
test(a_repeated_gap_solves_its_stored_run_against_the_second_face) :-
    pair('(pair (f (g (:seg $x)) (h (:seg $x))) (f (g (:seg $y)) (h b)))',
         Left, Right),
    Left = [_, [_, '$petta_seg'(Repeated, _)], _],
    Right = [_, [_, '$petta_seg'(Once, _)], _],
    once(spaces:petta_seq_unify(last_position, Left, Right)),
    Repeated == [b],
    Once == [b].

%The linear-shallow fragment DOES require it, and a pair that is neither final
%nor linear has no certificate at all.
test(a_repeated_root_gap_has_no_linear_shallow_certificate) :-
    pair('(pair (f (:seg $x) a) (f a (:seg $x)))', Left, Right),
    spaces:petta_seq_gaps(Left, 0, LeftGaps, []),
    spaces:petta_seq_gaps(Right, 0, RightGaps, []),
    \+ spaces:petta_seq_linear_shallow(LeftGaps, RightGaps).

%The occurs check the calculus carries: a gap whose run mentions the gap
%itself is a term containing itself, except for the trivial identity.
test(a_self_referential_run_refutes) :-
    pair('(pair (f (:seg $u)) (f a (:seg $u)))', Left, Right),
    findall(x, spaces:petta_seq_unify(last_position, Left, Right), Answers),
    Answers == [].

test(the_trivial_identity_holds) :-
    pair('(pair (f (:seg $u)) (f (:seg $u)))', Left, Right),
    findall(x, spaces:petta_seq_unify(last_position, Left, Right), Answers),
    Answers == [x].

:- end_tests(segments_last_position).

:- begin_tests(segments_linear_shallow).

%The widening calculus, projection first [source: LeaTTa
%MettaHyperonFull/Core/SeqLinearShallow.lean, solveLinearShallow].
test(two_root_gaps_solve_to_their_runs) :-
    pair('(pair (f (:seg $u) b) (f a (:seg $v)))', Left, Right),
    Left = [_, '$petta_seg'(U, _), _],
    Right = [_, _, '$petta_seg'(V, _)],
    findall(U-V, spaces:petta_seq_unify(linear_shallow, Left, Right), Answers),
    Answers == [[a]-[b]].

test(a_gap_facing_a_longer_side_widens) :-
    pair('(pair (f (:seg $u) c) (f a b c))', Left, Right),
    Left = [_, '$petta_seg'(U, _), _],
    findall(U, spaces:petta_seq_unify(linear_shallow, Left, Right), Answers),
    Answers == [[a, b]].

test(a_flex_flex_pair_relates_the_two_gaps) :-
    pair('(pair (f (:seg $u)) (f (:seg $v)))', Left, Right),
    Left = [_, '$petta_seg'(U, _)],
    findall(U, spaces:petta_seq_unify(linear_shallow, Left, Right), Answers),
    Answers = [_|_].

%Two gaps can absorb each other's fixed items, so a refutation needs a clash no
%split can repair: both sides end in a settled child and they disagree.
test(a_trailing_clash_refutes_every_widening) :-
    pair('(pair (f (:seg $u) a) (f (:seg $v) b))', Left, Right),
    findall(x, spaces:petta_seq_unify(linear_shallow, Left, Right), Answers),
    Answers == [].

%And the widening does relate two gaps across settled children when it can.
test(gaps_absorb_each_others_settled_children) :-
    pair('(pair (f (:seg $u) (g a)) (f (g b) (:seg $v)))', Left, Right),
    Left = [_, '$petta_seg'(U, _), _],
    Right = [_, _, '$petta_seg'(V, _)],
    findall(U-V, spaces:petta_seq_unify(linear_shallow, Left, Right), Answers),
    Answers == [[[g, b]]-[[g, a]]].

:- end_tests(segments_linear_shallow).

:- begin_tests(segments_space_door).

%The arity a gap pattern matches is what the gap decides, so the store is read
%across every arity its fixed part admits and the pattern's own head still
%selects the relation through the store's first-argument index.
test(a_gap_query_reads_every_admissible_arity) :-
    metta_add_atom('&j5door', ['A', b, c, 'D'], _),
    metta_add_atom('&j5door', ['A', 'D'], _),
    metta_add_atom('&j5door', ['B', b, 'D'], _),
    spaces:petta_seq_query_plan(['A', '...', 'D'], Asked),
    findall(x, match('&j5door', Asked, x, x), Answers),
    length(Answers, Matched),
    Matched == 2,
    metta_remove_atom('&j5door', ['A', b, c, 'D'], _),
    metta_remove_atom('&j5door', ['A', 'D'], _),
    metta_remove_atom('&j5door', ['B', b, 'D'], _).

%A marker STORED as an atom is data, never a gap, which is the frozen-subject
%reading [source: LeaTTa MettaHyperonFull/Core/SeqRuntime.lean,
%residualUnderRigid].
test(a_stored_marker_is_data) :-
    metta_add_atom('&j5stored', ['A', '...', 'D'], _),
    spaces:petta_seq_query_plan(['A', '...', 'D'], Asked),
    findall(x, match('&j5stored', Asked, x, x), Answers),
    Answers == [x],
    sread('(A ... D)', Literal),
    findall(y, match('&j5stored', Literal, y, y), Literals),
    Literals == [y],
    metta_remove_atom('&j5stored', ['A', '...', 'D'], _).

%A refusal is CARRIED in the plan and thrown at the ask, so a query nothing
%evaluates cannot stop a file from loading.
test(a_refused_plan_throws_at_the_ask) :-
    sread('(f (:seg $m) $m)', Pattern),
    spaces:petta_seq_query_plan(Pattern, Asked),
    Asked = '$petta_seq'(refused(_), _),
    catch(( match('&j5refuse', Asked, x, x), Outcome = answered ),
          error(Error, _),
          Outcome = Error),
    Outcome = petta_seq_outside_fragment(_, _, _, mixed_roles).

:- end_tests(segments_space_door).

:- begin_tests(segments_costs_nothing).

%The claim the feature rests on: a pattern with no gap never reaches the gap
%unit, because the walk that lifts modifiers answers the question on the way
%past and the two doors dispatch on a wrapper a gap-free pattern never carries.
test(a_gap_free_pattern_is_handed_over_untouched) :-
    translator:lift_pattern_modifiers([fact, X, [inner, Y]], Lifted, Guards,
                                      Segments),
    Segments == false,
    Guards == [],
    Lifted == [fact, X, [inner, Y]].

%And the door itself: an unwrapped pattern takes the clause it always took.
test(an_unwrapped_pattern_never_reaches_the_gap_door) :-
    metta_add_atom('&j5free', [edge, 1, 2], _),
    findall(x, match('&j5free', [edge, 1, 2], x, x), Answers),
    Answers == [x],
    metta_remove_atom('&j5free', [edge, 1, 2], _).

:- end_tests(segments_costs_nothing).
