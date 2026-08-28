% Purpose: run ONE engine benchmark case in this process and print its
%   counters, so the engine can be measured with no host in it at all. Every
%   other benchmark in this tree reaches the engine through a host, so an
%   engine change's cost is only ever observed with a host's cost added to it.
%   The process here is `swipl` and nothing else.
% Assumes:
%   - it is loaded BEFORE the engine, by
%     `swipl -g "metta_bench:bench_run(<case>)" -t halt engine/bench.pl`, and
%     never consulted by engine/metta.pl. The boot case
%     measures loading the engine, so a file that had already loaded it could
%     not measure that at all.
%   - engine/qlf_boot.pl and engine/metta.pl load the way engine/main.pl loads
%     them: qlf_boot first, then metta under set_prolog_flag(qcompile, auto),
%     both named without their extension so SWI takes the .qlf when it is
%     fresh. bench_boot/0 is that pair, copied rather than shared because
%     main.pl runs it in directives at ITS load time and this has to run it
%     inside a measured region [source: engine/main.pl:30-47]. main.pl's
%     torn-artifact retry, which purges the whole .qlf set and loads again on
%     any error, is deliberately NOT copied: a measurement that silently
%     repaired its own inputs and carried on would report the repair's cost as
%     the engine's.
%   - spaces:deferred_metta_function/6 is the engine's register of equations
%     whose translation is deferred. The translate case reads it only to CHECK
%     that its own forcing pass left nothing behind; the pass itself drives
%     the public metta_ensure_compiled/1 over names read out of the parse.
%     If that register is renamed this file throws `Unknown procedure` and
%     says so here rather than measuring less than it claims.
%   - the .qlf artifact set is warm. engine/bench.py warms it before sampling,
%     because a generating boot is a different workload from a loading one:
%     3,129,543 inferences against 612,598 [measured 2026-08-28].
% Guarantees:
%   - every case CHECKS its own result before its counters are printed, so a
%     case that stopped doing its work fails instead of reporting a cheaper
%     number [tested: engine/bench.sh; commit=WORKTREE].
%   - the measured region excludes setup and excludes the check, and when perf
%     supplies its control descriptors the enabled window brackets exactly the
%     same region [tested: engine/bench.sh; commit=WORKTREE].
%   - the inference delta is identical whether or not the run is under perf,
%     because the control writes sit OUTSIDE the counter reads
%     [measured 2026-08-28: every case identical across three plain runs and
%     three runs under `perf stat -e instructions:u`].
% Decides:
%   - the workloads are the tree's own text, not synthetic strings: the
%     engine's prelude for the reader, lib_pln for the translator, and the two
%     ch18 performance kernels for matching and reduction. Each is named in
%     bench_source/1 and engine/bench.py digests them into the baseline stamp,
%     so an edit to one REFUSES the comparison rather than reporting a move
%     the code did not cause.
%   - sizes are chosen so each measured region is large enough that the
%     measurement frame (4 inferences) and, where it applies, reading a short
%     query's own source are a negligible share, while a whole case still runs
%     in well under a second.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%A module that exports NOTHING. engine/metta.pl declares no module of its own,
%so the engine loads into whatever module its loader runs in, and a plain file
%here would put every bench_ name into `user` beside it -- the same `user` a
%MeTTa program's definitions reach, where a collision REPLACES the colliding
%predicate rather than refusing. Keeping the cases out of it costs the two
%`user:` qualifications in bench_boot_prepare/0 and bench_boot_load/0, which
%are what still load the engine where it belongs.
%
%It does NOT make the boot case independent of this file, and that was
%measured rather than assumed: appending one inert fact moves boot from
%612,598 inferences to 612,740 and evaluate from 4,276,161 to 4,276,145 with
%the module in place exactly as it did without, ten facts move boot to
%612,896, and removing them moves both back. The same boot with NO benchmark
%file in the process at all reads 612,610. So the process's predicate set is
%part of what the engine's boot costs, non-monotonically, and an edit to this
%file re-pins boot and evaluate. The boot row's `measures` in
%engine/bench-baseline.json carries the numbers [measured 2026-08-28].
:- module(metta_bench, []).

:- prolog_load_context(directory, BenchDirectory),
   asserta(bench_engine_directory(BenchDirectory)).

bench_root(Root) :-
    bench_engine_directory(Directory),
    atom_concat(Directory, '/..', Parent),
    absolute_file_name(Parent, Root, [file_type(directory)]).

bench_path(Relative, Path) :-
    bench_root(Root),
    atomic_list_concat([Root, '/', Relative], Path).

bench_text(Relative, Text) :-
    bench_path(Relative, Path),
    read_file_to_string(Path, Text, [encoding(utf8)]).

%%%% What the suite measures %%%%
%
% bench_case(Name, Unit, Operations). Operations is what the measured region
% completes, and every case verifies it: a loop runs exactly that many rounds,
% and a single-shot case checks the size of the answer it produced.

bench_case(boot,           boot,       1).
bench_case(parse,          parse,     25).
bench_case('parse-prolog', parse,     25).
bench_case(translate,      function,  49).
bench_case(match,          query,    600).
bench_case('match-skew',   query,     20).
bench_case(evaluate,       reduction, 50000).

% The corpus text the cases read. engine/bench.py digests exactly this list
% into the baseline's configuration stamp.
bench_source('engine/prelude.metta').
bench_source('lib/lib_pln/lib_pln.metta').
bench_source('examples/ch18-performance/18-01-larger-workloads/01-scale.metta').
bench_source('examples/ch18-performance/18-01-larger-workloads/02-holbenchmark.metta').

%%%% Booting the engine %%%%
%
% engine/main.pl's two load directives, run as goals so the boot case can put
% the counters around them, and split at the same seam main.pl splits them:
% engine/qlf_boot.pl decides artifact freshness, engine/metta.pl is the engine.
%
% The boot case measures the SECOND half only, which is what "consulting
% engine/metta.pl to a usable state" means. The first half is deliberately
% outside, because its cost is a function of how many .qlf files happen to be
% on this disk rather than of the engine: purge_stale_qlf/0 walks every one of
% them with time_file/2, and one extra file moves the count 6 inferences, past
% the harness's 4-inference allowance. That is not hypothetical. Booting
% through engine/main.pl writes engine/metta.qlf and booting through this file
% does not, so a tree that has run the CLI carries 14 engine artifacts and a
% tree that has only ever run this suite carries 13, and the same engine read
% 1,423,280 and 1,423,274 [measured 2026-08-28]. With the walk in setup both
% states read the same number.
bench_boot :-
    bench_boot_prepare,
    bench_boot_load.

% Both names are spelled WITHOUT the .pl, which is how engine/main.pl spells
% them and is load-bearing rather than cosmetic: SWI resolves an extensionless
% name through the prolog file type and takes engine/metta.qlf when it is
% fresh, while an explicit engine/metta.pl compiles the umbrella from source
% every time. Named with the extension, this case read 1,416,424 inferences
% with the artifact present or absent, because it was never loading it; named
% without, it loads what every `sh run.sh` loads [measured 2026-08-28].
% Both loads are qualified with user:, which is the module engine/main.pl
% loads the engine into. ensure_loaded/1 takes its context module from the
% caller, so an unqualified call from this module would load a plain
% engine/metta.pl into metta_bench and measure a configuration nothing ships.
bench_boot_prepare :-
    bench_path('engine/qlf_boot', QlfBoot),
    user:ensure_loaded(QlfBoot).

bench_boot_load :-
    bench_path('engine/metta', Metta),
    current_prolog_flag(qcompile, Previous),
    setup_call_cleanup(set_prolog_flag(qcompile, auto),
                       user:ensure_loaded(Metta),
                       set_prolog_flag(qcompile, Previous)).

% Boot, then silence the loader. Every case but `boot` loads corpus text in
% setup, and a loud load prints each form AND forces the translation the
% translate case exists to measure [source: engine/filereader.pl:684-686].
bench_boot_quiet :-
    bench_boot,
    metta_host_set_silent(true).

% Definitions only. A corpus file's runnable forms are its own demonstration,
% and running them would make setup do the work the case is supposed to
% measure, so they are dropped and the vocabulary is kept.
bench_definitions(Text, Source) :-
    metta_host_read_forms(Text, Pairs),
    findall(FormText,
            ( member([Kind, FormText], Pairs), Kind \== runnable ),
            Kept),
    atomic_list_concat(Kept, '\n', Source).

%%%% Setup, work, check %%%%
%
% bench_setup(Case, State) runs untimed. bench_work(Case, State, Result) is the
% measured region and NOTHING else is. bench_check(Case, Result) runs untimed
% and fails the case when the work did not happen.

% Only the freshness decision, which is disk bookkeeping and not the engine.
bench_setup(boot, none) :- bench_boot_prepare.
% engine/prelude.metta is the engine's own MeTTa vocabulary and every boot
% reads it through parse_metta_source/2, so it is the exact text the reader is
% asked for in production rather than a string invented for a benchmark. The
% two cases read it the same number of times through the two doors: the
% shipped one, whose work is in C and therefore invisible to the inference
% counter, and parse_metta_source_prolog/2. Note what the second one is on a
% built tree: its Prolog half is the form SPLITTER, since each split form's
% term goes through sread_mode/3, which takes metta_c_sread/3 while
% engine/reader.so is active [source: engine/parser.pl:836-842]. The per-form
% Prolog grammar is reached only with METTA_C_READER=off, which is a different
% configuration with its own stamp.
bench_setup(parse, Text) :- bench_setup_parse(Text).
bench_setup('parse-prolog', Text) :- bench_setup_parse(Text).
% lib_pln is the largest pure-equation library in the tree: 82 forms, 77 of
% them equations over 49 distinct names, no runnable form and no import. The
% names are read out of the parse, which is the same shape
% source_equation_name/2 reads [source: engine/filereader.pl:956], and loading
% the library REGISTERS them with their translation deferred, so forcing them
% is a translator measurement with the reader and the loader already paid for.
bench_setup(translate, Names) :- bench_setup_translate(Names).
% examples/ch18-performance/18-01-larger-workloads/01-scale.metta is the
% corpus's own indexing benchmark, and its five query shapes are exactly the
% index shapes the store has to tell apart. Its own !(test ...) runs a million
% atoms; 50,000 keeps a case under a second and keeps every shape's answer
% count fixed, because 643 and 42 are below it and it is a multiple of ten.
bench_setup(match, Space) :- bench_setup_scale(Space).
bench_setup('match-skew', Space) :- bench_setup_scale(Space).
% examples/ch18-performance/18-01-larger-workloads/02-holbenchmark.metta is the
% corpus's million-step reduction kernel. map-flat over a built range is pure
% rewriting: no space write, no I/O, one let and one cons per element. The
% pragma raises the evaluator's 100,000-reduction fuel the way the corpus file
% raises it for its own million-element run.
bench_setup(evaluate, Space) :- bench_setup_hol(Space).

bench_setup_parse(Text) :-
    bench_boot_quiet,
    bench_text('engine/prelude.metta', Text).

bench_setup_translate(Names) :-
    bench_boot_quiet,
    bench_text('lib/lib_pln/lib_pln.metta', Text),
    parse_metta_source(Text, Forms),
    findall(Name, member(parsed(function, _, [=, [Name|_], _]), Forms), Found),
    sort(Found, Names),
    %Said out loud rather than left to fail: a silent failure here would reach
    %the caller as `goal failed` with no clue which assumption moved. The
    %baseline's workload digest refuses first when the file is edited, so this
    %is the door for a library that changed some other way.
    (   length(Names, 49)
    ->  true
    ;   throw(error(domain_error(bench_workload, Names),
                    context(bench_setup/2,
                            'lib/lib_pln/lib_pln.metta no longer \c
                             defines 49 function names')))
    ),
    process_metta_string(Text, _, '&bench-pln').

% The warm-up round is what makes the two match cases steady. A query is
% idempotent, so running each shape once in setup changes nothing about what
% the region measures, and it moves two one-time costs out of it: the runnable
% template each query text compiles on first use, and whatever stack growth
% the first large answer forces. Without it the instruction count kept two
% modes 1.0% to 2.7% apart across triples with the inference count identical
% throughout, which is the same signature extensions/python/benchmarks/pure.py
% records for alpha-unique and answers the same way [measured 2026-08-28].
bench_setup_scale('&bench-scale') :-
    bench_boot_quiet,
    bench_text('examples/ch18-performance/18-01-larger-workloads/01-scale.metta',
               Text),
    bench_definitions(Text, Definitions),
    process_metta_string(Definitions, _, '&bench-scale'),
    process_metta_string("!(addK 50000)", _, '&bench-scale'),
    bench_selective_rounds(1, '&bench-scale', _),
    bench_query_rounds(1, "!(q-second 3)", '&bench-scale', _).

bench_setup_hol('&bench-hol') :-
    bench_boot_quiet,
    bench_text('examples/ch18-performance/18-01-larger-workloads/02-holbenchmark.metta',
               Text),
    bench_definitions(Text, Definitions),
    process_metta_string(Definitions, _, '&bench-hol'),
    process_metta_string("!(pragma! max-stack-depth 100000000)", _, '&bench-hol').

bench_work(boot, none, booted) :- bench_boot_load.
bench_work(parse, Text, Forms) :-
    bench_parse_rounds(25, parse_metta_source, Text, Forms).
bench_work('parse-prolog', Text, Forms) :-
    bench_parse_rounds(25, parse_metta_source_prolog, Text, Forms).
bench_work(translate, Names, forced) :-
    forall(member(Name, Names), metta_ensure_compiled(Name)).
bench_work(match, Space, Rows) :-
    bench_selective_rounds(200, Space, Rows).
bench_work('match-skew', Space, Rows) :-
    bench_query_rounds(20, "!(q-second 3)", Space, Rows).
bench_work(evaluate, Space, Result) :-
    process_metta_string("!(let $t (map-flat (+ 1) (range 50000)) (length $t))",
                         Result, Space).

% A usable engine, not merely a loaded one: the check evaluates through the
% same door a program uses.
bench_check(boot, booted) :-
    metta_host_set_silent(true),
    process_metta_string("!(+ 1 2)", [3], '&self').
bench_check(parse, Forms) :- length(Forms, 117).
bench_check('parse-prolog', Forms) :- length(Forms, 117).
% Forcing drove the 49 names read from the source. The deferred register is
% the engine's own account of what is left, and it has to be empty.
bench_check(translate, forced) :-
    \+ spaces:deferred_metta_function(_, _, _, _, _, _),
    process_metta_string("!(clamp 5 1 3)", [3], '&bench-pln').
bench_check(match, rows(First, Both, Relation)) :-
    length(First, 1), length(Both, 1), length(Relation, 1).
bench_check('match-skew', Rows) :- length(Rows, 5000).
bench_check(evaluate, [50000]).

% Each round parses into a FRESH variable. Threading one output through the
% loop instead makes every round after the first unify against the previous
% answer, which the Prolog reader raises a type error for and the C reader
% pays a whole structure comparison for; only the last round's forms leave.
bench_parse_rounds(1, Reader, Text, Forms) :-
    !,
    call(Reader, Text, Forms).
bench_parse_rounds(Rounds, Reader, Text, Forms) :-
    call(Reader, Text, _),
    Remaining is Rounds - 1,
    bench_parse_rounds(Remaining, Reader, Text, Forms).

% The three selective shapes 01-scale.metta defines, one round each: first
% column bound, both columns bound, and the relation itself a variable. Each
% answers exactly one row out of 50,000, which is what makes them selective.
bench_selective_rounds(1, Space, rows(First, Both, Relation)) :-
    !,
    bench_query("!(q-first 7)", Space, First),
    bench_query("!(q-both 42 2)", Space, Both),
    bench_query("!(q-rel r)", Space, Relation).
bench_selective_rounds(Rounds, Space, Rows) :-
    bench_query("!(q-first 7)", Space, _),
    bench_query("!(q-both 42 2)", Space, _),
    bench_query("!(q-rel r)", Space, _),
    Remaining is Rounds - 1,
    bench_selective_rounds(Remaining, Space, Rows).

bench_query_rounds(1, Query, Space, Rows) :-
    !,
    bench_query(Query, Space, Rows).
bench_query_rounds(Rounds, Query, Space, Rows) :-
    bench_query(Query, Space, _),
    Remaining is Rounds - 1,
    bench_query_rounds(Remaining, Query, Space, Rows).

% One query through the engine's source door, which is how a MeTTa program
% asks one. collapse answers one atom holding the matched rows.
bench_query(Query, Space, Rows) :-
    process_metta_string(Query, [Rows], Space).

%%%% Measurement %%%%
%
% The counter reads sit INSIDE perf's window rather than outside it, so the
% inference delta is the same number whether or not perf is watching. The
% delta carries a fixed 4-inference measurement frame, which is four orders of
% magnitude below the smallest pin here.
bench_timed(Case, State, Result, Inferences, Cpu, Wall) :-
    statistics(cputime, Cpu0),
    get_time(Wall0),
    statistics(inferences, Inferences0),
    bench_work(Case, State, Result),
    statistics(inferences, Inferences1),
    get_time(Wall1),
    statistics(cputime, Cpu1),
    Inferences is Inferences1 - Inferences0,
    Cpu is Cpu1 - Cpu0,
    Wall is Wall1 - Wall0.

% perf's control-descriptor protocol, the same handshake
% extensions/python/benchmarks/pure.py speaks: write `enable`, wait for the
% acknowledgement, run, write `disable`, wait again. Without it perf counts
% the whole process and every case would carry the engine boot.
%
% SWI has no door onto an inherited descriptor, so the pipes are reopened
% through /proc/self/fd, which on Linux hands back a new description on the
% same pipe. The read side takes a timeout because the descriptors perf owns
% stay open in this process: if perf died mid-run the acknowledgement would
% never arrive and never reach end of file either.
%
% A command goes out in ONE write, which is what makes the protocol work at
% all: perf reads a control message with a single read and matches the whole
% buffer against its command tags, so a command split across writes is a
% command perf cannot recognise. buffer(false) made SWI write `enable` as
% seven one-byte syscalls, and perf's poll can wake between two of them: one
% case in twenty-one failed that way at loadavg 13.2, with perf exiting 2 and
% this process waiting out its own timeout for an acknowledgement that was
% never coming. Under strace, which widens the same gap, the unbuffered form
% fails EVERY run: `strace -e trace=write` shows seven `write(3, "e", 1)`
% calls and perf returns 2, while the buffered form shows one
% `write(3, "enable\n", 7)` and returns 0 [measured 2026-08-28, the same case
% run under `strace -f -e trace=write` inside measure_instructions'
% controlled window with each spelling in turn]. Seven bytes is far below
% PIPE_BUF, so the buffered write is atomic
% [source: POSIX.1-2017 write(), the PIPE_BUF guarantee].
bench_window(Goal) :-
    (   getenv('METTA_PERF_CONTROL_FD', ControlText),
        getenv('METTA_PERF_ACK_FD', AcknowledgeText)
    ->  bench_control_streams(ControlText, AcknowledgeText, Control, Acknowledge),
        setup_call_cleanup(
            bench_control(Control, Acknowledge, "enable"),
            Goal,
            ( bench_control(Control, Acknowledge, "disable"),
              close(Control),
              close(Acknowledge) ))
    ;   call(Goal)
    ).

bench_control_streams(ControlText, AcknowledgeText, Control, Acknowledge) :-
    atom_number(ControlText, ControlDescriptor),
    atom_number(AcknowledgeText, AcknowledgeDescriptor),
    format(atom(ControlPath), '/proc/self/fd/~w', [ControlDescriptor]),
    format(atom(AcknowledgePath), '/proc/self/fd/~w', [AcknowledgeDescriptor]),
    open(ControlPath, write, Control, [type(binary), buffer(full)]),
    open(AcknowledgePath, read, Acknowledge, [type(binary)]),
    set_stream(Acknowledge, timeout(60)).

bench_control(Control, Acknowledge, Command) :-
    string_codes(Command, Codes),
    forall(member(Code, Codes), put_byte(Control, Code)),
    put_byte(Control, 0'\n),
    flush_output(Control),
    bench_acknowledged(Acknowledge).

% perf writes exactly the five bytes `ack\n\0`, its command tag plus the string
% terminator [measured 2026-08-28 under `strace -f -e trace=read`: two reads,
% one per command, each `read(4, "ack\n\0", 4096) = 5`]. Stopping at the
% NEWLINE rather than at the end of the read is what makes that trailing NUL
% harmless: it stays in the stream buffer and is consumed at the head of the
% next acknowledgement.
bench_acknowledged(Acknowledge) :-
    get_byte(Acknowledge, Byte),
    (   Byte =:= 0'\n
    ->  true
    ;   Byte =:= -1
    ->  throw(error(io_error(read, Acknowledge),
                    context(bench_acknowledged/1,
                            'perf closed its acknowledgement pipe')))
    ;   bench_acknowledged(Acknowledge)
    ).

%%%% Entry points %%%%

bench_run(Case) :-
    (   bench_case(Case, Unit, Operations)
    ->  true
    ;   throw(error(domain_error(bench_case, Case),
                    context(bench_run/1, 'no such benchmark case')))
    ),
    bench_setup(Case, State),
    bench_window(bench_timed(Case, State, Result, Inferences, Cpu, Wall)),
    (   bench_check(Case, Result)
    ->  true
    ;   throw(error(domain_error(bench_result, Case),
                    context(bench_run/1,
                            'the case did not produce the result it measures')))
    ),
    format("metta-bench case=~w unit=~w operations=~w inferences=~w \c
            cputime=~6f walltime=~6f~n",
           [Case, Unit, Operations, Inferences, Cpu, Wall]).

% What the suite is, printed without booting anything, so the driver holds no
% second copy of the case table or the workload list.
bench_describe :-
    forall(bench_case(Name, Unit, Operations),
           format("metta-bench-case name=~w unit=~w operations=~w~n",
                  [Name, Unit, Operations])),
    forall(bench_source(Relative),
           format("metta-bench-source path=~w~n", [Relative])).
