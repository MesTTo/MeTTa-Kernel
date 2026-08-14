% Purpose: verify file-reader form splitting and translation-error reporting.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).

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
    string_codes(Source, RawCodes),
    strip(RawCodes, outside, Codes),
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

test(missing_form_open_reports_its_syntax_error,
     [throws(error(syntax_error(_), none))]) :-
    string_codes("not-a-form", Codes),
    phrase(top_forms(_, 1), Codes).

test(missing_form_close_reports_its_syntax_error,
     [throws(error(syntax_error(_), none))]) :-
    string_codes("(not-closed", Codes),
    phrase(top_forms(_, 1), Codes).

:- end_tests(filereader_form_splitter).

:- begin_tests(filereader_terminal_output).

test(nonterminal_loader_output_has_no_ansi_escapes) :-
    with_output_to(string(Output),
                   process_metta_string("!(quote answer)", Results)),
    Results == [answer],
    once(sub_string(Output, _, _, _, "--> metta runnable  -->")),
    \+ sub_string(Output, _, _, _, "\e[").

:- end_tests(filereader_terminal_output).

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
          forall(( current_predicate(user:Space/Arity),
                   functor(Head, Space, Arity) ),
                 retractall(user:Head)),
          \+ user:'get-atoms'(Space, ['loader-life-marker', payload]),
          user:load_metta_file(Path, _, Space),
          once(user:'get-atoms'(Space, ['loader-life-marker', payload])) ),
        ( forall(( current_predicate(user:Space/Arity),
                   functor(Head, Space, Arity) ),
                 retractall(user:Head)),
          retractall(user:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(Space, Path)),
          delete_file(Path) )).

:- end_tests(filereader_control_errors).
