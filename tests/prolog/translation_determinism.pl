% Purpose: reject MeTTa forms with more than one Prolog translation.
% Guarantees:
%   - One root example supplied on argv is parsed without running its
%     executable forms.
%   - A second clause or expression translation names its file and source form
%     and fails the process.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(solution_sequences)).
:- use_module(library(readutil)).
:- initialization(main, main).

main :-
    catch(( check_requested_file -> Status = 0 ; Status = 1 ),
          Error,
          ( print_message(error, Error), Status = 2 )),
    halt(Status).

check_requested_file :-
    current_prolog_flag(argv, [File]),
    consult('../../src/metta.pl'),
    retractall(silent(_)),
    assertz(silent(true)),
    check_file(File).

check_file(File) :-
    read_file_to_string(File, Source, []),
    string_codes(Source, RawCodes),
    strip(RawCodes, outside, Codes),
    phrase(top_forms(Forms, 1), Codes),
    maplist(parsed_form, Forms, Terms),
    prepare_file_symbols(Terms),
    forall(member(Term, Terms), one_translation(File, Term)).

parsed_form(Form, Term) :-
    arg(1, Form, Source),
    sread(Source, Term).

prepare_file_symbols(Terms) :-
    forall(member([=, [Function|_], _], Terms),
           catch(register_fun(Function), _, true)),
    forall(member([':', Function, Type], Terms),
           catch(add_sexp('&self', [':', Function, Type]), _, true)).

one_translation(File, Term) :-
    translation_goal(Term, Witness, Goal),
    findnsols(2, Witness, catch(Goal, _, fail), Solutions),
    ( Solutions = [_, _]
      -> format(user_error,
                'multiple translations in ~w: ~q~n',
                [File, Term]),
         fail
    ; true ).

translation_goal(Term, Clause, translate_clause(Term, Clause)) :-
    Term = [=, [_|_], _], !.
translation_goal(Term, Goals-Out, translate_expr(Term, Goals, Out)).
