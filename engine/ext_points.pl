% Purpose: declare each engine extension seam, its direction and its cut
%   semantics, and publish the predicates extensions and host bindings may call.
% Guarantees:
%   - reader-token registration is an engine-owned host service, while token
%     construction is claimed by the host that owns the registered callable;
%     mapping introspection is an ordinary extension service [tested:
%     test_a_registered_token_class_parses_like_a_shipped_one,
%     every_seam_declares_one_kind,
%     every_seam_kind_matches_its_direction; commit=2c741dda928a30d0ce1c7e1fcf0b263b4d1bb97b].
%   - every handler seam lives in THIS module, so an extension writes
%     seam:atom_added/2 and the module carries the namespace the metta_on_
%     prefix used to carry [tested: test_every_seam_is_reached_under_its_module;
%     commit=dd407a40f623b16eda0bb51a74458f7dd3760e21].
%   - automatic-cache graph, source-boundary, policy, explanation and support
%     seams each declare their event/declaration/service direction explicitly
%     [tested: every_seam_kind_matches_its_direction,
%     test_a_doubly_branching_recursion_is_tabled_automatically_and_a_tail_recursion_is_not;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The module IS the namespace, which is why the names below are short. Every
%handler seam used to wear a prefix that did a module's job: metta_on_ for the
%events, metta_foreign_ for the space-provider protocol, metta_grounded_ for
%the grounded-value protocol, metta_host_ for the host's. The prefix was the
%only namespace there was, and being a convention it could not refuse
%anything: two libraries could declare the same seam name and corrupt each
%other by import order, and nothing said which module a handler belonged to.
%
%Now an extension writes
%
%    :- multifile seam:atom_added/2.
%    seam:atom_added(Space, Atom) :- ...
%
%which is SWI's own hook shape, the one prolog:message//1 has always used
%[source: SWI-Prolog 10.1 Reference Manual, section 4.10 and library(error)'s
%error:has_type/2]. The old spellings are GONE rather than aliased: an alias
%tier would be a second name for one thing, which the tree's ladder refuses,
%and compatibility against our own Prolog surface is not a constraint.
%
%Nothing here is imported into the engine's module. engine/metta.pl loads this
%file with an empty import list, so `seam:` is not optional and cannot decay
%back into a bare name that happens to resolve. The export list below is
%therefore the DECLARED surface rather than what anyone can reach, which is
%what the layering lane and the published-surface walk both ask for.
:- module(seam,
          [ % The extension-point table itself, and what it decides.
            kind/2,
            clauses_from/2,
            every_clause_runs/1,
            publish/1,
            publish_declared/0,
            seam_home/2,

            % Events: the engine tells, every handler runs.
            atom_added/2,
            atom_removed/2,
            cache_policy_changed/1,
            function_call_graph_changed/2,
            function_changed/1,
            function_clauses_changed/1,
            function_removed/1,
            source_program_compiled/0,
            backend_selftest/0,

            % The atom-write wrappers those events ride on.
            enable_atom_hook/1,
            disable_atom_hook/1,
            atom_hook_clause/2,
            atom_hook_changed/3,
            sync_atom_hook/1,
            write_door_module/2,

            % Declarations: fact tables the engine reads as data.
            backend_builtin/1,
            builtin_type_declaration/2,
            context_events/3,
            engine_emitted/1,
            foreign_capability/2,
            grounded_extra_type/2,
            host_builtin/1,
            automatic_cache_explanation/3,
            pure_operation/1,
            route_cap/4,

            % Ownership: the first handler that succeeds claims the request.
            custom_match/2,
            dispatch_call/4,
            effect_operation_name/3,
            form_rewriter/1,
            matchable_value/1,
            pattern_modifier/3,

            % The foreign-space provider protocol.
            foreign_add/2,
            foreign_add_many/2,
            foreign_atoms/2,
            foreign_begin/1,
            foreign_clear/1,
            foreign_commit/1,
            foreign_erring/5,
            foreign_match/3,
            foreign_plan/5,
            foreign_pushdown/3,
            foreign_refuse/2,
            foreign_remove/3,
            foreign_rollback/1,
            foreign_space/1,

            % The grounded-value protocol.
            grounded_applicable/1,
            grounded_apply/3,
            grounded_class_type/2,
            grounded_numeric/1,
            grounded_numeric_operation/3,
            grounded_structure/2,
            grounded_text/2,
            grounded_type_names/2,

            % The host protocol's handler half; its service half is the
            % engine's own predicates, reached under the subsystem that
            % defines them.
            host_add_hooks_idle/2,
            host_import/1,
            host_object/1,
            host_reader_token_construct/3,
            host_remove_hooks_idle/2
          ]).

%%%% What kind of seam each extension point is %%%%
%
%Every seam below is declared multifile and then given a KIND on the line
%after it. The kind is the load-bearing fact about a seam, because a cut means
%opposite things in the three of them, and it lived in this comment until a
%checker had to restate it by hand. A restated list drifts, and this one had:
%the prose named five event hooks, omitting backend_selftest/0 and
%wrongly including dispatch_call/4, and both were contradicted by their
%own call sites. So it is data now, and the prose derives from it.
%
%EVENT: run for an effect and the answer discarded, forall(Hook, true). Every
%handler runs.
%
%OWNERSHIP: consulted for an answer, and the first handler that succeeds
%CLAIMS the request; the caller takes it with ->/2 or once/1, and a provider
%declines by failing.
%
%DECLARATION: a fact table the engine reads as data rather than calls for an
%effect. Every clause has to stay readable for the same reason an event
%handler has to stay reachable.
%
%SERVICE: the other direction. The three kinds above are all HANDLER seams,
%where an extension writes the clauses and the engine calls them; a service is
%a predicate the ENGINE defines and an extension is allowed to CALL. A foreign
%space backend needs one: it speaks text over a wire, so it has to turn a term
%into text and back, and before this kind existed it reached into
%engine/parser.pl to do it. SQLite publishes the same half of its own contract
%and for the same reason, handing an extension an sqlite3_api_routines table
%of the host functions it may call so that an extension never links against
%internals [source: https://www.sqlite.org/vtab.html and loadext.html]. Naming
%the surface is what makes "reaches past the seam" a question a checker can
%answer, and two extensions had already answered it wrongly: morkspaces.pl and
%bindings/python/metta/shim.pl each wrapped metta_unwritable_symbol/2 under a private
%name of its own, which is what an undeclared dependency looks like from the
%outside [measured 2026-08-17].
%
%The cut rule follows from the kind rather than being a second list to keep.
%In an OWNERSHIP seam a clause guarded by a test that establishes "this
%request is mine" may cut freely, and lib/lib_redis.pl does:
%redis_space_conn(Space, _) fails for a space redis does not own, so a later
%provider's clauses are untouched, and the cut is a real optimisation there.
%In an EVENT or DECLARATION seam every clause must stay reachable, so a cut
%prunes that predicate's remaining clauses and silently disables every handler
%loaded after it. lib/lib_tabling.pl cut after metta_tabling_declared, a
%GLOBAL CONDITION rather than an ownership test: nothing about it says this
%handler is the one that should answer. With tabling declared, duals.pl's
%invalidation handler (asserted last, so ordered last) never ran and
%(not-provable (pq 2)) answered True and False at once.
%
%Write ( Condition -> Action ; true ) in an event handler, which keeps the
%guard's cost and prunes nothing. A cut is transparent through ,/2, ;/2 and
%the THEN branch of ->/2 and *->/2, and opaque everywhere else, including the
%CONDITION of ->/2, where the manual's own worked example is
%`t3 :- (a, !, b -> c ; d)` pruning a/0 and not t3/0
%[source: SWI-Prolog manual, !/0, scope-of-the-cut table]. So a checker that
%flags a cut in a condition is flagging correct code.
%
%Two checks enforce it and neither subsumes the other. A source scan reads
%every clause in the tree, including one a directive asserts, and a runtime
%scan reads clause/3 after the libraries have loaded, which is the only way to
%see a handler that Python installs or one whose body is built at run time
%[tested: tests/prolog/static_checks.pl, no_cut_in_an_event_hook and
%no_cut_in_a_live_hook_clause].
%
%kind/2 is itself multifile, so a library that introduces a seam of
%its own declares its kind beside it and gets the same gate. Every seam has
%exactly one kind and that is checked rather than trusted
%[tested: every_seam_declares_one_kind], so a seam added without one fails the
%gate instead of going quietly unchecked.
:- multifile kind/2.
%It is a seam itself, so it carries its own kind, and being a declaration it
%is covered by the cut check like any other.
kind(kind/2, declaration).

%The names the engine writes into compiled bodies and therefore binds into
%every space's module. Declared here because it is a seam in both directions:
%an extension that teaches the engine to emit a goal of its own names it, and
%the engine reads the whole table when it protects a space's module. Its
%clauses live in engine/translator.pl, beside the translation rules that emit
%them.
:- multifile engine_emitted/1.
kind(engine_emitted/1, declaration).

%Libraries contribute builtin arrows without replacing the engine's table.
%It is a declaration seam, so every contributed clause remains reachable
%[tested: test_a_library_types_its_own_blob_without_destroying_the_table;
%commit=65d5fff90323fb92e2415f9fe93c477d5c67f10e].
:- multifile builtin_type_declaration/2.
kind(builtin_type_declaration/2, declaration).

%Pattern modifiers are expression lists claimed by shape. The engine replaces
%the modifier position with a fresh variable and runs the owner's guard after
%matching, so an extension can add a structural view without teaching the
%store a new term kind. The lifting walk is a host service because a binding
%that constructs patterns must apply the same semantics as compiled match.
%[tested: test_a_path_reaches_into_a_handle_without_converting_it;
%commit=b54ecaaa1224eabb90f808275003cd9abeef8065].
:- multifile pattern_modifier/3.
kind(pattern_modifier/3, ownership).

%Who writes a seam's clauses. This is the primitive the cut rule derives from,
%rather than the cut rule naming kinds directly: that rule is about a handler
%an extension contributed staying reachable, so it can only bite where an
%extension contributes the clauses. A service's clauses are the engine's own
%and cut freely, as swrite/2 does; reading the rule off the kind list alone
%would have called every one of them an offender.
clauses_from(event,       extension).
clauses_from(ownership,   extension).
clauses_from(declaration, extension).
clauses_from(service,     engine).
clauses_from(host_service, engine).

%A seam whose clauses must all stay reachable: contributed by an extension,
%and not an ownership seam where the first success is meant to claim the
%request. Derived, so adding a kind does not mean editing a second list.
every_clause_runs(Seam) :-
    kind(Seam, Kind),
    clauses_from(Kind, extension),
    Kind \== ownership.

%A handler seam is multifile because an extension adds clauses to it. A
%service is not, because an extension calling it must not be able to redefine
%it, and multifile is exactly the permission to try. The two directions are
%checked apart for that reason [tested: every_seam_kind_matches_its_direction].

%CALL DISPATCH: a handler is offered every compiled call site and either
%CLAIMS it, by binding Goal to something the engine runs instead, or fails and
%the ordinary call proceeds. Failing is the shipped default and the whole of
%what a handler must do to opt out.
%
%It was named metta_memoized_dispatch_call/4, for the first library that used
%it, and the name was the problem: nothing suggested it was the general
%dispatch seam, so nothing reached for it to do anything else. lib_memo binds
%Goal to a cache lookup, and it is still the only handler in the tree. This is
%Trino's applyX / Optional.empty() shape, and it was here before that reading.
%
%A function name alone does not identify a function, because a named space
%compiles its equations into a module of its own, so a handler that keeps
%state per function reads current_metta_module/1 to learn which module the
%call site is in. It reads it rather than being passed it because this hook is
%consulted on every compiled call site.
:- multifile dispatch_call/4.
kind(dispatch_call/4, ownership).
%Function-change hooks, run once per compiled equation. Dynamic for the same
%reason the atom hooks below are: a handler needed only once a feature is used
%should cost nothing until then, so it is installed when that feature first
%runs rather than when its file loads. A resident handler clause costs four
%inferences on EVERY compiled equation [measured 2026-08-15: engine/duals.pl's
%invalidation handler, 4001 on source-load's thousand equations].
:- multifile function_changed/1.
kind(function_changed/1, event).
%The compiled half of the change story, run once per compiled equation AFTER
%its clause and provenance are in place. function_changed above is the
%DEFINITION event: it fires when an equation arrives whether or not the engine
%has translated it yet, which under deferred translation can be well before
%any clause exists. A handler that acts on the compiled predicate, wrapping it
%the way the tracer does, listens here instead, because at definition time
%there may be nothing to wrap and at materialisation time nothing else fires.
:- multifile function_clauses_changed/1.
kind(function_clauses_changed/1, event).
:- multifile function_call_graph_changed/2.
kind(function_call_graph_changed/2, event).
:- multifile function_removed/1.
kind(function_removed/1, event).
:- multifile cache_policy_changed/1.
kind(cache_policy_changed/1, event).
:- multifile source_program_compiled/0.
kind(source_program_compiled/0, event).
:- dynamic function_changed/1.
:- dynamic function_clauses_changed/1.
:- dynamic function_call_graph_changed/2.
:- dynamic function_removed/1.
:- dynamic cache_policy_changed/1.
:- dynamic source_program_compiled/0.

%Automatic caching decisions are extension-owned declarations. The core's
%explain door enumerates them, while lib_memo owns the state and reasons.
:- multifile automatic_cache_explanation/3.
kind(automatic_cache_explanation/3, declaration).

%Space writes: every 'add-atom'/3 and 'remove-atom'/3 runs these hooks with
%the space and the term, after the write. A standing query, a subscription,
%an index or a mirror hangs off them; with no handlers nothing changes.
%A removal hook fires only when something was actually removed, and it carries
%the term the caller ASKED to remove rather than the occurrence that left. The
%two coincide for a ground request and diverge for a pattern: removal is
%multiset subtraction, so (remove-atom &s (p $x)) takes one of the atoms
%matching (p $x) and the hook cannot say which. A handler that needs the
%occurrence re-reads the space; bindings/python/metta/structures.py's LiveView is the
%worked instance [tested: test_liveview_mirrors_the_space].
:- multifile atom_added/2.
kind(atom_added/2, event).
:- multifile atom_removed/2.
kind(atom_removed/2, event).
:- dynamic atom_added/2.
:- dynamic atom_removed/2.

%Foreign spaces: a host runtime may declare a space whose atoms live outside
%the Prolog database, in a database, a dataframe, a service. match/4,
%'add-atom'/3, 'remove-atom'/3 and 'get-atoms'/2 consult these hooks first
%for a declared name; with no declarations nothing changes.
:- multifile foreign_space/1.
kind(foreign_space/1, ownership).
:- multifile foreign_match/3.
%A declared error mode's stream: like foreign_match/3, with the
%mode enforced on the provider's own host, where its exceptions are
%native. Item is `answer` (the pattern is bound), kept(ErrorAtom), or
%`end` from an adapter that must mark exhaustion. Only adapters whose
%host exceptions cannot cross as Prolog exceptions implement this; a
%Prolog-hosted provider needs none, the engine's catch handles it.
:- multifile foreign_erring/5.
%Transactional participation, driven by (writes Ctx transactional): one
%begin at the provider's first write inside the outermost transaction,
%then exactly one commit or rollback when it finishes.
:- multifile foreign_begin/1.
:- multifile foreign_commit/1.
:- multifile foreign_rollback/1.
kind(foreign_match/3, ownership).
kind(foreign_erring/5, ownership).
kind(foreign_begin/1, ownership).
kind(foreign_commit/1, ownership).
kind(foreign_rollback/1, ownership).
%Custom matching for grounded values, Hyperon's CustomMatch: a host value
%may carry its own matching logic, consulted by petta_match_atoms/2 when
%that value meets a non-variable operand inside `unify`. The hook
%enumerates one solution per binding set, binding the other operand's
%variables; failure means no match. Variables always bind the value
%whole without consulting it, and values with no owner fall through to
%ground equality, so with no declarations nothing changes.
:- multifile matchable_value/1.
:- multifile custom_match/2.
kind(matchable_value/1, ownership).
kind(custom_match/2, ownership).
:- multifile foreign_add/2.
kind(foreign_add/2, ownership).
%A provider's own BATCH crossing, optional. The atoms arrive as a list and the
%provider stores them however it likes; one without this clause gets a
%foreign_add/2 per atom, which is what every provider written before it
%gets. The hooks are the provider's, exactly as they are for its per-atom add.
%
%A batch is a TRANSPORT optimisation and never a semantic one, so the engine
%routes only atoms whose add is a store and nothing more through here. That is
%not advice to the provider, it is enforced upstream: an equation or a type
%declaration in the list drops the whole batch to 'add-atom'/3 per atom.
:- multifile foreign_add_many/2.
kind(foreign_add_many/2, ownership).
:- multifile foreign_remove/3.
kind(foreign_remove/3, ownership).
:- multifile foreign_atoms/2.
kind(foreign_atoms/2, ownership).
%Clear was the sixth of these all along and was declared nowhere: it lived in
%bindings/python/metta/shim.pl, so a Prolog provider that implemented clear, as
%lib/lib_redis.pl does, was reachable only when Python was in the process.
:- multifile foreign_clear/1.
kind(foreign_clear/1, ownership).

%What the caller will do with a match. Options is a list; the only option
%today is limit(N), meaning the caller stops after N answers. It is `[]` when
%there is nothing to say, which is most calls.
%
%It is ADVISORY, and that is what makes it sound. A provider may
%over-approximate, so N candidates are not N answers, and a provider that
%truncated at N without knowing which of its candidates unify would
%under-answer, which is the one thing the contract forbids. So honour it only
%when you can tell an exact match from a candidate, and ignore it otherwise:
%the engine bounds the answers itself either way, and this changes only how
%much work the BACKEND does before the first one.
%
%Two levers a reader might expect here are already in place and need no
%option. The bound parts of a pattern reach a provider as ground atoms,
%including the bindings an enclosing join has made, so the second pattern of
%a join arrives as (other a0 $_) rather than (other $_ $_). And the engine
%stops pulling as soon as it has enough: a limit of 3 over a provider holding
%a thousand atoms pulls four [measured 2026-08-16].
%
%ONE hook, with the options always passed. There was a /2 beside this and the
%engine chose between them with `clause(foreign_match(_,_,_), _)`, which
%asks whether ANY provider anywhere declared the bounded form. The Python shim
%declares it unconditionally, so with Python in the process that guard was true
%for every space, and a Prolog-only provider writing /2 had the /3 form called
%instead: the shim's clause failed on its own ownership check and the whole
%match answered nothing. Reproduced as `unbounded: 3, bounded: 0`
%[measured 2026-08-16]. A provider that has nothing to do with the options
%ignores the argument, which costs it one underscore and cannot go wrong.

%How much a provider's own filtering is worth, per PATTERN. Class is exact or
%inexact, and a space with no clause is inexact, which is the answer every
%provider written before this gets for free.
%
%  exact    every candidate you yield for this pattern unifies with it, so N
%           candidates are N answers and limit(N) is a requirement you may
%           truncate to
%  inexact  you reduce what you produce, and some of it may not match; the
%           engine re-unifies and limit(N) stays advice you must not truncate to
%
%This is Apache DataFusion's TableProviderFilterPushDown, whose Exact rung
%says it in the same words: "Your source guarantees that no output rows will
%have a false value for this predicate. Because the filter is fully evaluated
%at the source, DataFusion will not add a FilterExec for it", against Inexact,
%"Your source has the ability to reduce the data produced, but the output may
%still include rows that do not satisfy the predicate"
%[source: Apache DataFusion, Custom Table Providers].
%
%PER PATTERN, not per provider, which is the part worth copying. A backend is
%usually exact on equality against an indexed column and inexact on everything
%else, and one flag for the whole provider would force it to claim the weaker
%answer everywhere. The clause takes the pattern, so it can say which is which.
%
%DataFusion's third rung, Unsupported, is deliberately absent. It exists there
%because the planner decides whether to SEND a filter at all; here the pattern
%is the only thing a provider is given, so there is nothing to withhold, and a
%provider that ignores it is inexact in the only sense the engine acts on.
%
%What the engine does with exact: it stops pulling at N instead of at N+1,
%since it no longer needs the extra candidate to learn the bound is met. What
%it does NOT do is skip unification, which is not a filter here but the step
%that binds the pattern's variables, so an exact claim cannot make an answer
%wrong. It can only make a wrong claim cost answers, which is why
%check_space_provider tests it against the provider's own output
%[tested: a_bounded_match_carries_its_options,
%a_bound_is_withheld_from_an_unclaimed_pattern,
%test_a_false_exact_claim_is_caught].
:- multifile foreign_pushdown/3.
kind(foreign_pushdown/3, ownership).

%The routing voice of a third-party declaration kind. Consulted after the
%declared fidelity or the provider's own method proposes a route class,
%and every loaded advisor may only DEMOTE: the effective class is the most
%conservative voice, refuse below inexact below exact, so advisors compose
%order-independently and none can widen a claim its author never made.
%route_cap(Space, Pattern, Cap, Why): Cap is exact (no objection),
%inexact (candidates must be re-unified, the pushdown of the caller's
%bound is withheld) or refuse (this route must not serve now, loud at the
%match and naming Why). An advisor typically reads its own kind's atoms
%from '&petta', often through petta_shape_route/5, which is what lets a
%freshness or cost kind change routing with no kernel edit
%[tested: a_route_cap_demotes_and_refuses_through_the_published_seam].
%Declared metadata steering the router is the oldest optimizer discipline
%there is: semantic query optimization transforms evaluation by declared
%integrity constraints [source: Chakravarthy, Grant and Minker, ACM TODS
%1990], and a FRESHNESS vocabulary gating routes runs in production as
%Oracle's QUERY_REWRITE_INTEGRITY, whose stale_tolerated mode alone lets
%a stale materialized view keep serving rewrites [source:
%https://docs.oracle.com/en/database/oracle/oracle-database/23/dwhsg/basic-query-rewrite-materialized-views.html].
:- multifile route_cap/4.
:- dynamic route_cap/4.
kind(route_cap/4, declaration).

%A conjunction, offered WHOLE before the engine splits it. Succeed to claim
%some of it, binding Goal to a goal that enumerates bindings for Claimed; fail
%to decline, and the engine plans it exactly as it does today.
%
%   foreign_plan(Space, Patterns, Claimed, Rest, Goal)
%
%This is the seam that makes a backend's own join reachable. Without it every
%conjunction is split one pattern at a time and re-dispatched per outer row,
%which is a nested-loop plan, and a nested-loop plan cannot reach the AGM bound
%however fast the provider is: for the triangle R(x,y), S(y,z), T(z,x) with each
%relation of size N the bound is N^1.5 and "it is not possible to achieve a
%running time of O(N^3/2) using only join plans" [source: Ngo/Re/Rudra and the
%worst-case-optimal join literature]. So this is not a tuning knob; it is the
%difference between a provider being allowed to be asymptotically better and
%not being allowed to.
%
%Four properties, each with a precedent elsewhere in this file:
%
%  - DECLINING IS THE DEFAULT. A provider with no clause gets today's behaviour
%    exactly, the same safe default the capability vocabulary has.
%  - A PARTIAL CLAIM IS LEGAL. Claimed plus Rest lets a backend take the two
%    patterns it owns and leave the third, so the seam is not all-or-nothing.
%    They must PARTITION Patterns: dropping a conjunct answers more rows than
%    the query asks for and the engine refuses it, because nothing downstream
%    would catch it.
%  - THE STRATEGY IS INVISIBLE. Leapfrog, a hash join, a SQL SELECT, a vector
%    index: the engine sees a goal. It supports none of them and therefore all.
%  - THE CLAIM IS EXACT, and this one is the exception to the seam's usual rule.
%    Elsewhere a provider may over-approximate because the engine re-unifies
%    each candidate, which is cheap. There is no cheap re-check for a join: the
%    only way to verify a row is to run the join. So claiming means answering
%    exactly, a provider that cannot must decline, and check_space_provider
%    verifies the claim against the engine's own split rather than trusting it.
%
%The caller's options are not passed. The engine still bounds the answers, so
%this costs work in the backend and never an answer, and a limit could not be
%honoured usefully anyway while a provider answers a whole batch at a time.
:- multifile foreign_plan/5.
kind(foreign_plan/5, ownership).

%What a provider answers. Failure alone cannot say: foreign_match/3 is a
%legitimate enumerator, so "no clause" and "no atoms match" look identical
%from the engine, and clause/2 cannot stand in either, because every provider
%in this tree writes ONE clause with a variable space and an ownership guard
%in the body, which unifies with any space at all.
%
%So it is declared, the way bindings/python/metta/foreign.py derives it from the narrow
%protocols a provider implements. The capabilities are add, remove, match,
%enumerate, clear, PLAN and RULES.
%
%`rules` is the odd one and it is the one that matters most. It says the
%space's atoms include EQUATIONS, which in MeTTa is the difference between a
%data source and a place a program lives. The provider stores one the way it
%stores any atom and the ENGINE compiles it, so a foreign rule is the same
%compiled clause a native one is; nothing in the provider knows what an
%equation is. A space without the declaration is refused an equation at
%add-atom rather than storing one that can never fire. A space that declares
%NOTHING is taken to provide everything, which is what every provider written
%before this assumed.
%
%Two things follow from a declaration, and the first is the one that matters:
%a space that enumerates but does not match now has its enumeration FILTERED
%here for a bound pattern, instead of answering nothing. The Python half has
%always said enumeration is enough ("An Enumerable provider need not implement
%Matcher"), and the Prolog half quietly required both. The second is that an
%operation a space does not provide raises with the space and the operation
%named, rather than failing into "there is nothing there".
:- multifile foreign_capability/2.
kind(foreign_capability/2, declaration).

%What a context's change events promise, for a provider that owns a FAMILY
%of space names rather than one name it could write an atom about.
%
%   context_events(Space, Delivery, Order)
%
%Delivery is at-most-once, at-least-once or per-write-exactly and Order is
%ordered or unordered, the catalog's own `delivery` and `event-order`
%vocabularies. The per-space door is the ordinary declaration atom,
%(events <ctx> <delivery> <order>) in '&petta', which is what
%Space.events(delivery, order) and a Python provider's registration write; this is
%the same answer for a provider like MORK, whose spaces are every name
%beginning &mork, so there is no one name to write the atom about. The two
%doors are read by one question, petta_event_capability/3, exactly as a
%Prolog provider's foreign_capability/2 clauses and the Python
%bridge's registered facts are read by one foreign_provides/2.
%
%Declaring nothing means no events, which is the safe answer and the one
%every provider written before this gets: a subscription on the space is
%refused naming the missing capability rather than served and silently
%missing writes [P12.14].
:- multifile context_events/3.
kind(context_events/3, declaration).

%Why a space says no, in the provider's own words. The engine refuses a
%capability a space does not declare, and "does not implement add" reads
%differently from "declines this add request"; a provider with a reason raises
%it here and the engine's generic permission_error is what a provider without
%one gets. It is expected to THROW rather than answer
%[tested: test_a_provider_states_its_own_refusal].
:- multifile foreign_refuse/2.
kind(foreign_refuse/2, ownership).

%An exception that must never be recovered from. A caught abort, limit, alarm
%or interrupt is a stopped program pretending it succeeded, and the engine's
%recovery catches all consult this: control_exception(Ball) true means the
%ball is rethrown rather than handled.
%
%A library that introduces its own cancellation or budget signal adds a
%clause and every recovery site in the engine respects it, which is the only
%way it could: a signal the engine has never heard of is swallowed by the
%first recovery catch it meets, and the failure is silent. This is
%KeyboardInterrupt living outside Exception, given a seam.
%
%library(exceptions) says the same thing more directly, and was measured
%rather than assumed. Written its way a recovery site is
%catch(Goal, \+ petta_control_signal, _, Recover), the negated type its
%is_exception/3 already supports, and it is behaviour-identical: ten balls,
%errors and non-errors, control and ordinary, recovered or escaped the same
%way both ways. It costs too much. catch/4 puts a freeze/2 on the ball at
%CALL time, so the price is paid whether or not anything throws: 20,000
%quiet calls went 140,002 to 240,002 inferences, 1.71x, and 20,000 throwing
%ones 240,003 to 1,340,002, 5.58x [measured 2026-08-16]. The recovery catch
%wraps every candidate the translator tries, so the quiet number is the one
%that decides it [source: ai-swi-library-review.md, entry 2].
%The multifile declaration for it is in engine/metta.pl, not here, because
%control_exception/1 is also an engine_emitted/1 name: the translator writes it
%into compiled bodies and protect_engine_emitted/1 imports it into every
%space's module from the ENGINE's module, which it can only do if that is
%where it lives. It is the one seam whose home is the engine core rather than
%this module, and seam_home/2 below is what lets the publication machinery say
%so instead of assuming.
kind(control_exception/1, declaration).

%Whether a HOST's own atom hooks are idle for a space, the host's clause of
%it: the shim answers for the Python side, and with no host loaded the seam
%has no clause and the engine's own no-handlers test already answered. The
%engine hands the host the full handler CENSUS as clause references, so a
%host clause matches the census against the one reference it installed and
%never consults engine internals to answer: a host is asked about ITS hooks,
%with the facts it needs in the question. engine/spaces.pl asks them; they are
%declared here because every seam is.
:- multifile host_add_hooks_idle/2.
kind(host_add_hooks_idle/2, ownership).
:- multifile host_remove_hooks_idle/2.
kind(host_remove_hooks_idle/2, ownership).

%An APPLICABLE GROUNDED ATOM. MeTTa's own definition of a Grounded atom is
%that it "may contain any binary object, for example operation (including deep
%neural networks), collection or value" [source: metta-lang.dev/docs/learn,
%Atom kinds and types], and an operation is a thing you call. The engine leaves
%a grounded head unevaluated unless a handler claims it, so `((py-atom
%numpy.absolute) -5)` answered itself and a callable held in a MeTTa variable
%was not a callable at all.
%
%   grounded_apply(Value, Args, Out)
%
%Value is the grounded atom in head position and Args are the arguments as the
%engine has them. Succeed to claim it and bind Out; fail and the expression
%stays unreduced, which is what every value that is not an operation should do.
%
%Nothing in the engine knows what makes a value applicable, which is the point:
%a Python bridge claims Python callables, and a bridge for something else
%claims its own. It is consulted only for a head that is neither a function
%name nor a partial application, so an ordinary call never reaches it.
:- multifile grounded_apply/3.
kind(grounded_apply/3, ownership).

%Whether a value is an operation at all, asked WITHOUT applying it. `bind!`
%needs to know before there are any arguments: a name bound to a callable is
%callable by that name, and a name bound to 5 is not.
:- multifile grounded_applicable/1.
kind(grounded_applicable/1, ownership).

%A grounded host value may participate in the language's numeric operations
%without becoming a Prolog number. Admission and execution stay one provider
%protocol: the owner recognizes its numeric objects, then evaluates with that
%host's operator dispatch so reflected methods and result types are retained
%[tested: test_numpy_numeric_family_keeps_python_result_types and
%test_user_numeric_subclass_uses_its_own_operator; commit=a0f1cc5f15a15e5ca6958fe02a20be8832c7237f].
:- multifile grounded_numeric/1.
kind(grounded_numeric/1, ownership).
:- multifile grounded_numeric_operation/3.
kind(grounded_numeric_operation/3, ownership).

%An operation with NO effect a cache could hide.
%
%   pure_operation(Name)
%
%Declared by whoever knows: the engine ships its own core list and a library
%adds its own. It is an ALLOW-list on purpose, and the asymmetry is the whole
%argument: a missing entry in a deny-list is a silent wrong answer, and a
%missing entry here is a loud refusal that someone fixes.
%
%What reads it is anything that may CACHE a result and hand the cached one back
%later: tabling and memoization both do. A goal that is not known pure is not
%known inert either, and treating unknown as inert cached a random draw, threw
%away a space write, and suppressed a println!.
:- multifile pure_operation/1.
kind(pure_operation/1, declaration).

%The MeTTa name behind a bridge's dispatch goal.
%
%   effect_operation_name(Goal, Name, Arity)
%
%A bridge compiles a MeTTa operation into a call on its OWN dispatcher, so a
%purity refusal that reads the goal's functor names the bridge rather than the
%program: `(tabled (uses-size $k))` refused `petta_py_dispatch_det/3` and
%advised declaring THAT pure, which is neither something an author wrote nor
%something that would help, since the refusal never reaches the operation's
%name. A bridge that can recover the name answers here, and the refusal then
%names what the program wrote and what pure_operation/1 matches.
%
%It is the engine's only way to ask, and it has to be, because the engine
%knows no bridge by name: the Python one answers for its four dispatch kinds,
%and a bridge for something else answers for its own
%[tested: test_a_pure_python_operation_can_be_declared_and_cached].
:- multifile effect_operation_name/3.
kind(effect_operation_name/3, ownership).

%The STRUCTURE a grounded value also has, when it has one.
%
%   grounded_structure(Value, Expression)
%
%The language names three things a grounded value may define for itself:
%"Grounded value type creators can define custom type, execution and matching
%logic for the value" [source: the language's Main concepts]. The two above are
%type and execution. This is matching, and it is what lets one atom answer to
%two readings without being two answers: a Python tuple stays the tuple when it
%is passed back to Python or read with py-dot, and reads as `(1 2)` when a
%program takes it apart.
%
%The disambiguation is the language's own, taken from how a space atom nested
%in another space already behaves: a query "just a variable, e.g. $x" matches
%the atom ITSELF, and a structured query is delegated inward
%[source: the language's Working with spaces]. So the handle is what a variable
%binds and what a space stores, and the structure is what an expression pattern
%and the atom-taking-apart operations see.
%
%Nothing here is Python's. A foreign space handle, a MORK record or an array
%answers it the same way, and no caller learns who did.
:- multifile grounded_structure/2.
kind(grounded_structure/2, ownership).

%How a grounded value RENDERS, for a writer that has no other way to know.
%
%   grounded_text(Value, Text)
%
%Without a provider the display renderer falls back to the term's own text, so
%this is never required and never fails a display. The round-trip writer does
%not consult it. A Python object answers with repr(), which is what the
%language's own tutorials show: `(np-array (py-atom "[1, 2, 3]"))` displays
%`array([1, 2, 3])`
%[source: metta-lang-docs/learn__tutorials__python_use__py_atom.md].
:- multifile grounded_text/2.
kind(grounded_text/2, ownership).

%%%% Native backends %%%%
%
%A backend is a space provider whose implementation is a shared library. It
%reaches the engine through the foreign-space seam above like any other
%provider; these two are the only things it needs that a Prolog provider does
%not, and both exist so the ENGINE never has to know a backend by name.
%
%The builtins a backend's bridge provides. Declared by the file that DEFINES
%them, so they exist exactly when the predicates behind them do: registering a
%name whose predicate is absent records no arity, and every call to it then
%compiles to a partial application. engine/metta.pl registers whatever is declared
%here, and names nothing.
:- multifile backend_builtin/1.
kind(backend_builtin/1, declaration).

%A backend's smoke test, run by engine/main.pl's demo. Every handler runs, so a
%process with two backends tests both, and one with none tests nothing and says
%so by being silent.
:- multifile backend_selftest/0.
kind(backend_selftest/0, event).

%%%% Services the engine publishes %%%%
%
%The seams above are all things the engine calls. These are the other
%direction: engine predicates an extension is allowed to call. An extension
%that reaches past them is depending on an internal that can be renamed under
%it, which for a backend is a gate failure rather than a style note
%[tested: a_backend_calls_only_published_surface].
%
%The MeTTa builtins are published too and are not repeated here: an extension
%calls 'add-atom'/3 or match/4 as the LANGUAGE, and builtin_fun/1 already says
%which names those are.
%
%TEXT. What being a shared library costs. A backend's atoms live on the far
%side of an FFI boundary that carries bytes, so every atom it stores is written
%and every atom it returns is read, and before these were declared MORK reached
%into engine/parser.pl for all four, wrapping one under a private name.
%
%swrite/2 and sread/2 are one rule about spelling rather than two conveniences.
%swrite/2 refuses a value that sread/2 would not read back as itself. MeTTa has
%no quoted-symbol syntax, its reader has no literal for some numbers, and a
%Janus tuple or another host compound is not a MeTTa term at all. A backend
%cannot decide any of these for itself because the grammar owns the answer;
%the other two services let it preflight a name or whole term before writing.
%metta_symbol_writable/1 answers the first question about one name;
%metta_unwritable_symbol/2 answers both about a whole term, and its name is
%narrower than what it reports because names were the only class known to fail
%when this surface was declared.
%HOST SERVICE: a service again, engine-defined and engine-owned, but for
%the other caller: the HOST BINDING's transport (bindings/python/metta's shim today,
%any future binding's transport tomorrow). The backend direction has
%a_backend_calls_only_published_surface; this kind is what the host
%direction's twin reads, so the binding can no longer grow a dependency on
%an engine internal silently. The list is measured, not aspirational: it is
%exactly the engine predicates the shipped shim calls, and shrinking it is
%the shim-thinning work's scoreboard.
kind(catch_recover/2, host_service).
kind(translate_expr/3, host_service).
kind(translate_cached_expr/3, host_service).
kind(lift_pattern_modifiers/4, host_service).
kind(petta_seq_query_plan/2, host_service).
%The host run and load surface: the grouped runner (with the
%using-substitution folded in as Bindings), the status runner, the load
%lifecycle and the manifest read, plus the reducible-head test the status
%vocabularies report. These replaced the parse-prepare-process walk and
%the six-deep load nest every binding used to carry: prepare_parsed_forms,
%process_form, read_metta_source, load_imported_metta_file_impl,
%replacing_previous_load, with_source_load, fun_here and
%translate_special_dl left this list with them (2026-08-20), and
%parse_metta_source moved to the extension service list below, the import
%libraries being its remaining callers.
kind(metta_host_run_source/4, host_service).
kind(metta_host_run_source_status/3, host_service).
kind(metta_host_load_file/3, host_service).
kind(metta_host_read_forms/2, host_service).
kind(metta_host_with_stack_limit/2, host_service).
kind(metta_host_function_generation/1, host_service).
kind(metta_reducible_head/2, host_service).
%Proof tools may open only a dispatch route the engine identifies as its
%shipped direct path. Every policy-sensitive route is executed engine-side and
%reported opaque, keeping host derivations out of the six-axis implementation.
kind(metta_host_dispatch_proof_step/6, host_service).
%Grouped answers carry a reader-name state. Host codecs flatten that state for
%their variable tag and use the same engine writer for host text.
kind(petta_name_pairs/2, host_service).
kind(swrite_with_names/3, host_service).
%The persistence surface moved engine-side the same day: the fast cache's
%save and integrity-checked load, the space digest, and the host-value
%substitution walk the using-runs share. metta_add_atom/3 and import_when/4
%left the list with them, the fast loader having been their last transport
%caller.
kind(metta_host_save_fast/3, host_service).
kind(metta_host_load_fast/2, host_service).
kind(metta_host_fast_header/1, host_service).
kind(metta_host_digest/2, host_service).
kind(metta_host_substitute/3, host_service).
%The registration lifecycle: open proves a name free before the host mutates
%anything, adopt makes an asserted dispatch clause a claimed function of the
%base tier, drop retires one arity, forget releases a name nothing defines.
%These four replaced the seven bookkeeping predicates every binding restated
%in order (claim_function_name, function_changed,
%recompile_definitions_mentioning, refuse_other_tiers_name, register_fun_in,
%release_function_name, unregister_fun_everywhere, 2026-08-20), and the
%dependent recompile that rode the shim's function_changed clause
%is the engine's own now, so those events are pure observations again.
kind(metta_host_open_function/3, host_service).
kind(metta_host_adopt_function/4, host_service).
kind(metta_host_drop_function/2, host_service).
kind(metta_host_forget_function/1, host_service).
%Reader classes keep their callable on the engine side. A host registers or
%removes one mapping through these services and owns construction through the
%handler seam declared below.
kind(metta_host_register_reader_token/2, host_service).
kind(metta_host_unregister_reader_token/1, host_service).
%The space read-and-remove pair a host talks to storage through:
%metta_host_stored/2 enumerates stored atoms unifying a pattern
%(index-directed native, provider-enumerated foreign), and
%metta_host_remove_reported/3 removes with the whether-anything-went
%verdict a host API wants, existence probed before the mutation. These
%replaced get_native_atom/2, native_storage_module/2 and
%metta_remove_atom/3 on this list (2026-08-20); the index-directed
%existence probe is engine-internal now.
kind(metta_host_stored/2, host_service).
kind(metta_host_remove_reported/3, host_service).
%The native proof-leaf decoder keeps private module and predicate encodings
%behind one host call, including expression-named spaces.
kind(metta_host_native_fact/4, host_service).
%The explain mirror: one call answers what the seam already decided for a
%query (per-pattern classes with term origins, the plan's claimed and rest
%indexes, refusals preflighted), so a host renders prose instead of
%re-deriving routing precedence. foreign_pushdown_class/3,
%petta_refuse_guard/2, refuse_lossy_plan/4, petta_handles_route/5 and
%foreign_provides/2 left this list with it (2026-08-20); the two that
%extensions genuinely consult moved to the service list below.
kind(metta_host_explain_match/3, host_service).
%The bulk space cleanups: clear a space whoever holds it (Prolog providers
%through their seam, native spaces with the announce-when-watched and
%tabling-death rules), and clear the (defined ...) reflection facts about
%one space in one crossing. clear_foreign_atoms/1, clear_native_atoms/1 and
%atom_hook_clause/2 left this list with them (2026-08-20): the
%handler census is engine-internal now, handed to the hooks-idle ownership
%seams as an argument.
kind(metta_host_clear_space/1, host_service).
kind(metta_host_clear_defined/1, host_service).
%Creation-time space topology and lifecycle are engine-owned, while Python's
%context-manager surface requests those transitions through these calls.
kind(metta_declare_space_parent/2, host_service).
kind(metta_declare_restricted_space/2, host_service).
kind(metta_assert_space_releasable/1, host_service).
kind(metta_release_space/1, host_service).
%The builtin-refusal classification: operation, kind, expected and culprit
%read from the error term the engine's own throwers shape, absence left
%unbound for the host to map to its None (2026-08-20).
kind(metta_host_operation_error/5, host_service).
kind(match_foreign/5, host_service).
kind(metta_add_atoms/2, host_service).
kind(metta_source_declarations/2, host_service).
kind(metta_space_names/1, host_service).
kind(metta_string_declarations/2, host_service).
kind(metta_substitute_self/3, host_service).
kind(metta_trace_source/4, host_service).
kind(petta_annotations/2, host_service).
kind(petta_contract_fact/1, host_service).
kind(petta_error_answer/3, host_service).
kind(petta_handles_coherent/1, host_service).
kind(petta_on_error_mode/3, host_service).
kind(petta_source_reset/1, host_service).
kind(petta_transaction/1, host_service).
kind(petta_transport_failure/1, host_service).
kind(sread_with_names/3, host_service).
kind(unregister_metta_extension/1, host_service).
kind(with_metta_module/2, host_service).
%The dispatch-ownership question behind every host direct-call door: a
%declared or rule-owned head declines the raw fast path (P14.32). One
%engine-owned door instead of the two raw reads it wraps, so the
%declaration walk and the rule registry stay free to move.
kind(metta_typed_dispatch_applies/2, host_service).

kind(swrite/2, service).
%Presentation text is deliberately distinct from the inverse writer. A host
%or extension uses this only where lossless re-reading is not the contract
%[tested: every_seam_declares_one_kind, parser_display; commit=53686aed41e7ff02de69052198afdb537536cbdb].
kind(sdisplay/2, service).
kind(sdisplay_with_names/3, service).
kind(sread/2, service).
%Moved from the host_service list on 2026-08-20: the host bindings read
%source through metta_host_run_source/4 and its siblings now, and the
%remaining callers are extension libraries (lib_gitimport, lib_import),
%which is exactly what this kind means.
kind(parse_metta_source/2, service).
kind(metta_reader_token_class/3, service).
kind(metta_reader_token_source/2, service).
kind(metta_symbol_writable/1, service).

%Every head the compiler gives a special meaning to, enumerable. A reflection
%library wants the SET, and reading engine/translator.pl's clause table for it
%is a dependency no walk can see and one that answers silently for nothing
%when the table moves module.
kind(metta_special_form_head/1, service).
kind(metta_unwritable_symbol/2, service).

%THE CATALOG'S CONSULTATION SITES, published for extensions. A route-cap
%advisor or any consumer of a declared kind reads the same routed view the
%engine reads: petta_shape_route/5 answers the most specific coherent
%entry for a query under any shape-routed head, shipped or third-party,
%and petta_contract_fact/1 is the raw row read beneath it (already a
%host_service above; named here in prose so an extension author finds the
%pair together).
kind(petta_shape_route/5, service).
%The event-capability door, for an extension that BLOCKS on a context's
%changes rather than merely observing them: lib/lib_thread.pl's Linda pair
%parks a caller until an atom arrives, and parking on a context that
%promises no events is a hang rather than a wait. Throws naming the context
%and the caller's own word for what it wanted to do; succeeds silently for a
%context that can deliver, native spaces included
%[tested: test_a_blocking_take_waits_for_a_matching_atom_and_removes_exactly_one].
kind(petta_require_events/2, service).
%The routing classifier and the capability probe, consulted by
%lib/lib_conformance.pl: published for extensions, no longer part of the
%host transport's own list.
kind(foreign_pushdown_class/3, service).
kind(foreign_provides/2, service).

%ERRORS. An extension that throws reports in the vocabulary of whatever threw,
%so `Y is X * 2` on a symbol names is/2 rather than the operation the program
%wrote. These two are how a builtin avoids that, and EXTENDING.md has told
%extension authors to call both for longer than either was declared: the
%rethrow in a worked example at two places and the type error in a third
%[source: EXTENDING.md, "Making your errors read like a builtin's"]. Declaring
%them changes nothing about who may call them and puts a decision that was
%already made into the data that the checker reads.
kind(throw_metta_type_error/3, service).
kind(rethrow_metta_operation_error/2, service).

%CONTEXT. Which module the call site is in. A named space compiles its
%equations into a module of its own, so a function name alone does not identify
%a function, and a handler keeping state per function has to ask. It is read
%rather than passed because dispatch_call/4 is consulted on every
%compiled call site and an extra argument there is not free.
kind(current_metta_module/1, service).

%CONTEXT, the other half: which MODULE a space compiles into, and which space
%a module serves. Published because Phase 11 made them necessary rather than
%convenient. A space and its module were the same atom for every space but
%&self, so a library could pass a space name wherever a module was wanted and
%it worked by coincidence; they are different atoms now and
%with_metta_module/2 REFUSES a space name, so a library that runs a goal in a
%space has to ask. lib_memo.pl and lib_tabling.pl each carried a hand-written
%copy of the inverse before this
%[source: ai-phase11-module-survey.md section 1.3, which counted four copies
%of it, three of them outside engine/spaces.pl].
kind(space_module/2, service).
kind(metta_module_space/2, service).
%The space a program is running in, beside the module it compiles into. A
%library that reads a declaration out of the running space asks for the space,
%not the module, because a declaration is stored as an atom.
kind(current_metta_space/1, service).
%Whether a term is a space name at all, the test every extension taking a
%space argument needs before it uses one. 'is-space'/2 is the MeTTa spelling
%of the same question and is published as a builtin; this is the Prolog one,
%and it is the test rather than a lookup, so an unbound or computed term is
%refused instead of read as an empty space.
kind(petta_space_name/1, service).

%EVALUATION IN A SPACE. space_module/2 above names the module a space compiles
%into; this is what a library names it FOR. lib/lib_thread.pl runs a MeTTa
%expression on a worker thread eight different ways and every one of them
%goes through here, because a thread inherits no context and the module has to
%travel with the expression [source: lib/lib_thread.pl, par_map_/4 and its
%siblings].
kind(eval_metta_in_module/3, service).

%NATIVE STORAGE. A space has two halves and the execution one is declared
%above. This is the other: which module a native space's atoms live in, which
%functor answers them, and what clause one atom becomes. Published as a group
%because a library that pre-generates a space's storage needs all three at
%once and must use the SAME spelling add-atom uses -- lib/lib_import.pl
%converts a data file to Prolog facts ahead of time, and a second spelling of
%the format would load clauses the space could never read, which is the defect
%that file's own header records. ensure_native_storage_module/2 is the
%make-it-exist half, for a writer that runs before the space holds anything.
kind(native_storage_module/2, service).
kind(native_storage_functor/2, service).
kind(ensure_native_storage_module/2, service).
kind(native_atom_clause/3, service).
%The match a foreign provider answers, published for the library that CHECKS
%providers: lib/lib_conformance.pl runs a provider's own atoms back through it
%to prove the over-approximation contract holds. match_foreign/5 is the host
%transport's arity and is a host_service above; this is the four-argument
%engine-side call an extension makes.
kind(match_foreign/4, service).

%PURITY AND CACHING. Whether a function may be cached, and what its body
%reads. Two independent libraries ask (lib/lib_memo.pl and lib/lib_tabling.pl)
%and both delegate the DECISION to the engine rather than deciding it twice:
%metta_effect_walk/3 is the engine's walk over a compiled body and carries the
%engine's own refusal for a goal nothing declares pure, metta_function_cacheable/1
%is the declared volatility, and metta_cache_unchecked/1 is the caller's own
%(cache Name unchecked) waiver. A cache that answered these for itself would
%drift from the declarations the engine enforces everywhere else.
kind(metta_effect_walk/3, service).
kind(metta_function_cacheable/1, service).
kind(metta_cache_unchecked/1, service).
%A library that batches a compile-time analysis needs to distinguish one
%source program from an isolated equation and recompile the affected call
%surface through the loader's established invalidation path.
kind(active_source_program/1, service).
kind(recompile_function_impl/1, service).

%THE SUPPORT GRAPH's other direction. Its handler seams are declared in
%engine/support_graph.pl (support_invalidation_action/1 and four more), so an
%extension can already be CALLED by the graph; these are the three calls it
%makes back to take part -- record an edge, invalidate from a changed input,
%and drop a node. Declaring only the inbound half is what left lib/lib_memo.pl
%reaching into the graph's internals to do the outbound one.
kind(support_record/2, service).
kind(support_invalidate/1, service).
kind(support_forget/1, service).
kind(support_memo_take_change/2, service).
kind(support_memo_sccs/2, service).

%SOURCE AND VOCABULARY. The published parser hands back parsed/3 terms, so
%without a way to take one apart the answer is opaque; parsed_form_parts/4 is
%that way and belongs beside parse_metta_source/2 above.
kind(parsed_form_parts/4, service).
%Where a relative path resolves from. The bare working_dir/1 has a clause only
%while a .metta load is active, so a library that reads a file from anywhere
%else simply failed with no answer and no error; this is the one that falls
%back to the process directory [source: lib/lib_import.pl, 'static-import!'/3].
kind(current_working_dir/1, service).
%Membership in a declared vocabulary, the question every consulting site asks.
%A library validating its own option against a vocabulary the catalog declares
%reads the same table the engine reads, so a value the catalog gains is
%accepted without editing the library.
kind(petta_vocabulary_value/2, service).
%The import lifecycle's marker. A library that performs an import of its own
%(lib/lib_gitimport.pl's git-import!) has to run under the same marker, or a
%failed load leaves behind the clauses the engine would have erased.
kind(run_with_loading_marker/2, service).
%The third error-vocabulary service, beside the two above. engine/kernel.pl's
%own builtins refuse an unbound argument through it, and a library builtin
%that takes an input refuses the same way rather than inventing a message.
kind(refuse_unbound_input/2, service).

%Extra type candidates for grounded host objects, beyond the object's own
%classes: a protocol the object satisfies may name a type, so a declared
%(-> DLTensor ...) can hold across libraries.
:- multifile grounded_extra_type/2.
kind(grounded_extra_type/2, declaration).

%A host bridge may compute an object's type names itself: values can sit in
%envelope objects the boundary must not rewrite, so the names, plain text,
%are what crosses rather than the value. What a bridge owns is the CLASS
%WALK: when one answers, its names stand in for the walk, and with none the
%local walk applies. It does not own grounded_extra_type/2 above, which is
%consulted either way, because a declaration seam is additive and reading
%this one as owning the whole answer silently dropped every declared type
%in the shipped configuration
%[tested: bindings/python/tests/test_ops.py::test_a_declared_type_survives_the_library_being_loaded].
:- multifile grounded_type_names/2.
kind(grounded_type_names/2, ownership).

%The host's own class enumeration, the fallback when no envelope bridge
%answered: walking a value's classes is host code by nature, so the host
%bridge supplies it and an engine with no host loaded has no clause here,
%which is the correct answer for a configuration in which no host value
%can exist.
:- multifile grounded_class_type/2.
kind(grounded_class_type/2, ownership).

%A host bridge's own builtins, registered by the engine's registry directive
%from these declarations, so no list inside the engine names a host: the
%bridge declares, the engine registers whatever was declared.
:- multifile host_builtin/1.
kind(host_builtin/1, declaration).

%A host claims an import whose source is its own kind of file and performs
%the whole job itself, lifecycle included, through the published
%import_when/4; with no host loaded, or none claiming, every import is a
%MeTTa import.
:- multifile host_import/1.
kind(host_import/1, ownership).

%Whether a value is a live host object at all, the question in front of
%every grounded-type lookup: the engine's own cheap class tests run first,
%and this seam is the bridge's part, so an engine with no host loaded
%answers no at one failed lookup and never initializes anything.
:- multifile host_object/1.
kind(host_object/1, ownership).

%Construct a reader token through the host that owns its retained callable.
%The token text is the full lexeme, quotes included for a string token, and the
%answer is the engine term the reader will return.
:- multifile host_reader_token_construct/3.
kind(host_reader_token_construct/3, ownership).

%A registered rewriter runs over every loaded form; a host installs one only
%while it is needed (the Python bridge registers its import-as alias rewrite
%when the first alias lands), so a program that never uses the feature pays
%one failed lookup per form and nothing more, the same install-on-demand
%shape the atom hooks use.
:- dynamic form_rewriter/1.
:- multifile form_rewriter/1.
kind(form_rewriter/1, ownership).

%%%% Published means exported %%%%
%
%Until now a declaration was a promise nothing kept: a seam declared here was
%no more reachable, and no less internal, than the predicate beside it, and the
%two surface checks answered "is this published" by reading this table a second
%time. Declaring a seam EXPORTS it, so the promise is a fact the module system
%holds and the checks ASK for: published_surface/1 in
%tests/prolog/surface_walk.pl reads module_property(Engine, exports(E)) and no
%longer reads this table
%[tested: every_declared_seam_that_exists_is_exported,
%a_seam_declared_in_a_later_file_is_exported,
%a_declaration_without_a_definition_is_not_exported].
%
%Every kind, not services alone. An extension resolves a handler seam by name
%as surely as it calls a service, and a name the engine publishes in either
%direction is surface either way. What the kinds still decide is who writes the
%clauses, which every_seam_kind_matches_its_direction checks apart.
%
%A declaration whose predicate does not exist yet is skipped rather than
%refused: a library declares its own seam beside the clauses that define it,
%and a seam is declared here before the file that defines it is loaded. The
%listener below is what catches both, and it is the same channel the atom
%hooks use, so a clause that arrives by consult is seen exactly as one that
%arrives by assert.
%A seam this module's own declaration already exports needs nothing done, and
%doing it anyway is not free: export/1 at RUN time also pushes the name into
%every module that has imported from here, so re-exporting the handler seams
%put seam:function_removed/1 into the engine's module on top of the different
%function_removed/1 engine/spaces.pl defines there, and SWI reported "Local
%definition of user:function_removed/1 overrides weak import from seam" on
%every static-check run. Two modules holding one name is what a module system
%is FOR; an accidental import of one into the other is not
%[measured 2026-08-22].
publish(Seam) :-
    (   seam_home(Seam, Home),
        \+ ( module_property(Home, exports(Exports)), memberchk(Seam, Exports) )
    ->  Home:export(Seam)
    ;   true
    ).

%!  seam_home(+Seam, -Module) is semidet.
%
%   Which module a declared seam's clauses live in: this module for every
%   handler seam, the engine core for control_exception/1 because the
%   translator emits it and a space's module has to import it from there, and
%   whichever subsystem defines a service for the rest.
%
%   implementation_module/1 rather than current_predicate/1, because
%   current_predicate/1 answers for a predicate this module can merely SEE. A
%   module inherits its base, so asking it that way said `seam` owned swrite/2
%   and every other engine service, and the boot sweep then exported ninety-five
%   of them out of the wrong module: the engine's own export list came back
%   holding twenty-six names where it holds a hundred and twenty
%   [measured 2026-08-22]. This is the same question the layering lane asks of
%   a call, and it has one answer per predicate
%   [source: SWI-Prolog predicate_property/2, implementation_module(Module)].
seam_home(Name/Arity, Home) :-
    functor(Head, Name, Arity),
    (   defined_in(seam, Head)
    ->  Home = seam
    ;   petta_engine_module(Engine),
        implemented_in(Engine, Head, Home)
    ).

%The `defined` half is load-bearing and not a belt-and-braces check. Asking
%implementation_module/1 about a name nothing has defined answers with the
%module that was ASKED, so every seam declared before its definition loads
%came back owned by whoever asked first: the boot directive in this file
%exported forty-odd engine services out of `seam` and SWI then reported each
%as "Exported procedure seam:refuse_unbound_input/2 is not defined"
%[measured 2026-08-22].
implemented_in(Module, Head, Home) :-
    catch(( predicate_property(Module:Head, defined),
            predicate_property(Module:Head, implementation_module(Home)) ),
          _, fail).

defined_in(Module, Head) :- implemented_in(Module, Head, Module).

publish_declared :-
    forall(kind(Seam, _), publish(Seam)).

%A seam declared later publishes itself. Only the additions matter, so a
%retract is ignored: SWI has no unexport, and a seam withdrawn at run time is
%not a thing the tree does.
declared(Action, Reference) :-
    % policy-inventory-exempt: mechanism-internal; reason=asserta and assertz are prolog_listen/2's own action vocabulary for a clause arriving rather than an engine decision; evidence=engine/ext_points.pl:declared/2
    (   memberchk(Action, [asserta, assertz]),
        blob(Reference, clause),
        catch(clause(kind(Seam, _), _, Reference), _, fail)
    ->  publish(Seam)
    ;   true
    ).

:- prolog_listen(kind/2, declared).
%And the ones declared above, which the listener could not have seen. The
%sweep runs again from engine/metta.pl's own initialization, after every file
%the engine loads has defined what it declared here.
:- publish_declared.

:- use_module(library(prolog_wrap)).

dispatch_call(_, _, _, _) :- fail.
cache_policy_changed(_).
function_changed(_).
function_clauses_changed(_).
function_call_graph_changed(_, _).
function_removed(_).
source_program_compiled.

%Atom hooks wrap the write predicates only while a multifile handler exists.
%prolog_listen/2 sees clauses loaded later, so an engine without handlers keeps
%the original direct write path. Multiple handlers still run through forall/2.

atom_hook_clause(added, Ref) :- clause(atom_added(_, _), _, Ref).
atom_hook_clause(removed, Ref) :- clause(atom_removed(_, _), _, Ref).

%Both branches succeed or throw, never fail. This installer runs from inside a
%prolog_listen/2 closure, and that channel's contract is asymmetric: on an
%assertz "the hook is called after the clause has been added. If the hook
%fails the clause is REMOVED", and on a retract "if the hook fails, the clause
%is not removed" [source: SWI-Prolog 10.1 Reference Manual, Appendix B.9]. So
%a failure here silently erases the handler that was just installed, or leaves
%one the caller believes it erased, and either way a library's subscription
%simply never fires with no error to find. The disable branches were already
%total; these were not. Nothing observed fails, so this is the seam's own
%installer being made unable to fail quietly rather than a live bug
%[tested: a_handler_survives_its_own_installation].
%The wrapped predicate is the WRITE DOOR's, and the module is asked rather
%than written: writing `user` here meant "the engine" in one breath and "the
%host" in the next, and only the second reading survives Phase 11. Asking
%petta_engine_module/1 was the right question only while every engine file
%shared that module. wrap_predicate/4 on a name a module merely IMPORTS wraps
%the import and leaves the definition alone, so once engine/spaces.pl declared
%a module of its own the wrapper would have watched a link the write door
%never follows and no atom hook would ever fire; the same shape made a
%translation-cache counter see every compile as a hit [measured 2026-08-22].
%implementation_module/1 answers where a predicate actually lives, which is
%the engine's module while the write door is there and the write door's module
%once it is not.
%
%The WRAPPER BODY is left unqualified deliberately. wrap_predicate/4 declares
%it `0` [source: library(prolog_wrap), meta_predicate wrap_predicate(:,+,-,0)],
%so SWI qualifies it with this file's own module at compile time, which is the
%same answer and is one SWI's code walker can follow: qualifying it by hand
%with a run-time variable made three live wrapper bodies unreachable from any
%root in tests/prolog/reachability.pl [measured 2026-08-19].
enable_atom_hook(added) :-
    write_door_module(metta_add_atom/3, Engine),
    current_predicate_wrapper(Engine:metta_add_atom(_, _, _), metta_atom_added_hooks, _, _), !.
enable_atom_hook(added) :-
    write_door_module(metta_add_atom/3, Engine),
    (   wrap_predicate(Engine:metta_add_atom(Space, Term, _Result), metta_atom_added_hooks, Wrapped,
                       run_atom_added_hooks(Wrapped, Space, Term))
    ->  true
    ;   throw(error(petta_atom_hook_install_failed(added),
                    context(enable_atom_hook/1,
                            'the write wrapper could not be installed')))
    ).
enable_atom_hook(removed) :-
    write_door_module(metta_remove_atom/3, Engine),
    current_predicate_wrapper(Engine:metta_remove_atom(_, _, _), metta_atom_removed_hooks, _, _), !.
enable_atom_hook(removed) :-
    write_door_module(metta_remove_atom/3, Engine),
    (   wrap_predicate(Engine:metta_remove_atom(Space, Term, Removed), metta_atom_removed_hooks, Wrapped,
                       run_atom_removed_hooks(Wrapped, Space, Term, Removed))
    ->  true
    ;   throw(error(petta_atom_hook_install_failed(removed),
                    context(enable_atom_hook/1,
                            'the write wrapper could not be installed')))
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_atom_hook_install_failed(Kind)) -->
    [ 'the ~w-atom write wrapper could not be installed, so a handler asserted \c
       now would be removed again by prolog_listen/2 and never fire'-[Kind] ].

%Where the write door actually lives, asked of SWI rather than assumed to be
%the engine's own module.
write_door_module(Name/Arity, Module) :-
    functor(Head, Name, Arity),
    petta_engine_module(Engine),
    predicate_property(Engine:Head, implementation_module(Module)).

run_atom_added_hooks(Wrapped, Space, Term) :-
    call(Wrapped),
    forall(atom_added(Space, Term), true).

run_atom_removed_hooks(Wrapped, Space, Term, Removed) :-
    call(Wrapped),
    ( Removed == true
      -> forall(atom_removed(Space, Term), true)
      ; true ).

disable_atom_hook(added) :-
    write_door_module(metta_add_atom/3, Engine),
    ( unwrap_predicate(Engine:metta_add_atom/3, metta_atom_added_hooks) -> true ; true ).
disable_atom_hook(removed) :-
    write_door_module(metta_remove_atom/3, Engine),
    ( unwrap_predicate(Engine:metta_remove_atom/3, metta_atom_removed_hooks) -> true ; true ).

sync_atom_hook(Kind) :- ( atom_hook_clause(Kind, _)
                                -> enable_atom_hook(Kind)
                                ; disable_atom_hook(Kind) ).

atom_hook_changed(Kind, Action, Context) :-
    ( ( Action == asserta ; Action == assertz ; Action == rollback(retract) )
      -> enable_atom_hook(Kind)
    ; ( Action == retract ; Action == rollback(asserta) ; Action == rollback(assertz) )
      -> ( atom_hook_clause(Kind, Other), Other \== Context
           -> true ; disable_atom_hook(Kind) )
    ; Action == retractall, Context = end(_)
      -> sync_atom_hook(Kind)
    ; true ).

:- prolog_listen(atom_added/2, atom_hook_changed(added)).
:- prolog_listen(atom_removed/2, atom_hook_changed(removed)).
:- sync_atom_hook(added).
:- sync_atom_hook(removed).
:- initialization(sync_atom_hook(added), restore_state).
:- initialization(sync_atom_hook(removed), restore_state).
