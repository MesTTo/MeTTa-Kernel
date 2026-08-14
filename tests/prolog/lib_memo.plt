% Purpose: direct PlUnit coverage for memoization storage and eviction.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- initialization(consult('../../src/metta.pl')).
:- initialization(consult('../../lib/lib_memo.pl')).

:- begin_tests(memo_eviction_output,
               [ setup((retractall(user:memo_size_limit(_)),
                        assertz(user:memo_size_limit(100)),
                        retractall(user:metta_memo_total_bytes(_)),
                        assertz(user:metta_memo_total_bytes(100)),
                        assertz(user:metta_memo_head(test_fun, 1, 0)),
                        assertz(user:metta_memo_tail(test_fun, 1, 1)),
                        assertz(user:metta_memo_count(test_fun, 1, 1)),
                        assertz(user:metta_memo_q(test_fun, 1, 1, [key])),
                        assertz(user:metta_memo_entry(test_fun, 1, 0,
                                                      [key], [value])))),
                 cleanup((retractall(user:memo_size_limit(_)),
                          retractall(user:metta_memo_total_bytes(_)),
                          retractall(user:metta_memo_head(test_fun, 1, _)),
                          retractall(user:metta_memo_tail(test_fun, 1, _)),
                          retractall(user:metta_memo_count(test_fun, 1, _)),
                          retractall(user:metta_memo_q(test_fun, 1, _, _)),
                          retractall(user:metta_memo_entry(test_fun, 1, _, _, _))))
               ]).

capture_user_error(Goal, Text) :-
    new_memory_file(Memory),
    setup_call_cleanup(
        open_memory_file(Memory, write, ErrorStream),
        ( current_input(Input),
          current_output(Output),
          stream_property(OriginalError, alias(user_error)),
          setup_call_cleanup(
              set_prolog_IO(Input, Output, ErrorStream),
              call(Goal),
              set_prolog_IO(Input, Output, OriginalError)) ),
        close(ErrorStream)),
    memory_file_to_string(Memory, Text),
    free_memory_file(Memory).

test(routine_eviction_is_silent) :-
    capture_user_error(user:evict_global_space(1), Output),
    Output == "",
    \+ user:metta_memo_entry(test_fun, 1, _, [key], _).

:- end_tests(memo_eviction_output).
