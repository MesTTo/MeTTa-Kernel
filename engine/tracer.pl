% Purpose: the reduction trace. metta_trace_source/3 runs MeTTa source
%   with every compiled MeTTa function wrapped by SWI's own
%   wrap_predicate, recording a call event with the input term and an
%   exit event with the answer per reduction, depth-nested through the
%   call tree, then unwraps whole, so tracing costs nothing when off. A
%   reduction that fails leaves its call without an exit, which is what
%   failing looks like. Events answer as event/5 terms carrying the term
%   itself, depth, kind, term, answer, and the names of the term's
%   variables.
% Guarantees:
%   - Functions defined by the traced source and calls from hyperpose workers
%     produce events [tested 2026-08-14: tracer].
%   - A symbol whose spelling reads back as something else survives the
%     trip: the trace and run answer the same atom
%     [tested 2026-08-15: tracer:a_symbol_that_looks_like_a_variable_stays_a_symbol].
%   - Traced get-type extensions report their public function name
%     [tested 2026-08-15: tracer:type_extensions_keep_the_public_name].
%   - A registered predicate whose clauses clause/3 refuses, a foreign one or
%     a builtin, is skipped rather than raising out of the whole trace
%     [tested 2026-08-16: test_a_foreign_predicate_does_not_break_tracing].
% Owns:
%   - metta_trace_source/4 removes every metta_tracer wrapper and state fact,
%     including after an event-limit error [tested 2026-08-14:
%     tracer:event_limit_truncates_and_removes_every_wrapper].
% Guarded by:
%   - '$metta_trace_state' serializes trace sessions and wrapper changes
%     [tested 2026-08-14: tracer:event_limit_truncates_and_removes_every_wrapper].
%   - '$metta_trace_events' assigns event sequence numbers and enforces the
%     event bound across hyperpose worker threads [tested 2026-08-14: tracer].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%Three predicates: what a trace records for a host, and the two questions
%engine/ext_points.pl asks before it wraps a compiled function. The event
%buffer, the sequence counter and the wrapper bodies are this subsystem's own
%[tested: engine_layering:test_the_engine_layering_contract_holds_and_a_violation_is_named].
:- module(tracer,
          [ metta_trace_source/4,
            metta_trace_source/5,
            metta_trace_default_events/1,
            metta_trace_target/1,
            metta_trace_wrap_once/1
          ]).

%metta_trace_source/4 reads the values off a pairs list. Imported here rather
%than into the engine module, because this is the only file that wants it and a
%module of one's own is what makes that distinction possible to state.
:- use_module(library(pairs), [pairs_values/2]).

:- dynamic metta_trace_event/2.
:- dynamic metta_trace_limit/1.
:- dynamic metta_trace_next_seq/1.
:- dynamic metta_trace_session/0.
:- dynamic metta_trace_truncated/0.
:- dynamic metta_trace_cells/1.
:- dynamic metta_trace_wrapped/1.

%Every name the translator compiled from equations, in &self's module and in
%each other space module that registered it: exactly the predicates owning at
%least one translated_from-tracked clause. Builtins and imports never do,
%which keeps a trace about the program, not the engine, and keeps the
%wrap away from library predicates a weak import makes visible.
metta_trace_target(Module:F/A) :-
    arity(LogicalF, A),
    ( fun_in(Module, LogicalF) ; metta_self_module(Module) ),
    compiled_function_name(LogicalF, F),
    current_predicate(Module:F/A),
    functor(Head, F, A),
    \+ predicate_property(Module:Head, imported_from(_)),
    %clause/3 REFUSES a predicate it cannot show, raising
    %permission_error(access, private_procedure, _) rather than failing, and a
    %foreign predicate is one of those. Registering a single C extension
    %anywhere in the process therefore made EVERY trace raise
    %`clause/3: No permission to access private_procedure 'c-bump'/2', because
    %this walks every registered arity looking for tracked clauses and reaches
    %the foreign one on the way
    %[tested: test_a_foreign_predicate_does_not_break_tracing].
    %
    %number_of_clauses is the guard rather than a list of kinds to skip: it is
    %true for exactly the predicates clause/3 accepts and false for every one
    %it refuses, foreign and builtin alike [measured 2026-08-16: false for
    %is/2, atom_length/2 and format/2, all three of which raise; true for
    %append/3, which does not].
    predicate_property(Module:Head, number_of_clauses(_)),
    once(( clause(Module:Head, _, Ref),
           clause_property(Ref, module(Module)),
           translated_from(Ref, _) )).

metta_trace_wrap(Module:F/A) :-
    functor(Head, F, A),
    compiled_function_name(LogicalF, F),
    In is A - 1,
    wrap_predicate(Module:Head, metta_tracer, Closure,
                   metta_trace_call(LogicalF, In, Head, Closure)).

metta_trace_unwrap(Module:F/A) :-
    catch(unwrap_predicate(Module:F/A, metta_tracer), _, true).

metta_trace_wrap_once(Target) :-
    ( metta_trace_wrapped(Target) -> true
    ; metta_trace_wrap(Target),
      assertz(metta_trace_wrapped(Target)) ).

%A function compiled while a trace is active must be wrapped before the next
%form runs. The compiled-clause event, not the definition event: wrapping
%needs the predicate, and under deferred translation function_changed fires
%when the equation ARRIVES, which can be before any clause exists to wrap;
%this one fires once per compiled equation, arrival-translated and
%materialised alike.
:- multifile seam:function_clauses_changed/1.
seam:function_clauses_changed(F) :-
    with_mutex('$metta_trace_state',
               ( metta_trace_session
                 -> compiled_function_name(F, Predicate),
                    findall(Target,
                            ( metta_trace_target(Target),
                              Target = _Module:Predicate/_Arity ),
                            Targets0),
                    sort(Targets0, Targets),
                    maplist(metta_trace_wrap_once, Targets)
                 ; true )).

metta_trace_call(F, In, Head, Closure) :-
    Head =.. [_|Args],
    length(InArgs, In),
    append(InArgs, [Out], Args),
    ( nb_current('$metta_trace_depth', D) -> true ; D = 0 ),
    metta_trace_record(D, call, [F|InArgs], ''),
    D1 is D + 1,
    b_setval('$metta_trace_depth', D1),
    call(Closure),
    b_setval('$metta_trace_depth', D),
    metta_trace_record(D, exit, [F|InArgs], Out).

%An event carries the term, not the term's text. Written with swrite and
%read back by the receiver, every symbol whose spelling reads as something
%else changed on the way: a stored (holds $notvar) traced as a variable
%while run answered the symbol, a semicolon truncated the rest of the term
%at the comment it starts, and a tab inside a symbol split the record into
%the wrong fields altogether. Variables are named by first occurrence,
%which is the one thing the text form did that a reader wants kept.
metta_trace_record(Depth, Kind, Term, Answer) :-
    copy_term(Term-Answer, TermCopy-AnswerCopy),
    term_variables(TermCopy-AnswerCopy, Variables),
    metta_trace_variable_names(Variables, 0, Names),
    Event = event(Depth, Kind, TermCopy, AnswerCopy, Names),
    term_size(Event, EventCells),
    with_mutex('$metta_trace_events',
               ( metta_trace_next_seq(N),
                 metta_trace_limit(Max),
                 metta_trace_cells(Cells),
                 Cells1 is Cells + EventCells,
                 metta_trace_cell_budget(Budget),
                 N1 is N + 1,
                 ( ( N1 > Max ; Cells1 > Budget )
                   -> ( metta_trace_truncated -> true
                      ; assertz(metta_trace_truncated) ),
                      throw('$metta_trace_bound_reached')
                 ; retractall(metta_trace_next_seq(_)),
                   assertz(metta_trace_next_seq(N1)),
                   retractall(metta_trace_cells(_)),
                   assertz(metta_trace_cells(Cells1)),
                   assertz(metta_trace_event(N, Event)) ) )).

%The throw still ABORTS the run, and metta_trace_source/5 catches it and
%answers the events recorded so far. Both halves matter and the earlier
%design had only one of each.
%
%Aborting is what bounds the TIME. The bound is a count, so a trace that
%merely stopped recording still ran the whole program: 02-tilepuzzle.metta
%at max_events 5000 did not finish in 240 seconds that way, where the
%abort ends it in seconds. A caller asking to be bounded is asking not to
%pay for the rest.
%
%Answering the prefix is what stops the memory being spent for nothing.
%The bound is a count and the memory an event costs is the size of its
%term, which nothing bounds, so a throw that also discarded the events
%charged the full memory of the bound and returned no trace: measured
%2026-09-03 on 02-tilepuzzle.metta, max_events 5000 peaks 0.08GB and
%10000 peaks 0.26GB, and a downstream renderer measured 50000 at 5.77GB,
%100000 above 14GB, and six concurrent renders taking a 60GB machine to
%2GB free -- every one of them raising and answering nothing.
%
%'$metta_trace_bound_reached' is a bare atom rather than an error term
%because it is this module's own control flow and must not be mistaken
%for, or caught by, anything that handles error/2. It never escapes
%metta_trace_source/5.

%_0, _1 and so on, by first occurrence, which is the naming swrite applied
%when an event crossed as text. The pairs travel with the term, so a
%receiver that encodes variables by name reads the same spelling; the
%leading $ belongs to the spelling of a variable, not to its name.
metta_trace_variable_names([], _, []).
metta_trace_variable_names([Variable|Rest], Index, [Name-Variable|Names]) :-
    atom_concat('_', Index, Name),
    Next is Index + 1,
    metta_trace_variable_names(Rest, Next, Names).

metta_trace_begin(Max) :-
    with_mutex('$metta_trace_state', metta_trace_begin_unlocked(Max)).

metta_trace_begin_unlocked(Max) :-
    ( metta_trace_session
      -> throw(error(permission_error(trace, evaluation, nested),
                     context(metta_trace_source/3,
                             'a trace is already running')))
    ; retractall(metta_trace_event(_, _)),
      retractall(metta_trace_limit(_)),
      retractall(metta_trace_next_seq(_)),
      retractall(metta_trace_truncated),
      retractall(metta_trace_cells(_)),
      assertz(metta_trace_cells(0)),
      retractall(metta_trace_wrapped(_)),
      assertz(metta_trace_limit(Max)),
      assertz(metta_trace_next_seq(0)),
      assertz(metta_trace_session),
      catch(( findall(Target, metta_trace_target(Target), Targets0),
              sort(Targets0, Targets),
              maplist(metta_trace_wrap_once, Targets) ),
            Error,
            ( metta_trace_end_unlocked, throw(Error) )) ).

metta_trace_end :-
    with_mutex('$metta_trace_state', metta_trace_end_unlocked).

metta_trace_end_unlocked :-
    findall(Target, metta_trace_wrapped(Target), Targets),
    maplist(metta_trace_unwrap, Targets),
    retractall(metta_trace_wrapped(_)),
    retractall(metta_trace_session),
    retractall(metta_trace_limit(_)),
    retractall(metta_trace_next_seq(_)),
    retractall(metta_trace_truncated),
    retractall(metta_trace_cells(_)),
    retractall(metta_trace_event(_, _)).

%Run Source in Space with the trace armed; Events come back oldest
%first, at most Max of them. Past the bound the recording STOPS and
%Truncated is true, so the caller keeps the prefix it asked to be bounded
%to: an event costs the size of its term and nothing bounds that, so a
%throw at the bound discarded everything already recorded and charged the
%full memory of the bound for no answer. The five-argument form reports
%whether the events are a prefix; the four- and three-argument forms drop
%that and carry the default bound. Each event is
%event(Depth, Kind, Term, Answer, VariableNames), Answer being '' on a
%call, and VariableNames pairing $_0, $_1 with the term's variables.
%
%DEFAULT_TRACE_EVENTS is 10000 rather than the 1000000 it was through
%2026-09-03. An unqualified trace has to be survivable on an ordinary
%machine, and the old default was not: measured on
%examples/ch22-a-reasoner-you-can-serve/22-03-search/02-tilepuzzle.metta,
%10000 events peak 0.26GB and a downstream renderer measured 50000 at
%5.77GB and 100000 above 14GB, six concurrent renders taking a 60GB
%machine to 2GB free. Truncation is what makes a low default safe rather
%than lossy: a caller who needs more asks for more and can SEE that the
%first answer was cut.
%A COUNT cannot bound the memory, because an event costs the size of its
%term and nothing bounds that. Measured 2026-09-03 on
%examples/ch22-a-reasoner-you-can-serve/22-03-search/02-tilepuzzle.metta,
%whose terms are search states: 1000 events peak 0.13GB, 5000 peak 1.38GB,
%and 10000 exceeded a 4GB cap and died. The same 10000 on an ordinary
%program costs nothing at all. So the bound a caller can set is a count
%because that is what a caller can reason about, and the bound that keeps
%the process alive is this, in cells of the Prolog store.
%
%Both truncate identically, so a caller never has to know which one
%stopped it; Truncated says only that the events are a prefix. Charged on
%the term ALREADY copied, so it costs a term_size walk over a term
%copy_term has just walked anyway.
%
%4 million cells is 32MB at 8 bytes a cell, and it is chosen from the
%measurement rather than the arithmetic: answering a trace collects,
%encodes, crosses and rebuilds it, each step holding its own copy, and
%that pipeline costs about twenty times the recorded size. On
%02-tilepuzzle.metta, which peaks at 0.19GB untraced, a whole traced run
%peaks at 0.39GB for 2M cells, 0.73GB for 4M and 2.76GB for 16M. 4M keeps
%the worst program measured under a gigabyte while leaving 4,035 events of
%it, and an ordinary program never reaches the budget at all: the 42-event
%trace of a recursive count is unchanged.
%
%The twenty-fold pipeline is where a streaming door would pay, since it
%is the materialising and not the recording that dominates. Nothing here
%streams yet.
metta_trace_cell_budget(4000000).

metta_trace_default_events(10000).

metta_trace_source(Source, Space, Events) :-
    metta_trace_default_events(Max),
    metta_trace_source(Source, Space, Max, Events).

metta_trace_source(Source, Space, Max, Events) :-
    metta_trace_source(Source, Space, Max, Events, _Truncated).

metta_trace_source(Source, Space, Max, Events, Truncated) :-
    ( integer(Max), Max > 0 -> true
    ; throw(error(domain_error(positive_integer, Max),
                  context(metta_trace_source/5, 'max_events bound')))),
    setup_call_cleanup(
        metta_trace_begin(Max),
        ( b_setval('$metta_trace_depth', 0),
          catch(process_metta_string(Source, _Results, Space),
                '$metta_trace_bound_reached',
                true),
          with_mutex('$metta_trace_events',
                     ( findall(N-E, metta_trace_event(N, E), Pairs),
                       ( metta_trace_truncated -> Truncated = true
                       ; Truncated = false ) )),
          keysort(Pairs, Sorted),
          pairs_values(Sorted, Events) ),
        metta_trace_end).
