% Purpose: report every Prolog predicate the tree defines that nothing in the
%     tree can reach, and prove the detector still discriminates. `vulture` and
%     `jscpd` are both Python-only, and the prolog-static lane runs SWI's
%     list_undefined, list_trivial_fails, list_redefined, list_void_declarations
%     and list_autoload, none of which reports unreachability: a predicate
%     defined and never called is invisible to all six.
% Assumes:
%     - the working directory is tests/prolog, which is where check.sh runs
%       every Prolog lane from
%     - arity/2 is the engine's own dispatch table, so a MeTTa call site
%       compiles to a call of Name/Arity exactly when arity(Name, Arity) holds
%       [source: engine/metta.pl:3960, register_prolog_arities/1, which registers
%       every arity current_predicate/1 reports for a registered name]
%     - a multifile declaration is the permission an outside caller needs, so
%       every seam declared multifile is called from outside this tree
%       [source: engine/ext_points.pl, and tests/prolog/static_checks.pl already
%       requires every unqualified multifile seam to declare an
%       seam:kind/2]
%     - the Python half names its Prolog entry points as text, so a predicate
%       named inside a string literal in bindings/python/metta/*.py is called across
%       janus [source: bindings/python/metta/_engine.py, apply/2 and do/2 take the
%       predicate NAME and hand it to janus.apply_once/cmd]
% Guarantees:
%     - reachability_report/0 walks every clause of every predicate defined
%       under engine/, lib/, backends/, backends/mork/mork_ffi/ and bindings/python/metta/, plus one probe
%       clause per directive, and reports the predicates no root reaches
%       [measured 2026-08-18: 1550 predicates, 2602 clauses, 6984 call and 760
%       construct edges, 24 reported, 1.10s min of 3]
%     - the walk is SWI's own prolog_walk_code/1, so it reaches a call through
%       control structure, through a declared meta-argument and through a
%       meta-predicate nobody declared, which it infers [source: SWI-Prolog
%       library(prolog_codewalk), infer_meta_predicates option]
%     - a goal the engine BUILDS as a term and plants in a clause it generates
%       is reached, because every term a clause holds rather than calls is
%       scanned for the shape of one of this tree's predicates. That is not a
%       refinement, it is most of the analysis: without it the report is 206
%       rather than 24, and the 182 it adds are led by engine/duals.pl's 58 and
%       lib/lib_memo/lib_memo.pl's 46, every one of them live [measured 2026-08-18]
%     - each door is worth what it claims, measured by disabling it and counting
%       [measured 2026-08-18, against a baseline of 24]: the MeTTa dispatch root
%       422, the janus root 235, the construct edge 206, the head half of it 40,
%       the directive probe 37, the seam root 31, the closure arity rule 26,
%       `backends` in argv 26
%     - reachability_selftest/0 fails unless the analysis puts each of nine
%       planted predicates on the side its door predicts, three of them
%       REPORTED, and names which door stopped firing [measured 2026-08-18:
%       eleven mutations, each disabling exactly one root class, edge kind or
%       scan, were each caught with the exact set of doors predicted and
%       nothing else, 0.90s min of 3]
%     - the report answers about the tree it is run against and not about a
%       fixture [measured 2026-08-18 on a throwaway branch: appending an
%       uncalled predicate to engine/parser.pl took the report from 24 to 25 and
%       named it at engine/parser.pl:338, and declaring the same predicate
%       multifile took it back to 24 with the seam roots going 37 to 38]
% Fails when:
%     - a predicate is reached only by a name assembled at run time from parts,
%       `atom_concat(Prefix, Suffix, Name), Goal =.. [Name|Args]` being the
%       shape. Nothing static sees that, and neither does list_undefined.
%     - a term that merely LOOKS like one of this tree's predicates sits in a
%       goal's argument. That marks its lookalike reached, so the report
%       under-counts rather than crying wolf, which is the error direction a
%       burn-down list wants. The Python scan is the same trade in text: reading
%       every identifier there rather than only the string literals hides
%       exactly one finding, parser.pl's seq/3, behind a Python local called
%       `seq` [measured 2026-08-18].
% Owns:
%     - edge/3 and reached/1 are scratch for one analysis and are cleared at
%       the start of each, because prolog_walk_code/1 reports through a side
%       effect rather than by answering, and the selftest runs the analysis a
%       second time over a fixture.
%     - the directive probe asserts one clause per directive and erases every
%       one of them before the walk's results are read.
% Decides:
%     - tests are neither definitions nor callers. tests/prolog/*.plt and
%       bindings/python/tests/*.py are excluded from both sides, so a predicate only a
%       test calls is REPORTED. That is the answer a dead-code lane owes: a
%       helper kept alive by its own test is dead product code, and the report
%       marks it `[tests]` rather than hiding it. Five of the 24 carry that mark
%       [measured 2026-08-18].
%     - reachable means reachable from a declared root, not merely called.
%       A call from a clause that is itself unreachable does not rescue its
%       callee, which is what stops a dead feature's own internals hiding
%       inside it.
% Open Obligations:
%     To Do: check.sh runs neither entry point yet, so nothing runs this on a
%         push. The two lines belong beside the other Prolog lanes:
%         a REPORT for reachability_report/0 and a GATE for
%         reachability_selftest/0, the second being the one that fails.
%     Hacks: None
%     Future Enhancements: None

:- use_module(library(prolog_codewalk)).
:- use_module(library(prolog_xref)).

:- dynamic edge/3.
:- dynamic reached/1.
:- dynamic analysed_extra_directory/1.
:- dynamic python_entry_scanned/0.
:- dynamic test_references_scanned/0.

%%%% What is analysed %%%%
%
% The five directories that ship Prolog. bindings/python/metta holds shim.pl, which is
% the Python library's own half of the engine and 2895 of the tree's 19423
% Prolog lines; leaving it out would leave the largest single file unchecked.
tree_directory_relative('../../engine').
tree_directory_relative('../../lib').
tree_directory_relative('../../backends').
tree_directory_relative('../../backends/mork/mork_ffi').
tree_directory_relative('../../bindings/python/metta').

% With the separator, so that a sibling named src_generated is not read as
% being inside src. The same rule surface_walk.pl states for the same reason.
directory_prefix(Relative, Directory) :-
    absolute_file_name(Relative, Absolute),
    atom_concat(Absolute, '/', Directory).

analysed_directory(Directory) :-
    (   tree_directory_relative(Relative)
    ;   analysed_extra_directory(Relative)
    ),
    directory_prefix(Relative, Directory).

in_analysed_tree(File) :-
    analysed_directory(Directory),
    sub_atom(File, 0, _, _, Directory), !.

% A predicate one of those files defines. `$`-prefixed names are SWI's own
% internals, and two of them ('$init_goal'/3 and '$load_context_module'/3) are
% attributed to any file carrying a directive, so they arrive here as though
% the tree had defined them.
tree_predicate(File, Module:Name/Arity) :-
    source_file(File),
    in_analysed_tree(File),
    source_file(Module:Head, File),
    functor(Head, Name, Arity),
    \+ sub_atom(Name, 0, _, _, $).

% The same set as a table keyed on the NAME, built once per analysis.
% record_constructions/1 asks "is there a predicate called this?" once per data
% subterm, and answering that by walking source_file/2 each time is 13.4 of the
% report's 14.1 seconds; with the index it is 0.9 [measured 2026-08-18].
:- dynamic tree_predicate_index/2.

index_tree_predicates :-
    retractall(tree_predicate_index(_, _)),
    findall(Predicate, tree_predicate(_, Predicate), Predicates0),
    sort(Predicates0, Predicates),
    forall(member(Module:Name/Arity, Predicates),
           assertz(tree_predicate_index(Name, Module:Name/Arity))).

tree_predicate(Predicate) :- tree_predicate_index(_, Predicate).

% Module-qualified throughout, unlike surface_walk.pl's indicator/2, which
% strips the module because its question is about one module. Here a clause of
% prolog:message//1 in bindings/python/metta/shim.pl and a user predicate of the same
% name are different nodes, and conflating them would rescue one through the
% other.
qualified(Module:Goal, Module:Name/Arity) :- !, plain(Goal, Name/Arity).
qualified(Goal, user:Name/Arity) :- plain(Goal, Name/Arity).

plain(Goal, Name/Arity) :-
    (   compound(Goal)
    ->  compound_name_arity(Goal, Name, Arity)     % f() is a compound of arity 0
    ;   atom(Goal)
    ->  Name = Goal, Arity = 0
    ).

%%%% The two kinds of edge %%%%

add_edge(Kind, From, To) :-
    ( edge(Kind, From, To) -> true ; assertz(edge(Kind, From, To)) ).

% A call. SWI's own walk finds it, including through control structure, a
% declared meta-argument and a meta-predicate it infers.
record_call(Callee, Caller, _Location) :-
    catch(qualified(Callee, CalleeIndicator), _, fail),
    caller_indicator(Caller, CallerIndicator),
    add_edge(call, CallerIndicator, CalleeIndicator).
record_call(_, _, _).

caller_indicator(Caller, Caller) :- Caller == '<initialization>', !.
caller_indicator(Caller, Indicator) :- catch(qualified(Caller, Indicator), _, fail).

% A construction. The translator and lib_memo.pl build a goal as a TERM and
% plant it in a clause they generate, so it stands in no goal position and no
% walk of call sites can see it:
%
%     lib/lib_memo/lib_memo.pl:125        Goal = cache_call(Fun, CallModule, Args, Out)
%     engine/duals.pl:340           Negation = metta_negation(Local, ..., Out)
%     engine/translator.pl:1026     foldall(agg_reduce(Acc, Value), ...)
%
% Only the ARGUMENTS of a goal are scanned, never the goal itself. Scanning
% every subterm of the body instead reads the `=@=/2` call at
% engine/translator.pl:73 as a construction of the tree's own '=@='/3 and hides it,
% which it did. '=@='/3 is defined beside '=alpha'/3 at engine/metta.pl:310 and,
% unlike it, was never registered, so !(=@= (f $x) (f $y)) answers the
% expression back where !(=alpha (f $x) (f $y)) answers true, and the report has
% to be able to say so [measured 2026-08-18].
%
% The arity is a lower bound because a term in an argument is as often a
% CLOSURE as a whole goal: agg_reduce/2 above is called by foldall/4 with two
% more arguments, and requiring an exact match reports the live agg_reduce/4.
record_constructions(References) :-
    forall(( member(Reference, References),
             catch(clause(Head, Body, Reference), _, fail),
             qualified(Head, From),
             clause_data(Head, Body, Data),
             compound_name_arity(Data, Name, Arity),
             Arity > 0,
             tree_predicate_index(Name, Module:Name/Total),
             Total >= Arity,
             To = Module:Name/Total,
             To \== From ),
           add_edge(construct, From, To)).

% Every term the clause HOLDS rather than calls. The head half is not about
% patterns and is not optional: SWI hoists a leading body unification into the
% head, so `builder(Goal) :- Goal = built(1, 2)` is STORED as
% `builder(built(1, 2)) :- true` and a body-only scan of it sees nothing at all
% [measured 2026-08-18 with clause/2 on both spellings].
clause_data(Head, _, Data) :-
    compound(Head), arg(_, Head, Argument), subterm(Argument, Data).
clause_data(_, Body, Data) :- body_data(Body, Data).

% Every term in a clause body that the body does NOT call: the arguments of
% each goal it does call, and their subterms. A goal itself is excluded because
% the walk already saw it, and including it reads the `=@=/2` call inside
% drop_fun_meta/3 as a construction of the tree's own '=@='/3 and hides it.
%
% Which argument holds a goal is read from the meta_predicate declaration
% rather than from a list of wrappers written here, which is what makes this
% cover once/1, forall/2, catch/3, findall/3 and setup_call_cleanup/3 without
% naming any of them. Reading the spec is not optional: '=@='/3 stayed hidden
% behind drop_fun_meta/3's once/1 at engine/translator.pl:71-73 until it did
% [measured 2026-08-18].
%
% A `1`..`9` argument is a CLOSURE rather than a goal, and is deliberately left
% as data: prolog_walk_code/1 already emits the call edge for a declared one,
% and for an undeclared caller like foldall/4 the closure is exactly what
% record_constructions/1 exists to catch.
body_data(Body, _) :- var(Body), !, fail.
body_data(Body, Data) :-
    goal_positions(Body, Positions),
    !,
    arg(Position, Body, Argument),
    (   memberchk(Position, Positions)
    ->  body_data(Argument, Data)
    ;   subterm(Argument, Data)
    ).
body_data(Goal, Data) :-
    compound(Goal),
    arg(_, Goal, Argument),
    subterm(Argument, Data).

goal_positions((_, _), [1, 2]).
goal_positions((_ ; _), [1, 2]).
goal_positions((_ -> _), [1, 2]).
goal_positions((_ *-> _), [1, 2]).
goal_positions(\+ _, [1]).
goal_positions(_ : _, [2]).
goal_positions(Body, Positions) :-
    compound(Body),
    catch(predicate_property(user:Body, meta_predicate(Spec)), _, fail),
    compound(Spec),
    findall(Position,
            ( arg(Position, Spec, Mode), Mode == 0 ),
            Positions),
    Positions \== [].

subterm(Term, Term) :- compound(Term).
subterm(Term, Subterm) :-
    compound(Term), arg(_, Term, Argument), subterm(Argument, Subterm).

%%%% What is walked %%%%

% Through the index, because tree_predicate/2 answers once per FILE and a
% predicate whose clauses come from two of them would otherwise have every
% clause walked twice.
%
% Filtered by the CLAUSE's own file, not the predicate's, because a multifile
% seam is shared: prolog:message//1 has clauses in bindings/python/metta/shim.pl and six
% more that arrive with library(prolog_xref), and walking those made the result
% depend on which libraries this file happens to import [measured 2026-08-18: 27
% clauses against 33]. A clause with no file is one something asserted at run
% time, and the assertz/1 site is in a tree file and is read as data there, so
% nothing is lost by leaving it out.
walked_clause(Reference) :-
    tree_predicate(Module:Name/Arity),
    functor(Head, Name, Arity),
    catch(nth_clause(Module:Head, _, Reference), _, fail),
    clause_property(Reference, file(File)),
    in_analysed_tree(File).

% A directive runs at load time and calls what it names, and prolog_walk_code/1
% walks clauses rather than directives: with the clauses/1 option it walks
% nothing else, and without it, it reaches only the goals registered through
% initialization/1,2 [source: library(prolog_codewalk), walk_from_initialization/1].
% So `:- maplist(register_builtin_fun, [...])` in engine/metta.pl, which is how
% every builtin name is declared, is invisible to it.
%
% Each directive becomes the body of one probe clause and is walked by the real
% walk, rather than being read by a second analysis written here. That is the
% same trick static_checks.pl's door_is_seen/1 uses, and for the same reason:
% the meta-predicate inference is the part worth having and is not worth
% reimplementing badly.
:- dynamic directive_probe/0.

directive_probe_clauses(References) :-
    retractall(directive_probe),
    findall(Reference,
            ( analysed_source_file(File),
              source_directive(File, Directive),
              assertz((directive_probe :- Directive), Reference) ),
            References).

analysed_source_file(File) :-
    analysed_directory(Directory),
    atom_concat(Directory, '*.pl', Pattern),
    expand_file_name(Pattern, Files),
    member(File, Files).

source_directive(File, Directive) :-
    setup_call_cleanup(prolog_open_source(File, Stream),
                       source_stream_directive(Stream, Directive),
                       prolog_close_source(Stream)).

source_stream_directive(Stream, Directive) :-
    repeat,
    prolog_read_source_term(Stream, Term, _, []),
    (   Term == end_of_file
    ->  !, fail
    ;   nonvar(Term), Term = (:- Directive)
    ).

build_graph :-
    retractall(edge(_, _, _)),
    index_tree_predicates,
    findall(Reference, walked_clause(Reference), ClauseReferences),
    directive_probe_clauses(DirectiveReferences),
    append(ClauseReferences, DirectiveReferences, References),
    prolog_walk_code([ clauses(References),
                       trace_reference(_),
                       on_edge(record_call),
                       source(false),
                       infer_meta_predicates(all),
                       autoload(false),
                       undefined(ignore) ]),
    % The same references, because a directive builds goals as freely as a
    % clause does: `:- prolog_listen(seam:atom_added/2,
    % seam:atom_hook_changed(added))` in engine/ext_points.pl:633 installs a
    % closure and stands in no clause at all.
    record_constructions(References),
    forall(member(Reference, DirectiveReferences), erase(Reference)).

%%%% The roots %%%%
%
% Every one is read as DATA rather than listed here, which is the only way a
% root set stays true as the tree moves. A list written by hand goes stale
% silently and every entry it should have gained becomes a false finding.
% A MeTTa call site. arity/2 is the table the translator consults to decide
% what (f a b) compiles to, so it is exactly the set of names MeTTa can call.
root_of(metta_dispatch, user:Name/Arity) :- arity(Name, Arity).

% A seam. multifile is the permission an extension or SWI itself needs to add
% clauses, so a multifile predicate is called from outside this tree by
% construction. This covers engine/ext_points.pl's declared seams and SWI's own
% hooks, prolog:message//1 and thread_message_hook/3 among them, in one rule.
root_of(seam, Module:Name/Arity) :-
    tree_predicate(Module:Name/Arity),
    functor(Head, Name, Arity),
    predicate_property(Module:Head, multifile).

% A load-time directive.
root_of(directive, Predicate) :- edge(call, user:directive_probe/0, Predicate).
root_of(directive, Predicate) :- edge(construct, user:directive_probe/0, Predicate).
root_of(directive, Predicate) :- edge(call, '<initialization>', Predicate).

% An entry point Python names across janus. The name is text there, so this
% reads the STRING LITERALS of the shipped library rather than its identifiers.
% Reading identifiers instead hides parser.pl's seq/3 behind a Python local
% called `seq`, and it is the difference between a rule about the boundary and a
% rule about any word that happens to appear [measured 2026-08-18: 24 findings
% against 23, the one lost being seq/3].
root_of(janus, user:Name/Arity) :-
    tree_predicate(user:Name/Arity),
    python_entry_name(Name).

%%%% Reachability %%%%

close_reachable :-
    retractall(reached(_)),
    forall(root_of(_, Predicate), mark(Predicate)).

mark(Predicate) :- reached(Predicate), !.
mark(Predicate) :-
    assertz(reached(Predicate)),
    forall(edge(_, Predicate, Next), mark(Next)).

unreachable(Unreachable) :-
    findall(Predicate, tree_predicate(Predicate), All0),
    sort(All0, All),
    findall(Predicate, ( member(Predicate, All), \+ reached(Predicate) ),
            Unreachable).

%%%% Reading the Python side %%%%
%
% A name in a string is not a call, and reading it as one over-approximates.
% The direction is deliberate: a burn-down list that cries wolf is abandoned
% and one that under-counts is merely incomplete.

python_entry_name(Name) :-
    ( python_entry_scanned -> true ; scan_python_entries ),
    python_entry_name_(Name).

:- dynamic python_entry_name_/1.

scan_python_entries :-
    assertz(python_entry_scanned),
    forall(( python_source_directory(Directory),
             atom_concat(Directory, '/*.py', Pattern),
             expand_file_name(Pattern, Files),
             member(File, Files),
             string_literal_name(File, Name),
             \+ python_entry_name_(Name) ),
           assertz(python_entry_name_(Name))).

python_source_directory('../../bindings/python/metta').
python_source_directory(Directory) :- analysed_extra_directory(Directory).

string_literal_name(File, Name) :-
    read_file_to_string(File, Text, []),
    string_codes(Text, Codes),
    python_string_codes(Codes, Literal),
    name_in(Literal, Name).

% Python's string literals, scanned left to right so that a quote inside a
% comment and a `#` inside a string each land on the right side. A prefix (r,
% f, b and their pairs) sits BEFORE the quote, so reaching the quote is enough
% and the prefix needs no case of its own.
python_string_codes([], _) :- !, fail.
python_string_codes([0'#|Rest], Literal) :- !,
    skip_to_newline(Rest, Tail), python_string_codes(Tail, Literal).
python_string_codes([Q, Q, Q|Rest], Literal) :-
    quote(Q), !,
    ( read_until_triple(Rest, Q, Content, Tail)
    -> ( Literal = Content ; python_string_codes(Tail, Literal) )
    ;  fail ).
python_string_codes([Q|Rest], Literal) :-
    quote(Q), !,
    ( read_until_quote(Rest, Q, Content, Tail)
    -> ( Literal = Content ; python_string_codes(Tail, Literal) )
    ;  fail ).
python_string_codes([_|Rest], Literal) :- python_string_codes(Rest, Literal).

quote(0'"). quote(0'').

skip_to_newline([], []).
skip_to_newline([0'\n|Rest], Rest) :- !.
skip_to_newline([_|Rest], Tail) :- skip_to_newline(Rest, Tail).

read_until_quote([0'\\, _|Rest], Q, Content, Tail) :- !,
    read_until_quote(Rest, Q, Content, Tail).
read_until_quote([Q|Rest], Q, [], Rest) :- !.
read_until_quote([0'\n|_], _, _, _) :- !, fail.       % an unterminated literal
read_until_quote([C|Rest], Q, [C|Content], Tail) :-
    read_until_quote(Rest, Q, Content, Tail).

read_until_triple([0'\\, _|Rest], Q, Content, Tail) :- !,
    read_until_triple(Rest, Q, Content, Tail).
read_until_triple([Q, Q, Q|Rest], Q, [], Rest) :- !.
read_until_triple([C|Rest], Q, [C|Content], Tail) :-
    read_until_triple(Rest, Q, Content, Tail).

% A Prolog or MeTTa name inside that text. The hyphen is an identifier
% character here and nowhere else: 'string-length' is one name in a goal string
% and `a-b` outside one is a subtraction.
name_in(Codes, Name) :-
    name_run(Codes, [], Names),
    member(Name, Names).

name_run([], Acc, Acc).
name_run([C|Rest], Acc, Names) :-
    (   code_type(C, csymf)
    ->  take_name(Rest, [C], Chars, Tail),
        atom_codes(Atom, Chars),
        name_run(Tail, [Atom|Acc], Names)
    ;   name_run(Rest, Acc, Names)
    ).

take_name([C|Rest], Sofar, Chars, Tail) :-
    ( code_type(C, csym) ; C == 0'- ), !,
    append(Sofar, [C], Next),
    take_name(Rest, Next, Chars, Tail).
take_name(Rest, Sofar, Sofar, Rest).

% Which reported predicates a test suite CALLS, which is triage rather than
% reachability: it separates "nothing calls this" from "only its own test does".
%
% The Prolog half is SWI's own source cross-referencer, which reads a file
% without loading it and resolves the call properly: it answers seq/3 for
% tests/prolog/suites/reader/parser.plt:101's `phrase(seq([1, 2, 3]), Codes)`, arity and all.
% A name scan of the same text was tried first and was wrong four times out of
% thirteen, marking call_site_type_chains/2, 'collapse-bind'/2,
% specializable_vars/4 and 'unify-mod'/5 on nothing but a mention in a comment
% [measured 2026-08-18: 43 files, 761 called indicators, 0.12s].
%
% The Python half is the same string-literal scan the janus root uses, pointed
% at bindings/python/tests, because a Python test names a Prolog goal as text exactly as
% the library does: bindings/python/tests/ch03_atoms_and_expressions/test_properties.py:70 is
% `rt.once("metta_py_swrite(W, Str)")`, which no Prolog reader will ever see.
named_by_a_test(Name/Arity) :-
    ( test_references_scanned -> true ; scan_test_references ),
    ( test_call(Name/Arity) -> true ; test_text_name(Name) ).

:- dynamic test_call/1.
:- dynamic test_text_name/1.

scan_test_references :-
    assertz(test_references_scanned),
    forall(prolog_test_source(File),
           xref_source(File, [silent(true), register_called(all)])),
    forall(( prolog_test_source(File),
             xref_called(File, Called, _),
             called_indicator(Called, Indicator),
             \+ test_call(Indicator) ),
           assertz(test_call(Indicator))),
    forall(( python_test_source(File),
             string_literal_name(File, Name),
             \+ test_text_name(Name) ),
           assertz(test_text_name(Name))).

called_indicator(Called, Name/Arity) :-
    nonvar(Called),
    ( Called = _:Plain -> true ; Plain = Called ),
    callable(Plain),
    functor(Plain, Name, Arity).

% This file is excluded from its own scan. It calls arity/2 and
% process_metta_string/2 to do the analysis, and marking a predicate `[tests]`
% because the analysis reads it would be the report talking about itself.
prolog_test_source(File) :-
    member(Pattern, ['../../tests/prolog/suites/*/*.plt',
                     '../../tests/prolog/*.pl', '../../tests/fixtures/*.pl']),
    expand_file_name(Pattern, Files),
    member(File, Files),
    \+ sub_atom(File, _, _, 0, 'reachability.pl').

python_test_source(File) :-
    expand_file_name('../../bindings/python/tests/*.py', Files),
    member(File, Files).

%%%% Loading the configuration that ships %%%%

analysed_library(Base) :-
    expand_file_name('../../lib/*/*.pl', Files),
    member(File, Files),
    file_base_name(File, Name),
    file_name_extension(Base, pl, Name).

library_imports(Base) :-
    format(atom(Form), "!(import! &self (library ~w))", [Base]),
    catch(process_metta_string(Form, _), _, fail).

library_companion(Base, Companion) :-
    atomic_list_concat(['../../lib/', Base, '.metta'], Companion).

% Each library's MeTTa-callable names are registered by its own .metta
% companion, through import_prolog_functions_from_file, so the import is what
% puts them in arity/2. A library with no companion cannot be imported at all,
% because 'import!' resolves a library name to a .metta file and nothing else
% [source: engine/metta.pl:3730, ensure_metta_ext/2], and its predicates are then
% genuinely unreachable rather than merely unseen. That is reported, not
% silently forgiven.
load_shipped_configuration(Unimported) :-
    % `backends` is what run.sh, the packaged CLI and the Python library all
    % pass, and it has to be set BEFORE the engine loads: engine/metta.pl:179 reads
    % argv to decide whether to glob backends/*.pl, and engine/metta.pl:4251 then
    % registers each backend's own builtin names in the SAME consult. Loading
    % the backends afterwards is too late for that directive, and it showed:
    % 'mm2-exec'/3 and 'mork-flush'/2 were reported dead while
    % backends/mork/mork_ffi/morkspaces.pl:257 declares both [measured 2026-08-18]. The
    % plunit lane appends the same flag for the same reason.
    set_prolog_flag(argv, [backends]),
    consult('../../engine/metta.pl'),
    metta_host_set_silent(true),
    findall(Base, ( analysed_library(Base), \+ library_imports(Base) ), Unimported),
    forall(( expand_file_name('../../lib/*/*.pl', Libraries), member(F, Libraries) ),
           ensure_loaded(F)),
    forall(( expand_file_name('../../backends/*.pl', Backends), member(F, Backends) ),
           ensure_loaded(F)),
    ensure_loaded('../../bindings/python/metta/shim.pl').

%%%% The report %%%%

reachability_report :-
    load_shipped_configuration(Unimported),
    build_graph,
    close_reachable,
    unreachable(Unreachable),
    print_counts,
    print_unimported(Unimported),
    print_unreachable(Unreachable),
    ( Unreachable == [] -> true ; halt(1) ).

print_counts :-
    findall(P, tree_predicate(P), Ps0), sort(Ps0, Ps), length(Ps, Predicates),
    aggregate_all(count, walked_clause(_), Clauses),
    aggregate_all(count, edge(call, _, _), Calls),
    aggregate_all(count, edge(construct, _, _), Constructions),
    findall(Class-Count,
            ( member(Class, [metta_dispatch, seam, directive, janus]),
              aggregate_all(count, distinct_root(Class, _), Count) ),
            Roots),
    format("reachability: ~d predicates in ~d clauses, ~d call and ~d \c
            construct edges~n", [Predicates, Clauses, Calls, Constructions]),
    format("  roots:"),
    forall(member(Class-Count, Roots), format(" ~d ~w", [Count, Class])),
    nl.

distinct_root(Class, Predicate) :-
    findall(P, root_of(Class, P), Ps0),
    sort(Ps0, Ps),
    member(Predicate, Ps).

% With the reason, because these entries EXPLAIN findings: minimal_metta_lib
% accounts for ten of the twenty-four on its own, and its companion is missing
% rather than its predicates being dead [measured 2026-08-18].
print_unimported([]).
print_unimported([First|Rest]) :-
    format("  these libraries could not be imported, so nothing registers \c
            their names:~n"),
    forall(member(Base, [First|Rest]),
           ( library_companion(Base, Companion),
             (   exists_file(Companion)
             ->  Why = 'the import failed'
             ;   Why = 'no .metta companion, and import! resolves a library \c
                        name to a .metta file and nothing else'
             ),
             format("    ~w~t~24| ~w~n", [Base, Why]) )).

print_unreachable([]) :-
    format("every predicate the tree defines is reachable from a declared \c
            root~n").
print_unreachable([First|Rest]) :-
    Unreachable = [First|Rest],
    length(Unreachable, Count),
    format("~d predicates are reachable from no root:~n", [Count]),
    forall(member(Predicate, Unreachable), print_one(Predicate)),
    format("each is a decision: delete it, or wire it to the root that was \c
            meant to reach it. A `[tests]` mark means a test calls it, so it \c
            is dead product code rather than dead code.~n").

print_one(Module:Name/Arity) :-
    predicate_site(Module:Name/Arity, Site),
    ( named_by_a_test(Name/Arity) -> Mark = ' [tests]' ; Mark = '' ),
    format("  ~w~t~46| ~q~w~n", [Site, Name/Arity, Mark]).

predicate_site(Module:Name/Arity, Site) :-
    functor(Head, Name, Arity),
    (   catch(nth_clause(Module:Head, 1, Reference), _, fail),
        clause_property(Reference, file(File)),
        clause_property(Reference, line_count(Line))
    ->  relative_site(File, Line, Site)
    ;   once(tree_predicate(File, Module:Name/Arity))
    ->  relative_site(File, 0, Site)
    ;   Site = '?'
    ).

relative_site(File, Line, Site) :-
    absolute_file_name('../..', Root),
    atom_concat(Root, '/', Prefix),
    ( atom_concat(Prefix, Relative, File) -> true ; Relative = File ),
    ( Line > 0 -> format(atom(Site), "~w:~d", [Relative, Line])
    ; Site = Relative ).

%%%% The selftest %%%%
%
% A report that finds nothing and a report that looks at nothing print the same
% line, and this one has a second way to be quietly useless: a root class that
% marks everything reachable reports nothing and looks clean. So a fixture is
% written to a temporary directory, added to the analysed set, and the analysis
% is run over it a second time. Nine predicates, one per door, and the check
% names WHICH door stopped firing rather than only that one did.
%
% The fixture is written rather than checked in for the reason
% tests/checks/check_evidence_selftest.py gives about its own: a deliberately dead
% predicate committed under engine/ would be a finding of the real report forever.

% One planted predicate per door, and three that must be REPORTED, because a
% probe in which everything is expected to survive cannot tell a working
% analysis from one that marks the whole tree reachable.
planted(defined,     'metta_reachability_planted_dead'/1,          reported).
planted(dispatch,    'metta_reachability_planted_live'/1,          reachable).
planted(call_edge,   'metta_reachability_planted_called'/0,        reachable).
planted(seam,        'metta_reachability_planted_hook'/1,          reachable).
planted(construct,   'metta_reachability_planted_built'/2,         reachable).
planted(directive,   'metta_reachability_planted_directed'/1,      reachable).
planted(janus,       'metta_reachability_planted_from_python'/1,   reachable).
% The Python scan reads string LITERALS, so a name that appears only in a
% comment must not rescue anything. Without this the janus door passes just as
% well when the scanner degenerates to reading every identifier, which is the
% reading that rescued minimal_metta_lib.pl's function/2 on a Python local.
planted(python_text, 'metta_reachability_planted_commented'/1,     reported).
% A goal in goal position is a call and not a construction, so a lookalike at a
% HIGHER arity must still be reported. This is the '=@=' shape: '=@='/2 is
% called inside drop_fun_meta/3's once/1 at engine/translator.pl:71-73 and the
% tree's own '=@='/3 is not, and reading that argument as data hides it.
planted(goal_position, 'metta_reachability_planted_goal'/3,        reported).

fixture_source("
:- multifile 'metta_reachability_planted_hook'/1.

metta_reachability_planted_dead(_).
metta_reachability_planted_commented(_).
metta_reachability_planted_goal(_, _, _).

metta_reachability_planted_live(X) :- metta_reachability_planted_called, X = 1.
metta_reachability_planted_called.

metta_reachability_planted_hook(_) :-
    metta_reachability_planted_builder(_),
    once(metta_reachability_planted_goal(1, 2)).
metta_reachability_planted_builder(Goal) :-
    Goal = metta_reachability_planted_built(1, 2).
metta_reachability_planted_built(_, _).
metta_reachability_planted_goal(_, _).

metta_reachability_planted_directed(_).
:- ignore(metta_reachability_planted_directed(1)).

metta_reachability_planted_from_python(_).
").

fixture_python("# metta_reachability_planted_commented is named in a COMMENT only
GOAL = \"metta_reachability_planted_from_python(X)\"
").

reachability_selftest :-
    load_shipped_configuration(_),
    setup_call_cleanup(plant_fixture(Directory),
                       run_selftest,
                       remove_fixture(Directory)).

fixture_file(Directory, Name, Path) :-
    atomic_list_concat([Directory, '/', Name], Path).

plant_fixture(Directory) :-
    tmp_file_stream(text, Scratch, Stream), close(Stream), delete_file(Scratch),
    atom_concat(Scratch, '_reachability', Directory),
    make_directory(Directory),
    forall(member(Name-Content,
                  ['planted.pl'-fixture_source, 'planted.py'-fixture_python]),
           ( fixture_file(Directory, Name, Path),
             Read =.. [Content, Text],
             call(Read),
             setup_call_cleanup(open(Path, write, Out), write(Out, Text),
                                close(Out)) )),
    assertz(analysed_extra_directory(Directory)),
    % The scans are cached, and the fixture arrives after the real report has
    % run one of them in the same process.
    retractall(python_entry_scanned),
    retractall(python_entry_name_(_)),
    fixture_file(Directory, 'planted.pl', Source),
    consult(Source),
    % metta_reachability_planted_live/1 stands for a name MeTTa can call, and
    % arity/2 is how the engine says so.
    assertz(arity('metta_reachability_planted_live', 1)).

remove_fixture(Directory) :-
    retractall(analysed_extra_directory(_)),
    retractall(arity('metta_reachability_planted_live', 1)),
    retractall(python_entry_scanned),
    retractall(python_entry_name_(_)),
    forall(member(Name/Arity,
                  ['metta_reachability_planted_dead'/1,
                   'metta_reachability_planted_commented'/1,
                   'metta_reachability_planted_live'/1,
                   'metta_reachability_planted_called'/0,
                   'metta_reachability_planted_builder'/1,
                   'metta_reachability_planted_built'/2,
                   'metta_reachability_planted_hook'/1,
                   'metta_reachability_planted_goal'/2,
                   'metta_reachability_planted_goal'/3,
                   'metta_reachability_planted_directed'/1,
                   'metta_reachability_planted_from_python'/1]),
           ( functor(Head, Name, Arity),
             ( predicate_property(user:Head, dynamic) -> retractall(user:Head)
             ; true ),
             catch(abolish(user:Name/Arity), _, true) )),
    forall(member(Name, ['planted.pl', 'planted.py']),
           ( fixture_file(Directory, Name, Path),
             ( exists_file(Path) -> delete_file(Path) ; true ) )),
    ( exists_directory(Directory) -> delete_directory(Directory) ; true ).

run_selftest :-
    build_graph,
    close_reachable,
    unreachable(Unreachable),
    findall(Door,
            ( planted(Door, Name/Arity, Expectation),
              \+ planted_as_expected(Expectation, Name/Arity, Unreachable) ),
            Wrong),
    aggregate_all(count, planted(_, _, _), Total),
    (   Wrong == []
    ->  length(Unreachable, Count),
        format("reachability selftest: each of ~d planted predicates landed on \c
                the side its door predicts, with ~d reported overall~n",
               [Total, Count])
    ;   forall(member(Door, Wrong),
               ( planted(Door, Indicator, Expectation),
                 format(user_error,
                        'the ~w door is broken: ~q was expected to be ~w and \c
                         is not~n', [Door, Indicator, Expectation]) )),
        format(user_error,
               'the reachability report cannot be trusted while that holds, \c
                because a door that no longer fires reports a live predicate \c
                dead or hides a dead one~n', []),
        halt(1)
    ).

planted_as_expected(reported, Name/Arity, Unreachable) :-
    memberchk(user:Name/Arity, Unreachable).
planted_as_expected(reachable, Name/Arity, Unreachable) :-
    \+ memberchk(user:Name/Arity, Unreachable),
    reached(user:Name/Arity).
