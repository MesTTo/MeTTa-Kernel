% Purpose: verify file-reader splitting, loader rollback, global function
%   scope, late-definition repair, and translation-error reporting.
% Guarantees:
%   - Failed loads and reloaded source contributions leave no orphaned support
%     graph state and preserve aggregate links owned by surviving source files
%     [tested: filereader_source_rollback:failed_load_removes_compiler_state_and_generated_lambdas,
%     filereader_source_reload:reloading_one_contributor_preserves_another_contributors_support;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - The grouped reader records its source contribution and returns one
%     answer group per runnable form after end-of-source repair
%     [tested: filereader_source_reload:a_grouped_load_runs_inside_the_source_lifecycle;
%     commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3].
%   - MeTTa source files retain non-ASCII heads under the C locale [tested:
%     filereader_source_reload:a_source_is_utf8_independent_of_the_locale;
%     commit=18b1135167d60396c41e63e42ded2f66d0eb1900].
%   - A committed public erase makes an import receipt stale, a rolled-back
%     erase preserves it, and the next public import rebuilds the exact source
%     contribution [tested:
%     filereader_import_lifecycle:
%     a_receipt_tracks_the_liveness_of_its_exact_stored_outputs;
%     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- encoding(utf8).
:- ensure_loaded('../../../../engine/qlf_boot.pl').
:- ensure_loaded('../../../../engine/metta.pl').

test_lambda_functions(Functions) :-
    findall(F,
            ( user:fun(F),
              atom(F),
              sub_atom(F, 0, 7, _, lambda_) ),
            Functions0),
    sort(Functions0, Functions).

cleanup_test_function(F) :-
    user:metta_self_module(SelfModule),
    specializer:forget_symbol(SelfModule, F),
    retractall(user:symbol_head(F, _)),
    retractall(user:fun_in(_, F)),
    retractall(user:fun_scoped(F)).

cleanup_new_lambdas(Before) :-
    test_lambda_functions(After),
    subtract(After, Before, Added),
    maplist(cleanup_test_function, Added).

:- begin_tests(filereader_translation_errors).

test(an_untranslatable_form_is_not_reported_as_invalid_syntax,
     [throws(error(metta_translation_failed(unhandled_form), _))]) :-
    filereader:process_form('&self', unhandled_form, _).

test(translation_error_has_an_engine_message) :-
    message_to_string(error(metta_translation_failed(unhandled_form), none),
                      Message),
    once(sub_string(Message, _, _, _, "Could not translate MeTTa form")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(filereader_translation_errors).

:- begin_tests(filereader_form_splitter).

test(escaped_quote_does_not_close_a_string_or_form) :-
    Source = "!(test \"quote: \\\" and )\" \"quote: \\\" and )\")\n!(quote done)",
    string_codes(Source, Codes),
    once(phrase(filereader:top_forms(Forms, 1), Codes)),
    Forms = [runnable(First), runnable(Second)],
    sread(First, FirstTerm),
    sread(Second, SecondTerm),
    FirstTerm == [test, "quote: \" and )", "quote: \" and )"],
    SecondTerm == [quote, done].

test(loader_and_reader_agree_on_inline_comments) :-
    sread("(a ; ignored tokens\n b)", ReadTerm),
    setup_call_cleanup(assertz(silent(true), Ref),
                       process_metta_string("!(noeval (a ; ignored tokens\n b))",
                                            Results),
                       erase(Ref)),
    ReadTerm == [a, b],
    Results == [[a, b]].

test(comment_parentheses_do_not_close_a_form) :-
    Source = "!(quote (a ; ignored ) and (!( \"\n b))\n!(quote done)",
    string_codes(Source, Codes),
    once(phrase(filereader:top_forms(Forms, 1), Codes)),
    Forms = [runnable(First), runnable(Second)],
    sread(First, FirstTerm),
    sread(Second, SecondTerm),
    FirstTerm == [quote, [a, b]],
    SecondTerm == [quote, done].

%A top-level form is ONE ATOM, and a parenthesised expression is only the
%commonest kind. The four splitter tests below pin the reader against the
%arbiter's own tokenizer rule: a leading `!` before `(`, layout or end of
%input marks the atom that follows as runnable, and a `!` anywhere else is
%an ordinary symbol character [source: LeaTTa
%MettaHyperonFull/Runtime/Parser.lean:85-88].
test(a_bare_symbol_is_a_top_level_form) :-
    string_codes("not-a-form", Codes),
    once(phrase(filereader:top_forms(Forms, 1), Codes)),
    Forms == [form("not-a-form")].

test(the_marker_takes_an_atom_of_any_kind) :-
    string_codes("! untouched-symbol\n! 42\n! \"a b\"\n! $free\n! &first",
                 Codes),
    once(phrase(filereader:top_forms(Forms, 1), Codes)),
    Forms == [runnable("untouched-symbol"), runnable("42"),
              runnable("\"a b\""), runnable("$free"), runnable("&first")].

%`!42` and `!$x` print nothing under the arbiter because its tokenizer keeps
%the `!` inside the symbol; only `(`, layout and end of input make it the
%marker [measured 2026-08-19: LeaTTa --observed-file on each exits 0 with no
%output].
test(a_marker_before_a_non_boundary_stays_an_ordinary_symbol_character) :-
    string_codes("!42\n!$x\n!(f)", Codes),
    once(phrase(filereader:top_forms(Forms, 1), Codes)),
    Forms == [form("!42"), form("!$x"), runnable("(f)")].

%The same measurement: a file ending in a bare `!` exits 0 and prints
%nothing, so the marker with no atom after it contributes no form.
test(a_trailing_marker_contributes_no_form) :-
    string_codes("!(f)\n!", Codes),
    once(phrase(filereader:top_forms(Forms, 1), Codes)),
    Forms == [runnable("(f)")].

test(missing_form_close_reports_its_syntax_error,
     [throws(error(syntax_error(_), none))]) :-
    string_codes("(not-closed", Codes),
    phrase(filereader:top_forms(_, 1), Codes).

:- end_tests(filereader_form_splitter).

:- begin_tests(filereader_bare_top_level_atoms).

%Both halves end to end: the marked atom evaluates to itself and the
%unmarked one is stored, which is what the arbiter does with each
%[source: LeaTTa tests/semantics/eval-core/self-evaluating-atoms.metta,
%grounded/25-state-rendering.metta, modules/09-bind/main.metta].
test(a_marked_bare_atom_evaluates_to_itself) :-
    setup_call_cleanup(
        assertz(silent(true), Ref),
        process_metta_string("! untouched-symbol\n! 42\n! \"text\"", Results),
        erase(Ref)),
    Results == ['untouched-symbol', 42, "text"].

test(an_unmarked_bare_atom_is_stored_as_data) :-
    setup_call_cleanup(
        assertz(silent(true), Ref),
        ( process_metta_string("stored-bare-atom", []),
          process_metta_string("!(match &self stored-bare-atom found)",
                               Results) ),
        erase(Ref)),
    Results == [found].

:- end_tests(filereader_bare_top_level_atoms).

:- begin_tests(filereader_comments).

%A source reaches the comment grammar through two doors: sread/2 on its own and
%the loader's raw-source splitter followed by sread/2. The two have to agree, so
%each case goes through both. parser.plt covers the reader on its own.
comment_case("(a ; ignored tokens\n b)", [a, b]).
comment_case("; a leading comment\n(a b)", [a, b]).
comment_case("(value \"a;b\")", [value, "a;b"]).
comment_case("(a b) ; a comment with no trailing newline", [a, b]).

test(the_loader_and_the_reader_agree_on_comments,
     [forall(comment_case(Source, Expected))]) :-
    sread(Source, Direct),
    Direct == Expected,
    %The wrapper's own ) goes on the next line: a comment that runs to end of
    %input would otherwise swallow it, which is what it is supposed to do.
    format(string(Runnable), "!(noeval ~s~n)", [Source]),
    setup_call_cleanup(assertz(silent(true), Ref),
                       process_metta_string(Runnable, Results),
                       erase(Ref)),
    Results == [Expected].

:- end_tests(filereader_comments).

:- begin_tests(filereader_terminal_output).

test(nonterminal_loader_output_has_no_ansi_escapes) :-
    with_output_to(string(Output),
                   process_metta_string("!(noeval answer)", Results)),
    Results == [answer],
    once(sub_string(Output, _, _, _, "--> metta runnable  -->")),
    \+ sub_string(Output, _, _, _, "\e[").

:- end_tests(filereader_terminal_output).

:- begin_tests(filereader_source_rollback).

test(failed_load_removes_compiler_state_and_generated_lambdas) :-
    Outer = 'plunit-loader-rollback-outer',
    Symbol = 'plunit-loader-rollback-symbol',
    RuntimeFunction = 'plunit-loader-runtime-function',
    test_lambda_functions(BeforeLambdas),
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(= (~w) (|-> ($x) (+ $x 1)))~n", [Outer]),
    format(Stream, "!(~w)~n", [Symbol]),
    format(Stream,
           "!(add-atom &self (plunit-loader-runtime-atom value))~n", []),
    format(Stream, "!(add-atom &self (= (~w $x) (+ $x 2)))~n",
           [RuntimeFunction]),
    %A form that RAISES, because integer division by zero and wrongly typed
    %operands are both ANSWERS now and a form that answers does not roll its
    %source back. `+` with two unknowns and an unbound result is the arithmetic
    %refusal: no finite domain to search, so nothing to enumerate.
    format(Stream, "!(+ $x $y)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( catch(filereader:load_metta_file(Path, _), Error, true),
          Error = error(metta_unsolved_arithmetic('+', unbounded_domain), _),
          flag('$gs_lambda_', LambdaNumber, LambdaNumber),
          format(atom(GeneratedLambda), 'lambda_~d', [LambdaNumber]),
          test_lambda_functions(AfterLambdas),
          AfterLambdas == BeforeLambdas,
          \+ user:fun(Outer),
          \+ user:arity(Outer, _),
          \+ translator:fun_meta_clause(_, Outer, _, _),
          \+ user:symbol_head(Symbol, _),
          \+ user:fun(GeneratedLambda),
          \+ user:arity(GeneratedLambda, _),
          \+ translator:fun_meta_clause(_, GeneratedLambda, _, _),
          \+ user:fun(RuntimeFunction),
          \+ user:arity(RuntimeFunction, _),
          \+ translator:fun_meta_clause(_, RuntimeFunction, _, _),
          \+ user:supports(_, compiled_function(_, Outer)),
          \+ user:supports(_, compiled_function(_, RuntimeFunction)),
          \+ user:supports(_, function(_, Outer)),
          \+ user:supports(_, function(_, RuntimeFunction)),
          functor(Head, Outer, 1),
          \+ clause(user:Head, _),
          functor(LambdaHead, GeneratedLambda, 2),
          \+ clause(user:LambdaHead, _),
          functor(RuntimeHead, RuntimeFunction, 2),
          \+ clause(user:RuntimeHead, _),
          \+ user:'get-atoms'('&self', [=, [Outer], _]),
          \+ user:'get-atoms'('&self',
                              ['plunit-loader-runtime-atom', value]),
          \+ user:'get-atoms'('&self',
                              [=, [RuntimeFunction, _], _]),
          \+ filereader:compiled_metta_source(Path),
          \+ user:imported_metta_source(_, Path),
          \+ user:import_life(_, Path, _) ),
        ( cleanup_test_function(Outer),
          cleanup_test_function(RuntimeFunction),
          retractall(user:symbol_head(Symbol, _)),
          cleanup_new_lambdas(BeforeLambdas),
          retractall(filereader:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )).

test(late_registration_recompile_replaces_metadata,
     [ setup((cleanup_test_function('plunit-repair-caller'),
              cleanup_test_function('plunit-repair-late'))),
       cleanup((cleanup_test_function('plunit-repair-caller'),
                cleanup_test_function('plunit-repair-late'))) ]) :-
    filereader:process_metta_string(
        "(= (plunit-repair-caller $x) (plunit-repair-late $x))", _),
    aggregate_all(count,
                  translator:fun_meta_clause(_, 'plunit-repair-caller', _, _),
                  Before),
    filereader:process_metta_string(
        "(= (plunit-repair-late $x) (+ $x 1))", _),
    aggregate_all(count,
                  translator:fun_meta_clause(_, 'plunit-repair-caller', _, _),
                  After),
    filereader:process_metta_string("!(plunit-repair-caller 41)", Results),
    Before == 1,
    After == 1,
    Results == [42].

test(failed_late_definition_does_not_recompile_existing_callers,
     [ setup((cleanup_test_function('plunit-rollback-caller'),
              cleanup_test_function('plunit-rollback-late'))),
       cleanup((cleanup_test_function('plunit-rollback-caller'),
                cleanup_test_function('plunit-rollback-late'))) ]) :-
    filereader:process_metta_string(
        "(= (plunit-rollback-caller $x) (plunit-rollback-late $x))", _),
    tmp_file_stream(text, Path, Stream),
    format(Stream,
           "(= (plunit-rollback-late $x) (+ $x 1))~n!(+ $a $b)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( catch(filereader:load_metta_file(Path, _), Error, true),
          Error = error(metta_unsolved_arithmetic('+', unbounded_domain), _),
          filereader:process_metta_string("!(plunit-rollback-caller 41)", Results),
          aggregate_all(count,
                        translator:fun_meta_clause(_, 'plunit-rollback-caller', _, _),
                        MetaCount),
          Results == [['plunit-rollback-late', 41]],
          MetaCount == 1,
          \+ translator:fun_meta_clause(_, 'plunit-rollback-late', _, _) ),
        ( retractall(filereader:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )).

:- end_tests(filereader_source_rollback).

%The engine's own door onto a reload. The Python library's is tested from the
%Python side in
%extensions/python/tests/ch05_equations_and_evaluation/test_reload.py; what these
%hold is the state the engine keeps about a file, which no Python assertion can
%see.
:- begin_tests(filereader_source_reload).

write_reload_source(Path, Text) :-
    setup_call_cleanup(open(Path, write, Stream),
                       write(Stream, Text),
                       close(Stream)).

write_reload_source_utf8(Path, Text) :-
    setup_call_cleanup(open(Path, write, Stream, [encoding(utf8)]),
                       write(Stream, Text),
                       close(Stream)).

reload_scratch_file(Path) :-
    tmp_file(plunit_reload, Base),
    file_name_extension(Base, metta, Path).

forget_reload_source(Path, Function) :-
    cleanup_test_function(Function),
    retractall(filereader:metta_source_load(Path, _, _, _)),
    retractall(filereader:compiled_metta_source(Path)),
    retractall(user:imported_metta_source(_, Path)),
    retractall(user:import_life(_, Path, _)),
    ( exists_file(Path) -> delete_file(Path) ; true ).

test(a_load_records_what_the_file_contributed) :-
    F = 'plunit-reload-recorded',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-recorded) 1)\n"),
        ( filereader:load_metta_file(Path, _, '&self'),
          absolute_file_name(Path, Canon, [access(read)]),
          once(filereader:metta_source_load(Canon, Space, LoadId, Digest)),
          Space == '&self',
          atom_length(Digest, 64),
          aggregate_all(count, filereader:source_load_assertion(LoadId, _), Asserted),
          Asserted > 0 ),
        forget_reload_source(Path, F)).

test(a_grouped_load_runs_inside_the_source_lifecycle) :-
    F = 'plunit-grouped-lifecycle',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(
            Path,
            "(= (plunit-grouped-lifecycle $x) (+ $x 1))\n!(plunit-grouped-lifecycle 41)\n"),
        ( filereader:load_metta_source_groups(Path, '&self', [Group]),
          maplist(user:metta_answer_term, Group, Answers),
          Answers == [42],
          absolute_file_name(Path, Canon, [access(read)]),
          once(filereader:metta_source_load(Canon, '&self', LoadId, Digest)),
          atom_length(Digest, 64),
          once(filereader:source_load_assertion(LoadId, _)) ),
        forget_reload_source(Path, F)).

test(a_source_is_utf8_independent_of_the_locale) :-
    F = 'plunit-utf8-head',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source_utf8(
            Path,
            "(= (plunit-utf8-head ×) matched)\n"),
        setup_call_cleanup(
            setlocale(ctype, OldLocale, 'C'),
            ( filereader:load_metta_file(Path, _, '&self'),
              filereader:process_metta_string(
                  "!(plunit-utf8-head ×)", Results),
              Results == [matched] ),
            setlocale(ctype, _, OldLocale)),
        forget_reload_source(Path, F)).

test(an_unchanged_file_is_not_loaded_again) :-
    F = 'plunit-reload-unchanged',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-unchanged) 1)\n"),
        ( filereader:load_metta_file(Path, _, '&self'),
          absolute_file_name(Path, Canon, [access(read)]),
          once(filereader:metta_source_load(Canon, '&self', FirstId, _)),
          filereader:load_metta_file(Path, _, '&self'),
          once(filereader:metta_source_load(Canon, '&self', AgainId, _)),
          AgainId == FirstId,
          \+ filereader:metta_source_changed(Canon) ),
        forget_reload_source(Path, F)).

%The same length either side, so a check on the modification time would have
%to see a difference the coarse clock may not have recorded.
test(an_edit_that_keeps_the_length_is_still_a_change) :-
    F = 'plunit-reload-samesize',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-samesize) 1)\n"),
        ( filereader:load_metta_file(Path, _, '&self'),
          absolute_file_name(Path, Canon, [access(read)]),
          write_reload_source(Path, "(= (plunit-reload-samesize) 2)\n"),
          filereader:metta_source_changed(Canon),
          filereader:load_metta_file(Path, _, '&self'),
          findall(V, user:'get-atoms'('&self', [=, [F], V]), Values),
          Values == [2] ),
        forget_reload_source(Path, F)).

test(a_reload_leaves_one_clause_for_a_redefined_function) :-
    F = 'plunit-reload-oneclause',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-oneclause) 1)\n"),
        ( filereader:load_metta_file(Path, _, '&self'),
          write_reload_source(Path, "(= (plunit-reload-oneclause) 2)\n"),
          filereader:load_metta_file(Path, _, '&self'),
          user:metta_self_module(Self),
          functor(Head, F, 1),
          aggregate_all(count, clause(Self:Head, _), Clauses),
          Clauses == 1,
          findall(T, filereader:translated_from(_, [=, [F], T]), Sources),
          Sources == [2] ),
        forget_reload_source(Path, F)).

test(reloading_one_contributor_preserves_another_contributors_support) :-
    F = 'plunit-reload-shared-support',
    Other = 'plunit-reload-shared-other',
    reload_scratch_file(PathA),
    reload_scratch_file(PathB),
    setup_call_cleanup(
        ( write_reload_source(
              PathA,
              "(= (plunit-reload-shared-support left) 1)\n"),
          write_reload_source(
              PathB,
              "(= (plunit-reload-shared-support right) 2)\n") ),
        ( filereader:load_metta_file(PathA, _, '&self'),
          filereader:load_metta_file(PathB, _, '&self'),
          write_reload_source(
              PathA,
              "(= (plunit-reload-shared-other) 3)\n"),
          filereader:load_metta_file(PathA, _, '&self'),
          user:metta_self_module(Module),
          assertion(user:supports(compiled_function(Module, F),
                                  function(Module, F))),
          assertion(filereader:translated_from(
                        _, [=, [F, right], 2])) ),
        ( forget_reload_source(PathA, F),
          forget_reload_source(PathB, F),
          cleanup_test_function(Other) )).

test(a_dependent_recompile_keeps_its_original_source_owner) :-
    Caller = 'plunit-owner-caller',
    Callee = 'plunit-owner-callee',
    Other = 'plunit-owner-other',
    reload_scratch_file(PathA),
    reload_scratch_file(PathB),
    setup_call_cleanup(
        ( write_reload_source(
              PathA,
              "(= (plunit-owner-caller) (plunit-owner-callee))\n"),
          write_reload_source(
              PathB,
              "(= (plunit-owner-callee) 42)\n") ),
        ( filereader:load_metta_file(PathA, _, '&self'),
          filereader:metta_source_load(PathA, '&self', CallerLoad, _),
          filereader:load_metta_file(PathB, _, '&self'),
          filereader:metta_source_load(PathB, '&self', CalleeLoad, _),
          once(filereader:translated_from(
                   Recompiled,
                   [=, [Caller], [Callee]])),
          once(filereader:source_load_assertion(
                   CallerLoad, artifact, Recompiled)),
          \+ filereader:source_load_assertion(
                 CalleeLoad, artifact, Recompiled),
          write_reload_source(
              PathB,
              "(= (plunit-owner-other) 7)\n"),
          filereader:load_metta_file(PathB, _, '&self'),
          once(filereader:translated_from(
                   Restored,
                   [=, [Caller], [Callee]])),
          once(filereader:source_load_assertion(
                   CallerLoad, artifact, Restored)),
          filereader:process_metta_string(
              "!(plunit-owner-caller)", Answers),
          Answers == [[Callee]] ),
        ( forget_reload_source(PathA, Caller),
          forget_reload_source(PathB, Callee),
          cleanup_test_function(Other) )).

:- end_tests(filereader_source_reload).

:- begin_tests(filereader_global_function_scope).

test(file_function_remains_a_global_fallback_after_a_named_homonym) :-
    Function = 'plunit-global-file-function',
    NamedSpace = '&plunit_file_homonym',
    OtherSpace = '&plunit_file_other',
    cleanup_test_function(Function),
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(= (~w $x) (+ $x 1))~n", [Function]),
    close(Stream),
    NamedTerm = [=, [Function, X], [+, X, 100]],
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            true,
            ( filereader:load_metta_file(Path, _),
              user:'add-atom'(NamedSpace, NamedTerm, _),
              filereader:process_metta_string(
                  "!(plunit-global-file-function 41)", Results, OtherSpace),
              %fun_in/2 is a relation; whether a bound-bound probe runs
              %determinate is JIT-index luck (the engine's own callers
              %always wrap it in -> or once), so the at-most-once intent
              %is stated here rather than assumed.
              user:metta_self_module(Self),
              once(user:fun_in(Self, Function)),
              Results == [42] ),
            ( user:'remove-atom'(NamedSpace, NamedTerm, _),
              cleanup_test_function(Function),
              retractall(filereader:compiled_metta_source(Path)),
              retractall(user:imported_metta_source(_, Path)),
              delete_file(Path) )),
        erase(SilentRef)).

:- end_tests(filereader_global_function_scope).

:- begin_tests(filereader_source_prefix).

test(a_runnable_sees_repaired_forward_callers) :-
    FileF = 'plunit-file-forward-f',
    FileG = 'plunit-file-forward-g',
    DynamicF = 'plunit-dynamic-forward-f',
    DynamicG = 'plunit-dynamic-forward-g',
    tmp_file_stream(text, Path, Stream),
    format(Stream,
           "(= (~w) (~w))~n(= (~w) 42)~n!(~w)~n",
           [FileF, FileG, FileG, FileF]),
    close(Stream),
    format(string(DynamicSource),
           "(= (~w) (~w))~n(= (~w) 42)~n!(~w)~n",
           [DynamicF, DynamicG, DynamicG, DynamicF]),
    setup_call_cleanup(
        true,
        ( filereader:load_metta_file(Path, FileAnswers, '&self'),
          filereader:process_metta_string(DynamicSource,
                                          DynamicAnswers,
                                          '&self'),
          assertion(FileAnswers == [42]),
          assertion(DynamicAnswers == [42]) ),
        ( cleanup_test_function(FileF),
          cleanup_test_function(FileG),
          cleanup_test_function(DynamicF),
          cleanup_test_function(DynamicG),
          retractall(filereader:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )).

:- end_tests(filereader_source_prefix).

:- begin_tests(filereader_control_errors).

test(loader_catches_do_not_consume_control_exceptions) :-
    tmp_file_stream(text, Path, Stream),
    format(Stream, "!(plunit-loader-control)~n", []),
    close(Stream),
    setup_call_cleanup(
        ( assertz((user:'plunit-loader-control'(_) :-
                       throw(inference_limit_exceeded)), ClauseRef),
          % The public route, not register_fun/1: registering a Prolog
          % predicate is what import_prolog_function/2 is for, and it is what
          % records the arity the call compiles against.
          user:import_prolog_function('plunit-loader-control', _) ),
        catch(filereader:load_metta_file(Path, _), Error, true),
        ( erase(ClauseRef),
          user:unregister_fun_everywhere('plunit-loader-control'),
          retractall(user:fun('plunit-loader-control')),
          retractall(user:arity('plunit-loader-control', _)),
          retractall(filereader:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )),
    Error == inference_limit_exceeded.

test(cleared_native_space_repopulates_compiled_source) :-
    Space = '&plunit_loader_life',
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(loader-life-marker payload)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( filereader:load_metta_file(Path, _, Space),
          once(user:'get-atoms'(Space, ['loader-life-marker', payload])),
          user:clear_native_atoms(Space),
          \+ user:'get-atoms'(Space, ['loader-life-marker', payload]),
          filereader:load_metta_file(Path, _, Space),
          once(user:'get-atoms'(Space, ['loader-life-marker', payload])) ),
        ( user:clear_native_atoms(Space),
          retractall(filereader:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(Space, Path)),
          delete_file(Path) )).

:- end_tests(filereader_control_errors).

:- begin_tests(filereader_import_lifecycle).

test(a_receipt_tracks_the_liveness_of_its_exact_stored_outputs) :-
    Space = '&plunit_import_receipt',
    tmp_file(metta, Base),
    atom_concat(Base, '.metta', Path0),
    open(Path0, write, Stream),
    format(Stream,
           "(= (plunit-import-receipt $x) (quote $x))~n", []),
    close(Stream),
    absolute_file_name(Path0, Path, [access(read)]),
    Equation = [=, ['plunit-import-receipt', X], [quote, X]],
    setup_call_cleanup(
        true,
        ( user:'import!'(Space, Path, []),
          user:import_receipt(Space, Path, LoadId, Digest),
          user:import_receipt_current(Space, Path),
          filereader:metta_source_load(Path, Space, LoadId, Digest),
          once(( filereader:source_load_assertion(LoadId, stored, StoredRef),
                 user:stored_atom_of_ref(StoredRef, Space, Stored),
                 Stored =@= Equation )),
          catch(
              transaction(
                  ( user:'remove-atom'(Space, Equation, []),
                    throw(plunit_receipt_rollback) )),
              plunit_receipt_rollback,
              true),
          user:import_receipt_current(Space, Path),
          user:'remove-atom'(Space, Equation, []),
          \+ user:import_receipt_current(Space, Path),
          user:'import!'(Space, Path, []),
          user:import_receipt_current(Space, Path),
          aggregate_all(
              count,
              user:'get-atoms'(
                  Space,
                  [=, ['plunit-import-receipt', _], [quote, _]]),
              Count),
          Count == 1 ),
        ( user:metta_release_space(Space),
          delete_file(Path) )).

test(removing_a_local_shadow_rearms_an_already_compiled_inherited_call) :-
    ParentSpace = '&self',
    ChildSpace = '&plunit_import_shadow_child',
    Function = 'plunit-import-shadow-call',
    ParentEquation = [=, [Function], parent],
    ChildEquation = [=, [Function], child],
    setup_call_cleanup(
        ( user:metta_add_atom(ParentSpace, ParentEquation, true),
          user:metta_add_atom(ChildSpace, ChildEquation, true),
          user:space_module(ChildSpace, ChildModule),
          Call =.. [Function, Answer],
          assertz(user:(plunit_saved_shadow_call(Answer) :-
                           ChildModule:Call),
                  SavedRef) ),
        ( findall(Before, user:plunit_saved_shadow_call(Before), [child]),
          user:metta_remove_atom(ChildSpace, ChildEquation, true),
          findall(After, user:plunit_saved_shadow_call(After), [parent]),
          functor(Direct, Function, 1),
          arg(1, Direct, DirectAnswer),
          findall(DirectAnswer, call(ChildModule:Direct), [parent]),
          Replacement = [=, [Function], replacement],
          user:metta_add_atom(ChildSpace, Replacement, true),
          findall(Replaced, user:plunit_saved_shadow_call(Replaced),
                  [replacement]),
          user:space_module(ParentSpace, ParentModule),
          functor(ParentCall, Function, 1),
          arg(1, ParentCall, ParentAnswer),
          findall(ParentAnswer, call(ParentModule:ParentCall), [parent]) ),
        ( catch(erase(SavedRef), _, true),
          user:metta_release_space(ChildSpace),
          user:metta_remove_atom(ParentSpace, ParentEquation, _) )).

test(a_repaired_shadow_import_follows_a_recycled_modules_new_parent) :-
    FirstParent = '&plunit_shadow_parent_first',
    SecondParent = '&plunit_shadow_parent_second',
    Child = '&plunit_shadow_reparented_child',
    Function = 'plunit-reparented-shadow-call',
    FirstEquation = [=, [Function], first],
    SecondEquation = [=, [Function], second],
    LocalEquation = [=, [Function], local],
    setup_call_cleanup(
        ( user:metta_add_atom(FirstParent, FirstEquation, true),
          user:metta_add_atom(SecondParent, SecondEquation, true),
          user:metta_declare_space_parent(Child, FirstParent),
          user:metta_add_atom(Child, LocalEquation, true),
          user:space_module(Child, ChildModule),
          Call =.. [Function, Answer],
          assertz(user:(plunit_saved_reparented_call(Answer) :-
                           ChildModule:Call),
                  SavedRef) ),
        ( findall(Before, user:plunit_saved_reparented_call(Before), [local]),
          user:metta_release_space(Child),
          user:metta_declare_space_parent(Child, SecondParent),
          user:space_module(Child, ChildModule),
          findall(After, user:plunit_saved_reparented_call(After), [second]) ),
        ( catch(erase(SavedRef), _, true),
          catch(user:metta_release_space(Child), _, true),
          user:metta_release_space(FirstParent),
          user:metta_release_space(SecondParent) )).

test(a_failed_local_redefinition_restores_the_repaired_inherited_call) :-
    ParentSpace = '&self',
    ChildSpace = '&plunit_failed_shadow_child',
    Function = 'plunit-failed-shadow-call',
    ParentEquation = [=, [Function], parent],
    ChildEquation = [=, [Function], child],
    FailedEquation = [=, [Function], never_committed],
    setup_call_cleanup(
        ( user:metta_add_atom(ParentSpace, ParentEquation, true),
          user:metta_add_atom(ChildSpace, ChildEquation, true),
          user:space_module(ChildSpace, ChildModule),
          Call =.. [Function, Answer],
          assertz(user:(plunit_saved_failed_shadow_call(Answer) :-
                           ChildModule:Call),
                  SavedRef) ),
        ( user:metta_remove_atom(ChildSpace, ChildEquation, true),
          setup_call_cleanup(
              assertz((seam:function_changed(Function) :-
                           throw(error(plunit_failed_shadow_redefinition,
                                       none))),
                      HookRef),
              catch(user:metta_add_atom(ChildSpace, FailedEquation, true),
                    Error,
                    true),
              erase(HookRef)),
          Error = error(plunit_failed_shadow_redefinition, none),
          findall(After, user:plunit_saved_failed_shadow_call(After),
                  [parent]),
          \+ user:'get-atoms'(ChildSpace, FailedEquation) ),
        ( catch(erase(SavedRef), _, true),
          user:metta_release_space(ChildSpace),
          user:metta_remove_atom(ParentSpace, ParentEquation, _) )).

test(a_failed_first_source_load_restores_the_repaired_inherited_call) :-
    ParentSpace = '&self',
    ChildSpace = '&plunit_failed_source_shadow_child',
    Function = 'plunit-failed-source-shadow-call',
    ParentEquation = [=, [Function], parent],
    ChildEquation = [=, [Function], child],
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(= (~w) never-committed)~n", [Function]),
    close(Stream),
    setup_call_cleanup(
        ( user:metta_add_atom(ParentSpace, ParentEquation, true),
          user:metta_add_atom(ChildSpace, ChildEquation, true),
          user:space_module(ChildSpace, ChildModule),
          Call =.. [Function, Answer],
          assertz(user:(plunit_saved_failed_source_call(Answer) :-
                           ChildModule:Call),
                  SavedRef) ),
        ( user:metta_remove_atom(ChildSpace, ChildEquation, true),
          setup_call_cleanup(
              assertz((seam:function_changed(Function) :-
                           throw(error(plunit_failed_source_shadow,
                                       none))),
                      HookRef),
              catch(filereader:load_metta_file(Path, _, ChildSpace),
                    Error,
                    true),
              erase(HookRef)),
          Error = error(plunit_failed_source_shadow, context(Path, _)),
          findall(After, user:plunit_saved_failed_source_call(After),
                  [parent]),
          \+ user:'get-atoms'(ChildSpace,
                               [=, [Function], never_committed]) ),
        ( catch(erase(SavedRef), _, true),
          user:metta_release_space(ChildSpace),
          user:metta_remove_atom(ParentSpace, ParentEquation, _),
          delete_file(Path) )).

test(wildcard_removal_does_not_make_reimport_duplicate_data) :-
    Space = '&plunit_import_wildcard',
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(plunit-import-triple left one)~n", []),
    format(Stream, "(plunit-import-triple right two)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( filereader:load_metta_file(Path, _, Space),
          aggregate_all(count,
                        user:'get-atoms'(Space,
                                         ['plunit-import-triple', _, _]),
                        Before),
          % Nothing removed, and that is the assertion. A wildcard of the
          % wrong SHAPE matches nothing, and BOTH doors say so: this used to
          % report `true` unconditionally, so the counts below were the only
          % evidence that nothing had been removed.
          %
          % The two doors word it differently on purpose. The language-facing
          % one answers the absence error a MeTTa program can branch on, and
          % metta_remove_atom/3 answers the plain boolean the engine's own
          % callers read, which is the same split 'add-atom'/3 draws against
          % metta_add_atom/3.
          user:'remove-atom'(Space, [_, _], Refused),
          Refused = ['Error', ['remove-atom', Space, [_, _]],
                     "remove-atom: atom is not in the space"],
          user:metta_remove_atom(Space, [_, _], false),
          aggregate_all(count,
                        user:'get-atoms'(Space,
                                         ['plunit-import-triple', _, _]),
                        AfterRemoval),
          filereader:load_metta_file(Path, _, Space),
          aggregate_all(count,
                        user:'get-atoms'(Space,
                                         ['plunit-import-triple', _, _]),
                        AfterReimport),
          user:import_life(Space, Path, loaded),
          [Before, AfterRemoval, AfterReimport] == [2, 2, 2] ),
        ( user:clear_native_atoms(Space),
          retractall(filereader:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(Space, Path)),
          delete_file(Path) )).

:- end_tests(filereader_import_lifecycle).

:- begin_tests(filereader_untypable_declaration).

%The evidence the refusal rests on, and it is the whole reason this is an
%error rather than a warning: an arrow declaration puts check_argument_type/3
%around the call and a non-arrow one leaves the call bare, so the same wrong
%argument is either refused at the function's door or carried into whatever
%finally breaks on it.
compiled_call_goals(Declaration, Goals) :-
    Function = 'plunit-untypable-inc',
    format(atom(Source), "~w~n(= (~w $x) (+ $x 1))~n",
           [Declaration, Function]),
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            filereader:process_metta_string(Source, _),
            user:translate_runnable_expr([Function, "s"], Goals, _),
            ( user:'remove-atom'('&self', [':', Function, _], _),
              user:'remove-atom'('&self', [=, [Function, _], _], _),
              cleanup_test_function(Function),
              retractall(user:arity(Function, _)) )),
        erase(SilentRef)).

test(an_arrow_declaration_compiles_the_check_a_non_arrow_one_cannot) :-
    compiled_call_goals("(: plunit-untypable-inc (-> Number Number))",
                        Guarded),
    compiled_call_goals("", Bare),
    term_string(Guarded, GuardedText),
    term_string(Bare, BareText),
    once(sub_string(GuardedText, _, _, _, "check_argument_type")),
    \+ sub_string(BareText, _, _, _, "check_argument_type").

test(a_non_arrow_declaration_for_a_function_is_refused,
     [throws(error(metta_untypable_declaration('plunit-untypable-inc',
                                               'Number'), _))]) :-
    compiled_call_goals("(: plunit-untypable-inc Number)", _).

test(the_refusal_names_the_declaration_and_the_arrow_to_write) :-
    message_to_string(
        error(metta_untypable_declaration(inc, ['List', 'Number']), none),
        Message),
    once(sub_string(Message, _, _, _, "(: inc (List Number))")),
    once(sub_string(Message, _, _, _, "(: inc (-> ...))")),
    once(sub_string(Message, _, _, _, "%Undefined%")).

test(an_explicitly_undefined_type_is_the_way_to_opt_out) :-
    compiled_call_goals("(: plunit-untypable-inc %Undefined%)", Goals),
    Goals \== [].

%MeTTa lets a name carry several declarations, so the rule asks whether any of
%them is an arrow rather than whether all of them are.
test(one_arrow_among_several_declarations_is_enough) :-
    compiled_call_goals("(: plunit-untypable-inc Number)\c
                         \n(: plunit-untypable-inc (-> Number Number))",
                        Goals),
    term_string(Goals, Text),
    once(sub_string(Text, _, _, _, "check_argument_type")).

%lib_nars.metta writes NARS inheritance as (--> $a $b) and
%lib_combinatorics.metta writes a lambda as (|-> ...). Both are deliberate
%atoms in data positions, and a spelling rule would have rejected them.
test(a_declaration_for_a_name_with_no_equations_is_data) :-
    Name = 'plunit-untypable-belief',
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            true,
            ( filereader:process_metta_string("(: plunit-untypable-belief \c
                                         (--> Cat Animal))", _),
              user:type_declaration(Name, Type),
              Type == ['-->', 'Cat', 'Animal'] ),
            user:'remove-atom'('&self', [':', Name, _], _)),
        erase(SilentRef)).

:- end_tests(filereader_untypable_declaration).

:- begin_tests(filereader_source_digest).

%engine/filereader.pl takes a source's digest from library(crypto) when the build
%has it and from library(sha) when it does not, which is the WebAssembly build
%[measured 2026-08-20: swipl-wasm 8.0.6 carries sha and not crypto]. That is
%only safe while the two answer the same, because metta_source_changed/1
%compares a digest this process took against one an earlier process recorded,
%and a provider that spelled it differently would call every file changed.
%
%So both are computed here whenever both are available, on text that is empty,
%plain and non-ASCII, and required to be identical. A build with one of them
%runs the half it has, which is the honest test on a host that cannot run the
%other.
digest_providers_agree(Text) :-
    exists_source(library(crypto)),
    exists_source(library(sha)),
    !,
    crypto:crypto_data_hash(Text, ByCrypto, [algorithm(sha256)]),
    sha:sha_hash(Text, Bytes, [algorithm(sha256)]),
    sha:hash_atom(Bytes, BySha),
    ByCrypto == BySha,
    filereader:metta_text_digest(Text, Chosen),
    Chosen == ByCrypto.
digest_providers_agree(Text) :-
    filereader:metta_text_digest(Text, Digest),
    atom_length(Digest, 64).

test(both_digest_providers_agree) :-
    forall(member(Text, ["", "hello", "a line\nand another", "héllo wörld"]),
           digest_providers_agree(Text)).

%The digest is what makes a reload notice an edit, so it has to separate texts
%that differ and join texts that do not.
test(a_digest_separates_texts_and_joins_equal_ones) :-
    filereader:metta_text_digest("(= (f) 1)", One),
    filereader:metta_text_digest("(= (f) 1)", Again),
    filereader:metta_text_digest("(= (f) 2)", Other),
    One == Again,
    One \== Other.

:- end_tests(filereader_source_digest).

:- begin_tests(filereader_late_definition_cost).

%A file whose callee is written LAST. Every caller ahead of it compiled that
%name as plain data, so each is rebuilt once the definition arrives, and
%finding a caller's stored equations used to walk EVERY equation in the system,
%two inferences a clause. translated_equation_of/3 asks the clause index
%instead.
%
%The claim is that the repair no longer costs anything that grows with the
%program it repairs INTO, so the same file with the callee written FIRST is the
%control: it defines the same names and compiles the same nine forms and takes
%no repair path, and it measures the same to the inference either way. What is
%left after subtracting it is the repair alone [measured 2026-08-23 with eight
%callers over a space already holding M unrelated equations: the excess was
%9,692 inferences at M=200 and 211,336 at M=12,800 and is 6,352 and 6,316, so
%it was linear in M and is flat].
%
%The threshold is 2.5 because the walk measured 6.15 over this pair and the
%index measures 1.32, neither near it. The index reading exceeds 1 only because
%the first repairing load in a process is about 2,100 inferences cheaper than
%the ones after it; the control is exact to the inference at every repetition.
write_bulk_equations(M, Path) :-
    tmp_file_stream(text, Path, Stream),
    forall(between(1, M, I),
           format(Stream, "(= (plunit_bulk_b~w) ~w)~n", [I, I])),
    close(Stream).

write_callers(late, Callers, Path) :-
    tmp_file_stream(text, Path, Stream),
    forall(between(1, Callers, I),
           format(Stream, "(= (plunit_late_u~w) (plunit_late_gee k0))~n", [I])),
    format(Stream, "(= (plunit_late_gee $x) (quote $x))~n", []),
    close(Stream).
write_callers(first, Callers, Path) :-
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(= (plunit_late_gee $x) (quote $x))~n", []),
    forall(between(1, Callers, I),
           format(Stream, "(= (plunit_late_u~w) (plunit_late_gee k0))~n", [I])),
    close(Stream).

forget_late_definition_load(M, Callers, Space, Bulk, Small) :-
    forall(between(1, Callers, I),
           ( atom_concat(plunit_late_u, I, F), cleanup_test_function(F) )),
    cleanup_test_function(plunit_late_gee),
    forall(between(1, M, I),
           ( atom_concat(plunit_bulk_b, I, F), cleanup_test_function(F) )),
    user:clear_native_atoms(Space),
    %metta_release_space/1 rather than metta_forget_space_parent/1, for the
    %reason spaces_join_order records: the partial form leaves the exec-module
    %link behind and a later unit asserts none exists.
    user:metta_release_space(Space),
    retractall(filereader:compiled_metta_source(_)),
    retractall(user:imported_metta_source(_, _)),
    ( exists_file(Bulk) -> delete_file(Bulk) ; true ),
    ( exists_file(Small) -> delete_file(Small) ; true ).

late_definition_load_cost(Order, M, Callers, Cost) :-
    Space = '&plunit_late_definition',
    write_bulk_equations(M, Bulk),
    write_callers(Order, Callers, Small),
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            filereader:load_metta_file(Bulk, _, Space),
            ( statistics(inferences, Before),
              filereader:load_metta_file(Small, _, Space),
              statistics(inferences, After),
              Cost is After - Before ),
            forget_late_definition_load(M, Callers, Space, Bulk, Small)),
        erase(SilentRef)).

repair_excess(M, Excess) :-
    late_definition_load_cost(late, M, 8, Repaired),
    late_definition_load_cost(first, M, 8, Control),
    Excess is Repaired - Control.

test(repairing_late_callers_costs_nothing_that_grows_with_the_program) :-
    repair_excess(200, Narrow),
    repair_excess(3200, Wide),
    %Deferred translation removed the load-time repair entirely, so both
    %readings sit at zero plus measurement noise and either can go NEGATIVE,
    %which flips a pure ratio. The absolute term keeps the flatness claim
    %decidable in the zero regime while a return of the linear walk (211,336
    %at the old M=12,800) still overwhelms it.
    assertion(Wide < max(Narrow, 0) * 2.5 + 500).

:- end_tests(filereader_late_definition_cost).

% Registering a name asks SWI which predicates already carry it, and
% current_predicate/1 with the arity unbound enumerates the predicate table.
% Asked once per name that is a walk per name, so the batch asks once for all
% of them. The two strategies are held together here rather than by sharing
% code, because only the batch can be cheap and only the per-name form is cheap
% for one name.
:- begin_tests(filereader_signature_registration).

probe_names(Count, Names) :-
    findall(Name,
            ( between(1, Count, Index),
              atom_concat(sigprobe_absent_, Index, Name) ),
            Fresh),
    append([member, append, length, format, is_list], Fresh, Names0),
    sort(Names0, Names).

test(registering_a_batch_of_names_answers_what_asking_one_by_one_does) :-
    probe_names(200, Names),
    filereader:existing_predicate_arities(Names, Batched0),
    sort(Batched0, Batched),
    findall(Name-Arity,
            ( member(Name, Names),
              current_predicate(Name/Arity),
              filereader:callable_as_written(Name, Arity) ),
            OneByOne0),
    sort(OneByOne0, OneByOne),
    assertion(Batched == OneByOne),
    assertion(Batched \== []).

test(registering_new_names_costs_nothing_that_grows_with_their_number) :-
    registration_cost(50, Narrow),
    registration_cost(3200, Wide),
    assertion(Wide < Narrow * 8).

registration_cost(Count, Micros) :-
    probe_names(Count, Names),
    forall(between(1, 3, _), filereader:existing_predicate_arities(Names, _)),
    T0 is cputime,
    forall(between(1, 20, _), filereader:existing_predicate_arities(Names, _)),
    T1 is cputime,
    Micros is (T1 - T0) * 1000000 / 20.

:- end_tests(filereader_signature_registration).

% Deciding which declarations in a source name something the same source
% defines used to walk an ordered list of the defined names once per
% declaration.
:- begin_tests(filereader_source_declaration_pass).

test(checking_a_sources_declarations_costs_nothing_that_grows_with_the_source) :-
    declaration_pass_cost(200, Narrow),
    declaration_pass_cost(3200, Wide),
    assertion(Wide < Narrow * 4).

declaration_pass_cost(Count, Micros) :-
    findall(Form,
            ( between(1, Count, Index),
              format(atom(Text), '(: dpc~w (-> Number))\n(= (dpc~w) ~w)',
                     [Index, Index, Index]),
              Form = Text ),
            Forms),
    atomic_list_concat(Forms, '\n', Source0),
    atom_string(Source0, Source),
    filereader:parse_metta_source_summary(Source, _, Sigs, Decls),
    findall(F, member(F-_, Sigs), Names0),
    sort(Names0, Names),
    forall(between(1, 3, _),
           ignore(filereader:refuse_untypable_from_summary(Names, Decls))),
    T0 is cputime,
    forall(between(1, 5, _),
           ignore(filereader:refuse_untypable_from_summary(Names, Decls))),
    T1 is cputime,
    Micros is (T1 - T0) * 1000000 / (5 * Count).

:- end_tests(filereader_source_declaration_pass).

:- begin_tests(filereader_data_runs).

%The run door and the per-atom door are one behaviour for plain data: the
%same atoms in the same order, the same journal rows, and the same
%withdrawal. The run door engages only under data_run/4's guards, silence
%among them, so quietly/1 is what makes these tests exercise it; the loud
%variant of the first test pins the per-form door to the same answer.

quietly(Goal) :-
    metta_engine_module(E),
    setup_call_cleanup(asserta(E:silent(true), Ref), Goal, erase(Ref)).

data_run_source(Prefix, S) :-
    numlist(1, 40, Ns),
    findall(T,
            ( member(N, Ns), M is N mod 4,
              format(atom(T), "(~w-fact~w ~w \"p\" 3.5)", [Prefix, M, N]) ),
            Ts),
    atomic_list_concat(Ts, '\n', A),
    atom_string(A, S).

stored_in_order(Head, Numbers) :-
    findall(N, get_native_atom('&self', [Head, N|_]), Numbers).

test(the_run_door_stores_what_the_per_atom_door_stores_in_order) :-
    data_run_source(drq, Quiet),
    quietly(filereader:process_metta_string(Quiet, _)),
    data_run_source(drl, Loud),
    filereader:process_metta_string(Loud, _),
    stored_in_order('drq-fact1', ViaRun),
    stored_in_order('drl-fact1', ViaForm),
    assertion(ViaRun == [1, 5, 9, 13, 17, 21, 25, 29, 33, 37]),
    assertion(ViaRun == ViaForm).

test(a_mixed_stream_keeps_every_form_where_it_stood) :-
    quietly(filereader:process_metta_string(
        "(dm-a 1) (dm-a 2) (: dm-marker Number) (dm-a 3) (dm-a 4)", _)),
    stored_in_order('dm-a', Ns),
    assertion(Ns == [1, 2, 3, 4]),
    findall(T, get_native_atom('&self', [':', 'dm-marker', T]), Ts),
    assertion(Ts == ['Number']).

test(the_run_door_journals_what_withdrawal_needs) :-
    tmp_file_stream(text, File, Stream),
    write(Stream, "(dj-run 1) (dj-run 2) (dj-run 3)"),
    close(Stream),
    quietly(filereader:metta_host_load_file(File, '&self', _)),
    stored_in_order('dj-run', Before),
    assertion(Before == [1, 2, 3]),
    filereader:withdraw_source_load(File, '&self', Count),
    assertion(Count =:= 3),
    stored_in_order('dj-run', AfterWithdraw),
    assertion(AfterWithdraw == []),
    delete_file(File).

test(a_bound_token_ends_the_fast_path_and_still_substitutes) :-
    quietly(( filereader:process_metta_string("!(bind! dtok 41)", _),
              filereader:process_metta_string(
                  "(dt-holder dtok) (dt-holder 2)", _) )),
    findall(A, get_native_atom('&self', ['dt-holder', A]), Held),
    assertion(Held == [41, 2]),
    quietly(filereader:process_metta_string(
        "!(remove-atom &self (= dtok 41))", _)).

test(scalars_and_variables_store_through_the_run_door) :-
    quietly(filereader:process_metta_string(
        "(ds-pair $x $x) (ds-pair a b)", _)),
    findall(P-Q, get_native_atom('&self', ['ds-pair', P, Q]), Pairs),
    assertion(Pairs = [_, a-b]),
    Pairs = [V1-V2|_],
    assertion(V1 == V2).

:- end_tests(filereader_data_runs).
