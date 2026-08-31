% This source holds non-ASCII text, and the encoding is declared HERE, ahead
% of it, rather than inherited from the ambient locale: SWI decodes the file as
% a stream, so a directive placed after the first non-ASCII byte is already too
% late. A boot under LC_ALL=C warned `Illegal multibyte Sequence` without it,
% which is every perf-measured child, because measure_instructions builds its
% environment from a small allowlist carrying no locale.
:- encoding(utf8).

% Purpose: provide test diagnostics, assertions, formatting, timing, and bounded execution helpers
% Assumes: engine/metta.pl consults this plain file while its owning module is the load context.
% Guarantees:
%   - every definition retains engine/metta.pl's implementation module and original load order
%     [tested: tests/prolog/suites/evaluation/metta.plt, tests/prolog/static_checks.pl; commit=9a116762fb4372d55675e2ef64b7657092bc136d]
%   - assert/2 reports a failed assertion through print_message/2, so it lands on user_error and
%     an embedded host's stdout carries only that host's own writes; test/3's
%     is/should line is the one diagnostic here that stays on current_output,
%     because it prints on success too [tested:
%     test_a_failing_assertion_stays_off_the_hosts_stdout in
%     extensions/python/tests/ch10_errors_and_refusals/test_engine_diagnostics.py,
%     test_the_c_binding_suite_passes in
%     extensions/python/tests/ch21_another_language_at_the_seam/test_c_binding.py,
%     tests/shell/test_example_runner_surfaces_failures.sh;
%     commit=b7eb5734f476f8a8f5b6f16c1e71a67c72a57478]
% Fails when: loaded directly or from another module; internal state and unqualified meta-goals would acquire the wrong owner.

%%% Diagnostics / Testing: %%%
:- multifile prolog:error_message//1.
:- multifile prolog:message//1.

prolog:error_message(metta_test_failed(Actual, Expected)) -->
    [ 'MeTTa test failed: ~p does not match ~p'-[Actual, Expected] ].
%The form is a MeTTa term, so it is rendered as MeTTa text. ~p on the Prolog
%list prints `[==,[collapse,[eval,[+,1,1]]],[collapse,[eval,3]]]`, which is the
%engine's storage and not what the program wrote. Nothing rendered a list here
%until assert/2 began reporting its operand as WRITTEN rather than the True or
%False it used to receive.
prolog:error_message(metta_assertion_failed(Goal)) -->
    { sdisplay(Goal, Written) },
    [ 'MeTTa assertion failed: ~w'-[Written] ].

%The three formals above are the program saying something FALSE, which is a
%different event from the engine breaking, and a harness has to be able to
%tell them apart without reading the sentence. This is the classifier that
%lets it: Form is the MeTTa operation that failed, Actual what it got and
%Expected what it wanted, both unbound where the form carries no such value.
%
%It lives beside the throwers rather than in the Python shim because the
%formals are the ENGINE's, so the two cannot drift: adding a fourth assertion
%form and forgetting this predicate leaves that form unclassified here, where
%it is read, rather than in a file the engine never loads [tested:
%extensions/python/tests/ch12_testing/test_assertion_failures.py].
%
%Actual and Expected are handed out as WRITTEN MeTTa terms; a caller that
%has to cross them to another language converts them itself, because the
%conversion belongs to that boundary and not to the engine.
metta_assertion_failure(error(metta_test_failed(Actual, Expected), _),
                        test, Actual, Expected).
metta_assertion_failure(error(metta_assertion_failed(Goal), _), assert, Goal, _).

prolog:error_message(metta_not_a_prolog_module(File)) -->
    [ '~w is not a Prolog module, so its exports cannot be imported under \c
       other names. Add :- module(name, [pred/arity, ...]) at its top, or \c
       register it without renaming.'-[File] ].
prolog:error_message(metta_not_exported(Module, Name, Exports)) -->
    [ '~w does not export ~w, so it cannot be imported under another name. \c
       It exports ~q.'-[Module, Name, Exports] ].
%The two names a Prolog registration cannot take, thrown by
%refuse_reserved_registration/1 below and rendered here so every
%prolog:error_message//1 clause in this file stays together.
prolog:error_message(permission_error(register, metta_builtin, Name)) -->
    [ '~w is a builtin, so registering a Prolog predicate under that name \c
       would replace the engine\'s own for every space in the process. A \c
       named space compiles its own clauses, so an equation there shadows \c
       the builtin for that space alone.'-[Name] ].
prolog:error_message(permission_error(register, metta_special_form, Name)) -->
    [ '~w is a special form, which the translator compiles directly, so a \c
       registration under that name could never be reached. Pick another \c
       name, or reach the predicate with (call (~w ...)), which needs no \c
       registration.'-[Name, Name] ].
prolog:error_message(metta_extension_api_mismatch(Name, Wanted, Ours)) -->
    [ '~w was written against extension seam ~w and this engine offers ~w. \c
       A major version differs, or the extension needs a hook this engine \c
       does not have yet.'-[Name, Wanted, Ours] ].
%Thrown by refuse_untypable_declaration/3 above. The type is written back
%through swrite/2 so the author sees the MeTTa they wrote rather than its
%Prolog list.
prolog:error_message(metta_untypable_declaration(Name, Type)) -->
    { swrite(Type, Written) },
    [ '(: ~w ~w) is not an arrow, so it types the symbol ~w and not a call \c
       to it: every (~w ...) compiles with no check at all, and a wrong \c
       argument surfaces wherever it finally breaks instead of here. Write \c
       (: ~w (-> ...)), or (: ~w %Undefined%) to say ~w is deliberately \c
       untyped.'-[Name, Written, Name, Name, Name, Name, Name] ].
prolog:error_message(metta_export_form(Text)) -->
    [ 'this is not an export declaration: ~w. An export is (: name (-> ...)) \c
       or (export name arity).'-[Text] ].
prolog:error_message(metta_load_failed(Summary)) -->
    [ 'the Prolog source did not load cleanly: ~w'-[Summary] ].
prolog:error_message(metta_name_owned_by_source(Name, Owner)) -->
    [ '~w is already registered from ~w. Two libraries defining one name \c
       destroy each other\'s predicate, because a consulted file REPLACES a \c
       static one of the same name and SWI only warns. Rename yours, or \c
       unregister the extension that owns it first.'-[Name, Owner] ].
prolog:error_message(permission_error(register, metta_function, Name)) -->
    [ '~w is already registered by another extension tier. Unregister it \c
       there first, or pick another name: two tiers sharing one name leaves \c
       whichever registered second in place and the other one\'s registry \c
       still claiming it.'-[Name] ].

%The value laid out for reading: (pretty-atom $x) answers the multi-line
%string swrite_pretty produces, so (println! (pretty-atom $big)) is the
%readable dump. Data in, data out; the printing stays println!'s job.
'pretty-atom'(Term, String) :- swrite_pretty(Term, String).

%An operation that ran for its EFFECT answers `true`, the engine's convention
%for the whole family: add-atom, remove-atom, bind!, change-state!, import!,
%git-import! and the translator-rule pair all answer it.
%tests/prolog/suites/spaces/spaces.plt's an_effectful_operation_answers_true
%holds the list, so an operation joining the family without answering `true`
%fails there rather than drifting quietly; the effect PROFILES are inventoried
%separately in tests/prolog/suites/evaluation/effects.plt.
%
%This is upstream PeTTa's answer and it is also what this tree's OWN catalogue
%already declared: `(: println! (-> %Undefined% Bool))` in
%lib/lib_builtin_types/lib_builtin_types.metta said Bool while the clause here
%answered unit, so the two disagreed until now
%[source: PeTTa@ae66fa8 src/metta.pl:212, `'println!'(Arg, true)`]
%[tested: effect_answers:every_effectful_builtin_answers_true; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
'println!'(Arg, true) :- sdisplay(Arg, RArg),
                         format('~w~n', [RArg]).

%One line, one form. A form spanning two lines is a syntax error here, which
%is why 'read-form!'/1 exists beside it.
'readln!'(Out) :- read_line_to_string(user_input, Str),
                  sread(Str, Out).

%A whole form, however many lines it takes. Reads until the brackets balance,
%so a console accepts (= (f $x)<enter>(+ $x 1)) the way every other language's
%does, and an empty line re-prompts instead of erroring.
%
%This is CPython's InteractiveConsole half: the buffering and prompting sit
%here, and the decision, sread_command/2, is in the reader with no I/O at all,
%so a Jupyter kernel or an editor integration uses the same answer without
%this loop [source: CPython, the code module's split between
%InteractiveInterpreter and InteractiveConsole]
%[tested: parser_reads_a_form_across_lines].
'read-form!'(Out) :- read_form_lines([], read_form_state(0, outside, false), Out).

%The decision on its own, with no I/O: (complete Term), incomplete, or a
%raise. A console that does its own reading asks this and keeps its own
%buffer.
%
%sread_command/2 answers the Prolog compound complete(Term), which is the
%right shape for a Prolog caller and the wrong one for a MeTTa program: it
%would arrive as an opaque term rather than as an expression to match on.
'parse-command'(Text, _) :- var(Text), !, refuse_unbound_input('parse-command', 1).
'parse-command'(Text, Result) :-
    sread_command(Text, Answer),
    ( Answer = complete(Term) -> Result = [complete, Term] ; Result = Answer ).

%A form may span lines, and each new line used to be appended to the whole
%buffered text and ALL of it handed back to sread_command/2: string_codes/2 over
%it, the content scan over it, the balance scan over it, once per line. That is
%Theta(L^2) in the form's total length. One form of 1,600 lines spent
%132,673,790,292 instructions where the SAME text on one line spent
%1,484,324,191, and the cost quadrupled per doubling
%[measured 2026-08-23, ai-tmp/synth/readform/].
%
%command_balance/5 already carries its (Depth, State) from one call to the next,
%so the same question can be asked of one LINE with that state carried, which is
%Theta(L) over the whole form, and the lines are joined once when it completes.
read_form_lines(Reversed, State0, Out) :-
    read_line_to_string(user_input, Line),
    (   Line == end_of_file
    ->  (   Reversed == []
        ->  Out = end_of_file
        ;   read_form_text(Reversed, Text),
            sread(Text, Out)
        )
    ;   Buffered = [Line|Reversed],
        read_form_step(Line, State0, State, Answer),
        (   Answer == complete
        ->  read_form_text(Buffered, Text),
            sread(Text, Out)
        %Malformed, so the reader's own error is the answer, exactly as it was
        %when the whole text reached sread_command/2's last clause.
        ;   Answer == malformed
        ->  read_form_text(Buffered, Text),
            sread(Text, _)
        ;   read_form_lines(Buffered, State, Out)
        )
    ).

%One line's worth of the scan sread_command/2 runs over a whole text, carrying
%what it learned. The line BREAK belongs to the scan and not only to the text:
%it is what ends a comment, so the state has to cross it. A closing bracket too
%many is MALFORMED rather than incomplete, which is why command_balance/5 fails
%on it and no amount of further typing repairs it.
read_form_step(Line, State0, State, Answer) :-
    State0 = read_form_state(Depth0, Scan0, Content0),
    string_codes(Line, Codes),
    (   command_balance(Codes, Depth0, Scan0, Depth, AfterLine)
    ->  string_state(AfterLine, 0'\n, Scan),
        (   Content0 == true
        ->  Content = true
        ;   command_content(Codes, Scan0)
        ->  Content = true
        ;   Content = false
        ),
        State = read_form_state(Depth, Scan, Content),
        (   read_form_settled(Content, Depth, Scan)
        ->  Answer = complete
        ;   Answer = incomplete
        )
    ;   State = State0,
        Answer = malformed
    ).

read_form_settled(true, 0, Scan) :-
    % policy-inventory-exempt: mechanism-internal; reason=string and escaped are internal states of the reader state machine; evidence=engine/metta/runtime.pl:read_form_settled/3
    \+ memberchk(Scan, [string, escaped]).

read_form_text(Reversed, Text) :-
    reverse(Reversed, Lines),
    atomic_list_concat(Lines, '\n', Joined),
    atom_string(Joined, Text).

test(A,B,true) :- (A =@= B -> E = '✅' ; E = '❌'),
                  sdisplay(A, RA),
                  sdisplay(B, RB),
                  format("is ~w, should ~w. ~w ~n", [RA, RB, E]),
                  ( A =@= B -> true
                  ; throw(error(metta_test_failed(A, B),
                                context(test/3, 'MeTTa test values differ'))) ).

%ZERO ANSWERS COMPARE AS `()`, which is upstream's own shape: its test form is
%`findall(Val, Conj, Results), (Results = [Actual] -> true ; Actual = Results)`,
%and `[] = [Actual]` fails, so an expression that answered nothing is compared
%as the empty expression [source: PeTTa@ae66fa8 src/translator.pl:146-152].
%This engine threw metta_test_no_answer here instead, which made
%`!(test (f T3in) ())` unwritable -- and that line is upstream's
%examples/types_nondet.metta, where a type mismatch is SUPPOSED to answer
%nothing and the test says so. Nothing is lost by not throwing: a test whose
%expression answers nothing when a value was wanted still prints
%`is (), should <value>. ❌` and still fails the run.
%test-no-answer/2 stays, and is not a synonym for `(test X ())`: it compares
%the raw answer LIST, so it distinguishes zero answers from one answer that is
%itself the empty expression, which this predicate deliberately conflates
%exactly as upstream conflates them.
test_answer_value([], []) :- !.
test_answer_value([Actual], Actual) :- !.
test_answer_value(Results, Results).

'test-no-answer'(Results, Out) :-
    test(Results, [], Out).

%The operand crosses UNEVALUATED, because `(: assert (-> Atom (->)))` is the
%arbiter's own declaration for this name
%[source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean:1020]. So the evaluation
%is this predicate's to make, and what it can report is the form as WRITTEN:
%`!(assert (== 1 2))` answers `(Error (assert (== 1 2)) ((== 1 2) not True))`
%on the arbiter and throws here naming that same `(== 1 2)`
%[measured 2026-08-24 against LeaTTa 9ea9f9d].
%
%Before the mask reached written builtin calls the operand arrived already
%reduced and this called the resulting `True`/`False` as a Prolog goal. Once the
%declaration was honoured that call received a LIST, which SWI reads as a
%consult list: `!(assertEqual (+ 1 1) 3)` printed
%`source_sink '==' does not exist` three times and then answered true for a
%false assertion.
%
%eval/2 resolves in the calling space's module, which is what the old
%call(Module:Goal) was for: the form may name a function the space itself
%defines and those clauses are in that module and nowhere else. It is also
%nondeterministic in the operand's answers, so a form with several answers is
%checked once per answer, which is what the caller's own argument evaluation
%did before.
%
%The failure is REPORTED through print_message/2 and then thrown. It used to
%be `format("Assertion failed: ~w~n", [Written])`, which upstream wrote when
%this predicate ended in halt(1) and the print was the only report there would
%ever be (2cd191b0). 12232d25 replaced the halt with the throw below and left
%the format behind, so from then on the report went to current_output -- for a
%host that embeds SWI in its own process, that host's stdout, which it cannot
%suppress and must not have written to (CMeTTa C12; ai-cmetta-c-constraints.md).
%print_message/2 puts it on user_error, renders it through the ONE
%prolog:error_message//1 clause at the top of this file rather than a second
%spelling of the same sentence, and makes it interceptable: a host that wants
%only the ball takes the message with message_hook/3.
%
%Reporting AND throwing is deliberate, and is what SWI's own assertion/1 does
%[source: SWI-Prolog 10.1.13 library/debug.pl:391-397,
%prolog_debug:assertion_failed/2, which calls print_message(error,
%assertion_failed(Reason, G)) and then throws]. A ball can be
%swallowed by any catch/3 up the stack, and an assertion that says nothing
%when that happens is not an assertion. When the ball IS reported the two
%lines say the same thing, which is the price.
%
%The is/should line stays test/3's alone. That one prints on success too, so
%it is a trace of a check that RAN rather than a failure report, and tests/
%test_example_runner_surfaces_failures.sh reads the difference: a failing
%assert is now diagnosed on stderr only, exactly like a syntax error.
assert(Form, true) :-
    current_metta_module(Module),
    eval_metta_in_module(Module, Form, Produced),
    metta_boundary_result(Form, Produced, Value),
    (   Value == true
    ->  true
    ;   print_message(error, error(metta_assertion_failed(Form), _)),
        throw(error(metta_assertion_failed(Form),
                    context(assert/2, 'MeTTa assertion failed')))
    ).

%%% The running space: %%%
% (context-space) answers the space whose module the current goal runs in,
% so a program loaded into a named space reaches its own atoms the way a
% program in &self writes (match &self ...); outside any named space the
% answer is &self.
'context-space'(Space) :- ( current_metta_space(Space) -> true ; Space = '&self' ).

%get-type, run with the SELECTED space as the context: upstream's
%get-type-space (pinned stdlib.md:849-868). The library stub this
%replaces matched the literal &self and answered nothing for any named
%space; the engine's type machinery is module-parameterized already, so
%selection is one with_metta_module/2 around the ordinary get-type.
%A name that is not a space is refused here as it is at every other space
%door, and in the same shape, an ANSWER rather than a throw: the arbiter's
%`(Error (get-type-space not-a-space scoped-atom) get-type-space expects a
%space as the first argument)` is what the four get-doc files read back through
%this operation [source: LeaTTa tests/semantics/spaces/get_type_space.metta,
%STATUS conforms] [tested: space_argument_refusals]. Without it, space_module/2
%made a module for the name and the lookup answered &self's own declarations
%through it.
'get-type-space'(Space, _, _) :- var(Space), !,
                                 refuse_unbound_input('get-type-space', 1).
%Both clauses guard themselves rather than leaning on a cut, for the reason
%match/4's last clause records: a proof walk enumerates clauses and calls each
%body, where an earlier cut prunes nothing.
'get-type-space'(Space, X, T) :- \+ metta_space_name(Space), !,
                                 space_argument_error('get-type-space',
                                                      [Space, X], T).
'get-type-space'(Space, X, T) :- metta_space_name(Space),
                                 reported_scoped_type_answers(Space, X, Types),
                                 member(T, Types).

%get-type-space is the other reporting observer. Its underlying scoped answer
%function stays unchanged because scoped_has_type/4 is a classifier consumer.
reported_scoped_type_answers(_, X, [['->']]) :- X == [], !.
reported_scoped_type_answers(Space, [F], [Result]) :-
    nonvar(F),
    (   match_stored(Space, [':', F, [->, ['%Rest%', _], Result]],
                       Result, _)
    *-> true
    ;   seam:builtin_type_declaration(F, [->, ['%Rest%', _], Result])
    ),
    !.
reported_scoped_type_answers(Space, X, Types) :-
    scoped_type_answers(Space, X, Types).

%%% Documentation, HE's vocabulary, first class %%%
%
%The design stays lib_doc's, which was already the right one:
%documentation is ATOMS IN A SPACE, (@doc name (@desc ...) ...) is data
%a program writes and can reason about, and retrieval is a match. What
%promotion adds is reach and a second tier: these are builtins now, no
%import, they resolve against the CURRENT context rather than literal
%&self, each has a -space twin selecting any space, and get-doc falls
%back to the engine's own register, where the prelude documents its
%vocabulary, so help! answers for engine forms too.
%
%The tier split is deliberate and asymmetric. RESOLVERS (get-doc,
%help!) consult the register, because "what does this name mean" wants
%an answer wherever the name comes from. ENUMERATORS (documented,
%defined-name, undocumented) are program-scoped and skip builtins,
%because "what have I documented" and "what did I forget" are questions
%about the program, and an engine that padded the answer with its own
%vocabulary would bury the user's gap under noise.
%
%The register branch comes FIRST in get-doc for the same determinism
%reason type_declaration_in orders its tiers: a first-arg-indexed miss
%is fast for ordinary names, and the disjunction is exhausted when
%match/4 ends, so raw first-solution callers keep match's own
%choicepoint profile.
:- dynamic prelude_doc_atom/2.

'get-doc'(Name, Doc) :- current_metta_space(Space),
                        'get-doc-space'(Space, Name, Doc).

%Upstream's two-input operation. The unary overload above remains the raw-doc
%convenience MeTTa already shipped; this arity is the formal family and follows
%the pinned stdlib equations field for field.
'get-doc'(Space, _, _) :- var(Space), !,
                          refuse_unbound_input('get-doc', 1).
'get-doc'(Space, Atom, Doc) :-
    metatype_of(Atom, 'Expression'), !,
    'get-doc-atom'(Space, Atom, Doc).
'get-doc'(Space, Atom, Doc) :-
    'get-doc-single-atom'(Space, Atom, Doc).

%A document now carries a kind plus as many parameter, return, and example
%fields as its source owns. Enumerate first and inspect the proper stored list;
%an open-tailed matcher pattern does not match the engine's list store.
doc_shape(Name, ['@doc', Name|Fields]) :- Fields = [_|_].

%match_stored/4, not the door: the door answers an error atom for a name that
%is not a space, and the slot it would land in here is discarded, so the doc
%shape would come back unbound as though a document had been found.
'get-doc-space'(Space, Name, Doc) :-
    (   prelude_doc_atom(Name, Doc)
    ;   'get-atoms'(Space, Doc)
    ),
    doc_shape(Name, Doc).

%Documentation used by the formal family comes from the selected space. The
%engine's prelude register is the fallback only for the current context, where
%it represents the vocabulary that space can call. A foreign space with no
%matching atom cannot acquire ambient prose.
formal_doc_atom(Space, Name, Pattern) :-
    (   \+ \+ match_stored(Space, Pattern, Pattern, _)
    ->  match_stored(Space, Pattern, Pattern, _)
    ;   current_metta_space(Space),
        prelude_doc_atom(Name, Stored),
        Stored = Pattern
    ).

doc_type_error(['Error'|_]).

'get-doc-single-atom'(Space, _, _) :- var(Space), !,
                                      refuse_unbound_input('get-doc-single-atom', 1).
'get-doc-single-atom'(Space, Atom, Doc) :-
    'get-type-space'(Space, Atom, Type),
    (   doc_type_error(Type)
    ->  Doc = Type
    ;   Type = [->|_]
    ->  'get-doc-function'(Space, Atom, Type, Doc)
    ;   'get-doc-atom'(Space, Atom, Doc)
    ).

'get-doc-atom'(Space, _, _) :- var(Space), !,
                               refuse_unbound_input('get-doc-atom', 1).
'get-doc-atom'(Space, Atom, Doc) :-
    'get-type-space'(Space, Atom, Type),
    (   doc_type_error(Type)
    ->  Doc = Type
    ;   \+ \+ formal_doc_atom(Space, Atom, ['@doc', Atom, _])
    ->  formal_doc_atom(Space, Atom, ['@doc', Atom, Description]),
        Doc = ['@doc-formal', ['@item', Atom], ['@kind', atom],
               ['@type', Type], Description]
    ;   'get-doc-function'(Space, Atom, '%Undefined%', Doc)
    ).

'get-doc-function'(Space, _, _, _) :- var(Space), !,
                                      refuse_unbound_input('get-doc-function', 1).
'get-doc-function'(Space, Name, Type, Doc) :-
    formal_doc_atom(Space, Name,
                    ['@doc', Name, Description, ['@params', Params], Return]),
    doc_function_types(Type, Params, Types),
    doc_params(Params, Return, Types, FormalParams, FormalReturn),
    Doc = ['@doc-formal', ['@item', Name], ['@kind', function],
           ['@type', Type], Description, ['@params', FormalParams],
           FormalReturn].

doc_function_types('%Undefined%', Params, Types) :- !,
    length(Params, ParameterCount),
    TypeCount is ParameterCount + 1,
    length(Types, TypeCount),
    maplist(=('%Undefined%'), Types).
doc_function_types([->|Types], _, Types).

'get-doc-params'(Params, _, Types, _) :-
    (   var(Params)
    ->  refuse_unbound_input('get-doc-params', 1)
    ;   var(Types)
    ->  refuse_unbound_input('get-doc-params', 3)
    ;   fail
    ), !.
'get-doc-params'(Params, Return, Types, [FormalParams, FormalReturn]) :-
    doc_params(Params, Return, Types, FormalParams, FormalReturn).

doc_params([], ['@return', Description], [Type|_], [],
           ['@return', ['@type', Type], ['@desc', Description]]).
doc_params([['@param', Description]|Params], Return, [Type|Types],
           [['@param', ['@type', Type], ['@desc', Description]]|FormalParams],
           FormalReturn) :-
    doc_params(Params, Return, Types, FormalParams, FormalReturn).

'help!'(Name, []) :-
    (   \+ 'get-doc'(Name, _)
    ->  swrite(Name, S),
        format("No documentation for ~w~n", [S])
    ;   forall('get-doc'(Name, Doc),
               ( swrite(Doc, DS), format("~w~n", [DS]) ))
    ).

documented(Name) :- current_metta_space(Space),
                    'documented-space'(Space, Name).

'documented-space'(Space, Name) :- 'get-atoms'(Space, Doc),
                                   doc_shape(Name, Doc).

%The library's exact semantics: every head of an equation THE SPACE
%HOLDS, once each. Enumerating the space's own atoms is what excludes
%builtins, engine-generated lambdas, and registered operations without
%any filter list: none of them stores an equation atom here.
'defined-name'(Name) :- current_metta_space(Space),
                        distinct(Name,
                                 ( get_native_atom(Space, [=, [Name|_], _]),
                                   atom(Name) )).

undocumented(Name) :- current_metta_space(Space),
                      'undocumented-space'(Space, Name).

'undocumented-space'(Space, Name) :-
    distinct(Name,
             ( get_native_atom(Space, [=, [Name|_], _]),
               atom(Name) )),
    \+ 'get-doc-space'(Space, Name, _).

%%% Time Retrieval: %%%
'current-time'(Time) :- get_time(Time).
'format-time'(Format, _) :- var(Format), !, refuse_unbound_input('format-time', 1).
'format-time'(Format, TimeString) :- get_time(Time), format_time(atom(TimeString), Format, Time).

%%% Filesystem tests: %%%
%
%SWI's exists_file/1 is a TEST, and the engine reads a registered predicate's
%LAST argument as the output, so registering the name bare made its only
%argument the answer slot: a path could never be passed in, and
%(exists_file "run.sh") raised function_input_arities(exists_file,[0]) while
%(exists_file) alone raised "Arguments are not sufficiently instantiated". A
%declared type for it, (-> %Undefined% Bool), said it took a path all the same.
%
%That silence is already on the record from the other side. lib_import.metta
%notes removing a former guard because "It made a missing file fail SILENTLY,
%with no answer", which is exactly what a zero-input registration does: the
%call site went and the registration stayed.
%
%The wrapper is sleep/2's shape below, and it answers false rather than
%FAILING, because a test that fails is indistinguishable from a test that was
%never reached, which is what made the original symptom so hard to read
%[tested: builtin_exists_file].
'exists_file'(Path, Result) :-
    (   ( atom(Path) ; string(Path) )
    ->  ( system:exists_file(Path) -> Result = true ; Result = false )
    ;   throw_metta_type_error(exists_file, 'a path as a symbol or string', Path)
    ).

%The ZERO-INPUT spelling is the same test read backwards. The engine takes a
%registered predicate's LAST argument as the output, so (exists_file) hands its
%only argument back, and a let* binding whose pattern variable already holds a
%path passes that path IN:
%
%  (let* (($file "./data.txt") ($file (exists_file))) $file)
%
%That is how lib_import.metta guards a file before consulting it, and it is the
%only spelling upstream has, because there the name reaches SWI's own
%exists_file/1 and nothing declares a second arity
%[source: PeTTa-upstream/lib/lib_import.metta:3, commit=57f21ba9edf94bcf28cde11f938bce2c241a3709].
%
%Defining it HERE rather than inheriting SWI's is what keeps both properties at
%once. Inheriting it made `!(exists_file)` abort the whole runnable with
%exists_file/1: Arguments are not sufficiently instantiated, measured on this
%tree, which is the host-abort that
%test_an_underapplied_operation_answers_instead_of_aborting exists to forbid;
%the engine's own clause answers instead. The arity is ours, so
%retract_unrelated_system_arities/0 leaves it alone: its test is
%predicate_property(built_in), and a redefined predicate is not built_in
%[tested: builtin_exists_file_reverse_mode].
%
%An UNBOUND slot is the under-applied call rather than the reverse-mode one,
%and it answers the same partial application every other under-applied
%operation answers, because the output slot is the only argument there is
%[tested: test_an_underapplied_operation_answers_instead_of_aborting].
:- redefine_system_predicate(exists_file(_)).
'exists_file'(Path) :- var(Path), !, Path = partial(exists_file, []).
'exists_file'(Path) :- 'exists_file'(Path, true).

%%% Time control: %%%
%Suspend this evaluation. In a thread, only this thread waits.
'sleep'(Seconds, _) :- var(Seconds), !, refuse_unbound_input(sleep, 1).
'sleep'(Seconds, true) :- must_be(number, Seconds), sleep(Seconds).

%Bound a goal by wall clock, keeping every answer.
%
%call_with_time_limit/2 runs its goal as once/1, so wrapping the goal directly
%would collapse a three-answer expression to one, the trap with_mutex/2 sets.
%The findall INSIDE the limit is what avoids that: the whole enumeration is
%bounded as one unit and member/2 hands the answers back.
%
%Do not be tempted to replace this with a raw alarm/4 around the goal to get
%lazy answers. It crashes: alarm/4 with throw/1 around a deeply recursive goal
%took SIGSEGV where call_with_time_limit/2 on the identical goal unwound
%cleanly [measured 2026-08-15, ai-tmp/pool/alarm.pl]. The cost of doing this
%safely is that answers are collected before the first is yielded, which for a
%deadline-bounded call is what you want anyway.
%
%A wall-clock bound is also the only one that survives concurrency. The
%inference limit counts the calling thread only, so it does not stop work a
%hyperpose branch or a spawned future is doing [measured 2026-08-15: a 50,000
%inference limit did not stop two branches spending six million].
%
%Expiry throws rather than failing, so a partial answer set is never mistaken
%for the whole one. time_limit_exceeded is already a control exception here.
:- meta_predicate metta_timeout(+, 0, ?),
                  metta_inferences(+, 0, ?),
                  metta_elapsed(0, ?, ?),
                  metta_with_pragmas(+, 0, ?),
                  metta_host_with_stack_limit(+, 0).
%Why these helpers: a runnable's goals run as call(Module:G), so a goal a
%special form passes to a HELPER used to lose the module on the way in,
%and the helper's findall called it back in user: every one of these
%forms was silently unusable in a named space, which is every space the
%Python surface creates ("Unknown procedure" for a function the space
%plainly defines). meta_predicate makes the call site wrap the goal
%argument as Module:Goal, the manual's own maplist example.
%metta_transaction/1 takes its declaration beside its clause in
%space_hooks.pl; metta_take/2 and metta_top/3 do the same in spaces.pl,
%because a meta_predicate directive above a predicate defined
%in another file warns that it has no clauses. Baking the
%qualification at translate time was measured as the alternative and
%costs MORE where wrapper forms are retranslated per run
%(annotated-relation +2498 baked against +996 wrapped, over 500
%named-space evaluations); the wrap is free in user because an
%already-plain goal in a user-context call needs no module hop
%[source: SWI-Prolog 10.1 manual, ch. 6 defining a meta-predicate;
%measured 2026-08-18; tested spaces:wrapper_forms_run_in_named_spaces].

%The platform check comes FIRST, before the operand is even type-checked: on a
%build without library(time) there is no bound to apply, and the alternative
%is existence_error(procedure, call_with_time_limit/2) raised from here, which
%names a Prolog predicate a MeTTa author never wrote
%[tested: platform_capabilities_reduced:a_bounded_form_refuses_by_name_when_deadlines_are_absent].
metta_timeout(Seconds, Goal, Value) :-
    metta_require_platform('(timeout N Expr)', deadlines),
    must_be(number, Seconds),
    call_with_time_limit(Seconds, findall(Value, Goal, Values)),
    member(Value, Values).

%timeout's deterministic twin, the kwarg vocabulary at the language tier:
%(inferences N Expr) bounds Expr by engine steps, the same limit
%m.run(inferences=) applies one level up, so a program bounds its own
%subexpression and the bound stops at the same step on every machine.
%The whole answer set is computed under the bound, timeout's own rule, so
%a partial set is never mistaken for the whole one; expiry throws the
%reserved resource envelope the Python tier already classifies.
metta_inferences(Limit, Goal, Value) :-
    must_be(positive_integer, Limit),
    call_with_inference_limit(findall(Value, Goal, Values), Limit, Result),
    (   Result == inference_limit_exceeded
    ->  throw(error(metta_control_signal(inference_limit, Limit),
                    context(metta, inference_limit)))
    ;   true
    ),
    member(Value, Values).

%Time one answer and report what it cost, as (Value Seconds). Each answer is
%timed from the start of the call, so backtracking into a later answer reports
%the total spent reaching it rather than restarting the clock.
metta_elapsed(Goal, Value, [Value, Seconds]) :-
    get_time(Start),
    Goal,
    get_time(End),
    Seconds is End - Start.
