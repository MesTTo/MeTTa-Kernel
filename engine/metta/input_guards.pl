% Purpose: enforce required-input positions and provide guarded structural and set operations
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: tests/prolog/metta.plt, tests/prolog/static_checks.pl; commit=WORKTREE]

%%%%%%%%%% An unbound argument where a value is required %%%%%%%%%%
%
%A structural operation READS a term; it does not solve for one. An unbound
%variable in a position the engine's own type surface declares Expression,
%Number, BigInt, String, Symbol or Bool is a program error, and letting one through
%produced four different silent wrongs at once, measured 2026-08-19 by a
%probe generated over every such position:
%
%  - 28 positions BOUND THE CALLER'S VARIABLE. (car-atom $u) unified $u with
%    [H|_] through the head and answered the fresh H, so the caller's own
%    variable came back a list it never wrote.
%  - 13 answered a fresh variable and 12 answered a value derived from
%    nothing, (union-atom (a b) $u) answering the partial list (a b|_).
%  - 2 EXHAUSTED THE STACK. (subtraction-atom $u (a b)) reaches a list walk
%    with both ends open and enumerates every list there is.
%  - 7 raised, but named a HOST predicate the MeTTa program never wrote:
%    (sort-atom $u) said `msort/2`, (sread $u) said `atom_codes/2`.
%
%The POSITIONS are read off seam:builtin_type_declaration/2 rather than listed, so
%declaring a type for a new builtin strengthens its guard in the same stroke
%and the table and the guards cannot drift apart. The probe in
%bindings/python/tests/test_builtin_inputs.py enumerates the same table.
%
%Each guard is a LEADING clause on a var first argument, and it costs nothing
%where it would be felt: 'car-atom'([1,2], _) is 2.0000 inferences per call
%with the guard and 2.0000 without, over 200,000 calls, and a MeTTa walk over
%a ten-element list through cdr-atom is 1052.23 inferences either way
%[measured 2026-08-19, both directly and through the engine's own counter].
%A bound argument does not reach the clause.
strict_input_type('Expression').
strict_input_type('Number').
strict_input_type('BigInt').
strict_input_type('String').
strict_input_type('Symbol').
strict_input_type('Bool').
%A space parameter is strict for the same reason the four above are: which
%space an operation touches cannot be left open. The engine's own surface said
%`Symbol` for these positions while a space handle answered Symbol, so they
%were already covered under that spelling and moved with it
%[tested: builtin_input_guards].
strict_input_type('SpaceType').

%The constraint family is RELATIONAL by design: (#+ $a 2 $r) is a constraint
%to post rather than a call to run, and an unbound argument there is the whole
%point. Both directions are pinned by metta.plt's relational_arithmetic unit.
relational_builtin('#+').   relational_builtin('#-').
relational_builtin('#*').   relational_builtin('#div').
relational_builtin('#mod'). relational_builtin('#min').
relational_builtin('#max'). relational_builtin('#<').
relational_builtin('#>').   relational_builtin('#//').

%One POSITION can be relational where the rest of the predicate is not, and
%the type surface cannot say so because it names a type and not a mode.
%(index-atom (a b) $i) enumerates 0-a and 1-b, which is deliberate and is
%pinned by metta.plt's metta_index_atom unit.
relational_input_position('index-atom', 2).
%and, or, not, xor and implies ENUMERATE the booleans for an open argument,
%so and(A, B, C) with all three open answers the whole truth table
%[tested: metta_operation_errors:boolean_operations_remain_relational].
relational_input_position(and, 1).      relational_input_position(and, 2).
relational_input_position(or, 1).       relational_input_position(or, 2).
relational_input_position(not, 1).
relational_input_position(xor, 1).      relational_input_position(xor, 2).
relational_input_position(implies, 1).  relational_input_position(implies, 2).
%cons builds a PATTERN, and an open tail is what makes it one: the engine's
%own prelude writes (cons Error $_) to test whether a value is an error
%[source: engine/prelude.metta, if-error]. cons-atom is the same operation under
%its MeTTa name.
relational_input_position(cons, 2).
relational_input_position('cons-atom', 2).
%union-atom IS append/3, and a shipped library takes a list apart with it:
%(= (mylast $x) (union-atom $xs ($x))) splits a list from the right by
%leaving $xs open [source: lib/lib_roman.metta:80, exercised by
%examples/libraries/roman.metta]. member and its two Bool-answering
%twins are Prolog's member/2 under a MeTTa name for the same reason, and
%examples/reasoning/logicprogset.metta solves (member a $M) for $M.
relational_input_position('union-atom', 1).
relational_input_position('union-atom', 2).
relational_input_position(member, 2).
relational_input_position('is-member', 2).
relational_input_position('is-alpha-member', 2).

%A position PeTTa promises to refuse. A name lent to MeTTa from SWI (msort,
%append, sort, maplist, length) keeps Prolog's own relational behaviour and
%its own errors, because under that name it IS the Prolog predicate; that is
%a boundary rather than an omission, and imported_from/1 is where the engine
%already records it.
guarded_input_position(Name, Arity, Position) :-
    seam:builtin_type_declaration(Name, ['->'|Chain]),
    \+ relational_builtin(Name),
    append(Inputs, [_], Chain),
    nth1(Position, Inputs, Type),
    nonvar(Type),
    strict_input_type(Type),
    length(Chain, Arity),
    functor(Head, Name, Arity),
    predicate_property(Head, defined),
    \+ predicate_property(Head, imported_from(_)),
    \+ relational_input_position(Name, Position),
    \+ unguarded_input_position(Name, Position).

%The residue register is deliberately present and empty. It used to name
%add-reduct, git-import!, sleep and sread; each now guards at its own door, and
%the surface match path already carries its refusal answer through translation.
%Keeping the failed predicate makes the generated completeness probe assert
%that no exception is being hidden rather than deleting the question.
%[tested: test_the_residual_positions_refuse_by_their_own_names].
unguarded_input_position(_, _) :- fail.

%Names the MeTTa operation and the argument, in the program's own vocabulary.
%The formal stays ISO so a MeTTa (catch ...) and the Python boundary can both
%read it, exactly as throw_metta_type_error/3 keeps its own.
refuse_unbound_input(Operation, Position) :-
    throw(error(petta_unbound_input(Operation, Position),
                context(Operation, 'invalid MeTTa operation argument'))).

:- multifile prolog:error_message//1.
%The operation's own name is the CONTEXT's to print, exactly as it is for
%`+: number expected, found "s"`, so it is not repeated here.
prolog:error_message(petta_unbound_input(_, Position)) -->
    [ 'a value expected in argument ~w, found an unbound variable'-[Position] ].

%%% Taking an expression apart, and the grounded values that also read as one.
%
%Each of these grew ONE clause, placed after the cut that a real list takes, so
%a MeTTa expression costs exactly what it did before and only a term that is
%not a list ever asks whether it has a structural view. The SWI manual's rule
%for it: these predicates stay under ten clauses, so selection is "a linear
%scan for a possible matching clause" on the primary index argument, and the
%variable-headed clause that was already here is what decides that, not the new
%one [source 2026-08-16, SWI-Prolog 10.1 Reference Manual 2.17].
'sort-atom'(List, _) :- var(List), !, refuse_unbound_input('sort-atom', 1).
'sort-atom'(List, Sorted) :- non_list(List), !,
                             ( grounded_list_view(List, View) -> msort(View, Sorted) ; Sorted = [] ).
'sort-atom'(List, Sorted) :- msort(List, Sorted).
'size-atom'(List, _) :- var(List), !, refuse_unbound_input('size-atom', 1).
'size-atom'(List, Size) :- non_list(List), !,
                           ( grounded_list_view(List, View) -> length(View, Size) ; Size = [] ).
'size-atom'(List, Size) :- length(List, Size).
'car-atom'(Term, _) :- var(Term), !, refuse_unbound_input('car-atom', 1).
'car-atom'([H|_], H) :- !.
'car-atom'(Term, Out) :- grounded_list_view(Term, [H|_]), !, Out = H.
'car-atom'(Term, []) :- \+ Term = [_|_].
'cdr-atom'(Term, _) :- var(Term), !, refuse_unbound_input('cdr-atom', 1).
'cdr-atom'([_|T], T) :- !.
'cdr-atom'(Term, Out) :- grounded_list_view(Term, [_|T]), !, Out = T.
'cdr-atom'(Term, []) :- \+ Term = [_|_].
decons(Term, _) :- var(Term), !, refuse_unbound_input(decons, 1).
decons([H|T], [H|[T]]).
%The same contract as 'cons-atom'/3 above, under PeTTa's own spelling and its
%own declaration `(: cons (-> Atom Expression Expression))`. An unbound tail
%still builds, which is what makes this the PATTERN constructor lib_roman
%writes `(cons $x $xs)` with; a tail that is decidedly not an Expression is
%refused rather than built into a term nothing can print. Over the shipped
%corpus the tail was a proper list 181,507 times, () 79 times and unbound 35
%times, and never anything else [measured 2026-08-23].
cons(H, T, Out) :-
    (   var(T)    -> Out = [H|T]
    ;   T == []   -> Out = [H]
    ;   T = [_|_] -> Out = [H|T]
    ;   metta_operation_answer(cons, [H, T], Out)
    ).
'index-atom'(List, _, _) :- var(List), !, refuse_unbound_input('index-atom', 1).
'index-atom'(_, Index, Elem) :- nonvar(Index), \+ integer(Index), !,
                                Elem = [].
'index-atom'(List, Index, Elem) :- var(Index), !,
                                  indexable_list(List, View),
                                  nth0(Index, View, Elem).
'index-atom'(List, Index, Elem) :-
    indexable_list(List, View),
    ( nth0(Index, View, Value) -> Elem = Value ; Elem = [] ).

%Reading the shape rather than walking the list is what makes indexing into one
%cost what the index costs instead of what the LIST costs: `(index-atom $l 0)`
%over 25,600 elements cost 34.2 microseconds and costs 0.6
%[measured 2026-08-23].
indexable_list(List, List) :- list_shaped(List), !.
indexable_list(Term, View) :- grounded_list_view(Term, View), !.
indexable_list(List, List).

%A grounded value's own reading of itself as an expression, asked only of terms
%that are not expressions already. Nothing here knows Python: the provider is
%whoever loaded one, and with none loaded this is a single failing call.
%once/1 because this is an OWNERSHIP seam: a value has one structural reading,
%and whichever provider recognises it is the one that answers. Without it every
%caller inherits the choice point of the providers that have not been tried,
%and a caller whose own cut comes BEFORE this call cannot prune it: decons-atom
%cuts on non_list/1 first, so every decons of a Python tuple carried a live
%choice point into whatever loop it was in
%[tested: a_tuple_reads_as_an_expression].
grounded_list_view(Term, View) :-
    nonvar(Term),
    (   seam:grounded_structure(Term, View)
    ->  true
    ;   compound(Term),
        compound_name_arguments(Term, Name, Arguments),
        View = [Name|Arguments]
    ).

%The fallback above is the writer's rule read backwards. A Prolog compound
%already PRINTS as `(name arg ...)`, which is how an error reaches a program:
%`(catch (f))` answers `(Error (python_error ZeroDivisionError "division by
%zero") (context ...))`, and every part of that after `Error` was a compound. So
%it printed as an expression and refused to behave as one, `car-atom` of the
%formal answering `()` and a `let` over it matching nothing. A program could see
%that a call failed and could not ask WHAT failed, which is most of what an
%error is for.
%
%A provider is asked first and can disagree: a Python tuple is -/N and reads as
%its elements NORMALIZED, so a None inside one reads as `()` rather than as
%janus's spelling of it.
member(X, L, true) :- member(X, L).
'is-member'(X, List, true) :- member(X, List).
'is-member'(X, List, false) :- \+ member(X, List).

%"Alpha" is historical. This predicate tests unifiability, with a bare query
%variable matching only a variable list element. Double negation at the public
%boundary keeps that test's bindings private; it is deliberately not =@=/2.
member_alpha(X, [H|_]) :- (var(X) -> var(H) ; true), X = H, !.
member_alpha(X, [_|T]) :- member_alpha(X, T).

'is-alpha-member'(X, List, true) :- \+ \+ member_alpha(X, List), !.
'is-alpha-member'(X, List, false) :- \+ member_alpha(X, List).

'exclude-item'(_, L, _) :- var(L), !, refuse_unbound_input('exclude-item', 2).
'exclude-item'(A, L, R) :- exclude(==(A), L, R).

%Remove the first element identical to X, keeping the rest in order. select/3
%unifies instead, which both answers wrongly and binds the caller's variables:
%(subtraction-atom ($x) (a)) came back () with $x bound to a. PeTTa's own
%formalisation removes by equality, in leanPeTTa/StreamOps.lean:
%  removeFirstEq (x : Pattern) : List Pattern -> Option (List Pattern)
%    | y :: ys => if y == x then some ys else ...
select_eq(X, [Y|Ys], Ys) :- X == Y, !.
select_eq(X, [Y|Ys], [Y|Rest]) :- select_eq(X, Ys, Rest).

%EXPERIMENT (worktree only): both of these rescanned the right operand with
%select_eq/3 once per left element, which is Theta(n*m). Measured on the
%shipped operation: N=100 cost 4,304,235 instructions and N=1600 cost
%1,053,976,615, an exponent of 1.98, while union-atom over the same sizes is
%linear at 606,874. The right operand is now indexed ONCE as a count map keyed
%by standard order, and the left operand is walked in order decrementing
%counts, giving O((n+m) log m).
%
%The three properties select_eq/3 carried are preserved deliberately:
%compare/3 and ==/2 agree on identity, so this still removes by EQUALITY and
%never unifies (the bug the comment above records, where (subtraction-atom
%($x) (a)) answered () and bound $x); a count of one per stored occurrence
%keeps the multiset multiplicity; and walking the left operand in order keeps
%its order. library(assoc) is already imported for exactly these three
%predicates at the head of this file.
count_assoc(List, Assoc) :- empty_assoc(Empty), count_assoc_(List, Empty, Assoc).
count_assoc_([], A, A).
count_assoc_([X|Xs], A0, A) :-
    ( get_assoc(X, A0, N) -> N1 is N+1 ; N1 = 1 ),
    put_assoc(X, A0, N1, A1),
    count_assoc_(Xs, A1, A).

%Succeeds only when one occurrence is still available, and answers the map
%with that occurrence consumed.
take_counted(X, A0, A) :-
    get_assoc(X, A0, N), N > 0, N1 is N-1, put_assoc(X, A0, N1, A).

subtract_counted([], _, []).
subtract_counted([H|T], C0, Out) :-
    (   take_counted(H, C0, C1)
    ->  subtract_counted(T, C1, Out)
    ;   Out = [H|Rest], subtract_counted(T, C0, Rest)
    ).

intersect_counted([], _, []).
intersect_counted([H|T], C0, Out) :-
    (   take_counted(H, C0, C1)
    ->  Out = [H|Rest], intersect_counted(T, C1, Rest)
    ;   intersect_counted(T, C0, Out)
    ).

%Multisets. Keep the variable-headed non-list fallback last so list calls use
%the first argument index. Over 100,000 two-element calls this reduced each
%operation from 2,200,002 to 1,400,002 inferences [measured: 800,000 fewer
%inferences per operation, 2026-08-15]. The list clauses still handle a
%non-list right operand before recursing, preserving the empty-tuple result.
'subtraction-atom'(A, B, _) :- ( var(A) -> refuse_unbound_input('subtraction-atom', 1)
                               ; var(B) -> refuse_unbound_input('subtraction-atom', 2)
                               ; fail ).
'subtraction-atom'([], _, []) :- !.
'subtraction-atom'([H|T], B, Out) :- !,
    ( non_list(B) -> Out = []
    ; count_assoc(B, Counts), subtract_counted([H|T], Counts, Out) ).
'subtraction-atom'(A, B, Out) :- ( non_list(A) ; non_list(B) ), !, Out = [].
%The guard its two siblings already have, and it leads rather than trails
%because append/3 succeeds on a non-list right operand: (union-atom (a) b)
%built the improper list [a|b], printed as (cons a b), which is not a tuple
%and cannot be consumed by any tuple operation. A non-list left operand
%failed silently. The empty-tuple answer is this family's settled convention.
%
%non_list/1 is false for an unbound argument, which is load-bearing: lib_roman
%calls (union-atom $xs ($x)) with $xs unbound to SPLIT a list, so append/3
%must still be reached in its relational modes
%[tested: metta_set_operations, examples/libraries/roman.metta].
'union-atom'(A, B, Out) :- ( non_list(A) ; non_list(B) ), !, Out = [].
'union-atom'(A, B, Out) :- append(A, B, Out).
'intersection-atom'(A, B, _) :- ( var(A) -> refuse_unbound_input('intersection-atom', 1)
                                ; var(B) -> refuse_unbound_input('intersection-atom', 2)
                                ; fail ).
'intersection-atom'([], _, []) :- !.
'intersection-atom'([H|T], B, Out) :- !,
    ( non_list(B) -> Out = []
    ; count_assoc(B, Counts), intersect_counted([H|T], Counts, Out) ).
'intersection-atom'(A, B, Out) :- ( non_list(A) ; non_list(B) ), !, Out = [].
