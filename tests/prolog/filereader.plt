% Purpose: verify file-reader form splitting and translation-error reporting.
% Open Obligations:
%   To Do: Add escaped-quote form-splitter coverage from the engine review.
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
