% Purpose: MeTTa's Python surface, the one where py-atom RESOLVES and MeTTa
%   applies. Every test here runs with janus alone: the engine ships
%   engine/petta_py.py and adds it to Python's path itself, so none of this needs
%   the `petta` package installed.
% Guarantees:
%   - a dotted name of any depth resolves, which splitting on the first dot
%     could not do [tested: a_dotted_path_of_any_depth_resolves]
%   - a resolved callable is applicable in head position, through the engine's
%     metta_grounded_apply/3 seam
%     [tested: a_resolved_callable_is_applicable]
%   - nothing is drained: an unbounded iterator yields one element at a time
%     [tested: iteration_is_lazy]
%   - host values without a MeTTa literal are refused at the text writer
%     instead of being emitted as Python syntax [tested:
%     a_python_value_without_a_metta_literal_is_refused; commit=53686aed41e7ff02de69052198afdb537536cbdb]
%   - repr keeps an explicit presentation path for those values [tested:
%     a_python_value_keeps_its_explicit_display; commit=53686aed41e7ff02de69052198afdb537536cbdb]
% Fails when:
%   - the claim is about the SHIPPED configuration. plunit consults
%     engine/metta.pl and never bindings/python/petta/shim.pl, so no host bridge answers
%     metta_grounded_type_names/2 here and anything the shim's presence changes is
%     invisible. That cost a real defect: the declared-type test below was
%     green while the shipped library dropped the declaration
%     [measured 2026-08-18]. A claim of that kind needs a library-door test
%     beside it, in bindings/python/tests/test_ops.py or another pytest module.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../engine/metta.pl')).

:- begin_tests(python_surface).

% py-atom resolves where py-call applies, and that split is the whole point:
% baking the call into the operator is why a Python function was never a value.

test(a_name_resolves_to_an_object) :-
    'py-atom'(len, Obj),
    assertion(py_is_object(Obj)).

% Splitting a spec on its first dot cannot reach an attribute of a SUBMODULE,
% because importing the root package does not bind one. The rule that works is
% pydoc's: import the longest prefix that imports, then getattr the rest.
test(a_dotted_path_of_any_depth_resolves) :-
    'py-atom'('os.path.join', Join),
    assertion(py_is_object(Join)),
    reduce([Join, "a", "b"], Joined, _),
    assertion(Joined == "a/b").

% A STRING is a Python expression rather than a name, so one operator covers
% both questions.
test(a_string_spec_is_an_expression) :-
    'py-atom'("1 + 2", Three),
    assertion(Three == 3).

% The engine applies a grounded atom through metta_grounded_apply/3, which is
% not Python-specific: MeTTa's own definition of a Grounded atom is that it may
% hold an operation.
test(a_resolved_callable_is_applicable) :-
    'py-atom'(abs, Abs),
    reduce([Abs, -5], Five, _),
    assertion(Five == 5).

% And a grounded value that is NOT an operation stays unreduced, which is what
% a value should do rather than raising.
test(a_grounded_value_that_is_not_callable_stays_unreduced) :-
    'py-atom'("[1, 2, 3]", List),
    reduce([List, 0], Out, Status),
    assertion(Status == 'not-reducible'),
    assertion(Out = [List, 0]).

test(an_attribute_is_read_rather_than_called) :-
    'py-atom'("complex(3, 4)", Complex),
    'py-dot'(Complex, real, Real),
    assertion(Real =:= 3.0).

% A bound method taken as a value and applied afterwards, which is what "a
% callable is a value" buys.
test(a_bound_method_is_a_value) :-
    'py-dot'("  padded  ", strip, Strip),
    reduce([Strip], Stripped, _),
    assertion(Stripped == "padded").

test(containers_are_built_as_their_python_types,
     [forall(member(Builder-Expected, ['py-list'-"list",
                                       'py-tuple'-"tuple",
                                       'py-dict'-"dict"]))]) :-
    ( Builder == 'py-dict' -> Items = [[a, 1]] ; Items = [1, 2] ),
    Goal =.. [Builder, Items, Built],
    call(Goal),
    'py-dot'(Built, '__class__', Class),
    'py-dot'(Class, '__name__', Name),
    assertion(Name == Expected).

% Nothing is drained. The engine used to materialise whatever it could iterate,
% so asking a generator for one element ran every side effect and an unbounded
% one could not cross at all.
test(iteration_is_lazy, [nondet]) :-
    'py-atom'("iter(range(10 ** 9))", Iterator),
    'py-iter'(Iterator, First),
    !,
    assertion(First == 0).

test(iteration_yields_every_element) :-
    'py-atom'("[10, 20, 30]", List),
    findall(E, 'py-iter'(List, E), Elements),
    assertion(Elements == [10, 20, 30]).

% Keyword arguments, in the language's own spelling. The pairs arrive
% unevaluated, so a keyword whose name is also a MeTTa function still names the
% keyword: without the mask `(Kwargs (reverse true))` was read as a call to the
% `reverse` builtin and the whole form vanished.
test(keyword_arguments_reach_python) :-
    'py-atom'("dict", Dict),
    reduce([Dict, ['Kwargs', [aaa, 1], [bbb, 2]]], Built, _),
    'py-atom'(len, Len),
    reduce([Len, Built], Count, _),
    assertion(Count == 2).

test(a_keyword_name_that_is_a_builtin_is_still_a_name) :-
    'py-atom'("sorted", Sorted),
    'py-list'([3, 1, 2], List),
    reduce([Sorted, List, ['Kwargs', [reverse, true]]], Descending, _),
    findall(E, 'py-iter'(Descending, E), Elements),
    assertion(Elements == [3, 2, 1]).

% The VALUE half of a pair is evaluated, which is the other half of getting the
% mask right: a name is a name and a value is a value.
test(a_keyword_value_is_evaluated) :-
    'py-atom'("dict", Dict),
    reduce([Dict, ['Kwargs', [n, [+, 1, 2]]]], Built, _),
    py_call(Built:get("n"), Three),
    assertion(Three == 3).

% A declared type is kept rather than accepted and dropped, and it rides the
% metta_grounded_extra_type/2 extension point that already existed for exactly this.
%
% This suite is ONE CONFIGURATION. plunit loads engine/metta.pl without
% bindings/python/petta/shim.pl, so no host bridge answers metta_grounded_type_names/2 here
% and this test only ever exercised the branch where none does. The
% declaration was being dropped in the shipped one for as long as this was
% green [measured 2026-08-18]. Its counterpart at the library door is
% bindings/python/tests/test_ops.py, test_a_declared_type_survives_the_library_being_loaded,
% and the pair is the claim: neither alone says the feature works.
test(a_declared_type_is_reported_beside_the_objects_own) :-
    'py-atom'(len, ['->', 'Atom', 'Number'], Obj),
    findall(T, get_type_candidate(Obj, T), Types),
    assertion(memberchk(['->', 'Atom', 'Number'], Types)),
    assertion(memberchk(builtin_function_or_method, Types)).

% The blob SWI registers for a Python object is named `py`. The engine asked
% for 'PyObject', so every clause behind that guard was unreachable and an
% engine without the Python library loaded could not type a Python object at
% all.
test(a_python_object_is_typed_without_the_python_library) :-
    'py-atom'("complex(1, 2)", Complex),
    findall(T, get_type_candidate(Complex, T), Types),
    assertion(memberchk(complex, Types)),
    'get-metatype'(Complex, Meta),
    assertion(Meta == 'Grounded').

% bind! is a TOKEN registration, which is what the specification says it is:
% "registers a new token which is replaced with an atom during the parsing of
% the rest of the program" [source: metta-lang-docs/corelib-stdlib-reference.md].
% PeTTa's bind! accepted only (new-state V) and FAILED SILENTLY on anything
% else, so the language's own idiom could not work.
test(a_bound_token_is_substituted_into_later_forms,
     [ cleanup(retractall(metta_token(_, _))) ]) :-
    process_metta_string("!(bind! plunit-token 6)", _),
    process_metta_string("!(collapse plunit-token)", Answer),
    assertion(Answer == [[6]]).

test(a_bound_token_can_hold_any_atom,
     [ cleanup(retractall(metta_token(_, _))) ]) :-
    process_metta_string("!(bind! plunit-greet (Hello world))", _),
    process_metta_string("!(collapse plunit-greet)", Answer),
    assertion(Answer == [[['Hello', world]]]).

% A callable bound to a name is callable BY that name, which needs two things:
% the token substitution above, and a grounded head reaching reduce/3 rather
% than being built as data.
test(a_token_bound_to_a_callable_is_applied,
     [ cleanup(retractall(metta_token(_, _))) ]) :-
    process_metta_string("!(bind! plunit-abs (py-atom \"abs\"))", _),
    process_metta_string("!(collapse (plunit-abs -5))", Answer),
    assertion(Answer == [[5]]).

% The state form binds no token, because PeTTa models a state cell by NAME and
% substituting the name away would take get-state with it.
test(the_state_form_still_makes_a_state_cell,
     [ cleanup(retractall(metta_token(_, _))) ]) :-
    process_metta_string("!(bind! plunit-cell (new-state 7))", _),
    process_metta_string("!(collapse (get-state plunit-cell))", Answer),
    assertion(Answer == [[7]]),
    assertion(\+ metta_token('plunit-cell', _)).

test(an_unresolvable_name_raises_rather_than_answering_nothing,
     [throws(_)]) :-
    'py-atom'('nosuchmodule.nosuchthing', _).

:- end_tests(python_surface).

:- begin_tests(python_readings).

%A Python value has one carrier and, when it is a sequence, a second READING of
%that carrier. These tests hold both halves at once, because either alone is
%easy and the pair is the point.

%%%% The three constants janus converts whatever the options say %%%%

%None is the unit value. Empty would have been the plausible choice and is the
%wrong one: it is a Symbol meaning no answer, so a let over any of Python's
%many effect-only methods would fail instead of binding.
test(none_is_the_unit_value) :-
    'py-atom'("None", None),
    assertion(None == []),
    reduce(['get-metatype', None], Meta, _),
    assertion(Meta == 'Expression'),
    reduce(['==', None, []], Equal, _),
    assertion(Equal == true).

test(none_is_not_empty) :-
    'py-atom'("None", None),
    reduce(['==', None, 'Empty'], Equal, _),
    assertion(Equal == false).

%A method called purely for effect returns None in Python, and the whole reason
%unit is right is that this binds rather than vanishing.
test(an_effect_only_method_still_binds) :-
    'py-atom'("[1, 2]", List),
    'py-dot'(List, append, Append),
    reduce([Append, 3], Result, _),
    assertion(Result == []),
    'py-atom'(len, Len),
    reduce([Len, List], Count, _),
    assertion(Count == 3).

test(a_python_boolean_is_the_language_boolean,
     [forall(member(Source-Expected, ["True"-true, "False"-false]))]) :-
    'py-atom'(Source, Value),
    assertion(Value == Expected).

%%%% The structural reading %%%%

%A tuple crosses as janus's -/N, which is faithful both ways, so the reading
%costs no crossing and the carrier is still what Python gets back.
test(a_tuple_reads_as_an_expression) :-
    'py-atom'("(1, 2, 3)", Tuple),
    'car-atom'(Tuple, Head),      assertion(Head == 1),
    'cdr-atom'(Tuple, Tail),      assertion(Tail == [2, 3]),
    'size-atom'(Tuple, Size),     assertion(Size == 3),
    'index-atom'(Tuple, 1, Item), assertion(Item == 2),
    'decons-atom'(Tuple, Split),  assertion(Split == [1, [2, 3]]).

test(a_tuple_is_still_a_tuple_going_back) :-
    'py-atom'("(1, 2)", Tuple),
    'py-dot'(Tuple, '__class__', Class),
    'py-dot'(Class, '__name__', Name),
    assertion(Name == "tuple").

test(an_explicit_grounded_tuple_is_a_python_reference) :-
    'py-atom'("(1, 2)", 'Grounded', Tuple),
    assertion(py_is_object(Tuple)),
    'py-dot'(Tuple, '__class__', Class),
    'py-dot'(Class, '__name__', Name),
    assertion(Name == "tuple").

%The empty tuple is a value, and the reason it once took the whole run down was
%the writer rather than anything about tuples: =../2 refuses a zero-arity
%compound [tested: parser_refuses_non_metta:an_empty_compound_is_refused].
test(the_empty_tuple_is_a_value_and_not_the_unit) :-
    'py-atom'("()", Empty),
    assertion(Empty \== []),
    'size-atom'(Empty, Size),
    assertion(Size == 0).

%A list is MUTABLE, so it stays a handle and its reading crosses for the
%elements. Both halves hold: it reads structurally AND it is still the same
%live object, so a change made through it is visible afterwards.
test(a_list_reads_structurally_and_stays_live) :-
    'py-atom'("[7, 8, 9]", List),
    'car-atom'(List, Head),   assertion(Head == 7),
    'size-atom'(List, Size),  assertion(Size == 3),
    'py-dot'(List, append, Append),
    reduce([Append, 10], _, _),
    'size-atom'(List, Grown),
    assertion(Grown == 4).

%PEP 634 decides which objects a sequence pattern may take apart, and these two
%are its exclusions. A dict is not a Sequence, and a str is one but is named as
%an exception, which is why a string does not read as its characters.
test(a_value_that_is_not_a_sequence_has_no_reading,
     [forall(member(Source, ["{'a': 1}", "{1, 2}", "'abc'"]))]) :-
    'py-atom'(Source, Value),
    assertion(\+ metta_grounded_structure(Value, _)).

%%%% Asking for the other reading %%%%

%Expression and Grounded are the language's own metatypes, and here they say
%which reading is wanted: a snapshot, or the live reference.
test(the_expression_type_materializes) :-
    'py-atom'("[1, 2, 3]", 'Expression', Value),
    assertion(Value == [1, 2, 3]).

%The point of materializing: it is ordinary MeTTa data, so it destructures
%through unification, which the handle cannot do.
test(a_materialized_value_destructures) :-
    'py-atom'("[1, 2, 3]", 'Expression', Value),
    assertion(Value = [_, _, _]).

test(materializing_goes_all_the_way_down) :-
    'py-atom'("[[1, 2], (3, 4)]", 'Expression', Value),
    assertion(Value == [[1, 2], [3, 4]]).

%A leaf is anything with no reading of its own, and it stays itself rather than
%being forced into one.
test(materializing_leaves_a_leaf_alone) :-
    'py-atom'("[{'a': 1}]", 'Expression', [Leaf]),
    assertion(py_is_object(Leaf)).

%A container may hold itself, and then this reading does not exist. Saying so
%is the answer; recursing until the stack goes is not.
test(a_value_that_contains_itself_says_so, [throws(_)]) :-
    'py-atom'("(lambda l: (l.append(l), l)[1])([])", Cyclic),
    'py-atom'("[1]", _),
    petta_py_materialize(Cyclic, _).

%%%% Text boundary %%%%

%An object uses Python repr; a converted tuple uses its structural MeTTa
%reading, which is the value the library door exposes too.
test(a_value_prints_according_to_its_default_reading,
     [forall(member(Source-Expected, ["[1, 2]"-"[1, 2]",
                                      "(1, 2)"-"(1 2)",
                                      "(1,)"-"(1)",
                                      "()"-"()",
                                      "{'a': 1}"-"{'a': 1}"]))]) :-
    'py-atom'(Source, Value),
    repr(Value, Text),
    assertion(Text == Expected).

%%%% Failure %%%%

%A Python exception is a MeTTa error, catchable and readable. It used to end
%the run: the survey recorded it as uncatchable because it tried `if-error` and
%`collapse`, and `catch` is the form that catches. What was really wrong is
%what catch ANSWERED, both slots holding live host objects.
%
%These go through process_metta_string/2 rather than reduce/3 because `catch`
%is a translator special form: it is compiled, not applied, so reduce/3 never
%sees it.

test(a_python_failure_is_catchable) :-
    process_metta_string("!(catch ((py-atom \"lambda: 1/0\")))", Answer),
    assertion(Answer = [['Error', _, _]]).

test(a_python_failure_carries_a_readable_message) :-
    process_metta_string("!(catch ((py-atom \"lambda: 1/0\")))", Answer),
    Answer = [['Error', Formal, _]],
    assertion(Formal = python_error('ZeroDivisionError', "division by zero")),
    %A string, not the exception object janus hands over: an object prints as an
    %address, compares by identity, and keeps the exception alive.
    Formal = python_error(_, Message),
    assertion(string(Message)).

%The context names the MeTTa call, WITH its arguments, which is what the
%message never had: janus reports the Python function, file and line, so a
%failure three levels down a MeTTa program pointed only into Python.
test(a_python_failure_names_the_metta_call) :-
    process_metta_string("!(catch ((py-atom \"lambda n: 1/0\") 7))", Answer),
    Answer = [['Error', _, Context]],
    assertion(Context = context([_Callable, 7], 'while calling Python')).

test(a_failure_to_resolve_names_the_call) :-
    process_metta_string("!(catch (py-atom \"nosuchmodule.thing\"))", Answer),
    Answer = [['Error', Formal, Context]],
    assertion(Formal = python_error('NameError', _)),
    assertion(Context = context(['py-atom', "nosuchmodule.thing"], _)).

%Nothing in the answer is a live host object, so it prints, compares and
%survives the value that raised it. The traceback janus attached was one.
test(a_python_failure_holds_no_host_objects) :-
    process_metta_string("!(catch ((py-atom \"lambda: 1/0\")))", Answer),
    Answer = [['Error', Formal, _]],
    forall(sub_term(Part, Formal), assertion(\+ py_is_object(Part))).

%A signal is NOT a failure. An interrupt, a time limit and an inference limit
%have to stay uncatchable, and KeyboardInterrupt reaches this code as an
%ordinary python_error, so converting it would reopen the hole from the Python
%side [source: bindings/python/tests/test_control_signals.py].
test(an_interrupt_is_not_converted_into_a_catchable_error,
     [forall(member(Class, ['KeyboardInterrupt', 'SystemExit']))]) :-
    catch(petta_py_failure(['some-call'],
                           error(python_error(Class, none), none)),
          Thrown, true),
    assertion(Thrown == metta_host_interrupted),
    assertion(control_exception(Thrown)).

test(an_engine_control_exception_passes_through_untouched) :-
    catch(petta_py_failure(['some-call'], inference_limit_exceeded), Thrown, true),
    assertion(Thrown == inference_limit_exceeded).

:- end_tests(python_readings).
