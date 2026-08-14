% Purpose: verify file-reader splitting, loader rollback, global function
%   scope, late-definition repair, and translation-error reporting.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

test_lambda_functions(Functions) :-
    findall(F,
            ( user:fun(F),
              atom(F),
              sub_atom(F, 0, 7, _, lambda_) ),
            Functions0),
    sort(Functions0, Functions).

cleanup_test_function(F) :-
    user:forget_symbol(F),
    retractall(user:symbol_head(F, _)),
    retractall(user:fun_in(_, F)),
    retractall(user:fun_scoped(F)).

cleanup_new_lambdas(Before) :-
    test_lambda_functions(After),
    subtract(After, Before, Added),
    maplist(cleanup_test_function, Added).

:- begin_tests(filereader_translation_errors).

test(an_untranslatable_form_is_not_reported_as_invalid_syntax,
     [throws(error(petta_translation_failed(unhandled_form), _))]) :-
    process_form('&self', unhandled_form, _).

test(translation_error_has_an_engine_message) :-
    message_to_string(error(petta_translation_failed(unhandled_form), none),
                      Message),
    once(sub_string(Message, _, _, _, "Could not translate MeTTa form")),
    \+ sub_string(Message, _, _, _, "Unknown error term").

:- end_tests(filereader_translation_errors).

:- begin_tests(filereader_form_splitter).

test(escaped_quote_does_not_close_a_string_or_form) :-
    Source = "!(test \"quote: \\\" and )\" \"quote: \\\" and )\")\n!(quote done)",
    string_codes(Source, Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    Forms = [runnable(First), runnable(Second)],
    sread(First, FirstTerm),
    sread(Second, SecondTerm),
    FirstTerm == [test, "quote: \" and )", "quote: \" and )"],
    SecondTerm == [quote, done].

test(loader_and_reader_agree_on_inline_comments) :-
    sread("(a ; ignored tokens\n b)", ReadTerm),
    setup_call_cleanup(assertz(silent(true), Ref),
                       process_metta_string("!(quote (a ; ignored tokens\n b))",
                                            Results),
                       erase(Ref)),
    ReadTerm == [a, b],
    Results == [[a, b]].

test(comment_parentheses_do_not_close_a_form) :-
    Source = "!(quote (a ; ignored ) and (!( \"\n b))\n!(quote done)",
    string_codes(Source, Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    Forms = [runnable(First), runnable(Second)],
    sread(First, FirstTerm),
    sread(Second, SecondTerm),
    FirstTerm == [quote, [a, b]],
    SecondTerm == [quote, done].

test(missing_form_open_reports_its_syntax_error,
     [throws(error(syntax_error(_), none))]) :-
    string_codes("not-a-form", Codes),
    phrase(top_forms(_, 1), Codes).

test(missing_form_close_reports_its_syntax_error,
     [throws(error(syntax_error(_), none))]) :-
    string_codes("(not-closed", Codes),
    phrase(top_forms(_, 1), Codes).

:- end_tests(filereader_form_splitter).

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
    format(string(Runnable), "!(quote ~s~n)", [Source]),
    setup_call_cleanup(assertz(silent(true), Ref),
                       process_metta_string(Runnable, Results),
                       erase(Ref)),
    Results == [Expected].

:- end_tests(filereader_comments).

:- begin_tests(filereader_terminal_output).

test(nonterminal_loader_output_has_no_ansi_escapes) :-
    with_output_to(string(Output),
                   process_metta_string("!(quote answer)", Results)),
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
    format(Stream, "!(+ 1 2 3)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( catch(user:load_metta_file(Path, _), Error, true),
          Error = error(domain_error(function_input_arities(+, [2]), 3), _),
          flag('$gs_lambda_', LambdaNumber, LambdaNumber),
          format(atom(GeneratedLambda), 'lambda_~d', [LambdaNumber]),
          test_lambda_functions(AfterLambdas),
          AfterLambdas == BeforeLambdas,
          \+ user:fun(Outer),
          \+ user:arity(Outer, _),
          \+ user:fun_meta_clause(Outer, _, _),
          \+ user:symbol_head(Symbol, _),
          \+ user:fun(GeneratedLambda),
          \+ user:arity(GeneratedLambda, _),
          \+ user:fun_meta_clause(GeneratedLambda, _, _),
          \+ user:fun(RuntimeFunction),
          \+ user:arity(RuntimeFunction, _),
          \+ user:fun_meta_clause(RuntimeFunction, _, _),
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
          \+ user:compiled_metta_source(Path),
          \+ user:imported_metta_source(_, Path),
          \+ user:import_life(_, Path, _) ),
        ( cleanup_test_function(Outer),
          cleanup_test_function(RuntimeFunction),
          retractall(user:symbol_head(Symbol, _)),
          cleanup_new_lambdas(BeforeLambdas),
          retractall(user:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )).

test(late_registration_recompile_replaces_metadata,
     [ setup((cleanup_test_function('plunit-repair-caller'),
              cleanup_test_function('plunit-repair-late'))),
       cleanup((cleanup_test_function('plunit-repair-caller'),
                cleanup_test_function('plunit-repair-late'))) ]) :-
    user:process_metta_string(
        "(= (plunit-repair-caller $x) (plunit-repair-late $x))", _),
    aggregate_all(count,
                  user:fun_meta_clause('plunit-repair-caller', _, _),
                  Before),
    user:process_metta_string(
        "(= (plunit-repair-late $x) (+ $x 1))", _),
    aggregate_all(count,
                  user:fun_meta_clause('plunit-repair-caller', _, _),
                  After),
    user:process_metta_string("!(plunit-repair-caller 41)", Results),
    Before == 1,
    After == 1,
    Results == [42].

test(failed_late_definition_does_not_recompile_existing_callers,
     [ setup((cleanup_test_function('plunit-rollback-caller'),
              cleanup_test_function('plunit-rollback-late'))),
       cleanup((cleanup_test_function('plunit-rollback-caller'),
                cleanup_test_function('plunit-rollback-late'))) ]) :-
    user:process_metta_string(
        "(= (plunit-rollback-caller $x) (plunit-rollback-late $x))", _),
    tmp_file_stream(text, Path, Stream),
    format(Stream,
           "(= (plunit-rollback-late $x) (+ $x 1))~n!(+ 1 2 3)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( catch(user:load_metta_file(Path, _), Error, true),
          Error = error(domain_error(function_input_arities(+, [2]), 3), _),
          user:process_metta_string("!(plunit-rollback-caller 41)", Results),
          aggregate_all(count,
                        user:fun_meta_clause('plunit-rollback-caller', _, _),
                        MetaCount),
          Results == [['plunit-rollback-late', 41]],
          MetaCount == 1,
          \+ user:fun_meta_clause('plunit-rollback-late', _, _) ),
        ( retractall(user:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )).

:- end_tests(filereader_source_rollback).

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
            ( user:load_metta_file(Path, _),
              user:'add-atom'(NamedSpace, NamedTerm, true),
              user:process_metta_string(
                  "!(plunit-global-file-function 41)", Results, OtherSpace),
              user:fun_in(user, Function),
              Results == [42] ),
            ( user:'remove-atom'(NamedSpace, NamedTerm, _),
              cleanup_test_function(Function),
              retractall(user:compiled_metta_source(Path)),
              retractall(user:imported_metta_source(_, Path)),
              delete_file(Path) )),
        erase(SilentRef)).

:- end_tests(filereader_global_function_scope).

:- begin_tests(filereader_control_errors).

test(loader_catches_do_not_consume_control_exceptions) :-
    tmp_file_stream(text, Path, Stream),
    format(Stream, "!(plunit-loader-control)~n", []),
    close(Stream),
    setup_call_cleanup(
        ( assertz((user:'plunit-loader-control'(_) :-
                       throw(inference_limit_exceeded)), ClauseRef),
          user:register_fun('plunit-loader-control') ),
        catch(user:load_metta_file(Path, _), Error, true),
        ( erase(ClauseRef),
          retractall(user:fun('plunit-loader-control')),
          retractall(user:arity('plunit-loader-control', _)),
          retractall(user:compiled_metta_source(Path)),
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
        ( user:load_metta_file(Path, _, Space),
          once(user:'get-atoms'(Space, ['loader-life-marker', payload])),
          user:clear_native_atoms(Space),
          \+ user:'get-atoms'(Space, ['loader-life-marker', payload]),
          user:load_metta_file(Path, _, Space),
          once(user:'get-atoms'(Space, ['loader-life-marker', payload])) ),
        ( user:clear_native_atoms(Space),
          retractall(user:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(Space, Path)),
          delete_file(Path) )).

:- end_tests(filereader_control_errors).

:- begin_tests(filereader_import_lifecycle).

test(wildcard_removal_does_not_make_reimport_duplicate_data) :-
    Space = '&plunit_import_wildcard',
    tmp_file_stream(text, Path, Stream),
    format(Stream, "(plunit-import-triple left one)~n", []),
    format(Stream, "(plunit-import-triple right two)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( user:load_metta_file(Path, _, Space),
          aggregate_all(count,
                        user:'get-atoms'(Space,
                                         ['plunit-import-triple', _, _]),
                        Before),
          user:'remove-atom'(Space, [_, _], true),
          aggregate_all(count,
                        user:'get-atoms'(Space,
                                         ['plunit-import-triple', _, _]),
                        AfterRemoval),
          user:load_metta_file(Path, _, Space),
          aggregate_all(count,
                        user:'get-atoms'(Space,
                                         ['plunit-import-triple', _, _]),
                        AfterReimport),
          user:import_life(Space, Path, loaded),
          [Before, AfterRemoval, AfterReimport] == [2, 2, 2] ),
        ( user:clear_native_atoms(Space),
          retractall(user:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(Space, Path)),
          delete_file(Path) )).

:- end_tests(filereader_import_lifecycle).
