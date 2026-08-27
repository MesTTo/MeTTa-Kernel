% Purpose: randomized property testing under plunit. A property is an
%   ordinary predicate whose head arguments are Value:Type pairs; quickcheck/1
%   generates values for the named types, calls the property, and on a failure
%   shrinks the counter-example before throwing error(counter_example, Ex).
%
%   VENDORED, not written here. This is Michael Hendricks' `quickcheck` pack
%   version 0.3.0, PUBLIC DOMAIN under the Unlicense (vendor/LICENSE, copied
%   verbatim from the repository, byte-identical to mavis' and list_util's)
%   [source: https://github.com/mndrix/quickcheck at 87dddf9, read 2026-08-19;
%   pack.pl names Nico Gallinal as 0.3.0's packager and
%   https://github.com/nicoabie/quickcheck as its current home]. What the
%   vendoring changed, and nothing else:
%
%   - the pack's four files become one. quickcheck.pl carried `:- [arbitrary].`,
%     `:- [shrink].` and `:- [composite].`, each loading a file with no module
%     declaration into this module. Each directive is replaced by that file's
%     text at the directive's own position, so the load ORDER is the order the
%     pack had, and the vendored file/end file banners keep it diff-able
%     against upstream section by section.
%
%   The pack is not on this box and pack_install is a network call a gate
%   cannot make, which is why the code is here rather than a dependency.
% Assumes:
%   - a property's first clause head carries the types, because quickcheck/1
%     reads them with clause/2 and unifies the head. A property with no clause
%     raises existence_error [source: the code below].
%   - library(random)'s generator is process-global, so a caller that wants a
%     repeatable run seeds it with set_random/1 before calling quickcheck/1.
%     The pack has no seed of its own [source: arbitrary.pl below, which draws
%     from random_between/3, random_member/2 and random/1].
% Guarantees:
%   - quickcheck/1 fails no test silently: it either succeeds or throws
%     error(counter_example, Example) naming the shrunken values
%     [tested: property_lane_selftest, planted_misprinter_is_caught].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%%%%%%%%%% vendored quickcheck.pl %%%%%%%%%%
:- module(quickcheck, [ arbitrary/2
                      , arbitrary_type/1
                      , shrink/3
                      , quickcheck/1
                      ]).
:- use_module(library(error), [existence_error/2]).
:- use_module(library(settings), [setting/4, setting/2]).

% Module settings
% ---------------
:- setting( test_count, positive_integer, 100, 'Number of random test cases to generate for each test.').


%% arbitrary(+Type, -Value) is det.
%
%  Generate a random Value of Type. If you define your own types, add
%  clauses to this multifile predicate to support them in quickcheck.
%  When defining your own types, it can be helpful to call arbitrary/2
%  recursively or to use library(random).
%
%  The following types from library(error) have built in support.
%
%    * `any`
%    * `atom`
%    * `atomic`
%    * between(L,U)
%    * `boolean`
%    * `chars`
%    * `code` - printable ASCII for now
%    * `codes`
%    * `encoding`
%    * `float`
%    * `integer`
%    * `list`
%    * list(T)
%    * `negative_integer`
%    * `nonneg alias natural`
%    * `number`
%    * oneof(L)
%    * `positive_integer`
%    * `rational`
%    * `string`
%    * `text`
:- multifile arbitrary/2.

%%%%%%%%%% vendored arbitrary.pl %%%%%%%%%%
% define arbitrary/2 and friends

:- use_module(library(apply), [maplist/2]).

:- if(\+ predicate_property(maplist(_,  _, _),_)).

:- use_module(library(apply_macros), [maplist/3]).

:- endif.

:- use_module(library(random), [random_between/3, random_member/2, random/1]).
:- if(\+predicate_property(random_between(_, _, _), _)).

:- use_module(library(random), [random/3]).

random_between(Lo, Hi, X) :-
        random(Lo, Hi, X).

:- endif.

:- if(\+predicate_property(random_member(_, _), _)).

random_member(X, Xs) :-
        length(Xs, N),
        random_between(1, N, I),
        nth(I, Xs, X).

:- endif.

%% arbitrary_type(?Type) is multi
%
%  True if Type supports arbitrary/2.
arbitrary_type(Type) :-
    clause(arbitrary(Type, _), _).

% TODO does this code make any sense?
:- multifile error:has_type/2.
error:has_type(arbitrary_type, Type) :-
    nonvar(Type),
    \+ \+ quickcheck:arbitrary_type(Type).

arbitrary(any, X) :-
    setof( Type
         , ( arbitrary_type(Type)
           , ground(Type)  % exclude parameterized types
           , Type \== any  % don't recurse
           )
         , Types
         ),
    random_member(Type, Types),
    arbitrary(Type, X).

arbitrary(boolean, X) :-
    random_member(X, [true, false]).

arbitrary(list, X) :-
    arbitrary(list(any), X).

arbitrary(list(T), X) :-
    random_between(1,30,Length),
    length(X, Length),
    maplist(arbitrary(T), X).

arbitrary(oneof(L), X) :-
    random_member(X, L).

arbitrary(between(L,U), X) :-
    ((integer(L), integer(U)) ->
     random_between(L,U,X)
    ;
     random(L, U, X)
    ).

arbitrary(code, X) :-
    random_between(0x20, 0x7e, X).  % printable ASCII

arbitrary(codes, X) :-
    arbitrary(list(code), X).

arbitrary(atom, X) :-
    arbitrary(codes, Codes),
    atom_codes(X, Codes).

arbitrary(float, X) :-
    arbitrary(integer, I),
    random(F), 
    X is I * F.

arbitrary(integer, X) :-
    random_between(-30000, 30000, X).

arbitrary(string, X) :-
    arbitrary(codes, Codes),
    string_codes(X, Codes).

arbitrary(atomic, X) :-
    random_member(Type, [atom,float,integer,string]),
    arbitrary(Type, X).

arbitrary(chars, X) :-
    arbitrary(atom, Atom),
    atom_chars(Atom, X).

arbitrary(text, X) :-
    random_member(Type, [atom, string, chars, codes]),
    arbitrary(Type, X).

arbitrary(number, X) :-
    random_member(Type, [integer, float]),
    arbitrary(Type, X).

arbitrary(natural, X) :-
    arbitrary(nonneg, X).

arbitrary(nonneg, X) :-
    random_between(0, 30000, X).

arbitrary(positive_integer, X) :-
    random_between(1, 30000, X).

arbitrary(negative_integer, X) :-
    random_between(-30000, -1, X).

arbitrary(rational, X) :-
    arbitrary(integer, Numerator),
    arbitrary(integer, Denominator),
    X is Numerator rdiv Denominator.

arbitrary(encoding, X) :-
    setof(E, error:current_encoding(E), Encodings),
    random_member(X, Encodings).
%%%%%%%%%% end arbitrary.pl %%%%%%%%%%



%% shrink(+Type, +Value, -Smaller) is nondet.
%
%  True if Smaller is a "smaller" version of Value according to the
%  semantics of Type. This predicate is called after
%  quickcheck finds a Value for which a property fails. By recursively
%  shrinking values, we can obtain a minimal, failing example.
%
%  When defining shrink/3 for your own types, be sure to fail if Value
%  cannot be shrunk any smaller. It's acceptable to produce additional
%  shrunken values on backtracking. It's often best to bisect your
%  type's values (rather than iterating all possible, smaller values) if
%  bisecting makes for your type.
:- multifile shrink/3.

%%%%%%%%%% vendored shrink.pl %%%%%%%%%%
:- use_module(library(lists)).


shrink(any, X, X).

shrink(atom, Atom, Shrunk) :-
    atom_codes(Atom, Codes0),
    shrink(codes, Codes0, Codes),
    atom_codes(Shrunk, Codes).

shrink(code, _, 0'a).
shrink(code, _, 0'b).
shrink(code, _, 0'c).
shrink(code, _, 0' ).

shrink(codes, Codes0, Codes) :-
    shrink(list(code), Codes0, Codes).

shrink(integer, _, 0).  % zero often triggers bugs
shrink(integer, X, Y) :-
    % bisect from 1 towards the integer
    X > 0,
    MaxExponent is floor(log(abs(X))),
    between(0,MaxExponent,Exponent),
    Y is sign(X) * round(exp(Exponent)).
shrink(integer, X, Y) :-
    % try a positive version of a negative integer
    X < 0,
    Y is -X.

shrink(list, L0, L) :-
    shrink(list(any), L0, L).

shrink(list(_), L0, L) :-
    shrink_list_bisect(L0, L).
shrink(list(Type), L0, L) :-
    shrink_list_one(Type, L0, L).

shrink(string, String, Shrunk) :-
    string_codes(String, Codes),
    subset_gen(ShrunkCodes, Codes),
    string_codes(Shrunk, ShrunkCodes).


% help shrink lists with bisection
shrink_list_bisect(L0, L) :-
    length(L0, Len),
    Len > 0,
    MaxExponent is ceiling(log(Len)),
    between(0,MaxExponent,Exponent),
    N is round(exp(MaxExponent-Exponent)),
    shrink_list_bisect_(L0, Len, N, L).

% shrink by removing large pieces of a list
shrink_list_bisect_([], _, _, []).
shrink_list_bisect_(_, Len, N, []) :-
    N > Len.
shrink_list_bisect_(L0, Len, N, L) :-
    length(Front, N),
    append(Front, Back, L0),
    ( L = Back
    ; BackLen is Len - N,
      shrink_list_bisect_(Back, BackLen, N, NewBack),
      append(Front, NewBack, L)
    ).

% shrink by removing or shrinking individual list elements
shrink_list_one(_, [], []).
shrink_list_one(Type, [H0|T], [H|T]) :-
    shrink(Type, H0, H).
shrink_list_one(Type, [H|T0], [H|T]) :-
    shrink_list_one(Type, T0, T).


%% subset_gen(-Subset, +Set) is det.
%
% Generates subsets for the given set.
%
% base case
subset_gen([], []).
% inductive case
subset_gen(Subset, [_ | Set]) :- subset_gen(Subset, Set).
subset_gen([H |Subset], [H | Set]) :- subset_gen(Subset, Set).
%%%%%%%%%% end shrink.pl %%%%%%%%%%


%% composite(+Type, +Arbitrary:BaseType, -Value) is det.
%
%  Generate a random Value of Type from a given Arbitrary.
:- multifile composite/3.

%%%%%%%%%% vendored composite.pl %%%%%%%%%%
%CHANGED HERE, and it is the one behavioural change in this file. The clause
%below asks `clause(quickcheck:has_type(Type,_), _)` to find out whether a user
%wrote a has_type/2 for a composite, which the pack's own README tells them to
%do. Every SWI module inherits from `user`, so where nobody wrote one that call
%does not fail: it RESOLVES to user:has_type/2, and this engine defines one
%[engine/metta.pl:1203, MeTTa's own type predicate, which COMPUTES a type by
%binding its second argument rather than testing it]. The result was that
%loading this pack beside the engine turned every must_be/2 whose check would
%have failed into a binding type inference: `must_be(atom, Var)` succeeded and
%left Var bound to '%Undefined%', so a variable-headed equation the engine
%refuses was accepted and compiled [measured 2026-08-19,
%tests/prolog/suites/spaces/spaces.plt:a_variable_headed_equation_raises_either_way went red
%under the typed build and nowhere else].
%
%One declaration fixes it. Declaring has_type/2 multifile HERE gives the module
%a local predicate with no clauses, so the inheritance fallback stops and
%clause/2 fails as the code expects, while a user's own
%`quickcheck:has_type(odd, X) :- ...` still lands exactly where the README says
%it does. The other three extension points, arbitrary/2, shrink/3 and
%composite/3, were already declared; this one was the omission.
:- multifile has_type/2.

:- multifile error:has_type/2.
error:has_type(Type, Term) :-
  (clause(quickcheck:has_type(Type, _), _) -> 
    quickcheck:has_type(Type, Term)
    ;
    % verify there is a composite of the given type
    clause(composite(Type, _, _), _),
    % run the composite backwards
    composite(Type, Arbitraries, Term),
    % verify base values are of proper types
    forall(member(ArbValue:ArbType, Arbitraries), is_of_type(ArbType, ArbValue))
  ).
%%%%%%%%%% end composite.pl %%%%%%%%%%


%% quickcheck(+Property:atom) is semidet.
%
%  True if Property holds for many random values. Property should be a
%  Name/Arity term. Details about test results are displayed
%  on the `user_error` stream.
:- meta_predicate quickcheck(:).
quickcheck(Module:Property/Arity) :-
    % make sure the property predicate exists
    ( Module:current_predicate(Property/Arity) ->
        true
    ; % property predicate missing ->
        existence_error(predicate, Module:Property/Arity)
    ),

    % what type is each argument?
    functor(Head, Property, Arity),
    once(Module:clause(Head, _)),
    Head =.. [Property|Args],

    % run randomized tests
    setting(test_count, TestCount),
    run_tests(TestCount, Module, Property, Args, Result),
    ( Result = ok ->
        warn("~d tests OK", [TestCount])
    ; Result = fail(Example) ->
        ExampleGoal =.. [Property|Example],
        warn("Failed test ~q", [ExampleGoal]),
        throw(error(counter_example, Example))
    ).

head([H|_], H).

run_tests(TestCount, Module, Property, Args, fail(Example)) :-
    between(1,TestCount,_),
    generate_arguments(Args, Values, ValuesWithBaseTypes),
    Goal =.. [Property|Values],
    \+ Module:Goal,
    !,

    % try shrinking this counter example
    shrink_example(0, Module, Property, ValuesWithBaseTypes, Example).
run_tests(_, _, _, _, ok).


% generates argument for simple arbitraries types
generate_argument(_:Type, [Value:Type]) :-
    arbitrary(Type, Value).

% generates argument for composites of one arbitrary type
generate_argument(_:Type, [Value:Type, BaseValue:BaseType]) :-
    % verify there is a composite of the given type
    clause(composite(Type, _:BaseType, _), _),
    generate_argument(_:BaseType, [BaseValue:BaseType]),
    composite(Type, BaseValue:BaseType, Value).

% generates argument for composites of many arbitraries types
generate_argument(_:Type, [Value:Type|BaseValues]) :-
    % verify there is a composite of the given type
    clause(composite(Type, [HBaseTypes|TBaseTypes], _), _),
    generate_arguments([HBaseTypes|TBaseTypes], BaseValues, _),
    composite(Type, BaseValues, Value).

generate_arguments(Args, Values, ValuesWithBaseTypes) :-
    maplist(generate_argument, Args, ValuesWithBaseTypes),
    maplist(head, ValuesWithBaseTypes, Values).


% shrink a typed argument
shrink_argument(Value:Type, [Shrunken:Type]) :-
    shrink(Type, Value, Shrunken).
shrink_argument([Value:Type], [Shrunken:Type]) :-
    shrink(Type, Value, Shrunken).

% shrink a composite argument
% we are not interested in the current value
% we need to generate shrunken values of the base
% arbitraries and then make a composite
shrink_argument([_:Type|BaseValuesWithTypes], [Shrunken:Type|ShrunkenBaseValuesWithTypes]) :-
    % verify there is a composite of the given type
    clause(composite(Type, BaseValuesWithTypes, _), _),
    shrink_arguments(BaseValuesWithTypes, ShrunkenBaseValuesWithTypes, _),
    composite(Type, ShrunkenBaseValuesWithTypes, Shrunken).

% there is no shrinker for the given Type
% return the same Value as shrunken
shrink_argument([Value:Type|T], [Value:Type|T]).

shrink_arguments(ValuesWithBaseTypes, Shrunk, ShrunkWithBaseTypes) :-
    maplist(shrink_argument, ValuesWithBaseTypes, ShrunkWithBaseTypes),
    maplist(head, ShrunkWithBaseTypes, Shrunk).


shrink_example(Depth0, Module, Property, ValuesWithBaseTypes, Example) :-
    Depth0 < 32,
    shrink_arguments(ValuesWithBaseTypes, Shrunk, ShrunkWithBaseTypes),
    ValuesWithBaseTypes \== ShrunkWithBaseTypes,
    ShrinkGoal =.. [Property|Shrunk],
    \+ Module:ShrinkGoal,
    !,
    Depth is Depth0 + 1,
    shrink_example(Depth, Module, Property, ShrunkWithBaseTypes, Example).

shrink_example(Depth,_,_,ValuesWithBaseTypes, Example) :-
    warn("Shrinking to depth ~d", [Depth]),
    % omit base types in example
    maplist(head, ValuesWithBaseTypes, Example).


:- dynamic tap_raw:is_test_running/0, tap_raw:diag/2.

warn(Format,Args) :-
    current_module(tap_raw),
    tap_raw:is_test_running,
    !,
    tap_raw:diag(Format,Args).
warn(Format,Args) :-
    format(user_error,Format,Args),
    writeln('').
    
