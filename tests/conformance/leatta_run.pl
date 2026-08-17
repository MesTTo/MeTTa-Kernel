% Purpose: run ONE LeaTTa semantics file under this engine and print the answer
%   GROUP of each `!` form on a marker line, so a comparator can read them
%   without having to tell an answer apart from the loader's own echo.
% Assumes:
%   - argv carries `--file <path>`, and the engine is already consulted.
% Guarantees:
%   - one `LEATTA-ANSWER ` line per RUNNABLE form, in source order, holding that
%     form's answers written as MeTTa. A form with no answers prints an empty
%     group rather than nothing, because "no answers" is an observation the
%     arbiter records as `[]` and dropping it would misalign every line after it.
%   - a raise prints `LEATTA-ERROR ` and stops, rather than being mistaken for
%     an empty run.
% Fails when:
%   - never silently: an unreadable file raises out of read_metta_source/2 and
%     is reported on the error line.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   append(_, ['--file', File|_], Argv)
    ->  true
    ;   throw(error(existence_error(argument, '--file'), _))
    ),
    catch(( run_grouped(File, Groups),
            forall(member(Group, Groups),
                   ( swrite(Group, Written),
                     format("LEATTA-ANSWER ~w~n", [Written]) )) ),
          Error,
          report_error(Error)),
    halt.

%The loader's own path flattens the per-form groups with append/2, which is
%right for a program and wrong here: the arbiter records one bracketed line per
%form, so the grouping IS the observation. These are the engine's own
%predicates, called in the engine's own order, with the flattening left out.
run_grouped(File, Groups) :-
    setup_call_cleanup(
        push_working_dir(File),
        ( read_metta_source(File, Source),
          prepare_metta_source(Source, Forms),
          maplist(process_form('&self', compile), Forms, PerForm),
          runnable_groups(Forms, PerForm, Groups) ),
        pop_working_dir).

runnable_groups([], [], []).
runnable_groups([Form|Forms], [Group|Rest], Groups) :-
    (   Form = parsed(runnable, _, _)
    ->  Groups = [Group|More]
    ;   Groups = More
    ),
    runnable_groups(Forms, Rest, More).

report_error(Error) :-
    message_to_text(Error, Text),
    format("LEATTA-ERROR ~w~n", [Text]).

%print_message/2 writes to user_error and returns nothing a caller can hold, so
%the message is rendered through its own DCG and captured instead.
message_to_text(Error, Text) :-
    (   catch(( message_to_codes(Error, Codes), Codes \== [] ), _, fail)
    ->  string_codes(Text, Codes)
    ;   term_string(Error, Text)
    ).

message_to_codes(Error, Codes) :-
    message_to_lines(Error, Lines),
    with_output_to(codes(Codes),
                   print_message_lines(current_output, '', Lines)).

message_to_lines(Error, Lines) :-
    (   phrase(prolog:message(Error), Lines)
    ->  true
    ;   Error = error(Formal, _),
        phrase(prolog:error_message(Formal), Lines)
    ).
