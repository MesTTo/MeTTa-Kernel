% Purpose: implement arithmetic, comparisons, booleans, list operators, and expression-shape guards
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees: every definition retains engine/metta.pl's implementation module and original load order.
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.
% [tested: full tests/prolog/*.plt battery in bare and backends configurations; commit=WORKTREE]

%%% Arithmetic & Comparison: %%%
%An arithmetic operand is a number. Everything else is refused here, before
%is/2 applies Prolog's own coercion rules to it.
%
%Two things came through that door. A MeTTa expression IS a Prolog list, and
%SWI reads a one-element list as a character code, so (+ 1 (g)) quietly
%answered 104, the code of g, and (* 2 (z)) answered 244: a symbol's SPELLING
%became a number, while the two-element case raised.
%
%Worse, Prolog's evaluable atoms silently outranked MeTTa. With (= pi 3.14)
%defined, (+ 1 pi) answered 4.141592653589793 from SWI's constant rather than
%4.14 from the user's own equation. A constant belongs in a MeTTa library as
%an ordinary rewrite, (= (my-pi) 3.14), which reduces before arithmetic sees
%it and now wins because nothing shadows it.
%
%Nobody chose either behaviour; both fall out of is/2. The whole corpus, 169
%programs including the ones passing inf and nan around, is unaffected
%[tested: metta_arithmetic_operands].
%An unbound operand is left to is/2, which raises instantiation_error for it,
%the answer Prolog and ISO both give; refusing it as a type error here would
%report a missing value as a wrong one.
%Both operands in one call: the inline type tests are free, the call is not,
%so checking them separately cost two inferences per operation instead of one
%[measured 2026-08-15: alpha-unique +200,010 against +100,005].
%
%This TESTS and no longer throws. What to answer for an operand that is not a
%number belongs to metta_operation_answer/3 above, which has the argument's
%type and can tell a wrong type from a value the operation simply cannot use.
metta_arith_operands(A, B) :-
    ( var(A) -> true ; number(A) ),
    ( var(B) -> true ; number(B) ).

%The four operators run BACKWARDS over integers: exactly one unbound
%argument among integers solves for it, so (let 4 (- $x 1) $x) answers 5
%and (unify 6 (* $x 2) ...) binds 3, the WAM plus/3 reading MeTTaLog
%compiles to. The ground fast path is untouched and stays first;
%petta_int_solve sits BEHIND the ground-number path, so ground floats
%never meet it (annotated-relation measured +1 inference per float op
%with the solver between the paths, and par with it behind them
%[measured 2026-08-18]); strings and the two-var case behave exactly as
%before (two unbound arguments stay an instantiation error: bounded
%solving is this file's job, constraint propagation is
%lib_constraints'). Multiplicative
%backward modes are exact-division only, and a non-divisible pair FAILS
%rather than errors, the relational reading: no integer solves it.
'+'(A,B,R)  :- ( integer(A), integer(B) -> R is A + B
                ; number(A), number(B)
                  -> catch(R is A + B, E, metta_saturating_recover('+', A + B, R, E))
                ; petta_int_solve('+', A, B, R, Verdict) -> Verdict == solved
                ; petta_clp_operands(A, B, R) -> petta_clp_backward('+', A, B, R)
                ; metta_arith_operands(A, B)
                  -> catch(R is A + B, E, metta_saturating_recover('+', A + B, R, E))
                ; metta_operation_answer('+', [A, B], R) ).
'-'(A,B,R)  :- ( integer(A), integer(B) -> R is A - B
                ; number(A), number(B)
                  -> catch(R is A - B, E, metta_saturating_recover('-', A - B, R, E))
                ; petta_int_solve('-', A, B, R, Verdict) -> Verdict == solved
                ; petta_clp_operands(A, B, R) -> petta_clp_backward('-', A, B, R)
                ; metta_arith_operands(A, B)
                  -> catch(R is A - B, E, metta_saturating_recover('-', A - B, R, E))
                ; metta_operation_answer('-', [A, B], R) ).
'*'(A,B,R)  :- ( integer(A), integer(B) -> R is A * B
                ; number(A), number(B)
                  -> catch(R is A * B, E, metta_saturating_recover('*', A * B, R, E))
                ; petta_int_solve('*', A, B, R, Verdict) -> Verdict == solved
                ; petta_clp_operands(A, B, R) -> petta_clp_backward('*', A, B, R)
                ; metta_arith_operands(A, B)
                  -> catch(R is A * B, E, metta_saturating_recover('*', A * B, R, E))
                ; metta_operation_answer('*', [A, B], R) ).
%Division has no catchless integer arm: an all-integer pair is exact until a
%non-divisible one converts to float, and THAT can overflow (10^400 / 3
%raised a raw float_overflow with no operation context from the old catchless
%arm), so it needs the same recovery as the float arms. The recovery separates
%that IEEE result from integer zero division, which is an Error answer.
'/'(A,B,R)  :- ( number(A), number(B)
                  -> catch(R is A / B, E,
                           metta_arithmetic_saturating_recovery(
                               '/', [A, B], A / B, E, R))
                ; petta_int_solve('/', A, B, R, Verdict) -> Verdict == solved
                ; petta_clp_operands(A, B, R) -> petta_clp_backward('/', A, B, R)
                ; metta_arith_operands(A, B)
                  -> catch(R is A / B, E,
                           metta_arithmetic_saturating_recovery(
                               '/', [A, B], A / B, E, R))
                ; metta_operation_answer('/', [A, B], R) ).

%One unbound slot among integers: the verdict says whether the mode
%applied at all (fail: not this shape, fall through to the CLP/float/error
%path) and whether it solved (none: the mode fits but no integer answers
%it, so the operator FAILS, the relational reading of (* $x 2) = 7).
%plus/3 carries the additive family in C. Two unbound slots are past this
%predicate's job and reach petta_clp_backward/4 below, beside the # family.
petta_int_solve('+', A, B, R, solved) :-
    ( var(A), integer(B), integer(R) -> plus(A, B, R)
    ; var(B), integer(A), integer(R) -> plus(A, B, R)
    ).
petta_int_solve('-', A, B, R, solved) :-
    ( var(A), integer(B), integer(R) -> plus(B, R, A)
    ; var(B), integer(A), integer(R) -> plus(B, R, A)
    ).
petta_int_solve('*', A, B, R, Verdict) :-
    ( var(A), integer(B), integer(R), B =\= 0
    ->  ( 0 =:= R mod B -> A is R // B, Verdict = solved ; Verdict = none )
    ; var(B), integer(A), integer(R), A =\= 0
    ->  ( 0 =:= R mod A -> B is R // A, Verdict = solved ; Verdict = none )
    ).
petta_int_solve('/', A, B, R, Verdict) :-
    ( var(A), integer(B), integer(R)
    ->  A is R * B, Verdict = solved
    ; var(B), integer(A), integer(R), R =\= 0
    ->  ( 0 =:= A mod R -> B is A // R, Verdict = solved ; Verdict = none )
    ).

'%'(A,B,R)  :- ( integer(A), integer(B), B =\= 0 -> R is A mod B
                ; metta_arith_operands(A, B)
                  -> catch(R is A mod B, E,
                           metta_operation_recovery('%', [A, B], E, R))
                ; metta_operation_answer('%', [A, B], R) ).
'<'(A,B,R)  :- ( number(A), number(B) -> (A<B -> R=true ; R=false)
                ; metta_arith_operands(A, B)
                  -> catch((A<B -> R=true ; R=false), E,
                           rethrow_metta_operation_error('<', E))
                ; metta_operation_answer('<', [A, B], R) ).
'>'(A,B,R)  :- ( number(A), number(B) -> (A>B -> R=true ; R=false)
                ; metta_arith_operands(A, B)
                  -> catch((A>B -> R=true ; R=false), E,
                           rethrow_metta_operation_error('>', E))
                ; metta_operation_answer('>', [A, B], R) ).
%(-> $a $a Bool): ONE type variable, so the two operands must have a
%consistent type, and a comparison across two known and different kinds is
%refused rather than answered. `!(== 1 "S")` answered False, which is the
%answer for two Numbers that differ, so a conditional took the else branch and
%nothing said the question was meaningless. `=alpha` is the comparison that
%accepts anything, and it is declared (-> Atom Atom Bool) for that reason.
%
%Measured 2026-08-19 on hyperon 0.2.10 and on the LeaTTa mechanised
%interpreter, byte-identical across both: (== 1 "S"), (== True 1),
%(== xnum ystr) and (== xnum "s") are BadArgType, while (== 1 a),
%(== a "a"), (== xnum 1), (== xnum undeclared) and (== 1 (foo)) are False and
%(== 1 1), (== "S" "S") and (== () ()) are True. The unknown side is what
%makes the False cases False: nothing is known about `a`, so nothing is
%contradicted.
%Two numbers inline, the shape '<'/3 above already uses, because that is what
%a loop compares and the guard must not be felt there. Numeric equality is by
%VALUE across the integer/float constructors: LeaTTa's Ground.equiv promotes
%the integer with Float.ofInt in both mixed cases, and Atom.equiv delegates its
%grounded case there [source: LeaTTa MettaHyperonFull/Core/Atom.lean:47-62,
%110-116] [tested: test_mixed_numeric_equality_answers_what_the_arbiter_answers].
'=='(A,B,R) :- ( number(A), number(B) -> (A =:= B -> R=true ; R=false)
                ; comparable_operands(A, B) -> (A==B -> R=true ; R=false)
                ; metta_operation_answer('==', [A, B], R) ).
'!='(A,B,R) :- ( number(A), number(B) -> (A =:= B -> R=false ; R=true)
                ; comparable_operands(A, B) -> (A==B -> R=false ; R=true)
                ; metta_operation_answer('!=', [A, B], R) ).
%The guard the declaration above states, enforced at the predicate's own door
%rather than through typed dispatch, which is what runtime_type_guarded/1
%means and what keeps the cost near zero: the common case is two literals and
%a first-argument-indexed type lookup.
%
%EXPRESSIONS ARE EXCLUDED, because the two references disagree about them and
%nothing here should pick a side that neither of them agrees on. Measured
%2026-08-19: hyperon answers False for (== () 1), (== "s" ()) and
%(== (1 2) (1 2 3)) while LeaTTa raises BadArgType for the first two and
%answers False for the third. Both answer False for (== (1 2 3) ()) and
%(== (1 2) (a b)), which is the shape a MeTTa program actually writes, so the
%collapse-and-compare idiom is untouched either way.
%TWO TIERS, because asking the type system costs 26 inferences and a program
%compares literals in a loop. Two operands of the same intrinsic kind settle
%it with one type test and no lookup, which is the case a loop writes; only a
%pair the kinds do not settle pays for a declaration
%[measured 2026-08-19: a thousand-iteration == loop is 4487.45 inferences
%unguarded, 30514.55 with the lookup on every call, and 4990.45 with this
%tier in front, so the guard costs 0.50 inferences per comparison instead
%of 26.03].
%This TESTS and no longer throws, for the reason metta_arith_operands/2 does:
%the refusal belongs to metta_operation_answer/3, which reports the position,
%the expected type and the actual one rather than a bare pair.
%AN ERROR ATOM IS NOT A COMPARABLE VALUE, it is an evaluation that finished in
%error, so `(== 4 (+ 1 "bad"))` hands the inner error on instead of answering
%False about it [source: LeaTTa tests/semantics/control-stdlib/07_error.metta,
%STATUS conforms: "A grounded equality must propagate its argument's
%BadArgType rather than compare it as a value"]. Falling through here sends the
%pair to metta_operation_answer/3, which is where that propagation lives.
%
%The test is asked only where a LIST operand is present, because an error atom
%is one; two literals, which is what a loop compares, never reach it and the
%measured 0.50 inferences per comparison the tier above costs are unchanged
%[tested: test_the_error_vocabulary_answers_what_the_arbiter_answers].
comparable_operands(A, B) :-
    (   same_intrinsic_kind(A, B)
    ->  true
    %() is a proper list, and one proper list is all the branches below need,
    %so an operand that IS one decides this without the walk is_list/1 would
    %spend on the other. `(== $l ())` is how a list is walked to its end, and
    %the walk asked is_list/1 of the whole remaining list at every step, which
    %made traversing N elements quadratic [measured 2026-08-23: 46,245
    %microseconds for 6,400 elements against 11,883 for the same walk that
    %threads the list without comparing it].
    %
    %Both readings are what the branches below answer, and neither skips the
    %error-shape rule. With A the empty list, is_list(A) holds and
    %error_shaped_operand([]) cannot, so the first branch reduces to the test
    %on B. With B the empty list, is_list(B) holds, so an A that is not a
    %proper list reaches the second branch and succeeds there, and an A that
    %is one succeeds in the first unless it is error-shaped: either way the
    %answer is settled by A's error shape alone, which is a constant-time
    %question.
    ;   A == []
    ->  \+ error_shaped_operand(B)
    ;   B == [], \+ error_shaped_operand(A)
    ->  true
    ;   is_list(A)
    ->  \+ error_shaped_operand(A), \+ error_shaped_operand(B)
    ;   is_list(B)
    ->  \+ error_shaped_operand(B)
    ;   current_metta_module(Module),
        once(( has_type_in(Module, A, Type), has_type_in(Module, B, Type) ))
    ).

error_shaped_operand(A) :-
    nonvar(A), A = [Head|Tail], Head == 'Error', nonvar(Tail).

%Fails when the kinds DIFFER and when they do not decide, so an undecided
%pair falls through to the declarations rather than being waved past.
same_intrinsic_kind(A, B) :- number(A), !, number(B).
same_intrinsic_kind(A, B) :- string(A), !, string(B).
same_intrinsic_kind(A, B) :- metta_boolean(A), !, metta_boolean(B).

metta_boolean(true).
metta_boolean(false).

'='(A,B,R) :-  (A=B -> R=true ; R=false).
'=?'(A,B,R) :- (\+ \+ A=B -> R=true ; R=false).
'=alpha'(A,B,R) :- (A =@= B -> R=true ; R=false).
'=@='(A,B,R) :- (A =@= B -> R=true ; R=false).
'<='(A,B,R) :- ( number(A), number(B) -> (A =< B -> R=true ; R=false)
                ; metta_arith_operands(A, B)
                  -> catch((A =< B -> R=true ; R=false), E,
                           rethrow_metta_operation_error('<=', E))
                ; metta_operation_answer('<=', [A, B], R) ).
'>='(A,B,R) :- ( number(A), number(B) -> (A >= B -> R=true ; R=false)
                ; metta_arith_operands(A, B)
                  -> catch((A >= B -> R=true ; R=false), E,
                           rethrow_metta_operation_error('>=', E))
                ; metta_operation_answer('>=', [A, B], R) ).
min(A,B,R)  :- ( integer(A), integer(B) -> R is min(A,B)
                ; metta_arith_operands(A, B)
                  -> catch(R is min(A,B), E,
                           rethrow_metta_operation_error(min, E))
                ; metta_operation_answer(min, [A, B], R) ).
max(A,B,R)  :- ( integer(A), integer(B) -> R is max(A,B)
                ; metta_arith_operands(A, B)
                  -> catch(R is max(A,B), E,
                           rethrow_metta_operation_error(max, E))
                ; metta_operation_answer(max, [A, B], R) ).
%exp/2 is PeTTa's own name for the same function exp-math names, so it refuses
%the same way rather than being the one numeric operation that raises.
exp(Arg, R) :- metta_math_eval(exp, exp(Arg), [Arg], R).
:- use_module(library(clpfd)).
'#+'(A, B, R) :- catch(R #= A + B, E,
                       rethrow_metta_operation_error('#+', E)).
'#-'(A, B, R) :- catch(R #= A - B, E,
                       rethrow_metta_operation_error('#-', E)).
'#*'(A, B, R) :- catch(R #= A * B, E,
                       rethrow_metta_operation_error('#*', E)).
'#div'(A, B, R) :- catch(R #= A div B, E,
                         rethrow_metta_operation_error('#div', E)).
'#//'(A, B, R) :- catch(R #= A // B, E,
                        rethrow_metta_operation_error('#//', E)).
'#mod'(A, B, R) :- catch(R #= A mod B, E,
                         rethrow_metta_operation_error('#mod', E)).
'#min'(A, B, R) :- catch(R #= min(A,B), E,
                         rethrow_metta_operation_error('#min', E)).
'#max'(A, B, R) :- catch(R #= max(A,B), E,
                         rethrow_metta_operation_error('#max', E)).
'#<'(A, B, true)  :- catch(A #< B, E,
                           rethrow_metta_operation_error('#<', E)), !.
'#<'(A, B, false) :- catch(A #>= B, E,
                           rethrow_metta_operation_error('#<', E)).
'#>'(A, B, true)  :- catch(A #> B, E,
                           rethrow_metta_operation_error('#>', E)), !.
'#>'(A, B, false) :- catch(A #=< B, E,
                           rethrow_metta_operation_error('#>', E)).
'#='(A, B, true)  :- catch(A #= B, E,
                           rethrow_metta_operation_error('#=', E)), !.
'#='(A, B, false) :- catch(A #\= B, E,
                           rethrow_metta_operation_error('#=', E)).
'#\\='(A, B, true)  :- catch(A #\= B, E,
                              rethrow_metta_operation_error('#\\=', E)), !.
'#\\='(A, B, false) :- catch(A #= B, E,
                              rethrow_metta_operation_error('#\\=', E)).
%The other two comparisons of the same family. Four of the six were defined and
%these two were not, and nothing in examples/ or lib/ used any of them, so
%nothing noticed.
%
%The absence was quiet rather than loud, and that part is the language working
%correctly: an expression whose head has no definition is DATA, so (#=< 1 2)
%answered (#=< 1 2). A symbol is data or a function depending on whether
%something defines it, which is what makes an undefined name usable as a term
%at all. The defect was the incomplete family, not the way it showed.
'#=<'(A, B, true)  :- catch(A #=< B, E,
                            rethrow_metta_operation_error('#=<', E)), !.
'#=<'(A, B, false) :- catch(A #> B, E,
                            rethrow_metta_operation_error('#=<', E)).
'#>='(A, B, true)  :- catch(A #>= B, E,
                            rethrow_metta_operation_error('#>=', E)), !.
'#>='(A, B, false) :- catch(A #< B, E,
                            rethrow_metta_operation_error('#>=', E)).

:- multifile prolog:error_message//1.
%%%% past ONE unknown: CLP(FD) is the solver, and its own boundary is ours %%%%
%
%petta_int_solve/5 rearranges ONE unbound slot among integers. Two
%unbound slots, or one slot written twice, is a CONSTRAINT rather than a
%rearrangement: 25 = X*X is nonlinear, and is/2 cannot run it in any mode at
%all. The route past that is the one the domain's own literature names,
%replacing the moded is/2 with the relation #=/2, which runs in every
%direction [source: Markus Triska, "Constraint Logic Programming over Finite
%Domains", https://github.com/triska/clpfd, read 2026-08-21: "?- 3 #= 1+Y.
%Y = 2"].
%
%Curry, the closest functional-logic language, answers the same question by
%RESIDUATION: its primitive arithmetic is rigid, a call holding a free
%variable suspends, and with nothing left to bind it the call FLOUNDERS
%[source: Sergio Antoy, "Curry: A Tutorial Introduction", draft 2025-04-17,
%section 3.14.2, "predefined arithmetic operations like the addition + are
%rigid. Thus, a call to + with a logic variable as an argument flounders"].
%PeTTa's evaluator has no suspension to residuate into, so the two answers
%available here are to SOLVE it or to SAY SO, and this does both: it solves
%where CLP(FD) is complete, and it names the reason where it is not.
%
%THE BOUNDARY IS A THEOREM, not an omission. Deciding whether a polynomial
%equation has an integer solution is undecidable [source: Hilbert's tenth
%problem, resolved negatively by Matiyasevich 1970 on Davis, Putnam and
%Robinson]. CLP(FD) is complete over FINITE domains and labeling requires
%them, so an unbounded domain is refused by name rather than searched
%forever. That refusal is the SOLVER's own line and not a number this file
%invented, which is why there is no cap here beside it: label/1 is a lazy
%generator, so a bounded consumer such as once or (take k ...) pays for the
%answers it reads and no more.
%
%Reached ONLY where the moded path in the four operators would raise. Every
%ground path,
%every float, every single-unknown inversion and every non-numeric operand is
%decided before this one, so nothing that answers today reaches it
%[tested: test_arithmetic_inverts_past_the_linear_case_or_refuses_with_the_reason].
petta_clp_operands(A, B, R) :-
    petta_clp_slot(A), petta_clp_slot(B), petta_clp_slot(R).

petta_clp_slot(S) :- var(S), !.
petta_clp_slot(S) :- integer(S).

%% petta_clp_backward(+Op, ?A, ?B, ?R) is nondet.
%
%Nondeterministic on purpose: 25 = X*X has TWO integer answers and a relation
%answers both. label/1 yields them one at a time and in ascending order.
petta_clp_backward(Op, A, B, R) :-
    (   petta_clp_expression(Op, A, B, Expression)
    ->  R #= Expression,
        term_variables([A, B, R], Unknowns),
        (   Unknowns == []
        ->  true
        ;   petta_clp_finite(Unknowns)
        ->  label(Unknowns)
        ;   petta_refuse_unsolved_arithmetic(Op, unbounded_domain)
        )
    ;   petta_refuse_unsolved_arithmetic(Op, no_integer_relation)
    ).

%The three operations CLP(FD) models exactly. `/` is deliberately absent: this
%engine's `/` answers a float on a non-divisible pair, so there is no integer
%relation to post and no finite set of integers to search. Its own backward
%mode for one unknown is petta_int_solve('/', ...) and is unaffected.
petta_clp_expression('+', A, B, A + B).
petta_clp_expression('-', A, B, A - B).
petta_clp_expression('*', A, B, A * B).

%fd_size/2 answers the atom `sup` for a domain with no bound, which is exactly
%the case label/1 cannot enumerate, and answers a plain integer for a variable
%that carries no CLP(FD) attribute at all only after one has been posted on
%it; a variable the constraint left unconstrained still reads sup.
petta_clp_finite(Unknowns) :-
    forall(member(Unknown, Unknowns),
           ( fd_size(Unknown, Size), integer(Size) )).

%A builtin refusal names the MeTTa operation in the error's CONTEXT, so a host
%reads the name from the term rather than from rendered text
%(metta_host_operation_error/5), and the engine's own guard sweep checks every
%guarded input position for exactly that
%[tested: tests/prolog/metta.plt, every_builtin_refuses_an_unbound_input_by_name].
petta_refuse_unsolved_arithmetic(Operation, Reason) :-
    throw(error(petta_unsolved_arithmetic(Operation, Reason),
                context(Operation, 'while evaluating MeTTa operation'))).

prolog:error_message(petta_unsolved_arithmetic(Op, unbounded_domain)) -->
    [ '~w ran backwards with more than one unknown, and what the constraint \c
       leaves has no finite domain to search, so there is no answer to \c
       enumerate. Bound the unknowns first, for example with the CLP(FD) \c
       comparisons (let True (#>= $x 0) ...), or post the relation with the \c
       # operators and read what it leaves. Deciding a polynomial equation \c
       over the integers is undecidable in general (Hilbert''s tenth \c
       problem), so this boundary is a theorem rather than an omission'
      -[Op] ].
prolog:error_message(petta_unsolved_arithmetic(Op, unbound_operand)) -->
    [ '~w needs a value it does not have: an operand is still unbound and \c
       this operation has no relation to solve for it. Only the integer \c
       relations +, - and * are solved for a missing operand, and only where \c
       every operand they do have is an integer, since a float has no finite \c
       domain to search. Bind the operand first, post the relation with the \c
       # (CLP(FD)) operators, or use clpq from lib_constraints for the \c
       rationals'-[Op] ].
prolog:error_message(petta_unsolved_arithmetic(Op, no_integer_relation)) -->
    [ '~w ran backwards with more than one unknown, and only +, - and * have \c
       an integer relation to solve: ~w may answer a float, so there is no \c
       finite set of integers to search. Use // or div for integer division, \c
       or clpq from lib_constraints for the rationals'-[Op, Op] ].

%Real-valued operations explicitly promote integer inputs before applying the
%host function. That is LeaTTa's toFloat? -> floatUn/floatBin law: sqrt, log
%and the trig family always run and answer in binary64, including their NaN
%and infinity edges [source: LeaTTa MettaHyperonFull/Core/Builtins.lean:
%143-194; tested:
%test_real_valued_math_treats_integer_and_float_operands_alike;
%commit=6e529fc2c08eb69c0df47e3cff7c921320a3300d].
%
%pow-math has one additional split from powMath: the base is always Float, an
%integer exponent must fit signed i32, a Float exponent has no such bound, and
%every successful result is Float. Check the base's numeric door before the
%bound so a bad base still earns pow-math's ordinary argument refusal.
'pow-math'(A, B, Out) :-
    (   maplist(metta_numeric_operand, [A, B])
    ->  metta_pow_math_numeric(A, B, Out)
    ;   metta_operation_answer('pow-math', [A, B], Out)
    ).

metta_pow_math_numeric(A, B, Out) :-
    (   integer(B), ( B < -2147483648 ; B > 2147483647 )
    ->  metta_error_atom(
            'pow-math', [A, B],
            "power argument is too big, try using float value", Out)
    ;   Expression = float(A) ** float(B),
        catch(Out is Expression, Error,
              metta_math_saturating_recovery(
                  'pow-math', Expression, [A, B], Error, Out))
    ).

metta_float_unary_eval(Operation, Function, A, Out) :-
    Expression =.. [Function, float(A)],
    metta_math_saturating_eval(Operation, Expression, [A], Out).

'sqrt-math'(A, Out) :-
    metta_float_unary_eval('sqrt-math', sqrt, A, Out).
'abs-math'(A, Out) :-
    ( integer(A) -> Out is abs(A)
    ; metta_math_saturating_eval('abs-math', abs(A), [A], Out) ).
%log of zero is float_overflow-classed by SWI (the result is an infinity),
%so it saturates with the family; this compound expression is also why the
%recovery retries under ALL the IEEE flags at once, because base 1 divides
%the saturated -inf by log(1) = 0.0 and the answer is -inf, not a second
%error.
'log-math'(Base, X, Out) :-
    metta_math_saturating_eval(
        'log-math', log(float(X)) / log(float(Base)), [Base, X], Out).
%exp-math is retained under PeTTa's existing real-valued doctrine. LeaTTa's
%floatUn table does not include exp-math, so no LeaTTa attribution is made for
%this operation; its integer and float spellings already share the host exp/1
%path and its overflow recovery.
'exp-math'(A, Out) :-
    metta_math_saturating_eval('exp-math', exp(A), [A], Out).
'trunc-math'(A, Out) :-
    metta_math_eval('trunc-math', truncate(A), [A], Out).
'ceil-math'(A, Out) :- metta_math_eval('ceil-math', ceil(A), [A], Out).
'floor-math'(A, Out) :- metta_math_eval('floor-math', floor(A), [A], Out).
'round-math'(A, Out) :- metta_math_eval('round-math', round(A), [A], Out).
'sin-math'(A, Out) :- metta_float_unary_eval('sin-math', sin, A, Out).
'cos-math'(A, Out) :- metta_float_unary_eval('cos-math', cos, A, Out).
'tan-math'(A, Out) :- metta_float_unary_eval('tan-math', tan, A, Out).
'asin-math'(A, Out) :- metta_float_unary_eval('asin-math', asin, A, Out).
'acos-math'(A, Out) :- metta_float_unary_eval('acos-math', acos, A, Out).
'atan-math'(A, Out) :- metta_float_unary_eval('atan-math', atan, A, Out).
'isnan-math'(A, Out) :-
    (   metta_numeric_operand(A)
    ->  catch(( A =:= A -> Out = false ; Out = true ), E,
              metta_math_recovery('isnan-math', [A], E, Out))
    ;   metta_operation_answer('isnan-math', [A], Out)
    ).
'isinf-math'(A, Out) :-
    (   metta_numeric_operand(A)
    ->  catch(( ( A =:= 1.0Inf ; A =:= -1.0Inf )
                -> Out = true ; Out = false ), E,
              metta_math_recovery('isinf-math', [A], E, Out))
    ;   metta_operation_answer('isinf-math', [A], Out)
    ).
%must_be/2 walks the list a second time with a type check per element, so a
%numeric list costs 3x what min_list alone does [measured 2026-08-15: 20 calls
%over 50,000 elements, 3,000,220 against 1,000,060 inferences]. That buys
%'min-atom': Type error: `number' expected, found `a' in place of a leaked
%lists:min_list/3, which is the trade this file makes everywhere.
%A list of numbers computes; anything else is answered by the shared door,
%whose refusal table words min-atom and max-atom the three ways upstream does.
'min-atom'(List, Out) :- ( metta_numeric_list(List) -> min_list(List, Out)
                         ; metta_operation_answer('min-atom', [List], Out) ).
'max-atom'(List, Out) :- ( metta_numeric_list(List) -> max_list(List, Out)
                         ; metta_operation_answer('max-atom', [List], Out) ).

metta_numeric_list(List) :- is_list(List), List \== [], maplist(number, List).

%%% Random Generators: %%%
'random-int'(Min, Max, Result) :-
    ( integer(Min), integer(Max), Min =< Max
      -> random_between(Min, Max, Result)
       ; catch(random_between(Min, Max, Result), E,
               rethrow_metta_operation_error('random-int', E)) ).
'random-int'('&rng', Min, Max, Result) :-
    ( integer(Min), integer(Max), Min =< Max
      -> random_between(Min, Max, Result)
       ; catch(random_between(Min, Max, Result), E,
               rethrow_metta_operation_error('random-int', E)) ).
'random-float'(Min, Max, Result) :-
    catch(( random(R), Result is Min + R * (Max - Min) ), E,
          rethrow_metta_operation_error('random-float', E)).
'random-float'('&rng', Min, Max, Result) :-
    catch(( random(R), Result is Min + R * (Max - Min) ), E,
          rethrow_metta_operation_error('random-float', E)).

%%% Runtime format strings and string ordering: %%%
%
%Both are always-loaded corelib operations rather than library ones, because
%the arbiter's corpus calls them with no import
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, the corelib blocks].
%They used to live in lib/lib_string.pl, where a program reached them only
%through (import! &self (library lib_string)) and where the formatter was a
%plain {}-substitution rather than upstream's.
%
%format-args interpolates through the dyn_fmt crate's Arguments, not Rust's
%own format!, and that formatter is looser than it looks. Two states, a
%literal PIECE and an ARG opened by `{`. In the piece state a `{` opens an
%argument and a `}` is DROPPED with the character after it taken literally,
%which is what makes `}}` print one brace. In the argument state a `}`
%consumes the next argument, or produces NOTHING once the arguments run out,
%while any other character ends the argument and is taken literally, which is
%what makes `{x}` print `x` and `{{` print one brace. A brace with nothing
%after it ends the string [source: the same file, formatPiece and formatArg,
%over https://docs.rs/dyn-fmt; measured 2026-08-19 against the arbiter:
%`"{{}}{}"` with one argument is `{}1`, `"{x}{}"` with two is `x{`, and
%`"{} and {}"` with one is `only and `, where this engine's library left the
%unfilled `{}` standing] [tested: runtime_format_strings].
'format-args'(Format, Arguments, Out) :-
    (   string(Format), is_list(Arguments)
    ->  maplist(metta_console_text, Arguments, Texts),
        string_codes(Format, Codes),
        format_piece(Texts, Codes, OutCodes),
        string_codes(Out, OutCodes)
    ;   metta_operation_answer('format-args', [Format, Arguments], Out)
    ).

format_piece(_, [], []).
format_piece(Arguments, [0'{|Rest], Out) :- !,
    ( Rest == [] -> Out = [] ; format_arg(Arguments, Rest, Out) ).
format_piece(Arguments, [0'}|Rest], Out) :- !,
    (   Rest = [Next|More]
    ->  Out = [Next|Tail],
        format_piece(Arguments, More, Tail)
    ;   Out = []
    ).
format_piece(Arguments, [Code|Rest], [Code|Tail]) :-
    format_piece(Arguments, Rest, Tail).

format_arg(_, [], []).
format_arg(Arguments, [0'}|Rest], Out) :- !,
    (   Arguments = [Text|More]
    ->  string_codes(Text, Codes),
        append(Codes, Tail, Out),
        format_piece(More, Rest, Tail)
    ;   format_piece([], Rest, Out)
    ).
format_arg(Arguments, [Code|Rest], [Code|Tail]) :-
    format_piece(Arguments, Rest, Tail).

%The CONSOLE rendering, which is what upstream interpolates: atom_to_string is
%the same rendering println! uses and it prints a string's characters with no
%quotes, which is what lets help! print documentation unquoted
%[source: the same file, formatArgsString].
metta_console_text(Value, Text) :- string(Value), !, Text = Value.
metta_console_text(Value, Text) :- sdisplay(Value, Text).

%Upstream sorts an expression of STRINGS and refuses anything else by name;
%sort-atom is the general form that orders any atom. The order is the printed
%form's, and for strings that is the strings' own
%[source: the same file, sortStringsOp and sortAtoms].
'sort-strings'(List, Out) :-
    (   is_list(List), maplist(string, List)
    ->  msort(List, Out)
    ;   metta_operation_answer('sort-strings', [List], Out)
    ).

%%% Boolean Logic: %%%
bool(true).
bool(false).
%An unbound argument ENUMERATES the booleans, so and(A, B, C) with all three
%open answers the whole truth table. That is deliberate and pinned by
%metta_operation_errors:boolean_operations_remain_relational, which is why
%these positions are relational_input_position/2 rather than guarded ones.
%ONE call per operand, with the enumeration inline: an unbound argument still
%enumerates the booleans, so and/3 with three open arguments answers the whole
%truth table, and a bound one is settled by two comparisons and no further
%call. Written as a test predicate plus a separate enumerator instead, and/3
%cost 6 inferences per call against the throwing shape's 2, and query-where
%23% [measured 2026-08-19: 688,351 inferences against 848,239].
boolean_operand(Value) :- ( var(Value) -> bool(Value) ; Value == true -> true
                          ; Value == false ).

%The soft cut is what lets an operand that is not a boolean be ANSWERED rather
%than raise while the enumeration above still runs: it takes every solution the
%operands have and reaches the refusal only when they have none. `(and True u)`
%is left as written and `(and True n)` is `(BadArgType 2 Bool Number)`
%[source: LeaTTa tests/semantics/grounded/07-partial-core.metta].
and(A,B,C) :- ( ( boolean_operand(A), boolean_operand(B) )
                *-> ( A == true -> C = B ; C = false )
                ;   metta_operation_answer(and, [A, B], C) ).
or(A,B,C) :- ( ( boolean_operand(A), boolean_operand(B) )
               *-> ( A == true -> C = true ; C = B )
               ;   metta_operation_answer(or, [A, B], C) ).
not(A,B) :- ( boolean_operand(A)
              *-> ( A == true -> B = false ; B = true )
              ;   metta_operation_answer(not, [A], B) ).
xor(A,B,C) :- ( ( boolean_operand(A), boolean_operand(B) )
                *-> ( A == B -> C = false ; C = true )
                ;   metta_operation_answer(xor, [A, B], C) ).
implies(A,B,C) :- ( ( boolean_operand(A), boolean_operand(B) )
                    *-> ( A == true -> C = B ; C = true )
                    ;   metta_operation_answer(implies, [A, B], C) ).

%%% Nondeterminism: %%%
superpose(L, _) :- var(L), !, refuse_unbound_input(superpose, 1).
superpose(L,X) :- member(X,L).
empty(_) :- fail.

%%% Lists / Tuples: %%%
%The tail's declared type is Expression [source: lib/lib_builtin_types.metta,
%(: cons-atom (-> Atom Expression Atom))], and the arbiter refuses a tail that
%is not one rather than building a term it could not print
%[source: LeaTTa MettaHyperonFull/Core/Builtins.lean, Builtins.consAtom;
%tests/regression/instruction_interp.metta pins native cons-atom and its mirror
%rejecting `(cons-atom a 1)` alike]. PeTTa BUILT the improper cons instead, and
%then could not write it: `!(cons-atom a 1)` raised swrite/2's "cannot write 1
%as MeTTa text because its printed form would read back as a different value".
%
%The refusal is the operation's own declaration read back by
%metta_operation_answer/3, so `(cons-atom a 1)` answers
%`(Error (cons-atom a 1) (BadArgType 2 Expression Number))`, and a tail whose
%type is not DECIDED, an undeclared symbol, is left unreduced as the ordinary
%three-element expression it already was.
%
%An unbound tail still builds, which is what relational_input_position/2
%declares for position 2 and what lets the third argument decompose a list.
%Nothing in the shipped corpus reaches either refusal: over 253 example
%programs the tail was a proper list 77 times and () 23 times, and never
%anything else [measured 2026-08-23].
%The test is SPELLED OUT rather than calling list_shaped/1, because this clause
%was a fact and a fact costs its caller nothing beyond the call: var/1, ==/2 and
%=/2 compile to VM instructions and raise no inference, where any predicate call
%here raises one per cons. let-heavy conses a million times and measured exactly
%that, 14,002,591 inferences against 13,002,551 [measured 2026-08-23].
'cons-atom'(H, T, Out) :-
    (   var(T)    -> Out = [H|T]
    ;   T == []   -> Out = [H]
    ;   T = [_|_] -> Out = [H|T]
    ;   metta_operation_answer('cons-atom', [H, T], Out)
    ).
%The grounded reading goes FIRST and fails fast, rather than after the cons
%clause, because the cons clause has no cut: a variable-headed clause behind it
%stays a candidate that indexing cannot rule out, so every decons of a real
%list left a choicepoint, in loops that recurse on exactly this
%[tested: decons_atom_is_total]. non_list/1 is false for both list shapes, so a
%list pays two inferences and reaches the same clauses in the same order.
'decons-atom'(Term, _) :- var(Term), !, refuse_unbound_input('decons-atom', 1).
'decons-atom'(Term, Out) :- non_list(Term), !,
                            grounded_list_view(Term, [H|T]), !, Out = [H|[T]].
%The second cut prunes the SEAM's remaining providers, which the first one
%cannot: it fires on non_list/1, before the seam has been consulted at all, so
%without this every decons of a grounded value carried a live choice point into
%whatever loop it was in [tested: a_tuple_reads_as_an_expression]. It belongs
%here, at the one caller whose own cut comes too early, rather than in the seam:
%making the seam itself deterministic costs 400 million instructions on
%alpha-unique, 10.7%, for reasons that outlive this comment
%[measured 2026-08-16, ai-design-grounded-view.md records the reproduction].
'decons-atom'([H|T], [H|[T]]).
%The empty expression answers an error rather than nothing, so decons-atom is
%TOTAL. Failing here is not "no decomposition", it is the whole continuation
%vanishing: (chain (decons-atom ()) $l TEMPLATE) never runs its template and
%the branch after it is unreachable. That cost the specification's own Turing
%machine both of its blank-cell arms and mm-switch its "no case matched" arm,
%and nothing in either program said why [source: lib/minimal_metta_lib.metta,
%recorded there as C1b and C1d].
%
%The shape is the reference implementation's, because PeTTa had no considered
%answer here to keep: failing was the absence of a clause rather than a
%decision. LeaTTa's conformance evidence pins it to the Rust interpreter,
%lib/src/metta/interpreter.rs:1750-1758, which tests the empty case as an
%execution error, and records the byte-identical output
%[source: LeaTTa tests/semantics/metaprogramming/EVIDENCE.md,
%M06 "Empty deconstruction is an error"].
%
%Three elements, which the callers need. lib_measure.metta and lib_soft.metta
%destructure with (let ($h $t) (decons-atom $ps) ...) and rely on the empty
%case not matching; a two-element error would bind $h to Error and answer a
%wrong result in silence, where a three-element one still fails to unify and
%those loops terminate exactly as before [tested: decons_atom_is_total, the_empty_error_does_not_destructure_as_a_pair].
'decons-atom'([], ['Error', ['decons-atom', []],
                   "expected: (decons-atom (: <expr> Expression)), \c
                    found: (decons-atom ())"]).
'first-from-pair'(Pair, _) :- var(Pair), !, refuse_unbound_input('first-from-pair', 1).
'first-from-pair'([A, _], A).
first(Pair, _) :- var(Pair), !, refuse_unbound_input(first, 1).
first([A, _], A).
'second-from-pair'(Pair, _) :- var(Pair), !, refuse_unbound_input('second-from-pair', 1).
'second-from-pair'([_, A], A).
'unique-atom'(A, _) :- var(A), !, refuse_unbound_input('unique-atom', 1).
'unique-atom'(A, B) :- non_list(A), !, B = [].
'unique-atom'(A, B) :- list_to_set(A, B).

%%% Alpha-equivalence unique atom %%%
'alpha-unique-atom'(A, _) :- var(A), !, refuse_unbound_input('alpha-unique-atom', 1).
'alpha-unique-atom'(A, B) :- non_list(A), !, B = [].
'alpha-unique-atom'(A, B) :- alpha_list_to_set(A, B).

alpha_list_to_set(List, Set) :-
    empty_assoc(Seen0),
    alpha_list_to_set_assoc(List, Seen0, Set).

alpha_list_to_set_assoc([], _, []).
alpha_list_to_set_assoc([H|T], SeenIn, R) :-
    copy_term(H, HCopy),
    numbervars(HCopy, 0, _),
    term_hash(HCopy, Key),
    alpha_bucket_insert(Key, HCopy, SeenIn, SeenOut, IsNew),
    ( IsNew == false ->
        alpha_list_to_set_assoc(T, SeenIn, R)
    ;
        R = [H|RT],
        alpha_list_to_set_assoc(T, SeenOut, RT)
    ).

%A term hash selects a small bucket. Identity inside the bucket decides alpha
%equivalence, because canonical terms produced above are ground.
alpha_bucket_insert(Key, Term, SeenIn, SeenOut, IsNew) :-
    ( get_assoc(Key, SeenIn, Bucket) ->
        ( memberchk_eq(Term, Bucket) ->
            SeenOut = SeenIn,
            IsNew = false
        ;
            put_assoc(Key, SeenIn, [Term|Bucket], SeenOut),
            IsNew = true
        )
    ;
        put_assoc(Key, SeenIn, [Term], SeenOut),
        IsNew = true
    ).

%A term that can never become a list, no matter how it gets instantiated:
non_list(X) :- atomic(X), X \== [].
non_list(X) :- compound(X), X \= [_|_].

%The positive reading of the same shape, and the engine's answer to "is this an
%Expression". A MeTTa Expression IS a proper list, by construction rather than
%by hope: the arbiter's Atom carries `Atom.expr (List Atom)`
%[source: LeaTTa MettaHyperonFull/Core/Builtins.lean, Builtins.consAtom], so an
%improper cons is not a term the semantics can express, and 'cons-atom'/3 above
%refuses to build one. The FIRST CELL therefore settles the question, where
%is_list/1 walks the whole list to reach the same answer.
%
%An unbound term is not an Expression, which is what is_list/1 answers for one
%and what the three callers of this predicate each relied on.
%
%Constant time, and cheaper than the walk at every length rather than only at
%long ones [measured 2026-08-23, per call: 85 nanoseconds against is_list/1's
%77 over 2 elements, 55 against 143 over 64, and 66 against 20,812 over 16,384].
list_shaped(X) :- var(X), !, fail.
list_shaped([]).
list_shaped([_|_]).
