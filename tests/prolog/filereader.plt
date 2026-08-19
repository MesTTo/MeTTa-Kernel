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
    user:metta_self_module(SelfModule),
    user:forget_symbol(SelfModule, F),
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

%A top-level form is ONE ATOM, and a parenthesised expression is only the
%commonest kind. The four splitter tests below pin the reader against the
%arbiter's own tokenizer rule: a leading `!` before `(`, layout or end of
%input marks the atom that follows as runnable, and a `!` anywhere else is
%an ordinary symbol character [source: LeaTTa
%MettaHyperonFull/Runtime/Parser.lean:85-88].
test(a_bare_symbol_is_a_top_level_form) :-
    string_codes("not-a-form", Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    Forms == [form("not-a-form")].

test(the_marker_takes_an_atom_of_any_kind) :-
    string_codes("! untouched-symbol\n! 42\n! \"a b\"\n! $free\n! &first",
                 Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    Forms == [runnable("untouched-symbol"), runnable("42"),
              runnable("\"a b\""), runnable("$free"), runnable("&first")].

%`!42` and `!$x` print nothing under the arbiter because its tokenizer keeps
%the `!` inside the symbol; only `(`, layout and end of input make it the
%marker [measured 2026-08-19: LeaTTa --observed-file on each exits 0 with no
%output].
test(a_marker_before_a_non_boundary_stays_an_ordinary_symbol_character) :-
    string_codes("!42\n!$x\n!(f)", Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    Forms == [form("!42"), form("!$x"), runnable("(f)")].

%The same measurement: a file ending in a bare `!` exits 0 and prints
%nothing, so the marker with no atom after it contributes no form.
test(a_trailing_marker_contributes_no_form) :-
    string_codes("!(f)\n!", Codes),
    once(phrase(top_forms(Forms, 1), Codes)),
    Forms == [runnable("(f)")].

test(missing_form_close_reports_its_syntax_error,
     [throws(error(syntax_error(_), none))]) :-
    string_codes("(not-closed", Codes),
    phrase(top_forms(_, 1), Codes).

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
    %A HOST error, because that is the kind that still raises: a wrong arity
    %and a wrongly typed operand are both ANSWERS now, and a form that answers
    %does not roll its source back.
    format(Stream, "!(/ 1 0)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( catch(user:load_metta_file(Path, _), Error, true),
          Error = error(evaluation_error(zero_divisor), _),
          flag('$gs_lambda_', LambdaNumber, LambdaNumber),
          format(atom(GeneratedLambda), 'lambda_~d', [LambdaNumber]),
          test_lambda_functions(AfterLambdas),
          AfterLambdas == BeforeLambdas,
          \+ user:fun(Outer),
          \+ user:arity(Outer, _),
          \+ user:fun_meta_clause(_, Outer, _, _),
          \+ user:symbol_head(Symbol, _),
          \+ user:fun(GeneratedLambda),
          \+ user:arity(GeneratedLambda, _),
          \+ user:fun_meta_clause(_, GeneratedLambda, _, _),
          \+ user:fun(RuntimeFunction),
          \+ user:arity(RuntimeFunction, _),
          \+ user:fun_meta_clause(_, RuntimeFunction, _, _),
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
                  user:fun_meta_clause(_, 'plunit-repair-caller', _, _),
                  Before),
    user:process_metta_string(
        "(= (plunit-repair-late $x) (+ $x 1))", _),
    aggregate_all(count,
                  user:fun_meta_clause(_, 'plunit-repair-caller', _, _),
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
           "(= (plunit-rollback-late $x) (+ $x 1))~n!(/ 1 0)~n", []),
    close(Stream),
    setup_call_cleanup(
        true,
        ( catch(user:load_metta_file(Path, _), Error, true),
          Error = error(evaluation_error(zero_divisor), _),
          user:process_metta_string("!(plunit-rollback-caller 41)", Results),
          aggregate_all(count,
                        user:fun_meta_clause(_, 'plunit-rollback-caller', _, _),
                        MetaCount),
          Results == [['plunit-rollback-late', 41]],
          MetaCount == 1,
          \+ user:fun_meta_clause(_, 'plunit-rollback-late', _, _) ),
        ( retractall(user:compiled_metta_source(Path)),
          retractall(user:imported_metta_source(_, Path)),
          delete_file(Path) )).

:- end_tests(filereader_source_rollback).

%The engine's own door onto a reload. The Python library's is tested from the
%Python side in python/tests/test_reload.py; what these hold is the state the
%engine keeps about a file, which no Python assertion can see.
:- begin_tests(filereader_source_reload).

write_reload_source(Path, Text) :-
    setup_call_cleanup(open(Path, write, Stream),
                       write(Stream, Text),
                       close(Stream)).

reload_scratch_file(Path) :-
    tmp_file(plunit_reload, Base),
    file_name_extension(Base, metta, Path).

forget_reload_source(Path, Function) :-
    cleanup_test_function(Function),
    retractall(user:metta_source_load(Path, _, _, _)),
    retractall(user:compiled_metta_source(Path)),
    retractall(user:imported_metta_source(_, Path)),
    retractall(user:import_life(_, Path, _)),
    ( exists_file(Path) -> delete_file(Path) ; true ).

test(a_load_records_what_the_file_contributed) :-
    F = 'plunit-reload-recorded',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-recorded) 1)\n"),
        ( user:load_metta_file(Path, _, '&self'),
          absolute_file_name(Path, Canon, [access(read)]),
          once(user:metta_source_load(Canon, Space, LoadId, Digest)),
          Space == '&self',
          atom_length(Digest, 64),
          aggregate_all(count, user:source_load_assertion(LoadId, _), Asserted),
          Asserted > 0 ),
        forget_reload_source(Path, F)).

test(an_unchanged_file_is_not_loaded_again) :-
    F = 'plunit-reload-unchanged',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-unchanged) 1)\n"),
        ( user:load_metta_file(Path, _, '&self'),
          absolute_file_name(Path, Canon, [access(read)]),
          once(user:metta_source_load(Canon, '&self', FirstId, _)),
          user:load_metta_file(Path, _, '&self'),
          once(user:metta_source_load(Canon, '&self', AgainId, _)),
          AgainId == FirstId,
          \+ user:metta_source_changed(Canon) ),
        forget_reload_source(Path, F)).

%The same length either side, so a check on the modification time would have
%to see a difference the coarse clock may not have recorded.
test(an_edit_that_keeps_the_length_is_still_a_change) :-
    F = 'plunit-reload-samesize',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-samesize) 1)\n"),
        ( user:load_metta_file(Path, _, '&self'),
          absolute_file_name(Path, Canon, [access(read)]),
          write_reload_source(Path, "(= (plunit-reload-samesize) 2)\n"),
          user:metta_source_changed(Canon),
          user:load_metta_file(Path, _, '&self'),
          findall(V, user:'get-atoms'('&self', [=, [F], V]), Values),
          Values == [2] ),
        forget_reload_source(Path, F)).

test(a_reload_leaves_one_clause_for_a_redefined_function) :-
    F = 'plunit-reload-oneclause',
    reload_scratch_file(Path),
    setup_call_cleanup(
        write_reload_source(Path, "(= (plunit-reload-oneclause) 1)\n"),
        ( user:load_metta_file(Path, _, '&self'),
          write_reload_source(Path, "(= (plunit-reload-oneclause) 2)\n"),
          user:load_metta_file(Path, _, '&self'),
          user:metta_self_module(Self),
          functor(Head, F, 1),
          aggregate_all(count, clause(Self:Head, _), Clauses),
          Clauses == 1,
          findall(T, user:translated_from(_, [=, [F], T]), Sources),
          Sources == [2] ),
        forget_reload_source(Path, F)).

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
            ( user:load_metta_file(Path, _),
              user:'add-atom'(NamedSpace, NamedTerm, _),
              user:process_metta_string(
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
          % The public route, not register_fun/1: registering a Prolog
          % predicate is what import_prolog_function/2 is for, and it is what
          % records the arity the call compiles against.
          user:import_prolog_function('plunit-loader-control', _) ),
        catch(user:load_metta_file(Path, _), Error, true),
        ( erase(ClauseRef),
          user:unregister_fun_everywhere('plunit-loader-control'),
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

:- begin_tests(filereader_untypable_declaration).

%The evidence the refusal rests on, and it is the whole reason this is an
%error rather than a warning: an arrow declaration puts has_type/2 around the
%call and a non-arrow one leaves the call bare, so the same wrong argument is
%either refused at the function's door or carried into whatever finally
%breaks on it.
compiled_call_goals(Declaration, Goals) :-
    Function = 'plunit-untypable-inc',
    format(atom(Source), "~w~n(= (~w $x) (+ $x 1))~n",
           [Declaration, Function]),
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            user:process_metta_string(Source, _),
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
    once(sub_string(GuardedText, _, _, _, "has_type")),
    \+ sub_string(BareText, _, _, _, "has_type").

test(a_non_arrow_declaration_for_a_function_is_refused,
     [throws(error(petta_untypable_declaration('plunit-untypable-inc',
                                               'Number'), _))]) :-
    compiled_call_goals("(: plunit-untypable-inc Number)", _).

test(the_refusal_names_the_declaration_and_the_arrow_to_write) :-
    message_to_string(
        error(petta_untypable_declaration(inc, ['List', 'Number']), none),
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
    once(sub_string(Text, _, _, _, "has_type")).

%lib_nars.metta writes NARS inheritance as (--> $a $b) and
%lib_combinatorics.metta writes a lambda as (|-> ...). Both are deliberate
%atoms in data positions, and a spelling rule would have rejected them.
test(a_declaration_for_a_name_with_no_equations_is_data) :-
    Name = 'plunit-untypable-belief',
    setup_call_cleanup(
        assertz(user:silent(true), SilentRef),
        setup_call_cleanup(
            true,
            ( user:process_metta_string("(: plunit-untypable-belief \c
                                         (--> Cat Animal))", _),
              user:type_declaration(Name, Type),
              Type == ['-->', 'Cat', 'Animal'] ),
            user:'remove-atom'('&self', [':', Name, _], _)),
        erase(SilentRef)).

:- end_tests(filereader_untypable_declaration).
